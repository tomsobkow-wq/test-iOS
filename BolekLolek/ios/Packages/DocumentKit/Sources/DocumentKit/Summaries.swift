import AgentCore
import Foundation

public enum CategoryNames {
    public static func label(_ category: String, _ language: ConversationLanguage) -> String {
        guard language == .pl else { return category.replacingOccurrences(of: "_", with: " ") }
        return [
            "groceries": "zakupy spożywcze", "eating_out": "jedzenie na mieście", "transport": "transport", "fuel": "paliwo", "shopping": "zakupy",
            "health": "zdrowie", "subscriptions": "subskrypcje", "utilities": "rachunki i telekomunikacja", "housing": "mieszkanie",
            "taxes_insurance": "podatki i ubezpieczenia", "travel": "podróże", "cash": "gotówka", "fees": "opłaty bankowe",
            "interest": "odsetki", "loans": "kredyty i raty", "savings": "oszczędności", "transfers": "przelewy", "income": "wpływy",
            "refund": "zwroty", "other": "inne",
        ][category] ?? category
    }
}

/// Prompts written for a 4B model: short, one job each, explicit about not inventing anything.
enum DocumentPrompts {
    static func languageName(_ language: ConversationLanguage) -> String { language == .pl ? "Polish" : "English" }

    static func mapSystem(_ language: ConversationLanguage) -> String {
        """
        You read one part of a longer document. Write 2 to 4 short sentences in \(languageName(language)) saying what this part contains. \
        Keep every number, date, name, amount and deadline exactly as written. Do not add anything that is not in the text. \
        If the part is only headers or boilerplate, write: nothing important.
        """
    }

    static func reduceSystem(_ language: ConversationLanguage, final: Bool) -> String {
        final
            ? """
            You get notes about the parts of one document. Write a clear summary in \(languageName(language)): first one sentence saying what the document is, \
            then up to 6 bullet points with the key facts (who the parties are, amounts, dates, obligations, deadlines). \
            Use only the notes. Copy numbers and dates exactly. Do not invent anything.
            """
            : """
            You get notes about parts of one document. Merge them into one short note in \(languageName(language)) (4 to 6 sentences). \
            Keep every number, date, name and deadline exactly. Use only the notes.
            """
    }

    static func extractSystem(_ language: ConversationLanguage) -> String {
        """
        Below are the key sentences of a document. Write a clear summary in \(languageName(language)): one sentence saying what the document is and who is involved, \
        then up to 6 short bullet points with the important facts (amounts, dates, deadlines, obligations, penalties). \
        Copy numbers, dates and the roles of people exactly as written. Use only these sentences. Do not invent anything.
        """
    }

    static func narrationSystem(_ language: ConversationLanguage) -> String {
        """
        You explain a bank statement summary to the user in \(languageName(language)), in a friendly and concise way (5 to 8 short lines). \
        Use ONLY the numbers in the data, copied exactly: do not round, convert, add or compute any number. \
        Cover: the period, money in and out, the biggest spending categories, regular payments, and anything unusual (fees, duplicate charges, warnings). \
        If the data contains a WARNING, tell the user that some transactions may be missing.
        """
    }
}

/// Long documents on a small model: split, summarise the most informative parts, merge, and strip anything
/// that mentions a number the document does not contain.
public struct DocumentSummarizer: Sendable {
    public typealias Generate = @Sendable (_ system: String, _ user: String, _ maxTokens: Int) async throws -> String

    public enum Strategy: Sendable {
        /// Pick the sentences with amounts, dates, deadlines and obligations, then one model call to phrase them.
        /// Fast and keeps the facts. The default.
        case extractive
        /// Summarise every part with the model, then merge. Slower, and a 4B model loses numbers on the way.
        case mapReduce
    }

    private let generate: Generate
    private let strategy: Strategy
    /// How many parts the model reads in `.mapReduce`. Each costs one model call, which takes seconds on a phone.
    public let maxParts: Int

    public init(strategy: Strategy = .extractive, maxParts: Int = 12, generate: @escaping Generate) {
        self.strategy = strategy
        self.maxParts = maxParts
        self.generate = generate
    }

    static let keywords = ["kwota", "kwot", "zł", "pln", "termin", "dnia", "umow", "strony", "wypowiedz", "kara", "opłat", "płatn", "zobowiąz",
                           "amount", "date", "shall", "agreement", "deadline", "payment", "terminate", "penalty", "fee", "invoice", "faktur", "total", "razem"]

