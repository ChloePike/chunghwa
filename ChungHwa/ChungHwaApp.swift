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
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let resolver: KernelBinaryResolver
    let downloader: KernelDownloader
    let kernel: KernelController

    override init() {
        let resolver = KernelBinaryResolver()
        self.resolver = resolver
        self.downloader = KernelDownloader(resolver: resolver)
        self.kernel = KernelController(resolver: resolver)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { await kernel.start() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        kernel.stop()
    }
}
