import Foundation
import SwiftUI

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
    var partialText: String = ""

    // MARK: - Panel

    var isPanelVisible = false

    // MARK: - Device

    let deviceId = "osx-desktop"

    // MARK: - Voice

    let voiceSession = VoiceSessionManager()

    var isListening: Bool {
        get { voiceSession.isListening }
        set {
            if newValue { voiceSession.startListening() }
            else { voiceSession.stopListening() }
        }
    }

    var isConnected: Bool { voiceSession.isConnected }
    var isSpeaking: Bool { voiceSession.isSpeaking }

    // MARK: - Managers

    var ringManager: RingManager?
    var sporeStore: SporeStore?
    var transcriptStore: TranscriptStore?

    // MARK: - Initialization

    /// Whether we have a valid configuration (ring0 path set).
    var isConfigured: Bool {
        let hasPath = !(UserDefaults.standard.string(forKey: "ring0Path") ?? "").isEmpty
        return hasPath
    }

    init() {
        setupVoiceCallbacks()
    }

    /// Reload everything from UserDefaults (called after Settings save).
    func reloadConfiguration() {
        let defaults = UserDefaults.standard

        // Load Ring 0
        guard let pathString = defaults.string(forKey: "ring0Path"),
              !pathString.isEmpty else { return }

        let expandedPath = NSString(string: pathString).expandingTildeInPath
        let ring0URL = URL(fileURLWithPath: expandedPath)
        bootstrap(ring0Path: ring0URL)

        // Auto-mount first allowed ring
        if let manifest = manifest,
           let pop = manifest.pops.first(where: { $0.deviceId == deviceId }),
           let firstRingName = pop.allowedRings.first,
           let ring = manifest.rings.first(where: { $0.name == firstRingName }),
           let hint = ring.localPathHint {
            let ringPath = URL(fileURLWithPath: NSString(string: hint).expandingTildeInPath)
            if FileManager.default.fileExists(atPath: ringPath.path) {
                mountRing(path: ringPath, name: firstRingName)
            }
        }

        // Configure voice from the mounted ring's backend config
        configureVoiceForCurrentRing()
    }

    func bootstrap(ring0Path: URL) {
        self.ring0Path = ring0Path
        self.ringManager = RingManager(ring0Path: ring0Path)

        if let rm = ringManager {
            self.manifest = rm.loadManifest()
            self.soulContent = rm.loadSOUL() ?? ""
        }
    }

    /// Resolve the API key for the currently mounted ring from Keychain
    /// and configure the voice session.
    func configureVoiceForCurrentRing() {
        guard let ringName = mountedRingName,
              let manifest = manifest,
              let ring = manifest.rings.first(where: { $0.name == ringName }),
              let backend = ring.backend
        else {
            print("[AppState] No backend config for mounted ring.")
            return
        }

        guard let apiKey = KeychainManager.get(ref: backend.apiKeyRef) else {
            print("[AppState] No API key in Keychain for ref '\(backend.apiKeyRef)'. Open Settings to add one.")
            return
        }

        // Build system instruction from SOUL.md + ring SOUL.md + recent context
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

        voiceSession.configure(apiKey: apiKey, systemInstruction: instruction)
        print("[AppState] Voice configured for ring '\(ringName)' via backend '\(backend.apiKeyRef)' (\(backend.provider)/\(backend.model))")
    }

    // MARK: - Ring & Channel

    func mountRing(path: URL, name: String) {
        // End current voice session (different ring = different backend)
        if mountedRingName != nil {
            voiceSession.endSession()
        }

        if let current = mountedRingPath {
            commitAndPersist(path: current, message: "Auto-commit before ring switch to \(name)")
        }

        mountedRingPath = path
        mountedRingName = name
        sporeStore = SporeStore(ringPath: path, deviceId: deviceId)
        transcriptStore = TranscriptStore(ringPath: path, deviceId: deviceId)

        channels = scanChannels(ringPath: path)
        if let defaultChannel = channels.first(where: { $0.name == "default" }) ?? channels.first {
            switchChannel(to: defaultChannel)
        }

        // Configure voice for the new ring's backend
        configureVoiceForCurrentRing()
    }

    func switchChannel(to channel: Channel) {
        activeChannel = channel
        if let store = transcriptStore {
            transcript = store.loadRecentEntries(channel: channel.name, limit: 50)
        }
    }

    func createChannel(name: String) {
        guard let ringPath = mountedRingPath else { return }
        let channelDir = ringPath.appendingPathComponent("channels/\(name)")
        try? FileManager.default.createDirectory(at: channelDir, withIntermediateDirectories: true)
        let gitkeep = channelDir.appendingPathComponent(".gitkeep")
        FileManager.default.createFile(atPath: gitkeep.path, contents: nil)
        channels = scanChannels(ringPath: ringPath)
    }

    // MARK: - Text Input

    func sendTextMessage(_ text: String) {
        let entry = TranscriptEntry(
            role: .user,
            text: text,
            originPop: deviceId
        )
        appendTranscriptEntry(entry)
        voiceSession.sendText(text)
    }

    // MARK: - Session End

    func endVoiceSession() {
        voiceSession.endSession()
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
            handleRememberThis(callId: callId, args: args)
        default:
            print("[AppState] Unknown tool call: \(name)")
            voiceSession.sendToolResponse(callId: callId, result: ["error": "Unknown tool"])
        }
    }

    private func handleRememberThis(callId: String, args: [String: Any]) {
        guard let content = args["content"] as? String,
              let typeStr = args["spore_type"] as? String,
              let sporeType = SporeType(rawValue: typeStr)
        else {
            voiceSession.sendToolResponse(callId: callId, result: ["error": "Invalid arguments"])
            return
        }

        let spore = Spore(
            type: sporeType,
            channel: activeChannel?.name ?? "default",
            content: content,
            originPop: deviceId
        )
        sporeStore?.append(spore: spore)

        voiceSession.sendToolResponse(callId: callId, result: [
            "status": "saved",
            "spore_id": spore.id,
            "type": typeStr,
        ])

        print("[AppState] Saved spore via tool call: \(sporeType.rawValue) — \(content.prefix(60))")
    }

    // MARK: - Handoff

    private func generateHandoffSpore() {
        guard let store = sporeStore, !transcript.isEmpty else { return }

        let recentTopics = transcript.suffix(10).map(\.text).joined(separator: " ")
        let recap = String(recentTopics.prefix(500))

        let spore = Spore(
            type: .handoff,
            status: .done,
            channel: activeChannel?.name ?? "default",
            content: "Session ended on macOS.",
            contextRecap: recap,
            originPop: deviceId
        )
        store.append(spore: spore)
    }

    // MARK: - Helpers

    private func scanChannels(ringPath: URL) -> [Channel] {
        let channelsDir = ringPath.appendingPathComponent("channels")
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: channelsDir,
            includingPropertiesForKeys: [.isDirectoryKey],
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
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["-C", path.path, "add", "-A"]
            try? process.run()
            process.waitUntilExit()

            let commitProcess = Process()
            commitProcess.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            commitProcess.arguments = ["-C", path.path, "commit", "-m", message]
            try? commitProcess.run()
            commitProcess.waitUntilExit()
        }
    }
}
