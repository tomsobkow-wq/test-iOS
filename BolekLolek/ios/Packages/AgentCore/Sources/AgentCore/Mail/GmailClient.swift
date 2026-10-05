import Foundation

/// A rough sort of who wrote it, used to group long lists. Gmail's own tabs plus a check for bulk-mail headers.
public enum EmailKind: String, Sendable, Equatable, CaseIterable {
    case person, updates, promotions, social
}

public struct EmailSummary: Sendable, Equatable {
    public let id: String
    public let from: String
    public let subject: String
    public let date: Date?
    public let snippet: String
    public let isUnread: Bool
    /// Which connected mailbox it came from; set only when more than one is connected.
    public var account: String?
    public var kind: EmailKind
    /// Where a reply should go (Reply-To if present, else the sender's address).
    public var replyAddress: String

    public init(id: String, from: String, subject: String, date: Date?, snippet: String, isUnread: Bool,
                account: String? = nil, kind: EmailKind = .person, replyAddress: String? = nil) {
        self.account = account
        self.kind = kind
        self.replyAddress = replyAddress ?? EmailAddress.parse(from).address
        self.id = id
        self.from = from
        self.subject = subject
        self.date = date
        self.snippet = snippet
        self.isUnread = isUnread
    }
}

public struct EmailMessage: Sendable, Equatable {
    public let summary: EmailSummary
    public let to: String
    public let body: String

    public init(summary: EmailSummary, to: String, body: String) {
        self.summary = summary
        self.to = to
        self.body = body
    }
}

/// Splits "Jan Kowalski <jan@x.com>" into a display name and an address.
public enum EmailAddress {
    public static func parse(_ raw: String) -> (name: String, address: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let open = text.lastIndex(of: "<"), let close = text.lastIndex(of: ">"), open < close {
            let address = String(text[text.index(after: open)..<close]).trimmingCharacters(in: .whitespaces)
            var name = String(text[..<open]).trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
            if name.isEmpty { name = address }
            return (name, address)
        }
        return (text, text)
    }
}

/// Read-only access to the user's mailbox. Implemented on the phone only; nothing here talks to our servers.
public protocol EmailProviding: Sendable {
    func isConnected() async -> Bool
    func search(query: String, limit: Int) async throws -> [EmailSummary]
    func message(id: String) async throws -> EmailMessage
    /// Every match, newest first, page by page. Nil when the provider cannot page.
    func feed(query: String, account: String?) async -> MailFeed?
    /// Unread messages in the inbox(es); nil when unknown.
    func unreadCount() async -> Int?
    /// Addresses of the connected mailboxes.
    func accountLabels() async -> [String]
}

extension EmailProviding {
    public func feed(query: String, account: String?) async -> MailFeed? { nil }
    public func unreadCount() async -> Int? { nil }
    public func accountLabels() async -> [String] { ["your mailbox"] }
}

/// Talks straight from the phone to Gmail's API with the `gmail.readonly` permission. The only host it will call is
/// gmail.googleapis.com; message ids come from the model, so they are checked before they go into a URL.
public struct GmailClient: EmailProviding, MailboxPaging {
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    private let signedIn: @Sendable () async -> Bool
    private let accessToken: @Sendable () async throws -> String
    private let transport: Transport
    private static let root = "https://gmail.googleapis.com/gmail/v1/users/me"
    private static let base = root + "/messages"
    /// Memory only: no cookies and no cache, so email text is never written to this phone's disk by the networking layer.
    private static let session = URLSession(configuration: .ephemeral)
    private static let headers = ["From", "Subject", "Date", "Reply-To", "List-Unsubscribe"]

