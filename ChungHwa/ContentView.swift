import SwiftUI

struct ContentView: View {
    @State private var selection: SidebarTab? = .overview

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection)
        } detail: {
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
        .frame(minWidth: 900, minHeight: 600)
    }
}

#Preview {
    let resolver = KernelBinaryResolver()
    let logStore = LogStore()
    let profileStore = ProfileStore()
    let trafficStore = TrafficStore()
    let connectionsStore = ConnectionsStore()
    return ContentView()
        .environment(KernelController(
            resolver: resolver,
            logStore: logStore,
            profileStore: profileStore,
            trafficStore: trafficStore,
            connectionsStore: connectionsStore))
        .environment(resolver)
        .environment(KernelDownloader(resolver: resolver))
        .environment(logStore)
        .environment(profileStore)
        .environment(SystemProxyController())
        .environment(ProxyStore())
        .environment(trafficStore)
        .environment(connectionsStore)
}
