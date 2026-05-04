import SwiftUI
import AppKit

struct MenubarContent: View {
    @Environment(KernelController.self) private var kernel
    @Environment(SystemProxyController.self) private var systemProxy

    var body: some View {
        statusHeader
        Divider()
        Button(systemProxy.enabled ? "Disable system proxy" : "Enable system proxy") {
            systemProxy.toggle()
        }
        Button(kernelToggleLabel) {
            Task {
                if isRunningOrStarting { kernel.stop() }
                else { await kernel.start() }
            }
        }
        Divider()
        Button("Show ChungHwa") { showMainWindow() }
            .keyboardShortcut("0", modifiers: [.command])
        Button("Quit ChungHwa") { NSApp.terminate(nil) }
            .keyboardShortcut("q", modifiers: [.command])
    }

    @ViewBuilder
    private var statusHeader: some View {
        switch kernel.status {
        case .running(let v):
            Text("mihomo \(v)")
        case .starting:
            Text("Starting…")
        case .failed:
            Text("Failed")
        case .idle:
            Text("Kernel idle")
        }
    }

    private var isRunningOrStarting: Bool {
        switch kernel.status {
        case .running, .starting: return true
        default: return false
        }
    }

    private var kernelToggleLabel: String {
        isRunningOrStarting ? "Stop kernel" : "Start kernel"
    }

    private func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        for w in NSApp.windows where w.canBecomeKey {
            w.makeKeyAndOrderFront(nil)
            return
        }
    }
}

/// Computes the SF Symbol name for the menubar icon based on the kernel state and
/// whether the system proxy is engaged.
@MainActor
struct MenubarIconName {
    static func current(kernel: KernelController, systemProxy: SystemProxyController) -> String {
        switch kernel.status {
        case .failed:    return "shield.slash"
        case .starting:  return "shield"
        case .idle:      return "shield"
        case .running:   return systemProxy.enabled ? "shield.lefthalf.filled" : "shield"
        }
    }
}
