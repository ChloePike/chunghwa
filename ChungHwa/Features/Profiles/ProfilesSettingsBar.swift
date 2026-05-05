import SwiftUI

/// Auto-refresh interval + storage-mode controls above the profiles list.
struct ProfilesSettingsBar: View {
    @Environment(ProfileStore.self) private var store
    @Binding var importError: String?
    let onPickFile: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            autoRefreshRow
            storageRow
        }
    }

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
                ProfilesGhostButton(title: "立即拉取", systemImage: "arrow.clockwise") {
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
}
