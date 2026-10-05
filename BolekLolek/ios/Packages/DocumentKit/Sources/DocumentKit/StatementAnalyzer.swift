import Foundation

public struct StatementQuery: Sendable {
    public enum Direction: String, Sendable { case money_in = "in", money_out = "out", both }
    public enum Sort: String, Sendable { case date, amount }

    public var from: Date?
    public var to: Date?
    public var category: String?
    public var merchant: String?
    public var search: String?
    public var direction: Direction = .both
    /// Absolute amounts, in minor units.
    public var minAmount: Int?
    public var maxAmount: Int?
    public var sort: Sort = .date
    public var limit = 15

    public init() {}
}

public struct RecurringPayment: Sendable, Equatable {
    public let merchant: String
    public let typicalMinor: Int
    public let every: String
    public let count: Int
}

/// Everything numeric is computed here, in code. The model only ever reads the results.
public enum StatementAnalyzer {
    /// Categories that move money around rather than spend it.
    private static let notSpending: Set<String> = ["savings", "transfers", "loans"]

    public static func filter(_ statement: ParsedStatement, _ query: StatementQuery) -> [Transaction] {
        let merchant = query.merchant?.folded
        let search = query.search?.folded
        var rows = statement.transactions.filter { tx in
            if let from = query.from, tx.date < from { return false }
            if let to = query.to, tx.date > to.addingTimeInterval(86_399) { return false }
            if let category = query.category, tx.category != category { return false }
            if let merchant, !(tx.merchant.folded.contains(merchant) || tx.text.folded.contains(merchant)) { return false }
            if let search, !(tx.text.folded.contains(search) || tx.merchant.folded.contains(search)) { return false }
            switch query.direction {
            case .money_in: if tx.minorUnits <= 0 { return false }
            case .money_out: if tx.minorUnits >= 0 { return false }
            case .both: break
            }
            if let min = query.minAmount, abs(tx.minorUnits) < min { return false }
            if let max = query.maxAmount, abs(tx.minorUnits) > max { return false }
            return true
        }
        if query.sort == .amount { rows.sort { abs($0.minorUnits) > abs($1.minorUnits) } }
        return rows
    }

    public static func recurring(_ statement: ParsedStatement) -> [RecurringPayment] {
        var found: [RecurringPayment] = []
        let debits = statement.transactions.filter(\.isDebit)
        for (merchant, items) in Dictionary(grouping: debits, by: \.merchant) where items.count >= 2 {
            let sorted = items.sorted { $0.date < $1.date }
            let amounts = sorted.map { abs($0.minorUnits) }.sorted()
            let median = amounts[amounts.count / 2]
            guard amounts.allSatisfy({ abs($0 - median) <= max(100, median * 15 / 100) }) else { continue }
            let gaps = zip(sorted, sorted.dropFirst()).map { $1.date.timeIntervalSince($0.date) / 86_400 }
            let average = gaps.reduce(0, +) / Double(gaps.count)
            let every: String
            switch average {
            case 5...9: every = "weekly"
            case 26...35: every = "monthly"
            case 85...100: every = "quarterly"
            case 350...380: every = "yearly"
            default: continue
            }
            found.append(RecurringPayment(merchant: merchant, typicalMinor: median, every: every, count: items.count))
        }
        return found.sorted { $0.typicalMinor > $1.typicalMinor }
    }

    // MARK: Digest

