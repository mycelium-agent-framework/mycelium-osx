import Foundation

/// Orchestrates the full voice pipeline in push-to-talk mode:
///   Hold button → mic streams to Gemini → release → Gemini responds with audio + text
/// Factory for creating Gemini Live clients. Allows test injection.
typealias GeminiLiveClientFactory = (String) -> GeminiLiveConnecting

@MainActor
@Observable
final class VoiceSessionManager {
    private var gemini: GeminiLiveConnecting?
    private let capture: AudioCapturing
    private let playback: AudioPlaying
    private let makeClient: GeminiLiveClientFactory

    init(
        capture: AudioCapturing = AudioCaptureManager(),
        playback: AudioPlaying = AudioPlaybackManager(),
        clientFactory: @escaping GeminiLiveClientFactory = { apiKey in GeminiLiveClient(apiKey: apiKey) }
    ) {
        self.capture = capture
        self.playback = playback
        self.makeClient = clientFactory
    }

    private(set) var isConnected = false
    /// True while user is holding the talk button and mic is streaming.
    private(set) var isRecording = false
    /// True while Vivian is speaking audio.
    private(set) var isSpeaking = false

    private var partialBuffer = ""
    private var thinkingBuffer = ""
    private var reconnectTask: Task<Void, Never>?

    /// Mic audio level (0.0-1.0) for UI visualization.
    var audioLevel: Float { capture.audioLevel }

    // Callbacks to AppState
    var onTranscriptEntry: ((TranscriptEntry) -> Void)?
    var onPartialText: ((String) -> Void)?
    var onThinkingText: ((String) -> Void)?
    var onToolCall: ((String, String, [String: Any]) -> Void)?
    var onConnectionChange: ((Bool) -> Void)?
    var onStatusMessage: ((String) -> Void)?

    private var apiKey: String = ""
    private var systemInstruction: String = ""

    // MARK: - Configuration

    func configure(apiKey: String, systemInstruction: String) {
        self.apiKey = apiKey
        self.systemInstruction = systemInstruction
        print("[VoiceSession] Configured with API key (\(apiKey.prefix(10))...)")
    }

    // MARK: - Session Lifecycle

