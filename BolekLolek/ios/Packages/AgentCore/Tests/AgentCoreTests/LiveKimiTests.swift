import XCTest
@testable import AgentCore

/// Talks to the real Kimi K3 on OpenRouter. Skipped unless OPENROUTER_API_KEY is set:
///     OPENROUTER_API_KEY=sk-or-... swift test --filter LiveKimiTests
/// Costs a few cents per run.
final class LiveKimiTests: XCTestCase {
    private actor Log {
        var opened: [URL] = []
        var notifications: [ScheduledNotification] = []
        var events: [CalendarEventInfo] = []
        var weatherPlaces: [String?] = []
        func open(_ u: URL) { opened.append(u) }
        func add(_ n: ScheduledNotification) { notifications.append(n) }
        func add(_ e: CalendarEventInfo) { events.append(e) }
        func place(_ p: String?) { weatherPlaces.append(p) }
    }

    private struct Fakes: NotificationScheduling, URLOpening, CalendarProviding, ContactsProviding, WeatherProviding {
        let log = Log()
        func schedule(_ n: ScheduledNotification) async throws { await log.add(n) }
        func open(_ url: URL) async -> Bool { await log.open(url); return true }
        func events(from: Date, to: Date) async throws -> [CalendarEventInfo] { [] }
        func addEvent(title: String, start: Date, end: Date, location: String?) async throws -> CalendarEventInfo {
            let e = CalendarEventInfo(title: title, start: start, end: end, location: location)
            await log.add(e)
            return e
        }
        func find(name: String) async throws -> [ContactInfo] {
            name.lowercased().contains("anna") ? [ContactInfo(name: "Anna Nowak", phoneNumbers: ["+48 500 600 700"])] : []
        }
        func weather(for place: String?) async throws -> WeatherReport {
            await log.place(place)
            return WeatherReport(place: place ?? "Warszawa", temperatureC: 13.6, condition: "Cloudy", highC: 16, lowC: 9, precipitationChancePercent: 70, note: "rain likely from 15:00")
        }
    }

    private struct AllowAll: ApprovalHandler {
        func decide(_ request: ApprovalRequest) async -> ApprovalDecision { .allowOnce }
    }

    private func makeSession(_ fakes: Fakes, store: SpendingStore = SpendingStore(fileURL: nil)) throws -> AgentSession {
        let key = ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"] ?? ""
        try XCTSkipUnless(!key.isEmpty, "set OPENROUTER_API_KEY to run the live Kimi tests")
        let tools = DeviceToolbox.tools(
            services: DeviceServices(weather: fakes, calendar: fakes, contacts: fakes, notifications: fakes, urlOpener: fakes, spending: store)
        )
        return AgentSession(
            mode: .bolek,
            provider: OpenRouterProvider(apiKey: { key }),
            registry: ToolRegistry(tools),
            approvalHandler: AllowAll(),
            language: .en
        )
    }

    private func toolNames(_ messages: [ChatMessage]) -> [String] {
        messages.flatMap { $0.toolCalls.map(\.name) }
    }

    func testWeatherInPolish() async throws {
        let fakes = Fakes()
        let session = try makeSession(fakes)
        let added = try await session.send("Jaka jest dziś pogoda w Krakowie?")
        print("WEATHER →", added.last?.text ?? "")
        XCTAssertTrue(toolNames(added).contains("get_weather"))
        let places = await fakes.log.weatherPlaces
        XCTAssertTrue(places.compactMap { $0 }.contains { $0.contains("Krak") }, "\(places)")
        let reply = try XCTUnwrap(added.last?.text)
        XCTAssertTrue(reply.contains("14") || reply.contains("13"), "reply should use the tool result: \(reply)")
        XCTAssertTrue(reply.lowercased().contains("kraków") || reply.contains("°") || reply.lowercased().contains("pochmurno"), reply)
    }

    func testAlarmTomorrow() async throws {
        let fakes = Fakes()
        let session = try makeSession(fakes)
        let added = try await session.send("Set an alarm for 6:30 tomorrow morning.")
        print("ALARM →", added.last?.text ?? "")
        let scheduled = await fakes.log.notifications
        let alarm = try XCTUnwrap(scheduled.first, "no alarm scheduled; calls: \(toolNames(added))")
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date())!
        XCTAssertTrue(calendar.isDate(alarm.fireDate, inSameDayAs: tomorrow), "\(alarm.fireDate)")
        XCTAssertEqual(calendar.component(.hour, from: alarm.fireDate), 6)
        XCTAssertEqual(calendar.component(.minute, from: alarm.fireDate), 30)
    }

    func testTextAnnaOpensMessages() async throws {
        let fakes = Fakes()
        let session = try makeSession(fakes)
        let added = try await session.send("Text Anna that I'm running 10 minutes late.")
        print("TEXT →", added.last?.text ?? "")
        let opened = await fakes.log.opened
        let url = try XCTUnwrap(opened.first, "calls: \(toolNames(added))")
        XCTAssertEqual(url.scheme, "sms")
        XCTAssertTrue(url.absoluteString.contains("+48500600700"))
        XCTAssertTrue(url.absoluteString.lowercased().contains("late"))
    }

    func testSpendingLoggedThenSummarised() async throws {
        let fakes = Fakes()
        let store = SpendingStore(fileURL: nil)
        let session = try makeSession(fakes, store: store)
        _ = try await session.send("I just spent 45 zł at Biedronka.")
        let saved = await store.allExpenses
        XCTAssertEqual(saved.first?.minorUnits, 4500, "expense not logged")
        XCTAssertEqual(saved.first?.category, "groceries")

        let added = try await session.send("How much have I spent today?")
        print("SPENDING →", added.last?.text ?? "")
        XCTAssertTrue(toolNames(added).contains("spending_summary"))
        XCTAssertTrue(added.last?.text.contains("45") == true, added.last?.text ?? "")
    }

    func testUnavailableThingsAreAdmittedNotInvented() async throws {
        let fakes = Fakes()
        let session = try makeSession(fakes)
        let added = try await session.send("Check the cheapest flights from Warsaw to Lisbon next month and keep watching the price.")
        print("FLIGHTS →", added.last?.text ?? "")
        XCTAssertTrue(toolNames(added).isEmpty, "no tool can do this: \(toolNames(added))")
        let reply = (added.last?.text ?? "").lowercased()
        XCTAssertFalse(reply.contains(where: { "ąćęłńóśźż".contains($0) }), "English question must get an English answer: \(reply)")
        XCTAssertTrue(reply.contains("can't") || reply.contains("cannot") || reply.contains("not available") || reply.contains("unable") || reply.contains("not yet") || reply.contains("don't"), reply)
    }
}
