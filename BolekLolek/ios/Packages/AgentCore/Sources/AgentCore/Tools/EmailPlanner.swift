import Foundation

/// The email the user opened in the Mail screen and wants to talk about. The next turn reads it for the model.
public actor EmailFocus {
    private var pending: String?
    /// Turns left in which follow-up questions are about the opened email, not about other documents.
    private var activeTurns = 0
    public init() {}
    public func set(id: String) { pending = id }
    func take() -> String? {
        defer { pending = nil }
        if pending != nil { activeTurns = 4 }
        return pending
    }
    /// Called once per user turn before anything else decides what the message is about.
    func tick() { if pending == nil, activeTurns > 0 { activeTurns -= 1 } }
    public var isActive: Bool { activeTurns > 0 }
}

/// Wraps another planner (the bank statement one) so it stays quiet while the user is talking about an opened email:
/// "how much does it cost?" means the booking in the email, not the statement. Words that clearly name a statement still pass.
public struct QuietWhileEmailIsOpen: TurnPlanner {
    private let inner: any TurnPlanner
    private let focus: EmailFocus
    private static let statementWords = ["wyciag", "statement", "bank", "konto", "account", "transakcj", "transaction", "saldo", "balance"]

    public init(_ inner: any TurnPlanner, focus: EmailFocus) {
        self.inner = inner
        self.focus = focus
    }

    public func plan(userText: String, language: ConversationLanguage) async -> [ToolCall] {
        if await focus.isActive {
            let folded = userText.folded
            if !Self.statementWords.contains(where: { folded.contains($0) }) { return [] }
        }
        return await inner.plan(userText: userText, language: language)
    }
}

/// Reads what the user asked about their mail and builds the search itself. A 4B model asked to turn "emails from today"
/// into a search either did not search or searched wrongly; code does not. The model still writes the answer.
public struct EmailPlanner: TurnPlanner {
    private let focus: EmailFocus
    private let isConnected: @Sendable () async -> Bool

    public init(focus: EmailFocus, isConnected: @escaping @Sendable () async -> Bool) {
        self.focus = focus
        self.isConnected = isConnected
    }

    private static let mailWords = ["mail", "maile", "maili", "maila", "mailu", "mailem", "email", "emaile", "emaili", "emaila", "poczt", "skrzynk", "inbox", "korespondencj"]
    private static let writingWords = ["wyslij", "napisz", "odpowiedz", "odpisz", "send", "write", "draft", "reply", "compose", "przygotuj"]

    public func plan(userText: String, language: ConversationLanguage) async -> [ToolCall] {
        guard await isConnected() else { return [] }
        await focus.tick()
        if let id = await focus.take() {
            return [ToolCall(id: "planned-read", name: "read_email", argumentsJSON: ToolArguments.encode(["id": id]))]
        }
        let folded = " " + userText.folded + " "
        let tokens = folded.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        func has(_ prefixes: [String]) -> Bool { prefixes.contains { p in tokens.contains { $0.hasPrefix(p) } } }

        guard has(Self.mailWords), !has(Self.writingWords) else { return [] }

        var args: [String: Any] = [:]
        if has(["dzis", "today"]) {
            args["when"] = "today"
        } else if has(["wczoraj", "yesterday"]) {
            args["when"] = "yesterday"
        } else if folded.contains("30 dni") || folded.contains("30 days") || folded.contains("last month") || folded.contains("ostatni miesiac") {
            args["when"] = "last_30_days"
        } else if folded.contains("7 dni") || folded.contains("7 days") || folded.contains("last week") || folded.contains("ostatni tydzien") || folded.contains("ostatnie 7") {
            args["when"] = "last_7_days"
        } else if folded.contains("this week") || folded.contains("w tym tygodniu") || folded.contains("tego tygodnia") || folded.contains("tym tygodniu") {
            args["when"] = "this_week"
        }
        if has(["unread", "nieprzeczytan", "nowe ", "nowych"]) || folded.contains("new mail") || folded.contains("new email") { args["unread"] = true }
        if let sender = Self.sender(in: tokens) { args["from"] = sender }
        // Asking about one kind of mail: list just that group (the others are still counted).
        if has(["people", "person", "humans", "ludzi", "osob"]) && (folded.contains("real") || folded.contains(" from ") || folded.contains(" od ") || folded.contains("prawdziw")) {
            args["only"] = "people"
        } else if has(["promo", "reklam", "newsletter", "oferty"]) {
            args["only"] = "promotions"
        }

        let counting = has(["ile", "how", "count", "policz"])
        // Only act when there is something concrete to look up; otherwise the model decides with the tools it has.
        guard !args.isEmpty || counting else { return [] }
        return [ToolCall(id: "planned-search", name: "search_email", argumentsJSON: Self.json(args))]
    }

    private static func json(_ object: [String: Any]) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    /// "from Delta" / "od Marka": the one or two words after the marker, up to a filler word.
    private static func sender(in tokens: [String]) -> String? {
        let markers: Set<String> = ["from", "od"]
        // "from real people" / "od ludzi" describe a kind of sender, not a name: leave the sender open.
        let generic: Set<String> = ["people", "person", "real", "anyone", "someone", "somebody", "human", "humans", "friends", "colleagues", "ludzi", "osoby", "osob", "kogos", "kogokolwiek", "znajomych", "rana", "morning"]
        let stop: Set<String> = ["today", "dzis", "dzisiaj", "yesterday", "wczoraj", "this", "last", "in", "w", "z", "on", "that", "which", "i", "and", "oraz", "unread", "nieprzeczytane", "mail", "maile", "email", "emails", "the"]
        guard let index = tokens.firstIndex(where: { markers.contains($0) }) else { return nil }
        var words: [String] = []
        if let first = tokens[(index + 1)...].first, generic.contains(first) { return nil }
        for token in tokens[(index + 1)...].prefix(2) {
            if stop.contains(token) { break }
            words.append(token)
        }
        return words.isEmpty ? nil : words.joined(separator: " ")
    }
}
