import Foundation
import Observation
import OSLog

/// Mirrors mihomo's `/configs` snapshot for the bits the UI cares about.
/// Currently outbound mode + log level + LAN inbound; expand as more
/// toolbar / settings bindings (port, …) move into the chrome.
@Observable
@MainActor
final class ConfigStore {
    private(set) var mode: MihomoMode?
    private(set) var logLevel: String?
    private(set) var allowLan: Bool?
    private(set) var lastError: String?
    private(set) var isApplyingMode: Bool = false

    private let log = Logger(subsystem: "com.tzaigroup.chunghwa", category: "config")

    func reset() {
        mode = nil
        logLevel = nil
        allowLan = nil
        lastError = nil
        isApplyingMode = false
    }

    func refresh(api: MihomoAPIClient?) async {
        guard let api else { reset(); return }
        do {
            let cfg = try await api.config()
            mode = MihomoMode.parse(cfg.mode)
            logLevel = cfg.logLevel
            allowLan = cfg.allowLan
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

    /// Push a new log level to mihomo. Optimistic; rolls back the cached
    /// snapshot on failure but the @AppStorage value in the UI keeps the
    /// user's choice (so the next kernel restart will retry implicitly).
    func setLogLevel(_ level: String, api: MihomoAPIClient?) async {
        guard let api else { return }
        let previous = logLevel
        logLevel = level
        do {
            try await api.setLogLevel(level)
            lastError = nil
        } catch {
            logLevel = previous
            lastError = String(describing: error)
            log.error("set log-level \(level, privacy: .public) failed: \(self.lastError ?? "?", privacy: .public)")
        }
    }

    /// Push the allow-lan flag. Optimistic + rollback on failure.
    func setAllowLan(_ allow: Bool, api: MihomoAPIClient?) async {
        guard let api else { return }
        let previous = allowLan
        allowLan = allow
        do {
            try await api.setAllowLan(allow)
            lastError = nil
        } catch {
            allowLan = previous
            lastError = String(describing: error)
            log.error("set allow-lan \(allow, privacy: .public) failed: \(self.lastError ?? "?", privacy: .public)")
        }
    }
}
