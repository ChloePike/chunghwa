import SwiftUI

struct OverviewView: View {
    @Environment(KernelController.self) private var kernel

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: statusIcon)
                .font(.system(size: 64))
                .foregroundStyle(statusColor)
                .symbolEffect(.pulse, options: .repeating, isActive: isWorking)

            Text(statusTitle).font(.title.weight(.semibold))

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
                    .padding(.horizontal, 24)
                Button("Retry") { Task { await kernel.start() } }
                    .buttonStyle(.borderedProminent)
            }

            if case .idle = kernel.status {
                Button("Start") { Task { await kernel.start() } }
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
        .navigationTitle("Overview")
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
