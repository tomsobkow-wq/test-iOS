import Foundation

/// One payment. Amounts are integer minor units (grosze, cents) to avoid float drift.
public struct Expense: Identifiable, Codable, Sendable, Equatable {
    public enum Source: String, Codable, Sendable {
        /// Logged by the Apple Pay automation.
        case automatic
        /// Logged because the user told the assistant.
        case manual
    }

    public let id: UUID
    public let date: Date
    public let minorUnits: Int
    public let currency: String
    public let merchant: String
    public let category: String
    public let card: String?
    public let source: Source

    public init(
        id: UUID = UUID(),
        date: Date,
        minorUnits: Int,
        currency: String,
        merchant: String,
        category: String,
        card: String? = nil,
        source: Source
    ) {
        self.id = id
        self.date = date
        self.minorUnits = minorUnits
        self.currency = currency
        self.merchant = merchant
        self.category = category
        self.card = card
        self.source = source
    }
}

public enum AmountParser {
    public struct Amount: Equatable, Sendable {
        public let minorUnits: Int
        public let currency: String
    }

    private static let symbols: [(String, String)] = [
        ("zł", "PLN"), ("zl", "PLN"), ("pln", "PLN"),
        ("€", "EUR"), ("eur", "EUR"),
        ("$", "USD"), ("usd", "USD"),
        ("£", "GBP"), ("gbp", "GBP"),
        ("chf", "CHF"), ("czk", "CZK"), ("kč", "CZK"),
    ]

    /// Understands "12,50 zł", "PLN 12.50", "€9.99", "1 234,50", "1.234,50 zł", "-45".
    public static func parse(_ raw: String, defaultCurrency: String = "PLN") -> Amount? {
        var text = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        var currency = defaultCurrency
        for (symbol, code) in symbols where text.contains(symbol) {
            currency = code
            text = text.replacingOccurrences(of: symbol, with: "")
        }
        text = text
            .replacingOccurrences(of: "\u{00A0}", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "+", with: "")
        guard !text.isEmpty, text.allSatisfy({ $0.isNumber || $0 == "," || $0 == "." }) else { return nil }

        // The last separator is the decimal one if 1–2 digits follow it; the rest group thousands.
        let lastSeparator = text.lastIndex(where: { $0 == "," || $0 == "." })
        var whole = text
        var fraction = ""
        if let index = lastSeparator {
            let after = text[text.index(after: index)...]
            if after.count <= 2, !after.isEmpty {
                whole = String(text[..<index])
                fraction = String(after)
            }
        }
        whole = whole.filter(\.isNumber)
        guard let wholeValue = Int(whole.isEmpty ? "0" : whole) else { return nil }
        let cents = Int((fraction + "00").prefix(2)) ?? 0
        let (product, overflow) = wholeValue.multipliedReportingOverflow(by: 100)
        guard !overflow else { return nil }
        return Amount(minorUnits: product + cents, currency: currency)
    }

    public static func format(_ minorUnits: Int, currency: String) -> String {
        let sign = minorUnits < 0 ? "-" : ""
        let absolute = abs(minorUnits)
        return String(format: "%@%d.%02d %@", sign, absolute / 100, absolute % 100, currency)
    }
}

public enum ExpenseCategorizer {
    public static let categories = [
        "groceries", "eating_out", "transport", "shopping", "health",
        "subscriptions", "travel", "home", "other",
    ]

    private static let keywords: [(String, [String])] = [
        ("groceries", ["biedronka", "lidl", "żabka", "zabka", "carrefour", "auchan", "kaufland", "frisco", "netto", "dino", "stokrotka", "delikatesy", "spar", "aldi", "tesco"]),
        ("eating_out", ["mcdonald", "kfc", "burger", "starbucks", "pyszne", "wolt", "glovo", "pizz", "restaur", "cafe", "kawiarn", "bistro", "sushi", "uber eats", "costa"]),
        ("transport", ["uber", "bolt", "orlen", "bp ", "shell", "circle k", "moya", "jakdojade", "ztm", "koleo", "pkp", "mpk", "parking", "taxi", "freenow"]),
        ("health", ["apteka", "dr.max", "doz", "rossmann", "hebe", "medicover", "lux med", "znanylekarz", "pharmacy", "clinic"]),
        ("subscriptions", ["netflix", "spotify", "youtube", "hbo", "disney", "apple.com", "icloud", "google one", "canva", "openai", "anthropic", "audible", "storytel"]),
        ("travel", ["ryanair", "wizz", "lot polish", "booking.com", "airbnb", "expedia", "hotel", "lufthansa", "easyjet"]),
        ("home", ["ikea", "leroy", "castorama", "obi", "media markt", "mediamarkt", "rtv euro", "neonet", "jysk"]),
        ("shopping", ["allegro", "zalando", "amazon", "empik", "reserved", "h&m", "zara", "decathlon", "vinted", "olx", "temu", "aliexpress", "ccc", "sinsay"]),
    ]

    public static func category(forMerchant merchant: String) -> String {
        let lower = merchant.lowercased()
        for (category, words) in keywords where words.contains(where: { lower.contains($0) }) {
            return category
        }
        return "other"
    }
}

/// Named time windows the assistant can ask for. Weeks start on Monday.
public enum SpendingPeriod: String, CaseIterable, Sendable {
    case today, yesterday
    case thisWeek = "this_week"
    case lastWeek = "last_week"
    case thisMonth = "this_month"
    case lastMonth = "last_month"
    case last7Days = "last_7_days"
    case last30Days = "last_30_days"
    case thisYear = "this_year"

