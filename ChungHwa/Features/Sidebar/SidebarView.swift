import SwiftUI

struct SidebarView: View {
    @Binding var selection: SidebarTab?

    var body: some View {
        List(selection: $selection) {
            ForEach(SidebarTab.sections) { section in
                Section {
                    ForEach(section.tabs) { tab in
                        Label(tab.title, systemImage: tab.symbol)
                            .tag(Optional(tab))
                    }
                } header: {
                    if let h = section.header {
                        Text(h)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(ChungHwa.Palette.faint)
                            .textCase(.uppercase)
                            .tracking(0.4)
                    } else {
                        BrandHeader().padding(.bottom, 4)
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SettingsFooter(selection: $selection)
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
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
        .padding(.top, 2)
    }
}

private struct SettingsFooter: View {
    @Binding var selection: SidebarTab?

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            Button {
                selection = .settings
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: SidebarTab.settings.symbol)
                        .font(.system(size: 13))
                    Text(SidebarTab.settings.title)
                        .font(.system(size: 12.5, weight: selection == .settings ? .semibold : .medium))
                    Spacer()
                }
                .foregroundStyle(selection == .settings
                                 ? ChungHwa.Palette.text
                                 : ChungHwa.Palette.dim)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(selection == .settings
                              ? ChungHwa.Palette.sideActive
                              : Color.clear)
                )
            }
            .buttonStyle(.plain)
            .padding(6)
        }
    }
}
