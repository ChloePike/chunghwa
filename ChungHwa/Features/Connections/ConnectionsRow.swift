import SwiftUI

/// One row of the connections list. Equatable so a parent `.equatable()` can
/// short-circuit re-renders when nothing the row displays has changed — the
/// list ticks at ~1Hz with a hundred+ rows, so skipping equal rows materially
/// cuts the per-tick cost.
///
/// Comparison covers only fields that visibly change after creation: id,
/// upload/download counters, selection, anon mode, country, rate, widths.
/// `metadata`, `rule`, `chains` are immutable for a connection's lifetime.
struct ConnectionRow: View, Equatable {
    let row: MihomoConnection
    let widths: ConnectionsColumnWidths
    let anonEnabled: Bool
    let isSelected: Bool
    /// ISO 3166-1 alpha-2 (e.g. "JP", "US") or "LAN" for private addresses;
    /// nil while the lookup is still in flight.
    let country: String?
    /// Live bytes/second from `ConnectionsStore`. `.zero` for first sighting.
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
                Text(ConnectionsHelpers.regionGlyph(country))
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
                Text(ConnectionsHelpers.ruleText(row.rule))
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

    /// Two-line trailing-aligned cell: live rate (bytes/sec) on top, total
    /// bytes underneath. "0 B/s" renders as a subdued "·" so quiet
    /// connections don't flood the column with zeros.
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
}

/// Pre-computed host / process column widths. Computed once at the card
/// level (single GeometryReader), passed to header + every row.
struct ConnectionsColumnWidths: Equatable {
    let hostW: CGFloat
    let procW: CGFloat

    init(totalWidth: CGFloat) {
        // dot 12 · region 36 · down 86 · up 86 · rule 110
        let fixedSum: CGFloat = 12 + 36 + 86 + 86 + 110
        let gapSum: CGFloat = 10 * 6
        // Subtract the row's .padding(.horizontal, 14) so the math matches
        // the original per-row GeometryReader.
        let cardHPad: CGFloat = 14 * 2
        let flex = max(0, totalWidth - cardHPad - fixedSum - gapSum)
        self.hostW = flex * (1.6 / 2.6)
        self.procW = flex * (1.0 / 2.6)
    }
}

/// Lays out the 7 columns: 12pt dot · 36pt region flag · 1.6fr host · 1fr
/// process · 86pt down · 86pt up · 110pt rule. Widths are pre-computed so
/// this struct does NO per-row geometry work.
struct ConnectionsGridRow<Region: View, Host: View, Process: View,
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
