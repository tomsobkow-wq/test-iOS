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
    /// Gmail lives with Lolek only: on this phone, never reaching Bolek or our servers.
    let mail = MailConnection()
    private let lolekProvider = LlamaCppProvider()
    private var connecting = false

    init() {
        // Each mode has its own chat and approvals. Device tools and the spending
        // log are the iPhone's own, so both assistants see the same ones.
        lolek = ChatViewModel(
            mode: .lolek,
            provider: lolekProvider,
            registry: Self.makeRegistry(extra: [OfferHandoffTool(sink: handoff)] + EmailToolbox.tools(provider: mail.provider, opener: AppServices.device.urlOpener)),
            documents: DocumentSupport(
                store: AppServices.documents,
                summarize: { [lolekProvider] chunks, language in
                    try await DocumentSummarizer(generate: lolekProvider.documentGenerator(language: language)).summarize(chunks: chunks, language: language)
                },
                modelReady: { [setup = lolekSetup] in setup.isReady }
            ),
            planner: CompositeTurnPlanner([WebIntentPlanner(), DocumentPlanner(store: AppServices.documents)]),
            fixedPromptLanguage: .en,
            willSend: { [handoff] text in handoff.begin(userText: text) }
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
        // Test helper: BOLEK_DEBUG_IMPORT=<file in the app's Documents folder> adds that file as if picked from Files.
        if let name = ProcessInfo.processInfo.environment["BOLEK_DEBUG_IMPORT"],
           let documentsFolder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
           let data = try? Data(contentsOf: documentsFolder.appendingPathComponent(name)) {
            Task { @MainActor [lolek] in lolek.importDocument(data: data, name: name) }
        }
        if ProcessInfo.processInfo.environment["BOLEK_DEMO_HANDOFF"] == "1" { Task { handoff.begin(userText: "Sprawdź ceny lotów do Lizbony"); await handoff.offer(request: "") } }
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

    /// Reaches the Bolek server (if one is set up): learns its tools and shows any alerts it stored while the app was closed.
    /// Safe to call often; with no server, or when it is unreachable, Bolek simply has no flight tools.
    func connectBackend() {
        guard !connecting, let config = BackendSettings.current() else { return }
        connecting = true
        let client = BackendClient(config: config)
        Task { [bolek] in
            defer { connecting = false }
            let tools = await RemoteTool.discover(client: client)
            bolek.register(tools: tools)
            guard !tools.isEmpty, let alerts = try? await client.alerts(since: BackendSettings.lastSeenAlertID),
                  let newest = alerts.map(\.id).max() else { return }
            for alert in alerts { bolek.receive(notice: alert.message) }
            BackendSettings.lastSeenAlertID = newest
            try? await client.markAlertsSeen(upTo: newest)
        }
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
