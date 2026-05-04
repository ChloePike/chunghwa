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
        }

        MenuBarExtra {
            MenubarContent()
                .environment(appDelegate.kernel)
                .environment(appDelegate.systemProxy)
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
    let kernel: KernelController

    override init() {
        let resolver = KernelBinaryResolver()
        let logStore = LogStore()
        let profileStore = ProfileStore()
        let systemProxy = SystemProxyController()
        let proxyStore = ProxyStore()
        let trafficStore = TrafficStore()
        self.resolver = resolver
        self.downloader = KernelDownloader(resolver: resolver)
        self.logStore = logStore
        self.profileStore = profileStore
        self.systemProxy = systemProxy
        self.proxyStore = proxyStore
        self.trafficStore = trafficStore
        self.kernel = KernelController(
            resolver: resolver,
            logStore: logStore,
            profileStore: profileStore,
            trafficStore: trafficStore
        )
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { await kernel.start() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if systemProxy.enabled { systemProxy.disable() }
        kernel.stop()
    }
}
