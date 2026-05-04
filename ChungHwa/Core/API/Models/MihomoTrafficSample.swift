import Foundation

nonisolated struct MihomoTrafficSample: Codable, Sendable {
    /// Upload bytes since the last sample (mihomo emits at 1 Hz, so this is
    /// effectively bytes / second).
    let up: Int
    let down: Int
}

nonisolated struct MihomoMemorySample: Codable, Sendable {
    /// Heap bytes currently in use by the kernel.
    let inuse: Int
    /// Soft limit configured for the kernel; 0 means unset / unlimited.
    let oslimit: Int
}
