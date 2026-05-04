import Foundation

/// One entry from `/providers/proxies`. mihomo keys these by name in a
/// dictionary, mirroring `/providers/rules`. Each entry also carries a
/// `proxies` array (the actual nodes) that's huge in practice — we only
/// surface the subscription-summary metadata in the Providers tab, so we
/// list `CodingKeys` explicitly to skip decoding it.
nonisolated struct MihomoProxyProvider: Codable, Sendable, Identifiable {
    var id: String { name }
    let name: String
    let type: String           // e.g. "Proxy", "Compatible"
    let vehicleType: String?   // "HTTP" / "File" / "Compatible"
    let updatedAt: String?
    let subscriptionInfo: SubscriptionInfo?

    private enum CodingKeys: String, CodingKey {
        case name
        case type
        case vehicleType
        case updatedAt
        case subscriptionInfo
    }

    /// Bytes counters returned by mihomo. Field names match the kernel's
    /// capitalised JSON keys verbatim so we don't need a custom decoder.
    nonisolated struct SubscriptionInfo: Codable, Sendable {
        let Total: Int?
        let Upload: Int?
        let Download: Int?
        let Expire: Int?       // epoch seconds; 0 = never
    }
}

nonisolated struct MihomoProxyProvidersResponse: Codable, Sendable {
    let providers: [String: MihomoProxyProvider]
}
