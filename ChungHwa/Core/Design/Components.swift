import Charts
import SwiftUI

// MARK: - Card

/// Plain Bone & Brass card. Use `ChCardWithHeader` if the card has a title row.
struct ChCard<Content: View>: View {
    let content: Content
    var padding: CGFloat = 14

    init(padding: CGFloat = 14, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .background(ChungHwa.Palette.card,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(ChungHwa.Palette.line, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.03), radius: 1, y: 1)
    }
}

/// Card with a title-row at the top (icon + title + right slot) and content
/// underneath. Mirrors `Card` from `design/src/app.jsx`.
struct ChCardWithHeader<Right: View, Content: View>: View {
    let title: String
    let systemImage: String?
    let iconColor: Color
    let right: Right
    let content: Content
    var padding: EdgeInsets = .init(top: 0, leading: 14, bottom: 14, trailing: 14)

    init(_ title: String,
         systemImage: String? = nil,
         iconColor: Color = ChungHwa.Palette.dim,
         padding: EdgeInsets = .init(top: 0, leading: 14, bottom: 14, trailing: 14),
         @ViewBuilder right: () -> Right = { EmptyView() },
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.iconColor = iconColor
        self.right = right()
        self.content = content()
        self.padding = padding
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                if let s = systemImage {
                    Image(systemName: s).foregroundStyle(iconColor).font(.system(size: 12))
                }
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(ChungHwa.Palette.text)
                    .tracking(-0.1)
                Spacer(minLength: 0)
                right
            }
            .padding(.horizontal, 14).padding(.top, 11).padding(.bottom, 8)
            content
                .padding(padding)
        }
        .background(ChungHwa.Palette.card,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(ChungHwa.Palette.line, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.03), radius: 1, y: 1)
    }
}

// MARK: - Stats

/// Big serif stat with a small icon-label above. Used in Overview cards.
struct ChStat: View {
    let label: String
    let value: String
    var systemImage: String?
    var color: Color = ChungHwa.Palette.brass

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                if let s = systemImage {
                    Image(systemName: s).font(.system(size: 11)).foregroundStyle(ChungHwa.Palette.dim)
                }
                Text(label)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(ChungHwa.Palette.dim)
            }
            Text(value)
                .font(ChungHwa.Typography.serif(26, weight: .medium))
                .foregroundStyle(color)
                .tracking(-0.4)
                .monospacedDigit()
        }
    }
}

/// Compact two-line stat row (icon-label on top, value below). For
/// secondary metadata under the headline stats.
struct ChSubStat<Value: View>: View {
    let label: String
    let value: Value
    var systemImage: String?

    init(_ label: String,
         systemImage: String? = nil,
         @ViewBuilder value: () -> Value) {
        self.label = label
        self.systemImage = systemImage
        self.value = value()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                if let s = systemImage {
                    Image(systemName: s).font(.system(size: 11)).foregroundStyle(ChungHwa.Palette.dim)
                }
                Text(label)
                    .font(.system(size: 10.5))
                    .foregroundStyle(ChungHwa.Palette.dim)
            }
            value
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(ChungHwa.Palette.text)
                .lineLimit(1).truncationMode(.tail)
        }
    }
}

extension ChSubStat where Value == Text {
    init(_ label: String, value: String, systemImage: String? = nil) {
        self.init(label, systemImage: systemImage) { Text(value) }
    }
}

// MARK: - Dot

/// Status dot with optional pulse. Pulse animates opacity, not size, so it
/// works inline with text without disturbing line height.
struct ChDot: View {
    var color: Color = ChungHwa.Palette.patina
    var size: CGFloat = 6
    var pulse: Bool = false

    @State private var animating = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .overlay(Circle().stroke(color.opacity(0.25), lineWidth: size / 2))
            .opacity(animating ? 0.4 : 1)
            .animation(pulse
                       ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                       : .default,
                       value: animating)
            .onAppear { if pulse { animating = true } }
    }
}

