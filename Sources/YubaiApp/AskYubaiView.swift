import SwiftUI
import PhotosUI
import ImageIO
import UniformTypeIdentifiers
import YubaiCore

private struct AskImage { let data: Data; let name: String }

private struct AskTableExcerpt {
    let preamble: String
    let text: String
    let rowCount: Int
    init?(_ text: String) {
        guard let statement = PastedStatement.detect(text) else { return nil }
        preamble = statement.preamble
        self.text = String(decoding: statement.data, as: UTF8.self).components(separatedBy: .newlines).prefix(4).map { String($0.prefix(60)) }.joined(separator: "\n")
        rowCount = statement.rowCount + 1
    }
}

private struct AskMessage: Identifiable {
    let id = UUID()
    let text: String
    var reply: AssistantReply? = nil
    var isUser = false
    var image: AskImage? = nil
    var protectedEdit = false
    var protectedRecords: [UUID] = []
    let tableExcerpt: AskTableExcerpt?
    init(text: String, reply: AssistantReply? = nil, isUser: Bool = false, image: AskImage? = nil, protectedEdit: Bool = false, protectedRecords: [UUID] = []) {
        self.text = text; self.reply = reply; self.isUser = isUser; self.image = image; self.protectedEdit = protectedEdit; self.protectedRecords = protectedRecords
        tableExcerpt = isUser ? AskTableExcerpt(text) : nil
    }
}

