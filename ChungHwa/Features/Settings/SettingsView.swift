import AppKit
import SwiftUI

/// Settings tab — "Bone & Brass on Patina" reskin.
///
/// Profiles management lives in its own `ProfilesView` (see
/// `Features/Profiles/`). This view focuses on app-level metadata and the
/// kernel binary lifecycle.
struct SettingsView: View {
    @Environment(KernelController.self) private var kernel
    @Environment(KernelBinaryResolver.self) private var resolver
    @Environment(KernelDownloader.self) private var downloader
    @Environment(LoginItemController.self) private var loginItem
    @AppStorage("ChungHwa.CloseKeepsRunning") private var closeKeepsRunning: Bool = true
    @AppStorage("ChungHwa.HideDockIcon") private var hideDockIcon: Bool = false

    @State private var localChecking: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                aboutCard
                startupCard
                updatesCard
                kernelBinaryCard
                resetCard
                Color.clear.frame(height: 12)
            }
            .padding(20)
            .frame(maxWidth: 720, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .background(ChungHwa.Palette.bg)
    }

    // MARK: - About

    private var aboutCard: some View {
        ChCardWithHeader("关于",
                         systemImage: "info.circle",
                         iconColor: ChungHwa.Palette.brass) {
            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(ChungHwa.Palette.brass.opacity(0.16))
                        .frame(width: 56, height: 56)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(ChungHwa.Palette.brass.opacity(0.35),
                                              lineWidth: 0.5)
                        )
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.system(size: 26, weight: .regular))
                        .foregroundStyle(ChungHwa.Palette.brass)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("中華")
                        .font(ChungHwa.Typography.serif(22, weight: .semibold))
                        .foregroundStyle(ChungHwa.Palette.text)
                        .tracking(-0.4)
                    Text("macOS 上的 mihomo 客户端 · v\(Self.shortVersion)+\(Self.buildVersion)")
                        .font(.system(size: 11.5))
                        .foregroundStyle(ChungHwa.Palette.dim)
                        .textSelection(.enabled)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.top, 4)
            .padding(.bottom, 6)
        }
    }

    private static var shortVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0"
    }

    private static var buildVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    // MARK: - Startup

    private var startupCard: some View {
        ChCardWithHeader("启动",
                         systemImage: "power",
                         iconColor: ChungHwa.Palette.brass) {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(isOn: Binding(
                        get: { loginItem.isRegistered },
                        set: { loginItem.setEnabled($0) }
                    )) {
                        Text("开机启动")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(ChungHwa.Palette.text)
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)

                    if let err = loginItem.lastError {
                        Text(err)
                            .font(.system(size: 11))
                            .foregroundStyle(.red)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Toggle(isOn: $closeKeepsRunning) {
                    Text("关窗保持后台运行")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(ChungHwa.Palette.text)
                }
                .toggleStyle(.switch)
                .controlSize(.small)

                VStack(alignment: .leading, spacing: 4) {
                    Toggle(isOn: $hideDockIcon) {
                        Text("隐藏 Dock 图标")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(ChungHwa.Palette.text)
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .onChange(of: hideDockIcon) { _, newValue in
                        NSApp.setActivationPolicy(newValue ? .accessory : .regular)
                    }

                    Text("仅作为菜单栏应用运行。无 Dock 图标、无 cmd-tab。可通过菜单栏唤回。")
                        .font(.system(size: 11))
                        .foregroundStyle(ChungHwa.Palette.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 2)
            .padding(.bottom, 4)
        }
    }

    // MARK: - Updates

    private var updatesCard: some View {
        ChCardWithHeader("更新",
                         systemImage: "arrow.down.circle",
                         iconColor: ChungHwa.Palette.patina) {
            VStack(alignment: .leading, spacing: 10) {
                installedRow
                latestRow
                lastCheckedRow

                HStack(spacing: 10) {
                    BrassButton(title: "立即检查", systemImage: "arrow.clockwise") {
                        Task {
                            localChecking = true
                            await downloader.checkForUpdates()
                            localChecking = false
                        }
                    }
                    .disabled(isChecking)
                    .opacity(isChecking ? 0.55 : 1)

                    if shouldShowUpdateButton {
                        GhostButton(title: "更新内核",
                                    systemImage: "arrow.down.circle") {
                            Task {
                                await downloader.updateLatest()
                                if case .completed = downloader.state {
                                    await kernel.restart()
                                }
                            }
                        }
                        .disabled(downloader.isWorking)
                        .opacity(downloader.isWorking ? 0.55 : 1)
                    }

                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 2)
        }
    }

    private var isChecking: Bool {
        localChecking || downloader.isWorking
    }

    private var installedVersion: String? {
        // Managed binaries have a sidecar version file; for bundled / custom
        // we fall back to whatever the running kernel reports.
        if let b = resolver.current, b.source == .managed,
           let v = resolver.managedVersion() {
            return v
        }
        if case .running(let v) = kernel.status, !v.isEmpty {
            return v
        }
        return nil
    }

    private var shouldShowUpdateButton: Bool {
        guard let latest = downloader.latestKnown else { return false }
        if let installed = installedVersion, installed == latest { return false }
        return true
    }

    @ViewBuilder
    private var installedRow: some View {
        HStack(spacing: 8) {
            Text("已安装")
                .font(.system(size: 11.5))
                .foregroundStyle(ChungHwa.Palette.dim)
                .frame(width: 110, alignment: .leading)
            Text(installedVersion ?? "—")
                .font(ChungHwa.Typography.mono(11.5))
                .foregroundStyle(ChungHwa.Palette.text)
                .textSelection(.enabled)
            Spacer(minLength: 0)
            if let b = resolver.current {
                SourceBadge(source: b.source)
            }
        }
    }

    @ViewBuilder
    private var latestRow: some View {
        HStack(spacing: 8) {
            Text("最新可用")
                .font(.system(size: 11.5))
                .foregroundStyle(ChungHwa.Palette.dim)
                .frame(width: 110, alignment: .leading)
            Text(downloader.latestKnown ?? "—")
                .font(ChungHwa.Typography.mono(11.5))
                .foregroundStyle(ChungHwa.Palette.text)
                .textSelection(.enabled)
            if let latest = downloader.latestKnown,
               installedVersion != latest {
                NewBadge()
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var lastCheckedRow: some View {
        HStack(spacing: 8) {
            Text("上次检查")
                .font(.system(size: 11))
                .foregroundStyle(ChungHwa.Palette.dim)
                .frame(width: 110, alignment: .leading)
            Text(lastCheckedText)
                .font(.system(size: 11))
                .foregroundStyle(ChungHwa.Palette.dim)
            Spacer(minLength: 0)
        }
    }

    private var lastCheckedText: String {
        guard let d = downloader.lastChecked else { return "从未" }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: d, relativeTo: .now)
    }

    // MARK: - Kernel binary

    private var kernelBinaryCard: some View {
        ChCardWithHeader("内核二进制",
                         systemImage: "cpu",
                         iconColor: ChungHwa.Palette.patina,
                         right: { managedVersionTag }) {
            VStack(alignment: .leading, spacing: 12) {
                if let b = resolver.current {
                    HStack(spacing: 8) {
                        SourceBadge(source: b.source)
                        Spacer(minLength: 0)
                    }
                    Text(b.url.path)
                        .font(ChungHwa.Typography.mono(11))
                        .foregroundStyle(ChungHwa.Palette.dim)
                        .textSelection(.enabled)
                        .lineLimit(2)
                        .truncationMode(.middle)
                } else {
                    Label("未找到内核二进制", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(ChungHwa.Palette.earth)
                }

                downloaderProgressLine

                HStack(spacing: 10) {
                    BrassButton(title: "更新内核", systemImage: "arrow.down.circle") {
                        Task {
                            await downloader.updateLatest()
                            if case .completed = downloader.state {
                                await kernel.restart()
                            }
                        }
                    }
                    .disabled(downloader.isWorking)
                    .opacity(downloader.isWorking ? 0.55 : 1)

                    GhostButton(title: "选择自定义二进制…",
                                systemImage: "folder") {
                        pickCustomBinary()
                    }

                    if resolver.customPath != nil || resolver.current?.source == .managed {
                        GhostButton(title: "恢复内置",
                                    systemImage: "arrow.uturn.backward",
                                    tone: .destructive) {
                            try? resolver.resetToBundled()
                            downloader.reset()
                            Task { await kernel.restart() }
                        }
                    }

                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 2)
        }
    }

    @ViewBuilder
    private var managedVersionTag: some View {
        if let b = resolver.current, b.source == .managed,
           let v = resolver.managedVersion() {
            Text("已安装 \(v)")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(ChungHwa.Palette.dim)
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private var downloaderProgressLine: some View {
        switch downloader.state {
        case .idle:
            EmptyView()
        case .fetchingMetadata:
            progressRow("查询 GitHub Releases…")
        case .downloading(let v):
            progressRow("下载 \(v) 中…")
        case .extracting(let v):
            progressRow("解压 \(v) 中…")
        case .installing(let v):
            progressRow("安装 \(v) 中…")
        case .completed(let v):
            Label("已安装 \(v)", systemImage: "checkmark.circle.fill")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(ChungHwa.Palette.patina)
        case .failed(let msg):
            Label(msg, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(ChungHwa.Palette.earth)
                .lineLimit(3)
        }
    }

    private func progressRow(_ text: String) -> some View {
        HStack(spacing: 6) {
            ProgressView().controlSize(.mini)
            Text(text)
                .font(.system(size: 11.5))
                .foregroundStyle(ChungHwa.Palette.dim)
        }
    }

    private func pickCustomBinary() {
        let panel = NSOpenPanel()
        panel.title = "选择 mihomo 二进制"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            resolver.customPath = url
            Task { await kernel.restart() }
        }
    }

    // MARK: - Reset / footer

    private var resetCard: some View {
        ChCardWithHeader("存储",
                         systemImage: "folder",
                         iconColor: ChungHwa.Palette.patina) {
            HStack(spacing: 10) {
                Text("打开 Application Support 目录以查看日志、配置和托管内核。")
                    .font(.system(size: 11.5))
                    .foregroundStyle(ChungHwa.Palette.dim)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                GhostButton(title: "在 Finder 中打开",
                            systemImage: "arrow.up.right.square") {
                    openApplicationSupport()
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 2)
        }
    }

    private func openApplicationSupport() {
        let fm = FileManager.default
        guard let base = try? fm.url(for: .applicationSupportDirectory,
                                     in: .userDomainMask,
                                     appropriateFor: nil,
                                     create: true) else { return }
        let dir = base.appendingPathComponent("ChungHwa", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        NSWorkspace.shared.open(dir)
    }
}

// MARK: - Source badge

private struct SourceBadge: View {
    let source: KernelBinarySource

    var body: some View {
        Text(label)
            .font(.system(size: 10.5, weight: .semibold))
            .tracking(0.3)
            .textCase(.uppercase)
            .foregroundStyle(ChungHwa.Palette.text)
            .padding(.horizontal, 9)
            .frame(height: 19)
            .background(
                Capsule(style: .continuous)
                    .fill(ChungHwa.Palette.brass.opacity(0.22))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(ChungHwa.Palette.brass.opacity(0.45), lineWidth: 0.5)
            )
    }

    private var label: String {
        switch source {
        case .bundled: return "内置"
        case .managed: return "托管"
        case .custom:  return "自定义"
        }
    }
}

// MARK: - "New" badge

private struct NewBadge: View {
    var body: some View {
        Text("新版")
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.3)
            .textCase(.uppercase)
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .frame(height: 17)
            .background(
                Capsule(style: .continuous)
                    .fill(LinearGradient(colors: [ChungHwa.Palette.brass,
                                                  ChungHwa.Palette.brassDark],
                                         startPoint: .top, endPoint: .bottom))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(.white.opacity(0.18), lineWidth: 0.5)
            )
    }
}

// MARK: - Buttons

private struct BrassButton: View {
    let title: String
    var systemImage: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let s = systemImage {
                    Image(systemName: s).font(.system(size: 11, weight: .semibold))
                }
                Text(title).font(.system(size: 11.5, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(height: 26)
            .background(
                LinearGradient(colors: [ChungHwa.Palette.brass,
                                        ChungHwa.Palette.brassDark],
                               startPoint: .top, endPoint: .bottom),
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(.white.opacity(0.18), lineWidth: 0.5)
            )
            .shadow(color: ChungHwa.Palette.brass.opacity(0.25), radius: 2, y: 1)
        }
        .buttonStyle(.plain)
    }
}

private struct GhostButton: View {
    enum Tone { case neutral, destructive }

    let title: String
    var systemImage: String?
    var tone: Tone = .neutral
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let s = systemImage {
                    Image(systemName: s).font(.system(size: 11, weight: .semibold))
                }
                Text(title).font(.system(size: 11.5, weight: .semibold))
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, 12)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(ChungHwa.Palette.fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    private var foreground: Color {
        switch tone {
        case .neutral:     return ChungHwa.Palette.text
        case .destructive: return ChungHwa.Palette.earth
        }
    }

    private var borderColor: Color {
        switch tone {
        case .neutral:     return ChungHwa.Palette.line
        case .destructive: return ChungHwa.Palette.earth.opacity(0.35)
        }
    }
}
