import SwiftUI
import AppKit

struct SettingsView: View {
    @Environment(KernelController.self) private var kernel
    @Environment(KernelBinaryResolver.self) private var resolver
    @Environment(KernelDownloader.self) private var downloader

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ProfilesSection()
                kernelBinarySection
            }
            .padding(20)
            .frame(maxWidth: 720, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .navigationTitle("Settings")
    }

    private var kernelBinarySection: some View {
        SectionCard(title: "Kernel binary") {
            VStack(alignment: .leading, spacing: 10) {
                if let b = resolver.current {
                    HStack {
                        Text(b.source.displayName)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .background(.secondary.opacity(0.15), in: Capsule())
                        Spacer()
                        if b.source == .managed, let v = resolver.managedVersion() {
                            Text("Installed \(v)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Text(b.url.path)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(2)
                        .truncationMode(.middle)
                } else {
                    Label("No kernel binary found", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }

                downloaderProgressLine

                HStack(spacing: 12) {
                    Button {
                        Task {
                            await downloader.updateLatest()
                            if case .completed = downloader.state {
                                await kernel.restart()
                            }
                        }
                    } label: {
                        Label("Update kernel", systemImage: "arrow.down.circle")
                    }
                    .disabled(downloader.isWorking)

                    Button("Use custom binary…") { pickCustomBinary() }

                    if resolver.customPath != nil || resolver.current?.source == .managed {
                        Button("Reset to bundled", role: .destructive) {
                            try? resolver.resetToBundled()
                            downloader.reset()
                            Task { await kernel.restart() }
                        }
                    }
                }
            }
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
                .font(.caption).foregroundStyle(.green)
        case .failed(let msg):
            Label(msg, systemImage: "exclamationmark.triangle.fill")
                .font(.caption).foregroundStyle(.red)
                .lineLimit(3)
        }
    }

    private func progressRow(_ text: String) -> some View {
        HStack(spacing: 6) {
            ProgressView().controlSize(.mini)
            Text(text).font(.caption).foregroundStyle(.secondary)
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
}

struct SectionCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.subheadline.weight(.bold))
                .padding(.horizontal, 14).padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.secondary.opacity(0.06))
            Divider()
            content().padding(14)
        }
        .background(.background.tertiary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.secondary.opacity(0.15)))
    }
}
