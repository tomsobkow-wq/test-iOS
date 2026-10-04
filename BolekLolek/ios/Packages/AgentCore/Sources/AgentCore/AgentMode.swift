import Foundation

/// The two assistants in the app. Display names live in the app target so
/// they can be renamed without touching the harness.
public enum AgentMode: String, CaseIterable, Codable, Sendable, Identifiable {
    /// Private, on-device, small model.
    case lolek
    /// Full agent, EU cloud, Kimi K3 in a TEE.
    case bolek

    public var id: String { rawValue }

    /// Upper bound on model round trips per user message. Lolek's small model
    /// is only trusted with short plans.
    public var maxSteps: Int {
        switch self {
        case .lolek: 3
        case .bolek: 25
        }
    }

    public func allows(_ tier: ToolTier) -> Bool {
        switch tier {
        case .both: true
        case .lolek: self == .lolek
        case .bolek: self == .bolek
        }
    }
}
