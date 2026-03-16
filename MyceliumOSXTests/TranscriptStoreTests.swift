import XCTest
@testable import MyceliumOSX

final class TranscriptStoreTests: XCTestCase {
    var tempDir: URL!
    var store: TranscriptStore!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mycelium-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        store = TranscriptStore(ringPath: tempDir, deviceId: "test-device")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testAppendAndLoadTranscript() {
        let entry = TranscriptEntry(
            role: .user,
            text: "Hello Vivian",
            originPop: "test-device"
        )
        store.append(entry: entry, channel: "default")

        let loaded = store.loadRecentEntries(channel: "default")
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.text, "Hello Vivian")
        XCTAssertEqual(loaded.first?.role, .user)
    }

    func testConversationRoundtrip() {
        store.append(entry: TranscriptEntry(role: .user, text: "What's the weather?", originPop: "test-device"), channel: "default")
        store.append(entry: TranscriptEntry(role: .model, text: "It looks sunny today.", originPop: "test-device"), channel: "default")

        let loaded = store.loadRecentEntries(channel: "default")
        XCTAssertEqual(loaded.count, 2)
        XCTAssertEqual(loaded[0].role, .user)
        XCTAssertEqual(loaded[1].role, .model)
    }

    func testMultiDeviceTranscripts() {
        let store1 = TranscriptStore(ringPath: tempDir, deviceId: "osx-desktop")
        let store2 = TranscriptStore(ringPath: tempDir, deviceId: "android-phone")

        store1.append(entry: TranscriptEntry(role: .user, text: "From Mac", originPop: "osx-desktop"), channel: "default")
        store2.append(entry: TranscriptEntry(role: .user, text: "From Android", originPop: "android-phone"), channel: "default")

        // Loading should merge both device transcripts
        let all = store1.loadRecentEntries(channel: "default")
        XCTAssertEqual(all.count, 2)
    }

    func testChannelIsolation() {
        store.append(entry: TranscriptEntry(role: .user, text: "Work stuff", originPop: "test-device"), channel: "work")
        store.append(entry: TranscriptEntry(role: .user, text: "Personal stuff", originPop: "test-device"), channel: "personal")

        let work = store.loadRecentEntries(channel: "work")
        XCTAssertEqual(work.count, 1)
        XCTAssertEqual(work.first?.text, "Work stuff")

        let personal = store.loadRecentEntries(channel: "personal")
        XCTAssertEqual(personal.count, 1)
        XCTAssertEqual(personal.first?.text, "Personal stuff")
    }

    func testRecentLimit() {
        for i in 0..<100 {
            store.append(entry: TranscriptEntry(role: .user, text: "Message \(i)", originPop: "test-device"), channel: "default")
        }

        let recent = store.loadRecentEntries(channel: "default", limit: 10)
        XCTAssertEqual(recent.count, 10)
        // Should be the last 10
        XCTAssertEqual(recent.first?.text, "Message 90")
    }
}
