import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Profiles tab — file/URL imports, storage selector, and per-profile cards.
/// Designed to the "Bone & Brass on Patina" tokens; see `Core/Design/`.
struct ProfilesView: View {
    @Environment(ProfileStore.self) private var store

    @State private var showImportURL = false
    @State private var urlText = ""
    @State private var urlName = ""

    @State private var pendingDelete: Profile?
    @State private var importError: String?
    @State private var isTargeted = false
    @State private var inspecting: Profile?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                autoRefreshRow
                storageRow
                if let importError {
                    errorBanner(importError)
                }
                if store.profiles.isEmpty {
                    emptyState
                        .frame(maxWidth: .infinity)
                        .padding(.top, 48)
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(store.profiles) { profile in
                            ProfileCard(
                                profile: profile,
                                isActive: profile.id == store.activeProfileID,
                                onActivate: { store.activate(profile.id) },
                                onRefresh: {
                                    Task { try? await store.refresh(profile.id) }
                                },
                                onInspect: { inspecting = profile },
                                onRequestDelete: { pendingDelete = profile }
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(ChungHwa.Palette.bg)
        .onDrop(of: [.fileURL, .url, .text], isTargeted: $isTargeted) { providers in
            handleDrop(providers: providers)
        }
        .overlay {
            if isTargeted {
                dropIndicator
                    .allowsHitTesting(false)
            }
        }
        .sheet(isPresented: $showImportURL) {
            ImportURLSheet(
                urlText: $urlText,
                urlName: $urlName,
                onCancel: { closeImportURL() },
                onSubmit: submitImportURL
            )
        }
        .sheet(item: $inspecting) { profile in
            YAMLInspectorSheet(
                profile: profile,
                yaml: store.yamlContent(for: profile.id),
                yamlURL: store.yamlURL(for: profile.id),
                onClose: { inspecting = nil }
            )
        }
        .alert(
            "删除这份配置？",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            presenting: pendingDelete
        ) { p in
            Button("取消", role: .cancel) { pendingDelete = nil }
            Button("删除", role: .destructive) {
                try? store.remove(p.id)
                pendingDelete = nil
            }
        } message: { p in
            Text("「\(p.name)」会被移除，无法恢复。")
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("配置")
                    .font(ChungHwa.Typography.serif(20, weight: .semibold))
                    .foregroundStyle(ChungHwa.Palette.text)
                    .tracking(-0.3)
                Text("\(store.profiles.count) 份")
                    .font(.system(size: 11.5))
                    .foregroundStyle(ChungHwa.Palette.dim)
            }
            Spacer(minLength: 12)
            HStack(spacing: 8) {
                BrassButton(title: "导入文件…", systemImage: "doc.badge.plus") {
                    pickFile()
                }
                GhostButton(title: "从 URL…", systemImage: "link.badge.plus") {
                    showImportURL = true
                }
            }
        }
    }

    // MARK: - Auto-refresh row

    private var hasURLProfiles: Bool {
        store.profiles.contains { p in
            if case .url = p.source { return true }
            return false
        }
    }

    private var autoRefreshBinding: Binding<Double> {
        Binding(
            get: { store.autoRefreshHours },
            set: { store.autoRefreshHours = $0 }
        )
    }

    private var autoRefreshLabel: String {
        let h = store.autoRefreshHours
        if h <= 0 { return "关闭" }
        if h < 1 { return String(format: "%.1f 小时", h) }
        return "\(Int(h)) 小时"
    }

    private var lastRefreshLabel: String {
        guard let last = store.lastAutoRefresh else { return "未拉取过" }
        let elapsed = Date.now.timeIntervalSince(last)
        if elapsed < 60 { return "刚刚" }
        let m = Int(elapsed / 60)
        if m < 60 { return "\(m) 分钟前" }
        let h = m / 60
        if h < 24 { return "\(h) 小时前" }
        let d = h / 24
        return "\(d) 天前"
    }

    private var autoRefreshRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 11))
                    .foregroundStyle(ChungHwa.Palette.dim)
                Text("自动拉取")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(ChungHwa.Palette.dim)
                Text(autoRefreshLabel)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(ChungHwa.Palette.text)
                    .frame(minWidth: 44, alignment: .leading)
                    .monospacedDigit()
                Stepper("", value: autoRefreshBinding, in: 0...168, step: 1)
                    .labelsHidden()
                Spacer(minLength: 8)
                GhostButton(title: "立即拉取", systemImage: "arrow.clockwise") {
                    Task { await store.refreshAll() }
                }
                .opacity(hasURLProfiles ? 1 : 0.4)
                .allowsHitTesting(hasURLProfiles)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(ChungHwa.Palette.cardSoft)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(ChungHwa.Palette.lineSoft, lineWidth: 0.5)
            )

            Text("上次拉取 \(lastRefreshLabel)")
                .font(.system(size: 10))
                .foregroundStyle(ChungHwa.Palette.faint)
                .padding(.leading, 14)
        }
    }

    private var storageRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "internaldrive")
                .font(.system(size: 11))
                .foregroundStyle(ChungHwa.Palette.dim)
            Text("存储")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(ChungHwa.Palette.dim)
            Spacer(minLength: 8)
            ChSeg(
                value: store.storageMode,
                onChange: { mode in
                    Task {
                        do { try await store.setStorageMode(mode) }
                        catch { importError = String(describing: error) }
                    }
                },
                options: storageOptions
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(ChungHwa.Palette.cardSoft)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(ChungHwa.Palette.lineSoft, lineWidth: 0.5)
        )
    }

    /// `ChSeg` doesn't speak "disabled option" so we mark unavailable iCloud
    /// by leaving its tap a no-op (handled in onChange via try/catch above).
    private var storageOptions: [(value: ProfileStore.StorageMode, label: String)] {
        let cloudLabel = store.iCloudDriveAvailable ? "iCloud Drive" : "iCloud（未开启）"
        return [
            (.appSupport, "本地"),
            (.iCloudDrive, cloudLabel),
        ]
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(ChungHwa.Palette.faint)
            Text("还没有配置")
                .font(ChungHwa.Typography.serif(16, weight: .medium))
                .foregroundStyle(ChungHwa.Palette.text)
            Text("导入一个 YAML 或粘贴订阅链接。")
                .font(.system(size: 12))
                .foregroundStyle(ChungHwa.Palette.dim)
        }
    }

    private func errorBanner(_ msg: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(ChungHwa.Palette.earth)
            Text(msg)
                .font(.system(size: 11.5))
                .foregroundStyle(ChungHwa.Palette.text)
                .lineLimit(3)
            Spacer()
            Button {
                importError = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(ChungHwa.Palette.dim)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(ChungHwa.Palette.earth.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .strokeBorder(ChungHwa.Palette.earth.opacity(0.30), lineWidth: 0.5)
        )
    }

    // MARK: - Drop indicator

    private var dropIndicator: some View {
        ZStack {
            ChungHwa.Palette.bg.opacity(0.55)
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(
                    ChungHwa.Palette.brass.opacity(0.5),
                    style: StrokeStyle(lineWidth: 2, dash: [8, 4])
                )
                .padding(10)
            Text("拖到这里")
                .font(ChungHwa.Typography.serif(16, weight: .medium))
                .foregroundStyle(ChungHwa.Palette.text)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(ChungHwa.Palette.card)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(ChungHwa.Palette.brass.opacity(0.5), lineWidth: 0.8)
                )
        }
    }

    // MARK: - Drop handling

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard !providers.isEmpty else { return false }
        var handled = false
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                handled = true
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    let url = urlFromItem(item)
                    guard let url, url.isFileURL else { return }
                    let ext = url.pathExtension.lowercased()
                    guard ext == "yaml" || ext == "yml" else { return }
                    DispatchQueue.main.async {
                        try? store.addFile(at: url, name: nil)
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                handled = true
                provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, _ in
                    guard let url = urlFromItem(item), !url.isFileURL,
                          let scheme = url.scheme?.lowercased(),
                          scheme == "http" || scheme == "https"
                    else { return }
                    DispatchQueue.main.async {
                        Task { try? await store.addURL(url, name: nil) }
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.text.identifier) {
                handled = true
                provider.loadItem(forTypeIdentifier: UTType.text.identifier, options: nil) { item, _ in
                    let text: String?
                    if let s = item as? String { text = s }
                    else if let d = item as? Data { text = String(data: d, encoding: .utf8) }
                    else { text = nil }
                    guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines),
                          !trimmed.isEmpty,
                          let url = URL(string: trimmed),
                          let scheme = url.scheme?.lowercased(),
                          scheme == "http" || scheme == "https"
                    else { return }
                    DispatchQueue.main.async {
                        Task { try? await store.addURL(url, name: nil) }
                    }
                }
            }
        }
        return handled
    }

    private func urlFromItem(_ item: NSSecureCoding?) -> URL? {
        if let url = item as? URL { return url }
        if let data = item as? Data {
            if let url = URL(dataRepresentation: data, relativeTo: nil) { return url }
            if let s = String(data: data, encoding: .utf8),
               let url = URL(string: s.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return url
            }
        }
        if let s = item as? String,
           let url = URL(string: s.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return url
        }
        return nil
    }

    // MARK: - Actions

    private func pickFile() {
        let panel = NSOpenPanel()
        panel.title = "选择 YAML"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        var types: [UTType] = [.yaml]
        if let yml = UTType(filenameExtension: "yml") { types.append(yml) }
        types.append(contentsOf: [.text, .plainText, .data])
        panel.allowedContentTypes = types
        if panel.runModal() == .OK, let url = panel.url {
            do {
                _ = try store.addFile(at: url)
                importError = nil
            } catch {
                importError = String(describing: error)
            }
        }
    }

    private func submitImportURL() {
        guard let url = URL(string: urlText.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme != nil
        else { return }
        let trimmedName = urlName.trimmingCharacters(in: .whitespaces)
        let nameOpt = trimmedName.isEmpty ? nil : trimmedName
        Task {
            do {
                _ = try await store.addURL(url, name: nameOpt)
                importError = nil
                closeImportURL()
            } catch {
                importError = String(describing: error)
                closeImportURL()
            }
        }
    }

    private func closeImportURL() {
        showImportURL = false
        urlText = ""
        urlName = ""
    }
}

