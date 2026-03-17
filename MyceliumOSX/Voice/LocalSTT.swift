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

    /// Called when final text is available (after stop or isFinal).
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

        recognitionTask?.cancel()
        recognitionTask = nil

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
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
                        print("[LocalSTT] Final text: \(text)")
                        self.onFinalText?(text)
                        self.cleanUp()
                    }
                }
            }

            if let error {
                print("[LocalSTT] Recognition error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    // Emit whatever we have as final before cleaning up
                    if !self.currentText.isEmpty {
                        self.onFinalText?(self.currentText)
                    }
                    self.cleanUp()
                }
            }
        }

        isListening = true
        currentText = ""
    }

    /// Stop listening. Signals end of audio, waits for final result via callback.
    func stop() {
        guard isListening else { return }

        // Stop the audio engine and end the audio stream.
        // This tells SFSpeechRecognizer we're done — it will deliver
        // one final result via the callback, which triggers cleanUp().
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        isListening = false

        // Safety: if the final callback doesn't fire within 3 seconds,
        // emit what we have and clean up.
        let capturedText = currentText
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, self.recognitionTask != nil else { return }
            print("[LocalSTT] Timeout waiting for final result, using: \(capturedText)")
            if !capturedText.isEmpty {
                self.onFinalText?(capturedText)
            }
            self.cleanUp()
        }
    }

    private func cleanUp() {
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
