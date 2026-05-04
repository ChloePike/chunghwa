import Foundation

nonisolated struct MihomoVersion: Codable, Sendable {
    let version: String
    let meta: Bool?
}
