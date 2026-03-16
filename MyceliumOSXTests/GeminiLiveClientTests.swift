import XCTest
@testable import MyceliumOSX

/// Tests for GeminiLiveClient message parsing.
final class GeminiLiveClientTests: XCTestCase {

    private func makeClient() -> GeminiLiveClient {
        GeminiLiveClient(apiKey: "test-key")
    }

    // MARK: - Output Transcription

    func testOutputTranscriptionAccumulatesUntilTurnComplete() {
        let client = makeClient()
        var receivedTranscript: String?
        client.onOutputTranscript = { receivedTranscript = $0 }

        client.handleServerContent(["outputTranscription": ["text": "Hello"]])
        XCTAssertNil(receivedTranscript, "Should not emit until turnComplete")

        client.handleServerContent(["outputTranscription": ["text": "Hello there"]])
        XCTAssertNil(receivedTranscript)

        client.handleServerContent(["turnComplete": true])
        XCTAssertEqual(receivedTranscript, "Hello there")
    }

    func testInputTranscriptionAccumulatesUntilTurnComplete() {
        let client = makeClient()
        var receivedTranscript: String?
        client.onUserTranscript = { receivedTranscript = $0 }

        client.handleServerContent(["inputTranscription": ["text": "What"]])
        client.handleServerContent(["inputTranscription": ["text": "What time is it"]])
        XCTAssertNil(receivedTranscript)

        client.handleServerContent(["turnComplete": true])
        XCTAssertEqual(receivedTranscript, "What time is it")
    }

    func testAudioChunksDelivered() {
        let client = makeClient()
        var audioChunkCount = 0
        client.onAudioReceived = { _ in audioChunkCount += 1 }

        let fakeAudio = Data([0, 1, 2, 3]).base64EncodedString()
        client.handleServerContent([
            "modelTurn": [
                "parts": [["inlineData": ["mimeType": "audio/pcm", "data": fakeAudio]]]
            ]
        ])

        XCTAssertEqual(audioChunkCount, 1)
    }

    func testThinkingBlocksSeparatedFromTranscript() {
        let client = makeClient()
        var thinkingReceived = false
        var transcriptText: String?
        client.onThinkingReceived = { _, _ in thinkingReceived = true }
        client.onOutputTranscript = { transcriptText = $0 }

        // Thinking part (should not appear as transcript)
        client.handleServerContent([
            "modelTurn": ["parts": [["text": "Analyzing...", "thought": true]]]
        ])
        XCTAssertTrue(thinkingReceived)

        // Actual spoken words
        client.handleServerContent(["outputTranscription": ["text": "Hello."]])
        client.handleServerContent(["turnComplete": true])

        XCTAssertEqual(transcriptText, "Hello.")
    }

    func testEmptyTranscriptionsNotEmitted() {
        let client = makeClient()
        var emitCount = 0
        client.onOutputTranscript = { _ in emitCount += 1 }
        client.onUserTranscript = { _ in emitCount += 1 }

        client.handleServerContent(["turnComplete": true])
        XCTAssertEqual(emitCount, 0)
    }

    func testBuffersClearedAfterTurnComplete() {
        let client = makeClient()
        var transcriptCount = 0
        client.onOutputTranscript = { _ in transcriptCount += 1 }

        client.handleServerContent(["outputTranscription": ["text": "Hi"]])
        client.handleServerContent(["turnComplete": true])
        XCTAssertEqual(transcriptCount, 1)

        // Second turn with no new transcription
        client.handleServerContent(["turnComplete": true])
        XCTAssertEqual(transcriptCount, 1, "Empty second turn should not emit")
    }

    func testMultipleTurnsProduceMultipleTranscripts() {
        let client = makeClient()
        var transcripts: [String] = []
        client.onOutputTranscript = { transcripts.append($0) }

        // Turn 1
        client.handleServerContent(["outputTranscription": ["text": "Hello"]])
        client.handleServerContent(["turnComplete": true])

        // Turn 2
        client.handleServerContent(["outputTranscription": ["text": "How are you?"]])
        client.handleServerContent(["turnComplete": true])

        XCTAssertEqual(transcripts, ["Hello", "How are you?"])
    }

    func testBothUserAndModelTranscriptsInSameTurn() {
        let client = makeClient()
        var userText: String?
        var modelText: String?
        client.onUserTranscript = { userText = $0 }
        client.onOutputTranscript = { modelText = $0 }

        client.handleServerContent(["inputTranscription": ["text": "What's up?"]])
        client.handleServerContent(["outputTranscription": ["text": "Not much!"]])
        client.handleServerContent(["turnComplete": true])

        XCTAssertEqual(userText, "What's up?")
        XCTAssertEqual(modelText, "Not much!")
    }

    func testNonThoughtTextPartsIgnoredInAudioMode() {
        let client = makeClient()
        var outputText: String?
        client.onOutputTranscript = { outputText = $0 }

        // Non-thought text (model's internal reasoning, not actual speech)
        client.handleServerContent([
            "modelTurn": ["parts": [["text": "I should say hello"]]]
        ])

        // Only outputTranscription counts as spoken text
        client.handleServerContent(["outputTranscription": ["text": "Hi"]])
        client.handleServerContent(["turnComplete": true])

        XCTAssertEqual(outputText, "Hi")
    }
}
