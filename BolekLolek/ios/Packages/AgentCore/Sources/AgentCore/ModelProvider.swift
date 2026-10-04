import Foundation

public struct ModelRequest: Sendable {
    public let mode: AgentMode
    public let systemPrompt: String
    public let messages: [ChatMessage]
    public let tools: [ToolSpec]
    public let language: ConversationLanguage

    public init(
        mode: AgentMode,
        systemPrompt: String,
        messages: [ChatMessage],
        tools: [ToolSpec],
        language: ConversationLanguage
    ) {
        self.mode = mode
        self.systemPrompt = systemPrompt
        self.messages = messages
        self.tools = tools
        self.language = language
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
/// Streaming is added with the real runtimes (build step 2).
public protocol ModelProvider: Sendable {
    var profile: ModelProfile { get }
    func respond(to request: ModelRequest) async throws -> ModelResponse
}
