import SwiftUI

/// Bone & Brass on Patina reskin of the Connections screen.
///
/// Mirrors `ConnectionsScreen` in `design/src/app.jsx` (≈L1007–L1085): a single
/// `ChCard` with a fixed grid header and a scrolling list of rows. The toolbar
/// above the card carries a "{active} · {total}" counter on the left and
/// pause/clear icon buttons on the right.
struct ConnectionsView: View {
    @Environment(KernelController.self) private var kernel
    @Environment(ConnectionsStore.self) private var store
    @Environment(AnonymousMode.self) private var anon

    @State private var paused: Bool = false
    /// Snapshot frozen at the moment the user pressed pause. Cleared when they
    /// resume so live updates flow through again.
    @State private var frozen: [MihomoConnection]? = nil

    var body: some View {
        VStack(spacing: 10) {
            toolbar
            card
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(ChungHwa.Palette.bg)
        .navigationTitle("Connections")
    }

    // MARK: - Data

    /// Rows the UI is currently rendering — the live store, or the frozen
    /// snapshot taken when the user pressed pause.
    private var rows: [MihomoConnection] {
        frozen ?? store.connections
    }

    /// We don't currently track per-connection liveness from the kernel, so
    /// every row is treated as "live" (pulsing green dot) per the spec.
    private var activeCount: Int { rows.count }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
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

    // MARK: - Card / table

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
                        .overlay(alignment: .top) {
                            Rectangle()
                                .fill(ChungHwa.Palette.lineSoft)
                                .frame(height: 0.5)
                        }
                        .contextMenu {
                            Button("Close", role: .destructive) {
                                Task { await store.close(id: row.id, api: kernel.apiClient) }
                            }
                        }
                }
            }
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
