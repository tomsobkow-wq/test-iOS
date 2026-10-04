import AgentCore
import Foundation

/// Turns what a small model wrote into plain text plus structured tool calls.
/// Understands Qwen3.5's XML calls and the JSON calls we ask Bielik for.
public enum ToolCallParser {
    public struct Parsed: Equatable, Sendable {
        public let text: String
        public let calls: [ToolCall]
    }

    public static func parse(_ raw: String, tools: [ToolSpec]) -> Parsed {
        let withoutThinking = stripThinking(raw)
        guard let firstCall = withoutThinking.range(of: "<tool_call>") else {
            return Parsed(text: withoutThinking.trimmingCharacters(in: .whitespacesAndNewlines), calls: [])
        }
        let before = String(withoutThinking[..<firstCall.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)

        var calls: [ToolCall] = []
        var rest = withoutThinking[firstCall.lowerBound...]
        while let open = rest.range(of: "<tool_call>") {
            let afterOpen = rest[open.upperBound...]
            let block: Substring
            if let close = afterOpen.range(of: "</tool_call>") {
                block = afterOpen[..<close.lowerBound]
                rest = afterOpen[close.upperBound...]
            } else {
                block = afterOpen // The model stopped right after the call; accept it.
                rest = ""
            }
            if let call = parseBlock(String(block), tools: tools) { calls.append(call) }
        }
        return Parsed(text: before, calls: calls)
    }

    /// The part of a partial answer that is safe to show while it is still streaming:
    /// no thinking, and nothing from the first `<tool_call` on (including a half-typed tag).
    public static func visibleText(streaming raw: String) -> String {
        var text = raw
        if let thinkStart = text.range(of: "<think>") {
            if let thinkEnd = text.range(of: "</think>", range: thinkStart.upperBound..<text.endIndex) {
                text.removeSubrange(thinkStart.lowerBound..<thinkEnd.upperBound)
            } else {
                text = String(text[..<thinkStart.lowerBound])
            }
        } else if let strayClose = text.range(of: "</think>") {
            text = String(text[strayClose.upperBound...])
        }
        let tag = "<tool_call>"
        if let start = text.range(of: "<tool_call") {
            text = String(text[..<start.lowerBound])
        } else {
            // Hold back a trailing partial "<tool_ca…" so it never flashes on screen.
            for length in stride(from: min(tag.count - 1, text.count), through: 1, by: -1) {
                if tag.hasPrefix(String(text.suffix(length))) {
                    text = String(text.dropLast(length))
                    break
                }
            }
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Internals

    static func stripThinking(_ text: String) -> String {
        var out = text
        while let start = out.range(of: "<think>") {
            if let end = out.range(of: "</think>", range: start.upperBound..<out.endIndex) {
                out.removeSubrange(start.lowerBound..<end.upperBound)
            } else {
                out = String(out[..<start.lowerBound])
            }
        }
        if let strayClose = out.range(of: "</think>") { out = String(out[strayClose.upperBound...]) }
        return out
    }

    private static func parseBlock(_ block: String, tools: [ToolSpec]) -> ToolCall? {
        if let functionStart = block.range(of: "<function=") {
            return parseXML(block, from: functionStart, tools: tools)
        }
        return parseJSON(block)
    }

    private static func parseXML(_ block: String, from functionStart: Range<String.Index>, tools: [ToolSpec]) -> ToolCall? {
        guard let nameEnd = block.range(of: ">", range: functionStart.upperBound..<block.endIndex) else { return nil }
        let name = String(block[functionStart.upperBound..<nameEnd.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let schema = tools.first { $0.name == name }.flatMap { JSONValue.parse($0.parametersSchema) }

        var pairs: [(key: String, value: JSONValue)] = []
        var cursor = nameEnd.upperBound
        while let open = block.range(of: "<parameter=", range: cursor..<block.endIndex),
              let openEnd = block.range(of: ">", range: open.upperBound..<block.endIndex) {
            let key = String(block[open.upperBound..<openEnd.lowerBound])
            let valueEnd = block.range(of: "</parameter>", range: openEnd.upperBound..<block.endIndex)
            var value = String(block[openEnd.upperBound..<(valueEnd?.lowerBound ?? block.endIndex)])
            if value.hasPrefix("\n") { value.removeFirst() }
            if value.hasSuffix("\n") { value.removeLast() }
            let type = schema?["properties"]?[key]?["type"]?.stringValue
            pairs.append((key, coerce(value, type: type)))
            cursor = valueEnd?.upperBound ?? block.endIndex
        }
        return ToolCall(name: name, argumentsJSON: JSONValue.object(pairs).pythonDump())
    }

    private static func parseJSON(_ block: String) -> ToolCall? {
        let trimmed = block.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let object = JSONValue.parse(trimmed), let name = object["name"]?.stringValue else { return nil }
        var arguments = object["arguments"] ?? object["parameters"] ?? .object([])
        if case let .string(text) = arguments, let parsed = JSONValue.parse(text) { arguments = parsed }
        guard case .object = arguments else { return nil }
        return ToolCall(name: name, argumentsJSON: arguments.pythonDump())
    }

    /// XML parameters are all text; the schema says what they really are.
    private static func coerce(_ text: String, type: String?) -> JSONValue {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch type {
        case "integer":
            if let int = Int(trimmed) { return .int(int) }
            if let double = Double(trimmed), double == double.rounded() { return .int(Int(double)) }
        case "number":
            if let int = Int(trimmed) { return .int(int) }
            if let double = Double(trimmed) { return .double(double) }
        case "boolean":
            if ["true", "yes", "1"].contains(trimmed.lowercased()) { return .bool(true) }
            if ["false", "no", "0"].contains(trimmed.lowercased()) { return .bool(false) }
        case "array", "object":
            if let parsed = JSONValue.parse(trimmed) { return parsed }
        default:
            break
        }
        return .string(text)
    }
}
