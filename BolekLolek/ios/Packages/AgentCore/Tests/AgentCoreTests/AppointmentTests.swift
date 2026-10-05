import XCTest
@testable import AgentCore

private let perth = TimeZone(identifier: "Australia/Perth")!
private func calendar() -> Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = perth; c.firstWeekday = 2; return c }
private func date(_ iso: String) -> Date {
    let f = ISO8601DateFormatter(); f.timeZone = perth; f.formatOptions = [.withInternetDateTime]
    return f.date(from: iso)!
}
private func local(_ d: Date?) -> String {
    guard let d else { return "nil" }
    let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = perth; f.dateFormat = "yyyy-MM-dd HH:mm"; return f.string(from: d)
}
private let now = date("2026-10-05T10:00:00+08:00")  // a Monday

final class AppointmentExtractorTests: XCTestCase {
    private func found(_ subject: String, _ body: String, invite: String? = nil) -> [AppointmentCandidate] {
        AppointmentExtractor.candidates(subject: subject, body: body, invite: invite, received: now, now: now, calendar: calendar())
    }

    func testPolishNumericDateWithTimeAndLocation() {
        let result = found("Wizyta kontrolna", "Przypominamy o wizycie 14.01.2027 o godz. 10:30.\nAdres: ul. Marszałkowska 10, Warszawa")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(local(result[0].start), "2027-01-14 10:30")
        XCTAssertEqual(result[0].location, "ul. Marszałkowska 10, Warszawa")
        XCTAssertEqual(result[0].title, "Wizyta kontrolna")
    }

    func testPaymentDeadlinesWithoutATimeAreNotAppointments() {
        XCTAssertTrue(found("Faktura", "Termin płatności: 20.10.2026. Kwota 212,55 zł.").isEmpty)
    }

    func testSpelledOutPolishAndEnglishDates() {
        XCTAssertEqual(local(found("Spotkanie", "Spotkajmy się 12 października o 14:30.").first?.start), "2026-10-12 14:30")
        XCTAssertEqual(local(found("Meeting", "See you on October 12 at 2:30 PM.").first?.start), "2026-10-12 14:30")
        XCTAssertEqual(local(found("Rezerwacja", "Zameldowanie 3 grudnia 2026, godz. 16").first?.start), "2026-12-03 16:00")
    }

    func testWeekdayMeansTheNextOne() {
        XCTAssertEqual(local(found("Sync", "Can we do Thursday at 3pm?").first?.start), "2026-10-08 15:00")
        XCTAssertEqual(local(found("Sync", "Widzimy się w czwartek o 15:00").first?.start), "2026-10-08 15:00")
        XCTAssertEqual(local(found("Sync", "Jutro o 9:15 w biurze").first?.start), "2026-10-06 09:15")
    }

    func testTimeRangeGivesAnEnd() {
        let result = found("Workshop", "Workshop on 2026-11-02 from 10:00 to 12:30")
        XCTAssertEqual(local(result.first?.start), "2026-11-02 10:00")
        XCTAssertEqual(local(result.first?.end), "2026-11-02 12:30")
    }

    func testYearlessDateInThePastRollsToNextYear() {
        XCTAssertEqual(local(found("Urodziny", "Impreza 2 marca o 18:00").first?.start), "2027-03-02 18:00")
    }

    func testPastAppointmentsAreDropped() {
        XCTAssertTrue(found("Old", "Meeting was on 2026-01-10 at 10:00").isEmpty)
    }

