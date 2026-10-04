import AgentCore
import Foundation

/// How a model wants its conversation laid out. Both families use ChatML framing;
/// they differ in tool handling. Verified against the chat templates embedded in the
/// GGUF files (see Tools/gen_golden.py and the golden tests).
public enum PromptStyle: String, Sendable {
    /// Qwen3.5: tools in the system prompt as JSON, calls as
    /// `<tool_call><function=name><parameter=k>v</parameter></function></tool_call>`,
    /// results as `<tool_response>` inside a user turn, thinking switched off.
    case qwen35
    /// Bielik v3: plain ChatML with a leading `<s>` and no tool support in its template.
    /// Tools are described in the system prompt and called with JSON in `<tool_call>` tags.
    case plainChatML
}

public struct PromptRenderer: Sendable {
    public let style: PromptStyle

    public init(style: PromptStyle) {
        self.style = style
    }

    /// The full prompt, ending where the assistant should start writing.
    public func render(system: String, messages: [ChatMessage], tools: [ToolSpec]) -> String {
        switch style {
        case .qwen35: renderQwen(system: system, messages: messages, tools: tools)
        case .plainChatML: renderPlain(system: system, messages: messages, tools: tools)
        }
    }

    // MARK: - Qwen3.5

    private static let qwenInstructions = """


    If you choose to call a function ONLY reply in the following format with NO suffix:

    <tool_call>
    <function=example_function_name>
    <parameter=example_parameter_1>
    value_1
    </parameter>
    <parameter=example_parameter_2>
    This is the value for the second parameter
    that can span
    multiple lines
    </parameter>
    </function>
    </tool_call>

    <IMPORTANT>
    Reminder:
    - Function calls MUST follow the specified format: an inner <function=...></function> block must be nested within <tool_call></tool_call> XML tags
    - Required parameters MUST be specified
    - You may provide optional reasoning for your function call in natural language BEFORE the function call, but NOT after
    - If there is no function call available, answer the question like normal with your current knowledge and do not tell the user about function calls
    </IMPORTANT>
    """

    private func renderQwen(system: String, messages: [ChatMessage], tools: [ToolSpec]) -> String {
        let conversation = messages.filter { $0.role != .system }
        let systemContent = system.trimmingCharacters(in: .whitespacesAndNewlines)
        var out = ""

        if !tools.isEmpty {
            out += "<|im_start|>system\n# Tools\n\nYou have access to the following functions:\n\n<tools>"
            for tool in tools { out += "\n" + Self.toolJSON(tool) }
            out += "\n</tools>" + Self.qwenInstructions
            if !systemContent.isEmpty { out += "\n\n" + systemContent }
            out += "<|im_end|>\n"
        } else if !systemContent.isEmpty {
            out += "<|im_start|>system\n" + systemContent + "<|im_end|>\n"
        }

        // Assistant turns after the last user message are part of the current tool loop.
        let lastQueryIndex = conversation.lastIndex { $0.role == .user } ?? (conversation.count - 1)

        for (index, message) in conversation.enumerated() {
            let content = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
            switch message.role {
            case .system:
                continue
            case .user:
                out += "<|im_start|>user\n" + content + "<|im_end|>\n"
            case .assistant:
                if index > lastQueryIndex {
                    out += "<|im_start|>assistant\n<think>\n\n</think>\n\n" + content
                } else {
                    out += "<|im_start|>assistant\n" + content
                }
                for (callIndex, call) in message.toolCalls.enumerated() {
                    if callIndex == 0 {
                        out += content.isEmpty ? "<tool_call>\n<function=\(call.name)>\n" : "\n\n<tool_call>\n<function=\(call.name)>\n"
                    } else {
                        out += "\n<tool_call>\n<function=\(call.name)>\n"
                    }
                    if case let .object(pairs)? = JSONValue.parse(call.argumentsJSON) {
                        for pair in pairs {
                            out += "<parameter=\(pair.key)>\n\(pair.value.pythonStr())\n</parameter>\n"
                        }
                    }
                    out += "</function>\n</tool_call>"
                }
                out += "<|im_end|>\n"
            case .tool:
                let previousIsTool = index > 0 && conversation[index - 1].role == .tool
                if !previousIsTool { out += "<|im_start|>user" }
                out += "\n<tool_response>\n" + content + "\n</tool_response>"
                let nextIsTool = index + 1 < conversation.count && conversation[index + 1].role == .tool
                if !nextIsTool { out += "<|im_end|>\n" }
            }
        }
        return out + "<|im_start|>assistant\n<think>\n\n</think>\n\n"
    }

    // MARK: - Bielik (plain ChatML)

    private func renderPlain(system: String, messages: [ChatMessage], tools: [ToolSpec]) -> String {
        var systemText = system
        if !tools.isEmpty {
            systemText += "\n\n# Tools\nYou can call these functions when needed:\n<tools>"
            for tool in tools { systemText += "\n" + Self.toolJSON(tool) }
            systemText += """

            </tools>
            To call a function, reply with ONLY:
            <tool_call>
            {"name": "function_name", "arguments": {"parameter": "value"}}
            </tool_call>
            You may write one short sentence before the call, never after it. \
            Wait for the <tool_response> before you answer. If no function is needed, just answer normally.
            """
        }

        var out = "<s><|im_start|>system\n" + systemText + "<|im_end|>\n"
        let conversation = messages.filter { $0.role != .system }
        for (index, message) in conversation.enumerated() {
            switch message.role {
            case .system:
                continue
            case .user:
                out += "<|im_start|>user\n" + message.text + "<|im_end|>\n"
            case .assistant:
                var text = message.text
                for call in message.toolCalls {
                    let arguments = JSONValue.parse(call.argumentsJSON)?.pythonDump() ?? "{}"
                    let json = "{\"name\": " + JSONValue.string(call.name).pythonDump() + ", \"arguments\": " + arguments + "}"
                    text += (text.isEmpty ? "" : "\n") + "<tool_call>\n" + json + "\n</tool_call>"
                }
                out += "<|im_start|>assistant\n" + text + "<|im_end|>\n"
            case .tool:
                let previousIsTool = index > 0 && conversation[index - 1].role == .tool
                if !previousIsTool { out += "<|im_start|>user" }
                out += "\n<tool_response>\n" + message.text + "\n</tool_response>"
                let nextIsTool = index + 1 < conversation.count && conversation[index + 1].role == .tool
                if !nextIsTool { out += "<|im_end|>\n" }
            }
        }
        return out + "<|im_start|>assistant\n"
    }

    // MARK: - Shared

    /// `{"type": "function", "function": {name, description, parameters}}` in Python's JSON style.
    static func toolJSON(_ tool: ToolSpec) -> String {
        let parameters = JSONValue.parse(tool.parametersSchema) ?? .object([])
        return JSONValue.object([
            ("type", .string("function")),
            ("function", .object([
                ("name", .string(tool.name)),
                ("description", .string(tool.description)),
                ("parameters", parameters),
            ])),
        ]).pythonDump()
    }
}
