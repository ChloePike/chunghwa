import Charts
import SwiftUI

// MARK: - Public surface

/// Bone & Brass dashboard. Reads only `KernelController` + a handful of
/// store identities at the parent level; every value that ticks at 1Hz lives
/// inside a leaf so the entire surface doesn't re-evaluate per sample.
struct OverviewView: View {
    @Environment(KernelController.self) private var kernel

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                LiveTrafficCard()

                // Three short cards in one row — same intrinsic content height
                // so the row reads as a clean band. Proxy groups goes full
                // width below since its row count varies wildly.
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12),
                    ],
                    spacing: 12
                ) {
                    NetworkCard()
                    ResourcesCard()
                    SubscriptionHealthCard()
                }

                ProxyGroupsCard()
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 18)
        }
        .background(ChungHwa.Palette.bg)
    }
}

// MARK: - Tab routing

/// Posts the sidebar-switch notification ContentView already listens for.
private func switchTab(_ tab: SidebarTab) {
    NotificationCenter.default.post(name: .chungHwaSwitchTab, object: tab.rawValue)
}

// MARK: - 2. Live traffic

/// Range selector chips drive the chart series. Owns its own state so the
/// wider page doesn't redraw when the user flips between ranges.
private struct LiveTrafficCard: View {
    enum Range: String, CaseIterable, Hashable {
        case oneMin, fiveMin, fifteenMin
        var label: String {
            switch self {
            case .oneMin:     return "1分钟"
            case .fiveMin:    return "5分钟"
            case .fifteenMin: return "15分钟"
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
private struct LiveSpeedRow: View {
    @Environment(TrafficStore.self) private var traffic

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            speedColumn(arrow: "↑", caption: "上传速度",
                        bps: traffic.current?.upBps ?? 0,
                        color: ChungHwa.Palette.patina)
                .frame(maxWidth: .infinity, alignment: .leading)
            speedColumn(arrow: "↓", caption: "下载速度",
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
private struct TrafficChart: View {
    let range: LiveTrafficCard.Range

    @Environment(TrafficStore.self) private var traffic
    @Environment(TrafficHistoryStore.self) private var historyStore

    var body: some View {
        let series = makeSeries()
        // Compute the y-axis ceiling once from the same series we plot —
        // makeSeries() is the hot path of this view (touched 1Hz from the
        // /traffic stream), so we cannot afford to walk it twice per body.
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

    /// Range chooses the source: 1/5min slice TrafficStore.samples (1Hz, last
    /// 90 s ring), 15min derives from TrafficHistoryStore minute buckets.
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
        // Empty buffer → draw a flat 0-line across the chart width so the
        // user sees an axis instead of blank space. Two endpoints are
        // enough; Chart's monotone interpolation fills the rest.
        if raw.isEmpty {
            return [Point(idx: 0, up: 0, down: 0),
                    Point(idx: 60, up: 0, down: 0)]
        }
        return raw
    }
}

/// Session totals + today累计. `today` is computed from history minute
/// buckets, so it survives the 90s rolling buffer.
private struct TrafficTotalsRow: View {
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
        return totals(label: "今日累计", up: up, down: down)
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

// MARK: - 3. Proxy groups

private struct ProxyGroupsCard: View {
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
                            Text("查看全部 \(proxyStore.groups.count) 组 →")
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
        Text("暂无代理组")
            .font(.system(size: 12))
            .foregroundStyle(ChungHwa.Palette.dim)
            .padding(.vertical, 14)
    }
}

/// One row in the groups card. Owns its testing state so a tap doesn't
/// re-invalidate sibling rows.
private struct ProxyGroupRow: View {
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

    /// Flags require an IP. Group nodes don't carry IPs in /proxies — best we
    /// can do is fall back to mihomo's egress IP when the group is the one
    /// currently routing traffic. Cheap: country() is an O(1) cache read and
    /// schedules a background lookup on miss.
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

// MARK: - 4. Network + IP

private struct NetworkCard: View {
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
                    latencyBlock("互联网", ms: net.internetLatencyMs, symbol: "globe.americas")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    latencyBlock("DNS", ms: net.dnsLatencyMs, symbol: "arrow.left.arrow.right")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    latencyBlock("路由", ms: net.routerLatencyMs, symbol: "wifi.router")
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

    /// `country(for:)` returns either a 2-letter ISO code, the literal `LAN`
    /// sentinel for private addresses, or nil for misses. We render flag emoji
    /// for ISO codes and a house glyph for LAN.
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

// Shared row heights so the three cards in the overview's 3-col band line
// up at the same vertical positions regardless of internal content.
private let statTopRowHeight: CGFloat = 54
private let statBottomRowHeight: CGFloat = 36

// MARK: - 5. Active connections + resources

private struct ResourcesCard: View {
    var body: some View {
        ChCardWithHeader(
            "活跃 · 资源",
            systemImage: "speedometer",
            iconColor: ChungHwa.Palette.patina,
            right: { EmptyView() }
        ) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    ConnectionCountStat()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    MemoryStat()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: statTopRowHeight)

                HStack(alignment: .top, spacing: 12) {
                    PeakSubStat(direction: .up)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    PeakSubStat(direction: .down)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: statBottomRowHeight)
            }
        }
    }
}

/// Connection count is a button so a click jumps to the Connections tab.
private struct ConnectionCountStat: View {
    @Environment(ConnectionsStore.self) private var connectionsStore

    var body: some View {
        Button { switchTab(.connections) } label: {
            ChStat(
                label: "连接数",
                value: String(connectionsStore.connectionCount),
                systemImage: "arrow.left.arrow.right",
                color: ChungHwa.Palette.brass
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

/// Peak rate as a sub-stat (smaller font) so it shares vertical rhythm with
/// NetworkCard's "出口 IP / 本地 IP" sub-stat row instead of duplicating the
/// big serif of the top stat row.
private struct PeakSubStat: View {
    enum Direction { case up, down }
    let direction: Direction

    @Environment(TrafficStore.self) private var traffic

    var body: some View {
        let bps = direction == .up ? traffic.peakUp : traffic.peakDown
        ChSubStat(
            direction == .up ? "峰值 ↑" : "峰值 ↓",
            value: bps > 0 ? ChFormat.rate(bps) : "—",
            systemImage: direction == .up ? "arrow.up.right" : "arrow.down.right"
        )
    }
}

// MARK: - 6. Subscription / config health

private struct SubscriptionHealthCard: View {
    @Environment(ProfileStore.self) private var profileStore
    @Environment(ProxyStore.self) private var proxyStore
    @Environment(RuleStore.self) private var ruleStore
    @Environment(KernelController.self) private var kernel

    @State private var refreshing = false

    var body: some View {
        ChCardWithHeader(
            "配置健康",
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
                    Text("上次更新")
                        .font(.system(size: 10.5))
                        .foregroundStyle(ChungHwa.Palette.dim)
                    Text(updatedAtText)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(ChungHwa.Palette.text)
                    Spacer(minLength: 0)
                    Button { switchTab(.profiles) } label: {
                        Text("管理配置 →")
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
                Text("更新订阅")
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
