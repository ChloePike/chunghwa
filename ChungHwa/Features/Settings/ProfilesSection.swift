import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ProfilesSection: View {
    @Environment(ProfileStore.self) private var store
    @Environment(KernelController.self) private var kernel

    @State private var showAddURL = false
    @State private var newURLText: String = ""
    @State private var newURLName: String = ""
    @State private var status: StatusBanner?

    var body: some View {
        SectionCard(title: "Profiles") {
            VStack(alignment: .leading, spacing: 12) {
                storageRow
                Divider()
                profilesList
                if let status { banner(status) }
                actionsRow
            }
        }
        .sheet(isPresented: $showAddURL) {
            addURLSheet
        }
    }

    // MARK: - Storage row

    private var storageRow: some View {
        HStack {
            Text("Storage").font(.subheadline.weight(.semibold))
            Spacer()
            Picker("", selection: pickerBinding) {
                ForEach(ProfileStore.StorageMode.allCases, id: \.self) { m in
                    Text(m.displayName).tag(m)
                }
            }
            .labelsHidden()
            .frame(width: 180)
            .disabled(!store.iCloudDriveAvailable && store.storageMode == .appSupport)
        }
    }

    private var pickerBinding: Binding<ProfileStore.StorageMode> {
        Binding(
            get: { store.storageMode },
            set: { newValue in
                Task {
                    do { try await store.setStorageMode(newValue) }
                    catch { status = .failure(String(describing: error)) }
                }
            }
        )
    }

    // MARK: - Profiles list

    @ViewBuilder
    private var profilesList: some View {
        if store.profiles.isEmpty {
            Text("No profiles yet. Add a yaml file or paste a subscription URL below.")
                .font(.caption).foregroundStyle(.secondary)
        } else {
            VStack(spacing: 6) {
                ForEach(store.profiles) { profile in
                    ProfileRow(profile: profile,
                               isActive: profile.id == store.activeProfileID,
                               onActivate: { activate(profile) },
                               onRefresh: { refresh(profile) },
                               onDelete: { delete(profile) })
                }
            }
        }
    }

    private var actionsRow: some View {
        HStack(spacing: 12) {
            Button {
                pickFile()
            } label: {
                Label("Add yaml…", systemImage: "doc.badge.plus")
            }
            Button {
                showAddURL = true
            } label: {
                Label("Add URL…", systemImage: "link.badge.plus")
            }
            Spacer()
        }
    }

    // MARK: - Add URL sheet

    private var addURLSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add subscription URL").font(.headline)
            VStack(alignment: .leading, spacing: 4) {
                Text("URL").font(.caption).foregroundStyle(.secondary)
                TextField("https://example.com/subscription", text: $newURLText)
                    .textFieldStyle(.roundedBorder)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Name (optional)").font(.caption).foregroundStyle(.secondary)
                TextField("My subscription", text: $newURLName)
                    .textFieldStyle(.roundedBorder)
            }
            HStack {
                Spacer()
                Button("Cancel") { closeAddURL() }
                Button("Add") { submitAddURL() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(URL(string: newURLText) == nil)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    // MARK: - Actions

    private func pickFile() {
        let panel = NSOpenPanel()
        panel.title = "Import yaml profile"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.yaml, UTType(filenameExtension: "yml") ?? .yaml, .text, .plainText, .data]
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let p = try store.addFile(at: url)
                status = .success("Imported \(p.name)")
            } catch {
                status = .failure(String(describing: error))
            }
        }
    }

    private func submitAddURL() {
        guard let url = URL(string: newURLText) else { return }
        let nameOpt = newURLName.trimmingCharacters(in: .whitespaces).isEmpty ? nil : newURLName
        Task {
            do {
                let p = try await store.addURL(url, name: nameOpt)
                status = .success("Imported \(p.name)")
                closeAddURL()
            } catch {
                status = .failure(String(describing: error))
            }
        }
    }

    private func closeAddURL() {
        showAddURL = false
        newURLText = ""
        newURLName = ""
    }

    private func activate(_ p: Profile) {
        store.activate(p.id)
        Task {
            await kernel.reload()
            status = .success("Activated \(p.name)")
        }
    }

    private func refresh(_ p: Profile) {
        Task {
            do {
                try await store.refresh(p.id)
                if p.id == store.activeProfileID { await kernel.reload() }
                status = .success("Refreshed \(p.name)")
            } catch {
                status = .failure(String(describing: error))
            }
        }
    }

    private func delete(_ p: Profile) {
        do {
            try store.remove(p.id)
            status = .success("Removed \(p.name)")
        } catch {
            status = .failure(String(describing: error))
        }
    }

    // MARK: - Banner

    enum StatusBanner: Equatable {
        case success(String), failure(String)
    }

    @ViewBuilder
    private func banner(_ s: StatusBanner) -> some View {
        switch s {
        case .success(let msg):
            Label(msg, systemImage: "checkmark.circle.fill")
                .font(.caption).foregroundStyle(.green)
        case .failure(let msg):
            Label(msg, systemImage: "exclamationmark.triangle.fill")
                .font(.caption).foregroundStyle(.red)
                .lineLimit(3)
        }
    }
}

private struct ProfileRow: View {
    let profile: Profile
    let isActive: Bool
    let onActivate: () -> Void
    let onRefresh: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: profile.source.subscriptionURL == nil ? "doc.text" : "globe")
                .foregroundStyle(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(profile.name).font(.subheadline.weight(.semibold))
                    if isActive {
                        Text("Active")
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(.green.opacity(0.18), in: Capsule())
                            .foregroundStyle(.green)
                    }
                }
                if let url = profile.source.subscriptionURL {
                    Text(url.absoluteString)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1).truncationMode(.middle)
                } else {
                    Text(profile.source.displayName)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            if !isActive {
                Button("Activate") { onActivate() }.controlSize(.small)
            }
            if profile.source.subscriptionURL != nil {
                Button { onRefresh() } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless).controlSize(.small)
                .help("Refresh subscription")
            }
            Button(role: .destructive) { onDelete() } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless).controlSize(.small)
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(isActive ? Color.green.opacity(0.07) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