    /// A compact, factual summary (about 400-600 tokens) that a small model can narrate without doing any arithmetic.
    public static func digest(_ s: ParsedStatement, maxItems: Int = 5) -> String {
        let c = s.currency
        func money(_ minor: Int, signed: Bool = false) -> String { MoneyFormat.text(minor, currency: c, signed: signed) }
        func day(_ date: Date) -> String { DateParsing.isoString(date) }

        let credits = s.transactions.filter { $0.minorUnits > 0 }
        let debits = s.transactions.filter { $0.minorUnits < 0 }
        let moneyIn = credits.reduce(0) { $0 + $1.minorUnits }
        let moneyOut = -debits.reduce(0) { $0 + $1.minorUnits }
        let spendingTx = debits.filter { !notSpending.contains($0.category) }
        let spending = -spendingTx.reduce(0) { $0 + $1.minorUnits }

        var lines: [String] = []
        let who = [s.bank, s.accountHint].compactMap { $0 }.joined(separator: " ")
        let period = [s.periodStart, s.periodEnd].compactMap { $0 }.map(day).joined(separator: " to ")
        lines.append("Statement\(who.isEmpty ? "" : " " + who), \(period), \(s.transactions.count) transactions, currency \(c).")
        if let opening = s.openingMinor, let closing = s.closingMinor {
            lines.append("Balance: opening \(money(opening)), closing \(money(closing)).")
        } else if let closing = s.closingMinor ?? s.transactions.last?.balanceMinor {
            lines.append("Balance at the end: \(money(closing)).")
        }
        switch s.reconciliation {
        case .matches: lines.append("Check: opening balance plus all transactions equals the closing balance, so nothing is missing.")
        case .mismatch: lines.append("WARNING: the transactions do not add up to the balances, so some may be missing or misread. Say this to the user.")
        case .unknown: break
        }
        lines.append("Money in: \(money(moneyIn)) (\(credits.count) transactions). Money out: \(money(moneyOut)) (\(debits.count)). Net: \(money(moneyIn - moneyOut, signed: true)).")
        if spending != moneyOut { lines.append("Spending, not counting savings, transfers and loan repayments: \(money(spending)).") }

        // Spending by category.
        let byCategory = Dictionary(grouping: spendingTx, by: \.category)
            .map { (category: $0.key, total: -$0.value.reduce(0) { $0 + $1.minorUnits }, count: $0.value.count) }
            .sorted { $0.total > $1.total }
        if !byCategory.isEmpty {
            let parts = byCategory.prefix(8).map { "\($0.category) \(money($0.total)) (\(spending > 0 ? $0.total * 100 / spending : 0)%, \($0.count)x)" }
            lines.append("Spending by category: " + parts.joined(separator: "; ") + ".")
        }
        // Top merchants.
        let byMerchant = Dictionary(grouping: spendingTx, by: \.merchant)
            .map { (merchant: $0.key, total: -$0.value.reduce(0) { $0 + $1.minorUnits }, count: $0.value.count) }
            .sorted { $0.total > $1.total }
        if !byMerchant.isEmpty {
            lines.append("Top merchants: " + byMerchant.prefix(maxItems).map { "\($0.merchant) \(money($0.total)) (\($0.count)x)" }.joined(separator: "; ") + ".")
        }
        let largestOut = debits.sorted { $0.minorUnits < $1.minorUnits }.prefix(3)
        if !largestOut.isEmpty {
            lines.append("Largest payments: " + largestOut.map { "\(day($0.date)) \($0.merchant) \(money(-$0.minorUnits))" }.joined(separator: "; ") + ".")
        }
        let largestIn = credits.sorted { $0.minorUnits > $1.minorUnits }.prefix(2)
        if !largestIn.isEmpty {
            lines.append("Largest money in: " + largestIn.map { "\(day($0.date)) \($0.merchant) \(money($0.minorUnits))" }.joined(separator: "; ") + ".")
        }

        // Regular payments: real repeats when the statement spans months, otherwise the kinds of payment that usually repeat.
        let repeats = recurring(s)
        if !repeats.isEmpty {
            lines.append("Recurring: " + repeats.prefix(maxItems).map { "\($0.merchant) about \(money($0.typicalMinor)) \($0.every) (\($0.count)x)" }.joined(separator: "; ") + ".")
        } else {
            let regular = debits.filter { ["subscriptions", "utilities", "housing", "loans", "taxes_insurance"].contains($0.category) }
            if !regular.isEmpty {
                lines.append("Regular-looking payments (subscriptions, bills, rent): " + regular.prefix(maxItems + 3).map { "\($0.merchant) \(money(-$0.minorUnits))" }.joined(separator: "; ") + ".")
            }
        }

        let fees = -debits.filter { $0.category == "fees" }.reduce(0) { $0 + $1.minorUnits }
        let cash = -debits.filter { $0.category == "cash" }.reduce(0) { $0 + $1.minorUnits }
        var extras: [String] = []
        if fees > 0 { extras.append("bank fees \(money(fees))") }
        if cash > 0 { extras.append("cash withdrawals \(money(cash))") }
        if !extras.isEmpty { lines.append("Also: " + extras.joined(separator: ", ") + ".") }

        // Same day, merchant and amount twice.
        let twins = Dictionary(grouping: debits, by: { "\(day($0.date))|\($0.merchant)|\($0.minorUnits)" }).filter { $0.value.count > 1 }
        if !twins.isEmpty {
            lines.append("Possible duplicate charges: " + twins.values.prefix(3).map { "\(day($0[0].date)) \($0[0].merchant) \(money(-$0[0].minorUnits)) x\($0.count)" }.joined(separator: "; ") + ".")
        }

        // Several months: one line per month.
        let months = Dictionary(grouping: s.transactions, by: { DateParsing.monthKey($0.date) })
        if months.count > 1 {
            let rows = months.keys.sorted().map { key -> String in
                let items = months[key]!
                let inn = items.filter { $0.minorUnits > 0 }.reduce(0) { $0 + $1.minorUnits }
                let out = -items.filter { $0.minorUnits < 0 }.reduce(0) { $0 + $1.minorUnits }
                return "\(key): in \(money(inn)), out \(money(out))"
            }
            lines.append("By month: " + rows.joined(separator: "; ") + ".")
        }
        for warning in s.warnings where !warning.contains("do not add up") && !warning.contains("short of") && !warning.contains("over the closing") {
            lines.append("Note: \(warning)")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: Query and breakdown results, for the tools

    public static func render(_ rows: [Transaction], of statement: ParsedStatement, limit: Int) -> String {
        let c = statement.currency
        guard !rows.isEmpty else { return "No transactions match." }
        let out = -rows.filter { $0.minorUnits < 0 }.reduce(0) { $0 + $1.minorUnits }
        let inn = rows.filter { $0.minorUnits > 0 }.reduce(0) { $0 + $1.minorUnits }
        var lines = rows.prefix(limit).map { tx in
            "\(DateParsing.isoString(tx.date)) | \(MoneyFormat.text(tx.minorUnits, currency: c)) | \(tx.merchant) | \(tx.category) | \(String(tx.text.prefix(70)))"
        }
        lines.append("Matches: \(rows.count) transactions; money out \(MoneyFormat.text(out, currency: c)), money in \(MoneyFormat.text(inn, currency: c))"
            + (rows.count > limit ? " (first \(limit) shown; totals cover all matches)." : "."))
        return lines.joined(separator: "\n")
    }

    public enum GroupBy: String, Sendable { case category, merchant, month }

    public static func breakdown(_ statement: ParsedStatement, by group: GroupBy, query: StatementQuery) -> String {
        let rows = filter(statement, query)
        let c = statement.currency
        guard !rows.isEmpty else { return "No transactions match." }
        let key: (Transaction) -> String = {
            switch group {
            case .category: $0.category
            case .merchant: $0.merchant
            case .month: DateParsing.monthKey($0.date)
            }
        }
        let grouped = Dictionary(grouping: rows, by: key).map { name, items -> (String, Int, Int, Int) in
            (name, -items.filter { $0.minorUnits < 0 }.reduce(0) { $0 + $1.minorUnits }, items.filter { $0.minorUnits > 0 }.reduce(0) { $0 + $1.minorUnits }, items.count)
        }
        let sorted = group == .month ? grouped.sorted { $0.0 < $1.0 } : grouped.sorted { $0.1 + $0.2 > $1.1 + $1.2 }
        var lines = sorted.prefix(12).map { "\($0.0): out \(MoneyFormat.text($0.1, currency: c)), in \(MoneyFormat.text($0.2, currency: c)), \($0.3) transactions" }
        if sorted.count > 12 { lines.append("(+\(sorted.count - 12) more groups)") }
        return lines.joined(separator: "\n")
    }
}
