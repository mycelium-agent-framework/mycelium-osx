import Foundation

// MARK: - Audio Capture

protocol AudioCapturing: AnyObject {
    var audioLevel: Float { get }
    var onAudioChunk: ((Data) -> Void)? { get set }
    func requestPermission() async -> Bool
    func startCapture() throws
    func stopCapture()
}

// MARK: - Audio Playback

protocol AudioPlaying: AnyObject {
    func start() throws
    func stop()
    func enqueue(pcmData: Data)
    func interrupt()
}

// MARK: - Keychain

protocol KeychainStoring {
    static func save(key: String, forRef ref: String) -> Bool
    static func get(ref: String) -> String?
    static func delete(ref: String) -> Bool
    static func listRefs() -> [String]
    static func preloadAll()
}

// MARK: - File System

protocol FileSystemAccessing {
    func fileExists(atPath path: String) -> Bool
    func contentsOfDirectory(at url: URL) throws -> [URL]
    func createDirectory(at url: URL) throws
    func read(at url: URL) -> Data?
    func write(data: Data, to url: URL) throws
    func readString(at url: URL) -> String?
}

// MARK: - Git Operations

protocol GitOperating {
    func add(path: URL) async -> Bool
    func commit(path: URL, message: String) async -> Bool
    func pull(path: URL) async -> Bool
    func push(path: URL) async -> Bool
}

// MARK: - Gemini Live Connection

protocol GeminiLiveConnecting: AnyObject {
    var isConnected: Bool { get }
    var isSetupComplete: Bool { get }
    var onTextReceived: ((String, Bool) -> Void)? { get set }
    var onThinkingReceived: ((String, Bool) -> Void)? { get set }
    var onUserTranscript: ((String) -> Void)? { get set }
    var onOutputTranscript: ((String) -> Void)? { get set }
    var onAudioReceived: ((Data) -> Void)? { get set }
    var onToolCall: ((String, String, [String: Any]) -> Void)? { get set }
    var onError: ((Error) -> Void)? { get set }
    var onDisconnect: (() -> Void)? { get set }

    func connect(systemInstruction: String) async -> Bool
    func disconnect()
    func sendAudio(pcmData: Data)
    func sendText(_ text: String)
    func sendToolResponse(callId: String, result: [String: Any])
}

// MARK: - Gemini Text

protocol GeminiTextSending: Actor {
    func send(_ text: String) async throws -> GeminiTextResponse
    func clearHistory() async
}

struct GeminiTextResponse: Sendable {
    let text: String
    let toolCalls: [(id: String, name: String, args: [String: Any])]

    // Sendable-safe init with no closures
    init(text: String, toolCalls: [(id: String, name: String, args: [String: Any])] = []) {
        self.text = text
        self.toolCalls = toolCalls
    }
}

// MARK: - Hotkey

protocol HotkeyListening: AnyObject {
    func start()
    func stop()
}