    /// Keeps the first parts, the last, and the ones with the most numbers, names and legal or money words.
    static func select(_ chunks: [DocumentChunk], cap: Int) -> [DocumentChunk] {
        guard chunks.count > cap else { return chunks }
        func score(_ chunk: DocumentChunk) -> Int {
            let text = chunk.text
            let lower = text.lowercased()
            return text.filter(\.isNumber).count + text.split(separator: " ").filter { $0.first?.isUppercase == true }.count / 2
                + keywords.reduce(0) { $0 + (lower.contains($1) ? 6 : 0) }
        }
        var chosen = Set([chunks[0].id, chunks[1].id, chunks[chunks.count - 1].id])
        for chunk in chunks.sorted(by: { score($0) > score($1) }) where chosen.count < cap { chosen.insert(chunk.id) }
        return chunks.filter { chosen.contains($0.id) }
    }

    public func summarize(
        chunks: [DocumentChunk], language: ConversationLanguage, progress: (@Sendable (Int, Int) -> Void)? = nil
    ) async throws -> String {
        if strategy == .extractive { return try await summarizeExtractively(chunks: chunks, language: language, progress: progress) }
        let parts = Self.select(chunks, cap: maxParts)
        let total = parts.count + (parts.count > 1 ? (parts.count > 8 ? parts.count / 6 + 2 : 1) : 0)
        var done = 0
        var notes: [String] = []
        for part in parts {
            let note = try await generate(DocumentPrompts.mapSystem(language), part.text, 170).trimmingCharacters(in: .whitespacesAndNewlines)
            done += 1; progress?(done, total)
            if !note.isEmpty, !note.lowercased().hasPrefix("nothing important"), !note.lowercased().hasPrefix("nic ważnego") { notes.append(note) }
        }
        guard !notes.isEmpty else { return language == .pl ? "Nie znalazłem w tym dokumencie nic istotnego do streszczenia." : "I found nothing important to summarise in this document." }

        // Merge in groups until one reduce call can read everything.
        while notes.count > 8 {
            var merged: [String] = []
            for group in stride(from: 0, to: notes.count, by: 6) {
                let slice = notes[group..<min(group + 6, notes.count)]
                merged.append(try await generate(DocumentPrompts.reduceSystem(language, final: false), slice.joined(separator: "\n\n"), 220))
                done += 1; progress?(done, total)
            }
            notes = merged
        }
        var summary = notes.count == 1 && parts.count == 1
            ? notes[0]
            : try await generate(DocumentPrompts.reduceSystem(language, final: true), notes.joined(separator: "\n\n"), 360)
        done += 1; progress?(total, total)

        let sources = parts.map(\.text)
        summary = NumberGrounding.removeUngroundedLines(from: summary, sources: sources).trimmingCharacters(in: .whitespacesAndNewlines)
        if chunks.count > parts.count {
            summary += language == .pl
                ? "\n\n(Streszczenie powstało z \(parts.count) najbardziej treściwych z \(chunks.count) fragmentów dokumentu.)"
                : "\n\n(Summarised from the \(parts.count) most informative of \(chunks.count) parts of the document.)"
        }
        return summary
    }
}

extension DocumentSummarizer {
    func summarizeExtractively(chunks: [DocumentChunk], language: ConversationLanguage, progress: (@Sendable (Int, Int) -> Void)?) async throws -> String {
        let brief = ExtractiveBrief.build(from: chunks)
        guard !brief.isEmpty else { return language == .pl ? "Nie znalazłem w tym dokumencie tekstu do streszczenia." : "I found no text to summarise in this document." }
        progress?(0, 1)
        let summary = try await generate(DocumentPrompts.extractSystem(language), brief, 380).trimmingCharacters(in: .whitespacesAndNewlines)
        progress?(1, 1)
        // Anything with a number that is not in the extracts is dropped.
        let cleaned = NumberGrounding.removeUngroundedLines(from: summary, sources: [brief]).trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? brief : cleaned
    }
}

/// Turns the statement digest into a friendly message. If the model keeps getting numbers wrong, the
/// answer is written by code instead, so the user never sees a wrong figure.
public struct StatementNarrator: Sendable {
    public struct Narration: Sendable { public let text: String; public let usedFallback: Bool }

    private let generate: DocumentSummarizer.Generate

    public init(generate: @escaping DocumentSummarizer.Generate) { self.generate = generate }

    public func narrate(_ statement: ParsedStatement, language: ConversationLanguage) async throws -> Narration {
        let digest = StatementAnalyzer.digest(statement)
        var text = try await generate(DocumentPrompts.narrationSystem(language), digest, 420).trimmingCharacters(in: .whitespacesAndNewlines)
        var missing = NumberGrounding.ungrounded(answer: text, sources: [digest])
        if !missing.isEmpty {
            let correction = language == .pl
                ? "Te liczby nie występują w danych: \(missing.joined(separator: ", ")). Napisz jeszcze raz, używając tylko liczb z danych, dokładnie przepisanych."
                : "These numbers are not in the data: \(missing.joined(separator: ", ")). Write it again using only numbers from the data, copied exactly."
            text = try await generate(DocumentPrompts.narrationSystem(language), digest + "\n\n" + correction, 420).trimmingCharacters(in: .whitespacesAndNewlines)
            missing = NumberGrounding.ungrounded(answer: text, sources: [digest])
        }
        if text.isEmpty || !missing.isEmpty { return Narration(text: Self.fallback(statement, language: language), usedFallback: true) }
        return Narration(text: text, usedFallback: false)
    }

