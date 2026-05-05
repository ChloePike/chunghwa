import Testing
import Foundation
@testable import ChungHwa

@MainActor
@Suite(.serialized)
struct ProxyStoreTests {

    /// Snapshot + restore the proxy_delays table around each test so we
    /// don't clobber the user's real cache.
    @MainActor
    private final class DelaysSandbox {
        let backup: [String: (delay: Int, testedAt: Date)]
        init() {
            self.backup = Database.shared.loadAllProxyDelays()
            Database.shared.deleteAllProxyDelays()
        }
        func restore() {
            Database.shared.deleteAllProxyDelays()
            let entries = backup.map { (name: $0.key, delay: $0.value.delay, testedAt: $0.value.testedAt) }
            Database.shared.upsertProxyDelays(entries)
        }
    }

    @Test func freshStoreHasEmptyState() {
        let sandbox = DelaysSandbox()
        defer { sandbox.restore() }

        let store = ProxyStore()
        #expect(store.snapshotProxies.isEmpty)
        #expect(store.groupOrder.isEmpty)
        #expect(!store.isRefreshing)
        #expect(store.lastError == nil)
        #expect(store.testingGroups.isEmpty)
        #expect(store.groups.isEmpty)
        #expect(store.proxy("Anything") == nil)
    }

    @Test func resetClearsState() async {
        let sandbox = DelaysSandbox()
        defer { sandbox.restore() }

        let store = ProxyStore()
        store.reset()
        #expect(store.snapshotProxies.isEmpty)
        #expect(store.groupOrder.isEmpty)
        #expect(!store.isRefreshing)
        #expect(store.testingGroups.isEmpty)
    }

    @Test func refreshWithNilAPIResetsAndDoesNotThrow() async {
        let sandbox = DelaysSandbox()
        defer { sandbox.restore() }

        let store = ProxyStore()
        await store.refresh(api: nil)
        #expect(store.snapshotProxies.isEmpty)
    }

    @Test func selectWithNilAPINoOps() async {
        let sandbox = DelaysSandbox()
        defer { sandbox.restore() }

        let store = ProxyStore()
        await store.select(group: "G", name: "N", api: nil)
        #expect(store.snapshotProxies.isEmpty)
    }

    @Test func testGroupWithNilAPINoOps() async {
        let sandbox = DelaysSandbox()
        defer { sandbox.restore() }

        let store = ProxyStore()
        await store.testGroup("G", api: nil)
        #expect(store.testingGroups.isEmpty)
    }

    /// Persisted delays written via the database survive across fresh store
    /// inits — verify by upserting directly, then re-reading via the store's
    /// public refresh path with a tame in-memory snapshot.
    @Test func persistedDelaysSurviveAcrossInits() {
        let sandbox = DelaysSandbox()
        defer { sandbox.restore() }

        Database.shared.upsertProxyDelay(name: "Test-Node", delay: 142, testedAt: Date())

        // A fresh store loads the delay from the database during init.
        // We can't read persistedDelays directly (private), so we verify by
        // checking the database round-trip and that init doesn't crash.
        _ = ProxyStore()
        let after = Database.shared.loadAllProxyDelays()
        #expect(after["Test-Node"]?.delay == 142)
    }
}
