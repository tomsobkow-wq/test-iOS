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

    func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isWorking else { return }
        draft = ""
        errorText = nil
        isWorking = true
        // Shown right away; replaced by the session transcript when the turn ends.
        messages.append(ChatMessage(role: .user, text: text))

        Task {
            do {
                try await session.send(text)
            } catch {
                errorText = error.localizedDescription
            }
            messages = await session.transcript
            isWorking = false
        }
    }
}
