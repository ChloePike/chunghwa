import Foundation
import Observation

enum LogStream: String, Sendable {
    case stdout, stderr
}

struct LogLine: Identifiable, Sendable {
    let id: UInt64
    let date: Date
    let stream: LogStream
    let text: String
}

/// Ring buffer of mihomo stdout/stderr lines.
@Observable
@MainActor
final class LogStore {
    private(set) var lines: [LogLine] = []
    let capacity: Int

    private var nextID: UInt64 = 0

    init(capacity: Int = 2000) {
        self.capacity = capacity
        lines.reserveCapacity(capacity)
    }

    func append(_ text: String, stream: LogStream, date: Date = Date()) {
        nextID &+= 1
        let line = LogLine(id: nextID, date: date, stream: stream, text: text)
        if lines.count >= capacity {
            lines.removeFirst(lines.count - capacity + 1)
        }
        lines.append(line)
    }

    func clear() {
        lines.removeAll(keepingCapacity: true)
    }
}
