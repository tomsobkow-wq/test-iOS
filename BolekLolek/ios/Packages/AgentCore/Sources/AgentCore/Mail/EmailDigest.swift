import Foundation

/// Reads every match (not just the first few), counts them and groups them, so the model gets complete evidence and a
/// true count. Code does the finding and counting; the model writes the answer.
public enum EmailDigest {
    public struct Collected: Sendable {
        public let items: [EmailSummary]
        /// False when the cap stopped the reading and more mail matched.
        public let complete: Bool
        public let failedAccounts: [String]
        public let estimatedTotal: Int
    }

    public static let cap = 120

    public static func collect(from feed: MailFeed, cap: Int = EmailDigest.cap) async throws -> Collected {
        var items: [EmailSummary] = []
        while items.count < cap {
            let batch = try await feed.next(min(25, cap - items.count))
            if batch.isEmpty { break }
            items += batch
        }
        let more = !(await feed.isExhausted)
        return Collected(items: items, complete: !more, failedAccounts: await feed.failedAccounts, estimatedTotal: await feed.estimatedTotal)
    }

    private static let limits: [(EmailKind, String, Int)] = [(.person, "PEOPLE", 15), (.updates, "UPDATES AND NOTICES", 8), (.promotions, "PROMOTIONS", 4), (.social, "SOCIAL", 3)]

    public static func render(_ collected: Collected, searched: String, accounts: [String], clock: ToolClock = ToolClock()) -> String {
        let items = collected.items
        let unread = items.filter(\.isUnread).count
        var lines: [String] = [EmailContent.warning]
        lines.append("Write the answer from these results, in the user's language. Use the counts exactly as given and never add emails that are not listed.")
        lines.append("Searched: \(searched). Mailboxes: \(accounts.joined(separator: ", ")).")
        if items.isEmpty {
            lines.append("Found 0 emails.")
        } else if collected.complete {
            lines.append("Found \(items.count) email\(items.count == 1 ? "" : "s") (\(unread) unread). This is every match.")
        } else {
            lines.append("Found at least \(items.count) emails (\(unread) unread among them). More exist (about \(max(collected.estimatedTotal, items.count)) in total); only the newest \(items.count) were counted.")
        }
        for name in collected.failedAccounts { lines.append("Could not reach \(name): its results are missing. Tell the user.") }

        for (kind, title, limit) in limits {
            let group = items.filter { $0.kind == kind }
            guard !group.isEmpty else { continue }
            let groupUnread = group.filter(\.isUnread).count
            lines.append("")
            lines.append("\(title): \(group.count) (\(groupUnread) unread)\(group.count > limit ? ", newest \(limit) shown" : "")")
            for item in group.prefix(limit) { lines.append(line(item, clock: clock, withSnippet: kind == .person)) }
        }
        var hidden = 0
        for (kind, _, limit) in limits { hidden += max(0, items.filter { $0.kind == kind }.count - limit) }
        if hidden > 0 || !collected.complete {
            lines.append("")
            lines.append("The Mail screen (envelope button at the top) lists everything and opens any email.")
        }
        return lines.joined(separator: "\n")
    }

    private static func line(_ item: EmailSummary, clock: ToolClock, withSnippet: Bool) -> String {
        var parts = ["[\(item.id)]", time(item.date, clock: clock)]
        if item.isUnread { parts.append("UNREAD") }
        if let account = item.account { parts.append("(\(account))") }
        let who = EmailAddress.parse(item.from).name
        var text = parts.joined(separator: " ") + " \(who) | \(EmailSanitizer.clean(item.subject))"
        if withSnippet {
            let snippet = EmailSanitizer.clean(item.snippet).trimmingCharacters(in: .whitespacesAndNewlines)
            if !snippet.isEmpty { text += " | " + String(snippet.prefix(90)) }
        }
        return text
    }

    static func time(_ date: Date?, clock: ToolClock) -> String {
        guard let date else { return "?" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = clock.calendar
        formatter.timeZone = clock.calendar.timeZone
        formatter.dateFormat = clock.calendar.isDate(date, inSameDayAs: clock.now()) ? "HH:mm" : "EEE d MMM HH:mm"
        return formatter.string(from: date)
    }
}
