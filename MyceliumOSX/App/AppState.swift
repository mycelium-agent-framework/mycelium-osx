import Foundation
import SwiftUI

enum InteractionMode: String {
    case text
    case voice
}

/// Dependencies that AppState needs, injectable for testing.
struct AppDependencies {
    var loadManifest: (URL) -> Manifest?
    var loadSOUL: (URL) -> String?
    var keychainGet: (String) -> String?
    var fileExists: (String) -> Bool
    var scanChannels: (URL) -> [Channel]
    var makeSporeStore: (URL, String) -> SporeStore
    var makeTranscriptStore: (URL, String) -> TranscriptStore
    var makeTextClient: (String, String) -> GeminiTextClient
    var commitAndPersist: (URL, String) -> Void

    static let live = AppDependencies(
        loadManifest: { url in
            let rm = RingManager(ring0Path: url)
            return rm.loadManifest()
        },
        loadSOUL: { url in
            try? String(contentsOf: url.appendingPathComponent("SOUL.md"), encoding: .utf8)
        },
        keychainGet: { KeychainManager.get(ref: $0) },
        fileExists: { FileManager.default.fileExists(atPath: $0) },
        scanChannels: { ringPath in
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
        },
        makeSporeStore: { SporeStore(ringPath: $0, deviceId: $1) },
        makeTranscriptStore: { TranscriptStore(ringPath: $0, deviceId: $1) },
        makeTextClient: { GeminiTextClient(apiKey: $0, systemInstruction: $1) },
        commitAndPersist: { path, message in
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
    )
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
    var lastThinking: String = ""
    var showThinking = false
    var partialText: String = ""
    var statusMessage: String = ""
    var isProcessing = false

    // MARK: - Mode

    var mode: InteractionMode = .text
    var isPanelVisible = false

    // MARK: - Device

    let deviceId = "osx-desktop"

    // MARK: - Voice

    let voiceSession: VoiceSessionManager  // Gemini Live (cloud)
    var localVoiceSession: LocalVoiceSession?  // Ollama + STT + TTS (local)

    var isRecording: Bool {
        if useLocalModel { return localVoiceSession?.isRecording ?? false }
        return voiceSession.isRecording
    }
    var isConnected: Bool { mode == .voice }
    var isSpeaking: Bool {
        if useLocalModel { return localVoiceSession?.isSpeaking ?? false }
        return voiceSession.isSpeaking
    }

    // MARK: - Text / Local LLM

    private var textClient: GeminiTextClient?
    private var ollamaClient: OllamaClient?
    private var ollamaHistory: [OllamaClient.Message] = []
    let localTTS = LocalTTS()
    private(set) var currentApiKey: String?
    private(set) var currentSystemInstruction: String = ""
    /// True when Ollama is available and should be used as primary.
    private(set) var useLocalModel = false

    // MARK: - Stores

    var sporeStore: SporeStore?
    var transcriptStore: TranscriptStore?

    // MARK: - Dependencies

    let deps: AppDependencies

    // MARK: - Initialization

    var isConfigured: Bool {
        !(UserDefaults.standard.string(forKey: "ring0Path") ?? "").isEmpty
    }

    init(deps: AppDependencies = .live, voiceSession: VoiceSessionManager? = nil) {
        self.deps = deps
        self.voiceSession = voiceSession ?? VoiceSessionManager()
        setupVoiceCallbacks()
    }

    func reloadConfiguration() {
        let defaults = UserDefaults.standard

        guard let pathString = defaults.string(forKey: "ring0Path"),
              !pathString.isEmpty else { return }

        let expandedPath = NSString(string: pathString).expandingTildeInPath
        let ring0URL = URL(fileURLWithPath: expandedPath)
        bootstrap(ring0Path: ring0URL)

        if let manifest = manifest,
           let pop = manifest.pops.first(where: { $0.deviceId == deviceId }),
           let firstRingName = pop.allowedRings.first {
            let userPath = defaults.string(forKey: "ringPath.\(firstRingName)") ?? ""
            if !userPath.isEmpty, deps.fileExists(userPath) {
                mountRing(path: URL(fileURLWithPath: userPath), name: firstRingName)
            } else {
                statusMessage = "Set path for '\(firstRingName)' in Settings"
            }
        }
    }

    func bootstrap(ring0Path: URL) {
        self.ring0Path = ring0Path
        self.manifest = deps.loadManifest(ring0Path)
        self.soulContent = deps.loadSOUL(ring0Path) ?? ""
    }

    // MARK: - Ring & Channel

    func mountRing(path: URL, name: String) {
        if mode == .voice {
            voiceSession.endSession()
            mode = .text
        }

        if let current = mountedRingPath {
            deps.commitAndPersist(current, "Auto-commit before ring switch to \(name)")
        }

        mountedRingPath = path
        mountedRingName = name
        sporeStore = deps.makeSporeStore(path, deviceId)
        transcriptStore = deps.makeTranscriptStore(path, deviceId)

        channels = deps.scanChannels(path)
        if let generalChannel = channels.first(where: { $0.name == "general" }) ?? channels.first {
            switchChannel(to: generalChannel)
        }

        configureBackendForCurrentRing()
        // Only set success status if backend config didn't set an error
        if currentApiKey != nil {
            statusMessage = "Ring: \(name)"
        }
    }

    func switchToRing(named name: String) {
        guard name != mountedRingName else { return }
        let userPath = UserDefaults.standard.string(forKey: "ringPath.\(name)") ?? ""
        guard !userPath.isEmpty, deps.fileExists(userPath) else {
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
        Task { await textClient?.clearHistory() }
    }

    func createChannel(name: String) {
        guard let ringPath = mountedRingPath else { return }
        let channelDir = ringPath.appendingPathComponent("channels/\(name)")
        try? FileManager.default.createDirectory(at: channelDir, withIntermediateDirectories: true)
        let gitkeep = channelDir.appendingPathComponent(".gitkeep")
        FileManager.default.createFile(atPath: gitkeep.path, contents: nil)
        channels = deps.scanChannels(ringPath)
    }

    // MARK: - Backend Configuration

    func configureBackendForCurrentRing() {
        guard let ringName = mountedRingName,
              let manifest = manifest,
              let ring = manifest.rings.first(where: { $0.name == ringName }),
              let backend = ring.backend
        else {
            statusMessage = "No backend config for ring"
            return
        }

        guard let apiKey = deps.keychainGet(backend.apiKeyRef) else {
            statusMessage = "No API key for '\(backend.apiKeyRef)'. Open Settings."
            return
        }

        var instruction = soulContent
        if let ringPath = mountedRingPath {
            if let ringSoul = deps.loadSOUL(ringPath) {
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

        textClient = deps.makeTextClient(apiKey, instruction)
        voiceSession.configure(apiKey: apiKey, systemInstruction: instruction)

        // Check if Ollama is available for local-first mode
        checkOllamaAvailability(systemInstruction: instruction)
    }

    private func checkOllamaAvailability(systemInstruction: String) {
        let client = OllamaClient(model: "gemma3:4b", systemInstruction: systemInstruction)
        ollamaClient = client
        statusMessage = "Checking local model..."
        print("[AppState] Checking Ollama availability...")

        Task {
            let available = await client.isAvailable()
            self.useLocalModel = available
            print("[AppState] Ollama check result: available=\(available), useLocalModel=\(self.useLocalModel)")

            if available {
                // Warmup: first Ollama call loads the model into memory
                statusMessage = "Loading local model..."
                isProcessing = true
                let start = Date()
                do {
                    let _ = try await client.send(prompt: "Ready.", history: [])
                    let elapsed = String(format: "%.1f", Date().timeIntervalSince(start))
                    print("[AppState] Ollama warmup in \(elapsed)s")
                } catch {
                    print("[AppState] Ollama warmup failed: \(error)")
                }
                isProcessing = false
                statusMessage = "Ready (local: gemma3:4b)"
            } else if let ring = mountedRingName {
                statusMessage = "Ring: \(ring) (cloud)"
                print("[AppState] Ollama not available — falling back to Gemini")
            }
        }
    }

    // MARK: - Text Input

    func sendTextMessage(_ text: String) {
        let userEntry = TranscriptEntry(role: .user, text: text, originPop: deviceId)
        appendTranscriptEntry(userEntry)

        if mode == .voice {
            voiceSession.sendText(text)
            return
        }

        isProcessing = true
        let startTime = Date()
        print("[AppState] sendTextMessage: useLocalModel=\(useLocalModel), ollamaClient=\(ollamaClient != nil), textClient=\(textClient != nil)")

        if useLocalModel, let ollama = ollamaClient {
            // Local-first: use Ollama
            statusMessage = "Local..."
            print("[AppState] Sending to Ollama: \(text.prefix(50))")

            Task {
                do {
                    let response = try await ollama.send(prompt: text, history: ollamaHistory)
                    let elapsed = String(format: "%.1f", Date().timeIntervalSince(startTime))
                    print("[AppState] Ollama response in \(elapsed)s: \(response.prefix(80))")

                    OllamaClient.appendToHistory(&ollamaHistory, role: "user", content: text)
                    OllamaClient.appendToHistory(&ollamaHistory, role: "assistant", content: response)
                    OllamaClient.truncateHistory(&ollamaHistory)

                    let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        let modelEntry = TranscriptEntry(role: .model, text: trimmed, originPop: deviceId)
                        appendTranscriptEntry(modelEntry)
                    }
                    statusMessage = useLocalModel ? "Ready (local)" : (mountedRingName ?? "")
                } catch {
                    print("[AppState] Ollama error: \(error), falling back to Gemini")
                    // Fallback to Gemini
                    await sendViaGemini(text: text, startTime: startTime)
                }
                isProcessing = false
            }
        } else if textClient != nil {
            // Cloud: use Gemini
            statusMessage = "Thinking..."
            let timerTask = Task { @MainActor in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    guard !Task.isCancelled else { break }
                    let elapsed = Int(Date().timeIntervalSince(startTime))
                    self.statusMessage = "Thinking... (\(elapsed)s)"
                }
            }
            Task {
                await sendViaGemini(text: text, startTime: startTime)
                timerTask.cancel()
                isProcessing = false
            }
        } else {
            statusMessage = "Not configured. Open Settings."
            isProcessing = false
        }
    }

    private func sendViaGemini(text: String, startTime: Date) async {
        guard let client = textClient else { return }
        do {
            let response = try await client.send(text)
            let elapsed = String(format: "%.1f", Date().timeIntervalSince(startTime))
            print("[AppState] Gemini response in \(elapsed)s")

            for tc in response.toolCalls {
                handleToolCall(callId: tc.id, name: tc.name, args: tc.args)
            }
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
            print("[AppState] Gemini error: \(error)")
            statusMessage = "Error: \(error.localizedDescription)"
            appendTranscriptEntry(TranscriptEntry(role: .system, text: "Error: \(error.localizedDescription)", originPop: deviceId))
        }
    }

    // MARK: - Voice Mode

    func startVoiceMode() {
        mode = .voice

        if useLocalModel, let ollama = ollamaClient {
            // Local voice: STT → Ollama → TTS
            if localVoiceSession == nil {
                let session = LocalVoiceSession(ollamaClient: ollama)
                session.onTranscriptEntry = { [weak self] entry in
                    self?.appendTranscriptEntry(entry)
                }
                session.onStatusMessage = { [weak self] msg in
                    self?.statusMessage = msg
                }
                localVoiceSession = session
            }
            statusMessage = "Voice ready (local)"
        } else if currentApiKey != nil {
            // Cloud voice: Gemini Live
            Task { _ = await voiceSession.startSession() }
        } else {
            statusMessage = "No backend available for voice"
            mode = .text
        }
    }

    func stopVoiceMode() {
        if useLocalModel {
            localVoiceSession?.stopRecording()
            localVoiceSession?.interrupt()
        } else {
            voiceSession.stopRecording()
            voiceSession.endSession()
        }
        mode = .text
        statusMessage = useLocalModel ? "Ready (local)" : (mountedRingName ?? "")
    }

    func toggleVoiceMode() {
        if mode == .voice { stopVoiceMode() } else { startVoiceMode() }
    }

    /// Push-to-talk: start recording (called by hotkey press).
    func startPushToTalk() {
        if mode != .voice { startVoiceMode() }
        if useLocalModel {
            localVoiceSession?.startRecording()
        } else {
            voiceSession.startRecording()
        }
    }

    /// Push-to-talk: stop recording (called by hotkey release).
    func stopPushToTalk() {
        if useLocalModel {
            localVoiceSession?.stopRecording()
        } else {
            voiceSession.stopRecording()
        }
    }

    // MARK: - Session End

    func endSession() {
        if mode == .voice { voiceSession.endSession() }
        generateHandoffSpore()
        if let ringPath = mountedRingPath {
            deps.commitAndPersist(ringPath, "Session ended")
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
        voiceSession.onThinkingText = { [weak self] text in
            self?.lastThinking = text
        }
        voiceSession.onToolCall = { [weak self] callId, name, args in
            self?.handleToolCall(callId: callId, name: name, args: args)
        }
        voiceSession.onStatusMessage = { [weak self] message in
            self?.statusMessage = message
        }
    }

    func appendTranscriptEntry(_ entry: TranscriptEntry) {
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
}
