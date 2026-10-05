import AgentCore
import Observation
import SwiftUI

/// An email being written in the app, whether from the Reply button or because Lolek drafted it from a chat request.
struct ComposeDraft: Identifiable, Equatable {
    let id = UUID()
    var outgoing: OutgoingEmail
    /// The email being answered, so Lolek can read it when asked to write the reply.
    var original: EmailMessage?
    /// Which connected mailbox it goes out from (nil: the only one).
    var account: String?

    static func == (a: ComposeDraft, b: ComposeDraft) -> Bool { a.id == b.id }
}

/// Holds the draft the model asked for. Presenting it sends nothing; the Send button in the composer does.
@MainActor
@Observable
final class ComposeCenter: ComposeSink {
    var draft: ComposeDraft?
    /// Which mailbox a draft goes out from when the user has only one connected.
    @ObservationIgnored var defaultAccount: @MainActor () -> String? = { nil }

    nonisolated func present(_ request: EmailDraftRequest) async {
        await MainActor.run {
            draft = ComposeDraft(
                outgoing: OutgoingEmail(from: "", to: request.to, subject: request.subject, body: request.body),
                original: nil, account: defaultAccount()
            )
        }
    }
}
