import Foundation
import Observation
import OSLog
import Network
import Darwin
#if canImport(CoreWLAN)
import CoreWLAN
#endif

/// Aggregates the various probes the Overview "网络状态" card surfaces:
/// internet reachability, DNS latency, gateway latency, current interface
/// type, the local IPv4 address, and (when mihomo is up) the public IP that
/// traffic actually exits from. Each measurement is independent so a single
/// failure (e.g. proxy down) doesn't stall the whole refresh.
@Observable
@MainActor
final class NetworkStatusStore {

    // MARK: - Published state

    private(set) var internetLatencyMs: Int?
    private(set) var dnsLatencyMs: Int?
    private(set) var routerLatencyMs: Int?
    private(set) var networkType: String = "Unknown"
    private(set) var ssid: String?
    private(set) var localIPv4: String?
    private(set) var proxyIPv4: String?
    private(set) var lastUpdated: Date?
    private(set) var isRefreshing: Bool = false

    // MARK: - Internals

    private let log = Logger(subsystem: "com.tzaigroup.chunghwa", category: "network")

    @ObservationIgnored private var pathMonitor: NWPathMonitor?
    @ObservationIgnored private var pathMonitorQueue = DispatchQueue(label: "com.tzaigroup.chunghwa.network.pathmonitor")
    @ObservationIgnored private var currentPath: NWPath?

    @ObservationIgnored private var autoRefreshTask: Task<Void, Never>?

    /// mihomo's default mixed/HTTP proxy port. The probe reads from
    /// `ConfigStore.currentMixedPort` so port changes in Settings flow
    /// through without a separate write here.
    private let proxyHost = "127.0.0.1"
    private var proxyPort: Int { ConfigStore.currentMixedPort }

    private static let autoRefreshInterval: UInt64 = 30 * 1_000_000_000

    init() {
        startPathMonitor()
    }

    deinit {
        autoRefreshTask?.cancel()
        pathMonitor?.cancel()
    }

    // MARK: - Public API

    func refresh() async {
        if isRefreshing { return }
        isRefreshing = true
        defer { isRefreshing = false }

        async let internet = measureInternet()
        async let dns      = measureDNS()
        async let router   = measureRouter()
        async let proxyIP  = measureProxyIP()

        let local = readLocalIPv4()
        let nw    = currentNetworkType()
        let ssidNow = readSSID()

        let internetVal = await internet
        let dnsVal      = await dns
        let routerVal   = await router
        let proxyVal    = await proxyIP

        self.internetLatencyMs = internetVal
        self.dnsLatencyMs      = dnsVal
        self.routerLatencyMs   = routerVal
        self.proxyIPv4         = proxyVal
        self.localIPv4         = local
        self.networkType       = nw
        self.ssid              = ssidNow
        self.lastUpdated       = Date()
    }

