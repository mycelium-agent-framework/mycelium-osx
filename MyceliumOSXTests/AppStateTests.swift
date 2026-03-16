import XCTest
@testable import MyceliumOSX

@MainActor
final class AppStateTests: XCTestCase {
    var tempDir: URL!
    var ringDir: URL!
    var deps: AppDependencies!
    var appState: AppState!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mycelium-appstate-\(UUID().uuidString)")
        ringDir = tempDir.appendingPathComponent("vivian-main")

        try? FileManager.default.createDirectory(
            at: ringDir.appendingPathComponent("channels/general"),
            withIntermediateDirectories: true
        )
        try? FileManager.default.createDirectory(
            at: ringDir.appendingPathComponent(".mycelium"),
            withIntermediateDirectories: true
        )

        // Write a SOUL.md
        try? "# SOUL — Vivian\nTest soul.".write(
            to: tempDir.appendingPathComponent("SOUL.md"), atomically: true, encoding: .utf8
        )
        try? "# Ring SOUL\nPersonal ring.".write(
            to: ringDir.appendingPathComponent("SOUL.md"), atomically: true, encoding: .utf8
        )

        let manifest = Manifest(
            agentName: "Vivian", version: "0.1.0",
            pops: [PopEntry(deviceId: "osx-desktop", displayName: "Mac", capabilities: [], lastActive: nil, allowedRings: ["vivian-main"])],
            rings: [RingEntry(name: "vivian-main", repoUrl: "url", accessRules: [:],
                              backend: BackendConfig(provider: "gemini", apiKeyRef: "test-key", model: "test-model"))],
            channels: [], activeRing: nil
        )

        var commitMessages: [String] = []

