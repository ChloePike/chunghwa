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
