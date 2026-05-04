import SwiftUI
import AppKit

@main
struct ChungHwaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appDelegate.kernel)
                .environment(appDelegate.resolver)
                .environment(appDelegate.downloader)
                .environment(appDelegate.logStore)
                .environment(appDelegate.profileStore)
                .environment(appDelegate.systemProxy)
                .environment(appDelegate.proxyStore)
                .environment(appDelegate.trafficStore)
                .environment(appDelegate.historyStore)
                .environment(appDelegate.connectionsStore)
                .environment(appDelegate.configStore)
                .environment(appDelegate.ruleStore)
                .environment(appDelegate.proxyProviderStore)
                .environment(appDelegate.anonymousMode)
                .environment(appDelegate.loginItem)
                .environment(appDelegate.notificationCenterStore)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            ChungHwaCommands()
        }

        MenuBarExtra {
            MenubarContent()
                .environment(appDelegate.kernel)
                .environment(appDelegate.systemProxy)
                .environment(appDelegate.configStore)
                .environment(appDelegate.profileStore)
                .environment(appDelegate.trafficStore)
                .environment(appDelegate.historyStore)
                .environment(appDelegate.connectionsStore)
        } label: {
            Image(systemName: MenubarIconName.current(
                kernel: appDelegate.kernel,
                systemProxy: appDelegate.systemProxy))
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let resolver: KernelBinaryResolver
    let downloader: KernelDownloader
    let logStore: LogStore
    let profileStore: ProfileStore
    let systemProxy: SystemProxyController
    let proxyStore: ProxyStore
    let trafficStore: TrafficStore
    let historyStore: TrafficHistoryStore
    let connectionsStore: ConnectionsStore
    let configStore: ConfigStore
    let ruleStore: RuleStore
    let proxyProviderStore: ProxyProviderStore
    let anonymousMode: AnonymousMode
    let kernel: KernelController
    let loginItem: LoginItemController
    let notificationCenterStore: NotificationCenterStore

    override init() {
        let resolver = KernelBinaryResolver()
        let logStore = LogStore()
        let profileStore = ProfileStore()
        let systemProxy = SystemProxyController()
        let proxyStore = ProxyStore()
        let trafficStore = TrafficStore()
        let historyStore = TrafficHistoryStore()
        let connectionsStore = ConnectionsStore()
        let configStore = ConfigStore()
        let ruleStore = RuleStore()
        let proxyProviderStore = ProxyProviderStore()
        let anonymousMode = AnonymousMode()
        let notificationCenterStore = NotificationCenterStore()
        self.resolver = resolver
        self.downloader = KernelDownloader(resolver: resolver)
        self.logStore = logStore
        self.profileStore = profileStore
        self.systemProxy = systemProxy
        self.proxyStore = proxyStore
        self.trafficStore = trafficStore
        self.historyStore = historyStore
        self.connectionsStore = connectionsStore
        self.configStore = configStore
        self.ruleStore = ruleStore
        self.proxyProviderStore = proxyProviderStore
        self.anonymousMode = anonymousMode
        self.notificationCenterStore = notificationCenterStore
        self.kernel = KernelController(
            resolver: resolver,
            logStore: logStore,
            profileStore: profileStore,
            trafficStore: trafficStore,
            historyStore: historyStore,
            connectionsStore: connectionsStore,
            configStore: configStore,
            notificationCenterStore: notificationCenterStore
        )
        self.loginItem = LoginItemController()
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { await kernel.start() }
        let hide = UserDefaults.standard.bool(forKey: "ChungHwa.HideDockIcon")
        NSApp.setActivationPolicy(hide ? .accessory : .regular)

        // SwiftUI's `.windowStyle(.hiddenTitleBar)` alone leaves the
        // NavigationSplitView toolbar row at the top — visible as a chunky
        // empty stripe above the sidebar / detail. Patch each window to
        // also remove the toolbar and let content extend through the
        // title-bar safe area.
        DispatchQueue.main.async {
            for window in NSApp.windows {
                window.titlebarAppearsTransparent = true
                window.titleVisibility = .hidden
                window.styleMask.insert(.fullSizeContentView)
                window.toolbar = nil
                window.isMovableByWindowBackground = true
            }
        }

        // Initial kernel-update check, delayed so we don't compete with kernel startup.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 30 * 1_000_000_000)
            await self.downloader.checkForUpdates()
            self.notifyIfKernelUpdateAvailable()
        }

        // Daily re-check.
        Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(24 * 3600 * 1_000_000_000))
                await self.downloader.checkForUpdates()
                self.notifyIfKernelUpdateAvailable()
            }
        }
    }

    /// Compare `downloader.latestKnown` against the currently-installed
    /// managed-kernel version and post an info notification if a newer release
    /// is available. No-op when we have no current version yet.
    private func notifyIfKernelUpdateAvailable() {
        guard let latest = downloader.latestKnown, !latest.isEmpty else { return }
        // We only know an installed version for the managed binary; for custom
        // / bundled, skip — user is driving their own kernel.
        guard let installed = resolver.managedVersion(), !installed.isEmpty else { return }
        guard latest != installed else { return }
        notificationCenterStore.post(
            source: "Kernel",
            level: .info,
            message: "mihomo \(latest) is available · open Settings → Update kernel"
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        if systemProxy.enabled { systemProxy.disable() }
        kernel.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        let key = "ChungHwa.CloseKeepsRunning"
        let keepsRunning: Bool = UserDefaults.standard.object(forKey: key) == nil
            ? true
            : UserDefaults.standard.bool(forKey: key)
        return !keepsRunning
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows {
            for w in NSApp.windows where w.canBecomeKey {
                w.makeKeyAndOrderFront(nil)
                return true
            }
            // No window — synthesize one. WindowGroup will recreate on activation.
            NSApp.activate(ignoringOtherApps: true)
        }
        return true
    }
}
