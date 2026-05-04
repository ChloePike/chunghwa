import Combine
import SwiftUI

// MARK: - Overview

/// Bone & Brass Overview surface. Mirrors the `Overview` component in
/// `design/src/app.jsx` (476-650). This slice ships 3 cards:
///   - Running Status   (uptime / connections / kernel memory)
///   - Network Status   (placeholder ping + IPs — values TBD)
///   - Traffic Stats    (live up / down sparks, full-width)
///
/// 7-Day Trend and Traffic Summary are intentionally omitted: they need
/// persistent multi-day storage we don't have yet.
struct OverviewView: View {
    @Environment(KernelController.self) private var kernel
    @Environment(TrafficStore.self) private var traffic
    @Environment(ConnectionsStore.self) private var connectionsStore
    @Environment(AnonymousMode.self) private var anon
    @Environment(NetworkStatusStore.self) private var net

    /// 1 Hz tick so the uptime stat re-renders every second while running.
    @State private var now = Date()
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12),
                ],
                spacing: 12
            ) {
                runningStatusCard
                    .gridCellColumns(isRunning ? 1 : 2)

                if isRunning {
                    networkStatusCard
                    trafficStatsCard
                        .gridCellColumns(2)
                }
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 18)
        }
        .background(ChungHwa.Palette.bg)
        .onReceive(ticker) { now = $0 }
    }

    // MARK: Running Status

    private var runningStatusCard: some View {
        ChCardWithHeader(
            "运行状态",
            systemImage: "power",
            iconColor: ChungHwa.Palette.patina,
            right: { runningStatusRight }
        ) {
            VStack(alignment: .leading, spacing: 14) {
                switch kernel.status {
                case .running:
                    runningStatusBody
                case .idle:
                    statusMessage("空闲")
                case .starting:
                    statusMessage("启动中…")
                case .failed(let reason):
                    statusMessage("失败: \(reason)")
                }
            }
        }
    }

    @ViewBuilder
    private var runningStatusRight: some View {
        if isRunning {
            ChDot(color: .green, size: 8, pulse: true)
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private var runningStatusBody: some View {
        let uptimeText: String = {
            if let started = kernel.startedAt {
                _ = now // tie re-render to the 1 Hz tick
                return ChFormat.uptime(since: started)
            }
            return "—"
        }()
        let memText: String = traffic.memoryInUse > 0
            ? ChFormat.bytes(traffic.memoryInUse)
            : "—"

        HStack(alignment: .top, spacing: 14) {
            ChStat(
                label: "运行时长",
                value: uptimeText,
                systemImage: "power",
                color: ChungHwa.Palette.brass
            )
            .frame(maxWidth: .infinity, alignment: .leading)

            ChStat(
                label: "连接数",
                value: String(connectionsStore.connections.count),
                systemImage: "link",
                color: ChungHwa.Palette.brass
            )
            .frame(maxWidth: .infinity, alignment: .leading)

            ChStat(
                label: "内核内存",
                value: memText,
                systemImage: "cpu",
                color: ChungHwa.Palette.brass
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        softDivider

        HStack(alignment: .top, spacing: 14) {
            ChSubStat(
                "系统",
                value: "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)",
                systemImage: "desktopcomputer"
            )
            .frame(maxWidth: .infinity, alignment: .leading)

            ChSubStat(
                "版本",
                value: appVersionString,
                systemImage: "shippingbox"
            )
            .frame(maxWidth: .infinity, alignment: .leading)

            ChSubStat(
                "内核",
                value: kernelVersionString,
                systemImage: "cpu"
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func statusMessage(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(text)
                .font(ChungHwa.Typography.serif(20, weight: .medium))
                .foregroundStyle(ChungHwa.Palette.text)
                .tracking(-0.3)
                .padding(.vertical, 6)
        }
    }

    // MARK: Network Status

    private var networkStatusCard: some View {
        ChCardWithHeader(
            "网络状态",
            systemImage: "globe",
            iconColor: ChungHwa.Palette.patina,
            right: {
                ghostRefreshButton {
                    Task { await net.refresh() }
                }
            }
        ) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 14) {
                    ChStat(
                        label: "互联网",
                        value: latencyText(net.internetLatencyMs),
                        systemImage: "globe",
                        color: ChungHwa.Palette.brass
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)

                    ChStat(
                        label: "DNS",
                        value: latencyText(net.dnsLatencyMs),
                        systemImage: "arrow.left.arrow.right",
                        color: ChungHwa.Palette.brass
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)

                    ChStat(
                        label: "路由",
                        value: latencyText(net.routerLatencyMs),
                        systemImage: "shippingbox",
                        color: ChungHwa.Palette.brass
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                softDivider

                HStack(alignment: .top, spacing: 14) {
                    ChSubStat(
                        "网络",
                        value: net.networkType,
                        systemImage: networkSymbol
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)

                    ChSubStat("本地 IP", systemImage: "shippingbox") {
                        Text(net.localIPv4 ?? "—").anonMask(anon.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    ChSubStat("代理 IP", systemImage: "globe") {
                        Text(net.proxyIPv4 ?? "—").anonMask(anon.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func latencyText(_ ms: Int?) -> String {
        guard let ms else { return "—" }
        return "\(ms) ms"
    }

    private var networkSymbol: String {
        switch net.networkType {
        case "Wi-Fi":    return "wifi"
        case "Ethernet": return "cable.connector"
        case "Cellular": return "antenna.radiowaves.left.and.right"
        default:         return "network"
        }
    }

    // MARK: Traffic Stats

    private var trafficStatsCard: some View {
        ChCardWithHeader(
            "流量",
            systemImage: "chart.line.uptrend.xyaxis",
            iconColor: ChungHwa.Palette.brass,
            right: { EmptyView() }
        ) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 16) {
                    trafficColumn(
                        caption: "上传速度",
                        arrow: "↑",
                        bps: traffic.current?.upBps ?? 0,
                        series: traffic.samples.map { Double($0.upBps) },
                        color: ChungHwa.Palette.patina
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)

                    trafficColumn(
                        caption: "下载速度",
                        arrow: "↓",
                        bps: traffic.current?.downBps ?? 0,
                        series: traffic.samples.map { Double($0.downBps) },
                        color: ChungHwa.Palette.brass
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                softDivider.padding(.top, 4)

                HStack {
                    Text("↑ 上传 ")
                        .foregroundStyle(ChungHwa.Palette.dim)
                    + Text(totalUpString)
                        .foregroundStyle(ChungHwa.Palette.text)
                        .fontWeight(.semibold)
                    Spacer()
                    Text("↓ 下载 ")
                        .foregroundStyle(ChungHwa.Palette.dim)
                    + Text(totalDownString)
                        .foregroundStyle(ChungHwa.Palette.text)
                        .fontWeight(.semibold)
                }
                .font(.system(size: 11))
                .monospacedDigit()
            }
        }
    }

    private func trafficColumn(
        caption: String,
        arrow: String,
        bps: Int,
        series: [Double],
        color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text(arrow).foregroundStyle(color)
                Text(caption).foregroundStyle(ChungHwa.Palette.dim)
            }
            .font(.system(size: 11))

            rateLabel(bps: bps, color: color)

            ChSpark(values: series.isEmpty ? [0, 0] : series, color: color)
                .frame(height: 56)
        }
    }

    private func rateLabel(bps: Int, color: Color) -> some View {
        let (number, unit) = splitRate(bps)
        return HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(number)
                .font(ChungHwa.Typography.serif(22, weight: .semibold))
                .tracking(-0.3)
                .foregroundStyle(color)
                .monospacedDigit()
            Text(unit)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
        }
    }

    /// Split "1.2 MB/s" → ("1.2", "MB/s") so the unit can render smaller.
    private func splitRate(_ bps: Int) -> (String, String) {
        let s = ChFormat.rate(bps)
        if let space = s.firstIndex(of: " ") {
            return (String(s[..<space]), String(s[s.index(after: space)...]))
        }
        return (s, "")
    }

    // MARK: - shared bits

    private var softDivider: some View {
        Rectangle()
            .fill(ChungHwa.Palette.lineSoft)
            .frame(height: 0.5)
    }

    private func ghostRefreshButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
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

    // MARK: - derived

    private var isRunning: Bool {
        if case .running = kernel.status { return true }
        return false
    }

    private var appVersionString: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String
        if let build, !build.isEmpty {
            return "\(short) (\(build))"
        }
        return short
    }

    private var kernelVersionString: String {
        if case let .running(version) = kernel.status { return version }
        return "—"
    }

    private var totalUpString: String {
        traffic.totalUp > 0 ? ChFormat.bytes(traffic.totalUp) : "—"
    }

    private var totalDownString: String {
        traffic.totalDown > 0 ? ChFormat.bytes(traffic.totalDown) : "—"
    }
}
