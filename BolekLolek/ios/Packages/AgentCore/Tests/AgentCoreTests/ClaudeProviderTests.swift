import XCTest
@testable import AgentCore

private func http(_ status: Int = 200) -> HTTPURLResponse {
    HTTPURLResponse(url: URL(string: "https://api.anthropic.com/v1/messages")!, statusCode: status, httpVersion: nil, headerFields: nil)!
}

private actor Captured {
    var requests: [URLRequest] = []
    func add(_ r: URLRequest) { requests.append(r) }
}

private func request(messages: [ChatMessage], language: ConversationLanguage = .en) -> ModelRequest {
    ModelRequest(
        mode: .bolek,
        systemPrompt: "You are Bolek.",
        messages: messages,
        tools: [ToolSpec(name: "get_weather", description: "Weather", parametersSchema: #"{"type":"object","properties":{"place":{"type":"string"}}}"#)],
        language: language
    )
}

final class ClaudeProviderTests: XCTestCase {
    func testMissingKeyGivesFriendlyError() async {
        let provider = ClaudeProvider(apiKey: { nil })
        do {
            _ = try await provider.respond(to: request(messages: [ChatMessage(role: .user, text: "hi")]))
            XCTFail("expected error")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("ANTHROPIC_API_KEY"))
        }
    }

    func testRequestShape() async throws {
        let captured = Captured()
        let provider = ClaudeProvider(apiKey: { "sk-test" }, transport: { req in
            await captured.add(req)
            return (Data(#"{"content":[{"type":"text","text":"Hello"}],"stop_reason":"end_turn"}"#.utf8), http())
        })
        let response = try await provider.respond(to: request(messages: [ChatMessage(role: .user, text: "hi")]))
        XCTAssertEqual(response.text, "Hello")

        let allSent = await captured.requests
        let sent = try XCTUnwrap(allSent.first)
        XCTAssertEqual(sent.value(forHTTPHeaderField: "x-api-key"), "sk-test")
        XCTAssertEqual(sent.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: sent.httpBody!) as? [String: Any])
        XCTAssertEqual(body["model"] as? String, "claude-sonnet-5-5")
        XCTAssertEqual((body["thinking"] as? [String: Any])?["type"] as? String, "between_tools")
        XCTAssertNil(body["tool_choice"], "forced tool_choice is rejected on this model")
        XCTAssertNil(body["temperature"], "sampling params are rejected on this model")
        let tools = try XCTUnwrap(body["tools"] as? [[String: Any]])
        XCTAssertEqual(tools.first?["name"] as? String, "get_weather")
        XCTAssertNotNil(tools.first?["input_schema"] as? [String: Any])
        XCTAssertEqual(tools.last?["type"] as? String, "web_search_20260209")
    }

    func testToolUseRoundTripKeepsThinkingBlocks() async throws {
        // Turn 1: model thinks, then calls a tool.
        let content = #"[{"type":"thinking","thinking":"","signature":"sig123"},{"type":"tool_use","id":"toolu_1","name":"get_weather","input":{"place":"Warszawa"}}]"#
        let first = try ClaudeProvider.response(from: JSONSerialization.jsonObject(with: Data(content.utf8)) as! [[String: Any]])
        XCTAssertEqual(first.toolCalls.first?.id, "toolu_1")
        XCTAssertEqual(first.toolCalls.first?.argumentsJSON, #"{"place":"Warszawa"}"#)
        XCTAssertTrue(first.providerState?.contains("sig123") == true)

        // Turn 2: history goes back with the original blocks and a tool_result.
        let transcript = [
            ChatMessage(role: .user, text: "weather in Warsaw?"),
            ChatMessage(role: .assistant, text: first.text, toolCalls: first.toolCalls, providerState: first.providerState),
            ChatMessage(role: .tool, text: "Warszawa: 14°C", toolCallID: "toolu_1"),
        ]
        let messages = try ClaudeProvider.messages(from: transcript)
        XCTAssertEqual(messages.count, 3)
        let assistant = try XCTUnwrap(messages[1]["content"] as? [[String: Any]])
        XCTAssertEqual(assistant.first?["type"] as? String, "thinking", "thinking block must be echoed back unchanged")
        XCTAssertEqual(assistant.first?["signature"] as? String, "sig123")
        let result = try XCTUnwrap(messages[2]["content"] as? [[String: Any]])
        XCTAssertEqual(result.first?["type"] as? String, "tool_result")
        XCTAssertEqual(result.first?["tool_use_id"] as? String, "toolu_1")
    }

    func testParallelToolResultsShareOneUserMessage() throws {
        let calls = [ToolCall(id: "a", name: "t", argumentsJSON: "{}"), ToolCall(id: "b", name: "t", argumentsJSON: "{}")]
        let transcript = [
            ChatMessage(role: .user, text: "do both"),
            ChatMessage(role: .assistant, text: "", toolCalls: calls),
            ChatMessage(role: .tool, text: "one", toolCallID: "a"),
            ChatMessage(role: .tool, text: "bad", toolCallID: "b", isError: true),
        ]
        let messages = try ClaudeProvider.messages(from: transcript)
        XCTAssertEqual(messages.count, 3)
        let results = try XCTUnwrap(messages[2]["content"] as? [[String: Any]])
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[1]["is_error"] as? Bool, true)
    }

    func testPauseTurnContinuesAndKeepsSearchBlocks() async throws {
        let counter = Captured()
        let provider = ClaudeProvider(apiKey: { "k" }, transport: { req in
            await counter.add(req)
            let n = await counter.requests.count
            if n == 1 {
                return (Data(#"{"content":[{"type":"server_tool_use","id":"srvtoolu_1","name":"web_search","input":{"query":"WAW LIS fares"}}],"stop_reason":"pause_turn"}"#.utf8), http())
            }
            return (Data(#"{"content":[{"type":"text","text":"Fares start around 420 zł."}],"stop_reason":"end_turn"}"#.utf8), http())
        })
        let response = try await provider.respond(to: request(messages: [ChatMessage(role: .user, text: "cheap flights Warsaw to Lisbon?")]))
        XCTAssertEqual(response.text, "Fares start around 420 zł.")
        XCTAssertTrue(response.providerState?.contains("srvtoolu_1") == true, "earlier segment must stay in the stored turn")
        let count = await counter.requests.count
        XCTAssertEqual(count, 2)
        let sentRequests = await counter.requests
        let second = try JSONSerialization.jsonObject(with: sentRequests[1].httpBody!) as! [String: Any]
        let msgs = second["messages"] as! [[String: Any]]
        XCTAssertEqual(msgs.last?["role"] as? String, "assistant")
    }

    func testHTTPErrorsAreReadable() async {
        let provider = ClaudeProvider(apiKey: { "bad" }, transport: { _ in
            (Data(#"{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}"#.utf8), http(401))
        })
        do {
            _ = try await provider.respond(to: request(messages: [ChatMessage(role: .user, text: "hi")]))
            XCTFail("expected error")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("401"))
            XCTAssertTrue(error.localizedDescription.contains("invalid x-api-key"))
        }
    }

    func testRefusalIsLocalized() async throws {
        let provider = ClaudeProvider(apiKey: { "k" }, transport: { _ in
            (Data(#"{"content":[],"stop_reason":"refusal"}"#.utf8), http())
        })
        let pl = try await provider.respond(to: request(messages: [ChatMessage(role: .user, text: "x")], language: .pl))
        XCTAssertEqual(pl.text, "Nie mogę w tym pomóc.")
    }

    func testFullAgentLoopWithFakeClaude() async throws {
        let counter = Captured()
        let provider = ClaudeProvider(apiKey: { "k" }, transport: { req in
            await counter.add(req)
            let n = await counter.requests.count
            if n == 1 {
                return (Data(#"{"content":[{"type":"tool_use","id":"toolu_9","name":"add_note","input":{"text":"buy milk"}}],"stop_reason":"tool_use"}"#.utf8), http())
            }
            return (Data(#"{"content":[{"type":"text","text":"Saved. Anything else?"}],"stop_reason":"end_turn"}"#.utf8), http())
        })
        let notes = NoteStore()
        struct Allow: ApprovalHandler { func decide(_ r: ApprovalRequest) async -> ApprovalDecision { .allowOnce } }
        let session = AgentSession(mode: .bolek, provider: provider, registry: ToolRegistry([AddNoteTool(store: notes)]), approvalHandler: Allow(), language: .en)
        let added = try await session.send("note buy milk")
        XCTAssertEqual(added.last?.text, "Saved. Anything else?")
        let saved = await notes.notes
        XCTAssertEqual(saved, ["buy milk"])
    }
}
