import Foundation

enum TranscriptRole: String, Codable {
    case user
    case model
    case system
}

struct TranscriptEntry: Codable, Identifiable, Sendable {
    var id: UUID = UUID()
    var timestamp: Date
    var role: TranscriptRole
    var text: String
    var isFinal: Bool
    var originPop: String

    enum CodingKeys: String, CodingKey {
        case timestamp, role, text
        case isFinal = "is_final"
        case originPop = "origin_pop"
    }

    init(
        timestamp: Date = Date(),
        role: TranscriptRole,
        text: String,
        isFinal: Bool = true,
        originPop: String
    ) {
        self.timestamp = timestamp
        self.role = role
        self.text = text
        self.isFinal = isFinal
        self.originPop = originPop
    }
}
