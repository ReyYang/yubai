import SwiftUI
import YubaiCore
#if os(iOS)
import UIKit
import Photos
#endif

struct QuickEntryPrefill {
    var category: String?; var amount: Int64?; var purpose: String?
    var screenshot: Data? = nil
    var nature: Nature? = nil
    var subcategory: String? = nil
    var accountID: UUID? = nil
    var otherAccountID: UUID? = nil
    var intoFixedSavings = false
    /// 「从存着的钱出」：存钱页和问余白的「从存着的钱买」带过来，记一笔里直接选中。
    var fromReserve = false
    /// 补记某一天；`nil` 为今天。
    var date: Date? = nil
}
extension AppStore {
    func requestCaptureSheet(_ next: AppSheet) {
        if locked { pendingQuickSheet = next }
        else {
            if accounts.isEmpty || !preferences.onboardingComplete { _ = update("开始记账", recordUndo: false, entryMotion: false, showToast: false) { FirstUse.prepareForEntry(&$0, now: Date()) } }
            sheetSource = nil; sheet = next
        }
    }
    func handleCaptureURL(_ url: URL) {
        guard url.scheme?.lowercased() == "yubai", let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        func value(_ name: String) -> String? { parts.queryItems?.first { $0.name == name }?.value }
        switch url.host?.lowercased() {
        case "saving", "save": openSavingPage()
        case "add":
            let amount = value("amount").flatMap { try? Money.parse($0) }.flatMap { $0 > 0 ? $0 : nil }
            requestCaptureSheet(.prefilledEntry(QuickEntryPrefill(category: value("category"), amount: amount, purpose: value("purpose"))))
        case "ask": requestCaptureSheet(.ask(""))
        case "capture": requestCaptureSheet(.screenshotCapture(nil))
        case "entry": if let id = value("id").flatMap(UUID.init(uuidString:)) { requestCaptureSheet(.editEntry(id)) }
        default: break
        }
    }
    /// App Intents 只在 App target 执行，和界面共用 MainActor、AppStore 及持久化／冲突检查。
    @discardableResult func captureUpdate<T>(_ reason: String, _ operation: (inout Ledger) throws -> T) throws -> T {
        guard !syncBusy, syncChoice == nil, !switchingLedgerLocation, !choosingSyncVersion else { throw YubaiError.invalid("账本正在同步，请稍后再记。") }
        var result: T?; var failure: Error?
        let saved = update(reason, recordUndo: false, reportError: false, entryMotion: false, allowLockedCapture: true) { ledger in
            do { result = try operation(&ledger) } catch { failure = error; throw error }
        }
        if let failure { throw failure }
        guard saved, let result else { throw YubaiError.invalid("这次没有保存，请打开余白核对账本。") }
        return result
    }
}

#if os(iOS)
enum CaptureImageSource {
    @MainActor static func recentOrClipboard() async -> Data? {
        if let image = UIPasteboard.general.image, let bytes = image.pngData() { return bytes }
        let permission = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard permission == .authorized || permission == .limited else { return nil }
        let options = PHFetchOptions(); options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]; options.fetchLimit = 1
        options.predicate = NSPredicate(format: "(mediaSubtype & %d) != 0", PHAssetMediaSubtype.photoScreenshot.rawValue)
        guard let asset = PHAsset.fetchAssets(with: .image, options: options).firstObject else { return nil }
        return await withCheckedContinuation { continuation in
            let request = PHImageRequestOptions(); request.isNetworkAccessAllowed = false; request.deliveryMode = .highQualityFormat
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: request) { bytes, _, _, _ in continuation.resume(returning: bytes) }
        }
    }
}
#endif

struct ScreenshotCaptureView: View {
    var imageData: Data?
    var body: some View {
        ReceiptCapturePage(imageData: imageData)
    }
}

extension QuickEntryPrefill {
    init(entry: Entry) {
        intoFixedSavings = entry.intoFixedSavings
        category = entry.category; amount = entry.amount; purpose = entry.purpose ?? entry.title
        nature = entry.nature; subcategory = entry.subcategory; accountID = entry.accountID; otherAccountID = entry.otherAccountID
    }
}

#if os(iOS)
@MainActor final class HomeActionDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: session.configuration.name, sessionRole: session.role)
        configuration.delegateClass = HomeActionSceneDelegate.self
        return configuration
    }
    func application(_ application: UIApplication, performActionFor shortcut: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {
        completionHandler(Self.route(shortcut))
    }
    static func route(_ shortcut: UIApplicationShortcutItem) -> Bool {
        let sheet: AppSheet
        switch shortcut.type {
        case "app.yubai.add": sheet = .addEntry
        case "app.yubai.capture": sheet = .screenshotCapture(nil)
        case "app.yubai.ask": sheet = .ask("")
        default: return false
        }
        AppStore.shared.requestCaptureSheet(sheet); return true
    }
}
@MainActor final class HomeActionSceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        if let shortcut = options.shortcutItem { _ = HomeActionDelegate.route(shortcut) }
    }
    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcut: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {
        completionHandler(HomeActionDelegate.route(shortcut))
    }
}
#endif
