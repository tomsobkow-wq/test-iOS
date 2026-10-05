import XCTest
@testable import AgentCore

private actor MemoryCalendar: CalendarProviding {
    private var items: [CalendarEventInfo]
    init(_ items: [CalendarEventInfo]) { self.items = items }
    func events(from: Date, to: Date) async throws -> [CalendarEventInfo] { items.filter { $0.start >= from && $0.start < to } }
    func addEvent(title: String, start: Date, end: Date, location: String?) async throws -> CalendarEventInfo {
        let e = CalendarEventInfo(title: title, start: start, end: end, location: location, id: UUID().uuidString)
        items.append(e); return e
    }
    func updateEvent(id: String, title: String?, start: Date?, end: Date?, location: String?) async throws -> CalendarEventInfo {
        guard let index = items.firstIndex(where: { $0.id == id }) else { throw ToolError("gone") }
        let old = items[index]
        let newStart = start ?? old.start
        let newEnd = end ?? (start != nil ? newStart.addingTimeInterval(old.end.timeIntervalSince(old.start)) : old.end)
        items[index] = CalendarEventInfo(title: title ?? old.title, start: newStart, end: newEnd, location: location ?? old.location, id: id)
        return items[index]
    }
    func deleteEvent(id: String) async throws { items.removeAll { $0.id == id } }
    var all: [CalendarEventInfo] { items }
}

