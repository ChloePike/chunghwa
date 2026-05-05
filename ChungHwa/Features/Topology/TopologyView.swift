import SwiftUI

/// Sankey-ish view of the active proxy chain (GLOBAL → group → upstream).
/// Path width + brass intensity track live connection counts; idle paths
/// fade to the neutral line colour.
struct TopologyView: View {
    @Environment(KernelController.self) private var kernel
    @Environment(ProxyStore.self) private var store
    @Environment(ConnectionsStore.self) private var connectionsStore

    var body: some View {
        Group {
            if kernel.apiClient == nil {
                emptyState(
                    symbol: "powerplug",
                    title: "内核未启动",
                    subtitle: "在概览页启动后再来看。"
                )
            } else if store.groups.isEmpty && store.isRefreshing {
                ProgressView().controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.groups.isEmpty {
                emptyState(
                    symbol: "point.3.connected.trianglepath.dotted",
                    title: "没有代理组",
                    subtitle: "当前配置里没有 proxy-groups。"
                )
            } else if connectionsStore.connections.isEmpty {
                emptyState(
                    symbol: "point.3.connected.trianglepath.dotted",
                    title: "暂无连接",
                    subtitle: "上网产生流量后这里会画出拓扑。"
                )
            } else {
                content
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ChungHwa.Palette.bg)
        .task(id: kernelStatusKey) {
            await store.refresh(api: kernel.apiClient)
        }
    }

    /// Tally connections-per-group and connections-per-upstream from the
    /// current `ConnectionsStore` snapshot. Recomputed every render — the
    /// snapshot is small (typically <500 entries).
    private var activity: TopologyActivity {
        var groupCounts: [String: Int] = [:]
        var upstreamCounts: [String: Int] = [:]
        for conn in connectionsStore.connections {
            guard let upstream = conn.chains.last else { continue }
            upstreamCounts[upstream, default: 0] += 1
            // Earlier entries in the chain are the groups that routed to it.
            // `chains` ordering is innermost-first, so everything before the
            // last element is a group.
            if conn.chains.count > 1 {
                for g in conn.chains.dropLast() {
                    groupCounts[g, default: 0] += 1
                }
            }
        }
        return TopologyActivity(groupCounts: groupCounts,
                                upstreamCounts: upstreamCounts,
                                totalConnections: connectionsStore.connections.count)
    }

    private var kernelStatusKey: String {
        switch kernel.status {
        case .idle:           return "idle"
        case .starting:       return "starting"
        case .failed(let r):  return "failed:\(r)"
        case .running(let v): return "running:\(v)"
        }
    }

    // MARK: layout

    private var content: some View {
        let activity = self.activity
        let model = TopologyModel(groups: store.groups,
                                  store: store,
                                  activity: activity)
        return ScrollView([.vertical, .horizontal]) {
            VStack(alignment: .leading, spacing: 18) {
                header(model: model, activity: activity)
                TopologyDiagram(model: model)
                    .padding(.bottom, 4)
                Text("线条越粗越亮，表示走的连接越多")
                    .font(.system(size: 10))
                    .foregroundStyle(ChungHwa.Palette.faint)
                    .padding(.bottom, 8)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
    }

    private func header(model: TopologyModel, activity: TopologyActivity) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("拓扑")
                    .font(ChungHwa.Typography.serif(22, weight: .medium))
                    .foregroundStyle(ChungHwa.Palette.text)
                    .tracking(-0.3)
                Text("\(model.groups.count) 组 · \(model.upstreams.count) 上游 · \(activity.totalConnections) 个连接")
                    .font(.system(size: 12))
                    .foregroundStyle(ChungHwa.Palette.dim)
            }
            Spacer(minLength: 16)
            refreshButton
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var refreshButton: some View {
        Button {
            Task { await store.refresh(api: kernel.apiClient) }
        } label: {
            HStack(spacing: 6) {
                if store.isRefreshing {
                    ProgressView().controlSize(.mini).scaleEffect(0.7)
                        .frame(width: 11, height: 11)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                }
                Text(store.isRefreshing ? "刷新中…" : "刷新")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(ChungHwa.Palette.text)
            .padding(.horizontal, 11)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(ChungHwa.Palette.fill)
                    .strokeBorder(ChungHwa.Palette.line, lineWidth: 0.5)
            )
            .opacity(store.isRefreshing ? 0.6 : 1)
        }
        .buttonStyle(.plain)
        .disabled(store.isRefreshing || kernel.apiClient == nil)
    }

    // MARK: empty state

    private func emptyState(symbol: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 44)).foregroundStyle(ChungHwa.Palette.faint)
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(ChungHwa.Palette.text)
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(ChungHwa.Palette.dim)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }
}

/// Live connection counts keyed by group / upstream name so the diagram
/// can light up the heaviest paths.
struct TopologyActivity {
    let groupCounts: [String: Int]
    let upstreamCounts: [String: Int]
    let totalConnections: Int

