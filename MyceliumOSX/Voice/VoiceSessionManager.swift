import Foundation

/// Orchestrates the full voice pipeline:
///   mic → GeminiLive → playback → transcript persistence
///
/// Owns the GeminiLiveClient, AudioCaptureManager, and AudioPlaybackManager.
/// AppState drives it via startSession / endSession / toggleListening.
@MainActor
@Observable
final class VoiceSessionManager {
    private var gemini: GeminiLiveClient?
    private let capture = AudioCaptureManager()
    private let playback = AudioPlaybackManager()

    private(set) var isConnected = false
    private(set) var isListening = false
    private(set) var isSpeaking = false

    // Accumulated partial text from the current model turn
    private var partialBuffer = ""

    // Callbacks to AppState
    var onTranscriptEntry: ((TranscriptEntry) -> Void)?
    var onPartialText: ((String) -> Void)?
    var onToolCall: ((String, String, [String: Any]) -> Void)?
    var onConnectionChange: ((Bool) -> Void)?

    private var apiKey: String = ""
    private var systemInstruction: String = ""
    private var reconnectTask: Task<Void, Never>?

    // MARK: - Session Lifecycle

    func configure(apiKey: String, systemInstruction: String) {
        self.apiKey = apiKey
        self.systemInstruction = systemInstruction
    }

    func startSession() {
        guard !apiKey.isEmpty else {
            print("[VoiceSession] No API key configured. Open Settings to add one.")
            return
        }
        guard gemini == nil else { return }

        let client = GeminiLiveClient(apiKey: apiKey)
        self.gemini = client

        // Wire callbacks (GeminiLiveClient callbacks fire on background threads)
        client.onTextReceived = { [weak self] text, isFinal in
            Task { @MainActor [weak self] in
                self?.handleText(text, isFinal: isFinal)
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

        client.connect(systemInstruction: systemInstruction)
        isConnected = true
        onConnectionChange?(true)
        print("[VoiceSession] Session started.")
    }

    func endSession() {
        reconnectTask?.cancel()
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
        guard isConnected else {
            // Auto-start session if not connected
            startSession()
            // Wait a beat for connection, then start capture
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                self.beginCapture()
            }
            return
        }
        beginCapture()
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
        capture.onAudioChunk = { [weak self] data in
            self?.gemini?.sendAudio(pcmData: data)
        }

        do {
            try capture.startCapture()
            isListening = true
        } catch {
            print("[VoiceSession] Failed to start capture: \(error)")
        }
    }

    // MARK: - Text Input

    func sendText(_ text: String) {
        guard isConnected else {
            startSession()
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                self.gemini?.sendText(text)
            }
            return
        }
        gemini?.sendText(text)
    }

    // MARK: - Tool Responses

    func sendToolResponse(callId: String, result: [String: Any]) {
        gemini?.sendToolResponse(callId: callId, result: result)
    }

    // MARK: - Handlers

    private func handleText(_ text: String, isFinal: Bool) {
        if isFinal {
            // Turn complete — emit the full accumulated text as a transcript entry
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
            // Partial — accumulate and show
            partialBuffer += text
            onPartialText?(partialBuffer)
        }
    }

    private func handleAudio(_ data: Data) {
        isSpeaking = true
        playback.enqueue(pcmData: data)

        // Auto-detect when speaking stops (no audio for 300ms)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            // If no new audio arrived, we've stopped speaking
            // (This is approximate — a proper implementation would track the player node)
            self.isSpeaking = false
        }
    }

    /// Interrupt playback (barge-in — user started speaking while model was talking).
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
        scheduleReconnect()
    }

    private func handleDisconnect() {
        print("[VoiceSession] Disconnected.")
        isConnected = false
        isSpeaking = false
        onConnectionChange?(false)
        scheduleReconnect()
    }

    // MARK: - Reconnection

    private func scheduleReconnect() {
        reconnectTask?.cancel()
        reconnectTask = Task { @MainActor in
            print("[VoiceSession] Reconnecting in 3 seconds...")
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }

            self.gemini = nil
            self.startSession()

            // Resume listening if we were listening before
            if self.isListening {
                self.beginCapture()
            }
        }
    }
}
