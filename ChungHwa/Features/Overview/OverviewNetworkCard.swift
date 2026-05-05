import SwiftUI

struct NetworkCard: View {
    @Environment(NetworkStatusStore.self) private var net
    @Environment(GeoIPStore.self) private var geo
    @Environment(AnonymousMode.self) private var anon

    var body: some View {
        ChCardWithHeader(
            "网络与 IP",
            systemImage: "network",
            iconColor: ChungHwa.Palette.patina,
            right: {
                Button { Task { await net.refresh() } } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(ChungHwa.Palette.dim)
                        .frame(width: 22, height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(ChungHwa.Palette.fill)
                        )
                }
                .buttonStyle(.plain)
            }
        ) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    latencyBlock("外网", ms: net.internetLatencyMs, symbol: "globe.americas")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    latencyBlock("DNS", ms: net.dnsLatencyMs, symbol: "arrow.left.arrow.right")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    latencyBlock("路由器", ms: net.routerLatencyMs, symbol: "wifi.router")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: statTopRowHeight)

                HStack(alignment: .top, spacing: 12) {
                    ChSubStat("直连 IP", systemImage: "desktopcomputer") {
                        ipWithFlag(net.directPublicIPv4)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    ChSubStat("代理 IP", systemImage: "cloud") {
                        ipWithFlag(net.proxyIPv4)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: statBottomRowHeight)
            }
            .task(id: ipPair) {
                let ips: Set<String> = Set([net.directPublicIPv4, net.proxyIPv4]
                    .compactMap { $0 }
                    .filter { !$0.isEmpty })
                guard !ips.isEmpty else { return }
                geo.resolve(ips: ips)
            }
        }
    }

    private var ipPair: String {
        "\(net.directPublicIPv4 ?? "")|\(net.proxyIPv4 ?? "")"
    }

    @ViewBuilder
    private func ipWithFlag(_ ip: String?) -> some View {
        if let ip, !ip.isEmpty {
            HStack(spacing: 5) {
                Text(ip).anonMask(anon.enabled)
                if let code = geo.country(for: ip),
                   let flag = flagOrTag(code) {
                    Text(flag)
                        .font(.system(size: 12))
                }
            }
        } else {
            Text("—")
        }
    }

    /// `country(for:)` returns either an ISO code, the `LAN` sentinel, or
    /// nil. Render flag emoji for ISO codes, a house glyph for LAN.
    private func flagOrTag(_ code: String) -> String? {
        if code == "LAN" { return "🏠" }
        let flag = GeoIPStore.flagEmoji(iso: code)
        return flag.isEmpty ? nil : flag
    }

    private func latencyBlock(_ label: String, ms: Int?, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 11))
                    .foregroundStyle(ChungHwa.Palette.dim)
                Text(label)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(ChungHwa.Palette.dim)
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(ms.map(String.init) ?? "—")
                    .font(ChungHwa.Typography.serif(26, weight: .medium))
                    .tracking(-0.4)
                    .foregroundStyle(ms.map { ChLatency.color($0) } ?? ChungHwa.Palette.dim)
                    .monospacedDigit()
                if ms != nil {
                    Text("ms")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(ChungHwa.Palette.dim)
                }
            }
        }
    }
}
