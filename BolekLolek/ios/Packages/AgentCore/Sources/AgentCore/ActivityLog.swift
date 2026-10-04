import Foundation

public struct ActivityEntry: Identifiable, Sendable, Equatable {
    public enum Outcome: String, Sendable {
        case succeeded, failed, denied, rejected
    }

    public let id: UUID
    public let date: Date
    public let mode: AgentMode
    public let toolName: String
    public let outcome: Outcome

    public init(id: UUID = UUID(), date: Date = Date(), mode: AgentMode, toolName: String, outcome: Outcome) {
        self.id = id
        self.date = date
        self.mode = mode
        self.toolName = toolName
        self.outcome = outcome
    }
}

/// Every tool call the agent attempted, visible to the user.
public actor ActivityLog {
    public private(set) var entries: [ActivityEntry] = []

    public init() {}

    public func record(_ entry: ActivityEntry) {
        entries.append(entry)
    }
}
