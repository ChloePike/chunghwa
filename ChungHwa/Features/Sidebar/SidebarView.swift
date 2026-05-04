import SwiftUI

struct SidebarView: View {
    @Binding var selection: SidebarTab?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                BrandHeader()
                    .padding(.horizontal, 14)
                    // Leave room above the wordmark for macOS's traffic
                    // light buttons (window has hiddenTitleBar so buttons
                    // overlay the content).
                    .padding(.top, 30)
                    .padding(.bottom, 6)

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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SettingsFooter(selection: $selection)
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
    }
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
                    .font(.system(size: 13))
                    .foregroundStyle(isActive ? ChungHwa.Palette.text : ChungHwa.Palette.dim)
                    .frame(width: 16)
                Text(tab.title)
                    .font(.system(size: 12.5, weight: isActive ? .semibold : .medium))
                    .foregroundStyle(isActive ? ChungHwa.Palette.text : ChungHwa.Palette.dim)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(rowBackground)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
        .padding(.vertical, 1)
        .onHover { hovering = $0 }
    }

    private var rowBackground: Color {
        if isActive { return ChungHwa.Palette.sideActive }
        if hovering { return ChungHwa.Palette.sideHover }
        return .clear
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
            Divider()
            TabRow(tab: .settings,
                   isActive: selection == .settings,
                   select: { selection = .settings })
                .padding(.vertical, 6)
        }
    }
}