// MARK: - Pill / Segmented

/// Single rounded pill button. Used by `ChSeg` and freestanding buttons.
struct ChPill<Label: View>: View {
    let active: Bool
    let action: () -> Void
    let label: Label

    init(active: Bool, action: @escaping () -> Void, @ViewBuilder label: () -> Label) {
        self.active = active
        self.action = action
        self.label = label()
    }

    var body: some View {
        Button(action: action) {
            label
                .font(.system(size: 12, weight: active ? .semibold : .medium))
                .foregroundStyle(active ? ChungHwa.Palette.text : ChungHwa.Palette.dim)
                .padding(.horizontal, 11)
                .frame(height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(active ? ChungHwa.Palette.pillBg : Color.clear)
                        .shadow(color: active ? .black.opacity(0.06) : .clear, radius: 1, y: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

/// Segmented control matching the design's `Seg` component.
struct ChSeg<Value: Hashable>: View {
    let value: Value
    let onChange: (Value) -> Void
    let options: [(value: Value, label: String)]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.value) { o in
                ChPill(active: o.value == value, action: { onChange(o.value) }) {
                    Text(o.label)
                }
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(ChungHwa.Palette.fill)
                .strokeBorder(ChungHwa.Palette.line, lineWidth: 0.5)
        )
    }
}

// MARK: - Sparkline (Swift Charts)

struct ChSpark: View {
    let values: [Double]
    var color: Color = ChungHwa.Palette.patina
    var fill: Color?

    var body: some View {
        let f = fill ?? color
        Chart {
            ForEach(Array(values.enumerated()), id: \.offset) { idx, v in
                AreaMark(x: .value("i", idx), y: .value("v", v))
                    .foregroundStyle(.linearGradient(
                        colors: [f.opacity(0.30), f.opacity(0)],
                        startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("i", idx), y: .value("v", v))
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
            }
        }
        .chartXAxis(.hidden).chartYAxis(.hidden).chartLegend(.hidden)
    }
}

// MARK: - Anonymous mask

/// Apply on any view containing identifying info (IPs, hostnames, process
/// names). When anonymous mode is on, the view blurs and desaturates, and
/// hovering briefly reveals — same UX as the design's `.ch-mask`.
extension View {
    func anonMask(_ enabled: Bool) -> some View {
        modifier(ChAnonMaskModifier(enabled: enabled))
    }
}

private struct ChAnonMaskModifier: ViewModifier {
    let enabled: Bool
    @State private var revealing = false

    func body(content: Content) -> some View {
        content
            .blur(radius: enabled && !revealing ? 4 : 0)
            .saturation(enabled && !revealing ? 0.5 : 1)
            .onHover { revealing = $0 }
            .animation(.easeInOut(duration: 0.18), value: enabled || revealing)
    }
}

// MARK: - Latency colour

/// Standard latency tiering used by Proxies / Connections / Overview.
enum ChLatency {
    static func color(_ ms: Int) -> Color {
        switch ms {
        case ..<80:  return ChungHwa.Palette.patina
        case ..<150: return ChungHwa.Palette.brass
        default:     return ChungHwa.Palette.earth
        }
    }
}

// MARK: - Byte / rate formatters

enum ChFormat {
    static func bytes(_ b: Int) -> String {
        let v = Double(b)
        switch v {
        case ..<1024:                return String(format: "%.0f B", v)
        case ..<1_048_576:           return String(format: "%.1f KB", v / 1024)
        case ..<1_073_741_824:       return String(format: "%.1f MB", v / 1_048_576)
        default:                     return String(format: "%.2f GB", v / 1_073_741_824)
        }
    }

    static func rate(_ bps: Int) -> String { bytes(bps) + "/s" }

    static func uptime(since: Date) -> String {
        let s = Int(Date().timeIntervalSince(since))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, sec) }
        return String(format: "%d:%02d", m, sec)
    }
}