    func testInviteWinsAndReadsTimeZoneLocationAndTitle() {
        let ics = "BEGIN:VCALENDAR\r\nMETHOD:REQUEST\r\nBEGIN:VEVENT\r\nDTSTART;TZID=Europe/Warsaw:20270120T150000\r\nDTEND;TZID=Europe/Warsaw:20270120T160000\r\nSUMMARY:Przegląd\\, projektu\r\nLOCATION:Google Meet\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n"
        let result = found("Invitation", "see attached 14.01.2027 o 10:30", invite: ics)
        XCTAssertEqual(result.count, 1, "the invite replaces anything guessed from the text")
        XCTAssertEqual(result[0].title, "Przegląd, projektu")
        XCTAssertEqual(result[0].location, "Google Meet")
        XCTAssertTrue(result[0].fromInvite)
        XCTAssertEqual(local(result[0].start), "2027-01-20 22:00", "15:00 Warsaw is 22:00 in Perth")
        XCTAssertEqual(result[0].effectiveEnd.timeIntervalSince(result[0].start), 3600)
    }

    func testUtcAndAllDayInvitesAndCancellations() {
        let utc = "BEGIN:VEVENT\nDTSTART:20270120T070000Z\nSUMMARY:Call\nEND:VEVENT"
        XCTAssertEqual(local(found("x", "", invite: utc).first?.start), "2027-01-20 15:00")
        let allDay = "BEGIN:VEVENT\nDTSTART;VALUE=DATE:20270201\nSUMMARY:Holiday\nEND:VEVENT"
        XCTAssertEqual(local(found("x", "", invite: allDay).first?.start), "2027-02-01 09:00")
        let cancelled = "METHOD:CANCEL\nBEGIN:VEVENT\nDTSTART:20270120T070000Z\nSUMMARY:Call\nEND:VEVENT"
        XCTAssertTrue(found("x", "", invite: cancelled).first?.isCancelled == true)
    }

    func testReplyPrefixesAreRemovedFromTheTitle() {
        XCTAssertEqual(found("Re: Fwd: Lunch", "Lunch 2026-10-09 at 12:30").first?.title, "Lunch")
        XCTAssertEqual(found("Odp: Obiad", "Obiad 2026-10-09 o 12:30").first?.title, "Obiad")
    }

    func testListHintNeedsBothDateAndTime() {
        XCTAssertTrue(AppointmentExtractor.mentionsDateAndTime("Wizyta 14.01.2027 o godz. 10:30", now: now, calendar: calendar()))
        XCTAssertFalse(AppointmentExtractor.mentionsDateAndTime("Termin płatności 20.10.2026", now: now, calendar: calendar()))
    }
}

final class CalendarFlowTests: XCTestCase {
    private let cal = calendar()

