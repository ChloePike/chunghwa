import AppKit
import SwiftUI

// MARK: - AdvancedView

/// Advanced settings tab — "Bone & Brass on Patina" design.
///
/// All values are persisted via `@AppStorage` under the
/// `ChungHwa.Advanced.*` namespace. Two of them — `LogLevel` and
/// `LANInbound` — are also pushed to mihomo's `/configs` endpoint at
/// runtime (via `ConfigStore`); the rest remain local-only and require
/// a kernel restart to take effect.
///
/// Mirrors `AdvancedScreen` in `design/src/app.jsx` (lines 1245-1408).
struct AdvancedView: View {
    @Environment(KernelController.self) private var kernel
    @Environment(ConfigStore.self)      private var config

    // ── Kernel logs ────────────────────────────────────────────────────
    @AppStorage("ChungHwa.Advanced.LogLevel")          private var logLevel: String  = "error"

    // ── Connection optimization ────────────────────────────────────────
    @AppStorage("ChungHwa.Advanced.UnifiedDelay")      private var unifiedDelay: Bool = true
    @AppStorage("ChungHwa.Advanced.TCPConcurrent")     private var tcpConcurrent: Bool = true
    @AppStorage("ChungHwa.Advanced.IPv6")              private var ipv6: Bool = true
    @AppStorage("ChungHwa.Advanced.QUIC")              private var quic: String = "ext"

    // ── DNS ────────────────────────────────────────────────────────────
    @AppStorage("ChungHwa.Advanced.DNSMode")           private var dnsMode: String = "smart"
    @AppStorage("ChungHwa.Advanced.DNSHijack")         private var dnsHijack: Bool = true

    // ── LAN ────────────────────────────────────────────────────────────
    @AppStorage("ChungHwa.Advanced.LANInbound")        private var lan: Bool = false

    // ── Proxy auth ─────────────────────────────────────────────────────
    @AppStorage("ChungHwa.Advanced.AuthUser")          private var authUser: String = ""
    @AppStorage("ChungHwa.Advanced.AuthPass")          private var authPass: String = ""
    @State private var showPass = false

    // ── Bypass list (persisted as JSON-encoded Data via UserDefaults) ──
    @State private var bypass: [BypassEntry] = AdvancedView.loadBypass()
    @State private var newIp: String = ""

