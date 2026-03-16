import Foundation

enum SporeType: String, Codable, CaseIterable {
    case task
    case note
    case discovery
    case decision
    case handoff
}

enum SporeStatus: String, Codable, CaseIterable {
    case open
    case inProgress = "in_progress"
    case blocked
    case done
    case archived
}

struct Spore: Codable, Identifiable, Sendable {
    var id: String
    var type: SporeType
    var status: SporeStatus
    var parentId: String?
    var blockedBy: [String]
    var channel: String
    var tags: [String]
    var metadata: [String: AnyCodable]
    var content: String
    var contextRecap: String?
    var createdAt: Date
    var updatedAt: Date
    var originPop: String

    enum CodingKeys: String, CodingKey {
        case id, type, status, channel, tags, metadata, content
        case parentId = "parent_id"
        case blockedBy = "blocked_by"
        case contextRecap = "context_recap"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case originPop = "origin_pop"
    }

    init(
        id: String = UUID().uuidString,
        type: SporeType,
        status: SporeStatus = .open,
        parentId: String? = nil,
        blockedBy: [String] = [],
        channel: String = "default",
        tags: [String] = [],
        metadata: [String: AnyCodable] = [:],
        content: String,
        contextRecap: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        originPop: String
    ) {
        self.id = id
        self.type = type
        self.status = status
        self.parentId = parentId
        self.blockedBy = blockedBy
        self.channel = channel
        self.tags = tags
        self.metadata = metadata
        self.content = content
        self.contextRecap = contextRecap
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.originPop = originPop
    }
}

/// Type-erased Codable wrapper for arbitrary JSON values in metadata.
struct AnyCodable: Codable, Sendable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            value = string
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map(\.value)
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues(\.value)
        } else {
            value = NSNull()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let string as String: try container.encode(string)
        case let int as Int: try container.encode(int)
        case let double as Double: try container.encode(double)
        case let bool as Bool: try container.encode(bool)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            try container.encodeNil()
        }
    }
}
