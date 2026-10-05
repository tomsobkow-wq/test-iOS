import XCTest
@testable import AgentCore

private func sampleMessage(subject: String = "Weekend w Krakowie", replyTo: String? = nil) -> EmailMessage {
    EmailMessage(
        summary: EmailSummary(id: "m1", from: "Anna Nowak <anna@example.com>", subject: subject, date: Date(timeIntervalSince1970: 1_800_000_000), snippet: "", isUnread: true, replyAddress: replyTo),
        to: "me@example.com", body: "Cześć!\nBierzemy apartament.\nAnia", threadId: "thr123", messageID: "<abc@mail.example.com>", references: "<first@mail.example.com>"
    )
}

private func decoded(_ data: Data) -> (headers: [String: String], body: String) {
    let text = String(decoding: data, as: UTF8.self)
    let parts = text.components(separatedBy: "\r\n\r\n")
    var headers: [String: String] = [:]
    for line in parts[0].components(separatedBy: "\r\n") {
        guard let colon = line.firstIndex(of: ":") else { continue }
        headers[String(line[..<colon])] = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
    }
    let b64 = parts.dropFirst().joined(separator: "\r\n\r\n").replacingOccurrences(of: "\r\n", with: "")
    return (headers, String(data: Data(base64Encoded: b64) ?? Data(), encoding: .utf8) ?? "")
}

final class MIMEBuilderTests: XCTestCase {
    func testReplyHasThreadHeadersSubjectAndQuote() throws {
        let draft = OutgoingEmail.reply(to: sampleMessage(), from: "me@example.com", body: "Super, dziękuję!")
        XCTAssertEqual(draft.subject, "Re: Weekend w Krakowie")
        XCTAssertEqual(draft.to, "anna@example.com")
        XCTAssertEqual(draft.threadId, "thr123")
        let parts = decoded(try MIMEBuilder.message(draft))
        XCTAssertEqual(parts.headers["In-Reply-To"], "<abc@mail.example.com>")
        XCTAssertEqual(parts.headers["References"], "<first@mail.example.com> <abc@mail.example.com>")
        XCTAssertEqual(parts.headers["To"], "anna@example.com")
        XCTAssertEqual(parts.headers["Content-Type"], "text/plain; charset=UTF-8")
        XCTAssertTrue(parts.body.hasPrefix("Super, dziękuję!"), parts.body)
        XCTAssertTrue(parts.body.contains("wrote:\r\n> Cześć!\r\n> Bierzemy apartament."), parts.body.debugDescription)
    }

    func testReplyUsesReplyToAndDoesNotDoublePrefix() {
        let draft = OutgoingEmail.reply(to: sampleMessage(subject: "Re: Test", replyTo: "list@example.com"), from: "me@example.com")
        XCTAssertEqual(draft.to, "list@example.com")
        XCTAssertEqual(draft.subject, "Re: Test")
        XCTAssertEqual(OutgoingEmail.reply(to: sampleMessage(subject: "Odp: Test"), from: "me@example.com").subject, "Odp: Test")
    }

    func testNonAsciiSubjectIsEncodedAndPolishBodySurvives() throws {
        let parts = decoded(try MIMEBuilder.message(OutgoingEmail(from: "me@example.com", to: "a@example.com", subject: "Zażółć gęślą jaźń", body: "Łódź, żółw, ćma: 100% ✓")))
        let subject = try XCTUnwrap(parts.headers["Subject"])
        XCTAssertTrue(subject.hasPrefix("=?UTF-8?B?") && subject.hasSuffix("?="))
        let inner = String(subject.dropFirst(10).dropLast(2))
        XCTAssertEqual(String(data: Data(base64Encoded: inner) ?? Data(), encoding: .utf8), "Zażółć gęślą jaźń")
        XCTAssertEqual(parts.body, "Łódź, żółw, ćma: 100% ✓")
    }

