import Foundation

nonisolated struct MihomoLogEvent: Codable, Sendable {
    let type: String      // "info" | "warning" | "error" | "debug"
    let payload: String
}