struct AskYubaiView: View {
    @Environment(AppStore.self) private var store
    var initialText = ""
    var initialImage: Data? = nil
    @State private var input = ""
    @State private var messages: [AskMessage] = []
    @State private var session = AskYubaiSession()
    @State private var voice = AskVoiceCapture()
    @State private var voicePrefix = ""
    @State private var busy = false
    @State private var reading = false
    @State private var errorText = ""
    @State private var originalImage: AskImage?
    @State private var photo: PhotosPickerItem?
    @State private var filePicker = false
    @State private var photoPicker = false
    @State private var task: Task<Void, Never>?
    @State private var captureTask: Task<Void, Never>?
    @State private var voiceTask: Task<Void, Never>?
    @State private var appeared = false
    @State private var configured = IntelligenceRuntime.isConfigured
    private var enabled: Bool { store.current.preferences.cloudAIEnabled && configured && IntelligenceRuntime.cloud.unavailableModel == nil }
    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: YubaiSpace.space16) {
                        if let model = IntelligenceRuntime.cloud.unavailableModel {
                            InlineNote(text: "模型「\(model)」现在用不了，请到智能与隐私换一个模型名字再试。", style: .attention)
                            NavigationLink("去智能与隐私") { IntelligencePrivacyView() }.buttonStyle(SecondaryButtonStyle())
                        } else if !enabled {
                            VStack(spacing: 12) {
                                AssistantMark(size: 56).accessibilityHidden(true)
                                Text("联网并配好密钥后，\n余白才能回答").yubaiFont(YubaiFont.quote).multilineTextAlignment(.center)
                                Text("「现在」的数字照常由本机计算，不受影响。整理和提议会等到能联网时再做。")
                                    .yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelMuted).multilineTextAlignment(.center).frame(maxWidth: 280)
                                NavigationLink("去配好密钥") { IntelligencePrivacyView() }
                                    .buttonStyle(PrimaryButtonStyle()).frame(maxWidth: 240)
                            }.frame(maxWidth: .infinity).padding(.top, 100)
                        } else if messages.isEmpty {
                            Text("想问什么，或记下一笔，都可以从这里开始。").yubaiFont(YubaiFont.lead)
                            Text("例如：午饭 32 微信，或这笔购买合理吗？").yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary)
                        }
                        ForEach(messages) { message in messageView(message).messageEntrance(user: message.isUser) }
                        if busy || reading {
                            HStack { AssistantMark(thinking: true); Text(reading ? "正在读截图…" : "正在查阅…").yubaiFont(YubaiFont.callout) }
                        }
                        if !errorText.isEmpty { InlineNote(text: errorText, style: .attention) }
                        if !voice.errorText.isEmpty { InlineNote(text: voice.errorText) }
                        Color.clear.frame(height: 1).id("latest")
                    }.padding(YubaiSpace.space20).frame(maxWidth: 760).frame(maxWidth: .infinity)
                }.onChange(of: messages.count) { _, _ in proxy.scrollTo("latest", anchor: .bottom) }
            }
            inputBar
        }.amountPrivacy(store.current.preferences.hideAmounts).paperBackground().navigationTitle("问余白").yubaiNavigation().toolbar { CloseButton() }
            .photosPicker(isPresented: $photoPicker, selection: $photo, matching: .images)
            .fileImporter(isPresented: $filePicker, allowedContentTypes: [.image]) { result in
                do {
                    let url = try result.get(); let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    guard size <= 50 * 1024 * 1024 else { throw YubaiError.invalid("图片请小于 50 MB。") }
                    recognize(try Data(contentsOf: url))
                } catch { errorText = error.localizedDescription }
            }
            .onChange(of: photo) { _, value in
                guard let value else { return }
                captureTask?.cancel(); reading = true
                captureTask = Task { @MainActor in
                    do {
                        guard let bytes = try await value.loadTransferable(type: Data.self) else { throw YubaiError.invalid("图片读取失败。") }
                        try Task.checkCancellation(); await readImage(bytes)
                    } catch { if !Task.isCancelled { errorText = error.localizedDescription; reading = false } }
                }
            }
            .onChange(of: voice.transcript) { _, text in input = voicePrefix + text }
            .onAppear { IntelligenceRuntime.cloud.refresh(); configured = IntelligenceRuntime.isConfigured; if !appeared { appeared = true; input = initialText; if let initialImage { recognize(initialImage) } } }
            .onChange(of: IntelligenceRuntime.cloud.unavailableModel) { _, model in if model == nil { errorText = "" } }
            .onDisappear { cancel() }
            .onChange(of: store.current.id) { _, _ in cancel(); messages = []; input = ""; originalImage = nil; session = AskYubaiSession() }
            .onChange(of: store.current.preferences.cloudAIEnabled) { _, value in if !value { cancel() } }
            .onChange(of: store.locked) { _, value in if value { cancel(); messages = []; originalImage = nil; session = AskYubaiSession() } }
    }
    private var inputBar: some View {
        VStack(alignment: .leading, spacing: YubaiSpace.space8) {
            if voice.recording { Text("正在听，停下后可以修改再发送。").yubaiFont(YubaiFont.caption) }
            HStack(alignment: .bottom, spacing: YubaiSpace.space8) {
                if enabled { Menu {
                    Button("从照片选择截图") { photoPicker = true }
                    Button("选择图片文件") { filePicker = true }
                } label: { Image(systemName: "plus").frame(width: YubaiSize.tapMin, height: YubaiSize.tapMin) }.accessibilityLabel("添加截图或照片") }
                TextField(enabled ? "接着问…" : "暂时还不能问", text: $input, axis: .vertical).lineLimit(1...5).yubaiFont(YubaiFont.body).accessibilityIdentifier("askInput").accessibilityLabel(enabled ? "问余白" : "问余白（暂不可用）")
                if enabled && (voice.available || voice.recording) {
                    Button {
                        if voice.recording { voice.stop() }
                        else { voicePrefix = input.isEmpty ? "" : input + " "; voiceTask = Task { await voice.start() } }
                    } label: { Image(systemName: voice.recording ? "stop.circle" : "mic").frame(width: YubaiSize.tapMin, height: YubaiSize.tapMin) }.accessibilityLabel(voice.recording ? "停止听写" : "语音输入")
                }
                if enabled { Button { send() } label: { Image(systemName: "arrow.up.circle.fill").frame(width: YubaiSize.tapMin, height: YubaiSize.tapMin) }
                    .accessibilityLabel("发送").accessibilityIdentifier("sendAsk").disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || voice.recording) }
            }.disabled(!enabled || busy || reading)
        }.padding(8).buttonStyle(PressButtonStyle()).floatingSurface(in: Capsule(), shadow: YubaiShadow.input)
            .padding(.horizontal, 18).padding(.bottom, 18).opacity(enabled ? 1 : 0.6)
    }
    @ViewBuilder private func messageView(_ message: AskMessage) -> some View {
        if message.isUser {
            HStack {
                Spacer(minLength: YubaiSpace.space24)
                userBubble(message)
                    .padding(YubaiSpace.space16).foregroundStyle(YubaiColor.onBrand)
                    .background(YubaiColor.brand, in: UnevenRoundedRectangle(topLeadingRadius: YubaiRadius.row, bottomLeadingRadius: YubaiRadius.row, bottomTrailingRadius: YubaiSpace.space6, topTrailingRadius: YubaiRadius.row))
            }
        } else if let reply = message.reply {
            if let statement = reply.pastedStatement { AskPastedStatementCard(statement: statement) }
            else if reply.purchaseJudgment == nil && !isEntryDraftReply(reply) { AssistantCard { VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) { AssistantMark(size: 14).accessibilityHidden(true); Text("余白助手").yubaiFont(YubaiFont.meta) }.foregroundStyle(YubaiColor.brandInk)
                Text(store.current.preferences.hideAmounts ? "金额已隐藏。" : reply.text).yubaiFont(YubaiFont.body).textSelection(.enabled).accessibilityIdentifier("askAnswer")
                if let chart = reply.chart, !store.current.preferences.hideAmounts { AnswerChartView(chart: chart) }
                if !message.protectedEdit {
                NavigationLink("依据：\(reply.evidenceEntryIDs.count) 笔记录 ›") { AskEvidenceView(ids: reply.evidenceEntryIDs) }.yubaiFont(YubaiFont.caption).frame(minHeight: 44).accessibilityIdentifier("answerEvidence")
                }
                if !reply.unverifiedAmounts.isEmpty {
                    InlineNote(text: store.current.preferences.hideAmounts ? "回答中有金额尚未核实，请核对记录。" : "这些金额尚未核实：" + reply.unverifiedAmounts.joined(separator: "、"), style: .attention)
                }
                if message.protectedEdit {
                    if message.protectedRecords.count == 1, let id = message.protectedRecords.first {
                        NavigationLink("核对这笔 · 记录详情 ›") { EntryDetailView(entryID: id) }.frame(minHeight: 44).yubaiFont(YubaiFont.caption)
                    } else {
                        NavigationLink("核对相关记录 ›") { AskRecordLookupView(ids: message.protectedRecords) }.frame(minHeight: 44).yubaiFont(YubaiFont.caption)
                    }
                }
                RememberedRows(notes: reply.rememberedNotes + reply.updatedNotes.map(\.note))
            } } }
            ForEach(reply.proposedChangeSets) { change in
                let drafts = change.items.compactMap { item -> EntryDraft? in if case .addEntry(let draft) = item { return draft }; return nil }
                if !drafts.isEmpty && drafts.count == change.items.count { AskEntryDraftCard(change: change, drafts: drafts, image: message.image) }
                else { AskChangeCard(change: change) }
            }
            if isEntryDraftReply(reply) { RememberedRows(notes: reply.rememberedNotes + reply.updatedNotes.map(\.note)) }
            if let purchase = reply.purchaseJudgment { AskPurchaseCard(purchase: purchase, evidence: reply.evidenceEntryIDs, snapshot: reply.unverifiedAmounts.isEmpty ? reply.text : "这次回答有金额尚未核实，请重新查阅。", notes: reply.rememberedNotes + reply.updatedNotes.map(\.note)) }
        }
    }
    private func isEntryDraftReply(_ reply: AssistantReply) -> Bool {
        !reply.proposedChangeSets.isEmpty && reply.proposedChangeSets.allSatisfy { change in
            !change.items.isEmpty && change.items.allSatisfy { if case .addEntry = $0 { return true }; return false }
        } && reply.unverifiedAmounts.isEmpty
    }
    @ViewBuilder private func userBubble(_ message: AskMessage) -> some View {
        if let statement = message.tableExcerpt {
            VStack(alignment: .leading, spacing: YubaiSpace.space6) {
                Text(store.current.preferences.hideAmounts ? "账单表格" : (statement.preamble.isEmpty ? "帮我导入这些" : statement.preamble)).yubaiFont(YubaiFont.body)
                Text(store.current.preferences.hideAmounts ? "金额已隐藏" : statement.text)
                    .yubaiFont(YubaiFont.meta).lineLimit(4).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(YubaiSpace.space8).background(YubaiColor.onBrand.opacity(0.15), in: RoundedRectangle(cornerRadius: YubaiRadius.control))
                Text("共 \(statement.rowCount) 行").yubaiFont(YubaiFont.meta)
            }.accessibilityIdentifier("pastedStatementBubble")
        } else { Text(store.current.preferences.hideAmounts ? "金额已隐藏" : message.text).yubaiFont(YubaiFont.body) }
    }
    @MainActor private func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard enabled, !busy, !text.isEmpty else { return }
        let ledger = store.current; let image = originalImage
        guard let transport = store.assistantTransport(for: ledger) else { return }
        input = ""; errorText = ""; busy = true; messages.append(AskMessage(text: text, isUser: true))
        task = Task { @MainActor in
            defer { busy = false }
            do {
                let reply = try await session.ask(text, ledger: ledger, transport: transport)
                try Task.checkCancellation()
                guard store.current == ledger, !store.locked, enabled else {
                    errorText = "账本已更新，可以再问一次。"; input = text; session = AskYubaiSession(); return
                }
                let protectedEdit = AskYubai.isProtectedEdit(text)
                let previousIDs = Set(messages.compactMap(\.reply).flatMap { $0.evidenceEntryIDs + $0.proposedChangeSets.flatMap { $0.items.flatMap(\.entryIDs) } })
                let amounts = EntryAmountParser.candidates(in: text)
                let related = ledger.activeEntries.filter { previousIDs.contains($0.id) }
                let matching = related.filter { amounts.contains($0.amount) }
                let recordIDs = (matching.isEmpty ? related : matching).map(\.id)
                if !reply.rememberedNotes.isEmpty || !reply.updatedNotes.isEmpty || !reply.usedMemoryIDs.isEmpty || !reply.proposedChangeSets.isEmpty {
                    guard store.update("记下问答", recordUndo: false, { ledger in
                        try Memory.apply(reply, to: &ledger)
                        ledger.pendingChanges.append(contentsOf: reply.proposedChangeSets)
                    }) else { input = text; session = AskYubaiSession(); return }
                }
                messages.append(AskMessage(text: reply.text, reply: reply, image: image, protectedEdit: protectedEdit, protectedRecords: recordIDs))
                if reply.proposedChangeSets.contains(where: { $0.items.contains { if case .addEntry = $0 { return true }; return false } }) { originalImage = nil }
            } catch is CancellationError {
                if !Task.isCancelled { errorText = "账本或智能设置已更新，可以再试一次。"; input = text; session = AskYubaiSession() }
            }
            catch { if IntelligenceRuntime.cloud.unavailableModel == nil { errorText = error.localizedDescription }; input = text }
        }
    }
    @MainActor private func recognize(_ bytes: Data) {
        guard enabled else { return }
        captureTask?.cancel(); reading = true; errorText = ""
        captureTask = Task { @MainActor in await readImage(bytes) }
    }
    @MainActor private func readImage(_ bytes: Data) async {
        let ledgerID = store.current.id
        defer { if !Task.isCancelled { reading = false } }
        do {
            guard bytes.count <= 50 * 1024 * 1024 else { throw YubaiError.invalid("图片请小于 50 MB。") }
            let receipt = try await Task.detached(priority: .userInitiated) { try ReceiptReader.recognize(bytes) }.value
            try Task.checkCancellation()
            guard store.current.id == ledgerID, !store.locked, enabled else { return }
            let source = CGImageSourceCreateWithData(bytes as CFData, nil)
            let type = source.flatMap { CGImageSourceGetType($0) }.map { $0 as String }
            let ext = type.flatMap { UTType($0)?.preferredFilenameExtension } ?? "image"
            originalImage = AskImage(data: bytes, name: "截图-" + Dates.text(Date()) + "." + ext)
            // OCR runs on device. Only the redacted text enters the conversation.
            input = "这是截图里的文字，帮我记一笔：\n" + Redactor(ledger: store.current).text(receipt.text)
        } catch { if !Task.isCancelled { errorText = error.localizedDescription } }
    }
    @MainActor private func cancel() { task?.cancel(); captureTask?.cancel(); voiceTask?.cancel(); voice.stop(); busy = false; reading = false }
}

