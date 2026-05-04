import Foundation
import Observation
import OSLog

@Observable
@MainActor
final class ConnectionsStore {
    private(set) var connections: [MihomoConnection] = []
    private(set) var downloadTotal: Int = 0
    private(set) var uploadTotal: Int = 0

    private let log = Logger(subsystem: "com.tzaigroup.chunghwa", category: "connections")

    /// Minimum gap between published snapshots. Mihomo's /connections stream
    /// can burst several frames within a few hundred ms when traffic spikes;
    /// 250 ms is below the perceptible-flicker threshold and still keeps the
    /// list feeling live, while collapsing bursts into a single SwiftUI redraw.
    private static let coalesceWindow: TimeInterval = 0.25

    @ObservationIgnored private var pendingSnapshot: MihomoConnectionsSnapshot?
    @ObservationIgnored private var coalesceTask: Task<Void, Never>?
    @ObservationIgnored private var lastCommit: Date = .distantPast

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
        connections = snapshot.connections ?? []
        downloadTotal = snapshot.downloadTotal ?? 0
        uploadTotal = snapshot.uploadTotal ?? 0
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
    }

    func close(id: String, api: MihomoAPIClient?) async {
        guard let api else { return }
        do {
            try await api.closeConnection(id: id)
            // Optimistically drop from local state — the next snapshot
            // confirms in <1 s.
            connections.removeAll { $0.id == id }
        } catch {
            log.error("close \(id, privacy: .public) failed: \(String(describing: error), privacy: .public)")
        }
    }

    func closeAll(api: MihomoAPIClient?) async {
        guard let api else { return }
        do {
            try await api.closeAllConnections()
            connections = []
        } catch {
            log.error("closeAll failed: \(String(describing: error), privacy: .public)")
        }
    }
}
