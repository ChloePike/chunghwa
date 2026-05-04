import SwiftUI

@Observable
@MainActor
final class BannerErrorBus {
    private(set) var current: (source: String, message: String, posted: Date)?

    func post(source: String, message: String?) {
        guard let message, !message.isEmpty else { return }
        current = (source: source, message: message, posted: Date())
    }

    func dismiss() {
        current = nil
    }
}

struct ContentView: View {
    @State private var selection: SidebarTab? = .overview
    @State private var errorBus = BannerErrorBus()

    @Environment(ConfigStore.self) private var configStore
    @Environment(ProxyStore.self) private var proxyStore
    @Environment(RuleStore.self) private var ruleStore

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection)
        } detail: {
            VStack(spacing: 0) {
                AppToolbar(title: title, onSwitchToProfiles: { selection = .profiles })
                ErrorBanner(bus: errorBus)
                detailScreen
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .focusedSceneValue(\.sidebarSelection, $selection)
        .onChange(of: configStore.lastError) { _, m in
            errorBus.post(source: "Config", message: m)
        }
        .onChange(of: proxyStore.lastError) { _, m in
            errorBus.post(source: "Proxy", message: m)
        }
        .onChange(of: ruleStore.lastError) { _, m in
            errorBus.post(source: "Rule", message: m)
        }
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

private struct ErrorBanner: View {
    let bus: BannerErrorBus

    var body: some View {
        Group {
            if let entry = bus.current {
                HStack(spacing: 8) {
                    Circle()
                        .fill(ChungHwa.Palette.earth)
                        .frame(width: 6, height: 6)
                    HStack(spacing: 6) {
                        Text("[\(entry.source)]")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(ChungHwa.Palette.text)
                        Text(entry.message)
                            .font(.system(size: 11))
                            .foregroundStyle(ChungHwa.Palette.text)
                            .lineLimit(2)
                            .truncationMode(.tail)
                    }
                    Spacer(minLength: 8)
                    Button {
                        bus.dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(ChungHwa.Palette.text)
                            .padding(4)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                .background(ChungHwa.Palette.earth.opacity(0.10))
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(ChungHwa.Palette.earth.opacity(0.4))
                        .frame(height: 0.5)
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .task(id: entry.posted) {
                    let posted = entry.posted
                    try? await Task.sleep(nanoseconds: 8_000_000_000)
                    if bus.current?.posted == posted {
                        bus.dismiss()
                    }
                }
            }
        }
        .animation(.snappy(duration: 0.18), value: bus.current?.posted)
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
