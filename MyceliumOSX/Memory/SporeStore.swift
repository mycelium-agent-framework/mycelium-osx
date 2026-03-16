import Foundation

/// Reads and writes spores to writer-sharded JSONL files.
/// Each device writes only to its own `memory-{deviceId}.jsonl`.
final class SporeStore: Sendable {
    let ringPath: URL
    let deviceId: String

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [] // Single line — no pretty print
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

    private var ownFile: URL {
        ringPath.appendingPathComponent(".mycelium/memory-\(deviceId).jsonl")
    }

    private var memoryDir: URL {
        ringPath.appendingPathComponent(".mycelium")
    }

    // MARK: - Write

    func append(spore: Spore) {
        let fileURL = ownFile
        ensureDirectoryExists(memoryDir)

        guard let data = try? Self.encoder.encode(spore),
              var line = String(data: data, encoding: .utf8) else {
            print("[SporeStore] Failed to encode spore \(spore.id)")
            return
        }

        line += "\n"

        // Atomic write strategy: append to temp file, rename if needed
        if FileManager.default.fileExists(atPath: fileURL.path) {
            guard let handle = try? FileHandle(forWritingTo: fileURL) else {
                print("[SporeStore] Failed to open \(fileURL.path) for writing")
                return
            }
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            handle.closeFile()
        } else {
            try? line.write(to: fileURL, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Read

    /// Load all spores from all device shards in this ring.
    func loadAll() -> [Spore] {
        let dir = memoryDir
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter({ $0.lastPathComponent.hasPrefix("memory-") && $0.pathExtension == "jsonl" })
        else { return [] }

        return files.flatMap { loadSpores(from: $0) }
            .sorted { $0.createdAt < $1.createdAt }
    }

    /// Load spores from a specific channel.
    func loadForChannel(_ channel: String) -> [Spore] {
        loadAll().filter { $0.channel == channel }
    }

    private func loadSpores(from url: URL) -> [Spore] {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return content.split(separator: "\n").compactMap { line in
            try? Self.decoder.decode(Spore.self, from: Data(line.utf8))
        }
    }

    // MARK: - Helpers

    private func ensureDirectoryExists(_ url: URL) {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}