    public init(
        isSignedIn: @escaping @Sendable () async -> Bool,
        accessToken: @escaping @Sendable () async throws -> String,
        transport: Transport? = nil
    ) {
        self.signedIn = isSignedIn
        self.accessToken = accessToken
        self.transport = transport ?? { request in
            var request = request
            request.timeoutInterval = 20
            let (data, response) = try await Self.session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw ToolError("Gmail did not answer.") }
            return (data, http)
        }
    }

    public func isConnected() async -> Bool { await signedIn() }

    public func search(query: String, limit: Int) async throws -> [EmailSummary] {
        try await page(query: query, pageToken: nil, size: max(1, min(limit, 10))).items
    }

    /// One page of matches, newest first, with their headers. `size` is capped at 50 so a page stays quick.
    public func page(query: String, pageToken: String?, size: Int) async throws -> EmailPage {
        var components = URLComponents(string: Self.base)!
        var items = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "maxResults", value: String(max(1, min(size, 50)))),
        ]
        if let pageToken { items.append(URLQueryItem(name: "pageToken", value: pageToken)) }
        components.queryItems = items
        let list = try await get(components.url!)
        let ids = ((list["messages"] as? [[String: Any]]) ?? []).compactMap { $0["id"] as? String }
        let summaries = try await withThrowingTaskGroup(of: (Int, EmailSummary?).self) { group in
            var found: [(Int, EmailSummary)] = []
            var next = 0
            // Eight at a time: quick, and well inside Gmail's rate limit.
            func launch() {
                guard next < ids.count else { return }
                let (index, id) = (next, ids[next])
                next += 1
                group.addTask { (index, try await summary(id: id)) }
            }
            for _ in 0..<min(8, ids.count) { launch() }
            for try await (index, item) in group {
                if let item { found.append((index, item)) }
                launch()
            }
            return found.sorted { $0.0 < $1.0 }.map(\.1)
        }
        return EmailPage(
            items: summaries,
            nextToken: list["nextPageToken"] as? String,
            estimatedTotal: (list["resultSizeEstimate"] as? Int)
        )
    }

    public func unreadCount() async -> Int? {
        guard let url = URL(string: Self.root + "/labels/INBOX"), let label = try? await get(url) else { return nil }
        return label["messagesUnread"] as? Int
    }

    public func message(id: String) async throws -> EmailMessage {
        let object = try await get(try url(for: id, format: "full"))
        guard let summary = Self.summary(from: object) else { throw ToolError("That email could not be read.") }
        let payload = object["payload"] as? [String: Any] ?? [:]
        return EmailMessage(summary: summary, to: Self.header("To", in: payload) ?? "", body: GmailParsing.body(of: payload))
    }

    private func summary(id: String) async throws -> EmailSummary? {
        Self.summary(from: try await get(try url(for: id, format: "metadata")))
    }

    private func url(for id: String, format: String) throws -> URL {
        guard !id.isEmpty, id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else {
            throw ToolError("That is not a valid email id. Search first and use an id from the results.")
        }
        var components = URLComponents(string: "\(Self.base)/\(id)")!
        components.queryItems = [URLQueryItem(name: "format", value: format)]
        if format == "metadata" {
            components.queryItems? += Self.headers.map { URLQueryItem(name: "metadataHeaders", value: $0) }
        }
        return components.url!
    }

    private func get(_ url: URL) async throws -> [String: Any] {
        guard url.host == "gmail.googleapis.com" else { throw ToolError("Refused to call an unexpected address.") }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(try await accessToken())", forHTTPHeaderField: "Authorization")
        let data: Data
        let response: HTTPURLResponse
        do { (data, response) = try await transport(request) } catch is ToolError { throw ToolError("Gmail is not reachable right now.") } catch {
            throw ToolError("Gmail is not reachable right now. Email needs an internet connection even though Lolek runs on the phone.")
        }
        switch response.statusCode {
        case 200..<300:
            return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        case 401:
            throw ToolError("Gmail sign-in expired. Tell the user to reconnect Gmail from the + menu.")
        case 403:
            throw ToolError("Gmail refused access. Tell the user to reconnect Gmail from the + menu and allow reading email.")
        case 404:
            throw ToolError("That email no longer exists.")
        case 429:
            throw ToolError("Gmail is limiting requests. Try again in a minute.")
        default:
            throw ToolError("Gmail answered with an error (\(response.statusCode)).")
        }
    }

    private static func summary(from object: [String: Any]) -> EmailSummary? {
        guard let id = object["id"] as? String else { return nil }
        let payload = object["payload"] as? [String: Any] ?? [:]
        let millis = (object["internalDate"] as? String).flatMap(Double.init)
        let labels = (object["labelIds"] as? [String]) ?? []
        let from = header("From", in: payload) ?? ""
        let replyTo = header("Reply-To", in: payload).map { EmailAddress.parse($0).address }
        return EmailSummary(
            id: id,
            from: from,
            subject: header("Subject", in: payload) ?? "(no subject)",
            date: millis.map { Date(timeIntervalSince1970: $0 / 1000) },
            snippet: GmailParsing.decodeEntities((object["snippet"] as? String) ?? ""),
            isUnread: labels.contains("UNREAD"),
            kind: kind(labels: labels, from: from, bulk: header("List-Unsubscribe", in: payload) != nil),
            replyAddress: replyTo
        )
    }

    static func kind(labels: [String], from: String, bulk: Bool) -> EmailKind {
        if labels.contains("CATEGORY_PROMOTIONS") { return .promotions }
        if labels.contains("CATEGORY_SOCIAL") { return .social }
        if labels.contains("CATEGORY_UPDATES") || labels.contains("CATEGORY_FORUMS") { return .updates }
        let address = EmailAddress.parse(from).address.lowercased()
        let automated = ["noreply", "no-reply", "donotreply", "do-not-reply", "notifications@", "newsletter", "mailer-daemon"].contains { address.contains($0) }
        return (bulk || automated) ? .updates : .person
    }

    private static func header(_ name: String, in payload: [String: Any]) -> String? {
        let headers = payload["headers"] as? [[String: Any]] ?? []
        return headers.first { ($0["name"] as? String)?.lowercased() == name.lowercased() }?["value"] as? String
    }
}

