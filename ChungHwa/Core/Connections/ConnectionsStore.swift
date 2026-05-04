import Foundation
import Observation
import OSLog

/// Per-connection live rate (bytes / second), derived by diffing
/// `upload`/`download` totals between consecutive coalesced snapshots.
/// Both fields are clamped to ≥0 so a counter reset (or a connection
/// being recycled with the same id) doesn't render a negative spike.
struct ConnectionRate: Sendable, Equatable {
    let up: Int
    let down: Int

    static let zero = ConnectionRate(up: 0, down: 0)
}

@Observable
@MainActor
final class ConnectionsStore {
    private(set) var connections: [MihomoConnection] = []
    private(set) var downloadTotal: Int = 0
    private(set) var uploadTotal: Int = 0
    /// Per-connection bytes/second derived from the last two commits.
    /// Keys are connection ids; entries vanish when the connection drops.
    private(set) var rates: [String: ConnectionRate] = [:]

    private let log = Logger(subsystem: "com.tzaigroup.chunghwa", category: "connections")

    /// Minimum gap between published snapshots. Mihomo's /connections stream
    /// can burst several frames within a few hundred ms when traffic spikes;
    /// 250 ms is below the perceptible-flicker threshold and still keeps the
    /// list feeling live, while collapsing bursts into a single SwiftUI redraw.
    private static let coalesceWindow: TimeInterval = 0.25

    @ObservationIgnored private var pendingSnapshot: MihomoConnectionsSnapshot?
    @ObservationIgnored private var coalesceTask: Task<Void, Never>?
    @ObservationIgnored private var lastCommit: Date = .distantPast
    /// Last committed (upload, download) byte totals per connection id.
    /// Used to diff against the next commit to derive bytes/second.
    @ObservationIgnored private var lastTotals: [String: (up: Int, down: Int)] = [:]

    func apply(_ snapshot: MihomoConnectionsSnapshot) {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastCommit)
        if elapsed >= Self.coalesceWindow {
            // Far enough past the last publish — commit immediately and drop
            // any in-flight deferred snapshot (this one supersedes it).
            coalesceTask?.cancel()
            coalesceTask = nil
            pendingSnapshot = nil
            commit(snapshot, at: now)
            return
        }

        // Within the coalesce window: stash the freshest snapshot and
        // (re)schedule a flush at lastCommit + window.
        pendingSnapshot = snapshot
        coalesceTask?.cancel()
        let delay = Self.coalesceWindow - elapsed
        let nanos = UInt64(max(0, delay) * 1_000_000_000)
        coalesceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: nanos)
            guard !Task.isCancelled else { return }
            await self?.flushPending()
        }
    }

    private func flushPending() {
        guard let snapshot = pendingSnapshot else { return }
        pendingSnapshot = nil
        coalesceTask = nil
        commit(snapshot, at: Date())
    }

    private func commit(_ snapshot: MihomoConnectionsSnapshot, at date: Date) {
        let nextConnections = snapshot.connections ?? []

        // Diff each connection's byte counters against the last commit to
        // derive bytes/second. First sighting of a connection has no prior
        // sample, so its rate is zero until the next commit.
        let dt = date.timeIntervalSince(lastCommit)
        var nextRates: [String: ConnectionRate] = [:]
        var nextTotals: [String: (up: Int, down: Int)] = [:]
        nextRates.reserveCapacity(nextConnections.count)
        nextTotals.reserveCapacity(nextConnections.count)

        // dt > 0.05 guards against a degenerate first commit where lastCommit
        // is .distantPast → dt is huge → rate ~0, fine; AND a tight retry
        // commit where dt is near zero → would amplify a 1-byte counter
        // jump into a phantom GB/s spike.
        let usable = dt > 0.05 && dt < 60 && lastCommit > .distantPast

        for c in nextConnections {
            nextTotals[c.id] = (c.upload, c.download)
            if usable, let prev = lastTotals[c.id] {
                let upDelta = max(0, c.upload - prev.up)
                let dnDelta = max(0, c.download - prev.down)
                let upBps = Int(Double(upDelta) / dt)
                let dnBps = Int(Double(dnDelta) / dt)
                if upBps != 0 || dnBps != 0 {
                    nextRates[c.id] = ConnectionRate(up: upBps, down: dnBps)
                }
            }
        }

        connections = nextConnections
        downloadTotal = snapshot.downloadTotal ?? 0
        uploadTotal = snapshot.uploadTotal ?? 0
        rates = nextRates
        lastTotals = nextTotals
        lastCommit = date
    }

    func reset() {
        coalesceTask?.cancel()
        coalesceTask = nil
        pendingSnapshot = nil
        lastCommit = .distantPast
        connections = []
        downloadTotal = 0
        uploadTotal = 0
        rates = [:]
        lastTotals = [:]
    }

    func close(id: String, api: MihomoAPIClient?) async {
        guard let api else { return }
        do {
            try await api.closeConnection(id: id)
            // Optimistically drop from local state — the next snapshot
            // confirms in <1 s.
            connections.removeAll { $0.id == id }
            rates.removeValue(forKey: id)
            lastTotals.removeValue(forKey: id)
        } catch {
            log.error("close \(id, privacy: .public) failed: \(String(describing: error), privacy: .public)")
        }
    }

    func closeAll(api: MihomoAPIClient?) async {
        guard let api else { return }
        do {
            try await api.closeAllConnections()
            connections = []
            rates = [:]
            lastTotals = [:]
        } catch {
            log.error("closeAll failed: \(String(describing: error), privacy: .public)")
        }
    }
}
