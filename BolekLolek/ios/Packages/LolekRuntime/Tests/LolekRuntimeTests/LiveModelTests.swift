import AgentCore
import XCTest
@testable import LolekRuntime

/// Runs the REAL models. Skipped unless LOLEK_MODEL_DIR points at a folder holding the GGUF files:
///     LOLEK_MODEL_DIR=~/Developer/lolek-models swift test --filter LiveModelTests
/// Speed numbers here are from a Mac, not an iPhone: use them for relative comparison only.
final class LiveModelTests: XCTestCase {
    private func store() throws -> ModelStore {
        guard let path = ProcessInfo.processInfo.environment["LOLEK_MODEL_DIR"], !path.isEmpty else {
            throw XCTSkip("set LOLEK_MODEL_DIR to run the live model tests")
        }
        return ModelStore(directory: URL(fileURLWithPath: (path as NSString).expandingTildeInPath))
    }

    private func installed(_ model: LocalModel, in store: ModelStore) throws {
        guard FileManager.default.fileExists(atPath: store.path(for: model).path) else {
            throw XCTSkip("\(model.fileName) not in LOLEK_MODEL_DIR")
        }
        if !store.isInstalled(model) { try store.markVerified(model) } // hash is checked separately below
    }

    func testPinnedHashesMatchTheRealFiles() throws {
        let store = try store()
        for model in LocalModels.all where FileManager.default.fileExists(atPath: store.path(for: model).path) {
            XCTAssertEqual(try ModelDownloader.sha256(of: store.path(for: model)), model.sha256, model.fileName)
            let size = (try FileManager.default.attributesOfItem(atPath: store.path(for: model).path)[.size] as? NSNumber)?.int64Value
            XCTAssertEqual(size, model.sizeBytes, model.fileName)
        }
    }

    func testBothModelsAnswerInPolishAndEnglish() async throws {
        let store = try store()
        for model in LocalModels.all {
            try installed(model, in: store)
            let provider = LlamaCppProvider(model: model, store: store)
            for (question, expectPolish) in [("Cześć! Jak masz na imię i co potrafisz?", true), ("Hi! What can you do for me?", false)] {
                let started = Date()
                let response = try await provider.respond(to: ModelRequest(
                    mode: .lolek, systemPrompt: "You are Lolek, a private assistant on the user's iPhone. Be brief. Reply in the user's language.",
                    messages: [ChatMessage(role: .user, text: question)], tools: [], language: expectPolish ? .pl : .en
                ))
                print("[\(model.profile.displayName)] \(question) → \(response.text.replacingOccurrences(of: "\n", with: " ")) (\(String(format: "%.1f", Date().timeIntervalSince(started)))s)")
                XCTAssertFalse(response.text.isEmpty, "\(model.id) gave an empty answer")
                XCTAssertTrue(response.toolCalls.isEmpty)
                let polishLetters = response.text.contains { "ąćęłńóśźż".contains($0) }
                if expectPolish { XCTAssertTrue(polishLetters, "\(model.id) should answer in Polish: \(response.text)") }
                else { XCTAssertFalse(polishLetters, "\(model.id) should answer in English: \(response.text)") }
            }
        }
    }

    func testPrefixCacheMakesFollowUpsCheaper() async throws {
        let store = try store()
        for model in LocalModels.all {
            try installed(model, in: store)
            let engine = try await LlamaEngine(modelPath: store.path(for: model).path)
            let renderer = PromptRenderer(style: model.promptStyle)
            let system = String(repeating: "You are Lolek. Be brief and helpful. ", count: 60)
            let user1 = ChatMessage(role: .user, text: "Say hi.")
            let first = renderer.renderParts(system: system, messages: [user1], tools: [])
            let a = try await engine.generate(header: first.header, prompt: first.body, suffix: first.generation, maxTokens: 20, temperature: 0) { _ in true }
            let second = renderer.renderParts(system: system, messages: [
                user1, ChatMessage(role: .assistant, text: a.text), ChatMessage(role: .user, text: "And bye.")
            ], tools: [])
            let b = try await engine.generate(header: second.header, prompt: second.body, suffix: second.generation, maxTokens: 20, temperature: 0) { _ in true }
            print("prefix cache [\(model.profile.displayName)]: first read \(a.stats.promptTokens) tokens in \(String(format: "%.2f", a.stats.prefillSeconds))s (checkpoint \(a.stats.checkpointBytes / 1_000_000) MB); follow-up reused \(b.stats.reusedTokens) of \(b.stats.promptTokens) (\(b.stats.checkpointTokens) from checkpoint), prefill \(String(format: "%.2f", b.stats.prefillSeconds))s")
            XCTAssertGreaterThan(b.stats.reusedTokens, a.stats.promptTokens / 2, "\(model.id): the follow-up should reuse most of the first prompt")
        }
    }

    // MARK: Tool-calling mini evaluation (first slice of build step 4)

    private actor Calls {
        var notifications: [ScheduledNotification] = []
        var opened: [URL] = []
        func add(_ n: ScheduledNotification) { notifications.append(n) }
        func open(_ u: URL) { opened.append(u) }
    }

