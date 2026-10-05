import XCTest
@testable import AgentCore

private let warsaw = TimeZone(identifier: "Europe/Warsaw")!
private func clock(_ iso: String) -> ToolClock {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = warsaw
    calendar.firstWeekday = 2
    let formatter = ISO8601DateFormatter()
    formatter.timeZone = warsaw
    formatter.formatOptions = [.withInternetDateTime]
    let date = formatter.date(from: iso)!
    return ToolClock(now: { date }, calendar: calendar)
}

final class EmailSanitizerTests: XCTestCase {
    func testVerificationCodesAreRemoved() {
        XCTAssertEqual(EmailSanitizer.clean("Your verification code is 482913. Do not share."), "Your verification code is [code removed]. Do not share.")
        XCTAssertTrue(EmailSanitizer.clean("Twój kod: 4829-13").contains("[code removed]"))
        XCTAssertTrue(EmailSanitizer.clean("Security code: 123 456").contains("[code removed]"))
        XCTAssertTrue(EmailSanitizer.clean("One-time code: AB12CD34").contains("[code removed]"))
        XCTAssertFalse(EmailSanitizer.clean("kod weryfikacyjny 90210").contains("90210"))
    }

    func testOrdinaryNumbersAndWordsSurvive() {
        let text = "Faktura nr 2026/09/114 na kwotę 1 230,00 zł. Spotkanie o 13:00, kod pocztowy 00-950. Status: Reminder"
        XCTAssertEqual(EmailSanitizer.clean(text), text)
    }

    func testSensitiveLinksAreRemovedAndOthersShortened() {
        let text = "Reset: https://accounts.example/reset?token=zzz999 and see https://www.delta.example/trips/very/long/path?utm=1234567890abcdef"
        let clean = EmailSanitizer.clean(text)
        XCTAssertTrue(clean.contains("[sensitive link removed]"))
        XCTAssertTrue(clean.contains("[link: delta.example]"))
        XCTAssertFalse(clean.contains("zzz999"))
        XCTAssertFalse(clean.contains("utm="))
    }

    func testMagicAndUnsubscribeLinksAreSensitive() {
        for link in ["https://x.example/magic/abc", "https://x.example/verify?id=1", "https://x.example/u?unsubscribe=1", "https://x.example/confirm/xyz", "https://x.example/login?otp=1"] {
            XCTAssertEqual(EmailSanitizer.clean(link), "[sensitive link removed]", link)
        }
    }
}

final class EmailQueryBuilderTests: XCTestCase {
    func testTodayUsesMidnightInTheUsersTimeZone() {
        let builder = EmailQueryBuilder(clock: clock("2026-10-05T15:30:00+02:00"))
        let midnight = Int(ISO8601DateFormatter().date(from: "2026-10-04T22:00:00Z")!.timeIntervalSince1970)
        XCTAssertEqual(builder.gmailQuery(EmailQuerySpec(when: .today)), "in:inbox after:\(midnight)")
    }

    func testYesterdayHasBothEdges() {
        let builder = EmailQueryBuilder(clock: clock("2026-10-05T15:30:00+02:00"))
        let query = builder.gmailQuery(EmailQuerySpec(when: .yesterday, unread: true, from: "Delta"))
        XCTAssertTrue(query.contains("after:") && query.contains("before:") && query.contains("is:unread") && query.contains("from:(Delta)"))
    }

    func testWeekStartsOnMonday() {
        let builder = EmailQueryBuilder(clock: clock("2026-10-08T10:00:00+02:00")) // Thursday
        let monday = Int(ISO8601DateFormatter().date(from: "2026-10-04T22:00:00Z")!.timeIntervalSince1970)
        XCTAssertTrue(builder.gmailQuery(EmailQuerySpec(when: .thisWeek)).contains("after:\(monday)"))
    }

    func testRawQueryPassesThroughAlone() {
        XCTAssertEqual(EmailQueryBuilder().gmailQuery(EmailQuerySpec(raw: "has:attachment larger:5M")), "has:attachment larger:5M")
    }

    func testDescriptionIsPlainWords() {
        XCTAssertEqual(EmailQueryBuilder().describe(EmailQuerySpec(when: .today, unread: true, from: "Delta")), "today, unread only, from Delta")
        XCTAssertEqual(EmailQueryBuilder().describe(EmailQuerySpec()), "latest inbox mail")
    }
}

