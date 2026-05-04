import SwiftUI
import AppKit

struct ContentView: View {
    @Environment(KernelController.self) private var kernel
    @Environment(KernelBinaryResolver.self) private var resolver
    @Environment(KernelDownloader.self) private var downloader

    var body: some View {
        VStack(spacing: 20) {
            statusBlock
            Divider()
            kernelBinaryBlock
        }
        .frame(minWidth: 480, minHeight: 360)
        .padding(20)
    }

    // MARK: - Status

    private var statusBlock: some View {
        VStack(spacing: 12) {
            Image(systemName: statusIcon)
                .font(.system(size: 56))
                .foregroundStyle(statusColor)
                .symbolEffect(.pulse, options: .repeating, isActive: isWorking)

            Text(statusTitle)
                .font(.title2.weight(.semibold))

            if case let .running(version) = kernel.status {
                Text("mihomo \(version)")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Button("Reload") { Task { await kernel.reload() } }
                    Button("Restart") { Task { await kernel.restart() } }
                    Button("Stop", role: .destructive) { kernel.stop() }
                }
            }

            if case let .failed(reason) = kernel.status {
                Text(reason)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Retry") { Task { await kernel.start() } }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Kernel binary

    private var kernelBinaryBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Kernel binary").font(.headline)
                Spacer()
                if let b = resolver.current {
                    Text(b.source.displayName)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(.secondary.opacity(0.15), in: Capsule())
                }
            }

            if let b = resolver.current {
                Text(b.url.path)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                if b.source == .managed, let v = resolver.managedVersion() {
                    Text("Installed: \(v)").font(.caption).foregroundStyle(.tertiary)
                }
            } else {
                Text("No kernel binary found.").font(.caption).foregroundStyle(.red)
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
            .controlSize(.regular)
        }
    }

    @ViewBuilder
    private var downloaderProgressLine: some View {
        switch downloader.state {
        case .idle:
            EmptyView()
        case .fetchingMetadata:
            HStack(spacing: 6) { ProgressView().controlSize(.mini); Text("Querying GitHub releases…").font(.caption).foregroundStyle(.secondary) }
        case .downloading(let v):
            HStack(spacing: 6) { ProgressView().controlSize(.mini); Text("Downloading \(v)…").font(.caption).foregroundStyle(.secondary) }
        case .extracting(let v):
            HStack(spacing: 6) { ProgressView().controlSize(.mini); Text("Extracting \(v)…").font(.caption).foregroundStyle(.secondary) }
        case .installing(let v):
            HStack(spacing: 6) { ProgressView().controlSize(.mini); Text("Installing \(v)…").font(.caption).foregroundStyle(.secondary) }
        case .completed(let v):
            Label("Installed \(v)", systemImage: "checkmark.circle.fill")
                .font(.caption).foregroundStyle(.green)
        case .failed(let msg):
            Label(msg, systemImage: "exclamationmark.triangle.fill")
                .font(.caption).foregroundStyle(.red)
                .lineLimit(3)
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

    // MARK: - status helpers

    private var statusIcon: String {
        switch kernel.status {
        case .idle: return "moon.zzz"
        case .starting: return "hourglass"
        case .running: return "checkmark.circle.fill"
        case .failed: return "xmark.octagon.fill"
        }
    }

    private var statusColor: Color {
        switch kernel.status {
        case .idle: return .secondary
        case .starting: return .orange
        case .running: return .green
        case .failed: return .red
        }
    }

    private var statusTitle: String {
        switch kernel.status {
        case .idle: return "Idle"
        case .starting: return "Starting…"
        case .running: return "Running"
        case .failed: return "Failed"
        }
    }

    private var isWorking: Bool {
        if case .starting = kernel.status { return true }
        return false
    }
}

#Preview {
    let resolver = KernelBinaryResolver()
    return ContentView()
        .environment(KernelController(resolver: resolver))
        .environment(resolver)
        .environment(KernelDownloader(resolver: resolver))
}
