import AgentCore
import Foundation

/// Signed amounts as banks print them: "-45,60", "(45.60)", "45.60-", "45,60 DR", "−1 234,50 zł".
public enum SignedMoney {
    public struct Parsed: Equatable, Sendable {
        public let minorUnits: Int
        public let currency: String?
        /// True when the text itself said debit or credit (a sign, brackets, DR/CR).
        public let hadExplicitSign: Bool
    }

    public static func parse(_ raw: String) -> Parsed? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        var negative = false
        var explicit = false

        if text.hasPrefix("(") && text.hasSuffix(")") { negative = true; explicit = true; text = String(text.dropFirst().dropLast()) }
        let upper = text.uppercased()
        if upper.hasSuffix(" DR") || upper.hasSuffix("DR") && upper.dropLast(2).last?.isNumber == true { negative = true; explicit = true; text = String(text.dropLast(2)) }
        else if upper.hasSuffix(" CR") || upper.hasSuffix("CR") && upper.dropLast(2).last?.isNumber == true { explicit = true; text = String(text.dropLast(2)) }

        text = text.trimmingCharacters(in: .whitespaces)
        for minus in ["-", "−", "–", "—"] where text.hasPrefix(minus) { negative = true; explicit = true; text = String(text.dropFirst()); break }
        for minus in ["-", "−", "–"] where text.hasSuffix(minus) { negative = true; explicit = true; text = String(text.dropLast()); break }
        if text.hasPrefix("+") { explicit = true; text = String(text.dropFirst()) }
        // A sign can also sit between the currency symbol and the digits: "$-45.60", "zł -45,60".
        text = text.trimmingCharacters(in: .whitespaces)
        for minus in ["-", "−", "–"] {
            if let range = text.range(of: minus), text[..<range.lowerBound].allSatisfy({ !$0.isNumber }) {
                negative = true; explicit = true; text.removeSubrange(range); break
            }
        }

        guard let amount = AmountParser.parse(text) else { return nil }
        // AmountParser defaults to PLN when no currency is written; do not claim that here.
        let wroteCurrency = text.rangeOfCharacter(from: .letters) != nil || text.contains(where: { "€$£".contains($0) })
        return Parsed(minorUnits: negative ? -amount.minorUnits : amount.minorUnits, currency: wroteCurrency ? amount.currency : nil, hadExplicitSign: explicit)
    }
}

public enum DayOrder: Sendable { case dayFirst, monthFirst }

public enum DateParsing {
    private static let months: [String: Int] = {
        var map: [String: Int] = [:]
        let english = [["january", "jan"], ["february", "feb"], ["march", "mar"], ["april", "apr"], ["may"], ["june", "jun"],
                       ["july", "jul"], ["august", "aug"], ["september", "sep", "sept"], ["october", "oct"], ["november", "nov"], ["december", "dec"]]
        let polish = [["stycznia", "styczen", "sty"], ["lutego", "luty", "lut"], ["marca", "marzec", "mar"], ["kwietnia", "kwiecien", "kwi"],
                      ["maja", "maj"], ["czerwca", "czerwiec", "cze"], ["lipca", "lipiec", "lip"], ["sierpnia", "sierpien", "sie"],
                      ["wrzesnia", "wrzesien", "wrz"], ["pazdziernika", "pazdziernik", "paz"], ["listopada", "listopad", "lis"],
                      ["grudnia", "grudzien", "gru"]]
        for (index, names) in english.enumerated() { for name in names { map[name] = index + 1 } }
        for (index, names) in polish.enumerated() { for name in names { map[name] = index + 1 } }
        return map
    }()

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    public static func date(year: Int, month: Int, day: Int) -> Date? {
        guard (1...12).contains(month), (1...31).contains(day) else { return nil }
        let components = DateComponents(year: year, month: month, day: day, hour: 12)
        guard let date = calendar.date(from: components),
              calendar.component(.day, from: date) == day, calendar.component(.month, from: date) == month else { return nil }
        return date
    }

