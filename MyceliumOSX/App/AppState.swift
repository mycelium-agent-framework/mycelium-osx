import Foundation
import SwiftUI

enum InteractionMode: String {
    case text    // Default: REST API, type messages
    case voice   // Explicit: WebSocket Live API, mic + audio playback
}

@MainActor
@Observable
final class AppState {
    // MARK: - Ring & Channel

    var ring0Path: URL?
    var mountedRingPath: URL?
    var mountedRingName: String?
    var soulContent: String = ""
    var manifest: Manifest?
    var channels: [Channel] = []
    var activeChannel: Channel?

    // MARK: - Conversation

    var transcript: [TranscriptEntry] = []
    var lastThinking: String = ""  // Most recent thinking block (shown in verbose mode)
    var showThinking = false       // Toggle for verbose/thinking view
    var partialText: String = ""
    var statusMessage: String = ""
    var isProcessing = false

    // MARK: - Mode

    var mode: InteractionMode = .text
    var isPanelVisible = false

    // MARK: - Device

    let deviceId = "osx-desktop"

    // MARK: - Voice (only used in voice mode)

    let voiceSession = VoiceSessionManager()

    var isListening: Bool { voiceSession.isListening }
    var isConnected: Bool { mode == .voice && voiceSession.isConnected }
    var isSpeaking: Bool { voiceSession.isSpeaking }

    // MARK: - Text (default mode)

    private var textClient: GeminiTextClient?
    private var currentApiKey: String?
    private var currentSystemInstruction: String = ""

    // MARK: - Managers

    var ringManager: RingManager?
    var sporeStore: SporeStore?
    var transcriptStore: TranscriptStore?

    // MARK: - Initialization

    var isConfigured: Bool {
        !(UserDefaults.standard.string(forKey: "ring0Path") ?? "").isEmpty
    }

    init() {
        setupVoiceCallbacks()
    }

    func reloadConfiguration() {
        let defaults = UserDefaults.standard

        guard let pathString = defaults.string(forKey: "ring0Path"),
              !pathString.isEmpty else { return }

        let expandedPath = NSString(string: pathString).expandingTildeInPath
        let ring0URL = URL(fileURLWithPath: expandedPath)
        bootstrap(ring0Path: ring0URL)

        // Mount first allowed ring using user-configured path
        if let manifest = manifest,
           let pop = manifest.pops.first(where: { $0.deviceId == deviceId }),
           let firstRingName = pop.allowedRings.first {
            let userPath = defaults.string(forKey: "ringPath.\(firstRingName)") ?? ""
            if !userPath.isEmpty, FileManager.default.fileExists(atPath: userPath) {
                mountRing(path: URL(fileURLWithPath: userPath), name: firstRingName)
            } else {
                statusMessage = "Set path for '\(firstRingName)' in Settings"
            }
        }
    }

    func bootstrap(ring0Path: URL) {
        self.ring0Path = ring0Path
        self.ringManager = RingManager(ring0Path: ring0Path)

        if let rm = ringManager {
            self.manifest = rm.loadManifest()
            self.soulContent = rm.loadSOUL() ?? ""
        }
    }

    // MARK: - Ring & Channel

    func mountRing(path: URL, name: String) {
        // End any active voice session (different ring = different backend)
        if mode == .voice {
            voiceSession.endSession()
            mode = .text
        }

        if let current = mountedRingPath {
            commitAndPersist(path: current, message: "Auto-commit before ring switch to \(name)")
        }

        mountedRingPath = path
        mountedRingName = name
        sporeStore = SporeStore(ringPath: path, deviceId: deviceId)
        transcriptStore = TranscriptStore(ringPath: path, deviceId: deviceId)

        channels = scanChannels(ringPath: path)
        if let generalChannel = channels.first(where: { $0.name == "general" }) ?? channels.first {
            switchChannel(to: generalChannel)
        }

        // Resolve API key and build system instruction for this ring
        configureBackendForCurrentRing()
        statusMessage = "Ring: \(name)"
    }