final class EmailPlannerTests: XCTestCase {
    private func plan(_ text: String, connected: Bool = true) async -> [ToolCall] {
        await EmailPlanner(focus: EmailFocus(), isConnected: { connected }).plan(userText: text, language: .en)
    }

    private func args(_ call: ToolCall) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: Data(call.argumentsJSON.utf8)) as? [String: Any]) ?? [:]
    }

    func testTodayInEnglishAndPolish() async throws {
        for text in ["What emails did I get today?", "Jakie maile dostałem dzisiaj?", "pokaż pocztę z dzisiaj"] {
            let calls = await plan(text)
            XCTAssertEqual(calls.first?.name, "search_email", text)
            XCTAssertEqual(args(try XCTUnwrap(calls.first))["when"] as? String, "today", text)
        }
    }

    func testUnreadAndSender() async throws {
        let planned = await plan("any unread emails from Delta this week?")
        let call = try XCTUnwrap(planned.first)
        XCTAssertEqual(args(call)["unread"] as? Bool, true)
        XCTAssertEqual(args(call)["from"] as? String, "delta")
        XCTAssertEqual(args(call)["when"] as? String, "this_week")
        let plannedPolish = await plan("czy mam nieprzeczytane maile od Marka?")
        let polish = try XCTUnwrap(plannedPolish.first)
        XCTAssertEqual(args(polish)["from"] as? String, "marka")
        XCTAssertEqual(args(polish)["unread"] as? Bool, true)
    }

    func testKindsOfSenderAreNotTreatedAsNames() async throws {
        for text in ["Which of today's emails are from real people?", "Które dzisiejsze maile są od ludzi?", "emails from people today"] {
            let planned = await plan(text)
            let call = try XCTUnwrap(planned.first, text)
            XCTAssertNil(args(call)["from"], text)
            XCTAssertEqual(args(call)["when"] as? String, "today", text)
            XCTAssertEqual(args(call)["only"] as? String, "people", text)
        }
    }

    func testHowManyAsksForCountsOnlyButWhichStillGetsTheList() async throws {
        let counts = await plan("Ile mam nieprzeczytanych maili?")
        XCTAssertEqual(args(try XCTUnwrap(counts.first))["counts_only"] as? Bool, true)
        let counts2 = await plan("How many promotion emails today?")
        XCTAssertEqual(args(try XCTUnwrap(counts2.first))["counts_only"] as? Bool, true)
        let list = await plan("Which emails did I get today?")
        XCTAssertNil(args(try XCTUnwrap(list.first))["counts_only"])
        let who = await plan("How many unread emails from Delta?")
        XCTAssertNil(args(try XCTUnwrap(who.first))["counts_only"], "a sender was named: list them")
    }

    func testCountingQuestionPlansASearch() async {
        let calls = await plan("Ile maili mam w skrzynce?")
        XCTAssertEqual(calls.first?.name, "search_email")
    }

    func testWritingMailIsLeftToTheModelAndOtherChatIsUntouched() async {
        let write = await plan("Napisz maila do Marka o fakturze dzisiaj")
        XCTAssertTrue(write.isEmpty)
        let reply = await plan("reply to the email from Sarah")
        XCTAssertTrue(reply.isEmpty)
        let other = await plan("What's the weather today?")
        XCTAssertTrue(other.isEmpty)
    }

    func testNothingPlannedWhenGmailIsNotConnected() async {
        let calls = await plan("emails from today", connected: false)
        XCTAssertTrue(calls.isEmpty)
    }

    func testOpenedEmailIsReadOnceOnTheNextTurn() async {
        let focus = EmailFocus()
        let planner = EmailPlanner(focus: focus, isConnected: { true })
        await focus.set(id: "0zabc12")
        let first = await planner.plan(userText: "Summarise this", language: .en)
        XCTAssertEqual(first.first?.name, "read_email")
        XCTAssertTrue(first.first?.argumentsJSON.contains("0zabc12") == true)
        let second = await planner.plan(userText: "And who is it from?", language: .en)
        XCTAssertTrue(second.isEmpty)
    }
}

private struct AlwaysPlans: TurnPlanner {
    func plan(userText: String, language: ConversationLanguage) async -> [ToolCall] { [ToolCall(name: "statement_query", argumentsJSON: "{}")] }
}

