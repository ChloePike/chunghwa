import SwiftUI

/// Bone & Brass on Patina reskin of the Connections screen.
///
/// Mirrors `ConnectionsScreen` in `design/src/app.jsx` (≈L1007–L1085): a single
/// `ChCard` with a fixed grid header and a scrolling list of rows. The toolbar
/// above the card carries a "{active} · {total}" counter on the left and
/// pause/clear icon buttons on the right.
///
/// Selecting a row reveals a 40%-wide details inspector to the right of the
/// list. The inspector lets the user inspect routing chain, source/destination
/// metadata and live stats, and close the connection. Selection persists even
/// if the underlying connection ends — we surface a "Connection ended" badge
/// and let the user dismiss the panel manually.
struct ConnectionsView: View {
    @Environment(KernelController.self) private var kernel
    @Environment(ConnectionsStore.self) private var store
    @Environment(AnonymousMode.self) private var anon
    @Environment(GeoIPStore.self) private var geo

    @State private var paused: Bool = false
    /// Snapshot frozen at the moment the user pressed pause. Cleared when they
    /// resume so live updates flow through again.
    @State private var frozen: [MihomoConnection]? = nil

    /// Currently selected row's id. When non-nil the inspector pane is shown.
    @State private var selectedID: MihomoConnection.ID? = nil
    /// Sticky last-known snapshot of the selected connection so the inspector
    /// can keep showing details after the kernel drops it from `connections`.
    @State private var lastSelectedSnapshot: MihomoConnection? = nil

    /// Free-text filter applied across host / process / chain / rule. Bound to
    /// the toolbar's TextField; can be focused via the global cmd-k shortcut.
    @State private var query: String = ""
    /// Debounced mirror of `query`. The TextField updates `query` immediately
    /// for responsive typing, but the (potentially N×M) filter predicate only
    /// recomputes ~150ms after the user pauses — keeping a 500-row list snappy.
    @State private var debouncedQuery: String = ""
    @FocusState private var filterFocused: Bool

    /// Whether the row list is the current first responder. When true, arrow
    /// keys move the selection and a brass focus ring appears around the card.
    @FocusState private var listFocused: Bool

