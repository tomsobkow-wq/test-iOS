import Foundation

public struct ChatMessage: Identifiable, Codable, Sendable, Equatable {
    public enum Role: String, Codable, Sendable {
        case system, user, assistant, tool
    }

    public let id: UUID
    public let role: Role
    public let text: String
    /// Tool calls requested by the assistant in this message.
    public let toolCalls: [ToolCall]
    /// For `.tool` messages: the call this is a result of.
    public let toolCallID: String?
    public let isError: Bool
    public let createdAt: Date
    /// Opaque data a provider needs echoed back next turn (for example Claude's
    /// thinking and search blocks). The UI and other providers never read it.
    public let providerState: String?

    public init(
        id: UUID = UUID(),
        role: Role,
        text: String,
        toolCalls: [ToolCall] = [],
        toolCallID: String? = nil,
        isError: Bool = false,
        createdAt: Date = Date(),
        providerState: String? = nil
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.toolCalls = toolCalls
        self.toolCallID = toolCallID
        self.isError = isError
        self.createdAt = createdAt
        self.providerState = providerState
    }
}