    public static func parts(_ date: Date) -> (year: Int, month: Int, day: Int) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return (c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    public static func isoString(_ date: Date) -> String {
        let p = parts(date)
        return String(format: "%04d-%02d-%02d", p.year, p.month, p.day)
    }

    public static func monthKey(_ date: Date) -> String {
        let p = parts(date)
        return String(format: "%04d-%02d", p.year, p.month)
    }

    /// Looks for a date at the start of `text`; returns it with the length of what it consumed.
    /// `defaultYear` is used for day-and-month-only dates such as "02 Mar" or "02.03".
    public static func leadingDate(in text: String, order: DayOrder, defaultYear: Int?) -> (date: Date, length: Int)? {
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: "^" + pattern.regex, options: [.caseInsensitive]),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let parsed = pattern.build(text, match, order, defaultYear) else { continue }
            return (parsed, match.range.length)
        }
        return nil
    }

    public static func parse(_ text: String, order: DayOrder, defaultYear: Int? = nil) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let found = leadingDate(in: trimmed, order: order, defaultYear: defaultYear) else { return nil }
        // Allow a time of day after the date ("2026-03-02 14:31:05"), nothing else.
        let rest = trimmed.dropFirst(found.length).trimmingCharacters(in: .whitespaces)
        return rest.isEmpty || rest.first?.isNumber == true || rest.hasPrefix("T") ? found.date : nil
    }

    /// Picks day-first or month-first from the evidence in a column of dates. Day-first when it is a toss-up.
    public static func detectOrder(_ samples: [String], hint: DayOrder = .dayFirst) -> DayOrder {
        var dayFirstEvidence = false, monthFirstEvidence = false
        let regex = try? NSRegularExpression(pattern: #"^\s*(\d{1,2})[./-](\d{1,2})[./-](\d{2,4})"#)
        for sample in samples {
            guard let match = regex?.firstMatch(in: sample, range: NSRange(sample.startIndex..., in: sample)),
                  let a = Range(match.range(at: 1), in: sample).flatMap({ Int(sample[$0]) }),
                  let b = Range(match.range(at: 2), in: sample).flatMap({ Int(sample[$0]) }) else { continue }
            if a > 12 { dayFirstEvidence = true }
            if b > 12 { monthFirstEvidence = true }
        }
        if dayFirstEvidence && !monthFirstEvidence { return .dayFirst }
        if monthFirstEvidence && !dayFirstEvidence { return .monthFirst }
        return hint
    }

    // MARK: Patterns

    private struct Pattern {
        let regex: String
        let build: (String, NSTextCheckingResult, DayOrder, Int?) -> Date?
    }

    private static func int(_ text: String, _ match: NSTextCheckingResult, _ group: Int) -> Int? {
        Range(match.range(at: group), in: text).flatMap { Int(text[$0]) }
    }

    private static func word(_ text: String, _ match: NSTextCheckingResult, _ group: Int) -> String? {
        Range(match.range(at: group), in: text).map { String(text[$0]) }
    }

    private static func fullYear(_ y: Int) -> Int { y < 100 ? (y < 70 ? 2000 + y : 1900 + y) : y }

    private static let patterns: [Pattern] = [
        // 2026-03-02, 2026.03.02, 2026/03/02
        Pattern(regex: #"(\d{4})[-./](\d{1,2})[-./](\d{1,2})(?!\d)"#) { t, m, _, _ in
            guard let y = int(t, m, 1), let mo = int(t, m, 2), let d = int(t, m, 3) else { return nil }
            return date(year: y, month: mo, day: d)
        },
        // 02.03.2026, 02-03-26, 03/02/2026
        Pattern(regex: #"(\d{1,2})[-./](\d{1,2})[-./](\d{4}|\d{2})(?!\d)"#) { t, m, order, _ in
            guard let a = int(t, m, 1), let b = int(t, m, 2), let y = int(t, m, 3) else { return nil }
            return order == .dayFirst ? date(year: fullYear(y), month: b, day: a) : date(year: fullYear(y), month: a, day: b)
        },
        // 12 Mar 2026, 12 marca 2026, 12 Mar. 2026
        Pattern(regex: #"(\d{1,2})\s+([A-Za-zĄĆĘŁŃÓŚŹŻąćęłńóśźż]{3,12})\.?,?\s+(\d{4})(?!\d)"#) { t, m, _, _ in
            guard let d = int(t, m, 1), let name = word(t, m, 2), let mo = months[name.folded], let y = int(t, m, 3) else { return nil }
            return date(year: y, month: mo, day: d)
        },
        // Mar 12, 2026
        Pattern(regex: #"([A-Za-z]{3,9})\.?\s+(\d{1,2}),?\s+(\d{4})(?!\d)"#) { t, m, _, _ in
            guard let name = word(t, m, 1), let mo = months[name.folded], let d = int(t, m, 2), let y = int(t, m, 3) else { return nil }
            return date(year: y, month: mo, day: d)
        },
        // 02 Mar (no year)
        Pattern(regex: #"(\d{1,2})\s+([A-Za-zĄĆĘŁŃÓŚŹŻąćęłńóśźż]{3,12})\b(?!\s*\d{4})"#) { t, m, _, defaultYear in
            guard let year = defaultYear, let d = int(t, m, 1), let name = word(t, m, 2), let mo = months[name.folded] else { return nil }
            return date(year: year, month: mo, day: d)
        },
        // 02.03 or 03/02 (no year), only when the caller knows the year
        Pattern(regex: #"(\d{1,2})[./](\d{1,2})(?![\d./])"#) { t, m, order, defaultYear in
            guard let year = defaultYear, let a = int(t, m, 1), let b = int(t, m, 2) else { return nil }
            return order == .dayFirst ? date(year: year, month: b, day: a) : date(year: year, month: a, day: b)
        },
    ]
}