    var body: some View {
        VStack(spacing: 10) {
            toolbar
            cardArea
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(ChungHwa.Palette.bg)
        .onChange(of: liveSelectedKey) { _, _ in
            // Capture the latest live copy of the selected row so the
            // inspector keeps showing up-to-date stats AND has something to
            // fall back to if the kernel later drops the connection.
            if let id = selectedID,
               let live = store.connections.first(where: { $0.id == id }) {
                lastSelectedSnapshot = live
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .chungHwaFocusFilter)) { _ in
            filterFocused = true
        }
        // Debounce filter typing: only re-run the predicate ~150ms after the
        // last keystroke. Cancellation on `query` change is automatic via
        // `.task(id:)` — SwiftUI tears the previous Task down before starting
        // the next one.
        .task(id: query) {
            try? await Task.sleep(nanoseconds: 150_000_000)
            if !Task.isCancelled {
                debouncedQuery = query
            }
        }
        // Feed currently-visible destination IPs to the GeoIP store. The store
        // de-dupes against its cache, so this is cheap to call on every
        // snapshot tick. Re-keys on connection count — granular enough to
        // pick up newly-opened connections without thrashing on byte-counter
        // updates.
        .task(id: store.connections.count) {
            let ips = Set(store.connections.compactMap { $0.metadata.destinationIP })
            geo.resolve(ips: ips)
        }
    }

    /// String fingerprint used as `onChange` trigger so we don't require
    /// `MihomoConnection: Equatable`. Encodes id, byte counters and chain so
    /// any meaningful change re-snapshots `lastSelectedSnapshot`.
    private var liveSelectedKey: String {
        guard let id = selectedID,
              let live = store.connections.first(where: { $0.id == id })
        else { return "" }
        return "\(live.id)|\(live.upload)|\(live.download)|\(live.chains.joined(separator: ">"))"
    }

    // MARK: - Data

    /// Rows the UI is currently rendering — the live store (or frozen
    /// snapshot if paused), filtered by the toolbar's free-text query.
    ///
    /// We deliberately hand `store.connections` straight through (no extra
    /// copy) when not paused, since the array is already a value-typed
    /// snapshot held by the store. The `q` string is lowercased once outside
    /// the predicate closure rather than once per row.
    private var rows: [MihomoConnection] {
        let base = frozen ?? store.connections
        let q = debouncedQuery
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !q.isEmpty else { return base }
        return base.filter { conn in
            if conn.destination.lowercased().contains(q) { return true }
            if let host = conn.metadata.host, host.lowercased().contains(q) { return true }
            if let ip = conn.metadata.destinationIP, ip.lowercased().contains(q) { return true }
            if let proc = conn.metadata.process, proc.lowercased().contains(q) { return true }
            if conn.rule.lowercased().contains(q) { return true }
            if conn.chains.contains(where: { $0.lowercased().contains(q) }) { return true }
            return false
        }
    }

    /// We don't currently track per-connection liveness from the kernel, so
    /// every row is treated as "live" (pulsing green dot) per the spec.
    private var activeCount: Int { rows.count }

    /// Connection driving the inspector. Falls back to the last seen snapshot
    /// when the kernel has dropped the connection so the panel remains stable.
    private var selectedConnection: MihomoConnection? {
        guard let id = selectedID else { return nil }
        if let live = store.connections.first(where: { $0.id == id }) {
            return live
        }
        return lastSelectedSnapshot
    }

    private var selectedIsEnded: Bool {
        guard let id = selectedID else { return false }
        return !store.connections.contains(where: { $0.id == id })
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(ChungHwa.Palette.faint)
                TextField("过滤连接", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(ChungHwa.Palette.text)
                    .focused($filterFocused)
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(ChungHwa.Palette.faint)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(ChungHwa.Palette.fill)
                    .strokeBorder(ChungHwa.Palette.line, lineWidth: 0.5)
            )

            Text("\(activeCount) 活跃 · \(rows.count) 总数")
                .font(.system(size: 11))
                .foregroundStyle(ChungHwa.Palette.dim)
                .monospacedDigit()

            Spacer(minLength: 0)

            iconButton(systemName: paused ? "play.fill" : "pause.fill",
                       size: paused ? 11 : 12) {
                togglePause()
            }
            .disabled(kernel.apiClient == nil)

            iconButton(systemName: "trash", size: 12) {
                Task { await store.closeAll(api: kernel.apiClient) }
            }
            .disabled(rows.isEmpty || kernel.apiClient == nil)
        }
    }

    private func togglePause() {
        if paused {
            paused = false
            frozen = nil
        } else {
            paused = true
            frozen = store.connections
        }
    }

    // MARK: - Card / table + inspector split

