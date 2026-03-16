import XCTest
@testable import MyceliumOSX

@MainActor
final class VoiceSessionManagerTests: XCTestCase {
    var mockCapture: MockAudioCapture!
    var mockPlayback: MockAudioPlayback!
    var mockGemini: MockGeminiLive!
    var session: VoiceSessionManager!

    override func setUp() {
        super.setUp()
        mockCapture = MockAudioCapture()
        mockPlayback = MockAudioPlayback()
        mockGemini = MockGeminiLive()

        session = VoiceSessionManager(
            capture: mockCapture,
            playback: mockPlayback,
            clientFactory: { [weak self] _ in self?.mockGemini ?? MockGeminiLive() }
        )
        session.configure(apiKey: "test-key", systemInstruction: "Be brief.")
    }

    // MARK: - Session Lifecycle

    func testStartSessionConnectsSuccessfully() async {
        let ok = await session.startSession()
        XCTAssertTrue(ok)
        XCTAssertTrue(session.isConnected)
        XCTAssertEqual(mockGemini.connectCallCount, 1)
    }

    func testStartSessionFailsWithNoApiKey() async {
        session.configure(apiKey: "", systemInstruction: "test")
        let ok = await session.startSession()
        XCTAssertFalse(ok)
        XCTAssertFalse(session.isConnected)
    }

    func testStartSessionFailsWhenConnectionFails() async {
        mockGemini.shouldConnectSuccessfully = false
        let ok = await session.startSession()
        XCTAssertFalse(ok)
        XCTAssertFalse(session.isConnected)
    }

    func testEndSessionDisconnects() async {
        _ = await session.startSession()
        session.endSession()
        XCTAssertFalse(session.isConnected)
        XCTAssertEqual(mockGemini.disconnectCallCount, 1)
    }

    func testEndSessionStopsRecording() async {
        _ = await session.startSession()
        session.startRecording()
        // Wait for async recording start
        try? await Task.sleep(for: .milliseconds(50))
        session.endSession()
        XCTAssertFalse(session.isRecording)
    }

    // MARK: - Push to Talk

    func testStartRecordingConnectsIfNeeded() {
        session.startRecording()
        // startRecording fires an async task that connects then captures
        let expectation = expectation(description: "recording starts")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            XCTAssertTrue(self.session.isConnected)
            XCTAssertTrue(self.mockCapture.isCapturing)
            XCTAssertTrue(self.session.isRecording)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2)
    }

    func testStartRecordingDeniedWhenMicNotGranted() {
        mockCapture.permissionGranted = false
        session.startRecording()

        let expectation = expectation(description: "denied")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            XCTAssertFalse(self.session.isRecording)
            XCTAssertFalse(self.mockCapture.isCapturing)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2)
    }

    func testStopRecordingStopsCapture() async {
        _ = await session.startSession()

        mockCapture.onAudioChunk = { _ in }
        try? mockCapture.startCapture()
        session.startRecording()
        try? await Task.sleep(for: .milliseconds(50))

        session.stopRecording()
        XCTAssertFalse(session.isRecording)
        XCTAssertTrue(mockCapture.stopCaptureCallCount > 0)
    }

    func testAudioChunksSentToGemini() async {
        _ = await session.startSession()
        session.startRecording()
        try? await Task.sleep(for: .milliseconds(100))

        // Simulate audio chunk from mic
        mockCapture.simulateAudioChunk(Data(repeating: 42, count: 320))

        XCTAssertEqual(mockGemini.sentAudioChunks.count, 1)
        XCTAssertEqual(mockGemini.sentAudioChunks[0].count, 320)
    }

    // MARK: - Transcript Callbacks

    func testUserTranscriptCallback() async {
        var receivedEntries: [TranscriptEntry] = []
        session.onTranscriptEntry = { receivedEntries.append($0) }

        _ = await session.startSession()

        mockGemini.simulateUserTranscript("Hello Vivian")
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(receivedEntries.count, 1)
        XCTAssertEqual(receivedEntries[0].role, .user)
        XCTAssertEqual(receivedEntries[0].text, "Hello Vivian")
    }

    func testOutputTranscriptCallback() async {
        var receivedEntries: [TranscriptEntry] = []
        session.onTranscriptEntry = { receivedEntries.append($0) }

        _ = await session.startSession()

        mockGemini.simulateOutputTranscript("Hi there!")
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(receivedEntries.count, 1)
        XCTAssertEqual(receivedEntries[0].role, .model)
        XCTAssertEqual(receivedEntries[0].text, "Hi there!")
    }

    func testEmptyTranscriptIgnored() async {
        var receivedEntries: [TranscriptEntry] = []
        session.onTranscriptEntry = { receivedEntries.append($0) }

        _ = await session.startSession()

        mockGemini.simulateUserTranscript("   ")
        mockGemini.simulateOutputTranscript("")
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(receivedEntries.count, 0)
    }

    // MARK: - Audio Playback

    func testAudioResponseEnqueued() async {
        _ = await session.startSession()

        let audioData = Data(repeating: 1, count: 100)
        mockGemini.simulateAudio(audioData)
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(mockPlayback.enqueuedChunks.count, 1)
        XCTAssertTrue(session.isSpeaking)
    }

    func testBargeInStopsPlaybackAndResetsSpeaking() async {
        _ = await session.startSession()

        mockGemini.simulateAudio()
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(session.isSpeaking)

        session.bargeIn()
        XCTAssertFalse(session.isSpeaking)
        XCTAssertEqual(mockPlayback.interruptCallCount, 1)
    }

    // MARK: - Text Input

    func testSendTextWhenConnected() async {
        _ = await session.startSession()
        session.sendText("Hello")
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(mockGemini.sentTexts, ["Hello"])
    }

    func testSendTextConnectsIfNeeded() {
        session.sendText("Hello")

        let expectation = expectation(description: "connects and sends")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            XCTAssertTrue(self.session.isConnected)
            XCTAssertEqual(self.mockGemini.sentTexts, ["Hello"])
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2)
    }

    // MARK: - Status Messages

    func testStatusMessageOnConnect() async {
        var messages: [String] = []
        session.onStatusMessage = { messages.append($0) }

        _ = await session.startSession()

        XCTAssertTrue(messages.contains("Connecting..."))
        XCTAssertTrue(messages.contains("Ready — hold mic to talk"))
    }

    func testStatusMessageOnConnectionFailure() async {
        var messages: [String] = []
        session.onStatusMessage = { messages.append($0) }

        mockGemini.shouldConnectSuccessfully = false
        _ = await session.startSession()

        XCTAssertTrue(messages.contains("Connection failed"))
    }

    // MARK: - Error Handling

    func testErrorDisconnectsSession() async {
        _ = await session.startSession()

        mockGemini.simulateError(NSError(domain: "test", code: 1))
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertFalse(session.isConnected)
    }

    func testDisconnectTriggersReconnect() async {
        var messages: [String] = []
        session.onStatusMessage = { messages.append($0) }

        _ = await session.startSession()
        mockGemini.simulateDisconnect()
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertTrue(messages.contains("Disconnected"))
        XCTAssertTrue(messages.contains { $0.contains("Reconnecting") })
    }

    // MARK: - Audio Level

    func testAudioLevelPassesThrough() {
        mockCapture.audioLevel = 0.75
        XCTAssertEqual(session.audioLevel, 0.75)
    }
}

// Helper for contains with predicate
private extension Array where Element == String {
    func contains(where predicate: (String) -> Bool) -> Bool {
        first(where: predicate) != nil
    }
}
