import AgentCore
import SwiftUI

/// A plain text-message thread. Anything that needs the user's say-so shows up
/// as a question with reply buttons under it, never as a separate screen.
struct ChatView: View {
    @Bindable var viewModel: ChatViewModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        if viewModel.visibleMessages.isEmpty {
                            Bubble(text: Text(viewModel.mode.intro), isMine: false, accent: viewModel.mode.accent)
                        }
                        ForEach(viewModel.visibleMessages) { message in
                            Bubble(text: Text(verbatim: message.text), isMine: message.role == .user, accent: viewModel.mode.accent)
                        }
                        if viewModel.isWorking, viewModel.approvals.pending == nil {
                            TypingBubble()
                        }
                        if let pending = viewModel.approvals.pending {
                            ApprovalMessage(request: pending.request, accent: viewModel.mode.accent) {
                                viewModel.approvals.resolve($0)
                            }
                        }
                        if let errorText = viewModel.errorText {
                            Text(verbatim: errorText)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .padding(.horizontal, 6)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: viewModel.messages.count) { scrollToBottom(proxy) }
                .onChange(of: viewModel.approvals.pending?.id) { scrollToBottom(proxy) }
                .onChange(of: viewModel.isWorking) { scrollToBottom(proxy) }
            }

            Composer(viewModel: viewModel)
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("bottom", anchor: .bottom) }
    }
}

struct Bubble: View {
    let text: Text
    let isMine: Bool
    let accent: Color

    var body: some View {
        HStack {
            if isMine { Spacer(minLength: 56) }
            text
                .font(.system(size: 16))
                .foregroundStyle(isMine ? Color.white : Color.primary)
                .padding(.horizontal, 15)
                .padding(.vertical, 10)
                .background(isMine ? accent : Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 19))
            if !isMine { Spacer(minLength: 56) }
        }
    }
}

struct TypingBubble: View {
    var body: some View {
        HStack {
            ProgressView()
                .padding(.horizontal, 15)
                .padding(.vertical, 10)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 19))
            Spacer()
        }
    }
}

/// "Do you want me to…?" with two reply buttons.
struct ApprovalMessage: View {
    let request: ApprovalRequest
    let accent: Color
    let onDecide: (ApprovalDecision) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Bubble(text: Text(verbatim: ApprovalText.question(for: request)), isMine: false, accent: accent)
            HStack(spacing: 8) {
                PillButton(title: "Allow", accent: accent) { onDecide(.allowOnce) }
                PillButton(title: "Not now", accent: accent) { onDecide(.deny) }
            }
        }
        .padding(.bottom, 4)
    }
}

struct PillButton: View {
    let title: LocalizedStringKey
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(accent)
                .padding(.horizontal, 20)
                .frame(minHeight: 44)
                .overlay(Capsule().strokeBorder(accent, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }
}

/// Turns a pending tool call into a sentence the user can approve at a glance.
enum ApprovalText {
    static func question(for request: ApprovalRequest) -> String {
        guard let data = request.argumentsJSON.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              !object.isEmpty
        else { return request.summary }
        let details = object.keys.sorted().map { "\($0): \(object[$0].map { "\($0)" } ?? "")" }.joined(separator: "\n")
        return request.summary + "\n\n" + details
    }
}

struct Composer: View {
    @Bindable var viewModel: ChatViewModel

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Message", text: $viewModel.draft, axis: .vertical)
                .lineLimit(1...5)
                .font(.system(size: 16))
                .padding(.leading, 16)
                .padding(.vertical, 9)
                .submitLabel(.send)
                .onSubmit(viewModel.send)
            Button(action: viewModel.send) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(viewModel.canSend ? Color.accentColor : Color(.systemGray3), in: Circle())
            }
            .padding(4)
            .disabled(!viewModel.canSend)
            .accessibilityLabel(Text("Send"))
        }
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Color(.systemGray4), lineWidth: 1))
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }
}
