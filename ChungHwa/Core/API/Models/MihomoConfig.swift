import Foundation

/// Subset of `/configs` we actually consume. Mihomo returns dozens of fields;
/// we model only what the UI binds against. `mode` is what drives the
/// outbound segmented control in the toolbar.
nonisolated struct MihomoConfig: Codable, Sendable {
    let mode: String?
    let logLevel: String?
    let allowLan: Bool?
    let port: Int?
    let socksPort: Int?

    enum CodingKeys: String, CodingKey {
        case mode
        case logLevel = "log-level"
        case allowLan = "allow-lan"
        case port
        case socksPort = "socks-port"
    }
}

enum MihomoMode: String, Codable, CaseIterable, Sendable {
    case rule, global, direct

    var displayName: String {
        switch self {
        case .rule:   return "Rule"
        case .global: return "Global"
        case .direct: return "Direct"
        }
    }

    static func parse(_ raw: String?) -> MihomoMode? {
        guard let raw else { return nil }
        return MihomoMode(rawValue: raw.lowercased())
    }
}
