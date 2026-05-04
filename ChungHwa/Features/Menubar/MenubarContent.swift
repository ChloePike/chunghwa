import AppKit
import SwiftUI

// MARK: - MenubarContent (rich SwiftUI popup, MenuBarExtraStyle.window)

/// 中華 菜单栏弹出窗口。固定 320pt 宽，玻璃底 + 大圆角，分七组 section。
/// 与 ClashMac 同款体验：头部状态、live 流量卡片、网络接管、出站模式、
/// per-group 节点切换、配置切换、Dashboard / 内核 / 偏好设置。
struct MenubarContent: View {
    @Environment(KernelController.self) private var kernel
    @Environment(SystemProxyController.self) private var systemProxy
    @Environment(ConfigStore.self) private var config
    @Environment(ProfileStore.self) private var profileStore
    @Environment(ProxyStore.self) private var proxyStore

    var body: some View {
        VStack(spacing: 0) {
            header
            // Live-stat strip subscribes to TrafficStore + ConnectionsStore
            // on its own. Extracted so 1Hz traffic ticks don't recompute
            // the entire popover (groupSection / profileSection / etc.).
            MenubarLiveStats()
                .padding(.top, 8)

            sectionDivider.padding(.vertical, 6)
            modeSection
            sectionDivider.padding(.vertical, 4)
            // 直接内联——组多了让弹窗变高，但 ScrollView 在 macOS Tahoe
            // 这套 .menuBarExtraStyle(.window) 下会把整段塌缩成 0 高度，
            // 与其折腾不如让它自然顶高。
            groupSection
            if !proxyStore.groups.isEmpty {
                sectionDivider.padding(.vertical, 4)
            }
            profileSection
            sectionDivider.padding(.vertical, 4)
            footerSection
        }
        .padding(8)
        .frame(width: 280)
        .background(.regularMaterial,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
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

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Text(statusSubtitle)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(ChungHwa.Palette.text)
                .lineLimit(1)

            Spacer(minLength: 0)

            HStack(spacing: 5) {
                ChDot(color: statusColor, size: 7, pulse: pulses)
                Text(statusLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(statusColor)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
    }

    private var activeProfileName: String {
        profileStore.profiles.first(where: { $0.id == profileStore.activeProfileID })?.name
            ?? "无配置"
    }

    private var statusLabel: String {
        switch kernel.status {
        case .running:  return "运行中"
        case .starting: return "启动中"
        case .failed:   return "失败"
        case .idle:     return "空闲"
        }
    }

    private var statusSubtitle: String {
        switch kernel.status {
        case .running(let v): return "mihomo \(v)"
        case .starting:       return "正在拉起内核"
        case .failed(let r):  return r.isEmpty ? "内核启动失败" : r
        case .idle:           return "内核未运行"
        }
    }

    private var statusColor: Color {
        switch kernel.status {
        case .running:  return ChungHwa.Palette.patina
        case .starting: return ChungHwa.Palette.brass
        case .failed:   return ChungHwa.Palette.earth
        case .idle:     return ChungHwa.Palette.dim
        }
    }

    private var pulses: Bool {
        switch kernel.status {
        case .running, .starting: return true
        default: return false
        }
    }

    // MARK: - Network section

    private var networkSection: some View {
        VStack(spacing: 0) {
            Menu {
                Button {
                    if !systemProxy.enabled { systemProxy.toggle() }
                } label: {
                    Label("系统代理", systemImage: systemProxy.enabled ? "checkmark" : "")
                }
                Button {
                    // TUN 切换尚未接入 — 占位提示用户
                } label: {
                    Label("TUN 模式（暂未接入）", systemImage: "")
                }
                .disabled(true)
            } label: {
                MenubarRowLabel(
                    icon: systemProxy.enabled ? "network" : "network.slash",
                    title: "网络接管",
                    trailing: systemProxy.enabled ? "系统代理" : "未启用",
                    showsChevron: true
                )
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)

            Button(action: copyProxyExports) {
                MenubarRowLabel(
                    icon: "doc.on.clipboard",
                    title: "复制代理导出",
                    trailing: "⌘C",
                    showsChevron: false
                )
            }
            .buttonStyle(.plain)
            .keyboardShortcut("c", modifiers: [.command])
        }
    }

    private func copyProxyExports() {
        let port = systemProxy.port
        let socks = port // mihomo mixed-port 同时承载 SOCKS5
        let payload = """
        export http_proxy=http://127.0.0.1:\(port)
        export https_proxy=http://127.0.0.1:\(port)
        export all_proxy=socks5://127.0.0.1:\(socks)
        """
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(payload, forType: .string)
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
            Menu {
                if let members = group.all, !members.isEmpty {
                    ForEach(members, id: \.self) { name in
                        Button {
                            Task {
                                await proxyStore.select(
                                    group: group.name,
                                    name: name,
                                    api: kernel.apiClient
                                )
                                await kernel.reload()
                            }
                        } label: {
                            Label(name, systemImage: name == group.now ? "checkmark" : "")
                        }
                    }
                } else {
                    Text("（无节点）")
                }
            } label: {
                MenubarRowLabel(icon: icon, title: group.name, trailing: now, showsChevron: true)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
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
        Menu {
            if profileStore.profiles.isEmpty {
                Text("（暂无配置）")
            } else {
                ForEach(profileStore.profiles) { p in
                    Button {
                        profileStore.activate(p.id)
                        Task { await kernel.reload() }
                    } label: {
                        Label(
                            p.name,
                            systemImage: profileStore.activeProfileID == p.id ? "checkmark" : ""
                        )
                    }
                }
            }
        } label: {
            MenubarRowLabel(
                icon: "doc.text",
                title: "切换配置",
                trailing: profileStore.activeProfile?.name ?? "—",
                showsChevron: true
            )
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
    }

    // MARK: - Dashboard section

    private var dashboardSection: some View {
        VStack(spacing: 0) {
            Button(action: showMainWindow) {
                MenubarRowLabel(
                    icon: "rectangle.on.rectangle",
                    title: "中華 Dashboard",
                    trailing: "⌘M",
                    showsChevron: false
                )
            }
            .buttonStyle(.plain)
            .keyboardShortcut("m", modifiers: [.command])

            Button(action: openWebDashboard) {
                MenubarRowLabel(
                    icon: "safari",
                    title: "Web Dashboard",
                    trailing: "⌘D",
                    showsChevron: false
                )
            }
            .buttonStyle(.plain)
            .keyboardShortcut("d", modifiers: [.command])
            .disabled(!isRunning)
        }
    }

    private func openWebDashboard() {
        guard let url = URL(string: "http://127.0.0.1:47913/ui") else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Kernel section

    private var kernelSection: some View {
        VStack(spacing: 0) {
            Menu {
                Button("启动内核") { Task { await kernel.start() } }
                    .disabled(isRunningOrStarting)
                Button("停止内核") { kernel.stop() }
                    .disabled(!isRunningOrStarting)
                Button("重启内核") { Task { await kernel.restart() } }
                    .disabled(!isRunningOrStarting)
                Divider()
                Button("重载配置") { Task { await kernel.reload() } }
                    .disabled(!isRunning)
                Button("查看日志目录") { openLogsDirectory() }
            } label: {
                MenubarRowLabel(
                    icon: "gearshape.2",
                    title: "内核管理",
                    trailing: kernelTrailingLabel,
                    showsChevron: true
                )
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)

            Menu {
                Button("打开 Application Support") { openAppSupportDirectory() }
                Button("打开 mihomo 数据目录") { openMihomoDataDirectory() }
            } label: {
                MenubarRowLabel(
                    icon: "folder",
                    title: "目录位置",
                    trailing: nil,
                    showsChevron: true
                )
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
        }
    }

    private var kernelTrailingLabel: String {
        switch kernel.status {
        case .running:  return "运行中"
        case .starting: return "启动中"
        case .failed:   return "失败"
        case .idle:     return "未运行"
        }
    }

    private func openLogsDirectory() {
        // ChungHwa 不显式写文件日志，统一打到 unified-log；这里打开
        // ~/Library/Logs/ChungHwa（不存在则降级到上层 Logs 目录）。
        let fm = FileManager.default
        let logs = fm.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/ChungHwa", isDirectory: true)
        let target: URL
        if fm.fileExists(atPath: logs.path) {
            target = logs
        } else {
            target = fm.urls(for: .libraryDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Logs", isDirectory: true)
        }
        NSWorkspace.shared.open(target)
    }

    private func openAppSupportDirectory() {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ChungHwa", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(dir)
    }

    private func openMihomoDataDirectory() {
        // mihomo 自带数据目录默认就是 Application Support/ChungHwa（kernel
        // 由我们复合 config 后启动）。这里直接复用同一路径。
        openAppSupportDirectory()
    }

    // MARK: - Footer section

    private var footerSection: some View {
        VStack(spacing: 0) {
            // 检查更新（mihomo 内核）— 暂走 Settings 流程，这里只触发后台
            // checkForUpdates，结果会在主窗口的 Settings 屏显示。
            Button(action: checkForUpdates) {
                MenubarRowLabel(
                    icon: "arrow.down.circle",
                    title: "检查内核更新",
                    trailing: "⌘K",
                    showsChevron: false
                )
            }
            .buttonStyle(.plain)
            .keyboardShortcut("k", modifiers: [.command])

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

    // 简化方案：菜单栏弹窗里没法直接拿 Sidebar selection（跨 Scene 边界），
    // 这里只把主窗口拉起来。后续可以走 NotificationCenter 跳到 Settings 屏。
    private func checkForUpdates() {
        // KernelDownloader 不在本视图的 environment 里（避免再加注入面），
        // 用 NotificationCenter 通知主窗口去执行；监听端尚未接入时静默。
        NotificationCenter.default.post(name: .chungHwaCheckKernelUpdate, object: nil)
    }

    private func openSettings() {
        showMainWindow()
    }

    // MARK: - Shared helpers

    private var sectionDivider: some View {
        Divider().opacity(0.3)
    }

    private var isRunningOrStarting: Bool {
        switch kernel.status {
        case .running, .starting: return true
        default: return false
        }
    }

    private var isRunning: Bool {
        if case .running = kernel.status { return true }
        return false
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
            Image(systemName: "memorychip")
                .font(.system(size: 10))
                .foregroundStyle(ChungHwa.Palette.dim)
            Text(ChFormat.bytes(traffic.memoryInUse))
                .font(ChungHwa.Typography.mono(10.5))
                .foregroundStyle(ChungHwa.Palette.dim)
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
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(tint ?? ChungHwa.Palette.dim)
                .frame(width: 16, alignment: .center)
            Text(title)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(tint ?? ChungHwa.Palette.text)
                .lineLimit(1)
            Spacer(minLength: 6)
            if let trailing, !trailing.isEmpty {
                Text(trailing)
                    .font(.system(size: 11.5))
                    .foregroundStyle(ChungHwa.Palette.dim)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(ChungHwa.Palette.faint)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(hovering ? ChungHwa.Palette.fill : Color.clear)
        )
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

/// macOS 菜单栏右上角的状态项：盾形图标 + 实时上下行速率（紧凑两行）。
/// 内容随 TrafficStore.current 每秒更新；kernel 没跑时只显图标省空间。
struct MenubarLabel: View {
    @Environment(KernelController.self) private var kernel
    @Environment(SystemProxyController.self) private var systemProxy
    @Environment(TrafficStore.self) private var traffic

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: MenubarIconName.current(
                kernel: kernel,
                systemProxy: systemProxy))
            if kernel.apiClient != nil {
                VStack(alignment: .trailing, spacing: 0) {
                    Text("↑ \(short(traffic.current?.upBps ?? 0))")
                    Text("↓ \(short(traffic.current?.downBps ?? 0))")
                }
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .lineSpacing(-1)
                .monospacedDigit()
            }
        }
    }

    /// 紧凑速率：菜单栏空间小，三位以内 + 单位。0 → "0"，<1 KB/s → "B"。
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
