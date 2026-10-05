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

    private static let limits: [(EmailKind, String, Int)] = [(.person, "PEOPLE", 8), (.updates, "UPDATES AND NOTICES", 4), (.promotions, "PROMOTIONS", 2), (.social, "SOCIAL", 1)]

    /// `only` limits the list to one group when the user asked about that group; the other groups are still counted.
    /// `countsOnly` is for questions that ask only how many: the counts are exact and no message lines are listed, which keeps the evidence tiny.
    public static func render(_ collected: Collected, searched: String, accounts: [String], only: EmailKind? = nil, countsOnly: Bool = false, clock: ToolClock = ToolClock()) -> String {
        let items = collected.items
        let unread = items.filter(\.isUnread).count
        var lines: [String] = [EmailContent.warning]
        lines.append("These results are everything you need: answer now, in the user's language, and do not call another tool unless the user asks to open one email. Use the counts exactly as given and never add emails that are not listed. Answer only what was asked and keep it short: at most 6 lines, no times unless asked.")
        lines.append("Searched: \(searched). Mailboxes: \(accounts.joined(separator: ", ")).")
        if items.isEmpty {
            lines.append("Found 0 emails. Nothing matched: tell the user plainly and do not search again.")
        } else if collected.complete {
            lines.append("Found \(items.count) email\(items.count == 1 ? "" : "s") (\(unread) unread). This is every match.")
        } else {
            lines.append("Found at least \(items.count) emails (\(unread) unread among them). More exist (about \(max(collected.estimatedTotal, items.count)) in total); only the newest \(items.count) were counted.")
        }
        for name in collected.failedAccounts { lines.append("Could not reach \(name): its results are missing. Tell the user.") }

        if countsOnly, !items.isEmpty {
            lines.append("The user asked only how many: answer with the counts, in one or two sentences, and do not list messages.")
            for (kind, title, _) in limits {
                let group = items.filter { $0.kind == kind }
                if !group.isEmpty { lines.append("\(title): \(group.count) (\(group.filter(\.isUnread).count) unread)") }
            }
            return lines.joined(separator: "\n")
        }

        if let only, !items.isEmpty {
            let others = limits.filter { $0.0 != only }.compactMap { kind, title, _ -> String? in
                let n = items.filter { $0.kind == kind }.count
                return n > 0 ? "\(n) \(title.lowercased())" : nil
            }
            if !others.isEmpty { lines.append("Not listed because the user asked only about one group: " + others.joined(separator: ", ") + ".") }
        }
        for (kind, title, limit) in limits where only == nil || only == kind {
            let group = items.filter { $0.kind == kind }
            guard !group.isEmpty else { continue }
            let groupUnread = group.filter(\.isUnread).count
            lines.append("")
            lines.append("\(title): \(group.count) (\(groupUnread) unread)\(group.count > limit ? ", newest \(limit) shown" : "")")
            for (index, item) in group.prefix(limit).enumerated() { lines.append(line(item, clock: clock, withSnippet: kind == .person && index < 4)) }
        }
        var hidden = 0
        for (kind, _, limit) in limits where only == nil || only == kind { hidden += max(0, items.filter { $0.kind == kind }.count - limit) }
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