    /// Switch to a different ring by name. Reads path from UserDefaults.
    func switchToRing(named name: String) {
        guard name != mountedRingName else { return }
        let userPath = UserDefaults.standard.string(forKey: "ringPath.\(name)") ?? ""
        guard !userPath.isEmpty, FileManager.default.fileExists(atPath: userPath) else {
            statusMessage = "Path for '\(name)' not set. Open Settings."
            return
        }
        mountRing(path: URL(fileURLWithPath: userPath), name: name)
    }

    func switchChannel(to channel: Channel) {
        activeChannel = channel
        if let store = transcriptStore {
            transcript = store.loadRecentEntries(channel: channel.name, limit: 50)
        }
        // Clear text client history on channel switch
        Task { await textClient?.clearHistory() }
    }

    func createChannel(name: String) {
        guard let ringPath = mountedRingPath else { return }
        let channelDir = ringPath.appendingPathComponent("channels/\(name)")
        try? FileManager.default.createDirectory(at: channelDir, withIntermediateDirectories: true)
        let gitkeep = channelDir.appendingPathComponent(".gitkeep")
        FileManager.default.createFile(atPath: gitkeep.path, contents: nil)
        channels = scanChannels(ringPath: ringPath)
    }

    // MARK: - Backend Configuration

    private func configureBackendForCurrentRing() {
        guard let ringName = mountedRingName,
              let manifest = manifest,
              let ring = manifest.rings.first(where: { $0.name == ringName }),
              let backend = ring.backend
        else {
            statusMessage = "No backend config for ring"
            return
        }

        guard let apiKey = KeychainManager.get(ref: backend.apiKeyRef) else {
            statusMessage = "No API key for '\(backend.apiKeyRef)'. Open Settings."
            return
        }

        // Build system instruction
        var instruction = soulContent
        if let ringPath = mountedRingPath, let rm = ringManager {
            if let ringSoul = rm.loadSOUL(ringPath: ringPath) {
                instruction += "\n\n---\n\n" + ringSoul
            }
        }
        if let store = sporeStore {
            let handoffs = store.loadAll().filter { $0.type == .handoff }
            if let lastHandoff = handoffs.last, let recap = lastHandoff.contextRecap {
                instruction += "\n\n---\nPrevious session context:\n" + recap
            }
        }

        currentApiKey = apiKey
        currentSystemInstruction = instruction

        // Create text client (default mode)
        textClient = GeminiTextClient(apiKey: apiKey, systemInstruction: instruction)

        // Pre-configure voice session (used only when user switches to voice mode)
        voiceSession.configure(apiKey: apiKey, systemInstruction: instruction)

        print("[AppState] Backend configured for '\(ringName)' via '\(backend.apiKeyRef)'")
    }

    // MARK: - Text Input (default mode)

    func sendTextMessage(_ text: String) {
        guard textClient != nil else {
            statusMessage = "Not configured. Open Settings."
            return
        }

        // Add user entry to transcript
        let userEntry = TranscriptEntry(role: .user, text: text, originPop: deviceId)
        appendTranscriptEntry(userEntry)

        if mode == .voice {
            // In voice mode, send via WebSocket
            voiceSession.sendText(text)
        } else {
            // In text mode, send via REST
            isProcessing = true
            statusMessage = "Thinking..."

            Task {
                do {
                    let response = try await textClient!.send(text)

                    // Handle tool calls
                    for tc in response.toolCalls {
                        handleToolCall(callId: tc.id, name: tc.name, args: tc.args)
                    }

                    // Add model response to transcript
                    if !response.text.isEmpty {
                        let modelEntry = TranscriptEntry(
                            role: .model,
                            text: response.text.trimmingCharacters(in: .whitespacesAndNewlines),
                            originPop: deviceId
                        )
                        appendTranscriptEntry(modelEntry)
                    }

                    statusMessage = mountedRingName ?? ""
                } catch {
                    statusMessage = "Error: \(error.localizedDescription)"
                    print("[AppState] Text send error: \(error)")
                }
                isProcessing = false
            }
        }
    }

