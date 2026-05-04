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

    private let log = Logger(subsystem: "com.tzaigroup.chunghwa", category: "proxies")

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
            snapshotProxies = snap.proxies
            groupOrder = computeGroupOrder(in: snap.proxies)
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
            for (name, ms) in results {
                guard var p = snapshotProxies[name] else { continue }
                let sample = MihomoProxy.DelaySample(time: now, delay: ms)
                let history = (p.history ?? []) + [sample]
                p = MihomoProxy(name: p.name, type: p.type, now: p.now,
                                all: p.all, history: history, udp: p.udp)
                snapshotProxies[name] = p
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
                }
            }
            lastError = nil
            log.debug("group delay \(group, privacy: .public): \(results.count, privacy: .public) responses")
        } catch {
            lastError = String(describing: error)
            log.error("group delay \(group, privacy: .public) failed: \(self.lastError ?? "?", privacy: .public)")
        }
    }

    var groups: [MihomoProxy] {
        groupOrder.compactMap { snapshotProxies[$0] }
    }

    func proxy(_ name: String) -> MihomoProxy? { snapshotProxies[name] }

    private func computeGroupOrder(in all: [String: MihomoProxy]) -> [String] {
        // Show only Selector groups by default — those are the ones the user
        // can manually switch. Auto-strategy groups (URLTest / Fallback /
        // LoadBalance / Relay) are hidden because they pick a node on their
        // own; surfacing them clutters the UI without giving the user
        // anything actionable. Configs with deeply-nested auto sub-groups
        // (very common in subscription bundles) used to render dozens of
        // rows before this filter.
        let selectorGroups = all.values.filter { $0.isUserSwitchable }.map(\.name)
        var seen = Set<String>()
        var ordered: [String] = []
        // GLOBAL ordering hint: if GLOBAL.all lists groups in a particular
        // order, mirror that to match config intent.
        if let global = all["GLOBAL"], let members = global.all {
            for name in members where selectorGroups.contains(name) {
                if seen.insert(name).inserted { ordered.append(name) }
            }
        }
        for name in selectorGroups.sorted() where !seen.contains(name) {
            ordered.append(name)
        }
        return ordered.filter { $0 != "GLOBAL" }
    }
}
