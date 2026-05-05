import Foundation
import Observation
import OSLog

/// Decides which mihomo binary the kernel should run.
///
/// Priority: privileged (setuid root, in `/Library/PrivilegedHelperTools/`) >
/// custom (user-picked) > managed (in-app downloader) > bundled (shipped with .app).
///
/// The privileged binary is authoritative when present: if the user authorized,
/// that's the kernel we run, regardless of which non-privileged source would
/// otherwise win. To update the privileged binary, the user re-authorizes from
/// the desired source.
@Observable
@MainActor
final class KernelBinaryResolver {
    private let log = Logger(subsystem: "org.clash.ChungHwa", category: "binary")
    private let defaults = UserDefaults.standard
    private static let customPathKey = "KernelCustomBinaryPath"

    private(set) var current: KernelBinary?

    /// Directory where the in-app downloader writes the managed binary.
    let managedDir: URL

    init() {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.managedDir = appSupport
            .appendingPathComponent("ChungHwa", isDirectory: true)
            .appendingPathComponent("kernel", isDirectory: true)
        refresh()
    }

    var managedBinaryURL: URL { managedDir.appendingPathComponent("mihomo") }
    var managedVersionURL: URL { managedDir.appendingPathComponent("version.txt") }

    var customPath: URL? {
        get {
            guard let s = defaults.string(forKey: Self.customPathKey), !s.isEmpty else { return nil }
            return URL(fileURLWithPath: s)
        }
        set {
            if let url = newValue {
                defaults.set(url.path, forKey: Self.customPathKey)
            } else {
                defaults.removeObject(forKey: Self.customPathKey)
            }
            refresh()
        }
    }

    /// Recompute `current` based on what's on disk. Privileged wins over
    /// every other tier: if the user has granted root, that's the kernel
    /// we run.
    func refresh() {
        if KernelPrivilegeHelper.isPrivileged() {
            let privilegedURL = URL(fileURLWithPath: KernelPrivilegeHelper.privilegedBinaryPath)
            current = KernelBinary(url: privilegedURL, source: .privileged)
            log.info("resolved kernel: privileged \(privilegedURL.path, privacy: .public)")
            return
        }
        if let nonPrivileged = nonPrivilegedCurrent {
            current = nonPrivileged
            log.info("resolved kernel: \(nonPrivileged.source.displayName, privacy: .public) \(nonPrivileged.url.path, privacy: .public)")
            return
        }
        current = nil
        log.error("no kernel binary found")
    }

    /// What `refresh()` would resolve to if `KernelPrivilegeHelper.isPrivileged()`
    /// were false. Used by Settings to pick the source for the
    /// `cp → /Library/PrivilegedHelperTools/` step when the user authorizes.
    var nonPrivilegedCurrent: KernelBinary? {
        if let custom = customPath, isExecutable(custom) {
            return KernelBinary(url: custom, source: .custom)
        }
        let managed = managedBinaryURL
        if isExecutable(managed) {
            return KernelBinary(url: managed, source: .managed)
        }
        if let bundled = bundledBinaryURL() {
            return KernelBinary(url: bundled, source: .bundled)
        }
        return nil
    }

    /// Forget the user-managed downloaded copy, drop any custom override, fall back to bundled.
    func resetToBundled() throws {
        customPath = nil
        if FileManager.default.fileExists(atPath: managedDir.path) {
            try FileManager.default.removeItem(at: managedDir)
        }
        refresh()
    }

    /// Sidecar version (only meaningful for `.managed`).
    func managedVersion() -> String? {
        guard let data = try? Data(contentsOf: managedVersionURL),
              let s = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !s.isEmpty else { return nil }
        return s
    }

    private func bundledBinaryURL() -> URL? {
        guard let resourceURL = Bundle.main.resourceURL else { return nil }
        let url = resourceURL.appendingPathComponent("mihomo")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private func isExecutable(_ url: URL) -> Bool {
        let path = url.path
        let fm = FileManager.default
        return fm.fileExists(atPath: path) && fm.isExecutableFile(atPath: path)
    }
}
