import AgentCore
import DocumentKit
import Foundation
import LolekRuntime
import UIKit
import XCTest
import os

/// Runs inside the app on a real iPhone. The model must already be in the app's container
/// (`devicectl device copy to ...`). Prints a report; asserts only that things work.
final class DeviceBenchmarkTests: XCTestCase {
    // MARK: Measurements

    private func footprintMB() -> Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return result == KERN_SUCCESS ? Int(info.phys_footprint / 1_048_576) : -1
    }

    private func headroomMB() -> Int { Int(os_proc_available_memory() / 1_048_576) }

    private var thermal: String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: "nominal"
        case .fair: "fair"
        case .serious: "SERIOUS"
        case .critical: "CRITICAL"
        @unknown default: "unknown"
        }
    }

    private func snapshot(_ label: String) -> String { "\(label): footprint \(footprintMB()) MB, headroom before iOS kills the app \(headroomMB()) MB, thermal \(thermal)" }

    override func setUp() async throws {
        await MainActor.run { UIApplication.shared.isIdleTimerDisabled = true }
    }

    // MARK: Fakes for the scorecard

    private actor Log { var items: [String] = []; func add(_ s: String) { items.append(s) } }
    private struct Fakes: NotificationScheduling, URLOpening, CalendarProviding, ContactsProviding, WeatherProviding {
        func schedule(_ n: ScheduledNotification) async throws {}
        func open(_ url: URL) async -> Bool { true }
        func events(from: Date, to: Date) async throws -> [CalendarEventInfo] { [] }
        func addEvent(title: String, start: Date, end: Date, location: String?) async throws -> CalendarEventInfo { CalendarEventInfo(title: title, start: start, end: end, location: location) }
        func find(name: String) async throws -> [ContactInfo] {
            let n = name.lowercased()
            if n.contains("ann") { return [ContactInfo(name: "Anna Nowak", phoneNumbers: ["+48500600700"])] }
            if n.contains("bob") { return [ContactInfo(name: "Bob Smith", phoneNumbers: ["+48600111222"])] }
            return []
        }
        func weather(for place: String?) async throws -> WeatherReport { WeatherReport(place: place ?? "Warszawa", temperatureC: 14, condition: "Cloudy", highC: 16, lowC: 9) }
    }
    private struct AllowAll: ApprovalHandler { func decide(_ r: ApprovalRequest) async -> ApprovalDecision { .allowOnce } }

    private func provider(stats: (@Sendable (GenerationStats) -> Void)? = nil) throws -> (LlamaCppProvider, ModelStore) {
        let store = ModelStore()
        guard store.isInstalled(LocalModels.qwen35) else {
            throw XCTSkip("Qwen model not in the app container: \(store.directory.path)")
        }
        return (LlamaCppProvider(model: LocalModels.qwen35, store: store, statsHandler: stats), store)
    }

    private final class StatsLog: @unchecked Sendable {
        private let lock = NSLock(); private var items: [GenerationStats] = []
        func add(_ s: GenerationStats) { lock.lock(); items.append(s); lock.unlock() }
        func drain() -> [GenerationStats] { lock.lock(); defer { lock.unlock() }; let out = items; items = []; return out }
    }

    // MARK: Tests

    func testEngineSpeedAndMemory() async throws {
        let (_, store) = try provider()
        var report = ["=== iPHONE ENGINE ===", "device: \(UIDevice.current.model) \(UIDevice.current.systemVersion), cores \(ProcessInfo.processInfo.activeProcessorCount), RAM \(ProcessInfo.processInfo.physicalMemory / 1_048_576) MB, low power mode: \(ProcessInfo.processInfo.isLowPowerModeEnabled)"]
        report.append(snapshot("before load"))
        let started = Date()
        let engine = try await LlamaEngine(modelPath: store.path(for: LocalModels.qwen35).path)
        report.append(String(format: "model load: %.1f s", Date().timeIntervalSince(started)))
        report.append(snapshot("after load"))

        let fakes = Fakes()
        let tools = DeviceToolbox.tools(services: DeviceServices(weather: fakes, calendar: fakes, contacts: fakes, notifications: fakes, urlOpener: fakes, spending: SpendingStore(fileURL: nil))).map { $0.spec(in: .pl) }
        let renderer = PromptRenderer(style: .qwen35)
        let user = ChatMessage(role: .user, text: "Jaka jest pogoda w Krakowie?")
        let parts = renderer.renderParts(system: "Jesteś Lolkiem, prywatnym asystentem. Odpowiadaj zwięźle.", messages: [user], tools: tools, timeZone: .current)

        // First message after launch: the whole prompt (instructions + tools) has to be read.
        let first = try await engine.generate(header: parts.header, prompt: parts.body, suffix: parts.generation, maxTokens: 60, temperature: 0) { _ in true }
        report.append(String(format: "cold prompt: %d tokens read in %.1f s (%.0f tok/s), generated %d tokens at %.1f tok/s, checkpoint %d MB", first.stats.promptTokens, first.stats.prefillSeconds, Double(first.stats.promptTokens - first.stats.reusedTokens) / max(first.stats.prefillSeconds, 0.001), first.stats.generatedTokens, first.stats.tokensPerSecond, first.stats.checkpointBytes / 1_000_000))
        report.append(snapshot("after first answer"))

        // Same header, new question: should reuse the checkpoint.
        let second = renderer.renderParts(system: "Jesteś Lolkiem, prywatnym asystentem. Odpowiadaj zwięźle.", messages: [ChatMessage(role: .user, text: "Ustaw budzik na 6:30")], tools: tools, timeZone: .current)
        let warm = try await engine.generate(header: second.header, prompt: second.body, suffix: second.generation, maxTokens: 60, temperature: 0) { _ in true }
        report.append(String(format: "warm prompt (header cached): reused %d of %d tokens, prefill %.2f s, generated %d tokens at %.1f tok/s", warm.stats.reusedTokens, warm.stats.promptTokens, warm.stats.prefillSeconds, warm.stats.generatedTokens, warm.stats.tokensPerSecond))

        // Sustained generation, to see heat.
        let long = renderer.renderParts(system: "Jesteś pomocnym asystentem.", messages: [ChatMessage(role: .user, text: "Napisz długi, szczegółowy opis dnia w Krakowie.")], tools: [], timeZone: nil)
        let burn = try await engine.generate(prompt: long.header + long.body, suffix: long.generation, maxTokens: 400, temperature: 0.3) { _ in true }
        report.append(String(format: "sustained: %d tokens at %.1f tok/s", burn.stats.generatedTokens, burn.stats.tokensPerSecond))
        report.append(snapshot("after sustained generation"))
        print("\n" + report.joined(separator: "\n"))
        XCTAssertGreaterThan(first.stats.generatedTokens, 0)
    }

    private struct Case { let prompt: String; let language: ConversationLanguage; let tool: String?; let check: (@Sendable (String) -> Bool)? }
    private static let cases: [Case] = [
        Case(prompt: "Jaka jest pogoda w Krakowie?", language: .pl, tool: "get_weather", check: { $0.contains("Krak") }),
        Case(prompt: "What's the weather in Gdańsk?", language: .en, tool: "get_weather", check: { $0.contains("Gda") }),
        Case(prompt: "Ustaw budzik na 6:30", language: .pl, tool: "set_alarm", check: { $0.contains("6:30") || $0.contains("06:30") }),
        Case(prompt: "Set a timer for 10 minutes", language: .en, tool: "set_timer", check: { $0.contains("600") }),
        Case(prompt: "Przypomnij mi jutro o 9 o wizycie u dentysty", language: .pl, tool: "add_reminder", check: { $0.lowercased().contains("dentyst") }),
        Case(prompt: "Napisz do Anny, że się spóźnię 10 minut", language: .pl, tool: "text_contact", check: { $0.contains("Ann") }),
        Case(prompt: "Call Bob", language: .en, tool: "call_contact", check: { $0.lowercased().contains("bob") || $0.contains("600111222") }),
        Case(prompt: "Wydałem 45 zł w Biedronce", language: .pl, tool: "log_expense", check: { $0.contains("45") }),
        Case(prompt: "How much did I spend this week?", language: .en, tool: "spending_summary", check: { $0.contains("this_week") }),
        Case(prompt: "What's on my calendar tomorrow?", language: .en, tool: "list_calendar_events", check: nil),
        Case(prompt: "Cześć!", language: .pl, tool: nil, check: nil),
        Case(prompt: "Tell me a short joke", language: .en, tool: nil, check: nil),
    ]

    func testToolScorecardOnDevice() async throws {
        let log = StatsLog()
        let (provider, _) = try provider(stats: { log.add($0) })
        let fakes = Fakes()
        let tools = DeviceToolbox.tools(services: DeviceServices(weather: fakes, calendar: fakes, contacts: fakes, notifications: fakes, urlOpener: fakes, spending: SpendingStore(fileURL: nil)))
        var passed = 0
        var times: [Double] = []
        var lines: [String] = []
        for item in Self.cases {
            let session = AgentSession(mode: .lolek, provider: provider, registry: ToolRegistry(tools), approvalHandler: AllowAll(), language: item.language, fixedPromptLanguage: .en)
            let started = Date()
            let added = try await session.send(item.prompt)
            let seconds = Date().timeIntervalSince(started)
            times.append(seconds)
            let steps = log.drain().map { String(format: "[read %d (reused %d, ckpt %d) %.1fs | wrote %d at %.1f t/s]", $0.promptTokens - $0.reusedTokens, $0.reusedTokens, $0.checkpointTokens, $0.prefillSeconds, $0.generatedTokens, $0.tokensPerSecond) }.joined(separator: " ")
            let calls = added.flatMap(\.toolCalls)
            let strays = calls.filter { $0.name != item.tool && $0.name != "find_contact" }
            let ok: Bool
            if let expected = item.tool, let call = calls.first(where: { $0.name == expected }) { ok = (item.check?(call.argumentsJSON) ?? true) && strays.isEmpty } else { ok = item.tool == nil && calls.isEmpty }
            if ok { passed += 1 }
            lines.append(String(format: "  %@ %@ [%@] %.1fs %@", ok ? "PASS" : "FAIL", item.prompt, calls.map(\.name).joined(separator: ","), seconds, steps))
        }
        let sorted = times.sorted()
        print("\n=== iPHONE TOOL SCORECARD: \(passed)/\(Self.cases.count) ===\nresponse time: median \(String(format: "%.1f", sorted[sorted.count / 2])) s, slowest \(String(format: "%.1f", sorted.last ?? 0)) s\n" + lines.joined(separator: "\n") + "\n" + snapshot("end"))
        XCTAssertGreaterThanOrEqual(passed, 9)
    }
}
