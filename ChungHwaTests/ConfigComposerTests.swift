import Testing
import Foundation
@testable import ChungHwa

@MainActor
@Suite(.serialized)
struct ConfigComposerTests {

    /// `ConfigComposer.compose` reads UserDefaults at call time (mixed-port,
    /// custom rules, DNS prefs, TUN). Snapshot the keys we touch so tests
    /// don't bleed into each other or the user's real prefs.
    private final class DefaultsSandbox {
        private let keys = [
            ConfigStore.tunEnabledDefaultsKey,
            ConfigStore.mixedPortDefaultsKey,
            ConfigStore.dnsNameserversKey,
            ConfigStore.dnsFallbackKey,
            ConfigStore.dnsHijackKey,
            ConfigStore.dnsModeKey,
            ConfigStore.customRulesKey,
        ]
        private var saved: [String: Any?] = [:]

        init() {
            for k in keys { saved[k] = UserDefaults.standard.object(forKey: k) }
            for k in keys { UserDefaults.standard.removeObject(forKey: k) }
        }

        func restore() {
            for k in keys {
                if let v = saved[k], let unwrapped = v {
                    UserDefaults.standard.set(unwrapped, forKey: k)
                } else {
                    UserDefaults.standard.removeObject(forKey: k)
                }
            }
        }
    }

    // MARK: - default profile (no user yaml)

    @Test func defaultProfileEmitsRequiredOverrides() {
        let sandbox = DefaultsSandbox()
        defer { sandbox.restore() }

        let yaml = ConfigComposer.compose(userYaml: nil,
                                          externalControllerHostPort: "127.0.0.1:9090",
                                          secret: "abc123")

        // Override block lands at the bottom with mixed-port, ec, secret.
        #expect(yaml.contains("mixed-port: 7890"))
        #expect(yaml.contains("external-controller: 127.0.0.1:9090"))
        #expect(yaml.contains("secret: abc123"))
        // tun: block is always injected (we always inject ours).
        #expect(yaml.contains("tun:"))
        #expect(yaml.contains("stack: gvisor"))
        // No user yaml → DNS block is injected.
        #expect(yaml.contains("dns:"))
        #expect(yaml.contains("enhanced-mode: "))
        #expect(yaml.contains("fake-ip-range: 198.18.0.1/16"))
    }

    @Test func defaultProfileWithoutCustomRulesEmitsCatchAll() {
        let sandbox = DefaultsSandbox()
        defer { sandbox.restore() }

        let yaml = ConfigComposer.compose(userYaml: nil,
                                          externalControllerHostPort: "127.0.0.1:9090",
                                          secret: "s")
        #expect(yaml.contains("rules:"))
        #expect(yaml.contains("- MATCH,DIRECT"))
    }

    @Test func customRulesRenderOnDefaultProfileWithCatchAll() {
        let sandbox = DefaultsSandbox()
        defer { sandbox.restore() }

        let rules = [
            CustomRule(match: "DOMAIN-SUFFIX,example.com", target: "DIRECT"),
            CustomRule(match: "DOMAIN-KEYWORD,ads",        target: "REJECT"),
        ]
        let data = try! JSONEncoder().encode(rules)
        UserDefaults.standard.set(data, forKey: ConfigStore.customRulesKey)

        let yaml = ConfigComposer.compose(userYaml: nil,
                                          externalControllerHostPort: "127.0.0.1:9090",
                                          secret: "s")
        #expect(yaml.contains("- DOMAIN-SUFFIX,example.com,DIRECT"))
        #expect(yaml.contains("- DOMAIN-KEYWORD,ads,REJECT"))
        // Catch-all is always appended after user rules.
        let rulesSection = yaml.components(separatedBy: "rules:").last ?? ""
        #expect(rulesSection.contains("- MATCH,DIRECT"))
    }

    // MARK: - user yaml: DNS preservation

    @Test func userDNSBlockIsPreserved() {
        let sandbox = DefaultsSandbox()
        defer { sandbox.restore() }

        let userYaml = """
        mixed-port: 7891
        mode: rule
        dns:
          enable: true
          enhanced-mode: redir-host
          nameserver:
            - tls://1.1.1.1
        rules:
          - MATCH,DIRECT
        """

        let yaml = ConfigComposer.compose(userYaml: userYaml,
                                          externalControllerHostPort: "127.0.0.1:9090",
                                          secret: "s")
        // User's dns block stays.
        #expect(yaml.contains("enhanced-mode: redir-host"))
        #expect(yaml.contains("tls://1.1.1.1"))
        // We do NOT inject our DNS block — the only `dns:` line is the user's,
        // not ours. Count occurrences:
        let dnsCount = yaml.components(separatedBy: "\ndns:").count - 1
        #expect(dnsCount == 1)
        // Our default-bootstrap servers must not be appended (regression
        // check for the recent fix).
        #expect(!yaml.contains("default-nameserver:"))
    }