        deps = AppDependencies(
            loadManifest: { _ in manifest },
            loadSOUL: { url in
                try? String(contentsOf: url.appendingPathComponent("SOUL.md"), encoding: .utf8)
            },
            keychainGet: { ref in ref == "test-key" ? "fake-api-key" : nil },
            fileExists: { path in FileManager.default.fileExists(atPath: path) },
            scanChannels: { ringPath in
                let channelsDir = ringPath.appendingPathComponent("channels")
                guard let contents = try? FileManager.default.contentsOfDirectory(
                    at: channelsDir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
                ) else { return [] }
                return contents.compactMap { url in
                    var isDir: ObjCBool = false
                    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir),
                          isDir.boolValue else { return nil }
                    return Channel(name: url.lastPathComponent, ringPath: ringPath)
                }
            },
            makeSporeStore: { SporeStore(ringPath: $0, deviceId: $1) },
            makeTranscriptStore: { TranscriptStore(ringPath: $0, deviceId: $1) },
            makeTextClient: { _, _ in GeminiTextClient(apiKey: "fake", systemInstruction: "test") },
            commitAndPersist: { _, msg in commitMessages.append(msg) }
        )

        let mockVoiceSession = VoiceSessionManager(
            capture: MockAudioCapture(),
            playback: MockAudioPlayback(),
            clientFactory: { _ in MockGeminiLive() }
        )
        appState = AppState(deps: deps, voiceSession: mockVoiceSession)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Bootstrap

    func testBootstrapLoadsManifestAndSOUL() {
        appState.bootstrap(ring0Path: tempDir)

        XCTAssertNotNil(appState.manifest)
        XCTAssertEqual(appState.manifest?.agentName, "Vivian")
        XCTAssertTrue(appState.soulContent.contains("Vivian"))
    }

    func testBootstrapWithMissingSOUL() {
        try? FileManager.default.removeItem(at: tempDir.appendingPathComponent("SOUL.md"))
        appState.bootstrap(ring0Path: tempDir)

        XCTAssertNotNil(appState.manifest)
        XCTAssertEqual(appState.soulContent, "")
    }

    // MARK: - Mount Ring

    func testMountRingSetsState() {
        appState.bootstrap(ring0Path: tempDir)
        appState.mountRing(path: ringDir, name: "vivian-main")

        XCTAssertEqual(appState.mountedRingName, "vivian-main")
        XCTAssertEqual(appState.mountedRingPath, ringDir)
        XCTAssertNotNil(appState.sporeStore)
        XCTAssertNotNil(appState.transcriptStore)
    }

    func testMountRingScansChannels() {
        appState.bootstrap(ring0Path: tempDir)
        appState.mountRing(path: ringDir, name: "vivian-main")

        XCTAssertEqual(appState.channels.count, 1)
        XCTAssertEqual(appState.channels.first?.name, "general")
    }

    func testMountRingSetsActiveChannel() {
        appState.bootstrap(ring0Path: tempDir)
        appState.mountRing(path: ringDir, name: "vivian-main")

        XCTAssertEqual(appState.activeChannel?.name, "general")
    }

    func testMountRingConfiguresBackend() {
        appState.bootstrap(ring0Path: tempDir)
        appState.mountRing(path: ringDir, name: "vivian-main")

        XCTAssertEqual(appState.currentApiKey, "fake-api-key")
        XCTAssertTrue(appState.currentSystemInstruction.contains("Vivian"))
    }

    func testMountRingSetsStatusMessage() {
        appState.bootstrap(ring0Path: tempDir)
        appState.mountRing(path: ringDir, name: "vivian-main")

        XCTAssertEqual(appState.statusMessage, "Ring: vivian-main")
    }

    func testMountRingEndsVoiceMode() {
        appState.mode = .voice
        appState.bootstrap(ring0Path: tempDir)
        appState.mountRing(path: ringDir, name: "vivian-main")

        XCTAssertEqual(appState.mode, .text)
    }

    // MARK: - Backend Configuration

    func testBackendConfigMissingKeyShowsStatus() {
        let noKeyDeps = AppDependencies(
            loadManifest: deps.loadManifest,
            loadSOUL: deps.loadSOUL,
            keychainGet: { _ in nil },
            fileExists: deps.fileExists,
            scanChannels: deps.scanChannels,
            makeSporeStore: deps.makeSporeStore,
            makeTranscriptStore: deps.makeTranscriptStore,
            makeTextClient: deps.makeTextClient,
            commitAndPersist: deps.commitAndPersist
        )

        let mockVS = VoiceSessionManager(
            capture: MockAudioCapture(), playback: MockAudioPlayback(),
            clientFactory: { _ in MockGeminiLive() }
        )
        let state = AppState(deps: noKeyDeps, voiceSession: mockVS)
        state.bootstrap(ring0Path: tempDir)
        state.mountRing(path: ringDir, name: "vivian-main")

        XCTAssertTrue(state.statusMessage.contains("No API key"))
        XCTAssertNil(state.currentApiKey)
    }

    func testBackendConfigIncludesRingSOUL() {
        appState.bootstrap(ring0Path: tempDir)
        appState.mountRing(path: ringDir, name: "vivian-main")

        XCTAssertTrue(appState.currentSystemInstruction.contains("Personal ring"))
    }

    // MARK: - Switch Ring

    func testSwitchToRingNotConfiguredShowsStatus() {
        appState.bootstrap(ring0Path: tempDir)
        appState.switchToRing(named: "nonexistent")

        XCTAssertTrue(appState.statusMessage.contains("not set"))
    }

    func testSwitchToSameRingIsNoOp() {
        appState.bootstrap(ring0Path: tempDir)
        appState.mountRing(path: ringDir, name: "vivian-main")
        let originalStatus = appState.statusMessage

        appState.switchToRing(named: "vivian-main")
        XCTAssertEqual(appState.statusMessage, originalStatus)
    }

    // MARK: - Channel

    func testSwitchChannelUpdatesActiveChannel() {
        appState.bootstrap(ring0Path: tempDir)
        appState.mountRing(path: ringDir, name: "vivian-main")

        let channel = Channel(name: "work", ringPath: ringDir)
        appState.switchChannel(to: channel)

        XCTAssertEqual(appState.activeChannel?.name, "work")
    }

    // MARK: - Text Message

    func testSendTextMessageNotConfiguredShowsStatus() {
        appState.sendTextMessage("hello")
        XCTAssertEqual(appState.statusMessage, "Not configured. Open Settings.")
    }

    func testSendTextMessageAddsUserEntry() {
        appState.bootstrap(ring0Path: tempDir)
        appState.mountRing(path: ringDir, name: "vivian-main")
        appState.sendTextMessage("hello")

        XCTAssertEqual(appState.transcript.count, 1)
        XCTAssertEqual(appState.transcript[0].role, .user)
        XCTAssertEqual(appState.transcript[0].text, "hello")
    }

    func testSendTextMessageSetsProcessing() {
        appState.bootstrap(ring0Path: tempDir)
        appState.mountRing(path: ringDir, name: "vivian-main")
        appState.sendTextMessage("hello")

        XCTAssertTrue(appState.isProcessing)
        XCTAssertEqual(appState.statusMessage, "Thinking...")
    }

    // MARK: - Voice Mode

    func testStartVoiceModeWithoutBackend() {
        appState.startVoiceMode()
        XCTAssertEqual(appState.statusMessage, "No backend available for voice")
        XCTAssertEqual(appState.mode, .text)
    }

    func testStartVoiceModeChangesMode() {
        appState.bootstrap(ring0Path: tempDir)
        appState.mountRing(path: ringDir, name: "vivian-main")
        appState.startVoiceMode()

        XCTAssertEqual(appState.mode, .voice)
    }

    func testStopVoiceModeChangesMode() {
        appState.bootstrap(ring0Path: tempDir)
        appState.mountRing(path: ringDir, name: "vivian-main")
        appState.startVoiceMode()
        appState.stopVoiceMode()

        XCTAssertEqual(appState.mode, .text)
    }

    func testToggleVoiceMode() {
        appState.bootstrap(ring0Path: tempDir)
        appState.mountRing(path: ringDir, name: "vivian-main")

        appState.toggleVoiceMode()
        XCTAssertEqual(appState.mode, .voice)

        appState.toggleVoiceMode()
        XCTAssertEqual(appState.mode, .text)
    }

    // MARK: - Transcript Persistence

    func testAppendTranscriptEntryPersists() {
        appState.bootstrap(ring0Path: tempDir)
        appState.mountRing(path: ringDir, name: "vivian-main")

        let entry = TranscriptEntry(role: .user, text: "persisted", originPop: "osx-desktop")
        appState.appendTranscriptEntry(entry)

        XCTAssertEqual(appState.transcript.count, 1)

        // Verify it was written to disk
        let loaded = appState.transcriptStore!.loadRecentEntries(channel: "general")
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].text, "persisted")
    }

    // MARK: - End Session

    func testEndSessionGeneratesHandoffSpore() {
        appState.bootstrap(ring0Path: tempDir)
        appState.mountRing(path: ringDir, name: "vivian-main")

        appState.appendTranscriptEntry(TranscriptEntry(role: .user, text: "Hello", originPop: "osx-desktop"))
        appState.appendTranscriptEntry(TranscriptEntry(role: .model, text: "Hi there", originPop: "osx-desktop"))

        appState.endSession()

        let spores = appState.sporeStore!.loadAll()
        let handoffs = spores.filter { $0.type == .handoff }
        XCTAssertEqual(handoffs.count, 1)
        XCTAssertNotNil(handoffs[0].contextRecap)
    }

    // MARK: - Thinking Toggle

    func testShowThinkingDefaultsToFalse() {
        XCTAssertFalse(appState.showThinking)
    }

    // MARK: - Defaults

    func testInitialState() {
        XCTAssertNil(appState.ring0Path)
        XCTAssertNil(appState.mountedRingName)
        XCTAssertEqual(appState.mode, .text)
        XCTAssertFalse(appState.isPanelVisible)
        XCTAssertTrue(appState.transcript.isEmpty)
        XCTAssertEqual(appState.deviceId, "osx-desktop")
    }
}
