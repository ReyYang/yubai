import SwiftUI
import YubaiCore
#if os(iOS)
import UIKit
import Photos
#endif

struct QuickEntryPrefill {
    var category: String?; var amount: Int64?; var purpose: String?
    var screenshot: Data? = nil
}
extension AppStore {
    func requestCaptureSheet(_ next: AppSheet) {
        if locked { pendingQuickSheet = next } else { sheetSource = nil; sheet = next }
    }
    func handleCaptureURL(_ url: URL) {
        guard url.scheme?.lowercased() == "yubai", let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        func value(_ name: String) -> String? { parts.queryItems?.first { $0.name == name }?.value }
        switch url.host?.lowercased() {
        case "add":
            let amount = value("amount").flatMap { try? Money.parse($0) }.flatMap { $0 > 0 ? $0 : nil }
            requestCaptureSheet(.prefilledEntry(QuickEntryPrefill(category: value("category"), amount: amount, purpose: value("purpose"))))
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
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var imageData: Data?
    @State private var bytes: Data?
    @State private var drafts: [EntryDraft] = []
    @State private var selected = Set<UUID>()
    @State private var reading = true
    @State private var failure: String?
    var body: some View {
        Page {
            if reading { ProgressView("正在读取截图") }
            else if drafts.isEmpty {
                Text("没认出金额").yubaiFont(YubaiFont.cardTitle)
                Button("打开记一笔") { store.sheet = .prefilledEntry(QuickEntryPrefill(category: nil, amount: nil, purpose: nil, screenshot: bytes)) }.buttonStyle(PrimaryButtonStyle())
            } else {
                Text("余白 · 从截图认出 \(drafts.count) 笔").yubaiFont(YubaiFont.cardTitle)
                Card(style: .list) {
                    VStack(spacing: YubaiSpace.none) {
                        ForEach(drafts, id: \.id) { draft in
                            Button {
                                if selected.contains(draft.id) { selected.remove(draft.id) } else { selected.insert(draft.id) }
                            } label: {
                                HStack(spacing: YubaiSpace.gapGroup) {
                                    Image(systemName: selected.contains(draft.id) ? "checkmark.circle.fill" : "circle").foregroundStyle(YubaiColor.brandInk)
                                    VStack(alignment: .leading, spacing: YubaiSpace.space4) {
                                        Text(draft.title).yubaiFont(YubaiFont.rowTitle)
                                        Text(Classification.displayCategory(draft.category) + " · " + store.current.accountName(draft.accountID) + " · " + ManualBookkeeping.dayLabel(draft.date))
                                            .yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary)
                                    }
                                    Spacer()
                                    AmountLabel(cents: draft.amount, hide: store.current.preferences.hideAmounts, sign: draft.nature.inflow ? .inflow : .outflow)
                                }.padding(.vertical, YubaiSpace.space4).frame(minHeight: YubaiSize.rowDouble).contentShape(Rectangle())
                            }.buttonStyle(PressButtonStyle()).accessibilityAddTraits(selected.contains(draft.id) ? .isSelected : [])
                        }
                    }
                }
                HStack(spacing: YubaiSpace.gapGroup) {
                    Button("打开核对") { if let bytes { store.sheet = .screenshotReview(bytes) } }.buttonStyle(SecondaryButtonStyle())
                    Button("记下 \(selected.count) 笔", action: save).buttonStyle(PrimaryButtonStyle()).disabled(selected.isEmpty)
                }
            }
            if let failure { InlineNote(text: failure, style: .attention) }
        }.navigationTitle("截图记").yubaiNavigation().toolbar { CloseButton() }
            .task { await recognize() }
    }
    @MainActor private func recognize() async {
        defer { reading = false }
        bytes = imageData
        #if os(iOS)
        if bytes == nil { bytes = await CaptureImageSource.recentOrClipboard() }
        #endif
        guard let bytes else { store.sheet = .imports; return }
        let ledgerID = store.current.id
        do {
            guard bytes.count <= 50 * 1024 * 1024 else { throw YubaiError.invalid("图片请小于 50 MB。") }
            let receipt = try await Task.detached(priority: .userInitiated) { try ReceiptReader.recognize(bytes) }.value
            try Task.checkCancellation()
            guard !store.locked, store.current.id == ledgerID else { return }
            guard let account = ManualBookkeeping.defaultAccount(in: store.current) else { failure = "请先添加账户。"; return }
            drafts = ReceiptTextParser.drafts(lines: receipt.text.components(separatedBy: .newlines)).map { $0.entryDraft(in: store.current, accountID: account.id) }
            selected = Set(drafts.map(\.id))
        } catch is CancellationError {} catch { failure = "没认出金额" }
    }
    private func save() {
        let entries = drafts.filter { selected.contains($0.id) }
        if store.update("截图记", { ledger in
            let ids = try QuickCapture.record(entries, in: &ledger, source: "截图记", withoutOpeningApp: false)
            if let bytes {
                let compressed = ImageCompression.compress(bytes, name: "截图.png")
                let attachment = Attachment(name: compressed.name, data: compressed.data); ledger.attachments.append(attachment)
                let saved = Set(ids)
                for i in ledger.entries.indices where saved.contains(ledger.entries[i].id) { ledger.entries[i].attachmentID = attachment.id }
            }
        }) { dismiss() }
    }
}
