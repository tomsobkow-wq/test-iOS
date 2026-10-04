import Foundation

public enum ApprovalDecision: String, Codable, Sendable {
    case allowOnce
    case alwaysAllow
    case deny
}

/// What the user is asked to approve.
public struct ApprovalRequest: Identifiable, Sendable, Equatable {
    public let id: String
    public let mode: AgentMode
    public let toolName: String
    /// Localized description of the tool.
    public let summary: String
    public let argumentsJSON: String
    public let risk: ToolRisk

    public init(id: String, mode: AgentMode, toolName: String, summary: String, argumentsJSON: String, risk: ToolRisk) {
        self.id = id
        self.mode = mode
        self.toolName = toolName
        self.summary = summary
        self.argumentsJSON = argumentsJSON
        self.risk = risk
    }
}

/// Asks the user. Implemented by the app's UI.
public protocol ApprovalHandler: Sendable {
    func decide(_ request: ApprovalRequest) async -> ApprovalDecision
}

/// Remembers "always allow" choices, per mode.
public actor ApprovalPolicy {
    private var alwaysAllowed: Set<String> = []

    public init() {}

    public func isAlwaysAllowed(_ toolName: String, mode: AgentMode) -> Bool {
        alwaysAllowed.contains(key(toolName, mode))
    }

    public func allowAlways(_ toolName: String, mode: AgentMode) {
        alwaysAllowed.insert(key(toolName, mode))
    }

    private func key(_ toolName: String, _ mode: AgentMode) -> String {
        "\(mode.rawValue):\(toolName)"
    }
}
