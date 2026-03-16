import XCTest
@testable import MyceliumOSX

final class SporeModelTests: XCTestCase {
    func testSporeEncodeDecode() throws {
        let spore = Spore(
            type: .decision,
            status: .done,
            channel: "general",
            tags: ["[[Architecture]]"],
            metadata: ["key": AnyCodable("value")],
            content: "Use push-to-talk for voice mode",
            originPop: "osx-desktop"
        )

        let data = try JSONEncoder.mycelium.encode(spore)
        let decoded = try JSONDecoder.mycelium.decode(Spore.self, from: data)

        XCTAssertEqual(decoded.type, .decision)
        XCTAssertEqual(decoded.status, .done)
        XCTAssertEqual(decoded.channel, "general")
        XCTAssertEqual(decoded.content, "Use push-to-talk for voice mode")
        XCTAssertEqual(decoded.originPop, "osx-desktop")
        XCTAssertEqual(decoded.tags, ["[[Architecture]]"])
    }

    func testSporeJsonlSingleLine() throws {
        let spore = Spore(
            type: .note,
            content: "Multi-line\ncontent\nshould\nserialize",
            originPop: "osx-desktop"
        )
        let data = try JSONEncoder.mycelium.encode(spore)
        let json = String(data: data, encoding: .utf8)!
        XCTAssertFalse(json.contains("\n"), "JSONL must be single line")
    }

    func testSporeDefaultValues() {
        let spore = Spore(type: .note, content: "test", originPop: "osx-desktop")
        XCTAssertEqual(spore.status, .open)
        XCTAssertEqual(spore.channel, "general")
        XCTAssertTrue(spore.blockedBy.isEmpty)
        XCTAssertTrue(spore.tags.isEmpty)
        XCTAssertNil(spore.parentId)
        XCTAssertNil(spore.contextRecap)
    }

    func testHandoffSporeWithRecap() throws {
        let spore = Spore(
            type: .handoff,
            status: .done,
            content: "Session ended.",
            contextRecap: "Discussed voice architecture.",
            originPop: "osx-desktop"
        )
        let data = try JSONEncoder.mycelium.encode(spore)
        let decoded = try JSONDecoder.mycelium.decode(Spore.self, from: data)
        XCTAssertEqual(decoded.type, .handoff)
        XCTAssertEqual(decoded.contextRecap, "Discussed voice architecture.")
    }

    func testAllSporeTypes() {
        for sporeType in SporeType.allCases {
            let spore = Spore(type: sporeType, content: "test", originPop: "osx-desktop")
            XCTAssertEqual(spore.type, sporeType)
        }
    }

    func testAllSporeStatuses() {
        for status in SporeStatus.allCases {
            let spore = Spore(type: .note, status: status, content: "test", originPop: "osx-desktop")
            XCTAssertEqual(spore.status, status)
        }
    }
}

final class TranscriptEntryModelTests: XCTestCase {
    func testTranscriptEncodeDecode() throws {
        let entry = TranscriptEntry(role: .user, text: "Hello Vivian", originPop: "osx-desktop")
        let data = try JSONEncoder.mycelium.encode(entry)
        let decoded = try JSONDecoder.mycelium.decode(TranscriptEntry.self, from: data)
        XCTAssertEqual(decoded.role, .user)
        XCTAssertEqual(decoded.text, "Hello Vivian")
        XCTAssertEqual(decoded.originPop, "osx-desktop")
        XCTAssertTrue(decoded.isFinal)
    }

    func testPartialTranscriptEntry() throws {
        let entry = TranscriptEntry(role: .model, text: "Thinking...", isFinal: false, originPop: "osx-desktop")
        let data = try JSONEncoder.mycelium.encode(entry)
        let decoded = try JSONDecoder.mycelium.decode(TranscriptEntry.self, from: data)
        XCTAssertFalse(decoded.isFinal)
    }

    func testAllRoles() {
        for role in [TranscriptRole.user, .model, .system] {
            let entry = TranscriptEntry(role: role, text: "test", originPop: "osx-desktop")
            XCTAssertEqual(entry.role, role)
        }
    }
}

final class ManifestModelTests: XCTestCase {
    func testManifestDecode() throws {
        let json = """
        {
          "agent_name": "Vivian",
          "version": "0.1.0",
          "pops": [
            {
              "device_id": "osx-desktop",
              "display_name": "MacBook",
              "capabilities": ["voice", "text"],
              "last_active": null,
              "allowed_rings": ["vivian-main"]
            }
          ],
          "rings": [
            {
              "name": "vivian-main",
              "repo_url": "git@github.com:user/repo.git",
              "access_rules": {"osx-desktop": ["read", "write"]},
              "backend": {
                "provider": "gemini",
                "api_key_ref": "gemini-personal",
                "model": "gemini-2.5-flash-native-audio-latest"
              }
            }
          ],
          "channels": [],
          "active_ring": null
        }
        """.data(using: .utf8)!

        let manifest = try JSONDecoder().decode(Manifest.self, from: json)
        XCTAssertEqual(manifest.agentName, "Vivian")
        XCTAssertEqual(manifest.pops.count, 1)
        XCTAssertEqual(manifest.pops[0].deviceId, "osx-desktop")
        XCTAssertEqual(manifest.pops[0].allowedRings, ["vivian-main"])
        XCTAssertEqual(manifest.rings.count, 1)
        XCTAssertEqual(manifest.rings[0].backend?.apiKeyRef, "gemini-personal")
        XCTAssertEqual(manifest.rings[0].backend?.model, "gemini-2.5-flash-native-audio-latest")
    }

    func testManifestWithoutBackend() throws {
        let json = """
        {
          "agent_name": "Test",
          "version": "0.1.0",
          "pops": [],
          "rings": [{"name": "ring", "repo_url": "url", "access_rules": {}}],
          "channels": [],
          "active_ring": null
        }
        """.data(using: .utf8)!

        let manifest = try JSONDecoder().decode(Manifest.self, from: json)
        XCTAssertNil(manifest.rings[0].backend)
    }

    func testPopAccessRules() throws {
        let json = """
        {
          "agent_name": "Vivian",
          "version": "0.1.0",
          "pops": [
            {"device_id": "osx-desktop", "display_name": "Mac", "capabilities": [], "last_active": null, "allowed_rings": ["main", "work"]},
            {"device_id": "android-phone", "display_name": "Phone", "capabilities": [], "last_active": null, "allowed_rings": ["main"]}
          ],
          "rings": [],
          "channels": [],
          "active_ring": null
        }
        """.data(using: .utf8)!

        let manifest = try JSONDecoder().decode(Manifest.self, from: json)
        let android = manifest.pops.first { $0.deviceId == "android-phone" }!
        XCTAssertFalse(android.allowedRings.contains("work"), "Android should not access work ring")
    }
}

// MARK: - JSON encoder/decoder helpers for tests

private extension JSONEncoder {
    static let mycelium: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}

private extension JSONDecoder {
    static let mycelium: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
