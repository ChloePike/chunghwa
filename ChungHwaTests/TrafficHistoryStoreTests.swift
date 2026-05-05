import Testing
import Foundation
@testable import ChungHwa

@MainActor
@Suite(.serialized)
struct TrafficHistoryStoreTests {

    /// Snapshot + restore the traffic_history table around each test so we
    /// don't clobber the user's real history.
    @MainActor
    private final class HistorySandbox {
        let backup: [(minuteStart: Date, up: Int, down: Int)]
        init() {
            self.backup = Database.shared.loadTrafficHistory(
                since: Date(timeIntervalSince1970: 0))
            Database.shared.deleteAllTraffic()
        }
        func restore() {
            Database.shared.deleteAllTraffic()
            for row in backup {
                Database.shared.upsertTrafficBucket(
                    minuteStart: row.minuteStart, up: row.up, down: row.down)
            }
        }
    }

    @Test func sameMinuteSamplesAccumulateInOneBucket() {
        let sandbox = HistorySandbox()
        defer { sandbox.restore() }

        let store = TrafficHistoryStore()
        let t = Date(timeIntervalSince1970: 1_700_000_000)
        store.feed(MihomoTrafficSample(up: 10, down: 100), at: t)
        store.feed(MihomoTrafficSample(up: 5,  down: 50),  at: t.addingTimeInterval(15))
        store.feed(MihomoTrafficSample(up: 3,  down: 30),  at: t.addingTimeInterval(45))

        #expect(store.minutes.count == 1)
        let b = store.minutes[0]
        #expect(b.upBytes == 18)
        #expect(b.downBytes == 180)
    }

    @Test func minuteBoundaryCreatesNewBucket() {
        let sandbox = HistorySandbox()
        defer { sandbox.restore() }

        let store = TrafficHistoryStore()
        // Pin to a known minute boundary then advance past it.
        let cal = Calendar.current
        let t = cal.dateInterval(of: .minute, for: Date(timeIntervalSince1970: 1_700_000_000))!.start

        store.feed(MihomoTrafficSample(up: 1, down: 1), at: t)
        store.feed(MihomoTrafficSample(up: 2, down: 2), at: t.addingTimeInterval(30))
        store.feed(MihomoTrafficSample(up: 3, down: 3), at: t.addingTimeInterval(61))   // next minute
        store.feed(MihomoTrafficSample(up: 4, down: 4), at: t.addingTimeInterval(125))  // +2 min

        #expect(store.minutes.count == 3)
        #expect(store.minutes[0].upBytes == 3)   // 1 + 2 in minute 0
        #expect(store.minutes[1].upBytes == 3)
        #expect(store.minutes[2].upBytes == 4)
    }

    @Test func backwardsClockDropsSample() {
        let sandbox = HistorySandbox()
        defer { sandbox.restore() }

        let store = TrafficHistoryStore()
        let t = Date(timeIntervalSince1970: 1_700_000_000)
        store.feed(MihomoTrafficSample(up: 10, down: 10), at: t)
        // Earlier minute — should be dropped.
        store.feed(MihomoTrafficSample(up: 99, down: 99), at: t.addingTimeInterval(-120))
        #expect(store.minutes.count == 1)
        #expect(store.minutes[0].upBytes == 10)
    }

    @Test func hourlyHas24SlotsEvenWhenEmpty() {
        let sandbox = HistorySandbox()
        defer { sandbox.restore() }

        let store = TrafficHistoryStore()
        #expect(store.hourly.count == 24)
        for h in store.hourly {
            #expect(h.upBytes == 0)
            #expect(h.downBytes == 0)
        }
    }

    @Test func hourlyAggregatesAcrossMinutesInSameHour() {
        let sandbox = HistorySandbox()
        defer { sandbox.restore() }

        let store = TrafficHistoryStore()
        let cal = Calendar.current
        // Use the current hour so the bucket falls inside the 24-slot window.
        let now = Date()
        let hourStart = cal.dateInterval(of: .hour, for: now)!.start

        // Feed three different minutes in the same hour.
        store.feed(MihomoTrafficSample(up: 10, down: 100),
                   at: hourStart.addingTimeInterval(60))
        store.feed(MihomoTrafficSample(up: 20, down: 200),
                   at: hourStart.addingTimeInterval(120))
        store.feed(MihomoTrafficSample(up: 30, down: 300),
                   at: hourStart.addingTimeInterval(180))

        let hourly = store.hourly
        // The current hour is the last entry.
        let last = hourly.last
        #expect(last?.upBytes == 60)
        #expect(last?.downBytes == 600)
    }
}
