import Foundation

enum MihomoAPIError: Error, CustomStringConvertible {
    case invalidResponse
    case httpStatus(Int, body: String?)
    case transport(any Error)
    case decoding(any Error)

    var description: String {
        switch self {
        case .invalidResponse:
            return "invalid HTTP response"
        case .httpStatus(let code, let body):
            return "HTTP \(code): \(body ?? "<no body>")"
        case .transport(let e):
            return "transport: \(e)"
        case .decoding(let e):
            return "decoding: \(e)"
        }
    }
}

private nonisolated struct ReloadConfigBody: Encodable, Sendable {
    let path: String
}

private nonisolated struct SelectProxyBody: Encodable, Sendable {
    let name: String
}

/// Body for `PATCH /configs`. All fields are optional — only non-nil
/// fields are encoded so we can hot-patch a single setting without
/// clobbering anything else mihomo currently has.
///
/// `JSONEncoder` does *not* skip nil Optionals automatically (it emits
/// `"key": null`), so we drive the keyed container manually with
/// `encodeIfPresent`.
/// Body for `PATCH /configs` carrying a nested `tun` block. Mihomo accepts a
/// partial nested object here — fields we omit are left untouched. We always
/// send the full block we care about so the kernel doesn't end up with a
/// half-configured TUN (e.g. enabled but with no auto-route).
private nonisolated struct PatchTunBody: Encodable, Sendable {
    struct Tun: Encodable, Sendable {
        let enable: Bool
        let stack: String
        let autoRoute: Bool
        let autoDetectInterface: Bool
        let dnsHijack: [String]

        enum CodingKeys: String, CodingKey {
            case enable, stack
            case autoRoute = "auto-route"
            case autoDetectInterface = "auto-detect-interface"
            case dnsHijack = "dns-hijack"
        }
    }
    let tun: Tun
}

/// Body for `PATCH /configs` carrying the nested `dns` block. Like the TUN
/// patch, mihomo accepts a partial nested object and merges into the running
/// config, but to avoid leaving half-configured DNS we always send the full
/// shape.
private nonisolated struct PatchDNSBody: Encodable, Sendable {
    struct DNS: Encodable, Sendable {
        let enable: Bool
        let listen: String?
        let enhancedMode: String
        let fakeIPRange: String
        let nameserver: [String]
        let fallback: [String]

        enum CodingKeys: String, CodingKey {
            case enable, listen
            case enhancedMode = "enhanced-mode"
            case fakeIPRange = "fake-ip-range"
            case nameserver, fallback
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(enable, forKey: .enable)
            try c.encodeIfPresent(listen, forKey: .listen)
            try c.encode(enhancedMode, forKey: .enhancedMode)
            try c.encode(fakeIPRange, forKey: .fakeIPRange)
            try c.encode(nameserver, forKey: .nameserver)
            try c.encode(fallback, forKey: .fallback)
        }
    }
    let dns: DNS
}

private nonisolated struct PatchConfigBody: Encodable, Sendable {
    var mode: String?
    var logLevel: String?
    var allowLan: Bool?
    var ipv6: Bool?
    var tcpConcurrent: Bool?

    enum CodingKeys: String, CodingKey {
        case mode
        case logLevel = "log-level"
        case allowLan = "allow-lan"
        case ipv6
        case tcpConcurrent = "tcp-concurrent"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(mode,          forKey: .mode)
        try c.encodeIfPresent(logLevel,      forKey: .logLevel)
        try c.encodeIfPresent(allowLan,      forKey: .allowLan)
        try c.encodeIfPresent(ipv6,          forKey: .ipv6)
        try c.encodeIfPresent(tcpConcurrent, forKey: .tcpConcurrent)
    }
}

