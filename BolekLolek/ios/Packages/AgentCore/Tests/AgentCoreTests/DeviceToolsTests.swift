import XCTest
@testable import AgentCore

private let warsaw: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
    calendar.firstWeekday = 2
    return calendar
}()

/// Monday 2026-10-05 09:41 Warsaw time.
private let now = warsaw.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 9, minute: 41))!
private let clock = ToolClock(now: { now }, calendar: warsaw)

private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12, _ min: Int = 0) -> Date {
    warsaw.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
}

// MARK: - Fakes

private actor Recorder {
    var notifications: [ScheduledNotification] = []
    var openedURLs: [URL] = []
    var addedEvents: [CalendarEventInfo] = []
    func add(_ n: ScheduledNotification) { notifications.append(n) }
    func open(_ u: URL) { openedURLs.append(u) }
    func add(_ e: CalendarEventInfo) { addedEvents.append(e) }
}

private struct FakeServices: NotificationScheduling, URLOpening, CalendarProviding, ContactsProviding, WeatherProviding {
    let recorder = Recorder()
    var contactList: [ContactInfo] = []
    var openSucceeds = true

    func schedule(_ notification: ScheduledNotification) async throws { await recorder.add(notification) }
    func open(_ url: URL) async -> Bool { await recorder.open(url); return openSucceeds }
    func events(from: Date, to: Date) async throws -> [CalendarEventInfo] {
        [CalendarEventInfo(title: "Dentist", start: date(2026, 10, 8, 16, 30), end: date(2026, 10, 8, 17, 15), location: "Puławska 41")]
    }
    func addEvent(title: String, start: Date, end: Date, location: String?) async throws -> CalendarEventInfo {
        let event = CalendarEventInfo(title: title, start: start, end: end, location: location)
        await recorder.add(event)
        return event
    }
    func find(name: String) async throws -> [ContactInfo] {
        contactList.filter { $0.name.localizedCaseInsensitiveContains(name) }
    }
    func weather(for place: String?) async throws -> WeatherReport {
        WeatherReport(place: place ?? "Current location", temperatureC: 14.4, condition: "Cloudy", highC: 16, lowC: 9, precipitationChancePercent: 60)
    }
}

final class AmountParserTests: XCTestCase {
    func testPolishFormats() {
        XCTAssertEqual(AmountParser.parse("12,50 zł"), .init(minorUnits: 1250, currency: "PLN"))
        XCTAssertEqual(AmountParser.parse("1 234,50 zł"), .init(minorUnits: 123_450, currency: "PLN"))
        XCTAssertEqual(AmountParser.parse("1.234,50"), .init(minorUnits: 123_450, currency: "PLN"))
        XCTAssertEqual(AmountParser.parse("45"), .init(minorUnits: 4500, currency: "PLN"))
        XCTAssertEqual(AmountParser.parse("-45,00 PLN"), .init(minorUnits: 4500, currency: "PLN"))
    }

    func testOtherCurrencies() {
        XCTAssertEqual(AmountParser.parse("€9.99"), .init(minorUnits: 999, currency: "EUR"))
        XCTAssertEqual(AmountParser.parse("12.5 USD"), .init(minorUnits: 1250, currency: "USD"))
        XCTAssertEqual(AmountParser.parse("£1,200"), .init(minorUnits: 120_000, currency: "GBP"))
    }

    func testGarbageIsRejected() {
        XCTAssertNil(AmountParser.parse("abc"))
        XCTAssertNil(AmountParser.parse(""))
    }

    func testFormat() {
        XCTAssertEqual(AmountParser.format(123_450, currency: "PLN"), "1234.50 PLN")
        XCTAssertEqual(AmountParser.format(5, currency: "PLN"), "0.05 PLN")
    }
}

final class CategorizerTests: XCTestCase {
    func testKnownMerchants() {
        XCTAssertEqual(ExpenseCategorizer.category(forMerchant: "BIEDRONKA 1234"), "groceries")
        XCTAssertEqual(ExpenseCategorizer.category(forMerchant: "Żabka Z1234"), "groceries")
        XCTAssertEqual(ExpenseCategorizer.category(forMerchant: "Uber *Trip"), "transport")
        XCTAssertEqual(ExpenseCategorizer.category(forMerchant: "Netflix.com"), "subscriptions")
        XCTAssertEqual(ExpenseCategorizer.category(forMerchant: "Some Random Shop"), "other")
    }
}

final class SpendingStoreTests: XCTestCase {
    func testAutomaticIgnoredWhileTrackingOff() async {
        let store = SpendingStore(fileURL: nil)
        let result = await store.add(Expense(date: now, minorUnits: 1000, currency: "PLN", merchant: "Lidl", category: "groceries", source: .automatic))
        XCTAssertEqual(result, .trackingOff)
        let count = await store.allExpenses.count
        XCTAssertEqual(count, 0)
    }

