import SwiftUI

struct SidebarView: View {
    @Binding var selection: SidebarTab?
    @Environment(KernelController.self) private var kernel

    var body: some View {
        List(selection: $selection) {
            Section {
                ForEach(SidebarTab.primary) { tab in
                    Label(tab.title, systemImage: tab.symbol).tag(Optional(tab))
                }
            } header: {
                BrandHeader().padding(.bottom, 6)
            }

            Section("Configuration") {
                Label(SidebarTab.settings.title, systemImage: SidebarTab.settings.symbol)
                    .tag(Optional(SidebarTab.settings))
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            FooterStatusPill()
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
    }
}

private struct BrandHeader: View {
    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(LinearGradient(colors: [Color.green, Color.blue],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: "shield.fill").foregroundStyle(.white).font(.system(size: 13, weight: .bold))
            }
            .frame(width: 26, height: 26)
            .shadow(color: .blue.opacity(0.35), radius: 3, y: 2)

            VStack(alignment: .leading, spacing: 1) {
                Text("ChungHwa").font(.system(size: 13, weight: .bold))
                Text(Bundle.main.shortVersion).font(.system(size: 10)).foregroundStyle(.tertiary)
            }
        }
        .textCase(nil)
    }
}

private struct FooterStatusPill: View {
    @Environment(KernelController.self) private var kernel
    @Environment(KernelBinaryResolver.self) private var resolver

    var body: some View {
        HStack(spacing: 9) {
            Circle().fill(dotColor).frame(width: 8, height: 8)
                .overlay(Circle().stroke(dotColor.opacity(0.35), lineWidth: 4))
            VStack(alignment: .leading, spacing: 1) {
                Text(headline).font(.caption.weight(.semibold)).lineLimit(1)
                Text(subline).font(.system(size: 10)).foregroundStyle(.tertiary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.horizontal, 8).padding(.bottom, 8)
    }

    private var dotColor: Color {
        switch kernel.status {
        case .running: return .green
        case .starting: return .orange
        case .failed: return .red
        case .idle: return .secondary
        }
    }

    private var headline: String {
        switch kernel.status {
        case .running(let v): return "mihomo \(v)"
        case .starting:       return "Starting…"
        case .failed:         return "Failed"
        case .idle:           return "Idle"
        }
    }

    private var subline: String {
        if let b = resolver.current { return b.source.displayName }
        return "no kernel"
    }
}

private extension Bundle {
    var shortVersion: String {
        (infoDictionary?["CFBundleShortVersionString"] as? String).map { "v\($0)" } ?? ""
    }
}
