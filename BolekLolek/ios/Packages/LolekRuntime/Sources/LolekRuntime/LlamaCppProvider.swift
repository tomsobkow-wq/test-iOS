import AgentCore
import DocumentKit
import Foundation

public enum LolekError: LocalizedError, Sendable {
    case modelNotInstalled(String)

    public var errorDescription: String? {
        switch self {
        case let .modelNotInstalled(name): "Lolek's brain (\(name)) is not downloaded yet."
        }
    }
}

/// Loads the engine once and keeps it. Memory-heavy, so it can be dropped under pressure.
public actor LolekEngineHost {
    private let model: LocalModel
    private let store: ModelStore
    private let settings: EngineSettings
    private var engine: LlamaEngine?

    public init(model: LocalModel, store: ModelStore = ModelStore(), settings: EngineSettings = EngineSettings()) {
        self.model = model
        self.store = store
        self.settings = settings
    }

    /// Debug aid: called with a line whenever the model has to be (re)loaded into memory.
    private var onLoad: (@Sendable (String) -> Void)?
    public func setOnLoad(_ handler: @escaping @Sendable (String) -> Void) { onLoad = handler }

    public func loadedEngine() async throws -> LlamaEngine {
        if let engine { return engine }
        let loadStart = Date()
        defer { onLoad?("{\"event\":\"model_load\",\"seconds\":\(String(format: "%.1f", Date().timeIntervalSince(loadStart))),\"t\":\(Date().timeIntervalSince1970)}\n") }
        guard store.isInstalled(model) else { throw LolekError.modelNotInstalled(model.profile.displayName) }
        var settings = settings
        settings.contextTokens = min(settings.contextTokens, model.profile.contextTokens)
        let path = store.path(for: model).path
        let loaded: LlamaEngine
        do {
            loaded = try await LlamaEngine(modelPath: path, settings: settings)
        } catch LlamaEngineError.contextFailed {
            // Seen on a real iPhone right after a relaunch: iOS had not yet given back the previous run's memory.
            // Wait, try again, and if it still does not fit, load with a smaller working window rather than fail.
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            do {
                loaded = try await LlamaEngine(modelPath: path, settings: settings)
            } catch LlamaEngineError.contextFailed {
                settings.contextTokens = max(2048, settings.contextTokens / 2)
                settings.batchTokens = max(128, settings.batchTokens / 2)
                loaded = try await LlamaEngine(modelPath: path, settings: settings)
            }
        }
        engine = loaded
        return loaded
    }

    /// Frees the model (about 3 GB). It is loaded again on the next message.
    public func unload() { engine = nil }
}

/// Lolek's brain: a small open model running on this phone through llama.cpp.
public struct LlamaCppProvider: ModelProvider {
    public let profile: ModelProfile
    private let model: LocalModel
    private let host: LolekEngineHost
    private let renderer: PromptRenderer
    /// Called after every model call with its timings. For measuring on a real phone.
    private let statsHandler: (@Sendable (GenerationStats) -> Void)?

    public init(model: LocalModel = LocalModels.default, store: ModelStore = ModelStore(), settings: EngineSettings = EngineSettings(), statsHandler: (@Sendable (GenerationStats) -> Void)? = nil) {
        self.statsHandler = statsHandler
        self.model = model
        self.profile = model.profile
        self.host = LolekEngineHost(model: model, store: store, settings: settings)
        self.renderer = PromptRenderer(style: model.promptStyle)
    }

    public var engineHost: LolekEngineHost { host }

    /// Reads the fixed header (instructions and tools) so the first real message is quick.
    public func warmUp(for request: ModelRequest) async {
        guard let engine = try? await host.loadedEngine() else { return }
        let header = renderer.renderHeader(system: request.systemPrompt, tools: request.tools)
        _ = try? await engine.generate(header: header, prompt: "", suffix: "", maxTokens: 0, temperature: 0) { _ in true }
    }

    public func respond(to request: ModelRequest) async throws -> ModelResponse {
        try await respond(to: request, onText: { _ in })
    }

    public func respond(to request: ModelRequest, onText: @escaping @Sendable (String) -> Void) async throws -> ModelResponse {
        let engine = try await host.loadedEngine()
        let maxOutput = request.maxOutputTokens ?? profile.maxOutputTokens
        let limit = profile.contextTokens - maxOutput

        // Drop the oldest turns until the prompt fits; the current turn is never dropped.
        var messages = request.messages
        func parts() -> (header: String, body: String, generation: String) {
            renderer.renderParts(system: request.systemPrompt, messages: messages, tools: request.tools, timeZone: request.includeClock ? request.timeZone : nil, languageTags: request.includeClock)
        }
        var prompt = parts()
        while try await engine.tokenCount(prompt.header + prompt.body + prompt.generation) > limit, let cut = Self.firstDroppableTurnEnd(in: messages) {
            messages.removeSubrange(0..<cut)
            prompt = parts()
        }

        let raw = Accumulator()
        let (_, stats) = try await engine.generate(
            header: prompt.header,
            prompt: prompt.body,
            suffix: prompt.generation,
            maxTokens: maxOutput,
            temperature: Float(profile.temperature)
        ) { piece in
            let text = raw.append(piece)
            onText(ToolCallParser.visibleText(streaming: text))
            return !Task.isCancelled
        }

        var reported = stats
        var checksum: UInt32 = 2_166_136_261
        for byte in prompt.header.utf8 { checksum = (checksum ^ UInt32(byte)) &* 16_777_619 }
        reported.headerChecksum = checksum
        reported.headerCharacters = prompt.header.count
        statsHandler?(reported)
        let parsed = ToolCallParser.parse(raw.value, tools: request.tools)
        return ModelResponse(text: parsed.text, toolCalls: parsed.calls)
    }

    /// Index just past the oldest complete exchange (user message through the answer before the
    /// next user message), or nil if only the current turn is left.
    static func firstDroppableTurnEnd(in messages: [ChatMessage]) -> Int? {
        guard messages.count > 1, messages.first?.role == .user,
              let lastUser = messages.lastIndex(where: { $0.role == .user }),
              let nextUser = messages[1...].firstIndex(where: { $0.role == .user }),
              nextUser <= lastUser
        else { return nil }
        return nextUser
    }
}

/// Collects streamed pieces from the engine's queue.
private final class Accumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var text = ""

    func append(_ piece: String) -> String {
        lock.lock()
        defer { lock.unlock() }
        text += piece
        return text
    }

    var value: String {
        lock.lock()
        defer { lock.unlock() }
        return text
    }
}

extension LlamaCppProvider {
    /// One-shot text generation for the document harness: a system prompt, some text, an answer.
    public func documentGenerator(language: ConversationLanguage) -> DocumentSummarizer.Generate {
        { system, user, maxTokens in
            let request = ModelRequest(
                mode: .lolek, systemPrompt: system, messages: [ChatMessage(role: .user, text: user)], tools: [], language: language,
                maxOutputTokens: maxTokens, includeClock: false
            )
            return try await self.respond(to: request).text
        }
    }
}
