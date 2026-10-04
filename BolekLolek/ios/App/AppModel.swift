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

/// Bolek's brain: Claude when a developer key is present, otherwise the typed-command demo.
/// Kimi K3 replaces `ClaudeProvider` here once it is hosted.
struct BolekBrain: ModelProvider {
    private let claude = ClaudeProvider(apiKey: { APIKeyStore.current() })
    private let demo = DemoModelProvider(profile: ModelCatalog.bolek)

    var profile: ModelProfile { APIKeyStore.current() == nil ? demo.profile : claude.profile }

    func respond(to request: ModelRequest) async throws -> ModelResponse {
        APIKeyStore.current() == nil
            ? try await demo.respond(to: request)
            : try await claude.respond(to: request)
    }
}
