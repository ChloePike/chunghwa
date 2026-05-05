import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Profiles tab — file/URL imports, storage selector, and per-profile cards.
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
                ProfilesSettingsBar(
                    importError: $importError,
                    onPickFile: pickFile
                )
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
            ProfileInspectorSheet(
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
                ProfilesBrassButton(title: "导入文件…", systemImage: "doc.badge.plus") {
                    pickFile()
                }
                ProfilesGhostButton(title: "从 URL…", systemImage: "link.badge.plus") {
                    showImportURL = true
                }
            }
        }
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

struct ProfileCard: View {
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
                ProfilesBadgeButton(title: "使用中", systemImage: "checkmark", enabled: false) {}
            } else {
                ProfilesBadgeButton(title: "启用", systemImage: "play.fill", enabled: true, action: onActivate)
            }
            if profile.source.subscriptionURL != nil {
                ProfilesIconBadgeButton(systemImage: "arrow.clockwise",
                                        tint: ChungHwa.Palette.dim,
                                        help: "拉取订阅",
                                        action: onRefresh)
            }
            ProfilesGhostMiniButton(title: "查看",
                                    systemImage: "doc.text.magnifyingglass",
                                    help: "查看 YAML",
                                    action: onInspect)
            ProfilesIconBadgeButton(systemImage: "trash",
                                    tint: ChungHwa.Palette.earth,
                                    help: "删除",
                                    action: onRequestDelete)
        }
    }
}
