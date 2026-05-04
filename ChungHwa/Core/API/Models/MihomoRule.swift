import Foundation

/// One row from mihomo's `/rules` endpoint. mihomo doesn't return a stable
/// identifier and the same `(type, payload, proxy)` triple can legitimately
/// appear more than once, so for SwiftUI we synthesise an `id` from the row's
/// index in the response (see `init(type:payload:proxy:index:)`). The plain
/// `init(from:)` falls back to the triple — fine when consumed standalone.
nonisolated struct MihomoRule: Codable, Sendable, Identifiable {
    let type: String
    let payload: String
    let proxy: String
    let id: String

    private enum CodingKeys: String, CodingKey {
        case type, payload, proxy
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        let payload = try c.decode(String.self, forKey: .payload)
        let proxy = try c.decode(String.self, forKey: .proxy)
        self.type = type
        self.payload = payload
        self.proxy = proxy
        self.id = "\(type)|\(payload)|\(proxy)"
    }

    /// Build a rule with an index-prefixed id so duplicates remain stable in
    /// `ForEach`.
    init(type: String, payload: String, proxy: String, index: Int) {
        self.type = type
        self.payload = payload
        self.proxy = proxy
        self.id = "\(index)|\(type)|\(payload)|\(proxy)"
    }
}

nonisolated struct MihomoRulesResponse: Codable, Sendable {
    let rules: [MihomoRule]
}

/// One entry from `/providers/rules`. mihomo keys providers by name in a
/// dictionary, so `name` is filled in by the client after decoding.
nonisolated struct MihomoRuleProvider: Codable, Sendable, Identifiable {
    var id: String { name }
    let name: String
    let behavior: String
    let type: String
    let ruleCount: Int
    let updatedAt: String?
    let vehicleType: String?
}

nonisolated struct MihomoRuleProvidersResponse: Codable, Sendable {
    let providers: [String: MihomoRuleProvider]
}
