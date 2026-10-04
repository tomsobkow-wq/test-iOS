import Foundation

/// The shared agent loop. One session per mode; the mode decides which tools
/// the model sees and how many steps it may take.
public actor AgentSession {
    public nonisolated let mode: AgentMode
    public nonisolated let activity = ActivityLog()
    public private(set) var transcript: [ChatMessage] = []
    public private(set) var language: ConversationLanguage

    private let provider: any ModelProvider
    private let registry: ToolRegistry
    private let approvalHandler: any ApprovalHandler
    private let policy = ApprovalPolicy()

    public init(
        mode: AgentMode,
        provider: any ModelProvider,
        registry: ToolRegistry,
        approvalHandler: any ApprovalHandler,
        language: ConversationLanguage = .fromLocale()
    ) {
        self.mode = mode
        self.provider = provider
        self.registry = registry
        self.approvalHandler = approvalHandler
        self.language = language
    }

    /// Reads the fixed prompt (instructions and tool list) ahead of time so the first message is quick.
    public func warmUp() async {
        let request = ModelRequest(
            mode: mode,
            systemPrompt: SystemPrompt.text(for: mode, language: language),
            messages: [],
            tools: registry.tools(for: mode).map { $0.spec(in: language) },
            language: language
        )
        await provider.warmUp(for: request)
    }

    /// Runs one user turn to completion. Returns the messages added in this turn.
    @discardableResult
    public func send(_ text: String, onText: (@Sendable (String) -> Void)? = nil) async throws -> [ChatMessage] {
        let start = transcript.count
        language = ConversationLanguage.detect(text, fallback: language)
        transcript.append(ChatMessage(role: .user, text: text))
        let specs = registry.tools(for: mode).map { $0.spec(in: language) }

        for _ in 0..<mode.maxSteps {
            let request = ModelRequest(
                mode: mode,
                systemPrompt: SystemPrompt.text(for: mode, language: language),
                messages: transcript,
                tools: specs,
                language: language
            )
            let response = try await provider.respond(to: request, onText: onText ?? { _ in })
            transcript.append(ChatMessage(role: .assistant, text: response.text, toolCalls: response.toolCalls, providerState: response.providerState))
            if response.toolCalls.isEmpty {
                return Array(transcript[start...])
            }
            for call in response.toolCalls {
                let result = await execute(call)
                transcript.append(ChatMessage(
                    role: .tool,
                    text: result.content,
                    toolCallID: call.id,
                    isError: result.isError
                ))
            }
        }

        transcript.append(ChatMessage(
            role: .assistant,
            text: SystemPrompt.stepLimitNotice(mode.maxSteps, language: language)
        ))
        return Array(transcript[start...])
    }

    private func execute(_ call: ToolCall) async -> ToolResult {
        guard let tool = registry.tool(named: call.name, for: mode) else {
            await activity.record(ActivityEntry(mode: mode, toolName: call.name, outcome: .rejected))
            return ToolResult(callID: call.id, content: "Unknown tool: \(call.name)", isError: true)
        }

        if tool.risk.needsApproval {
            let preapproved = await policy.isAlwaysAllowed(tool.name, mode: mode)
            if !preapproved {
                let request = ApprovalRequest(
                    id: call.id,
                    mode: mode,
                    toolName: tool.name,
                    summary: tool.description.text(for: language),
                    argumentsJSON: call.argumentsJSON,
                    risk: tool.risk
                )
                switch await approvalHandler.decide(request) {
                case .deny:
                    await activity.record(ActivityEntry(mode: mode, toolName: tool.name, outcome: .denied))
                    return ToolResult(callID: call.id, content: "The user denied this action.", isError: true)
                case .alwaysAllow:
                    await policy.allowAlways(tool.name, mode: mode)
                case .allowOnce:
                    break
                }
            }
        }

        do {
            let output = try await tool.run(argumentsJSON: call.argumentsJSON)
            await activity.record(ActivityEntry(mode: mode, toolName: tool.name, outcome: .succeeded))
            return ToolResult(callID: call.id, content: output)
        } catch {
            await activity.record(ActivityEntry(mode: mode, toolName: tool.name, outcome: .failed))
            return ToolResult(callID: call.id, content: "Tool failed: \(error.localizedDescription)", isError: true)
        }
    }
}
