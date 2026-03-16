import Foundation

/// Reads and writes transcript entries to writer-sharded JSONL files.
/// Each device writes to `channels/{name}/transcript-{deviceId}.jsonl`.
final class TranscriptStore: Sendable {
    let ringPath: URL
    let deviceId: String

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = []
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    init(ringPath: URL, deviceId: String) {
        self.ringPath = ringPath
        self.deviceId = deviceId
    }

    // MARK: - File paths

    private func ownFile(channel: String) -> URL {
        ringPath.appendingPathComponent("channels/\(channel)/transcript-\(deviceId).jsonl")
    }

    private func channelDir(_ channel: String) -> URL {
        ringPath.appendingPathComponent("channels/\(channel)")
    }

    // MARK: - Write

    func append(entry: TranscriptEntry, channel: String) {
        let fileURL = ownFile(channel: channel)
        let dir = channelDir(channel)
        ensureDirectoryExists(dir)

        guard let data = try? Self.encoder.encode(entry),
              var line = String(data: data, encoding: .utf8) else {
            print("[TranscriptStore] Failed to encode transcript entry")
            return
        }

        line += "\n"

        if FileManager.default.fileExists(atPath: fileURL.path) {
            guard let handle = try? FileHandle(forWritingTo: fileURL) else { return }
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            handle.closeFile()
        } else {
            try? line.write(to: fileURL, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Read

    /// Load recent transcript entries from all device shards for a channel.
    func loadRecentEntries(channel: String, limit: Int = 50) -> [TranscriptEntry] {
        let dir = channelDir(channel)
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter({ $0.lastPathComponent.hasPrefix("transcript-") && $0.pathExtension == "jsonl" })
        else { return [] }

        let allEntries = files.flatMap { loadEntries(from: $0) }
            .sorted { $0.timestamp < $1.timestamp }

        return Array(allEntries.suffix(limit))
    }

    private func loadEntries(from url: URL) -> [TranscriptEntry] {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return content.split(separator: "\n").compactMap { line in
            try? Self.decoder.decode(TranscriptEntry.self, from: Data(line.utf8))
        }
    }

    private func ensureDirectoryExists(_ url: URL) {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}
