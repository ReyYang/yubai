import Foundation
import UserNotifications
import YubaiCore

@MainActor enum WeeklyPush {
    static let identifier = "yubai.weekly-letter"
    private static var revision = 0
    private static var desiredEnabled = false
    // Only the explicit settings action calls requestAuthorization. Restoration,
    // undo and app launch synchronize the one repeating request without prompting.
    static func sync(enabled: Bool) async {
        revision &+= 1; let requestRevision = revision; desiredEnabled = enabled
        let center = UNUserNotificationCenter.current()
        guard enabled else {
            center.removePendingNotificationRequests(withIdentifiers: [identifier])
            center.removeDeliveredNotifications(withIdentifiers: [identifier]); return
        }
        let settings = await center.notificationSettings()
        guard requestRevision == revision else { return }
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        let content = UNMutableNotificationContent()
        content.title = "余白"; content.body = "这周的来信写好了"
        var date = DateComponents(); date.weekday = 2; date.hour = 9; date.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: date, repeats: true)
        try? await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
        if !desiredEnabled { center.removePendingNotificationRequests(withIdentifiers: [identifier]) }
    }
}

@MainActor extension AppStore {
    func setWeeklyLetterPush(_ enabled: Bool) async {
        guard !updatingWeeklyPush else { return }
        let id = current.id
        updatingWeeklyPush = true
        defer { updatingWeeklyPush = false }
        if enabled {
            do {
                let allowed = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert])
                guard allowed else { error = "每周来信提醒尚未开启，可以在系统通知设置中允许余白发送通知。"; return }
            } catch { self.error = "暂时无法开启每周来信提醒。"; return }
        }
        guard current.id == id, !locked else { return }
        if update("保存来信提醒", { $0.preferences.weeklyLetterPush = enabled }) {
            await WeeklyPush.sync(enabled: enabled)
        }
    }
}