    func group(_ name: String) -> Int { groupCounts[name] ?? 0 }
    func upstream(_ name: String) -> Int { upstreamCounts[name] ?? 0 }
}

/// Pre-computed positions and links for the diagram. Doing this once
/// outside of the Canvas/overlay layout keeps both branches in lockstep.
private struct TopologyModel {
    struct Node: Identifiable, Hashable {
        enum Kind: Hashable { case root, group, upstream }
        let id: String
        let kind: Kind
        let title: String
        let subtitle: String?
        let lastDelay: Int?
        let position: CGPoint
        let isActive: Bool
        /// Live connection count routed through this node, used to drive
        /// brass intensity and the corner badge.
        let activity: Int
    }

    struct Link: Hashable {
        let from: CGPoint
        let to: CGPoint
        let active: Bool
        /// Live connections flowing through this link. 0 → neutral line.
        let activity: Int
    }

    let groups: [MihomoProxy]
    /// Names of upstreams referenced by some group's `now`, deduplicated and
    /// preserved in the order their groups first appear so the layout is
    /// stable across refreshes.
    let upstreams: [String]

    let canvasSize: CGSize
    let nodes: [Node]
    let links: [Link]

    // Card metrics are shared between the Canvas (for link endpoints) and
    // the overlay (for card frames), so they live as constants here.
    static let cardWidth: CGFloat = 156
    static let cardHeight: CGFloat = 50
    static let columnGap: CGFloat = 110
    static let rowGap: CGFloat = 14
    static let topPadding: CGFloat = 14
    static let sidePadding: CGFloat = 14
    static let minDiagramWidth: CGFloat = 720

