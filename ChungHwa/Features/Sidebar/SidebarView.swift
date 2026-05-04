import AppKit
import SwiftUI

struct SidebarView: View {
    @Binding var selection: SidebarTab?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(SidebarTab.sections) { section in
                    if let h = section.header {
                        Text(h)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(ChungHwa.Palette.faint)
                            .textCase(.uppercase)
                            .tracking(0.4)
                            .padding(.horizontal, 16)
                            .padding(.top, 14)
                            .padding(.bottom, 4)
                    } else {
                        Color.clear.frame(height: 4)
                    }

                    ForEach(section.tabs) { tab in
                        TabRow(tab: tab,
                               isActive: selection == tab,
                               select: { selection = tab })
                    }
                }
                Color.clear.frame(height: 8)
            }
        }
        .scrollContentBackground(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(SidebarGlass().ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SettingsFooter(selection: $selection)
        }
        .navigationSplitViewColumnWidth(min: 140, ideal: 160, max: 200)
    }
}

/// `NSVisualEffectView` with the system `.sidebar` material — on macOS Tahoe
/// (26+) this is the surface AppKit auto-promotes to Liquid Glass, matching
/// the look of Apple Music / Mail / Notes sidebars.
private struct SidebarGlass: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .sidebar
        v.blendingMode = .behindWindow
        v.state = .followsWindowActiveState
        v.isEmphasized = true
        return v
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

private struct TabRow: View {
    let tab: SidebarTab
    let isActive: Bool
    let select: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: select) {
            HStack(spacing: 10) {
                Image(systemName: tab.symbol)
                    .font(.system(size: 13, weight: isActive ? .semibold : .regular))
                    .foregroundStyle(iconColor)
                    .frame(width: 16)
                Text(tab.title)
                    .font(.system(size: 12.5, weight: isActive ? .semibold : .medium))
                    .foregroundStyle(textColor)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rowBackground)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Keep horizontal inset > the window's outer corner radius (≈10pt)
        // so the pill never slips into the curved corner zone.
        .padding(.horizontal, 10)
        .padding(.vertical, 1)
        .onHover { hovering = $0 }
    }

    @ViewBuilder
    private var rowBackground: some View {
        if isActive {
            // Saturated brass pill, drops a small shadow so it floats off
            // the sidebar glass — same vibe as Apple Music's red selection.
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(LinearGradient(
                    colors: [
                        ChungHwa.Palette.brass.opacity(0.95),
                        ChungHwa.Palette.brass.opacity(0.78),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .shadow(color: ChungHwa.Palette.brass.opacity(0.35), radius: 4, y: 2)
        } else if hovering {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(.thinMaterial)
                .opacity(0.6)
        } else {
            Color.clear
        }
    }

    private var iconColor: Color {
        if isActive { return .white }
        return ChungHwa.Palette.dim
    }

    private var textColor: Color {
        if isActive { return .white }
        return ChungHwa.Palette.text
    }
}

private struct BrandHeader: View {
    var body: some View {
        HStack(spacing: 0) {
            Spacer()
            Text("中華")
                .font(ChungHwa.Typography.serif(15, weight: .medium))
                .foregroundStyle(ChungHwa.Palette.text)
                .tracking(-0.1)
            Text("·")
                .font(ChungHwa.Typography.serif(15, weight: .medium))
                .foregroundStyle(ChungHwa.Palette.brass)
                .padding(.leading, 2)
        }
        .textCase(nil)
    }
}

private struct SettingsFooter: View {
    @Binding var selection: SidebarTab?

    var body: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.4)
            TabRow(tab: .settings,
                   isActive: selection == .settings,
                   select: { selection = .settings })
                .padding(.top, 6)
                // Bigger bottom inset so the active pill stays clear of
                // the window's rounded corner curve.
                .padding(.bottom, 10)
        }
        .background(SidebarGlass())
    }
}
