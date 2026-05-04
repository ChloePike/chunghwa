import SwiftUI

/// Top-level menu commands. Adds a "View" menu whose items double as keyboard
/// shortcuts for sidebar navigation:
///
/// - cmd-1 .. cmd-9 — first nine tabs (overview … providers)
/// - cmd-shift-, — Advanced
/// - cmd-shift-p — Profiles
/// - cmd-, — Settings (macOS standard for Preferences)
///
/// The selection binding is read via `@FocusedValue` from the focused scene so
/// the same command set drives whichever ContentView is frontmost.
struct ChungHwaCommands: Commands {
    @FocusedValue(\.sidebarSelection) private var selection: Binding<SidebarTab?>?

    var body: some Commands {
        CommandMenu("View") {
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
