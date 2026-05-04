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
    private(set) var ipv6: Bool?
    private(set) var tcpConcurrent: Bool?
    /// Persisted user preference. Mirrors `ChungHwa.TunEnabled` UserDefaults
    /// key — `MihomoConfig.tun` is not modeled, so this is what the UI binds
    /// against and what `ConfigComposer` injects into the boot yaml.
    private(set) var tunEnabled: Bool
    private(set) var lastError: String?
    private(set) var isApplyingMode: Bool = false

    static let tunEnabledDefaultsKey = "ChungHwa.TunEnabled"

    private let log = Logger(subsystem: "com.tzaigroup.chunghwa", category: "config")

    init() {
        self.tunEnabled = UserDefaults.standard.bool(forKey: Self.tunEnabledDefaultsKey)
    }

    func reset() {
        mode = nil
        logLevel = nil
        allowLan = nil
        ipv6 = nil
        tcpConcurrent = nil
        // tunEnabled is intentionally NOT reset — it's a persisted user pref,
        // not a runtime mirror like the others.
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
            ipv6 = cfg.ipv6
            tcpConcurrent = cfg.tcpConcurrent
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

    /// Push the ipv6 flag. Optimistic + rollback on failure.
    func setIPv6(_ enabled: Bool, api: MihomoAPIClient?) async {
        guard let api else { return }
        let previous = ipv6
        ipv6 = enabled
        do {
            try await api.setIPv6(enabled)
            lastError = nil
        } catch {
            ipv6 = previous
            lastError = String(describing: error)
            log.error("set ipv6 \(enabled, privacy: .public) failed: \(self.lastError ?? "?", privacy: .public)")
        }
    }

    /// Persist + push the TUN enable flag. The local pref is written
    /// immediately so subsequent kernel restarts pick it up via the YAML
    /// composer; on PATCH failure we roll back both the local state and the
    /// persisted pref.
    func setTUN(_ enabled: Bool, api: MihomoAPIClient?) async {
        let previous = tunEnabled
        tunEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.tunEnabledDefaultsKey)
        guard let api else {
            // No live kernel — just keep the persisted pref; next start picks
            // it up via ConfigComposer.
            return
        }
        do {
            try await api.setTUN(enabled: enabled)
            lastError = nil
        } catch {
            tunEnabled = previous
            UserDefaults.standard.set(previous, forKey: Self.tunEnabledDefaultsKey)
            lastError = String(describing: error)
            log.error("set tun \(enabled, privacy: .public) failed: \(self.lastError ?? "?", privacy: .public)")
        }
    }

    /// Push the tcp-concurrent flag. Optimistic + rollback on failure.
    func setTCPConcurrent(_ enabled: Bool, api: MihomoAPIClient?) async {
        guard let api else { return }
        let previous = tcpConcurrent
        tcpConcurrent = enabled
        do {
            try await api.setTCPConcurrent(enabled)
            lastError = nil
        } catch {
            tcpConcurrent = previous
            lastError = String(describing: error)
            log.error("set tcp-concurrent \(enabled, privacy: .public) failed: \(self.lastError ?? "?", privacy: .public)")
        }
    }
}
