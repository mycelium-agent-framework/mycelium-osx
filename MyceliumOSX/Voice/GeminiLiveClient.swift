import Foundation

/// Gemini Live API WebSocket client for real-time voice conversation.
///
/// Protocol:
/// - Connect to wss://generativelanguage.googleapis.com/ws/...
/// - Send `setup` message with system instruction and tools
/// - Wait for `setupComplete` before sending any content
/// - Send `realtimeInput` with base64 PCM audio chunks
/// - Receive `serverContent` with text parts and audio responses
@Observable
final class GeminiLiveClient: @unchecked Sendable {
    private var webSocket: URLSessionWebSocketTask?
    private var session: URLSession?
    private var setupContinuation: CheckedContinuation<Bool, Never>?

    private(set) var isConnected = false
    private(set) var isSetupComplete = false

    var onTextReceived: ((String, Bool) -> Void)?      // (text, isFinal)
    var onThinkingReceived: ((String, Bool) -> Void)?  // (text, isFinal) — thinking blocks
    var onUserTranscript: ((String) -> Void)?           // What Gemini heard the user say
    var onAudioReceived: ((Data) -> Void)?              // PCM audio data
    var onToolCall: ((String, String, [String: Any]) -> Void)?
    var onError: ((Error) -> Void)?
    var onDisconnect: (() -> Void)?

    private let apiKey: String
    private let model: String

    init(apiKey: String, model: String = "gemini-2.5-flash-native-audio-latest") {
        self.apiKey = apiKey
        self.model = model
    }

    // MARK: - Connection

    /// Connect and wait for setupComplete. Returns true if setup succeeded.
    func connect(systemInstruction: String) async -> Bool {
        let urlString = "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent?key=\(apiKey)"

        guard let url = URL(string: urlString) else {
            print("[GeminiLive] Invalid URL")
            return false
        }

        print("[GeminiLive] Connecting to \(model)...")

        session = URLSession(configuration: .default)
        webSocket = session?.webSocketTask(with: url)
        webSocket?.resume()

        // Start receive loop before sending setup (to catch setupComplete)
        receiveLoop()

        // Send setup message
        let setup: [String: Any] = [
            "setup": [
                "model": "models/\(model)",
                "generationConfig": [
                    "responseModalities": ["AUDIO"],
                    "speechConfig": [
                        "voiceConfig": [
                            "prebuiltVoiceConfig": [
                                "voiceName": "Aoede"
                            ]
                        ]
                    ],
                    "thinkingConfig": [
                        "includeThoughts": true
                    ]
                ],
                "systemInstruction": [
                    "parts": [
                        ["text": systemInstruction]
                    ]
                ],
                "outputAudioTranscription": [:] as [String: Any],
                "inputAudioTranscription": [:] as [String: Any],
                "tools": buildToolDeclarations()
            ]
        ]

        send(json: setup)

        // Wait for setupComplete (with timeout)
        let setupOk = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            self.setupContinuation = continuation

            // Timeout after 10 seconds
            DispatchQueue.global().asyncAfter(deadline: .now() + 10) { [weak self] in
                self?.setupContinuation?.resume(returning: false)
                self?.setupContinuation = nil
            }
        }

        if setupOk {
            isConnected = true
            isSetupComplete = true
            print("[GeminiLive] Connected and setup complete.")
        } else {
            print("[GeminiLive] Setup timed out or failed.")
            disconnect()
        }

