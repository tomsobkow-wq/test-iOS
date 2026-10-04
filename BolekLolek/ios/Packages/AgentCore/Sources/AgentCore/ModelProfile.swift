import Foundation

/// Everything model-specific lives here, so swapping Bielik and Qwen is a
/// profile change rather than a code change.
public struct ModelProfile: Identifiable, Codable, Sendable, Equatable {
    public enum Runtime: String, Codable, Sendable {
        case onDevice, remote
    }

    public enum ChatTemplate: String, Codable, Sendable {
        case chatML
        case openAICompatible
    }

    public enum ToolCallFormat: String, Codable, Sendable {
        /// `<tool_call>{"name": ..., "arguments": {...}}</tool_call>` in the text. Used for
        /// Bielik, whose template has no tool support, so we ask for this format ourselves.
        case hermesJSON
        /// `<tool_call><function=name><parameter=k>v</parameter></function></tool_call>`.
        /// Qwen3.5's native format, read from its GGUF chat template.
        case qwenXML
        /// Structured `tool_calls` in an OpenAI-compatible API response.
        case openAIFunctions
    }

    public let id: String
    public let displayName: String
    public let runtime: Runtime
    public let chatTemplate: ChatTemplate
    public let toolCallFormat: ToolCallFormat
    public let contextTokens: Int
    public let maxOutputTokens: Int
    public let temperature: Double

    public init(
        id: String,
        displayName: String,
        runtime: Runtime,
        chatTemplate: ChatTemplate,
        toolCallFormat: ToolCallFormat,
        contextTokens: Int,
        maxOutputTokens: Int,
        temperature: Double
    ) {
        self.id = id
        self.displayName = displayName
        self.runtime = runtime
        self.chatTemplate = chatTemplate
        self.toolCallFormat = toolCallFormat
        self.contextTokens = contextTokens
        self.maxOutputTokens = maxOutputTokens
        self.temperature = temperature
    }
}

extension ModelProfile {
    // Templates and tool-call formats are verified against the chat templates embedded in
    // the GGUF files; LolekRuntime's golden tests render them with Jinja and compare.
    public static let bielikV3_4_5B = ModelProfile(
        id: "bielik-v3-4.5b-instruct",
        displayName: "Bielik v3 4.5B",
        runtime: .onDevice,
        chatTemplate: .chatML,
        toolCallFormat: .hermesJSON,
        contextTokens: 8_192,
        maxOutputTokens: 512,
        temperature: 0.3
    )

    public static let qwen35_4B = ModelProfile(
        id: "qwen3.5-4b-instruct",
        displayName: "Qwen3.5 4B",
        runtime: .onDevice,
        chatTemplate: .chatML,
        toolCallFormat: .qwenXML,
        contextTokens: 8_192,
        maxOutputTokens: 512,
        temperature: 0.3
    )

    public static let kimiK3 = ModelProfile(
        // Same id on OpenRouter and on Phala's own API.
        id: "moonshotai/kimi-k3",
        displayName: "Kimi K3",
        runtime: .remote,
        chatTemplate: .openAICompatible,
        toolCallFormat: .openAIFunctions,
        contextTokens: 1_048_576,
        // Reasoning tokens count towards this limit, so keep it generous.
        maxOutputTokens: 8_192,
        temperature: 0.6
    )
}

public enum ModelCatalog {
    /// Lolek's model. Switch to `.qwen35_4B` here if the evals favour it.
    public static let lolekDefault: ModelProfile = .bielikV3_4_5B
    public static let lolekAlternatives: [ModelProfile] = [.qwen35_4B]
    public static let bolek: ModelProfile = .kimiK3
}
