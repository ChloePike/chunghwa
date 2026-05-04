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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                kernelLogs
                connectionOptimization
                dns
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
        .navigationTitle("Advanced")
        // Live-push to mihomo whenever the user flips the wired settings.
        // The @AppStorage value is the source of truth for the UI; the
        // store does an optimistic update + rollback against /configs.
        .onChange(of: logLevel) { _, newValue in
            Task { await config.setLogLevel(newValue, api: kernel.apiClient) }
        }
        .onChange(of: lan) { _, newValue in
            Task { await config.setAllowLan(newValue, api: kernel.apiClient) }
        }
    }

    // MARK: - Sections

    private var kernelLogs: some View {
        AdvSection(title: "Kernel logs") {
            AdvRow(icon: "list.bullet",
                   iconColor: ChungHwa.Palette.brass,
                   label: "Log level",
                   sub: "Verbose output is written to ~/Library/Logs/ChungHwa") {
                Stepper(value: $logLevel, options: [
                    ("silent",  "Silent"),
                    ("error",   "Error"),
                    ("warning", "Warning"),
                    ("info",    "Info"),
                    ("debug",   "Debug"),
                ])
            }
            FootnoteRow(text: "Pushed to mihomo at runtime · synced from /configs on kernel start")
            AdvRow(icon: "doc.text",
                   iconColor: ChungHwa.Palette.patina,
                   label: "View kernel log",
                   last: true) {
                IconButton(systemName: "arrow.up.forward") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Utilities/Console.app"))
                }
            }
        }
    }

    private var connectionOptimization: some View {
        AdvSection(title: "Connection optimization") {
            AdvRow(icon: "arrow.triangle.2.circlepath",
                   iconColor: ChungHwa.Palette.patina,
                   label: "Unified delay test",
                   sub: "Requires kernel restart") {
                Switch(isOn: $unifiedDelay)
            }
            AdvRow(icon: "link",
                   iconColor: ChungHwa.Palette.brass,
                   label: "TCP concurrent connections",
                   sub: "Open multiple TCP streams to the chosen node") {
                Switch(isOn: $tcpConcurrent)
            }
            AdvRow(icon: "globe",
                   iconColor: ChungHwa.Palette.patina,
                   label: "IPv6 support") {
                Switch(isOn: $ipv6)
            }
            AdvRow(icon: "cube",
                   iconColor: ChungHwa.Palette.brass,
                   label: "Disable QUIC",
                   sub: "Some networks throttle QUIC; falling back to TCP improves stability",
                   last: true) {
                Stepper(value: $quic, options: [
                    ("off", "Never"),
                    ("ext", "Outside LAN only"),
                    ("all", "Always"),
                ])
            }
            FootnoteRow(text: "Local — restart mihomo to apply")
        }
    }

    private var dns: some View {
        AdvSection(title: "DNS") {
            AdvRow(icon: "arrow.left.arrow.right",
                   iconColor: ChungHwa.Palette.patina,
                   label: "Resolution mode",
                   sub: "Smart routes domestic to system, foreign to fake-ip") {
                Stepper(value: $dnsMode, options: [
                    ("system",  "System"),
                    ("smart",   "Smart"),
                    ("fake-ip", "Fake-IP"),
                ])
            }
            AdvRow(icon: "shield",
                   iconColor: ChungHwa.Palette.brass,
                   label: "Hijack port 53",
                   sub: "Capture all DNS traffic on the system") {
                Switch(isOn: $dnsHijack)
            }
            AdvRow(icon: "network",
                   iconColor: ChungHwa.Palette.patina,
                   label: "Upstream resolvers",
                   sub: "One per line; supports DoH, DoT, DoQ",
                   last: true) {
                Text("4 active")
                    .font(ChungHwa.Typography.mono(11))
                    .foregroundStyle(ChungHwa.Palette.dim)
                IconButton(systemName: "chevron.right") { /* no-op */ }
            }
            FootnoteRow(text: "Local — restart mihomo to apply")
        }
    }

    private var lanInbound: some View {
        AdvSection(title: "LAN inbound") {
            AdvRow(icon: "network",
                   iconColor: lan ? ChungHwa.Palette.brass : ChungHwa.Palette.patina,
                   label: "Allow connections from local network",
                   sub: lan
                        ? "Other devices can use this Mac as a gateway"
                        : "Only this Mac can connect to the proxy",
                   last: true) {
                Switch(isOn: $lan)
            }
            FootnoteRow(text: "Pushed to mihomo at runtime · synced from /configs on kernel start")
        }
    }

    private var proxyAuth: some View {
        AdvSection(title: "Proxy authentication") {
            AdvRow(icon: "shield",
                   iconColor: ChungHwa.Palette.patina,
                   label: "Username") {
                TextInputField(text: $authUser, placeholder: "optional")
            }
            AdvRow(icon: "shield",
                   iconColor: ChungHwa.Palette.brass,
                   label: "Password") {
                TextInputField(text: $authPass,
                               placeholder: "optional",
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
                (Text("Local connections (")
                    + Text("127.0.0.0/8").font(ChungHwa.Typography.mono(10.5))
                    + Text(") bypass authentication by default."))
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
        AdvSection(title: "IP ranges that bypass authentication") {
            // Add row
            HStack(spacing: 8) {
                TextInputField(text: $newIp,
                               placeholder: "e.g. 198.18.0.0/16",
                               mono: true,
                               fillsWidth: true)
                Button(action: addIp) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus").font(.system(size: 11, weight: .semibold))
                        Text("Add").font(.system(size: 11, weight: .semibold))
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
            case .defaultTag: return "Default"
            case .custom:     return "Custom"
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

// MARK: - Stepper (cycles through fixed options)

private struct Stepper: View {
    @Binding var value: String
    let options: [(value: String, label: String)]

    var body: some View {
        Button {
            let i = options.firstIndex(where: { $0.value == value }) ?? -1
            value = options[(i + 1) % options.count].value
        } label: {
            HStack(spacing: 6) {
                Text(options.first(where: { $0.value == value })?.label ?? value)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(ChungHwa.Palette.text)
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
        }
        .buttonStyle(.plain)
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
