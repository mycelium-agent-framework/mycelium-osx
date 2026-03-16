import XCTest
@testable import MyceliumOSX

/// Tests for KeychainStoring protocol via MockKeychain.
/// Does NOT hit real Keychain — no system prompts during tests.
final class KeychainManagerTests: XCTestCase {

    override func setUp() {
        MockKeychain.reset()
    }

    func testSaveAndRetrieve() {
        let saved = MockKeychain.save(key: "test-api-key-123", forRef: "test-ref")
        XCTAssertTrue(saved)

        let retrieved = MockKeychain.get(ref: "test-ref")
        XCTAssertEqual(retrieved, "test-api-key-123")
    }

    func testUpdateExistingKey() {
        MockKeychain.save(key: "old-key", forRef: "ref")
        MockKeychain.save(key: "new-key", forRef: "ref")

        XCTAssertEqual(MockKeychain.get(ref: "ref"), "new-key")
    }

    func testGetNonExistent() {
        XCTAssertNil(MockKeychain.get(ref: "missing"))
    }

    func testDelete() {
        MockKeychain.save(key: "to-delete", forRef: "ref")
        XCTAssertTrue(MockKeychain.delete(ref: "ref"))
        XCTAssertNil(MockKeychain.get(ref: "ref"))
    }

    func testDeleteNonExistent() {
        XCTAssertFalse(MockKeychain.delete(ref: "missing"))
    }

    func testListRefs() {
        MockKeychain.save(key: "a", forRef: "ref1")
        MockKeychain.save(key: "b", forRef: "ref2")
        let refs = MockKeychain.listRefs().sorted()
        XCTAssertEqual(refs, ["ref1", "ref2"])
    }

    func testPreloadAllIsNoOp() {
        MockKeychain.save(key: "val", forRef: "ref")
        MockKeychain.preloadAll()
        XCTAssertEqual(MockKeychain.get(ref: "ref"), "val")
    }

    func testMultipleKeysIsolated() {
        MockKeychain.save(key: "key1", forRef: "personal")
        MockKeychain.save(key: "key2", forRef: "work")

        XCTAssertEqual(MockKeychain.get(ref: "personal"), "key1")
        XCTAssertEqual(MockKeychain.get(ref: "work"), "key2")

        MockKeychain.delete(ref: "personal")
        XCTAssertNil(MockKeychain.get(ref: "personal"))
        XCTAssertEqual(MockKeychain.get(ref: "work"), "key2")
    }
}
