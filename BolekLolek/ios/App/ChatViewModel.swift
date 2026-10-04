import AgentCore
import Foundation
import Observation

@MainActor
@Observable
final class ChatViewModel {
    let mode: AgentMode
    let approvals: ApprovalCenter
    var draft = ""
    private(set) var messages: [ChatMessage] = []
    private(set) var isWorking = false
    /// The answer as it is being written, before the turn finishes.
    private(set) var streamingText = ""
    private(set) var errorText: String?

    private let session: AgentSession

    init(mode: AgentMode, provider: any ModelProvider, registry: ToolRegistry) {
        let approvals = ApprovalCenter()
        self.mode = mode
        self.approvals = approvals
        self.session = AgentSession(
            mode: mode,
            provider: provider,
            registry: registry,
            approvalHandler: ApprovalCenterHandler(center: approvals)
        )
    }

    var visibleMessages: [ChatMessage] {
        messages.filter { message in
            switch message.role {
            case .system: false
            case .assistant: !message.text.isEmpty
            case .user, .tool: true
            }
        }
    }

    var actionCount: Int {
        messages.filter { $0.role == .tool }.count
    }

    var canSend: Bool {
        !isWorking && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Reads the fixed prompt ahead of time so the first message is quick (on-device models only).
    func warmUp() {
        Task { await session.warmUp() }
    }

    func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isWorking else { return }
        draft = ""
        errorText = nil
        isWorking = true
        streamingText = ""
        // Shown right away; replaced by the session transcript when the turn ends.
        messages.append(ChatMessage(role: .user, text: text))

        Task {
            do {
                try await session.send(text) { [weak self] partial in
                    Task { @MainActor in self?.streamingText = partial }
                }
            } catch {
                errorText = error.localizedDescription
            }
            messages = await session.transcript
            streamingText = ""
            isWorking = false
        }
    }
}
