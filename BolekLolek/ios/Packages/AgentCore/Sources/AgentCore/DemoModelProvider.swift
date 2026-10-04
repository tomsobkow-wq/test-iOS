import Foundation

/// Scripted stand-in until the real runtimes land (Lolek: step 2, Bolek: step 6).
/// "note: …" / "notatka: …" saves a note; "send: …" / "wyślij: …" triggers
/// the approval flow; anything else is echoed back.
public struct DemoModelProvider: ModelProvider {
    public let profile: ModelProfile

    public init(profile: ModelProfile) {
        self.profile = profile
    }

    public func respond(to request: ModelRequest) async throws -> ModelResponse {
        let language = request.language
        guard let last = request.messages.last else { return ModelResponse() }

        if last.role == .tool {
            if last.isError {
                return ModelResponse(text: language == .pl ? "Nie udało się: \(last.text)" : "That didn't work: \(last.text)")
            }
            return ModelResponse(text: language == .pl ? "Gotowe." : "Done.")
        }

        let text = last.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let payload = Self.payload(of: text, prefixes: ["note:", "notatka:"]),
           request.tools.contains(where: { $0.name == "add_note" }) {
            return call("add_note", text: payload)
        }
        if let payload = Self.payload(of: text, prefixes: ["send:", "wyślij:", "wyslij:"]),
           request.tools.contains(where: { $0.name == "send_message_demo" }) {
            return call("send_message_demo", text: payload)
        }

        let name = request.mode == .lolek ? "Lolek" : "Bolek"
        switch language {
        case .en:
            return ModelResponse(text: "\(name) (demo model, \(profile.displayName) coming soon): “\(text)”")
        case .pl:
            return ModelResponse(text: "\(name) (model demonstracyjny, wkrótce \(profile.displayName)): „\(text)”")
        }
    }

    private func call(_ tool: String, text: String) -> ModelResponse {
        ModelResponse(toolCalls: [ToolCall(name: tool, argumentsJSON: ToolArguments.encode(TextArgument(text: text)))])
    }

    static func payload(of text: String, prefixes: [String]) -> String? {
        let lower = text.lowercased()
        for prefix in prefixes where lower.hasPrefix(prefix) {
            return String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }
}
