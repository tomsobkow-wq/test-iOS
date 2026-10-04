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
        case anthropicMessages
    }

    public enum ToolCallFormat: String, Codable, Sendable {
        /// `<tool_call>{"name": ..., "arguments": {...}}</tool_call>` in the text.
        case hermesTags
        /// Structured `tool_calls` in an OpenAI-compatible API response.
        case openAIFunctions
        /// `tool_use` / `tool_result` blocks in the Anthropic Messages API.
        case anthropicToolUse
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
    // Template and tool-call format for the on-device models are verified
    // against the GGUF metadata in build step 2.
    public static let bielikV3_4_5B = ModelProfile(
        id: "bielik-v3-4.5b-instruct",
        displayName: "Bielik v3 4.5B",
        runtime: .onDevice,
        chatTemplate: .chatML,
        toolCallFormat: .hermesTags,
        contextTokens: 8_192,
        maxOutputTokens: 512,
        temperature: 0.3
    )

    public static let qwen35_4B = ModelProfile(
        id: "qwen3.5-4b-instruct",
        displayName: "Qwen3.5 4B",
        runtime: .onDevice,
        chatTemplate: .chatML,
        toolCallFormat: .hermesTags,
        contextTokens: 8_192,
        maxOutputTokens: 512,
        temperature: 0.3
    )

    public static let kimiK3 = ModelProfile(
        id: "moonshotai/kimi-k3",
        displayName: "Kimi K3",
        runtime: .remote,
        chatTemplate: .openAICompatible,
        toolCallFormat: .openAIFunctions,
        contextTokens: 128_000,
        maxOutputTokens: 4_096,
        temperature: 0.6
    )
}

extension ModelProfile {
    /// Bolek's stand-in brain until Kimi K3 is hosted. Same app, different provider.
    public static let claudeSonnet55 = ModelProfile(
        id: "claude-sonnet-5-5",
        displayName: "Claude Sonnet 5.5",
        runtime: .remote,
        chatTemplate: .anthropicMessages,
        toolCallFormat: .anthropicToolUse,
        contextTokens: 1_000_000,
        maxOutputTokens: 4_096,
        temperature: 1.0
    )
}

public enum ModelCatalog {
    /// Lolek's model. Switch to `.qwen35_4B` here if the evals favour it.
    public static let lolekDefault: ModelProfile = .bielikV3_4_5B
    public static let lolekAlternatives: [ModelProfile] = [.qwen35_4B]
    public static let bolek: ModelProfile = .kimiK3
}
