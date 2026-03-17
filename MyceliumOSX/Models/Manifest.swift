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

struct ProviderConfig: Codable, Sendable {
    let name: String      // "ollama", "claude", "gemini"
    let model: String     // "gemma3:4b", "haiku", "gemini-2.5-flash"
    let apiKeyRef: String? // Only needed for gemini

    enum CodingKeys: String, CodingKey {
        case name, model
        case apiKeyRef = "api_key_ref"
    }
}

enum RoutingMode: String, Codable, Sendable {
    case auto    // Local model classifies and routes
    case manual  // User picks, or first available
}

struct BackendConfig: Codable, Sendable {
    let providers: [ProviderConfig]
    let routing: RoutingMode?

    // Backwards compatibility: single-provider format
    let provider: String?
    let apiKeyRef: String?
    let model: String?

    enum CodingKeys: String, CodingKey {
        case providers, routing, provider, model
        case apiKeyRef = "api_key_ref"
    }

    /// Memberwise init for programmatic construction.
    init(providers: [ProviderConfig] = [], routing: RoutingMode? = nil,
         provider: String? = nil, apiKeyRef: String? = nil, model: String? = nil) {
        self.providers = providers
        self.routing = routing
        self.provider = provider
        self.apiKeyRef = apiKeyRef
        self.model = model
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        providers = (try? container.decode([ProviderConfig].self, forKey: .providers)) ?? []
        routing = try? container.decode(RoutingMode.self, forKey: .routing)
        provider = try? container.decode(String.self, forKey: .provider)
        apiKeyRef = try? container.decode(String.self, forKey: .apiKeyRef)
        model = try? container.decode(String.self, forKey: .model)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if !providers.isEmpty {
            try container.encode(providers, forKey: .providers)
            try container.encodeIfPresent(routing, forKey: .routing)
        }
        try container.encodeIfPresent(provider, forKey: .provider)
        try container.encodeIfPresent(apiKeyRef, forKey: .apiKeyRef)
        try container.encodeIfPresent(model, forKey: .model)
    }

    /// Resolved list of providers (handles both old single-provider and new multi-provider format).
    var resolvedProviders: [ProviderConfig] {
        if !providers.isEmpty { return providers }
        // Legacy: convert single provider to list
        if let provider, let model {
            return [ProviderConfig(name: provider, model: model, apiKeyRef: apiKeyRef)]
        }
        return []
    }

    var resolvedRouting: RoutingMode {
        routing ?? .manual
    }
}

struct RingEntry: Codable, Sendable {
    let name: String
    let repoUrl: String
    let accessRules: [String: [String]]
    let backend: BackendConfig?

    enum CodingKeys: String, CodingKey {
        case name, backend
        case repoUrl = "repo_url"
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
