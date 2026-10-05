import XCTest
@testable import AgentCore

private actor Offers: HandoffSink {
    var requests: [String] = []
    func offer(request: String) async { requests.append(request) }
}

final class HandoffTests: XCTestCase {
    func testInternetRequestsGoToTheHandoff() async {
        let planner = WebIntentPlanner()
        for text in ["Sprawdź mi ceny lotów do Lizbony na listopad", "Find the cheapest flights to Lisbon", "Wyszukaj w internecie recenzje tego telefonu",
                     "Znajdź hotel w Gdańsku", "Search the web for train tickets", "Jakie są dzisiaj wiadomości ze świata?", "Ile kosztuje bilet do Berlina?"] {
            let calls = await planner.plan(userText: text, language: .pl)
            XCTAssertEqual(calls.first?.name, "ask_bolek", text)
            XCTAssertTrue(calls.first?.argumentsJSON.contains("request") == true)
        }
    }

    func testEverydayRequestsAreLeftAlone() async {
        let planner = WebIntentPlanner()
        for text in ["Jaka jest pogoda w Krakowie?", "Ustaw budzik na 6:30", "Cześć!", "Napisz do Anny, że się spóźnię", "Ile wydałem na zakupy?", "What's on my calendar tomorrow?"] {
            let calls = await planner.plan(userText: text, language: .pl)
            XCTAssertTrue(calls.isEmpty, "\(text) → \(calls.map(\.name))")
        }
    }

    func testToolOffersButSendsNothing() async throws {
        let sink = Offers()
        let tool = OfferHandoffTool(sink: sink)
        XCTAssertEqual(tool.tier, .lolek, "Bolek never gets this tool")
        XCTAssertEqual(tool.risk, .read, "offering is harmless; only the user's tap sends")
        let result = try await tool.run(argumentsJSON: #"{"request":"cheap flights to Lisbon"}"#)
        let requests = await sink.requests
        XCTAssertEqual(requests, ["cheap flights to Lisbon"])
        XCTAssertTrue(result.contains(OfferHandoffTool.sentencePL) && result.contains(OfferHandoffTool.sentenceEN), "the model is given the exact sentences to copy")
        XCTAssertTrue(result.contains("Do not try to answer"))
    }

    func testCompositePlannerUsesTheFirstOpinion() async {
        struct Fixed: TurnPlanner { let name: String; func plan(userText: String, language: ConversationLanguage) async -> [ToolCall] { name.isEmpty ? [] : [ToolCall(name: name, argumentsJSON: "{}")] } }
        let composite = CompositeTurnPlanner([Fixed(name: ""), Fixed(name: "second"), Fixed(name: "third")])
        let calls = await composite.plan(userText: "x", language: .en)
        XCTAssertEqual(calls.map(\.name), ["second"])
    }

    func testSessionOffersTheButtonAndTheModelOnlyPhrasesIt() async throws {
        struct Phrase: ModelProvider {
            var profile: ModelProfile { .qwen35_4B }
            func respond(to request: ModelRequest) async throws -> ModelResponse {
                XCTAssertEqual(request.messages.last?.role, .tool, "the planned call ran before the model was asked")
                return ModelResponse(text: "Tego nie zrobię sam, bo potrzebuję internetu. Przycisk poniżej wyśle tylko tę prośbę do Bolka.")
            }
        }
        struct Allow: ApprovalHandler { func decide(_ r: ApprovalRequest) async -> ApprovalDecision { .allowOnce } }
        let sink = Offers()
        let session = AgentSession(mode: .lolek, provider: Phrase(), registry: ToolRegistry([OfferHandoffTool(sink: sink)]), approvalHandler: Allow(), language: .pl, planner: WebIntentPlanner())
        let added = try await session.send("Sprawdź ceny lotów do Lizbony")
        let requests = await sink.requests
        XCTAssertEqual(requests, ["Sprawdź ceny lotów do Lizbony"])
        XCTAssertTrue(added.last?.text.contains("Bolka") == true)
    }

    func testBolekDoesNotSeeTheHandoffTool() {
        let registry = ToolRegistry([OfferHandoffTool(sink: Offers())])
        XCTAssertTrue(registry.tools(for: .bolek).isEmpty)
        XCTAssertEqual(registry.tools(for: .lolek).map(\.name), ["ask_bolek"])
    }
}
