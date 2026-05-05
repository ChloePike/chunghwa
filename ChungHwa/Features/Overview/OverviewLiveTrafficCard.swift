import Charts
import SwiftUI

/// Range chips drive the chart series. Owns its own state so the wider page
/// doesn't redraw when the user flips between ranges.
struct LiveTrafficCard: View {
    enum Range: String, CaseIterable, Hashable {
        case oneMin, fiveMin, fifteenMin
        var label: String {
            switch self {
            case .oneMin:     return "1 分钟"
            case .fiveMin:    return "5 分钟"
            case .fifteenMin: return "15 分钟"
            }
        }
    }

    @State private var range: Range = .fiveMin

    var body: some View {
        ChCardWithHeader(
            "实时流量",
            systemImage: "chart.line.uptrend.xyaxis",
            iconColor: ChungHwa.Palette.brass,
            right: {
                ChSeg(value: range, onChange: { range = $0 },
                      options: Range.allCases.map { ($0, $0.label) })
            }
        ) {
            VStack(alignment: .leading, spacing: 10) {
                LiveSpeedRow()
                TrafficChart(range: range)
                    .frame(height: 110)
                Rectangle()
                    .fill(ChungHwa.Palette.lineSoft)
                    .frame(height: 0.5)
                TrafficTotalsRow()
            }
        }
    }
}

/// Up/down current rates. Subscribes only to TrafficStore.
struct LiveSpeedRow: View {
    @Environment(TrafficStore.self) private var traffic

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            speedColumn(arrow: "↑", caption: "上传",
                        bps: traffic.current?.upBps ?? 0,
                        color: ChungHwa.Palette.patina)
                .frame(maxWidth: .infinity, alignment: .leading)
            speedColumn(arrow: "↓", caption: "下载",
                        bps: traffic.current?.downBps ?? 0,
                        color: ChungHwa.Palette.brass)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func speedColumn(arrow: String, caption: String, bps: Int, color: Color) -> some View {
        let (number, unit) = splitRate(bps)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(arrow).foregroundStyle(color)
                Text(caption).foregroundStyle(ChungHwa.Palette.dim)
            }
            .font(.system(size: 11))
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(number)
                    .font(ChungHwa.Typography.serif(26, weight: .semibold))
                    .tracking(-0.4)
                    .foregroundStyle(color)
                    .monospacedDigit()
                Text(unit)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(color)
            }
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

/// Two-series area chart. Pulls from TrafficStore (1/5min) or
/// TrafficHistoryStore (15min) depending on the selected range.
struct TrafficChart: View {
    let range: LiveTrafficCard.Range

    @Environment(TrafficStore.self) private var traffic
    @Environment(TrafficHistoryStore.self) private var historyStore

    var body: some View {
        let series = makeSeries()
        // Y-axis ceiling: walk the same series we plot. makeSeries() is the
        // hot path here (1Hz from /traffic), so we cannot afford to walk it
        // twice per body.
        var peak: Double = 0
        for p in series {
            if p.up   > peak { peak = p.up }
            if p.down > peak { peak = p.down }
        }
        return Chart {
            ForEach(series) { p in
                AreaMark(
                    x: .value("t", p.idx),
                    yStart: .value("0", 0),
                    yEnd: .value("v", p.up)
                )
                .foregroundStyle(.linearGradient(
                    colors: [ChungHwa.Palette.patina.opacity(0.30),
                             ChungHwa.Palette.patina.opacity(0)],
                    startPoint: .top, endPoint: .bottom))
                .interpolationMethod(.linear)

                AreaMark(
                    x: .value("t", p.idx),
                    yStart: .value("0", 0),
                    yEnd: .value("v", p.down)
                )
                .foregroundStyle(.linearGradient(
                    colors: [ChungHwa.Palette.brass.opacity(0.28),
                             ChungHwa.Palette.brass.opacity(0)],
                    startPoint: .top, endPoint: .bottom))
                .interpolationMethod(.linear)

                LineMark(x: .value("t", p.idx), y: .value("up", p.up))
                    .foregroundStyle(ChungHwa.Palette.patina)
                    .lineStyle(StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.linear)

                LineMark(x: .value("t", p.idx), y: .value("down", p.down))
                    .foregroundStyle(ChungHwa.Palette.brass)
                    .lineStyle(StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.linear)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        // Force a non-degenerate y-domain so a flat 0-series still draws a
        // baseline at the chart bottom instead of collapsing the plot area.
        .chartYScale(domain: 0...max(1, peak))
    }

    private struct Point: Identifiable {
        let idx: Int
        let up: Double
        let down: Double
        var id: Int { idx }
    }

    /// 1/5min slices from TrafficStore.samples (1Hz, 90s ring); 15min from
    /// TrafficHistoryStore minute buckets.
    private func makeSeries() -> [Point] {
        let raw: [Point] = {
            switch range {
            case .oneMin:
                let take = min(60, traffic.samples.count)
                let slice = traffic.samples.suffix(take)
                return slice.enumerated().map { i, s in
                    Point(idx: i, up: Double(s.upBps), down: Double(s.downBps))
                }
            case .fiveMin:
                let slice = traffic.samples
                return slice.enumerated().map { i, s in
                    Point(idx: i, up: Double(s.upBps), down: Double(s.downBps))
                }
            case .fifteenMin:
                let cutoff = Date().addingTimeInterval(-15 * 60)
                let buckets = historyStore.minutes.filter { $0.minuteStart >= cutoff }
                return buckets.enumerated().map { i, b in
                    Point(idx: i,
                          up: Double(b.upBytes) / 60.0,
                          down: Double(b.downBytes) / 60.0)
                }
            }
        }()
        // Empty buffer → flat 0-line across the chart width so the user sees
        // an axis instead of blank space. Two endpoints suffice; Chart fills.
        if raw.isEmpty {
            return [Point(idx: 0, up: 0, down: 0),
                    Point(idx: 60, up: 0, down: 0)]
        }
        return raw
    }
}

/// Session totals + today's累计. `today` derives from history minute
/// buckets so it survives the 90s rolling buffer.
struct TrafficTotalsRow: View {
    @Environment(TrafficStore.self) private var traffic
    @Environment(TrafficHistoryStore.self) private var historyStore

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            totals(label: "本次会话",
                   up: traffic.totalUp, down: traffic.totalDown)
                .frame(maxWidth: .infinity, alignment: .leading)
            todayTotals
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var todayTotals: some View {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: Date())
        var up = 0, down = 0
        for b in historyStore.minutes where b.minuteStart >= dayStart {
            up &+= b.upBytes
            down &+= b.downBytes
        }
        return totals(label: "今日", up: up, down: down)
    }

    private func totals(label: String, up: Int, down: Int) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 10.5))
                .foregroundStyle(ChungHwa.Palette.dim)
            HStack(spacing: 12) {
                HStack(spacing: 3) {
                    Text("↑").foregroundStyle(ChungHwa.Palette.patina)
                    Text(up > 0 ? ChFormat.bytes(up) : "—")
                        .foregroundStyle(ChungHwa.Palette.text)
                        .fontWeight(.semibold)
                }
                HStack(spacing: 3) {
                    Text("↓").foregroundStyle(ChungHwa.Palette.brass)
                    Text(down > 0 ? ChFormat.bytes(down) : "—")
                        .foregroundStyle(ChungHwa.Palette.text)
                        .fontWeight(.semibold)
                }
            }
            .font(.system(size: 11))
            .monospacedDigit()
        }
    }
}
