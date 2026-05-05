import Foundation
import Observation
import OSLog
import SystemConfiguration
import Security

enum SystemProxyError: Error, CustomStringConvertible {
    case authorization(String)
    case preferences(String)

    var description: String {
        switch self {
        case .authorization(let s): return "authorization: \(s)"
        case .preferences(let s):   return "preferences: \(s)"
        }
    }
}

/// Controls macOS HTTP / HTTPS / SOCKS5 system proxy via SCPreferences.
///
/// Modifying network preferences requires admin authorization. We cache the
/// `AuthorizationRef` for the controller's lifetime so the user is prompted
/// **once per app launch**, not on every toggle. macOS keeps the granted
/// `system.preferences` right valid as long as the AuthorizationRef stays
/// alive — the previous implementation created + freed a fresh ref each
/// apply() and that's why every toggle re-prompted.
@Observable
@MainActor
final class SystemProxyController {
    private(set) var enabled: Bool = false
    private(set) var lastError: String?

    let host = "127.0.0.1"
    /// mihomo's mixed-port handles HTTP CONNECT and SOCKS5 on the same port.
    /// Reads from `ConfigStore.currentMixedPort` so changing the port in
    /// Settings + restarting the kernel automatically routes the system
    /// proxy at the new port without a separate write here.
    var port: Int { ConfigStore.currentMixedPort }

    private let log = Logger(subsystem: "org.clash.ChungHwa", category: "systemProxy")

    /// Cached admin auth — created lazily on first apply(), reused forever.
    /// `@ObservationIgnored` so observation tracking isn't affected.
    @ObservationIgnored private var cachedAuth: AuthorizationRef?

    init() {
        self.enabled = currentlyEnabled()
    }

    deinit {
        if let auth = cachedAuth {
            AuthorizationFree(auth, [.destroyRights])
        }
    }

    func toggle() { enabled ? disable() : enable() }

    func enable() {
        do {
            try apply(on: true)
            enabled = true
            lastError = nil
            log.info("system proxy enabled @ \(self.host, privacy: .public):\(self.port, privacy: .public)")
        } catch {
            lastError = String(describing: error)
            log.error("enable failed: \(self.lastError ?? "?", privacy: .public)")
        }
    }

    /// Re-apply current state (used after the bypass list changes so the
    /// new ExceptionsList is picked up without the user toggling off+on).
    func reapply() {
        guard enabled else { return }
        do {
            try apply(on: true)
            lastError = nil
        } catch {
            lastError = String(describing: error)
            log.error("reapply failed: \(self.lastError ?? "?", privacy: .public)")
        }
    }

    func disable() {
        do {
            try apply(on: false)
            enabled = false
            lastError = nil
            log.info("system proxy disabled")
        } catch {
            lastError = String(describing: error)
            log.error("disable failed: \(self.lastError ?? "?", privacy: .public)")
        }
    }

    /// Best-effort: check if any enabled network service currently has the
    /// HTTP proxy pointing at our host. We do not claim ownership of state we
    /// did not set; this is just to seed the UI on launch.
    private func currentlyEnabled() -> Bool {
        guard let prefs = SCPreferencesCreate(nil, "ChungHwa.read" as CFString, nil),
              let services = SCNetworkServiceCopyAll(prefs) as? [SCNetworkService] else {
            return false
        }
        for service in services {
            guard SCNetworkServiceGetEnabled(service),
                  let proto = SCNetworkServiceCopyProtocol(service, kSCNetworkProtocolTypeProxies),
                  let cfg = SCNetworkProtocolGetConfiguration(proto) as? [String: Any] else { continue }
            if let on = cfg[kSCPropNetProxiesHTTPEnable as String] as? Int, on == 1,
               let host = cfg[kSCPropNetProxiesHTTPProxy as String] as? String,
               host == self.host {
                return true
            }
        }
        return false
    }

    /// Baseline + user-added bypass entries. De-duped, preserves baseline
    /// order so a user-added duplicate doesn't shadow the system defaults.
    private static func composeExceptions() -> [String] {
        let baseline = [
            "127.0.0.1", "localhost",
            "10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16",
            "*.local",
        ]
        var seen = Set(baseline)
        var out = baseline
        for entry in ConfigStore.currentBypassIPs() {
            let trimmed = entry.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !seen.contains(trimmed) else { continue }
            seen.insert(trimmed)
            out.append(trimmed)
        }
        return out
    }

