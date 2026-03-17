import XCTest
@testable import MyceliumOSX

// MARK: - Manifest Multi-Provider Parsing

final class BackendConfigTests: XCTestCase {

    func testParseLegacySingleProvider() throws {
        let json = """
        {"provider": "gemini", "api_key_ref": "gemini-personal", "model": "gemini-2.5-flash"}
        """.data(using: .utf8)!

        let config = try JSONDecoder().decode(BackendConfig.self, from: json)
        let resolved = config.resolvedProviders

        XCTAssertEqual(resolved.count, 1)
        XCTAssertEqual(resolved[0].name, "gemini")
        XCTAssertEqual(resolved[0].model, "gemini-2.5-flash")
        XCTAssertEqual(resolved[0].apiKeyRef, "gemini-personal")
    }

    func testParseMultiProvider() throws {
        let json = """
        {
          "providers": [
            {"name": "ollama", "model": "gemma3:4b"},
            {"name": "claude", "model": "haiku"},
            {"name": "gemini", "model": "gemini-2.5-flash", "api_key_ref": "gemini-personal"}
          ],
          "routing": "manual"
        }
        """.data(using: .utf8)!

        let config = try JSONDecoder().decode(BackendConfig.self, from: json)
        let resolved = config.resolvedProviders

        XCTAssertEqual(resolved.count, 3)
        XCTAssertEqual(resolved[0].name, "ollama")
        XCTAssertEqual(resolved[1].name, "claude")
        XCTAssertEqual(resolved[2].name, "gemini")
        XCTAssertEqual(config.resolvedRouting, .manual)
    }

    func testParseAutoRouting() throws {
        let json = """
        {"providers": [{"name": "ollama", "model": "gemma3:4b"}], "routing": "auto"}
        """.data(using: .utf8)!

        let config = try JSONDecoder().decode(BackendConfig.self, from: json)
        XCTAssertEqual(config.resolvedRouting, .auto)
    }

    func testDefaultRoutingIsManual() throws {
        let json = """
        {"providers": [{"name": "ollama", "model": "gemma3:4b"}]}
        """.data(using: .utf8)!

        let config = try JSONDecoder().decode(BackendConfig.self, from: json)
        XCTAssertEqual(config.resolvedRouting, .manual)
    }

    func testEmptyBackendConfig() throws {
        let json = "{}".data(using: .utf8)!
        let config = try JSONDecoder().decode(BackendConfig.self, from: json)
        XCTAssertTrue(config.resolvedProviders.isEmpty)
    }

    func testProviderWithoutApiKeyRef() throws {
        let json = """
        {"providers": [{"name": "ollama", "model": "gemma3:4b"}]}
        """.data(using: .utf8)!

        let config = try JSONDecoder().decode(BackendConfig.self, from: json)
        XCTAssertNil(config.resolvedProviders[0].apiKeyRef)
    }
}

// MARK: - AppState Provider Routing

@MainActor
final class BackendRoutingAppStateTests: XCTestCase {
    var tempDir: URL!
    var ringDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mycelium-routing-\(UUID().uuidString)")
        ringDir = tempDir.appendingPathComponent("vivian-main")
        try? FileManager.default.createDirectory(
            at: ringDir.appendingPathComponent("channels/general"),
            withIntermediateDirectories: true
        )
        try? FileManager.default.createDirectory(
            at: ringDir.appendingPathComponent(".mycelium"),
            withIntermediateDirectories: true
        )
        try? "# SOUL".write(to: tempDir.appendingPathComponent("SOUL.md"), atomically: true, encoding: .utf8)
        try? "# Ring".write(to: ringDir.appendingPathComponent("SOUL.md"), atomically: true, encoding: .utf8)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private func makeAppState(providers: [ProviderConfig], routing: RoutingMode = .manual) -> AppState {
        let backend = BackendConfig(providers: providers, routing: routing)
        let manifest = Manifest(
            agentName: "Vivian", version: "0.1.0",
            pops: [PopEntry(deviceId: "osx-desktop", displayName: "Mac", capabilities: [], lastActive: nil, allowedRings: ["vivian-main"])],
            rings: [RingEntry(name: "vivian-main", repoUrl: "url", accessRules: [:], backend: backend)],
            channels: [], activeRing: nil
        )

        let deps = AppDependencies(
            loadManifest: { _ in manifest },
            loadSOUL: { url in try? String(contentsOf: url.appendingPathComponent("SOUL.md"), encoding: .utf8) },
            keychainGet: { ref in ref == "gemini-key" ? "fake-api-key" : nil },
            fileExists: { FileManager.default.fileExists(atPath: $0) },
            scanChannels: { _ in [Channel(name: "general", ringPath: self.ringDir)] },
            makeSporeStore: { SporeStore(ringPath: $0, deviceId: $1) },
            makeTranscriptStore: { TranscriptStore(ringPath: $0, deviceId: $1) },
            makeTextClient: { _, _ in GeminiTextClient(apiKey: "fake", systemInstruction: "test") },
            commitAndPersist: { _, _ in }
        )

        let vs = VoiceSessionManager(capture: MockAudioCapture(), playback: MockAudioPlayback(), clientFactory: { _ in MockGeminiLive() })
        return AppState(deps: deps, voiceSession: vs)
    }

