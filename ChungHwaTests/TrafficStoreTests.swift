import Testing
import Foundation
@testable import ChungHwa

@MainActor
struct TrafficStoreTests {

    @Test func appendUpdatesSamplesAndCurrent() {
        let store = TrafficStore(capacity: 10)
        store.append(MihomoTrafficSample(up: 100, down: 200))
        #expect(store.samples.count == 1)
        let cur = store.current
        #expect(cur?.upBps == 100)
        #expect(cur?.downBps == 200)
    }

    @Test func peakReflectsMaxInRing() {
        let store = TrafficStore(capacity: 10)
        store.append(MihomoTrafficSample(up: 50, down: 100))
        store.append(MihomoTrafficSample(up: 250, down: 80))
        store.append(MihomoTrafficSample(up: 120, down: 400))
        #expect(store.peakUp == 250)
        #expect(store.peakDown == 400)
    }

    @Test func capacityCapsRing() {
        let cap = 5
        let store = TrafficStore(capacity: cap)
        for i in 1...10 {
            store.append(MihomoTrafficSample(up: i, down: i * 2))
        }
        #expect(store.samples.count == cap)
        // The oldest entries got dropped — the first remaining sample is
        // from iteration 6 (up=6).
        #expect(store.samples.first?.upBps == 6)
        #expect(store.samples.last?.upBps == 10)
    }

    @Test func resetClearsEverything() {
        let store = TrafficStore(capacity: 10)
        store.append(MihomoTrafficSample(up: 100, down: 200))
        store.update(memory: MihomoMemorySample(inuse: 1024, oslimit: 4096))
        #expect(store.memoryInUse == 1024)
        #expect(store.memoryLimit == 4096)

        store.reset()
        #expect(store.samples.isEmpty)
        #expect(store.memoryInUse == 0)
        #expect(store.memoryLimit == 0)
        #expect(store.totalUp == 0)
        #expect(store.totalDown == 0)
        #expect(store.current == nil)
    }

    @Test func memorySampleStored() {
        let store = TrafficStore()
        store.update(memory: MihomoMemorySample(inuse: 12_345, oslimit: 0))
        #expect(store.memoryInUse == 12_345)
        #expect(store.memoryLimit == 0)
    }

    @Test func defaultCapacityIs90() {
        let store = TrafficStore()
        #expect(store.capacity == 90)
    }
}
