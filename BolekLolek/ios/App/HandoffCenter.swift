import AgentCore
import Observation

/// Holds the "Ask Bolek" offer Lolek made for the last request. Offering sends nothing; tapping the button does.
@MainActor
@Observable
final class HandoffCenter: HandoffSink {
    struct Offer: Equatable { let request: String }
    private(set) var current: Offer?

    func offer(request: String) async { current = Offer(request: request) }
    func clear() { current = nil }
}
