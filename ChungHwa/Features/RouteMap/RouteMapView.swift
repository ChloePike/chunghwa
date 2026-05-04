import SwiftUI

/// Bone & Brass on Patina Route Map screen.
///
/// Geographic visualisation of where active connections are heading. We don't
/// have IP-to-geo lookup yet (that lands in M5+), so the dots and arcs are
/// structural-but-mocked: every unique destination host hashes deterministically
/// to one of eight mock regions. The right-hand side panel uses real
/// connection counts derived from the same bucketing.
struct RouteMapView: View {
    @Environment(KernelController.self) private var kernel
    @Environment(ConnectionsStore.self) private var connectionsStore

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
        VStack(alignment: .leading, spacing: 2) {
            Text("Route Map")
                .font(ChungHwa.Typography.serif(22, weight: .medium))
                .foregroundStyle(ChungHwa.Palette.text)
                .tracking(-0.4)
            Text("\(connectionsStore.connections.count) active connections")
                .font(.system(size: 11.5))
                .foregroundStyle(ChungHwa.Palette.dim)
                .monospacedDigit()
        }
    }

    // MARK: - Bucketing

    /// Bucket every unique host into one of the eight mock regions and tally
    /// the connection count. Same host → same region every time, because we
    /// hash on the host string.
    private var regionBuckets: [(region: MockRegion, count: Int)] {
        var counts: [Int: Int] = [:]
        for conn in connectionsStore.connections {
            let key = conn.metadata.host?.isEmpty == false
                ? conn.metadata.host!
                : (conn.metadata.destinationIP ?? conn.id)
            let idx = MockRegion.bucket(for: key)
            counts[idx, default: 0] += 1
        }
        return counts
            .map { (region: MockRegion.all[$0.key], count: $0.value) }
            .sorted { $0.count > $1.count }
    }

    // MARK: - Map card

    private var mapCard: some View {
        ChCard(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                MapCanvas(active: regionBuckets.map { $0.region })
                    .frame(height: 320)
                    .frame(maxWidth: .infinity)

                Text("Mock geo — IP→region lookup will land in M5+")
                    .font(.system(size: 10))
                    .foregroundStyle(ChungHwa.Palette.faint)
            }
        }
    }

    // MARK: - Region list

    private var regionList: some View {
        ChCardWithHeader("Active by Region", systemImage: "globe") {
            VStack(spacing: 0) {
                if regionBuckets.isEmpty {
                    HStack {
                        Spacer()
                        Text("No active connections")
                            .font(.system(size: 11.5))
                            .foregroundStyle(ChungHwa.Palette.dim)
                        Spacer()
                    }
                    .padding(.vertical, 18)
                } else {
                    ForEach(Array(regionBuckets.enumerated()), id: \.offset) { idx, entry in
                        if idx > 0 {
                            Rectangle()
                                .fill(ChungHwa.Palette.lineSoft)
                                .frame(height: 0.5)
                        }
                        RegionRow(region: entry.region, count: entry.count)
                    }
                }
            }
        }
    }
}

// MARK: - Region row

private struct RegionRow: View {
    let region: MockRegion
    let count: Int

    var body: some View {
        HStack(spacing: 10) {
            ChDot(color: ChungHwa.Palette.brass, size: 7, pulse: false)
                .frame(width: 12, height: 12)
            Text(region.name)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(ChungHwa.Palette.text)
            Spacer(minLength: 0)
            Text("\(count)")
                .font(ChungHwa.Typography.mono(11.5))
                .foregroundStyle(ChungHwa.Palette.dim)
                .monospacedDigit()
        }
        .padding(.vertical, 9)
    }
}

// MARK: - Map canvas

/// Stylised abstract dot-lattice "map" with brass destination dots and arcs
/// from the origin (Bay Area-ish) to each active region. Pure Canvas so it
/// scales cheaply at any size.
private struct MapCanvas: View {
    let active: [MockRegion]

    /// Bay Area-ish, in normalised (0..1) coords.
    private let originNorm = CGPoint(x: 0.20, y: 0.45)

