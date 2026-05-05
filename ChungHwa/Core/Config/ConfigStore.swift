import Foundation
import Observation
import OSLog

/// Snapshot of the user's persisted DNS preferences. Read by both the live
/// kernel (PATCH /configs) and the YAML composer at boot.
struct DNSPrefs: Equatable, Sendable {
    var nameservers: [String]
    var fallback: [String]
    var hijackEnabled: Bool
    var mode: String

    /// Convert the UI mode string into mihomo's `enhanced-mode` value.
    var enhancedMode: String {
        switch mode {
        case "system":  return "redir-host"
        case "fake-ip": return "fake-ip"
        default:        return "fake-ip"   // smart → fake-ip on the egress side
        }
    }
}

/// One persisted custom routing rule. `match` is a mihomo rule prefix
/// (e.g. "DOMAIN-SUFFIX,example.com"), `target` is "DIRECT" / "REJECT" or
/// the name of a proxy group.
struct CustomRule: Codable, Equatable, Identifiable, Sendable {
    var id: UUID = UUID()
    var match: String
    var target: String
}

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
    /// Persisted mixed-port (mihomo's combined HTTP/SOCKS5 inbound). Mirrors
    /// `ChungHwa.MixedPort` UserDefaults; `ConfigComposer`, system proxy
    /// apply, and the network probe all read from the same key.
    private(set) var mixedPort: Int
    private(set) var dnsNameservers: [String]
    private(set) var dnsFallback: [String]
    private(set) var dnsHijackEnabled: Bool
    private(set) var dnsMode: String
    private(set) var customRules: [CustomRule]
    private(set) var unifiedDelay: Bool
    private(set) var proxyAuthUser: String
    private(set) var proxyAuthPass: String
    private(set) var lastError: String?
    private(set) var isApplyingMode: Bool = false

    static let tunEnabledDefaultsKey = "ChungHwa.TunEnabled"
    static let mixedPortDefaultsKey = "ChungHwa.MixedPort"
    static let dnsNameserversKey = "ChungHwa.DNS.Nameservers"
    static let dnsFallbackKey = "ChungHwa.DNS.Fallback"
    static let dnsHijackKey = "ChungHwa.Advanced.DNSHijack"
    static let dnsModeKey = "ChungHwa.Advanced.DNSMode"
    static let customRulesKey = "ChungHwa.CustomRules"
    static let unifiedDelayKey = "ChungHwa.Advanced.UnifiedDelay"
    static let proxyAuthUserKey = "ChungHwa.Advanced.AuthUser"
    static let proxyAuthPassKey = "ChungHwa.Advanced.AuthPass"
    static let bypassListKey = "ChungHwa.Advanced.BypassList"
    static let defaultMixedPort = 7890

    static let defaultNameservers = [
        "https://cloudflare-dns.com/dns-query",
        "https://dns.google/dns-query",
    ]
    static let defaultFallback = [
        "tls://1.1.1.1",
        "tls://8.8.8.8",
    ]

    static var currentMixedPort: Int {
        UserDefaults.standard.object(forKey: mixedPortDefaultsKey) as? Int ?? defaultMixedPort
    }

    /// Static accessor for the current DNS preferences. Read at YAML compose
    /// time (no live ConfigStore in scope there) and at hot-PATCH time via
    /// the instance helper. UserDefaults is the single source of truth.
    static func currentDNS() -> DNSPrefs {
        let ns = (UserDefaults.standard.array(forKey: dnsNameserversKey) as? [String])
            ?? defaultNameservers
        let fb = (UserDefaults.standard.array(forKey: dnsFallbackKey) as? [String])
            ?? defaultFallback
        let hijack: Bool = {
            if UserDefaults.standard.object(forKey: dnsHijackKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: dnsHijackKey)
        }()
        let mode = (UserDefaults.standard.string(forKey: dnsModeKey)) ?? "smart"
        return DNSPrefs(nameservers: ns, fallback: fb, hijackEnabled: hijack, mode: mode)
    }

    static func currentCustomRules() -> [CustomRule] {
        guard let data = UserDefaults.standard.data(forKey: customRulesKey),
              let decoded = try? JSONDecoder().decode([CustomRule].self, from: data)
        else { return [] }
        return decoded
    }

    /// Whether to inject `unified-delay: true` into the composed yaml. mihomo
    /// reports a single delay number per node when on, instead of separate
    /// connect / handshake numbers — friendlier for at-a-glance comparison.
    static var currentUnifiedDelay: Bool {
        if UserDefaults.standard.object(forKey: unifiedDelayKey) == nil { return true }
        return UserDefaults.standard.bool(forKey: unifiedDelayKey)
    }

    /// `(user, pass)` for HTTP/SOCKS inbound auth. Both empty = no auth.
    static func currentProxyAuth() -> (user: String, pass: String) {
        let u = UserDefaults.standard.string(forKey: proxyAuthUserKey) ?? ""
        let p = UserDefaults.standard.string(forKey: proxyAuthPassKey) ?? ""
        return (u, p)
    }

    /// User-managed system-proxy bypass entries. Read by SystemProxyController
    /// to populate the `ExceptionsList` when enabling the macOS proxy. Stored
    /// as JSON-encoded `[BypassEntry]` from AdvancedView; we only need the
    /// `ip` field here so we extract it loosely.
    static func currentBypassIPs() -> [String] {
        guard let data = UserDefaults.standard.data(forKey: bypassListKey),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return [] }
        return array.compactMap { $0["ip"] as? String }
    }

    private let log = Logger(subsystem: "org.clash.ChungHwa", category: "config")

    init() {
        self.tunEnabled = UserDefaults.standard.bool(forKey: Self.tunEnabledDefaultsKey)
        self.mixedPort = Self.currentMixedPort
        let prefs = Self.currentDNS()
        self.dnsNameservers = prefs.nameservers
        self.dnsFallback = prefs.fallback
        self.dnsHijackEnabled = prefs.hijackEnabled
        self.dnsMode = prefs.mode
        self.customRules = Self.currentCustomRules()
        self.unifiedDelay = Self.currentUnifiedDelay
        let auth = Self.currentProxyAuth()
        self.proxyAuthUser = auth.user
        self.proxyAuthPass = auth.pass
    }

    /// Persist + flag the unified-delay switch. Caller must trigger a kernel
    /// restart for the new yaml to take effect (no PATCH path on mihomo for
    /// this).
    func setUnifiedDelay(_ enabled: Bool) {
        unifiedDelay = enabled
        UserDefaults.standard.set(enabled, forKey: Self.unifiedDelayKey)
    }

    /// Persist proxy-auth credentials. Empty user disables auth entirely.
    /// Caller must restart the kernel to apply.
    func setProxyAuth(user: String, pass: String) {
        proxyAuthUser = user
        proxyAuthPass = pass
        UserDefaults.standard.set(user, forKey: Self.proxyAuthUserKey)
        UserDefaults.standard.set(pass, forKey: Self.proxyAuthPassKey)
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

    /// Persist a new mixed-port. The kernel does NOT hot-reload listening
    /// ports via PATCH /configs, so the caller must restart the kernel for
    /// the change to take effect. Returns false on invalid range.
    @discardableResult
    func setMixedPort(_ port: Int) -> Bool {
        guard (1...65535).contains(port) else { return false }
        mixedPort = port
        UserDefaults.standard.set(port, forKey: Self.mixedPortDefaultsKey)
        return true
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

    /// Persist the upstream nameserver / fallback lists and (when the kernel
    /// is up) PATCH the live `dns` block. Empties are dropped before save.
    func setDNS(nameservers: [String], fallback: [String], api: MihomoAPIClient?) async {
        let cleanNS = nameservers
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let cleanFB = fallback
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        dnsNameservers = cleanNS
        dnsFallback = cleanFB
        UserDefaults.standard.set(cleanNS, forKey: Self.dnsNameserversKey)
        UserDefaults.standard.set(cleanFB, forKey: Self.dnsFallbackKey)
        await pushDNS(api: api)
    }

    /// Persist the DNS mode. Mirrors `ChungHwa.Advanced.DNSMode` AppStorage.
    func setDNSMode(_ mode: String, api: MihomoAPIClient?) async {
        dnsMode = mode
        UserDefaults.standard.set(mode, forKey: Self.dnsModeKey)
        await pushDNS(api: api)
    }

    /// Persist the DNS hijack toggle.
    func setDNSHijack(_ enabled: Bool, api: MihomoAPIClient?) async {
        dnsHijackEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.dnsHijackKey)
        await pushDNS(api: api)
    }

    private func pushDNS(api: MihomoAPIClient?) async {
        guard let api else { return }
        let prefs = DNSPrefs(
            nameservers: dnsNameservers,
            fallback: dnsFallback,
            hijackEnabled: dnsHijackEnabled,
            mode: dnsMode
        )
        do {
            try await api.setDNS(prefs)
            lastError = nil
        } catch {
            lastError = String(describing: error)
            log.error("set dns failed: \(self.lastError ?? "?", privacy: .public)")
        }
    }

    /// Persist the custom rule list. Effective only when the active profile
    /// is the default (no user yaml) — see ConfigComposer for the rationale.
    /// A kernel restart is required to take effect.
    func setCustomRules(_ rules: [CustomRule]) {
        customRules = rules
        if let data = try? JSONEncoder().encode(rules) {
            UserDefaults.standard.set(data, forKey: Self.customRulesKey)
        }
    }
}
