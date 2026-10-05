import AgentCore
import SwiftUI

private let mailAccent = AgentMode.lolek.accent

/// One email, read on this iPhone. Lolek can summarise it, answer questions about it, or start a reply.
struct MailDetailView: View {
    let item: EmailSummary
    let provider: MultiEmailProvider
    var onSummarise: () -> Void
    var onAsk: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var message: EmailMessage?
    @State private var failure: String?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(verbatim: item.subject)
                        .font(.system(size: 24, weight: .bold))
                        .fixedSize(horizontal: false, vertical: true)
                    sender
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
        .task { await load() }
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
        do { message = try await provider.message(id: item.id) } catch { failure = (error as? ToolError)?.message ?? error.localizedDescription }
    }

    /// Opens the Mail app with the draft addressed; the user writes and sends it there.
    private func reply() {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = item.replyAddress
        let subject = item.subject.lowercased().hasPrefix("re:") ? item.subject : "Re: " + item.subject
        components.queryItems = [URLQueryItem(name: "subject", value: subject)]
        if let url = components.url { openURL(url) }
    }
}