    /// Lazily creates (or returns the cached) AuthorizationRef. The first
    /// call prompts the user; subsequent calls reuse the same ref so the
    /// user isn't re-prompted on every toggle.
    private func obtainAuth() throws -> AuthorizationRef {
        if let cached = cachedAuth { return cached }

        var auth: AuthorizationRef?
        let flags: AuthorizationFlags = [.interactionAllowed, .extendRights, .preAuthorize]
        let status = AuthorizationCreate(nil, nil, flags, &auth)
        guard status == errAuthorizationSuccess, let auth else {
            throw SystemProxyError.authorization("AuthorizationCreate -> \(status)")
        }

        // Pre-authorize `system.preferences` so SCPreferencesCommitChanges
        // doesn't trigger a fresh prompt later. Granted rights stick to the
        // AuthorizationRef for its lifetime.
        var rightName = "system.preferences".cString(using: .utf8)!
        let granted: AuthorizationFlags = [.interactionAllowed, .extendRights, .preAuthorize]
        let copyStatus = rightName.withUnsafeMutableBufferPointer { buf -> OSStatus in
            var item = AuthorizationItem(
                name: buf.baseAddress!,
                valueLength: 0, value: nil, flags: 0
            )
            return withUnsafeMutablePointer(to: &item) { itemPtr in
                var rights = AuthorizationRights(count: 1, items: itemPtr)
                return AuthorizationCopyRights(auth, &rights, nil, granted, nil)
            }
        }
        if copyStatus != errAuthorizationSuccess {
            AuthorizationFree(auth, [.destroyRights])
            throw SystemProxyError.authorization("AuthorizationCopyRights system.preferences -> \(copyStatus)")
        }

        cachedAuth = auth
        return auth
    }

    private func apply(on: Bool) throws {
        let auth = try obtainAuth()

        guard let prefs = SCPreferencesCreateWithAuthorization(nil, "ChungHwa" as CFString, nil, auth) else {
            throw SystemProxyError.preferences("SCPreferencesCreateWithAuthorization returned nil")
        }
        guard let services = SCNetworkServiceCopyAll(prefs) as? [SCNetworkService] else {
            throw SystemProxyError.preferences("SCNetworkServiceCopyAll returned nil")
        }

        var touched = 0
        for service in services {
            guard SCNetworkServiceGetEnabled(service),
                  let proto = SCNetworkServiceCopyProtocol(service, kSCNetworkProtocolTypeProxies) else { continue }
            let current = (SCNetworkProtocolGetConfiguration(proto) as? [String: Any]) ?? [:]
            var next = current
            if on {
                next[kSCPropNetProxiesHTTPEnable as String]  = 1
                next[kSCPropNetProxiesHTTPProxy as String]   = host
                next[kSCPropNetProxiesHTTPPort as String]    = port
                next[kSCPropNetProxiesHTTPSEnable as String] = 1
                next[kSCPropNetProxiesHTTPSProxy as String]  = host
                next[kSCPropNetProxiesHTTPSPort as String]   = port
                next[kSCPropNetProxiesSOCKSEnable as String] = 1
                next[kSCPropNetProxiesSOCKSProxy as String]  = host
                next[kSCPropNetProxiesSOCKSPort as String]   = port
                // Bypass list = baseline (loopback + RFC1918 + .local) PLUS
                // anything the user added in Advanced > Bypass list. We always
                // overwrite so changes in the UI take effect on the next
                // toggle-cycle.
                next[kSCPropNetProxiesExceptionsList as String] = Self.composeExceptions()
            } else {
                next[kSCPropNetProxiesHTTPEnable as String]  = 0
                next[kSCPropNetProxiesHTTPSEnable as String] = 0
                next[kSCPropNetProxiesSOCKSEnable as String] = 0
            }
            if !SCNetworkProtocolSetConfiguration(proto, next as CFDictionary) {
                throw SystemProxyError.preferences("SetConfiguration failed for service")
            }
            touched += 1
        }
        guard SCPreferencesCommitChanges(prefs) else {
            throw SystemProxyError.preferences("commit failed (errno=\(SCError()))")
        }
        guard SCPreferencesApplyChanges(prefs) else {
            throw SystemProxyError.preferences("apply failed (errno=\(SCError()))")
        }
        log.info("touched \(touched, privacy: .public) services")
    }
}
