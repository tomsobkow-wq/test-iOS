import AgentCore
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// A plain text-message thread. Anything that needs the user's say-so shows up
/// as a question with reply buttons under it, never as a separate screen.
struct ChatView: View {
    @Bindable var viewModel: ChatViewModel
    /// Only for Lolek: the one-time model download.
    var setup: LolekSetupModel?

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        if viewModel.visibleMessages.isEmpty {
                            Bubble(text: Text(viewModel.mode.intro), isMine: false, accent: viewModel.mode.accent)
                        }
                        if let setup, !setup.isReady {
                            SetupBubble(setup: setup, accent: viewModel.mode.accent)
                        }
                        ForEach(viewModel.visibleMessages) { message in
                            Bubble(text: Text(verbatim: message.text), isMine: message.role == .user, accent: viewModel.mode.accent)
                        }
                        if let status = viewModel.importStatus {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text(verbatim: status).font(.system(size: 15)).foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 15).padding(.vertical, 10)
                            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 19))
                        } else if viewModel.isWorking, viewModel.approvals.pending == nil {
                            if viewModel.streamingText.isEmpty {
                                TypingBubble()
                            } else {
                                Bubble(text: Text(verbatim: viewModel.streamingText), isMine: false, accent: viewModel.mode.accent)
                            }
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
                .onChange(of: viewModel.streamingText) { scrollToBottom(proxy) }
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
    @State private var showFiles = false
    @State private var photo: PhotosPickerItem?

    private static let fileTypes: [UTType] = [.pdf, .commaSeparatedText, .tabSeparatedText, .plainText, .image, UTType(filenameExtension: "csv")].compactMap { $0 }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if viewModel.documents != nil {
                Menu {
                    Button { showFiles = true } label: { Label("Files", systemImage: "folder") }
                    PhotosPicker(selection: $photo, matching: .images) { Label("Photos", systemImage: "photo") }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 36)
                        .background(Color(.secondarySystemBackground), in: Circle())
                }
                .padding(.bottom, 3)
                .accessibilityLabel(Text("Add a document or statement"))
                .disabled(viewModel.isWorking)
            }
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
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .fileImporter(isPresented: $showFiles, allowedContentTypes: Self.fileTypes) { result in
            if case let .success(url) = result { viewModel.importFile(at: url) }
        }
        .onChange(of: photo) {
            guard let item = photo else { return }
            photo = nil
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) { viewModel.importDocument(data: data, name: "photo.jpg") }
            }
        }
    }
}

/// "Lolek needs to download his brain once." Progress and the button live in the chat.
struct SetupBubble: View {
    @Bindable var setup: LolekSetupModel
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch setup.state {
            case .needsDownload:
                Bubble(text: Text("Lolek needs to download his brain once (\(setup.sizeText)). Wi-Fi is best. After that he works offline and nothing leaves this phone."), isMine: false, accent: accent)
                PillButton(title: "Download", accent: accent) { setup.start() }
            case let .downloading(fraction):
                Bubble(text: Text("Getting Lolek ready… \(Int(fraction * 100))%"), isMine: false, accent: accent)
                ProgressView(value: fraction).tint(accent).padding(.horizontal, 6)
            case .verifying:
                Bubble(text: Text("Checking the download…"), isMine: false, accent: accent)
            case let .failed(message):
                Bubble(text: Text(verbatim: message), isMine: false, accent: accent)
                PillButton(title: "Try again", accent: accent) { setup.start() }
            case .ready:
                EmptyView()
            }
        }
        .padding(.bottom, 4)
    }
}
