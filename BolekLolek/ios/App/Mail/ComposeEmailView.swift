import AgentCore
import SwiftUI

private let accent = AgentMode.lolek.accent

/// Where an email is written, read over and sent. Reading and sending happen on this iPhone, straight to Gmail.
struct ComposeEmailView: View {
    @State var draft: ComposeDraft
    let connection: MailConnection
    /// Asks Lolek (on this iPhone) to write the reply from a short instruction; nil when the model is not ready.
    var writeWithLolek: ((String, ComposeDraft) async throws -> String)?
    var onSent: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var instruction = ""
    @State private var isWriting = false
    @State private var isSending = false
    @State private var sent = false
    @State private var error: String?
    @State private var canSend = true
    @FocusState private var focus: Field?
    private enum Field { case to, subject, body, instruction }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                header
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if !canSend { permissionBanner }
                        if connection.accounts.count > 1 { fromRow; Divider() }
                        row("To") { TextField("name@example.com", text: $draft.outgoing.to).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled().focused($focus, equals: .to).accessibilityIdentifier("compose-to") }
                        Divider()
                        row("Subject") { TextField("Subject", text: $draft.outgoing.subject).focused($focus, equals: .subject).accessibilityIdentifier("compose-subject") }
                        Divider()
                        if writeWithLolek != nil { lolekRow; Divider() }
                        TextEditor(text: $draft.outgoing.body)
                            .font(.system(size: 17))
                            .frame(minHeight: 200)
                            .padding(.horizontal, 16).padding(.top, 8)
                            .focused($focus, equals: .body)
                            .accessibilityIdentifier("compose-body")
                        if draft.outgoing.quoted != nil {
                            Label("The original message is quoted below your text.", systemImage: "quote.opening")
                                .font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 20).padding(.vertical, 12)
                        }
                        if let error { Text(verbatim: error).font(.footnote).foregroundStyle(.red).padding(.horizontal, 20).padding(.bottom, 12).accessibilityIdentifier("compose-error") }
                        Label("Sent from your Gmail, straight from this iPhone.", systemImage: "lock.fill")
                            .font(.footnote).foregroundStyle(.tertiary).padding(.horizontal, 20).padding(.bottom, 24)
                    }
                }
                .scrollDismissesKeyboard(.interactively)
            }
            if sent { sentOverlay }
        }
        .background(Color(.systemBackground))
        .tint(accent)
        .task { await refreshPermission() }
        .interactiveDismissDisabled(isSending)
    }

    // MARK: Pieces

    private var header: some View {
        HStack {
            Button("Cancel") { dismiss() }.font(.system(size: 17)).frame(minHeight: 44)
            Spacer()
            Text(draft.original == nil ? "New email" : "Reply").font(.system(size: 17, weight: .semibold))
            Spacer()
            Button(action: send) {
                if isSending { ProgressView() } else { Text("Send").font(.system(size: 17, weight: .bold)) }
            }
            .frame(minWidth: 44, minHeight: 44)
            .disabled(!canSubmit)
            .accessibilityIdentifier("compose-send")
        }
        .padding(.horizontal, 20).padding(.top, 8)
    }

    private func row<Content: View>(_ label: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 10) {
            Text(label).font(.system(size: 16)).foregroundStyle(.secondary).frame(width: 64, alignment: .leading)
            content().font(.system(size: 17))
        }
        .padding(.horizontal, 20).frame(minHeight: 48)
    }

    private var fromRow: some View {
        row("From") {
            Menu {
                ForEach(connection.accounts, id: \.self) { address in
                    Button { draft.account = address; Task { await refreshPermission() } } label: { Label(address, systemImage: draft.account == address ? "checkmark" : "envelope") }
                }
            } label: {
                HStack(spacing: 4) { Text(verbatim: draft.account ?? String(localized: "Choose account")); Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold)) }
                    .foregroundStyle(draft.account == nil ? Color.red : Color.primary)
            }
            .accessibilityIdentifier("compose-from")
        }
    }

    private var lolekRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles").foregroundStyle(accent)
            TextField("Tell Lolek what to say…", text: $instruction, axis: .vertical)
                .font(.system(size: 16)).lineLimit(1...3)
                .focused($focus, equals: .instruction)
                .accessibilityIdentifier("compose-instruction")
            if isWriting { ProgressView() } else {
                Button { Task { await write() } } label: {
                    Text("Write").font(.system(size: 15, weight: .semibold)).foregroundStyle(accent)
                        .padding(.horizontal, 14).frame(minHeight: 34).overlay(Capsule().strokeBorder(accent, lineWidth: 1.5))
                }
                .disabled(instruction.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityIdentifier("compose-write")
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 8)
    }

    private var permissionBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("This account is connected for reading only. Reconnect it and allow sending to send from the app.").font(.system(size: 14))
            HStack(spacing: 10) {
                Button { Task { _ = await connection.connect(); await refreshPermission() } } label: {
                    Text("Reconnect Gmail").font(.system(size: 14, weight: .semibold)).foregroundStyle(accent)
                        .padding(.horizontal, 14).frame(minHeight: 34).overlay(Capsule().strokeBorder(accent, lineWidth: 1.5))
                }
                .accessibilityIdentifier("compose-reconnect")
                Button { openInMailApp() } label: { Text("Open in Mail app").font(.system(size: 14)).foregroundStyle(.secondary) }
            }
        }
        .padding(14).background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12)).padding(.horizontal, 20).padding(.vertical, 12)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("compose-readonly-banner")
    }

    private var sentOverlay: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 54)).foregroundStyle(accent)
            Text("Sent").font(.system(size: 22, weight: .bold))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).background(Color(.systemBackground).opacity(0.96))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("compose-sent")
        .transition(.opacity)
    }

    // MARK: Actions

    private var recipientLooksRight: Bool {
        (try? MIMEBuilder.message(OutgoingEmail(from: "me@example.com", to: draft.outgoing.to, subject: "x", body: "x"))) != nil
    }

    private var canSubmit: Bool {
        canSend && !isSending && recipientLooksRight && !draft.outgoing.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (connection.accounts.count <= 1 || draft.account != nil)
    }

    private func refreshPermission() async {
        canSend = await connection.provider.canSend(from: draft.account)
        if connection.accounts.isEmpty { canSend = false }
    }

    private func send() {
        focus = nil
        error = nil
        isSending = true
        Task {
            defer { isSending = false }
            do {
                try await connection.provider.send(draft.outgoing, from: draft.account)
                withAnimation { sent = true }
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                onSent()
                dismiss()
            } catch {
                self.error = (error as? ToolError)?.message ?? error.localizedDescription
                await refreshPermission()
            }
        }
    }

    private func write() async {
        guard let writeWithLolek else { return }
        isWriting = true
        error = nil
        defer { isWriting = false }
        do {
            let text = try await writeWithLolek(instruction, draft)
            draft.outgoing.body = text
            instruction = ""
            focus = .body
        } catch {
            self.error = (error as? ToolError)?.message ?? String(localized: "Lolek could not write that. Try again, or write it yourself.")
        }
    }

    private func openInMailApp() {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = draft.outgoing.to
        components.queryItems = [URLQueryItem(name: "subject", value: draft.outgoing.subject), URLQueryItem(name: "body", value: draft.outgoing.body)]
        if let url = components.url { openURL(url) }
    }
}
