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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                aboutCard
                startupCard
                kernelBinaryCard
                resetCard
                Color.clear.frame(height: 12)
            }
            .padding(20)
            .frame(maxWidth: 720, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .background(ChungHwa.Palette.bg)
        .navigationTitle("Settings")
    }

    // MARK: - About

    private var aboutCard: some View {
        ChCardWithHeader("About",
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
                    Text("ChungHwa")
                        .font(ChungHwa.Typography.serif(22, weight: .semibold))
                        .foregroundStyle(ChungHwa.Palette.text)
                        .tracking(-0.4)
                    Text("mihomo controller for macOS · v\(Self.shortVersion)+\(Self.buildVersion)")
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
        ChCardWithHeader("Startup",
                         systemImage: "power",
                         iconColor: ChungHwa.Palette.brass) {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(isOn: Binding(
                        get: { loginItem.isRegistered },
                        set: { loginItem.setEnabled($0) }
                    )) {
                        Text("Launch at login")
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
                    Text("Close window keeps app running")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(ChungHwa.Palette.text)
                }
                .toggleStyle(.switch)
                .controlSize(.small)
            }
            .padding(.horizontal, 14)
            .padding(.top, 2)
            .padding(.bottom, 4)
        }
    }

    // MARK: - Kernel binary

    private var kernelBinaryCard: some View {
        ChCardWithHeader("Kernel binary",
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
                    Label("No kernel binary found", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(ChungHwa.Palette.earth)
                }

                downloaderProgressLine

                HStack(spacing: 10) {
                    BrassButton(title: "Update kernel", systemImage: "arrow.down.circle") {
                        Task {
                            await downloader.updateLatest()
                            if case .completed = downloader.state {
                                await kernel.restart()
                            }
                        }
                    }
                    .disabled(downloader.isWorking)
                    .opacity(downloader.isWorking ? 0.55 : 1)

                    GhostButton(title: "Use custom binary…",
                                systemImage: "folder") {
                        pickCustomBinary()
                    }

                    if resolver.customPath != nil || resolver.current?.source == .managed {
                        GhostButton(title: "Reset to bundled",
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
            Text("Installed \(v)")
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
            progressRow("Querying GitHub releases…")
        case .downloading(let v):
            progressRow("Downloading \(v)…")
        case .extracting(let v):
            progressRow("Extracting \(v)…")
        case .installing(let v):
            progressRow("Installing \(v)…")
        case .completed(let v):
            Label("Installed \(v)", systemImage: "checkmark.circle.fill")
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
        panel.title = "Select mihomo binary"
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
        ChCardWithHeader("Storage",
                         systemImage: "folder",
                         iconColor: ChungHwa.Palette.patina) {
            HStack(spacing: 10) {
                Text("Open the application support folder to inspect logs, configs, and the managed kernel.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(ChungHwa.Palette.dim)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                GhostButton(title: "Open in Finder",
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
        case .bundled: return "bundled"
        case .managed: return "managed"
        case .custom:  return "custom"
        }
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
