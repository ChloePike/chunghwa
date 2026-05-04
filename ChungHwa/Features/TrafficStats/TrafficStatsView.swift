import Charts
import SwiftUI

/// Bone & Brass Traffic Stats surface. The Live card reflects real data
/// streamed via `TrafficStore`; the By-Hour and By-Process cards are
/// synthetic placeholders until persistent multi-day storage lands. Mirrors
/// the layout of the design's stats screen — see `design/src/app.jsx`.
struct TrafficStatsView: View {
    @Environment(TrafficStore.self) private var traffic
    @Environment(KernelController.self) private var kernel

    /// Deterministic mock series (computed once per view life) so bars don't
    /// reshuffle on every render.
    private let hourBars: [Double] = makeHourBars(seed: 42)
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
        .navigationTitle("Traffic Stats")
    }

    // MARK: - Live (real)

    private var liveCard: some View {
        ChCardWithHeader(
            "Live",
            systemImage: "chart.line.uptrend.xyaxis",
            iconColor: ChungHwa.Palette.brass,
            right: { EmptyView() }
        ) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 16) {
                    liveColumn(
                        caption: "Upload Speed",
                        arrow: "↑",
                        bps: traffic.current?.upBps ?? 0,
                        series: traffic.samples.map { Double($0.upBps) },
                        color: ChungHwa.Palette.patina
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)

                    liveColumn(
                        caption: "Download Speed",
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
            stripChunk(label: "Peak ↑", value: ChFormat.rate(traffic.peakUp))
            stripDot
            stripChunk(label: "Peak ↓", value: ChFormat.rate(traffic.peakDown))
            stripDot
            stripChunk(label: "Total ↑", value: ChFormat.bytes(traffic.totalUp))
            stripDot
            stripChunk(label: "Total ↓", value: ChFormat.bytes(traffic.totalDown))
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

    // MARK: - By Hour (mock)

    private var byHourCard: some View {
        ChCardWithHeader(
            "By Hour",
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
                    Text("Daily Avg ")
                        .foregroundStyle(ChungHwa.Palette.dim)
                    + Text(dailyAverageString)
                        .foregroundStyle(ChungHwa.Palette.text)
                        .fontWeight(.semibold)
                    Spacer()
                    Text("Peak ")
                        .foregroundStyle(ChungHwa.Palette.dim)
                    + Text(hourlyPeakString)
                        .foregroundStyle(ChungHwa.Palette.text)
                        .fontWeight(.semibold)
                }
                .font(.system(size: 11))
                .monospacedDigit()

                demoNote
            }
        }
    }

    private var hourChart: some View {
        let currentHour = Calendar.current.component(.hour, from: Date())
        return Chart {
            ForEach(Array(hourBars.enumerated()), id: \.offset) { idx, v in
                BarMark(
                    x: .value("hour", idx),
                    y: .value("mb", v),
                    width: .ratio(0.62)
                )
                .foregroundStyle(
                    idx == currentHour
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
            "By Process",
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
            "Memory & Session",
            systemImage: "memorychip",
            iconColor: ChungHwa.Palette.patina,
            right: { EmptyView() }
        ) {
            HStack(alignment: .top, spacing: 14) {
                ChStat(
                    label: "Kernel Memory",
                    value: traffic.memoryInUse > 0 ? ChFormat.bytes(traffic.memoryInUse) : "—",
                    systemImage: "cpu",
                    color: ChungHwa.Palette.brass
                )
                .frame(maxWidth: .infinity, alignment: .leading)

                ChStat(
                    label: "Live Samples",
                    value: "\(traffic.samples.count)",
                    systemImage: "waveform.path",
                    color: ChungHwa.Palette.brass
                )
                .frame(maxWidth: .infinity, alignment: .leading)

                ChStat(
                    label: "OS Limit",
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
            Text("Kernel not running")
                .font(ChungHwa.Typography.serif(18, weight: .medium))
                .foregroundStyle(ChungHwa.Palette.text)
                .tracking(-0.2)
            Text("Start the kernel to see live traffic statistics.")
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
        Text("Demo data — historical logging coming soon")
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
        let total = hourBars.reduce(0, +)
        let avg = total / Double(max(hourBars.count, 1))
        return formatMB(avg)
    }

    private var hourlyPeakString: String {
        formatMB(hourBars.max() ?? 0)
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

/// Mulberry32 PRNG seeded by `seed` so the bar heights are stable across
/// view rebuilds — same shape every render.
private func makeHourBars(seed: UInt32) -> [Double] {
    var state: UInt32 = seed
    func next() -> Double {
        state &+= 0x6D2B79F5
        var z: UInt32 = state
        z = (z ^ (z >> 15)) &* (z | 1)
        z = z &+ ((z ^ (z >> 7)) &* (z | 61))
        z = z ^ (z >> 14)
        return Double(z) / Double(UInt32.max)
    }

    return (0..<24).map { i in
        // Daily curve: low overnight, peak around midday + early evening.
        let phase = Double(i) / 24.0 * 2 * .pi
        let curve = 0.55 + 0.45 * sin(phase - .pi / 2)
        let evening = 0.25 * exp(-pow(Double(i) - 20, 2) / 8)
        let noise = (next() - 0.5) * 0.25
        let raw = max(0.05, curve + evening + noise)
        return raw * 220 // scaled to MB
    }
}
