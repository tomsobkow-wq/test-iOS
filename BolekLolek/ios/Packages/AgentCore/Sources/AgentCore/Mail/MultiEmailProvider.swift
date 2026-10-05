import Foundation

/// Several mailboxes behind one provider. Ids handed to the model carry the account's position and a "z"
/// (Gmail ids are hexadecimal, so "z" never appears inside one): "1z18c3f0a" is message 18c3f0a in the second account.
public struct MultiEmailProvider: EmailProviding {
    public struct Account: Sendable {
        public let label: String
        public let provider: any EmailProviding
        public let paging: (any MailboxPaging)?
        public init(label: String, provider: any EmailProviding, paging: (any MailboxPaging)? = nil) {
            self.label = label
            self.provider = provider
            self.paging = paging
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
            to: email.to, body: email.body, invite: email.invite
        )
    }
}