        return setupOk
    }

    func disconnect() {
        webSocket?.cancel(with: .normalClosure, reason: nil)
        webSocket = nil
        isConnected = false
        isSetupComplete = false
        onDisconnect?()
    }

    // MARK: - Send Audio

    func sendAudio(pcmData: Data) {
        guard isSetupComplete else { return }
        let base64 = pcmData.base64EncodedString()
        let message: [String: Any] = [
            "realtimeInput": [
                "mediaChunks": [
                    [
                        "mimeType": "audio/pcm;rate=16000",
                        "data": base64
                    ]
                ]
            ]
        ]
        send(json: message)
    }

    func sendText(_ text: String) {
        guard isSetupComplete else {
            print("[GeminiLive] Cannot send text — setup not complete")
            return
        }
        let message: [String: Any] = [
            "clientContent": [
                "turns": [
                    [
                        "role": "user",
                        "parts": [["text": text]]
                    ]
                ],
                "turnComplete": true
            ]
        ]
        send(json: message)
    }

    func sendToolResponse(callId: String, result: [String: Any]) {
        guard isSetupComplete else { return }
        let message: [String: Any] = [
            "toolResponse": [
                "functionResponses": [
                    [
                        "id": callId,
                        "name": callId,
                        "response": result
                    ]
                ]
            ]
        ]
        send(json: message)
    }

    // MARK: - Receive Loop

    private func receiveLoop() {
        webSocket?.receive { [weak self] result in
            guard let self else { return }

            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self.handleMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.handleMessage(text)
                    }
                @unknown default:
                    break
                }
                self.receiveLoop()

            case .failure(let error):
                print("[GeminiLive] WebSocket error: \(error)")
                self.isConnected = false
                self.isSetupComplete = false
                self.onError?(error)
            }
        }
    }

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }

        // Handle setup complete
        if json["setupComplete"] != nil {
            print("[GeminiLive] Received setupComplete")
            setupContinuation?.resume(returning: true)
            setupContinuation = nil
            return
        }

        // Handle server content
        if let serverContent = json["serverContent"] as? [String: Any] {
            // Log keys for debugging
            let keys = serverContent.keys.sorted().joined(separator: ", ")
            let hasText = (serverContent["modelTurn"] as? [String: Any])?["parts"] != nil
            if hasText || serverContent["turnComplete"] != nil || serverContent["inputTranscript"] != nil {
                print("[GeminiLive] serverContent keys: [\(keys)]")
            }
            handleServerContent(serverContent)
        }

        // Handle tool calls
        if let toolCall = json["toolCall"] as? [String: Any],
           let functionCalls = toolCall["functionCalls"] as? [[String: Any]] {
            for call in functionCalls {
                if let callId = call["id"] as? String,
                   let name = call["name"] as? String,
                   let args = call["args"] as? [String: Any] {
                    onToolCall?(callId, name, args)
                }
            }
        }
    }

    private func handleServerContent(_ content: [String: Any]) {
        let turnComplete = content["turnComplete"] as? Bool ?? false

        // Process model turn parts (audio + thinking text)
        if let modelTurn = content["modelTurn"] as? [String: Any],
           let parts = modelTurn["parts"] as? [[String: Any]] {
            for part in parts {
                let isThought = part["thought"] as? Bool ?? false

                if let text = part["text"] as? String {
                    if isThought {
                        onThinkingReceived?(text, false)
                    }
                    // Non-thought text in AUDIO mode is typically thinking too,
                    // so we rely on outputTranscription for the actual spoken text
                }

                if let inlineData = part["inlineData"] as? [String: Any],
                   let b64 = inlineData["data"] as? String,
                   let audioData = Data(base64Encoded: b64) {
                    onAudioReceived?(audioData)
                }
            }
        }

        // Output transcription: what Vivian actually said (spoken words, not thinking)
        if let outputTranscription = content["outputTranscription"] as? [String: Any],
           let text = outputTranscription["text"] as? String, !text.isEmpty {
            print("[GeminiLive] Vivian said: \(text)")
            onTextReceived?(text, false)
        }

        // Input transcription: what Gemini heard the user say
        if let inputTranscription = content["inputTranscription"] as? [String: Any],
           let text = inputTranscription["text"] as? String, !text.isEmpty {
            print("[GeminiLive] User said: \(text)")
            onUserTranscript?(text)
        }

        // Legacy field name check
        if let inputTranscript = content["inputTranscript"] as? String, !inputTranscript.isEmpty {
            print("[GeminiLive] User said (legacy): \(inputTranscript)")
            onUserTranscript?(inputTranscript)
        }

        // Finalize thinking on turn complete
        if turnComplete {
            onThinkingReceived?("", true)
            onTextReceived?("", true)
        }
    }

    // MARK: - Tool Declarations

    private func buildToolDeclarations() -> [[String: Any]] {
        return [
            [
                "functionDeclarations": [
                    [
                        "name": "remember_this",
                        "description": "Store a decision, discovery, or important fact as a persistent spore in memory.",
                        "parameters": [
                            "type": "object",
                            "properties": [
                                "content": [
                                    "type": "string",
                                    "description": "What to remember"
                                ],
                                "spore_type": [
                                    "type": "string",
                                    "enum": ["decision", "discovery", "note", "task"],
                                    "description": "Classification of the memory"
                                ]
                            ],
                            "required": ["content", "spore_type"]
                        ]
                    ]
                ]
            ]
        ]
    }

    // MARK: - Helpers

    private func send(json: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: json),
              let string = String(data: data, encoding: .utf8)
        else { return }

        webSocket?.send(.string(string)) { error in
            if let error {
                print("[GeminiLive] Send error: \(error)")
            }
        }
    }
}