    public func interval(now: Date, calendar: Calendar) -> DateInterval {
        var cal = calendar
        cal.firstWeekday = 2
        let startOfToday = cal.startOfDay(for: now)
        func interval(_ start: Date, _ end: Date) -> DateInterval { DateInterval(start: start, end: end) }
        switch self {
        case .today:
            return interval(startOfToday, cal.date(byAdding: .day, value: 1, to: startOfToday)!)
        case .yesterday:
            return interval(cal.date(byAdding: .day, value: -1, to: startOfToday)!, startOfToday)
        case .thisWeek:
            let start = cal.dateInterval(of: .weekOfYear, for: now)!.start
            return interval(start, cal.date(byAdding: .day, value: 1, to: startOfToday)!)
        case .lastWeek:
            let thisStart = cal.dateInterval(of: .weekOfYear, for: now)!.start
            return interval(cal.date(byAdding: .weekOfYear, value: -1, to: thisStart)!, thisStart)
        case .thisMonth:
            let start = cal.dateInterval(of: .month, for: now)!.start
            return interval(start, cal.date(byAdding: .day, value: 1, to: startOfToday)!)
        case .lastMonth:
            let thisStart = cal.dateInterval(of: .month, for: now)!.start
            return interval(cal.date(byAdding: .month, value: -1, to: thisStart)!, thisStart)
        case .last7Days:
            return interval(cal.date(byAdding: .day, value: -6, to: startOfToday)!, cal.date(byAdding: .day, value: 1, to: startOfToday)!)
        case .last30Days:
            return interval(cal.date(byAdding: .day, value: -29, to: startOfToday)!, cal.date(byAdding: .day, value: 1, to: startOfToday)!)
        case .thisYear:
            let start = cal.dateInterval(of: .year, for: now)!.start
            return interval(start, cal.date(byAdding: .day, value: 1, to: startOfToday)!)
        }
    }
}

public struct SpendingSummary: Sendable, Equatable {
    public struct CategoryTotal: Sendable, Equatable {
        public let category: String
        public let minorUnits: Int
        public let count: Int
    }

    public let currency: String
    public let totalMinorUnits: Int
    public let count: Int
    public let byCategory: [CategoryTotal]
    public let topMerchants: [String]
}

/// Passive spending log, stored on the device. Nothing is recorded until the
/// user turns tracking on.
public actor SpendingStore {
    private struct Snapshot: Codable {
        var enabled: Bool
        var expenses: [Expense]
    }

    private let fileURL: URL?
    private var snapshot: Snapshot

    /// Pass `nil` for an in-memory store (tests).
    public init(fileURL: URL?) {
        self.fileURL = fileURL
        if let fileURL, let data = try? Data(contentsOf: fileURL),
           let loaded = try? JSONDecoder().decode(Snapshot.self, from: data) {
            snapshot = loaded
        } else {
            snapshot = Snapshot(enabled: false, expenses: [])
        }
    }

    public var isTrackingEnabled: Bool { snapshot.enabled }
    public var allExpenses: [Expense] { snapshot.expenses }

    public func setTracking(enabled: Bool) {
        snapshot.enabled = enabled
        save()
    }

    public enum AddResult: Equatable, Sendable {
        case added(Expense)
        case trackingOff
        /// The same payment arrived twice in a row (automations can double-fire).
        case duplicate
    }

    /// Records a payment. Automatic entries are ignored while tracking is off;
    /// manual ones ("I spent 20 zł on lunch") are an explicit request and always saved.
    @discardableResult
    public func add(_ expense: Expense) -> AddResult {
        if expense.source == .automatic, !snapshot.enabled { return .trackingOff }
        let duplicate = snapshot.expenses.contains {
            $0.source == expense.source
                && $0.merchant == expense.merchant
                && $0.minorUnits == expense.minorUnits
                && $0.currency == expense.currency
                && $0.card == expense.card
                && abs($0.date.timeIntervalSince(expense.date)) < 60
        }
        if duplicate { return .duplicate }
        snapshot.expenses.append(expense)
        save()
        return .added(expense)
    }

    public func summaries(in interval: DateInterval, category: String? = nil) -> [SpendingSummary] {
        let matching = snapshot.expenses.filter {
            interval.start <= $0.date && $0.date < interval.end
                && (category == nil || $0.category == category)
        }
        return Dictionary(grouping: matching, by: \.currency).map { currency, items in
            let byCategory = Dictionary(grouping: items, by: \.category)
                .map { SpendingSummary.CategoryTotal(
                    category: $0.key,
                    minorUnits: $0.value.reduce(0) { $0 + $1.minorUnits },
                    count: $0.value.count
                ) }
                .sorted { $0.minorUnits > $1.minorUnits }
            let merchants = Dictionary(grouping: items, by: \.merchant)
                .map { ($0.key, $0.value.reduce(0) { $0 + $1.minorUnits }) }
                .sorted { $0.1 > $1.1 }
                .prefix(3)
                .map(\.0)
            return SpendingSummary(
                currency: currency,
                totalMinorUnits: items.reduce(0) { $0 + $1.minorUnits },
                count: items.count,
                byCategory: byCategory,
                topMerchants: Array(merchants)
            )
        }
        .sorted { $0.currency < $1.currency }
    }

    public func deleteAll() {
        snapshot.expenses = []
        save()
    }

    private func save() {
        guard let fileURL, let data = try? JSONEncoder().encode(snapshot) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
