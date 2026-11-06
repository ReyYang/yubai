import Foundation
import UserNotifications
import SwiftUI
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
        content.title = "余白"; content.body = "每周来信写好了"
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
                guard allowed else { return }
            } catch { self.error = "暂时无法开启每周来信提醒。"; return }
        }
        guard current.id == id, !locked else { return }
        if update("保存每周来信提醒", { $0.preferences.weeklyLetterPush = enabled }) {
            await WeeklyPush.sync(enabled: enabled)
        }
    }
}

struct WeeklyLetterReminder: View {
    @Environment(AppStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var denied = false
    var body: some View {
        VStack(alignment: .leading, spacing: YubaiSpace.space8) {
            Toggle("每周来信提醒", isOn: Binding(get: { store.preferences.weeklyLetterPush }, set: { value in
                Task { await store.setWeeklyLetterPush(value); await refresh() }
            })).tint(YubaiColor.toggleOn).disabled(store.updatingWeeklyPush).frame(minHeight: YubaiSize.rowSingle)
            if denied {
                HStack(spacing: YubaiSpace.space8) {
                    Text("通知没开").yubaiFont(YubaiFont.caption)
                    Spacer()
                    SystemSettingsButton(title: "去打开", pane: .notifications)
                }.foregroundStyle(YubaiColor.amberInk)
            }
        }.task { await refresh() }
            .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await refresh() } } }
    }
    private func refresh() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        denied = settings.authorizationStatus == .denied
    }
}
