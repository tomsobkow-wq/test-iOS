import Foundation

public struct Transaction: Codable, Sendable, Equatable, Identifiable {
    public var id: Int
    public var date: Date
    /// Signed: debits are negative.
    public var minorUnits: Int
    public var currency: String
    /// Everything the bank wrote about it, tidied up.
    public var text: String
    /// Short merchant or counterparty name ("Biedronka", "Netflix", "ZUS").
    public var merchant: String
    public var category: String
    public var balanceMinor: Int?

    public var isDebit: Bool { minorUnits < 0 }
}

public struct ParsedStatement: Codable, Sendable, Equatable {
    public enum Reconciliation: String, Codable, Sendable { case matches, mismatch, unknown }

    public var bank: String?
    public var accountHint: String?
    public var currency: String
    public var transactions: [Transaction]
    public var openingMinor: Int?
    public var closingMinor: Int?
    public var periodStart: Date?
    public var periodEnd: Date?
    public var warnings: [String]
    public var reconciliation: Reconciliation

    /// Opening balance plus every transaction should equal the closing balance. When it does, the
    /// parse is almost certainly complete and correct; when it does not, the digest says so.
    mutating func reconcile() {
        let sum = transactions.reduce(0) { $0 + $1.minorUnits }
        if let opening = openingMinor, let closing = closingMinor {
            reconciliation = abs(opening + sum - closing) <= 1 ? .matches : .mismatch
            if reconciliation == .mismatch {
                let gap = closing - (opening + sum)
                warnings.append("Opening balance plus transactions is \(MoneyFormat.text(abs(gap), currency: currency)) \(gap > 0 ? "short of" : "over") the closing balance, so some transactions may be missing or misread.")
            }
        } else if transactions.allSatisfy({ $0.balanceMinor != nil }), transactions.count > 1 {
            // No stated balances, but a running balance on every row: check the steps.
            var broken = 0
            for pair in zip(transactions, transactions.dropFirst()) {
                if let a = pair.0.balanceMinor, let b = pair.1.balanceMinor, abs(a + pair.1.minorUnits - b) > 1 { broken += 1 }
            }
            reconciliation = broken == 0 ? .matches : .mismatch
            if broken > 0 { warnings.append("\(broken) running-balance steps do not add up, so some rows may be misread.") }
        } else {
            reconciliation = .unknown
        }
    }
}
