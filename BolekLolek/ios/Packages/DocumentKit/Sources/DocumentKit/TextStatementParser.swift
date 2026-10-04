import Foundation

/// Reads a statement from plain text, for example what PDFKit or OCR pulled out of a PDF. There are no
/// columns to rely on, so it finds each transaction by its leading date, takes the money amounts from the
/// end of the entry, and decides debit or credit from the running balance whenever the statement has one.
public enum TextStatementParser {
    private static let openingKeys = ["saldo poczatkowe", "saldo otwarcia", "saldo na poczatek", "saldo z poprzedniego", "opening balance",
                                      "balance brought forward", "balance b/f", "previous balance", "starting balance", "beginning balance"]
    private static let closingKeys = ["saldo koncowe", "saldo zamkniecia", "saldo na koniec", "saldo biezace", "closing balance",
                                      "balance carried forward", "balance c/f", "ending balance", "new balance"]
    private static let noiseKeys = ["strona ", "page ", " of ", "wyciag", "statement", "saldo", "balance", "razem", "suma", "total",
                                    "podsumowanie", "summary", "data operacji", "date description", "opis operacji", "www.", "infolinia"]
    private static let debitWords = ["obciazenie", "platnosc", "zakup", "wyplata", "wychodzacy", "oplata", "prowizja", "splata", "zlecenie stale",
                                     "polecenie zaplaty", "card payment", "purchase", "withdrawal", "fee", "direct debit", "standing order", "payment to", "atm"]
    private static let creditWords = ["uznanie", "wplyw", "wplata", "przychodzacy", "zwrot", "odsetki", "wynagrodzenie", "deposit", "credit",
                                      "salary", "refund", "interest", "payment from", "transfer from", "received", "bank giro credit"]

