import AgentCore
import Foundation

/// Where the Bolek backend is. Developer builds: launch once with `BOLEK_BACKEND_URL` and
/// `BOLEK_BACKEND_TOKEN` set and they are remembered (the token in the Keychain).
enum BackendSettings {
    private static let service = "com.boleklolek.backend"
    private static let account = "token"
    private static let urlKey = "backendURL"
    private static let seenKey = "lastSeenAlertID"

    static func current() -> BackendConfig? {
        adoptEnvironment()
        guard let text = UserDefaults.standard.string(forKey: urlKey), let url = URL(string: text),
              let token = Keychain.read(service: service, account: account) else { return nil }
        return BackendConfig(baseURL: url, token: token)
    }

    static func save(url: String, token: String) {
        UserDefaults.standard.set(url.hasSuffix("/") ? url : url + "/", forKey: urlKey)
        Keychain.write(token, service: service, account: account)
    }

    static var lastSeenAlertID: Int {
        get { UserDefaults.standard.integer(forKey: seenKey) }
        set { UserDefaults.standard.set(newValue, forKey: seenKey) }
    }

    private static func adoptEnvironment() {
        let env = ProcessInfo.processInfo.environment
        guard let url = env["BOLEK_BACKEND_URL"]?.trimmingCharacters(in: .whitespacesAndNewlines), !url.isEmpty,
              let token = env["BOLEK_BACKEND_TOKEN"]?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty
        else { return }
        save(url: url, token: token)
    }
}
