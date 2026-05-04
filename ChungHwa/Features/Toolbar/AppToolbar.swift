import SwiftUI

/// Custom top bar that sits above each detail screen, mirroring the design
/// in `design/src/app.jsx` Toolbar(). It hosts:
///   - the title (selected sidebar tab, serif)
///   - mode segmented control (`/configs.mode`)
///   - active profile pill (read-only for now; full picker comes with the
///     Profiles tab)
///   - three toggle chips (System Proxy / TUN / Anonymous)
///
/// The window's native title bar still draws the traffic lights and the
/// sidebar collapse, so we don't reproduce those here.
struct AppToolbar: View {
    let title: String

    @Environment(KernelController.self) private var kernel
    @Environment(ConfigStore.self) private var configStore
    @Environment(SystemProxyController.self) private var systemProxy
    @Environment(ProfileStore.self) private var profileStore
    @Environment(AnonymousMode.self) private var anon

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(ChungHwa.Typography.serif(18, weight: .medium))
                .foregroundStyle(ChungHwa.Palette.text)
                .tracking(-0.2)

            Spacer()

            profilePill
            modeSegmented
            chipCluster
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .background(ChungHwa.Palette.bg)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(ChungHwa.Palette.line)
                .frame(height: 0.5)
        }
    }

    // MARK: - segments

    private var modeSegmented: some View {
        let active = configStore.mode
        let kernelReady = kernel.apiClient != nil
        return HStack(spacing: 0) {
            ForEach(MihomoMode.allCases, id: \.self) { mode in
                Button {
                    Task { await configStore.setMode(mode, api: kernel.apiClient) }
                } label: {
                    Text(mode.displayName)
                        .font(.system(size: 12, weight: active == mode ? .semibold : .medium))
                        .foregroundStyle(active == mode
                                         ? ChungHwa.Palette.text
                                         : ChungHwa.Palette.dim)
                        .padding(.horizontal, 12)
                        .frame(height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 7)
                                .fill(active == mode ? ChungHwa.Palette.pillBg : Color.clear)
                                .shadow(color: active == mode ? .black.opacity(0.06) : .clear,
                                        radius: 1, y: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(ChungHwa.Palette.fill)
                .strokeBorder(ChungHwa.Palette.line, lineWidth: 0.5)
        )
        .opacity(kernelReady ? 1 : 0.5)
        .disabled(!kernelReady)
        .help(kernelReady
              ? "Outbound mode (Direct / Rule / Global)"
              : "Mode switching requires a running kernel")
    }

    private var profilePill: some View {
        let name = profileStore.profiles.first(where: { $0.id == profileStore.activeProfileID })?.name
            ?? "No profile"
        return HStack(spacing: 6) {
            Text(name)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(ChungHwa.Palette.text)
                .lineLimit(1)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(ChungHwa.Palette.dim)
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(ChungHwa.Palette.pillBg)
                .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
        )
        .overlay(RoundedRectangle(cornerRadius: 8)
            .strokeBorder(ChungHwa.Palette.line, lineWidth: 0.5))
        .help("Active profile (open Profiles tab to switch)")
    }

    private var chipCluster: some View {
        HStack(spacing: 6) {
            ToggleChip(
                isOn: systemProxy.enabled,
                symbol: "network",
                tint: ChungHwa.Palette.patina,
                help: "System Proxy · \(systemProxy.enabled ? "ON" : "OFF")",
                action: { systemProxy.toggle() }
            )
            ToggleChip(
                isOn: false,
                symbol: "shield.lefthalf.filled",
                tint: ChungHwa.Palette.brass,
                help: "TUN Mode · OFF (requires privileged helper, M5+)",
                disabled: true,
                action: {}
            )
            ToggleChip(
                isOn: anon.enabled,
                symbol: anon.enabled ? "eye.slash" : "eye",
                tint: ChungHwa.Palette.ink,
                help: "Anonymous Mode · \(anon.enabled ? "ON (info masked)" : "OFF")",
                action: { anon.enabled.toggle() }
            )
        }
    }
}

// MARK: - chip

private struct ToggleChip: View {
    let isOn: Bool
    let symbol: String
    let tint: Color
    let help: String
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isOn ? .white : ChungHwa.Palette.dim)
                    .frame(width: 30, height: 30)
                    .background(
                        Circle()
                            .fill(isOn
                                  ? AnyShapeStyle(LinearGradient(
                                      colors: [tint, tint.opacity(0.85)],
                                      startPoint: .topLeading, endPoint: .bottomTrailing))
                                  : AnyShapeStyle(ChungHwa.Palette.fill))
                    )
                    .overlay(Circle().strokeBorder(
                        isOn ? tint.opacity(0.4) : ChungHwa.Palette.line,
                        lineWidth: 0.5))
                    .shadow(color: isOn ? tint.opacity(0.25) : .clear, radius: 3, y: 1)

                if isOn {
                    Circle()
                        .fill(ChungHwa.Palette.patina)
                        .frame(width: 8, height: 8)
                        .overlay(Circle().strokeBorder(ChungHwa.Palette.bg, lineWidth: 1.5))
                        .offset(x: 1, y: 1)
                }
            }
        }
        .buttonStyle(.plain)
        .opacity(disabled ? 0.5 : 1)
        .disabled(disabled)
        .help(help)
    }
}
