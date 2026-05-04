import Foundation
import Observation
import OSLog

/// Mirrors mihomo's `/configs` snapshot for the bits the UI cares about.
/// Currently that's just outbound mode; expand as more toolbar bindings
/// (LAN, log level, port, …) move into the chrome.
@Observable
@MainActor
final class ConfigStore {
    private(set) var mode: MihomoMode?
    private(set) var lastError: String?
    private(set) var isApplyingMode: Bool = false

    private let log = Logger(subsystem: "com.tzaigroup.chunghwa", category: "config")

    func reset() {
        mode = nil
        lastError = nil
        isApplyingMode = false
    }

    func refresh(api: MihomoAPIClient?) async {
        guard let api else { reset(); return }
        do {
            let cfg = try await api.config()
            mode = MihomoMode.parse(cfg.mode)
            lastError = nil
        } catch {
            lastError = String(describing: error)
            log.error("refresh failed: \(self.lastError ?? "?", privacy: .public)")
        }
    }

    func setMode(_ next: MihomoMode, api: MihomoAPIClient?) async {
        guard let api else { return }
        let previous = mode
        // Optimistic — flip the toolbar pill instantly and roll back on
        // failure. Mihomo accepts the change in <50 ms locally so the
        // optimistic update almost always lands.
        mode = next
        isApplyingMode = true
        defer { isApplyingMode = false }
        do {
            try await api.setMode(next)
            lastError = nil
        } catch {
            mode = previous
            lastError = String(describing: error)
            log.error("set mode \(next.rawValue, privacy: .public) failed: \(self.lastError ?? "?", privacy: .public)")
        }
    }
}
