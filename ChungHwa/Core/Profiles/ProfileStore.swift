import Foundation
import Observation
import OSLog

enum ProfileError: Error, CustomStringConvertible {
    case downloadFailed(String)
    case readFailed(String)
    case writeFailed(String)
    case storageUnavailable(String)

    var description: String {
        switch self {
        case .downloadFailed(let s):    return "download failed: \(s)"
        case .readFailed(let s):        return "read failed: \(s)"
        case .writeFailed(let s):       return "write failed: \(s)"
        case .storageUnavailable(let s): return "storage unavailable: \(s)"
        }
    }
}

@Observable
@MainActor
final class ProfileStore {
    enum StorageMode: String, Codable, CaseIterable, Sendable {
        case appSupport, iCloudDrive

        var displayName: String {
            switch self {
            case .appSupport:  return "App Support"
            case .iCloudDrive: return "iCloud Drive"
            }
        }
    }

    private(set) var profiles: [Profile] = []
    private(set) var activeProfileID: UUID?
    private(set) var storageMode: StorageMode = .appSupport
    /// Last user-visible error from `addFile` / `addURL` / `refresh`. Surfaced
    /// in the global error banner via the same .onChange wiring as the other
    /// stores, so a 401 / network failure / non-yaml response doesn't
    /// disappear silently.
    private(set) var lastError: String?

    // MARK: - auto-refresh

    private static let autoRefreshKey = "ChungHwa.Profiles.AutoRefreshHours"
    private static let defaultAutoRefreshHours: Double = 24

    /// User-configurable interval (in hours) between automatic background
    /// refreshes of URL-source profiles. `0` disables auto-refresh.
    var autoRefreshHours: Double {
        didSet {
            UserDefaults.standard.set(autoRefreshHours, forKey: Self.autoRefreshKey)
            startAutoRefreshLoop()
        }
    }
    private(set) var lastAutoRefresh: Date?
    private(set) var autoRefreshTask: Task<Void, Never>?

    private let log = Logger(subsystem: "com.tzaigroup.chunghwa", category: "profiles")
    private let session: URLSession
    private let appSupportRoot: URL
    private let metadataURL: URL

    init() {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ChungHwa", isDirectory: true)
        self.appSupportRoot = support
        self.metadataURL = support.appendingPathComponent("profiles.json")
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 30
        cfg.timeoutIntervalForResource = 120
        self.session = URLSession(configuration: cfg)

        let stored = UserDefaults.standard.double(forKey: Self.autoRefreshKey)
        // Treat 0 as "unset" only on first launch: if the key was never written,
        // `double(forKey:)` returns 0. We want 24h as the first-run default but
        // also need to honour an explicit user choice of 0 (off). We disambiguate
        // by checking whether the key exists.
        if UserDefaults.standard.object(forKey: Self.autoRefreshKey) == nil {
            self.autoRefreshHours = Self.defaultAutoRefreshHours
        } else {
            self.autoRefreshHours = max(0, stored)
        }

        load()
        startAutoRefreshLoop()
    }

    // No deinit cancel: the loop captures `weak self`, so it returns on the
    // first iteration after the store deallocates.

    // MARK: - paths

