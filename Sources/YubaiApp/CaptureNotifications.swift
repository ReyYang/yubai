#if os(iOS)
import Foundation
import UserNotifications
import YubaiCore

final class CaptureNotificationDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = CaptureNotificationDelegate()
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) { completionHandler([.banner, .sound]) }
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        guard let raw = response.notification.request.content.userInfo["entryID"] as? String, let id = UUID(uuidString: raw) else { completionHandler(); return }
        Task { @MainActor in
            defer { completionHandler() }
            let store = AppStore.shared
            if response.actionIdentifier == "capture.undo" {
                do { try store.captureUpdate("撤销这笔") { QuickCapture.undo(entryID: id, in: &$0) }; CaptureNotifications.remove(id: id) }
                catch { store.error = error.localizedDescription }
            } else if response.actionIdentifier != UNNotificationDismissActionIdentifier { store.requestCaptureSheet(.editEntry(id)) }
        }
    }
}
enum CaptureNotifications {
    static func register() {
        let center = UNUserNotificationCenter.current(); center.delegate = CaptureNotificationDelegate.shared
        let edit = UNNotificationAction(identifier: "capture.edit", title: "改一下", options: [.foreground])
        let undo = UNNotificationAction(identifier: "capture.undo", title: "撤销这笔", options: [.destructive])
        center.setNotificationCategories([UNNotificationCategory(identifier: "quick-capture", actions: [edit, undo], intentIdentifiers: [])])
    }
    static func requestPermission() async -> Bool { (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false }
    static func post(entry: Entry, ledger: Ledger) async {
        let center = UNUserNotificationCenter.current()
        // 自动化不弹权限框；首次设置在「快速记账」里由用户开启。
        let settings = await center.notificationSettings()
        guard [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus) else { return }
        let content = UNMutableNotificationContent(); content.title = "余白"; content.sound = .default
        let privateResult = ledger.preferences.lockEnabled || ledger.preferences.hideAmounts
        if privateResult { content.body = "已记下 " + (ledger.preferences.hideAmounts ? "••••" : Money.text(entry.amount)) }
        else {
            let category = entry.hasNoCaptureCategory ? "先放在 其他支出" : entry.category
            content.body = "已记下 " + entry.displayTitle + " " + Money.text(entry.amount) + " · " + category + " · " + ledger.accountName(entry.accountID)
        }
        content.body += "\n还能花 " + (ledger.preferences.hideAmounts ? "••••" : Money.text(QuickCapture.available(in: ledger))) + " · 轻点改一下"
        content.categoryIdentifier = "quick-capture"; content.userInfo = ["entryID": entry.id.uuidString]
        try? await center.add(UNNotificationRequest(identifier: entry.id.uuidString, content: content, trigger: nil))
    }
    static func remove(id: UUID) {
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [id.uuidString])
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id.uuidString])
    }
}
#endif
