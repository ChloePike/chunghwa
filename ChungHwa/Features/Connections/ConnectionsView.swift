import Combine
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
    @FocusState private var filterFocused: Bool

    var body: some View {
        VStack(spacing: 10) {
            toolbar
            cardArea
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(ChungHwa.Palette.bg)
        .navigationTitle("Connections")
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
    private var rows: [MihomoConnection] {
        let base = frozen ?? store.connections
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
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
                TextField("Filter connections", text: $query)
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

            Text("\(activeCount) active · \(rows.count) total")
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
                emptyState(title: "Kernel is not running",
                           system: "powerplug",
                           subtitle: "Connections appear here once mihomo is up.")
            } else {
                VStack(spacing: 0) {
                    headerRow
                    if rows.isEmpty {
                        emptyState(title: "No active connections",
                                   system: "link.circle",
                                   subtitle: "Browse a website to see proxied connections.")
                    } else {
                        rowList
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var headerRow: some View {
        ConnectionsGridRow(
            dot:     { Color.clear.frame(width: 12, height: 12) },
            host:    { headerCell("Host", alignment: .leading) },
            process: { headerCell("Process", alignment: .leading) },
            down:    { headerCell("Down", alignment: .trailing) },
            up:      { headerCell("Up", alignment: .trailing) },
            rule:    { headerCell("Rule", alignment: .leading) }
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

    private var rowList: some View {
        ScrollView(.vertical, showsIndicators: true) {
            LazyVStack(spacing: 0) {
                ForEach(rows) { row in
                    ConnectionRowView(row: row, anon: anon.enabled)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(
                            row.id == selectedID
                            ? ChungHwa.Palette.brass.opacity(0.10)
                            : Color.clear
                        )
                        .overlay(alignment: .top) {
                            Rectangle()
                                .fill(ChungHwa.Palette.lineSoft)
                                .frame(height: 0.5)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            select(row)
                        }
                        .contextMenu {
                            rowContextMenu(for: [row.id])
                        }
                }
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

        Button("Copy host") {
            let value = conns
                .map { $0.metadata.host ?? $0.metadata.destinationIP ?? "—" }
                .joined(separator: "\n")
            Self.copy(value)
        }
        .disabled(conns.isEmpty)

        Button("Copy IP") {
            let value = conns
                .map { $0.metadata.destinationIP ?? "—" }
                .joined(separator: "\n")
            Self.copy(value)
        }
        .disabled(conns.isEmpty)

        Button("Copy host:port") {
            let value = conns.map { $0.destination }.joined(separator: "\n")
            Self.copy(value)
        }
        .disabled(conns.isEmpty)

        Button("Copy chain") {
            let value = conns.map { $0.chainPath }.joined(separator: "\n")
            Self.copy(value)
        }
        .disabled(conns.isEmpty)

        Button("Copy as JSON") {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let pieces: [String] = conns.compactMap { conn in
                guard let data = try? encoder.encode(conn) else { return nil }
                return String(data: data, encoding: .utf8)
            }
            Self.copy(pieces.joined(separator: "\n"))
        }
        .disabled(conns.isEmpty)

        Divider()

        Button("Close", role: .destructive) {
            let api = kernel.apiClient
            for id in ids {
                Task { await store.close(id: id, api: api) }
            }
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

private struct ConnectionRowView: View {
    let row: MihomoConnection
    let anon: Bool

    var body: some View {
        ConnectionsGridRow(
            dot: {
                ChDot(color: ChungHwa.Palette.patina, size: 6, pulse: true)
                    .frame(width: 12, height: 12)
            },
            host: {
                Text(hostText)
                    .font(ChungHwa.Typography.mono(11))
                    .foregroundStyle(ChungHwa.Palette.text)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .help(hostText)
                    .anonMask(anon)
            },
            process: {
                Text(processText)
                    .font(.system(size: 11.5))
                    .foregroundStyle(ChungHwa.Palette.dim)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .anonMask(anon)
            },
            down: {
                Text(ChFormat.bytes(row.download))
                    .font(.system(size: 11.5))
                    .monospacedDigit()
                    .foregroundStyle(ChungHwa.Palette.text)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            },
            up: {
                Text(ChFormat.bytes(row.upload))
                    .font(.system(size: 11.5))
                    .monospacedDigit()
                    .foregroundStyle(ChungHwa.Palette.text)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            },
            rule: {
                Text(row.rule)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(row.rule == "DIRECT"
                                     ? ChungHwa.Palette.dim
                                     : ChungHwa.Palette.patina)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        )
    }

    private var hostText: String { row.destination }
    private var processText: String { row.metadata.process ?? "—" }
}

// MARK: - Shared 6-column grid

/// Lays out the 6 columns from the JSX
/// (`gridTemplateColumns: "12px 1.6fr 1fr 80px 80px 90px"`).
///
/// SwiftUI has no direct equivalent of CSS `fr` units, but combining
/// `frame(maxWidth: .infinity)` with `.layoutPriority` on the two flexible
/// cells — and giving the 1.6fr cell a higher priority so it grows faster —
/// produces the same visual proportion at the widths this screen renders at.
private struct ConnectionsGridRow<Dot: View, Host: View, Process: View,
                                  Down: View, Up: View, Rule: View>: View {
    @ViewBuilder var dot: () -> Dot
    @ViewBuilder var host: () -> Host
    @ViewBuilder var process: () -> Process
    @ViewBuilder var down: () -> Down
    @ViewBuilder var up: () -> Up
    @ViewBuilder var rule: () -> Rule

    var body: some View {
        GeometryReader { geo in
            // Total width minus the fixed cells (12 + 80 + 80 + 90) and the
            // five 10pt gaps between six columns. What's left is split 1.6 : 1
            // between Host and Process.
            let fixedSum: CGFloat = 12 + 80 + 80 + 90
            let gapSum: CGFloat = 10 * 5
            let flex = max(0, geo.size.width - fixedSum - gapSum)
            let hostW = flex * (1.6 / 2.6)
            let procW = flex * (1.0 / 2.6)

            HStack(spacing: 10) {
                dot().frame(width: 12, alignment: .center)
                host().frame(width: hostW, alignment: .leading)
                process().frame(width: procW, alignment: .leading)
                down().frame(width: 80, alignment: .trailing)
                up().frame(width: 80, alignment: .trailing)
                rule().frame(width: 90, alignment: .leading)
            }
        }
        .frame(height: rowHeight)
    }

    /// Single-line row height. 11.5pt body + comfortable line-height matches
    /// the design's `padding: 7px 14px` plus text size.
    private var rowHeight: CGFloat { 18 }
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

    /// 1Hz tick that drives the elapsed-time counter without re-rendering on
    /// the global store cadence.
    @State private var now: Date = .init()
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ChCardWithHeader(
            connection.destination,
            systemImage: "info.circle",
            iconColor: ChungHwa.Palette.brass,
            right: {
                HStack(spacing: 6) {
                    if ended {
                        Text("Connection ended")
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
                    .help("Close panel")
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
        .onReceive(tick) { now = $0 }
    }

    // MARK: blocks

    private var destinationBlock: some View {
        block(title: "Destination") {
            row("Host",    valueText(connection.metadata.host ?? "—"), masked: true)
            row("IP",      valueText(connection.metadata.destinationIP ?? "—"), masked: true)
            row("Port",    valueText(connection.metadata.destinationPort ?? "—"))
            row("Network", valueText(connection.metadata.network?.uppercased() ?? "—"))
            row("Type",    valueText(connection.metadata.type ?? "—"))
        }
    }

    private var processBlock: some View {
        block(title: "Process") {
            row("Name",
                valueText(connection.metadata.process ?? "—"),
                masked: true)
            row("Path",
                valueText(truncateMiddle(connection.metadata.processPath ?? "—",
                                         max: 56))
                    .help(connection.metadata.processPath ?? ""),
                masked: true)
            row("Source",
                valueText(formattedSource),
                masked: true)
        }
    }

    private var routingBlock: some View {
        block(title: "Routing") {
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
        block(title: "Rule") {
            row("Rule", valueText(connection.rule))
            if let payload = connection.rulePayload, !payload.isEmpty {
                row("Payload", valueText(payload))
            }
        }
    }

    private var statsBlock: some View {
        block(title: "Stats") {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Upload")
                        .font(.system(size: 10.5))
                        .foregroundStyle(ChungHwa.Palette.dim)
                    Text("↑ \(ChFormat.bytes(connection.upload))")
                        .font(ChungHwa.Typography.mono(11))
                        .foregroundStyle(ChungHwa.Palette.text)
                        .monospacedDigit()
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Download")
                        .font(.system(size: 10.5))
                        .foregroundStyle(ChungHwa.Palette.dim)
                    Text("↓ \(ChFormat.bytes(connection.download))")
                        .font(ChungHwa.Typography.mono(11))
                        .foregroundStyle(ChungHwa.Palette.text)
                        .monospacedDigit()
                }
                Spacer(minLength: 0)
            }
            row("Elapsed", valueText(elapsedString))
        }
    }

    private var actionsBlock: some View {
        HStack(spacing: 8) {
            Button(action: closeConnection) {
                HStack(spacing: 6) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                    Text("Close connection")
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

    /// `start` is an ISO-8601 timestamp from mihomo. Falls back to "—" if it
    /// fails to parse.
    private var elapsedString: String {
        guard let started = parseISO(connection.start) else { return "—" }
        let s = Int(now.timeIntervalSince(started))
        guard s >= 0 else { return "0s" }
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        if h > 0 { return String(format: "%dh %02dm %02ds", h, m, sec) }
        if m > 0 { return String(format: "%dm %02ds", m, sec) }
        return "\(sec)s"
    }

    private func parseISO(_ s: String) -> Date? {
        let f1 = ISO8601DateFormatter()
        f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f1.date(from: s) { return d }
        let f2 = ISO8601DateFormatter()
        f2.formatOptions = [.withInternetDateTime]
        return f2.date(from: s)
    }
}
