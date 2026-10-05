import Foundation

/// Picks the sentences of a document that carry facts: amounts, dates, deadlines, obligations. A 4B model asked to
/// summarise a whole contract drops the numbers; shown only these sentences, it only has to phrase them.
public enum ExtractiveBrief {
    private static let amount = try! NSRegularExpression(pattern: #"\d[\d  .,']*\s?(?:zł|zl|pln|eur|€|usd|\$|£|gbp|%)|(?:£|€|\$)\s?\d[\d,.]*"#, options: .caseInsensitive)
    private static let date = try! NSRegularExpression(pattern: #"\b\d{1,2}[./-]\d{1,2}[./-]\d{2,4}\b|\b\d{1,2}\s+(?:[A-Za-ząćęłńóśźż]{3,12})\s+\d{4}\b|\b(?:19|20)\d{2}\b"#, options: .caseInsensitive)
    private static let duration = try! NSRegularExpression(pattern: #"\b\d+\s*(?:dni|dzień|dnia|tygod|miesi|lat|days?|weeks?|months?|years?)\b|(?:trzy|dwa|sześć|dwanaście)\w*\s*miesi"#, options: .caseInsensitive)
    private static let keywords = ["zobowiąz", "obowiąz", "kara", "kaucj", "czynsz", "opłat", "płatn", "wypowiedz", "rozwiąz", "termin", "odsetk", "zakaz", "prawo do",
                                   "shall", "must", "penalty", "deposit", "rent", "fee", "payable", "due", "terminate", "notice", "interest", "prohibited", "total", "razem", "suma"]

    static func sentences(in text: String) -> [String] {
        var out: [String] = []
        for paragraph in text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            var current = ""
            for word in paragraph.split(separator: " ", omittingEmptySubsequences: true) {
                current += (current.isEmpty ? "" : " ") + word
                // A sentence ends at . ! ? ; but not inside "1.", "ul.", "§ 2." or an abbreviation of one or two letters.
                if let last = word.last, ".!?;".contains(last), word.count > 3, !word.first!.isNumber || word.count > 4 {
                    out.append(current); current = ""
                }
            }
            if !current.isEmpty { out.append(current) }
        }
        // Short lines are kept when they carry a figure: "VAT at 20%: £660.00" is 19 characters and the most important line of an invoice.
        return out.map { $0.trimmingCharacters(in: .whitespaces) }.filter { $0.count >= 20 || ($0.count >= 6 && score($0) > 0) }
    }

    static func score(_ sentence: String) -> Int {
        let range = NSRange(sentence.startIndex..., in: sentence)
        let lower = sentence.lowercased()
        return amount.numberOfMatches(in: sentence, range: range) * 4 + date.numberOfMatches(in: sentence, range: range) * 2
            + duration.numberOfMatches(in: sentence, range: range) * 3 + keywords.reduce(0) { $0 + (lower.contains($1) ? 2 : 0) }
    }

    /// The most informative sentences, in the order they appear, within `budgetCharacters`. The opening is always kept
    /// so the model can say what kind of document it is.
    public static func build(from chunks: [DocumentChunk], budgetCharacters: Int = 3_000) -> String {
        let all = chunks.flatMap { sentences(in: $0.text) }
        guard !all.isEmpty else { return "" }
        var chosen = Set(all.indices.prefix(2))
        var used = chosen.reduce(0) { $0 + min(all[$1].count, 320) }
        for index in all.indices.sorted(by: { score(all[$0]) > score(all[$1]) }) where !chosen.contains(index) {
            guard score(all[index]) > 0 else { break }
            let cost = min(all[index].count, 320)
            if used + cost > budgetCharacters { continue }
            chosen.insert(index); used += cost
        }
        return chosen.sorted().map { sentence in
            let text = all[sentence]
            return "• " + (text.count > 320 ? String(text.prefix(320)) + "…" : text)
        }.joined(separator: "\n")
    }
}
