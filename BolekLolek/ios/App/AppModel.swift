import AgentCore
import DocumentKit
import LolekRuntime
import Observation
import UIKit

@MainActor
@Observable
final class AppModel {
    var mode: AgentMode = .lolek
    let lolek: ChatViewModel
    let bolek: ChatViewModel
    let lolekSetup = LolekSetupModel()
    let network = NetworkStatus()
    let handoff = HandoffCenter()
    private let lolekProvider = LlamaCppProvider()

    init() {
        // Each mode has its own chat and approvals. Device tools and the spending
        // log are the iPhone's own, so both assistants see the same ones.
        lolek = ChatViewModel(
            mode: .lolek,
            provider: lolekProvider,
            registry: Self.makeRegistry(extra: [OfferHandoffTool(sink: handoff)]),
            documents: DocumentSupport(
                store: AppServices.documents,
                summarize: { [lolekProvider] chunks, language in
                    try await DocumentSummarizer(generate: lolekProvider.documentGenerator(language: language)).summarize(chunks: chunks, language: language)
                },
                modelReady: { [setup = lolekSetup] in setup.isReady }
            ),
            planner: CompositeTurnPlanner([WebIntentPlanner(), DocumentPlanner(store: AppServices.documents)]),
            fixedPromptLanguage: .en,
            willSend: { [handoff] in handoff.clear() }
        )
        bolek = ChatViewModel(
            mode: .bolek,
            provider: BolekBrain(),
            registry: Self.makeRegistry(),
            isOnline: { [network] in network.isOnline }
        )

        // Load the model in the background so the first message is not slow, and drop it
        // (about 3 GB) if iOS asks for memory back.
        let host = lolekProvider.engineHost
        #if DEBUG
        // Screenshot helpers: BOLEK_START_MODE=bolek, BOLEK_DEMO_HANDOFF=1.
        if ProcessInfo.processInfo.environment["BOLEK_START_MODE"] == "bolek" { mode = .bolek }
        if ProcessInfo.processInfo.environment["BOLEK_DEMO_HANDOFF"] == "1" { Task { await handoff.offer(request: "Sprawdź ceny lotów do Lizbony") } }
        #endif
        lolekSetup.onReady = { [weak lolek] in Task { @MainActor in lolek?.warmUp() } }
        // Under XCTest the tests load their own copy of the model; two would not fit in memory.
        let underTest = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        if lolekSetup.isReady, !underTest { lolekSetup.onReady?() }
        NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: nil) { _ in
            Task { await host.unload() }
        }
    }

    var current: ChatViewModel {
        switch mode {
        case .lolek: lolek
        case .bolek: bolek
        }
    }

    /// Called when the user taps "Ask Bolek": switch over and ask just that request. Nothing else from Lolek goes along.
    func askBolek(_ request: String) {
        handoff.clear()
        mode = .bolek
        bolek.sendText(request)
    }

    private static func makeRegistry(extra: [any Tool] = []) -> ToolRegistry {
        ToolRegistry([AddNoteTool(store: NoteStore())] + DeviceToolbox.tools(services: AppServices.device) + DocumentToolbox.tools(store: AppServices.documents) + extra)
    }
}

/// Bolek's brain: Kimi K3 through OpenRouter when a developer key is present, otherwise the
/// typed-command demo. Moving to our own backend later only changes this provider.
struct BolekBrain: ModelProvider {
    private let kimi = OpenRouterProvider(apiKey: { APIKeyStore.current() })
    private let demo = DemoModelProvider(profile: ModelCatalog.bolek)

    var profile: ModelProfile { APIKeyStore.current() == nil ? demo.profile : kimi.profile }

    func respond(to request: ModelRequest) async throws -> ModelResponse {
        APIKeyStore.current() == nil
            ? try await demo.respond(to: request)
            : try await kimi.respond(to: request)
    }
}
