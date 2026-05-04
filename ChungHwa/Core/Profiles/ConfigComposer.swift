import Foundation

/// Builds the on-disk yaml mihomo runs.
///
/// Strategy: strip any top-level `external-controller` / `secret` from the
/// user's yaml and append our own at the bottom. Earlier we relied on Go
/// yaml.v3 "last value wins" semantics, but mihomo's parser is strict about
/// duplicate keys and refuses to load when both are present.
enum ConfigComposer {
    static func compose(userYaml: String?, externalControllerHostPort: String, secret: String) -> String {
        let usingDefault = (userYaml == nil)
        let bodyRaw = userYaml ?? defaultBody

        // Only strip / inject `dns:` when the source yaml has none. A
        // subscription's DNS block is usually carefully tuned (fake-ip-filter,
        // China-bootstrap servers, geosite lists); replacing it with our
        // minimal version breaks resolution. Our DNS editor is therefore
        // effective only on the default profile (or any yaml that didn't
        // ship its own dns block).
        let userHasDNS = hasTopLevelKey(bodyRaw, key: "dns")

        let blockKeysToStrip: [String] = userHasDNS ? ["tun"] : ["tun", "dns"]
        let withoutBlocks = stripTopLevelBlocks(bodyRaw, keys: blockKeysToStrip)
        let stripped = stripTopLevelKeys(
            withoutBlocks,
            keys: ["external-controller", "secret", "mixed-port", "port", "socks-port"]
        )
        let body = trimmedTrailing(stripped)
        let tunEnabled = UserDefaults.standard.bool(forKey: ConfigStore.tunEnabledDefaultsKey)
        let mixedPort = ConfigStore.currentMixedPort
        let rulesBlock = renderRulesBlockIfNeeded(usingDefault: usingDefault)
        let dnsBlock = userHasDNS ? "" : "\n" + renderDNSBlock(ConfigStore.currentDNS())

        return """
        \(body)\(rulesBlock)

        # === ChungHwa overrides — managed by the app, do not edit ===
        mixed-port: \(mixedPort)
        external-controller: \(externalControllerHostPort)
        secret: \(secret)
        tun:
          enable: \(tunEnabled)
          stack: gvisor
          auto-route: true
          auto-detect-interface: true
          dns-hijack:
            - any:53\(dnsBlock)
        """
    }

    /// Tolerant top-level key check — used to decide whether the user's yaml
    /// already provides a block we shouldn't clobber.
    private static func hasTopLevelKey(_ yaml: String, key: String) -> Bool {
        for line in yaml.split(separator: "\n", omittingEmptySubsequences: false) {
            if matchesTopLevelKey(line, keys: [key]) { return true }
        }
        return false
    }

    /// Composed DNS block used when the source yaml has none. Emits the
    /// pieces mihomo actually needs to resolve: a `default-nameserver` block
    /// (plain UDP) so the DoH endpoints can be bootstrap-resolved, a
    /// `fake-ip-filter` glob list so common LAN hostnames don't get
    /// fake-ip'd into oblivion, plus the user-edited nameserver / fallback.
    /// The `listen: 0.0.0.0:53` line is dropped when the kernel isn't
    /// running as root — binding 53 needs privilege; emitting it without
    /// privilege makes mihomo fail to come up.
    private static func renderDNSBlock(_ prefs: DNSPrefs) -> String {
        var lines: [String] = ["dns:", "  enable: true"]
        if prefs.hijackEnabled && bundledKernelIsPrivileged() {
            lines.append("  listen: 0.0.0.0:53")
        }
        lines.append("  enhanced-mode: \(prefs.enhancedMode)")
        lines.append("  fake-ip-range: 198.18.0.1/16")
        lines.append("  default-nameserver:")
        for entry in defaultBootstrap {
            lines.append("    - \(yamlScalar(entry))")
        }
        lines.append("  fake-ip-filter:")
        for pattern in defaultFakeIPFilter {
            lines.append("    - \(yamlScalar(pattern))")
        }
        lines.append("  nameserver:")
        let ns = prefs.nameservers.isEmpty ? ConfigStore.defaultNameservers : prefs.nameservers
        for entry in ns {
            lines.append("    - \(yamlScalar(entry))")
        }
        lines.append("  fallback:")
        let fb = prefs.fallback.isEmpty ? ConfigStore.defaultFallback : prefs.fallback
        for entry in fb {
            lines.append("    - \(yamlScalar(entry))")
        }
        return lines.joined(separator: "\n")
    }

