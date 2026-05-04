import Foundation
import Observation

/// UI-only flag toggled from the toolbar's "anonymous" chip. When on, views
/// that show identifying info (IPs, hostnames, process names) should apply
/// `.blur(radius:)` to those fields. Persisted across launches via
/// UserDefaults so the user doesn't have to re-enable on every screen-share.
@Observable
@MainActor
final class AnonymousMode {
    private let key = "AnonymousMode"

    var enabled: Bool {
        didSet { UserDefaults.standard.set(enabled, forKey: key) }
    }

    init() {
        self.enabled = UserDefaults.standard.bool(forKey: "AnonymousMode")
    }
}
