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
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let resolver: KernelBinaryResolver
    let downloader: KernelDownloader
    let logStore: LogStore
    let kernel: KernelController

    override init() {
        let resolver = KernelBinaryResolver()
        let logStore = LogStore()
        self.resolver = resolver
        self.downloader = KernelDownloader(resolver: resolver)
        self.logStore = logStore
        self.kernel = KernelController(resolver: resolver, logStore: logStore)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { await kernel.start() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        kernel.stop()
    }
}
