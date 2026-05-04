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
    @Environment(NotificationCenterStore.self) private var notifications
    @Environment(ProfileStore.self) private var profileStore
    @Environment(KernelController.self) private var kernelController
    @Environment(LogStore.self) private var logStore

    @AppStorage("ChungHwa.OnboardingDismissed") private var onboardingDismissed: Bool = false

    private var showOnboarding: Bool {
        profileStore.profiles.isEmpty && !onboardingDismissed
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection)
        } detail: {
            VStack(spacing: 0) {
                AppToolbar(title: title, onSwitchToProfiles: { selection = .profiles })
                ErrorBanner(bus: errorBus)
                if showOnboarding {
                    OnboardingBanner(
                        onCreate: { selection = .profiles },
                        onDismiss: { onboardingDismissed = true }
                    )
                }
                detailScreen
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                StatusBar()
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .focusedSceneValue(\.sidebarSelection, $selection)
        .focusedSceneValue(\.kernelController, kernelController)
        .focusedSceneValue(\.logStore, logStore)
        .onChange(of: configStore.lastError) { _, m in
            errorBus.post(source: "Config", message: m)
            notifications.post(source: "Config", level: .error, message: m)
        }
        .onChange(of: proxyStore.lastError) { _, m in
            errorBus.post(source: "Proxy", message: m)
            notifications.post(source: "Proxy", level: .error, message: m)
        }
        .onChange(of: ruleStore.lastError) { _, m in
            errorBus.post(source: "Rule", message: m)
            notifications.post(source: "Rule", level: .error, message: m)
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

private struct OnboardingBanner: View {
    let onCreate: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 16))
                .foregroundStyle(ChungHwa.Palette.brass)
            VStack(alignment: .leading, spacing: 1) {
                Text("Welcome to ChungHwa")
                    .font(ChungHwa.Typography.serif(14))
                    .foregroundStyle(ChungHwa.Palette.text)
                Text("Add a YAML profile to get started.")
                    .font(.system(size: 11))
                    .foregroundStyle(ChungHwa.Palette.text)
            }
            Spacer(minLength: 8)
            Button(action: onCreate) {
                Text("Create profile")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ChungHwa.Palette.bone)
                    .padding(.horizontal, 12)
                    .frame(height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            .fill(ChungHwa.Palette.brass)
                    )
            }
            .buttonStyle(.plain)
            Button(action: onDismiss) {
                Text("Dismiss")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(ChungHwa.Palette.dim)
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        .background(ChungHwa.Palette.brass.opacity(0.10))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(ChungHwa.Palette.brass.opacity(0.5))
                .frame(height: 0.5)
        }
    }
}

private struct StatusBar: View {
    @Environment(KernelController.self) private var kernel
    @Environment(ConnectionsStore.self) private var connectionsStore
    @Environment(TrafficStore.self) private var traffic
    @Environment(ConfigStore.self) private var configStore
    @Environment(SystemProxyController.self) private var systemProxy

    var body: some View {
        HStack(spacing: 8) {
            kernelItem
            separator
            connectionsItem
            separator
            trafficItem
            Spacer(minLength: 8)
            modeItem
            separator
            systemProxyBadge
        }
        .padding(.horizontal, 12)
        .frame(height: 24)
        .frame(maxWidth: .infinity)
        .background(ChungHwa.Palette.fill)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(ChungHwa.Palette.line)
                .frame(height: 0.5)
        }
    }

    private var separator: some View {
        Text("·")
            .font(.system(size: 10.5))
            .foregroundStyle(ChungHwa.Palette.faint)
    }

    @ViewBuilder
    private var kernelItem: some View {
        HStack(spacing: 6) {
            ChDot(color: kernelDotColor, size: 6, pulse: isStarting)
            Text(kernelLabel)
                .font(.system(size: 10.5))
                .foregroundStyle(ChungHwa.Palette.dim)
            if let v = kernelVersion {
                Text("·")
                    .font(.system(size: 10.5))
                    .foregroundStyle(ChungHwa.Palette.faint)
                Text(v)
                    .font(ChungHwa.Typography.mono(10.5))
                    .foregroundStyle(ChungHwa.Palette.dim)
            }
        }
    }

    private var isStarting: Bool {
        if case .starting = kernel.status { return true }
        return false
    }

    private var kernelDotColor: Color {
        switch kernel.status {
        case .running:  return ChungHwa.Palette.patina
        case .starting: return ChungHwa.Palette.brass
        case .failed:   return ChungHwa.Palette.earth
        case .idle:     return ChungHwa.Palette.faint
        }
    }

    private var kernelLabel: String {
        switch kernel.status {
        case .running:  return "running"
        case .starting: return "starting…"
        case .failed:   return "failed"
        case .idle:     return "idle"
        }
    }

    private var kernelVersion: String? {
        if case .running(let v) = kernel.status, !v.isEmpty {
            return v.hasPrefix("v") ? v : "v\(v)"
        }
        return nil
    }

    private var connectionsItem: some View {
        HStack(spacing: 4) {
            Text("\(connectionsStore.connections.count)")
                .font(ChungHwa.Typography.mono(10.5))
                .foregroundStyle(ChungHwa.Palette.dim)
            Text("conns")
                .font(.system(size: 10.5))
                .foregroundStyle(ChungHwa.Palette.dim)
        }
    }

    private var trafficItem: some View {
        HStack(spacing: 4) {
            Text("↑")
                .font(.system(size: 10.5))
                .foregroundStyle(ChungHwa.Palette.faint)
            Text(upRate)
                .font(ChungHwa.Typography.mono(10.5))
                .foregroundStyle(ChungHwa.Palette.dim)
            Text("·")
                .font(.system(size: 10.5))
                .foregroundStyle(ChungHwa.Palette.faint)
            Text("↓")
                .font(.system(size: 10.5))
                .foregroundStyle(ChungHwa.Palette.faint)
            Text(downRate)
                .font(ChungHwa.Typography.mono(10.5))
                .foregroundStyle(ChungHwa.Palette.dim)
        }
    }

    private var upRate: String {
        guard let s = traffic.current else { return "—" }
        return ChFormat.rate(s.upBps)
    }

    private var downRate: String {
        guard let s = traffic.current else { return "—" }
        return ChFormat.rate(s.downBps)
    }

    private var modeItem: some View {
        HStack(spacing: 4) {
            Text("mode:")
                .font(.system(size: 10.5))
                .foregroundStyle(ChungHwa.Palette.dim)
            Text(configStore.mode?.displayName ?? "—")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(ChungHwa.Palette.dim)
        }
    }

    private var systemProxyBadge: some View {
        let on = systemProxy.enabled
        return Text(on ? "SP on" : "SP off")
            .font(ChungHwa.Typography.mono(10, weight: .medium))
            .foregroundStyle(on ? ChungHwa.Palette.patina : ChungHwa.Palette.faint)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(on
                          ? ChungHwa.Palette.patina.opacity(0.12)
                          : ChungHwa.Palette.fillStrong)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(on
                                  ? ChungHwa.Palette.patina.opacity(0.30)
                                  : ChungHwa.Palette.line,
                                  lineWidth: 0.5)
            )
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
        .environment(NotificationCenterStore())
}
