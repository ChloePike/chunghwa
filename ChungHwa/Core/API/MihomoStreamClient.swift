import Foundation
import OSLog

/// Long-lived WebSocket consumer for mihomo's streaming endpoints
/// (`/logs`, `/traffic`, `/connections`, `/memory`).
///
/// Each `*Events` method returns an `AsyncStream` that:
///   1. Opens a WebSocket task with the bearer secret in the
///      `Authorization` header.
///   2. Decodes incoming JSON text frames into typed events.
///   3. On disconnect, sleeps with exponential backoff (1s → 2s → 4s,
///      capped at 8s) and reconnects, until the consumer task is
///      cancelled. Mihomo will only ever close these streams when the
///      kernel itself is going away, so reconnect-forever is correct.
actor MihomoStreamClient {
    let baseURL: URL
    private let secret: String
    private let session: URLSession
    private let log = Logger(subsystem: "com.tzaigroup.chunghwa", category: "stream")

    init(baseURL: URL, secret: String) {
        self.baseURL = baseURL
        self.secret = secret
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 0      // streams are long-lived
        cfg.timeoutIntervalForResource = 0
        cfg.waitsForConnectivity = true
        self.session = URLSession(configuration: cfg)
    }

    func logEvents(level: String = "info") -> AsyncStream<MihomoLogEvent> {
        events(path: "/logs", query: [URLQueryItem(name: "level", value: level)])
    }

    private func events<E: Decodable & Sendable>(
        path: String,
        query: [URLQueryItem] = []
    ) -> AsyncStream<E> {
        let url = streamURL(path: path, query: query)
        let request = makeRequest(url: url)
        let session = self.session
        let log = self.log
        return AsyncStream<E> { continuation in
            let task = Task {
                let decoder = JSONDecoder()
                var attempt = 0
                while !Task.isCancelled {
                    let ws = session.webSocketTask(with: request)
                    ws.resume()
                    log.debug("ws connected \(path, privacy: .public) attempt=\(attempt, privacy: .public)")
                    attempt = 0
                    do {
                        while !Task.isCancelled {
                            let message = try await ws.receive()
                            let data = try data(from: message)
                            if let event = try? decoder.decode(E.self, from: data) {
                                continuation.yield(event)
                            }
                        }
                    } catch {
                        log.warning("ws \(path, privacy: .public) closed: \(String(describing: error), privacy: .public)")
                    }
                    ws.cancel(with: .goingAway, reason: nil)
                    if Task.isCancelled { break }
                    attempt += 1
                    let backoffNs = UInt64(min(8, 1 << min(attempt, 3))) * 1_000_000_000
                    try? await Task.sleep(nanoseconds: backoffNs)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private nonisolated func streamURL(path: String, query: [URLQueryItem]) -> URL {
        var c = URLComponents(url: baseURL.appendingPathComponent(path),
                              resolvingAgainstBaseURL: false)!
        if !query.isEmpty { c.queryItems = query }
        // `ws://` is what URLSessionWebSocketTask expects when constructed
        // from a URL; the http→ws scheme swap is intentional.
        if c.scheme == "http"  { c.scheme = "ws" }
        if c.scheme == "https" { c.scheme = "wss" }
        return c.url!
    }

    private nonisolated func makeRequest(url: URL) -> URLRequest {
        var req = URLRequest(url: url)
        if !secret.isEmpty {
            req.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        }
        return req
    }

    private nonisolated func data(from message: URLSessionWebSocketTask.Message) throws -> Data {
        switch message {
        case .data(let d):   return d
        case .string(let s): return Data(s.utf8)
        @unknown default:    return Data()
        }
    }
}
