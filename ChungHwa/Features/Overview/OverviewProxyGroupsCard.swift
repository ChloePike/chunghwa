import SwiftUI

struct ProxyGroupsCard: View {
    @Environment(ProxyStore.self) private var proxyStore
    @Environment(KernelController.self) private var kernel

    var body: some View {
        ChCardWithHeader(
            "当前节点",
            systemImage: "globe",
            iconColor: ChungHwa.Palette.patina,
            right: { rightChip }
        ) {
            VStack(alignment: .leading, spacing: 0) {
                if proxyStore.groups.isEmpty {
                    emptyState
                } else {
                    ForEach(Array(proxyStore.groups.prefix(6).enumerated()), id: \.element.id) { idx, group in
                        ProxyGroupRow(group: group)
                        if idx < proxyStore.groups.prefix(6).count - 1 {
                            Rectangle()
                                .fill(ChungHwa.Palette.lineSoft)
                                .frame(height: 0.5)
                        }
                    }
                    if proxyStore.groups.count > 6 {
                        Button {
                            switchTab(.proxies)
                        } label: {
                            Text("看全部 \(proxyStore.groups.count) 组 →")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(ChungHwa.Palette.brass)
                                .padding(.vertical, 8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .task(id: kernel.startedAt) {
            await proxyStore.refresh(api: kernel.apiClient)
        }
    }

    private var rightChip: some View {
        Text("\(proxyStore.groups.count) 组")
            .font(ChungHwa.Typography.mono(10.5))
            .foregroundStyle(ChungHwa.Palette.dim)
    }

    private var emptyState: some View {
        Text("没有代理组")
            .font(.system(size: 12))
            .foregroundStyle(ChungHwa.Palette.dim)
            .padding(.vertical, 14)
    }
}

/// One row in the groups card. Owns its testing state so a tap doesn't
/// re-invalidate sibling rows.
struct ProxyGroupRow: View {
    let group: MihomoProxy

    @Environment(ProxyStore.self) private var proxyStore
    @Environment(KernelController.self) private var kernel
    @Environment(GeoIPStore.self) private var geo
    @Environment(NetworkStatusStore.self) private var net

    var body: some View {
        Button {
            switchTab(.proxies)
        } label: {
            HStack(spacing: 10) {
                Text(flagGlyph)
                    .font(.system(size: 14))
                    .frame(width: 22, alignment: .center)

                VStack(alignment: .leading, spacing: 1) {
                    Text(group.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(ChungHwa.Palette.text)
                        .lineLimit(1).truncationMode(.tail)
                    Text(group.now ?? "—")
                        .font(ChungHwa.Typography.mono(10.5))
                        .foregroundStyle(ChungHwa.Palette.dim)
                        .lineLimit(1).truncationMode(.middle)
                }

                Spacer(minLength: 6)

                latencyBadge
                testButton
            }
            .padding(.vertical, 9)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var latencyBadge: some View {
        if let ms = activeLatency {
            Text("\(ms) ms")
                .font(ChungHwa.Typography.mono(10.5, weight: .semibold))
                .foregroundStyle(ChLatency.color(ms))
                .monospacedDigit()
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(ChLatency.color(ms).opacity(0.10))
                )
        } else {
            Text("— ms")
                .font(ChungHwa.Typography.mono(10.5))
                .foregroundStyle(ChungHwa.Palette.faint)
        }
    }

    private var testButton: some View {
        let testing = proxyStore.testingGroups.contains(group.name)
        return Button {
            Task { await proxyStore.testGroup(group.name, api: kernel.apiClient) }
        } label: {
            Image(systemName: testing ? "hourglass" : "bolt")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(testing ? ChungHwa.Palette.faint : ChungHwa.Palette.brass)
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(ChungHwa.Palette.fill)
                )
        }
        .buttonStyle(.plain)
        .disabled(testing)
    }

    private var activeLatency: Int? {
        guard let now = group.now,
              let active = proxyStore.proxy(now),
              let last = active.history?.last else { return nil }
        return last.delay > 0 ? last.delay : nil
    }

    /// Flags need an IP. Group nodes don't carry IPs in /proxies — fall back
    /// to mihomo's egress IP when the group is the one currently routing.
    /// Cheap: country() is an O(1) cache read with a background backfill on miss.
    private var flagGlyph: String {
        guard let ip = net.proxyIPv4,
              let code = geo.country(for: ip) else { return "·" }
        if code == "LAN" { return "🏠" }
        return Self.flag(code)
    }

    private static func flag(_ iso: String) -> String {
        let upper = iso.uppercased()
        guard upper.count == 2 else { return "" }
        let base: UInt32 = 0x1F1E6 - 0x41
        var out = ""
        for ch in upper.unicodeScalars {
            guard (0x41...0x5A).contains(ch.value),
                  let scalar = Unicode.Scalar(base + ch.value)
            else { return "" }
            out.unicodeScalars.append(scalar)
        }
        return out
    }
}
