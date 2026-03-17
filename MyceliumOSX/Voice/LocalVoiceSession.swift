import AVFoundation
import Foundation

/// Local voice pipeline: SFSpeechRecognizer → Ollama → AVSpeechSynthesizer.
/// All on-device, no network required. Push-to-talk driven.
@MainActor
@Observable
final class LocalVoiceSession {
    private let stt = LocalSTT()
    private let tts = LocalTTS()
    private let ollama: OllamaClient

    private(set) var isRecording = false
    private(set) var isSpeaking = false
    var partialUserText: String = ""
    var history: [OllamaClient.Message] = []

    var onTranscriptEntry: ((TranscriptEntry) -> Void)?
    var onStatusMessage: ((String) -> Void)?

    init(ollamaClient: OllamaClient) {
        self.ollama = ollamaClient
        setupCallbacks()
    }

    private func setupCallbacks() {
        stt.onPartialText = { [weak self] text in
            DispatchQueue.main.async {
                self?.partialUserText = text
            }
        }

        stt.onFinalText = { [weak self] text in
            DispatchQueue.main.async {
                self?.handleUserSpeech(text)
            }
        }

        tts.onFinished = { [weak self] in
            DispatchQueue.main.async {
                self?.isSpeaking = false
                self?.onStatusMessage?("Ready — hold to talk")
            }
        }
    }

    // MARK: - Push to Talk

    func startRecording() {
        guard !isRecording else { return }

        // Interrupt TTS if speaking
        if isSpeaking {
            interrupt()
        }

        // Check speech recognition authorization first
        let authStatus = LocalSTT.authorizationStatus()
        if authStatus == .notDetermined {
            onStatusMessage?("Requesting speech permission...")
            Task {
                let status = await LocalSTT.requestAuthorization()
                if status == .authorized {
                    beginRecording()
                } else {
                    onStatusMessage?("Speech recognition denied — System Settings > Privacy > Speech Recognition")
                    print("[LocalVoice] Speech recognition denied: \(status.rawValue)")
                }
            }
            return
        }

        guard authStatus == .authorized else {
            onStatusMessage?("Speech recognition not authorized — System Settings > Privacy > Speech Recognition")
            print("[LocalVoice] Speech recognition not authorized: \(authStatus.rawValue)")
            return
        }

        // Also check mic permission
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        if micStatus == .notDetermined {
            Task {
                let granted = await AVCaptureDevice.requestAccess(for: .audio)
                if granted { beginRecording() }
                else { onStatusMessage?("Microphone access denied") }
            }
            return
        }
        guard micStatus == .authorized else {
            onStatusMessage?("Microphone not authorized — System Settings > Privacy > Microphone")
            return
        }

        beginRecording()
    }

    private func beginRecording() {
        do {
            try stt.start()
            isRecording = true
            partialUserText = ""
            onStatusMessage?("Listening...")
            print("[LocalVoice] Recording started")
        } catch {
            onStatusMessage?("Speech error: \(error.localizedDescription)")
            print("[LocalVoice] STT start failed: \(error)")
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        stt.stop()
        isRecording = false
        onStatusMessage?("Processing...")
        print("[LocalVoice] Recording stopped, text: \(stt.currentText.prefix(50))")
    }

    func interrupt() {
        tts.stop()
        isSpeaking = false
    }

    // MARK: - Pipeline

    private var isProcessingVoice = false

    private func handleUserSpeech(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            onStatusMessage?("Ready — hold to talk")
            return
        }

        // Prevent duplicate processing (STT can fire onFinalText more than once)
        guard !isProcessingVoice else {
            print("[LocalVoice] Ignoring duplicate final text: \(trimmed.prefix(30))")
            return
        }
        isProcessingVoice = true
        partialUserText = ""

        // Add user transcript
        let userEntry = TranscriptEntry(role: .user, text: trimmed, originPop: "osx-desktop")
        onTranscriptEntry?(userEntry)

        // Send to Ollama
        onStatusMessage?("Thinking...")

        Task {
            do {
                let response = try await ollama.send(prompt: trimmed, history: history)
                let responseText = response.trimmingCharacters(in: .whitespacesAndNewlines)

                // Update history
                OllamaClient.appendToHistory(&history, role: "user", content: trimmed)
                OllamaClient.appendToHistory(&history, role: "assistant", content: responseText)
                OllamaClient.truncateHistory(&history)

                guard !responseText.isEmpty else {
                    onStatusMessage?("Ready — hold to talk")
                    isProcessingVoice = false
                    return
                }

                // Add model transcript
                let modelEntry = TranscriptEntry(role: .model, text: responseText, originPop: "osx-desktop")
                onTranscriptEntry?(modelEntry)

                // Speak the response
                isSpeaking = true
                onStatusMessage?("Speaking...")
                tts.speak(responseText)

                print("[LocalVoice] Response: \(responseText.prefix(80))")
            } catch {
                print("[LocalVoice] Ollama error: \(error)")
                onStatusMessage?("Error: \(error.localizedDescription)")
            }
            isProcessingVoice = false
        }
    }
}
