import Foundation

public enum OpenRouterError: LocalizedError, Sendable {
    case missingKey
    case http(status: Int, message: String)
    case malformedResponse

    public var errorDescription: String? {
        switch self {
        case .missingKey:
            "Bolek needs an OpenRouter API key (developer build). Launch the app once with OPENROUTER_API_KEY set; it is then kept in the Keychain."
        case let .http(status, message):
            switch status {
            case 401: "OpenRouter rejected the API key (401). \(message)"
            case 402: "The OpenRouter account is out of credits (402)."
            case 429: "OpenRouter is rate limiting this key (429). Try again in a moment."
            default: "OpenRouter returned an error (\(status)): \(message)"
            }
        case .malformedResponse:
            "OpenRouter sent a reply the app could not read."
        }
    }
}

/// Bolek's brain: Kimi K3 through OpenRouter's OpenAI-compatible chat API.
/// The agent loop stays in `AgentSession`; moving to Phala's own endpoint later is a
/// base URL and key change.
///
/// Privacy: OpenRouter sees the plaintext in between, so this path is NOT confidential,
/// even when pinned to the Phala TEE provider. It is for development. For prototype
/// the key lives on the phone; a shipped Bolek calls our backend so no key reaches a user.
public struct OpenRouterProvider: ModelProvider {
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    public struct Options: Sendable {
        public var baseURL = URL(string: "https://openrouter.ai/api/v1")!
        /// Provider slugs to try first. Phala hosts Kimi K3 inside a GPU TEE.
        public var providerOrder: [String] = ["phala"]
        /// Allow other providers if the preferred one is down.
        public var allowFallbacks = true
        /// Refuse providers that may store or train on prompts.
        public var denyDataCollection = true
        public var reasoningEffort = "medium"

        public init() {}
    }

    public let profile: ModelProfile
    private let apiKey: @Sendable () -> String?
    private let options: Options
    private let transport: Transport

