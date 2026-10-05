import Foundation

/// Scripted stand-in until the real runtimes land (Lolek: step 2, Bolek: step 6).
/// It understands a few typed commands so every real tool can be exercised end
/// to end without a language model; anything else is echoed back:
///
///     weather | weather: Kraków      alarm: 06:30        timer: 10 (minutes)
///     remind: pay rent @ 2026-11-02T09:00   events       text: Anna: running late
///     call: Anna       spent: 12,50 Lidl    spending: this_week
///     tracking on | tracking off     note: buy milk      send: hello
///
/// Polish equivalents work too (pogoda, budzik, minutnik, przypomnij, kalendarz,
/// napisz, zadzwoń, wydałem, wydatki, śledzenie włącz/wyłącz, notatka, wyślij).
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
            // Plain confirmations are localized; informative results (weather, totals) are echoed.
            if last.text == "Saved note." { return ModelResponse(text: language == .pl ? "Gotowe." : "Done.") }
            return ModelResponse(text: last.text)
        }

        let text = last.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let call = Self.command(in: text), request.tools.contains(where: { $0.name == call.name }) {
            return ModelResponse(toolCalls: [call])
        }

        let name = request.mode == .lolek ? "Lolek" : "Bolek"
        switch language {
        case .en:
            return ModelResponse(text: "\(name) (demo model, \(profile.displayName) coming soon): “\(text)”")
        case .pl:
            return ModelResponse(text: "\(name) (model demonstracyjny, wkrótce \(profile.displayName)): „\(text)”")
        }
    }

    // MARK: - Command parsing

    static func command(in text: String) -> ToolCall? {
        let lower = text.lowercased()

        func tool(_ name: String, _ arguments: [String: Any]) -> ToolCall {
            let data = (try? JSONSerialization.data(withJSONObject: arguments, options: [.sortedKeys])) ?? Data("{}".utf8)
            return ToolCall(name: name, argumentsJSON: String(decoding: data, as: UTF8.self))
        }

        if let place = payload(of: text, prefixes: ["weather:", "pogoda:"]) { return tool("get_weather", ["place": place]) }
        if ["weather", "pogoda"].contains(lower) { return tool("get_weather", [:]) }
        if let time = payload(of: text, prefixes: ["alarm:", "budzik:"]) { return tool("set_alarm", ["time": time]) }
        if let minutes = payload(of: text, prefixes: ["timer:", "minutnik:"]), let value = Double(minutes) {
            return tool("set_timer", ["seconds": Int(value * 60)])
        }
        if let body = payload(of: text, prefixes: ["remind:", "przypomnij:"]) {
            let parts = body.components(separatedBy: "@")
            guard parts.count == 2 else { return nil }
            return tool("add_reminder", ["title": parts[0].trimmingCharacters(in: .whitespaces), "when": parts[1].trimmingCharacters(in: .whitespaces)])
        }
        if ["events", "kalendarz"].contains(lower) { return tool("list_calendar_events", [:]) }
        if let body = payload(of: text, prefixes: ["text:", "napisz:"]) {
            let parts = body.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { return nil }
            return tool("text_contact", ["to": parts[0], "body": parts[1]])
        }
        if let who = payload(of: text, prefixes: ["call:", "zadzwoń:", "zadzwon:"]) { return tool("call_contact", ["to": who]) }
        if let body = payload(of: text, prefixes: ["spent:", "wydałem:", "wydalem:", "wydałam:"]) {
            // "12,50 Lidl": the first word is the amount, the rest the merchant.
            let parts = body.split(separator: " ", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return nil }
            return tool("log_expense", ["amount": parts[0], "merchant": parts[1]])
        }
        if let period = payload(of: text, prefixes: ["spending:", "wydatki:"]) { return tool("spending_summary", ["period": period]) }
        if ["tracking on", "śledzenie włącz", "sledzenie wlacz"].contains(lower) { return tool("set_spending_tracking", ["enabled": true]) }
        if ["tracking off", "śledzenie wyłącz", "sledzenie wylacz"].contains(lower) { return tool("set_spending_tracking", ["enabled": false]) }
        if let note = payload(of: text, prefixes: ["note:", "notatka:"]) { return tool("add_note", ["text": note]) }
        if let message = payload(of: text, prefixes: ["send:", "wyślij:", "wyslij:"]) { return tool("send_message_demo", ["text": message]) }
        return nil
    }

    static func payload(of text: String, prefixes: [String]) -> String? {
        let lower = text.lowercased()
        for prefix in prefixes where lower.hasPrefix(prefix) {
            return String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }
}
