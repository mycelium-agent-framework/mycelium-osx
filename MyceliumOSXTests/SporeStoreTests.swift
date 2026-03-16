import XCTest
@testable import MyceliumOSX

final class SporeStoreTests: XCTestCase {
    var tempDir: URL!
    var store: SporeStore!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mycelium-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        store = SporeStore(ringPath: tempDir, deviceId: "test-device")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testAppendAndLoadSpore() {
        let spore = Spore(
            type: .note,
            content: "Test note",
            originPop: "test-device"
        )
        store.append(spore: spore)

        let loaded = store.loadAll()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.content, "Test note")
        XCTAssertEqual(loaded.first?.originPop, "test-device")
    }

    func testMultipleSporesAppendToSameFile() {
        for i in 0..<5 {
            store.append(spore: Spore(
                type: .note,
                content: "Note \(i)",
                originPop: "test-device"
            ))
        }

        let loaded = store.loadAll()
        XCTAssertEqual(loaded.count, 5)
    }

    func testShardedFilesDoNotConflict() {
        let store1 = SporeStore(ringPath: tempDir, deviceId: "osx-desktop")
        let store2 = SporeStore(ringPath: tempDir, deviceId: "android-phone")

        store1.append(spore: Spore(type: .note, content: "From Mac", originPop: "osx-desktop"))
        store2.append(spore: Spore(type: .note, content: "From Android", originPop: "android-phone"))

        // Both stores can read all spores
        let all = store1.loadAll()
        XCTAssertEqual(all.count, 2)

        // Verify files are separate
        let memDir = tempDir.appendingPathComponent(".mycelium")
        let files = try? FileManager.default.contentsOfDirectory(at: memDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "jsonl" }
        XCTAssertEqual(files?.count, 2)
    }

    func testHandoffSporeWithRecap() {
        let spore = Spore(
            type: .handoff,
            status: .done,
            content: "Session ended.",
            contextRecap: "Discussed project architecture and memory sharding.",
            originPop: "test-device"
        )
        store.append(spore: spore)

        let loaded = store.loadAll()
        XCTAssertEqual(loaded.first?.type, .handoff)
        XCTAssertEqual(loaded.first?.contextRecap, "Discussed project architecture and memory sharding.")
    }

    func testChannelFilter() {
        store.append(spore: Spore(type: .note, channel: "work", content: "Work note", originPop: "test-device"))
        store.append(spore: Spore(type: .note, channel: "personal", content: "Personal note", originPop: "test-device"))

        let workSpores = store.loadForChannel("work")
        XCTAssertEqual(workSpores.count, 1)
        XCTAssertEqual(workSpores.first?.content, "Work note")
    }
}
