import Foundation
import Observation

/// Rolling buffer of mihomo /traffic samples. Holds the last `capacity`
/// seconds for the live chart and tracks running totals for header stats.
@Observable
@MainActor
final class TrafficStore {
    struct Sample: Identifiable, Sendable {
        let id: UInt64
        let timestamp: Date
        let upBps: Int
        let downBps: Int
    }

    private(set) var samples: [Sample] = []
    private(set) var totalUp: Int = 0
    private(set) var totalDown: Int = 0
    private(set) var memoryInUse: Int = 0
    private(set) var memoryLimit: Int = 0

    let capacity: Int
    private var nextID: UInt64 = 0

    init(capacity: Int = 90) {
        self.capacity = capacity
        samples.reserveCapacity(capacity)
    }

    var current: Sample? { samples.last }
    var peakUp: Int { samples.map(\.upBps).max() ?? 0 }
    var peakDown: Int { samples.map(\.downBps).max() ?? 0 }

    func append(_ sample: MihomoTrafficSample, at date: Date = Date()) {
        nextID &+= 1
        let s = Sample(id: nextID, timestamp: date, upBps: sample.up, downBps: sample.down)
        if samples.count >= capacity {
            samples.removeFirst(samples.count - capacity + 1)
        }
        samples.append(s)
        totalUp   &+= sample.up
        totalDown &+= sample.down
    }

    func update(memory sample: MihomoMemorySample) {
        memoryInUse = sample.inuse
        memoryLimit = sample.oslimit
    }

    func reset() {
        samples.removeAll(keepingCapacity: true)
        totalUp = 0
        totalDown = 0
        memoryInUse = 0
        memoryLimit = 0
    }
}
