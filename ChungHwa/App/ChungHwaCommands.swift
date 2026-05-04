import AppKit
import SwiftUI

/// Notification posted when the user invokes the "Focus Filter" menu command.
/// Feature views with a search field listen for this to grab keyboard focus.
extension Notification.Name {
    static let chungHwaFocusFilter = Notification.Name("ChungHwa.FocusFilter")
}

private func openURL(_ string: String) {
    guard let url = URL(string: string) else { return }
    NSWorkspace.shared.open(url)
}

/// Top-level menu commands. Adds a "View" menu whose items double as keyboard
/// shortcuts for sidebar navigation:
///
/// - cmd-1 .. cmd-9 — first nine tabs (overview … providers)
/// - cmd-shift-, — Advanced
/// - cmd-shift-p — Profiles
/// - cmd-, — Settings (macOS standard for Preferences)
///
/// And a "ChungHwa" menu for app-wide actions:
///
/// - cmd-r — Reload mihomo config (no restart)
/// - cmd-shift-k — Clear logs
/// - cmd-k — Focus the active screen's filter field
///
/// The selection binding, kernel controller and log store are all read via
/// `@FocusedValue` from the focused scene so the same command set drives
/// whichever ContentView is frontmost.
struct ChungHwaCommands: Commands {
    @FocusedValue(\.sidebarSelection) private var selection: Binding<SidebarTab?>?
    @FocusedValue(\.kernelController) private var kernel: KernelController?
    @FocusedValue(\.logStore) private var logStore: LogStore?

    var body: some Commands {
        CommandMenu("视图") {
            tabButton(.overview,     key: "1")
            tabButton(.trafficStats, key: "2")
            tabButton(.connections,  key: "3")
            tabButton(.logs,         key: "4")
            tabButton(.topology,     key: "5")
            tabButton(.routeMap,     key: "6")
            tabButton(.proxies,      key: "7")
            tabButton(.rules,        key: "8")
            tabButton(.providers,    key: "9")

            Divider()

            tabButton(.profiles, key: "p", modifiers: [.command, .shift])
            tabButton(.advanced, key: ",", modifiers: [.command, .shift])
            tabButton(.settings, key: ",", modifiers: [.command])
        }

        CommandMenu("中華") {
            Button("重载配置") {
                guard let kernel else { return }
                Task { await kernel.reload() }
            }
            .keyboardShortcut("r", modifiers: [.command])
            .disabled(kernel?.apiClient == nil)

            Button("清空日志") {
                logStore?.clear()
            }
            .keyboardShortcut("k", modifiers: [.command, .shift])

            Button("聚焦搜索") {
                NotificationCenter.default.post(name: .chungHwaFocusFilter, object: nil)
            }
            .keyboardShortcut("k", modifiers: [.command])
        }

        CommandGroup(replacing: .help) {
            Button("在 GitHub 上查看中華") {
                openURL("https://github.com/ChloePike/chunghwa")
            }

            Button("反馈问题") {
                openURL("https://github.com/ChloePike/chunghwa/issues/new")
            }

            Divider()

            Button("mihomo 文档") {
                openURL("https://wiki.metacubex.one/")
            }

            Button("mihomo GitHub") {
                openURL("https://github.com/MetaCubeX/mihomo")
            }

            Divider()

            Button("关于中華") {
                NSApplication.shared.orderFrontStandardAboutPanel(nil)
            }
        }
    }

    @ViewBuilder
    private func tabButton(
        _ tab: SidebarTab,
        key: KeyEquivalent,
        modifiers: EventModifiers = [.command]
    ) -> some View {
        Button(tab.title) {
            selection?.wrappedValue = tab
        }
        .keyboardShortcut(key, modifiers: modifiers)
        .disabled(selection == nil)
    }
}
