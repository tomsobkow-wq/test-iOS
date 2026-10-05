import Foundation

/// RFC 4180 reader that works out the delimiter itself (Polish banks use `;`, English ones `,`).
public enum CSVReader {
    public static func rows(_ text: String) -> [[String]] {
        let delimiter = detectDelimiter(text)
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        let chars = Array(text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n"))
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < chars.count, chars[i + 1] == "\"" { field.append("\""); i += 1 } else { inQuotes = false }
                } else { field.append(c) }
            } else if c == "\"" {
                inQuotes = true
            } else if c == delimiter {
                row.append(field); field = ""
            } else if c == "\n" {
                row.append(field); field = ""
                if !(row.count == 1 && row[0].trimmingCharacters(in: .whitespaces).isEmpty) { rows.append(row) }
                row = []
            } else { field.append(c) }
            i += 1
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows.map { $0.map { $0.trimmingCharacters(in: .whitespaces) } }
    }

    static func detectDelimiter(_ text: String) -> Character {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true).prefix(25)
        var best: (Character, Int) = (",", 0)
        for candidate in [";", ",", "\t", "|"] as [Character] {
            // Count outside quotes; a good delimiter appears the same number of times on most lines.
            let counts = lines.map { line -> Int in
                var quoted = false, n = 0
                for c in line { if c == "\"" { quoted.toggle() } else if c == candidate, !quoted { n += 1 } }
                return n
            }.filter { $0 > 0 }
            guard let mode = Dictionary(grouping: counts, by: { $0 }).max(by: { $0.value.count < $1.value.count }) else { continue }
            let score = mode.value.count * 100 + mode.key
            if score > best.1 { best = (candidate, score) }
        }
        return best.0
    }
}

enum ColumnRole: Hashable { case date, valueDate, text, counterparty, amount, debit, credit, balance, currency, type, bankCategory }

enum StatementColumns {
    private static let synonyms: [(ColumnRole, exact: [String], prefix: [String])] = [
        (.date, ["data ksiegowania", "data operacji", "data transakcji", "data", "date", "transaction date", "posted date", "post date",
                 "completed date", "booking date", "data zaksiegowania", "started date", "date started (utc)", "data operacji/waluty"], []),
        (.valueDate, ["data waluty", "value date", "data waluty/ksiegowania"], []),
        (.counterparty, ["dane kontrahenta", "kontrahent", "nazwa kontrahenta", "nadawca / odbiorca", "nadawca/odbiorca", "odbiorca", "payee", "name", "merchant"], []),
        (.text, ["opis operacji", "opis transakcji", "tytul", "tytul operacji", "tresc", "opis", "szczegoly", "description", "details", "memo",
                 "reference", "payment reference", "narrative", "transaction description", "lokalizacja"], []),
        (.amount, ["kwota", "kwota operacji", "amount", "transaction amount", "value", "kwota transakcji"], ["kwota transakcji", "amount ("]),
        (.debit, ["obciazenia", "obciazenie", "winien", "debit", "money out", "paid out", "withdrawals", "debit amount"], []),
        (.credit, ["uznania", "uznanie", "ma", "credit", "money in", "paid in", "deposits", "credit amount"], []),
        (.balance, ["saldo", "balance", "running balance", "saldo po transakcji", "saldo po operacji", "saldo po"], ["saldo po", "balance"]),
        (.currency, ["waluta", "currency"], []),
        (.type, ["typ transakcji", "rodzaj transakcji", "typ operacji", "rodzaj", "type", "operacja", "transaction type"], []),
        (.bankCategory, ["kategoria", "category", "subcategory"], []),
    ]

    static func normalize(_ header: String) -> String {
        header.replacingOccurrences(of: "#", with: "").folded.collapsedWhitespace
    }

    static func role(of header: String) -> ColumnRole? {
        let h = normalize(header)
        guard !h.isEmpty else { return nil }
        for (role, exact, prefix) in synonyms {
            if exact.contains(h) || prefix.contains(where: { h.hasPrefix($0) }) { return role }
        }
        return nil
    }

    /// First row that looks like a header: a date column plus an amount (or debit/credit) column.
    static func findHeader(in rows: [[String]]) -> (index: Int, roles: [Int: ColumnRole])? {
        for (index, row) in rows.prefix(40).enumerated() {
            var roles: [Int: ColumnRole] = [:]
            var seen = Set<ColumnRole>()
            for (column, cell) in row.enumerated() {
                guard let role = role(of: cell) else { continue }
                // Keep the first column for each role, except descriptions, which are joined.
                if seen.contains(role), role != .text, role != .counterparty { continue }
                seen.insert(role)
                roles[column] = role
            }
            let hasDate = seen.contains(.date) || seen.contains(.valueDate)
            let hasMoney = seen.contains(.amount) || seen.contains(.debit) || seen.contains(.credit)
            if hasDate && hasMoney { return (index, roles) }
        }
        return nil
    }
}

