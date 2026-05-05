import SwiftUI

/// Custom-routing-rules editor. Composer splices these in ABOVE the
/// subscription's own rules so they match first.
struct RoutingEditor: View {
    @Environment(ConfigStore.self) private var config
    @Environment(ProxyStore.self) private var proxyStore
    @Environment(KernelController.self) private var kernel
    @Environment(\.dismiss) private var dismiss

    @State private var rows: [Row] = []

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    rulesList
                    addButton
                    hint
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
            }
            footer
        }
        .frame(width: 620, height: 560)
        .background(ChungHwa.Palette.bg)
        .task {
            self.rows = config.customRules.map { Row(from: $0) }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 13))
                .foregroundStyle(ChungHwa.Palette.brass)
            Text("自定义路由")
                .font(ChungHwa.Typography.serif(15, weight: .semibold))
                .foregroundStyle(ChungHwa.Palette.text)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 10)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(ChungHwa.Palette.line)
                .frame(height: 0.5)
        }
    }

    private var rulesList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("类型").frame(width: 130, alignment: .leading)
                Text("匹配值").frame(maxWidth: .infinity, alignment: .leading)
                Text("目标").frame(width: 130, alignment: .leading)
                Color.clear.frame(width: 22)
            }
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(ChungHwa.Palette.dim)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(ChungHwa.Palette.lineSoft)
                    .frame(height: 0.5)
            }

            if rows.isEmpty {
                Text("还没有规则")
                    .font(.system(size: 11))
                    .foregroundStyle(ChungHwa.Palette.faint)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 22)
            } else {
                ForEach($rows) { $row in
                    RuleRow(
                        row: $row,
                        groups: groupNames,
                        onDelete: {
                            rows.removeAll { $0.id == row.id }
                        }
                    )
                    if row.id != rows.last?.id {
                        Rectangle()
                            .fill(ChungHwa.Palette.lineSoft)
                            .frame(height: 0.5)
                    }
                }
            }
        }
        .background(ChungHwa.Palette.card,
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(ChungHwa.Palette.line, lineWidth: 0.5))
    }

    private var addButton: some View {
        Button {
            rows.append(Row(type: .domainSuffix, value: "", target: "DIRECT"))
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                Text("添加规则")
                    .font(.system(size: 11.5, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(ChungHwa.Palette.brass)
            )
        }
        .buttonStyle(.plain)
    }

    private var hint: some View {
        Text("规则按顺序匹配；优先于订阅自带规则。")
            .font(.system(size: 10.5))
            .foregroundStyle(ChungHwa.Palette.faint)
            .padding(.horizontal, 4)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            Button("取消") { dismiss() }
                .buttonStyle(SecondaryButtonStyle())
                .keyboardShortcut(.cancelAction)
            Button("保存") { save() }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(ChungHwa.Palette.line)
                .frame(height: 0.5)
        }
    }

    private var groupNames: [String] {
        proxyStore.groupOrder
    }

    private func save() {
        let cleaned: [CustomRule] = rows.compactMap { row in
            let value = row.value.trimmingCharacters(in: .whitespaces)
            let target = row.target.trimmingCharacters(in: .whitespaces)
            guard !value.isEmpty, !target.isEmpty else { return nil }
            let match = "\(row.type.rawValue),\(value)"
            return CustomRule(match: match, target: target)
        }
        config.setCustomRules(cleaned)
        // Rules live in the yaml — persisted preference alone wouldn't take
        // effect until the user manually reloaded. Kick a hot reload so the
        // newly composed yaml is applied right away.
        Task { await kernel.reload() }
        dismiss()
    }
}

private struct Row: Identifiable, Equatable {
    let id = UUID()
    var type: RuleType
    var value: String
    var target: String

    init(type: RuleType, value: String, target: String) {
        self.type = type
        self.value = value
        self.target = target
    }

    /// Decode an existing CustomRule (which stores the canonical "TYPE,value"
    /// form) back into the editable triple.
    init(from rule: CustomRule) {
        let parts = rule.match.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false)
        let type = parts.first.map(String.init) ?? "DOMAIN-SUFFIX"
        let value = parts.count > 1 ? String(parts[1]) : ""
        self.type = RuleType(rawValue: type) ?? .domainSuffix
        self.value = value
        self.target = rule.target
    }
}

private enum RuleType: String, CaseIterable, Identifiable {
    case domainSuffix  = "DOMAIN-SUFFIX"
    case domainKeyword = "DOMAIN-KEYWORD"
    case domain        = "DOMAIN"
    case ipCIDR        = "IP-CIDR"
    case geoIP         = "GEOIP"
    case processName   = "PROCESS-NAME"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .domainSuffix:  return "域名后缀"
        case .domainKeyword: return "域名关键字"
        case .domain:        return "域名"
        case .ipCIDR:        return "IP-CIDR"
        case .geoIP:         return "GeoIP"
        case .processName:   return "进程名"
        }
    }

    var placeholder: String {
        switch self {
        case .domainSuffix:  return "example.com"
        case .domainKeyword: return "google"
        case .domain:        return "example.com"
        case .ipCIDR:        return "192.168.0.0/16"
        case .geoIP:         return "CN"
        case .processName:   return "Telegram"
        }
    }
}

private struct RuleRow: View {
    @Binding var row: Row
    let groups: [String]
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            typeMenu
                .frame(width: 130, alignment: .leading)

            TextField(row.type.placeholder, text: $row.value)
                .textFieldStyle(.plain)
                .font(ChungHwa.Typography.mono(11.5))
                .foregroundStyle(ChungHwa.Palette.text)
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(ChungHwa.Palette.fill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(ChungHwa.Palette.line, lineWidth: 0.5)
                )
                .frame(maxWidth: .infinity)

            targetMenu
                .frame(width: 130, alignment: .leading)

            Button(action: onDelete) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ChungHwa.Palette.faint)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var typeMenu: some View {
        Menu {
            ForEach(RuleType.allCases) { t in
                Button {
                    row.type = t
                } label: {
                    if t == row.type {
                        Label(t.displayName, systemImage: "checkmark")
                    } else {
                        Text(t.displayName)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(row.type.displayName)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(ChungHwa.Palette.text)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9))
                    .foregroundStyle(ChungHwa.Palette.faint)
            }
            .padding(.leading, 9)
            .padding(.trailing, 7)
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
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private var targetMenu: some View {
        Menu {
            ForEach(["DIRECT", "PROXY", "REJECT"], id: \.self) { t in
                Button {
                    row.target = t
                } label: {
                    if t == row.target {
                        Label(t, systemImage: "checkmark")
                    } else {
                        Text(t)
                    }
                }
            }
            if !groups.isEmpty {
                Divider()
                Section("代理组") {
                    ForEach(groups, id: \.self) { name in
                        Button {
                            row.target = name
                        } label: {
                            if name == row.target {
                                Label(name, systemImage: "checkmark")
                            } else {
                                Text(name)
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(row.target.isEmpty ? "选择" : row.target)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(ChungHwa.Palette.text)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9))
                    .foregroundStyle(ChungHwa.Palette.faint)
            }
            .padding(.leading, 9)
            .padding(.trailing, 7)
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
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

private struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(configuration.isPressed
                          ? ChungHwa.Palette.brass.opacity(0.78)
                          : ChungHwa.Palette.brass)
            )
    }
}

private struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(ChungHwa.Palette.text)
            .padding(.horizontal, 12)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(configuration.isPressed
                          ? ChungHwa.Palette.fillStrong
                          : ChungHwa.Palette.fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(ChungHwa.Palette.line, lineWidth: 0.5)
            )
    }
}
