import SwiftUI

/// Connections tab — toolbar + scrolling row list, with a 60/40 inspector
/// split when a row is selected. Selection persists past kernel-side drops so
/// the inspector keeps showing details after a connection ends.
struct ConnectionsView: View {
    @Environment(KernelController.self) private var kernel
    @Environment(ConnectionsStore.self) private var store
    @Environment(AnonymousMode.self) private var anon
    @Environment(GeoIPStore.self) private var geo

    @State private var paused: Bool = false
    /// Snapshot frozen on pause; cleared on resume so live updates flow again.
    @State private var frozen: [MihomoConnection]? = nil

    @State private var selectedID: MihomoConnection.ID? = nil
    /// Sticky last-known snapshot of the selected connection so the inspector
    /// can keep showing details after the kernel drops it from `connections`.
    @State private var lastSelectedSnapshot: MihomoConnection? = nil

    @State private var query: String = ""
    /// Debounced mirror of `query` — predicate only re-runs ~150ms after the
    /// user pauses typing, keeping a 500-row list snappy.
    @State private var debouncedQuery: String = ""
    @FocusState private var filterFocused: Bool

    @FocusState private var listFocused: Bool

    var body: some View {
        // Filter once per body — `rows` was being recomputed by the toolbar
        // count and the row list independently.
        let visible = rows
        return VStack(spacing: 10) {
            toolbar(rows: visible)
            cardArea(rows: visible)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(ChungHwa.Palette.bg)
        .onChange(of: liveSelectedKey) { _, _ in
            if let id = selectedID,
               let live = store.connections.first(where: { $0.id == id }) {
                lastSelectedSnapshot = live
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .chungHwaFocusFilter)) { _ in
            filterFocused = true
        }
        // Debounce filter typing. `.task(id:)` cancels the prior task on each
        // keystroke; only the last surviving sleep commits.
        .task(id: query) {
            try? await Task.sleep(nanoseconds: 150_000_000)
            if !Task.isCancelled {
                debouncedQuery = query
            }
        }
        // Feed visible destination IPs to GeoIP. Re-keys on connection count
        // — granular enough to catch new connections without thrashing on
        // byte-counter ticks.
        .task(id: store.connections.count) {
            let ips = Set(store.connections.compactMap { $0.metadata.destinationIP })
            geo.resolve(ips: ips)
        }
    }

    /// Fingerprint used as `onChange` trigger so we don't require
    /// `MihomoConnection: Equatable`. Encodes id, byte counters and chain.
    private var liveSelectedKey: String {
        guard let id = selectedID,
              let live = store.connections.first(where: { $0.id == id })
        else { return "" }
        return "\(live.id)|\(live.upload)|\(live.download)|\(live.chains.joined(separator: ">"))"
    }

    /// Live store (or frozen snapshot if paused) filtered by the toolbar's
    /// free-text query. `q` is lowercased once outside the predicate.
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

    private func toolbar(rows: [MihomoConnection]) -> some View {
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

            Text("\(rows.count) / \(rows.count)")
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

    @ViewBuilder
    private func cardArea(rows: [MihomoConnection]) -> some View {
        // SwiftUI flexible layout drifts toward 50/50 once both sides have
        // maxWidth: .infinity, so we measure with a GeometryReader.
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
                card(rows: rows)
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
    private func card(rows: [MihomoConnection]) -> some View {
        ChCard(padding: 0) {
            if kernel.apiClient == nil {
                emptyState(title: "内核未启动",
                           system: "powerplug",
                           subtitle: "启动 mihomo 后这里会显示连接。")
            } else {
                // One layout pass at the card level → header + every row uses
                // the same widths. Replaces a per-row GeometryReader.
                GeometryReader { geo in
                    let widths = ConnectionsColumnWidths(totalWidth: geo.size.width)
                    VStack(spacing: 0) {
                        headerRow(widths: widths)
                        if rows.isEmpty {
                            emptyState(title: "暂无连接",
                                       system: "link.circle",
                                       subtitle: "上网后被代理的连接会出现在这里。")
                        } else {
                            rowList(rows: rows, widths: widths)
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
            region:  { headerCell("", alignment: .center) },
            host:    { headerCell("主机", alignment: .leading) },
            process: { headerCell("进程", alignment: .leading) },
            down:    { headerCell("下行", alignment: .trailing) },
            up:      { headerCell("上行", alignment: .trailing) },
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

    private func rowList(rows: [MihomoConnection],
                         widths: ConnectionsColumnWidths) -> some View {
        let anonEnabled = anon.enabled
        let currentSelection = selectedID
        let liveRates = store.rates

        return ScrollView(.vertical, showsIndicators: true) {
            LazyVStack(spacing: 0) {
                ForEach(rows) { row in
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
            // Pick the first row when Return arrives without a selection
            // (focus came in from elsewhere).
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
            // Brass focus ring while the list owns the keyboard.
            if listFocused {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(ChungHwa.Palette.brass.opacity(0.55),
                                  lineWidth: 0.5)
                    .allowsHitTesting(false)
            }
        }
    }

    /// Shared between per-row right-click and table-wide selection right-click.
    /// For multi-id selections the copy actions newline-join values.
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
            Label("断开", systemImage: "xmark.circle")
        }
        .disabled(ids.isEmpty)
    }

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

    /// Move selection by `delta` within the post-filter `rows`. Bootstraps
    /// to first/last when nothing is selected; clamps at edges (no wrap).
    private func moveSelection(_ delta: Int) {
        let visible = rows
        guard !visible.isEmpty else { return }

        let newRow: MihomoConnection
        if let id = selectedID,
           let idx = visible.firstIndex(where: { $0.id == id }) {
            let next = max(0, min(visible.count - 1, idx + delta))
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

    private static func copy(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }
}
