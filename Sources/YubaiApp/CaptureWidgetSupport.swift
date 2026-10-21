import Foundation
import YubaiCore
#if canImport(WidgetKit)
import WidgetKit
#endif

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
    static func publish(_ ledger: Ledger) {
        #if os(iOS)
        guard let file else { return }
        // 设备锁或隐藏金额时连用途快照也移除，扩展只能显示入口。
        if ledger.preferences.lockEnabled || ledger.preferences.hideAmounts {
            try? FileManager.default.removeItem(at: file)
        } else {
            do {
                let bytes = try JSONEncoder().encode(QuickCaptureSnapshot(ledger: ledger))
                try bytes.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            } catch { try? FileManager.default.removeItem(at: file) }
        }
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
    static func read(now: Date = Date()) -> QuickCaptureSnapshot? {
        guard let file, let bytes = try? Data(contentsOf: file), let value = try? JSONDecoder().decode(QuickCaptureSnapshot.self, from: bytes),
              value.generatedAt <= now, Dates.calendar.isDate(value.generatedAt, inSameDayAs: now) else { return nil }
        return value
    }
    static func addURL(category: String? = nil, amount: Int64? = nil, purpose: String? = nil) -> URL {
        var url = URLComponents(); url.scheme = "yubai"; url.host = "add"
        url.queryItems = [category.map { URLQueryItem(name: "category", value: $0) }, amount.map { URLQueryItem(name: "amount", value: Money.input($0)) }, purpose.map { URLQueryItem(name: "purpose", value: $0) }].compactMap { $0 }
        return url.url!
    }
}
