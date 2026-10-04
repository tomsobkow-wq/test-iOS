import AgentCore
import SwiftUI

struct ChatView: View {
    @Bindable var viewModel: ChatViewModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if viewModel.visibleMessages.isEmpty {
                            Text(viewModel.mode.intro)
                                .foregroundStyle(.secondary)
                                .padding(.top, 24)
                        }
                        ForEach(viewModel.visibleMessages) { message in
                            MessageRow(message: message)
                                .id(message.id)
                        }
                        if viewModel.isWorking {
                            ProgressView()
                        }
                        if let errorText = viewModel.errorText {
                            Text(errorText)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    }
                    .padding()
                }
                .onChange(of: viewModel.messages.count) {
                    guard let last = viewModel.visibleMessages.last else { return }
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }

            if viewModel.actionCount > 0 {
                Text("\(viewModel.actionCount) actions in this chat")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }

            HStack(alignment: .bottom, spacing: 8) {
                TextField("Message", text: $viewModel.draft, axis: .vertical)
                    .lineLimit(1...5)
                    .textFieldStyle(.roundedBorder)
                Button(action: viewModel.send) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title)
                }
                .disabled(!viewModel.canSend)
                .accessibilityLabel(Text("Send"))
            }
            .padding()
        }
        .sheet(item: approvalBinding) { pending in
            ApprovalSheet(request: pending.request) { decision in
                viewModel.approvals.resolve(decision)
            }
        }
    }

    /// Dismissing the sheet any other way counts as "deny", so the agent never hangs.
    private var approvalBinding: Binding<PendingApproval?> {
        Binding(
            get: { viewModel.approvals.pending },
            set: { newValue in
                if newValue == nil { viewModel.approvals.resolve(.deny) }
            }
        )
    }
}

struct MessageRow: View {
    let message: ChatMessage

    var body: some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 40)
                Text(message.text)
                    .padding(10)
                    .background(Color.accentColor.opacity(0.2), in: RoundedRectangle(cornerRadius: 14))
            }
        case .assistant:
            HStack {
                Text(message.text)
                    .padding(10)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
                Spacer(minLength: 40)
            }
        case .tool:
            let title: LocalizedStringKey = message.isError ? "Action not completed" : "Action completed"
            Label(title, systemImage: message.isError ? "xmark.circle" : "checkmark.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .system:
            EmptyView()
        }
    }
}

struct ApprovalSheet: View {
    let request: ApprovalRequest
    let onDecide: (ApprovalDecision) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Approval needed")
                .font(.title2.bold())
            Text(request.summary)
            Text(request.argumentsJSON)
                .font(.footnote.monospaced())
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                onDecide(.allowOnce)
            } label: {
                Text("Allow once").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            Button {
                onDecide(.alwaysAllow)
            } label: {
                Text("Always allow").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            Button(role: .destructive) {
                onDecide(.deny)
            } label: {
                Text("Deny").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .presentationDetents([.medium])
    }
}
