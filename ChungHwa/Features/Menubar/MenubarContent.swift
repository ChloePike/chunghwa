import AppKit
import SwiftUI

// MARK: - MenubarContent (rich SwiftUI popup, MenuBarExtraStyle.window)

/// 中華 菜单栏弹出窗口。固定 280pt 宽，玻璃底 + 大圆角。
/// 头部（live 流量）→ 快捷开关 → 出站模式 → per-group 节点 → 配置 → 设置 / 退出。
struct MenubarContent: View {
    @Environment(KernelController.self) private var kernel
    @Environment(SystemProxyController.self) private var systemProxy
    @Environment(ConfigStore.self) private var config
    @Environment(ProfileStore.self) private var profileStore
    @Environment(ProxyStore.self) private var proxyStore
    @Environment(AnonymousMode.self) private var anon

    var body: some View {
        VStack(spacing: 0) {
            MenubarLiveStats()
                .padding(.top, 2)

            sectionDivider.padding(.vertical, 4)
            quickToggleRow
            sectionDivider.padding(.vertical, 4)
            modeSection
            sectionDivider.padding(.vertical, 3)
            // 节点组单行 + 左侧 popover；ScrollView 在 .menuBarExtraStyle(.window)
            // 下会塌缩，所以全部直接 inline。
            groupSection
            if !proxyStore.groups.isEmpty {
                sectionDivider.padding(.vertical, 3)
            }
            profileSection
            sectionDivider.padding(.vertical, 3)
            footerSection
        }
        .padding(6)
        .frame(width: 260)
        .background(.regularMaterial,
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(ChungHwa.Palette.line, lineWidth: 0.5)
        )
        .task(id: kernel.apiClient == nil ? "off" : "on") {
            // Re-run when kernel readiness flips. **Only** call the refresh
            // helpers when there's an actual API client — `refresh(api:nil)`
            // calls `reset()` and would wipe groups the main window just
            // hydrated.
            guard kernel.apiClient != nil else { return }
            await proxyStore.refresh(api: kernel.apiClient)
            await config.refresh(api: kernel.apiClient)
        }
    }

    // MARK: - Quick toggles row

    /// Three compact pills mirroring the toolbar chips: 系统代理 / TUN / 匿名.
    /// Same on/off visual language as the OverviewView hero pills.
    private var quickToggleRow: some View {
        HStack(spacing: 6) {
            togglePill(
                label: "系统代理",
                symbol: "network",
                on: systemProxy.enabled
            ) {
                systemProxy.toggle()
            }
            togglePill(
                label: "TUN",
                symbol: "shield.lefthalf.filled",
                on: config.tunEnabled,
                disabled: kernel.apiClient == nil
            ) {
                Task { await config.setTUN(!config.tunEnabled, api: kernel.apiClient) }
            }
            togglePill(
                label: "匿名",
                symbol: "eye.slash",
                on: anon.enabled
            ) {
                anon.enabled.toggle()
            }
        }
        .padding(.horizontal, 4)
    }

