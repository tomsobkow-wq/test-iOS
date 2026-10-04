import AgentCore
import Observation

@MainActor
@Observable
final class AppModel {
    var mode: AgentMode = .lolek
    let lolek: ChatViewModel
    let bolek: ChatViewModel

    init() {
        // Each mode has its own chat and approvals. Device tools and the spending
        // log are the iPhone's own, so both assistants see the same ones.
        lolek = ChatViewModel(
            mode: .lolek,
            provider: DemoModelProvider(profile: ModelCatalog.lolekDefault),
            registry: Self.makeRegistry()
        )
        bolek = ChatViewModel(
            mode: .bolek,
            provider: BolekBrain(),
            registry: Self.makeRegistry()
        )
    }

    var current: ChatViewModel {
        switch mode {
        case .lolek: lolek
        case .bolek: bolek
        }
    }

    private static func makeRegistry() -> ToolRegistry {
        ToolRegistry([AddNoteTool(store: NoteStore())] + DeviceToolbox.tools(services: AppServices.device))
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
