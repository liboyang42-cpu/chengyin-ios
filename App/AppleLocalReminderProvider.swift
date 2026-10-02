import Foundation
import UserNotifications

/// No APNs registration or remote subscription. Generic notification text avoids
/// exposing the account, route title, or gameplay details on a locked screen.
@MainActor final class AppleLocalReminderProvider: NativeLocalReminderProviding {
    static let prefix = "questify.native-window.v1."
    private let enabled: Bool
    private let center: UNUserNotificationCenter
    init(enabled: Bool = false, center: UNUserNotificationCenter = .current()) { self.enabled = enabled; self.center = center }
    func permission() async -> NativePlatformPermission {
        guard enabled else { return .unsupported }
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .authorized: return settings.alertSetting == .enabled ? .allowed : .denied
        case .provisional, .ephemeral: return .denied // Require the requested visible one-time alert.
        @unknown default: return .unsupported
        }
    }
    func requestPermission() async throws -> NativePlatformPermission {
        guard enabled else { throw NativePlatformIssue.disabled }
        if await permission() == .notDetermined { _ = try await center.requestAuthorization(options: [.alert, .sound]) }
        return await permission()
    }
    func pending() async -> [NativeLocalReminder] {
        guard enabled else { return [] }
        return await center.pendingNotificationRequests().compactMap { request in
            guard request.identifier.hasPrefix(Self.prefix), let trigger = request.trigger as? UNCalendarNotificationTrigger,
                  !trigger.repeats, let date = trigger.nextTriggerDate(),
                  let owner = request.content.userInfo["owner"] as? String,
                  let revision = request.content.userInfo["windowRevision"] as? String,
                  let zone = request.content.userInfo["timeZone"] as? String else { return nil }
            return NativeLocalReminder(identifier: request.identifier, owner: owner, windowRevision: revision, fireAt: date, timeZone: zone)
        }
    }
    func replace(_ reminder: NativeLocalReminder, title: String, body: String) async throws {
        guard enabled else { throw NativePlatformIssue.disabled }
        guard await permission() == .allowed else { throw NativePlatformIssue.denied }
        guard reminder.identifier.hasPrefix(Self.prefix), TimeZone(identifier: reminder.timeZone) != nil, reminder.fireAt > Date() else { throw NativePlatformIssue.expired }
        // UTC absolute components preserve the exact server instant through travel,
        // daylight-saving transitions and a changed phone timezone.
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: reminder.fireAt)
        components.calendar = calendar; components.timeZone = calendar.timeZone
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        guard let next = trigger.nextTriggerDate(), abs(next.timeIntervalSince(reminder.fireAt)) < 1 else { throw NativePlatformIssue.expired }
        let content = UNMutableNotificationContent(); content.title = title; content.body = body; content.sound = .default
        content.userInfo = ["owner": reminder.owner, "windowRevision": reminder.windowRevision, "timeZone": reminder.timeZone]
        cancel(identifier: reminder.identifier)
        try await center.add(UNNotificationRequest(identifier: reminder.identifier, content: content, trigger: trigger))
    }
    func cancel(identifier: String) {
        guard enabled, identifier.hasPrefix(Self.prefix) else { return }
        center.removePendingNotificationRequests(withIdentifiers: [identifier]); center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }
    func cancelAllOwned(owner: String) {
        guard enabled else { return }
        // Fetch only our namespace. Never remove another feature's notifications.
        let prefix = Self.prefix
        center.getPendingNotificationRequests { [center] requests in
            let ids = requests.filter { $0.identifier.hasPrefix(prefix) && $0.content.userInfo["owner"] as? String == owner }.map(\.identifier)
            center.removePendingNotificationRequests(withIdentifiers: ids)
        }
        center.getDeliveredNotifications { [center] notifications in
            let ids = notifications.filter { $0.request.identifier.hasPrefix(prefix) && $0.request.content.userInfo["owner"] as? String == owner }.map { $0.request.identifier }
            center.removeDeliveredNotifications(withIdentifiers: ids)
        }
    }
}
