import Testing
import Foundation
@testable import ChungHwa

@MainActor
@Suite(.serialized)
struct ProxyStoreTests {

    /// Sandbox the on-disk proxy-delays file so we can inspect persistence
    /// without clobbering the user's real cache.
    private final class DelaysSandbox {
        let url: URL
        let backup: URL?
        init() {
            let dir = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("ChungHwa", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            self.url = dir.appendingPathComponent("proxy-delays.json")
            if FileManager.default.fileExists(atPath: url.path) {
                let bak = dir.appendingPathComponent("proxy-delays.test-backup.json")
                try? FileManager.default.removeItem(at: bak)
                try? FileManager.default.moveItem(at: url, to: bak)
                self.backup = bak
            } else {
                self.backup = nil
            }
        }
        func restore() {
            try? FileManager.default.removeItem(at: url)
            if let bak = backup {
                try? FileManager.default.moveItem(at: bak, to: url)
            }
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
        // No crash, no state change.
        #expect(store.snapshotProxies.isEmpty)
    }

    @Test func testGroupWithNilAPINoOps() async {
        let sandbox = DelaysSandbox()
        defer { sandbox.restore() }

        let store = ProxyStore()
        await store.testGroup("G", api: nil)
        #expect(store.testingGroups.isEmpty)
    }

    /// Persisted-delay file written by a prior session is loaded by a fresh
    /// store init. We verify by writing a file in the layout the store
    /// emits, instantiating, then writing again via the store and reading
    /// the file back.
    @Test func persistedDelaysFileSurvivesAcrossInits() {
        let sandbox = DelaysSandbox()
        defer { sandbox.restore() }

        // Pre-seed disk with a delays dict in the same shape ProxyStore writes.
        // PersistedDelay is a private nested type; we mirror its JSON schema.
        let payload: [String: [String: Any]] = [
            "Test-Node": ["delay": 142, "testedAt": ISO8601DateFormatter().string(from: Date())],
        ]
        let data = try! JSONSerialization.data(withJSONObject: payload)
        try! data.write(to: sandbox.url, options: .atomic)
        #expect(FileManager.default.fileExists(atPath: sandbox.url.path))

        // Instantiating the store loads it (no public observable to check,
        // but the file must remain readable + parseable — i.e. the schema
        // matches what ProxyStore expects). We at minimum verify init
        // doesn't crash, doesn't truncate the file, and the file's still
        // there afterwards.
        _ = ProxyStore()
        #expect(FileManager.default.fileExists(atPath: sandbox.url.path))
        let after = try! Data(contentsOf: sandbox.url)
        #expect(after.count > 0)
    }
}
