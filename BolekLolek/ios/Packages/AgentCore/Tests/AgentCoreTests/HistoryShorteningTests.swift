import XCTest
@testable import AgentCore

private struct BigResultTool: Tool {
    let name: String
    let description = LocalizedText(en: "x", pl: "x")
    let parametersSchema = #"{"type":"object","properties":{}}"#
    let tier = ToolTier.lolek
    let risk = ToolRisk.read
    func run(argumentsJSON: String) async throws -> String { String(repeating: "line of results\n", count: 60) }
}

private final class Seen: @unchecked Sendable {
    private let lock = NSLock()
    private var all: [[ChatMessage]] = []
    func add(_ messages: [ChatMessage]) { lock.lock(); all.append(messages); lock.unlock() }
    var requests: [[ChatMessage]] { lock.lock(); defer { lock.unlock() }; return all }
}

private struct Recorder: ModelProvider {
    let seen: Seen
    var profile: ModelProfile { ModelCatalog.bolek }
    func respond(to request: ModelRequest) async throws -> ModelResponse {
        seen.add(request.messages)
        return ModelResponse(text: "ok", toolCalls: [])
    }
}

private struct PlanEvery: TurnPlanner {
    let tool: String
    func plan(userText: String, language: ConversationLanguage) async -> [ToolCall] { [ToolCall(name: tool, argumentsJSON: "{}")] }
}

final class HistoryShorteningTests: XCTestCase {
    func testOldSearchResultsShrinkButOtherResultsStay() async throws {
        let seen = Seen()
        let session = AgentSession(
            mode: .lolek, provider: Recorder(seen: seen),
            registry: ToolRegistry([BigResultTool(name: "search_email"), BigResultTool(name: "read_email")]),
            approvalHandler: AlwaysAllow(), planner: PlanEvery(tool: "search_email"), shortenOldResultsOf: ["search_email"]
        )
        _ = try await session.send("first")
        _ = try await session.send("second")
        let last = try XCTUnwrap(seen.requests.last)
        let tools = last.filter { $0.role == .tool }
        XCTAssertEqual(tools.count, 2)
        XCTAssertTrue(tools[0].text.hasPrefix("(Results of an earlier search_email were removed"), tools[0].text)
        XCTAssertGreaterThan(tools[1].text.count, 500, "this turn's result is intact")
    }

    func testOtherToolsAreNeverShortened() async throws {
        let seen = Seen()
        let session = AgentSession(
            mode: .lolek, provider: Recorder(seen: seen),
            registry: ToolRegistry([BigResultTool(name: "search_email"), BigResultTool(name: "read_email")]),
            approvalHandler: AlwaysAllow(), planner: PlanEvery(tool: "read_email"), shortenOldResultsOf: ["search_email"]
        )
        _ = try await session.send("first")
        _ = try await session.send("second")
        let tools = try XCTUnwrap(seen.requests.last).filter { $0.role == .tool }
        XCTAssertTrue(tools.allSatisfy { $0.text.count > 500 })
    }
}

private struct AlwaysAllow: ApprovalHandler {
    func decide(_ request: ApprovalRequest) async -> ApprovalDecision { .allowOnce }
}