    var body: some View {
        ZStack {
            // ── Background lattice (the "half-formed map") ───────────────
            Canvas { ctx, size in
                let cols = 16
                let rows = 8
                let dotSize: CGFloat = 1.6
                let lineColor = ChungHwa.Palette.line
                for r in 0..<rows {
                    for c in 0..<cols {
                        let x = (CGFloat(c) + 0.5) / CGFloat(cols) * size.width
                        let y = (CGFloat(r) + 0.5) / CGFloat(rows) * size.height
                        let rect = CGRect(
                            x: x - dotSize / 2,
                            y: y - dotSize / 2,
                            width: dotSize,
                            height: dotSize
                        )
                        ctx.fill(Path(ellipseIn: rect), with: .color(lineColor))
                    }
                }

                // Subtle equator + meridian guides for "world map" suggestion.
                let guide = ChungHwa.Palette.line
                var equator = Path()
                equator.move(to: CGPoint(x: 0, y: size.height * 0.5))
                equator.addLine(to: CGPoint(x: size.width, y: size.height * 0.5))
                ctx.stroke(
                    equator,
                    with: .color(guide.opacity(0.6)),
                    style: StrokeStyle(lineWidth: 0.5, dash: [2, 4])
                )

                var meridian = Path()
                meridian.move(to: CGPoint(x: size.width * 0.5, y: 0))
                meridian.addLine(to: CGPoint(x: size.width * 0.5, y: size.height))
                ctx.stroke(
                    meridian,
                    with: .color(guide.opacity(0.6)),
                    style: StrokeStyle(lineWidth: 0.5, dash: [2, 4])
                )
            }

            // ── Arcs from origin to each active region ───────────────────
            Canvas { ctx, size in
                let arcColor = ChungHwa.Palette.brass.opacity(0.4)
                let origin = CGPoint(
                    x: originNorm.x * size.width,
                    y: originNorm.y * size.height
                )
                for region in active {
                    let dest = CGPoint(
                        x: region.coords.x * size.width,
                        y: region.coords.y * size.height
                    )
                    var path = Path()
                    path.move(to: origin)
                    let mid = CGPoint(
                        x: (origin.x + dest.x) / 2,
                        y: (origin.y + dest.y) / 2
                    )
                    let lift = max(40, abs(dest.x - origin.x) * 0.25)
                    let control = CGPoint(x: mid.x, y: mid.y - lift)
                    path.addQuadCurve(to: dest, control: control)
                    ctx.stroke(
                        path,
                        with: .color(arcColor),
                        style: StrokeStyle(lineWidth: 1.0, lineCap: .round)
                    )
                }
            }

            // ── Origin + destination dots (overlaid as real ChDots so the
            //    pulse animation works) ──────────────────────────────────
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height

                // Origin dot — patina, no pulse, slightly bigger ring.
                ChDot(color: ChungHwa.Palette.patina, size: 7, pulse: false)
                    .position(x: originNorm.x * w, y: originNorm.y * h)

                ForEach(active, id: \.name) { region in
                    ChDot(color: ChungHwa.Palette.brass, size: 7, pulse: true)
                        .position(x: region.coords.x * w, y: region.coords.y * h)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(ChungHwa.Palette.patina.opacity(0.15))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(ChungHwa.Palette.line, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Mock regions

/// Eight hand-picked destinations on a normalised 0..1 equirectangular grid.
/// These coordinates approximate each city's longitude/latitude mapped onto
/// the canvas — they're not surveyed, but close enough to read "world map".
private struct MockRegion {
    let name: String
    let coords: CGPoint  // normalised 0..1 (x = longitude, y = latitude)

    static let all: [MockRegion] = [
        MockRegion(name: "Tokyo",         coords: CGPoint(x: 0.86, y: 0.40)),
        MockRegion(name: "Singapore",     coords: CGPoint(x: 0.78, y: 0.58)),
        MockRegion(name: "San Francisco", coords: CGPoint(x: 0.18, y: 0.43)),
        MockRegion(name: "New York",      coords: CGPoint(x: 0.30, y: 0.42)),
        MockRegion(name: "Frankfurt",     coords: CGPoint(x: 0.52, y: 0.36)),
        MockRegion(name: "London",        coords: CGPoint(x: 0.49, y: 0.34)),
        MockRegion(name: "São Paulo",     coords: CGPoint(x: 0.36, y: 0.68)),
        MockRegion(name: "Sydney",        coords: CGPoint(x: 0.92, y: 0.78))
    ]

    /// Stable bucket index for an arbitrary key, so the same host always
    /// renders to the same region between snapshots.
    static func bucket(for key: String) -> Int {
        // `hashValue` is randomised across launches in Swift, so use a small
        // FNV-1a over the bytes for determinism within a single run *and*
        // across runs — same key, same dot, every time.
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in key.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return Int(hash % UInt64(all.count))
    }
}