    func testManualAlwaysSaved() async {
        let store = SpendingStore(fileURL: nil)
        let result = await store.add(Expense(date: now, minorUnits: 1000, currency: "PLN", merchant: "Lunch", category: "eating_out", source: .manual))
        guard case .added = result else { return XCTFail("expected added") }
    }

    func testDuplicateWithinAMinuteIsDropped() async {
        let store = SpendingStore(fileURL: nil)
        await store.setTracking(enabled: true)
        let first = Expense(date: now, minorUnits: 2500, currency: "PLN", merchant: "Lidl", category: "groceries", card: "Visa", source: .automatic)
        let second = Expense(date: now.addingTimeInterval(5), minorUnits: 2500, currency: "PLN", merchant: "Lidl", category: "groceries", card: "Visa", source: .automatic)
        _ = await store.add(first)
        let result = await store.add(second)
        XCTAssertEqual(result, .duplicate)
        let count = await store.allExpenses.count
        XCTAssertEqual(count, 1)
    }

    func testSummaryByPeriodAndCategory() async {
        let store = SpendingStore(fileURL: nil)
        await store.setTracking(enabled: true)
        _ = await store.add(Expense(date: date(2026, 10, 5, 8), minorUnits: 3000, currency: "PLN", merchant: "Lidl", category: "groceries", source: .automatic))
        _ = await store.add(Expense(date: date(2026, 10, 3, 8), minorUnits: 2000, currency: "PLN", merchant: "Uber", category: "transport", source: .automatic))
        _ = await store.add(Expense(date: date(2026, 9, 30, 8), minorUnits: 9900, currency: "PLN", merchant: "Biedronka", category: "groceries", source: .automatic))

        let week = SpendingPeriod.thisWeek.interval(now: now, calendar: warsaw)
        let thisWeek = await store.summaries(in: week)
        XCTAssertEqual(thisWeek.first?.totalMinorUnits, 3000, "Monday-based week: only today counts")

        let month = SpendingPeriod.thisMonth.interval(now: now, calendar: warsaw)
        let thisMonth = await store.summaries(in: month)
        XCTAssertEqual(thisMonth.first?.totalMinorUnits, 5000)
        XCTAssertEqual(thisMonth.first?.byCategory.first?.category, "groceries")

        let lastMonth = SpendingPeriod.lastMonth.interval(now: now, calendar: warsaw)
        let septemberGroceries = await store.summaries(in: lastMonth, category: "groceries")
        XCTAssertEqual(septemberGroceries.first?.totalMinorUnits, 9900)
    }

    func testPersistenceRoundTrip() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("spending-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = SpendingStore(fileURL: url)
        await store.setTracking(enabled: true)
        _ = await store.add(Expense(date: now, minorUnits: 1234, currency: "PLN", merchant: "Kawa", category: "eating_out", source: .automatic))

        let reloaded = SpendingStore(fileURL: url)
        let enabled = await reloaded.isTrackingEnabled
        let expenses = await reloaded.allExpenses
        XCTAssertTrue(enabled)
        XCTAssertEqual(expenses.first?.minorUnits, 1234)
    }
}

final class DeviceToolsTests: XCTestCase {
    private func toolbox(_ services: FakeServices, store: SpendingStore = SpendingStore(fileURL: nil)) -> [String: any Tool] {
        let all = DeviceToolbox.tools(
            services: DeviceServices(weather: services, calendar: services, contacts: services, notifications: services, urlOpener: services, spending: store),
            clock: clock
        )
        return Dictionary(uniqueKeysWithValues: all.map { ($0.name, $0) })
    }

    func testToolNamesAreUniqueAndAvailableToBothModes() {
        let tools = toolbox(FakeServices())
        let registry = ToolRegistry(Array(tools.values))
        XCTAssertEqual(registry.tools(for: .lolek).count, tools.count)
        XCTAssertEqual(registry.tools(for: .bolek).count, tools.count)
    }