    private func togglePill(
        label: String,
        symbol: String,
        on: Bool,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: 9.5, weight: .medium))
                Text(label)
                    .font(.system(size: 10.5, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(on ? ChungHwa.Palette.patina : ChungHwa.Palette.faint)
            .frame(maxWidth: .infinity)
            .frame(height: 20)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(on ? ChungHwa.Palette.patina.opacity(0.10) : ChungHwa.Palette.fill)
                    .strokeBorder(on ? ChungHwa.Palette.patina.opacity(0.30) : ChungHwa.Palette.line,
                                  lineWidth: 0.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
    }

    // MARK: - Mode section

    /// Mode picker as a popup menu — click the right-side label to drop a
    /// 3-option select.
    private var modeSection: some View {
        let kernelReady = kernel.apiClient != nil
        return HStack(spacing: 4) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 11))
                .foregroundStyle(ChungHwa.Palette.dim)
                .frame(width: 14)
            Text("模式")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(ChungHwa.Palette.dim)
            Spacer(minLength: 8)
            Picker("出站模式", selection: modePickerBinding) {
                ForEach([MihomoMode.direct, .rule, .global], id: \.self) { mode in
                    Text(mode.displayName).tag(Optional(mode))
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
            .disabled(!kernelReady)
            .opacity(kernelReady ? 1 : 0.5)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .help(kernelReady ? "出站模式" : "切换模式需要内核运行中")
    }

    private var modePickerBinding: Binding<MihomoMode?> {
        Binding(
            get: { config.mode },
            set: { newMode in
                guard let newMode, newMode != config.mode else { return }
                Task { await config.setMode(newMode, api: kernel.apiClient) }
            }
        )
    }

    // MARK: - Group section

    @ViewBuilder
    private var groupSection: some View {
        if proxyStore.groups.isEmpty {
            MenubarRowLabel(
                icon: "globe",
                title: "无可用代理组",
                trailing: nil,
                showsChevron: false
            )
            .opacity(0.5)
        } else {
            VStack(spacing: 0) {
                ForEach(proxyStore.groups) { group in
                    groupRow(group)
                }
            }
        }
    }

    @ViewBuilder
    private func groupRow(_ group: MihomoProxy) -> some View {
        let icon = groupIcon(for: group)
        let now = group.now ?? "—"
        if group.isUserSwitchable {
            // Popover instead of Menu — Menu inside .menuBarExtraStyle(.window)
            // expands the popup downward; popover with arrowEdge .leading
            // floats out the LEFT side of the menubar item (where there's
            // actual screen space), which is the standard cascade direction.
            GroupPickerRow(
                group: group,
                icon: icon,
                now: now,
                onSelect: { name in
                    Task {
                        await proxyStore.select(group: group.name, name: name, api: kernel.apiClient)
                        await kernel.reload()
                    }
                }
            )
        } else {
            MenubarRowLabel(icon: icon, title: group.name, trailing: now, showsChevron: false)
        }
    }

    private func groupIcon(for g: MihomoProxy) -> String {
        switch g.type.lowercased() {
        case "selector":    return "hand.tap"
        case "urltest":     return "bolt.horizontal"
        case "fallback":    return "arrow.uturn.backward.circle"
        case "loadbalance": return "scale.3d"
        case "relay":       return "arrow.triangle.swap"
        default:            return "globe"
        }
    }

    // MARK: - Profile section

    private var profileSection: some View {
        ProfilePickerRow(
            profiles: profileStore.profiles,
            activeID: profileStore.activeProfileID,
            onSelect: { id in
                profileStore.activate(id)
                Task { await kernel.reload() }
            }
        )
    }

    // MARK: - Footer section

    private var footerSection: some View {
        VStack(spacing: 0) {
            Button(action: openSettings) {
                MenubarRowLabel(
                    icon: "gearshape",
                    title: "设置",
                    trailing: "⌘,",
                    showsChevron: false
                )
            }
            .buttonStyle(.plain)
            .keyboardShortcut(",", modifiers: [.command])

            Button(action: { NSApp.terminate(nil) }) {
                MenubarRowLabel(
                    icon: "power",
                    title: "退出中華",
                    trailing: "⌘Q",
                    showsChevron: false,
                    tint: ChungHwa.Palette.earth
                )
            }
            .buttonStyle(.plain)
            .keyboardShortcut("q", modifiers: [.command])
        }
    }

    private func openSettings() {
        showMainWindow()
    }

    // MARK: - Shared helpers

    private var sectionDivider: some View {
        Divider().opacity(0.3)
    }

    private func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        for w in NSApp.windows where w.canBecomeKey {
            w.makeKeyAndOrderFront(nil)
            return
        }
    }
}

// MARK: - Notification placeholder

