import SwiftUI
import UniformTypeIdentifiers
import PhotosUI
import Vision
import YubaiCore

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
        let regex = try NSRegularExpression(pattern: #"[¥￥]?[−-]?\d[\d,]*\.\d{2}(?!\d)"#)
        var amounts: [String] = []
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            if let range = Range(match.range, in: text), let cents = try? Money.parse(String(text[range]), allowNegative: true), cents != 0 { let input = Money.input(abs(cents)); if !amounts.contains(input) { amounts.append(input) } }
        }
        let title = lines.first { line in line.count > 2 && line.count < 60 && !["支付", "微信", "支付宝", "交易", "账单", "金额", "详情", "服务", "时间", "单号", "收款方", "付款"].contains(where: line.contains) && line.rangeOfCharacter(from: .decimalDigits) == nil } ?? "截图补记"
        let date = lines.compactMap(Dates.parse).first
        return ReceiptCandidate(text: text, amounts: amounts, title: title, date: date)
    }
}

struct ImportView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var accountID: UUID?; @State private var filePicker = false; @State private var photo: PhotosPickerItem?
    @State private var data: Data?; @State private var filename = ""; @State private var preview: ImportPreview?
    @State private var busy = false; @State private var result: ImportBatch?; @State private var filter = "全部"
    @State private var queue: [URL] = []; @State private var queueTotal = 0; @State private var processed = 0
    @State private var receipt: ReceiptCandidate?; @State private var receiptAmount = ""; @State private var receiptTitle = ""
    @State private var receiptInflow = false; @State private var receiptDate = Date(); @State private var localError: String?
    @State private var showAccount = false
    @State private var accountMappings: [String: UUID] = [:]
    @State private var parseID = UUID()
    @State private var questionText: [UUID: String] = [:]
    @State private var freeTextQuestion: UUID?
    @State private var parsingTask: Task<Void, Never>?
    var body: some View {
        VStack(spacing: 0) {
            if let result { resultView(result) }
            else if busy { readingView }
            else if let receipt { receiptView(receipt) }
            else if let preview { previewView(preview) }
            else { intake }
            if let localError { InlineNote(text: localError, style: .attention).padding(YubaiSpace.space18).textSelection(.enabled) }
        }.yubaiFont(YubaiFont.body).foregroundStyle(YubaiColor.label).background(YubaiColor.canvas).navigationTitle("整理账单").yubaiNavigation().toolbar { CloseButton() }
            .fileImporter(isPresented: $filePicker, allowedContentTypes: [.commaSeparatedText, .tabSeparatedText, .plainText, .image, UTType(filenameExtension: "xlsx") ?? .data], allowsMultipleSelection: true) { result in
                switch result { case .success(let urls): queue = urls; queueTotal = urls.count; processed = 0; readNext(); case .failure(let e): localError = e.localizedDescription }
            }
            .onChange(of: photo) { _, value in guard let value else { return }; busy = true; localError = nil; Task { do { guard let bytes = try await value.loadTransferable(type: Data.self) else { throw YubaiError.invalid("图片读取失败。") }; data = bytes; filename = "账单截图-\(Dates.text(Date())).jpg"; await recognize(bytes) } catch { localError = error.localizedDescription; busy = false } } }
            .sheet(isPresented: $showAccount) { NavigationStack { AccountEditor(account: nil) }.environment(store).appErrors().frame(minWidth: 340, minHeight: 520) }
            .onChange(of: store.current.accounts.count) { _, _ in if accountID == nil { accountID = store.current.accounts.last?.id } }
            .onChange(of: accountMappings) { _, _ in if preview != nil, let data { parse(data) } }
            .onDisappear { parsingTask?.cancel() }
            .onAppear { if accountID == nil { accountID = store.current.accounts.first { !$0.archived && ($0.kind == .cash || $0.kind == .bank) }?.id }; if let url = store.importedURL { store.importedURL = nil; queue = [url]; queueTotal = 1; readNext() } }
    }
    private var readingView: some View {
        VStack(spacing: YubaiSpace.space20) {
            WaterLevelView(filledBands: 6)
            Text("正在读取账单…").yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelMuted)
            Text("原始文件留在本机；云端智能只接收脱敏后的任务摘要。").yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary)
        }.padding(YubaiSpace.space18).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    var accountPicker: some View {
        Picker("默认收付款账户", selection: $accountID) { Text("请选择账户").tag(UUID?.none); ForEach(store.current.accounts.filter { !$0.archived }) { Text($0.name).tag(Optional($0.id)) } }.onChange(of: accountID) { _, _ in if preview != nil, let data { parse(data) } }
    }
    var intake: some View {
        Form {
            Section { EmptyState("tray.and.arrow.down", "一次整理，安心继续生活", "支持微信、支付宝与标准银行账单。系统自动分类，只把真正不确定的地方留给你。") }.listRowBackground(YubaiColor.card).listRowSeparatorTint(YubaiColor.separator)
            Section("1 · 选择账户") { accountPicker; Button("添加账户") { showAccount = true }; InlineNote(text: "文件里有支付方式时，下一步可把零钱、银行卡分别对应到账户。没有标注支付方式的记录使用这里的默认账户。") }.listRowBackground(YubaiColor.card).listRowSeparatorTint(YubaiColor.separator)
            Section("2 · 选择文件或截图") {
                Button { filePicker = true } label: { Label("选择账单文件", systemImage: "doc.badge.plus") }.disabled(accountID == nil).accessibilityIdentifier("chooseBillFile")
                PhotosPicker(selection: $photo, matching: .images) { Label("从照片选一张账单截图", systemImage: "photo") }.disabled(accountID == nil)
                Text("文件支持 CSV、TSV、XLSX；截图在本机识别，金额由你确认。原始文件留在本地账本中。").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
            }.listRowBackground(YubaiColor.card).listRowSeparatorTint(YubaiColor.separator)
            Section("导出账单的方法") {
                Text("微信：我 → 服务 → 钱包 → 账单 → 常见问题 → 下载账单。\n支付宝：我的 → 账单 → 更多 → 开具交易流水证明 / 导出账单。\n银行：导出带日期、金额和收支方向的明细；不匹配时可使用余白 CSV 模板。") .yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary)
                Text("各应用入口可能随版本调整。加密压缩包请先使用账单邮件提供的密码解压。").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
            }.listRowBackground(YubaiColor.card).listRowSeparatorTint(YubaiColor.separator)
            if !store.current.imports.filter({ $0.needsOrganization == true || !($0.organization?.questions.isEmpty ?? true) }).isEmpty {
                Section("稍后继续的整理") {
                    ForEach(store.current.imports.filter { $0.needsOrganization == true || !($0.organization?.questions.isEmpty ?? true) }) { batch in
                        Button(batch.filename) { result = batch }
                    }
                }.listRowBackground(YubaiColor.card).listRowSeparatorTint(YubaiColor.separator)
            }
            if !queue.isEmpty { Section { Button("继续下一份文件") { readNext() } }.listRowBackground(YubaiColor.card).listRowSeparatorTint(YubaiColor.separator) }
        }.editorForm()
    }
    func previewView(_ p: ImportPreview) -> some View {
        VStack(spacing: 0) {
            previewHeader(p)
            ScrollView {
                VStack(alignment: .leading, spacing: YubaiSpace.space12) {
                    if !p.paymentMethods.isEmpty { mappingCard(p) }
                    ForEach(p.warnings, id: \.self) { InlineNote(text: $0, style: .attention) }
                    CardRows(p.rows.filter { filter == "全部" || (filter == "将导入" && $0.included) || (filter == "需留意" && [.invalid, .conflict, .possibleDuplicate, .needsAccount].contains($0.status)) }) { row in previewRow(row) }
                }.padding(.horizontal, YubaiSpace.space18).padding(.bottom, YubaiSpace.space12)
            }
            previewActions(p)
        }
    }
    private func previewHeader(_ p: ImportPreview) -> some View {
        VStack(alignment: .leading, spacing: YubaiSpace.space12) {
            Text(p.filename).yubaiFont(YubaiFont.rowTitle).lineLimit(1)
            accountPicker
            HStack { countPill("待导入", p.selectedEntries.count, .brand); countPill("已重复", p.duplicateCount, .neutral); countPill("需留意", p.issueCount, .amber) }
            Picker("显示", selection: $filter) { Text("全部").tag("全部"); Text("将导入").tag("将导入"); Text("需留意").tag("需留意") }.pickerStyle(.segmented)
            Text("\(p.source) · 金额保持原样。保存后整理用途，不确定的地方稍后回答即可。").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
        }.padding(YubaiSpace.space18)
    }
    private func mappingCard(_ p: ImportPreview) -> some View {
        Card(style: .list) { VStack(alignment: .leading, spacing: YubaiSpace.space8) {
            SectionHeading(title: "对应实际资金账户")
            ForEach(p.paymentMethods, id: \.self) { method in
                Picker(method, selection: Binding<UUID?>(get: { accountMappings[method] }, set: { accountMappings[method] = $0 })) {
                    Text("请选择对应账户").tag(UUID?.none)
                    ForEach(store.current.accounts.filter { !$0.archived }) { Text($0.name).tag(Optional($0.id)) }
                }.frame(minHeight: YubaiSize.buttonHeight).accessibilityIdentifier("mapping_" + method)
                Rectangle().fill(YubaiColor.separator).frame(height: 1).accessibilityHidden(true)
            }
            if let accountID { Button("全部对应到“\(store.current.accountName(accountID))”") { accountMappings = Dictionary(uniqueKeysWithValues: p.paymentMethods.map { ($0, accountID) }) }.frame(minHeight: YubaiSize.tapMin) }
            Button("添加缺少的账户") { showAccount = true }.frame(minHeight: YubaiSize.tapMin)
        } }
    }
    private func previewRow(_ row: ImportRow) -> some View {
        HStack(alignment: .top, spacing: YubaiSpace.space10) {
            if row.entry != nil && [.ready, .possibleDuplicate].contains(row.status) {
                Button { toggle(row.id) } label: { Image(systemName: row.included ? "checkmark.circle.fill" : "circle").yubaiFont(YubaiFont.cardTitle).foregroundStyle(YubaiColor.brand).frame(width: YubaiSize.tapMin, height: YubaiSize.tapMin) }.buttonStyle(PressButtonStyle()).accessibilityLabel(row.included ? "不导入这一行" : "导入这一行")
            } else { Image(systemName: row.status == .duplicate ? "arrow.triangle.2.circlepath" : "exclamationmark.circle").foregroundStyle(YubaiColor.labelSecondary).frame(width: YubaiSize.barMax) }
            VStack(alignment: .leading, spacing: YubaiSpace.space4) {
                let layout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: YubaiSpace.space6)) : AnyLayout(HStackLayout(spacing: YubaiSpace.space10))
                layout {
                    Text(row.entry?.title ?? "第 \(row.line) 行").yubaiFont(YubaiFont.rowTitle).lineLimit(textSize.isAccessibilitySize ? nil : 2)
                    if !textSize.isAccessibilitySize { Spacer() }
                    if let e = row.entry { AmountLabel(cents: e.amount, sign: e.nature.inflow ? .inflow : .outflow) }
                }
                if let e = row.entry, row.status != .needsAccount { Text("\(Dates.text(e.date)) · \(store.current.accountName(e.accountID))").yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary) }
                Text("第 \(row.line) 行 · " + row.message).yubaiFont(YubaiFont.caption).foregroundStyle([.invalid, .conflict, .needsAccount].contains(row.status) ? YubaiColor.amberInk : YubaiColor.labelSecondary)
            }
        }.padding(.vertical, YubaiSpace.space4)
    }
    private func previewActions(_ p: ImportPreview) -> some View {
        let layout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: YubaiSpace.space10)) : AnyLayout(HStackLayout(spacing: YubaiSpace.space10))
        return layout {
            Button("重新选文件") { preview = nil; data = nil; filePicker = true }.frame(minHeight: YubaiSize.tapMin)
            if !textSize.isAccessibilitySize { Spacer() }
            Button("保存 \(p.selectedEntries.count) 笔", action: commit).buttonStyle(PrimaryButtonStyle()).disabled(p.selectedEntries.isEmpty).accessibilityIdentifier("commitImport")
        }.padding(YubaiSpace.space18).background(YubaiColor.raised)
    }
    func countPill(_ label: String, _ count: Int, _ variant: Pill.Variant) -> some View {
        VStack(alignment: .leading, spacing: YubaiSpace.space6) {
            Text("\(count)").yubaiFont(YubaiFont.amountLarge).foregroundStyle(YubaiColor.label)
            Pill(text: label, variant: variant, showsDot: false)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    @ViewBuilder func resultView(_ savedBatch: ImportBatch) -> some View {
        if let batch = store.current.imports.first(where: { $0.id == savedBatch.id }) {
            Page {
                if store.organizingBatchID == batch.id { ProgressView("正在整理…").padding(YubaiSpace.space18) }
                EmptyState("checkmark.seal", batch.needsOrganization == true ? "账单已保存" : "这一份，整理好了",
                           "已保存 \(batch.importedCount) 笔，跳过 \(batch.duplicateCount) 笔重复，另有 \(batch.skippedCount) 行未导入。")
                if let organization = batch.organization {
                    Card { VStack(alignment: .leading, spacing: YubaiSpace.space12) {
                        Text("分类 \(organization.categoryCount) · 配对 \(organization.pairCount) · 周期 \(organization.recurringCount) · 重复 \(organization.duplicateCount)").yubaiFont(YubaiFont.rowTitle)
                        DisclosureGroup("查看整理明细") {
                            ForEach(Array(organization.changeSet.preview(in: store.current).enumerated()), id: \.offset) { _, line in
                                Text(line).yubaiFont(YubaiFont.caption).frame(maxWidth: .infinity, alignment: .leading)
                            }
                            ForEach(Array(organization.skipped.enumerated()), id: \.offset) { _, line in
                                Text(line).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                            }
                        }
                    } }
                    ForEach(organization.questions) { question in questionCard(question, batchID: batch.id) }
                }
                if batch.needsOrganization == true {
                    Card { VStack(alignment: .leading, spacing: YubaiSpace.space12) {
                        Text(store.organizationErrors[batch.id] ?? "记录已按账单保存。云端智能可用时，会继续整理这一批。").yubaiFont(YubaiFont.callout)
                        Button("现在整理") { Task { await store.organizeImport(batch.id) } }
                            .buttonStyle(SecondaryButtonStyle()).disabled(store.organizingBatchID != nil || IntelligenceRuntime.backend(for: store.current) == nil)
                    } }
                }
                Text("原始文件保留在本地。未回答的问题会留着，待明确的资金继续保守计算。").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                Button("整批撤销", role: .destructive) { store.undoImport(batch.id) }.disabled(store.organizingBatchID == batch.id)
                if !queue.isEmpty { Button("继续下一份（\(processed)/\(queueTotal)）") { result = nil; preview = nil; receipt = nil; readNext() }.buttonStyle(PrimaryButtonStyle()).disabled(store.organizingBatchID != nil) }
                Button("回到账本") { store.destination = .ledger; store.sheet = nil }.buttonStyle(PrimaryButtonStyle())
            }
        } else {
            Page { EmptyState("arrow.uturn.backward", "这一批已撤销", "整理产生的关联与安排也已还原。")
                Button("继续导入") { result = nil; preview = nil; receipt = nil; data = nil }
            }
        }
    }
    private func questionCard(_ question: ImportQuestion, batchID: UUID) -> some View {
        let covered = Set(question.entryIDs)
        return Card { VStack(alignment: .leading, spacing: YubaiSpace.space12) {
            Text(question.text).yubaiFont(YubaiFont.cardTitle)
            Pill(text: "\(question.entryIDs.count) 笔 · 可以稍后回答", variant: .neutral, showsDot: false)
            DisclosureGroup("看看这几笔") {
                LazyVStack { ForEach(store.sortedEntries.filter { covered.contains($0.id) }) { EntryRow(entry: $0) } }
            }
            ForEach(question.options.indices, id: \.self) { index in
                Button(question.options[index].title) { store.answerImportQuestion(question, batchID: batchID, option: index) }
                    .buttonStyle(SecondaryButtonStyle())
            }
            Button("都不是") { freeTextQuestion = question.id }.buttonStyle(SecondaryButtonStyle())
            if freeTextQuestion == question.id {
                TextField("用自己的话补充用途", text: Binding(get: { questionText[question.id] ?? "" }, set: { questionText[question.id] = $0 }))
                Button("记下用途") { store.describeImportQuestion(question, batchID: batchID, text: questionText[question.id] ?? "") }
                    .disabled((questionText[question.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Text("先记下你的说明，资金性质仍待明确。可在账本中继续补充。").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
            }
        } }
    }
    func receiptView(_ candidate: ReceiptCandidate) -> some View {
        Form {
            Section { Label("识别完成，请确认金额", systemImage: "text.viewfinder").yubaiFont(YubaiFont.rowTitle); Text("截图识别可能出错。确认后才会记入账本，余白不会自动修正金额。").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary) }.listRowBackground(YubaiColor.card).listRowSeparatorTint(YubaiColor.separator)
            Section { TextField("用途", text: $receiptTitle); TextField("确认金额", text: $receiptAmount).numericInput().yubaiFont(YubaiFont.amountInput); if candidate.amounts.count > 1 { Picker("截图中的金额", selection: $receiptAmount) { Text("手动填写").tag(receiptAmount); ForEach(candidate.amounts, id: \.self) { Text("¥" + $0).tag($0) } } }; Toggle("这是一笔收入", isOn: $receiptInflow).tint(YubaiColor.toggleOn); accountPicker; DatePicker("发生时间", selection: $receiptDate, in: ...Date(), displayedComponents: [.date, .hourAndMinute]) }.listRowBackground(YubaiColor.card).listRowSeparatorTint(YubaiColor.separator)
            Section { DisclosureGroup("查看识别到的原文") { Text(candidate.text).yubaiFont(YubaiFont.caption).textSelection(.enabled) } }.listRowBackground(YubaiColor.card).listRowSeparatorTint(YubaiColor.separator)
            Section { Button("确认并保存", action: saveReceipt); Button("放弃这张截图") { receipt = nil; data = nil; photo = nil } }.listRowBackground(YubaiColor.card).listRowSeparatorTint(YubaiColor.separator)
        }.editorForm()
    }
    func toggle(_ id: UUID) { guard let i = preview?.rows.firstIndex(where: { $0.id == id }) else { return }; preview?.rows[i].included.toggle() }
    func readNext() {
        guard !queue.isEmpty else { return }
        let url = queue.removeFirst(); processed += 1; result = nil; preview = nil; receipt = nil; localError = nil; accountMappings = [:]
        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let attributes = try url.resourceValues(forKeys: [.fileSizeKey]); guard (attributes.fileSize ?? 0) <= 50 * 1024 * 1024 else { throw YubaiError.invalid("单个文件请小于 50 MB。") }
            let bytes = try Data(contentsOf: url); data = bytes; filename = url.lastPathComponent
            if UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true { busy = true; Task { await recognize(bytes) } }
            else { parse(bytes) }
        } catch { localError = error.localizedDescription }
    }
    func parse(_ bytes: Data) {
        guard let accountID else { localError = "请先选择实际收付款账户。"; return }
        let ledger = store.current; let name = filename; let mappings = accountMappings; let requestID = UUID(); parseID = requestID; busy = true; localError = nil
        let columnMapping = preview?.columnMapping; let mappedHeader = preview?.mappedHeader ?? 0
        parsingTask?.cancel()
        parsingTask = Task { do {
            let client = ledger.preferences.cloudAIEnabled ? DeepSeekClient.configured(redactor: Redactor(ledger: ledger)) : nil
            let parsed = try await Task.detached(priority: .userInitiated) {
                if let columnMapping {
                    return try BillImporter.preview(data: bytes, filename: name, accountID: accountID, ledger: ledger,
                        accountMappings: mappings, requireAccountMapping: true, mapping: columnMapping, mappedHeader: mappedHeader)
                }
                if let client {
                    return try await BillImporter.preview(data: bytes, filename: name, accountID: accountID, ledger: ledger,
                        accountMappings: mappings, requireAccountMapping: true, columnMapper: AIImportColumnMapper(transport: client))
                }
                return try BillImporter.preview(data: bytes, filename: name, accountID: accountID, ledger: ledger, accountMappings: mappings, requireAccountMapping: true)
            }.value
            guard parseID == requestID, !Task.isCancelled else { return }; preview = parsed; busy = false
        } catch { guard parseID == requestID, !Task.isCancelled else { return }; localError = error.localizedDescription; preview = nil; busy = false } }
    }
    func recognize(_ bytes: Data) async {
        do { let recognized = try await Task.detached(priority: .userInitiated) { try ReceiptReader.recognize(bytes) }.value; receipt = recognized; receiptAmount = recognized.amounts.count == 1 ? recognized.amounts[0] : ""; receiptTitle = recognized.title; receiptDate = min(recognized.date ?? Date(), Date()); busy = false }
        catch { localError = error.localizedDescription; busy = false }
    }
    func commit() {
        guard let preview, let data else { return }; var batch: ImportBatch?
        if store.update("导入账单", { l in batch = try BillImporter.commit(preview, data: data, to: &l) }) { result = batch; if let batch { Task { await store.organizeImport(batch.id) } } }
    }
    func saveReceipt() {
        do {
            guard let accountID, let data, receipt != nil else { throw YubaiError.invalid("请先选择账户。") }
            let amount = try Money.parse(receiptAmount); guard amount > 0, !receiptTitle.isEmpty else { throw YubaiError.invalid("请确认用途和有效金额。") }
            var e = Entry(date: receiptDate, amount: amount, nature: receiptInflow ? .income : .expense, accountID: accountID, title: receiptTitle, category: "待整理"); e.source = "截图"; e.note = "本机 OCR，金额经手动确认"; e.classificationReason = "截图金额经用户确认，等待整理"
            if store.current.activeEntries.contains(where: { $0.accountID == accountID && $0.amount == amount && $0.nature.inflow == receiptInflow && abs($0.date.timeIntervalSince(receiptDate)) < 60 }) { throw YubaiError.invalid("同账户已有同时间同金额记录，请先核对账本，避免重复补记。") }
            var batch = ImportBatch(filename: filename, importedCount: 1, duplicateCount: 0, skippedCount: 0)
            batch.needsOrganization = true; batch.undo = ImportUndo(updatedAt: store.current.updatedAt)
            if store.update("保存截图记录", { l in let attachment = Attachment(name: filename, data: data); l.attachments.append(attachment); e.attachmentID = attachment.id; e.batchID = batch.id; batch.attachmentID = attachment.id; l.entries.append(e); l.imports.append(batch) }) { result = batch; Task { await store.organizeImport(batch.id) } }
        } catch { localError = error.localizedDescription }
    }
}
