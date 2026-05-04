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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
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
        .navigationTitle("Profiles")
        .sheet(isPresented: $showImportURL) {
            ImportURLSheet(
                urlText: $urlText,
                urlName: $urlName,
                onCancel: { closeImportURL() },
                onSubmit: submitImportURL
            )
        }
        .alert(
            "Remove profile?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            presenting: pendingDelete
        ) { p in
            Button("Cancel", role: .cancel) { pendingDelete = nil }
            Button("Remove", role: .destructive) {
                try? store.remove(p.id)
                pendingDelete = nil
            }
        } message: { p in
            Text("\(p.name) will be removed from ChungHwa. This cannot be undone.")
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Profiles")
                    .font(ChungHwa.Typography.serif(20, weight: .semibold))
                    .foregroundStyle(ChungHwa.Palette.text)
                    .tracking(-0.3)
                Text("\(store.profiles.count) configuration\(store.profiles.count == 1 ? "" : "s")")
                    .font(.system(size: 11.5))
                    .foregroundStyle(ChungHwa.Palette.dim)
            }
            Spacer(minLength: 12)
            HStack(spacing: 8) {
                BrassButton(title: "Import file…", systemImage: "doc.badge.plus") {
                    pickFile()
                }
                GhostButton(title: "From URL…", systemImage: "link.badge.plus") {
                    showImportURL = true
                }
            }
        }
    }

    private var storageRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "internaldrive")
                .font(.system(size: 11))
                .foregroundStyle(ChungHwa.Palette.dim)
            Text("Storage")
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
        let cloudLabel = store.iCloudDriveAvailable ? "iCloud Drive" : "iCloud (off)"
        return [
            (.appSupport, "App Support"),
            (.iCloudDrive, cloudLabel),
        ]
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.text")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(ChungHwa.Palette.faint)
            Text("No profiles yet")
                .font(ChungHwa.Typography.serif(16, weight: .medium))
                .foregroundStyle(ChungHwa.Palette.text)
            Text("Import a YAML or paste a subscription URL to get started.")
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

    // MARK: - Actions

    private func pickFile() {
        let panel = NSOpenPanel()
        panel.title = "Import yaml profile"
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
            Image(systemName: profile.source.subscriptionURL == nil ? "doc.text" : "globe")
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
            Text("ACTIVE")
                .font(.system(size: 9.5, weight: .bold))
                .tracking(0.7)
                .foregroundStyle(ChungHwa.Palette.brassDark)
        }
        .padding(.horizontal, 7).padding(.vertical, 2)
        .background(Capsule().fill(ChungHwa.Palette.brass.opacity(0.18)))
    }

    private var metaRow: some View {
        HStack(spacing: 6) {
            Text("Imported")
                .font(.system(size: 11))
                .foregroundStyle(ChungHwa.Palette.dim)
            RelativeDateText(date: profile.importedAt)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(ChungHwa.Palette.text)
            Text("·")
                .font(.system(size: 11))
                .foregroundStyle(ChungHwa.Palette.faint)
            Text("Updated")
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
                BadgeButton(title: "Active", systemImage: "checkmark", enabled: false) {}
            } else {
                BadgeButton(title: "Activate", systemImage: "play.fill", enabled: true, action: onActivate)
            }
            if profile.source.subscriptionURL != nil {
                IconBadgeButton(systemImage: "arrow.clockwise",
                                tint: ChungHwa.Palette.dim,
                                help: "Refresh subscription",
                                action: onRefresh)
            }
            IconBadgeButton(systemImage: "trash",
                            tint: ChungHwa.Palette.earth,
                            help: "Remove profile",
                            action: onRequestDelete)
        }
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
            Text("Import subscription URL")
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
                Text("Name (optional)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ChungHwa.Palette.dim)
                TextField("My subscription", text: $urlName)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Import", action: onSubmit)
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
        if elapsed < 0 { return "just now" }
        let s = Int(elapsed)
        switch s {
        case ..<5:
            return "just now"
        case ..<60:
            return "\(s) sec\(s == 1 ? "" : "s") ago"
        case ..<3_600:
            let m = s / 60
            return "\(m) min\(m == 1 ? "" : "s") ago"
        case ..<86_400:
            let h = s / 3600
            return "\(h) hour\(h == 1 ? "" : "s") ago"
        case ..<(86_400 * 7):
            let dys = s / 86_400
            return "\(dys) day\(dys == 1 ? "" : "s") ago"
        case ..<(86_400 * 30):
            let w = s / (86_400 * 7)
            return "\(w) week\(w == 1 ? "" : "s") ago"
        case ..<(86_400 * 365):
            let mo = s / (86_400 * 30)
            return "\(mo) month\(mo == 1 ? "" : "s") ago"
        default:
            let y = s / (86_400 * 365)
            return "\(y) year\(y == 1 ? "" : "s") ago"
        }
    }
}
