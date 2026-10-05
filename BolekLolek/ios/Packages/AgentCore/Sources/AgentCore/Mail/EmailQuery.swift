import Foundation

public enum EmailWhen: String, Sendable, Equatable, CaseIterable {
    case any, today, yesterday
    case thisWeek = "this_week"
    case last7Days = "last_7_days"
    case last30Days = "last_30_days"
}

/// What the user asked for, in structured form. Code turns it into an exact Gmail search so a small model never has to.
public struct EmailQuerySpec: Sendable, Equatable {
    public var when: EmailWhen = .any
    public var unread = false
    public var from: String?
    public var text: String?
    /// Advanced Gmail syntax passed through untouched.
    public var raw: String?
    public var account: String?

    public init(when: EmailWhen = .any, unread: Bool = false, from: String? = nil, text: String? = nil, raw: String? = nil, account: String? = nil) {
        self.when = when
        self.unread = unread
        self.from = from
        self.text = text
        self.raw = raw
        self.account = account
    }
}

public struct EmailQueryBuilder: Sendable {
    public let clock: ToolClock

    public init(clock: ToolClock = ToolClock()) { self.clock = clock }

    /// Time ranges use exact epoch seconds in the user's own time zone, so "today" means today where they are.
    public func range(for when: EmailWhen) -> (start: Date, end: Date?)? {
        let calendar = clock.calendar
        let now = clock.now()
        let startOfToday = calendar.startOfDay(for: now)
        switch when {
        case .any: return nil
        case .today: return (startOfToday, nil)
        case .yesterday: return (calendar.date(byAdding: .day, value: -1, to: startOfToday)!, startOfToday)
        case .thisWeek: return (calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? startOfToday, nil)
        case .last7Days: return (calendar.date(byAdding: .day, value: -6, to: startOfToday)!, nil)
        case .last30Days: return (calendar.date(byAdding: .day, value: -29, to: startOfToday)!, nil)
        }
    }

    public func gmailQuery(_ spec: EmailQuerySpec) -> String {
        if let raw = spec.raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty, spec.when == .any, !spec.unread, spec.from == nil, spec.text == nil {
            return raw
        }
        var parts = ["in:inbox"]
        if let range = range(for: spec.when) {
            parts.append("after:\(Int(range.start.timeIntervalSince1970))")
            if let end = range.end { parts.append("before:\(Int(end.timeIntervalSince1970))") }
        }
        if spec.unread { parts.append("is:unread") }
        if let from = Self.safe(spec.from) { parts.append("from:(\(from))") }
        if let text = Self.safe(spec.text) { parts.append(text) }
        if let raw = Self.safe(spec.raw) { parts.append(raw) }
        return parts.joined(separator: " ")
    }

    /// Plain words for the answer ("today, unread, from Delta"), so the model can say what was searched.
    public func describe(_ spec: EmailQuerySpec) -> String {
        var parts: [String] = []
        switch spec.when {
        case .any: break
        case .today: parts.append("today")
        case .yesterday: parts.append("yesterday")
        case .thisWeek: parts.append("this week")
        case .last7Days: parts.append("the last 7 days")
        case .last30Days: parts.append("the last 30 days")
        }
        if spec.unread { parts.append("unread only") }
        if let from = Self.safe(spec.from) { parts.append("from \(from)") }
        if let text = Self.safe(spec.text) { parts.append("matching \"\(text)\"") }
        if let raw = Self.safe(spec.raw) { parts.append("query \"\(raw)\"") }
        return parts.isEmpty ? "latest inbox mail" : parts.joined(separator: ", ")
    }

    private static func safe(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return String(value.prefix(120))
    }
}