    var iCloudDriveRoot: URL? {
        let url = FileManager.default
            .urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    var iCloudDriveAvailable: Bool { iCloudDriveRoot != nil }

    private func storageRoot(for mode: StorageMode) -> URL? {
        switch mode {
        case .appSupport:
            return appSupportRoot
        case .iCloudDrive:
            return iCloudDriveRoot?.appendingPathComponent("ChungHwa", isDirectory: true)
        }
    }

    private var profilesDir: URL {
        let root = storageRoot(for: storageMode) ?? appSupportRoot
        return root.appendingPathComponent("Profiles", isDirectory: true)
    }

    func yamlURL(for id: UUID) -> URL {
        profilesDir.appendingPathComponent("\(id.uuidString).yaml")
    }

    var activeProfile: Profile? {
        guard let id = activeProfileID else { return nil }
        return profiles.first(where: { $0.id == id })
    }

    func yamlContent(for id: UUID) -> String? {
        try? String(contentsOf: yamlURL(for: id), encoding: .utf8)
    }

    var activeYamlContent: String? {
        guard let id = activeProfileID else { return nil }
        return yamlContent(for: id)
    }

    // MARK: - mutations

    @discardableResult
    func addFile(at url: URL, name: String? = nil) throws -> Profile {
        do {
            let data: Data
            do { data = try Data(contentsOf: url) }
            catch { throw ProfileError.readFailed("\(error)") }
            try assertLooksLikeYAML(data, source: url.path)
            let profile = Profile(
                id: UUID(),
                name: name ?? url.deletingPathExtension().lastPathComponent,
                source: .file,
                importedAt: Date(),
                updatedAt: Date()
            )
            try writeYaml(data, for: profile.id)
            profiles.append(profile)
            try save()
            lastError = nil
            return profile
        } catch {
            lastError = "Import failed: \(error)"
            log.error("addFile \(url.path, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            throw error
        }
    }

    @discardableResult
    func addURL(_ url: URL, name: String? = nil) async throws -> Profile {
        do {
            let data = try await fetch(url)
            try assertLooksLikeYAML(data, source: url.absoluteString)
            let profile = Profile(
                id: UUID(),
                name: name ?? url.host.map { "Sub @ \($0)" } ?? "Subscription",
                source: .url(url),
                importedAt: Date(),
                updatedAt: Date()
            )
            try writeYaml(data, for: profile.id)
            profiles.append(profile)
            try save()
            lastError = nil
            return profile
        } catch {
            lastError = "Add URL failed: \(error)"
            log.error("addURL \(url.absoluteString, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            throw error
        }
    }

    /// Reject obviously-not-yaml payloads (e.g. an HTML auth page returned
    /// behind a 200) so we never write them to disk and feed the kernel.
    private func assertLooksLikeYAML(_ data: Data, source: String) throws {
        // First non-whitespace byte. HTML / login walls almost always start
        // with `<` (`<!doctype …>` or `<html …>`), JSON with `{` / `[`.
        // Real clash/mihomo yaml starts with a comment, a key, or a hyphen.
        guard let first = data.first(where: { c in
            !(c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D)
        }) else {
            throw ProfileError.downloadFailed("empty body")
        }
        if first == 0x3C { // '<'
            throw ProfileError.downloadFailed(
                "got HTML — subscription URL probably needs auth or returned an error page"
            )
        }
    }

    func setYaml(_ content: String, for id: UUID) throws {
        let data = Data(content.utf8)
        try writeYaml(data, for: id)
        if let idx = profiles.firstIndex(where: { $0.id == id }) {
            profiles[idx].updatedAt = Date()
            try save()
        }
    }

    func refresh(_ id: UUID) async throws {
        guard let idx = profiles.firstIndex(where: { $0.id == id }),
              case let .url(url) = profiles[idx].source else {
            return
        }
        let data = try await fetch(url)
        try writeYaml(data, for: id)
        profiles[idx].updatedAt = Date()
        try save()
    }

    /// Unconditionally refresh every URL-source profile. Errors per-profile are
    /// swallowed (logged) so one bad subscription doesn't sink the rest.
    func refreshAll() async {
        let urlIDs = profiles.compactMap { p -> UUID? in
            if case .url = p.source { return p.id }
            return nil
        }
        for id in urlIDs {
            do {
                try await refresh(id)
            } catch {
                log.error("refreshAll: profile \(id.uuidString, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            }
        }
        lastAutoRefresh = Date()
    }

    /// Refresh URL-source profiles whose `updatedAt` is older than the
    /// configured auto-refresh interval. Called by the background loop.
    func refreshDueProfiles() async {
        guard autoRefreshHours > 0 else { return }
        let threshold = autoRefreshHours * 3600
        let now = Date()
        let dueIDs = profiles.compactMap { p -> UUID? in
            guard case .url = p.source else { return nil }
            return now.timeIntervalSince(p.updatedAt) >= threshold ? p.id : nil
        }
        for id in dueIDs {
            do {
                try await refresh(id)
                if Task.isCancelled { break }
            } catch {
                log.error("auto-refresh: profile \(id.uuidString, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            }
        }
        lastAutoRefresh = Date()
    }

    /// Start (or restart) the auto-refresh loop. The loop checks for due
    /// profiles immediately, then sleeps for `min(autoRefreshHours, 1)` hours
    /// before re-evaluating, so even a long interval re-checks at least hourly.
    /// Cancelling the task — via setter changes or deinit — is honoured both
    /// during sleep (`Task.sleep` throws CancellationError) and around each
    /// per-profile fetch (`Task.isCancelled` short-circuits the inner loop).
    func startAutoRefreshLoop() {
        autoRefreshTask?.cancel()
        guard autoRefreshHours > 0 else {
            autoRefreshTask = nil
            log.info("auto-refresh disabled")
            return
        }
        let hours = autoRefreshHours
        log.info("auto-refresh loop starting; interval=\(hours, privacy: .public)h")
        autoRefreshTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refreshDueProfiles()
                if Task.isCancelled { return }
                let sleepHours = min(self.autoRefreshHours, 1.0)
                guard sleepHours > 0 else { return }
                let nanos = UInt64(sleepHours * 3600 * 1_000_000_000)
                do {
                    try await Task.sleep(nanoseconds: nanos)
                } catch {
                    return // cancelled
                }
            }
        }
    }

    func remove(_ id: UUID) throws {
        try? FileManager.default.removeItem(at: yamlURL(for: id))
        profiles.removeAll(where: { $0.id == id })
        if activeProfileID == id { activeProfileID = nil }
        try save()
    }

    func activate(_ id: UUID?) {
        activeProfileID = id
        try? save()
    }

    func setStorageMode(_ mode: StorageMode) async throws {
        if mode == storageMode { return }
        guard let newRoot = storageRoot(for: mode) else {
            throw ProfileError.storageUnavailable("\(mode.displayName) is not available — sign into iCloud Drive in System Settings to enable it")
        }
        let oldDir = profilesDir
        let newDir = newRoot.appendingPathComponent("Profiles", isDirectory: true)
        try FileManager.default.createDirectory(at: newDir, withIntermediateDirectories: true)
        for p in profiles {
            let oldURL = oldDir.appendingPathComponent("\(p.id.uuidString).yaml")
            let newURL = newDir.appendingPathComponent("\(p.id.uuidString).yaml")
            if FileManager.default.fileExists(atPath: oldURL.path) {
                try? FileManager.default.removeItem(at: newURL)
                try FileManager.default.moveItem(at: oldURL, to: newURL)
            }
        }
        storageMode = mode
        try save()
    }

    // MARK: - persistence

    private struct Library: Codable {
        var profiles: [Profile]
        var activeProfileID: UUID?
        var storageMode: StorageMode
    }

    private func load() {
        try? FileManager.default.createDirectory(at: appSupportRoot, withIntermediateDirectories: true)
        guard let data = try? Data(contentsOf: metadataURL) else { return }
        guard let lib = try? JSONDecoder().decode(Library.self, from: data) else {
            log.error("could not decode profile metadata")
            return
        }
        self.profiles = lib.profiles
        self.activeProfileID = lib.activeProfileID
        self.storageMode = lib.storageMode
        // Drop stale active profile id if it points at nothing.
        if let id = activeProfileID, !profiles.contains(where: { $0.id == id }) {
            activeProfileID = nil
        }
    }

    private func save() throws {
        let lib = Library(profiles: profiles,
                          activeProfileID: activeProfileID,
                          storageMode: storageMode)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data: Data
        do { data = try encoder.encode(lib) }
        catch { throw ProfileError.writeFailed("encode: \(error)") }
        do {
            try FileManager.default.createDirectory(at: appSupportRoot, withIntermediateDirectories: true)
            try data.write(to: metadataURL, options: .atomic)
        } catch {
            throw ProfileError.writeFailed("\(error)")
        }
    }

    private func writeYaml(_ data: Data, for id: UUID) throws {
        let dir = profilesDir
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try data.write(to: yamlURL(for: id), options: .atomic)
        } catch {
            throw ProfileError.writeFailed("\(error)")
        }
    }

    private func fetch(_ url: URL) async throws -> Data {
        var req = URLRequest(url: url)
        // Many subscription endpoints require a clash-style UA to return yaml.
        req.setValue("ChungHwa/1.0 (clash)", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw ProfileError.downloadFailed("HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
            }
            return data
        } catch let err as ProfileError {
            throw err
        } catch {
            throw ProfileError.downloadFailed("\(error)")
        }
    }
}
