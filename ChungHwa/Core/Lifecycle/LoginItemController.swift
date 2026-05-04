import Foundation
import Observation
import OSLog
import ServiceManagement

@Observable
@MainActor
final class LoginItemController {
    private(set) var isRegistered: Bool = SMAppService.mainApp.status == .enabled
    private(set) var lastError: String?
    private let log = Logger(subsystem: "com.tzaigroup.chunghwa", category: "loginitem")

    func refresh() {
        isRegistered = SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            lastError = nil
        } catch {
            lastError = String(describing: error)
            log.error("login item toggle failed: \(self.lastError ?? "?", privacy: .public)")
        }
        refresh()
    }
}