    /// Quick check that the active mihomo binary is setuid-root, mirroring
    /// `KernelPrivilegeHelper.isPrivileged` without the dependency. Returns
    /// false defensively when the path can't be resolved.
    private static func bundledKernelIsPrivileged() -> Bool {
        let candidates: [String?] = [
            UserDefaults.standard.string(forKey: "KernelCustomBinaryPath"),
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first?.appendingPathComponent("ChungHwa/kernel/mihomo").path,
            Bundle.main.resourceURL?.appendingPathComponent("mihomo").path,
        ]
        for case let p? in candidates where FileManager.default.fileExists(atPath: p) {
            var st = stat()
            guard stat(p, &st) == 0 else { continue }
            if st.st_uid == 0 && (st.st_mode & UInt16(S_ISUID)) != 0 { return true }
            return false
        }
        return false
    }

    /// Plain-UDP DNS used to bootstrap DoH/DoT endpoint resolution.
    private static let defaultBootstrap: [String] = [
        "223.5.5.5",
        "119.29.29.29",
    ]

    /// Common LAN / device-discovery hostnames that should NOT receive
    /// fake-ip — return real IPs instead, otherwise printers / AirPlay /
    /// captive portals break.
    private static let defaultFakeIPFilter: [String] = [
        "*.lan",
        "*.local",
        "+.market.xiaomi.com",
        "localhost.ptlogin2.qq.com",
        "*.msftconnecttest.com",
        "*.msftncsi.com",
        "+.in-addr.arpa",
        "+.ip6.arpa",
        "time.*.com",
        "ntp.*.com",
        "+.apple.com",
        "+.icloud.com",
    ]

    /// When the user is on the default profile (no source yaml), inject the
    /// persisted custom rules as the entire `rules:` block. We deliberately
    /// don't try to merge with a user-supplied yaml — the simplest behavior
    /// that does the right thing: custom rules apply on the default profile,
    /// users who bring their own yaml manage their rules in that yaml.
    private static func renderRulesBlockIfNeeded(usingDefault: Bool) -> String {
        guard usingDefault else { return "" }
        let rules = ConfigStore.currentCustomRules()
        guard !rules.isEmpty else {
            return "\nrules:\n  - MATCH,DIRECT"
        }
        var lines: [String] = ["", "rules:"]
        for r in rules {
            let match = r.match.trimmingCharacters(in: .whitespaces)
            let target = r.target.trimmingCharacters(in: .whitespaces)
            guard !match.isEmpty, !target.isEmpty else { continue }
            lines.append("  - \(match),\(target)")
        }
        // Always end with a catch-all so traffic without a matching custom
        // rule still has a defined disposition.
        lines.append("  - MATCH,DIRECT")
        return lines.joined(separator: "\n")
    }

    private static func yamlScalar(_ s: String) -> String {
        // Quote anything containing characters that YAML treats specially in
        // a plain scalar. Most resolver URLs fit the plain form, but tls://
        // and similar schemes are clean too — we just quote everything to
        // be safe and to keep the composed output unambiguous.
        let escaped = s.replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    /// Remove every top-level (zero-indent) line that defines one of the
    /// listed keys. Naive, line-based, comment-tolerant. Doesn't handle
    /// multi-line block scalars or anchors for these keys, but
    /// `external-controller` and `secret` are always inline scalars in
    /// practice.
    private static func stripTopLevelKeys(_ yaml: String, keys: [String]) -> String {
        let lines = yaml.split(separator: "\n", omittingEmptySubsequences: false)
        var out: [Substring] = []
        out.reserveCapacity(lines.count)
        for line in lines {
            if matchesTopLevelKey(line, keys: keys) { continue }
            out.append(line)
        }
        return out.joined(separator: "\n")
    }

    /// Remove a top-level block-style mapping (`key:` followed by indented
    /// child lines) for any key in `keys`. The block ends at the next
    /// non-empty line at column 0. Used for `tun:` which carries nested
    /// children (`stack`, `auto-route`, …).
    private static func stripTopLevelBlocks(_ yaml: String, keys: [String]) -> String {
        let lines = yaml.split(separator: "\n", omittingEmptySubsequences: false)
        var out: [Substring] = []
        out.reserveCapacity(lines.count)
        var skipping = false
        for line in lines {
            if skipping {
                if line.isEmpty { continue }
                if let first = line.first, first.isWhitespace { continue }
                skipping = false
            }
            if matchesTopLevelKey(line, keys: keys) {
                skipping = true
                continue
            }
            out.append(line)
        }
        return out.joined(separator: "\n")
    }

    private static func matchesTopLevelKey(_ line: Substring, keys: [String]) -> Bool {
        // Top-level: must start at column 0 with a non-whitespace character.
        guard let first = line.first, !first.isWhitespace else { return false }
        guard let colon = line.firstIndex(of: ":") else { return false }
        let key = line[..<colon].trimmingCharacters(in: .whitespaces)
        return keys.contains(key)
    }

    private static let defaultBody: String = """
    mixed-port: 7890
    allow-lan: false
    mode: rule
    log-level: info
    """

    private static func trimmedTrailing(_ s: String) -> String {
        var s = s
        while let last = s.last, last == "\n" || last == " " || last == "\t" || last == "\r" {
            s.removeLast()
        }
        return s
    }
}
