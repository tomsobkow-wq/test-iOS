import AgentCore
import Foundation

public enum CategoryNames {
    public static func label(_ category: String, _ language: ConversationLanguage) -> String {
        guard language == .pl else { return category.replacingOccurrences(of: "_", with: " ") }
        return [
            "groceries": "zakupy spożywcze", "eating_out": "jedzenie na mieście", "transport": "transport", "shopping": "zakupy",
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

    private let generate: Generate
    /// How many parts the model reads. Each costs one model call, which takes seconds on a phone.
    public let maxParts: Int

    public init(maxParts: Int = 12, generate: @escaping Generate) {
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
    public static func fallback(_ s: ParsedStatement, language: ConversationLanguage) -> String {
        let c = s.currency
        let pl = language == .pl
        func money(_ minor: Int) -> String { MoneyFormat.text(minor, currency: c) }
        let credits = s.transactions.filter { $0.minorUnits > 0 }.reduce(0) { $0 + $1.minorUnits }
        let debits = -s.transactions.filter { $0.minorUnits < 0 }.reduce(0) { $0 + $1.minorUnits }
        let period = [s.periodStart, s.periodEnd].compactMap { $0 }.map(DateParsing.isoString).joined(separator: pl ? " – " : " to ")
        var lines = [pl ? "Wyciąg za okres \(period): \(s.transactions.count) transakcji." : "Statement for \(period): \(s.transactions.count) transactions."]
        lines.append(pl ? "Wpływy: \(money(credits)). Wydatki: \(money(debits)). Bilans: \(money(credits - debits))."
                        : "Money in: \(money(credits)). Money out: \(money(debits)). Net: \(money(credits - debits)).")
        let byCategory = Dictionary(grouping: s.transactions.filter { $0.minorUnits < 0 && !["savings", "transfers", "loans"].contains($0.category) }, by: \.category)
            .map { ($0.key, -$0.value.reduce(0) { $0 + $1.minorUnits }) }.sorted { $0.1 > $1.1 }.prefix(3)
        if !byCategory.isEmpty {
            lines.append((pl ? "Największe wydatki: " : "Biggest spending: ") + byCategory.map { "\(CategoryNames.label($0.0, language)) \(money($0.1))" }.joined(separator: ", ") + ".")
        }
        if s.reconciliation == .mismatch {
            lines.append(pl ? "Uwaga: sumy nie zgadzają się z saldami, więc część transakcji mogła zostać pominięta lub źle odczytana." : "Warning: the totals do not match the balances, so some transactions may be missing or misread.")
        }
        return lines.joined(separator: "\n")
    }
}