final class CalendarEditTests: XCTestCase {
    private var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Australia/Perth")!; return c }
    private func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int = 0) -> Date { cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))! }
    private var now: Date { at(2026, 10, 5, 10) }
    private func clock() -> ToolClock { ToolClock(now: { self.now }, calendar: cal) }

    private func make() -> MemoryCalendar {
        MemoryCalendar([
            CalendarEventInfo(title: "Wizyta kontrolna", start: at(2027, 1, 14, 10, 30), end: at(2027, 1, 14, 11, 30), id: "a"),
            CalendarEventInfo(title: "Team sync", start: at(2026, 10, 8, 15), end: at(2026, 10, 8, 16), id: "b"),
            CalendarEventInfo(title: "Team sync", start: at(2026, 10, 15, 15), end: at(2026, 10, 15, 16), id: "c"),
        ])
    }

    func testMoveKeepsTheLengthAndChangesOnlyTheTime() async throws {
        let box = make()
        let tool = RescheduleCalendarEventTool(calendar: box, clock: clock())
        let reply = try await tool.run(argumentsJSON: #"{"title":"wizyta","new_start":"2027-01-21T09:00"}"#)
        XCTAssertTrue(reply.contains("Moved"), reply)
        let moved = await box.all.first { $0.id == "a" }
        XCTAssertEqual(moved?.start, at(2027, 1, 21, 9))
        XCTAssertEqual(moved?.end, at(2027, 1, 21, 10), "still one hour")
        XCTAssertEqual(moved?.title, "Wizyta kontrolna")
    }

    func testExtraWordsAroundTheTitleDoNotBreakTheMatch() async throws {
        let box = make()
        let tool = RescheduleCalendarEventTool(calendar: box, clock: clock())
        for title in ["Wizyta kontrolna appointment", "the wizyta kontrolna", "wizyta kontrolna event", "Lolek wizyta kontrolna"] {
            _ = try await tool.run(argumentsJSON: "{\"title\":\"\(title)\",\"new_start\":\"2027-01-21T09:00\"}")
        }
        let moved = await box.all.filter { $0.title == "Wizyta kontrolna" }
        XCTAssertEqual(moved.count, 1)
    }

    func testAWrongDayFromTheModelDoesNotHideTheEvent() async throws {
        let box = make()
        // The model put today's date in "on" although the event is in January.
        let tool = RescheduleCalendarEventTool(calendar: box, clock: clock())
        _ = try await tool.run(argumentsJSON: #"{"title":"Wizyta kontrolna","on":"2026-10-05","new_start":"2027-01-21T09:00:00"}"#)
        let moved = await box.all.first { $0.id == "a" }
        XCTAssertEqual(moved?.start, at(2027, 1, 21, 9))
        let delete = DeleteCalendarEventTool(calendar: box, clock: clock())
        _ = try await delete.run(argumentsJSON: #"{"title":"wizyta","on":"2026-12-24"}"#)
        let left = await box.all.map(\.id).sorted()
        XCTAssertEqual(left, ["b", "c"])
    }

    func testARightDayStillNarrowsBetweenTwoSimilarEvents() async throws {
        let box = make()
        _ = try await DeleteCalendarEventTool(calendar: box, clock: clock()).run(argumentsJSON: #"{"title":"Team sync","on":"2026-10-08"}"#)
        let left = await box.all.map(\.id).sorted()
        XCTAssertEqual(left, ["a", "c"])
    }

    func testAWrongOrUnrelatedTitleStillMatchesNothing() async {
        let tool = DeleteCalendarEventTool(calendar: make(), clock: clock())
        for title in ["Dentist", "zebra kontrolna", "appointment"] {
            do { _ = try await tool.run(argumentsJSON: "{\"title\":\"\(title)\"}"); XCTFail(title) } catch is ToolError {} catch { XCTFail() }
        }
    }

    func testTwoMatchesNeverGuess() async throws {
        let box = make()
        let tool = RescheduleCalendarEventTool(calendar: box, clock: clock())
        do { _ = try await tool.run(argumentsJSON: #"{"title":"Team sync","new_start":"2026-10-20T15:00"}"#); XCTFail("moved one of two") } catch let error as ToolError {
            XCTAssertTrue(error.message.contains("2 events match"), error.message)
        }
        let unchanged = await box.all
        XCTAssertEqual(unchanged.filter { $0.title == "Team sync" }.map(\.start).sorted(), [at(2026, 10, 8, 15), at(2026, 10, 15, 15)])
    }

    func testTheDayNarrowsItToOne() async throws {
        let box = make()
        let tool = DeleteCalendarEventTool(calendar: box, clock: clock())
        let reply = try await tool.run(argumentsJSON: #"{"title":"Team sync","on":"2026-10-15"}"#)
        XCTAssertTrue(reply.contains("Deleted"), reply)
        let left = await box.all.map(\.id).sorted()
        XCTAssertEqual(left, ["a", "b"])
    }

    func testNoMatchSaysWhatIsThereInstead() async {
        let tool = DeleteCalendarEventTool(calendar: make(), clock: clock())
        do { _ = try await tool.run(argumentsJSON: #"{"title":"Dentist"}"#); XCTFail() } catch let error as ToolError {
            XCTAssertTrue(error.message.contains("No calendar event matches"), error.message)
            XCTAssertTrue(error.message.contains("Team sync"), "lists what is nearby so the user can say which")
        } catch { XCTFail() }
    }

    func testDeleteAndMoveNeedApprovalAndDeleteIsMarkedDestructive() {
        let box = make()
        XCTAssertTrue(RescheduleCalendarEventTool(calendar: box, clock: clock()).risk.needsApproval)
        XCTAssertEqual(DeleteCalendarEventTool(calendar: box, clock: clock()).risk, .destructive)
    }

    func testBadNewEndIsRefusedBeforeAnythingChanges() async throws {
        let box = make()
        let tool = RescheduleCalendarEventTool(calendar: box, clock: clock())
        do { _ = try await tool.run(argumentsJSON: #"{"title":"wizyta","new_start":"2027-01-21T09:00","new_end":"2027-01-21T08:00"}"#); XCTFail() } catch is ToolError {}
        let same = await box.all.first { $0.id == "a" }
        XCTAssertEqual(same?.start, at(2027, 1, 14, 10, 30))
    }
}

private actor FakeAlarms: AlarmManaging {
    var items: [AlarmInfo]
    init(_ items: [AlarmInfo]) { self.items = items }
    func pending() async -> [AlarmInfo] { items }
    func cancel(id: String) async throws { items.removeAll { $0.id == id } }
    var ids: [String] { items.map(\.id) }
}

final class AlarmToolsTests: XCTestCase {
    private var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Australia/Perth")!; return c }
    private func clock() -> ToolClock { ToolClock(now: { self.cal.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 6))! }, calendar: cal) }
    private func at(_ h: Int, _ m: Int) -> Date { cal.date(from: DateComponents(year: 2026, month: 10, day: 6, hour: h, minute: m))! }

    func testListAndCancelByLabelOrTime() async throws {
        let alarms = FakeAlarms([AlarmInfo(id: "11111111-aaaa", title: "Wake up", fireDate: at(7, 15)), AlarmInfo(id: "22222222-bbbb", title: "Lolek test", fireDate: at(8, 30), isTimer: false)])
        let listed = try await ListAlarmsTool(alarms: alarms, clock: clock()).run(argumentsJSON: "{}")
        XCTAssertTrue(listed.contains("Wake up") && listed.contains("Lolek test"), listed)
        let byLabel = try await CancelAlarmTool(alarms: alarms, clock: clock()).run(argumentsJSON: #"{"label":"wake"}"#)
        XCTAssertTrue(byLabel.contains("Cancelled \"Wake up\""), byLabel)
        let byTime = try await CancelAlarmTool(alarms: alarms, clock: clock()).run(argumentsJSON: #"{"time":"08:30"}"#)
        XCTAssertTrue(byTime.contains("Lolek test"), byTime)
        let left = await alarms.ids
        XCTAssertTrue(left.isEmpty)
    }

    func testAmbiguousCancelAsksInsteadOfGuessing() async throws {
        let alarms = FakeAlarms([AlarmInfo(id: "1", title: "A", fireDate: at(7, 0)), AlarmInfo(id: "2", title: "B", fireDate: at(8, 0))])
        do { _ = try await CancelAlarmTool(alarms: alarms, clock: clock()).run(argumentsJSON: "{}"); XCTFail() } catch let error as ToolError {
            XCTAssertTrue(error.message.contains("2 alarms or timers"), error.message)
        }
        let count = await alarms.ids.count
        XCTAssertEqual(count, 2)
        let all = try await CancelAlarmTool(alarms: alarms, clock: clock()).run(argumentsJSON: #"{"all":true}"#)
        XCTAssertTrue(all.contains("2 alarms and timers"), all)
    }

    func testSetAlarmReplyIsHonestAboutTheClockApp() async throws {
        struct Sink: NotificationScheduling { func schedule(_ notification: ScheduledNotification) async throws {} }
        let reply = try await SetAlarmTool(notifications: Sink(), clock: clock()).run(argumentsJSON: #"{"time":"07:15","label":"Wake up"}"#)
        XCTAssertTrue(reply.contains("not listed in the Clock app"), reply)
    }
}