    private struct Fakes: NotificationScheduling, URLOpening, CalendarProviding, ContactsProviding, WeatherProviding {
        let calls = Calls()
        func schedule(_ n: ScheduledNotification) async throws { await calls.add(n) }
        func open(_ url: URL) async -> Bool { await calls.open(url); return true }
        func events(from: Date, to: Date) async throws -> [CalendarEventInfo] { [] }
        func addEvent(title: String, start: Date, end: Date, location: String?) async throws -> CalendarEventInfo {
            CalendarEventInfo(title: title, start: start, end: end, location: location)
        }
        func find(name: String) async throws -> [ContactInfo] {
            let n = name.lowercased()
            if n.contains("ann") { return [ContactInfo(name: "Anna Nowak", phoneNumbers: ["+48500600700"])] }
            if n.contains("bob") { return [ContactInfo(name: "Bob Smith", phoneNumbers: ["+48600111222"])] }
            return []
        }
        func weather(for place: String?) async throws -> WeatherReport {
            WeatherReport(place: place ?? "Warszawa", temperatureC: 14, condition: "Cloudy", highC: 16, lowC: 9)
        }
    }

    private struct AllowAll: ApprovalHandler {
        func decide(_ request: ApprovalRequest) async -> ApprovalDecision { .allowOnce }
    }

    private struct Case {
        let prompt: String
        let language: ConversationLanguage
        /// Expected first tool, or nil when no tool should be used.
        let tool: String?
        /// Checks the arguments of the first call.
        let check: (@Sendable (String) -> Bool)?
        init(_ prompt: String, _ language: ConversationLanguage, tool: String?, check: (@Sendable (String) -> Bool)? = nil) {
            self.prompt = prompt; self.language = language; self.tool = tool; self.check = check
        }
    }

    private static let cases: [Case] = [
        Case("Jaka jest pogoda w Krakowie?", .pl, tool: "get_weather") { $0.contains("Krak") },
        Case("What's the weather in Gdańsk?", .en, tool: "get_weather") { $0.contains("Gda") },
        Case("Ustaw budzik na 6:30", .pl, tool: "set_alarm") { $0.contains("6:30") || $0.contains("06:30") },
        Case("Set a timer for 10 minutes", .en, tool: "set_timer") { $0.contains("600") },
        Case("Przypomnij mi jutro o 9 o wizycie u dentysty", .pl, tool: "add_reminder") { $0.lowercased().contains("dentyst") && $0.contains("09:00") },
        Case("Napisz do Anny, że się spóźnię 10 minut", .pl, tool: "text_contact") { $0.contains("Ann") },
        // Looking Bob up first and then dialling his number is the right behaviour.
        Case("Call Bob", .en, tool: "call_contact") { $0.lowercased().contains("bob") || $0.contains("600111222") },
        Case("Wydałem 45 zł w Biedronce", .pl, tool: "log_expense") { $0.contains("45") },
        Case("How much did I spend this week?", .en, tool: "spending_summary") { $0.contains("this_week") },
        Case("What's on my calendar tomorrow?", .en, tool: "list_calendar_events"),
        Case("Cześć!", .pl, tool: nil),
        Case("Tell me a short joke", .en, tool: nil),
    ]

    func testToolCallingScorecard() async throws {
        let store = try store()
        var scorecard: [String] = []
        for model in LocalModels.all {
            try installed(model, in: store)
            let fakes = Fakes()
            let tools = DeviceToolbox.tools(services: DeviceServices(
                weather: fakes, calendar: fakes, contacts: fakes, notifications: fakes, urlOpener: fakes, spending: SpendingStore(fileURL: nil)
            ))
            let provider = LlamaCppProvider(model: model, store: store)
            var passed = 0
            var seconds = 0.0
            var lines: [String] = []
            for item in Self.cases {
                let session = AgentSession(
                    mode: .lolek, provider: provider, registry: ToolRegistry(tools), approvalHandler: AllowAll(), language: item.language
                )
                let started = Date()
                let added = try await session.send(item.prompt)
                seconds += Date().timeIntervalSince(started)
                // Looking something up first (find_contact before text_contact) is fine: score the call we want.
                let allCalls = added.flatMap(\.toolCalls)
                let firstCall = item.tool.flatMap { name in allCalls.first { $0.name == name } } ?? allCalls.first
                var ok: Bool
                // Strict: any tool the user did not ask for fails the case (a lookup first is allowed).
                let strays = allCalls.filter { $0.name != item.tool && $0.name != "find_contact" }
                if let expected = item.tool {
                    ok = firstCall?.name == expected && (item.check?(firstCall?.argumentsJSON ?? "") ?? true) && strays.isEmpty
                } else {
                    ok = allCalls.isEmpty && !(added.last?.text.isEmpty ?? true)
                }
                if ok { passed += 1 }
                lines.append("  \(ok ? "PASS" : "FAIL") \(item.prompt) [calls: \(allCalls.map(\.name).joined(separator: ", "))] → \(firstCall.map { "\($0.name) \($0.argumentsJSON)" } ?? "no tool") | \(added.last?.text.replacingOccurrences(of: "\n", with: " ").prefix(80) ?? "")")
            }
            scorecard.append("\(model.profile.displayName): \(passed)/\(Self.cases.count), \(String(format: "%.1f", seconds / Double(Self.cases.count)))s per request (Mac)\n" + lines.joined(separator: "\n"))
        }
        print("\n=== LOLEK TOOL-CALLING SCORECARD ===\n" + scorecard.joined(separator: "\n\n"))
    }
}
