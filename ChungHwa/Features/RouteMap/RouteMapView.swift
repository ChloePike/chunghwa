import SwiftUI

/// Bone & Brass on Patina 路由地图.
///
/// 以亚洲为中心的简化等距圆柱投影地图，从用户原点（默认设在香港一带，
/// 待 M5+ Local IP 探测接入后替换）向各代理目的地画 quadratic bezier 弧线，
/// 弧线上分布若干 SF Symbol 飞机沿曲线缓动循环。地图轮廓为手绘控制点，
/// 不依赖外部 GeoJSON。所有目的地为 mock —— 真实 IP→GeoIP 查询将在 M5+ 接入。
struct RouteMapView: View {
    @Environment(KernelController.self) private var kernel
    @Environment(ConnectionsStore.self) private var connectionsStore

    @State private var range: TimeRange = .live

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 14) {
                header
                mapCard
                regionList
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(ChungHwa.Palette.bg)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("路由")
                    .font(ChungHwa.Typography.serif(22, weight: .medium))
                    .foregroundStyle(ChungHwa.Palette.text)
                    .tracking(-0.4)
                Text("\(connectionsStore.connections.count) 个活跃连接")
                    .font(.system(size: 11.5))
                    .foregroundStyle(ChungHwa.Palette.dim)
                    .monospacedDigit()
            }
            Spacer(minLength: 12)
            ChSeg(
                value: range,
                onChange: { range = $0 },
                options: TimeRange.allCases.map { (value: $0, label: $0.label) }
            )
        }
    }

    // MARK: - Buckets

    /// 把每个 unique host 哈希到一个 mock 目的地，给图例显示真实数字用。
    /// 同一 host 始终落在同一目的地（FNV-1a 决定性哈希）。
    private var destinationBuckets: [(dest: MockDestination, count: Int)] {
        var counts: [Int: Int] = [:]
        for conn in connectionsStore.connections {
            let key = conn.metadata.host?.isEmpty == false
                ? conn.metadata.host!
                : (conn.metadata.destinationIP ?? conn.id)
            let idx = MockDestination.bucket(for: key)
            counts[idx, default: 0] += 1
        }
        return counts
            .map { (dest: MockDestination.all[$0.key], count: $0.value) }
            .sorted { $0.count > $1.count }
    }

    /// 时段切换让图例数字与飞机密度有微小差异，显得「切换有反馈」。
    /// 所有数据均为占位 —— 真实历史区间在 M5+ 接历史聚合后替换。
    private var rangeMultiplier: Double {
        switch range {
        case .live:      return 1.0
        case .today:     return 1.6
        case .month:     return 6.4
        case .lastMonth: return 5.1
        }
    }

    // MARK: - Map card

    private var mapCard: some View {
        ChCard(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                MapCanvas(
                    destinations: MockDestination.all,
                    activeIndices: Set(destinationBuckets.map { idx in
                        MockDestination.all.firstIndex(where: { $0.name == idx.dest.name }) ?? 0
                    }),
                    rangeMultiplier: rangeMultiplier
                )
                .frame(height: 360)
                .frame(maxWidth: .infinity)

                Text("地图坐标为示意，IP→GeoIP 在 M5+ 接入后替换")
                    .font(.system(size: 10))
                    .foregroundStyle(ChungHwa.Palette.faint)
            }
        }
    }

    // MARK: - Destination list

    private var regionList: some View {
        ChCardWithHeader("按地区分布", systemImage: "globe.asia.australia") {
            VStack(spacing: 0) {
                if destinationBuckets.isEmpty {
                    HStack {
                        Spacer()
                        Text("无活跃连接")
                            .font(.system(size: 11.5))
                            .foregroundStyle(ChungHwa.Palette.dim)
                        Spacer()
                    }
                    .padding(.vertical, 18)
                } else {
                    ForEach(Array(destinationBuckets.enumerated()), id: \.offset) { idx, entry in
                        if idx > 0 {
                            Rectangle()
                                .fill(ChungHwa.Palette.lineSoft)
                                .frame(height: 0.5)
                        }
                        DestinationRow(
                            destination: entry.dest,
                            count: Int(Double(entry.count) * rangeMultiplier)
                        )
                    }
                }
            }
        }
    }
}