    @ViewBuilder
    private var cardArea: some View {
        // 60 / 40 horizontal split when a row is selected. We use a
        // GeometryReader because SwiftUI's flexible layout otherwise tends
        // toward 50/50 once both children have `maxWidth: .infinity`.
        GeometryReader { geo in
            let gap: CGFloat = 10
            let showInspector = selectedID != nil && selectedConnection != nil
            let inspectorW = showInspector
                ? max(0, (geo.size.width - gap) * 0.40)
                : 0
            let cardW = showInspector
                ? max(0, geo.size.width - inspectorW - gap)
                : geo.size.width

            HStack(spacing: gap) {
                card
                    .frame(width: cardW)

                if showInspector, let conn = selectedConnection {
                    ConnectionInspector(
                        connection: conn,
                        ended: selectedIsEnded,
                        anon: anon.enabled,
                        closeConnection: {
                            let id = conn.id
                            Task { await store.close(id: id, api: kernel.apiClient) }
                            clearSelection()
                        },
                        dismiss: { clearSelection() }
                    )
                    .frame(width: inspectorW)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    @ViewBuilder
    private var card: some View {
        ChCard(padding: 0) {
            if kernel.apiClient == nil {
                emptyState(title: "内核未运行",
                           system: "powerplug",
                           subtitle: "mihomo 启动后连接会显示在这里。")
            } else {
                // Compute column widths ONCE from the card's frame and feed
                // them into header + every row. Replaces a per-row
                // GeometryReader (one per visible row × every store tick)
                // with a single layout pass at the card level.
                GeometryReader { geo in
                    let widths = ConnectionsColumnWidths(totalWidth: geo.size.width)
                    VStack(spacing: 0) {
                        headerRow(widths: widths)
                        if rows.isEmpty {
                            emptyState(title: "无活跃连接",
                                       system: "link.circle",
                                       subtitle: "访问网站后会显示被代理的连接。")
                        } else {
                            rowList(widths: widths)
                        }
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func headerRow(widths: ConnectionsColumnWidths) -> some View {
        ConnectionsGridRow(
            widths:  widths,
            region:  { headerCell("地区", alignment: .center) },
            host:    { headerCell("主机", alignment: .leading) },
            process: { headerCell("进程", alignment: .leading) },
            down:    { headerCell("下载", alignment: .trailing) },
            up:      { headerCell("上传", alignment: .trailing) },
            rule:    { headerCell("规则", alignment: .leading) }
        )
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(ChungHwa.Palette.line)
                .frame(height: 0.5)
        }
    }

    private func headerCell(_ text: String, alignment: Alignment) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.4)
            .textCase(.uppercase)
            .foregroundStyle(ChungHwa.Palette.faint)
            .frame(maxWidth: .infinity, alignment: alignment)
    }

    private func rowList(widths: ConnectionsColumnWidths) -> some View {
        // Cache the visible array once per body rather than re-reading the
        // computed property six times below. With LazyVStack iterating, the
        // ForEach only materialises the on-screen window; the cached array is
        // just a thin Swift COW reference.
        let visible = rows
        let anonEnabled = anon.enabled
        let currentSelection = selectedID
        let liveRates = store.rates

        return ScrollView(.vertical, showsIndicators: true) {
            LazyVStack(spacing: 0) {
                ForEach(visible) { row in
                    ConnectionRow(
                        row: row,
                        widths: widths,
                        anonEnabled: anonEnabled,
                        isSelected: row.id == currentSelection,
                        country: geo.country(for: row.metadata.destinationIP ?? ""),
                        rate: liveRates[row.id] ?? .zero,
                        onTap: {
                            select(row)
                            listFocused = true
                        },
                        contextMenu: {
                            AnyView(rowContextMenu(for: [row.id]))
                        }
                    )
                    .equatable()
                }
            }
        }
        .focusable()
        .focused($listFocused)
        .focusEffectDisabled()
        .onKeyPress(.upArrow) {
            moveSelection(-1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            moveSelection(+1)
            return .handled
        }
        .onKeyPress(.return) {
            // Selection already drives the inspector; if nothing is selected
            // (e.g. focus came in from elsewhere), pick the first row so
            // Return reliably "opens" something.
            if selectedID == nil, let first = rows.first {
                select(first)
            }
            return .handled
        }
        .onKeyPress(.escape) {
            clearSelection()
            return .handled
        }
        .overlay {
            // Subtle brass focus ring layered over the existing ChCard border
            // — only visible while the list owns the keyboard.
            if listFocused {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(ChungHwa.Palette.brass.opacity(0.55),
                                  lineWidth: 0.5)
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: - Right-click menu

    /// Shared context-menu content used both for individual rows (right-click
    /// without selecting) and for table-wide selection-based right-clicks.
    /// When `ids` covers multiple rows the copy actions concatenate values
    /// with newlines, so the user gets a useful clipboard either way.
    @ViewBuilder
    private func rowContextMenu(for ids: [MihomoConnection.ID]) -> some View {
        let conns = ids.compactMap { id in
            rows.first(where: { $0.id == id })
        }

        Button {
            let value = conns
                .map { $0.metadata.host ?? $0.metadata.destinationIP ?? "—" }
                .joined(separator: "\n")
            Self.copy(value)
        } label: {
            Label("复制主机", systemImage: "globe")
        }
        .disabled(conns.isEmpty)

        Button {
            let value = conns
                .map { $0.metadata.destinationIP ?? "—" }
                .joined(separator: "\n")
            Self.copy(value)
        } label: {
            Label("复制 IP", systemImage: "number")
        }
        .disabled(conns.isEmpty)

        Button {
            let value = conns.map { $0.destination }.joined(separator: "\n")
            Self.copy(value)
        } label: {
            Label("复制 主机:端口", systemImage: "doc.on.clipboard")
        }
        .disabled(conns.isEmpty)

        Button {
            let value = conns.map { $0.chainPath }.joined(separator: "\n")
            Self.copy(value)
        } label: {
            Label("复制链路", systemImage: "point.3.connected.trianglepath.dotted")
        }
        .disabled(conns.isEmpty)

        Button {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let pieces: [String] = conns.compactMap { conn in
                guard let data = try? encoder.encode(conn) else { return nil }
                return String(data: data, encoding: .utf8)
            }
            Self.copy(pieces.joined(separator: "\n"))
        } label: {
            Label("复制 JSON", systemImage: "curlybraces")
        }
        .disabled(conns.isEmpty)

        Divider()

        Button(role: .destructive) {
            let api = kernel.apiClient
            for id in ids {
                Task { await store.close(id: id, api: api) }
            }
        } label: {
            Label("关闭连接", systemImage: "xmark.circle")
        }
        .disabled(ids.isEmpty)
    }

    // MARK: - Selection helpers

    private func select(_ row: MihomoConnection) {
        withAnimation(.snappy(duration: 0.18)) {
            selectedID = row.id
            lastSelectedSnapshot = row
        }
    }

    private func clearSelection() {
        withAnimation(.snappy(duration: 0.18)) {
            selectedID = nil
            lastSelectedSnapshot = nil
        }
    }

    /// Move the current selection by `delta` rows within the post-filter
    /// `rows` array. Bootstraps to the first/last row when nothing is selected
    /// yet, and clamps at the edges so arrow-mashing doesn't wrap around.
    private func moveSelection(_ delta: Int) {
        let visible = rows
        guard !visible.isEmpty else { return }

        let newRow: MihomoConnection
        if let id = selectedID,
           let idx = visible.firstIndex(where: { $0.id == id }) {
            let next = max(0, min(visible.count - 1, idx + delta))
            // Already at the edge — nothing to do.
            if next == idx { return }
            newRow = visible[next]
        } else {
            newRow = delta > 0 ? visible.first! : visible.last!
        }

        withAnimation(.snappy(duration: 0.15)) {
            selectedID = newRow.id
            lastSelectedSnapshot = newRow
        }
    }

    // MARK: - Empty state

    private func emptyState(title: String, system: String, subtitle: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: system)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(ChungHwa.Palette.faint)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ChungHwa.Palette.text)
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(ChungHwa.Palette.dim)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .padding(.horizontal, 24)
    }

    // MARK: - Icon button (matches design's btnGhost 28×28)

    private func iconButton(systemName: String,
                            size: CGFloat,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(ChungHwa.Palette.dim)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(ChungHwa.Palette.fill)
                        .strokeBorder(ChungHwa.Palette.line, lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Pasteboard

    /// Replace the system pasteboard with `s`. Used by the right-click menu's
    /// "Copy …" actions.
    private static func copy(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }
}

// MARK: - Row

/// One row of the connections list. Marked `Equatable` so a parent
/// `.equatable()` modifier can short-circuit re-rendering when nothing the row
/// actually displays has changed — the connection list ticks at ~1Hz with a
/// hundred+ rows, so skipping equal rows materially cuts the per-tick cost.
///
/// We compare only the fields that visibly change once a connection exists:
/// id (cheap stability check), upload/download counters, the selection flag,
/// and anon mode. `metadata`, `rule`, `chains` etc. are immutable for the life
/// of a connection so we don't bother diffing them.
private struct ConnectionRow: View, Equatable {
    let row: MihomoConnection
    let widths: ConnectionsColumnWidths
    let anonEnabled: Bool
    let isSelected: Bool
    /// ISO 3166-1 alpha-2 code (e.g. "JP", "US") or the sentinel "LAN" for
    /// private addresses. nil while the lookup is still in flight.
    let country: String?
    /// Live bytes/second derived by `ConnectionsStore` from successive
    /// snapshots. `.zero` for a connection's first sighting.
    let rate: ConnectionRate
    let onTap: () -> Void
    let contextMenu: () -> AnyView

    static func == (lhs: ConnectionRow, rhs: ConnectionRow) -> Bool {
        lhs.row.id == rhs.row.id
            && lhs.row.upload == rhs.row.upload
            && lhs.row.download == rhs.row.download
            && lhs.isSelected == rhs.isSelected
            && lhs.anonEnabled == rhs.anonEnabled
            && lhs.country == rhs.country
            && lhs.rate == rhs.rate
            && lhs.widths == rhs.widths
    }

    var body: some View {
        ConnectionsGridRow(
            widths: widths,
            region: {
                Text(regionGlyph)
                    .font(.system(size: 13))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .help(country ?? "")
            },
            host: {
                Text(hostText)
                    .font(ChungHwa.Typography.mono(11))
                    .foregroundStyle(ChungHwa.Palette.text)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .help(hostText)
                    .anonMask(anonEnabled)
            },
            process: {
                Text(processText)
                    .font(.system(size: 11.5))
                    .foregroundStyle(ChungHwa.Palette.dim)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .anonMask(anonEnabled)
            },
            down: {
                rateCell(bps: rate.down, total: row.download)
            },
            up: {
                rateCell(bps: rate.up, total: row.upload)
            },
            rule: {
                Text(ruleText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(row.rule == "DIRECT"
                                     ? ChungHwa.Palette.dim
                                     : ChungHwa.Palette.patina)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .help(row.rule)
            }
        )
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(
            isSelected
            ? ChungHwa.Palette.brass.opacity(0.10)
            : Color.clear
        )
        .overlay(alignment: .top) {
            Rectangle()
                .fill(ChungHwa.Palette.lineSoft)
                .frame(height: 0.5)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .contextMenu { contextMenu() }
    }

    private var hostText: String { row.destination }
    private var processText: String { row.metadata.process ?? "—" }

    /// Display string for the rule column. mihomo emits a few wordy
    /// constants (e.g. "DOMAIN-SUFFIX", "DOMAIN-KEYWORD") that don't fit
    /// the 110pt column without truncation; abbreviate the ones that
    /// have a conventional short form so the column stays glanceable.
    private var ruleText: String {
        switch row.rule {
        case "DOMAIN-SUFFIX":  return "SUFFIX"
        case "DOMAIN-KEYWORD": return "KEYWORD"
        case "RuleSet":        return "RULESET"
        case "":               return "—"
        default:               return row.rule
        }
    }

    /// Two-line trailing-aligned cell: live rate on top (bytes/sec),
    /// cumulative bytes underneath. The rate is what the user wants for
    /// live monitoring; the total is preserved as secondary context.
    /// "0 B/s" renders as a subdued "·" so a quiet connection doesn't
    /// flood the column with zeros.
    @ViewBuilder
    private func rateCell(bps: Int, total: Int) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(bps > 0 ? ChFormat.rate(bps) : "·")
                .font(.system(size: 11.5))
                .monospacedDigit()
                .foregroundStyle(bps > 0
                                 ? ChungHwa.Palette.text
                                 : ChungHwa.Palette.faint)
            Text(ChFormat.bytes(total))
                .font(.system(size: 9.5))
                .monospacedDigit()
                .foregroundStyle(ChungHwa.Palette.dim)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    /// Single-glyph rendering for the region column. "LAN" sentinel becomes
    /// a house emoji; a real ISO code becomes the regional-indicator flag;
    /// a still-pending lookup or missing IP renders empty so the column
    /// just stays blank rather than thrashing.
    private var regionGlyph: String {
        guard let country, !country.isEmpty else { return "" }
        if country == "LAN" { return "🏠" }
        return Self.flag(country)
    }

    /// Convert an ISO 3166-1 alpha-2 country code to a regional-indicator
    /// flag emoji. "JP" → 🇯🇵. Returns "" for inputs that aren't two ASCII
    /// letters so we never render a half-broken codepoint.
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

// MARK: - Shared 7-column grid

/// Pre-computed host / process column widths for the connections grid. The
/// parent `ConnectionsView.card` runs a SINGLE `GeometryReader` against the
/// card's width and hands these down to header + every row. Replaces a
/// per-row `GeometryReader` (one per visible row × every store tick).
struct ConnectionsColumnWidths: Equatable {
    let hostW: CGFloat
    let procW: CGFloat

    init(totalWidth: CGFloat) {
        // dot 12 · region 36 · down 86 · up 86 · rule 110
        let fixedSum: CGFloat = 12 + 36 + 86 + 86 + 110
        let gapSum: CGFloat = 10 * 6
        // The row's own .padding(.horizontal, 14) inside its body must be
        // subtracted from the available space — same arithmetic the
        // original per-row GeometryReader produced.
        let cardHPad: CGFloat = 14 * 2
        let flex = max(0, totalWidth - cardHPad - fixedSum - gapSum)
        self.hostW = flex * (1.6 / 2.6)
        self.procW = flex * (1.0 / 2.6)
    }
}

/// Lays out the 7 columns: 12px dot · 36px region flag · 1.6fr host · 1fr
/// process · 80px down · 80px up · 90px rule. The region column is fixed
/// at 36pt — wide enough for a regional-indicator emoji pair plus a touch
/// of breathing room without crowding the host name. Column widths are
/// computed once at the card level (see `ConnectionsColumnWidths`) and
/// passed in, so this struct does NO per-row geometry work.
private struct ConnectionsGridRow<Region: View, Host: View, Process: View,
                                  Down: View, Up: View, Rule: View>: View {
    let widths: ConnectionsColumnWidths
    @ViewBuilder var region: () -> Region
    @ViewBuilder var host: () -> Host
    @ViewBuilder var process: () -> Process
    @ViewBuilder var down: () -> Down
    @ViewBuilder var up: () -> Up
    @ViewBuilder var rule: () -> Rule

    var body: some View {
        HStack(spacing: 10) {
            region().frame(width: 36, alignment: .center)
            host().frame(width: widths.hostW, alignment: .leading)
            process().frame(width: widths.procW, alignment: .leading)
            down().frame(width: 86, alignment: .trailing)
            up().frame(width: 86, alignment: .trailing)
            rule().frame(width: 110, alignment: .leading)
        }
    }
}

// MARK: - Inspector

/// Right-hand details panel shown when the user selects a row. Renders the
/// destination, process, routing chain, rule, live stats and provides actions
/// to close the connection or dismiss the panel.
private struct ConnectionInspector: View {
    let connection: MihomoConnection
    let ended: Bool
    let anon: Bool
    let closeConnection: () -> Void
    let dismiss: () -> Void

    var body: some View {
        ChCardWithHeader(
            connection.destination,
            systemImage: "info.circle",
            iconColor: ChungHwa.Palette.brass,
            right: {
                HStack(spacing: 6) {
                    if ended {
                        Text("连接已结束")
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(0.3)
                            .textCase(.uppercase)
                            .foregroundStyle(ChungHwa.Palette.dim)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(ChungHwa.Palette.fill)
                                    .strokeBorder(ChungHwa.Palette.line, lineWidth: 0.5)
                            )
                    }
                    Button(action: dismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(ChungHwa.Palette.dim)
                            .frame(width: 22, height: 22)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(ChungHwa.Palette.fill)
                                    .strokeBorder(ChungHwa.Palette.line, lineWidth: 0.5)
                            )
                    }
                    .buttonStyle(.plain)
                    .help("关闭面板")
                }
            }
        ) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    destinationBlock
                    divider
                    processBlock
                    divider
                    routingBlock
                    divider
                    ruleBlock
                    divider
                    statsBlock
                    divider
                    actionsBlock
                }
                .padding(.top, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: blocks

    private var destinationBlock: some View {
        block(title: "目标") {
            row("主机",    valueText(connection.metadata.host ?? "—"), masked: true)
            row("IP",      valueText(connection.metadata.destinationIP ?? "—"), masked: true)
            row("端口",    valueText(connection.metadata.destinationPort ?? "—"))
            row("网络",    valueText(connection.metadata.network?.uppercased() ?? "—"))
            row("类型",    valueText(connection.metadata.type ?? "—"))
        }
    }

    private var processBlock: some View {
        block(title: "进程") {
            row("名称",
                valueText(connection.metadata.process ?? "—"),
                masked: true)
            row("路径",
                valueText(truncateMiddle(connection.metadata.processPath ?? "—",
                                         max: 56))
                    .help(connection.metadata.processPath ?? ""),
                masked: true)
            row("来源",
                valueText(formattedSource),
                masked: true)
        }
    }

    private var routingBlock: some View {
        block(title: "路由") {
            // `chains` is ordered from upstream-most to root group; the design
            // shows the active proxy at the top, so we walk it reversed.
            let path = connection.chains.reversed().map { String($0) }
            VStack(alignment: .leading, spacing: 4) {
                if path.isEmpty {
                    Text("DIRECT")
                        .font(ChungHwa.Typography.mono(11))
                        .foregroundStyle(ChungHwa.Palette.text)
                } else {
                    ForEach(Array(path.enumerated()), id: \.offset) { idx, name in
                        HStack(spacing: 6) {
                            Text(name)
                                .font(ChungHwa.Typography.mono(11,
                                    weight: idx == 0 ? .semibold : .regular))
                                .foregroundStyle(idx == 0
                                    ? ChungHwa.Palette.text
                                    : ChungHwa.Palette.dim)
                            Spacer(minLength: 0)
                        }
                        if idx < path.count - 1 {
                            Text("↓")
                                .font(ChungHwa.Typography.mono(10))
                                .foregroundStyle(ChungHwa.Palette.faint)
                                .padding(.leading, 1)
                        }
                    }
                }
            }
        }
    }

    private var ruleBlock: some View {
        block(title: "规则") {
            row("规则", valueText(connection.rule))
            if let payload = connection.rulePayload, !payload.isEmpty {
                row("载荷", valueText(payload))
            }
        }
    }

    private var statsBlock: some View {
        block(title: "统计") {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("上传")
                        .font(.system(size: 10.5))
                        .foregroundStyle(ChungHwa.Palette.dim)
                    Text("↑ \(ChFormat.bytes(connection.upload))")
                        .font(ChungHwa.Typography.mono(11))
                        .foregroundStyle(ChungHwa.Palette.text)
                        .monospacedDigit()
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("下载")
                        .font(.system(size: 10.5))
                        .foregroundStyle(ChungHwa.Palette.dim)
                    Text("↓ \(ChFormat.bytes(connection.download))")
                        .font(ChungHwa.Typography.mono(11))
                        .foregroundStyle(ChungHwa.Palette.text)
                        .monospacedDigit()
                }
                Spacer(minLength: 0)
            }
            // Elapsed-time owns its own TimelineView so the rest of the
            // inspector doesn't redraw at 1Hz.
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("时长")
                    .font(.system(size: 10.5))
                    .foregroundStyle(ChungHwa.Palette.dim)
                    .frame(width: 64, alignment: .leading)
                ElapsedText(start: connection.start)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var actionsBlock: some View {
        HStack(spacing: 8) {
            Button(action: closeConnection) {
                HStack(spacing: 6) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                    Text("关闭连接")
                        .font(.system(size: 11.5, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(ended ? ChungHwa.Palette.brassDark.opacity(0.55)
                                    : ChungHwa.Palette.brass)
                )
            }
            .buttonStyle(.plain)
            .disabled(ended)

            Spacer(minLength: 0)
        }
    }

    // MARK: helpers

    private var divider: some View {
        Rectangle()
            .fill(ChungHwa.Palette.lineSoft)
            .frame(height: 0.5)
    }

    @ViewBuilder
    private func block<Content: View>(title: String,
                                      @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.4)
                .textCase(.uppercase)
                .foregroundStyle(ChungHwa.Palette.faint)
            content()
        }
    }

    /// Label / value row used inside blocks. `masked` plumbs the screen-level
    /// anonymous-mode flag down so the same identifying fields the table
    /// blurs are blurred here too.
    private func row(_ label: String,
                     _ value: some View,
                     masked: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(.system(size: 10.5))
                .foregroundStyle(ChungHwa.Palette.dim)
                .frame(width: 64, alignment: .leading)
            Group {
                if masked {
                    AnyView(value.anonMask(anon))
                } else {
                    AnyView(value)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func valueText(_ s: String) -> some View {
        Text(s)
            .font(ChungHwa.Typography.mono(11))
            .foregroundStyle(ChungHwa.Palette.text)
            .lineLimit(2)
            .truncationMode(.middle)
            .textSelection(.enabled)
    }

    private var formattedSource: String {
        let ip   = connection.metadata.sourceIP ?? "—"
        let port = connection.metadata.sourcePort ?? ""
        return port.isEmpty ? ip : "\(ip):\(port)"
    }

    /// Truncate `s` in the middle so both ends remain visible when the path
    /// is too long for one line. Used for `processPath`.
    private func truncateMiddle(_ s: String, max: Int) -> String {
        guard s.count > max, max > 3 else { return s }
        let keep = (max - 1) / 2
        let head = s.prefix(keep)
        let tail = s.suffix(max - keep - 1)
        return "\(head)…\(tail)"
    }

}

/// Renders mihomo's connection-elapsed counter without forcing the parent
/// inspector to redraw every second. Uses a `TimelineView(.periodic)` so
/// the only thing invalidating per-second is this single Text.
private struct ElapsedText: View {
    let start: String

    private var startedAt: Date? { Self.parseISO(start) }

    var body: some View {
        Group {
            if let started = startedAt {
                TimelineView(.periodic(from: started, by: 1.0)) { ctx in
                    Text(Self.formatElapsed(since: started, now: ctx.date))
                        .font(ChungHwa.Typography.mono(11))
                        .foregroundStyle(ChungHwa.Palette.text)
                        .monospacedDigit()
                        .textSelection(.enabled)
                }
            } else {
                Text("—")
                    .font(ChungHwa.Typography.mono(11))
                    .foregroundStyle(ChungHwa.Palette.text)
            }
        }
    }

    private static func formatElapsed(since started: Date, now: Date) -> String {
        let s = Int(now.timeIntervalSince(started))
        guard s >= 0 else { return "0s" }
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        if h > 0 { return String(format: "%dh %02dm %02ds", h, m, sec) }
        if m > 0 { return String(format: "%dm %02ds", m, sec) }
        return "\(sec)s"
    }

    private static func parseISO(_ s: String) -> Date? {
        let f1 = ISO8601DateFormatter()
        f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f1.date(from: s) { return d }
        let f2 = ISO8601DateFormatter()
        f2.formatOptions = [.withInternetDateTime]
        return f2.date(from: s)
    }
}
