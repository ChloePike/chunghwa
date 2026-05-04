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
    @Environment(NetworkStatusStore.self) private var net
    @Environment(AnonymousMode.self) private var anon

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
                    OverviewTrafficCard()
                        .gridCellColumns(2)
                }
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 18)
        }
        .background(ChungHwa.Palette.bg)
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
        HStack(alignment: .top, spacing: 14) {
            // Uptime owns its own TimelineView so the parent doesn't tick at 1Hz.
            UptimeStat(startedAt: kernel.startedAt)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Connection count read on its own to subscribe a leaf.
            ConnectionCountStat()
                .frame(maxWidth: .infinity, alignment: .leading)

            // Memory read on its own.
            MemoryStat()
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
                systemImage: "app.badge"
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
            systemImage: "network",
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
                        systemImage: "globe.americas",
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
                        systemImage: "wifi.router",
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

                    ChSubStat("本地 IP", systemImage: "desktopcomputer") {
                        Text(net.localIPv4 ?? "—").anonMask(anon.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    ChSubStat("代理 IP", systemImage: "cloud") {
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
}

// MARK: - Leaf views (isolate per-store subscriptions)

/// Drives the uptime label off a `TimelineView`. Crucially, the parent
/// `OverviewView` does NOT subscribe to a 1Hz tick — only this leaf does,
/// so the surrounding `LazyVGrid` + cards don't re-evaluate every second.
private struct UptimeStat: View {
    let startedAt: Date?

    var body: some View {
        Group {
            if let started = startedAt {
                TimelineView(.periodic(from: started, by: 1.0)) { ctx in
                    ChStat(
                        label: "运行时长",
                        value: ChFormat.uptime(since: started, now: ctx.date),
                        systemImage: "clock",
                        color: ChungHwa.Palette.brass
                    )
                }
            } else {
                ChStat(
                    label: "运行时长",
                    value: "—",
                    systemImage: "clock",
                    color: ChungHwa.Palette.brass
                )
            }
        }
    }
}

/// Reads only `connections.count` from the store. The store still publishes
/// when the underlying array mutates, but this leaf is the only thing that
/// re-evaluates as a result.
private struct ConnectionCountStat: View {
    @Environment(ConnectionsStore.self) private var connectionsStore

    var body: some View {
        ChStat(
            label: "连接数",
            value: String(connectionsStore.connections.count),
            systemImage: "arrow.left.arrow.right",
            color: ChungHwa.Palette.brass
        )
    }
}

private struct MemoryStat: View {
    @Environment(TrafficStore.self) private var traffic

    var body: some View {
        ChStat(
            label: "内核内存",
            value: traffic.memoryInUse > 0 ? ChFormat.bytes(traffic.memoryInUse) : "—",
            systemImage: "memorychip",
            color: ChungHwa.Palette.brass
        )
    }
}

/// Traffic card extracted to its own view so the parent OverviewView does
/// not subscribe to TrafficStore changes (which fire at ~1Hz). Only this
/// card and the inner `OverviewSparkRow` re-evaluate on each sample.
private struct OverviewTrafficCard: View {
    var body: some View {
        ChCardWithHeader(
            "流量",
            systemImage: "chart.line.uptrend.xyaxis",
            iconColor: ChungHwa.Palette.brass,
            right: { EmptyView() }
        ) {
            VStack(alignment: .leading, spacing: 10) {
                OverviewSparkRow()

                Rectangle()
                    .fill(ChungHwa.Palette.lineSoft)
                    .frame(height: 0.5)
                    .padding(.top, 4)

                OverviewTrafficTotals()
            }
        }
    }
}

/// Sparkline row owns the per-sample subscription. The line below (totals)
/// updates on a slower 500ms cadence, so it lives in its own leaf.
private struct OverviewSparkRow: View {
    @Environment(TrafficStore.self) private var traffic

    var body: some View {
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

    private func splitRate(_ bps: Int) -> (String, String) {
        let s = ChFormat.rate(bps)
        if let space = s.firstIndex(of: " ") {
            return (String(s[..<space]), String(s[s.index(after: space)...]))
        }
        return (s, "")
    }
}

/// Totals strip — reads `totalUp / totalDown` which the store flushes at
/// 500ms, so this leaf only invalidates on that cadence.
private struct OverviewTrafficTotals: View {
    @Environment(TrafficStore.self) private var traffic

    var body: some View {
        HStack {
            Text("↑ 上传 ")
                .foregroundStyle(ChungHwa.Palette.dim)
            + Text(traffic.totalUp > 0 ? ChFormat.bytes(traffic.totalUp) : "—")
                .foregroundStyle(ChungHwa.Palette.text)
                .fontWeight(.semibold)
            Spacer()
            Text("↓ 下载 ")
                .foregroundStyle(ChungHwa.Palette.dim)
            + Text(traffic.totalDown > 0 ? ChFormat.bytes(traffic.totalDown) : "—")
                .foregroundStyle(ChungHwa.Palette.text)
                .fontWeight(.semibold)
        }
        .font(.system(size: 11))
        .monospacedDigit()
    }
}
