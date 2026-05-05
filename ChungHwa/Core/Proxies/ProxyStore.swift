import Foundation
import Observation
import OSLog

/// In-memory mirror of mihomo's `/proxies` snapshot, plus operations to mutate
/// it. The store does not poll; views call `refresh` on appear / after writes.
/// This keeps the design analogous to ProfileStore and avoids a hidden timer.
@Observable
@MainActor
final class ProxyStore {
    private(set) var snapshotProxies: [String: MihomoProxy] = [:]
    /// Names of groups, in the order they should be displayed in the UI.
    /// Mihomo lacks a stable global order, so we sort: top-level groups
    /// first (those reachable from GLOBAL.all), then everything else,
    /// alphabetically within each bucket.
    private(set) var groupOrder: [String] = []

    private(set) var isRefreshing: Bool = false
    private(set) var lastError: String?
    /// Names of groups currently running a latency test. UI shows shimmer
    /// rows while this is non-empty.
    private(set) var testingGroups: Set<String> = []

    /// Persisted last-known delay per proxy name, keyed at the moment of
    /// each test. mihomo throws this away on every kernel restart, so we
    /// keep it on disk and merge it into the snapshot until a fresh test
    /// arrives. 0 = timeout (still useful — keeps "—" out of the UI when
    /// the server has nothing else to say).
    private var persistedDelays: [String: PersistedDelay] = [:]

    private let log = Logger(subsystem: "org.clash.ChungHwa", category: "proxies")

    init() {
        let snapshot = Database.shared.loadAllProxyDelays()
        persistedDelays = snapshot.mapValues {
            PersistedDelay(delay: $0.delay, testedAt: $0.testedAt)
        }
        log.debug("loaded \(self.persistedDelays.count, privacy: .public) persisted delays")
    }

    func reset() {
        snapshotProxies = [:]
        groupOrder = []
        isRefreshing = false
        lastError = nil
        testingGroups = []
    }

    func refresh(api: MihomoAPIClient?) async {
        guard let api else {
            reset()
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let snap = try await api.proxies()
            snapshotProxies = mergePersistedDelays(into: snap.proxies)
            groupOrder = computeGroupOrder(in: snapshotProxies)
            lastError = nil
            log.debug("refreshed \(snap.proxies.count, privacy: .public) proxies, \(self.groupOrder.count, privacy: .public) groups")
        } catch {
            lastError = String(describing: error)
            log.error("refresh failed: \(self.lastError ?? "?", privacy: .public)")
        }
    }

    func select(group: String, name: String, api: MihomoAPIClient?) async {
        guard let api else { return }
        do {
            try await api.selectProxy(group: group, name: name)
            // Patch the snapshot optimistically so the radio tick moves
            // immediately, then refresh in the background to pick up the
            // server's authoritative state.
            if var g = snapshotProxies[group] {
                g = MihomoProxy(name: g.name, type: g.type, now: name,
                                all: g.all, history: g.history, udp: g.udp)
                snapshotProxies[group] = g
            }
            await refresh(api: api)
        } catch {
            lastError = String(describing: error)
            log.error("select \(group, privacy: .public) -> \(name, privacy: .public) failed: \(self.lastError ?? "?", privacy: .public)")
        }
    }

    /// Run mihomo's batched group-delay test. Updates each member proxy's
    /// most-recent history sample so the UI badges refresh.
    func testGroup(_ group: String, api: MihomoAPIClient?) async {
        guard let api, snapshotProxies[group] != nil else { return }
        testingGroups.insert(group)
        defer { testingGroups.remove(group) }
        do {
            let results = try await api.groupDelay(group: group)
            let now = ISO8601DateFormatter().string(from: Date())
            let nowDate = Date()
            var fresh: [(name: String, delay: Int, testedAt: Date)] = []
            for (name, ms) in results {
                guard var p = snapshotProxies[name] else { continue }
                let sample = MihomoProxy.DelaySample(time: now, delay: ms)
                let history = (p.history ?? []) + [sample]
                p = MihomoProxy(name: p.name, type: p.type, now: p.now,
                                all: p.all, history: history, udp: p.udp)
                snapshotProxies[name] = p
                persistedDelays[name] = PersistedDelay(delay: ms, testedAt: nowDate)
                fresh.append((name: name, delay: ms, testedAt: nowDate))
            }
            // Members not present in the response timed out — record a 0
            // sample so the badge shows "—" instead of stale latency.
            if let g = snapshotProxies[group], let members = g.all {
                for name in members where results[name] == nil {
                    guard var p = snapshotProxies[name] else { continue }
                    let sample = MihomoProxy.DelaySample(time: now, delay: 0)
                    let history = (p.history ?? []) + [sample]
                    p = MihomoProxy(name: p.name, type: p.type, now: p.now,
                                    all: p.all, history: history, udp: p.udp)
                    snapshotProxies[name] = p
                    persistedDelays[name] = PersistedDelay(delay: 0, testedAt: nowDate)
                    fresh.append((name: name, delay: 0, testedAt: nowDate))
                }
            }
            Database.shared.upsertProxyDelays(fresh)
            lastError = nil
            log.debug("group delay \(group, privacy: .public): \(results.count, privacy: .public) responses")
        } catch {
            lastError = String(describing: error)
            log.error("group delay \(group, privacy: .public) failed: \(self.lastError ?? "?", privacy: .public)")
        }
    }

    // MARK: - Persistence

    private struct PersistedDelay {
        let delay: Int
        let testedAt: Date
    }

    private func mergePersistedDelays(into proxies: [String: MihomoProxy]) -> [String: MihomoProxy] {
        var out = proxies
        for (name, persisted) in persistedDelays {
            guard var p = out[name] else { continue }
            // mihomo's own history is authoritative when present (it ran a
            // test more recently than us). Only fill in when empty.
            if (p.history ?? []).isEmpty {
                let sample = MihomoProxy.DelaySample(
                    time: ISO8601DateFormatter().string(from: persisted.testedAt),
                    delay: persisted.delay
                )
                p = MihomoProxy(name: p.name, type: p.type, now: p.now,
                                all: p.all, history: [sample], udp: p.udp)
                out[name] = p
            }
        }
        return out
    }

    var groups: [MihomoProxy] {
        groupOrder.compactMap { snapshotProxies[$0] }
    }

    func proxy(_ name: String) -> MihomoProxy? { snapshotProxies[name] }

    private func computeGroupOrder(in all: [String: MihomoProxy]) -> [String] {
        // Show every group mihomo reports (Selector / URLTest / Fallback /
        // LoadBalance / Relay) — earlier we filtered to top-level only but
        // users want to see / switch into auto-strategy sub-groups too.
        // Only GLOBAL itself is dropped (it's a meta-aggregate).
        let allGroups = all.values.filter(\.isGroup).map(\.name)
        var seen = Set<String>()
        var ordered: [String] = []
        if let global = all["GLOBAL"], let members = global.all {
            for name in members where allGroups.contains(name) {
                if seen.insert(name).inserted { ordered.append(name) }
            }
        }
        for name in allGroups.sorted() where !seen.contains(name) {
            ordered.append(name)
        }
        return ordered.filter { $0 != "GLOBAL" }
    }
}
