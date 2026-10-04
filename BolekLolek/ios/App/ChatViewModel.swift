import AgentCore
import DocumentKit
import Foundation
import Observation

/// What Lolek needs to take in documents: where they are kept, how to summarise text, and whether the model is ready.
struct DocumentSupport {
    let store: DocumentStore
    let summarize: @Sendable ([DocumentChunk], ConversationLanguage) async throws -> String
    let modelReady: @MainActor () -> Bool
}

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
    /// "Reading your file…" while a document is being taken in.
    private(set) var importStatus: String?
    let documents: DocumentSupport?

    private let session: AgentSession
    private let isOnline: (@MainActor () -> Bool)?
    private let willSend: (@MainActor () -> Void)?

    init(
        mode: AgentMode, provider: any ModelProvider, registry: ToolRegistry, documents: DocumentSupport? = nil,
        planner: (any TurnPlanner)? = nil, fixedPromptLanguage: ConversationLanguage? = nil,
        isOnline: (@MainActor () -> Bool)? = nil, willSend: (@MainActor () -> Void)? = nil
    ) {
        self.documents = documents
        self.isOnline = isOnline
        self.willSend = willSend
        let approvals = ApprovalCenter()
        self.mode = mode
        self.approvals = approvals
        self.session = AgentSession(
            mode: mode,
            provider: provider,
            registry: registry,
            approvalHandler: ApprovalCenterHandler(center: approvals),
            // With documents: pick the obvious query tool ourselves and check every figure the model writes.
            verifier: documents.map { _ in GroundingVerifier() },
            planner: planner,
            fixedPromptLanguage: fixedPromptLanguage
        )
    }

    func register(tools: [any Tool]) {
        Task { await session.register(tools) }
    }

    /// Something Bolek found while the app was closed, such as a fare drop. Shown as Bolek's own message.
    func receive(notice: String) {
        Task {
            await session.append(ChatMessage(role: .assistant, text: notice))
            messages = await session.transcript
        }
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
        sendText(text)
    }

    /// Sends a message as if the user had typed it. Used by the "Ask Bolek" button.
    func sendText(_ text: String) {
        guard !isWorking else { return }
        errorText = nil
        isWorking = true
        streamingText = ""
        willSend?()
        // Shown right away; replaced by the session transcript when the turn ends.
        messages.append(ChatMessage(role: .user, text: text))

        // Bolek lives in the cloud. With no connection, say so kindly instead of failing.
        if let isOnline, !isOnline() {
            Task {
                await session.append(ChatMessage(role: .user, text: text))
                await session.append(ChatMessage(role: .assistant, text: String(localized: "Bolek needs the internet and there is no connection right now. Lolek still works offline.")))
                messages = await session.transcript
                isWorking = false
            }
            return
        }

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

    // MARK: Documents

    func importFile(at url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            errorText = String(localized: "I could not open that file.")
            return
        }
        importDocument(data: data, name: url.lastPathComponent)
    }

    /// Takes a file in: reads it, tells the user what it is, and keeps it on the phone. A statement is summarised by
    /// code at once; a text document is summarised by the model, which takes a few seconds.
    func importDocument(data: Data, name: String) {
        guard let documents, !isWorking else { return }
        errorText = nil
        isWorking = true
        importStatus = String(localized: "Reading your file…")
        messages.append(ChatMessage(role: .user, text: String(localized: "Added file: \(name)")))

        Task {
            let language = await session.language
            await session.append(ChatMessage(role: .user, text: String(localized: "Added file: \(name)")))
            do {
                let document = try await DocumentIngestor.ingest(data: data, fileName: name, into: documents.store, recognizer: VisionTextRecognizer())
                if let statement = document.statement {
                    let summary = StatementSummaryText.make(statement, language: language)
                    await documents.store.setSummary(summary, for: document.id)
                    await session.append(ChatMessage(role: .assistant, text: summary + "\n\n" + String(localized: "Ask me anything about it, for example “how much did I spend on food?”.")))
                } else if documents.modelReady() {
                    importStatus = String(localized: "Summarising the document…")
                    messages = await session.transcript
                    let summary = try await documents.summarize(document.chunks, language)
                    await documents.store.setSummary(summary, for: document.id)
                    await session.append(ChatMessage(role: .assistant, text: summary + "\n\n" + String(localized: "Ask me anything about it.")))
                } else {
                    await session.append(ChatMessage(role: .assistant, text: String(localized: "I saved the document. When my brain has finished downloading I can summarise it and answer questions about it.")))
                }
            } catch {
                await session.append(ChatMessage(role: .assistant, text: error.localizedDescription))
            }
            messages = await session.transcript
            importStatus = nil
            isWorking = false
        }
    }
}
