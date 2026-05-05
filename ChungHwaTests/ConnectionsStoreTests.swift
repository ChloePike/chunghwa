import Testing
import Foundation
@testable import ChungHwa

@MainActor
struct ConnectionsStoreTests {

    private func conn(id: String, up: Int, down: Int) -> MihomoConnection {
        MihomoConnection(
            id: id,
            metadata: MihomoConnection.Metadata(
                network: "tcp", type: "HTTPS",
                sourceIP: "192.168.1.10", sourcePort: "1000",
                destinationIP: "1.1.1.1", destinationPort: "443",
                host: "example.com",
                process: nil, processPath: nil
            ),
            upload: up, download: down,
            start: "2026-01-01T00:00:00Z",
            chains: ["DIRECT"], rule: "Match", rulePayload: nil
        )
    }

    private func frame(_ connections: [MihomoConnection],
                       totalUp: Int = 0, totalDown: Int = 0) -> Data {
        let snap = MihomoConnectionsSnapshot(downloadTotal: totalDown,
                                             uploadTotal: totalUp,
                                             connections: connections,
                                             memory: 0)
        return try! JSONEncoder().encode(snap)
    }

    @Test func firstFramePublishesImmediatelyButRateIsZero() async {
        let store = ConnectionsStore()
        store.apply(frame: frame([conn(id: "a", up: 0, down: 0)]))
        // First frame commits synchronously (elapsed >= window since
        // lastCommit is .distantPast).
        #expect(store.connections.count == 1)
        #expect(store.connectionCount == 1)
        // No prior totals → no rate entry.
        #expect(store.rates["a"] == nil)
    }

    @Test func rateDerivedFromTwoFramesAcrossWindow() async {
        let store = ConnectionsStore()
        // Prime the store and let the coalesce window elapse so the next
        // apply commits immediately and we get a real diff.
        store.apply(frame: frame([conn(id: "a", up: 0, down: 0)]))
        try? await Task.sleep(nanoseconds: 300_000_000)
        store.apply(frame: frame([conn(id: "a", up: 0, down: 1024)]))

        // Rate should reflect ~1024 / dt B/s. dt is ~0.3s so rate ~3413 B/s
        // — verify it's positive.
        let rate = store.rates["a"]
        #expect(rate != nil)
        if let r = rate {
            #expect(r.down > 0)
            #expect(r.up == 0)
        }
    }

    @Test func uploadRateMatchesDelta() async {
        let store = ConnectionsStore()
        store.apply(frame: frame([conn(id: "a", up: 0, down: 0)]))
        try? await Task.sleep(nanoseconds: 300_000_000)
        store.apply(frame: frame([conn(id: "a", up: 8192, down: 0)]))
        let rate = store.rates["a"]
        #expect(rate != nil)
        if let r = rate {
            #expect(r.up > 0)
            #expect(r.down == 0)
        }
    }

    @Test func coalesceCollapsesBurstIntoSinglePublish() async {
        let store = ConnectionsStore()
        // Initial publish at t0.
        store.apply(frame: frame([conn(id: "a", up: 0, down: 0)]))
        let initialCount = store.connectionCount
        #expect(initialCount == 1)

        // Five rapid frames within the 250ms window — they queue up in
        // pendingFrame. Only the LATEST is committed when the deferred
        // flush fires.
        for d in [100, 200, 300, 400, 500] {
            store.apply(frame: frame([conn(id: "a", up: 0, down: d),
                                      conn(id: "b", up: 0, down: 0)]))
        }
        // Before the flush has fired, connections still reflects the
        // initial frame.
        #expect(store.connectionCount == 1)

        try? await Task.sleep(nanoseconds: 350_000_000)

        // After flush: the FINAL frame wins (count == 2, with the final
        // download value).
        #expect(store.connections.count == 2)
        #expect(store.connectionCount == 2)
        let a = store.connections.first(where: { $0.id == "a" })
        #expect(a?.download == 500)
    }

    @Test func resetClearsRateAndConnections() async {
        let store = ConnectionsStore()
        store.apply(frame: frame([conn(id: "a", up: 0, down: 0)]))
        try? await Task.sleep(nanoseconds: 300_000_000)
        store.apply(frame: frame([conn(id: "a", up: 0, down: 4096)]))
        #expect(store.rates["a"] != nil)

        store.reset()
        #expect(store.rates.isEmpty)
        #expect(store.connections.isEmpty)
        #expect(store.connectionCount == 0)
        #expect(store.downloadTotal == 0)
        #expect(store.uploadTotal == 0)
    }

    @Test func droppedConnectionNoLongerHasRate() async {
        let store = ConnectionsStore()
        store.apply(frame: frame([conn(id: "a", up: 0, down: 0),
                                  conn(id: "b", up: 0, down: 0)]))
        try? await Task.sleep(nanoseconds: 300_000_000)
        store.apply(frame: frame([conn(id: "a", up: 0, down: 1000),
                                  conn(id: "b", up: 0, down: 1000)]))
        try? await Task.sleep(nanoseconds: 300_000_000)
        // Drop "b" — the next commit should clear b's rate.
        store.apply(frame: frame([conn(id: "a", up: 0, down: 2000)]))
        #expect(store.rates["b"] == nil)
        #expect(store.connections.count == 1)
        #expect(store.connectionCount == 1)
    }

    @Test func malformedFrameIsIgnored() {
        let store = ConnectionsStore()
        store.apply(frame: frame([conn(id: "a", up: 0, down: 0)]))
        let countBefore = store.connectionCount
        // Garbage frame. With the coalesce in play this gets stashed as
        // pendingFrame and on flush the decode fails silently. Either way
        // the live state should remain consistent.
        store.apply(frame: Data("not-json".utf8))
        #expect(store.connectionCount == countBefore)
    }

    @Test func totalsTrackSnapshot() async {
        let store = ConnectionsStore()
        store.apply(frame: frame([conn(id: "a", up: 0, down: 0)],
                                 totalUp: 1234, totalDown: 5678))
        #expect(store.uploadTotal == 1234)
        #expect(store.downloadTotal == 5678)
    }
}
