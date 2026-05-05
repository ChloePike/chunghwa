import SwiftUI

struct ProxyNodeCard: View, Equatable {
    let name: String
    let proxy: MihomoProxy?
    let isSelected: Bool
    let isSwitchable: Bool
    let isTesting: Bool
    let onSelect: () -> Void

    @State private var shimmer: Bool = false

    /// Equatable so the 1Hz refresh only re-renders cards whose state actually changed.
    static func == (lhs: ProxyNodeCard, rhs: ProxyNodeCard) -> Bool {
        lhs.name == rhs.name
            && lhs.proxy?.lastDelay == rhs.proxy?.lastDelay
            && lhs.isSelected == rhs.isSelected
            && lhs.isSwitchable == rhs.isSwitchable
            && lhs.isTesting == rhs.isTesting
    }

    private var pingValue: Int { proxy?.lastDelay ?? 0 }
    private var pingColor: Color {
        pingValue == 0 ? ChungHwa.Palette.faint : ChLatency.color(pingValue)
    }
    /// 0…1 fill width for the latency bar.
    private var pingFraction: Double {
        guard pingValue > 0 else { return 0 }
        let raw = 1.0 - Double(pingValue) / 250.0
        return max(0.08, min(1.0, raw))
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 7) {
                row1
                row2
                latencyBar
            }
            .padding(.horizontal, 11).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isSelected
                          ? ChungHwa.Palette.brass.opacity(0.10)
                          : ChungHwa.Palette.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(isSelected ? ChungHwa.Palette.brass : ChungHwa.Palette.line,
                                  lineWidth: 0.5)
            )
            .shadow(color: isSelected ? ChungHwa.Palette.brass.opacity(0.20) : .black.opacity(0.02),
                    radius: isSelected ? 1 : 0.5, y: 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isSwitchable && !isSelected)
        .help(isSwitchable ? "点击切换" : "由 \(proxy?.type ?? "分组") 自动选")
    }

    private var row1: some View {
        HStack(spacing: 7) {
            Text(name)
                .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(ChungHwa.Palette.text)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            if isSelected {
                ZStack {
                    Circle().fill(ChungHwa.Palette.brass)
                        .frame(width: 14, height: 14)
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
        }
    }

    private var row2: some View {
        HStack(spacing: 6) {
            if let p = proxy {
                Text(p.type.uppercased())
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    .tracking(0.2)
                    .foregroundStyle(ChungHwa.Palette.faint)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(ChungHwa.Palette.fill)
                    )
            }
            Spacer()
            if isTesting {
                HStack(spacing: 4) {
                    ProgressView()
                        .controlSize(.mini)
                        .scaleEffect(0.6)
                        .frame(width: 8, height: 8)
                    Text("测试中")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(ChungHwa.Palette.brass)
                        .monospacedDigit()
                }
            } else {
                Text(pingValue == 0 ? "—" : "\(pingValue) ms")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(pingColor)
                    .monospacedDigit()
            }
        }
    }

    private var latencyBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(ChungHwa.Palette.fill)
                if isTesting {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(
                            LinearGradient(
                                colors: [
                                    ChungHwa.Palette.brass.opacity(0),
                                    ChungHwa.Palette.brass,
                                    ChungHwa.Palette.brass.opacity(0),
                                ],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * 0.5)
                        .offset(x: shimmer ? geo.size.width * 0.5 : -geo.size.width * 0.5)
                        .animation(.linear(duration: 1.1).repeatForever(autoreverses: false),
                                   value: shimmer)
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                        .onAppear { shimmer = true }
                        .onDisappear { shimmer = false }
                } else if pingValue > 0 {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(pingColor)
                        .frame(width: geo.size.width * pingFraction)
                        .animation(.easeInOut(duration: 0.28), value: pingFraction)
                }
            }
        }
        .frame(height: 3)
    }
}

struct ProxyNodeRow: View, Equatable {
    let name: String
    let proxy: MihomoProxy?
    let isSelected: Bool
    let isSwitchable: Bool
    let isTesting: Bool
    let onSelect: () -> Void

    static func == (lhs: ProxyNodeRow, rhs: ProxyNodeRow) -> Bool {
        lhs.name == rhs.name
            && lhs.proxy?.lastDelay == rhs.proxy?.lastDelay
            && lhs.isSelected == rhs.isSelected
            && lhs.isSwitchable == rhs.isSwitchable
            && lhs.isTesting == rhs.isTesting
    }

    private var pingValue: Int { proxy?.lastDelay ?? 0 }
    private var pingColor: Color {
        pingValue == 0 ? ChungHwa.Palette.faint : ChLatency.color(pingValue)
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                radio
                    .frame(width: 13)
                Text(name)
                    .font(.system(size: 12.5, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(ChungHwa.Palette.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(proxy?.type.uppercased() ?? "—")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(ChungHwa.Palette.faint)
                    .frame(width: 90, alignment: .leading)
                Text(pingValue > 0 ? "已测" : "未测")
                    .font(.system(size: 10.5))
                    .foregroundStyle(ChungHwa.Palette.dim)
                    .frame(width: 70, alignment: .leading)
                latencyTrailing
                    .frame(width: 70, alignment: .trailing)
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected ? ChungHwa.Palette.brass.opacity(0.10) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isSwitchable && !isSelected)
        .help(isSwitchable ? "点击切换" : "由 \(proxy?.type ?? "分组") 自动选")
    }

    private var radio: some View {
        ZStack {
            Circle()
                .strokeBorder(isSelected ? ChungHwa.Palette.brass : ChungHwa.Palette.line,
                              lineWidth: 1.4)
                .background(
                    Circle().fill(isSelected ? ChungHwa.Palette.brass : Color.clear)
                )
                .frame(width: 13, height: 13)
            if isSelected {
                Circle().fill(.white).frame(width: 4, height: 4)
            }
        }
    }

    @ViewBuilder
    private var latencyTrailing: some View {
        if isTesting {
            Text("…")
                .font(.system(size: 11.5, weight: .bold))
                .foregroundStyle(ChungHwa.Palette.brass)
                .monospacedDigit()
        } else {
            Text(pingValue == 0 ? "—" : "\(pingValue) ms")
                .font(.system(size: 11.5, weight: .bold))
                .foregroundStyle(pingColor)
                .monospacedDigit()
        }
    }
}
