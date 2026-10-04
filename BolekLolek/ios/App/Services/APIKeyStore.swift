import Foundation
import Security

/// Developer-build storage for the Anthropic key. Launch once with
/// `ANTHROPIC_API_KEY` set and it moves into the Keychain. A shipped app must
/// never carry a key: Bolek will call our backend instead.
enum APIKeyStore {
    private static let service = "com.boleklolek.anthropic"
    private static let account = "api-key"

    static func current() -> String? {
        adoptEnvironmentKey()
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
              let key = String(data: data, encoding: .utf8), !key.isEmpty
        else { return nil }
        return key
    }

    static func save(_ key: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = Data(key.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    private static func adoptEnvironmentKey() {
        guard let key = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"]?
            .trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else { return }
        save(key)
    }
}
