import SwiftUI

/// Bridges the main window's `selection` binding into the menu-command scope so
/// that `ChungHwaCommands` (declared on the WindowGroup) can flip the active
/// sidebar tab in response to keyboard shortcuts.
struct SidebarSelectionKey: FocusedValueKey {
    typealias Value = Binding<SidebarTab?>
}

/// Exposes the focused scene's `KernelController` to menu commands so that
/// shortcuts like "Reload Config" can act on the running kernel.
struct KernelControllerKey: FocusedValueKey {
    typealias Value = KernelController
}

/// Exposes the focused scene's `LogStore` to menu commands so that shortcuts
/// like "Clear Logs" can clear the buffer.
struct LogStoreKey: FocusedValueKey {
    typealias Value = LogStore
}

extension FocusedValues {
    var sidebarSelection: Binding<SidebarTab?>? {
        get { self[SidebarSelectionKey.self] }
        set { self[SidebarSelectionKey.self] = newValue }
    }

    var kernelController: KernelController? {
        get { self[KernelControllerKey.self] }
        set { self[KernelControllerKey.self] = newValue }
    }

    var logStore: LogStore? {
        get { self[LogStoreKey.self] }
        set { self[LogStoreKey.self] = newValue }
    }
}
