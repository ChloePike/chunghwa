import Foundation
import Observation
import OSLog

/// Owns the snapshot of mihomo's proxy providers (subscription-fetched node
/// lists) for the Providers tab. Mirrors `RuleStore`'s shape: a `refresh`
/// driven by the view's `.task`, and per-name button handlers that flip a
/// pending-set so the row can show progress without blocking neighbours.
@Observable
@MainActor
final class ProxyProviderStore {
    private(set) var providers: [MihomoProxyProvider] = []
    private(set) var isRefreshing: Bool = false
    private(set) var updatingProviders: Set<String> = []
    private(set) var lastError: String?

    private let log = Logger(subsystem: "com.tzaigroup.chunghwa", category: "proxy-providers")

    func reset() {
        providers = []
        isRefreshing = false
        updatingProviders = []
        lastError = nil
    }

    /// Pull the proxy-provider list. Failure is non-fatal — older mihomo
    /// builds or profiles without proxy-providers simply yield an empty
    /// array, matching how `RuleStore` treats `ruleProviders()`.
    func refresh(api: MihomoAPIClient?) async {
        guard let api else {
            reset()
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }

        self.providers = (try? await api.proxyProviders()) ?? []
        // We deliberately swallow the error here: surfacing it would
        // spam the banner on every kernel-restart for users with no
        // proxy-providers configured.
        lastError = nil
    }

    /// Ask mihomo to re-pull the provider's vehicle (HTTP subscription or
    /// file), then refresh so the new updatedAt / subscriptionInfo land in
    /// the UI.
    func updateProvider(_ name: String, api: MihomoAPIClient?) async {
        guard let api else { return }
        updatingProviders.insert(name)
        defer { updatingProviders.remove(name) }

        do {
            try await api.updateProxyProvider(name: name)
        } catch {
            log.error("updateProxyProvider \(name, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            lastError = String(describing: error)
            return
        }
        await refresh(api: api)
    }

    /// Trigger a healthcheck across the provider's nodes. mihomo answers
    /// 204 / no body; we don't surface per-node delays here since they're
    /// the proxies tab's domain.
    func healthcheck(_ name: String, api: MihomoAPIClient?) async {
        guard let api else { return }
        updatingProviders.insert(name)
        defer { updatingProviders.remove(name) }

        do {
            try await api.healthcheckProxyProvider(name: name)
        } catch {
            log.error("healthcheckProxyProvider \(name, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            lastError = String(describing: error)
        }
    }
}
