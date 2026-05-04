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

private nonisolated struct PatchConfigBody: Encodable, Sendable {
    let mode: String
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

    /// 让 mihomo 重新读取磁盘上的配置文件并热加载，无需重启进程。
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
