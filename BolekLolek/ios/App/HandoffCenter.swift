import AgentCore
import Observation

/// Holds the "Ask Bolek" offer Lolek made for the last request. Offering sends nothing; tapping the button does.
@MainActor
@Observable
final class HandoffCenter: HandoffSink {
    struct Offer: Equatable { let request: String }
    private(set) var current: Offer?

    private var userText: String?

    /// What goes to Bolek is the user's own message, never text the model wrote: the model may have just read an email
    /// or a document, and none of that may travel to the cloud through this button.
    func offer(request: String) async { current = Offer(request: userText ?? "") }
    func begin(userText: String) { self.userText = userText; current = nil }
    func clear() { current = nil }
}
