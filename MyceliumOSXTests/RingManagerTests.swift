import XCTest
@testable import MyceliumOSX

final class RingManagerTests: XCTestCase {
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mycelium-ring-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testLoadManifest() throws {
        let manifest = """
        {
          "agent_name": "TestAgent",
          "version": "0.1.0",
          "pops": [],
          "rings": [],
          "channels": [],
          "active_ring": null
        }
        """
        try manifest.write(to: tempDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)

        let rm = RingManager(ring0Path: tempDir)
        let loaded = rm.loadManifest()

        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.agentName, "TestAgent")
        XCTAssertEqual(loaded?.version, "0.1.0")
    }

    func testLoadManifestMissingFile() {
        let rm = RingManager(ring0Path: tempDir)
        XCTAssertNil(rm.loadManifest())
    }

    func testLoadSOUL() throws {
        let soul = "# SOUL.md — TestAgent\n\nHello world."
        try soul.write(to: tempDir.appendingPathComponent("SOUL.md"), atomically: true, encoding: .utf8)

        let rm = RingManager(ring0Path: tempDir)
        let loaded = rm.loadSOUL()

        XCTAssertNotNil(loaded)
        XCTAssertTrue(loaded!.contains("TestAgent"))
    }

    func testLoadSOULMissingFile() {
        let rm = RingManager(ring0Path: tempDir)
        XCTAssertNil(rm.loadSOUL())
    }

    func testLoadRingSOUL() throws {
        let ringDir = tempDir.appendingPathComponent("ring1")
        try FileManager.default.createDirectory(at: ringDir, withIntermediateDirectories: true)
        let soul = "# Ring 1 SOUL"
        try soul.write(to: ringDir.appendingPathComponent("SOUL.md"), atomically: true, encoding: .utf8)

        let rm = RingManager(ring0Path: tempDir)
        let loaded = rm.loadSOUL(ringPath: ringDir)

        XCTAssertNotNil(loaded)
        XCTAssertTrue(loaded!.contains("Ring 1"))
    }

    func testCanAccessRing() throws {
        let manifest = """
        {
          "agent_name": "Vivian",
          "version": "0.1.0",
          "pops": [
            {"device_id": "osx-desktop", "display_name": "Mac", "capabilities": [], "last_active": null, "allowed_rings": ["main", "work"]},
            {"device_id": "android", "display_name": "Phone", "capabilities": [], "last_active": null, "allowed_rings": ["main"]}
          ],
          "rings": [],
          "channels": [],
          "active_ring": null
        }
        """
        try manifest.write(to: tempDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)

        let rm = RingManager(ring0Path: tempDir)
        XCTAssertTrue(rm.canAccess(ring: "main", pop: "osx-desktop"))
        XCTAssertTrue(rm.canAccess(ring: "work", pop: "osx-desktop"))
        XCTAssertTrue(rm.canAccess(ring: "main", pop: "android"))
        XCTAssertFalse(rm.canAccess(ring: "work", pop: "android"))
        XCTAssertFalse(rm.canAccess(ring: "main", pop: "nonexistent"))
    }
}
