import Testing
import Foundation
@testable import ChungHwa

@MainActor
struct GeoIPStoreTests {

    // MARK: - flagEmoji

    @Test func flagEmojiUS() {
        #expect(GeoIPStore.flagEmoji(iso: "US") == "🇺🇸")
    }

    @Test func flagEmojiCN() {
        #expect(GeoIPStore.flagEmoji(iso: "CN") == "🇨🇳")
    }

    @Test func flagEmojiJP() {
        #expect(GeoIPStore.flagEmoji(iso: "JP") == "🇯🇵")
    }

    @Test func flagEmojiAcceptsLowercase() {
        // Implementation uppercases first → should still produce a flag.
        #expect(GeoIPStore.flagEmoji(iso: "us") == "🇺🇸")
    }

    @Test func flagEmojiThreeLetterReturnsEmpty() {
        #expect(GeoIPStore.flagEmoji(iso: "USA") == "")
    }

    @Test func flagEmojiEmptyReturnsEmpty() {
        #expect(GeoIPStore.flagEmoji(iso: "") == "")
    }

    @Test func flagEmojiNonAsciiReturnsEmpty() {
        // Two non-ASCII chars: not regional-indicator-eligible → "" by guard.
        #expect(GeoIPStore.flagEmoji(iso: "中文") == "")
    }

    @Test func flagEmojiLanSentinel() {
        #expect(GeoIPStore.flagEmoji(iso: "LAN") == "🏠")
    }

    // MARK: - isPrivateOrLoopback

    @Test func privateRanges() {
        #expect(GeoIPStore.isPrivateOrLoopback("10.0.0.1"))
        #expect(GeoIPStore.isPrivateOrLoopback("127.0.0.1"))
        #expect(GeoIPStore.isPrivateOrLoopback("169.254.1.1"))
        #expect(GeoIPStore.isPrivateOrLoopback("172.16.0.1"))
        #expect(GeoIPStore.isPrivateOrLoopback("172.31.255.254"))
        #expect(GeoIPStore.isPrivateOrLoopback("192.168.1.1"))
        #expect(GeoIPStore.isPrivateOrLoopback("100.64.0.1"))
        #expect(GeoIPStore.isPrivateOrLoopback("::1"))
        #expect(GeoIPStore.isPrivateOrLoopback("fe80::1"))
        #expect(GeoIPStore.isPrivateOrLoopback("fc00::1"))
        #expect(GeoIPStore.isPrivateOrLoopback("fd12:3456::1"))
    }

    @Test func publicRanges() {
        #expect(!GeoIPStore.isPrivateOrLoopback("8.8.8.8"))
        #expect(!GeoIPStore.isPrivateOrLoopback("1.1.1.1"))
        #expect(!GeoIPStore.isPrivateOrLoopback("172.32.0.1"))   // outside 16..31
        #expect(!GeoIPStore.isPrivateOrLoopback("100.128.0.1"))  // outside CGNAT range
        #expect(!GeoIPStore.isPrivateOrLoopback("2001:4860:4860::8888"))
    }

    // MARK: - country(for:)

    @Test func countryForPrivateIPCachesLanSentinel() {
        let store = GeoIPStore()
        let result = store.country(for: "192.168.1.1")
        #expect(result == "LAN")
        // Subsequent call hits the cache.
        #expect(store.country(for: "192.168.1.1") == "LAN")
    }

    @Test func countryForEmptyReturnsNil() {
        let store = GeoIPStore()
        #expect(store.country(for: "") == nil)
    }

    @Test func countryForPublicIPMissesAndQueues() {
        let store = GeoIPStore()
        // Cache doesn't have this IP → returns nil and queues for batch
        // lookup. We don't await the network — just verify the queueing
        // contract. Use an IP that's definitively public-scoped but won't
        // hit the network during the test (we never await flushPending).
        // First make sure the seed cache isn't already pre-populated for
        // this IP from a previous run.
        let probe = "203.0.113.42"  // TEST-NET-3 (RFC5737), guaranteed public-scope-shaped
        if store.countryByIP[probe] != nil { return }
        let r = store.country(for: probe)
        #expect(r == nil)
        #expect(store.pendingIPs.contains(probe))
    }

    @Test func resolveBulkSeparatesLanFromPublic() {
        let store = GeoIPStore()
        store.resolve(ips: ["192.168.1.1", "10.0.0.5"])
        // Private addresses got the LAN sentinel synchronously.
        #expect(store.countryByIP["192.168.1.1"] == "LAN")
        #expect(store.countryByIP["10.0.0.5"] == "LAN")
        // No pending entries for them.
        #expect(!store.pendingIPs.contains("192.168.1.1"))
        #expect(!store.pendingIPs.contains("10.0.0.5"))
    }

    @Test func resetCancelsPendingButPreservesCache() {
        let store = GeoIPStore()
        _ = store.country(for: "192.168.5.5")
        // Use a TEST-NET-1 address — guaranteed not in any production cache.
        _ = store.country(for: "192.0.2.123")
        #expect(!store.pendingIPs.isEmpty)
        store.reset()
        #expect(store.pendingIPs.isEmpty)
        // Cached entries (the LAN sentinel for the 192.168 lookup) are
        // intentionally preserved across reset.
        #expect(store.countryByIP["192.168.5.5"] == "LAN")
    }
}
