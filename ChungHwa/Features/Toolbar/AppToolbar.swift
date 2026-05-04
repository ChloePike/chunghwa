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
    var onSwitchToProfiles: (() -> Void)? = nil

    @Environment(KernelController.self) private var kernel
    @Environment(ConfigStore.self) private var configStore
    @Environment(SystemProxyController.self) private var systemProxy
    @Environment(ProfileStore.self) private var profileStore
    @Environment(AnonymousMode.self) private var anon
    @Environment(NotificationCenterStore.self) private var notifications

    @State private var notificationsOpen = false

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(ChungHwa.Typography.serif(18, weight: .medium))
                .foregroundStyle(ChungHwa.Palette.text)
                .tracking(-0.2)

            Spacer()

            reloadButton
            bellButton
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

    // MARK: - reload + bell

    private var reloadButton: some View {
        let kernelReady = kernel.apiClient != nil
        return IconButton(
            symbol: "arrow.clockwise",
            help: "Reload mihomo config (preserves connections)",
            disabled: !kernelReady
        ) {
            Task { await kernel.reload() }
        }
    }

    private var bellButton: some View {
        let unread = notifications.unreadCount
        let symbol = unread > 0 ? "bell.badge" : "bell"
        return IconButton(
            symbol: symbol,
            help: unread > 0
                ? "Notifications · \(unread) new"
                : "Notifications",
            tint: unread > 0 ? ChungHwa.Palette.brass : nil
        ) {
            notificationsOpen.toggle()
        }
        .popover(isPresented: $notificationsOpen, arrowEdge: .top) {
            NotificationsPopover(store: notifications)
                .onAppear { notifications.markAllRead() }
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
        return Menu {
            if profileStore.profiles.isEmpty {
                Text("No profiles")
            } else {
                ForEach(profileStore.profiles) { p in
                    Button {
                        profileStore.activate(p.id)
                        Task { await kernel.reload() }
                    } label: {
                        if profileStore.activeProfileID == p.id {
                            Label(p.name, systemImage: "checkmark")
                        } else {
                            Text(p.name)
                        }
                    }
                }
            }
            Divider()
            Button("Manage profiles…") {
                onSwitchToProfiles?()
            }
        } label: {
            HStack(spacing: 6) {
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
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Active profile — click to switch")
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

// MARK: - icon button (reload / bell)

/// Borderless 28pt icon button used by the reload + bell toolbar slots.
/// Matches the visual weight of the chips' off-state (no fill, soft border on
/// hover) without the chip badge.
private struct IconButton: View {
    let symbol: String
    let help: String
    var disabled: Bool = false
    var tint: Color? = nil
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(tint ?? ChungHwa.Palette.dim)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(hovered && !disabled
                              ? ChungHwa.Palette.fill
                              : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(hovered && !disabled
                                      ? ChungHwa.Palette.line
                                      : Color.clear,
                                      lineWidth: 0.5)
                )
                .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .opacity(disabled ? 0.4 : 1)
        .disabled(disabled)
        .onHover { hovered = $0 }
        .help(help)
    }
}

// MARK: - notifications popover

private struct NotificationsPopover: View {
    let store: NotificationCenterStore

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(width: 320)
        .frame(maxHeight: 360)
        .background(ChungHwa.Palette.card)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Notifications")
                .font(ChungHwa.Typography.serif(14, weight: .medium))
                .foregroundStyle(ChungHwa.Palette.text)
            Spacer(minLength: 6)
            Button("Mark all read") { store.markAllRead() }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(ChungHwa.Palette.dim)
                .disabled(store.entries.isEmpty)
            Button("Clear") { store.clear() }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(ChungHwa.Palette.dim)
                .disabled(store.entries.isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var content: some View {
        if store.entries.isEmpty {
            VStack {
                Spacer()
                Text("No notifications")
                    .font(.system(size: 11))
                    .foregroundStyle(ChungHwa.Palette.faint)
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .frame(height: 120)
        } else {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(store.entries.prefix(10))) { entry in
                        Row(entry: entry, formatter: Self.relativeFormatter)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                        if entry.id != store.entries.prefix(10).last?.id {
                            Divider().opacity(0.4)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private struct Row: View {
        let entry: NotificationCenterStore.Entry
        let formatter: RelativeDateTimeFormatter

        private var dotColor: Color {
            switch entry.level {
            case .info:    return ChungHwa.Palette.patina
            case .warning: return ChungHwa.Palette.brass
            case .error:   return ChungHwa.Palette.earth
            }
        }

        var body: some View {
            HStack(alignment: .top, spacing: 8) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 7, height: 7)
                    .padding(.top, 5)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("[\(entry.source)]")
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(ChungHwa.Palette.dim)
                        Spacer(minLength: 4)
                        Text(formatter.localizedString(for: entry.posted, relativeTo: Date()))
                            .font(.system(size: 10.5))
                            .foregroundStyle(ChungHwa.Palette.faint)
                            .monospacedDigit()
                    }
                    Text(entry.message)
                        .font(.system(size: 11.5))
                        .foregroundStyle(ChungHwa.Palette.text)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}
