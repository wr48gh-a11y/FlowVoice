import Foundation
import Security

/// Minimal Keychain wrapper for storing the Anthropic API key.
enum Keychain {
    private static let service = "dev.hugh.flowvoice"

    /// Stores (or, for an empty value, deletes) a keychain item.
    /// Returns true on success so callers can warn the user if a save silently
    /// failed — otherwise a failed save would just vanish on next launch.
    @discardableResult
    static func set(_ value: String, for key: String) -> Bool {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        let deleteStatus = SecItemDelete(query as CFDictionary)
        guard value.isEmpty == false else {
            // Deleting: success, or nothing was there to delete.
            return deleteStatus == errSecSuccess || deleteStatus == errSecItemNotFound
        }
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    static func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
