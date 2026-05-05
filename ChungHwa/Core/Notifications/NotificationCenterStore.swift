import Foundation
import Observation
import UserNotifications

/// In-memory ring buffer of recent app-level notifications (errors / warnings /
/// info). Surfaced through the toolbar bell popover.
///
/// We post here in addition to the transient `BannerErrorBus` so that users who
/// miss the auto-dismissing banner can still find what just went wrong. The
/// store is intentionally tiny (50 entries) and process-lifetime-only — it is
/// not persisted across launches.
///
/// `warning` / `error` levels are also forwarded to macOS Notification Center
/// (`UNUserNotificationCenter`) so the user notices problems even when the
/// main window is closed. `info` level stays in-app only — those are routine
/// status updates, not worth the system-wide buzz.
@Observable
@MainActor
final class NotificationCenterStore {
    enum Level: String, Sendable, CaseIterable {
        case info, warning, error
    }

    struct Entry: Identifiable, Sendable, Equatable {
        let id: UUID
        let source: String
        let message: String
        let level: Level
        let posted: Date
    }

    /// Newest first. Capped at `capacity`.
    private(set) var entries: [Entry] = []

    /// Number of entries posted since the bell popover was last opened.
    private(set) var unreadCount: Int = 0

    let capacity: Int

    init(capacity: Int = 50) {
        self.capacity = capacity
        Task { await Self.requestAuthorizationIfNeeded() }
    }

    /// Record a new notification. No-op when `message` is nil or empty.
    func post(source: String, level: Level, message: String?) {
        guard let message, !message.isEmpty else { return }
        let entry = Entry(
            id: UUID(),
            source: source,
            message: message,
            level: level,
            posted: Date()
        )
        entries.insert(entry, at: 0)
        if entries.count > capacity {
            entries.removeLast(entries.count - capacity)
        }
        unreadCount += 1

        if level != .info {
            Self.deliverSystemNotification(source: source, message: message, level: level)
        }
    }

    // MARK: - System notifications (UNUserNotificationCenter)

    private static func requestAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    private static func deliverSystemNotification(
        source: String,
        message: String,
        level: Level
    ) {
        let content = UNMutableNotificationContent()
        content.title = source
        content.body = message
        if level == .error {
            content.sound = .defaultCritical
        } else {
            content.sound = .default
        }
        let req = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(req) { _ in }
    }

    /// Clear the unread badge without removing any entries.
    func markAllRead() {
        unreadCount = 0
    }

    /// Drop everything and reset the badge.
    func clear() {
        entries.removeAll(keepingCapacity: true)
        unreadCount = 0
    }
}