    func testWeather() async throws {
        let out = try await toolbox(FakeServices())["get_weather"]!.run(argumentsJSON: #"{"place":"Warszawa"}"#)
        XCTAssertTrue(out.contains("Warszawa"))
        XCTAssertTrue(out.contains("14°C"))
        XCTAssertTrue(out.contains("60%"))
    }

    func testAlarmHHmmMeansNextOccurrence() async throws {
        let services = FakeServices()
        let out = try await toolbox(services)["set_alarm"]!.run(argumentsJSON: #"{"time":"06:30","label":"Gym"}"#)
        XCTAssertTrue(out.contains("2026-10-06 06:30"), out)
        let scheduled = await services.recorder.notifications
        XCTAssertEqual(scheduled.first?.title, "Gym")
        XCTAssertEqual(scheduled.first?.isAlarm, true)
    }

    func testAlarmInThePastIsRejected() async {
        do {
            _ = try await toolbox(FakeServices())["set_alarm"]!.run(argumentsJSON: #"{"time":"2026-10-05T08:00:00"}"#)
            XCTFail("expected error")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("past"))
        }
    }

    func testTimer() async throws {
        let services = FakeServices()
        _ = try await toolbox(services)["set_timer"]!.run(argumentsJSON: #"{"seconds":600}"#)
        let scheduled = await services.recorder.notifications
        XCTAssertEqual(scheduled.first?.fireDate, now.addingTimeInterval(600))
    }

    func testRecurringReminder() async throws {
        let services = FakeServices()
        let out = try await toolbox(services)["add_reminder"]!.run(
            argumentsJSON: #"{"title":"Pay rent","when":"2026-11-02T09:00:00","repeat":"monthly"}"#
        )
        XCTAssertTrue(out.contains("monthly"))
        let scheduled = await services.recorder.notifications
        XCTAssertEqual(scheduled.first?.repeats, .monthly)
    }

    func testCalendarAddDefaultsToOneHourAndNeedsApproval() async throws {
        let services = FakeServices()
        let tool = toolbox(services)["add_calendar_event"]!
        XCTAssertTrue(tool.risk.needsApproval)
        _ = try await tool.run(argumentsJSON: #"{"title":"Meeting with Marta","start":"2026-10-08T16:00:00"}"#)
        let events = await services.recorder.addedEvents
        XCTAssertEqual(events.first?.end.timeIntervalSince(events.first!.start), 3600)
    }

    func testListEvents() async throws {
        let out = try await toolbox(FakeServices())["list_calendar_events"]!.run(argumentsJSON: "{}")
        XCTAssertTrue(out.contains("Dentist"))
        XCTAssertTrue(out.contains("Puławska 41"))
    }

    func testTextContactBuildsSMSLinkAndNeedsApproval() async throws {
        var services = FakeServices()
        services.contactList = [ContactInfo(name: "Bob Smith", phoneNumbers: ["+48 600 111 222"])]
        let tool = toolbox(services)["text_contact"]!
        XCTAssertEqual(tool.risk, .send)
        _ = try await tool.run(argumentsJSON: #"{"to":"Bob","body":"Spóźnię się 10 minut"}"#)
        let url = await services.recorder.openedURLs.first
        XCTAssertEqual(url?.scheme, "sms")
        XCTAssertTrue(url?.absoluteString.hasPrefix("sms:+48600111222?body=") == true, url?.absoluteString ?? "nil")
        XCTAssertTrue(url?.absoluteString.contains("Sp%C3%B3%C5%BAni%C4%99") == true || url?.absoluteString.contains("Sp%C3%B3") == true)
    }

    func testCallByNumberSkipsContacts() async throws {
        let services = FakeServices()
        _ = try await toolbox(services)["call_contact"]!.run(argumentsJSON: #"{"to":"+48 600 111 222"}"#)
        let url = await services.recorder.openedURLs.first
        XCTAssertEqual(url?.absoluteString, "tel:+48600111222")
    }

    func testAmbiguousContactAsksForClarification() async {
        var services = FakeServices()
        services.contactList = [
            ContactInfo(name: "Bob Smith", phoneNumbers: ["+48600111222"]),
            ContactInfo(name: "Bob Jones", phoneNumbers: ["+48600333444"]),
        ]
        do {
            _ = try await toolbox(services)["call_contact"]!.run(argumentsJSON: #"{"to":"Bob"}"#)
            XCTFail("expected error")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Bob Smith"))
            XCTAssertTrue(error.localizedDescription.contains("Bob Jones"))
        }
    }

    func testUnknownContact() async {
        do {
            _ = try await toolbox(FakeServices())["text_contact"]!.run(argumentsJSON: #"{"to":"Nobody","body":"hi"}"#)
            XCTFail("expected error")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("No contact"))
        }
    }

    func testSpendingEndToEnd() async throws {
        let store = SpendingStore(fileURL: nil)
        let tools = toolbox(FakeServices(), store: store)

        let setup = try await tools["set_spending_tracking"]!.run(argumentsJSON: #"{"enabled":true}"#)
        XCTAssertTrue(setup.contains("Shortcuts"))
        let enabled = await store.isTrackingEnabled
        XCTAssertTrue(enabled)

        // What the Apple Pay automation does:
        _ = await store.add(Expense(date: now, minorUnits: 4590, currency: "PLN", merchant: "BIEDRONKA 22", category: "groceries", source: .automatic))
        _ = try await tools["log_expense"]!.run(argumentsJSON: #"{"amount":"20 zł","merchant":"Lunch","category":"eating_out"}"#)

        let summary = try await tools["spending_summary"]!.run(argumentsJSON: #"{"period":"today"}"#)
        XCTAssertTrue(summary.contains("65.90 PLN"), summary)
        XCTAssertTrue(summary.contains("groceries: 45.90 PLN"), summary)

        let groceriesOnly = try await tools["spending_summary"]!.run(argumentsJSON: #"{"period":"this_month","category":"groceries"}"#)
        XCTAssertTrue(groceriesOnly.contains("45.90 PLN"), groceriesOnly)

        XCTAssertEqual(tools["delete_spending_data"]!.risk, .destructive)
        _ = try await tools["delete_spending_data"]!.run(argumentsJSON: "{}")
        let after = try await tools["spending_summary"]!.run(argumentsJSON: #"{"period":"today"}"#)
        XCTAssertTrue(after.contains("No spending"))
    }

    func testLogExpenseAcceptsNumericAmount() async throws {
        let out = try await toolbox(FakeServices())["log_expense"]!.run(argumentsJSON: #"{"amount":12.5,"merchant":"Kawa"}"#)
        XCTAssertTrue(out.contains("12.50 PLN"), out)
    }
}

final class SystemPromptClockTests: XCTestCase {
    func testPromptContainsCurrentDate() {
        let text = SystemPrompt.text(for: .lolek, language: .en, now: now, timeZone: warsaw.timeZone)
        XCTAssertTrue(text.contains("Monday 2026-10-05 09:41 (Europe/Warsaw)"), text)
    }
}

private struct AllowAll: ApprovalHandler {
    func decide(_ request: ApprovalRequest) async -> ApprovalDecision { .allowOnce }
}

final class AgentLoopWithDeviceToolsTests: XCTestCase {
    private func session(_ services: FakeServices, store: SpendingStore) -> AgentSession {
        let tools = DeviceToolbox.tools(
            services: DeviceServices(weather: services, calendar: services, contacts: services, notifications: services, urlOpener: services, spending: store),
            clock: clock
        )
        return AgentSession(
            mode: .lolek,
            provider: DemoModelProvider(profile: .bielikV3_4_5B),
            registry: ToolRegistry(tools),
            approvalHandler: AllowAll(),
            language: .en
        )
    }

    func testTypedCommandsReachRealTools() async throws {
        var services = FakeServices()
        services.contactList = [ContactInfo(name: "Anna Nowak", phoneNumbers: ["+48 500 600 700"])]
        let store = SpendingStore(fileURL: nil)
        let session = session(services, store: store)

        var added = try await session.send("weather: Kraków")
        XCTAssertTrue(added.last?.text.contains("Kraków") == true)

        added = try await session.send("spent: 12,50 Lidl")
        XCTAssertTrue(added.last?.text.contains("12.50 PLN") == true, added.last?.text ?? "")

        added = try await session.send("spending: today")
        XCTAssertTrue(added.last?.text.contains("12.50 PLN") == true, added.last?.text ?? "")

        added = try await session.send("text: Anna: running late")
        XCTAssertTrue(added.last?.text.contains("Anna Nowak") == true, added.last?.text ?? "")
        let url = await services.recorder.openedURLs.first
        XCTAssertEqual(url?.absoluteString, "sms:+48500600700?body=running%20late")

        added = try await session.send("alarm: 06:30")
        XCTAssertTrue(added.last?.text.contains("06:30") == true)
        let scheduled = await services.recorder.notifications
        XCTAssertEqual(scheduled.count, 1)
    }

    func testSendTextAsksApprovalBeforeOpeningMessages() async throws {
        struct DenyAll: ApprovalHandler {
            func decide(_ request: ApprovalRequest) async -> ApprovalDecision { .deny }
        }
        var services = FakeServices()
        services.contactList = [ContactInfo(name: "Anna Nowak", phoneNumbers: ["+48500600700"])]
        let tools = DeviceToolbox.tools(
            services: DeviceServices(weather: services, calendar: services, contacts: services, notifications: services, urlOpener: services, spending: SpendingStore(fileURL: nil)),
            clock: clock
        )
        let session = AgentSession(mode: .lolek, provider: DemoModelProvider(profile: .bielikV3_4_5B), registry: ToolRegistry(tools), approvalHandler: DenyAll(), language: .en)
        _ = try await session.send("text: Anna: hi")
        let opened = await services.recorder.openedURLs
        XCTAssertTrue(opened.isEmpty, "Denied, so Messages must not open")
    }
}
