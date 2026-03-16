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
    var isListening = false
    var isConnected = false
    var isSpeaking = false
    var partialText: String = ""

    // MARK: - Panel

    var isPanelVisible = false

    // MARK: - Device

    let deviceId = "osx-desktop"

    // MARK: - Managers

    var ringManager: RingManager?
    var sporeStore: SporeStore?
    var transcriptStore: TranscriptStore?

    // MARK: - Initialization

    func bootstrap(ring0Path: URL) {
        self.ring0Path = ring0Path
        self.ringManager = RingManager(ring0Path: ring0Path)

        // Load manifest and SOUL
        if let rm = ringManager {
            self.manifest = rm.loadManifest()
            self.soulContent = rm.loadSOUL() ?? ""
        }
    }

    func mountRing(path: URL, name: String) {
        // Commit any current state before switching
        if let current = mountedRingPath {
            gitCommit(path: current, message: "Auto-commit before ring switch to \(name)")
        }

        mountedRingPath = path
        mountedRingName = name
        sporeStore = SporeStore(ringPath: path, deviceId: deviceId)
        transcriptStore = TranscriptStore(ringPath: path, deviceId: deviceId)

        // Load channels
        channels = scanChannels(ringPath: path)
        if let defaultChannel = channels.first(where: { $0.name == "default" }) ?? channels.first {
            switchChannel(to: defaultChannel)
        }
    }

    func switchChannel(to channel: Channel) {
        activeChannel = channel
        // Load recent transcript for this channel
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

    private func gitCommit(path: URL, message: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", path.path, "add", "-A"]
        try? process.run()
        process.waitUntilExit()

        let commitProcess = Process()
        commitProcess.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        commitProcess.arguments = ["-C", path.path, "commit", "-m", message, "--allow-empty-message"]
        try? commitProcess.run()
        commitProcess.waitUntilExit()
    }
}
