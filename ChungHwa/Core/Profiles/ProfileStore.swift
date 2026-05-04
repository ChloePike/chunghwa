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
        load()
    }

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
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ProfileError.readFailed("\(error)")
        }
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
        return profile
    }

    @discardableResult
    func addURL(_ url: URL, name: String? = nil) async throws -> Profile {
        let data = try await fetch(url)
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
        return profile
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
