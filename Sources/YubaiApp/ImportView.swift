import SwiftUI
import UniformTypeIdentifiers
import Vision
import PhotosUI
import YubaiCore
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct ReceiptCandidate: Sendable {
    var text: String; var amounts: [String]; var title: String; var date: Date?
}
enum ReceiptReader {
    static func recognize(_ data: Data) throws -> ReceiptCandidate {
        let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate; request.recognitionLanguages = ["zh-Hans", "en-US"]; request.usesLanguageCorrection = true
        try VNImageRequestHandler(data: data).perform([request])
        let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        guard !lines.isEmpty else { throw YubaiError.invalid("没有识别到文字。请使用清晰、完整的账单截图，或手动记一笔。") }
        let text = lines.joined(separator: "\n")
        let drafts = ReceiptTextParser.drafts(lines: lines)
        let amounts = drafts.map { Money.input($0.amount) }
        let title = drafts.first?.title ?? "截图补记"
        let date = lines.compactMap(Dates.parse).first
        return ReceiptCandidate(text: text, amounts: amounts, title: title, date: date)
    }
}

private struct ImportQueueFile: Identifiable {
    enum Input { case file(URL), photo(PhotosPickerItem), pasted(PastedStatement), screenshot(Data) }
    let id = UUID()
    let input: Input
    var name: String
    var original: Data?
    var table: Data?
    var preview: ImportPreview?
    var reading = false
    var progress = 0.0
    var error: String?
    var screenshot = false
    var accountMappings: [String: UUID] = [:]
    var categoryMappings: [String: String] = [:]
    var confirmedNewCategories: Set<String> = []
    var selections: [Int: Bool] = [:]
    var edits: [Int: Entry] = [:]
    var screenshotConfirmed = false
}

private struct ImportDayGroup: Identifiable {
    let id: Date
    let title: String
    let rows: [ImportRow]
}

private struct ImportReceiptSelection: Identifiable {
    let id = UUID()
    let data: Data
}

/// Observe the existing mapper's sample count for the source pill; forward unchanged.
private struct ImportSourceMapper: ImportColumnMapper {
    let base: any ImportColumnMapper
    let sampleCount: @MainActor @Sendable (Int) -> Void
    func map(headers: [String], samples: [[String]]) async throws -> ImportColumnMapping {
        await sampleCount(samples.count)
        return try await base.map(headers: headers, samples: samples)
    }
}