struct AskEvidenceView: View {
    @Environment(AppStore.self) private var store
    let ids: [UUID]
    var body: some View {
        let rows = store.sortedEntries.filter { ids.contains($0.id) && $0.deletedAt == nil }
        Page {
            Text("回答依据生成时的记录；汇总较多时展示最近的部分记录。").yubaiFont(YubaiFont.caption)
            CardRows(rows) { entry in
                EntryLink(entry: entry, hideAmount: store.current.preferences.hideAmounts).accessibilityIdentifier("evidenceEntry_" + entry.id.uuidString)
            }
            if rows.isEmpty { Text("没有可展示的记录，或原记录已移除。") }
        }.navigationTitle("依据").yubaiNavigation()
    }
}

private struct AskRecordLookupView: View {
    @Environment(AppStore.self) private var store
    let ids: [UUID]
    @State private var search = ""
    var body: some View {
        Page {
            Text("金额、账户和日期按来源保存，请在记录详情核对原始账单。").yubaiFont(YubaiFont.callout)
            TextField("找一笔记录", text: $search).frame(minHeight: 44)
            let rows = store.sortedEntries.filter { $0.deletedAt == nil && (ids.isEmpty || ids.contains($0.id)) && (search.isEmpty || $0.displayTitle.localizedCaseInsensitiveContains(search)) }
            CardRows(rows) { entry in
                EntryLink(entry: entry, hideAmount: store.current.preferences.hideAmounts)
            }
        }.navigationTitle("核对记录").yubaiNavigation()
    }
}

