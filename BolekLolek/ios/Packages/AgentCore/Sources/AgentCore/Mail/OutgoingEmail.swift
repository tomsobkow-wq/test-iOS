import Foundation

/// An email the user has reviewed and is about to send from the app.
public struct OutgoingEmail: Sendable, Equatable {
    public var from: String
    public var to: String
    public var subject: String
    public var body: String
    /// For a reply: the thread, the message being answered and the chain before it, so it lands in the same conversation.
    public var threadId: String?
    public var inReplyTo: String?
    public var references: String?
    /// The original message, quoted under the reply (already plain text).
    public var quoted: String?

    public init(from: String, to: String, subject: String, body: String, threadId: String? = nil, inReplyTo: String? = nil, references: String? = nil, quoted: String? = nil) {
        self.from = from
        self.to = to
        self.subject = subject
        self.body = body
        self.threadId = threadId
        self.inReplyTo = inReplyTo
        self.references = references
        self.quoted = quoted
    }

    /// A reply to `message`, addressed to its sender (or Reply-To), with "Re:" in front of the subject.
    public static func reply(to message: EmailMessage, from account: String, body: String = "") -> OutgoingEmail {
        let subject = message.summary.subject
        let prefixed = subject.range(of: "^(re|odp)\\s*:", options: [.regularExpression, .caseInsensitive]) != nil ? subject : "Re: " + subject
        let chain = [message.references, message.messageID].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        return OutgoingEmail(
            from: account, to: message.summary.replyAddress, subject: prefixed, body: body,
            threadId: message.threadId, inReplyTo: message.messageID, references: chain.isEmpty ? nil : chain,
            quoted: Self.quote(message)
        )
    }

    static func quote(_ message: EmailMessage) -> String? {
        let text = EmailSanitizer.display(message.body).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let who = EmailAddress.parse(message.summary.from).name
        let when = message.summary.date.map { date -> String in
            let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short; return f.string(from: date)
        } ?? ""
        let clipped = String(text.prefix(2_000))
        let lines = clipped.split(separator: "\n", omittingEmptySubsequences: false).map { "> " + $0 }.joined(separator: "\n")
        return "On \(when), \(who) wrote:\n\(lines)"
    }
}

public enum MIMEBuilder {
    /// A plain-text email as Gmail's API wants it. Header values lose any line break, so nothing typed or copied into a
    /// field can add a header (a hidden Bcc, for instance). The body is base64, so any language and any characters survive.
    public static func message(_ email: OutgoingEmail) throws -> Data {
        let to = try address(email.to)
        let from = try address(email.from)
        var headers = [
            "From: \(from)",
            "To: \(to)",
            "Subject: \(encodeHeader(oneLine(email.subject)))",
            "MIME-Version: 1.0",
            "Content-Type: text/plain; charset=UTF-8",
            "Content-Transfer-Encoding: base64",
        ]
        if let inReplyTo = email.inReplyTo.map(oneLine), !inReplyTo.isEmpty { headers.append("In-Reply-To: \(inReplyTo)") }
        if let references = email.references.map(oneLine), !references.isEmpty { headers.append("References: \(references)") }
        var body = email.body.replacingOccurrences(of: "\r\n", with: "\n")
        if let quoted = email.quoted, !quoted.isEmpty { body += (body.isEmpty ? "" : "\n\n") + quoted }
        let encoded = Data(body.replacingOccurrences(of: "\n", with: "\r\n").utf8).base64EncodedString(options: [.lineLength76Characters, .endLineWithCarriageReturn, .endLineWithLineFeed])
        return Data((headers.joined(separator: "\r\n") + "\r\n\r\n" + encoded + "\r\n").utf8)
    }

    public static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    static func oneLine(_ text: String) -> String {
        text.replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
    }

    /// One plain address. Several recipients, display tricks and anything that could smuggle in more are refused.
    static func address(_ raw: String) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // "Name <a@b.com>" is fine; anything after the closing bracket is not.
        if trimmed.contains("<"), !trimmed.hasSuffix(">") { throw ToolError("\"\(raw)\" is not a single email address.") }
        let parsed = EmailAddress.parse(raw).address.trimmingCharacters(in: .whitespacesAndNewlines)
        let ok = parsed.range(of: "^[^\\s@,;<>()\\[\\]\"]+@[^\\s@,;<>()\\[\\]\"]+\\.[^\\s@,;<>()\\[\\]\"]+$", options: .regularExpression) != nil
        guard ok else { throw ToolError("\"\(raw)\" is not a single email address.") }
        return parsed
    }

    static func encodeHeader(_ text: String) -> String {
        guard text.unicodeScalars.contains(where: { !$0.isASCII }) else { return text }
        return "=?UTF-8?B?\(Data(text.utf8).base64EncodedString())?="
    }
}

/// Sends mail through the user's own account. Only the Mail screen's composer calls this, after the user taps Send.
public protocol EmailSending: Sendable {
    /// Whether this sign-in was granted permission to send (older sign-ins only allowed reading).
    func canSend() async -> Bool
    func send(_ email: OutgoingEmail) async throws
}
