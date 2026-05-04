import SwiftUI

/// Native window-toolbar content for ChungHwa. Hosts:
///   - the title (selected sidebar tab, serif) on the leading side
///   - reload + bell + profile pill + mode segmented + chip cluster on the
///     trailing side
///
/// On macOS 26 Tahoe the Liquid Glass title bar fuses traffic lights with
/// these toolbar items in a single row, so we no longer reproduce a custom
/// 48pt bar inside the detail VStack.
struct ChungHwaToolbar: ToolbarContent {
    let title: String
    var onSwitchToProfiles: (() -> Void)? = nil

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            ToolbarTitle(title: title)
        }
        ToolbarItem(placement: .primaryAction) {
            ToolbarTrailing(onSwitchToProfiles: onSwitchToProfiles)
        }
    }
}

// MARK: - title

private struct ToolbarTitle: View {
    let title: String

    var body: some View {
        Text(title)
            .font(ChungHwa.Typography.serif(18, weight: .medium))
            .foregroundStyle(ChungHwa.Palette.text)
            .tracking(-0.2)
    }
}

// MARK: - trailing cluster

private struct ToolbarTrailing: View {
    var onSwitchToProfiles: (() -> Void)? = nil

    @Environment(KernelController.self) private var kernel
    @Environment(ConfigStore.self) private var configStore
    @Environment(SystemProxyController.self) private var systemProxy
    @Environment(ProfileStore.self) private var profileStore
    @Environment(AnonymousMode.self) private var anon
    @Environment(NotificationCenterStore.self) private var notifications

    @State private var notificationsOpen = false

    var body: some View {
        HStack(spacing: 8) {
            reloadButton
            bellButton
            profilePill
            modeSegmented
            chipCluster
        }
    }

    // MARK: - reload + bell

    private var reloadButton: some View {
        let kernelReady = kernel.apiClient != nil
        return IconButton(
            symbol: "arrow.clockwise",
            help: "重载 mihomo 配置（保留连接）",
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
                ? "通知 · \(unread) 条新"
                : "通知",
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
              ? "出站模式（直连 / 规则 / 全局）"
              : "切换模式需要内核运行中")
    }

    private var profilePill: some View {
        let name = profileStore.profiles.first(where: { $0.id == profileStore.activeProfileID })?.name
            ?? "无配置"
        return Menu {
            if profileStore.profiles.isEmpty {
                Text("暂无配置")
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
            Button("管理配置…") {
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
        .help("当前配置 — 点击切换")
    }

    private var chipCluster: some View {
        HStack(spacing: 6) {
            ToggleChip(
                isOn: systemProxy.enabled,
                symbol: "network",
                tint: ChungHwa.Palette.patina,
                help: "系统代理 · \(systemProxy.enabled ? "已开" : "已关")",
                action: { systemProxy.toggle() }
            )
            ToggleChip(
                isOn: false,
                symbol: "shield.lefthalf.filled",
                tint: ChungHwa.Palette.brass,
                help: "TUN 模式 · 已关（需要特权辅助，M5+）",
                disabled: true,
                action: {}
            )
            ToggleChip(
                isOn: anon.enabled,
                symbol: anon.enabled ? "eye.slash" : "eye",
                tint: ChungHwa.Palette.ink,
                help: "匿名模式 · \(anon.enabled ? "已开（信息已隐藏）" : "已关")",
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
            Text("通知")
                .font(ChungHwa.Typography.serif(14, weight: .medium))
                .foregroundStyle(ChungHwa.Palette.text)
            Spacer(minLength: 6)
            Button("全部已读") { store.markAllRead() }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(ChungHwa.Palette.dim)
                .disabled(store.entries.isEmpty)
            Button("清空") { store.clear() }
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
                Text("暂无通知")
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