final class QuietWhileEmailIsOpenTests: XCTestCase {
    func testStatementPlannerStaysQuietForThreeFollowUpsThenWakes() async {
        let focus = EmailFocus()
        let email = EmailPlanner(focus: focus, isConnected: { true })
        let quiet = QuietWhileEmailIsOpen(AlwaysPlans(), focus: focus)
        await focus.set(id: "0zabc")
        _ = await email.plan(userText: "Summarise this email.", language: .en)
        for question in ["Ile ta rezerwacja kosztuje?", "A kiedy płatne?", "Kto to wysłał?"] {
            _ = await email.plan(userText: question, language: .pl)
            let calls = await quiet.plan(userText: question, language: .pl)
            XCTAssertTrue(calls.isEmpty, question)
        }
        _ = await email.plan(userText: "Ile wydałem na paliwo?", language: .pl)
        let later = await quiet.plan(userText: "Ile wydałem na paliwo?", language: .pl)
        XCTAssertEqual(later.count, 1)
    }

    func testWordsThatNameAStatementStillReachIt() async {
        let focus = EmailFocus()
        let email = EmailPlanner(focus: focus, isConnected: { true })
        let quiet = QuietWhileEmailIsOpen(AlwaysPlans(), focus: focus)
        await focus.set(id: "0zabc")
        _ = await email.plan(userText: "Summarise", language: .en)
        _ = await email.plan(userText: "Ile mam na koncie z wyciągu?", language: .pl)
        let calls = await quiet.plan(userText: "Ile mam na koncie z wyciągu?", language: .pl)
        XCTAssertEqual(calls.count, 1)
    }

    func testNothingIsQuietWithoutAnOpenedEmail() async {
        let focus = EmailFocus()
        let quiet = QuietWhileEmailIsOpen(AlwaysPlans(), focus: focus)
        let calls = await quiet.plan(userText: "Ile wydałem w Biedronce?", language: .pl)
        XCTAssertEqual(calls.count, 1)
    }
}

final class MailFeedTests: XCTestCase {
    func testStreamsEveryMatchNewestFirstAcrossPages() async throws {
        let box = FixtureMailbox(now: Date())
        let feed = MailFeed(sources: [(0, "demo", box)], query: "in:inbox", labelled: false, pageSize: 7)
        var all: [EmailSummary] = []
        while true {
            let batch = try await feed.next(10)
            if batch.isEmpty { break }
            all += batch
        }
        let expected = try await box.search(query: "in:inbox", limit: 1000)
        XCTAssertEqual(all.count, expected.count)
        XCTAssertGreaterThan(all.count, 30)
        XCTAssertEqual(all.map(\.date), all.compactMap(\.date).sorted(by: >).map { Optional($0) })
        let exhausted = await feed.isExhausted
        XCTAssertTrue(exhausted)
    }

    func testTwoMailboxesInterleaveByDateAndKeepTheirPositions() async throws {
        let now = Date()
        let a = FixtureMailbox(label: "a@x.com", now: now)
        let b = FixtureMailbox(label: "b@x.com", now: now.addingTimeInterval(-3000))
        let feed = MailFeed(sources: [(0, "a@x.com", a), (1, "b@x.com", b)], query: "in:inbox", labelled: true, pageSize: 10)
        let items = try await feed.next(40)
        XCTAssertEqual(items.compactMap(\.date), items.compactMap(\.date).sorted(by: >))
        XCTAssertTrue(items.contains { $0.id.hasPrefix("0z") } && items.contains { $0.id.hasPrefix("1z") })
        XCTAssertEqual(Set(items.compactMap(\.account)), ["a@x.com", "b@x.com"])
    }

    func testFilteredFeedKeepsTheTrueAccountPosition() async throws {
        let provider = MultiEmailProvider {
            [.init(label: "a@x.com", provider: FixtureMailbox(label: "a@x.com"), paging: FixtureMailbox(label: "a@x.com")),
             .init(label: "b@x.com", provider: FixtureMailbox(label: "b@x.com"), paging: FixtureMailbox(label: "b@x.com"))]
        }
        let maybeFeed = await provider.feed(query: "in:inbox", account: "b@")
        let feed = try XCTUnwrap(maybeFeed)
        let items = try await feed.next(3)
        XCTAssertTrue(items.allSatisfy { $0.id.hasPrefix("1z") })
        XCTAssertTrue(items.allSatisfy { $0.account == "b@x.com" })
        let email = try await provider.message(id: items[0].id)
        XCTAssertEqual(email.summary.account, "b@x.com")
    }