// MARK: - Profile card

private struct ProfileCard: View {
    let profile: Profile
    let isActive: Bool
    let onActivate: () -> Void
    let onRefresh: () -> Void
    let onInspect: () -> Void
    let onRequestDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            sourceIcon
            VStack(alignment: .leading, spacing: 6) {
                titleRow
                metaRow
                if case .url(let url) = profile.source, let host = url.host {
                    Text(host)
                        .font(ChungHwa.Typography.mono(11))
                        .foregroundStyle(ChungHwa.Palette.faint)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 8)
            actionCluster
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isActive
                      ? ChungHwa.Palette.brass.opacity(0.08)
                      : ChungHwa.Palette.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    isActive ? ChungHwa.Palette.brass.opacity(0.55) : ChungHwa.Palette.line,
                    lineWidth: isActive ? 1 : 0.5
                )
        )
        .shadow(color: .black.opacity(isActive ? 0.04 : 0.03), radius: 1, y: 1)
    }

    private var sourceIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(ChungHwa.Palette.fill)
            Image(systemName: profile.source.subscriptionURL == nil ? "doc.text" : "link")
                .font(.system(size: 14))
                .foregroundStyle(ChungHwa.Palette.dim)
        }
        .frame(width: 32, height: 32)
    }

    private var titleRow: some View {
        HStack(spacing: 8) {
            Text(profile.name)
                .font(ChungHwa.Typography.serif(16, weight: .semibold))
                .foregroundStyle(ChungHwa.Palette.text)
                .tracking(-0.2)
            sourceBadge
            if isActive { activeBadge }
        }
    }

    private var sourceBadge: some View {
        Text(profile.source.displayName.uppercased())
            .font(.system(size: 9.5, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(ChungHwa.Palette.dim)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(
                Capsule().fill(ChungHwa.Palette.fill)
            )
            .overlay(
                Capsule().strokeBorder(ChungHwa.Palette.lineSoft, lineWidth: 0.5)
            )
    }

    private var activeBadge: some View {
        HStack(spacing: 4) {
            ChDot(color: ChungHwa.Palette.brass, size: 5, pulse: false)
            Text("使用中")
                .font(.system(size: 9.5, weight: .bold))
                .tracking(0.7)
                .foregroundStyle(ChungHwa.Palette.brassDark)
        }
        .padding(.horizontal, 7).padding(.vertical, 2)
        .background(Capsule().fill(ChungHwa.Palette.brass.opacity(0.18)))
    }

    private var metaRow: some View {
        HStack(spacing: 6) {
            Text("导入")
                .font(.system(size: 11))
                .foregroundStyle(ChungHwa.Palette.dim)
            RelativeDateText(date: profile.importedAt)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(ChungHwa.Palette.text)
            Text("·")
                .font(.system(size: 11))
                .foregroundStyle(ChungHwa.Palette.faint)
            Text("更新")
                .font(.system(size: 11))
                .foregroundStyle(ChungHwa.Palette.dim)
            RelativeDateText(date: profile.updatedAt)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(ChungHwa.Palette.text)
        }
    }

    private var actionCluster: some View {
        HStack(spacing: 6) {
            if isActive {
                BadgeButton(title: "使用中", systemImage: "checkmark", enabled: false) {}
            } else {
                BadgeButton(title: "启用", systemImage: "play.fill", enabled: true, action: onActivate)
            }
            if profile.source.subscriptionURL != nil {
                IconBadgeButton(systemImage: "arrow.clockwise",
                                tint: ChungHwa.Palette.dim,
                                help: "拉取订阅",
                                action: onRefresh)
            }
            GhostMiniButton(title: "查看",
                            systemImage: "doc.text.magnifyingglass",
                            help: "查看 YAML",
                            action: onInspect)
            IconBadgeButton(systemImage: "trash",
                            tint: ChungHwa.Palette.earth,
                            help: "删除",
                            action: onRequestDelete)
        }
    }
}

// MARK: - View YAML mini-button

private struct GhostMiniButton: View {
    let title: String
    let systemImage: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 9.5, weight: .medium))
                Text(title)
                    .font(.system(size: 11.5, weight: .medium))
            }
            .foregroundStyle(ChungHwa.Palette.text)
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(ChungHwa.Palette.pillBg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(ChungHwa.Palette.line, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

// MARK: - Buttons (local)

private struct BrassButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage).font(.system(size: 10.5, weight: .semibold))
                Text(title).font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(ChungHwa.Palette.ink)
            .padding(.horizontal, 11)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(ChungHwa.Palette.brass)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(ChungHwa.Palette.brassDark.opacity(0.55), lineWidth: 0.5)
            )
            .shadow(color: ChungHwa.Palette.brassDark.opacity(0.20), radius: 1, y: 1)
        }
        .buttonStyle(.plain)
    }
}