    func testNothingTypedIntoAFieldCanAddAHiddenHeader() throws {
        let evil = OutgoingEmail(from: "me@example.com", to: "a@example.com", subject: "Hi\r\nBcc: spy@evil.example", body: "x", inReplyTo: "<id@x>\r\nBcc: spy@evil.example")
        let raw = String(decoding: try MIMEBuilder.message(evil), as: UTF8.self)
        XCTAssertFalse(raw.lowercased().contains("\r\nbcc:"), raw)
        let headerBlock = raw.components(separatedBy: "\r\n\r\n")[0]
        XCTAssertEqual(headerBlock.components(separatedBy: "\r\n").filter { $0.hasPrefix("Subject:") }.count, 1)
    }

    func testOnlyASingleCleanAddressIsAccepted() {
        for bad in ["a@example.com, b@example.com", "a@example.com;b@example.com", "not an address", "a@b", "<a@example.com>x", "a@example.com\nBcc: x@y.com", ""] {
            XCTAssertThrowsError(try MIMEBuilder.message(OutgoingEmail(from: "me@example.com", to: bad, subject: "s", body: "b")), bad)
        }
        XCTAssertNoThrow(try MIMEBuilder.message(OutgoingEmail(from: "me@example.com", to: "Anna Nowak <anna@example.com>", subject: "s", body: "b")))
    }

    func testLongBodyIsWrappedForTransport() throws {
        let raw = String(decoding: try MIMEBuilder.message(OutgoingEmail(from: "me@example.com", to: "a@example.com", subject: "s", body: String(repeating: "word ", count: 400))), as: UTF8.self)
        XCTAssertTrue(raw.components(separatedBy: "\r\n").allSatisfy { $0.count <= 78 })
    }
}

final class GmailSendTests: XCTestCase {
    private final class Captured: @unchecked Sendable {
        private let lock = NSLock()
        private var requests: [URLRequest] = []
        func add(_ r: URLRequest) { lock.lock(); requests.append(r); lock.unlock() }
        var all: [URLRequest] { lock.lock(); defer { lock.unlock() }; return requests }
    }

