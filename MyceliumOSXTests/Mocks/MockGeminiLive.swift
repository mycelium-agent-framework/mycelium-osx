import Foundation
@testable import MyceliumOSX

final class MockGeminiLive: GeminiLiveConnecting {
    var isConnected = false
    var isSetupComplete = false

    var onTextReceived: ((String, Bool) -> Void)?
    var onThinkingReceived: ((String, Bool) -> Void)?
    var onUserTranscript: ((String) -> Void)?
    var onOutputTranscript: ((String) -> Void)?
    var onAudioReceived: ((Data) -> Void)?
    var onToolCall: ((String, String, [String: Any]) -> Void)?
    var onError: ((Error) -> Void)?
    var onDisconnect: (() -> Void)?

    var connectCallCount = 0
    var disconnectCallCount = 0
    var sentAudioChunks: [Data] = []
    var sentTexts: [String] = []
    var sentToolResponses: [(String, [String: Any])] = []
    var shouldConnectSuccessfully = true
    var lastSystemInstruction: String?

    func connect(systemInstruction: String) async -> Bool {
        connectCallCount += 1
        lastSystemInstruction = systemInstruction
        if shouldConnectSuccessfully {
            isConnected = true
            isSetupComplete = true
        }
        return shouldConnectSuccessfully
    }

    func disconnect() {
        disconnectCallCount += 1
        isConnected = false
        isSetupComplete = false
    }

    func sendAudio(pcmData: Data) {
        sentAudioChunks.append(pcmData)
    }

    func sendText(_ text: String) {
        sentTexts.append(text)
    }

    func sendToolResponse(callId: String, result: [String: Any]) {
        sentToolResponses.append((callId, result))
    }

    // MARK: - Simulation helpers

    func simulateUserTranscript(_ text: String) {
        onUserTranscript?(text)
    }

    func simulateOutputTranscript(_ text: String) {
        onOutputTranscript?(text)
    }

    func simulateAudio(_ data: Data = Data(repeating: 0, count: 100)) {
        onAudioReceived?(data)
    }

    func simulateError(_ error: Error) {
        onError?(error)
    }

    func simulateDisconnect() {
        isConnected = false
        onDisconnect?()
    }
}
