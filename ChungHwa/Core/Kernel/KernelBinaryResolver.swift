import Foundation
import Observation
import OSLog

/// Decides which mihomo binary the kernel should run.
///
/// Priority: custom (user-picked) > managed (in-app downloader) > bundled (shipped with .app).
@Observable
@MainActor
final class KernelBinaryResolver {
    private let log = Logger(subsystem: "com.tzaigroup.chunghwa", category: "binary")
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

    /// Recompute `current` based on what's on disk.
    func refresh() {
        if let custom = customPath, isExecutable(custom) {
            current = KernelBinary(url: custom, source: .custom)
            log.info("resolved kernel: custom \(custom.path, privacy: .public)")
            return
        }
        let managed = managedBinaryURL
        if isExecutable(managed) {
            current = KernelBinary(url: managed, source: .managed)
            log.info("resolved kernel: managed \(managed.path, privacy: .public)")
            return
        }
        if let bundled = bundledBinaryURL() {
            current = KernelBinary(url: bundled, source: .bundled)
            log.info("resolved kernel: bundled \(bundled.path, privacy: .public)")
            return
        }
        current = nil
        log.error("no kernel binary found")
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
