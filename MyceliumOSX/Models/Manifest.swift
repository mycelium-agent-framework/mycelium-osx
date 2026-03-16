import Foundation

struct PopEntry: Codable, Sendable {
    let deviceId: String
    let displayName: String
    let capabilities: [String]
    let lastActive: Date?
    let allowedRings: [String]

    enum CodingKeys: String, CodingKey {
        case capabilities
        case deviceId = "device_id"
        case displayName = "display_name"
        case lastActive = "last_active"
        case allowedRings = "allowed_rings"
    }
}

struct RingEntry: Codable, Sendable {
    let name: String
    let repoUrl: String
    let localPathHint: String?
    let accessRules: [String: [String]]

    enum CodingKeys: String, CodingKey {
        case name
        case repoUrl = "repo_url"
        case localPathHint = "local_path_hint"
        case accessRules = "access_rules"
    }
}

struct ChannelState: Codable, Sendable {
    let name: String
    let ring: String
    let lastActive: Date?
    let isActive: Bool

    enum CodingKeys: String, CodingKey {
        case name, ring
        case lastActive = "last_active"
        case isActive = "is_active"
    }
}

struct Manifest: Codable, Sendable {
    let agentName: String
    let version: String
    let pops: [PopEntry]
    let rings: [RingEntry]
    let channels: [ChannelState]
    let activeRing: String?

    enum CodingKeys: String, CodingKey {
        case pops, rings, channels, version
        case agentName = "agent_name"
        case activeRing = "active_ring"
    }
}
