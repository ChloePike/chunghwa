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
                .environment(appDelegate.anonymousMode)
                .environment(appDelegate.loginItem)
                .environment(appDelegate.notificationCenterStore)
        }
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
        let anonymousMode = AnonymousMode()
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
        self.anonymousMode = anonymousMode
        self.kernel = KernelController(
            resolver: resolver,
            logStore: logStore,
            profileStore: profileStore,
            trafficStore: trafficStore,
            historyStore: historyStore,
            connectionsStore: connectionsStore,
            configStore: configStore
        )
        self.loginItem = LoginItemController()
        self.notificationCenterStore = NotificationCenterStore()
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { await kernel.start() }
        let hide = UserDefaults.standard.bool(forKey: "ChungHwa.HideDockIcon")
        NSApp.setActivationPolicy(hide ? .accessory : .regular)
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
