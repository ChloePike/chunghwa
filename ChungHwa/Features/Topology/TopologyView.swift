import SwiftUI

// MARK: - Public screen

/// Sankey-ish visualization of the active proxy chain:
///
///   GLOBAL  ──▶  group  ──▶  upstream
///
/// We don't actually know which group is currently routing without runtime
/// matching info, so every group's `now` upstream is highlighted uniformly
/// — this conveys the static shape of the routing fabric, which is the
/// useful affordance here.
struct TopologyView: View {
    @Environment(KernelController.self) private var kernel
    @Environment(ProxyStore.self) private var store

    var body: some View {
        Group {
            if kernel.apiClient == nil {
                emptyState(
                    symbol: "powerplug",
                    title: "Kernel is not running",
                    subtitle: "Start the kernel from Overview to see the active topology."
                )
            } else if store.groups.isEmpty && store.isRefreshing {
                ProgressView().controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.groups.isEmpty {
                emptyState(
                    symbol: "point.3.connected.trianglepath.dotted",
                    title: "No proxy groups",
                    subtitle: "Topology renders once your active profile defines `proxy-groups`."
                )
            } else {
                content
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ChungHwa.Palette.bg)
        .navigationTitle("Topology")
        .task(id: kernelStatusKey) {
            await store.refresh(api: kernel.apiClient)
        }
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
        let model = TopologyModel(groups: store.groups, store: store)
        return ScrollView([.vertical, .horizontal]) {
            VStack(alignment: .leading, spacing: 18) {
                header(model: model)
                TopologyDiagram(model: model)
                    .padding(.bottom, 8)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
    }

    private func header(model: TopologyModel) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Active Topology")
                    .font(ChungHwa.Typography.serif(22, weight: .medium))
                    .foregroundStyle(ChungHwa.Palette.text)
                    .tracking(-0.3)
                Text("\(model.groups.count) groups routing through \(model.upstreams.count) upstreams")
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
                Text(store.isRefreshing ? "Refreshing" : "Refresh")
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

// MARK: - Model

/// Pre-computed positions and links for the diagram. Doing this once outside
/// of the Canvas/overlay layout keeps both branches in lockstep.
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
    }

    struct Link: Hashable {
        let from: CGPoint
        let to: CGPoint
        let active: Bool
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

    init(groups: [MihomoProxy], store: ProxyStore) {
        self.groups = groups

        // Build the right column: each upstream a group points at, in
        // first-seen order.
        var seen = Set<String>()
        var ups: [String] = []
        for g in groups {
            if let now = g.now, !now.isEmpty, seen.insert(now).inserted {
                ups.append(now)
            }
        }
        self.upstreams = ups

        // Layout — three columns. Row count is max(groups, upstreams, 1)
        // so the diagram is tall enough for whichever side is longest.
        let rowCount = max(groups.count, ups.count, 1)
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

        let groupYs = ys(count: groups.count)
        let upstreamYs = ys(count: ups.count)

        // Root node — single GLOBAL card vertically centred.
        let rootPos = CGPoint(x: colXs[0], y: height / 2)
        let rootNode = Node(
            id: "GLOBAL",
            kind: .root,
            title: "GLOBAL",
            subtitle: "Mode: Rule",
            lastDelay: nil,
            position: rootPos,
            isActive: true
        )

        var allNodes: [Node] = [rootNode]
        var allLinks: [Link] = []

        // Group column.
        var groupCenters: [String: CGPoint] = [:]
        for (i, g) in groups.enumerated() {
            let pos = CGPoint(x: colXs[1], y: groupYs[i])
            groupCenters[g.name] = pos
            let isActive = (g.now != nil)
            allNodes.append(Node(
                id: "group:\(g.name)",
                kind: .group,
                title: g.name,
                subtitle: g.type,
                lastDelay: nil,
                position: pos,
                isActive: isActive
            ))
            // GLOBAL → group
            allLinks.append(Link(
                from: CGPoint(x: rootPos.x + Self.cardWidth / 2, y: rootPos.y),
                to:   CGPoint(x: pos.x - Self.cardWidth / 2,     y: pos.y),
                active: isActive
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
                isActive: true
            ))
        }

        // group → upstream
        for g in groups {
            guard let now = g.now,
                  let from = groupCenters[g.name],
                  let to = upstreamCenters[now] else { continue }
            allLinks.append(Link(
                from: CGPoint(x: from.x + Self.cardWidth / 2, y: from.y),
                to:   CGPoint(x: to.x - Self.cardWidth / 2,   y: to.y),
                active: true
            ))
        }

        self.nodes = allNodes
        self.links = allLinks
    }
}

// MARK: - Diagram

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
                    let color: Color = link.active
                        ? ChungHwa.Palette.brass.opacity(0.5)
                        : ChungHwa.Palette.line
                    ctx.stroke(path,
                               with: .color(color),
                               style: StrokeStyle(lineWidth: link.active ? 1.4 : 1.0,
                                                  lineCap: .round))
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
            (.root,     "ROOT"),
            (.group,    "GROUPS"),
            (.upstream, "UPSTREAMS"),
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

// MARK: - Node card

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
        .modifier(CardChrome(active: true))
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
        .modifier(CardChrome(active: node.isActive))
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
        .modifier(CardChrome(active: node.isActive))
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

// MARK: - Card chrome

/// Bone & Brass card surface with optional brass accent for active path
/// nodes. Inlined here instead of leaning on `ChCard` because we need a
/// tighter padding budget and a brass-tinted variant.
private struct CardChrome: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(active
                          ? ChungHwa.Palette.brass.opacity(0.10)
                          : ChungHwa.Palette.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(active ? ChungHwa.Palette.brass
                                          : ChungHwa.Palette.line,
                                  lineWidth: active ? 1 : 0.5)
            )
            .shadow(color: active
                    ? ChungHwa.Palette.brass.opacity(0.18)
                    : .black.opacity(0.03),
                    radius: active ? 1 : 0.5, y: 1)
    }
}