extension Notification.Name {
    /// 菜单栏「检查内核更新」按下时发出。监听端（主窗口 Settings）暂未接入，
    /// 后续再补；不接也不会报错，只是按钮变成 no-op。
    static let chungHwaCheckKernelUpdate = Notification.Name("ChungHwa.CheckKernelUpdate")
}

// MARK: - Live stats strip

/// Compact live-stat strip extracted as a leaf so the surrounding popover
/// (group/profile menus etc.) does not re-evaluate when TrafficStore or
/// ConnectionsStore tick at 1Hz. Only this view subscribes to those stores.
private struct MenubarLiveStats: View {
    @Environment(TrafficStore.self) private var traffic
    @Environment(ConnectionsStore.self) private var connectionsStore

    var body: some View {
        let up = traffic.current?.upBps ?? 0
        let down = traffic.current?.downBps ?? 0
        HStack(spacing: 8) {
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 10))
                .foregroundStyle(ChungHwa.Palette.dim)
            Text("\(connectionsStore.connections.count)")
                .font(ChungHwa.Typography.mono(11, weight: .semibold))
                .foregroundStyle(ChungHwa.Palette.text)
            Text("·").foregroundStyle(ChungHwa.Palette.faint)
            Text("↑ \(ChFormat.rate(up))")
                .font(ChungHwa.Typography.mono(10.5))
                .foregroundStyle(ChungHwa.Palette.patina)
            Text("↓ \(ChFormat.rate(down))")
                .font(ChungHwa.Typography.mono(10.5))
                .foregroundStyle(ChungHwa.Palette.brass)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .monospacedDigit()
    }
}

// MARK: - Row primitive

/// 单行菜单项的显示标签：左 icon、中 title、右可选 trailing label + chevron。
/// 点击高亮由父 Button/Menu 的 hover 渲染，但 .plain 不带高亮，于是我们在
/// onHover 里手动加 fill 背景。
private struct MenubarRowLabel: View {
    let icon: String
    let title: String
    let trailing: String?
    let showsChevron: Bool
    var tint: Color? = nil   // nil → 默认 Palette.text；非 nil → icon + 文字都改色

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 11.5))
                .foregroundStyle(tint ?? ChungHwa.Palette.dim)
                .frame(width: 14, alignment: .center)
            Text(title)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(tint ?? ChungHwa.Palette.text)
                .lineLimit(1)
            Spacer(minLength: 6)
            if let trailing, !trailing.isEmpty {
                Text(trailing)
                    .font(.system(size: 10.5))
                    .foregroundStyle(ChungHwa.Palette.dim)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(ChungHwa.Palette.faint)
            }
        }
        .padding(.horizontal, 7)
        .frame(height: 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(hovering ? ChungHwa.Palette.fill : Color.clear)
        )
        .onHover { hovering = $0 }
    }
}

// MARK: - Picker rows (left-side popovers)

/// Tappable row for a switchable proxy group. Click → popover slides out the
/// LEFT edge with a scrollable node list. The popover is its own NSPanel so
/// internal ScrollView works (unlike the parent .menuBarExtraStyle(.window)).
private struct GroupPickerRow: View {
    let group: MihomoProxy
    let icon: String
    let now: String
    let onSelect: (String) -> Void

    @State private var presented = false

    var body: some View {
        Button { presented = true } label: {
            MenubarRowLabel(icon: icon, title: group.name, trailing: now, showsChevron: true)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $presented, arrowEdge: .leading) {
            NodeListPopover(
                names: group.all ?? [],
                activeName: group.now
            ) { name in
                onSelect(name)
                presented = false
            }
        }
    }
}

/// Tappable row that swaps the active profile.
private struct ProfilePickerRow: View {
    let profiles: [Profile]
    let activeID: UUID?
    let onSelect: (UUID) -> Void

    @State private var presented = false