    func startSession() async -> Bool {
        guard !apiKey.isEmpty else {
            onStatusMessage?("No API key. Open Settings.")
            return false
        }
        guard gemini == nil else { return isConnected }

        onStatusMessage?("Connecting...")

        let client = makeClient(apiKey)
        self.gemini = client

        client.onTextReceived = { [weak self] text, isFinal in
            Task { @MainActor [weak self] in self?.handleText(text, isFinal: isFinal) }
        }
        client.onThinkingReceived = { [weak self] text, isFinal in
            Task { @MainActor [weak self] in self?.handleThinking(text, isFinal: isFinal) }
        }
        client.onUserTranscript = { [weak self] text in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                print("[VoiceSession] User transcript: \(trimmed)")
                let entry = TranscriptEntry(role: .user, text: trimmed, originPop: "osx-desktop")
                self.onTranscriptEntry?(entry)
            }
        }
        client.onOutputTranscript = { [weak self] text in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                print("[VoiceSession] Vivian transcript: \(trimmed)")
                let entry = TranscriptEntry(role: .model, text: trimmed, originPop: "osx-desktop")
                self.onTranscriptEntry?(entry)
                self.onStatusMessage?("Ready — hold mic to talk")
            }
        }
        client.onAudioReceived = { [weak self] data in
            Task { @MainActor [weak self] in self?.handleAudio(data) }
        }
        client.onToolCall = { [weak self] callId, name, args in
            Task { @MainActor [weak self] in self?.onToolCall?(callId, name, args) }
        }
        client.onError = { [weak self] error in
            Task { @MainActor [weak self] in self?.handleError(error) }
        }
        client.onDisconnect = { [weak self] in
            Task { @MainActor [weak self] in self?.handleDisconnect() }
        }

        let ok = await client.connect(systemInstruction: systemInstruction)

        if ok {
            isConnected = true
            onConnectionChange?(true)
            onStatusMessage?("Ready — hold mic to talk")
            print("[VoiceSession] Connected.")
        } else {
            gemini = nil
            onStatusMessage?("Connection failed")
        }

        return ok
    }

    func endSession() {
        reconnectTask?.cancel()
        reconnectTask = nil
        stopRecording()
        playback.stop()
        gemini?.disconnect()
        gemini = nil
        isConnected = false
        isSpeaking = false
        partialBuffer = ""
        thinkingBuffer = ""
        onConnectionChange?(false)
    }

    // MARK: - Push-to-Talk

    /// Start recording (user pressed and is holding the talk button).
    func startRecording() {
        Task { @MainActor in
            // Request mic permission if needed
            let micOk = await capture.requestPermission()
            guard micOk else {
                onStatusMessage?("Mic denied — System Settings > Privacy > Microphone")
                return
            }

            // Connect if needed
            if !isConnected {
                let ok = await startSession()
                guard ok else { return }
            }

            // Interrupt any current playback
            if isSpeaking {
                bargeIn()
            }

            // Start streaming mic to Gemini
            capture.onAudioChunk = { [weak self] data in
                self?.gemini?.sendAudio(pcmData: data)
            }

            do {
                try capture.startCapture()
                isRecording = true
                onStatusMessage?("Recording — release to send")
                print("[VoiceSession] Push-to-talk: recording started")
            } catch {
                onStatusMessage?("Mic error: \(error.localizedDescription)")
            }
        }
    }

    /// Stop recording (user released the talk button).
    func stopRecording() {
        guard isRecording else { return }
        capture.stopCapture()
        capture.onAudioChunk = nil
        isRecording = false
        onStatusMessage?("Processing...")
        print("[VoiceSession] Push-to-talk: recording stopped, waiting for response")
    }

    // MARK: - Text Input

    func sendText(_ text: String) {
        if !isConnected {
            Task { @MainActor in
                let ok = await startSession()
                guard ok else { return }
                self.gemini?.sendText(text)
            }
        } else {
            gemini?.sendText(text)
        }
    }

    func sendToolResponse(callId: String, result: [String: Any]) {
        gemini?.sendToolResponse(callId: callId, result: result)
    }

    // MARK: - Barge-In

    func bargeIn() {
        playback.interrupt()
        isSpeaking = false
        partialBuffer = ""
        onPartialText?("")
    }

    // MARK: - Handlers

    // Text received from model (used in text-mode Live API, not audio mode)
    private func handleText(_ text: String, isFinal: Bool) {
        // In audio mode, we use outputTranscript instead
        // This handler is kept for text-mode fallback
        if isFinal {
            let fullText = partialBuffer + text
            partialBuffer = ""
            onPartialText?("")
        } else {
            partialBuffer += text
            onPartialText?(partialBuffer)
        }
    }

    private func handleThinking(_ text: String, isFinal: Bool) {
        if isFinal {
            let full = thinkingBuffer + text
            thinkingBuffer = ""
            if !full.isEmpty { onThinkingText?(full) }
        } else {
            thinkingBuffer += text
        }
    }

    private var speakingTimer: Task<Void, Never>?

    private func handleAudio(_ data: Data) {
        isSpeaking = true
        playback.enqueue(pcmData: data)

        speakingTimer?.cancel()
        speakingTimer = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self.isSpeaking = false
        }
    }

    private func handleError(_ error: Error) {
        print("[VoiceSession] Error: \(error.localizedDescription)")
        isConnected = false
        isRecording = false
        onConnectionChange?(false)
        onStatusMessage?("Error: \(error.localizedDescription)")
        scheduleReconnect()
    }

    private func handleDisconnect() {
        isConnected = false
        isSpeaking = false
        onConnectionChange?(false)
        onStatusMessage?("Disconnected")
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        reconnectTask?.cancel()
        reconnectTask = Task { @MainActor in
            onStatusMessage?("Reconnecting in 3s...")
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self.gemini = nil
            _ = await self.startSession()
        }
    }
}
