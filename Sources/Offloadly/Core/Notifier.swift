import Foundation
import UserNotifications

/// Thin wrapper around UNUserNotificationCenter for "download finished" alerts.
/// No-ops gracefully if the app can't register (e.g. not a proper bundle).
enum Notifier {
    private static var center: UNUserNotificationCenter? {
        // UNUserNotificationCenter.current() requires a bundle identifier;
        // guard so a non-bundled dev run can't crash.
        guard Bundle.main.bundleIdentifier != nil else { return nil }
        return UNUserNotificationCenter.current()
    }

    static func requestAuthorization() {
        center?.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func downloadFinished(title: String) {
        guard let center else { return }
        let content = UNMutableNotificationContent()
        content.title = "Download complete"
        content.body = title
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: UUID().uuidString, content: content, trigger: nil)
        center.add(request, withCompletionHandler: nil)
    }
}
