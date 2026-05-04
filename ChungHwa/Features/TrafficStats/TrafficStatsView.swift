import Charts
import SwiftUI

/// Bone & Brass Traffic Stats surface. The Live and By-Hour cards reflect
/// real data (streamed via `TrafficStore` for live, persisted via
/// `TrafficHistoryStore` for the 24h view); By-Process is still a synthetic
/// placeholder because we don't have per-process attribution yet. Mirrors
/// the layout of the design's stats screen — see `design/src/app.jsx`.
struct TrafficStatsView: View {
    @Environment(TrafficStore.self) private var traffic
    @Environment(TrafficHistoryStore.self) private var history
    @Environment(KernelController.self) private var kernel

    /// Deterministic mock rows (computed once per view life) so values don't
    /// reshuffle on every render. Used only by the By-Process card.
    private let processRows: [ProcessRow] = makeProcessRows()

    var body: some View {
        ScrollView {
            if isRunning {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12),
                    ],
                    spacing: 12
                ) {
                    liveCard.gridCellColumns(2)

                    byHourCard
                    byProcessCard

                    memoryCard.gridCellColumns(2)
                }
                .padding(.vertical, 16)
                .padding(.horizontal, 18)
            } else {
                emptyState
                    .frame(maxWidth: .infinity, minHeight: 360)
                    .padding(.vertical, 16)
                    .padding(.horizontal, 18)
            }
        }
        .background(ChungHwa.Palette.bg)
    }

    // MARK: - Live (real)

    private var liveCard: some View {
        ChCardWithHeader(
            "实时",
            systemImage: "chart.line.uptrend.xyaxis",
            iconColor: ChungHwa.Palette.brass,
            right: { EmptyView() }
        ) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 16) {
                    liveColumn(
                        caption: "上传速度",
                        arrow: "↑",
                        bps: traffic.current?.upBps ?? 0,
                        series: traffic.samples.map { Double($0.upBps) },
                        color: ChungHwa.Palette.patina
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)

                    liveColumn(
                        caption: "下载速度",
                        arrow: "↓",
                        bps: traffic.current?.downBps ?? 0,
                        series: traffic.samples.map { Double($0.downBps) },
                        color: ChungHwa.Palette.brass
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                softDivider.padding(.top, 4)

                liveStrip
            }
        }
    }

    private func liveColumn(
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

    private var liveStrip: some View {
        HStack(spacing: 0) {
            stripChunk(label: "峰值 ↑", value: ChFormat.rate(traffic.peakUp))
            stripDot
            stripChunk(label: "峰值 ↓", value: ChFormat.rate(traffic.peakDown))
            stripDot
            stripChunk(label: "总计 ↑", value: ChFormat.bytes(traffic.totalUp))
            stripDot
            stripChunk(label: "总计 ↓", value: ChFormat.bytes(traffic.totalDown))
        }
        .font(.system(size: 11))
        .monospacedDigit()
    }

    private func stripChunk(label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(label).foregroundStyle(ChungHwa.Palette.dim)
            Text(value)
                .foregroundStyle(ChungHwa.Palette.text)
                .fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var stripDot: some View {
        Text("·")
            .foregroundStyle(ChungHwa.Palette.faint)
            .padding(.horizontal, 2)
    }

    // MARK: - By Hour (real)

    private var byHourCard: some View {
        ChCardWithHeader(
            "按小时下载",
            systemImage: "clock",
            iconColor: ChungHwa.Palette.patina,
            right: {
                ChSeg(
                    value: "24h",
                    onChange: { _ in },
                    options: [
                        (value: "24h", label: "24h"),
                        (value: "7d",  label: "7d"),
                        (value: "30d", label: "30d"),
                    ]
                )
            }
        ) {
            VStack(alignment: .leading, spacing: 10) {
                hourChart
                    .frame(height: 110)

                softDivider

                HStack {
                    Text("日均 ")
                        .foregroundStyle(ChungHwa.Palette.dim)
                    + Text(dailyAverageString)
                        .foregroundStyle(ChungHwa.Palette.text)
                        .fontWeight(.semibold)
                    Spacer()
                    Text("峰值 ")
                        .foregroundStyle(ChungHwa.Palette.dim)
                    + Text(hourlyPeakString)
                        .foregroundStyle(ChungHwa.Palette.text)
                        .fontWeight(.semibold)
                }
                .font(.system(size: 11))
                .monospacedDigit()
            }
        }
    }

    private var hourChart: some View {
        let cal = Calendar.current
        let currentHour = cal.component(.hour, from: Date())
        let buckets = history.hourly
        return Chart {
            ForEach(buckets) { bucket in
                let hour = cal.component(.hour, from: bucket.hourStart)
                BarMark(
                    x: .value("hour", hour),
                    y: .value("bytes", bucket.downBytes),
                    width: .ratio(0.62)
                )
                .foregroundStyle(
                    hour == currentHour
                        ? ChungHwa.Palette.brass
                        : ChungHwa.Palette.brass.opacity(0.85)
                )
                .cornerRadius(2)
            }
        }
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: [0, 6, 12, 18]) { value in
                AxisValueLabel {
                    if let i = value.as(Int.self) {
                        Text(String(format: "%02d", i))
                            .font(.system(size: 9.5))
                            .foregroundStyle(ChungHwa.Palette.faint)
                    }
                }
            }
        }
        .chartXScale(domain: -0.5...23.5)
    }

    // MARK: - By Process (mock)

    private var byProcessCard: some View {
        ChCardWithHeader(
            "按进程",
            systemImage: "cpu",
            iconColor: ChungHwa.Palette.patina,
            right: { EmptyView() }
        ) {
            let maxVal = processRows.map(\.mb).max() ?? 1
            VStack(alignment: .leading, spacing: 6) {
                ForEach(processRows) { row in
                    processRowView(row, max: maxVal)
                }

                softDivider.padding(.top, 4)

                demoNote
            }
        }
    }

    private func processRowView(_ row: ProcessRow, max maxVal: Double) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(row.color)
                .frame(width: 6, height: 6)

            Text(row.name)
                .font(.system(size: 11))
                .foregroundStyle(ChungHwa.Palette.text)
                .frame(width: 96, alignment: .leading)
                .lineLimit(1)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .fill(ChungHwa.Palette.fillStrong)
                        .frame(height: 5)

                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .fill(row.color.opacity(0.8))
                        .frame(
                            width: max(2, geo.size.width * CGFloat(row.mb / maxVal)),
                            height: 5
                        )
                }
                .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 12)

            Text(formatMB(row.mb))
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(ChungHwa.Palette.dim)
                .frame(width: 56, alignment: .trailing)
        }
        .padding(.vertical, 1)
    }

    // MARK: - Memory & sessions (real)

    private var memoryCard: some View {
        ChCardWithHeader(
            "内存 & 会话",
            systemImage: "memorychip",
            iconColor: ChungHwa.Palette.patina,
            right: { EmptyView() }
        ) {
            HStack(alignment: .top, spacing: 14) {
                ChStat(
                    label: "内核内存",
                    value: traffic.memoryInUse > 0 ? ChFormat.bytes(traffic.memoryInUse) : "—",
                    systemImage: "cpu",
                    color: ChungHwa.Palette.brass
                )
                .frame(maxWidth: .infinity, alignment: .leading)

                ChStat(
                    label: "实时样本数",
                    value: "\(traffic.samples.count)",
                    systemImage: "waveform.path",
                    color: ChungHwa.Palette.brass
                )
                .frame(maxWidth: .infinity, alignment: .leading)

                ChStat(
                    label: "系统上限",
                    value: traffic.memoryLimit > 0 ? ChFormat.bytes(traffic.memoryLimit) : "—",
                    systemImage: "shippingbox",
                    color: ChungHwa.Palette.brass
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 36))
                .foregroundStyle(ChungHwa.Palette.faint)
            Text("内核未运行")
                .font(ChungHwa.Typography.serif(18, weight: .medium))
                .foregroundStyle(ChungHwa.Palette.text)
                .tracking(-0.2)
            Text("启动内核以查看实时流量统计。")
                .font(.system(size: 12))
                .foregroundStyle(ChungHwa.Palette.dim)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - shared bits

    private var softDivider: some View {
        Rectangle()
            .fill(ChungHwa.Palette.lineSoft)
            .frame(height: 0.5)
    }

    private var demoNote: some View {
        Text("示例数据 —— 持久化日志稍后上线")
            .font(.system(size: 10))
            .foregroundStyle(ChungHwa.Palette.faint)
    }

    private var isRunning: Bool {
        if case .running = kernel.status { return true }
        return false
    }

    private func splitRate(_ bps: Int) -> (String, String) {
        let s = ChFormat.rate(bps)
        if let space = s.firstIndex(of: " ") {
            return (String(s[..<space]), String(s[s.index(after: space)...]))
        }
        return (s, "")
    }

    private func formatMB(_ mb: Double) -> String {
        if mb < 1 {
            return String(format: "%.0f KB", mb * 1024)
        }
        return String(format: "%.1f MB", mb)
    }

    private var dailyAverageString: String {
        // Sum across all 24 buckets and divide by 24, regardless of how many
        // hours actually have data — gives a stable "per-hour average over
        // last 24h" reading consistent with the bar chart.
        let total = history.hourly.map(\.downBytes).reduce(0, +)
        return ChFormat.bytes(total / 24)
    }

    private var hourlyPeakString: String {
        ChFormat.bytes(history.hourly.map(\.downBytes).max() ?? 0)
    }
}

// MARK: - Mock data

private struct ProcessRow: Identifiable {
    let id = UUID()
    let name: String
    let color: Color
    let mb: Double
}

private func makeProcessRows() -> [ProcessRow] {
    let palette: [Color] = [
        ChungHwa.Palette.brass,
        ChungHwa.Palette.patina,
        ChungHwa.Palette.brassDark,
        ChungHwa.Palette.patina.opacity(0.75),
        ChungHwa.Palette.brass.opacity(0.7),
        ChungHwa.Palette.faint,
        ChungHwa.Palette.brass,
    ]
    let names = ["Code Helper", "Safari", "Spotify", "iTerm2", "Mail", "Music", "Xcode"]
    let values: [Double] = [184.2, 132.7, 98.4, 64.0, 41.5, 22.8, 9.6]
    return zip(zip(names, values), palette).map { pair, color in
        ProcessRow(name: pair.0, color: color, mb: pair.1)
    }
}