    private static let moneyRegex = try! NSRegularExpression(
        pattern: #"[-+−–]?\(?\d{1,3}(?:[  .,']\d{3})*[.,]\d{2}\)?(?:\s?(?:CR|DR)\b)?-?|[-+−–]?\(?\d+[.,]\d{2}\)?(?:\s?(?:CR|DR)\b)?-?"#
    )
    private static let currencyWords = try! NSRegularExpression(pattern: #"(?i)\b(PLN|EUR|GBP|USD|CHF|zł|zl)\b|[€$£]"#)

    public static func parse(_ text: String, bankHint: (name: String, dayOrder: DayOrder)? = nil) -> ParsedStatement? {
        let lines = text.components(separatedBy: .newlines).map(\.collapsedWhitespace).filter { !$0.isEmpty }
        guard lines.count >= 4 else { return nil }

        // Statement-level facts.
        var opening: Int?, closing: Int?
        var periodDates: [Date] = []
        let sampleDates = lines.compactMap { line -> String? in
            line.range(of: #"^\d{1,2}[./-]\d{1,2}[./-]\d{2,4}"#, options: .regularExpression).map { String(line[$0]) }
        }
        let order = DateParsing.detectOrder(sampleDates, hint: bankHint?.dayOrder ?? .dayFirst)
        for (index, line) in lines.enumerated() {
            let folded = line.folded
            if opening == nil, openingKeys.contains(where: { folded.contains($0) }) { opening = lastMoney(in: line) ?? lines[safe: index + 1].flatMap(lastMoney) }
            if closing == nil, closingKeys.contains(where: { folded.contains($0) }) { closing = lastMoney(in: line) ?? lines[safe: index + 1].flatMap(lastMoney) }
            if periodDates.isEmpty, ["okres", "period", "from ", "za okres", "od "].contains(where: { folded.contains($0) }) {
                periodDates = allDates(in: line, order: order)
            }
        }
        let defaultYear = periodDates.last.map { DateParsing.parts($0).year } ?? yearMentioned(in: text) ?? Calendar.current.component(.year, from: Date())

        // Which kind of date do entries start with?
        func starts(_ line: String, allowShort: Bool) -> (date: Date, length: Int)? {
            guard let found = DateParsing.leadingDate(in: line, order: order, defaultYear: allowShort ? defaultYear : nil) else { return nil }
            let rest = line.dropFirst(found.length).trimmingCharacters(in: .whitespaces)
            // A short date like "12.50" is really an amount unless words or another date follow.
            if allowShort, rest.isEmpty || rest.first?.isNumber == true && DateParsing.leadingDate(in: rest, order: order, defaultYear: defaultYear) == nil { return nil }
            return found
        }
        let fullDateLines = lines.filter { starts($0, allowShort: false) != nil }.count
        let allowShort = fullDateLines < 3
        guard lines.filter({ starts($0, allowShort: allowShort) != nil }).count >= 3 else { return nil }

        // Group lines into entries.
        var blocks: [[String]] = []
        for line in lines {
            if starts(line, allowShort: allowShort) != nil { blocks.append([line]); continue }
            guard !blocks.isEmpty else { continue }
            let folded = " " + line.folded + " "
            if noiseKeys.contains(where: { folded.contains($0) }) { continue }
            blocks[blocks.count - 1].append(line)
        }

        struct Entry { var date: Date; var text: String; var tokens: [(value: SignedMoney.Parsed, range: Range<String.Index>)] }
        var entries: [Entry] = []
        var lastMonth = 0
        var yearOffset = 0
        for block in blocks {
            var joined = block.joined(separator: " ")
            guard var found = starts(joined, allowShort: allowShort) else { continue }
            var date = found.date
            if allowShort, !(joined.range(of: #"^\S+\s+\S+\s+\d{4}"#, options: .regularExpression) != nil) {
                // Short dates: roll the year over when months wrap (Dec -> Jan).
                let month = DateParsing.parts(date).month
                if lastMonth - month > 6 { yearOffset += 1 }
                lastMonth = month
                let p = DateParsing.parts(date)
                date = DateParsing.date(year: p.year + yearOffset, month: p.month, day: p.day) ?? date
            }
            joined = String(joined.dropFirst(found.length)).trimmingCharacters(in: .whitespaces)
            // A second date (value date) may follow the first.
            if let second = starts(joined, allowShort: allowShort) { joined = String(joined.dropFirst(second.length)).trimmingCharacters(in: .whitespaces); found = second }

            let matches = moneyRegex.matches(in: joined, range: NSRange(joined.startIndex..., in: joined))
            let tokens = matches.compactMap { match -> (SignedMoney.Parsed, Range<String.Index>)? in
                guard let range = Range(match.range, in: joined), let value = SignedMoney.parse(String(joined[range])) else { return nil }
                return (value, range)
            }
            guard !tokens.isEmpty else { continue }
            entries.append(Entry(date: date, text: joined, tokens: tokens.map { ($0.0, $0.1) }))
        }
        guard entries.count >= 3 else { return nil }

        // Does the statement carry a running balance? Then most entries end in two amounts.
        let counts = Dictionary(grouping: entries.map { min($0.tokens.count, 2) }, by: { $0 })
        let hasBalance = (counts[2]?.count ?? 0) > (counts[1]?.count ?? 0)

        // Process oldest first, whichever way the statement lists them.
        if let first = entries.first, let last = entries.last, first.date > last.date { entries.reverse() }

        var transactions: [Transaction] = []
        var previousBalance = opening
        var guessed = 0
        let currency = statementCurrency(text)
        for entry in entries {
            let tokens = entry.tokens
            let amountToken = hasBalance && tokens.count >= 2 ? tokens[tokens.count - 2] : tokens[tokens.count - 1]
            let balanceToken = hasBalance && tokens.count >= 2 ? tokens[tokens.count - 1] : nil
            var magnitude = abs(amountToken.value.minorUnits)
            var signed = amountToken.value.minorUnits

            // The text of the entry without amounts and currency symbols.
            var description = entry.text
            for token in tokens.sorted(by: { $0.range.lowerBound > $1.range.lowerBound }) { description.removeSubrange(token.range) }
            description = currencyWords.stringByReplacingMatches(in: description, range: NSRange(description.startIndex..., in: description), withTemplate: " ").collapsedWhitespace

            if !amountToken.value.hadExplicitSign {
                if let balance = balanceToken?.value.minorUnits, let previous = previousBalance, abs(abs(balance - previous) - magnitude) <= 1 {
                    signed = balance - previous >= 0 ? magnitude : -magnitude
                } else {
                    let folded = " " + description.folded + " "
                    let debit = debitWords.filter { folded.contains($0) }.count
                    let credit = creditWords.filter { folded.contains($0) }.count
                    if credit > debit { signed = magnitude } else { signed = -magnitude; if debit == 0 { guessed += 1 } }
                }
            }
            magnitude = abs(signed)
            let known = Merchants.knownMerchant(in: description)
            transactions.append(Transaction(
                id: transactions.count, date: entry.date, minorUnits: signed, currency: currency, text: description,
                merchant: known?.name ?? Merchants.cleanName(description),
                category: Merchants.category(for: description, merchantCategory: known?.category, minorUnits: signed),
                balanceMinor: balanceToken?.value.minorUnits
            ))
            if let balance = balanceToken?.value.minorUnits { previousBalance = balance } else if let previous = previousBalance { previousBalance = previous + signed }
        }

        var statement = ParsedStatement(
            bank: bankHint?.name, accountHint: accountHint(in: text), currency: currency, transactions: transactions,
            openingMinor: opening, closingMinor: closing,
            periodStart: periodDates.first ?? transactions.first?.date, periodEnd: periodDates.dropFirst().first ?? transactions.last?.date,
            warnings: [], reconciliation: .unknown
        )
        if guessed > 0 { statement.warnings.append("For \(guessed) transactions the statement did not say debit or credit, so they were counted as payments.") }
        statement.reconcile()
        return statement
    }

    // MARK: Helpers

    private static func lastMoney(in line: String) -> Int? {
        let matches = moneyRegex.matches(in: line, range: NSRange(line.startIndex..., in: line))
        guard let last = matches.last, let range = Range(last.range, in: line) else { return nil }
        return SignedMoney.parse(String(line[range]))?.minorUnits
    }

    private static func allDates(in line: String, order: DayOrder) -> [Date] {
        var found: [Date] = []
        var rest = Substring(line)
        while !rest.isEmpty {
            if let match = DateParsing.leadingDate(in: String(rest), order: order, defaultYear: nil) {
                found.append(match.date)
                rest = rest.dropFirst(match.length)
            } else { rest = rest.dropFirst() }
        }
        return found
    }

    private static func yearMentioned(in text: String) -> Int? {
        guard let range = text.range(of: #"\b20\d{2}\b"#, options: .regularExpression) else { return nil }
        return Int(text[range])
    }

    private static func statementCurrency(_ text: String) -> String {
        let folded = text.folded
        let candidates: [(String, [String])] = [("PLN", ["pln", " zl"]), ("EUR", ["eur", "€"]), ("GBP", ["gbp", "£"]), ("USD", ["usd", "$"])]
        let scores = candidates.map { code, needles in (code, needles.reduce(0) { $0 + folded.components(separatedBy: $1).count - 1 }) }
        return scores.max { $0.1 < $1.1 }.flatMap { $0.1 > 0 ? $0.0 : nil } ?? "PLN"
    }

    private static func accountHint(in text: String) -> String? {
        guard let range = text.range(of: #"\b[A-Z]{2}\s?\d{2}(?:\s?\d{4}){5,7}\b|\b\d{2}(?:\s?\d{4}){6}\b"#, options: .regularExpression) else { return nil }
        let digits = text[range].filter(\.isNumber)
        return "…" + digits.suffix(4)
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

/// One entry point: works out whether the text is a CSV export or text from a PDF, and parses it.
public enum StatementParser {
    public static func parse(_ text: String) -> ParsedStatement? {
        let bank = BankDetector.detect(text)
        if let csv = CSVStatementParser.parse(text, bankHint: bank), csv.transactions.count >= 3 { return csv }
        return TextStatementParser.parse(text, bankHint: bank)
    }
}
