import Foundation

extension String {
    /// Lowercase without diacritics ("Płatność" -> "platnosc"), for keyword matching.
    var folded: String {
        replacingOccurrences(of: "ł", with: "l").replacingOccurrences(of: "Ł", with: "L")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
}

/// Where a hand-off offer goes. The app shows it as a button; nothing is sent until the user taps it.
public protocol HandoffSink: Sendable {
    func offer(request: String) async
}

/// Lolek cannot reach the internet. For requests that need it, this tool puts an "Ask Bolek" button in the chat and
/// tells the model to say so briefly. Offering sends nothing: only the user's tap does, and then only this request.
public struct OfferHandoffTool: Tool {
    public let name = "ask_bolek"
    public let description = LocalizedText(
        en: "Use when the user's request needs the internet or live information (web search, prices, flights, tickets, news, booking). Shows the user a button that sends just this request to Bolek, the cloud assistant. Pass the user's request.",
        pl: "Użyj, gdy prośba wymaga internetu lub bieżących informacji (wyszukiwanie, ceny, loty, bilety, wiadomości, rezerwacje). Pokazuje użytkownikowi przycisk, który wysyła tylko tę prośbę do Bolka, asystenta w chmurze. Przekaż prośbę użytkownika."
    )
    public let parametersSchema = #"{"type":"object","properties":{"request":{"type":"string"}},"required":["request"]}"#
    public let tier = ToolTier.lolek
    public let risk = ToolRisk.read
    private let sink: any HandoffSink

    public init(sink: any HandoffSink) { self.sink = sink }

    struct Args: Decodable { let request: String }

    public func run(argumentsJSON: String) async throws -> String {
        let args = try ToolArguments.decode(Args.self, from: argumentsJSON)
        await sink.offer(request: args.request)
        return Self.instruction
    }

    /// The same sentence every time, written by us. A small model copies a sentence well and composes Polish badly.
    static let sentencePL = "Tego nie zrobię sam, bo potrzebuję internetu. Przycisk poniżej wyśle tylko tę prośbę do Bolka."
    static let sentenceEN = "I can't do this myself because it needs the internet. The button below sends only this request to Bolek."

    static var instruction: String {
        "An Ask Bolek button is now shown. Reply with exactly one of these sentences, in the language the user wrote in, copied word for word, and nothing else. "
            + "Polish: \"\(sentencePL)\" English: \"\(sentenceEN)\" Do not try to answer the request."
    }
}

/// Clear internet requests go straight to the hand-off. A 4B model asked to decide would sometimes just invent prices.
public struct WebIntentPlanner: TurnPlanner {
    public init() {}

    private static let words = ["loty", "lotow", "lotu", "flight", "flights", "bilet", "ticket", "najtansz", "cheapest", "wyszukaj", "w internecie", "w sieci",
                                "online", "google", "wiadomosci ze swiata", "aktualnosci", "news", "hotel", "airbnb", "booking", "search the web", "look up online"]

    public func plan(userText: String, language: ConversationLanguage) async -> [ToolCall] {
        let folded = " " + userText.folded + " "
        let tokens = folded.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        let hit = Self.words.contains { word in
            word.contains(" ") ? folded.contains(word) : tokens.contains { $0.hasPrefix(word) }
        }
        guard hit else { return [] }
        return [ToolCall(id: "planned-handoff", name: "ask_bolek", argumentsJSON: ToolArguments.encode(["request": userText]))]
    }
}

/// Tries each planner in order and uses the first that has an opinion.
public struct CompositeTurnPlanner: TurnPlanner {
    private let planners: [any TurnPlanner]

    public init(_ planners: [any TurnPlanner]) { self.planners = planners }

    public func plan(userText: String, language: ConversationLanguage) async -> [ToolCall] {
        for planner in planners {
            let calls = await planner.plan(userText: userText, language: language)
            if !calls.isEmpty { return calls }
        }
        return []
    }
}