    @Test func userDNSAbsentInjectsOurBlock() {
        let sandbox = DefaultsSandbox()
        defer { sandbox.restore() }

        let userYaml = """
        mixed-port: 7891
        mode: rule
        rules:
          - MATCH,DIRECT
        """

        let yaml = ConfigComposer.compose(userYaml: userYaml,
                                          externalControllerHostPort: "127.0.0.1:9090",
                                          secret: "s")
        #expect(yaml.contains("dns:"))
        #expect(yaml.contains("default-nameserver:"))
        #expect(yaml.contains("fake-ip-filter:"))
    }

    // MARK: - user yaml: TUN stripping

    @Test func userTunBlockIsStripped() {
        let sandbox = DefaultsSandbox()
        defer { sandbox.restore() }

        let userYaml = """
        mixed-port: 7891
        mode: rule
        tun:
          enable: true
          stack: system
          auto-route: false
        rules:
          - MATCH,DIRECT
        """

        let yaml = ConfigComposer.compose(userYaml: userYaml,
                                          externalControllerHostPort: "127.0.0.1:9090",
                                          secret: "s")
        // User's stack: system must be gone — we always inject gvisor.
        #expect(!yaml.contains("stack: system"))
        #expect(yaml.contains("stack: gvisor"))
        // Our tun: block is the only one.
        let tunCount = yaml.components(separatedBy: "\ntun:").count - 1
        #expect(tunCount == 1)
    }

    // MARK: - user yaml: port stripping

    @Test func userPortsAreStrippedOursWins() {
        let sandbox = DefaultsSandbox()
        defer { sandbox.restore() }

        UserDefaults.standard.set(8765, forKey: ConfigStore.mixedPortDefaultsKey)

        let userYaml = """
        mixed-port: 1234
        port: 5678
        socks-port: 9012
        mode: rule
        """

        let yaml = ConfigComposer.compose(userYaml: userYaml,
                                          externalControllerHostPort: "127.0.0.1:9090",
                                          secret: "s")
        #expect(!yaml.contains("mixed-port: 1234"))
        #expect(!yaml.contains("port: 5678"))
        #expect(!yaml.contains("socks-port: 9012"))
        #expect(yaml.contains("mixed-port: 8765"))
    }

    // MARK: - top-level matcher edge cases

    @Test func indentedTunInsideOtherBlockIsNotStripped() {
        let sandbox = DefaultsSandbox()
        defer { sandbox.restore() }

        // A `tun:` that's actually a child of a different block (non-standard
        // but the matcher must not false-positive on indentation).
        let userYaml = """
        mode: rule
        proxy-providers:
          some-provider:
            tun: notatun
            url: https://example.com
        dns:
          enable: false
        """

        let yaml = ConfigComposer.compose(userYaml: userYaml,
                                          externalControllerHostPort: "127.0.0.1:9090",
                                          secret: "s")
        // The indented `tun: notatun` survives — it's a child key, not a
        // top-level block.
        #expect(yaml.contains("tun: notatun"))
        // Our top-level tun: block is still appended.
        #expect(yaml.contains("stack: gvisor"))
    }

    @Test func customRulesIgnoredWhenUserYamlPresent() {
        let sandbox = DefaultsSandbox()
        defer { sandbox.restore() }

        let rules = [CustomRule(match: "DOMAIN-SUFFIX,foo.com", target: "DIRECT")]
        UserDefaults.standard.set(try! JSONEncoder().encode(rules),
                                  forKey: ConfigStore.customRulesKey)

        let userYaml = """
        mode: rule
        rules:
          - MATCH,DIRECT
        """
        let yaml = ConfigComposer.compose(userYaml: userYaml,
                                          externalControllerHostPort: "127.0.0.1:9090",
                                          secret: "s")
        // Custom rules apply only on the default profile.
        #expect(!yaml.contains("DOMAIN-SUFFIX,foo.com"))
    }
}
