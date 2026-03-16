import XCTest
@testable import MyceliumOSX

final class KeychainManagerTests: XCTestCase {
    private let testRef = "mycelium-test-\(UUID().uuidString)"

    override func tearDown() {
        KeychainManager.delete(ref: testRef)
        super.tearDown()
    }

    func testSaveAndRetrieve() {
        let saved = KeychainManager.save(key: "test-api-key-123", forRef: testRef)
        XCTAssertTrue(saved)

        let retrieved = KeychainManager.get(ref: testRef)
        XCTAssertEqual(retrieved, "test-api-key-123")
    }

    func testUpdateExistingKey() {
        KeychainManager.save(key: "old-key", forRef: testRef)
        KeychainManager.save(key: "new-key", forRef: testRef)

        let retrieved = KeychainManager.get(ref: testRef)
        XCTAssertEqual(retrieved, "new-key")
    }

    func testGetNonExistent() {
        let retrieved = KeychainManager.get(ref: "nonexistent-\(UUID().uuidString)")
        XCTAssertNil(retrieved)
    }

    func testDelete() {
        KeychainManager.save(key: "to-delete", forRef: testRef)
        let deleted = KeychainManager.delete(ref: testRef)
        XCTAssertTrue(deleted)

        let retrieved = KeychainManager.get(ref: testRef)
        XCTAssertNil(retrieved)
    }

    func testDeleteNonExistent() {
        let deleted = KeychainManager.delete(ref: "nonexistent-\(UUID().uuidString)")
        XCTAssertFalse(deleted)
    }

    func testCacheHit() {
        KeychainManager.save(key: "cached-key", forRef: testRef)
        // Second get should come from cache (no Keychain prompt)
        let first = KeychainManager.get(ref: testRef)
        let second = KeychainManager.get(ref: testRef)
        XCTAssertEqual(first, second)
        XCTAssertEqual(second, "cached-key")
    }
}

// MARK: - MockKeychain Tests

final class MockKeychainTests: XCTestCase {
    override func setUp() {
        MockKeychain.reset()
    }

    func testSaveAndGet() {
        MockKeychain.save(key: "test-key", forRef: "test-ref")
        XCTAssertEqual(MockKeychain.get(ref: "test-ref"), "test-key")
    }

    func testGetNonExistent() {
        XCTAssertNil(MockKeychain.get(ref: "missing"))
    }

    func testDelete() {
        MockKeychain.save(key: "val", forRef: "ref")
        XCTAssertTrue(MockKeychain.delete(ref: "ref"))
        XCTAssertNil(MockKeychain.get(ref: "ref"))
    }

    func testListRefs() {
        MockKeychain.save(key: "a", forRef: "ref1")
        MockKeychain.save(key: "b", forRef: "ref2")
        let refs = MockKeychain.listRefs().sorted()
        XCTAssertEqual(refs, ["ref1", "ref2"])
    }
}