    func testReadEmailListsAppointmentsWithExactValues() async throws {
        let box = FixtureMailbox(now: now, calendar: cal)
        let tool = ReadEmailTool(provider: box, clock: ToolClock(now: { now }, calendar: cal))
        let text = try await tool.run(argumentsJSON: #"{"id":"d0a1"}"#)
        XCTAssertTrue(text.contains("Appointments found in this email"), text)
        XCTAssertTrue(text.contains("start: 2027-01-14T10:30"), text)
        XCTAssertTrue(text.contains("location: ul. Marszałkowska 10, Warszawa"), text)
        XCTAssertFalse(text.contains("20.10.2026") && text.contains("start: 2026-10-20"), "the payment deadline is not an appointment")
    }

    func testCalendarRequestWithAnOpenedEmailPlansTheEvent() async throws {
        let box = FixtureMailbox(now: now, calendar: cal)
        let focus = EmailFocus()
        let planner = EmailPlanner(focus: focus, provider: box, clock: ToolClock(now: { now }, calendar: cal), isConnected: { true })
        await focus.set(id: "d0a1")
        let first = await planner.plan(userText: "Summarise this email.", language: .en)
        XCTAssertEqual(first.first?.name, "read_email")
        let second = await planner.plan(userText: "Dodaj to do kalendarza", language: .pl)
        let call = try XCTUnwrap(second.first)
        XCTAssertEqual(call.name, "add_calendar_event")
        let args = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(call.argumentsJSON.utf8)) as? [String: Any])
        XCTAssertEqual(args["start"] as? String, "2027-01-14T10:30")
        XCTAssertEqual(args["end"] as? String, "2027-01-14T11:30")
        XCTAssertEqual(args["title"] as? String, "Lolek test – wizyta kontrolna")
    }

    func testNothingIsPlannedWithoutAnOpenEmailOrWithoutCalendarWords() async {
        let box = FixtureMailbox(now: now, calendar: cal)
        let focus = EmailFocus()
        let planner = EmailPlanner(focus: focus, provider: box, clock: ToolClock(now: { now }, calendar: cal), isConnected: { true })
        let none = await planner.plan(userText: "Dodaj to do kalendarza", language: .pl)
        XCTAssertTrue(none.isEmpty)
        await focus.set(id: "d0a1")
        _ = await planner.plan(userText: "Summarise", language: .en)
        let other = await planner.plan(userText: "Kiedy ta wizyta?", language: .pl)
        XCTAssertTrue(other.isEmpty)
    }

    func testEventsFilterFindsInvitesAndAppointmentMails() async throws {
        let box = FixtureMailbox(now: now, calendar: cal)
        let found = try await box.search(query: "in:inbox {subject:(appointment OR meeting) filename:ics}", limit: 50)
        let ids = Set(found.map(\.id))
        XCTAssertTrue(ids.contains("d0a1") && ids.contains("d0a3") && ids.contains("d0a2"))
        XCTAssertLessThan(found.count, 8, "ordinary mail is not an event")
    }

    func testGmailInviteAttachmentIsFetched() async throws {
        let ics = "BEGIN:VEVENT\nDTSTART:20270120T070000Z\nSUMMARY:Call\nEND:VEVENT"
        let encoded = Data(ics.utf8).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        let client = GmailClient(isSignedIn: { true }, accessToken: { "t" }) { request in
            let url = request.url!
            let ok = { (json: String) in (Data(json.utf8), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!) }
            if url.path.hasSuffix("/attachments/ATT-1_x") { return ok(#"{"data":"\#(encoded)"}"#) }
            return ok(#"{"id":"m1","internalDate":"1","payload":{"mimeType":"multipart/mixed","headers":[{"name":"Subject","value":"Invite"}],"parts":[{"mimeType":"text/plain","body":{"data":"aGk"}},{"mimeType":"application/ics","filename":"invite.ics","body":{"attachmentId":"ATT-1_x"}}]}}"#)
        }
        let message = try await client.message(id: "m1")
        XCTAssertEqual(message.invite, ics)
        let items = message.appointments(now: now, calendar: cal)
        XCTAssertEqual(items.first?.title, "Call")
    }
}

final class InviteThroughTheAppPathTests: XCTestCase {
    func testInviteEmailThroughTheMultiProviderPlansTheEventWithTheInvitesValues() async throws {
        let cal = calendar()
        let box = FixtureMailbox(now: now, calendar: cal)
        let provider = MultiEmailProvider { [.init(label: "demo@example.com", provider: box, paging: box)] }
        let focus = EmailFocus()
        let planner = EmailPlanner(focus: focus, provider: provider, clock: ToolClock(now: { now }, calendar: cal), isConnected: { true })
        // Ids reach the planner with the account position in front, exactly as the Mail screen hands them over.
        await focus.set(id: "0zd0a3")
        let first = await planner.plan(userText: "Summarise this email.", language: .en)
        XCTAssertEqual(first.first?.name, "read_email")
        let message = try await provider.message(id: "0zd0a3")
        XCTAssertNotNil(message.invite, "the fixture invite must come through the provider")
        XCTAssertEqual(message.appointments(now: now, calendar: cal).count, 1)
        let second = await planner.plan(userText: "Dodaj to do kalendarza", language: .pl)
        let call = try XCTUnwrap(second.first, "planner must propose the invite's event")
        XCTAssertEqual(call.name, "add_calendar_event")
        XCTAssertTrue(call.argumentsJSON.contains("Lolek test – przegląd projektu"), call.argumentsJSON)
        XCTAssertTrue(call.argumentsJSON.contains("2027-01-20T22:00"), "15:00 Warsaw in the phone's zone: \(call.argumentsJSON)")
    }
}
