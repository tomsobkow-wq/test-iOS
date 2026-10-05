import Foundation
import Network
import Observation

/// Whether the phone has any connection. Lolek never needs one; Bolek always does. In airplane mode the path is unsatisfied.
/// Set BOLEK_FORCE_OFFLINE=1 in the launch environment to see the offline look without touching the phone.
@MainActor
@Observable
final class NetworkStatus {
    private(set) var isOnline = true
    @ObservationIgnored private let monitor = NWPathMonitor()

    init() {
        if ProcessInfo.processInfo.environment["BOLEK_FORCE_OFFLINE"] == "1" {
            isOnline = false
            return
        }
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in self?.isOnline = online }
        }
        monitor.start(queue: DispatchQueue(label: "com.boleklolek.network"))
    }
}