    public init(
        profile: ModelProfile = ModelCatalog.bolek,
        options: Options = Options(),
        apiKey: @escaping @Sendable () -> String?,
        transport: Transport? = nil
    ) {
        self.profile = profile
        self.options = options
        self.apiKey = apiKey
        self.transport = transport ?? { request in
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw OpenRouterError.malformedResponse }
            return (data, http)
        }
    }

    public func respond(to request: ModelRequest) async throws -> ModelResponse {
        guard let key = apiKey(), !key.isEmpty else { throw OpenRouterError.missingKey }
        let system = request.systemPrompt + "\n\n" + PromptClock.line(now: request.now, timeZone: request.timeZone, language: request.language)
        let messages = Self.messages(systemPrompt: system, from: request.messages)
        let body = Self.body(profile: profile, options: options, request: request, messages: messages)

        var http = URLRequest(url: options.baseURL.appendingPathComponent("chat/completions"))
        http.httpMethod = "POST"
        http.timeoutInterval = 180
        http.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        http.setValue("application/json", forHTTPHeaderField: "Content-Type")
        http.setValue("Bolek & Lolek", forHTTPHeaderField: "X-Title")
        http.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await transport(http)
        guard (200..<300).contains(response.statusCode) else {
            throw OpenRouterError.http(status: response.statusCode, message: Self.errorMessage(in: data))
        }
        return try Self.response(from: data)
    }

    // MARK: - Request building (pure, tested)

    static func body(profile: ModelProfile, options: Options, request: ModelRequest, messages: [[String: Any]]) -> [String: Any] {
        var body: [String: Any] = [
            "model": profile.id,
            "messages": messages,
            "max_tokens": profile.maxOutputTokens,
            "temperature": profile.temperature,
            "reasoning": ["effort": options.reasoningEffort],
            "provider": [
                "order": options.providerOrder,
                "allow_fallbacks": options.allowFallbacks,
                "data_collection": options.denyDataCollection ? "deny" : "allow",
            ] as [String: Any],
        ]
        if !request.tools.isEmpty {
            body["tools"] = request.tools.map { spec -> [String: Any] in
                [
                    "type": "function",
                    "function": [
                        "name": spec.name,
                        "description": spec.description,
                        "parameters": (try? JSONSerialization.jsonObject(with: Data(spec.parametersSchema.utf8))) ?? ["type": "object"],
                    ] as [String: Any],
                ]
            }
        }
        return body
    }

    /// Keys of the assistant message that must go back unchanged for reasoning models.
    private static let echoedKeys = ["reasoning", "reasoning_details"]

    static func messages(systemPrompt: String, from transcript: [ChatMessage]) -> [[String: Any]] {
        var out: [[String: Any]] = [["role": "system", "content": systemPrompt]]
        for message in transcript {
            switch message.role {
            case .system:
                continue
            case .user:
                out.append(["role": "user", "content": message.text])
            case .tool:
                let content = message.isError ? "Error: \(message.text)" : message.text
                out.append(["role": "tool", "tool_call_id": message.toolCallID ?? "", "content": content])
            case .assistant:
                var assistant: [String: Any] = ["role": "assistant"]
                assistant["content"] = message.text.isEmpty ? NSNull() : message.text
                if !message.toolCalls.isEmpty {
                    assistant["tool_calls"] = message.toolCalls.map { call -> [String: Any] in
                        [
                            "id": call.id,
                            "type": "function",
                            "function": ["name": call.name, "arguments": call.argumentsJSON],
                        ]
                    }
                }
                if let state = message.providerState,
                   let echoed = (try? JSONSerialization.jsonObject(with: Data(state.utf8))) as? [String: Any] {
                    for (key, value) in echoed { assistant[key] = value }
                }
                if message.text.isEmpty && message.toolCalls.isEmpty && message.providerState == nil { continue }
                out.append(assistant)
            }
        }
        return out
    }

    // MARK: - Response parsing (pure, tested)

    static func response(from data: Data) throws -> ModelResponse {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OpenRouterError.malformedResponse
        }
        // OpenRouter can return an error object with HTTP 200 (e.g. provider failure mid-route).
        if let error = object["error"] as? [String: Any] {
            let code = (error["code"] as? Int) ?? 502
            throw OpenRouterError.http(status: code, message: error["message"] as? String ?? "Unknown error")
        }
        guard let choices = object["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any]
        else { throw OpenRouterError.malformedResponse }

        var text = ""
        if let content = message["content"] as? String {
            text = content
        } else if let parts = message["content"] as? [[String: Any]] {
            text = parts.compactMap { $0["text"] as? String }.joined()
        }

        var calls: [ToolCall] = []
        for call in (message["tool_calls"] as? [[String: Any]]) ?? [] {
            guard let id = call["id"] as? String,
                  let function = call["function"] as? [String: Any],
                  let name = function["name"] as? String else { continue }
            let arguments = (function["arguments"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "{}"
            calls.append(ToolCall(id: id, name: name, argumentsJSON: arguments))
        }

        var echoed: [String: Any] = [:]
        for key in echoedKeys {
            if let value = message[key], !(value is NSNull) { echoed[key] = value }
        }
        let state = echoed.isEmpty ? nil : String(decoding: try JSONSerialization.data(withJSONObject: echoed), as: UTF8.self)

        let finish = choices.first?["finish_reason"] as? String
        if text.isEmpty, calls.isEmpty, finish == "length" {
            text = "I ran out of room to answer. Please ask again, more briefly."
        }
        return ModelResponse(text: text.trimmingCharacters(in: .whitespacesAndNewlines), toolCalls: calls, providerState: state)
    }

    static func errorMessage(in data: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = object["error"] as? [String: Any],
              let message = error["message"] as? String
        else { return String(decoding: data.prefix(200), as: UTF8.self) }
        return message
    }
}
