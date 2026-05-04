import Foundation
import Observation
import OSLog

enum KernelError: Error, CustomStringConvertible {
    case binaryMissing
    case notReady(any Error)
    case startupFailure(String)

    var description: String {
        switch self {
        case .binaryMissing:
            return "mihomo binary not found in app bundle"
        case .notReady(let e):
            return "mihomo not ready in time: \(e)"
        case .startupFailure(let s):
            return "mihomo failed to start: \(s)"
        }
    }
}

@Observable
@MainActor
final class KernelController {
    private(set) var status: KernelStatus = .idle
    private(set) var apiClient: MihomoAPIClient?
    private(set) var activeBinary: KernelBinary?

    private var process: Process?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?

    private let log = Logger(subsystem: "com.tzaigroup.chunghwa", category: "kernel")
    private let externalControllerPort = 47913

    private let resolver: KernelBinaryResolver
    private let logStore: LogStore
    private let dataDir: URL
    private let configFile: URL

    init(resolver: KernelBinaryResolver, logStore: LogStore) {
        self.resolver = resolver
        self.logStore = logStore
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.dataDir = appSupport
            .appendingPathComponent("ChungHwa", isDirectory: true)
            .appendingPathComponent("mihomo", isDirectory: true)
        self.configFile = dataDir.appendingPathComponent("config.yaml")
    }

    func start() async {
        switch status {
        case .running, .starting: return
        default: break
        }
        status = .starting

        do {
            try FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)

            let secret = generateSecret()
            try writeBootstrapConfig(secret: secret)

            resolver.refresh()
            guard let binary = resolver.current else {
                throw KernelError.binaryMissing
            }
            self.activeBinary = binary
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.url.path)

            let process = Process()
            process.executableURL = binary.url
            process.arguments = ["-d", dataDir.path, "-f", configFile.path]

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe
            self.stdoutPipe = outPipe
            self.stderrPipe = errPipe
            attachLog(pipe: outPipe, label: "mihomo.stdout", stream: .stdout)
            attachLog(pipe: errPipe, label: "mihomo.stderr", stream: .stderr)

            process.terminationHandler = { [weak self] proc in
                let code = proc.terminationStatus
                Task { @MainActor [weak self] in
                    self?.handleTermination(exitCode: code)
                }
            }

            try process.run()
            self.process = process
            log.info("mihomo spawned pid=\(process.processIdentifier, privacy: .public) port=\(self.externalControllerPort, privacy: .public)")

            let baseURL = URL(string: "http://127.0.0.1:\(externalControllerPort)")!
            let client = MihomoAPIClient(baseURL: baseURL, secret: secret)
            self.apiClient = client

            let version = try await waitForReady(client: client, timeout: 8)
            status = .running(version: version)
            log.info("mihomo ready version=\(version, privacy: .public)")
        } catch {
            log.error("kernel start failed: \(String(describing: error), privacy: .public)")
            cleanupProcess()
            status = .failed(reason: String(describing: error))
        }
    }

    func stop() {
        if let process, process.isRunning {
            process.terminate()
        }
        cleanupProcess()
        status = .idle
    }

    /// 热加载：让 mihomo 重新读取配置文件，进程不重启、连接不中断。
    /// 调用前先把新配置写入 `configFile`，再调本方法。
    /// 内核未运行时降级为 start()。
    func reload() async {
        guard case .running = status, let client = apiClient else {
            await start()
            return
        }
        do {
            try await client.reloadConfig(path: configFile.path)
            log.info("mihomo config reloaded")
            // 复测一次 version，确认 reload 后内核仍存活；失败则视作降级
            if let v = try? await client.version().version {
                status = .running(version: v)
            }
        } catch {
            log.error("kernel reload failed: \(String(describing: error), privacy: .public)")
            // 保持当前 running 状态：旧配置仍在生效
        }
    }

    /// 冷重启：杀进程后重新拉起。`reload()` 不可用时（例如配置变化太大）的兜底。
    func restart() async {
        log.info("kernel restart requested")
        stop()
        await start()
    }

    /// 暴露当前用于启动 mihomo 的配置文件路径，方便外层在 reload 前写入新内容。
    var activeConfigFile: URL { configFile }

    // MARK: - private

    private func writeBootstrapConfig(secret: String) throws {
        let yaml = """
        mixed-port: 7890
        allow-lan: false
        mode: rule
        log-level: info
        external-controller: 127.0.0.1:\(externalControllerPort)
        secret: \(secret)
        """
        try yaml.write(to: configFile, atomically: true, encoding: .utf8)
    }

    private func generateSecret() -> String {
        UUID().uuidString + UUID().uuidString
    }

    private func waitForReady(client: MihomoAPIClient, timeout: TimeInterval) async throws -> String {
        let deadline = Date().addingTimeInterval(timeout)
        var lastError: (any Error) = MihomoAPIError.invalidResponse
        while Date() < deadline {
            do {
                return try await client.version().version
            } catch {
                lastError = error
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
        throw KernelError.notReady(lastError)
    }

    private func attachLog(pipe: Pipe, label: String, stream: LogStream) {
        let logger = self.log
        let store = self.logStore
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            let lines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
            guard !lines.isEmpty else { return }
            for line in lines {
                logger.debug("\(label, privacy: .public): \(line, privacy: .public)")
            }
            Task { @MainActor in
                for line in lines {
                    store.append(line, stream: stream)
                }
            }
        }
    }

    private func cleanupProcess() {
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        stdoutPipe = nil
        stderrPipe = nil
        process = nil
        apiClient = nil
        activeBinary = nil
    }

    private func handleTermination(exitCode: Int32) {
        log.warning("mihomo terminated exit=\(exitCode, privacy: .public)")
        if case .running = status {
            status = .failed(reason: "mihomo exited with code \(exitCode)")
        } else if case .starting = status {
            status = .failed(reason: "mihomo exited during startup (code \(exitCode))")
        }
        cleanupProcess()
    }
}