    func startAutoRefresh() {
        guard autoRefreshTask == nil else { return }
        autoRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(nanoseconds: NetworkStatusStore.autoRefreshInterval)
            }
        }
    }

    func stop() {
        autoRefreshTask?.cancel()
        autoRefreshTask = nil
    }

    // MARK: - Path monitor

    private func startPathMonitor() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            // Hop back to MainActor so we can mutate the cached path safely.
            Task { @MainActor [weak self] in
                self?.currentPath = path
            }
        }
        monitor.start(queue: pathMonitorQueue)
        self.pathMonitor = monitor
    }

    private func currentNetworkType() -> String {
        guard let path = currentPath else { return "Unknown" }
        if path.usesInterfaceType(.wifi) { return "Wi-Fi" }
        if path.usesInterfaceType(.wiredEthernet) { return "Ethernet" }
        if path.usesInterfaceType(.cellular) { return "Cellular" }
        if path.usesInterfaceType(.loopback) { return "Loopback" }
        if path.status == .satisfied { return "Other" }
        return "Unknown"
    }

    /// CoreWLAN often returns nil under sandboxing or without
    /// `com.apple.developer.networking.wifi-info`; treat that as expected.
    private func readSSID() -> String? {
        #if canImport(CoreWLAN)
        guard currentNetworkType() == "Wi-Fi" else { return nil }
        guard let iface = CWWiFiClient.shared().interface() else { return nil }
        let s = iface.ssid()
        if let s, !s.isEmpty { return s }
        return nil
        #else
        return nil
        #endif
    }

    // MARK: - Local IPv4

    private func readLocalIPv4() -> String? {
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0, let first = ifaddrPtr else { return nil }
        defer { freeifaddrs(ifaddrPtr) }

        // Prefer en0 / en1 (built-in ethernet/wifi); fall back to any other
        // non-loopback IPv4 interface so VPN tun devices still show something.
        var preferred: String?
        var fallback: String?

        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let ptr = cursor {
            let addr = ptr.pointee
            cursor = addr.ifa_next

            guard let saPtr = addr.ifa_addr else { continue }
            let family = saPtr.pointee.sa_family
            guard family == UInt8(AF_INET) else { continue }

            // Skip down/loopback interfaces.
            let flags = Int32(addr.ifa_flags)
            if (flags & IFF_UP) == 0 { continue }
            if (flags & IFF_LOOPBACK) != 0 { continue }

            let name = String(cString: addr.ifa_name)
            if name == "lo0" { continue }

            var hostBuf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let rc = getnameinfo(
                saPtr,
                socklen_t(MemoryLayout<sockaddr_in>.size),
                &hostBuf,
                socklen_t(hostBuf.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            guard rc == 0 else { continue }
            let ip = String(cString: hostBuf)
            if ip.hasPrefix("169.254.") { continue } // link-local

            if name == "en0" || name == "en1" {
                preferred = ip
                break
            } else if fallback == nil {
                fallback = ip
            }
        }

        return preferred ?? fallback
    }

    // MARK: - Internet probe

    private func measureInternet() async -> Int? {
        let url = URL(string: "https://www.gstatic.com/generate_204")!
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 2)
        req.httpMethod = "HEAD"

        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 2
        cfg.timeoutIntervalForResource = 2
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: cfg)
        defer { session.invalidateAndCancel() }

        let start = Date()
        do {
            _ = try await session.data(for: req)
            return Int(Date().timeIntervalSince(start) * 1000)
        } catch {
            log.error("internet probe failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - DNS probe

    /// Times how long it takes an `NWConnection` to reach `.ready`/`.failed`
    /// against `example.com:80`. That lifecycle includes the SRV resolution,
    /// so it doubles as a DNS RTT proxy without needing CFHost.
    private func measureDNS() async -> Int? {
        let host: NWEndpoint.Host = "example.com"
        let port: NWEndpoint.Port = 80
        let params = NWParameters.tcp
        let conn = NWConnection(host: host, port: port, using: params)

        let start = Date()
        let result: Bool = await withCheckedContinuation { cont in
            let queue = DispatchQueue(label: "com.tzaigroup.chunghwa.network.dnsprobe")
            var settled = false
            conn.stateUpdateHandler = { state in
                guard !settled else { return }
                switch state {
                case .ready:
                    settled = true
                    cont.resume(returning: true)
                case .failed, .cancelled:
                    settled = true
                    cont.resume(returning: false)
                default: break
                }
            }
            conn.start(queue: queue)

            // Timeout guard: 3s is generous; resolver usually returns in <500ms.
            queue.asyncAfter(deadline: .now() + 3) {
                guard !settled else { return }
                settled = true
                cont.resume(returning: false)
            }
        }
        conn.cancel()
        if !result {
            log.error("dns probe did not reach ready")
            return nil
        }
        return Int(Date().timeIntervalSince(start) * 1000)
    }

    // MARK: - Router probe

    /// ICMP requires root, so we approximate by opening a TCP connection to
    /// the default gateway on a common port. Works on most home routers
    /// (which expose 80 for the admin UI), silently nils out otherwise.
    private func measureRouter() async -> Int? {
        guard let gateway = readDefaultGateway() else {
            log.error("router probe: no default gateway")
            return nil
        }

        // Try 80 first, then 443 if the first attempt fails — many ISPs ship
        // routers with HTTPS-only admin UIs.
        for port in [UInt16(80), UInt16(443)] {
            if let ms = await tcpConnectLatencyMs(host: gateway, port: port, timeout: 1.5) {
                return ms
            }
        }
        log.error("router probe failed to connect to \(gateway, privacy: .public)")
        return nil
    }

    private func tcpConnectLatencyMs(host: String, port: UInt16, timeout: TimeInterval) async -> Int? {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return nil }
        let conn = NWConnection(
            host: NWEndpoint.Host(host),
            port: nwPort,
            using: .tcp
        )
        let start = Date()
        let ok: Bool = await withCheckedContinuation { cont in
            let queue = DispatchQueue(label: "com.tzaigroup.chunghwa.network.tcpprobe")
            var settled = false
            conn.stateUpdateHandler = { state in
                guard !settled else { return }
                switch state {
                case .ready:
                    settled = true
                    cont.resume(returning: true)
                case .failed, .cancelled:
                    settled = true
                    cont.resume(returning: false)
                default: break
                }
            }
            conn.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) {
                guard !settled else { return }
                settled = true
                cont.resume(returning: false)
            }
        }
        conn.cancel()
        return ok ? Int(Date().timeIntervalSince(start) * 1000) : nil
    }

    /// Parses `route -n get default` output for the `gateway:` line.
    /// Synchronous: it's fast (usually <20ms) and simpler than launching it
    /// through Process+pipe ceremony in the hot path of an async probe.
    private func readDefaultGateway() -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/sbin/route")
        proc.arguments = ["-n", "get", "default"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        do {
            try proc.run()
        } catch {
            log.error("route launch failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        proc.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let out = String(data: data, encoding: .utf8) else { return nil }
        for line in out.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("gateway:") {
                let parts = trimmed.split(separator: ":", maxSplits: 1)
                if parts.count == 2 {
                    return parts[1].trimmingCharacters(in: .whitespaces)
                }
            }
        }
        return nil
    }

    // MARK: - Proxy egress IP

    /// Routes a request through mihomo's HTTP proxy and asks ipify what the
    /// far-end address looks like. nil whenever mihomo isn't up, the proxy
    /// can't egress, or the request times out.
    private func measureProxyIP() async -> String? {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 4
        cfg.timeoutIntervalForResource = 4
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        cfg.connectionProxyDictionary = [
            kCFNetworkProxiesHTTPEnable as String: true,
            kCFNetworkProxiesHTTPProxy as String: proxyHost,
            kCFNetworkProxiesHTTPPort as String: proxyPort,
            // No public CFNetwork constants for HTTPS proxy on macOS — these
            // string keys are the documented workaround.
            "HTTPSEnable": true,
            "HTTPSProxy": proxyHost,
            "HTTPSPort": proxyPort,
        ]

        let session = URLSession(configuration: cfg)
        defer { session.invalidateAndCancel() }

        guard let url = URL(string: "https://api.ipify.org") else { return nil }
        let req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 4)
        do {
            let (data, _) = try await session.data(for: req)
            guard let raw = String(data: data, encoding: .utf8) else { return nil }
            let ip = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return ip.isEmpty ? nil : ip
        } catch {
            log.error("proxy IP probe failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