actor MihomoAPIClient {
    let baseURL: URL
    private let secret: String
    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(baseURL: URL, secret: String) {
        self.baseURL = baseURL
        self.secret = secret
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 5
        self.session = URLSession(configuration: config)
    }

    // MARK: - endpoints

    func version() async throws -> MihomoVersion {
        try await sendDecoding("/version", method: "GET")
    }

    /// Ask mihomo to re-read the on-disk config and hot-reload — no process restart.
    func reloadConfig(path: String, force: Bool = true) async throws {
        let query = force ? [URLQueryItem(name: "force", value: "true")] : []
        try await sendVoid("/configs", method: "PUT", query: query, body: ReloadConfigBody(path: path))
    }

    func proxies() async throws -> MihomoProxiesSnapshot {
        try await sendDecoding("/proxies", method: "GET")
    }

    func config() async throws -> MihomoConfig {
        try await sendDecoding("/configs", method: "GET")
    }

    /// Switch outbound mode. `mode` must be `rule`, `global`, or `direct`.
    func setMode(_ mode: MihomoMode) async throws {
        try await sendVoid("/configs", method: "PATCH", body: PatchConfigBody(mode: mode.rawValue))
    }

    /// Hot-patch the kernel's log verbosity. Accepts mihomo's canonical
    /// values: `silent`, `error`, `warning`, `info`, `debug`. (The UI
    /// uses "warn" so callers should normalize as needed.)
    func setLogLevel(_ level: String) async throws {
        try await sendVoid("/configs", method: "PATCH", body: PatchConfigBody(logLevel: level))
    }

    /// Toggle whether mihomo accepts inbound connections from the LAN
    /// (i.e. binds the inbound listener to 0.0.0.0 vs 127.0.0.1).
    func setAllowLan(_ allow: Bool) async throws {
        try await sendVoid("/configs", method: "PATCH", body: PatchConfigBody(allowLan: allow))
    }

    /// Toggle IPv6 support in the kernel.
    func setIPv6(_ enabled: Bool) async throws {
        try await sendVoid("/configs", method: "PATCH", body: PatchConfigBody(ipv6: enabled))
    }

    /// Toggle TCP-concurrent dialing (race multiple TCP streams to a node).
    func setTCPConcurrent(_ enabled: Bool) async throws {
        try await sendVoid("/configs", method: "PATCH", body: PatchConfigBody(tcpConcurrent: enabled))
    }

    /// Push a fresh `dns` block to the running kernel. Mirrors the TUN patch:
    /// we send the entire nested object so the kernel never ends up with a
    /// half-configured resolver. First-boot still needs the YAML composer.
    func setDNS(_ prefs: DNSPrefs) async throws {
        let body = PatchDNSBody(dns: .init(
            enable: true,
            listen: prefs.hijackEnabled ? "0.0.0.0:53" : nil,
            enhancedMode: prefs.enhancedMode,
            fakeIPRange: "198.18.0.1/16",
            nameserver: prefs.nameservers,
            fallback: prefs.fallback
        ))
        try await sendVoid("/configs", method: "PATCH", body: body)
    }

    /// Toggle TUN mode at runtime via a nested `tun` block PATCH. The kernel
    /// still needs the bits baked into the start-up yaml (see ConfigComposer)
    /// for the very first boot — this call only matters once the API is up.
    func setTUN(enabled: Bool) async throws {
        let body = PatchTunBody(tun: .init(
            enable: enabled,
            stack: "gvisor",
            autoRoute: true,
            autoDetectInterface: true,
            dnsHijack: ["any:53"]
        ))
        try await sendVoid("/configs", method: "PATCH", body: body)
    }

    /// Switch the upstream choice of a Selector group.
    func selectProxy(group: String, name: String) async throws {
        try await sendVoid("/proxies/\(escape(group))",
                           method: "PUT",
                           body: SelectProxyBody(name: name))
    }

    /// Probe a single proxy's latency. Returns nil for "timeout / unreachable"
    /// (mihomo answers HTTP 200 with `{"message": "..."}` and no delay).
    func proxyDelay(name: String,
                    testURL: String = "https://www.gstatic.com/generate_204",
                    timeoutMS: Int = 2500) async throws -> Int? {
        let resp: MihomoDelayResponse = try await sendDecoding(
            "/proxies/\(escape(name))/delay",
            method: "GET",
            query: [
                URLQueryItem(name: "url", value: testURL),
                URLQueryItem(name: "timeout", value: String(timeoutMS)),
            ])
        if let d = resp.delay, d > 0 { return d }
        return nil
    }

    func closeConnection(id: String) async throws {
        _ = try await send(makeRequest(path: "/connections/\(escape(id))", method: "DELETE"))
    }

    func closeAllConnections() async throws {
        _ = try await send(makeRequest(path: "/connections", method: "DELETE"))
    }

    /// Test latency of every node in a group in a single call. Returns
    /// `[node-name: ms]`; nodes that timed out are omitted.
    func groupDelay(group: String,
                    testURL: String = "https://www.gstatic.com/generate_204",
                    timeoutMS: Int = 2500) async throws -> [String: Int] {
        let req = makeRequest(
            path: "/group/\(escape(group))/delay",
            method: "GET",
            query: [
                URLQueryItem(name: "url", value: testURL),
                URLQueryItem(name: "timeout", value: String(timeoutMS)),
            ])
        let data = try await send(req)
        do {
            return try decoder.decode([String: Int].self, from: data)
        } catch {
            throw MihomoAPIError.decoding(error)
        }
    }

    func rules() async throws -> [MihomoRule] {
        let r: MihomoRulesResponse = try await sendDecoding("/rules", method: "GET")
        return r.rules
    }

    func ruleProviders() async throws -> [MihomoRuleProvider] {
        let r: MihomoRuleProvidersResponse = try await sendDecoding("/providers/rules", method: "GET")
        return r.providers.values.sorted { $0.name < $1.name }
    }

    func updateRuleProvider(name: String) async throws {
        _ = try await send(makeRequest(path: "/providers/rules/\(escape(name))", method: "PUT"))
    }

    func proxyProviders() async throws -> [MihomoProxyProvider] {
        let r: MihomoProxyProvidersResponse = try await sendDecoding("/providers/proxies", method: "GET")
        return r.providers.values.sorted { $0.name < $1.name }
    }

    func updateProxyProvider(name: String) async throws {
        _ = try await send(makeRequest(path: "/providers/proxies/\(escape(name))", method: "PUT"))
    }

    func healthcheckProxyProvider(name: String) async throws {
        _ = try await send(makeRequest(path: "/providers/proxies/\(escape(name))/healthcheck", method: "GET"))
    }

    private nonisolated func escape(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? s
    }

    // MARK: - request helpers

    private func makeRequest(
        path: String,
        method: String,
        query: [URLQueryItem] = [],
        bodyData: Data? = nil
    ) -> URLRequest {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var req = URLRequest(url: components.url!)
        req.httpMethod = method
        if !secret.isEmpty {
            req.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        }
        if let bodyData {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = bodyData
        }
        return req
    }

    private func send(_ req: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw MihomoAPIError.transport(error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw MihomoAPIError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw MihomoAPIError.httpStatus(http.statusCode, body: String(data: data, encoding: .utf8))
        }
        return data
    }

    private func sendDecoding<T: Decodable>(
        _ path: String,
        method: String,
        query: [URLQueryItem] = []
    ) async throws -> T {
        let data = try await send(makeRequest(path: path, method: method, query: query))
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw MihomoAPIError.decoding(error)
        }
    }

    private func sendVoid<B: Encodable>(
        _ path: String,
        method: String,
        query: [URLQueryItem] = [],
        body: B
    ) async throws {
        let bodyData: Data
        do {
            bodyData = try encoder.encode(body)
        } catch {
            throw MihomoAPIError.decoding(error)
        }
        _ = try await send(makeRequest(path: path, method: method, query: query, bodyData: bodyData))
    }
}