private struct AskChangeCard: View {
    @Environment(AppStore.self) private var store
    let change: ChangeSet
    @State private var status: String?
    var body: some View {
        if let status { Text(status).yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.brandInk).frame(minHeight: 44) }
        else {
            let count = Set(change.items.flatMap(\.entryIDs)).count
            ProposalCard(title: store.current.preferences.hideAmounts ? "等你核对的修改" : change.reason, lines: store.current.preferences.hideAmounts ? ["金额已隐藏，请显示金额后核对完整提案。"] : change.preview(in: store.current, showPreviousValues: true),
                         primaryTitle: count > 0 ? "改好这 \(count) 笔" : "记下这些修改", canConfirm: !store.current.preferences.hideAmounts, confirm: {
                if store.apply(change, label: "问余白修改") {
                    status = "已改好，可撤销上一项修改。" + (store.toast?.contains("；") == true ? (store.toast ?? "") : "")
                }
            }, cancel: {
                if store.update("放下提案", { $0.pendingChanges.removeAll { $0.id == change.id } }) { status = "这次不改了。" }
            })
        }
    }
}

private struct AskPastedStatementCard: View {
    @Environment(AppStore.self) private var store
    let statement: PastedStatement
    @State private var cancelled = false
    @State private var reviewing = false
    private var count: Int { statement.summary?.entryCount ?? statement.rowCount }
    var body: some View {
        if cancelled { Text("这次不导入了。").yubaiFont(YubaiFont.callout) }
        else {
            Card(style: .compact) {
                VStack(alignment: .leading, spacing: YubaiSpace.space10) {
                    HStack(spacing: YubaiSpace.space6) { AssistantMark(size: 14); Text("余白助手").yubaiFont(YubaiFont.meta) }.foregroundStyle(YubaiColor.brandInk)
                    if let summary = statement.summary {
                        Text("这是一份\(ImportStatementText.source(summary.source))导出，\(count) 笔").yubaiFont(YubaiFont.cardTitle)
                        Text(ImportStatementText.range(start: summary.startDate, end: summary.endDate) + " · 在本机读完，没有发给云端")
                            .yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                        ViewThatFits(in: .horizontal) {
                            HStack { total("支出", count: summary.expenseCount, amount: summary.expenseTotal); Spacer(); total("收入", count: summary.incomeCount, amount: summary.incomeTotal) }
                            VStack(alignment: .leading, spacing: YubaiSpace.space6) { total("支出", count: summary.expenseCount, amount: summary.expenseTotal); total("收入", count: summary.incomeCount, amount: summary.incomeTotal) }
                        }
                    } else {
                        Text("这是一份账单表格，\(count) 笔").yubaiFont(YubaiFont.cardTitle)
                        Text("在本机读完，没有发给云端").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                        Text(statement.needsColumnMapping ? "表头还没认出，核对时只发出表头和 5 行脱敏样例" : (statement.previewError ?? "日期待核对"))
                            .yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.amberInk)
                    }
                    HStack(spacing: YubaiSpace.space8) {
                        Button("不导入") { cancelled = true }.buttonStyle(SecondaryButtonStyle(background: YubaiColor.raised, compact: true)).accessibilityIdentifier("cancelPastedImport")
                        Button("核对 \(count) 笔") { reviewing = true }.buttonStyle(PrimaryButtonStyle(compact: true)).accessibilityIdentifier("reviewPastedStatement")
                    }
                }
            }.accessibilityIdentifier("pastedStatementCard")
                .sheet(isPresented: $reviewing) { NavigationStack { ImportView(pasted: statement) }.environment(store).appErrors() }
        }
    }
    private func total(_ title: String, count: Int, amount: Int64) -> some View {
        HStack(spacing: YubaiSpace.space6) {
            Text("\(title) \(count) 笔").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelMuted)
            AmountLabel(cents: amount, hide: store.current.preferences.hideAmounts, role: .small, sign: .none, fractionDigits: 2)
        }
    }
}

