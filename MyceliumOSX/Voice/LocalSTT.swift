import AVFoundation
import Foundation
import Speech

/// Local speech-to-text using macOS built-in SFSpeechRecognizer.
/// No network required — runs on-device with Apple Silicon optimization.
@Observable
final class LocalSTT {
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    /// Current partial transcription (updates as user speaks).
    private(set) var currentText: String = ""

    /// Whether actively listening.
    private(set) var isListening = false

    /// Called with each partial update (for live display).
    var onPartialText: ((String) -> Void)?

    /// Called when user stops speaking and final text is available.
    var onFinalText: ((String) -> Void)?

    /// Request speech recognition authorization.
    static func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    static func authorizationStatus() -> SFSpeechRecognizerAuthorizationStatus {
        SFSpeechRecognizer.authorizationStatus()
    }

    /// Start listening. Call stop() when user releases push-to-talk.
    func start() throws {
        guard let recognizer, recognizer.isAvailable else {
            throw STTError.notAvailable
        }

        // Cancel any existing task
        recognitionTask?.cancel()
        recognitionTask = nil

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // Force on-device recognition (no network)
        if #available(macOS 13, *) {
            request.requiresOnDeviceRecognition = true
        }
        self.recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            if let result {
                let text = result.bestTranscription.formattedString
                DispatchQueue.main.async {
                    self.currentText = text
                    self.onPartialText?(text)
                }

                if result.isFinal {
                    DispatchQueue.main.async {
                        self.onFinalText?(text)
                    }
                }
            }

            if error != nil {
                DispatchQueue.main.async {
                    self.stopInternal()
                }
            }
        }

        isListening = true
        currentText = ""
    }

    /// Stop listening and finalize.
    func stop() {
        guard isListening else { return }

        // End the audio stream — this triggers the final result
        recognitionRequest?.endAudio()
        stopInternal()

        // If we have accumulated text, emit it as final
        if !currentText.isEmpty {
            onFinalText?(currentText)
        }
    }

    private func stopInternal() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        isListening = false
    }

    enum STTError: Error, LocalizedError {
        case notAvailable
        case notAuthorized

        var errorDescription: String? {
            switch self {
            case .notAvailable: return "Speech recognition not available"
            case .notAuthorized: return "Speech recognition not authorized"
            }
        }
    }
}