    private struct Broken: MailboxPaging {
        func page(query: String, pageToken: String?, size: Int) async throws -> EmailPage { throw ToolError("sign-in expired") }
    }

    func testOneBrokenMailboxIsReportedNotFatal() async throws {
        let feed = MailFeed(sources: [(0, "a", Broken()), (1, "b", FixtureMailbox(label: "b"))], query: "in:inbox", labelled: true)
        let items = try await feed.next(5)
        XCTAssertEqual(items.count, 5)
        let failed = await feed.failedAccounts
        XCTAssertEqual(failed, ["a"])
    }

    func testAllBrokenThrows() async {
        let feed = MailFeed(sources: [(0, "a", Broken())], query: "x", labelled: false)
        do { _ = try await feed.next(5); XCTFail() } catch let error as ToolError { XCTAssertEqual(error.message, "sign-in expired") } catch { XCTFail() }
    }
}

final class SearchEmailHarnessTests: XCTestCase {
    func testTodayReportsTheTrueCountGroupedAndCleaned() async throws {
        let now = Date()
        let box = FixtureMailbox(now: now)
        let tool = SearchEmailTool(provider: MultiEmailProvider { [.init(label: "demo@example.com", provider: box, paging: box)] }, clock: ToolClock(now: { now }))
        let result = try await tool.run(argumentsJSON: #"{"when":"today"}"#)
        let truth = try await box.search(query: EmailQueryBuilder(clock: ToolClock(now: { now })).gmailQuery(EmailQuerySpec(when: .today)), limit: 1000)
        XCTAssertEqual(truth.count, 17)
        XCTAssertTrue(result.contains("Found 17 emails"), result)
        XCTAssertTrue(result.contains("This is every match."))
        XCTAssertTrue(result.contains("PEOPLE: 4") && result.contains("PROMOTIONS: 5") && result.contains("UPDATES AND NOTICES: 7") && result.contains("SOCIAL: 1"), result)
        XCTAssertTrue(result.hasPrefix(EmailContent.warning))
        XCTAssertFalse(result.contains("482913"), "verification code must not reach the model")
        XCTAssertTrue(result.contains("Your verification code"), "the subject is listed, the code itself is not")
        XCTAssertTrue(result.contains("Searched: today"))
    }

    func testOnlyPeopleListsJustThatGroupAndStillCountsTheRest() async throws {
        let box = FixtureMailbox()
        let tool = SearchEmailTool(provider: MultiEmailProvider { [.init(label: "demo@example.com", provider: box, paging: box)] })
        let result = try await tool.run(argumentsJSON: #"{"when":"today","only":"people"}"#)
        XCTAssertTrue(result.contains("PEOPLE: 4"), result)
        XCTAssertFalse(result.contains("PROMOTIONS:") || result.contains("UPDATES AND NOTICES:"), result)
        XCTAssertTrue(result.contains("Not listed because the user asked only about one group"), result)
        XCTAssertTrue(result.contains("5 promotions"), result)
        XCTAssertLessThan(result.count, 1800, "small evidence keeps the small model fast")
    }

    func testCountsOnlyGivesExactCountsAndNoMessageLines() async throws {
        let box = FixtureMailbox()
        let tool = SearchEmailTool(provider: MultiEmailProvider { [.init(label: "demo@example.com", provider: box, paging: box)] })
        let result = try await tool.run(argumentsJSON: #"{"when":"today","counts_only":true}"#)
        XCTAssertTrue(result.contains("Found 17 emails") && result.contains("PEOPLE: 4") && result.contains("PROMOTIONS: 5"), result)
        XCTAssertFalse(result.contains("Anna Nowak") || result.contains("Subject"), "no message lines in a counts answer: \(result)")
        XCTAssertLessThan(result.count, 900)
    }

    func testUnreadFilterCountsOnlyUnread() async throws {
        let box = FixtureMailbox()
        let tool = SearchEmailTool(provider: MultiEmailProvider { [.init(label: "demo@example.com", provider: box, paging: box)] })
        let result = try await tool.run(argumentsJSON: #"{"unread":true}"#)
        XCTAssertTrue(result.contains("(5 unread)"), result)
        XCTAssertTrue(result.contains("Found 5 emails"), result)
    }

    func testCapSaysMoreExist() async throws {
        let box = FixtureMailbox()
        let maybeFeed = await box.feed(query: "in:inbox", account: nil)
        let feed = try XCTUnwrap(maybeFeed)
        let collected = try await EmailDigest.collect(from: feed, cap: 20)
        XCTAssertFalse(collected.complete)
        let text = EmailDigest.render(collected, searched: "latest inbox mail", accounts: ["demo"])
        XCTAssertTrue(text.contains("Found at least 20 emails"))
        XCTAssertTrue(text.contains("Mail screen"))
    }

    func testReadEmailStripsCodesAndSensitiveLinks() async throws {
        let box = FixtureMailbox()
        let text = try await ReadEmailTool(provider: box).run(argumentsJSON: #"{"id":"a005"}"#)
        XCTAssertFalse(text.contains("482913") || text.contains("zzz999"))
        XCTAssertTrue(text.contains("[code removed]") && text.contains("[sensitive link removed]"))
    }
}

final class GmailPagingTests: XCTestCase {
    func testPagesThroughListWithTokensAndReadsUnread() async throws {
        let seen = TokenBox()
        let client = GmailClient(isSignedIn: { true }, accessToken: { "t" }) { request in
            let url = request.url!
            let ok = { (json: String) in (Data(json.utf8), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!) }
            if url.path.hasSuffix("/labels/INBOX") { return ok(#"{"messagesUnread":7}"#) }
            if url.path.hasSuffix("/messages") {
                let token = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "pageToken" }?.value
                seen.add(token ?? "none")
                return token == nil
                    ? ok(#"{"messages":[{"id":"m1"},{"id":"m2"}],"nextPageToken":"T2","resultSizeEstimate":3}"#)
                    : ok(#"{"messages":[{"id":"m3"}],"resultSizeEstimate":3}"#)
            }
            let id = url.lastPathComponent
            return ok(#"{"id":"\#(id)","internalDate":"1800000000000","labelIds":["CATEGORY_PROMOTIONS"],"payload":{"headers":[{"name":"From","value":"Shop <hi@shop.example>"},{"name":"Subject","value":"Sale"},{"name":"List-Unsubscribe","value":"<x>"}]}}"#)
        }
        let first = try await client.page(query: "in:inbox", pageToken: nil, size: 2)
        XCTAssertEqual(first.items.map(\.id), ["m1", "m2"])
        XCTAssertEqual(first.nextToken, "T2")
        XCTAssertEqual(first.estimatedTotal, 3)
        XCTAssertEqual(first.items[0].kind, .promotions)
        let second = try await client.page(query: "in:inbox", pageToken: "T2", size: 2)
        XCTAssertEqual(second.items.map(\.id), ["m3"])
        XCTAssertNil(second.nextToken)
        XCTAssertEqual(seen.all, ["none", "T2"])
        let unread = await client.unreadCount()
        XCTAssertEqual(unread, 7)
    }

    func testKindFromHeadersAndAddresses() {
        XCTAssertEqual(GmailClient.kind(labels: ["CATEGORY_UPDATES"], from: "x@y.com", bulk: false), .updates)
        XCTAssertEqual(GmailClient.kind(labels: [], from: "No Reply <noreply@x.com>", bulk: false), .updates)
        XCTAssertEqual(GmailClient.kind(labels: [], from: "Jan <jan@x.com>", bulk: true), .updates)
        XCTAssertEqual(GmailClient.kind(labels: ["INBOX"], from: "Jan <jan@x.com>", bulk: false), .person)
    }

    func testAddressParsing() {
        XCTAssertEqual(EmailAddress.parse("Jan Kowalski <jan@x.com>").name, "Jan Kowalski")
        XCTAssertEqual(EmailAddress.parse("\"Kowalski, Jan\" <jan@x.com>").address, "jan@x.com")
        XCTAssertEqual(EmailAddress.parse("plain@x.com").address, "plain@x.com")
    }
}

private final class TokenBox: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String] = []
    func add(_ value: String) { lock.lock(); values.append(value); lock.unlock() }
    var all: [String] { lock.lock(); defer { lock.unlock() }; return values }
}
