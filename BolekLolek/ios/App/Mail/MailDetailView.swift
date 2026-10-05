import AgentCore
import SwiftUI

private let mailAccent = AgentMode.lolek.accent

/// One email, read on this iPhone. Lolek can summarise it, answer questions about it, or start a reply.
struct MailDetailView: View {
    let item: EmailSummary
    let provider: MultiEmailProvider
    let connection: MailConnection
    var writeWithLolek: ((String, ComposeDraft) async throws -> String)?
    var onSummarise: () -> Void
    var onAsk: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var message: EmailMessage?
    @State private var failure: String?
    @State private var appointments: [AppointmentCandidate] = []
    @State private var states: [String: AppointmentCard.State] = [:]
    @State private var editing: AppointmentCandidate?
    @State private var changingID: String?
    @State private var replyDraft: ComposeDraft?
    @State private var calendarError: String?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(verbatim: item.subject)
                        .font(.system(size: 24, weight: .bold))
                        .fixedSize(horizontal: false, vertical: true)
                    sender
                    ForEach(appointments) { candidate in
                        AppointmentCard(
                            candidate: candidate, state: states[candidate.id] ?? .idle,
                            onAdd: { changingID = nil; editing = candidate },
                            onChange: { if case .saved(let id, _) = states[candidate.id] { changingID = id; editing = candidate } },
                            onRemove: { remove(candidate) },
                            onOpenCalendar: { openCalendar(at: candidate.start) }
                        )
                    }
                    Divider()
                    bodyText
                    Label("On this iPhone only", systemImage: "lock.fill")
                        .font(.footnote).foregroundStyle(.tertiary)
                        .padding(.top, 8)
                }
                .padding(.horizontal, 22)
                .padding(.top, 28)
                .padding(.bottom, 32)
            }
            actions
        }
        .background(Color(.systemBackground))
        .tint(mailAccent)
        .presentationDragIndicator(.visible)
        .sheet(item: $replyDraft) { draft in
            ComposeEmailView(draft: draft, connection: connection, writeWithLolek: writeWithLolek)
                .presentationDetents([.large])
        }
        .alert("Could not change the calendar", isPresented: Binding(get: { calendarError != nil }, set: { if !$0 { calendarError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(verbatim: calendarError ?? "") }
        .task { await load() }
        .sheet(item: $editing) { candidate in
            AppointmentSheet(candidate: candidate, existingID: changingID) { outcome, _ in
                if case .added(let id) = outcome { states[candidate.id] = .saved(id: id, alreadyThere: false) }
                else { states[candidate.id] = .saved(id: outcome.id, alreadyThere: changingID == nil) }
            }
        }
    }

    private var sender: some View {
        HStack(spacing: 12) {
            MailAvatar(item: item, size: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: EmailAddress.parse(item.from).name).font(.system(size: 17, weight: .semibold))
                Text(verbatim: EmailAddress.parse(item.from).address).font(.system(size: 14)).foregroundStyle(.secondary)
                Text(verbatim: MailDates.full(item.date) + (item.account.map { " · " + $0 } ?? ""))
                    .font(.system(size: 13)).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var bodyText: some View {
        if let message {
            Text(verbatim: EmailSanitizer.display(message.body.isEmpty ? item.snippet : message.body))
                .font(.system(size: 17))
                .lineSpacing(5)
                .textSelection(.enabled)
        } else if let failure {
            Text(verbatim: failure).font(.system(size: 16)).foregroundStyle(.secondary)
        } else {
            HStack(spacing: 10) { ProgressView(); Text("Opening…").foregroundStyle(.secondary) }
        }
    }

    private var actions: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 10) {
                Button { dismiss(); onSummarise() } label: {
                    Text("Summarise").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 46).background(mailAccent, in: Capsule())
                }
                .accessibilityIdentifier("mail-summarise")
                outlined("Ask Lolek") { dismiss(); onAsk() }
                outlined("Reply") { reply() }
                    .accessibilityIdentifier("mail-reply")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .background(.bar)
    }

    private func outlined(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 16, weight: .semibold)).foregroundStyle(mailAccent)
                .padding(.horizontal, 18).frame(minHeight: 46)
                .overlay(Capsule().strokeBorder(mailAccent, lineWidth: 1.5))
        }
    }

    private func load() async {
        do {
            let loaded = try await provider.message(id: item.id)
            message = loaded
            appointments = loaded.appointments()
        } catch { failure = (error as? ToolError)?.message ?? error.localizedDescription }
    }

    private func remove(_ candidate: AppointmentCandidate) {
        guard case .saved(let id, _) = states[candidate.id] else { return }
        Task {
            do { try await CalendarAdder.remove(id: id); states[candidate.id] = .idle }
            catch { calendarError = (error as? ToolError)?.message ?? error.localizedDescription }
        }
    }

    /// Opens the Calendar app on that day.
    private func openCalendar(at date: Date) {
        if let url = URL(string: "calshow:\(Int(date.timeIntervalSinceReferenceDate))") { openURL(url) }
    }

    /// Opens the composer, addressed to the sender and in the same conversation; the user writes (or has Lolek write) and sends it here.
    private func reply() {
        let account = item.account ?? (connection.accounts.count == 1 ? connection.accounts.first : nil)
        let original = message ?? EmailMessage(summary: item, to: "", body: item.snippet)
        replyDraft = ComposeDraft(outgoing: OutgoingEmail.reply(to: original, from: account ?? ""), original: original, account: account)
    }
}
