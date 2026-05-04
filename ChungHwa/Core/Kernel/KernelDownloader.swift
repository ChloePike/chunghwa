import Foundation
import Observation
import OSLog
import Darwin

enum KernelDownloadError: Error, CustomStringConvertible {
    case metadata(String)
    case download(String)
    case gunzip(String)
    case sign(String)
    case install(String)

    var description: String {
        switch self {
        case .metadata(let s): return "metadata: \(s)"
        case .download(let s): return "download: \(s)"
        case .gunzip(let s):   return "gunzip: \(s)"
        case .sign(let s):     return "sign: \(s)"
        case .install(let s):  return "install: \(s)"
        }
    }
}

/// Downloads the latest mihomo release into the resolver's managed directory.
@Observable
@MainActor
final class KernelDownloader {
    enum State: Equatable {
        case idle
        case fetchingMetadata
        case downloading(version: String)
        case extracting(version: String)
        case installing(version: String)
        case completed(version: String)
        case failed(String)
    }

    private(set) var state: State = .idle

    private let resolver: KernelBinaryResolver
    private let log = Logger(subsystem: "com.tzaigroup.chunghwa", category: "downloader")
    private let session: URLSession

    init(resolver: KernelBinaryResolver) {
        self.resolver = resolver
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 30
        cfg.timeoutIntervalForResource = 600
        self.session = URLSession(configuration: cfg)
    }

    var isWorking: Bool {
        switch state {
        case .idle, .completed, .failed: return false
        default: return true
        }
    }

    func reset() { state = .idle }

    func updateLatest() async {
        do {
            state = .fetchingMetadata
            let version = try await fetchLatestVersion()
            log.info("latest mihomo tag: \(version, privacy: .public)")

            let arch = nativeArch()
            state = .downloading(version: version)
            let gzData = try await downloadAsset(version: version, arch: arch)

            state = .extracting(version: version)
            let binary = try gunzipData(gzData)

            state = .installing(version: version)
            try installBinary(binary, version: version)

            state = .completed(version: version)
            resolver.refresh()
            log.info("kernel installed: \(version, privacy: .public)")
        } catch {
            let msg = String(describing: error)
            log.error("download failed: \(msg, privacy: .public)")
            state = .failed(msg)
        }
    }

    // MARK: - phases

    private func fetchLatestVersion() async throws -> String {
        let url = URL(string: "https://api.github.com/repos/MetaCubeX/mihomo/releases/latest")!
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw KernelDownloadError.metadata("HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
        }
        struct Release: Decodable { let tag_name: String }
        let r = try JSONDecoder().decode(Release.self, from: data)
        guard !r.tag_name.isEmpty else { throw KernelDownloadError.metadata("empty tag_name") }
        return r.tag_name
    }

    private func downloadAsset(version: String, arch: String) async throws -> Data {
        let urlStr = "https://github.com/MetaCubeX/mihomo/releases/download/\(version)/mihomo-darwin-\(arch)-\(version).gz"
        guard let url = URL(string: urlStr) else {
            throw KernelDownloadError.download("invalid URL")
        }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw KernelDownloadError.download("HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
        }
        return data
    }

    private nonisolated func gunzipData(_ data: Data) throws -> Data {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("chunghwa-mihomo-\(UUID().uuidString).gz")
        try data.write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/gunzip")
        proc.arguments = ["-c", tmp.path]
        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe
        try proc.run()
        let out = outPipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else {
            let stderr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw KernelDownloadError.gunzip("exit=\(proc.terminationStatus) \(stderr)")
        }
        return out
    }

    private func installBinary(_ data: Data, version: String) throws {
        let dir = resolver.managedDir
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let staging = dir.appendingPathComponent(".mihomo.staging")
        try? FileManager.default.removeItem(at: staging)
        try data.write(to: staging)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: staging.path)

        let sign = Process()
        sign.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        sign.arguments = ["--force", "--sign", "-", staging.path]
        let errPipe = Pipe()
        sign.standardOutput = Pipe()
        sign.standardError = errPipe
        try sign.run()
        sign.waitUntilExit()
        guard sign.terminationStatus == 0 else {
            let stderr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw KernelDownloadError.sign("exit=\(sign.terminationStatus) \(stderr)")
        }

        let dest = resolver.managedBinaryURL
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.moveItem(at: staging, to: dest)
        try version.write(to: resolver.managedVersionURL, atomically: true, encoding: .utf8)
    }

    private nonisolated func nativeArch() -> String {
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var bytes = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &bytes, &size, nil, 0)
        let machine = String(cString: bytes)
        // mihomo asset naming: arm64, amd64
        return machine == "arm64" ? "arm64" : "amd64"
    }
}
