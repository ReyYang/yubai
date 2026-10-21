import SwiftUI
import PhotosUI
import ImageIO
import UniformTypeIdentifiers
import YubaiCore

private struct AskImage { let data: Data; let name: String }

private struct AskMessage: Identifiable {
    let id = UUID()
    let text: String
    var reply: AssistantReply? = nil
    var isUser = false
    var image: AskImage? = nil
    var protectedEdit = false
    var protectedRecords: [UUID] = []
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
                            Text("问点什么").yubaiFont(YubaiFont.lead).padding(.top, YubaiSpace.space20)
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
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        return VStack(alignment: .leading, spacing: YubaiSpace.space12) {
            if enabled && messages.isEmpty && !busy && !reading {
                VStack(alignment: .leading, spacing: YubaiSpace.space8) {
                    ForEach(["这周外卖花了多少？", "11月1日的房租够吗？", "想买一双 899 的鞋，合理吗？"], id: \.self) { question in
                        Button { input = question; send() } label: {
                            Text(question).yubaiFont(YubaiFont.callout).padding(.horizontal, 14).padding(.vertical, 10)
                                .overlay { Capsule().strokeBorder(YubaiColor.grabber, lineWidth: 1) }
                        }.buttonStyle(PressButtonStyle())
                    }
                }.padding(.bottom, YubaiSpace.space8)
            }
            if voice.recording { Text("正在听，停下后可以修改再发送。").yubaiFont(YubaiFont.caption) }
            HStack(alignment: .bottom, spacing: YubaiSpace.space8) {
                Menu {
                    Button("从照片选择截图") { photoPicker = true }
                    Button("选择图片文件") { filePicker = true }
                } label: {
                    Image(systemName: "plus").frame(width: YubaiSize.iconButton, height: YubaiSize.iconButton)
                }.accessibilityLabel("添加截图或照片")
                TextField(enabled ? (messages.isEmpty ? "问点什么…" : "接着问…") : "暂时还不能问", text: $input, axis: .vertical)
                    .lineLimit(1...5).yubaiFont(YubaiFont.navTitle, weight: .regular)
                    .padding(.vertical, 10).frame(minHeight: YubaiSize.iconButton)
                    .accessibilityIdentifier("askInput").accessibilityLabel(enabled ? "问余白" : "问余白（暂不可用）")
                if voice.recording || (trimmed.isEmpty && voice.available) {
                    Button {
                        if voice.recording { voice.stop() }
                        else { voicePrefix = input.isEmpty ? "" : input + " "; voiceTask = Task { await voice.start() } }
                    } label: {
                        Image(systemName: voice.recording ? "stop.fill" : "mic")
                            .frame(width: YubaiSize.iconButton, height: YubaiSize.iconButton)
                            .foregroundStyle(YubaiColor.label).background(YubaiColor.card, in: Circle())
                    }.accessibilityLabel(voice.recording ? "停止听写" : "语音输入")
                } else {
                    Button { send() } label: {
                        Image(systemName: "arrow.up").fontWeight(.semibold)
                            .frame(width: YubaiSize.iconButton, height: YubaiSize.iconButton)
                            .foregroundStyle(Color.white).background(YubaiColor.brand, in: Circle())
                    }.accessibilityLabel("发送").accessibilityIdentifier("sendAsk").disabled(trimmed.isEmpty)
                }
            }.disabled(!enabled || busy || reading).padding(6).frame(minHeight: 52)
                .buttonStyle(PressButtonStyle()).floatingSurface(in: Capsule(), shadow: YubaiShadow.input)
                .opacity(enabled ? 1 : 0.6)
        }.padding(.horizontal, 18).padding(.bottom, 18)
    }
    @ViewBuilder private func messageView(_ message: AskMessage) -> some View {
        if message.isUser {
            HStack { Spacer(minLength: YubaiSpace.space24); Text(message.text).yubaiFont(YubaiFont.body).padding(YubaiSpace.space16).foregroundStyle(YubaiColor.onBrand).background(YubaiColor.brand, in: UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 18, bottomTrailingRadius: 6, topTrailingRadius: 18)) }
        } else if let reply = message.reply {
            if reply.purchaseJudgment == nil { AssistantCard { VStack(alignment: .leading, spacing: 6) {
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
                if case .addEntry(let draft)? = change.items.first { AskEntryDraftCard(change: change, draft: draft, image: message.image) }
                else { AskChangeCard(change: change) }
            }
            if let purchase = reply.purchaseJudgment { AskPurchaseCard(purchase: purchase, evidence: reply.evidenceEntryIDs, snapshot: reply.unverifiedAmounts.isEmpty ? reply.text : "这次回答有金额尚未核实，请重新查阅。", notes: reply.rememberedNotes + reply.updatedNotes.map(\.note)) }
        }
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

private struct AskEntryDraftCard: View {
    @Environment(AppStore.self) private var store
    let change: ChangeSet
    @State var draft: EntryDraft
    let image: AskImage?
    @State private var saved = false
    @State private var cancelled = false
    var body: some View {
        if saved { Text("已记下这笔，可撤销上一项修改。").yubaiFont(YubaiFont.callout) }
        else if cancelled { Text("这次不记了。").yubaiFont(YubaiFont.callout) }
        else {
            Card { VStack(alignment: .leading, spacing: 12) {
                Text("准备记下这一笔").yubaiFont(YubaiFont.cardTitle)
                TextField("用途", text: $draft.title)
                AmountLabel(cents: draft.amount, hide: store.current.preferences.hideAmounts)
                DatePicker("日期", selection: $draft.date, displayedComponents: .date)
                Picker("账户", selection: $draft.accountID) { ForEach(store.current.accounts.filter { !$0.archived }) { Text($0.name).tag($0.id) } }
                Picker("分类", selection: $draft.category) { ForEach(Array(Set(store.current.categories.map(\.name) + [draft.category])).sorted(), id: \.self) { Text($0).tag($0) } }
                Toggle("我已核对金额", isOn: $draft.amountConfirmed).tint(YubaiColor.toggleOn)
                Text("请对照原文核对；金额不对时，可修改输入后再问一次。").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
            } }
            ProposalCard(title: "记下这笔", lines: store.current.preferences.hideAmounts ? ["金额已隐藏，请显示金额后核对。"] : confirmed.preview(in: store.current), primaryTitle: "记下这笔",
                         canConfirm: !store.current.preferences.hideAmounts && draft.amountConfirmed && !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, confirm: {
                saved = store.apply(confirmed, label: "问余白修改") { ledger in
                    if let image, let index = ledger.entries.firstIndex(where: { $0.id == draft.id }), ledger.entries[index].attachmentID == nil {
                        let attachment = Attachment(name: image.name, data: image.data)
                        ledger.attachments.append(attachment); ledger.entries[index].attachmentID = attachment.id
                    }
                }
            }, cancel: {
                if store.update("放下补记", { $0.pendingChanges.removeAll { $0.id == change.id } }) { cancelled = true }
            })
        }
    }
    private var confirmed: ChangeSet { var value = change; value.items = [.addEntry(draft)]; return value }
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