    var body: some View {
        Button { presented = true } label: {
            MenubarRowLabel(
                icon: "doc.text",
                title: "切换配置",
                trailing: profiles.first(where: { $0.id == activeID })?.name ?? "—",
                showsChevron: true
            )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $presented, arrowEdge: .leading) {
            ProfileListPopover(
                profiles: profiles,
                activeID: activeID
            ) { id in
                onSelect(id)
                presented = false
            }
        }
    }
}

private struct NodeListPopover: View {
    let names: [String]
    let activeName: String?
    let onTap: (String) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if names.isEmpty {
                    Text("（无节点）")
                        .font(.system(size: 11.5))
                        .foregroundStyle(ChungHwa.Palette.dim)
                        .padding(.vertical, 10)
                } else {
                    ForEach(names, id: \.self) { name in
                        PickerRow(
                            label: name,
                            isActive: name == activeName,
                            action: { onTap(name) }
                        )
                    }
                }
            }
            .padding(4)
        }
        .frame(width: 240)
        .frame(minHeight: 36, maxHeight: 380)
    }
}

private struct ProfileListPopover: View {
    let profiles: [Profile]
    let activeID: UUID?
    let onTap: (UUID) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if profiles.isEmpty {
                    Text("（暂无配置）")
                        .font(.system(size: 11.5))
                        .foregroundStyle(ChungHwa.Palette.dim)
                        .padding(.vertical, 10)
                } else {
                    ForEach(profiles) { p in
                        PickerRow(
                            label: p.name,
                            isActive: p.id == activeID,
                            action: { onTap(p.id) }
                        )
                    }
                }
            }
            .padding(4)
        }
        .frame(width: 240)
        .frame(minHeight: 36, maxHeight: 320)
    }
}

private struct PickerRow: View {
    let label: String
    let isActive: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: isActive ? "checkmark" : "")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(ChungHwa.Palette.brass)
                    .frame(width: 12, alignment: .center)
                Text(label)
                    .font(.system(size: 11.5))
                    .foregroundStyle(ChungHwa.Palette.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .frame(height: 22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(hovering ? ChungHwa.Palette.fill : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - Menubar icon (status-driven SF Symbol, unchanged from before)

@MainActor
struct MenubarIconName {
    static func current(kernel: KernelController, systemProxy: SystemProxyController) -> String {
        switch kernel.status {
        case .failed:    return "shield.slash"
        case .starting:  return "shield"
        case .idle:      return "shield"
        case .running:   return systemProxy.enabled ? "shield.lefthalf.filled" : "shield"
        }
    }
}

// MARK: - Menubar status bar label (icon + ↑↓ speeds)

/// macOS 菜单栏状态项：盾形图标 + 实时上下行速率，单行横排。
/// 字号走 NSFont menuBarFont 体感（11pt）确保看得清；内核没跑时只显图标。
struct MenubarLabel: View {
    @Environment(KernelController.self) private var kernel
    @Environment(SystemProxyController.self) private var systemProxy
    @Environment(TrafficStore.self) private var traffic

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: MenubarIconName.current(
                kernel: kernel,
                systemProxy: systemProxy))
            if kernel.apiClient != nil {
                Text("↑\(short(traffic.current?.upBps ?? 0)) ↓\(short(traffic.current?.downBps ?? 0))")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .monospacedDigit()
            }
        }
    }

    /// 紧凑速率：菜单栏空间有限，三位以内 + 单位。0 → "0"，<1 KB/s → "B"。
    private func short(_ bps: Int) -> String {
        switch bps {
        case 0:               return "0"
        case ..<1024:         return "\(bps)B"
        case ..<1_048_576:    return String(format: "%.0fK", Double(bps) / 1024)
        case ..<1_073_741_824: return String(format: "%.1fM", Double(bps) / 1_048_576)
        default:               return String(format: "%.1fG", Double(bps) / 1_073_741_824)
        }
    }
}
