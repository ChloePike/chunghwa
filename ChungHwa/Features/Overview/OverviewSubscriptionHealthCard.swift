import SwiftUI

struct SubscriptionHealthCard: View {
    @Environment(ProfileStore.self) private var profileStore
    @Environment(ProxyStore.self) private var proxyStore
    @Environment(RuleStore.self) private var ruleStore
    @Environment(KernelController.self) private var kernel

    @State private var refreshing = false

    var body: some View {
        ChCardWithHeader(
            "配置",
            systemImage: "tray.full",
            iconColor: ChungHwa.Palette.brass,
            right: { refreshButton }
        ) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    ChStat(
                        label: "节点",
                        value: String(nodeCount),
                        systemImage: "globe",
                        color: ChungHwa.Palette.brass
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Button { switchTab(.rules) } label: {
                        ChStat(
                            label: "规则",
                            value: String(ruleStore.rules.count),
                            systemImage: "list.bullet.rectangle",
                            color: ChungHwa.Palette.brass
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: statTopRowHeight)

                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 10))
                        .foregroundStyle(ChungHwa.Palette.dim)
                    Text("更新于")
                        .font(.system(size: 10.5))
                        .foregroundStyle(ChungHwa.Palette.dim)
                    Text(updatedAtText)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(ChungHwa.Palette.text)
                    Spacer(minLength: 0)
                    Button { switchTab(.profiles) } label: {
                        Text("管理 →")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(ChungHwa.Palette.brass)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .frame(height: statBottomRowHeight)
            }
        }
        .task(id: kernel.startedAt) {
            await ruleStore.refresh(api: kernel.apiClient)
        }
    }

    private var refreshButton: some View {
        Button {
            Task {
                guard let id = profileStore.activeProfileID else { return }
                refreshing = true
                defer { refreshing = false }
                try? await profileStore.refresh(id)
                await kernel.reload()
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: refreshing ? "hourglass" : "arrow.clockwise")
                    .font(.system(size: 10, weight: .semibold))
                Text("拉取订阅")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(ChungHwa.Palette.bone)
            .padding(.horizontal, 10)
            .frame(height: 22)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(refreshing ? ChungHwa.Palette.brass.opacity(0.6) : ChungHwa.Palette.brass)
            )
        }
        .buttonStyle(.plain)
        .disabled(refreshing || profileStore.activeProfileID == nil)
    }

    /// `snapshotProxies` includes both groups and concrete nodes; show the
    /// concrete-node count to match what the user expects from "节点".
    private var nodeCount: Int {
        proxyStore.snapshotProxies.values.reduce(into: 0) { acc, p in
            if !p.isGroup { acc += 1 }
        }
    }

    private var updatedAtText: String {
        guard let at = profileStore.activeProfile?.updatedAt else { return "—" }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: at, relativeTo: Date())
    }
}