    // MARK: - Voice Mode

    func startVoiceMode() {
        guard currentApiKey != nil else {
            statusMessage = "No API key configured"
            return
        }
        mode = .voice
        voiceSession.startListening()
        statusMessage = "Voice mode"
    }

    func stopVoiceMode() {
        voiceSession.stopListening()
        voiceSession.endSession()
        mode = .text
        statusMessage = mountedRingName ?? ""
    }

    func toggleVoiceMode() {
        if mode == .voice {
            stopVoiceMode()
        } else {
            startVoiceMode()
        }
    }

    // MARK: - Session End

    func endSession() {
        if mode == .voice {
            voiceSession.endSession()
        }
        generateHandoffSpore()
        if let ringPath = mountedRingPath {
            commitAndPersist(path: ringPath, message: "Session ended")
        }
    }

    // MARK: - Voice Callbacks

    private func setupVoiceCallbacks() {
        voiceSession.onTranscriptEntry = { [weak self] entry in
            self?.appendTranscriptEntry(entry)
        }
        voiceSession.onPartialText = { [weak self] text in
            self?.partialText = text
        }
        voiceSession.onToolCall = { [weak self] callId, name, args in
            self?.handleToolCall(callId: callId, name: name, args: args)
        }
        voiceSession.onThinkingText = { [weak self] text in
            self?.lastThinking = text
        }
        voiceSession.onStatusMessage = { [weak self] message in
            self?.statusMessage = message
        }
    }

    private func appendTranscriptEntry(_ entry: TranscriptEntry) {
        transcript.append(entry)
        if let store = transcriptStore, let channel = activeChannel {
            store.append(entry: entry, channel: channel.name)
        }
    }

    // MARK: - Tool Call Handling

    private func handleToolCall(callId: String, name: String, args: [String: Any]) {
        switch name {
        case "remember_this":
            guard let content = args["content"] as? String,
                  let typeStr = args["spore_type"] as? String,
                  let sporeType = SporeType(rawValue: typeStr)
            else { return }

            let spore = Spore(
                type: sporeType,
                channel: activeChannel?.name ?? "general",
                content: content,
                originPop: deviceId
            )
            sporeStore?.append(spore: spore)

            if mode == .voice {
                voiceSession.sendToolResponse(callId: callId, result: [
                    "status": "saved", "spore_id": spore.id, "type": typeStr
                ])
            }
        default:
            print("[AppState] Unknown tool: \(name)")
        }
    }

    // MARK: - Handoff

    private func generateHandoffSpore() {
        guard let store = sporeStore, !transcript.isEmpty else { return }
        let recap = String(transcript.suffix(10).map(\.text).joined(separator: " ").prefix(500))
        let spore = Spore(
            type: .handoff, status: .done,
            channel: activeChannel?.name ?? "general",
            content: "Session ended on macOS.",
            contextRecap: recap, originPop: deviceId
        )
        store.append(spore: spore)
    }

    // MARK: - Helpers

    private func scanChannels(ringPath: URL) -> [Channel] {
        let channelsDir = ringPath.appendingPathComponent("channels")
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: channelsDir, includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        ) else { return [] }

        return contents.compactMap { url in
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir),
                  isDir.boolValue else { return nil }
            return Channel(name: url.lastPathComponent, ringPath: ringPath)
        }.sorted { $0.name < $1.name }
    }

    private func commitAndPersist(path: URL, message: String) {
        Task.detached {
            let add = Process()
            add.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            add.arguments = ["-C", path.path, "add", "-A"]
            try? add.run(); add.waitUntilExit()

            let commit = Process()
            commit.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            commit.arguments = ["-C", path.path, "commit", "-m", message]
            try? commit.run(); commit.waitUntilExit()
        }
    }
}
