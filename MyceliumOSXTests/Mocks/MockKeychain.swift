import Foundation
@testable import MyceliumOSX

/// In-memory keychain for testing.
final class MockKeychain: KeychainStoring {
    static var store: [String: String] = [:]

    static func save(key: String, forRef ref: String) -> Bool {
        store[ref] = key
        return true
    }

    static func get(ref: String) -> String? {
        store[ref]
    }

    static func delete(ref: String) -> Bool {
        store.removeValue(forKey: ref) != nil
    }

    static func listRefs() -> [String] {
        Array(store.keys)
    }

    static func preloadAll() {
        // No-op for mock
    }

    static func reset() {
        store = [:]
    }
}
