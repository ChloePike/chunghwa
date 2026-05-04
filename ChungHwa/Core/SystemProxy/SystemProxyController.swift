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
/// Modifying network preferences requires admin authorization, prompted by
/// the system the first time `enable()` or `disable()` runs.
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

    private let log = Logger(subsystem: "com.tzaigroup.chunghwa", category: "systemProxy")

    init() {
        self.enabled = currentlyEnabled()
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

    private func apply(on: Bool) throws {
        var auth: AuthorizationRef?
        let flags: AuthorizationFlags = [.interactionAllowed, .extendRights, .preAuthorize]
        let status = AuthorizationCreate(nil, nil, flags, &auth)
        guard status == errAuthorizationSuccess, let auth else {
            throw SystemProxyError.authorization("AuthorizationCreate -> \(status)")
        }
        defer { AuthorizationFree(auth, []) }

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
                // Bypass localhost & RFC1918 — leave any existing exception list alone if present.
                if next[kSCPropNetProxiesExceptionsList as String] == nil {
                    next[kSCPropNetProxiesExceptionsList as String] = [
                        "127.0.0.1", "localhost",
                        "10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16",
                        "*.local",
                    ]
                }
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
