import SwiftUI

struct ResourcesCard: View {
    var body: some View {
        ChCardWithHeader(
            "资源",
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
struct ConnectionCountStat: View {
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

struct MemoryStat: View {
    @Environment(TrafficStore.self) private var traffic

    var body: some View {
        ChStat(
            label: "内存",
            value: traffic.memoryInUse > 0 ? ChFormat.bytes(traffic.memoryInUse) : "—",
            systemImage: "memorychip",
            color: ChungHwa.Palette.brass
        )
    }
}

/// Peak rate as a sub-stat so it shares vertical rhythm with NetworkCard's
/// IP sub-stat row instead of duplicating the big serif of the top row.
struct PeakSubStat: View {
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
