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

    /// `samples` is published immediately so the live chart stays accurate at
    /// 1 Hz, but the running totals only need to look "live" for header text
    /// — flushing them every 500 ms halves the redraw cost on every view that
    /// reads `totalUp` / `totalDown` (StatusBar, Overview, Stats panels).
    private static let totalsFlushWindow: TimeInterval = 0.5

    @ObservationIgnored private var pendingTotalUp: Int = 0
    @ObservationIgnored private var pendingTotalDown: Int = 0
    @ObservationIgnored private var totalsDirty: Bool = false
    @ObservationIgnored private var totalsFlushTask: Task<Void, Never>?
    @ObservationIgnored private var lastTotalsFlush: Date = .distantPast

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

        // Accumulate totals in shadow state; only republish on the flush
        // cadence so header text doesn't drag a re-render every second.
        pendingTotalUp   &+= sample.up
        pendingTotalDown &+= sample.down
        totalsDirty = true
        scheduleTotalsFlush(now: date)
    }

    private func scheduleTotalsFlush(now: Date) {
        let elapsed = now.timeIntervalSince(lastTotalsFlush)
        if elapsed >= Self.totalsFlushWindow {
            totalsFlushTask?.cancel()
            totalsFlushTask = nil
            commitTotals(at: now)
            return
        }
        // Already a flush scheduled — let it fire; new pending values will
        // be picked up when it does.
        if totalsFlushTask != nil { return }
        let delay = Self.totalsFlushWindow - elapsed
        let nanos = UInt64(max(0, delay) * 1_000_000_000)
        totalsFlushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: nanos)
            guard !Task.isCancelled else { return }
            await self?.flushTotals()
        }
    }

    private func flushTotals() {
        totalsFlushTask = nil
        guard totalsDirty else { return }
        commitTotals(at: Date())
    }

    private func commitTotals(at date: Date) {
        totalUp = pendingTotalUp
        totalDown = pendingTotalDown
        totalsDirty = false
        lastTotalsFlush = date
    }

    func update(memory sample: MihomoMemorySample) {
        memoryInUse = sample.inuse
        memoryLimit = sample.oslimit
    }

    func reset() {
        totalsFlushTask?.cancel()
        totalsFlushTask = nil
        totalsDirty = false
        pendingTotalUp = 0
        pendingTotalDown = 0
        lastTotalsFlush = .distantPast
        samples.removeAll(keepingCapacity: true)
        totalUp = 0
        totalDown = 0
        memoryInUse = 0
        memoryLimit = 0
    }
}
