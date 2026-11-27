import Foundation
import os
import YubaiCore
#if canImport(WidgetKit)
import WidgetKit
#endif

/// 主币种 only changes display. Every amount that goes through `HomeDisplay.money` is shown in the
/// main currency at this device's latest synced rate; the ledger stays in CNY.
enum DisplayCurrency {
    /// Written on the main actor whenever the ledger's preferences or the local rates change; read from
    /// anywhere (notifications, Siri), so behind a lock. Take it once per message, not per amount.
    private static let storage = OSAllocatedUnfairLock<MoneyDisplay>(initialState: .cny)
    static var current: MoneyDisplay { storage.withLock { $0 } }

    /// True when the shown currency or rate changed.
    @discardableResult @MainActor static func configure(_ ledger: Ledger, synced: SyncedExchangeRates?, now: Date) -> Bool {
        let next = MoneyDisplay(ledger: ledger, synced: synced, now: now)
        return storage.withLock { value in
            guard value != next else { return false }
            value = next; return true
        }
    }
}

/// 两个 target 只共享快照，扩展不持有账本，也没有写账入口。
enum CaptureSnapshotBridge {
    private static var file: URL? {
        #if os(iOS) && YUBAI_APP_GROUP
        guard let group = Bundle.main.object(forInfoDictionaryKey: "YubaiAppGroupIdentifier") as? String, !group.isEmpty else { return nil }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)?.appendingPathComponent("quick-capture.json")
        #else
        return nil
        #endif
    }
    private static let publishQueue = DispatchQueue(label: "app.yubai.capture-snapshot", qos: .utility)
    static func publish(_ ledger: Ledger) {
        #if os(iOS)
        // The widget shows amounts the way the app does: main currency at this device's rate.
        let display = DisplayCurrency.current
        publishQueue.async {
            // App Group lookup can itself synchronously wait on system I/O.
            guard let file else { return }
            // 设备锁或隐藏金额时连用途快照也移除，扩展只能显示入口。
            if ledger.preferences.lockEnabled || ledger.preferences.hideAmounts {
                try? FileManager.default.removeItem(at: file)
            } else {
                do {
                    let bytes = try JSONEncoder().encode(QuickCaptureSnapshot(ledger: ledger, display: display))
                    try bytes.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                } catch { try? FileManager.default.removeItem(at: file) }
            }
            WidgetCenter.shared.reloadAllTimelines()
        }
        #endif
    }
    static func read(now: Date = Dates.now) -> QuickCaptureSnapshot? {
        guard let file, let bytes = try? Data(contentsOf: file), let value = try? JSONDecoder().decode(QuickCaptureSnapshot.self, from: bytes),
              value.headlineTitle != nil,
              value.generatedAt <= now, Dates.calendar.isDate(value.generatedAt, inSameDayAs: now) else { return nil }
        return value
    }
    static func addURL(category: String? = nil, amount: Int64? = nil, purpose: String? = nil) -> URL {
        var url = URLComponents(); url.scheme = "yubai"; url.host = "add"
        url.queryItems = [category.map { URLQueryItem(name: "category", value: $0) }, amount.map { URLQueryItem(name: "amount", value: Money.input($0)) }, purpose.map { URLQueryItem(name: "purpose", value: $0) }].compactMap { $0 }
        return url.url!
    }
}
