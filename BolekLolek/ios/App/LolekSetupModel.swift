import Foundation
import LolekRuntime
import Observation

/// First run: Lolek's model has to be downloaded once. Shown in the chat, not as a separate screen.
@MainActor
@Observable
final class LolekSetupModel {
    enum State: Equatable {
        case needsDownload
        case downloading(fraction: Double)
        case verifying
        case ready
        case failed(String)
    }

    private(set) var state: State
    let model: LocalModel
    let store: ModelStore
    private let downloader = ModelDownloader()
    private var task: Task<Void, Never>?

    /// Called once the model is in place, so the engine can warm up before the first message.
    var onReady: (() -> Void)?

    init(model: LocalModel = LocalModels.default, store: ModelStore = ModelStore()) {
        self.model = model
        self.store = store
        state = store.isInstalled(model) ? .ready : .needsDownload
    }

    var isReady: Bool { state == .ready }

    var sizeText: String {
        ByteCountFormatter.string(fromByteCount: model.sizeBytes, countStyle: .file)
    }

    func start() {
        switch state {
        case .downloading, .verifying, .ready: return
        case .needsDownload, .failed: break
        }
        state = .downloading(fraction: Double(store.partialBytes(for: model)) / Double(model.sizeBytes))
        task = Task { [model, store, downloader] in
            do {
                for try await progress in downloader.download(model, to: store) {
                    switch progress.phase {
                    case .downloading: state = .downloading(fraction: progress.fraction)
                    case .verifying: state = .verifying
                    case .finished: state = .ready
                    }
                }
                state = .ready
                onReady?()
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }
}
