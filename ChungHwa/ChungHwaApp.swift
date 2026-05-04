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
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let resolver: KernelBinaryResolver
    let downloader: KernelDownloader
    let logStore: LogStore
    let profileStore: ProfileStore
    let kernel: KernelController

    override init() {
        let resolver = KernelBinaryResolver()
        let logStore = LogStore()
        let profileStore = ProfileStore()
        self.resolver = resolver
        self.downloader = KernelDownloader(resolver: resolver)
        self.logStore = logStore
        self.profileStore = profileStore
        self.kernel = KernelController(resolver: resolver, logStore: logStore, profileStore: profileStore)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { await kernel.start() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        kernel.stop()
    }
}
