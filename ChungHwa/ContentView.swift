import SwiftUI

struct ContentView: View {
    @State private var selection: SidebarTab? = .overview

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection)
        } detail: {
            switch selection ?? .overview {
            case .overview:    OverviewView()
            case .proxies:     ProxiesView()
            case .rules:       RulesView()
            case .connections: ConnectionsView()
            case .logs:        LogsView()
            case .settings:    SettingsView()
            }
        }
        .frame(minWidth: 900, minHeight: 600)
    }
}

#Preview {
    let resolver = KernelBinaryResolver()
    let logStore = LogStore()
    let profileStore = ProfileStore()
    return ContentView()
        .environment(KernelController(resolver: resolver, logStore: logStore, profileStore: profileStore))
        .environment(resolver)
        .environment(KernelDownloader(resolver: resolver))
        .environment(logStore)
        .environment(profileStore)
        .environment(SystemProxyController())
}
