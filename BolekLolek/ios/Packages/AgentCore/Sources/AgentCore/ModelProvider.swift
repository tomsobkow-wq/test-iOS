import Foundation

public struct ModelRequest: Sendable {
    public let mode: AgentMode
    public let systemPrompt: String
    public let messages: [ChatMessage]
    public let tools: [ToolSpec]
    public let language: ConversationLanguage
    /// When this request is made, for providers that tell the model the date.
    public let now: Date
    public let timeZone: TimeZone
    /// Overrides the profile's output limit for this call (summaries need less, narration more).
    public let maxOutputTokens: Int?
    /// False for one-off prompts (summarising a document) where a date stamp is noise.
    public let includeClock: Bool

    public init(
        mode: AgentMode,
        systemPrompt: String,
        messages: [ChatMessage],
        tools: [ToolSpec],
        language: ConversationLanguage,
        now: Date = Date(),
        timeZone: TimeZone = .current,
        maxOutputTokens: Int? = nil,
        includeClock: Bool = true
    ) {
        self.mode = mode
        self.systemPrompt = systemPrompt
        self.messages = messages
        self.tools = tools
        self.language = language
        self.now = now
        self.timeZone = timeZone
        self.maxOutputTokens = maxOutputTokens
        self.includeClock = includeClock
    }
}

public struct ModelResponse: Sendable, Equatable {
    public let text: String
    public let toolCalls: [ToolCall]
    /// See `ChatMessage.providerState`.
    public let providerState: String?

    public init(text: String = "", toolCalls: [ToolCall] = [], providerState: String? = nil) {
        self.text = text
        self.toolCalls = toolCalls
        self.providerState = providerState
    }
}

/// A "brain". Lolek uses an on-device llama.cpp provider, Bolek a remote one.
public protocol ModelProvider: Sendable {
    var profile: ModelProfile { get }
    func respond(to request: ModelRequest) async throws -> ModelResponse
    /// Like `respond(to:)`, but calls `onText` with the answer so far (the full visible text
    /// each time, never tool-call markup). Providers that cannot stream use the default.
    func respond(to request: ModelRequest, onText: @escaping @Sendable (String) -> Void) async throws -> ModelResponse
    /// Lets an on-device provider read the fixed part of the prompt (system text and tools) ahead of
    /// the first message. The default does nothing.
    func warmUp(for request: ModelRequest) async
}

extension ModelProvider {
    public func warmUp(for request: ModelRequest) async {}

    public func respond(to request: ModelRequest, onText: @escaping @Sendable (String) -> Void) async throws -> ModelResponse {
        try await respond(to: request)
    }
}
