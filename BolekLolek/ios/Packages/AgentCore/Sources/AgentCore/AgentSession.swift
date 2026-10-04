import Foundation

/// Checks an answer before the user sees it. Small models get numbers wrong, so for answers built on tool
/// results (bank statements) a verifier can ask for one rewrite.
public protocol AnswerVerifier: Sendable {
    /// A correction to give the model, or nil when the answer is fine.
    func review(answer: String, toolNames: [String], toolResults: [String], userText: String, language: ConversationLanguage) -> String?
    /// Appended to an answer that still fails after the rewrite.
    func caution(language: ConversationLanguage) -> String
}

/// Decides, before the model is asked anything, which tools obviously answer the user's message. A 4B model
/// is unreliable at choosing and calling tools for questions about the user's data; code is not.
public protocol TurnPlanner: Sendable {
    /// Tool calls to run first, or an empty array to leave everything to the model.
    func plan(userText: String, language: ConversationLanguage) async -> [ToolCall]
}

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
    private let verifier: (any AnswerVerifier)?
    private let planner: (any TurnPlanner)?

    public init(
        mode: AgentMode,
        provider: any ModelProvider,
        registry: ToolRegistry,
        approvalHandler: any ApprovalHandler,
        language: ConversationLanguage = .fromLocale(),
        verifier: (any AnswerVerifier)? = nil,
        planner: (any TurnPlanner)? = nil
    ) {
        self.verifier = verifier
        self.planner = planner
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
            tools: await availableTools().map { $0.spec(in: language) },
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
        let specs = await availableTools().map { $0.spec(in: language) }

        // Run the obvious tool calls first, so the model only has to phrase the result.
        if let planner {
            let available = Set(specs.map(\.name))
            let planned = await planner.plan(userText: text, language: language).filter { available.contains($0.name) }
            if !planned.isEmpty {
                transcript.append(ChatMessage(role: .assistant, text: "", toolCalls: planned))
                for call in planned {
                    let result = await execute(call)
                    transcript.append(ChatMessage(role: .tool, text: result.content, toolCallID: call.id, isError: result.isError))
                }
            }
        }

        for _ in 0..<mode.maxSteps {
            let request = ModelRequest(
                mode: mode,
                systemPrompt: SystemPrompt.text(for: mode, language: language),
                messages: transcript,
                tools: specs,
                language: language
            )
            var response = try await provider.respond(to: request, onText: onText ?? { _ in })
            if response.toolCalls.isEmpty, let verifier {
                response = try await verified(response, with: verifier, request: request, turnStart: start, userText: text)
            }
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

    /// One rewrite at most. The correction is shown to the model but never stored in the conversation.
    private func verified(
        _ response: ModelResponse, with verifier: any AnswerVerifier, request: ModelRequest, turnStart: Int, userText: String
    ) async throws -> ModelResponse {
        let turn = transcript[turnStart...]
        let toolNames = turn.flatMap { $0.toolCalls.map(\.name) }
        let toolResults = turn.filter { $0.role == .tool }.map(\.text)
        guard !toolResults.isEmpty,
              let correction = verifier.review(answer: response.text, toolNames: toolNames, toolResults: toolResults, userText: userText, language: language)
        else { return response }

        var retry = request
        retry = ModelRequest(
            mode: request.mode, systemPrompt: request.systemPrompt,
            messages: request.messages + [ChatMessage(role: .assistant, text: response.text), ChatMessage(role: .user, text: correction)],
            tools: [], language: request.language, now: request.now, timeZone: request.timeZone
        )
        let second = try await provider.respond(to: retry)
        if verifier.review(answer: second.text, toolNames: toolNames, toolResults: toolResults, userText: userText, language: language) == nil { return second }
        return ModelResponse(text: second.text + "\n\n" + verifier.caution(language: language), toolCalls: [], providerState: second.providerState)
    }

    private func availableTools() async -> [any Tool] {
        var tools: [any Tool] = []
        for tool in registry.tools(for: mode) {
            if let conditional = tool as? any ConditionallyAvailable, !(await conditional.isAvailable()) { continue }
            tools.append(tool)
        }
        return tools
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