    init(groups: [MihomoProxy], store: ProxyStore, activity: TopologyActivity) {
        // Filter groups down to those that currently carry traffic. The
        // outer view only renders this branch when at least one connection
        // exists, so this drops the noise of idle groups from the diagram.
        let filteredGroups = groups.filter { activity.group($0.name) > 0 }
        self.groups = filteredGroups

        // Build the right column: each upstream a filtered group points at,
        // in first-seen order. We also drop upstreams whose activity is 0
        // (defensive — usually a routed group implies a hot upstream, but
        // the connections-store snapshot can lag), while still keeping
        // the column populated for any filtered group whose `now` is the
        // only path we have.
        var seen = Set<String>()
        var ups: [String] = []
        for g in filteredGroups {
            guard let now = g.now, !now.isEmpty else { continue }
            // Keep an upstream if it has activity, OR if the group routing
            // to it has activity (so the link still has a target column).
            let upActive = activity.upstream(now) > 0
            let groupActive = activity.group(g.name) > 0
            guard upActive || groupActive else { continue }
            if seen.insert(now).inserted {
                ups.append(now)
            }
        }
        self.upstreams = ups

        // Layout — three columns. Row count is max(groups, upstreams, 1)
        // so the diagram is tall enough for whichever side is longest.
        let rowCount = max(filteredGroups.count, ups.count, 1)
        let totalRowsHeight = CGFloat(rowCount) * Self.cardHeight
            + CGFloat(max(rowCount - 1, 0)) * Self.rowGap
        let height = totalRowsHeight + Self.topPadding * 2
        // Three columns of cards + two gaps + side padding either edge.
        let baseWidth = Self.cardWidth * 3
            + Self.columnGap * 2
            + Self.sidePadding * 2
        let width = max(baseWidth, Self.minDiagramWidth)
        self.canvasSize = CGSize(width: width, height: height)

        // X centres for each column.
        let colSpan = baseWidth - Self.sidePadding * 2
        let colXs = [
            Self.sidePadding + Self.cardWidth / 2,
            Self.sidePadding + colSpan / 2,
            Self.sidePadding + colSpan - Self.cardWidth / 2,
        ]

        // Helper that vertically distributes `n` cards inside the canvas.
        func ys(count: Int) -> [CGFloat] {
            guard count > 0 else { return [] }
            let used = CGFloat(count) * Self.cardHeight
                + CGFloat(max(count - 1, 0)) * Self.rowGap
            let startY = (height - used) / 2 + Self.cardHeight / 2
            return (0..<count).map { i in
                startY + CGFloat(i) * (Self.cardHeight + Self.rowGap)
            }
        }

        let groupYs = ys(count: filteredGroups.count)
        let upstreamYs = ys(count: ups.count)

        // Root node — single GLOBAL card vertically centred.
        let rootPos = CGPoint(x: colXs[0], y: height / 2)
        let rootNode = Node(
            id: "GLOBAL",
            kind: .root,
            title: "全局",
            subtitle: "规则模式",
            lastDelay: nil,
            position: rootPos,
            isActive: true,
            activity: activity.totalConnections
        )

        var allNodes: [Node] = [rootNode]
        var allLinks: [Link] = []

        // Group column.
        var groupCenters: [String: CGPoint] = [:]
        for (i, g) in filteredGroups.enumerated() {
            let pos = CGPoint(x: colXs[1], y: groupYs[i])
            groupCenters[g.name] = pos
            let isActive = (g.now != nil)
            let groupActivity = activity.group(g.name)
            allNodes.append(Node(
                id: "group:\(g.name)",
                kind: .group,
                title: g.name,
                subtitle: g.type,
                lastDelay: nil,
                position: pos,
                isActive: isActive,
                activity: groupActivity
            ))
            // GLOBAL → group. Width/colour of this leg keys off how many
            // live connections pass through the group.
            allLinks.append(Link(
                from: CGPoint(x: rootPos.x + Self.cardWidth / 2, y: rootPos.y),
                to:   CGPoint(x: pos.x - Self.cardWidth / 2,     y: pos.y),
                active: isActive,
                activity: groupActivity
            ))
        }

        // Upstream column.
        var upstreamCenters: [String: CGPoint] = [:]
        for (i, name) in ups.enumerated() {
            let pos = CGPoint(x: colXs[2], y: upstreamYs[i])
            upstreamCenters[name] = pos
            let proxy = store.proxy(name)
            allNodes.append(Node(
                id: "up:\(name)",
                kind: .upstream,
                title: name,
                subtitle: proxy?.type.uppercased(),
                lastDelay: proxy?.lastDelay,
                position: pos,
                isActive: true,
                activity: activity.upstream(name)
            ))
        }

        // group → upstream. We approximate per-link traffic by min(group,
        // upstream) — the connections-store doesn't expose per-edge counts,
        // so this avoids over-stating either node's load. The guard also
        // ensures we only draw an edge when both endpoints survived the
        // activity filter above.
        for g in filteredGroups {
            guard let now = g.now,
                  let from = groupCenters[g.name],
                  let to = upstreamCenters[now] else { continue }
            let edgeActivity = min(activity.group(g.name), activity.upstream(now))
            allLinks.append(Link(
                from: CGPoint(x: from.x + Self.cardWidth / 2, y: from.y),
                to:   CGPoint(x: to.x - Self.cardWidth / 2,   y: to.y),
                active: true,
                activity: edgeActivity
            ))
        }

        self.nodes = allNodes
        self.links = allLinks
    }
}

/// Brass colour and stroke width derived from a connection count. Keeps
/// links readable when N=0 (subtle line) and saturates at high N so a
/// single dominant path doesn't blow out.
private enum TopoStyle {
    static func linkColor(activity: Int, fallback: Color) -> Color {
        guard activity > 0 else { return fallback }
        let opacity = min(0.85, 0.30 + 0.10 * Double(activity))
        return ChungHwa.Palette.brass.opacity(opacity)
    }

    static func linkWidth(activity: Int, inactive: CGFloat = 1.0) -> CGFloat {
        guard activity > 0 else { return inactive }
        let bonus = min(2.4, log2(Double(activity + 1)) * 0.6)
        return 1.2 + CGFloat(bonus)
    }
}

private struct TopologyDiagram: View {
    let model: TopologyModel

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Curved links behind the cards.
            Canvas { ctx, _ in
                for link in model.links {
                    var path = Path()
                    path.move(to: link.from)
                    let dx = link.to.x - link.from.x
                    let c1 = CGPoint(x: link.from.x + dx * 0.55, y: link.from.y)
                    let c2 = CGPoint(x: link.to.x   - dx * 0.55, y: link.to.y)
                    path.addCurve(to: link.to, control1: c1, control2: c2)
                    // Inactive links (no `now`) keep the neutral line; active
                    // links light up proportional to how many connections
                    // currently traverse them.
                    let fallback: Color = link.active
                        ? ChungHwa.Palette.brass.opacity(0.30)
                        : ChungHwa.Palette.line
                    let color = TopoStyle.linkColor(activity: link.activity,
                                                    fallback: fallback)
                    let width = TopoStyle.linkWidth(activity: link.activity,
                                                    inactive: link.active ? 1.2 : 1.0)
                    ctx.stroke(path,
                               with: .color(color),
                               style: StrokeStyle(lineWidth: width, lineCap: .round))
                }
            }
            .frame(width: model.canvasSize.width, height: model.canvasSize.height)

            // Node overlay.
            ForEach(model.nodes) { node in
                NodeCard(node: node)
                    .frame(width: TopologyModel.cardWidth,
                           height: TopologyModel.cardHeight)
                    .position(x: node.position.x, y: node.position.y)
            }

