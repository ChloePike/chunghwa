import Foundation
import Observation
import OSLog

/// Owns the snapshot of mihomo's rule table and rule providers for the Rules
/// tab. mihomo's `/rules` endpoint is one-shot (no streaming), so the store
/// just exposes a `refresh` the view triggers from `.task` and a manual button.
@Observable
@MainActor
final class RuleStore {
    private(set) var rules: [MihomoRule] = []
    private(set) var providers: [MihomoRuleProvider] = []
    private(set) var isRefreshing: Bool = false
    private(set) var updatingProviders: Set<String> = []
    private(set) var lastError: String?

    private let log = Logger(subsystem: "com.tzaigroup.chunghwa", category: "rules")

    func reset() {
        rules = []
        providers = []
        isRefreshing = false
        updatingProviders = []
        lastError = nil
    }

    /// Pull the rule table and (best-effort) the providers list. Re-keys each
    /// rule with its index so duplicate `(type, payload, proxy)` triples stay
    /// distinct in `ForEach`.
    func refresh(api: MihomoAPIClient?) async {
        guard let api else {
            reset()
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let raw = try await api.rules()
            self.rules = raw.enumerated().map { idx, r in
                MihomoRule(type: r.type, payload: r.payload, proxy: r.proxy, index: idx)
            }
            lastError = nil
        } catch {
            log.error("rules refresh failed: \(String(describing: error), privacy: .public)")
            lastError = String(describing: error)
        }

        // Providers are optional — older mihomo builds may not expose them, or
        // the configuration may not declare any rule-providers at all. Failure
        // here mustn't blank the rules list.
        self.providers = (try? await api.ruleProviders()) ?? []
    }

    /// Ask mihomo to re-pull a rule provider from its remote (or reload from
    /// disk for `file` vehicles), then refresh so the new ruleCount lands in
    /// the UI.
    func updateProvider(_ name: String, api: MihomoAPIClient?) async {
        guard let api else { return }
        updatingProviders.insert(name)
        defer { updatingProviders.remove(name) }

        do {
            try await api.updateRuleProvider(name: name)
        } catch {
            log.error("updateRuleProvider \(name, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            lastError = String(describing: error)
            return
        }
        await refresh(api: api)
    }
}
