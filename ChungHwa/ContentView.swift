import SwiftUI

struct ContentView: View {
    @State private var selection: SidebarTab? = .overview

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection)
        } detail: {
            VStack(spacing: 0) {
                AppToolbar(title: title, onSwitchToProfiles: { selection = .profiles })
                detailScreen
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 900, minHeight: 600)
    }

    private var title: String {
        (selection ?? .overview).title
    }

    @ViewBuilder
    private var detailScreen: some View {
        switch selection ?? .overview {
        case .overview:     OverviewView()
        case .trafficStats: TrafficStatsView()
        case .connections:  ConnectionsView()
        case .logs:         LogsView()
        case .topology:     TopologyView()
        case .routeMap:     RouteMapView()
        case .proxies:      ProxiesView()
        case .rules:        RulesView()
        case .providers:    ProvidersView()
        case .profiles:     ProfilesView()
        case .advanced:     AdvancedView()
        case .settings:     SettingsView()
        }
    }
}

#Preview {
    let resolver = KernelBinaryResolver()
    let logStore = LogStore()
    let profileStore = ProfileStore()
    let trafficStore = TrafficStore()
    let historyStore = TrafficHistoryStore()
    let connectionsStore = ConnectionsStore()
    let configStore = ConfigStore()
    let ruleStore = RuleStore()
    return ContentView()
        .environment(KernelController(
            resolver: resolver,
            logStore: logStore,
            profileStore: profileStore,
            trafficStore: trafficStore,
            historyStore: historyStore,
            connectionsStore: connectionsStore,
            configStore: configStore))
        .environment(resolver)
        .environment(KernelDownloader(resolver: resolver))
        .environment(logStore)
        .environment(profileStore)
        .environment(SystemProxyController())
        .environment(ProxyStore())
        .environment(trafficStore)
        .environment(historyStore)
        .environment(connectionsStore)
        .environment(configStore)
        .environment(ruleStore)
        .environment(AnonymousMode())
}
