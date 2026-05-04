import Foundation

/// Single entry in `/proxies`. Both upstream proxies and groups share the same
/// shape; the difference is whether `now` / `all` are populated.
nonisolated struct MihomoProxy: Codable, Sendable, Identifiable {
    var id: String { name }

    let name: String
    let type: String
    let now: String?
    let all: [String]?
    let history: [DelaySample]?
    let udp: Bool?

    nonisolated struct DelaySample: Codable, Sendable {
        let time: String
        let delay: Int
    }

    /// Mihomo "group" types that bundle other proxies. Membership is
    /// case-insensitive because mihomo varies between releases.
    static let groupTypes: Set<String> = [
        "selector", "urltest", "fallback", "loadbalance", "relay",
    ]

    var isGroup: Bool { Self.groupTypes.contains(type.lowercased()) }

    /// Only Selector groups support arbitrary manual selection via
    /// `PUT /proxies/{name}`. Auto-strategy groups (URLTest, Fallback,
    /// LoadBalance) compute their own pick.
    var isUserSwitchable: Bool { type.lowercased() == "selector" }

    /// Latency of the most recent successful probe, or nil if untested.
    var lastDelay: Int? {
        guard let history, let last = history.last else { return nil }
        return last.delay > 0 ? last.delay : nil
    }
}

nonisolated struct MihomoProxiesSnapshot: Codable, Sendable {
    let proxies: [String: MihomoProxy]
}

nonisolated struct MihomoDelayResponse: Codable, Sendable {
    let delay: Int?
    let message: String?
}
