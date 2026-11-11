import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import YubaiCore
#if os(iOS)
import UIKit
#endif

private struct ReceiptCaptureLine: Identifiable {
    let id: Int
    let draft: ReceiptTextParser.Draft
    let hint: CategoryAssignment?
}
private struct ReceiptCategorySelection: Identifiable {
    let id: Int
    let income: Bool
    let suggested: String?
}

struct ReceiptCapturePage: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var textSize
    let imageData: Data?
    @State private var bytes: Data?
    @State private var lines: [ReceiptCaptureLine] = []
    @State private var selected = Set<Int>()
    @State private var choices: [Int: CategoryAssignment] = [:]
    @State private var shop = ""
    @State private var shopHint: CategoryAssignment?
    @State private var mode = ReceiptEntryMode.separate.rawValue
    @State private var accountID: UUID?
    @State private var prepared: [EntryDraft] = []
    @State private var preparedKey: String?
    @State private var preparationID = UUID()
    @State private var recognitionID = UUID()
    @State private var total: Int64 = 0
    @State private var availableAfter: Int64?
    @State private var reading = false
    @State private var preparing = false
    @State private var failure: String?
    @State private var photoPicker = false
    @State private var filePicker = false
    @State private var photo: PhotosPickerItem?
    @State private var camera = false
    @State private var editingCategory: ReceiptCategorySelection?
    @State private var request: Task<Void, Never>?
    @State private var loaded = false
    private var allowed: Bool {
        store.preferences.isAIEnabled(for: .receiptRecognition) && IntelligenceRuntime.isConfigured && IntelligenceRuntime.cloud.unavailableModel == nil
    }
    private var selectionKey: String {
        let assignments = choices.keys.sorted().map { "\($0)=\(choices[$0]?.path ?? "")" }.joined(separator: ";")
        return mode + ":" + selected.sorted().map(String.init).joined(separator: ",") + ":\(accountID?.uuidString ?? ""):\(store.ledgerRevision):\(recognitionID):" + assignments
    }

    var body: some View {
        VStack(spacing: YubaiSpace.none) {
            Page(spacing: YubaiSpace.gapGroup) {
                if !allowed { unavailable }
                else if reading { ProgressView("正在读截图…") }
                else if !lines.isEmpty { review }
                if let failure { InlineNote(text: failure, style: .attention) }
            }
            Button("都记下", action: save).buttonStyle(PrimaryButtonStyle())
                .disabled(!allowed || reading || preparing || preparedKey != selectionKey || prepared.isEmpty || failure != nil || store.preferences.hideAmounts)
                .accessibilityIdentifier("saveReceiptEntries").accessibilityValue("\(prepared.count) 笔").padding(YubaiSpace.insetPage)
        }.paperBackground().amountPrivacy(store.preferences.hideAmounts).navigationTitle("拍小票").yubaiNavigation()
            .manualSheetHeader("拍小票", actionTitle: "重拍", primary: false, enabled: allowed && !reading,
                               actionIdentifier: "retakeReceipt", action: chooseImage)
            .accessibilityIdentifier("receiptCapturePage")
            .photosPicker(isPresented: $photoPicker, selection: $photo, matching: .images)
            .fileImporter(isPresented: $filePicker, allowedContentTypes: [.image]) { result in
                do {
                    let url = try result.get(), access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 50 * 1024 * 1024 else { throw YubaiError.invalid("图片请小于 50 MB。") }
                    start(try Data(contentsOf: url))
                } catch { if (error as NSError).code != NSUserCancelledError { failure = error.localizedDescription } }
            }
            .onChange(of: photo) { _, value in
                guard let value, allowed else { return }
                request?.cancel()
                request = Task { @MainActor in
                    do {
                        guard let data = try await value.loadTransferable(type: Data.self) else { throw YubaiError.invalid("图片读取失败。") }
                        try Task.checkCancellation(); await recognize(data)
                    } catch { if !Task.isCancelled { failure = error.localizedDescription } }
                }
            }
            .task {
                guard !loaded else { return }; loaded = true
                accountID = ManualBookkeeping.defaultAccount(in: store.current)?.id
                #if DEBUG && targetEnvironment(simulator)
                if let fixture = UITestSupport.secondBatchReceipt { await recognize(nil, fixture: fixture); return }
                #endif
                if let imageData { start(imageData) } else { chooseImage() }
            }
            .task(id: selectionKey) { await prepare() }
            .onChange(of: allowed) { _, value in if !value { request?.cancel(); reading = false; prepared = [] } }
            .onChange(of: store.current.id) { _, _ in request?.cancel(); dismiss() }
            .onDisappear { request?.cancel() }
            .sheet(item: $editingCategory) { target in categoryPicker(target) }
            #if os(iOS)
            .sheet(isPresented: $camera) {
                ReceiptCamera { data in camera = false; if let data { start(data) } }
            }
            #endif
    }

    private var review: some View {
        VStack(alignment: .leading, spacing: YubaiSpace.gapGroup) {
            Text("认出 \(lines.count) 笔，共 " + amount2(total, hide: store.preferences.hideAmounts) + "。")
                .yubaiFont(YubaiFont.lead).accessibilityIdentifier("receiptSummary")
            Text(shop + " · " + ImportStatementText.range(lines.map { $0.draft.date }))
                .yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
            CardRows(lines) { line in lineRow(line) }
            SegmentedWide(choices: [(ReceiptEntryMode.separate.rawValue, "分开记 \(selected.count) 笔"), (ReceiptEntryMode.merged.rawValue, "合成 1 笔")],
                          selection: $mode, identifier: { "receiptMode_" + $0 })
            if mode == ReceiptEntryMode.merged.rawValue {
                categoryButton(id: -1, title: shop, income: lines.first?.draft.nature.categoryIncome ?? false, hint: shopHint)
            }
            Menu {
                ForEach(store.accounts.filter { !$0.archived }) { account in
                    Button(account.name) { accountID = account.id }.accessibilityIdentifier("receiptAccount_" + account.id.uuidString)
                }
            } label: {
                Label(store.accountName(accountID), systemImage: "creditcard").yubaiFont(YubaiFont.caption).frame(minHeight: YubaiSize.tapMin)
            }.buttonStyle(PressButtonStyle()).accessibilityIdentifier("receiptAccount")
            if let availableAfter {
                ResultBar(label: "记下后还能花", value: ResultBar.change(store.funds.available, availableAfter, hide: store.preferences.hideAmounts),
                          amber: availableAfter < 0, identifier: "receiptAvailableAfter")
            }
        }
    }
    private func lineRow(_ line: ReceiptCaptureLine) -> some View {
        HStack(alignment: .top, spacing: YubaiSpace.space8) {
            Button {
                if selected.contains(line.id) { selected.remove(line.id) } else { selected.insert(line.id) }
            } label: {
                Image(systemName: selected.contains(line.id) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected.contains(line.id) ? YubaiColor.brand : YubaiColor.labelSecondary)
                    .frame(width: YubaiSize.tapMin, height: YubaiSize.tapMin)
            }.buttonStyle(PressButtonStyle()).accessibilityLabel(line.draft.title)
                .accessibilityValue(selected.contains(line.id) ? "已选" : "未选").accessibilityIdentifier("receiptSelect_\(line.id)")
            VStack(alignment: .leading, spacing: YubaiSpace.space2) {
                let layout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: YubaiSpace.space4)) : AnyLayout(HStackLayout(spacing: YubaiSpace.space8))
                layout {
                    Text(line.draft.title).yubaiFont(YubaiFont.row).frame(maxWidth: .infinity, alignment: .leading)
                    AmountLabel(cents: line.draft.amount, hide: store.preferences.hideAmounts, sign: line.draft.nature.inflow ? .inflow : .outflow)
                }
                categoryButton(id: line.id, title: line.draft.title, income: line.draft.nature.categoryIncome, hint: line.hint)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(.vertical, YubaiSpace.space4)
    }
    private func categoryButton(id: Int, title: String, income: Bool, hint: CategoryAssignment?) -> some View {
        let choice = choices[id]
        let label = choice?.subcategory ?? choice?.category ?? hint?.subcategory ?? hint?.category ?? "没分类"
        return Button { editingCategory = ReceiptCategorySelection(id: id, income: income, suggested: hint?.category) } label: {
            Text(Classification.displayCategory(label)).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                .padding(.horizontal, YubaiSpace.space8).frame(minHeight: YubaiSize.tapMin)
                .overlay { if choice == nil && hint != nil { RoundedRectangle(cornerRadius: YubaiRadius.control).strokeBorder(YubaiColor.brand) } }
        }.buttonStyle(PressButtonStyle()).accessibilityLabel(title + "，分类")
            .accessibilityValue(choice == nil && hint != nil ? "建议" + label : label).accessibilityIdentifier("receiptCategory_\(id)")
    }
    private func categoryPicker(_ target: ReceiptCategorySelection) -> some View {
        NavigationStack {
            Page {
                CategoryPicker(income: target.income, selected: choices[target.id], suggested: target.suggested,
                               identifier: "receiptPickCategory_\(target.id)", style: .entry) { assignment, addition in
                    if let addition, !store.update("新分类", { try addition.apply(to: &$0) }) { return false }
                    choices[target.id] = assignment; editingCategory = nil; return true
                }
            }.navigationTitle("分类").yubaiNavigation().manualSheetHeader("分类", showsAction: false)
        }.environment(store).appErrors().yubaiSheetBackground()
    }
    private var unavailable: some View {
        VStack(alignment: .leading, spacing: YubaiSpace.gapGroup) {
            let status = !IntelligenceRuntime.isConfigured ? "还没配密钥" : (IntelligenceRuntime.cloud.unavailableModel != nil ? "模型不可用" : "云端智能没开")
            Text(status).yubaiFont(YubaiFont.rowTitle)
            NavigationLink("智能与隐私") { IntelligencePrivacyView() }
                .buttonStyle(SecondaryButtonStyle()).accessibilityIdentifier("configureReceiptAI")
        }
    }
    private func chooseImage() {
        guard allowed else { return }
        #if os(iOS)
        if UIImagePickerController.isSourceTypeAvailable(.camera), Bundle.main.object(forInfoDictionaryKey: "NSCameraUsageDescription") != nil {
            camera = true
        } else { photoPicker = true }
        #else
        filePicker = true
        #endif
    }
    private func start(_ data: Data) {
        guard allowed else { return }
        request?.cancel()
        request = Task { @MainActor in await recognize(data) }
    }
    @MainActor private func recognize(_ data: Data?, fixture: ReceiptCandidate? = nil) async {
        guard allowed else { return }
        reading = true; failure = nil; prepared = []; bytes = data
        let ledger = store.current
        defer { if !Task.isCancelled { reading = false } }
        do {
            let receipt: ReceiptCandidate
            if let fixture { receipt = fixture }
            else {
                guard let data, data.count <= 50 * 1024 * 1024 else { throw YubaiError.invalid("图片请小于 50 MB。") }
                receipt = try await Task.detached(priority: .userInitiated) { try ReceiptReader.recognize(data) }.value
            }
            try Task.checkCancellation()
            guard let transport = store.assistantTransport(for: ledger, feature: .receiptRecognition) else { return }
            let recognized = try await ReceiptRecognition.read(receipt, transport: transport, redactor: Redactor(ledger: ledger), now: Date())
            try Task.checkCancellation()
            guard store.current.id == ledger.id, !store.locked, allowed else { return }
            recognitionID = UUID(); shop = recognized.shop; choices = [:]
            shopHint = CategoryGuesser.guess(recognized.shop, nature: recognized.lines.first?.nature ?? .expense, in: ledger)
            lines = recognized.lines.enumerated().map { index, draft in
                ReceiptCaptureLine(id: index, draft: draft, hint: CategoryGuesser.guess(draft.title, nature: draft.nature, date: draft.date, in: ledger))
            }
            selected = Set(lines.map(\.id))
            total = try recognized.lines.reduce(Int64(0)) { value, draft in
                guard value <= Money.limit - draft.amount else { throw YubaiError.invalid("金额超出范围。") }
                return value + draft.amount
            }
            await prepare()
        } catch is CancellationError {
            if !Task.isCancelled { failure = "账本或智能设置已更新，可以再试一次。" }
        }
        catch { if !Task.isCancelled { failure = error.localizedDescription } }
    }
    @MainActor private func prepare() async {
        guard !lines.isEmpty, let accountID else { prepared = []; return }
        let runID = UUID(); preparationID = runID
        preparing = true; availableAfter = nil; failure = nil; preparedKey = nil
        defer { if preparationID == runID { preparing = false } }
        do {
            let checked = lines.filter { selected.contains($0.id) }
            var drafts = try ReceiptTextParser.entryDrafts(from: checked.map(\.draft), shopName: shop,
                                                         mode: ReceiptEntryMode(rawValue: mode) ?? .separate, in: store.current, accountID: accountID)
            for index in drafts.indices {
                let choice = choices[mode == ReceiptEntryMode.merged.rawValue ? -1 : checked[index].id]
                drafts[index].category = choice?.category ?? Classification.pendingCategory
                drafts[index].subcategory = choice?.subcategory
                drafts[index].categoryUserEdited = choice != nil
            }
            let ledger = store.current, revision = store.ledgerRevision, key = selectionKey, now = Date()
            let change = ChangeSet(source: "截图记", reason: "都记下", items: drafts.map { .addEntry($0) })
            let after: Int64?
            if drafts.isEmpty { after = nil }
            else { after = try await Task.detached(priority: .userInitiated) { try ManualBookkeeping.available(after: change, in: ledger, now: now) }.value }
            guard !Task.isCancelled, preparationID == runID, revision == store.ledgerRevision, key == selectionKey else { return }
            prepared = drafts; availableAfter = after; preparedKey = key
        } catch {
            if !Task.isCancelled, preparationID == runID { prepared = []; failure = error.localizedDescription }
        }
    }
    private func save() {
        guard allowed, !preparing, preparedKey == selectionKey, !prepared.isEmpty, failure == nil, !store.preferences.hideAmounts else { return }
        let drafts = prepared
        if store.update("拍小票", { ledger in
            let ids = try QuickCapture.record(drafts, in: &ledger, source: "截图记", withoutOpeningApp: false)
            if let bytes {
                let compressed = ImageCompression.compress(bytes, name: "截图.png")
                let attachment = Attachment(name: compressed.name, data: compressed.data)
                ledger.attachments.append(attachment)
                let saved = Set(ids)
                for index in ledger.entries.indices where saved.contains(ledger.entries[index].id) { ledger.entries[index].attachmentID = attachment.id }
            }
        }) { store.setEntrySaveToast("已记下 \(drafts.count) 笔"); dismiss() }
    }
}

#if os(iOS)
private struct ReceiptCamera: UIViewControllerRepresentable {
    let finish: (Data?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(finish: finish) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController(); controller.sourceType = .camera; controller.delegate = context.coordinator
        return controller
    }
    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let finish: (Data?) -> Void
        init(finish: @escaping (Data?) -> Void) { self.finish = finish }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { finish(nil) }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            finish((info[.originalImage] as? UIImage)?.jpegData(compressionQuality: 0.9))
        }
    }
}
#endif
