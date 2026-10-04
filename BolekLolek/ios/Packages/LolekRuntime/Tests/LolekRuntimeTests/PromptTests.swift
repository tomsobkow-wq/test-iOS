import AgentCore
import XCTest
@testable import LolekRuntime

/// Fixtures come from Tools/gen_golden.py, which renders the REAL chat templates
/// embedded in the GGUF files with Jinja. Our Swift renderer must match byte for byte.
final class GoldenPromptTests: XCTestCase {
    private func cases(_ file: String) throws -> [JSONValue] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: file, withExtension: "json", subdirectory: "Fixtures"))
        let text = String(decoding: try Data(contentsOf: url), as: UTF8.self)
        guard case let .array(items)? = JSONValue.parse(text) else { throw XCTSkip("bad fixture") }
        return items
    }

    private func check(_ file: String, style: PromptStyle) throws {
        for golden in try cases(file) {
            let name = golden["name"]?.stringValue ?? "?"
            var system = ""
            var messages: [ChatMessage] = []
            guard case let .array(rawMessages)? = golden["messages"] else { return XCTFail("no messages") }
            for raw in rawMessages {
                let content = raw["content"]?.stringValue ?? ""
                switch raw["role"]?.stringValue {
                case "system": system = content
                case "user": messages.append(ChatMessage(role: .user, text: content))
                case "tool": messages.append(ChatMessage(role: .tool, text: content, toolCallID: "x"))
                default:
                    var calls: [ToolCall] = []
                    if case let .array(rawCalls)? = raw["tool_calls"] {
                        for call in rawCalls {
                            let function = try XCTUnwrap(call["function"])
                            calls.append(ToolCall(name: function["name"]?.stringValue ?? "", argumentsJSON: function["arguments"]?.pythonDump() ?? "{}"))
                        }
                    }
                    messages.append(ChatMessage(role: .assistant, text: content, toolCalls: calls))
                }
            }
            var tools: [ToolSpec] = []
            if case let .array(rawTools)? = golden["tools"] {
                for raw in rawTools {
                    let function = try XCTUnwrap(raw["function"])
                    tools.append(ToolSpec(
                        name: function["name"]?.stringValue ?? "",
                        description: function["description"]?.stringValue ?? "",
                        parametersSchema: function["parameters"]?.pythonDump() ?? "{}"
                    ))
                }
            }
            let rendered = PromptRenderer(style: style).render(system: system, messages: messages, tools: tools)
            XCTAssertEqual(rendered, golden["expected"]?.stringValue, "\(file)/\(name)")
        }
    }

    func testQwen35MatchesRealTemplate() throws { try check("qwen35.golden", style: .qwen35) }
    func testBielikMatchesRealTemplate() throws { try check("bielik.golden", style: .plainChatML) }
}

final class ToolCallParserTests: XCTestCase {
    private let tools = [
        ToolSpec(name: "set_timer", description: "t", parametersSchema: #"{"type":"object","properties":{"seconds":{"type":"integer"},"label":{"type":"string"},"loud":{"type":"boolean"}}}"#),
        ToolSpec(name: "get_weather", description: "w", parametersSchema: #"{"type":"object","properties":{"place":{"type":"string"}}}"#),
    ]

    func testQwenXMLCallWithTypedParameters() {
        let raw = "Sure, starting it.\n\n<tool_call>\n<function=set_timer>\n<parameter=seconds>\n300\n</parameter>\n<parameter=label>\nherbata\n</parameter>\n<parameter=loud>\ntrue\n</parameter>\n</function>\n</tool_call>"
        let parsed = ToolCallParser.parse(raw, tools: tools)
        XCTAssertEqual(parsed.text, "Sure, starting it.")
        XCTAssertEqual(parsed.calls.count, 1)
        XCTAssertEqual(parsed.calls[0].name, "set_timer")
        XCTAssertEqual(parsed.calls[0].argumentsJSON, #"{"seconds": 300, "label": "herbata", "loud": true}"#)
    }

    func testQwenCallWithoutArguments() {
        let parsed = ToolCallParser.parse("<tool_call>\n<function=get_weather>\n</function>\n</tool_call>", tools: tools)
        XCTAssertEqual(parsed.calls.first?.name, "get_weather")
        XCTAssertEqual(parsed.calls.first?.argumentsJSON, "{}")
    }

    func testParallelCallsAndUnclosedTag() {
        let raw = "<tool_call>\n<function=get_weather>\n<parameter=place>\nKraków\n</parameter>\n</function>\n</tool_call>\n<tool_call>\n<function=set_timer>\n<parameter=seconds>\n60\n</parameter>\n</function>"
        let parsed = ToolCallParser.parse(raw, tools: tools)
        XCTAssertEqual(parsed.calls.map(\.name), ["get_weather", "set_timer"])
        XCTAssertEqual(parsed.calls[0].argumentsJSON, #"{"place": "Kraków"}"#)
    }

    func testHermesJSONCall() {
        let raw = "Jasne.\n<tool_call>\n{\"name\": \"get_weather\", \"arguments\": {\"place\": \"Gdańsk\"}}\n</tool_call>"
        let parsed = ToolCallParser.parse(raw, tools: tools)
        XCTAssertEqual(parsed.text, "Jasne.")
        XCTAssertEqual(parsed.calls.first?.argumentsJSON, #"{"place": "Gdańsk"}"#)
    }

    func testThinkingIsDropped() {
        let parsed = ToolCallParser.parse("<think>\nhmm\n</think>\n\nCześć!", tools: tools)
        XCTAssertEqual(parsed.text, "Cześć!")
        XCTAssertTrue(parsed.calls.isEmpty)
    }

    func testPlainAnswerHasNoCalls() {
        let parsed = ToolCallParser.parse("  Warszawa.  ", tools: tools)
        XCTAssertEqual(parsed, .init(text: "Warszawa.", calls: []))
    }

    func testGarbageCallIsIgnored() {
        let parsed = ToolCallParser.parse("<tool_call>\nnot json at all\n</tool_call>", tools: tools)
        XCTAssertTrue(parsed.calls.isEmpty)
    }

    func testStreamingNeverShowsToolTags() {
        XCTAssertEqual(ToolCallParser.visibleText(streaming: "Sure, <tool_ca"), "Sure,")
        XCTAssertEqual(ToolCallParser.visibleText(streaming: "Sure, <tool_call>\n<function=x>"), "Sure,")
        XCTAssertEqual(ToolCallParser.visibleText(streaming: "Wynik: 3 < 5"), "Wynik: 3 < 5")
        XCTAssertEqual(ToolCallParser.visibleText(streaming: "<think>\nplanning"), "")
        XCTAssertEqual(ToolCallParser.visibleText(streaming: "<think>\nx\n</think>\n\nHej"), "Hej")
    }
}
