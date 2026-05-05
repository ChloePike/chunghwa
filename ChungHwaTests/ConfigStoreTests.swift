import Testing
import Foundation
@testable import ChungHwa

@MainActor
@Suite(.serialized)
struct ConfigStoreTests {

    /// Snapshot/restore the UserDefaults keys ConfigStore touches so tests
    /// don't bleed into the user's real prefs. ConfigStore reads
    /// `UserDefaults.standard` directly (no DI) so suite-name isolation
    /// isn't usable here.
    private final class DefaultsSandbox {
        private let keys: [String]
        private var saved: [String: Any?] = [:]
        init() {
            self.keys = [
                ConfigStore.tunEnabledDefaultsKey,
                ConfigStore.mixedPortDefaultsKey,
                ConfigStore.dnsNameserversKey,
                ConfigStore.dnsFallbackKey,
                ConfigStore.dnsHijackKey,
                ConfigStore.dnsModeKey,
                ConfigStore.customRulesKey,
            ]
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

    // MARK: - mixed-port

    @Test func setMixedPortValid() {
        let sandbox = DefaultsSandbox()
        defer { sandbox.restore() }

        let store = ConfigStore()
        #expect(store.setMixedPort(8080))
        #expect(store.mixedPort == 8080)
        #expect(UserDefaults.standard.integer(forKey: ConfigStore.mixedPortDefaultsKey) == 8080)
    }

    @Test func setMixedPortRejectsZero() {
        let sandbox = DefaultsSandbox()
        defer { sandbox.restore() }

        let store = ConfigStore()
        let originalPort = store.mixedPort
        #expect(!store.setMixedPort(0))
        #expect(store.mixedPort == originalPort)
    }

    @Test func setMixedPortRejectsOutOfRange() {
        let sandbox = DefaultsSandbox()
        defer { sandbox.restore() }

        let store = ConfigStore()
        #expect(!store.setMixedPort(-1))
        #expect(!store.setMixedPort(65536))
        #expect(!store.setMixedPort(100_000))
    }

    @Test func setMixedPortAcceptsBoundaries() {
        let sandbox = DefaultsSandbox()
        defer { sandbox.restore() }

        let store = ConfigStore()
        #expect(store.setMixedPort(1))
        #expect(store.setMixedPort(65535))
    }

    @Test func defaultMixedPortFallback() {
        let sandbox = DefaultsSandbox()
        defer { sandbox.restore() }

        let store = ConfigStore()
        #expect(store.mixedPort == ConfigStore.defaultMixedPort)
    }

    // MARK: - DNS round-trip

    @Test func currentDNSReadsFromDefaults() {
        let sandbox = DefaultsSandbox()
        defer { sandbox.restore() }

        UserDefaults.standard.set(["1.1.1.1"], forKey: ConfigStore.dnsNameserversKey)
        UserDefaults.standard.set(["tls://8.8.8.8"], forKey: ConfigStore.dnsFallbackKey)
        UserDefaults.standard.set(false, forKey: ConfigStore.dnsHijackKey)
        UserDefaults.standard.set("fake-ip", forKey: ConfigStore.dnsModeKey)

        let prefs = ConfigStore.currentDNS()
        #expect(prefs.nameservers == ["1.1.1.1"])
        #expect(prefs.fallback == ["tls://8.8.8.8"])
        #expect(prefs.hijackEnabled == false)
        #expect(prefs.mode == "fake-ip")
    }

    @Test func currentDNSDefaultsWhenUnset() {
        let sandbox = DefaultsSandbox()
        defer { sandbox.restore() }

        let prefs = ConfigStore.currentDNS()
        #expect(prefs.nameservers == ConfigStore.defaultNameservers)
        #expect(prefs.fallback == ConfigStore.defaultFallback)
        // Hijack defaults to true when unset.
        #expect(prefs.hijackEnabled == true)
        #expect(prefs.mode == "smart")
    }

    @Test func enhancedModeMapping() {
        #expect(DNSPrefs(nameservers: [], fallback: [], hijackEnabled: true, mode: "system").enhancedMode == "redir-host")
        #expect(DNSPrefs(nameservers: [], fallback: [], hijackEnabled: true, mode: "fake-ip").enhancedMode == "fake-ip")
        #expect(DNSPrefs(nameservers: [], fallback: [], hijackEnabled: true, mode: "smart").enhancedMode == "fake-ip")
    }

    // MARK: - custom rules round-trip

    @Test func customRulesRoundTrip() {
        let sandbox = DefaultsSandbox()
        defer { sandbox.restore() }

        let store = ConfigStore()
        let rules = [
            CustomRule(match: "DOMAIN-SUFFIX,foo.com", target: "DIRECT"),
            CustomRule(match: "DOMAIN-KEYWORD,ads",    target: "REJECT"),
        ]
        store.setCustomRules(rules)

        let read = ConfigStore.currentCustomRules()
        #expect(read.count == 2)
        #expect(read[0].match == "DOMAIN-SUFFIX,foo.com")
        #expect(read[0].target == "DIRECT")
        #expect(read[1].match == "DOMAIN-KEYWORD,ads")
        #expect(read[1].target == "REJECT")
    }

    @Test func customRulesEmptyByDefault() {
        let sandbox = DefaultsSandbox()
        defer { sandbox.restore() }

        #expect(ConfigStore.currentCustomRules().isEmpty)
    }

    @Test func newStoreReadsPersistedRules() {
        let sandbox = DefaultsSandbox()
        defer { sandbox.restore() }

        let rules = [CustomRule(match: "DOMAIN,example.com", target: "PROXY")]
        if let data = try? JSONEncoder().encode(rules) {
            UserDefaults.standard.set(data, forKey: ConfigStore.customRulesKey)
        }
        let store = ConfigStore()
        #expect(store.customRules.count == 1)
        #expect(store.customRules[0].match == "DOMAIN,example.com")
    }

    // MARK: - reset preserves persistence-backed prefs

    @Test func resetDoesNotClearPersistedTUN() async {
        let sandbox = DefaultsSandbox()
        defer { sandbox.restore() }

        UserDefaults.standard.set(true, forKey: ConfigStore.tunEnabledDefaultsKey)
        let store = ConfigStore()
        #expect(store.tunEnabled == true)

        store.reset()
        // tunEnabled is a persisted user pref — must NOT be cleared by reset.
        #expect(store.tunEnabled == true)
    }
}
