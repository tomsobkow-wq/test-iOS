import XCTest
@testable import AgentCore

private func http(_ status: Int = 200) -> HTTPURLResponse {
    HTTPURLResponse(url: URL(string: "https://openrouter.ai/api/v1/chat/completions")!, statusCode: status, httpVersion: nil, headerFields: nil)!
}

private actor Captured {
    var requests: [URLRequest] = []
    func add(_ r: URLRequest) { requests.append(r) }
}

private func request(_ messages: [ChatMessage], language: ConversationLanguage = .en) -> ModelRequest {
    ModelRequest(
        mode: .bolek,
        systemPrompt: "You are Bolek.",
        messages: messages,
        tools: [ToolSpec(name: "get_weather", description: "Weather", parametersSchema: #"{"type":"object","properties":{"place":{"type":"string"}}}"#)],
        language: language
    )
}

final class OpenRouterProviderTests: XCTestCase {
    func testMissingKey() async {
        let provider = OpenRouterProvider(apiKey: { nil })
        do {
            _ = try await provider.respond(to: request([ChatMessage(role: .user, text: "hi")]))
            XCTFail("expected error")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("OPENROUTER_API_KEY"))
        }
    }

    func testRequestShape() async throws {
        let captured = Captured()
        let provider = OpenRouterProvider(apiKey: { "sk-or-test" }, transport: { req in
            await captured.add(req)
            return (Data(#"{"choices":[{"message":{"role":"assistant","content":"Hello"},"finish_reason":"stop"}]}"#.utf8), http())
        })
        let response = try await provider.respond(to: request([ChatMessage(role: .user, text: "hi")]))
        XCTAssertEqual(response.text, "Hello")

        let all = await captured.requests
        let sent = try XCTUnwrap(all.first)
        XCTAssertEqual(sent.url?.absoluteString, "https://openrouter.ai/api/v1/chat/completions")
        XCTAssertEqual(sent.value(forHTTPHeaderField: "Authorization"), "Bearer sk-or-test")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: sent.httpBody!) as? [String: Any])
        XCTAssertEqual(body["model"] as? String, "moonshotai/kimi-k3")
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.first?["role"] as? String, "system")
        XCTAssertEqual(messages.last?["content"] as? String, "hi")
        let tool = try XCTUnwrap((body["tools"] as? [[String: Any]])?.first)
        XCTAssertEqual(tool["type"] as? String, "function")
        XCTAssertEqual((tool["function"] as? [String: Any])?["name"] as? String, "get_weather")
        let provider_ = try XCTUnwrap(body["provider"] as? [String: Any])
        XCTAssertEqual(provider_["order"] as? [String], ["phala"])
        XCTAssertEqual(provider_["data_collection"] as? String, "deny")
        XCTAssertEqual((body["reasoning"] as? [String: Any])?["effort"] as? String, "medium")
    }

    func testToolCallsAndReasoningRoundTrip() throws {
        let reply = #"""
        {"choices":[{"message":{"role":"assistant","content":null,"reasoning":"The user wants weather.","reasoning_details":[{"type":"reasoning.text","text":"think"}],"tool_calls":[{"id":"call_1","type":"function","function":{"name":"get_weather","arguments":"{\"place\":\"Warszawa\"}"}}]},"finish_reason":"tool_calls"}]}
        """#
        let first = try OpenRouterProvider.response(from: Data(reply.utf8))
        XCTAssertEqual(first.text, "")
        XCTAssertEqual(first.toolCalls.first?.id, "call_1")
        XCTAssertEqual(first.toolCalls.first?.argumentsJSON, #"{"place":"Warszawa"}"#)
        XCTAssertTrue(first.providerState?.contains("reasoning_details") == true)

        let transcript = [
            ChatMessage(role: .user, text: "weather in Warsaw?"),
            ChatMessage(role: .assistant, text: first.text, toolCalls: first.toolCalls, providerState: first.providerState),
            ChatMessage(role: .tool, text: "Warszawa: 14°C", toolCallID: "call_1"),
        ]
        let messages = OpenRouterProvider.messages(systemPrompt: "sys", from: transcript)
        XCTAssertEqual(messages.count, 4)
        let assistant = messages[2]
        XCTAssertTrue(assistant["content"] is NSNull)
        XCTAssertEqual(assistant["reasoning"] as? String, "The user wants weather.")
        XCTAssertNotNil(assistant["reasoning_details"])
        let calls = try XCTUnwrap(assistant["tool_calls"] as? [[String: Any]])
        XCTAssertEqual(calls.first?["id"] as? String, "call_1")
        XCTAssertEqual(messages[3]["role"] as? String, "tool")
        XCTAssertEqual(messages[3]["tool_call_id"] as? String, "call_1")
    }

    func testToolErrorsAreMarked() {
        let transcript = [ChatMessage(role: .tool, text: "No contact found", toolCallID: "c", isError: true)]
        let messages = OpenRouterProvider.messages(systemPrompt: "s", from: transcript)
        XCTAssertEqual(messages.last?["content"] as? String, "Error: No contact found")
    }

    func testEmptyArgumentsBecomeEmptyObject() throws {
        let reply = #"{"choices":[{"message":{"role":"assistant","content":"","tool_calls":[{"id":"x","type":"function","function":{"name":"list_calendar_events","arguments":""}}]},"finish_reason":"tool_calls"}]}"#
        let response = try OpenRouterProvider.response(from: Data(reply.utf8))
        XCTAssertEqual(response.toolCalls.first?.argumentsJSON, "{}")
    }

    func testHTTPAndInBodyErrors() async {
        let unauthorized = OpenRouterProvider(apiKey: { "bad" }, transport: { _ in
            (Data(#"{"error":{"code":401,"message":"No auth credentials found"}}"#.utf8), http(401))
        })
        do { _ = try await unauthorized.respond(to: request([ChatMessage(role: .user, text: "hi")])); XCTFail() }
        catch { XCTAssertTrue(error.localizedDescription.contains("401")) }

        let outOfCredits = OpenRouterProvider(apiKey: { "k" }, transport: { _ in
            (Data(#"{"error":{"code":402,"message":"Insufficient credits"}}"#.utf8), http(402))
        })
        do { _ = try await outOfCredits.respond(to: request([ChatMessage(role: .user, text: "hi")])); XCTFail() }
        catch { XCTAssertTrue(error.localizedDescription.contains("credits")) }

        let inBody = OpenRouterProvider(apiKey: { "k" }, transport: { _ in
            (Data(#"{"error":{"code":502,"message":"Provider returned error"}}"#.utf8), http(200))
        })
        do { _ = try await inBody.respond(to: request([ChatMessage(role: .user, text: "hi")])); XCTFail() }
        catch { XCTAssertTrue(error.localizedDescription.contains("Provider returned error")) }
    }

    func testFullAgentLoopWithFakeKimi() async throws {
        let counter = Captured()
        let provider = OpenRouterProvider(apiKey: { "k" }, transport: { req in
            await counter.add(req)
            let n = await counter.requests.count
            if n == 1 {
                return (Data(#"{"choices":[{"message":{"role":"assistant","content":null,"tool_calls":[{"id":"call_7","type":"function","function":{"name":"add_note","arguments":"{\"text\":\"buy milk\"}"}}]},"finish_reason":"tool_calls"}]}"#.utf8), http())
            }
            return (Data(#"{"choices":[{"message":{"role":"assistant","content":"Saved."},"finish_reason":"stop"}]}"#.utf8), http())
        })
        let notes = NoteStore()
        struct Allow: ApprovalHandler { func decide(_ r: ApprovalRequest) async -> ApprovalDecision { .allowOnce } }
        let session = AgentSession(mode: .bolek, provider: provider, registry: ToolRegistry([AddNoteTool(store: notes)]), approvalHandler: Allow(), language: .en)
        let added = try await session.send("note buy milk")
        XCTAssertEqual(added.last?.text, "Saved.")
        let saved = await notes.notes
        XCTAssertEqual(saved, ["buy milk"])

        // The second request must carry the tool result back.
        let sent = await counter.requests
        let second = try JSONSerialization.jsonObject(with: sent[1].httpBody!) as! [String: Any]
        let roles = (second["messages"] as! [[String: Any]]).map { $0["role"] as! String }
        XCTAssertEqual(roles, ["system", "user", "assistant", "tool"])
    }
}
