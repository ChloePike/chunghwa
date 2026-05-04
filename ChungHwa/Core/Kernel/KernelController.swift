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
    private(set) var streamClient: MihomoStreamClient?
    private(set) var activeBinary: KernelBinary?
    /// Timestamp when mihomo first reached `.running` for the current
    /// session. `nil` while idle / starting / failed. Drives Overview's
    /// uptime stat.
    private(set) var startedAt: Date?

    private var process: Process?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var streamTasks: [Task<Void, Never>] = []

    private let log = Logger(subsystem: "com.tzaigroup.chunghwa", category: "kernel")
    private let externalControllerPort = 47913

    private let resolver: KernelBinaryResolver
    private let logStore: LogStore
    private let profileStore: ProfileStore
    private let trafficStore: TrafficStore
    private let historyStore: TrafficHistoryStore
    private let connectionsStore: ConnectionsStore
    private let configStore: ConfigStore
    private let notificationCenterStore: NotificationCenterStore
    private let dataDir: URL
    private let configFile: URL

    init(resolver: KernelBinaryResolver,
         logStore: LogStore,
         profileStore: ProfileStore,
         trafficStore: TrafficStore,
         historyStore: TrafficHistoryStore,
         connectionsStore: ConnectionsStore,
         configStore: ConfigStore,
         notificationCenterStore: NotificationCenterStore) {
        self.resolver = resolver
        self.logStore = logStore
        self.profileStore = profileStore
        self.trafficStore = trafficStore
        self.historyStore = historyStore
        self.connectionsStore = connectionsStore
        self.configStore = configStore
        self.notificationCenterStore = notificationCenterStore
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

        // Reap any orphan mihomo from a previous app instance (force-quit /
        // crash leaves the child running and listening on our port; the new
        // mihomo then can't bind 47913 and the old one rejects our fresh
        // secret with 401).
        killOrphanMihomo()

        do {
            try FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)

            let secret = generateSecret()
            self.runtimeSecret = secret
            try writeComposedConfig(secret: secret)

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
            let stream = MihomoStreamClient(baseURL: baseURL, secret: secret)
            self.streamClient = stream

            let version = try await waitForReady(client: client, timeout: 8)
            status = .running(version: version)
            startedAt = Date()
            log.info("mihomo ready version=\(version, privacy: .public)")
            await configStore.refresh(api: client)
            startStreams(stream)
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

    /// 热加载：把当前 active profile 的 yaml 重新合成、写到 configFile，再让 mihomo 重读。
    /// 进程不重启、连接不中断。内核未运行时降级为 start()。
    func reload() async {
        guard case .running = status, let client = apiClient, let secret = runtimeSecret else {
            await start()
            return
        }
        do {
            try writeComposedConfig(secret: secret)
            try await client.reloadConfig(path: configFile.path)
            log.info("mihomo config reloaded")
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

    private var runtimeSecret: String?

    // MARK: - private

    private func writeComposedConfig(secret: String) throws {
        let userYaml = profileStore.activeYamlContent
        let yaml = ConfigComposer.compose(
            userYaml: userYaml,
            externalControllerHostPort: "127.0.0.1:\(externalControllerPort)",
            secret: secret
        )
        try yaml.write(to: configFile, atomically: true, encoding: .utf8)
    }

    private func generateSecret() -> String {
        UUID().uuidString + UUID().uuidString
    }

    /// Find any mihomo process whose `-d` argument points at our dataDir
    /// and SIGTERM it. Uses `pgrep -af` so we match the exact subprocess
    /// invocation; this won't touch other mihomo binaries (Clash Verge etc.)
    /// because their data-dirs are different.
    private func killOrphanMihomo() {
        let pgrep = Process()
        pgrep.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        pgrep.arguments = ["-af", "mihomo.*-d \(dataDir.path)"]
        let pipe = Pipe()
        pgrep.standardOutput = pipe
        pgrep.standardError = Pipe()
        do {
            try pgrep.run()
            pgrep.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let raw = String(data: data, encoding: .utf8) else { return }
            let pids = raw.split(separator: "\n").compactMap { line -> Int32? in
                // pgrep -af prints "PID command…" — first token is the PID.
                guard let pidStr = line.split(separator: " ", maxSplits: 1).first,
                      let pid = Int32(pidStr) else { return nil }
                return pid == ProcessInfo.processInfo.processIdentifier ? nil : pid
            }
            guard !pids.isEmpty else { return }
            log.warning("reaping \(pids.count, privacy: .public) orphan mihomo process(es)")
            for pid in pids {
                kill(pid, SIGTERM)
            }
            // Give them up to 1s to exit cleanly before binding the port.
            usleep(1_000_000)
        } catch {
            log.warning("orphan-cleanup failed: \(String(describing: error), privacy: .public)")
        }
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
        streamClient = nil
        activeBinary = nil
        runtimeSecret = nil
        startedAt = nil
        for task in streamTasks { task.cancel() }
        streamTasks = []
        trafficStore.reset()
        connectionsStore.reset()
        configStore.reset()
    }

    private func startStreams(_ stream: MihomoStreamClient) {
        for task in streamTasks { task.cancel() }
        streamTasks = [
            startLogStream(stream),
            startTrafficStream(stream),
            startMemoryStream(stream),
            startConnectionsStream(stream),
        ]
    }

    private func startLogStream(_ stream: MihomoStreamClient) -> Task<Void, Never> {
        let store = self.logStore
        let notifications = self.notificationCenterStore
        return Task {
            for await event in await stream.logEvents(level: "debug") {
                let mapped: LogStream = switch event.type.lowercased() {
                case "warning": .warning
                case "error":   .error
                case "debug":   .debug
                default:        .info
                }
                store.append(event.payload, stream: mapped)
                if mapped == .warning || mapped == .error {
                    let trimmed = String(event.payload.prefix(200))
                    notifications.post(
                        source: "mihomo",
                        level: mapped == .error ? .error : .warning,
                        message: trimmed
                    )
                }
            }
        }
    }

    private func startTrafficStream(_ stream: MihomoStreamClient) -> Task<Void, Never> {
        let store = self.trafficStore
        let history = self.historyStore
        return Task {
            for await sample in await stream.trafficEvents() {
                store.append(sample)
                history.feed(sample)
            }
        }
    }

    private func startMemoryStream(_ stream: MihomoStreamClient) -> Task<Void, Never> {
        let store = self.trafficStore
        return Task {
            for await sample in await stream.memoryEvents() {
                store.update(memory: sample)
            }
        }
    }

    private func startConnectionsStream(_ stream: MihomoStreamClient) -> Task<Void, Never> {
        let store = self.connectionsStore
        return Task {
            for await snapshot in await stream.connectionsEvents() {
                store.apply(snapshot)
            }
        }
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
