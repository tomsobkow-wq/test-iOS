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
            provider: DemoModelProvider(profile: ModelCatalog.bolek),
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
