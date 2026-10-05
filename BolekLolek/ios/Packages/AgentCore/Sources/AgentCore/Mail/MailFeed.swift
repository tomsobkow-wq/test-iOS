import Foundation

public struct EmailPage: Sendable {
    public let items: [EmailSummary]
    public let nextToken: String?
    public let estimatedTotal: Int?

    public init(items: [EmailSummary], nextToken: String?, estimatedTotal: Int?) {
        self.items = items
        self.nextToken = nextToken
        self.estimatedTotal = estimatedTotal
    }
}

/// One mailbox that can hand out its messages a page at a time, newest first.
public protocol MailboxPaging: Sendable {
    func page(query: String, pageToken: String?, size: Int) async throws -> EmailPage
}

/// Newest-first stream over one or several mailboxes. Each mailbox is already sorted, so taking the newest of the
/// waiting heads keeps the merged order right without reading everything first. Ids get the mailbox position and a "z"
/// in front (Gmail ids are hexadecimal, so "z" never occurs inside one) so a later read goes to the right account.
public actor MailFeed {
    private struct Source {
        /// Position of this mailbox among all connected ones; it goes into the ids.
        let position: Int
        let label: String
        let paging: any MailboxPaging
        var buffer: [EmailSummary] = []
        var token: String?
        var started = false
        var exhausted = false
        var estimate = 0
    }

    private var sources: [Source]
    private let query: String
    private let labelled: Bool
    public private(set) var failedAccounts: [String] = []
    private var lastError: Error?
    private let pageSize: Int

    public init(sources: [(position: Int, label: String, paging: any MailboxPaging)], query: String, labelled: Bool, pageSize: Int = 25) {
        self.sources = sources.map { Source(position: $0.position, label: $0.label, paging: $0.paging) }
        self.query = query
        self.labelled = labelled
        self.pageSize = pageSize
    }

    /// Rough size of the whole result (Gmail only estimates), once every mailbox has been asked.
    public var estimatedTotal: Int { sources.reduce(0) { $0 + $1.estimate } }

    public var isExhausted: Bool { sources.allSatisfy { $0.exhausted && $0.buffer.isEmpty } }

    /// The next `count` messages in date order. A mailbox that fails is skipped and named in `failedAccounts`;
    /// only if every mailbox fails does the call throw.
    public func next(_ count: Int) async throws -> [EmailSummary] {
        var out: [EmailSummary] = []
        while out.count < count {
            try await refill()
            guard let index = newestHead() else { break }
            var item = sources[index].buffer.removeFirst()
            item = EmailSummary(
                id: "\(sources[index].position)z\(item.id)", from: item.from, subject: item.subject, date: item.date, snippet: item.snippet,
                isUnread: item.isUnread, account: labelled ? sources[index].label : nil, kind: item.kind, replyAddress: item.replyAddress
            )
            out.append(item)
        }
        if out.isEmpty, failedAccounts.count == sources.count, let lastError { throw lastError }
        return out
    }

    /// Makes sure every mailbox that still has pages has at least one message waiting.
    private func refill() async throws {
        for index in sources.indices where sources[index].buffer.isEmpty && !sources[index].exhausted {
            do {
                let page = try await sources[index].paging.page(query: query, pageToken: sources[index].token, size: pageSize)
                sources[index].buffer = page.items
                sources[index].token = page.nextToken
                sources[index].started = true
                if let total = page.estimatedTotal, sources[index].estimate == 0 { sources[index].estimate = total }
                if page.nextToken == nil { sources[index].exhausted = true }
                // An empty page with a token would loop forever; treat it as the end.
                if page.items.isEmpty { sources[index].exhausted = true }
            } catch {
                lastError = error
                sources[index].exhausted = true
                if !failedAccounts.contains(sources[index].label) { failedAccounts.append(sources[index].label) }
            }
        }
    }

    private func newestHead() -> Int? {
        sources.indices
            .filter { !sources[$0].buffer.isEmpty }
            .max { (sources[$0].buffer[0].date ?? .distantPast) < (sources[$1].buffer[0].date ?? .distantPast) }
    }
}