// MARK: - Time range

private enum TimeRange: Hashable, CaseIterable {
    case live, today, month, lastMonth

    var label: String {
        switch self {
        case .live:      return "实时"
        case .today:     return "今日"
        case .month:     return "本月"
        case .lastMonth: return "上月"
        }
    }
}

// MARK: - Destination row

private struct DestinationRow: View {
    let destination: MockDestination
    let count: Int

    var body: some View {
        HStack(spacing: 10) {
            ChDot(color: destination.color, size: 7, pulse: false)
                .frame(width: 12, height: 12)
            Text(destination.name)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(ChungHwa.Palette.text)
            Text(destination.group)
                .font(.system(size: 10.5))
                .foregroundStyle(ChungHwa.Palette.faint)
            Spacer(minLength: 0)
            Text("\(count) 条连接")
                .font(ChungHwa.Typography.mono(11))
                .foregroundStyle(ChungHwa.Palette.dim)
                .monospacedDigit()
        }
        .padding(.vertical, 9)
    }
}

// MARK: - Map projection

/// 简化等距圆柱投影：lon 70..155E / lat 0..50N 映射到画布 0..1。
/// 越界经度会 clamp 到右边缘外（飞机会被裁剪），保证亚洲范围内尺寸正确。
private enum AsiaProjection {
    static let minLon: Double = 70
    static let maxLon: Double = 155
    static let minLat: Double = 0
    static let maxLat: Double = 50

    static func project(lat: Double, lon: Double, in size: CGSize) -> CGPoint {
        let clampedLon = max(minLon - 5, min(maxLon + 5, lon))
        let x = (clampedLon - minLon) / (maxLon - minLon) * Double(size.width)
        let y = (maxLat - lat) / (maxLat - minLat) * Double(size.height)
        return CGPoint(x: x, y: y)
    }
}

// MARK: - Map canvas

/// 真世界亚洲轮廓 + 弧线 + 飞机动画.
/// 采用 TimelineView(.animation) 驱动飞机沿 quadratic bezier 缓动循环；
/// 离屏后 SwiftUI 自动暂停，不耗 CPU。
private struct MapCanvas: View {
    let destinations: [MockDestination]
    let activeIndices: Set<Int>
    let rangeMultiplier: Double

    /// 用户原点：默认放在香港，作为 mock 本机位置。后期接 Local IP 后替换。
    private let originLat = 22.3
    private let originLon = 114.2

