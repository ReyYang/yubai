#if os(iOS) && canImport(AppIntents)
import AppIntents
import SwiftUI
import UniformTypeIdentifiers
import YubaiCore

struct CaptureEntryIntent: AppIntent {
    static let title: LocalizedStringResource = "记一笔"
    static let description = IntentDescription("记下金额和用途。")
    static var openAppWhenRun: Bool = false
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
    @Parameter(title: "一句话", requestValueDialog: "多少钱，花在什么上？") var text: String?
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetIntent {
        let store = AppStore.shared
        await store.configureSync()
        guard case .drafts(let drafts) = try QuickCapture.parse(text ?? "", in: store.current) else { throw $text.needsValueError("多少钱，花在什么上？") }
        let ids = try store.captureUpdate("记一笔") { try QuickCapture.record(drafts, in: &$0, source: "Siri／快捷指令") }
        return .result(dialog: "已记下", snippetIntent: CaptureSnippetIntent(ids: ids))
    }
}
struct CaptureSnippetIntent: SnippetIntent {
    static let title: LocalizedStringResource = "记账结果"
    @Parameter(title: "记录") var entryIDs: [String]
    init() {}
    init(ids: [UUID]) { entryIDs = ids.map(\.uuidString) }
    @MainActor func perform() async throws -> some IntentResult & ShowsSnippetView {
        let store = AppStore.shared; let ids = Set(entryIDs.compactMap(UUID.init(uuidString:)))
        let entries = store.current.activeEntries.filter { ids.contains($0.id) }
        let privateResult = store.preferences.lockEnabled || store.preferences.hideAmounts
        return .result(view: CaptureSnippetView(entries: entries, ledger: store.current, privateResult: privateResult))
    }
}
private struct CaptureSnippetView: View {
    let entries: [Entry]; let ledger: Ledger; let privateResult: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: YubaiSpace.gapGroup) {
            Label(entries.isEmpty ? "余白 · 已撤销" : "余白 · 已记下", systemImage: "square.righthalf.filled").yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary)
            ForEach(entries) { entry in
                VStack(alignment: .leading, spacing: YubaiSpace.space4) {
                    HStack(alignment: .firstTextBaseline, spacing: YubaiSpace.gapGroup) {
                        if !privateResult { Text(entry.displayTitle).yubaiFont(YubaiFont.cardTitle) }
                        Spacer()
                        AmountLabel(cents: entry.amount, hide: ledger.preferences.hideAmounts, role: .account, sign: .outflow)
                    }
                    if !privateResult {
                        Text(Classification.displayCategory(entry.category) + " · " + ledger.accountName(entry.accountID) + " · " + ManualBookkeeping.dayLabel(entry.date) + " " + entry.date.formatted(.dateTime.hour().minute()))
                            .yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary)
                    }
                }
            }
            Divider()
            HStack(spacing: YubaiSpace.gapGroup) {
                Text("还能花").foregroundStyle(YubaiColor.labelSecondary)
                Spacer(); AmountLabel(cents: QuickCapture.available(in: ledger), hide: ledger.preferences.hideAmounts, currency: true)
            }.yubaiFont(YubaiFont.caption)
            ForEach(entries) { entry in
                HStack(spacing: YubaiSpace.gapGroup) {
                    Button("改一下", intent: EditCapturedEntryIntent(id: entry.id)).buttonStyle(.bordered)
                    Button("撤销", intent: UndoCapturedEntryIntent(id: entry.id)).buttonStyle(.bordered).tint(YubaiColor.amberInk)
                }
            }
        }.padding(YubaiSpace.insetCard).foregroundStyle(YubaiColor.label).background(YubaiColor.canvas)
    }
}
struct EditCapturedEntryIntent: AppIntent {
    static let title: LocalizedStringResource = "改一下"
    static var openAppWhenRun: Bool = true
    static var isDiscoverable: Bool = false
    @Parameter(title: "记录") var entryID: String
    init() {}
    init(id: UUID) { entryID = id.uuidString }
    @MainActor func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: entryID) else { throw YubaiError.invalid("记录已不存在。") }
        AppStore.shared.requestCaptureSheet(.editEntry(id)); return .result()
    }
}
struct UndoCapturedEntryIntent: AppIntent {
    static let title: LocalizedStringResource = "撤销这笔"
    static var openAppWhenRun: Bool = false
    static var isDiscoverable: Bool = false
    @Parameter(title: "记录") var entryID: String
    init() {}
    init(id: UUID) { entryID = id.uuidString }
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let id = UUID(uuidString: entryID) else { throw YubaiError.invalid("记录已不存在。") }
        try AppStore.shared.captureUpdate("撤销这笔") { QuickCapture.undo(entryID: id, in: &$0) }
        CaptureNotifications.remove(id: id)
        return .result(dialog: "已撤销")
    }
}
struct ApplePayCaptureIntent: AppIntent {
    static let title: LocalizedStringResource = "Apple Pay 记一笔"
    static var openAppWhenRun: Bool = false
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
    @Parameter(title: "商户") var merchant: String
    @Parameter(title: "金额") var amount: String
    @Parameter(title: "卡名") var card: String
    @Parameter(title: "付款时间") var transactionDate: Date?
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = AppStore.shared; await store.configureSync()
        let result = try store.captureUpdate("Apple Pay 记一笔") {
            try QuickCapture.applePay(merchant: merchant, amount: amount, card: card, date: transactionDate ?? Date(), in: &$0)
        }
        if result.inserted { await CaptureNotifications.post(entry: result.entry, ledger: store.current) }
        return .result(dialog: "已记下")
    }
}
struct OpenQuickEntryIntent: AppIntent {
    static let title: LocalizedStringResource = "打开记一笔"
    static var openAppWhenRun: Bool = true
    @Parameter(title: "分类") var category: String?
    @Parameter(title: "金额") var amount: String?
    @Parameter(title: "用途") var purpose: String?
    @MainActor func perform() async throws -> some IntentResult {
        let cents = try amount.map { try QuickCapture.applePayAmount($0) }
        AppStore.shared.requestCaptureSheet(.prefilledEntry(QuickEntryPrefill(category: category, amount: cents, purpose: purpose)))
        return .result()
    }
}
struct ScreenshotCaptureIntent: AppIntent {
    static let title: LocalizedStringResource = "截图记"
    static var openAppWhenRun: Bool = true
    @Parameter(title: "图片", supportedContentTypes: [.image]) var image: IntentFile?
    @MainActor func perform() async throws -> some IntentResult {
        let bytes = image?.data
        if let bytes, bytes.count > 50 * 1024 * 1024 { throw YubaiError.invalid("图片请小于 50 MB。") }
        AppStore.shared.requestCaptureSheet(.screenshotCapture(bytes)); return .result()
    }
}
struct YubaiQuickShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: CaptureEntryIntent(), phrases: ["用\(.applicationName)记一笔", "\(.applicationName)记一笔"], shortTitle: "记一笔", systemImageName: "plus")
        AppShortcut(intent: ScreenshotCaptureIntent(), phrases: ["\(.applicationName)截图记", "用\(.applicationName)截图记"], shortTitle: "截图记", systemImageName: "text.viewfinder")
        AppShortcut(intent: OpenQuickEntryIntent(), phrases: ["打开\(.applicationName)记一笔"], shortTitle: "打开记一笔", systemImageName: "plus.circle")
    }
}
#endif
