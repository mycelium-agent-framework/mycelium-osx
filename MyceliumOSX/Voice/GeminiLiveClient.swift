import Foundation

/// Gemini Live API WebSocket client for real-time voice conversation.
///
/// Protocol:
/// - Connect to wss://generativelanguage.googleapis.com/ws/...
/// - Send `setup` message with system instruction and tools
/// - Send `realtimeInput` with base64 PCM audio chunks
/// - Receive `serverContent` with text parts and audio responses
/// - Handle `toolCall` for function calling
@Observable
final class GeminiLiveClient: @unchecked Sendable {
    private var webSocket: URLSessionWebSocketTask?
    private var session: URLSession?

    var isConnected = false
    var onTextReceived: ((String, Bool) -> Void)?  // (text, isFinal)
    var onAudioReceived: ((Data) -> Void)?          // PCM audio data
    var onToolCall: ((String, String, [String: Any]) -> Void)?  // (callId, functionName, args)
    var onError: ((Error) -> Void)?
    var onDisconnect: (() -> Void)?

    private let apiKey: String
    private let model: String

    init(apiKey: String, model: String = "gemini-2.5-flash-native-audio-latest") {
        self.apiKey = apiKey
        self.model = model
    }

    // MARK: - Connection

    func connect(systemInstruction: String) {
        let urlString = "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent?key=\(apiKey)"

        guard let url = URL(string: urlString) else {
            print("[GeminiLive] Invalid URL")
            return
        }

        session = URLSession(configuration: .default)
        webSocket = session?.webSocketTask(with: url)
        webSocket?.resume()

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
                    ]
                ],
                "systemInstruction": [
                    "parts": [
                        ["text": systemInstruction]
                    ]
                ],
                "tools": buildToolDeclarations()
            ]
        ]

        send(json: setup)
        isConnected = true
        receiveLoop()
    }

    func disconnect() {
        webSocket?.cancel(with: .normalClosure, reason: nil)
        webSocket = nil
        isConnected = false
        onDisconnect?()
    }

    // MARK: - Send Audio

    /// Send a chunk of PCM audio (16-bit LE, 16kHz mono).
    func sendAudio(pcmData: Data) {
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

    /// Send a text message (for text-only interaction or testing).
    func sendText(_ text: String) {
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

    /// Send a tool response back to Gemini.
    func sendToolResponse(callId: String, result: [String: Any]) {
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
                // Continue receiving
                self.receiveLoop()

            case .failure(let error):
                print("[GeminiLive] WebSocket error: \(error)")
                self.isConnected = false
                self.onError?(error)
            }
        }
    }

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }

        // Handle server content (text + audio responses)
        if let serverContent = json["serverContent"] as? [String: Any] {
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

        // Handle setup complete
        if json["setupComplete"] != nil {
            print("[GeminiLive] Setup complete, ready for conversation.")
        }
    }

    private func handleServerContent(_ content: [String: Any]) {
        guard let modelTurn = content["modelTurn"] as? [String: Any],
              let parts = modelTurn["parts"] as? [[String: Any]]
        else { return }

        let turnComplete = content["turnComplete"] as? Bool ?? false

        for part in parts {
            // Text part
            if let text = part["text"] as? String {
                onTextReceived?(text, turnComplete)
            }

            // Audio part
            if let inlineData = part["inlineData"] as? [String: Any],
               let b64 = inlineData["data"] as? String,
               let audioData = Data(base64Encoded: b64) {
                onAudioReceived?(audioData)
            }
        }
    }

    // MARK: - Tool Declarations

    private func buildToolDeclarations() -> [[String: Any]] {
        // Phase 4 prep: tool declarations for Google Drive access
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