            // Column labels at the top — purely decorative, but anchor the
            // user's reading.
            columnLabels
        }
        .frame(width: model.canvasSize.width, height: model.canvasSize.height)
    }

    private var columnLabels: some View {
        let xs = model.nodes.reduce(into: [TopologyModel.Node.Kind: CGFloat]()) { acc, n in
            if acc[n.kind] == nil { acc[n.kind] = n.position.x }
        }
        let labels: [(TopologyModel.Node.Kind, String)] = [
            (.root,     "入口"),
            (.group,    "代理组"),
            (.upstream, "上游"),
        ]
        return ZStack(alignment: .topLeading) {
            ForEach(labels, id: \.0) { kind, text in
                if let x = xs[kind] {
                    Text(text)
                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                        .tracking(0.6)
                        .foregroundStyle(ChungHwa.Palette.faint)
                        .position(x: x, y: 8)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

private struct NodeCard: View {
    let node: TopologyModel.Node

    var body: some View {
        switch node.kind {
        case .root:     rootBody
        case .group:    groupBody
        case .upstream: upstreamBody
        }
    }

    // MARK: variants

    private var rootBody: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                ChDot(color: ChungHwa.Palette.brass, size: 6)
                Text(node.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ChungHwa.Palette.text)
            }
            if let s = node.subtitle {
                Text(s)
                    .font(.system(size: 10.5))
                    .foregroundStyle(ChungHwa.Palette.dim)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.horizontal, 11)
        .modifier(CardChrome(active: true, hasActivity: node.activity > 0))
    }

    private var groupBody: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(node.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(ChungHwa.Palette.text)
                .lineLimit(1)
                .truncationMode(.middle)
            if let s = node.subtitle {
                Text(s.uppercased())
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    .tracking(0.3)
                    .foregroundStyle(ChungHwa.Palette.faint)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(ChungHwa.Palette.fill)
                    )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.horizontal, 11)
        // Brass border now keys off live connections, not just `now`. A
        // group with `now` set but zero traffic shows the neutral chrome.
        .modifier(CardChrome(active: false, hasActivity: node.activity > 0))
        .overlay(alignment: .topTrailing) { activityBadge }
    }

    private var upstreamBody: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(node.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ChungHwa.Palette.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let s = node.subtitle {
                    Text(s)
                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                        .tracking(0.3)
                        .foregroundStyle(ChungHwa.Palette.faint)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            latencyTag
        }
        .padding(.horizontal, 11)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        // Same activity-driven accent as group cards.
        .modifier(CardChrome(active: false, hasActivity: node.activity > 0))
        .overlay(alignment: .topTrailing) { activityBadge }
    }

    /// Small "•N" tag tucked into the top-right corner of group/upstream
    /// cards when they have live connections. Mono 10pt to harmonize with
    /// the existing type-tag.
    @ViewBuilder
    private var activityBadge: some View {
        if node.activity > 0 {
            Text("\u{2022}\(node.activity)")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(ChungHwa.Palette.brass)
                .padding(.horizontal, 4).padding(.vertical, 1)
                .background(
                    Capsule(style: .continuous)
                        .fill(ChungHwa.Palette.brass.opacity(0.12))
                )
                .padding(5)
        }
    }

    @ViewBuilder
    private var latencyTag: some View {
        if let ms = node.lastDelay, ms > 0 {
            Text("\(ms) ms")
                .font(.system(size: 10.5, weight: .bold))
                .foregroundStyle(ChLatency.color(ms))
                .monospacedDigit()
        } else {
            Text("—")
                .font(.system(size: 10.5, weight: .bold))
                .foregroundStyle(ChungHwa.Palette.faint)
                .monospacedDigit()
        }
    }
}

/// Card surface. Brass accent keys off `hasActivity` (live connections),
/// not `active` (group has a `now`); the root card passes `active: true`
/// to keep its permanent brass treatment regardless of traffic.
private struct CardChrome: ViewModifier {
    /// True for the root card (always brass). Group/upstream cards pass
    /// `false` and let `hasActivity` decide the accent.
    let active: Bool
    /// True when this node currently carries live connections.
    let hasActivity: Bool

    private var lit: Bool { active || hasActivity }

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(lit
                          ? ChungHwa.Palette.brass.opacity(0.10)
                          : ChungHwa.Palette.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(lit ? ChungHwa.Palette.brass
                                       : ChungHwa.Palette.line,
                                  lineWidth: lit ? 1 : 0.5)
            )
            .shadow(color: lit
                    ? ChungHwa.Palette.brass.opacity(0.18)
                    : .black.opacity(0.03),
                    radius: lit ? 1 : 0.5, y: 1)
    }
}
