import SwiftUI
import AppKit

struct MenubarContent: View {
    @Environment(KernelController.self) private var kernel
    @Environment(SystemProxyController.self) private var systemProxy
    @Environment(ConfigStore.self) private var config
    @Environment(ProfileStore.self) private var profileStore
    @Environment(TrafficStore.self) private var traffic
    @Environment(ConnectionsStore.self) private var connectionsStore

    var body: some View {
        // 1. Status header (non-selectable)
        statusTitle
        rateLine

        Divider()

        // 3. Outbound mode submenu
        Menu("Mode: \(modeName)") {
            modeButton(.direct)
            modeButton(.rule)
            modeButton(.global)
        }

        // 4. Profile submenu
        Menu("Profile: \(activeProfileName)") {
            if profileStore.profiles.isEmpty {
                Text("No profiles")
            } else {
                ForEach(profileStore.profiles) { p in
                    Button {
                        profileStore.activate(p.id)
                    } label: {
                        HStack {
                            Image(systemName: profileStore.activeProfileID == p.id
                                  ? "checkmark" : "")
                            Text(p.name)
                        }
                    }
                }
            }
        }

        Divider()

        // 6. System proxy toggle
        Button(systemProxy.enabled ? "✓ System Proxy" : "System Proxy") {
            systemProxy.toggle()
        }
        .keyboardShortcut("p", modifiers: [.command, .shift])

        // 7. Kernel control
        Button(kernelToggleLabel) {
            Task {
                if isRunningOrStarting { kernel.stop() }
                else { await kernel.start() }
            }
        }

        Divider()

        // 9. Live stats (non-selectable)
        Text("\(connectionsStore.connections.count) active connections")
        Text("Memory: \(ChFormat.bytes(traffic.memoryInUse))")

        Divider()

        // 11. Reload config
        Button("Reload config") {
            Task { await kernel.reload() }
        }
        .disabled(!isRunning)

        // 12. Show ChungHwa
        Button("Show ChungHwa") { showMainWindow() }
            .keyboardShortcut("0", modifiers: [.command])

        // 13. Quit
        Button("Quit ChungHwa") { NSApp.terminate(nil) }
            .keyboardShortcut("q", modifiers: [.command])
    }

    // MARK: - Status header

    @ViewBuilder
    private var statusTitle: some View {
        switch kernel.status {
        case .running(let v): Text("mihomo \(v)")
        case .starting:       Text("Starting…")
        case .failed:         Text("Failed")
        case .idle:           Text("Idle")
        }
    }

    private var rateLine: some View {
        let up = traffic.current?.upBps ?? 0
        let down = traffic.current?.downBps ?? 0
        return Text("↑ \(ChFormat.rate(up)) · ↓ \(ChFormat.rate(down))")
    }

    // MARK: - Mode helpers

    private var modeName: String {
        config.mode?.displayName ?? "—"
    }

    @ViewBuilder
    private func modeButton(_ m: MihomoMode) -> some View {
        Button {
            Task { await config.setMode(m, api: kernel.apiClient) }
        } label: {
            HStack {
                Image(systemName: config.mode == m ? "checkmark" : "")
                Text(m.displayName)
            }
        }
    }

    // MARK: - Profile helpers

    private var activeProfileName: String {
        profileStore.activeProfile?.name ?? "—"
    }

    // MARK: - Kernel state

    private var isRunningOrStarting: Bool {
        switch kernel.status {
        case .running, .starting: return true
        default: return false
        }
    }

    private var isRunning: Bool {
        if case .running = kernel.status { return true }
        return false
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
