import Foundation

/// Several mailboxes behind one provider. Ids handed to the model carry the account's position and a "z"
/// (Gmail ids are hexadecimal, so "z" never appears inside one): "1z18c3f0a" is message 18c3f0a in the second account.
public struct MultiEmailProvider: EmailProviding {
    public struct Account: Sendable {
        public let label: String
        public let provider: any EmailProviding
        public let paging: (any MailboxPaging)?
        public let sending: (any EmailSending)?
        public init(label: String, provider: any EmailProviding, paging: (any MailboxPaging)? = nil, sending: (any EmailSending)? = nil) {
            self.label = label
            self.provider = provider
            self.paging = paging
            self.sending = sending
        }
    }

    private let accounts: @Sendable () async -> [Account]

    public init(accounts: @escaping @Sendable () async -> [Account]) { self.accounts = accounts }

    public func isConnected() async -> Bool { !(await accounts()).isEmpty }

    public func search(query: String, limit: Int) async throws -> [EmailSummary] {
        let list = await accounts()
        guard !list.isEmpty else { return [] }
        let labelled = list.count > 1
        var failure: Error?
        var merged: [EmailSummary] = []
        await withTaskGroup(of: (Int, Result<[EmailSummary], Error>).self) { group in
            for (index, account) in list.enumerated() {
                group.addTask {
                    do { return (index, .success(try await account.provider.search(query: query, limit: limit))) } catch { return (index, .failure(error)) }
                }
            }
            for await (index, result) in group {
                switch result {
                case .success(let found):
                    merged += found.map { item in
                        var copy = item
                        copy = EmailSummary(id: "\(index)z\(item.id)", from: item.from, subject: item.subject, date: item.date,
                                            snippet: item.snippet, isUnread: item.isUnread, account: labelled ? list[index].label : nil)
                        return copy
                    }
                case .failure(let error): failure = error
                }
            }
        }
        // One account failing (expired sign-in) must not hide the others; only fail if nothing came back at all.
        if merged.isEmpty, let failure { throw failure }
        let ordered = merged.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        return Array(ordered.prefix(max(1, min(limit, 10))))
    }

    /// The mailboxes (all, or those whose address contains `account`) that can page, as one newest-first stream.
    public func feed(query: String, account: String?) async -> MailFeed? {
        let all = await accounts()
        let wanted = account?.trimmingCharacters(in: .whitespaces).lowercased()
        let sources = all.enumerated().compactMap { position, candidate -> (position: Int, label: String, paging: any MailboxPaging)? in
            if let wanted, !wanted.isEmpty, !candidate.label.lowercased().contains(wanted) { return nil }
            return candidate.paging.map { (position: position, label: candidate.label, paging: $0) }
        }
        guard !sources.isEmpty else { return nil }
        return MailFeed(sources: sources, query: query, labelled: all.count > 1)
    }

    /// Sends through the mailbox whose address is `account` (or the only one). Fails clearly when that sign-in cannot send.
    public func send(_ email: OutgoingEmail, from account: String?) async throws {
        let all = await accounts()
        let wanted = account?.lowercased()
        guard let chosen = Self.pick(all, wanted: wanted) else {
            throw ToolError("Choose which Gmail account to send from.")
        }
        guard let sending = chosen.sending, await sending.canSend() else {
            throw ToolError("\(chosen.label) was connected for reading only. Reconnect it from the + menu and allow sending.")
        }
        var outgoing = email
        outgoing.from = chosen.label
        try await sending.send(outgoing)
    }

    /// The named mailbox; with no name only when exactly one is connected. Never a guess between several: mail must not go out from the wrong address.
    private static func pick(_ all: [Account], wanted: String?) -> Account? {
        if let wanted { return all.first { $0.label.lowercased() == wanted } }
        return all.count == 1 ? all[0] : nil
    }

    /// Whether the given mailbox (or the only one) may send.
    public func canSend(from account: String?) async -> Bool {
        let all = await accounts()
        let wanted = account?.lowercased()
        guard let chosen = Self.pick(all, wanted: wanted) else { return false }
        return await chosen.sending?.canSend() ?? false
    }

    public func accountLabels() async -> [String] { await accounts().map(\.label) }

    public func unreadCount() async -> Int? {
        var total = 0
        var known = false
        for account in await accounts() {
            if let count = await account.provider.unreadCount() { total += count; known = true }
        }
        return known ? total : nil
    }

    public func message(id: String) async throws -> EmailMessage {
        let list = await accounts()
        guard let split = id.firstIndex(of: "z"), let index = Int(id[..<split]), list.indices.contains(index) else {
            throw ToolError("That is not a valid email id. Search first and use an id from the results.")
        }
        let inner = String(id[id.index(after: split)...])
        let email = try await list[index].provider.message(id: inner)
        let summary = email.summary
        return EmailMessage(
            summary: EmailSummary(id: id, from: summary.from, subject: summary.subject, date: summary.date, snippet: summary.snippet,
                                  isUnread: summary.isUnread, account: list.count > 1 ? list[index].label : nil),
            to: email.to, body: email.body, invite: email.invite, threadId: email.threadId, messageID: email.messageID, references: email.references
        )
    }
}
