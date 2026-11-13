import SwiftUI
import UserNotifications
import YubaiCore

@MainActor enum ButlerNoticeDelivery {
    private static var revision = 0
    static func sync(_ ledger: Ledger, now: Date) async {
        revision &+= 1
        let requested = revision
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        let enabled = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
        let notices: [ButlerNotice]
        if enabled { notices = await Task.detached(priority: .utility) { ButlerNotices.planned(ledger, now: now) }.value }
        else { notices = [] }
        guard requested == revision else { return }
        let prefix = "yubai.butler." + ledger.id.uuidString + "."
        let defaults = UserDefaults.standard
        let pending = (await center.pendingNotificationRequests()).filter { $0.identifier.hasPrefix("yubai.butler.") }
        guard requested == revision else { return }
        let desired = Set(notices.map { prefix + $0.id })
        let removed = pending.map(\.identifier).filter { !desired.contains($0) }
        center.removePendingNotificationRequests(withIdentifiers: removed)
        for key in removed where (defaults.object(forKey: key) as? Date).map({ $0 > now }) == true { defaults.removeObject(forKey: key) }
        for notice in notices {
            guard requested == revision else { return }
            let key = prefix + notice.id
            if let reserved = defaults.object(forKey: key) as? Date, reserved <= now { continue }
            let content = UNMutableNotificationContent()
            content.title = notice.copy.kicker; content.body = notice.copy.title
            content.userInfo = ["butlerTaskID": notice.taskID]
            content.interruptionLevel = notice.tier == .immediate ? .timeSensitive : .active
            let trigger: UNNotificationTrigger?
            if notice.fireDate > now.addingTimeInterval(1) {
                let parts = Dates.calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: notice.fireDate)
                trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            } else { trigger = nil }
            do {
                try await center.add(UNNotificationRequest(identifier: key, content: content, trigger: trigger))
                defaults.set(notice.fireDate, forKey: key)
            } catch { /* A failed local schedule is retried on the next refresh. */ }
        }
    }
}

@MainActor extension AppStore {
    func setButlerNotice(_ tier: ButlerNoticeTier, enabled: Bool) async {
        let ledgerID = current.id
        if enabled && tier != .home {
            do {
                guard try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) else { error = "通知权限没开"; return }
            } catch { self.error = "暂时无法开启通知"; return }
        }
        guard current.id == ledgerID, !locked else { return }
        _ = update(tier.title, recordUndo: false, showToast: false) {
            var settings = $0.preferences.butlerNotices ?? ButlerNoticePreferences()
            settings[tier] = enabled; $0.preferences.butlerNotices = settings
        }
    }
    func openButlerNotice(_ id: String) {
        if locked { pendingButlerTaskID = id; return }
        resetRootNavigation()
        if homeTasks.contains(where: { $0.id == id }) { butlerFocusID = id }
    }
}

struct ButlerNoticeSettings: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        Card(style: .list) {
            VStack(spacing: YubaiSpace.none) {
                ForEach(ButlerNoticeTier.allCases) { tier in
                    Toggle(tier.title, isOn: Binding(get: {
                        (store.preferences.butlerNotices ?? ButlerNoticePreferences())[tier]
                    }, set: { value in Task { await store.setButlerNotice(tier, enabled: value) } }))
                        .tint(YubaiColor.toggleOn).frame(minHeight: YubaiSize.rowSingle)
                        .accessibilityIdentifier("butlerNotice_" + tier.rawValue)
                    if tier != .home { EntryFormDivider() }
                }
            }
        }.accessibilityIdentifier("butlerNoticeSettings")
    }
}

struct ButlerNoticeSyncTask: ViewModifier {
    @Environment(AppStore.self) private var store
    func body(content: Content) -> some View {
        content.task(id: "\(store.ledgerRevision)-\(Dates.text(store.financialNow))-\(store.locked)") {
            guard !store.locked else { return }
            await ButlerNoticeDelivery.sync(store.current, now: store.financialNow)
        }
    }
}
