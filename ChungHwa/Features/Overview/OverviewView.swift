import SwiftUI
import Charts

struct OverviewView: View {
    @Environment(KernelController.self) private var kernel
    @Environment(SystemProxyController.self) private var systemProxy
    @Environment(TrafficStore.self) private var traffic

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

            if case .running = kernel.status {
                trafficCard
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
        .navigationTitle("Overview")
    }

    private var trafficCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 16) {
                rateLabel(symbol: "arrow.up", color: .blue,
                          bps: traffic.current?.upBps ?? 0)
                rateLabel(symbol: "arrow.down", color: .green,
                          bps: traffic.current?.downBps ?? 0)
                Spacer()
                if traffic.memoryInUse > 0 {
                    Label(formatBytes(traffic.memoryInUse), systemImage: "memorychip")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            chart
                .frame(height: 80)
        }
        .padding(14)
        .background(.background.tertiary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.secondary.opacity(0.15)))
        .frame(maxWidth: 520)
    }

    private func rateLabel(symbol: String, color: Color, bps: Int) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).foregroundStyle(color)
            Text(formatRate(bps))
                .font(.system(.callout, design: .monospaced).weight(.semibold))
                .monospacedDigit()
        }
    }

    @ViewBuilder
    private var chart: some View {
        if traffic.samples.isEmpty {
            HStack {
                Spacer()
                Text("Waiting for traffic…")
                    .font(.caption).foregroundStyle(.tertiary)
                Spacer()
            }
        } else {
            Chart(traffic.samples) { s in
                AreaMark(x: .value("t", s.timestamp),
                         y: .value("down", s.downBps))
                    .foregroundStyle(.green.opacity(0.25))
                AreaMark(x: .value("t", s.timestamp),
                         y: .value("up", s.upBps))
                    .foregroundStyle(.blue.opacity(0.25))
                LineMark(x: .value("t", s.timestamp),
                         y: .value("down", s.downBps))
                    .foregroundStyle(.green)
                LineMark(x: .value("t", s.timestamp),
                         y: .value("up", s.upBps))
                    .foregroundStyle(.blue)
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartLegend(.hidden)
        }
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

private func formatRate(_ bps: Int) -> String {
    formatBytes(bps) + "/s"
}

private func formatBytes(_ bytes: Int) -> String {
    let v = Double(bytes)
    switch v {
    case ..<1024:                    return String(format: "%.0f B", v)
    case ..<1_048_576:               return String(format: "%.1f KB", v / 1024)
    case ..<1_073_741_824:           return String(format: "%.1f MB", v / 1_048_576)
    default:                         return String(format: "%.2f GB", v / 1_073_741_824)
    }
}
