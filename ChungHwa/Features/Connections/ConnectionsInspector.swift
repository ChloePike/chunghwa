import SwiftUI

/// Right-hand details panel for the selected connection. Renders destination,
/// process, routing chain, rule, live stats. Provides close + dismiss.
struct ConnectionInspector: View {
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
                        Text("已结束")
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
                    .help("关闭")
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
            // `chains` is ordered upstream-most to root group; design shows
            // active proxy at top, so we walk it reversed.
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
                    Text("断开")
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

    /// `masked` plumbs the screen-level anonymous-mode flag down so the same
    /// identifying fields the table blurs are blurred here too.
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

    /// Middle-truncate so both ends of a long path remain visible.
    private func truncateMiddle(_ s: String, max: Int) -> String {
        guard s.count > max, max > 3 else { return s }
        let keep = (max - 1) / 2
        let head = s.prefix(keep)
        let tail = s.suffix(max - keep - 1)
        return "\(head)…\(tail)"
    }
}

/// Renders the connection's elapsed counter in its own TimelineView so the
/// parent inspector doesn't redraw every second.
struct ElapsedText: View {
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
