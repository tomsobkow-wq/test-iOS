import Foundation
import Security

/// Small Keychain wrapper for the developer-build secrets (OpenRouter key, backend token).
enum Keychain {
    static func read(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8), !value.isEmpty
        else { return nil }
        return value
    }

    static func write(_ value: String, service: String, account: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }
}

/// Developer-build storage for the OpenRouter key. Launch once with
/// `OPENROUTER_API_KEY` set and it moves into the Keychain. A shipped app must
/// never carry a key: Bolek will call our backend instead.
enum APIKeyStore {
    private static let service = "com.boleklolek.openrouter"
    private static let account = "api-key"

    static func current() -> String? {
        adoptEnvironmentKey()
        return Keychain.read(service: service, account: account)
    }

    static func save(_ key: String) {
        Keychain.write(key, service: service, account: account)
    }

    private static func adoptEnvironmentKey() {
        guard let key = ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"]?
            .trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else { return }
        save(key)
    }
}
