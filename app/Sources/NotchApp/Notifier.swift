import AppKit
import Foundation
import UserNotifications

// Posts real macOS notification banners (e.g. on CI failure). Clicking one opens
// the associated URL.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()
    private var urls: [String: String] = [:]

    func start() {
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func notify(title: String, body: String, url: String?) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let id = UUID().uuidString
        if let url { urls[id] = url }
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }

    // Show the banner even if our (accessory) app happens to be frontmost.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    // Click → open the linked page.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let url = urls[response.notification.request.identifier], let u = URL(string: url) {
            NSWorkspace.shared.open(u)
        }
        completionHandler()
    }
}
