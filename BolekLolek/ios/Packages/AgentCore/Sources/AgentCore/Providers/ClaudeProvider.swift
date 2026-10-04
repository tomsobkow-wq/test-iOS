import Foundation

public enum ClaudeError: LocalizedError, Sendable {
    case missingKey
    case http(status: Int, message: String)
    case malformedResponse
    case tooManyPauses

    public var errorDescription: String? {
        switch self {
        case .missingKey:
            "Bolek needs an Anthropic API key (developer build). Set ANTHROPIC_API_KEY when launching the app once; it is then kept in the Keychain."
        case let .http(status, message):
            switch status {
            case 401: "The API key was rejected (401). \(message)"
            case 429: "Claude is rate limiting this key (429). Try again in a moment."
            case 529: "Claude is overloaded right now (529). Try again in a moment."
            default: "Claude returned an error (\(status)): \(message)"
            }
        case .malformedResponse:
            "Claude sent a reply the app could not read."
        case .tooManyPauses:
            "The web search took too many steps. Try a narrower question."
        }
    }
}

/// Bolek's brain while Kimi K3 is not hosted yet: Claude through the Messages API
/// (plain HTTP; there is no Swift SDK). The agent loop stays in `AgentSession`, so
/// switching to Kimi later means writing another `ModelProvider`, not touching the app.
///
/// For a prototype the key lives on the phone. A shipped Bolek must call the backend
/// instead, so the key never reaches a user's device.
public struct ClaudeProvider: ModelProvider {
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    public let profile: ModelProfile
    private let apiKey: @Sendable () -> String?
    private let enableWebSearch: Bool
    private let transport: Transport

    public init(
        profile: ModelProfile = .claudeSonnet55,
        enableWebSearch: Bool = true,
        apiKey: @escaping @Sendable () -> String?,
        transport: Transport? = nil
    ) {
        self.profile = profile
        self.enableWebSearch = enableWebSearch
        self.apiKey = apiKey
        self.transport = transport ?? { request in
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw ClaudeError.malformedResponse }
            return (data, http)
        }
    }

    public func respond(to request: ModelRequest) async throws -> ModelResponse {
        guard let key = apiKey(), !key.isEmpty else { throw ClaudeError.missingKey }
        let base = try Self.messages(from: request.messages)

        // Server-side web search can pause a long turn; resend until it finishes.
        var accumulated: [[String: Any]] = []
        for _ in 0..<4 {
            var messages = base
            if !accumulated.isEmpty { messages.append(["role": "assistant", "content": accumulated]) }
            let body = Self.body(model: profile.id, maxTokens: profile.maxOutputTokens, request: request, messages: messages, webSearch: enableWebSearch)

            var http = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
            http.httpMethod = "POST"
            http.timeoutInterval = 120
            http.setValue(key, forHTTPHeaderField: "x-api-key")
            http.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            http.setValue("application/json", forHTTPHeaderField: "content-type")
            http.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, response) = try await transport(http)
            guard (200..<300).contains(response.statusCode) else {
                throw ClaudeError.http(status: response.statusCode, message: Self.errorMessage(in: data))
            }
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let content = object["content"] as? [[String: Any]]
            else { throw ClaudeError.malformedResponse }

            accumulated += content
            let stopReason = object["stop_reason"] as? String
            if stopReason == "pause_turn" { continue }
            if stopReason == "refusal" {
                let text = request.language == .pl
                    ? "Nie mogę w tym pomóc."
                    : "I can't help with that."
                return ModelResponse(text: text)
            }
            return try Self.response(from: accumulated)
        }
        throw ClaudeError.tooManyPauses
    }

    // MARK: - Request building (pure, tested)

    static func body(model: String, maxTokens: Int, request: ModelRequest, messages: [[String: Any]], webSearch: Bool) -> [String: Any] {
        var tools: [[String: Any]] = request.tools.map { spec in
            [
                "name": spec.name,
                "description": spec.description,
                "input_schema": (try? JSONSerialization.jsonObject(with: Data(spec.parametersSchema.utf8))) ?? ["type": "object"],
            ]
        }
        if webSearch {
            tools.append(["type": "web_search_20260209", "name": "web_search", "max_uses": 5])
        }
        var body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "system": request.systemPrompt,
            // Cheapest thinking mode on Sonnet 5.5. Thinking blocks it returns are echoed back via providerState.
            "thinking": ["type": "between_tools"],
            "messages": messages,
        ]
        if !tools.isEmpty { body["tools"] = tools }
        return body
    }

    /// Maps the transcript to API messages. Consecutive tool results become one user message.
    static func messages(from transcript: [ChatMessage]) throws -> [[String: Any]] {
        var out: [[String: Any]] = []
        var pendingResults: [[String: Any]] = []

        func flush() {
            if !pendingResults.isEmpty {
                out.append(["role": "user", "content": pendingResults])
                pendingResults = []
            }
        }

        for message in transcript {
            switch message.role {
            case .system:
                continue
            case .user:
                flush()
                out.append(["role": "user", "content": message.text])
            case .tool:
                var block: [String: Any] = [
                    "type": "tool_result",
                    "tool_use_id": message.toolCallID ?? "",
                    "content": message.text,
                ]
                if message.isError { block["is_error"] = true }
                pendingResults.append(block)
            case .assistant:
                flush()
                if let state = message.providerState,
                   let blocks = try JSONSerialization.jsonObject(with: Data(state.utf8)) as? [[String: Any]] {
                    out.append(["role": "assistant", "content": blocks])
                    continue
                }
                var blocks: [[String: Any]] = []
                if !message.text.isEmpty { blocks.append(["type": "text", "text": message.text]) }
                for call in message.toolCalls {
                    let input = (try? JSONSerialization.jsonObject(with: Data(call.argumentsJSON.utf8))) ?? [String: Any]()
                    blocks.append(["type": "tool_use", "id": call.id, "name": call.name, "input": input])
                }
                if !blocks.isEmpty { out.append(["role": "assistant", "content": blocks]) }
            }
        }
        flush()
        return out
    }

    // MARK: - Response parsing (pure, tested)

    static func response(from content: [[String: Any]]) throws -> ModelResponse {
        var text = ""
        var calls: [ToolCall] = []
        for block in content {
            switch block["type"] as? String {
            case "text":
                text += block["text"] as? String ?? ""
            case "tool_use":
                guard let id = block["id"] as? String, let name = block["name"] as? String else { continue }
                let input = block["input"] ?? [String: Any]()
                let data = try JSONSerialization.data(withJSONObject: input, options: [.sortedKeys])
                calls.append(ToolCall(id: id, name: name, argumentsJSON: String(decoding: data, as: UTF8.self)))
            default:
                continue // thinking, server_tool_use, web_search_tool_result: kept in providerState only
            }
        }
        let state = try JSONSerialization.data(withJSONObject: content)
        return ModelResponse(
            text: text.trimmingCharacters(in: .whitespacesAndNewlines),
            toolCalls: calls,
            providerState: String(decoding: state, as: UTF8.self)
        )
    }

    static func errorMessage(in data: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = object["error"] as? [String: Any],
              let message = error["message"] as? String
        else { return String(decoding: data.prefix(200), as: UTF8.self) }
        return message
    }
}
