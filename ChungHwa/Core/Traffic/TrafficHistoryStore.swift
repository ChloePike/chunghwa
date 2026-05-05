import Foundation
import Observation
import OSLog

/// Long-lived traffic history. Persists per-minute totals to disk so the
/// Traffic Stats "By Hour" card can show real numbers across kernel
/// restarts. The rolling-second buffer for the live chart still lives in
/// `TrafficStore`; this store is intentionally separate because its lifetime
/// (and persistence semantics) outlives any single kernel session.
///
/// Storage: `~/Library/Application Support/ChungHwa/traffic-history.json`.
/// We keep a chronological list of up to 1440 minute buckets (24h * 60).
@Observable
@MainActor
final class TrafficHistoryStore {
    struct Bucket: Codable, Sendable, Identifiable {
        let minuteStart: Date
        var downBytes: Int
        var upBytes: Int

        var id: Date { minuteStart }
    }

    struct HourlyBucket: Codable, Sendable, Identifiable {
        let hourStart: Date
        let downBytes: Int
        let upBytes: Int

        var id: Date { hourStart }
    }

    private(set) var minutes: [Bucket] = []

    private let log = Logger(subsystem: "com.tzaigroup.chunghwa", category: "traffic-history")

    private static let maxMinutes = 1440
    private static let keepHours = 24

    init() {
        let cutoff = Date().addingTimeInterval(-Double(Self.keepHours) * 3600)
        let rows = Database.shared.loadTrafficHistory(since: cutoff)
        self.minutes = rows.map {
            Bucket(minuteStart: $0.minuteStart, downBytes: $0.down, upBytes: $0.up)
        }
        log.info("traffic-history: loaded \(self.minutes.count, privacy: .public) buckets")
    }

    // MARK: - Public API

    /// 24 entries covering the last 24 full hours up to (and including) the
    /// current hour. Hours with no samples are reported as zeros so the bar
    /// chart always has 24 slots.
    var hourly: [HourlyBucket] {
        let cal = Calendar.current
        let now = Date()
        guard let currentHourStart = cal.dateInterval(of: .hour, for: now)?.start else {
            return []
        }
        // Group samples by their hour-start once for O(n) lookup.
        var grouped: [Date: (down: Int, up: Int)] = [:]
        for b in minutes {
            guard let hour = cal.dateInterval(of: .hour, for: b.minuteStart)?.start else { continue }
            var entry = grouped[hour] ?? (0, 0)
            entry.down += b.downBytes
            entry.up += b.upBytes
            grouped[hour] = entry
        }

        var out: [HourlyBucket] = []
        out.reserveCapacity(24)
        for offset in (0..<24).reversed() {
            guard let hourStart = cal.date(byAdding: .hour, value: -offset, to: currentHourStart) else { continue }
            let entry = grouped[hourStart] ?? (0, 0)
            out.append(HourlyBucket(hourStart: hourStart, downBytes: entry.down, upBytes: entry.up))
        }
        return out
    }

    /// Fold a 1Hz mihomo sample into the current minute bucket. Each `up`/
    /// `down` value is treated as bytes transferred over that one second,
    /// so we just accumulate. Rolls into a new bucket when the wall-clock
    /// minute advances; trims the oldest entry once we exceed 24h.
    func feed(_ sample: MihomoTrafficSample, at date: Date = Date()) {
        let minute = Self.floorToMinute(date)
        var rolled = false

        if let last = minutes.last {
            if last.minuteStart == minute {
                minutes[minutes.count - 1].downBytes &+= sample.down
                minutes[minutes.count - 1].upBytes   &+= sample.up
            } else if minute > last.minuteStart {
                minutes.append(Bucket(minuteStart: minute, downBytes: sample.down, upBytes: sample.up))
                rolled = true
            } else {
                // Clock went backwards (sleep/clock-skew). Drop sample
                // rather than corrupting ordering.
                return
            }
        } else {
            minutes.append(Bucket(minuteStart: minute, downBytes: sample.down, upBytes: sample.up))
            rolled = true
        }

        if minutes.count > Self.maxMinutes {
            minutes.removeFirst(minutes.count - Self.maxMinutes)
        }

        if let current = minutes.last {
            Database.shared.upsertTrafficBucket(
                minuteStart: current.minuteStart,
                up: current.upBytes,
                down: current.downBytes
            )
        }
        if rolled {
            Database.shared.pruneTrafficHistory(keepHours: Self.keepHours)
        }
    }

    /// Wipes both in-memory state and the persisted history. Intended for a
    /// user-initiated reset from Settings; we deliberately do *not* call this
    /// on kernel stop, so the history survives restarts.
    func reset() {
        minutes.removeAll(keepingCapacity: true)
        Database.shared.deleteAllTraffic()
    }

    // MARK: - Helpers

    private static func floorToMinute(_ date: Date) -> Date {
        let cal = Calendar.current
        return cal.dateInterval(of: .minute, for: date)?.start
            ?? Date(timeIntervalSince1970: floor(date.timeIntervalSince1970 / 60) * 60)
    }
}