    func testMultiProviderAvailabilityPopulated() {
        let providers = [
            ProviderConfig(name: "ollama", model: "gemma3:4b", apiKeyRef: nil),
            ProviderConfig(name: "claude", model: "haiku", apiKeyRef: nil),
            ProviderConfig(name: "gemini", model: "gemini-2.5-flash", apiKeyRef: "gemini-key"),
        ]
        let appState = makeAppState(providers: providers)
        appState.bootstrap(ring0Path: tempDir)
        appState.mountRing(path: ringDir, name: "vivian-main")

        // availableProviders should be populated from manifest
        XCTAssertEqual(appState.availableProviders.count, 3)
        XCTAssertEqual(appState.availableProviders[0].name, "ollama")
        XCTAssertEqual(appState.availableProviders[1].name, "claude")
    }

    func testDefaultProviderIsFirstAvailable() {
        let providers = [
            ProviderConfig(name: "ollama", model: "gemma3:4b", apiKeyRef: nil),
            ProviderConfig(name: "claude", model: "haiku", apiKeyRef: nil),
        ]
        let appState = makeAppState(providers: providers)
        appState.bootstrap(ring0Path: tempDir)
        appState.mountRing(path: ringDir, name: "vivian-main")

        // First provider that's available becomes active
        XCTAssertFalse(appState.activeProvider.isEmpty)
    }

    func testSwitchProvider() {
        let providers = [
            ProviderConfig(name: "ollama", model: "gemma3:4b", apiKeyRef: nil),
            ProviderConfig(name: "claude", model: "haiku", apiKeyRef: nil),
        ]
        let appState = makeAppState(providers: providers)
        appState.bootstrap(ring0Path: tempDir)
        appState.mountRing(path: ringDir, name: "vivian-main")

        appState.switchProvider(to: "claude")
        XCTAssertEqual(appState.activeProvider, "claude")

        appState.switchProvider(to: "ollama")
        XCTAssertEqual(appState.activeProvider, "ollama")
    }

    func testSwitchToNonexistentProviderDoesNothing() {
        let providers = [ProviderConfig(name: "ollama", model: "gemma3:4b", apiKeyRef: nil)]
        let appState = makeAppState(providers: providers)
        appState.bootstrap(ring0Path: tempDir)
        appState.mountRing(path: ringDir, name: "vivian-main")

        let original = appState.activeProvider
        appState.switchProvider(to: "nonexistent")
        XCTAssertEqual(appState.activeProvider, original)
    }

    func testUseLocalModelTrueWhenOllamaActive() {
        let providers = [
            ProviderConfig(name: "ollama", model: "gemma3:4b", apiKeyRef: nil),
            ProviderConfig(name: "claude", model: "haiku", apiKeyRef: nil),
        ]
        let appState = makeAppState(providers: providers)
        appState.bootstrap(ring0Path: tempDir)
        appState.mountRing(path: ringDir, name: "vivian-main")

        appState.switchProvider(to: "ollama")
        XCTAssertTrue(appState.useLocalModel)

        appState.switchProvider(to: "claude")
        XCTAssertFalse(appState.useLocalModel)
    }

    func testLegacySingleProviderStillWorks() {
        // Legacy format: provider/model/api_key_ref at top level
        let legacyBackend = BackendConfig(providers: [], routing: nil)
        // Since we can't easily construct legacy format in Swift,
        // test via JSON parsing
        let json = """
        {"provider": "gemini", "api_key_ref": "gemini-key", "model": "gemini-2.5-flash"}
        """.data(using: .utf8)!
        let config = try! JSONDecoder().decode(BackendConfig.self, from: json)

        XCTAssertEqual(config.resolvedProviders.count, 1)
        XCTAssertEqual(config.resolvedProviders[0].name, "gemini")
    }
}
