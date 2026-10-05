import AgentCore
import Observation

struct PendingApproval: Identifiable {
    let request: ApprovalRequest
    fileprivate let continuation: CheckedContinuation<ApprovalDecision, Never>

    var id: String { request.id }
}

/// Bridges the agent's approval requests to the UI. One request at a time.
@MainActor
@Observable
final class ApprovalCenter {
    private(set) var pending: PendingApproval?

    func request(_ request: ApprovalRequest) async -> ApprovalDecision {
        await withCheckedContinuation { continuation in
            pending?.continuation.resume(returning: .deny)
            pending = PendingApproval(request: request, continuation: continuation)
        }
    }

    func resolve(_ decision: ApprovalDecision) {
        guard let pending else { return }
        self.pending = nil
        pending.continuation.resume(returning: decision)
    }
}

struct ApprovalCenterHandler: ApprovalHandler {
    let center: ApprovalCenter

    func decide(_ request: ApprovalRequest) async -> ApprovalDecision {
        await center.request(request)
    }
}