struct ImportView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dynamicTypeSize) private var textSize
    var pasted: PastedStatement? = nil
    var initialScreenshot: Data? = nil
    /// Welcome reviews a local draft; account creation and commit belong to Start.
    private var welcomeReview: Binding<ImportPreview>? = nil
    @State private var accountID: UUID?
    @State private var filePicker = false
    @State private var photoPicker = false
    @State private var photos: [PhotosPickerItem] = []
    @State private var data: Data?
    #if os(iOS)
    @State private var screenshotImage: UIImage?
    #elseif os(macOS)
    @State private var screenshotImage: NSImage?
    #endif
    @State private var tableData: Data?
    @State private var filename = ""
    @State private var preview: ImportPreview?
    @State private var busy = false
    @State private var result: ImportBatch?
    @State private var filter = "全部"
    @State private var queue: [ImportQueueFile] = []
    @State private var queueTotal = 0
    @State private var processed = 0
    @State private var activeFileID: UUID?
    @State private var cloudSampleCounts: [UUID: Int] = [:]
    @State private var reviewWhenReady = false
    @State private var localError: String?
    @State private var showAccount = false
    @State private var showCategories = false
    @State private var accountMappings: [String: UUID] = [:]
    @State private var categoryMappings: [String: String] = [:]
    @State private var confirmedNewCategories: Set<String> = []
    @State private var rowSelections: [Int: Bool] = [:]
    @State private var parseID = UUID()
    @State private var parsingTask: Task<Void, Never>?
    @State private var queueTask: Task<Void, Never>?
    @State private var queueRunID = UUID()
    @State private var appeared = false
    @State private var screenshot = false
    @State private var screenshotConfirmed = false
    @State private var rowEdits: [Int: Entry] = [:]
    @State private var editingScreenshotRow: ImportRow?
    @State private var showScreenshot = false
    @State private var receiptCapture: ImportReceiptSelection?
    init(pasted: PastedStatement? = nil, initialScreenshot: Data? = nil, welcomeReview: Binding<ImportPreview>? = nil) {
        self.pasted = pasted; self.initialScreenshot = initialScreenshot; self.welcomeReview = welcomeReview
        _preview = State(initialValue: welcomeReview?.wrappedValue)
    }
    private var resultTitle: String {
        guard let result else { return preview == nil ? "导入账单" : "核对 \(processed + 1)/\(max(queueTotal, 1))" }
        guard let batch = store.imports.first(where: { $0.id == result.id && $0.undoneAt == nil }) else { return "这一批已撤销" }
        return batch.needsOrganization == true ? "账单已保存" : "整理好了"
    }
    var body: some View {
        VStack(spacing: YubaiSpace.none) {
            if screenshot && preview != nil {
                Menu { accountPicker; Button("添加账户") { showAccount = true } } label: { Label(store.accountName(accountID), systemImage: "creditcard") }
                    .accessibilityLabel("选择截图记账的账户").padding(.horizontal, 20).frame(minHeight: 44)
            }
            if let result { resultView(result) }
            else if let preview { previewView(preview) }
            else { intake }
            if let localError { InlineNote(text: store.preferences.hideAmounts ? "这份账单还没读好" : localError, style: .attention).padding(YubaiSpace.insetPage).textSelection(.enabled) }
        }
        .yubaiFont(YubaiFont.body).foregroundStyle(YubaiColor.label).paperBackground()
        .amountPrivacy(store.preferences.hideAmounts).navigationTitle(resultTitle).yubaiNavigation()
        .manualSheetHeader(resultTitle, actionTitle: result != nil ? "整批撤销" : "导入", primary: false,
                           enabled: result.map { store.organizingBatchID != $0.id } ?? true, cancelTitle: result != nil ? "关闭" : "取消",
                           showsAction: result == nil && preview != nil && welcomeReview == nil, actionIdentifier: "undoImportResult", action: {
            if let result, let batch = store.imports.first(where: { $0.id == result.id && $0.undoneAt == nil }) { store.undoImport(batch.id) }
            else if preview != nil && welcomeReview == nil { returnToIntake() }
        })
        .fileImporter(isPresented: $filePicker, allowedContentTypes: [.commaSeparatedText, .tabSeparatedText, .plainText, .image, UTType(filenameExtension: "xlsx") ?? .data], allowsMultipleSelection: true) { selection in
            switch selection {
            case .success(let urls): enqueue(urls.map { ImportQueueFile(input: .file($0), name: $0.lastPathComponent) })
            case .failure(let error): localError = error.localizedDescription
            }
        }
        .photosPicker(isPresented: $photoPicker, selection: $photos, matching: .images)
        .onChange(of: photos) { _, selection in
            guard !selection.isEmpty else { return }
            enqueue(selection.enumerated().map { ImportQueueFile(input: .photo($0.element), name: "截图 \($0.offset + 1)") }); photos = []
        }
        .sheet(isPresented: $showAccount) { NavigationStack { AccountEditor(account: nil) }.environment(store).appErrors().yubaiSheetBackground().frame(minWidth: 340, minHeight: 520) }
        .sheet(item: $receiptCapture, onDismiss: prepareQueue) { selection in
            NavigationStack { ScreenshotCaptureView(imageData: selection.data) }.environment(store).appErrors().yubaiSheetBackground()
        }
        .sheet(isPresented: $showCategories) { NavigationStack { categoryCorrespondence }.environment(store).yubaiSheetBackground() }
        .sheet(isPresented: $showScreenshot) { NavigationStack { screenshotOriginal }.environment(store).yubaiSheetBackground() }
        .sheet(item: $editingScreenshotRow) { row in
            if let entry = row.entry {
                NavigationStack {
                    ImportScreenshotEntryEditor(entry: entry) { edited in
                        rowEdits[row.line] = edited
                        if let index = preview?.rows.firstIndex(where: { $0.id == row.id }) { preview?.rows[index].entry = edited }
                        screenshotConfirmed = false
                    }
                }.environment(store).yubaiSheetBackground()
            }
        }
        .onChange(of: store.accounts.count) { _, _ in
            if accountID == nil { accountID = store.accounts.last(where: { !$0.archived })?.id; refreshPreview() }
        }
        .onChange(of: accountID) { _, _ in refreshPreview() }
        .onChange(of: accountMappings) { _, _ in refreshPreview() }
        .onChange(of: categoryMappings) { _, _ in refreshPreview() }
        .onDisappear { parsingTask?.cancel(); queueTask?.cancel() }
        .onAppear {
            guard welcomeReview == nil else { return }
            if !appeared, let initialScreenshot { enqueue([ImportQueueFile(input: .screenshot(initialScreenshot), name: "截图.png")]); reviewWhenReady = true }
            if appeared {
                if queueTask == nil || queueTask?.isCancelled == true {
                    for index in queue.indices where queue[index].reading { queue[index].reading = false }
                    prepareQueue()
                }
                if busy { refreshPreview() }
                return
            }
            appeared = true
            accountID = store.accounts.first { !$0.archived && ($0.kind == .cash || $0.kind == .bank) }?.id
                ?? store.accounts.first { !$0.archived }?.id
            #if DEBUG && targetEnvironment(simulator)
            if preview == nil && result == nil && data == nil, let url = UITestSupport.statementURL { store.importedURL = url }
            #endif
            if let pasted { reviewWhenReady = true; enqueue([ImportQueueFile(input: .pasted(pasted), name: pasted.filename)]) }
            else if let url = store.importedURL { store.importedURL = nil; reviewWhenReady = true; enqueue([ImportQueueFile(input: .file(url), name: url.lastPathComponent)]) }
        }
    }
    private var intake: some View {
        VStack(spacing: YubaiSpace.none) {
            Page(spacing: YubaiSpace.gapSection) {
                sourceRows
                if !queue.isEmpty {
                    VStack(alignment: .leading, spacing: YubaiSpace.gapHeading) {
                        SectionHeading(title: "选了 \(queue.count) 份").padding(.horizontal, YubaiSpace.insetCard)
                        CardRows(queue) { item in queueRow(item) }
                    }
                }
                let unfinished = store.imports.filter { $0.undoneAt == nil && ($0.needsOrganization == true || !($0.organization?.questions.isEmpty ?? true)) }
                if !unfinished.isEmpty {
                    DisclosureGroup("稍后继续的整理") { ForEach(unfinished) { batch in Button(batch.filename) { result = batch }.frame(minHeight: YubaiSize.tapMin) } }
                }
            }
            if queue.isEmpty {
                Button("选文件") { filePicker = true }.buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("chooseBillFile")
                    .padding(YubaiSpace.insetPage)
            } else {
                Button("核对第 \(processed + 1) 份") { readNext() }.buttonStyle(PrimaryButtonStyle())
                    .disabled(queue.first?.preview == nil).accessibilityIdentifier("reviewNextImport")
                    .padding(YubaiSpace.insetPage)
            }
        }
    }
    private var sourceRows: some View {
        VStack(alignment: .leading, spacing: YubaiSpace.gapSection) {
            Card(style: .list) {
                VStack(spacing: YubaiSpace.none) {
                    sourceRow("微信支付", hint: "账单 → 下载账单 → 发到邮箱", identifier: "importSource_wechat") { filePicker = true }
                    EntryFormDivider()
                    sourceRow("支付宝", hint: "账单 → 开具交易流水证明", identifier: "importSource_alipay") { filePicker = true }
                    EntryFormDivider()
                    sourceRow("银行卡", hint: "网银导出的 CSV 或 Excel", identifier: "importSource_bank") { filePicker = true }
                    EntryFormDivider()
                    if store.preferences.isAIEnabled(for: .receiptRecognition) && IntelligenceRuntime.isConfigured {
                        sourceRow("截图或照片", hint: "付款成功页、小票", identifier: "chooseBillScreenshots") { photoPicker = true }
                    }
                }
            }
            importedBefore
        }
    }
    private func sourceRow(_ title: String, hint: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: YubaiSpace.gapGroup) {
                VStack(alignment: .leading, spacing: YubaiSpace.space2) {
                    Text(title).yubaiFont(YubaiFont.rowTitle)
                    Text(hint).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary).multilineTextAlignment(.leading)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right").yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary).accessibilityHidden(true)
            }.frame(minHeight: YubaiSize.rowDouble).contentShape(Rectangle())
        }.buttonStyle(PressButtonStyle()).accessibilityIdentifier(identifier).accessibilityLabel(title + "，" + hint)
    }
    @ViewBuilder private var importedBefore: some View {
        let batches = Array(store.imports.filter { $0.undoneAt == nil }.sorted { $0.importedAt > $1.importedAt }.prefix(5))
        if !batches.isEmpty {
            VStack(alignment: .leading, spacing: YubaiSpace.gapHeading) {
                Text("导入过的").yubaiFont(YubaiFont.callout, weight: .semibold).foregroundStyle(YubaiColor.labelSecondary)
                    .padding(.horizontal, YubaiSpace.space4)
                Card(style: .list) {
                    VStack(spacing: YubaiSpace.none) {
                        ForEach(batches) { batch in
                            HStack(spacing: YubaiSpace.gapGroup) {
                                Text(batch.filename + " · " + FixedFlowPresentation.monthDay(batch.importedAt)).yubaiFont(YubaiFont.row)
                                    .lineLimit(1).truncationMode(.middle).frame(maxWidth: .infinity, alignment: .leading)
                                Text("\(batch.importedCount) 笔").yubaiFont(YubaiFont.amount)
                            }.frame(minHeight: YubaiSize.rowSingle)
                            if batch.id != batches.last?.id { EntryFormDivider() }
                        }
                    }
                }
            }
        }
    }
    private func queueRow(_ item: ImportQueueFile) -> some View {
        HStack(spacing: YubaiSpace.gapGroup) {
            VStack(alignment: .leading, spacing: YubaiSpace.space4) {
                Text(item.name).yubaiFont(YubaiFont.row).lineLimit(1)
                if let p = item.preview {
                    Text("\(ImportStatementText.source(p.source)) · \(p.rows.count) 笔 · " + ImportStatementText.range(p.rows.compactMap { $0.entry?.date }))
                        .yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary)
                } else { Text(item.error ?? (item.reading ? "读取中" : "排队中")).yubaiFont(YubaiFont.meta).foregroundStyle(item.error == nil ? YubaiColor.labelSecondary : YubaiColor.amberInk) }
            }.frame(maxWidth: .infinity, alignment: .leading)
            if item.preview != nil {
                Button { open(item.id) } label: { Pill(text: "读好了", height: YubaiSize.tagHeight, showsDot: false) }.buttonStyle(PressButtonStyle())
            } else if item.reading {
                ImportReadingProgress(value: item.progress)
            } else {
                Button { queue.removeAll { $0.id == item.id }; queueTotal = max(processed, queueTotal - 1) } label: { Image(systemName: "xmark").frame(width: YubaiSize.tapMin, height: YubaiSize.tapMin) }
                    .buttonStyle(PressButtonStyle()).accessibilityLabel("移除" + item.name).accessibilityIdentifier("removeImport_" + item.id.uuidString)
            }
        }.accessibilityIdentifier("importQueue_" + item.id.uuidString)
    }
    private func previewView(_ p: ImportPreview) -> some View {
        VStack(spacing: YubaiSpace.none) {
            Page(spacing: YubaiSpace.gapSection, topPadding: YubaiSpace.gapGroup) {
                previewHeader(p)
                if welcomeReview == nil { decisionCard(p) }
                if !screenshot {
                    if welcomeReview == nil {
                        Card(style: .list) {
                            VStack(spacing: YubaiSpace.none) {
                                accountPicker
                                Divider().overlay(YubaiColor.separator)
                                Button { showCategories = true } label: {
                                    HStack(spacing: YubaiSpace.gapGroup) { Text("分类对应"); Spacer(); Text("\(directCategoryCount(p)) 个直接对上").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary); Image(systemName: "chevron.right") }
                                        .frame(minHeight: YubaiSize.tapMin).contentShape(Rectangle())
                                }.buttonStyle(PressButtonStyle()).accessibilityIdentifier("importCategoryMapping")
                                if accountID == nil { Button("添加账户") { showAccount = true }.frame(minHeight: YubaiSize.tapMin) }
                            }
                        }
                    }
                    Segmented(choices: [("全部", "全部 \(p.rows.count)"), ("要你选", "要你选 \(p.rows.filter(needsDecision).count)"), ("不导入", "不导入 \(p.rows.filter { !$0.included }.count)")], selection: $filter)
                        .accessibilityIdentifier("importPreviewFilter")
                }
                if busy { ProgressView("正在核对…").yubaiFont(YubaiFont.caption) }
                if screenshot {
                    CardRows(p.rows) { row in previewRow(row) }
                } else {
                    ForEach(groupedRows(p)) { group in
                        VStack(alignment: .leading, spacing: YubaiSpace.gapHeading) {
                            Text(group.title).yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary).padding(.horizontal, YubaiSpace.insetCard)
                            CardRows(group.rows) { row in previewRow(row) }
                        }
                    }
                }
                if screenshot {
                    Button("对照原图") { showScreenshot = true }.buttonStyle(SecondaryButtonStyle()).accessibilityIdentifier("viewImportScreenshot")
                    Toggle("金额和原图对得上", isOn: $screenshotConfirmed).tint(YubaiColor.toggleOn).accessibilityIdentifier("confirmScreenshotAmounts")
                }
            }
            if welcomeReview == nil { previewActions(p) }
        }
    }
    private func previewHeader(_ p: ImportPreview) -> some View {
        VStack(alignment: .leading, spacing: YubaiSpace.gapGroup) {
            if screenshot {
                HStack(spacing: YubaiSpace.gapGroup) {
                    Text("截图 · \(p.rows.count) 笔").yubaiFont(YubaiFont.heroLabel)
                    Spacer()
                    sourcePill(p)
                }
            } else {
                VStack(alignment: .leading, spacing: YubaiSpace.space4) {
                    Text("\(ImportStatementText.source(p.source)) · " + ImportStatementText.range(p.rows.compactMap { $0.entry?.date }) + " · \(p.rows.count) 笔").yubaiFont(YubaiFont.rowTitle)
                    sourcePill(p)
                }
                Card(style: .compact) {
                    VStack(spacing: YubaiSpace.gapGroup) {
                        HStack(spacing: YubaiSpace.gapGroup) { countPill("将导入", p.selectedEntries.count); countPill("已经记过", p.duplicateCount); countPill("要你选", p.rows.filter(needsDecision).count) }
                        // Review totals follow the same direction as each row's amount sign.
                        // Nature (income, refund, unknown incoming, etc.) stays unchanged.
                        let outgoing = p.selectedEntries.filter { !$0.nature.inflow }, incoming = p.selectedEntries.filter { $0.nature.inflow }
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: YubaiSpace.gapGroup) { total("流出", entries: outgoing); Spacer(); total("流入", entries: incoming) }
                            VStack(alignment: .leading, spacing: YubaiSpace.space8) { total("流出", entries: outgoing); total("流入", entries: incoming) }
                        }
                    }
                }
            }
        }
    }
    @ViewBuilder private func sourcePill(_ p: ImportPreview) -> some View {
        if p.columnMapping == nil {
            LocalSourcePill().accessibilityIdentifier("importPrivacySummary")
        } else {
            let count = activeFileID.flatMap { cloudSampleCounts[$0] }
            NavigationLink { CloudSendLogView() } label: { Pill(text: count.map { "云端 · \($0) 行 ›" } ?? "云端 ›", variant: .amber, showsDot: false) }
                .buttonStyle(PressButtonStyle()).frame(minHeight: YubaiSize.tapMin)
                .accessibilityLabel(count.map { "已发送表头和 \($0) 行脱敏样例，查看发送内容" } ?? "已发送脱敏表头和样例，查看发送内容")
                .accessibilityIdentifier("importPrivacySummary")
        }
    }
    private func countPill(_ label: String, _ count: Int) -> some View {
        VStack(alignment: .leading, spacing: YubaiSpace.space4) {
            Text("\(count)").yubaiFont(YubaiFont.amountDonut)
            Text(label).yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func total(_ title: String, entries: [Entry]) -> some View {
        HStack(spacing: YubaiSpace.space8) {
            Text("\(title) \(entries.count) 笔").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelMuted)
            AmountLabel(cents: entries.reduce(0) { $0 + $1.amount }, hide: store.preferences.hideAmounts, role: .small, sign: .none)
        }.accessibilityElement(children: .combine).accessibilityIdentifier("importTotal_" + title)
    }
    private var accountPicker: some View {
        Picker("没写账户的记到", selection: $accountID) {
            Text("请选择账户").tag(UUID?.none)
            ForEach(store.accounts.filter { !$0.archived }) { Text($0.name).tag(Optional($0.id)) }
        }.yubaiFont(YubaiFont.row).frame(minHeight: YubaiSize.tapMin).accessibilityIdentifier("importDefaultAccount")
    }
    private var screenshotOriginal: some View {
        Page {
            if store.preferences.hideAmounts { Text("金额已隐藏") }
            else {
                #if os(iOS)
                if let image = screenshotImage { Image(uiImage: image).resizable().scaledToFit().accessibilityLabel("账单原图") }
                #elseif os(macOS)
                if let image = screenshotImage { Image(nsImage: image).resizable().scaledToFit().accessibilityLabel("账单原图") }
                #endif
            }
        }.navigationTitle("原图").yubaiNavigation().manualSheetHeader("原图", cancelTitle: "关闭", showsAction: false)
    }
    private func unknownCategories(_ p: ImportPreview) -> [String] {
        var seen = Set<String>()
        return p.rows.filter { !Classification.isPending($0.sourceCategory) && CategoryMapping.match($0.sourceCategory, in: store.current, income: $0.entry?.nature.categoryIncome ?? false) == nil && seen.insert($0.sourceCategory).inserted }.map(\.sourceCategory)
    }
    private func directCategoryCount(_ p: ImportPreview) -> Int {
        Set(p.rows.filter { row in
            row.sourceCategory != Classification.pendingCategory && (categoryMappings[row.sourceCategory] != nil || CategoryMapping.match(row.sourceCategory, in: store.current, income: row.entry?.nature.categoryIncome ?? false) != nil)
        }.map(\.sourceCategory)).count
    }
    private func needsDecision(_ row: ImportRow) -> Bool {
        if [.invalid, .conflict, .needsAccount].contains(row.status) { return true }
        if row.status == .duplicate || row.status == .skipped { return false }
        if row.status == .possibleDuplicate && rowSelections[row.line] == nil { return true }
        if screenshot && rowEdits[row.line] == nil && row.entry?.note.contains("待核对") == true { return true }
        return !row.sourceCategory.isEmpty && row.sourceCategory != Classification.pendingCategory && CategoryMapping.match(row.sourceCategory, in: store.current, income: row.entry?.nature.categoryIncome ?? false) == nil && categoryMappings[row.sourceCategory] == nil
    }
    @ViewBuilder private func decisionCard(_ p: ImportPreview) -> some View {
        let unknown = unknownCategories(p)
        let methods = p.paymentMethods
        let possible = p.rows.filter { $0.status == .possibleDuplicate && rowSelections[$0.line] == nil }
        let invalid = p.rows.filter { [.invalid, .conflict].contains($0.status) }
        if !unknown.isEmpty || !methods.isEmpty || !possible.isEmpty || !invalid.isEmpty {
            Card(style: .compact, background: YubaiColor.amberTint) {
                VStack(alignment: .leading, spacing: YubaiSpace.gapGroup) {
                    Text("要你决定的事").yubaiFont(YubaiFont.rowTitle).foregroundStyle(YubaiColor.amberStrong)
                    ForEach(unknown, id: \.self) { name in
                        let count = p.rows.filter { $0.sourceCategory == name }.count
                        VStack(alignment: .leading, spacing: YubaiSpace.space8) {
                            Text("分类「\(name)」你这里还没有，\(count) 笔").yubaiFont(YubaiFont.row).foregroundStyle(YubaiColor.amberStrong)
                            ViewThatFits(in: .horizontal) {
                                HStack(spacing: YubaiSpace.space8) { categoryChoices(name, preview: p) }
                                VStack(alignment: .leading, spacing: YubaiSpace.space8) { categoryChoices(name, preview: p) }
                            }
                        }
                    }
                    ForEach(methods, id: \.self) { method in
                        Picker(method, selection: Binding<UUID?>(get: { accountMappings[method] }, set: { accountMappings[method] = $0 })) {
                            Text("请选择对应账户").tag(UUID?.none)
                            ForEach(store.accounts.filter { !$0.archived }) { Text($0.name).tag(Optional($0.id)) }
                        }.yubaiFont(YubaiFont.row).frame(minHeight: YubaiSize.tapMin).accessibilityIdentifier("mapping_" + method)
                    }
                    if !methods.isEmpty { Button("添加缺少的账户") { showAccount = true }.frame(minHeight: YubaiSize.tapMin) }
                    if !possible.isEmpty {
                        Text("\(possible.count) 笔可能已经记过").yubaiFont(YubaiFont.row)
                        HStack(spacing: YubaiSpace.space8) {
                            Button("核对这几笔") { filter = "要你选" }.buttonStyle(SecondaryButtonStyle(background: YubaiColor.raised, compact: true))
                            Button("这些不导入") { for row in possible { select(row, included: false) } }.buttonStyle(SecondaryButtonStyle(background: YubaiColor.raised, compact: true))
                        }
                    }
                    if !invalid.isEmpty { Text("\(invalid.count) 行没读好，暂不导入").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.amberInk) }
                }
            }
        }
    }
    private func categoryChoices(_ name: String, preview p: ImportPreview) -> some View {
        let fallback = p.rows.first { $0.sourceCategory == name }?.entry?.nature == .income ? "其他收入" : "其他支出"
        return Group {
            Button("新建「\(name)」") { confirmedNewCategories.insert(name); categoryMappings[name] = name }
                .buttonStyle(SecondaryButtonStyle(background: confirmedNewCategories.contains(name) ? YubaiColor.selected : YubaiColor.raised, compact: true))
                .accessibilityAddTraits(confirmedNewCategories.contains(name) ? .isSelected : []).accessibilityIdentifier("createImportCategory_" + name)
            Button("归到「\(fallback)」") { confirmedNewCategories.remove(name); categoryMappings[name] = fallback }
                .buttonStyle(SecondaryButtonStyle(background: categoryMappings[name] == fallback ? YubaiColor.selected : YubaiColor.raised, compact: true))
                .accessibilityAddTraits(categoryMappings[name] == fallback ? .isSelected : []).accessibilityIdentifier("fallbackImportCategory_" + name)
        }
    }
    private var categoryCorrespondence: some View {
        Page {
            if let preview {
                ForEach(sourceCategoryNames(preview), id: \.self) { name in
                    let nature = preview.rows.first { $0.sourceCategory == name }?.entry?.nature
                    let income = nature.map { $0 != .refund && $0.inflow } ?? false
                    let raw = categoryMappings[name] ?? name
                    let choice = CategoryMapping.match(raw, in: store.current, income: income) ?? CategoryAssignment(path: raw)
                    Card(style: .list) {
                        VStack(alignment: .leading, spacing: YubaiSpace.space8) {
                            Text(name).yubaiFont(YubaiFont.caption).lineLimit(1).fixedSize()
                            CategoryPickerField(income: income, selection: choice, identifier: "importCategory_" + name) { selected in
                                confirmedNewCategories.remove(name); categoryMappings[name] = selected.path
                            }
                        }
                    }
                }
            }
        }.navigationTitle("分类对应").yubaiNavigation().manualSheetHeader("分类对应", cancelTitle: "关闭", showsAction: false)
    }
    private func sourceCategoryNames(_ preview: ImportPreview) -> [String] {
        var seen = Set<String>()
        return preview.rows.map(\.sourceCategory).filter { !$0.isEmpty && seen.insert($0).inserted }
    }
    private func groupedRows(_ p: ImportPreview) -> [ImportDayGroup] {
        let rows = p.rows.filter { filter == "全部" || (filter == "要你选" && needsDecision($0)) || (filter == "不导入" && !$0.included) }
        let grouped = Dictionary(grouping: rows) { $0.entry.map { Dates.day($0.date) } ?? Date.distantPast }
        return grouped.keys.sorted(by: >).map { date in
            ImportDayGroup(id: date, title: date == .distantPast ? "日期没读出" : ImportStatementText.range([date]), rows: grouped[date, default: []].sorted { ($0.entry?.date ?? .distantPast) > ($1.entry?.date ?? .distantPast) })
        }
    }
    private func previewRow(_ row: ImportRow) -> some View {
        HStack(spacing: YubaiSpace.space8) {
            if row.entry != nil && [.ready, .possibleDuplicate].contains(row.status) {
                Button { select(row, included: !row.included) } label: {
                    Image(systemName: row.included ? "checkmark.square.fill" : "square").foregroundStyle(row.included ? YubaiColor.brand : YubaiColor.labelSecondary).frame(width: YubaiSize.tapMin, height: YubaiSize.tapMin)
                }.buttonStyle(PressButtonStyle()).accessibilityLabel(row.included ? "不导入这一行" : "导入这一行").accessibilityValue(row.included ? "已选" : "未选").accessibilityIdentifier("selectImportRow_" + String(row.line))
            }
            VStack(alignment: .leading, spacing: YubaiSpace.space4) {
                Text(row.entry?.title ?? "第 \(row.line) 行").yubaiFont(YubaiFont.row).lineLimit(textSize.isAccessibilitySize ? nil : 2)
                Text(rowSubtitle(row)).yubaiFont(YubaiFont.meta).foregroundStyle(needsDecision(row) ? YubaiColor.amberInk : YubaiColor.labelSecondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
            if let entry = row.entry { AmountLabel(cents: entry.amount, hide: store.preferences.hideAmounts, sign: entry.nature.inflow ? .inflow : .none) }
            if screenshot, row.entry != nil {
                Button { editingScreenshotRow = row } label: { Image(systemName: "chevron.right").yubaiFont(YubaiFont.meta).frame(width: YubaiSize.tapMin, height: YubaiSize.tapMin) }
                    .buttonStyle(PressButtonStyle()).accessibilityLabel("核对这一笔").accessibilityIdentifier("editScreenshotRow_" + String(row.line))
            }
        }.opacity(row.status == .duplicate ? 0.6 : 1).padding(.vertical, YubaiSpace.space4)
    }
    private func rowSubtitle(_ row: ImportRow) -> String {
        if store.preferences.hideAmounts && [.invalid, .conflict].contains(row.status) { return "这一行需要核对" }
        guard let entry = row.entry else { return row.message }
        let detail: String
        switch row.status {
        case .duplicate: detail = "已经记过"
        case .possibleDuplicate: detail = "可能记重了"
        case .needsAccount, .invalid, .conflict, .skipped: detail = row.message
        case .ready: detail = needsDecision(row) ? (screenshot ? "日期和收支待核对" : "分类待定") : Classification.displayCategory(entry.category)
        }
        return ImportStatementText.time(entry.date) + " · " + detail
    }
    private func previewActions(_ p: ImportPreview) -> some View {
        let layout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: YubaiSpace.gapGroup)) : AnyLayout(HStackLayout(spacing: YubaiSpace.gapGroup))
        return VStack(spacing: YubaiSpace.gapGroup) {
            if screenshot {
                HStack(spacing: YubaiSpace.gapGroup) {
                    Text("选了 \(p.selectedEntries.count) 笔").yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary)
                    Spacer()
                    AmountLabel(cents: p.selectedEntries.filter { !$0.nature.inflow }.reduce(0) { $0 + $1.amount }, hide: store.preferences.hideAmounts, sign: .outflow)
                }.padding(.horizontal, YubaiSpace.insetCard)
            }
            layout {
                Button("跳过这份") { finishFile(); preview = nil; readNext() }.buttonStyle(SecondaryButtonStyle()).accessibilityIdentifier("skipImportFile")
                Button("导入 \(p.selectedEntries.count) 笔", action: commit).buttonStyle(PrimaryButtonStyle())
                    .disabled(busy || accountID == nil || p.selectedEntries.isEmpty || p.rows.contains { $0.included && needsDecision($0) } || (screenshot && !screenshotConfirmed))
                    .accessibilityIdentifier("commitImport")
            }
        }.padding(YubaiSpace.insetPage)
    }
    @ViewBuilder func resultView(_ savedBatch: ImportBatch) -> some View {
        ImportResultPage(batchID: savedBatch.id, hasNext: !queue.isEmpty,
                         next: { result = nil; readNext() },
                         restart: { result = nil; preview = nil; data = nil })
    }
    private func select(_ row: ImportRow, included: Bool) {
        guard let index = preview?.rows.firstIndex(where: { $0.id == row.id }) else { return }
        rowSelections[row.line] = included; preview?.rows[index].included = included
        if let welcomeReview, let preview { welcomeReview.wrappedValue = preview }
    }
    private func enqueue(_ files: [ImportQueueFile]) {
        localError = nil; queue.append(contentsOf: files); queueTotal += files.count
        if queueTask == nil { prepareQueue() }
    }
    @MainActor private func prepareQueue() {
        let runID = UUID(); queueRunID = runID
        queueTask = Task { @MainActor in
            defer { if queueRunID == runID { queueTask = nil } }
            while let index = queue.firstIndex(where: { $0.preview == nil && $0.error == nil && !$0.reading }) {
                let item = queue[index], id = item.id
                queue[index].reading = true
                do {
                    let original: Data
                    var name = item.name
                    var image = false
                    switch item.input {
                    case .file(let url):
                        original = try await Task.detached(priority: .userInitiated) {
                            let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                            guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 50 * 1024 * 1024 else { throw YubaiError.invalid("单个文件请小于 50 MB。") }
                            return try Data(contentsOf: url)
                        }.value
                        image = UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true
                    case .photo(let photo):
                        guard let bytes = try await photo.loadTransferable(type: Data.self) else { throw YubaiError.invalid("图片读取失败。") }
                        original = bytes; image = true
                        name += "." + (photo.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg")
                    case .pasted(let statement): original = statement.data
                    case .screenshot(let bytes): original = bytes; image = true
                    }
                    try Task.checkCancellation()
                    guard original.count <= 50 * 1024 * 1024 else { throw YubaiError.invalid("单个文件请小于 50 MB。") }
                    if image {
                        guard store.preferences.isAIEnabled(for: .receiptRecognition), IntelligenceRuntime.isConfigured else { throw YubaiError.invalid("云端智能没开") }
                        queue.removeAll { $0.id == id }
                        processed += 1
                        receiptCapture = ImportReceiptSelection(data: original)
                        return
                    }
                    updateQueue(id) { $0.progress = 1 }
                    let table: Data
                    if image {
                        table = try await Task.detached(priority: .userInitiated) { try Self.screenshotTable(original) }.value
                    } else { table = original }
                    try Task.checkCancellation()
                    updateQueue(id) { $0.progress = 2 }
                    let ledger = previewLedger()
                    guard let account = accountID ?? ledger.accounts.last?.id else { throw YubaiError.invalid("请选择导入账户。") }
                    let transport = store.assistantTransport(for: store.current, feature: image ? .receiptRecognition : .importClassification)
                    let mapper = transport.map { transport in
                        ImportSourceMapper(base: AIImportColumnMapper(transport: transport), sampleCount: { count in cloudSampleCounts[id] = count })
                    }
                    let worker = Task.detached(priority: .userInitiated) {
                        if let mapper {
                            return try await BillImporter.preview(data: table, filename: name, accountID: account, ledger: ledger, requireAccountMapping: true, columnMapper: mapper)
                        }
                        return try BillImporter.preview(data: table, filename: name, accountID: account, ledger: ledger, requireAccountMapping: true)
                    }
                    var parsed = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
                    try Task.checkCancellation()
                    if image { parsed = BillImporter.screenshotPreview(parsed, original: original, ledger: ledger) }
                    updateQueue(id) { $0.name = name; $0.original = original; $0.table = table; $0.preview = parsed; $0.screenshot = image; $0.reading = false; $0.progress = 3 }
                    if reviewWhenReady, queue.first?.id == id { reviewWhenReady = false; open(id) }
                } catch {
                    guard !Task.isCancelled else { return }
                    updateQueue(id) { $0.reading = false; $0.error = error.localizedDescription }
                    if reviewWhenReady, queue.first?.id == id { reviewWhenReady = false; localError = error.localizedDescription }
                }
            }
        }
    }
    private func updateQueue(_ id: UUID, _ update: (inout ImportQueueFile) -> Void) {
        if let index = queue.firstIndex(where: { $0.id == id }) { update(&queue[index]) }
    }
    private func previewLedger() -> Ledger {
        var ledger = store.current
        if accountID == nil { ledger.accounts.append(Account(name: "待选择导入账户")) }
        return ledger
    }
    private func readNext() {
        guard let first = queue.first else { result = nil; preview = nil; return }
        if first.preview != nil { open(first.id) }
        else { reviewWhenReady = true; preview = nil; if let error = first.error { localError = error; reviewWhenReady = false } }
    }
    private func open(_ id: UUID) {
        saveReviewChoices()
        guard let item = queue.first(where: { $0.id == id }), let prepared = item.preview else { return }
        activeFileID = id; data = item.original; tableData = item.table; filename = item.name
        result = nil; localError = nil; accountMappings = item.accountMappings; categoryMappings = item.categoryMappings; rowSelections = item.selections; rowEdits = item.edits
        confirmedNewCategories = item.confirmedNewCategories
        #if os(iOS)
        screenshotImage = item.screenshot ? item.original.flatMap { UIImage(data: $0) } : nil
        #elseif os(macOS)
        screenshotImage = item.screenshot ? item.original.flatMap { NSImage(data: $0) } : nil
        #endif
        screenshot = item.screenshot; screenshotConfirmed = item.screenshotConfirmed; filter = "全部"; preview = prepared
        refreshPreview()
    }
    private func refreshPreview() {
        guard preview != nil, let bytes = tableData else { return }
        let ledger = previewLedger()
        guard let account = accountID ?? ledger.accounts.last?.id else { return }
        let name = filename, methods = accountMappings, categories = categoryMappings
        let mapping = preview?.columnMapping, header = preview?.mappedHeader ?? 0
        let oldRows = Dictionary(uniqueKeysWithValues: (preview?.rows ?? []).map { ($0.line, $0) })
        let requestID = UUID(); parseID = requestID; busy = true; localError = nil
        parsingTask?.cancel()
        parsingTask = Task { @MainActor in
            do {
                var parsed = try await Task.detached(priority: .userInitiated) {
                    try BillImporter.preview(data: bytes, filename: name, accountID: account, ledger: ledger, accountMappings: methods, requireAccountMapping: true, categoryMappings: categories, mapping: mapping, mappedHeader: header)
                }.value
                guard parseID == requestID, !Task.isCancelled else { return }
                if screenshot, let data { parsed = BillImporter.screenshotPreview(parsed, original: data, ledger: ledger) }
                for i in parsed.rows.indices {
                    if let old = oldRows[parsed.rows[i].line] {
                        parsed.rows[i].id = old.id
                        if let id = old.entry?.id { parsed.rows[i].entry?.id = id }
                    }
                }
                for i in parsed.rows.indices where [.ready, .possibleDuplicate].contains(parsed.rows[i].status) {
                    if let raw = categories[parsed.rows[i].sourceCategory],
                       let entry = parsed.rows[i].entry,
                       let choice = CategoryMapping.match(raw, in: ledger, income: entry.nature.categoryIncome),
                       SubcategoryClassifier.valid(choice, in: ledger, nature: entry.nature) {
                        parsed.rows[i].entry?.category = choice.category
                        parsed.rows[i].entry?.subcategory = choice.subcategory
                        parsed.rows[i].entry?.subcategoryUserEdited = true
                    }
                    if let selected = rowSelections[parsed.rows[i].line] { parsed.rows[i].included = selected }
                    else if screenshot { parsed.rows[i].included = false }
                    if let edited = rowEdits[parsed.rows[i].line], var entry = parsed.rows[i].entry {
                        entry.title = edited.title; entry.date = edited.date; entry.nature = edited.nature; entry.category = edited.category; entry.subcategory = edited.subcategory; entry.subcategoryUserEdited = edited.subcategoryUserEdited; entry.userEdited = edited.userEdited
                        parsed.rows[i].entry = entry
                    }
                }
                preview = parsed; busy = false
            } catch {
                guard parseID == requestID, !Task.isCancelled else { return }
                localError = error.localizedDescription; busy = false
            }
        }
    }
    private func finishFile() {
        parsingTask?.cancel(); parseID = UUID(); busy = false
        if let activeFileID { queue.removeAll { $0.id == activeFileID }; processed += 1 }
        activeFileID = nil; data = nil; tableData = nil; localError = nil
    }
    private func saveReviewChoices() {
        guard let activeFileID else { return }
        updateQueue(activeFileID) {
            $0.preview = preview; $0.accountMappings = accountMappings; $0.categoryMappings = categoryMappings
            $0.confirmedNewCategories = confirmedNewCategories
            $0.selections = rowSelections; $0.edits = rowEdits; $0.screenshotConfirmed = screenshotConfirmed
        }
    }
    private func returnToIntake() {
        saveReviewChoices(); parsingTask?.cancel(); parseID = UUID(); preview = nil; activeFileID = nil; busy = false
    }
    private func commit() {
        guard !busy, accountID != nil, let preview, let data, !preview.selectedEntries.isEmpty,
              !preview.rows.contains(where: { $0.included && needsDecision($0) }), !screenshot || screenshotConfirmed else { return }
        let categories = confirmedNewCategories
        busy = true
        parsingTask = Task { @MainActor in
            defer { busy = false }
            do {
                guard let batch = try await store.commitImport(preview, data: data, confirmedNewCategories: categories) else { return }
                result = batch; self.preview = nil; parsingTask = nil; finishFile()
                Task { await store.organizeImport(batch.id) }
            } catch is CancellationError { }
            catch { localError = error.localizedDescription }
        }
    }
    /// OCR stays on device. Only decimal money candidates become selectable rows;
    /// none is selected until the user reviews the screenshot amounts.
    nonisolated private static func screenshotTable(_ bytes: Data) throws -> Data {
        let receipt = try ReceiptReader.recognize(bytes)
        if let table = PastedStatement.detect(receipt.text) { return table.data }
        return try ReceiptTextParser.table(lines: receipt.text.components(separatedBy: .newlines))
    }
}

private struct ImportScreenshotEntryEditor: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var entry: Entry
    let save: (Entry) -> Void
    var body: some View {
        Form {
            Section {
                TextField("用途", text: $entry.title)
                AmountLabel(cents: entry.amount, hide: store.preferences.hideAmounts)
                DatePicker("日期", selection: $entry.date, displayedComponents: [.date, .hourAndMinute])
                Picker("收支", selection: $entry.nature) { Text("支出").tag(Nature.expense); Text("收入").tag(Nature.income) }
                CategoryPickerField(income: entry.nature.categoryIncome,
                                    selection: .init(category: entry.category, subcategory: entry.subcategory),
                                    identifier: "screenshotCategory") { choice in
                    entry.category = choice.category; entry.subcategory = choice.subcategory; entry.subcategoryUserEdited = true
                }
            }.listRowBackground(YubaiColor.card)
        }.onChange(of: entry.nature) { _, _ in
            entry.category = Classification.pendingCategory; entry.subcategory = nil; entry.subcategoryUserEdited = false
        } .editorForm().manualSheetHeader("核对这一笔", actionTitle: "核对好了", enabled: !entry.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                                           actionIdentifier: "saveScreenshotEntry", action: { entry.userEdited = true; save(entry); dismiss() })
    }
}
