import SwiftUI

/// Window-toolbar content. Reload / bell / profile / mode / chip cluster on
/// the trailing side. macOS 26's Liquid Glass title bar fuses traffic lights
/// with these items in a single row, so we don't reproduce a 48pt bar inside
/// the detail VStack.
struct ChungHwaToolbar: ToolbarContent {
    let title: String
    var onSwitchToProfiles: (() -> Void)? = nil

    var body: some ToolbarContent {
        // .navigationTitle carries the tab name — adding a custom title item
        // here would visually stack with it.
        ToolbarItem(placement: .primaryAction) { ToolbarReload() }
        ToolbarItem(placement: .primaryAction) { ToolbarBell() }
        ToolbarItem(placement: .primaryAction) {
            ToolbarProfile(onSwitchToProfiles: onSwitchToProfiles)
        }
        ToolbarItem(placement: .primaryAction) { ToolbarMode() }
        ToolbarItem(placement: .primaryAction) { ToolbarSysProxy() }
        ToolbarItem(placement: .primaryAction) { ToolbarTUN() }
        ToolbarItem(placement: .primaryAction) { ToolbarAnonymous() }
    }
}

private struct ToolbarTitle: View {
    let title: String

    var body: some View {
        Text(title)
            .font(ChungHwa.Typography.serif(18, weight: .medium))
            .foregroundStyle(ChungHwa.Palette.text)
            .tracking(-0.2)
    }
}

private struct ToolbarReload: View {
    @Environment(KernelController.self) private var kernel
    var body: some View {
        let ready = kernel.apiClient != nil
        Button {
            Task { await kernel.reload() }
        } label: {
            Image(systemName: "arrow.clockwise")
        }
        .disabled(!ready)
        .help("重载配置")
    }
}

private struct ToolbarBell: View {
    @Environment(NotificationCenterStore.self) private var notifications
    @State private var open = false
    var body: some View {
        let unread = notifications.unreadCount
        Button {
            open.toggle()
        } label: {
            Image(systemName: unread > 0 ? "bell.badge" : "bell")
                .foregroundStyle(unread > 0
                                 ? AnyShapeStyle(ChungHwa.Palette.brass)
                                 : AnyShapeStyle(.primary))
        }
        .help(unread > 0 ? "通知（\(unread) 条新）" : "通知")
        .popover(isPresented: $open, arrowEdge: .top) {
            NotificationsPopover(store: notifications)
                .onAppear { notifications.markAllRead() }
        }
    }
}

private struct ToolbarProfile: View {
    var onSwitchToProfiles: (() -> Void)? = nil

    @Environment(KernelController.self) private var kernel
    @Environment(ProfileStore.self) private var profileStore

    var body: some View {
        let name = profileStore.profiles.first(where: { $0.id == profileStore.activeProfileID })?.name
            ?? "无配置"
        Menu {
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
            // macOS toolbar Menu hides the Label's title by default; force
            // titleAndIcon so the active profile name appears.
            Label(name, systemImage: "doc.text")
                .labelStyle(.titleAndIcon)
        }
        .help("切换配置")
    }
}

private struct ToolbarMode: View {
    @Environment(KernelController.self) private var kernel
    @Environment(ConfigStore.self) private var configStore

    var body: some View {
        let kernelReady = kernel.apiClient != nil
        Picker("出站模式", selection: pickerBinding) {
            ForEach(MihomoMode.allCases, id: \.self) { mode in
                Text(mode.displayName).tag(Optional(mode))
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .disabled(!kernelReady)
        .help(kernelReady
              ? "出站模式：直连 / 规则 / 全局"
              : "需要内核运行中")
    }

    private var pickerBinding: Binding<MihomoMode?> {
        Binding(
            get: { configStore.mode },
            set: { newMode in
                guard let newMode, newMode != configStore.mode else { return }
                Task { await configStore.setMode(newMode, api: kernel.apiClient) }
            }
        )
    }
}

private struct ToolbarSysProxy: View {
    @Environment(SystemProxyController.self) private var systemProxy
    var body: some View {
        Button {
            systemProxy.toggle()
        } label: {
            Image(systemName: "network")
                .foregroundStyle(systemProxy.enabled
                                 ? AnyShapeStyle(ChungHwa.Palette.patina)
                                 : AnyShapeStyle(.primary))
        }
        .help(systemProxy.enabled ? "系统代理 已开" : "系统代理 已关")
    }
}

private struct ToolbarTUN: View {
    @Environment(KernelController.self) private var kernel
    @Environment(ConfigStore.self) private var config

    var body: some View {
        let kernelReady = kernel.apiClient != nil
        let on = config.tunEnabled
        Button {
            // If there's no privileged kernel installed, TUN can't actually
            // open /dev/utun — bounce to Settings so the user can grant
            // privileges instead of leaving them with a silent no-op.
            if !on, !KernelPrivilegeHelper.isPrivileged() {
                NotificationCenter.default.post(
                    name: .chungHwaSwitchTab,
                    object: SidebarTab.settings.rawValue
                )
                return
            }
            // mihomo's PATCH /configs accepts tun.enable=false but doesn't
            // reliably tear down the utun device at runtime; flip the
            // persisted pref then restart the kernel so the new yaml drives
            // a clean state. Same logic for on→off and off→on.
            Task {
                await config.setTUN(!on, api: kernel.apiClient)
                await kernel.restart()
            }
        } label: {
            Image(systemName: on ? "shield.lefthalf.filled" : "shield")
                .foregroundStyle(on
                                 ? AnyShapeStyle(ChungHwa.Palette.brass)
                                 : AnyShapeStyle(.primary))
        }
        .disabled(!kernelReady)
        .help(on ? "TUN 已开（需要 root）" : "TUN 已关")
    }
}

private struct ToolbarAnonymous: View {
    @Environment(AnonymousMode.self) private var anon
    var body: some View {
        Button {
            anon.enabled.toggle()
        } label: {
            Image(systemName: anon.enabled ? "eye.slash" : "eye")
                .foregroundStyle(anon.enabled
                                 ? AnyShapeStyle(ChungHwa.Palette.brass)
                                 : AnyShapeStyle(.primary))
        }
        .help(anon.enabled ? "匿名模式 已开" : "匿名模式 已关")
    }
}

/// 28pt borderless icon button for the reload + bell toolbar slots.
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
            Button("标为已读") { store.markAllRead() }
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
