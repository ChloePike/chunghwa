import Foundation
import Observation
import OSLog

@Observable
@MainActor
final class ConnectionsStore {
    private(set) var connections: [MihomoConnection] = []
    private(set) var downloadTotal: Int = 0
    private(set) var uploadTotal: Int = 0

    private let log = Logger(subsystem: "com.tzaigroup.chunghwa", category: "connections")

    func apply(_ snapshot: MihomoConnectionsSnapshot) {
        connections = snapshot.connections ?? []
        downloadTotal = snapshot.downloadTotal ?? 0
        uploadTotal = snapshot.uploadTotal ?? 0
    }

    func reset() {
        connections = []
        downloadTotal = 0
        uploadTotal = 0
    }

    func close(id: String, api: MihomoAPIClient?) async {
        guard let api else { return }
        do {
            try await api.closeConnection(id: id)
            // Optimistically drop from local state — the next snapshot
            // confirms in <1 s.
            connections.removeAll { $0.id == id }
        } catch {
            log.error("close \(id, privacy: .public) failed: \(String(describing: error), privacy: .public)")
        }
    }

    func closeAll(api: MihomoAPIClient?) async {
        guard let api else { return }
        do {
            try await api.closeAllConnections()
            connections = []
        } catch {
            log.error("closeAll failed: \(String(describing: error), privacy: .public)")
        }
    }
}