    var body: some View {
        ZStack {
            // 1) 地图底图：国家轮廓 + 字标
            Canvas { ctx, size in
                drawCountries(in: ctx, size: size)
                drawCountryLabels(in: ctx, size: size)
                drawGuides(in: ctx, size: size)
            }

            // 2) 弧线：每个目的地一条 quadratic bezier
            Canvas { ctx, size in
                let origin = AsiaProjection.project(lat: originLat, lon: originLon, in: size)
                for (i, dest) in destinations.enumerated() {
                    let p1 = AsiaProjection.project(lat: dest.lat, lon: dest.lon, in: size)
                    let control = controlPoint(from: origin, to: p1, fanIndex: i, total: destinations.count)
                    var path = Path()
                    path.move(to: origin)
                    path.addQuadCurve(to: p1, control: control)
                    let alpha: Double = activeIndices.contains(i) ? 0.85 : 0.45
                    ctx.stroke(
                        path,
                        with: .color(dest.color.opacity(alpha)),
                        style: StrokeStyle(lineWidth: 1.2, lineCap: .round, dash: [3, 3])
                    )
                }
            }
            .allowsHitTesting(false)

            // 3) 飞机动画 + 端点 dot + 城市标签
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { ctx in
                let now = ctx.date.timeIntervalSinceReferenceDate
                let phase = (now / 6.0).truncatingRemainder(dividingBy: 1.0) // 6s 一周期

                GeometryReader { geo in
                    let size = geo.size
                    let origin = AsiaProjection.project(lat: originLat, lon: originLon, in: size)

                    // 飞机沿弧线（直接用 Image overlay + .position + rotation
                    // 替代 Canvas symbols —— Canvas symbols 在嵌套 ForEach 下
                    // 触发 SwiftUI 内部 assertionFailure，会闪退）。
                    ForEach(Array(destinations.enumerated()), id: \.offset) { i, dest in
                        let p1 = AsiaProjection.project(lat: dest.lat, lon: dest.lon, in: size)
                        let control = controlPoint(from: origin, to: p1, fanIndex: i, total: destinations.count)
                        let active = activeIndices.contains(i)
                        let planeCount = active ? 3 : 2
                        let alpha: Double = active ? 1 : 0.55
                        ForEach(0..<planeCount, id: \.self) { k in
                            let phaseOffset = Double(k) / Double(planeCount)
                            let raw = phase + phaseOffset + Double(i) * 0.07
                            let t = raw - Foundation.floor(raw)
                            let pt = bezierPoint(t: t, p0: origin, c: control, p1: p1)
                            let tan = bezierTangent(t: t, p0: origin, c: control, p1: p1)
                            let angle = atan2(tan.dy, tan.dx)
                            Image(systemName: "airplane")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(dest.color.opacity(alpha))
                                .rotationEffect(.radians(angle))
                                .position(pt)
                        }
                    }

                    // 原点（绿色，pulse）
                    ChDot(color: .green, size: 9, pulse: true)
                        .position(origin)

                    // 目的地端点 + 城市标签
                    ForEach(Array(destinations.enumerated()), id: \.offset) { i, dest in
                        let p = AsiaProjection.project(lat: dest.lat, lon: dest.lon, in: size)
                        ChDot(color: dest.color, size: 7, pulse: activeIndices.contains(i))
                            .position(p)
                        Text(dest.name)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(ChungHwa.Palette.text)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(ChungHwa.Palette.bg.opacity(0.85))
                            )
                            .position(x: p.x + 28, y: p.y - 6)
                    }
                }
            }
            .allowsHitTesting(false)

            // 4) 图例（左下角）
            VStack {
                Spacer()
                HStack {
                    legend
                    Spacer()
                }
            }
            .padding(10)
            .allowsHitTesting(false)
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(ChungHwa.Palette.cardSoft.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(ChungHwa.Palette.line, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: drawing helpers

    /// Quadratic bezier control point — 把中点向上抬一段，让弧线像航线。
    /// 同时按 fan index 做小幅左右扇形偏移，避免多条同向曲线完全重叠。
    private func controlPoint(from p0: CGPoint, to p1: CGPoint, fanIndex i: Int, total: Int) -> CGPoint {
        let mid = CGPoint(x: (p0.x + p1.x) / 2, y: (p0.y + p1.y) / 2)
        let dx = p1.x - p0.x
        let dy = p1.y - p0.y
        let length = sqrt(dx * dx + dy * dy)
        // 让所有曲线向上拱（y 为负方向）；同时按法线方向做扇形小偏移避免重叠
        let nx = length > 0 ? -dy / length : 0.0
        let lift = max(60.0, length * 0.28)
        let fan = (Double(i) - Double(total - 1) / 2.0) * 8.0
        return CGPoint(
            x: mid.x + nx * fan,
            y: mid.y - lift
        )
    }

    private func bezierPoint(t: Double, p0: CGPoint, c: CGPoint, p1: CGPoint) -> CGPoint {
        let u = 1 - t
        let x = u * u * p0.x + 2 * u * t * c.x + t * t * p1.x
        let y = u * u * p0.y + 2 * u * t * c.y + t * t * p1.y
        return CGPoint(x: x, y: y)
    }

    private func bezierTangent(t: Double, p0: CGPoint, c: CGPoint, p1: CGPoint) -> CGVector {
        // d/dt = 2(1-t)(C-P0) + 2t(P1-C)
        let u = 1 - t
        let dx = 2 * u * (c.x - p0.x) + 2 * t * (p1.x - c.x)
        let dy = 2 * u * (c.y - p0.y) + 2 * t * (p1.y - c.y)
        return CGVector(dx: dx, dy: dy)
    }


    private var legend: some View {
        let groups = Dictionary(grouping: destinations, by: { $0.group })
            .sorted { $0.key < $1.key }
        return HStack(spacing: 10) {
            ForEach(groups, id: \.key) { entry in
                HStack(spacing: 5) {
                    Circle()
                        .fill(entry.value.first?.color ?? ChungHwa.Palette.brass)
                        .frame(width: 6, height: 6)
                    Text(entry.key)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(ChungHwa.Palette.dim)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(ChungHwa.Palette.bg.opacity(0.7))
                .strokeBorder(ChungHwa.Palette.line, lineWidth: 0.5)
        )
    }

    // MARK: countries

    private func drawCountries(in ctx: GraphicsContext, size: CGSize) {
        let fill = GraphicsContext.Shading.color(ChungHwa.Palette.fill.opacity(0.6))
        let stroke = GraphicsContext.Shading.color(ChungHwa.Palette.line)
        let style = StrokeStyle(lineWidth: 0.5, lineJoin: .round)
        for shape in CountryShapes.all {
            var path = Path()
            for (idx, ll) in shape.outline.enumerated() {
                let p = AsiaProjection.project(lat: ll.lat, lon: ll.lon, in: size)
                if idx == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            path.closeSubpath()
            ctx.fill(path, with: fill)
            ctx.stroke(path, with: stroke, style: style)
        }
    }

    private func drawCountryLabels(in ctx: GraphicsContext, size: CGSize) {
        for shape in CountryShapes.all {
            guard let (lat, lon) = shape.labelAnchor else { continue }
            let p = AsiaProjection.project(lat: lat, lon: lon, in: size)
            let text = Text(shape.label)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundColor(ChungHwa.Palette.faint)
                .tracking(1.6)
            ctx.draw(text, at: p, anchor: .center)
        }
    }

    private func drawGuides(in ctx: GraphicsContext, size: CGSize) {
        // 经线（每 15°）
        let lonStep = 15.0
        var lon = ceil(AsiaProjection.minLon / lonStep) * lonStep
        let stroke = GraphicsContext.Shading.color(ChungHwa.Palette.lineSoft)
        let style = StrokeStyle(lineWidth: 0.4, dash: [1, 4])
        while lon <= AsiaProjection.maxLon {
            let p0 = AsiaProjection.project(lat: AsiaProjection.maxLat, lon: lon, in: size)
            let p1 = AsiaProjection.project(lat: AsiaProjection.minLat, lon: lon, in: size)
            var p = Path()
            p.move(to: p0); p.addLine(to: p1)
            ctx.stroke(p, with: stroke, style: style)
            lon += lonStep
        }
        // 纬线（每 10°）
        var lat = ceil(AsiaProjection.minLat / 10.0) * 10.0
        while lat <= AsiaProjection.maxLat {
            let p0 = AsiaProjection.project(lat: lat, lon: AsiaProjection.minLon, in: size)
            let p1 = AsiaProjection.project(lat: lat, lon: AsiaProjection.maxLon, in: size)
            var p = Path()
            p.move(to: p0); p.addLine(to: p1)
            ctx.stroke(p, with: stroke, style: style)
            lat += 10.0
        }
    }
}

// MARK: - Mock destinations

private struct MockDestination {
    let name: String
    let lat: Double
    let lon: Double
    let group: String
    let color: Color

    /// 飞往各地的 mock 目的地，名字用中文，颜色按 group 分配。
    static let all: [MockDestination] = [
        MockDestination(name: "香港",   lat: 22.30, lon: 114.20, group: "直连",       color: ChungHwa.Palette.patina),
        MockDestination(name: "台北",   lat: 25.03, lon: 121.56, group: "亚太",       color: .pink),
        MockDestination(name: "东京",   lat: 35.68, lon: 139.69, group: "亚太",       color: .orange),
        MockDestination(name: "大阪",   lat: 34.69, lon: 135.50, group: "亚太",       color: ChungHwa.Palette.brass),
        MockDestination(name: "首尔",   lat: 37.57, lon: 126.98, group: "亚太",       color: ChungHwa.Palette.earth),
        MockDestination(name: "新加坡", lat:  1.35, lon: 103.82, group: "东南亚",     color: .teal),
        MockDestination(name: "曼谷",   lat: 13.75, lon: 100.50, group: "东南亚",     color: .cyan),
        MockDestination(name: "孟买",   lat: 19.08, lon:  72.88, group: "南亚",       color: .purple)
    ]

    /// FNV-1a 决定性哈希，让同一 host 总是落到同一目的地。
    static func bucket(for key: String) -> Int {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in key.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return Int(hash % UInt64(all.count))
    }
}

// MARK: - Country shapes

/// 手画的简化国家轮廓 —— 用一组 (lat, lon) 控制点逼近大轮廓。
/// 不追求拓扑精确，只求一眼看出「东亚 + 东南亚 + 南亚」轮廓。
private struct CountryOutline {
    let id: String
    let label: String              // 大写英文国名（图上小标签）
    let outline: [(lat: Double, lon: Double)]
    let labelAnchor: (lat: Double, lon: Double)?
}

private enum CountryShapes {
    static let all: [CountryOutline] = [
        china, mongolia, northKorea, southKorea, japan, taiwan,
        vietnam, laos, cambodia, thailand, myanmar, malaysia,
        indonesia, philippines, india, bangladesh, nepal, pakistan,
        sriLanka
    ]

    // 中国 —— 大致东南海岸 + 北部 + 西部轮廓
    static let china = CountryOutline(
        id: "CN",
        label: "CHINA",
        outline: [
            (22.0, 108.0), (21.5, 110.0), (22.7, 114.5), (23.5, 117.0),
            (26.0, 120.0), (29.5, 122.0), (32.0, 121.5), (35.0, 120.0),
            (37.5, 122.5), (39.5, 121.5), (40.5, 124.0), (42.0, 130.0),
            (45.0, 131.0), (48.0, 134.5), (50.0, 127.5), (49.5, 122.0),
            (49.0, 117.5), (47.5, 117.0), (46.5, 110.5), (44.0, 111.5),
            (42.0, 105.0), (41.0, 96.0), (43.0, 90.0), (45.0, 84.0),
            (43.5, 80.5), (40.5, 76.0), (38.0, 74.5), (35.0, 78.0),
            (33.5, 79.0), (29.5, 82.0), (28.0, 85.5), (28.0, 88.5),
            (27.5, 92.0), (29.0, 96.5), (28.0, 98.5), (25.5, 98.0),
            (23.5, 100.0), (22.0, 103.5), (22.0, 108.0)
        ],
        labelAnchor: (35.0, 102.0)
    )

    // 蒙古
    static let mongolia = CountryOutline(
        id: "MN",
        label: "MONGOLIA",
        outline: [
            (49.5, 89.0), (51.5, 98.0), (52.0, 107.0), (50.0, 115.0),
            (49.5, 117.5), (47.5, 117.0), (46.5, 110.5), (44.0, 111.5),
            (42.0, 105.0), (41.0, 96.0), (43.0, 90.0), (45.0, 89.0),
            (49.5, 89.0)
        ],
        labelAnchor: (47.0, 103.0)
    )

    // 朝鲜
    static let northKorea = CountryOutline(
        id: "KP",
        label: "DPRK",
        outline: [
            (38.0, 124.6), (39.0, 124.5), (40.0, 124.5), (40.5, 126.5),
            (42.0, 130.5), (42.5, 130.7), (41.5, 129.5), (40.5, 129.5),
            (39.5, 128.0), (38.6, 128.4), (38.0, 126.7), (38.0, 124.6)
        ],
        labelAnchor: (40.0, 127.0)
    )

    // 韩国
    static let southKorea = CountryOutline(
        id: "KR",
        label: "S.KOREA",
        outline: [
            (38.0, 126.7), (38.6, 128.4), (37.5, 129.5), (35.5, 129.5),
            (34.5, 128.5), (34.3, 126.5), (35.5, 126.4), (37.0, 126.6),
            (38.0, 126.7)
        ],
        labelAnchor: (36.5, 127.8)
    )

    // 日本（本州 + 北海道 + 九州 简化）
    static let japan = CountryOutline(
        id: "JP",
        label: "JAPAN",
        outline: [
            (31.5, 130.5), (33.5, 132.5), (34.5, 135.0), (35.0, 137.0),
            (35.7, 140.0), (37.0, 141.0), (38.5, 141.5), (40.0, 141.7),
            (41.5, 141.5), (43.0, 144.5), (44.0, 145.0), (43.5, 141.0),
            (42.0, 140.5), (41.0, 140.0), (39.5, 140.0), (38.0, 139.5),
            (36.5, 138.0), (35.5, 135.5), (34.0, 132.0), (33.0, 130.0),
            (31.5, 130.5)
        ],
        labelAnchor: (37.0, 138.0)
    )

    // 台湾
    static let taiwan = CountryOutline(
        id: "TW",
        label: "TAIWAN",
        outline: [
            (22.0, 120.5), (23.5, 120.2), (25.3, 121.5), (25.0, 121.9),
            (23.5, 121.6), (22.5, 121.0), (22.0, 120.5)
        ],
        labelAnchor: (23.7, 121.0)
    )

    // 越南
    static let vietnam = CountryOutline(
        id: "VN",
        label: "VIETNAM",
        outline: [
            (8.5, 104.8), (10.0, 105.0), (12.0, 109.0), (15.0, 109.3),
            (18.0, 106.5), (20.5, 106.0), (22.5, 104.0), (22.0, 103.0),
            (20.5, 102.5), (18.5, 105.0), (16.5, 107.0), (14.0, 108.0),
            (11.5, 107.5), (10.0, 104.5), (8.5, 104.8)
        ],
        labelAnchor: (16.0, 107.5)
    )

    // 老挝
    static let laos = CountryOutline(
        id: "LA",
        label: "LAOS",
        outline: [
            (14.5, 105.5), (15.5, 107.5), (18.0, 105.5), (20.0, 102.5),
            (22.0, 101.5), (21.0, 100.5), (19.5, 101.0), (17.5, 101.5),
            (15.5, 104.5), (14.5, 105.5)
        ],
        labelAnchor: (18.5, 103.5)
    )

    // 柬埔寨
    static let cambodia = CountryOutline(
        id: "KH",
        label: "CAMBODIA",
        outline: [
            (10.5, 103.5), (10.5, 105.0), (12.0, 106.5), (14.5, 107.5),
            (14.0, 105.5), (13.5, 103.5), (11.5, 103.0), (10.5, 103.5)
        ],
        labelAnchor: (12.5, 105.0)
    )

    // 泰国
    static let thailand = CountryOutline(
        id: "TH",
        label: "THAILAND",
        outline: [
            (6.5, 100.0), (7.5, 100.5), (10.0, 99.5), (12.5, 100.0),
            (13.5, 101.5), (14.5, 105.5), (15.5, 105.5), (17.5, 104.0),
            (19.5, 101.0), (20.0, 100.5), (19.0, 99.0), (17.0, 98.0),
            (14.5, 98.5), (12.0, 99.0), (10.0, 98.5), (8.0, 99.0),
            (6.5, 100.0)
        ],
        labelAnchor: (15.5, 101.5)
    )

    // 缅甸
    static let myanmar = CountryOutline(
        id: "MM",
        label: "MYANMAR",
        outline: [
            (10.0, 98.5), (12.0, 99.0), (14.5, 98.5), (17.0, 98.0),
            (19.0, 99.0), (21.0, 100.5), (24.0, 98.5), (27.5, 97.5),
            (28.0, 96.0), (26.5, 95.0), (24.5, 94.0), (22.0, 92.5),
            (20.0, 92.5), (17.5, 94.5), (16.0, 95.0), (13.0, 97.5),
            (10.0, 98.5)
        ],
        labelAnchor: (21.0, 96.5)
    )

    // 马来西亚（半岛 + 沙巴/砂拉越简化）
    static let malaysia = CountryOutline(
        id: "MY",
        label: "MALAYSIA",
        outline: [
            (1.3, 103.5), (2.0, 102.5), (3.5, 101.0), (5.5, 100.5),
            (6.5, 100.5), (6.5, 101.5), (5.0, 102.5), (3.5, 103.5),
            (2.5, 104.0), (1.3, 103.5)
        ],
        labelAnchor: (4.0, 102.0)
    )

    // 印尼（苏门答腊 + 爪哇简化轮廓）
    static let indonesia = CountryOutline(
        id: "ID",
        label: "INDONESIA",
        outline: [
            (5.5, 95.5), (3.5, 99.0), (0.5, 102.0), (-2.5, 104.0),
            (-5.5, 105.5), (-7.0, 108.0), (-8.5, 113.0), (-8.0, 116.0),
            (-8.5, 119.0), (-9.0, 124.0), (-7.5, 128.0), (-3.0, 128.0),
            (-1.0, 127.0), (1.5, 127.0), (3.5, 124.5), (1.5, 110.0),
            (1.0, 104.0), (3.0, 100.0), (5.5, 95.5)
        ],
        labelAnchor: (-3.0, 117.0)
    )

    // 菲律宾（吕宋 + 棉兰老简化）
    static let philippines = CountryOutline(
        id: "PH",
        label: "PHILIPPINES",
        outline: [
            (5.5, 121.0), (7.0, 122.0), (9.5, 124.5), (12.0, 124.5),
            (14.5, 121.5), (17.5, 121.0), (18.5, 122.0), (16.5, 124.0),
            (14.0, 125.0), (11.0, 126.5), (8.0, 126.5), (5.5, 125.0),
            (5.5, 121.0)
        ],
        labelAnchor: (13.0, 123.0)
    )

    // 印度
    static let india = CountryOutline(
        id: "IN",
        label: "INDIA",
        outline: [
            (8.0, 77.5), (9.5, 78.0), (12.0, 80.5), (15.0, 80.5),
            (19.0, 84.5), (21.5, 86.5), (22.0, 88.5), (24.0, 88.5),
            (26.5, 89.5), (27.5, 88.0), (28.5, 84.5), (30.0, 81.0),
            (32.5, 78.5), (34.0, 76.0), (35.5, 76.5), (33.0, 74.5),
            (31.5, 73.0), (28.0, 70.5), (24.0, 68.5), (22.0, 68.7),
            (20.5, 70.0), (17.0, 73.0), (13.0, 74.5), (10.0, 75.5),
            (8.5, 76.5), (8.0, 77.5)
        ],
        labelAnchor: (22.0, 79.0)
    )

    // 孟加拉国
    static let bangladesh = CountryOutline(
        id: "BD",
        label: "BANGLADESH",
        outline: [
            (21.5, 89.0), (22.0, 91.5), (24.0, 92.5), (26.0, 91.5),
            (26.5, 89.5), (24.0, 88.5), (22.0, 88.5), (21.5, 89.0)
        ],
        labelAnchor: (24.0, 90.5)
    )

    // 尼泊尔
    static let nepal = CountryOutline(
        id: "NP",
        label: "NEPAL",
        outline: [
            (26.5, 80.5), (27.0, 84.0), (27.5, 88.0), (28.5, 88.0),
            (30.0, 81.0), (28.5, 80.5), (26.5, 80.5)
        ],
        labelAnchor: (28.0, 84.0)
    )

    // 巴基斯坦
    static let pakistan = CountryOutline(
        id: "PK",
        label: "PAKISTAN",
        outline: [
            (24.0, 68.5), (25.0, 67.0), (28.0, 66.0), (30.0, 62.5),
            (32.0, 62.0), (34.5, 71.0), (36.5, 73.5), (35.5, 76.5),
            (34.0, 76.0), (31.5, 73.0), (28.0, 70.5), (24.0, 68.5)
        ],
        labelAnchor: (30.5, 70.5)
    )

    // 斯里兰卡
    static let sriLanka = CountryOutline(
        id: "LK",
        label: "SRI LANKA",
        outline: [
            (6.0, 80.0), (6.5, 81.5), (8.5, 81.5), (9.5, 80.5),
            (8.5, 79.7), (6.5, 79.8), (6.0, 80.0)
        ],
        labelAnchor: (7.5, 80.8)
    )
}