private struct AskDraftEdit: Identifiable { let draft: EntryDraft; var id: UUID { draft.id } }
private struct AskEntryDraftCard: View {
    @Environment(AppStore.self) private var store
    let change: ChangeSet
    @State private var drafts: [EntryDraft]
    let image: AskImage?
    @State private var selected: Set<UUID>
    @State private var amountsConfirmed = false
    @State private var editing: AskDraftEdit?
    @State private var savedCount = 0
    @State private var cancelled = false
    init(change: ChangeSet, drafts: [EntryDraft], image: AskImage?) {
        self.change = change; self.image = image
        _drafts = State(initialValue: drafts); _selected = State(initialValue: Set(drafts.map(\.id)))
    }
    private var chosen: [EntryDraft] { drafts.filter { selected.contains($0.id) } }
    private var sum: Int64? {
        var total: Int64 = 0
        for draft in chosen { let next = total.addingReportingOverflow(draft.amount); guard !next.overflow else { return nil }; total = next.partialValue }
        return total
    }
    private var summary: String {
        let dates = drafts.map(\.date)
        let today = dates.allSatisfy { Dates.calendar.isDateInToday($0) }
        let accounts = Set(drafts.map(\.accountID))
        return (today ? "今天" : ImportStatementText.range(dates)) + " · " + (accounts.count == 1 ? store.current.accountName(drafts[0].accountID) : "多个账户")
    }
    var body: some View {
        if savedCount > 0 { Text("已记下 \(savedCount) 笔，可撤销上一项修改。").yubaiFont(YubaiFont.callout).accessibilityIdentifier("draftEntriesSaved") }
        else if cancelled { Text("这次不记了。").yubaiFont(YubaiFont.callout) }
        else {
            Card(style: .compact) {
                VStack(alignment: .leading, spacing: YubaiSpace.space10) {
                    HStack(spacing: YubaiSpace.space6) { AssistantMark(size: 14); Text("余白助手").yubaiFont(YubaiFont.meta) }.foregroundStyle(YubaiColor.brandInk)
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline) { Text("准备记下 \(chosen.count) 笔").yubaiFont(YubaiFont.cardTitle); Spacer(); Text(summary).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary) }
                        VStack(alignment: .leading, spacing: YubaiSpace.space4) { Text("准备记下 \(chosen.count) 笔").yubaiFont(YubaiFont.cardTitle); Text(summary).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary) }
                    }
                    Card(style: .list, background: YubaiColor.raised) {
                        VStack(spacing: 0) {
                            ForEach(drafts, id: \.id) { draft in
                                draftRow(draft)
                                if draft.id != drafts.last?.id { Divider().overlay(YubaiColor.separator) }
                            }
                        }
                    }
                    Text("点一笔可以改").yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary)
                    HStack {
                        Text("合计").yubaiFont(YubaiFont.row)
                        Spacer()
                        if let sum { AmountLabel(cents: sum, hide: store.current.preferences.hideAmounts, role: .small, sign: .none, fractionDigits: 2) }
                        else { Text("金额超出范围").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.amberInk) }
                    }
                    Toggle("金额和原文对得上", isOn: $amountsConfirmed).tint(YubaiColor.toggleOn).yubaiFont(YubaiFont.row).accessibilityIdentifier("confirmDraftAmounts")
                    HStack(spacing: YubaiSpace.space8) {
                        Button("不记了", action: cancelDraft).buttonStyle(SecondaryButtonStyle(background: YubaiColor.raised, compact: true)).accessibilityIdentifier("cancelDraftEntries")
                        Button("记下 \(chosen.count) 笔", action: save).buttonStyle(PrimaryButtonStyle(compact: true))
                            .disabled(!amountsConfirmed || chosen.isEmpty || sum == nil || store.current.preferences.hideAmounts || chosen.contains { $0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
                            .accessibilityIdentifier("saveDraftEntries")
                    }
                }
            }.accessibilityIdentifier("multiEntryDraftCard")
                .sheet(item: $editing) { selection in
                    NavigationStack { AskDraftEditor(draft: selection.draft) { edited in
                        if let index = drafts.firstIndex(where: { $0.id == edited.id }) { drafts[index] = edited; amountsConfirmed = false }
                    } }.environment(store)
                }
        }
    }
    private func draftRow(_ draft: EntryDraft) -> some View {
        HStack(spacing: YubaiSpace.space6) {
            Button {
                if selected.contains(draft.id) { selected.remove(draft.id) } else { selected.insert(draft.id) }
                amountsConfirmed = false
            } label: { Image(systemName: selected.contains(draft.id) ? "checkmark.circle.fill" : "circle").foregroundStyle(selected.contains(draft.id) ? YubaiColor.brand : YubaiColor.labelSecondary).frame(width: YubaiSize.tapMin, height: YubaiSize.tapMin) }
                .buttonStyle(PressButtonStyle()).accessibilityLabel((selected.contains(draft.id) ? "不记" : "记下") + draft.title).accessibilityIdentifier("selectDraft_" + draft.id.uuidString)
            Button { editing = AskDraftEdit(draft: draft) } label: {
                HStack(spacing: YubaiSpace.space10) {
                    VStack(alignment: .leading, spacing: YubaiSpace.space2) {
                        Text(draft.purpose ?? draft.title).yubaiFont(YubaiFont.row)
                        Text(draft.category).yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    AmountLabel(cents: draft.amount, hide: store.current.preferences.hideAmounts, sign: draft.nature.inflow ? .inflow : .none)
                }.frame(minHeight: YubaiSize.tapMin)
            }.buttonStyle(PressButtonStyle()).accessibilityIdentifier("editDraft_" + draft.id.uuidString)
        }
    }
    private func save() {
        guard amountsConfirmed, !chosen.isEmpty, sum != nil, !store.current.preferences.hideAmounts else { return }
        let chosen = self.chosen
        var confirmed = change
        confirmed.items = chosen.map { draft in var value = draft; value.amountConfirmed = true; return .addEntry(value) }
        if store.apply(confirmed, label: "问余白修改", finishing: { ledger in
            if let image {
                let attachment = Attachment(name: image.name, data: image.data)
                let ids = Set(chosen.map(\.id))
                ledger.attachments.append(attachment)
                for index in ledger.entries.indices where ids.contains(ledger.entries[index].id) && ledger.entries[index].attachmentID == nil { ledger.entries[index].attachmentID = attachment.id }
            }
        }) { savedCount = chosen.count }
    }
    private func cancelDraft() {
        if store.update("放下补记", { $0.pendingChanges.removeAll { $0.id == change.id } }) { cancelled = true }
    }
}