    // ── Sheet presentation state ──────────────────────────────────────
    @State private var showDNSEditor: Bool = false
    @State private var showRoutingEditor: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                kernelLogs
                connectionOptimization
                dns
                routing
                lanInbound
                proxyAuth
                bypassList
                Color.clear.frame(height: 18)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(ChungHwa.Palette.bg)
        // Live-push to mihomo whenever the user flips the wired settings.
        // The @AppStorage value is the source of truth for the UI; the
        // store does an optimistic update + rollback against /configs.
        .onChange(of: logLevel) { _, newValue in
            Task { await config.setLogLevel(newValue, api: kernel.apiClient) }
        }
        .onChange(of: lan) { _, newValue in
            Task { await config.setAllowLan(newValue, api: kernel.apiClient) }
        }
        .onChange(of: ipv6) { _, newValue in
            Task { await config.setIPv6(newValue, api: kernel.apiClient) }
        }
        .onChange(of: tcpConcurrent) { _, newValue in
            Task { await config.setTCPConcurrent(newValue, api: kernel.apiClient) }
        }
        .onChange(of: dnsMode) { _, newValue in
            Task { await config.setDNSMode(newValue, api: kernel.apiClient) }
        }
        .onChange(of: dnsHijack) { _, newValue in
            Task { await config.setDNSHijack(newValue, api: kernel.apiClient) }
        }
        .sheet(isPresented: $showDNSEditor) {
            DNSEditorSheet()
                .environment(kernel)
                .environment(config)
        }
        .sheet(isPresented: $showRoutingEditor) {
            RoutingEditor()
        }
    }

    // MARK: - Sections

    private var kernelLogs: some View {
        AdvSection(title: "内核日志") {
            AdvRow(icon: "dial.medium",
                   iconColor: ChungHwa.Palette.brass,
                   label: "日志级别",
                   sub: "详细输出写入 ~/Library/Logs/ChungHwa") {
                Stepper(value: $logLevel, options: [
                    ("silent",  "静默"),
                    ("error",   "错误"),
                    ("warning", "警告"),
                    ("info",    "信息"),
                    ("debug",   "调试"),
                ])
            }
            FootnoteRow(text: "实时同步至 mihomo · 启动时从 /configs 拉回")
            AdvRow(icon: "doc.text.magnifyingglass",
                   iconColor: ChungHwa.Palette.patina,
                   label: "查看内核日志",
                   last: true) {
                IconButton(systemName: "arrow.up.forward") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Utilities/Console.app"))
                }
            }
        }
    }

    private var connectionOptimization: some View {
        AdvSection(title: "连接优化") {
            AdvRow(icon: "gauge.with.dots.needle.50percent",
                   iconColor: ChungHwa.Palette.patina,
                   label: "统一延迟测试",
                   sub: "需要重启内核") {
                Switch(isOn: $unifiedDelay)
            }
            AdvRow(icon: "arrow.triangle.branch",
                   iconColor: ChungHwa.Palette.brass,
                   label: "TCP 并发连接",
                   sub: "对所选节点开多条 TCP 流") {
                Switch(isOn: $tcpConcurrent)
            }
            AdvRow(icon: "globe",
                   iconColor: ChungHwa.Palette.patina,
                   label: "IPv6 支持") {
                Switch(isOn: $ipv6)
            }
            AdvRow(icon: "bolt.horizontal",
                   iconColor: ChungHwa.Palette.brass,
                   label: "禁用 QUIC",
                   sub: "部分网络限速 QUIC，回落 TCP 更稳",
                   last: true) {
                Stepper(value: $quic, options: [
                    ("off", "从不"),
                    ("ext", "仅外网"),
                    ("all", "总是"),
                ])
            }
            FootnoteRow(text: "实时: TCP 并发、IPv6 · 本地: 统一延迟、禁用 QUIC")
        }
    }

    private var dns: some View {
        AdvSection(title: "DNS") {
            AdvRow(icon: "arrow.left.arrow.right",
                   iconColor: ChungHwa.Palette.patina,
                   label: "解析模式",
                   sub: "智能模式: 国内走系统，国外走 fake-ip") {
                Stepper(value: $dnsMode, options: [
                    ("system",  "系统"),
                    ("smart",   "智能"),
                    ("fake-ip", "Fake-IP"),
                ])
            }
            AdvRow(icon: "shield",
                   iconColor: ChungHwa.Palette.brass,
                   label: "劫持 53 端口",
                   sub: "捕获系统所有 DNS 流量") {
                Switch(isOn: $dnsHijack)
            }
            AdvRow(icon: "server.rack",
                   iconColor: ChungHwa.Palette.patina,
                   label: "上游解析器",
                   sub: "每行一条；支持 DoH、DoT、DoQ",
                   last: true) {
                Text(upstreamSummary)
                    .font(ChungHwa.Typography.mono(11))
                    .foregroundStyle(ChungHwa.Palette.dim)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Button {
                    showDNSEditor = true
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11))
                        .foregroundStyle(ChungHwa.Palette.dim)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            FootnoteRow(text: "仅在使用默认配置时生效；订阅 YAML 自带 dns 块时优先用订阅自己的")
        }
    }

    private var routing: some View {
        AdvSection(title: "我的路由") {
            AdvRow(icon: "list.bullet.rectangle",
                   iconColor: ChungHwa.Palette.brass,
                   label: "自定义规则",
                   sub: routingSummary,
                   last: true) {
                Button {
                    showRoutingEditor = true
                } label: {
                    HStack(spacing: 4) {
                        Text("查看 / 编辑")
                            .font(.system(size: 11, weight: .semibold))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(ChungHwa.Palette.brass)
                    .padding(.horizontal, 10)
                    .frame(height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(ChungHwa.Palette.brass.opacity(0.12))
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            FootnoteRow(text: "仅在使用默认配置时生效；订阅 YAML 请直接编辑源文件")
        }
    }

    private var upstreamSummary: String {
        let count = config.dnsNameservers.count
        guard count > 0 else { return "0 个" }
        let first = config.dnsNameservers.first ?? ""
        let host = Self.hostFragment(of: first)
        return "\(count) 个 · \(host)"
    }

    private var routingSummary: String {
        let n = config.customRules.count
        if n == 0 { return "尚未添加规则" }
        return "\(n) 条规则"
    }

    /// Pull a short host-ish fragment out of a resolver string for the row
    /// summary. For URLs we want the host; for raw IPs we want the IP itself.
    private static func hostFragment(of value: String) -> String {
        if let url = URL(string: value), let host = url.host, !host.isEmpty {
            return host
        }
        if let scheme = value.range(of: "://") {
            return String(value[scheme.upperBound...])
        }
        return value
    }

    private var lanInbound: some View {
        AdvSection(title: "局域网入站") {
            AdvRow(icon: "dot.radiowaves.left.and.right",
                   iconColor: lan ? ChungHwa.Palette.brass : ChungHwa.Palette.patina,
                   label: "允许局域网连接",
                   sub: lan
                        ? "其他设备可使用此 Mac 作为网关"
                        : "只有此 Mac 能连接代理",
                   last: true) {
                Switch(isOn: $lan)
            }
            FootnoteRow(text: "实时同步至 mihomo · 启动时从 /configs 拉回")
        }
    }

    private var proxyAuth: some View {
        AdvSection(title: "代理认证") {
            AdvRow(icon: "person",
                   iconColor: ChungHwa.Palette.patina,
                   label: "用户名") {
                TextInputField(text: $authUser, placeholder: "可选")
            }
            AdvRow(icon: "key.horizontal",
                   iconColor: ChungHwa.Palette.brass,
                   label: "密码") {
                TextInputField(text: $authPass,
                               placeholder: "可选",
                               isSecure: !showPass,
                               mono: true) {
                    Button {
                        showPass.toggle()
                    } label: {
                        Image(systemName: showPass ? "eye.slash" : "eye")
                            .font(.system(size: 11))
                            .foregroundStyle(ChungHwa.Palette.faint)
                    }
                    .buttonStyle(.plain)
                }
            }
            // Footer note as a final non-row element inside the section card.
            HStack(alignment: .top, spacing: 0) {
                (Text("本地连接（")
                    + Text("127.0.0.0/8").font(ChungHwa.Typography.mono(10.5))
                    + Text("）默认绕过认证。"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(ChungHwa.Palette.faint)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(ChungHwa.Palette.lineSoft)
                    .frame(height: 0.5)
            }
        }
    }

    private var bypassList: some View {
        AdvSection(title: "绕过认证的 IP 段") {
            // Add row
            HStack(spacing: 8) {
                TextInputField(text: $newIp,
                               placeholder: "例如 198.18.0.0/16",
                               mono: true,
                               fillsWidth: true)
                Button(action: addIp) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus").font(.system(size: 11, weight: .semibold))
                        Text("添加").font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .frame(height: 24)
                    .background(ChungHwa.Palette.brass,
                                in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            ForEach(bypass) { entry in
                IpChip(entry: entry) {
                    if !entry.locked {
                        bypass.removeAll { $0.id == entry.id }
                        AdvancedView.saveBypass(bypass)
                    }
                }
            }
        }
    }

    // MARK: - Mutations

    private func addIp() {
        let trimmed = newIp.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        bypass.append(.init(ip: trimmed, tag: .custom, locked: false))
        AdvancedView.saveBypass(bypass)
        newIp = ""
    }

    // MARK: - Bypass persistence

    private static let bypassDefaultsKey = "ChungHwa.Advanced.BypassList"

    private static func defaultBypass() -> [BypassEntry] {
        [
            .init(ip: "127.0.0.0/8",    tag: .defaultTag, locked: true),
            .init(ip: "172.16.0.0/12",  tag: .defaultTag, locked: true),
            .init(ip: "10.0.0.0/8",     tag: .defaultTag, locked: true),
            .init(ip: "192.168.0.0/16", tag: .defaultTag, locked: true),
            .init(ip: "fd00::/8",       tag: .custom,     locked: false),
            .init(ip: "100.64.0.0/10",  tag: .tailscale,  locked: false),
        ]
    }

    private static func loadBypass() -> [BypassEntry] {
        guard let data = UserDefaults.standard.data(forKey: bypassDefaultsKey),
              let decoded = try? JSONDecoder().decode([BypassEntry].self, from: data)
        else { return defaultBypass() }
        return decoded
    }

    private static func saveBypass(_ list: [BypassEntry]) {
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: bypassDefaultsKey)
        }
    }
}

// MARK: - Bypass entry model

private struct BypassEntry: Identifiable, Codable, Hashable {
    enum Tag: String, Codable {
        case defaultTag = "default"
        case custom
        case tailscale

        var label: String {
            switch self {
            case .defaultTag: return "默认"
            case .custom:     return "自定义"
            case .tailscale:  return "Tailscale"
            }
        }

        var color: Color {
            switch self {
            case .defaultTag: return ChungHwa.Palette.patina
            case .custom:     return ChungHwa.Palette.brass
            case .tailscale:  return ChungHwa.Palette.brass
            }
        }
    }

    var id = UUID()
    var ip: String
    var tag: Tag
    var locked: Bool
}

// MARK: - FootnoteRow

/// Tiny faint caption that sits under a row inside an `AdvSection`. Lives
/// inside the section card and gets a thin top divider, matching the
/// hairline rule between regular rows.
private struct FootnoteRow: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(ChungHwa.Palette.lineSoft)
                .frame(height: 0.5)
            Text(text)
                .font(.system(size: 9.5))
                .foregroundStyle(ChungHwa.Palette.faint)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - AdvSection

private struct AdvSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(ChungHwa.Typography.serif(13, weight: .medium))
                .foregroundStyle(ChungHwa.Palette.dim)
                .tracking(-0.05)
                .padding(.horizontal, 4)
                .padding(.bottom, 8)

            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ChungHwa.Palette.card,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(ChungHwa.Palette.line, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.03), radius: 1, y: 1)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

// MARK: - AdvRow

private struct AdvRow<Trailing: View>: View {
    let icon: String?
    let iconColor: Color
    let label: String
    let sub: String?
    let last: Bool
    @ViewBuilder var trailing: Trailing

    init(icon: String? = nil,
         iconColor: Color = ChungHwa.Palette.patina,
         label: String,
         sub: String? = nil,
         last: Bool = false,
         @ViewBuilder trailing: () -> Trailing) {
        self.icon = icon
        self.iconColor = iconColor
        self.label = label
        self.sub = sub
        self.last = last
        self.trailing = trailing()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                if let icon {
                    ZStack {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(iconColor.opacity(0.094)) // 0x18 / 255
                        Image(systemName: icon)
                            .font(.system(size: 12))
                            .foregroundStyle(iconColor)
                    }
                    .frame(width: 22, height: 22)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(label)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(ChungHwa.Palette.text)
                    if let sub {
                        Text(sub)
                            .font(.system(size: 10.5))
                            .foregroundStyle(ChungHwa.Palette.faint)
                    }
                }
                Spacer(minLength: 8)
                HStack(spacing: 8) { trailing }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .frame(minHeight: 44)

            if !last {
                Rectangle()
                    .fill(ChungHwa.Palette.lineSoft)
                    .frame(height: 0.5)
            }
        }
    }
}

// MARK: - Switch

private struct Switch: View {
    @Binding var isOn: Bool
    var color: Color = ChungHwa.Palette.patina

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isOn ? color : Color(red: 14/255, green: 42/255, blue: 42/255).opacity(0.18))
                    .frame(width: 36, height: 20)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(isOn
                                          ? color
                                          : Color(red: 14/255, green: 42/255, blue: 42/255).opacity(0.10),
                                          lineWidth: 0.5)
                    )

                Circle()
                    .fill(.white)
                    .frame(width: 16, height: 16)
                    .shadow(color: .black.opacity(0.20), radius: 1, y: 1)
                    .padding(.horizontal, 2)
            }
            .animation(.easeInOut(duration: 0.16), value: isOn)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Stepper (real dropdown picker)

/// Actually a popup picker — keeps the original name to avoid touching the
/// call sites. Earlier this was a click-to-cycle button which gave no way to
/// jump straight to a specific option; now it's a Menu with `.fixedSize`
/// chrome matching the design.
private struct Stepper: View {
    @Binding var value: String
    let options: [(value: String, label: String)]

    var body: some View {
        Menu {
            ForEach(options, id: \.value) { opt in
                Button {
                    value = opt.value
                } label: {
                    if opt.value == value {
                        Label(opt.label, systemImage: "checkmark")
                    } else {
                        Text(opt.label)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(options.first(where: { $0.value == value })?.label ?? value)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(ChungHwa.Palette.text)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9))
                    .foregroundStyle(ChungHwa.Palette.faint)
            }
            .padding(.leading, 10)
            .padding(.trailing, 8)
            .frame(height: 24)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(ChungHwa.Palette.fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(ChungHwa.Palette.line, lineWidth: 0.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

// MARK: - TextInputField

private struct TextInputField<Trailing: View>: View {
    @Binding var text: String
    var placeholder: String = ""
    var isSecure: Bool = false
    var mono: Bool = false
    var fillsWidth: Bool = false
    @ViewBuilder var trailing: Trailing

    init(text: Binding<String>,
         placeholder: String = "",
         isSecure: Bool = false,
         mono: Bool = false,
         fillsWidth: Bool = false,
         @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self._text = text
        self.placeholder = placeholder
        self.isSecure = isSecure
        self.mono = mono
        self.fillsWidth = fillsWidth
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 4) {
            field
                .textFieldStyle(.plain)
                .font(mono ? ChungHwa.Typography.mono(11.5) : .system(size: 11.5))
                .foregroundStyle(ChungHwa.Palette.text)
                .frame(maxWidth: fillsWidth ? .infinity : nil)
            trailing
        }
        .padding(.horizontal, 8)
        .frame(width: fillsWidth ? nil : 180, height: 24)
        .frame(maxWidth: fillsWidth ? .infinity : nil)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(ChungHwa.Palette.fill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(ChungHwa.Palette.line, lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private var field: some View {
        if isSecure {
            SecureField(placeholder, text: $text)
        } else {
            TextField(placeholder, text: $text)
        }
    }
}

// MARK: - IpChip

private struct IpChip: View {
    let entry: BypassEntry
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(ChungHwa.Palette.lineSoft)
                .frame(height: 0.5)

            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(entry.tag.color.opacity(0.125)) // 0x20 / 255
                    Image(systemName: "shield")
                        .font(.system(size: 11))
                        .foregroundStyle(entry.tag.color)
                }
                .frame(width: 22, height: 22)

                Text(entry.ip)
                    .font(ChungHwa.Typography.mono(11.5))
                    .foregroundStyle(ChungHwa.Palette.text)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(entry.tag.label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(entry.tag.color)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(entry.tag.color.opacity(0.094))
                    )

                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(ChungHwa.Palette.faint)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .disabled(entry.locked)
                .opacity(entry.locked ? 0.35 : 1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
        }
    }
}

// MARK: - IconButton

private struct IconButton: View {
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11))
                .foregroundStyle(ChungHwa.Palette.dim)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
