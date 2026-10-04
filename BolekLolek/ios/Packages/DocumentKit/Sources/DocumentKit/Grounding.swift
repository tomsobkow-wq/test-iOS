import AgentCore
import Foundation

/// Finds numbers in an answer that the source data never contained. A 4B model that is shown "4745.93" will
/// sometimes write "4754.93"; this catches that before the user sees it.
public enum NumberGrounding {
    private static let regex = try! NSRegularExpression(pattern: #"\d{1,3}(?:[  .,']\d{3})+(?:[.,]\d{1,2})?|\d+(?:[.,]\d{1,2})?"#)

    /// Value in hundredths, plus whether the text showed decimals.
    struct Number: Hashable { let cents: Int; let hadDecimals: Bool; let text: String }

    static func numbers(in text: String) -> [Number] {
        regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            guard let range = Range(match.range, in: text) else { return nil }
            return parse(String(text[range]))
        }
    }

    static func parse(_ token: String) -> Number? {
        let compact = token.replacingOccurrences(of: "\u{00A0}", with: "").replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "'", with: "")
        let lastDot = compact.lastIndex(of: "."), lastComma = compact.lastIndex(of: ",")
        var decimalIndex: String.Index?
        if let dot = lastDot, let comma = lastComma { decimalIndex = max(dot, comma) }
        else if let only = lastDot ?? lastComma {
            let separator = compact[only]
            let after = compact.distance(from: only, to: compact.endIndex) - 1
            let count = compact.filter { $0 == separator }.count
            if count == 1 && after != 3 { decimalIndex = only }   // "12,50" and "4745.9" are decimals; "1,234" is thousands
        }
        var whole = compact, fraction = ""
        if let index = decimalIndex {
            whole = String(compact[..<index]); fraction = String(compact[compact.index(after: index)...])
        }
        whole = whole.filter(\.isNumber)
        guard let wholeValue = Int(whole.isEmpty ? "0" : whole), wholeValue < 1_000_000_000 else { return nil }
        let cents = Int((fraction + "00").prefix(2)) ?? 0
        return Number(cents: wholeValue * 100 + cents, hadDecimals: !fraction.isEmpty, text: token)
    }

    /// Numbers in `answer` that cannot be found in `sources`. Small whole numbers (counts, days, times, years) are free.
    public static func ungrounded(answer: String, sources: [String]) -> [String] {
        let known = Set(sources.flatMap { numbers(in: $0) }.map(\.cents))
        let knownList = Array(known)
        var missing: [String] = []
        for number in numbers(in: answer) {
            let whole = number.cents / 100
            if !number.hadDecimals, number.cents % 100 == 0, whole <= 99 || (1900...2100).contains(whole) { continue }
            if known.contains(number.cents) { continue }
            // A rounded figure ("4746" for 4745.93) is fine when it is within half a percent of a real one.
            if !number.hadDecimals, knownList.contains(where: { abs($0 - number.cents) * 200 <= max($0, 1) }) { continue }
            if !missing.contains(number.text) { missing.append(number.text) }
        }
        return missing
    }

    /// Drops lines that contain an unsupported number (for summaries, where a rewrite is too expensive).
    public static func removeUngroundedLines(from summary: String, sources: [String]) -> String {
        summary.components(separatedBy: "\n").filter { ungrounded(answer: $0, sources: sources).isEmpty }.joined(separator: "\n")
    }
}

/// Plugs the number check into the agent loop for answers built on statement and document tools.
public struct GroundingVerifier: AnswerVerifier {
    public init() {}

    public func review(answer: String, toolNames: [String], toolResults: [String], userText: String, language: ConversationLanguage) -> String? {
        guard toolNames.contains(where: { $0.hasPrefix("statement_") || $0 == "document_summary" }) else { return nil }
        let missing = NumberGrounding.ungrounded(answer: answer, sources: toolResults + [userText])
        guard !missing.isEmpty else { return nil }
        let list = missing.prefix(5).joined(separator: ", ")
        switch language {
        case .pl: return "W Twojej odpowiedzi są liczby, których nie ma w danych z narzędzi: \(list). Napisz odpowiedź jeszcze raz, używając wyłącznie liczb z wyników narzędzi, przepisanych dokładnie. Niczego nie dodawaj ani nie zaokrąglaj. Jeśli czegoś nie ma w danych, powiedz to."
        case .en: return "Your answer contains numbers that are not in the tool results: \(list). Write the answer again using only numbers from the tool results, copied exactly. Do not add or round anything. If something is not in the data, say so."
        }
    }

    public func caution(language: ConversationLanguage) -> String {
        switch language {
        case .pl: "(Uwaga: nie wszystkie liczby udało się potwierdzić w danych. Sprawdź dokładne kwoty w wyciągu.)"
        case .en: "(Note: I could not confirm every figure against the data. Please check the exact amounts in the statement.)"
        }
    }
}
