import Foundation

nonisolated struct MihomoConnection: Codable, Sendable, Identifiable {
    let id: String
    let metadata: Metadata
    let upload: Int
    let download: Int
    let start: String
    let chains: [String]
    let rule: String
    let rulePayload: String?

    nonisolated struct Metadata: Codable, Sendable {
        let network: String?
        let type: String?
        let sourceIP: String?
        let sourcePort: String?
        let destinationIP: String?
        let destinationPort: String?
        let host: String?
        let process: String?
        let processPath: String?
    }

    /// "host:port" if the kernel resolved a hostname; falls back to IP:port.
    var destination: String {
        let port = metadata.destinationPort ?? ""
        if let host = metadata.host, !host.isEmpty {
            return port.isEmpty ? host : "\(host):\(port)"
        }
        let ip = metadata.destinationIP ?? "?"
        return port.isEmpty ? ip : "\(ip):\(port)"
    }

    /// Last entry of `chains` is the actual upstream proxy mihomo dispatched
    /// the connection through. The earlier entries are the groups that led
    /// to it.
    var activeProxy: String {
        chains.last ?? "DIRECT"
    }

    var chainPath: String {
        chains.reversed().joined(separator: " › ")
    }
}

nonisolated struct MihomoConnectionsSnapshot: Codable, Sendable {
    let downloadTotal: Int?
    let uploadTotal: Int?
    let connections: [MihomoConnection]?
    let memory: Int?
}