public enum CSVStatementParser {
    public static func parse(_ text: String, bankHint: (name: String, dayOrder: DayOrder)? = nil) -> ParsedStatement? {
        let rows = CSVReader.rows(text)
        guard let header = StatementColumns.findHeader(in: rows) else { return nil }
        let roles = header.roles
        func column(_ role: ColumnRole) -> Int? { roles.first { $0.value == role }?.key }
        func columns(_ role: ColumnRole) -> [Int] { roles.filter { $0.value == role }.map(\.key).sorted() }

        let dateColumn = column(.date) ?? column(.valueDate)!
        let body = rows.dropFirst(header.index + 1).filter { $0.count > dateColumn }
        let sampleDates = body.prefix(200).map { $0[dateColumn] }
        let order = DateParsing.detectOrder(sampleDates, hint: bankHint?.dayOrder ?? .dayFirst)

        var transactions: [Transaction] = []
        var currencies: [String: Int] = [:]
        var skipped = 0
        for row in body {
            guard let date = DateParsing.parse(row[dateColumn], order: order) else { skipped += 1; continue }

            var amount: Int?
            var rowCurrency: String?
            if let amountColumn = column(.amount), amountColumn < row.count, let parsed = SignedMoney.parse(row[amountColumn]) {
                amount = parsed.minorUnits
                rowCurrency = parsed.currency
            } else {
                let debit = column(.debit).flatMap { $0 < row.count ? SignedMoney.parse(row[$0]) : nil }
                let credit = column(.credit).flatMap { $0 < row.count ? SignedMoney.parse(row[$0]) : nil }
                if debit != nil || credit != nil { amount = abs(credit?.minorUnits ?? 0) - abs(debit?.minorUnits ?? 0) }
            }
            guard let minor = amount else { skipped += 1; continue }

            let balance = column(.balance).flatMap { $0 < row.count ? SignedMoney.parse(row[$0])?.minorUnits : nil }
            let currencyCell = column(.currency).flatMap { $0 < row.count ? row[$0].uppercased() : nil }
            let currency = [currencyCell, rowCurrency].compactMap { $0 }.first { $0.count == 3 } ?? "PLN"
            currencies[currency, default: 0] += 1

            // Counterparty first, then the title and details: the order Polish statements read naturally.
            let parts = (columns(.counterparty) + columns(.text) + (column(.type).map { [$0] } ?? []))
                .compactMap { $0 < row.count ? row[$0] : nil }
                .map(\.collapsedWhitespace).filter { !$0.isEmpty }
            let combined = parts.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }.joined(separator: " | ")

            let known = Merchants.knownMerchant(in: combined)
            let merchant = known?.name ?? Merchants.cleanName(parts.first ?? combined)
            transactions.append(Transaction(
                id: transactions.count, date: date, minorUnits: minor, currency: currency, text: combined, merchant: merchant,
                category: Merchants.category(for: combined, merchantCategory: known?.category, minorUnits: minor), balanceMinor: balance
            ))
        }
        guard transactions.count >= 2 else { return nil }

        // Exports list newest first or oldest first; analyse oldest first.
        if let first = transactions.first, let last = transactions.last, first.date > last.date { transactions.reverse() }
        transactions = transactions.enumerated().map { var t = $1; t.id = $0; return t }

        let currency = currencies.max { $0.value < $1.value }?.key ?? "PLN"
        var statement = ParsedStatement(
            bank: bankHint?.name, accountHint: nil, currency: currency, transactions: transactions,
            openingMinor: nil, closingMinor: nil, periodStart: transactions.first?.date, periodEnd: transactions.last?.date,
            warnings: skipped > 0 ? ["\(skipped) rows could not be read and were skipped."] : [], reconciliation: .unknown
        )
        // With a running balance, the balance before the first row gives the opening balance.
        if let first = transactions.first, let balance = first.balanceMinor { statement.openingMinor = balance - first.minorUnits }
        if let last = transactions.last, let balance = last.balanceMinor { statement.closingMinor = balance }
        statement.reconcile()
        return statement
    }
}
