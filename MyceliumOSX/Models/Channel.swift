import Foundation

struct Channel: Identifiable, Sendable {
    let name: String
    let ringPath: URL
    var lastActivity: Date?

    var id: String { name }

    var directoryURL: URL {
        ringPath.appendingPathComponent("channels/\(name)")
    }

    var transcriptPattern: String {
        "transcript-*.jsonl"
    }
}
