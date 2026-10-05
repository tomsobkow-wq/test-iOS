import XCTest
@testable import AgentCore

final class ConversationLanguageTests: XCTestCase {
    func testPolishDiacriticsWin() {
        XCTAssertEqual(ConversationLanguage.detect("Kupić mleko", fallback: .en), .pl)
    }

    func testPolishFunctionWords() {
        XCTAssertEqual(ConversationLanguage.detect("czy jest jutro na liscie", fallback: .en), .pl)
    }

    func testEnglishFunctionWords() {
        XCTAssertEqual(ConversationLanguage.detect("I need to buy milk for the party", fallback: .pl), .en)
    }

    func testTieKeepsFallback() {
        XCTAssertEqual(ConversationLanguage.detect("OK", fallback: .pl), .pl)
        XCTAssertEqual(ConversationLanguage.detect("OK", fallback: .en), .en)
    }
}

final class ToolRegistryTests: XCTestCase {
    func testModesOnlySeeTheirTiers() {
        let registry = ToolRegistry([
            StubTool(name: "shared", tier: .both),
            StubTool(name: "cloud_only", tier: .bolek),
            StubTool(name: "device_only", tier: .lolek),
        ])
        XCTAssertEqual(registry.tools(for: .lolek).map { $0.name }, ["device_only", "shared"])
        XCTAssertEqual(registry.tools(for: .bolek).map { $0.name }, ["cloud_only", "shared"])
        XCTAssertNil(registry.tool(named: "cloud_only", for: .lolek))
    }
}

final class AgentSessionTests: XCTestCase {
    func testLocalWriteRunsWithoutApproval() async throws {
        let notes = NoteStore()
        let approvals = StubApprovals(.deny)
        let session = makeSession(.lolek, notes: notes, approvals: approvals)

        try await session.send("note: buy milk")

        let saved = await notes.notes
        let asked = await approvals.count
        let last = await session.transcript.last
        XCTAssertEqual(saved, ["buy milk"])
        XCTAssertEqual(asked, 0)
        XCTAssertEqual(last?.text, "Done.")
    }

    func testRepliesInPolish() async throws {
        let session = makeSession(.lolek, notes: NoteStore(), approvals: StubApprovals(.deny))

        try await session.send("notatka: kupić mleko")

        let last = await session.transcript.last
        XCTAssertEqual(last?.text, "Gotowe.")
    }

    func testSendNeedsApprovalAndDenyIsRespected() async throws {
        let approvals = StubApprovals(.deny)
        let session = makeSession(.bolek, notes: NoteStore(), approvals: approvals)

        try await session.send("send: hello")

        let asked = await approvals.count
        let transcript = await session.transcript
        let entries = await session.activity.entries
        let toolMessage = transcript.first { $0.role == .tool }
        let outcomes = entries.map { $0.outcome }
        XCTAssertEqual(asked, 1)
        XCTAssertEqual(toolMessage?.isError, true)
        XCTAssertEqual(outcomes, [.denied])
    }

    func testAlwaysAllowIsRemembered() async throws {
        let approvals = StubApprovals(.alwaysAllow)
        let session = makeSession(.bolek, notes: NoteStore(), approvals: approvals)

        try await session.send("send: one")
        try await session.send("send: two")

        let asked = await approvals.count
        XCTAssertEqual(asked, 1)
    }

    func testStepLimitStopsRunawayLoops() async throws {
        let session = AgentSession(
            mode: .lolek,
            provider: AlwaysCallsToolProvider(),
            registry: ToolRegistry([AddNoteTool(store: NoteStore())]),
            approvalHandler: StubApprovals(.deny),
            language: .en
        )

        let added = try await session.send("loop")

        let modelTurns = added.filter { $0.role == .assistant && !$0.toolCalls.isEmpty }.count
        XCTAssertEqual(modelTurns, AgentMode.lolek.maxSteps)
        XCTAssertTrue(added.last?.text.hasPrefix("I stopped after") ?? false)
    }

    func testUnknownToolIsRejected() async throws {
        // Lolek cannot reach a Bolek-only tool even if the model asks for it.
        let session = AgentSession(
            mode: .lolek,
            provider: ScriptedProvider(calls: ["cloud_only"]),
            registry: ToolRegistry([StubTool(name: "cloud_only", tier: .bolek)]),
            approvalHandler: StubApprovals(.allowOnce),
            language: .en
        )

        try await session.send("hi")

        let entries = await session.activity.entries
        XCTAssertEqual(entries.map { $0.outcome }, [.rejected])
    }

    private func makeSession(_ mode: AgentMode, notes: NoteStore, approvals: StubApprovals) -> AgentSession {
        let profile = mode == .lolek ? ModelCatalog.lolekDefault : ModelCatalog.bolek
        return AgentSession(
            mode: mode,
            provider: DemoModelProvider(profile: profile),
            registry: ToolRegistry([AddNoteTool(store: notes), DemoSendMessageTool()]),
            approvalHandler: approvals,
            language: .en
        )
    }
}

// MARK: - Test doubles

private actor StubApprovals: ApprovalHandler {
    let decision: ApprovalDecision
    private(set) var count = 0

    init(_ decision: ApprovalDecision) {
        self.decision = decision
    }

    func decide(_ request: ApprovalRequest) async -> ApprovalDecision {
        count += 1
        return decision
    }
}

private struct StubTool: Tool {
    let name: String
    let description = LocalizedText(en: "Stub", pl: "Atrapa")
    let parametersSchema = "{}"
    let tier: ToolTier
    let risk = ToolRisk.read

    init(name: String, tier: ToolTier) {
        self.name = name
        self.tier = tier
    }

    func run(argumentsJSON: String) async throws -> String { "ok" }
}

private struct AlwaysCallsToolProvider: ModelProvider {
    let profile = ModelCatalog.lolekDefault

    func respond(to request: ModelRequest) async throws -> ModelResponse {
        ModelResponse(toolCalls: [ToolCall(name: "add_note", argumentsJSON: #"{"text":"again"}"#)])
    }
}

/// Calls the given tools once, then answers with text.
private struct ScriptedProvider: ModelProvider {
    let profile = ModelCatalog.lolekDefault
    let calls: [String]

    func respond(to request: ModelRequest) async throws -> ModelResponse {
        if request.messages.last?.role == .tool {
            return ModelResponse(text: "done")
        }
        return ModelResponse(toolCalls: calls.map { ToolCall(name: $0, argumentsJSON: "{}") })
    }
}
