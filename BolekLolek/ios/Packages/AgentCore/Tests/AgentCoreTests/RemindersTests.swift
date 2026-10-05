import XCTest
@testable import AgentCore

private actor MemoryReminders: RemindersProviding {
    private var items: [ReminderInfo] = []
    private(set) var repeatsSeen: [ScheduledNotification.Repeat?] = []
    func add(title: String, due: Date, repeats: ScheduledNotification.Repeat?) async throws -> ReminderInfo {
        let item = ReminderInfo(id: UUID().uuidString, title: title, due: due)
        items.append(item); repeatsSeen.append(repeats); return item
    }
    func pending() async throws -> [ReminderInfo] { items }
    func complete(id: String) async throws { items.removeAll { $0.id == id } }
    func seed(_ titles: [String]) { items = titles.map { ReminderInfo(id: $0, title: $0, due: nil) } }
}

private struct ShouldNotBeUsed: NotificationScheduling {
    func schedule(_ notification: ScheduledNotification) async throws { XCTFail("a reminder must go to the Reminders app, not a loose notification") }
}

private struct LegacySink: NotificationScheduling {
    let count: Counter
    func schedule(_ notification: ScheduledNotification) async throws { await count.bump() }
}
private actor Counter { var value = 0; func bump() { value += 1 } }

final class RemindersTests: XCTestCase {
    private var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Australia/Perth")!; return c }
    private func clock() -> ToolClock { ToolClock(now: { self.cal.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 10))! }, calendar: cal) }

    func testReminderGoesToTheRemindersAppAndNotToANotification() async throws {
        let box = MemoryReminders()
        let tool = AddReminderTool(notifications: ShouldNotBeUsed(), reminders: box, clock: clock())
        let reply = try await tool.run(argumentsJSON: #"{"title":"Zadzwonić do mamy","when":"2026-10-06T18:00","repeat":"weekly"}"#)
        XCTAssertTrue(reply.contains("Reminders app"), reply)
        let pending = try await box.pending()
        XCTAssertEqual(pending.map(\.title), ["Zadzwonić do mamy"])
        XCTAssertEqual(pending.first?.due, cal.date(from: DateComponents(year: 2026, month: 10, day: 6, hour: 18)))
        let repeats = await box.repeatsSeen
        XCTAssertEqual(repeats, [.weekly])
    }

    func testWithoutTheRemindersAppItStillFallsBackToANotification() async throws {
        let count = Counter()
        let tool = AddReminderTool(notifications: LegacySink(count: count), reminders: nil, clock: clock())
        _ = try await tool.run(argumentsJSON: #"{"title":"x","when":"2026-10-06T18:00"}"#)
        let value = await count.value
        XCTAssertEqual(value, 1)
    }

    func testPastTimesAreRefusedBeforeAnythingIsAdded() async throws {
        let box = MemoryReminders()
        let tool = AddReminderTool(notifications: ShouldNotBeUsed(), reminders: box, clock: clock())
        do { _ = try await tool.run(argumentsJSON: #"{"title":"x","when":"2026-10-01T18:00"}"#); XCTFail() } catch is ToolError {}
        let pending = try await box.pending()
        XCTAssertTrue(pending.isEmpty)
    }

    func testListShowsOpenRemindersByDueDate() async throws {
        let box = MemoryReminders()
        _ = try await box.add(title: "Later", due: cal.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 9))!, repeats: nil)
        _ = try await box.add(title: "Sooner", due: cal.date(from: DateComponents(year: 2026, month: 10, day: 6, hour: 9))!, repeats: nil)
        let text = try await ListRemindersTool(reminders: box, clock: clock()).run(argumentsJSON: "{}")
        XCTAssertLessThan(text.range(of: "Sooner")!.lowerBound, text.range(of: "Later")!.lowerBound)
    }

    func testTickingOffFindsTheRightOneAndNeverGuessesBetweenTwo() async throws {
        let box = MemoryReminders()
        await box.seed(["Kupić mleko", "Kupić chleb", "Zadzwonić do mamy"])
        let tool = CompleteReminderTool(reminders: box, clock: clock())
        let done = try await tool.run(argumentsJSON: #"{"title":"the reminder zadzwonić do mamy"}"#)
        XCTAssertTrue(done.contains("Zadzwonić do mamy"), done)
        do { _ = try await tool.run(argumentsJSON: #"{"title":"kupić"}"#); XCTFail("guessed between milk and bread") } catch let error as ToolError {
            XCTAssertTrue(error.message.contains("2 reminders match"), error.message)
        }
        let left = try await box.pending().map(\.title).sorted()
        XCTAssertEqual(left, ["Kupić chleb", "Kupić mleko"])
        do { _ = try await tool.run(argumentsJSON: #"{"title":"zebra"}"#); XCTFail() } catch is ToolError {}
        do { _ = try await tool.run(argumentsJSON: #"{"title":"call mom"}"#); XCTFail("a half-matching name must not tick something off") } catch is ToolError {}
    }
}
