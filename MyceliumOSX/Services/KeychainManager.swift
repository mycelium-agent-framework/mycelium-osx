import Foundation
import Security

/// Stores and retrieves API keys from the macOS Keychain.
/// Caches values in memory after first read to minimize Keychain access prompts
/// (ad-hoc signed apps get prompted on each Keychain access).
enum KeychainManager {
    private static let service = "org.mycelium.osx"
    private static var cache: [String: String] = [:]

    /// Save or update an API key.
    @discardableResult
    static func save(key: String, forRef ref: String) -> Bool {
        cache[ref] = key
        let data = Data(key.utf8)

        // Try to update first
        let updateQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: ref,
        ]
        let updateAttrs: [String: Any] = [
            kSecValueData as String: data,
        ]
        let updateStatus = SecItemUpdate(updateQuery as CFDictionary, updateAttrs as CFDictionary)
        if updateStatus == errSecSuccess { return true }

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: ref,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
        ]
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus != errSecSuccess {
            print("[Keychain] Failed to save key '\(ref)': \(addStatus)")
        }
        return addStatus == errSecSuccess
    }

    /// Retrieve an API key. Returns from in-memory cache if available.
    static func get(ref: String) -> String? {
        if let cached = cache[ref] { return cached }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: ref,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data,
              let value = String(data: data, encoding: .utf8)
        else { return nil }

        cache[ref] = value
        return value
    }

    /// Load all keys into memory cache in a single Keychain query.
    /// Call once at startup to avoid repeated Keychain prompts.
    static func preloadAll() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let items = result as? [[String: Any]] else { return }

        for item in items {
            if let account = item[kSecAttrAccount as String] as? String,
               let data = item[kSecValueData as String] as? Data,
               let value = String(data: data, encoding: .utf8) {
                cache[account] = value
            }
        }
        print("[Keychain] Preloaded \(cache.count) keys into memory cache")
    }

    /// Check if a key exists (cache only, no Keychain hit).
    static func exists(ref: String) -> Bool {
        cache[ref] != nil
    }

    @discardableResult
    static func delete(ref: String) -> Bool {
        cache.removeValue(forKey: ref)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: ref,
        ]
        return SecItemDelete(query as CFDictionary) == errSecSuccess
    }

    static func listRefs() -> [String] {
        Array(cache.keys)
    }
}
