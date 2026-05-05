import SwiftUI

// MARK: - DNSEditorSheet

/// Sheet for editing the upstream DNS resolver lists. Two ordered lists —
/// 主上游 (`nameserver`) and 兜底 (`fallback`) — each row a TextField + delete
/// button. Save trims whitespace, drops empties, persists via ConfigStore,
/// and (if the kernel is up) PATCH /configs.
struct DNSEditorSheet: View {
    @Environment(KernelController.self) private var kernel
    @Environment(ConfigStore.self) private var config
    @Environment(\.dismiss) private var dismiss

    @State private var nameservers: [Entry] = []
    @State private var fallback:    [Entry] = []
    @State private var isSaving = false

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    listSection(
                        title: "主上游",
                        entries: $nameservers
                    )
                    listSection(
                        title: "兜底",
                        entries: $fallback
                    )
                    formatHint
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
            }
            footer
        }
        .frame(width: 520, height: 540)
        .background(ChungHwa.Palette.bg)
        .task {
            self.nameservers = config.dnsNameservers.map { Entry(value: $0) }
            self.fallback = config.dnsFallback.map { Entry(value: $0) }
            if self.nameservers.isEmpty { self.nameservers = [Entry(value: "")] }
            if self.fallback.isEmpty { self.fallback = [Entry(value: "")] }
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "server.rack")
                .font(.system(size: 13))
                .foregroundStyle(ChungHwa.Palette.brass)
            Text("上游解析器")
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

    private func listSection(title: String, entries: Binding<[Entry]>) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(ChungHwa.Typography.serif(13, weight: .medium))
                .foregroundStyle(ChungHwa.Palette.dim)
                .tracking(-0.05)
                .padding(.horizontal, 4)
                .padding(.bottom, 8)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(entries) { $entry in
                    DNSRow(
                        entry: $entry,
                        onDelete: {
                            entries.wrappedValue.removeAll { $0.id == entry.id }
                            if entries.wrappedValue.isEmpty {
                                entries.wrappedValue = [Entry(value: "")]
                            }
                        }
                    )
                    if entry.id != entries.wrappedValue.last?.id {
                        Rectangle()
                            .fill(ChungHwa.Palette.lineSoft)
                            .frame(height: 0.5)
                    }
                }
                Rectangle()
                    .fill(ChungHwa.Palette.lineSoft)
                    .frame(height: 0.5)
                addButton {
                    entries.wrappedValue.append(Entry(value: ""))
                }
            }
            .background(ChungHwa.Palette.card,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(ChungHwa.Palette.line, lineWidth: 0.5))
        }
    }

    private func addButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                Text("添加")
                    .font(.system(size: 11.5, weight: .semibold))
            }
            .foregroundStyle(ChungHwa.Palette.brass)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var formatHint: some View {
        Text("https:// 是 DoH，tls:// 是 DoT，quic:// 是 DoQ，纯 IP 走 UDP")
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
            Button {
                Task { await save() }
            } label: {
                HStack(spacing: 5) {
                    if isSaving {
                        Image(systemName: "hourglass")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    Text(isSaving ? "保存中…" : "保存")
                        .font(.system(size: 11.5, weight: .semibold))
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .keyboardShortcut(.defaultAction)
            .disabled(isSaving)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(ChungHwa.Palette.line)
                .frame(height: 0.5)
        }
    }

    // MARK: - Save

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let ns = nameservers.map { $0.value }
        let fb = fallback.map { $0.value }
        await config.setDNS(nameservers: ns, fallback: fb, api: kernel.apiClient)
        // PATCH /configs 对 dns 子树的覆盖不彻底（且 user yaml 自带 dns
        // 时我们根本不注入），reload 让新 nameserver / fallback 通过
        // ConfigComposer 重新落盘后即刻应用。
        await kernel.reload()
        dismiss()
    }
}

// MARK: - Entry

private struct Entry: Identifiable, Equatable {
    let id = UUID()
    var value: String
}

// MARK: - DNSRow

private struct DNSRow: View {
    @Binding var entry: Entry
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            TextField("https://… 或 tls://… 或 1.1.1.1", text: $entry.value)
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
}

// MARK: - Button styles

private struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
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
