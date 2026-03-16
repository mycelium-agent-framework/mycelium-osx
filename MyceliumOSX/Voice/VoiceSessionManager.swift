import Foundation

/// Orchestrates the full voice pipeline:
///   mic → GeminiLive → playback → transcript persistence
@MainActor
@Observable
final class VoiceSessionManager {
    private var gemini: GeminiLiveClient?
    private let capture = AudioCaptureManager()
    private let playback = AudioPlaybackManager()

    private(set) var isConnected = false
    private(set) var isListening = false
    private(set) var isSpeaking = false

    /// Mic audio level (0.0-1.0) for UI visualization.
    var audioLevel: Float { capture.audioLevel }

    private var partialBuffer = ""
    private var connectingTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?

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
        print("[VoiceSession] Configured with API key (\(apiKey.prefix(10))...) and \(systemInstruction.count) char system instruction")
    }

    // MARK: - Session Lifecycle

    /// Connect to Gemini Live API. Waits for setupComplete before returning.
    func startSession() async -> Bool {
        guard !apiKey.isEmpty else {
            print("[VoiceSession] No API key configured.")
            onStatusMessage?("No API key. Open Settings.")
            return false
        }
        guard gemini == nil else { return isConnected }

        onStatusMessage?("Connecting to Gemini...")

        let client = GeminiLiveClient(apiKey: apiKey)
        self.gemini = client

        client.onTextReceived = { [weak self] text, isFinal in
            Task { @MainActor [weak self] in
                self?.handleText(text, isFinal: isFinal)
            }
        }

        client.onThinkingReceived = { [weak self] text, isFinal in
            Task { @MainActor [weak self] in
                self?.handleThinking(text, isFinal: isFinal)
            }
        }

        client.onAudioReceived = { [weak self] data in
            Task { @MainActor [weak self] in
                self?.handleAudio(data)
            }
        }

        client.onToolCall = { [weak self] callId, name, args in
            Task { @MainActor [weak self] in
                self?.onToolCall?(callId, name, args)
            }
        }

        client.onError = { [weak self] error in
            Task { @MainActor [weak self] in
                self?.handleError(error)
            }
        }

        client.onDisconnect = { [weak self] in
            Task { @MainActor [weak self] in
                self?.handleDisconnect()
            }
        }

        let ok = await client.connect(systemInstruction: systemInstruction)

        if ok {
            isConnected = true
            onConnectionChange?(true)
            onStatusMessage?("Connected")
            print("[VoiceSession] Session started successfully.")
        } else {
            gemini = nil
            onStatusMessage?("Connection failed")
            print("[VoiceSession] Session failed to start.")
        }

        return ok
    }

    func endSession() {
        connectingTask?.cancel()
        reconnectTask?.cancel()
        connectingTask = nil
        reconnectTask = nil
        stopListening()
        playback.stop()
        gemini?.disconnect()
        gemini = nil
        isConnected = false
        isSpeaking = false
        partialBuffer = ""
        onConnectionChange?(false)
        print("[VoiceSession] Session ended.")
    }

    // MARK: - Listening

    func startListening() {
        connectingTask = Task { @MainActor in
            onStatusMessage?("Requesting mic access...")

            let micOk = await capture.requestPermission()
            guard micOk else {
                print("[VoiceSession] Microphone permission denied.")
                onStatusMessage?("Mic denied — open System Settings > Privacy > Microphone")
                return
            }
            print("[VoiceSession] Mic permission granted.")

            if !isConnected {
                onStatusMessage?("Connecting to Gemini Live...")
                let ok = await startSession()
                guard ok else {
                    onStatusMessage?("Failed to connect to Gemini")
                    return
                }
            }

            onStatusMessage?("Starting mic capture...")
            beginCapture()
        }
    }

    func stopListening() {
        capture.stopCapture()
        capture.onAudioChunk = nil
        isListening = false
    }

    func toggleListening() {
        if isListening {
            stopListening()
        } else {
            startListening()
        }
    }

    private func beginCapture() {
        var chunkCount = 0
        capture.onAudioChunk = { [weak self] data in
            guard let self else { return }
            // Half-duplex: don't send mic audio while Vivian is speaking
            // (prevents echo loop where she hears herself and responds to it)
            guard !self.isSpeaking else { return }
            self.gemini?.sendAudio(pcmData: data)
            chunkCount += 1
            if chunkCount == 1 {
                print("[VoiceSession] First audio chunk sent (\(data.count) bytes)")
            }
        }

        do {
            try capture.startCapture()
            isListening = true
            onStatusMessage?("Voice active — speak now")
            print("[VoiceSession] Mic capture started, streaming to Gemini")
        } catch {
            print("[VoiceSession] Failed to start capture: \(error)")
            onStatusMessage?("Mic error: \(error.localizedDescription)")
        }
    }

    // MARK: - Text Input

    func sendText(_ text: String) {
        if !isConnected {
            Task { @MainActor in
                let ok = await startSession()
                guard ok else { return }
                gemini?.sendText(text)
            }
        } else {
            gemini?.sendText(text)
        }
    }

    // MARK: - Tool Responses

    func sendToolResponse(callId: String, result: [String: Any]) {
        gemini?.sendToolResponse(callId: callId, result: result)
    }

    // MARK: - Handlers

    private var thinkingBuffer = ""

    private func handleThinking(_ text: String, isFinal: Bool) {
        if isFinal {
            let fullThinking = thinkingBuffer + text
            thinkingBuffer = ""
            if !fullThinking.isEmpty {
                onThinkingText?(fullThinking)
            }
        } else {
            thinkingBuffer += text
        }
    }

    private func handleText(_ text: String, isFinal: Bool) {
        if isFinal {
            let fullText = partialBuffer + text
            partialBuffer = ""
            onPartialText?("")

            if !fullText.isEmpty {
                let entry = TranscriptEntry(
                    role: .model,
                    text: fullText.trimmingCharacters(in: .whitespacesAndNewlines),
                    isFinal: true,
                    originPop: "osx-desktop"
                )
                onTranscriptEntry?(entry)
            }
        } else {
            partialBuffer += text
            onPartialText?(partialBuffer)
        }
    }

    private var speakingTimer: Task<Void, Never>?

    private func handleAudio(_ data: Data) {
        isSpeaking = true
        playback.enqueue(pcmData: data)

        // Reset the "done speaking" timer on each audio chunk.
        // Only mark as not speaking after 500ms with no new audio.
        speakingTimer?.cancel()
        speakingTimer = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self.isSpeaking = false
        }
    }

    func bargeIn() {
        playback.interrupt()
        isSpeaking = false
        partialBuffer = ""
        onPartialText?("")
    }

    private func handleError(_ error: Error) {
        print("[VoiceSession] Error: \(error.localizedDescription)")
        isConnected = false
        isListening = false
        onConnectionChange?(false)
        onStatusMessage?("Error: \(error.localizedDescription)")
        scheduleReconnect()
    }

    private func handleDisconnect() {
        print("[VoiceSession] Disconnected.")
        isConnected = false
        isSpeaking = false
        onConnectionChange?(false)
        onStatusMessage?("Disconnected")
        scheduleReconnect()
    }

    // MARK: - Reconnection

    private func scheduleReconnect() {
        reconnectTask?.cancel()
        reconnectTask = Task { @MainActor in
            onStatusMessage?("Reconnecting in 3s...")
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }

            self.gemini = nil
            let wasListening = self.isListening
            let ok = await self.startSession()

            if ok && wasListening {
                self.beginCapture()
            }
        }
    }
}
