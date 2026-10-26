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
    var selections: [Int: Bool] = [:]
    var edits: [Int: Entry] = [:]
    var screenshotConfirmed = false
}

private struct ImportDayGroup: Identifiable {
    let id: Date
    let title: String
    let rows: [ImportRow]
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
    @State private var accountID: UUID?
    @State private var filePicker = false
    @State private var photoPicker = false
    @State private var photos: [PhotosPickerItem] = []
    @State private var data: Data?
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
    @State private var rowSelections: [Int: Bool] = [:]
    @State private var parseID = UUID()
    @State private var questionText: [UUID: String] = [:]
    @State private var freeTextQuestion: UUID?
    @State private var parsingTask: Task<Void, Never>?
    @State private var queueTask: Task<Void, Never>?
    @State private var queueRunID = UUID()
    @State private var appeared = false
    @State private var screenshot = false
    @State private var screenshotConfirmed = false
    @State private var rowEdits: [Int: Entry] = [:]
    @State private var editingScreenshotRow: ImportRow?
    @State private var showScreenshot = false
    init(pasted: PastedStatement? = nil, initialScreenshot: Data? = nil) { self.pasted = pasted; self.initialScreenshot = initialScreenshot }
    private var resultTitle: String {
        guard let result else { return preview == nil ? "导入" : "核对 \(processed + 1)/\(max(queueTotal, 1))" }
        guard let batch = store.current.imports.first(where: { $0.id == result.id && $0.undoneAt == nil }) else { return "这一批已撤销" }
        return batch.needsOrganization == true ? "账单已保存" : "整理好了"
    }
    var body: some View {
        VStack(spacing: YubaiSpace.none) {
            if let result { resultView(result) }
            else if let preview { previewView(preview) }
            else { intake }
            if let localError { InlineNote(text: store.current.preferences.hideAmounts ? "这份账单还没读好" : localError, style: .attention).padding(YubaiSpace.insetPage).textSelection(.enabled) }
        }
        .yubaiFont(YubaiFont.body).foregroundStyle(YubaiColor.label).paperBackground()
        .amountPrivacy(store.current.preferences.hideAmounts).navigationTitle(resultTitle).yubaiNavigation()
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { CloseButton() }
            ToolbarItem(placement: .primaryAction) {
                if screenshot && preview != nil {
                    Menu { accountPicker; Button("添加账户") { showAccount = true } } label: { Image(systemName: "creditcard") }
                        .accessibilityLabel("选择截图记账的账户").accessibilityValue(store.current.accountName(accountID))
                }
            }
            ToolbarItem(placement: .cancellationAction) {
                if let result, let batch = store.current.imports.first(where: { $0.id == result.id && $0.undoneAt == nil }) {
                    Button("整批撤销", role: .destructive) { store.undoImport(batch.id) }
                        .disabled(store.organizingBatchID == batch.id).frame(minHeight: YubaiSize.tapMin).accessibilityIdentifier("undoImportResult")
                } else if preview != nil {
                    Button("导入", action: returnToIntake)
                }
            }
        }
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
        .sheet(isPresented: $showAccount) { NavigationStack { AccountEditor(account: nil) }.environment(store).appErrors().frame(minWidth: 340, minHeight: 520) }
        .sheet(isPresented: $showCategories) { NavigationStack { categoryCorrespondence }.environment(store) }
        .sheet(isPresented: $showScreenshot) { NavigationStack { screenshotOriginal }.environment(store) }
        .sheet(item: $editingScreenshotRow) { row in
            if let entry = row.entry {
                NavigationStack {
                    ImportScreenshotEntryEditor(entry: entry) { edited in
                        rowEdits[row.line] = edited
                        if let index = preview?.rows.firstIndex(where: { $0.id == row.id }) { preview?.rows[index].entry = edited }
                        screenshotConfirmed = false
                    }
                }.environment(store)
            }
        }
        .onChange(of: store.current.accounts.count) { _, _ in
            if accountID == nil { accountID = store.current.accounts.last(where: { !$0.archived })?.id; refreshPreview() }
        }
        .onChange(of: accountID) { _, _ in refreshPreview() }
        .onChange(of: accountMappings) { _, _ in refreshPreview() }
        .onChange(of: categoryMappings) { _, _ in refreshPreview() }
        .onDisappear { parsingTask?.cancel(); queueTask?.cancel() }
        .onAppear {
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
            accountID = store.current.accounts.first { !$0.archived && ($0.kind == .cash || $0.kind == .bank) }?.id
                ?? store.current.accounts.first { !$0.archived }?.id
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
                HStack(spacing: YubaiSpace.gapGroup) {
                    intakeButton("截图", symbol: "photo.on.rectangle", identifier: "chooseBillScreenshots") { photoPicker = true }
                    intakeButton("账单文件", symbol: "doc.badge.plus", identifier: "chooseBillFile") { filePicker = true }
                }
                VStack(alignment: .leading, spacing: YubaiSpace.space8) {
                    Text("认得这些导出").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: YubaiSpace.space8) { exportChips(["微信", "支付宝", "银行流水", "蜜蜂记账"]) }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 72))], alignment: .leading, spacing: YubaiSpace.space8) { exportChips(["微信", "支付宝", "银行流水", "蜜蜂记账"]) }
                    }
                    HStack(spacing: YubaiSpace.space8) { exportChips(["随手记", "鲨鱼记账", "钱迹"]) }
                }
                if !queue.isEmpty {
                    VStack(alignment: .leading, spacing: YubaiSpace.gapHeading) {
                        SectionHeading(title: "选了 \(queue.count) 份").padding(.horizontal, YubaiSpace.insetCard)
                        CardRows(queue) { item in queueRow(item) }
                    }
                }
                let unfinished = store.current.imports.filter { $0.undoneAt == nil && ($0.needsOrganization == true || !($0.organization?.questions.isEmpty ?? true)) }
                if !unfinished.isEmpty {
                    DisclosureGroup("稍后继续的整理") { ForEach(unfinished) { batch in Button(batch.filename) { result = batch }.frame(minHeight: YubaiSize.tapMin) } }
                }
            }
            Button("核对第 \(processed + 1) 份") { readNext() }.buttonStyle(PrimaryButtonStyle())
                .disabled(queue.first?.preview == nil).accessibilityIdentifier("reviewNextImport")
                .padding(YubaiSpace.insetPage)
        }
    }
    private func intakeButton(_ title: String, symbol: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: YubaiSpace.gapGroup) {
                Image(systemName: symbol).frame(minHeight: YubaiSize.barMax)
                VStack(alignment: .leading, spacing: YubaiSpace.space4) {
                    Text(title).yubaiFont(YubaiFont.rowTitle)
                }
            }.frame(maxWidth: .infinity, minHeight: YubaiSize.buttonHeight, alignment: .leading)
                .padding(YubaiSpace.insetCard).background(YubaiColor.card, in: RoundedRectangle(cornerRadius: YubaiRadius.card))
        }.buttonStyle(PressButtonStyle()).accessibilityIdentifier(identifier)
    }
    private func exportChips(_ names: [String]) -> some View {
        ForEach(names, id: \.self) { Pill(text: $0, variant: .neutral, showsDot: false) }
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
                ProgressView(value: item.progress, total: 3).tint(YubaiColor.brand).frame(width: YubaiSize.buttonHeight).accessibilityLabel("读取进度")
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
                decisionCard(p)
                if !screenshot {
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
            previewActions(p)
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
            AmountLabel(cents: entries.reduce(0) { $0 + $1.amount }, hide: store.current.preferences.hideAmounts, role: .small, sign: .none)
        }.accessibilityElement(children: .combine).accessibilityIdentifier("importTotal_" + title)
    }
    private var accountPicker: some View {
        Picker("没写账户的记到", selection: $accountID) {
            Text("请选择账户").tag(UUID?.none)
            ForEach(store.current.accounts.filter { !$0.archived }) { Text($0.name).tag(Optional($0.id)) }
        }.yubaiFont(YubaiFont.row).frame(minHeight: YubaiSize.tapMin).accessibilityIdentifier("importDefaultAccount")
    }
    private var screenshotOriginal: some View {
        Page {
            if store.current.preferences.hideAmounts { Text("金额已隐藏") }
            else if let data {
                #if os(iOS)
                if let image = UIImage(data: data) { Image(uiImage: image).resizable().scaledToFit().accessibilityLabel("账单原图") }
                #elseif os(macOS)
                if let image = NSImage(data: data) { Image(nsImage: image).resizable().scaledToFit().accessibilityLabel("账单原图") }
                #endif
            }
        }.navigationTitle("原图").yubaiNavigation().toolbar { CloseButton() }
    }
    private func unknownCategories(_ p: ImportPreview) -> [String] {
        let known = Set(store.current.categories.map(\.name))
        return Set(p.rows.map(\.sourceCategory).filter { !$0.isEmpty && $0 != Classification.pendingCategory && !known.contains($0) }).sorted()
    }
    private func directCategoryCount(_ p: ImportPreview) -> Int {
        Set(p.rows.map(\.sourceCategory).filter { name in
            name != Classification.pendingCategory && (categoryMappings[name] != nil || store.current.categories.contains { $0.name == name })
        }).count
    }
    private func needsDecision(_ row: ImportRow) -> Bool {
        if [.invalid, .conflict, .needsAccount].contains(row.status) { return true }
        if row.status == .duplicate || row.status == .skipped { return false }
        if row.status == .possibleDuplicate && rowSelections[row.line] == nil { return true }
        if screenshot && rowEdits[row.line] == nil && row.entry?.note.contains("待核对") == true { return true }
        return !row.sourceCategory.isEmpty && row.sourceCategory != Classification.pendingCategory && !store.current.categories.contains { $0.name == row.sourceCategory } && categoryMappings[row.sourceCategory] == nil
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
                            ForEach(store.current.accounts.filter { !$0.archived }) { Text($0.name).tag(Optional($0.id)) }
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
            Button("新建「\(name)」") { categoryMappings[name] = name }
                .buttonStyle(SecondaryButtonStyle(background: categoryMappings[name] == name ? YubaiColor.selected : YubaiColor.raised, compact: true))
                .accessibilityAddTraits(categoryMappings[name] == name ? .isSelected : []).accessibilityIdentifier("createImportCategory_" + name)
            Button("归到「\(fallback)」") { categoryMappings[name] = fallback }
                .buttonStyle(SecondaryButtonStyle(background: categoryMappings[name] == fallback ? YubaiColor.selected : YubaiColor.raised, compact: true))
                .accessibilityAddTraits(categoryMappings[name] == fallback ? .isSelected : []).accessibilityIdentifier("fallbackImportCategory_" + name)
        }
    }
    private var categoryCorrespondence: some View {
        Page {
            if let preview {
                ForEach(Set(preview.rows.map(\.sourceCategory).filter { !$0.isEmpty }).sorted(), id: \.self) { name in
                    Card(style: .list) {
                        Picker(name, selection: Binding(get: { categoryMappings[name] ?? name }, set: { categoryMappings[name] = $0 })) {
                            ForEach(Set(store.current.categories.map(\.name) + [name]).sorted(), id: \.self) { Text(Classification.displayCategory($0)).tag($0) }
                        }.frame(minHeight: YubaiSize.tapMin)
                    }
                }
            }
        }.navigationTitle("分类对应").yubaiNavigation().toolbar { CloseButton() }
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
            if let entry = row.entry { AmountLabel(cents: entry.amount, hide: store.current.preferences.hideAmounts, sign: entry.nature.inflow ? .inflow : .none) }
            if screenshot, row.entry != nil {
                Button { editingScreenshotRow = row } label: { Image(systemName: "chevron.right").yubaiFont(YubaiFont.meta).frame(width: YubaiSize.tapMin, height: YubaiSize.tapMin) }
                    .buttonStyle(PressButtonStyle()).accessibilityLabel("核对这一笔").accessibilityIdentifier("editScreenshotRow_" + String(row.line))
            }
        }.opacity(row.status == .duplicate ? 0.6 : 1).padding(.vertical, YubaiSpace.space4)
    }
    private func rowSubtitle(_ row: ImportRow) -> String {
        if store.current.preferences.hideAmounts && [.invalid, .conflict].contains(row.status) { return "这一行需要核对" }
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
                    AmountLabel(cents: p.selectedEntries.filter { !$0.nature.inflow }.reduce(0) { $0 + $1.amount }, hide: store.current.preferences.hideAmounts, sign: .outflow)
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
        if let batch = store.current.imports.first(where: { $0.id == savedBatch.id && $0.undoneAt == nil }) {
            Page {
                if store.organizingBatchID == batch.id { ProgressView("正在整理…").padding(YubaiSpace.insetCard) }
                Text(batch.filename + "，\(batch.importedCount) 笔，" + (batch.needsOrganization == true ? "已经保存了。" : "已经整理好了。"))
                    .yubaiFont(YubaiFont.heroLabel)
                Text("跳过 \(batch.duplicateCount) 笔重复，另有 \(batch.skippedCount) 行未导入。")
                    .yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                if let organization = batch.organization {
                    Card { VStack(alignment: .leading, spacing: YubaiSpace.gapGroup) {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), alignment: .leading)], alignment: .leading, spacing: YubaiSpace.space8) {
                            resultCount("归了类", organization.categoryCount)
                            resultCount("配成转账", organization.pairCount)
                            resultCount("像是固定收付", organization.recurringCount)
                            resultCount("可能记重了", organization.duplicateCount)
                        }
                        DisclosureGroup("看看改了什么") {
                            ForEach(Array(organization.changeSet.preview(in: store.current).enumerated()), id: \.offset) { _, line in
                                Text(store.current.preferences.hideAmounts ? "金额已隐藏" : line).yubaiFont(YubaiFont.caption).frame(maxWidth: .infinity, alignment: .leading)
                            }
                            ForEach(Array(organization.skipped.enumerated()), id: \.offset) { _, line in
                                Text(store.current.preferences.hideAmounts ? "金额已隐藏" : line).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                            }
                        }
                    } }
                    if !organization.questions.isEmpty {
                        Text("还有 \(min(5, organization.questions.count)) 个问题")
                            .yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.amberInk)
                        ForEach(Array(organization.questions.prefix(5))) { question in questionCard(question, batchID: batch.id) }
                    }
                    ForEach(organization.comments ?? []) { comment in
                        if let card = store.current.cards.first(where: { $0.dedupeKey == comment.dedupeKey }), card.dismissedAt == nil, !ButlerCards.isMuted(card.dedupeKey, in: store.current) {
                            ButlerCardView(card: card)
                        }
                    }
                }
                if batch.needsOrganization == true {
                    Card { VStack(alignment: .leading, spacing: YubaiSpace.gapGroup) {
                        Text(store.organizationErrors[batch.id] ?? "记录已保存").yubaiFont(YubaiFont.callout)
                        Button("现在整理") { Task { await store.organizeImport(batch.id) } }
                            .buttonStyle(SecondaryButtonStyle()).disabled(store.organizingBatchID != nil || store.assistantTransport(for: store.current) == nil)
                    } }
                }
                if !queue.isEmpty { Button("继续下一份") { result = nil; readNext() }.buttonStyle(PrimaryButtonStyle()).disabled(store.organizingBatchID != nil) }
                Button("回到现在") { store.destination = .overview; store.sheet = nil }.buttonStyle(PrimaryButtonStyle())
            }
        } else {
            Page { EmptyState("arrow.uturn.backward", "这一批已撤销", action: "继续导入", onAction: { result = nil; preview = nil; data = nil })
                Text("有效记录 \(store.current.activeEntries.count) 笔").accessibilityIdentifier("activeEntryCount")
            }
        }
    }
    private func resultCount(_ title: String, _ count: Int) -> some View {
        VStack(alignment: .leading, spacing: YubaiSpace.space4) {
            Text("\(count)").yubaiFont(YubaiFont.amountDonut)
            Text(title).yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary)
        }
    }
    private func questionCard(_ question: ImportQuestion, batchID: UUID) -> some View {
        let covered = Set(question.entryIDs)
        return Card(style: .compact, background: YubaiColor.amberTint) { VStack(alignment: .leading, spacing: YubaiSpace.space8) {
            Text(store.current.preferences.hideAmounts ? "有几笔记录要你核对" : question.text).yubaiFont(YubaiFont.cardTitle).accessibilityIdentifier("importQuestion")
            HStack(spacing: YubaiSpace.space8) {
                Pill(text: "\(question.entryIDs.count) 笔", variant: .neutral, showsDot: false)
                Spacer()
                Button("稍后") { store.destination = .overview; store.sheet = nil }
                    .buttonStyle(SecondaryButtonStyle(background: YubaiColor.raised, compact: true))
            }
            DisclosureGroup("看看这几笔") {
                LazyVStack(spacing: YubaiSpace.gapGroup) { ForEach(store.sortedEntries.filter { covered.contains($0.id) }) { EntryRow(entry: $0) } }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110))], alignment: .leading, spacing: YubaiSpace.space8) {
            ForEach(question.options.indices, id: \.self) { index in
                Button(store.current.preferences.hideAmounts ? "选项 \(index + 1)" : question.options[index].title) { store.answerImportQuestion(question, batchID: batchID, option: index) }
                    .disabled(store.current.preferences.hideAmounts)
                    .buttonStyle(SecondaryButtonStyle(background: YubaiColor.raised, compact: true)).accessibilityIdentifier("importAnswer_" + String(index))
            }
            Button("都不是") { freeTextQuestion = question.id }.buttonStyle(SecondaryButtonStyle(background: YubaiColor.raised, compact: true))
            }
            if freeTextQuestion == question.id {
                TextField("用自己的话补充用途", text: Binding(get: { questionText[question.id] ?? "" }, set: { questionText[question.id] = $0 }))
                Button("记下用途") { store.describeImportQuestion(question, batchID: batchID, text: questionText[question.id] ?? "") }
                    .disabled((questionText[question.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Text("没写用途").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
            }
        } }
    }
    private func select(_ row: ImportRow, included: Bool) {
        guard let index = preview?.rows.firstIndex(where: { $0.id == row.id }) else { return }
        rowSelections[row.line] = included; preview?.rows[index].included = included
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
                    updateQueue(id) { $0.progress = 1 }
                    let table: Data
                    if image {
                        table = try await Task.detached(priority: .userInitiated) { try Self.screenshotTable(original) }.value
                    } else { table = original }
                    try Task.checkCancellation()
                    updateQueue(id) { $0.progress = 2 }
                    let ledger = previewLedger()
                    guard let account = accountID ?? ledger.accounts.last?.id else { throw YubaiError.invalid("请选择导入账户。") }
                    let transport = store.assistantTransport(for: store.current)
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
                    if let selected = rowSelections[parsed.rows[i].line] { parsed.rows[i].included = selected }
                    else if screenshot { parsed.rows[i].included = false }
                    if let edited = rowEdits[parsed.rows[i].line], var entry = parsed.rows[i].entry {
                        entry.title = edited.title; entry.date = edited.date; entry.nature = edited.nature; entry.category = edited.category; entry.userEdited = edited.userEdited
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
            $0.selections = rowSelections; $0.edits = rowEdits; $0.screenshotConfirmed = screenshotConfirmed
        }
    }
    private func returnToIntake() {
        saveReviewChoices(); parsingTask?.cancel(); parseID = UUID(); preview = nil; activeFileID = nil; busy = false
    }
    private func commit() {
        guard !busy, accountID != nil, let preview, let data, !preview.selectedEntries.isEmpty,
              !preview.rows.contains(where: { $0.included && needsDecision($0) }), !screenshot || screenshotConfirmed else { return }
        var batch: ImportBatch?
        if store.update("导入账单", { ledger in
            for entry in preview.selectedEntries where !ledger.categories.contains(where: { $0.name == entry.category }) && entry.category != Classification.pendingCategory {
                ledger.categories.append(YubaiCore.Category(entry.category, income: entry.nature == .income))
            }
            batch = try BillImporter.commit(preview, data: data, to: &ledger)
        }) {
            result = batch; self.preview = nil; finishFile()
            if let batch { Task { await store.organizeImport(batch.id) } }
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
                AmountLabel(cents: entry.amount, hide: store.current.preferences.hideAmounts)
                DatePicker("日期", selection: $entry.date, displayedComponents: [.date, .hourAndMinute])
                Picker("收支", selection: $entry.nature) { Text("支出").tag(Nature.expense); Text("收入").tag(Nature.income) }
                Picker("分类", selection: $entry.category) {
                    ForEach(Set(store.current.categories.filter { $0.income == entry.nature.inflow }.map(\.name) + [entry.category]).sorted(), id: \.self) { Text(Classification.displayCategory($0)).tag($0) }
                }
            }.listRowBackground(YubaiColor.card)
        }.editorForm().navigationTitle("核对这一笔").yubaiNavigation().toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("核对好了") { entry.userEdited = true; save(entry); dismiss() }
                    .disabled(entry.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityIdentifier("saveScreenshotEntry")
            }
        }
    }
}
