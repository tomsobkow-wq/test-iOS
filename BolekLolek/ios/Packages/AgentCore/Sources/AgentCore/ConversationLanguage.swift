import Foundation

/// Languages the agent replies in. Polish and English are first-class.
public enum ConversationLanguage: String, CaseIterable, Codable, Sendable {
    case en
    case pl

    public static func fromLocale(_ locale: Locale = .current) -> ConversationLanguage {
        locale.language.languageCode?.identifier == "pl" ? .pl : .en
    }

    /// Cheap heuristic for the language of a user message. Polish diacritics
    /// win outright; otherwise common function words are counted. Ties keep
    /// `fallback` (usually the language of the previous turn).
    public static func detect(_ text: String, fallback: ConversationLanguage) -> ConversationLanguage {
        let lower = text.lowercased()
        if lower.contains(where: { polishLetters.contains($0) }) {
            return .pl
        }
        let words = lower.split(whereSeparator: { !$0.isLetter }).map(String.init)
        let pl = words.filter { polishMarkers.contains($0) }.count
        let en = words.filter { englishMarkers.contains($0) }.count
        if pl > en { return .pl }
        if en > pl { return .en }
        return fallback
    }

    private static let polishLetters: Set<Character> = ["ą", "ć", "ę", "ł", "ń", "ó", "ś", "ź", "ż"]

    private static let polishMarkers: Set<String> = [
        "w", "z", "na", "nie", "jest", "czy", "jak", "co", "mi", "mnie",
        "jutro", "dzisiaj", "proszę", "prosze", "dzieki", "dzięki", "zrob", "napisz",
        "przypomnij", "notatka", "wyslij", "kupic", "albo", "ale", "tak",
    ]

    private static let englishMarkers: Set<String> = [
        "the", "is", "are", "and", "of", "you", "me", "my", "please", "what",
        "how", "can", "remind", "tomorrow", "today", "send", "note", "buy",
        "with", "for", "this", "that", "yes",
    ]
}

/// A string the agent needs in both languages (prompts, tool descriptions).
public struct LocalizedText: Codable, Sendable, Equatable {
    public let en: String
    public let pl: String

    public init(en: String, pl: String) {
        self.en = en
        self.pl = pl
    }

    public func text(for language: ConversationLanguage) -> String {
        switch language {
        case .en: en
        case .pl: pl
        }
    }
}
