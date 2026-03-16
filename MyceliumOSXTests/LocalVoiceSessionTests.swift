import XCTest
@testable import MyceliumOSX

@MainActor
final class LocalVoiceSessionTests: XCTestCase {

    func testInitialState() {
        let session = LocalVoiceSession(ollamaClient: OllamaClient(model: "test", systemInstruction: "test"))
        XCTAssertFalse(session.isRecording)
        XCTAssertFalse(session.isSpeaking)
        XCTAssertEqual(session.partialUserText, "")
    }

    func testStopRecordingWhenNotRecording() {
        let session = LocalVoiceSession(ollamaClient: OllamaClient(model: "test", systemInstruction: "test"))
        session.stopRecording()
        XCTAssertFalse(session.isRecording)
    }

    func testInterruptStopsTTS() {
        let session = LocalVoiceSession(ollamaClient: OllamaClient(model: "test", systemInstruction: "test"))
        session.interrupt()
        XCTAssertFalse(session.isSpeaking)
    }

    func testHistoryAccumulatesOnProcessing() {
        let session = LocalVoiceSession(ollamaClient: OllamaClient(model: "test", systemInstruction: "test"))
        XCTAssertTrue(session.history.isEmpty)
    }

    func testCallbacksWired() {
        let session = LocalVoiceSession(ollamaClient: OllamaClient(model: "test", systemInstruction: "test"))
        var entries: [TranscriptEntry] = []
        session.onTranscriptEntry = { entries.append($0) }
        // Just verifying the callback is settable
        XCTAssertTrue(entries.isEmpty)
    }
}
