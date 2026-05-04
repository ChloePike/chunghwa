import SwiftUI

/// Bridges the main window's `selection` binding into the menu-command scope so
/// that `ChungHwaCommands` (declared on the WindowGroup) can flip the active
/// sidebar tab in response to keyboard shortcuts.
struct SidebarSelectionKey: FocusedValueKey {
    typealias Value = Binding<SidebarTab?>
}

extension FocusedValues {
    var sidebarSelection: Binding<SidebarTab?>? {
        get { self[SidebarSelectionKey.self] }
        set { self[SidebarSelectionKey.self] = newValue }
    }
}