    /// Always correct, never fancy.
    public static func fallback(_ s: ParsedStatement, language: ConversationLanguage) -> String { StatementSummaryText.make(s, language: language) }
}

/// The summary shown when a statement is added. Written by code from the parsed numbers: correct Polish and English,
/// no waiting for the model, nothing it can get wrong. The model's job is to answer questions and explain on request.
public enum StatementSummaryText {
    private static func pluralPL(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
        if n == 1 { return one }
        let lastTwo = n % 100, last = n % 10
        return (2...4).contains(last) && !(12...14).contains(lastTwo) ? few : many
    }

    public static func make(_ s: ParsedStatement, language: ConversationLanguage) -> String {
        let pl = language == .pl
        let c = s.currency
        func money(_ minor: Int) -> String { MoneyFormat.text(minor, currency: c) }
        let credits = s.transactions.filter { $0.minorUnits > 0 }
        let debits = s.transactions.filter { $0.minorUnits < 0 }
        let moneyIn = credits.reduce(0) { $0 + $1.minorUnits }
        let moneyOut = -debits.reduce(0) { $0 + $1.minorUnits }
        let period = [s.periodStart, s.periodEnd].compactMap { $0 }.map(DateParsing.isoString).joined(separator: pl ? " – " : " to ")
        let who = s.bank.map { " \($0)" } ?? ""
        let count = s.transactions.count

        var lines: [String] = []
        lines.append(pl ? "Wyciąg\(who), \(period): \(count) \(pluralPL(count, "transakcja", "transakcje", "transakcji"))."
                        : "Statement\(who), \(period): \(count) transactions.")
        lines.append(pl ? "Wpływy: \(money(moneyIn)). Wydatki: \(money(moneyOut)). Bilans: \(MoneyFormat.text(moneyIn - moneyOut, currency: c, signed: true))."
                        : "Money in: \(money(moneyIn)). Money out: \(money(moneyOut)). Net: \(MoneyFormat.text(moneyIn - moneyOut, currency: c, signed: true)).")
        if let opening = s.openingMinor, let closing = s.closingMinor {
            lines.append(pl ? "Saldo początkowe \(money(opening)), końcowe \(money(closing))." : "Balance: \(money(opening)) at the start, \(money(closing)) at the end.")
        } else if let closing = s.closingMinor ?? s.transactions.last?.balanceMinor {
            lines.append(pl ? "Saldo na koniec: \(money(closing))." : "Balance at the end: \(money(closing)).")
        }
        let spending = debits.filter { !["savings", "transfers", "loans"].contains($0.category) }
        let byCategory = Dictionary(grouping: spending, by: \.category).map { ($0.key, -$0.value.reduce(0) { $0 + $1.minorUnits }) }.sorted { $0.1 > $1.1 }.prefix(4)
        if !byCategory.isEmpty {
            lines.append((pl ? "Największe wydatki: " : "Biggest spending: ") + byCategory.map { "\(CategoryNames.label($0.0, language)) \(money($0.1))" }.joined(separator: ", ") + ".")
        }
        let regular = StatementAnalyzer.recurring(s).map { ($0.merchant, $0.typicalMinor) }
            + (StatementAnalyzer.recurring(s).isEmpty ? debits.filter { ["subscriptions", "housing"].contains($0.category) }.map { ($0.merchant, -$0.minorUnits) } : [])
        if !regular.isEmpty {
            lines.append((pl ? "Stałe płatności: " : "Regular payments: ") + regular.prefix(5).map { "\($0.0) \(money($0.1))" }.joined(separator: ", ") + ".")
        }
        var extras: [String] = []
        let fees = -debits.filter { $0.category == "fees" }.reduce(0) { $0 + $1.minorUnits }
        let cash = -debits.filter { $0.category == "cash" }.reduce(0) { $0 + $1.minorUnits }
        if fees > 0 { extras.append((pl ? "opłaty bankowe " : "bank fees ") + money(fees)) }
        if cash > 0 { extras.append((pl ? "wypłaty gotówki " : "cash withdrawals ") + money(cash)) }
        if !extras.isEmpty { lines.append((pl ? "Do uwagi: " : "Worth knowing: ") + extras.joined(separator: ", ") + ".") }
        if s.reconciliation == .mismatch {
            lines.append(pl ? "Uwaga: sumy nie zgadzają się z saldami, więc część transakcji mogła zostać pominięta lub źle odczytana."
                            : "Warning: the totals do not match the balances, so some transactions may be missing or misread.")
        }
        return lines.joined(separator: "\n")
    }
}