private struct GhostButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage).font(.system(size: 10.5, weight: .medium))
                Text(title).font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(ChungHwa.Palette.text)
            .padding(.horizontal, 11)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(ChungHwa.Palette.pillBg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(ChungHwa.Palette.line, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct BadgeButton: View {
    let title: String
    let systemImage: String
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 9.5, weight: .semibold))
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))
            }
            .foregroundStyle(enabled ? ChungHwa.Palette.text : ChungHwa.Palette.dim)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(enabled ? ChungHwa.Palette.pillBg : ChungHwa.Palette.fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(ChungHwa.Palette.line, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

private struct IconBadgeButton: View {
    let systemImage: String
    let tint: Color
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(ChungHwa.Palette.pillBg)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(ChungHwa.Palette.line, lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

// MARK: - Import URL sheet

private struct ImportURLSheet: View {
    @Binding var urlText: String
    @Binding var urlName: String
    let onCancel: () -> Void
    let onSubmit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("从 URL 导入")
                .font(ChungHwa.Typography.serif(17, weight: .semibold))
                .foregroundStyle(ChungHwa.Palette.text)

            VStack(alignment: .leading, spacing: 4) {
                Text("URL")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ChungHwa.Palette.dim)
                TextField("https://example.com/subscription", text: $urlText)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("名称（可留空）")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ChungHwa.Palette.dim)
                TextField("起个名字", text: $urlName)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Spacer()
                Button("取消", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("导入", action: onSubmit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValidURL)
            }
        }
        .padding(20)
        .frame(width: 440)
        .background(ChungHwa.Palette.card)
    }

    private var isValidURL: Bool {
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else { return false }
        return true
    }
}

// MARK: - Relative date

private struct RelativeDateText: View {
    let date: Date

    var body: some View {
        Text(format(date))
    }

    private func format(_ d: Date) -> String {
        let elapsed = Date.now.timeIntervalSince(d)
        if elapsed < 0 { return "刚刚" }
        let s = Int(elapsed)
        switch s {
        case ..<5:
            return "刚刚"
        case ..<60:
            return "\(s) 秒前"
        case ..<3_600:
            let m = s / 60
            return "\(m) 分钟前"
        case ..<86_400:
            let h = s / 3600
            return "\(h) 小时前"
        case ..<(86_400 * 7):
            let dys = s / 86_400
            return "\(dys) 天前"
        case ..<(86_400 * 30):
            let w = s / (86_400 * 7)
            return "\(w) 周前"
        case ..<(86_400 * 365):
            let mo = s / (86_400 * 30)
            return "\(mo) 个月前"
        default:
            let y = s / (86_400 * 365)
            return "\(y) 年前"
        }
    }
}

// MARK: - YAML inspector sheet

private struct YAMLInspectorSheet: View {
    let profile: Profile
    let yaml: String?
    let yamlURL: URL
    let onClose: () -> Void

    @Environment(ProfileStore.self) private var store
    @Environment(KernelController.self) private var kernel

    @State private var copyHint: String?
    @State private var isEditing: Bool = false
    @State private var editedContent: String = ""
    /// Read-mode display content. Initialized from `yaml`; refreshed after a
    /// successful save so the highlighted view shows the new bytes without
    /// having to close & reopen the sheet.
    @State private var displayContent: String?
    /// Cached highlighted version of `displayContent`. Recomputed off the
    /// main thread whenever `displayContent` changes; nil while a recompute
    /// is in flight (we render plain text in the meantime).
    @State private var highlighted: AttributedString?
    /// YAML files larger than this skip the AttributedString highlighter
    /// entirely — past ~100KB the per-line `out.append` path hits an O(N²)
    /// wall in AttributedString and freezes the main thread.
    private let highlightCap = 100_000
    /// Brief "Saved." / "Reloading mihomo…" status message shown after a save.
    @State private var saveStatus: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            titleBar
            Divider().background(ChungHwa.Palette.lineSoft)
            sourceLine
            bodyArea
            footerLine
            Divider().background(ChungHwa.Palette.lineSoft)
            bottomButtons
        }
        .frame(minWidth: 720, idealWidth: 720, minHeight: 600, idealHeight: 600)
        .background(ChungHwa.Palette.card)
        .onAppear {
            displayContent = yaml
            editedContent = yaml ?? ""
        }
        .task(id: displayContent ?? "") {
            await rehighlight()
        }
    }

    /// Recompute the syntax-highlighted AttributedString off the main thread
    /// and cache it. Skipped for files past `highlightCap` (renders as plain
    /// text instead).
    private func rehighlight() async {
        guard let content = displayContent, !content.isEmpty else {
            highlighted = nil
            return
        }
        if content.utf8.count > highlightCap {
            highlighted = nil
            return
        }
        let attr = await Task.detached(priority: .userInitiated) {
            YAMLHighlighter.highlight(content)
        }.value
        // Only commit if displayContent didn't change underneath us.
        if displayContent == content {
            highlighted = attr
        }
    }

    // MARK: title

    private var titleBar: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(profile.name)
                .font(ChungHwa.Typography.serif(18, weight: .semibold))
                .foregroundStyle(ChungHwa.Palette.text)
                .tracking(-0.2)
            Spacer(minLength: 8)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ChungHwa.Palette.dim)
                    .frame(width: 24, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            .fill(ChungHwa.Palette.pillBg)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .strokeBorder(ChungHwa.Palette.line, lineWidth: 0.5)
                    )
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help("关闭")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    // MARK: source line

    private var sourceLine: some View {
        HStack(spacing: 6) {
            Text(sourceTag)
                .font(ChungHwa.Typography.mono(11))
                .foregroundStyle(ChungHwa.Palette.dim)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(
                    Capsule().fill(ChungHwa.Palette.fill)
                )
                .overlay(
                    Capsule().strokeBorder(ChungHwa.Palette.lineSoft, lineWidth: 0.5)
                )
            Spacer(minLength: 0)
            if let saveStatus {
                Text(saveStatus)
                    .font(.system(size: 11))
                    .foregroundStyle(ChungHwa.Palette.brass)
                    .transition(.opacity)
            }
            if let copyHint {
                Text(copyHint)
                    .font(.system(size: 11))
                    .foregroundStyle(ChungHwa.Palette.patina)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private var sourceTag: String {
        switch profile.source {
        case .file:
            return "本地文件"
        case .url(let url):
            return url.host ?? url.absoluteString
        }
    }

    // MARK: body

    @ViewBuilder
    private var bodyArea: some View {
        if isEditing {
            // TextEditor doesn't support AttributedString styling, so we lose
            // syntax highlighting in edit mode; we keep the same mono font and
            // soft card background so the visual change is minimal.
            TextEditor(text: $editedContent)
                .font(ChungHwa.Typography.mono(11))
                .foregroundStyle(ChungHwa.Palette.text)
                .scrollContentBackground(.hidden)
                .background(ChungHwa.Palette.cardSoft)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(ChungHwa.Palette.lineSoft, lineWidth: 0.5)
                )
                .padding(.horizontal, 18)
        } else if let displayContent {
            ScrollView([.vertical, .horizontal]) {
                Group {
                    if let highlighted {
                        Text(highlighted)
                    } else {
                        // Either the highlighter is still running, or the
                        // file's too big for it (highlightCap). Render as
                        // plain mono text so the sheet stays responsive.
                        Text(displayContent)
                            .foregroundStyle(ChungHwa.Palette.text)
                    }
                }
                .textSelection(.enabled)
                .font(ChungHwa.Typography.mono(11))
                .lineSpacing(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
            }
            .background(ChungHwa.Palette.cardSoft)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(ChungHwa.Palette.lineSoft, lineWidth: 0.5)
            )
            .padding(.horizontal, 18)
        } else {
            ScrollView {
                Text("找不到 \(yamlURL.path)")
                    .font(ChungHwa.Typography.mono(11))
                    .foregroundStyle(ChungHwa.Palette.earth)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            }
            .background(ChungHwa.Palette.cardSoft)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(ChungHwa.Palette.lineSoft, lineWidth: 0.5)
            )
            .padding(.horizontal, 18)
        }
    }

    // MARK: footer

    /// In edit mode the footer counts the live buffer; in read mode it counts
    /// the on-disk content shown above (which we update after a successful save).
    private var footerSource: String? {
        isEditing ? editedContent : displayContent
    }

    private var footerLine: some View {
        HStack(spacing: 10) {
            if let s = footerSource {
                Text("\(s.utf8.count) 字节")
                    .font(.system(size: 11))
                    .foregroundStyle(ChungHwa.Palette.dim)
                    .monospacedDigit()
                Text("·")
                    .font(.system(size: 11))
                    .foregroundStyle(ChungHwa.Palette.faint)
                Text("\(lineCount(s)) 行")
                    .font(.system(size: 11))
                    .foregroundStyle(ChungHwa.Palette.dim)
                    .monospacedDigit()
            } else {
                Text("空文件")
                    .font(.system(size: 11))
                    .foregroundStyle(ChungHwa.Palette.faint)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    private func lineCount(_ s: String) -> Int {
        if s.isEmpty { return 0 }
        var n = 1
        for c in s where c == "\n" { n += 1 }
        // Don't count a trailing newline as an extra empty line.
        if s.hasSuffix("\n") { n -= 1 }
        return max(n, 1)
    }

    // MARK: bottom buttons

    @ViewBuilder
    private var bottomButtons: some View {
        if isEditing {
            editModeButtons
        } else {
            readModeButtons
        }
    }

    private var readModeButtons: some View {
        HStack(spacing: 8) {
            // Edit (brass) — left aligned to set it apart from the right-side
            // utility cluster.
            sheetBrassButton(title: "编辑", systemImage: "pencil") {
                editedContent = displayContent ?? ""
                saveStatus = nil
                isEditing = true
            }
            Spacer(minLength: 0)
            if case .file = profile.source {
                sheetGhostButton(title: "在 Finder 显示", systemImage: "folder") {
                    NSWorkspace.shared.activateFileViewerSelecting([yamlURL])
                }
            }
            sheetGhostButton(title: "复制内容", systemImage: "doc.on.doc") {
                guard let s = displayContent else { return }
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(s, forType: .string)
                withAnimation { copyHint = "已复制" }
                Task {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    withAnimation { copyHint = nil }
                }
            }
            sheetGhostButton(title: "关闭", systemImage: "xmark", action: onClose)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private var editModeButtons: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            sheetGhostButton(title: "取消", systemImage: "arrow.uturn.backward") {
                editedContent = displayContent ?? ""
                isEditing = false
                saveStatus = nil
            }
            sheetBrassButton(title: "保存", systemImage: "checkmark") {
                performSave()
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    /// Save edits to disk, refresh the read-mode buffer, and — if this is the
    /// active profile — trigger a mihomo reload. We don't validate the yaml
    /// here; the kernel will surface parse errors via the global error banner.
    private func performSave() {
        let toSave = editedContent
        do {
            try store.setYaml(toSave, for: profile.id)
        } catch {
            // Surface the write error inline; leave the user in edit mode so
            // they can copy out their changes if needed.
            saveStatus = "保存失败: \(error)"
            return
        }
        displayContent = toSave
        isEditing = false

        if profile.id == store.activeProfileID {
            withAnimation { saveStatus = "重载中…" }
            Task {
                await kernel.reload()
                withAnimation { saveStatus = "已保存" }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                withAnimation { saveStatus = nil }
            }
        } else {
            withAnimation { saveStatus = "已保存" }
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                withAnimation { saveStatus = nil }
            }
        }
    }

    // MARK: - shared button shapes

    private func sheetBrassButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 10.5, weight: .semibold))
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(ChungHwa.Palette.ink)
            .padding(.horizontal, 11)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(ChungHwa.Palette.brass)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(ChungHwa.Palette.brassDark.opacity(0.55), lineWidth: 0.5)
            )
            .shadow(color: ChungHwa.Palette.brassDark.opacity(0.20), radius: 1, y: 1)
        }
        .buttonStyle(.plain)
    }

    private func sheetGhostButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 10.5, weight: .medium))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(ChungHwa.Palette.text)
            .padding(.horizontal, 11)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(ChungHwa.Palette.pillBg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(ChungHwa.Palette.line, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Cheap YAML syntax highlighter

private enum YAMLHighlighter {
    /// Per-line scan, no real parser. Light coloring only:
    /// - comments (`# ...`) → faint
    /// - top-level keys (`^([\w-]+)\s*:` no leading indent) → brass
    /// - quoted string values → patina
    /// - anchors / aliases (`&name`, `*name`) → earth
    /// - everything else → text
    static func highlight(_ yaml: String) -> AttributedString {
        var out = AttributedString("")
        let lines = yaml.split(separator: "\n", omittingEmptySubsequences: false)
        for (idx, line) in lines.enumerated() {
            out.append(highlight(line: String(line)))
            if idx < lines.count - 1 {
                var nl = AttributedString("\n")
                nl.foregroundColor = ChungHwa.Palette.text
                out.append(nl)
            }
        }
        return out
    }

    private static func highlight(line raw: String) -> AttributedString {
        // Empty line: emit as text-colored empty.
        if raw.isEmpty {
            var s = AttributedString("")
            s.foregroundColor = ChungHwa.Palette.text
            return s
        }

        // Whole-line comment (after optional whitespace).
        let trimmed = raw.drop(while: { $0 == " " || $0 == "\t" })
        if trimmed.first == "#" {
            var s = AttributedString(raw)
            s.foregroundColor = ChungHwa.Palette.faint
            return s
        }

        // Top-level key: starts at column 0 with `[\w-]+` then `:`.
        if let colonIdx = topLevelKeyColonIndex(raw) {
            var out = AttributedString("")
            let keyPart = String(raw[..<colonIdx]) + ":"
            var keyAttr = AttributedString(keyPart)
            keyAttr.foregroundColor = ChungHwa.Palette.brass
            out.append(keyAttr)
            let afterColon = raw.index(after: colonIdx)
            if afterColon < raw.endIndex {
                let rest = String(raw[afterColon...])
                out.append(colorizeValue(rest))
            }
            return out
        }

        return colorizeValue(raw)
    }

    /// If `line` starts at column 0 with a `[\w-]+` identifier followed by `:`,
    /// return the index of that colon; otherwise nil.
    private static func topLevelKeyColonIndex(_ line: String) -> String.Index? {
        guard let first = line.first, !first.isWhitespace else { return nil }
        var i = line.startIndex
        var sawAny = false
        while i < line.endIndex {
            let c = line[i]
            if c.isLetter || c.isNumber || c == "_" || c == "-" {
                sawAny = true
                i = line.index(after: i)
            } else {
                break
            }
        }
        guard sawAny, i < line.endIndex, line[i] == ":" else { return nil }
        return i
    }

    /// Colorize an arbitrary value-region: handles quoted strings and
    /// anchors/aliases; everything else is default text color.
    private static func colorizeValue(_ s: String) -> AttributedString {
        var out = AttributedString("")
        var i = s.startIndex
        var pending = ""

        func flushPending() {
            guard !pending.isEmpty else { return }
            var a = AttributedString(pending)
            a.foregroundColor = ChungHwa.Palette.text
            out.append(a)
            pending = ""
        }

        while i < s.endIndex {
            let c = s[i]

            // Inline comment from `#` to end of line — only when preceded by
            // whitespace or start; cheap heuristic.
            if c == "#", (i == s.startIndex || s[s.index(before: i)].isWhitespace) {
                flushPending()
                let rest = String(s[i...])
                var a = AttributedString(rest)
                a.foregroundColor = ChungHwa.Palette.faint
                out.append(a)
                return out
            }

            // Quoted strings: " ... " or ' ... '
            if c == "\"" || c == "'" {
                flushPending()
                let quote = c
                let start = i
                var j = s.index(after: i)
                while j < s.endIndex {
                    let cc = s[j]
                    if cc == "\\", s.index(after: j) < s.endIndex {
                        j = s.index(j, offsetBy: 2)
                        continue
                    }
                    if cc == quote {
                        j = s.index(after: j)
                        break
                    }
                    j = s.index(after: j)
                }
                let segment = String(s[start..<j])
                var a = AttributedString(segment)
                a.foregroundColor = ChungHwa.Palette.patina
                out.append(a)
                i = j
                continue
            }

            // Anchors/aliases: & or * followed by name chars.
            if (c == "&" || c == "*"),
               (i == s.startIndex || s[s.index(before: i)].isWhitespace) {
                let next = s.index(after: i)
                if next < s.endIndex {
                    let nc = s[next]
                    if nc.isLetter || nc.isNumber || nc == "_" || nc == "-" {
                        flushPending()
                        let start = i
                        var j = next
                        while j < s.endIndex {
                            let cc = s[j]
                            if cc.isLetter || cc.isNumber || cc == "_" || cc == "-" {
                                j = s.index(after: j)
                            } else { break }
                        }
                        let segment = String(s[start..<j])
                        var a = AttributedString(segment)
                        a.foregroundColor = ChungHwa.Palette.earth
                        out.append(a)
                        i = j
                        continue
                    }
                }
            }

            pending.append(c)
            i = s.index(after: i)
        }

        flushPending()
        return out
    }
}
