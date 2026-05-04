import SwiftUI

struct OverviewView: View {
    @Environment(KernelController.self) private var kernel
    @Environment(SystemProxyController.self) private var systemProxy

    var body: some View {
        VStack(spacing: 22) {
            VStack(spacing: 14) {
                Image(systemName: statusIcon)
                    .font(.system(size: 64))
                    .foregroundStyle(statusColor)
                    .symbolEffect(.pulse, options: .repeating, isActive: isWorking)

                Text(statusTitle).font(.title.weight(.semibold))

                if case let .running(version) = kernel.status {
                    Text("mihomo \(version)")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                if case let .failed(reason) = kernel.status {
                    Text(reason)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
            }

            HStack(spacing: 12) {
                if case .running = kernel.status {
                    Button("Reload") { Task { await kernel.reload() } }
                    Button("Restart") { Task { await kernel.restart() } }
                    Button("Stop", role: .destructive) { kernel.stop() }
                }
                if case .failed = kernel.status {
                    Button("Retry") { Task { await kernel.start() } }
                        .buttonStyle(.borderedProminent)
                }
                if case .idle = kernel.status {
                    Button("Start") { Task { await kernel.start() } }
                        .buttonStyle(.borderedProminent)
                }
            }

            systemProxyCard
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
        .navigationTitle("Overview")
    }

    private var systemProxyCard: some View {
        HStack(spacing: 14) {
            Image(systemName: systemProxy.enabled ? "shield.lefthalf.filled" : "shield")
                .font(.system(size: 22))
                .foregroundStyle(systemProxy.enabled ? .green : .secondary)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text("System Proxy").font(.subheadline.weight(.semibold))
                Text(systemProxy.enabled
                     ? "All HTTP/HTTPS/SOCKS5 traffic routes through 127.0.0.1:\(systemProxy.port)"
                     : "Browsers and most apps will not use mihomo")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let err = systemProxy.lastError {
                    Text(err).font(.caption2).foregroundStyle(.red).lineLimit(2)
                }
            }
            Spacer()
            Toggle("", isOn: Binding(get: { systemProxy.enabled },
                                     set: { _ in systemProxy.toggle() }))
                .toggleStyle(.switch)
                .labelsHidden()
        }
        .padding(14)
        .background(.background.tertiary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.secondary.opacity(0.15)))
        .frame(maxWidth: 520)
    }

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