    private func client(status: Int = 200, captured: Captured = Captured(), canSend: Bool = true) -> GmailClient {
        GmailClient(isSignedIn: { true }, accessToken: { "tok" }, canSend: { canSend }) { request in
            captured.add(request)
            return (Data(#"{"id":"x","threadId":"thr123"}"#.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        }
    }

    func testSendPostsRawMessageWithThreadToGmailOnly() async throws {
        let captured = Captured()
        let draft = OutgoingEmail.reply(to: sampleMessage(), from: "me@example.com", body: "OK")
        try await client(captured: captured).send(draft)
        let request = try XCTUnwrap(captured.all.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "https://gmail.googleapis.com/gmail/v1/users/me/messages/send")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(body["threadId"] as? String, "thr123")
        XCTAssertTrue((body["raw"] as? String)?.isEmpty == false)
    }

    func testErrorsAreSaidInPlainWordsAndNothingIsClaimedSent() async {
        let draft = OutgoingEmail(from: "me@example.com", to: "a@example.com", subject: "s", body: "b")
        for (status, expect) in [(403, "allow sending"), (401, "expired"), (400, "did not accept"), (500, "nothing was sent")] {
            do { try await client(status: status).send(draft); XCTFail("\(status) accepted") } catch let error as ToolError {
                XCTAssertTrue(error.message.contains(expect), "\(status): \(error.message)")
            } catch { XCTFail() }
        }
    }

    func testReadOnlySignInIsRefusedBeforeAnythingIsSent() async throws {
        let captured = Captured()
        let readOnly = client(captured: captured, canSend: false)
        let provider = MultiEmailProvider { [.init(label: "me@example.com", provider: readOnly, paging: readOnly, sending: readOnly)] }
        let canSend = await provider.canSend(from: nil)
        XCTAssertFalse(canSend)
        do { try await provider.send(OutgoingEmail(from: "", to: "a@example.com", subject: "s", body: "b"), from: nil); XCTFail() } catch let error as ToolError {
            XCTAssertTrue(error.message.contains("reading only"), error.message)
        }
        XCTAssertTrue(captured.all.isEmpty)
    }

    func testTwoAccountsNeedAChoiceAndTheRightOneSends() async throws {
        let a = FixtureMailbox(label: "a@x.com"), b = FixtureMailbox(label: "b@x.com")
        let provider = MultiEmailProvider { [.init(label: "a@x.com", provider: a, paging: a, sending: a), .init(label: "b@x.com", provider: b, paging: b, sending: b)] }
        do { try await provider.send(OutgoingEmail(from: "", to: "c@x.com", subject: "s", body: "b"), from: nil); XCTFail("guessed an account") } catch is ToolError {}
        try await provider.send(OutgoingEmail(from: "", to: "c@x.com", subject: "s", body: "b"), from: "b@x.com")
        XCTAssertEqual(a.sent.count, 0)
        XCTAssertEqual(b.sent.map(\.from), ["b@x.com"])
    }

    func testGmailFullMessageCarriesThreadAndMessageIds() async throws {
        let client = GmailClient(isSignedIn: { true }, accessToken: { "t" }) { request in
            let json = #"{"id":"m1","threadId":"thr9","internalDate":"1","payload":{"mimeType":"text/plain","headers":[{"name":"From","value":"A <a@x.com>"},{"name":"Subject","value":"Hi"},{"name":"Message-ID","value":"<id1@x.com>"},{"name":"References","value":"<r0@x.com>"}],"body":{"data":"aGk"}}}"#
            return (Data(json.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let message = try await client.message(id: "m1")
        XCTAssertEqual(message.threadId, "thr9")
        XCTAssertEqual(message.messageID, "<id1@x.com>")
        XCTAssertEqual(message.references, "<r0@x.com>")
    }
}

final class ComposeToolSinkTests: XCTestCase {
    private final class Sink: ComposeSink, @unchecked Sendable {
        private let lock = NSLock()
        private var drafts: [EmailDraftRequest] = []
        func present(_ draft: EmailDraftRequest) async { lock.lock(); drafts.append(draft); lock.unlock() }
        var all: [EmailDraftRequest] { lock.lock(); defer { lock.unlock() }; return drafts }
    }
    private struct NeverOpens: URLOpening { func open(_ url: URL) async -> Bool { XCTFail("Mail app must not open"); return false } }

    func testComposeOpensTheInAppComposerAndNeverTheMailApp() async throws {
        let sink = Sink()
        let tool = ComposeEmailTool(opener: NeverOpens(), sink: sink)
        XCTAssertFalse(tool.risk.needsApproval, "opening a draft is harmless; the Send tap is the approval")
        let reply = try await tool.run(argumentsJSON: #"{"to":"anna@example.com","subject":"Weekend","body":"Tak, bierzemy."}"#)
        XCTAssertEqual(sink.all, [EmailDraftRequest(to: "anna@example.com", subject: "Weekend", body: "Tak, bierzemy.")])
        XCTAssertTrue(reply.contains("NOT sent"), reply)
    }

    func testBadAddressesNeverReachTheComposer() async {
        let sink = Sink()
        let tool = ComposeEmailTool(opener: NeverOpens(), sink: sink)
        for bad in ["a@b.com,c@d.com", "x@y.com?bcc=z@w.com", "no at"] {
            do { _ = try await tool.run(argumentsJSON: "{\"to\":\"\(bad)\",\"body\":\"x\"}"); XCTFail(bad) } catch is ToolError {} catch { XCTFail() }
        }
        XCTAssertTrue(sink.all.isEmpty)
    }

    func testToolHasNoWayToSend() {
        let names = EmailToolbox.tools(provider: FixtureMailbox(), opener: NeverOpens(), composer: Sink()).map(\.name)
        XCTAssertEqual(Set(names), ["search_email", "read_email", "compose_email"])
    }
}