/// Turns Gmail's message payload into readable text. Pure functions, tested without a network.
enum GmailParsing {
    static func body(of payload: [String: Any], limit: Int = 4000) -> String {
        let plain = text(in: payload, mime: "text/plain")
        let raw = plain ?? text(in: payload, mime: "text/html").map(stripHTML) ?? ""
        let lines = raw.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { !$0.hasPrefix(">") }
        var cleaned = lines.joined(separator: "\n")
        while cleaned.contains("\n\n\n") { cleaned = cleaned.replacingOccurrences(of: "\n\n\n", with: "\n\n") }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.count > limit ? String(cleaned.prefix(limit)) + "\n[…cut, the email is longer]" : cleaned
    }

    private static func text(in part: [String: Any], mime: String) -> String? {
        if (part["mimeType"] as? String) == mime,
           let data = (part["body"] as? [String: Any])?["data"] as? String,
           let decoded = decodeBase64URL(data) { return decoded }
        for child in (part["parts"] as? [[String: Any]]) ?? [] {
            if let found = text(in: child, mime: mime) { return found }
        }
        return nil
    }

    static func decodeBase64URL(_ string: String) -> String? {
        var base64 = string.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        return Data(base64Encoded: base64).flatMap { String(data: $0, encoding: .utf8) }
    }

    static func stripHTML(_ html: String) -> String {
        var text = html
        for pattern in ["<style[\\s\\S]*?</style>", "<script[\\s\\S]*?</script>", "<br\\s*/?>", "</p>|</div>|</tr>|</li>", "<[^>]+>"] {
            let replacement = pattern.hasPrefix("<br") || pattern.hasPrefix("</p>") ? "\n" : ""
            text = text.replacingOccurrences(of: pattern, with: replacement, options: [.regularExpression, .caseInsensitive])
        }
        return decodeEntities(text)
    }

    static func decodeEntities(_ text: String) -> String {
        text.replacingOccurrences(of: "&nbsp;", with: " ").replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&#39;", with: "'")
    }
}