private struct AskDraftEditor: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var draft: EntryDraft
    let save: (EntryDraft) -> Void
    var body: some View {
        Form {
            Section {
                TextField("用途", text: Binding(get: { draft.purpose ?? draft.title }, set: { draft.title = $0; if draft.purpose != nil { draft.purpose = $0 } })).accessibilityIdentifier("draftPurpose")
                AmountLabel(cents: draft.amount, hide: store.current.preferences.hideAmounts)
                DatePicker("日期", selection: $draft.date, displayedComponents: .date)
                Picker("账户", selection: $draft.accountID) { ForEach(store.current.accounts.filter { !$0.archived }) { Text($0.name).tag($0.id) } }
                Picker("分类", selection: $draft.category) { ForEach(Set(store.current.categories.map(\.name) + [draft.category]).sorted(), id: \.self) { Text($0).tag($0) } }
            }.listRowBackground(YubaiColor.card)
        }.editorForm().navigationTitle("编辑这一笔").yubaiNavigation().toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("改好了") { save(draft); dismiss() }.disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityIdentifier("saveDraftEdit") }
        }
    }
}

private struct AskPurchaseCard: View {
    @Environment(AppStore.self) private var store
    let purchase: PurchaseJudgment
    let evidence: [UUID]
    let snapshot: String
    let notes: [MemoryNote]
    @State private var wishID: UUID?
    @State private var linking = false
    private func save() -> UUID? {
        if let wishID { return wishID }
        let wish = WishItem(title: purchase.title, amount: purchase.amount, purpose: purchase.category ?? "", judgment: String(snapshot.prefix(1000)))
        guard store.update("加入心愿单", { $0.wishlist.append(wish) }) else { return nil }
        wishID = wish.id; return wish.id
    }
    var body: some View {
        AssistantCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) { AssistantMark(size: 14).accessibilityHidden(true); Text("余白助手").yubaiFont(YubaiFont.meta) }.foregroundStyle(YubaiColor.brandInk)
                HStack { Text(purchase.title).yubaiFont(YubaiFont.rowTitle); Spacer(); AmountLabel(cents: purchase.amount, hide: store.current.preferences.hideAmounts) }
                judgmentRow("付得起吗", affordability)
                Divider().overlay(YubaiColor.separator)
                judgmentRow("和你平时比", habit)
                if purchase.hasProfile, let values = purchase.facts["values"] {
                    Divider().overlay(YubaiColor.separator)
                    judgmentRow("和你在乎的比", quotes(values))
                } else { Text("还不知道你在乎什么，可以在『我的消费观』里补上。").yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary) }
                NavigationLink("依据：\(evidence.count) 笔记录 ›") { AskEvidenceView(ids: evidence) }
                    .yubaiFont(YubaiFont.caption).frame(minHeight: 44).accessibilityIdentifier("answerEvidence")
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { actions }
                    VStack(spacing: 8) { actions }
                }
                if linking, let wishID { NavigationLink("选择对应的支出记录") { WishEntryPicker(wishID: wishID) }.frame(minHeight: 44) }
                RememberedRows(notes: notes)
            }
        }
    }
    private func judgmentRow(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary)
            Text(store.current.preferences.hideAmounts ? "金额已隐藏。" : text).yubaiFont(YubaiFont.body)
        }.padding(.vertical, 8)
    }
    private var affordability: String {
        let facts = purchase.facts["affordability"]
        let after = facts?["available_after_purchase"]?["text"]?.stringValue
        let warnings = facts?["warnings"]?.arrayValue?.compactMap(\.stringValue) ?? []
        return (after.map { "买后保守余量 " + $0 + "。底线与预留已扣除，未到账收入不算进来。" } ?? "还缺少计算依据。") + warnings.joined(separator: " ")
    }
    private var habit: String {
        guard let average = purchase.facts["habit"]?["average"]?["text"]?.stringValue else { return "近 90 天还没有足够的同类消费记录。" }
        return "过去 90 天，同类消费平均一次 " + average + "。"
    }
    private func quotes(_ values: JSONValue) -> String {
        func quote(_ text: String, date: JSONValue?) -> String {
            let at = date?.stringValue.flatMap(Dates.parse)
            let prefix = at.map { "你 " + String(Dates.calendar.component(.month, from: $0)) + " 月写过" } ?? "你写过（时间未记录）"
            let old = at.map { Dates.addDays(180, to: $0) < Date() } ?? false
            return prefix + "「" + text + "」" + (old ? "，这可能已经变了" : "")
        }
        var lines = (values["principles"]?.arrayValue ?? []).compactMap { row -> String? in
            guard let text = row["text"]?.stringValue ?? row.stringValue else { return nil }
            return quote(text, date: row["confirmed_at"])
        }
        for (key, label) in [("generous", "愿意多花"), ("restrain", "想克制")] {
            for area in values[key]?.arrayValue ?? [] {
                if let title = area["title"]?.stringValue {
                    let text = area["quote"]?.stringValue.flatMap { $0.isEmpty ? nil : $0 } ?? title
                    lines.append(label + "：" + quote(text, date: area["confirmed_at"]))
                }
            }
        }
        return lines.isEmpty ? "这件还没有对应到你写下的消费观。" : lines.joined(separator: "。")
    }
    private var actions: some View {
        Group {
            Button(wishID == nil ? "放进心愿单" : "已放进心愿单") { _ = save() }.buttonStyle(PrimaryButtonStyle(compact: true)).disabled(wishID != nil)
            Button("已经买了") { if save() != nil { linking = true } }.buttonStyle(SecondaryButtonStyle(background: YubaiColor.raised, compact: true))
        }
    }
}
