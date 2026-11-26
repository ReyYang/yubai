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
    /// 退款冲的那笔支出；只在 `nature == .refund` 时生效。
    var relatedEntryID: UUID? = nil
    var copiedEntry: Entry? = nil

    init(category: String?, amount: Int64?, purpose: String?, screenshot: Data? = nil, nature: Nature? = nil,
         subcategory: String? = nil, accountID: UUID? = nil, otherAccountID: UUID? = nil, intoFixedSavings: Bool = false,
         fromReserve: Bool = false, date: Date? = nil, relatedEntryID: UUID? = nil) {
        self.category = category; self.amount = amount; self.purpose = purpose; self.screenshot = screenshot
        self.nature = nature; self.subcategory = subcategory; self.accountID = accountID; self.otherAccountID = otherAccountID
        self.intoFixedSavings = intoFixedSavings; self.fromReserve = fromReserve; self.date = date; self.relatedEntryID = relatedEntryID
    }

    init(copying entry: Entry, date: Date, keepLink: Bool = false) {
        self.init(category: entry.category, amount: entry.originalAmount ?? entry.amount, purpose: entry.displayTitle,
                  nature: entry.nature, subcategory: entry.subcategory, accountID: entry.accountID, otherAccountID: entry.otherAccountID,
                  intoFixedSavings: entry.intoFixedSavings, fromReserve: entry.fromReserve, date: date,
                  relatedEntryID: keepLink ? entry.relatedEntryID : nil)
        copiedEntry = entry
    }
}
extension AppStore {
    /// 记一笔 on a ledger with no account yet: prepare the default account first.
    func beginFirstEntry() {
        homeEntrySession = destination == .ledger
        guard update("开始记账", recordUndo: false, entryMotion: false, showToast: false, {
            FirstUse.prepareForEntry(&$0, now: Dates.now)
        }) else { return }
        openEntrySheet()
    }
    func requestCaptureSheet(_ next: AppSheet) {
        if loadingLedger || locked { pendingQuickSheet = next }
        else {
            if accounts.isEmpty || !preferences.onboardingComplete { _ = update("开始记账", recordUndo: false, entryMotion: false, showToast: false) { FirstUse.prepareForEntry(&$0, now: Dates.now) } }
            switch next {
            case .addEntry: openEntrySheet()
            case .prefilledEntry(let prefill): openEntrySheet(prefill)
            case .ask(let text): openAsk(text, send: !text.isEmpty)
            case .editEntry(let id):
                if let entry = current.entries.first(where: { $0.id == id && $0.deletedAt == nil }) { openBillEditor(entry) }
                else { error = "找不到账单。" }
            default: sheetSource = nil; sheet = next
            }
        }
    }
    func handleCaptureURL(_ url: URL) {
        if loadingLedger { pendingOpenURL = url; return }
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
        routeSavingURL(options.urlContexts)
        if let shortcut = options.shortcutItem { _ = HomeActionDelegate.route(shortcut) }
    }
    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        routeSavingURL(URLContexts)
    }
    private func routeSavingURL(_ contexts: Set<UIOpenURLContext>) {
        guard let url = contexts.map(\.url).first(where: {
            $0.scheme?.lowercased() == "yubai" && ["saving", "save"].contains($0.host?.lowercased() ?? "")
        }) else { return }
        AppStore.shared.handleCaptureURL(url)
    }
    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcut: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {
        completionHandler(HomeActionDelegate.route(shortcut))
    }
}
#endif
