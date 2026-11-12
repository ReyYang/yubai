import SwiftUI
import Observation
import PhotosUI
import ImageIO
import UniformTypeIdentifiers
import YubaiCore

struct AskImage { let data: Data; let name: String }

struct AskTableExcerpt {
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

struct AskMessage: Identifiable {
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

@MainActor @Observable final class AskConversationState {
    var day = Dates.day(Date())
    var messages: [AskMessage] = []
    var session = AskYubaiSession()
    func expire() {
        if day != Dates.day(Date()) { clear() }
    }
    func clear() { day = Dates.day(Date()); messages = []; session = AskYubaiSession() }
}

struct AskYubaiView: View {
    @Environment(AppStore.self) private var store
    var initialText = ""
    var initialImage: Data? = nil
    var autoSend = false
    @Environment(\.yubaiSheetSurface) private var inSheet
    @State private var pendingAutoSend = false
    @State private var input = ""
    @State private var messages: [AskMessage] = []
    @State private var session = AskYubaiSession()
    @State private var voice = AskVoiceCapture()
    @State private var connectivity = AskConnectivity()
    @Environment(\.scenePhase) private var scenePhase
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
    @State private var conversationDay = Dates.day(Date())
    @State private var conversationLedgerID: UUID?
    @State private var configured = IntelligenceRuntime.isConfigured
    @FocusState private var inputFocused: Bool
    private var enabled: Bool { store.preferences.isAIEnabled(for: .answers) && configured && IntelligenceRuntime.cloud.unavailableModel == nil && connectivity.connected }
    private var canRecognizeReceipt: Bool { enabled && store.preferences.isAIEnabled(for: .receiptRecognition) }
    private var headerTitle: String {
        let replies = messages.compactMap(\.reply)
        if replies.contains(where: { $0.purchaseJudgment != nil || !($0.purchaseQuestions ?? []).isEmpty }) { return "该不该买" }
        if replies.contains(where: { reply in
            !reply.proposedChangeSets.isEmpty && reply.proposedChangeSets.allSatisfy { change in
                change.items.allSatisfy { if case .addEntry = $0 { return true }; return false }
            }
        }) { return "帮我记" }
        if replies.contains(where: { $0.chart != nil }) { return "钱去哪了" }
        return "问余白"
    }
    private func clearConversation() {
        cancel(); messages = []; session = AskYubaiSession(); store.askConversation.clear()
    }
    @MainActor private func sendPendingQuestion() {
        guard pendingAutoSend, enabled, !busy, !input.isEmpty else { return }
        pendingAutoSend = false
        send()
    }
    var body: some View {
        VStack(spacing: YubaiSpace.none) {
            conversation
            inputBar
        }.amountPrivacy(store.preferences.hideAmounts).paperBackground().navigationTitle(headerTitle).yubaiNavigation().accessibilityIdentifier("askPage")
            #if DEBUG && targetEnvironment(simulator)
            .uiTestAccessibilityValue(UITestSupport.secondBatchState(in: store.current))
            #endif
            #if os(iOS)
            .toolbarBackground(.hidden, for: .navigationBar)
            #endif
            .modifier(AskPageHeader(inSheet: inSheet, showsClear: !messages.isEmpty, clear: clearConversation))
            .onChange(of: enabled) { _, _ in sendPendingQuestion() }
            .task { try? await Task.sleep(nanoseconds: 400_000_000); sendPendingQuestion() }
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
            .onAppear { connectivity.start(); voice.refreshPermissions(); IntelligenceRuntime.cloud.refresh(); configured = IntelligenceRuntime.isConfigured; if !appeared { appeared = true; store.askConversation.expire(); messages = store.askConversation.messages; session = store.askConversation.session; conversationDay = store.askConversation.day; conversationLedgerID = store.current.id; input = initialText; pendingAutoSend = autoSend && !initialText.isEmpty; if let initialImage { recognize(initialImage) } } }
            .onChange(of: IntelligenceRuntime.cloud.unavailableModel) { _, model in if model == nil { errorText = "" } }
            .onDisappear { cancel(); connectivity.stop(); if conversationDay == Dates.day(Date()) && conversationLedgerID == store.current.id { store.askConversation.messages = messages; store.askConversation.session = session } }
            .onChange(of: scenePhase) { _, phase in if phase == .active { if conversationDay != Dates.day(Date()) { cancel(); messages = []; session = AskYubaiSession(); store.askConversation.clear(); conversationDay = store.askConversation.day }; voice.refreshPermissions(); configured = IntelligenceRuntime.isConfigured } }
            .onChange(of: store.current.id) { _, _ in cancel(); messages = []; input = ""; originalImage = nil; session = AskYubaiSession() }
            .onChange(of: store.preferences.cloudAIEnabled) { _, value in if !value { cancel() } }
            .onChange(of: store.preferences.isAIEnabled(for: .answers)) { _, value in if !value { cancel() } }
            .onChange(of: store.preferences.isAIEnabled(for: .receiptRecognition)) { _, value in
                if !value { captureTask?.cancel(); reading = false; if originalImage != nil { cancel(); originalImage = nil; input = "" } }
            }
            .onChange(of: store.locked) { _, value in if value { cancel() } }
    }
    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: YubaiSpace.gapGroup) {
                    ForEach(messages) { message in
                        messageView(message, proxy: proxy).messageEntrance(user: message.isUser).id(message.id)
                    }
                    if busy || reading {
                        HStack(spacing: YubaiSpace.gapGroup) { AssistantMark(thinking: true); Text(reading ? "正在读截图…" : "正在查阅…").yubaiFont(YubaiFont.callout) }
                    }
                    if !errorText.isEmpty { InlineNote(text: errorText, style: .attention) }
                    if !voice.errorText.isEmpty && !voice.permissionDenied { InlineNote(text: voice.errorText) }
                    Color.clear.frame(height: 1).id("latest")
                }.padding(YubaiSpace.space20).frame(maxWidth: 760).frame(maxWidth: .infinity)
            }.onChange(of: messages.count) { _, _ in
                if let last = messages.last, !(last.reply?.purchaseQuestions ?? []).isEmpty {
                    inputFocused = false
                    proxy.scrollTo(last.id, anchor: .top)
                } else { proxy.scrollTo("latest", anchor: .bottom) }
            }
        }
    }
    private var inputBar: some View {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        return VStack(alignment: .leading, spacing: YubaiSpace.gapGroup) {
            if messages.isEmpty && !busy && !reading {
                VStack(alignment: .leading, spacing: YubaiSpace.gapGroup) {
                    ForEach(AskYubai.exampleQuestions(ledger: store.current, occurrences: store.funds.occurrences, now: Date()), id: \.self) { question in
                        Button { input = question; send() } label: {
                            Text(question).yubaiFont(YubaiFont.callout).padding(.horizontal, YubaiSpace.gapGroup).padding(.vertical, YubaiSpace.gapGroup)
                                .frame(minHeight: YubaiSize.tapMin)
                                .overlay { Capsule().strokeBorder(YubaiColor.grabber, lineWidth: 1) }
                                .contentShape(Capsule())
                        }.foregroundStyle(enabled ? YubaiColor.label : YubaiColor.labelSecondary)
                            .buttonStyle(PressButtonStyle()).disabled(!enabled).opacity(enabled ? 1 : 0.55)
                    }
                }
            }
            availabilityStatus
            ChatInputBar(text: $input, placeholder: messages.isEmpty ? "问点什么…" : "接着问…",
                accessibilityLabel: enabled ? "问余白" : "问余白（暂不可用）", inputID: "askInput", sendID: "sendAsk",
                enabled: enabled, busy: busy || reading, showSend: !(voice.recording || (trimmed.isEmpty && (voice.available || voice.permissionDenied))), focus: $inputFocused, send: send) {
                Menu {
                    Button("从照片选择截图") { photoPicker = true }.accessibilityIdentifier("askChooseReceiptPhoto")
                    Button("选择图片文件") { filePicker = true }.accessibilityIdentifier("askChooseReceiptFile")
                } label: {
                    Image(systemName: "plus").frame(width: YubaiSize.iconButton, height: YubaiSize.iconButton)
                        .yubaiHitTarget()
                }.disabled(!canRecognizeReceipt).accessibilityLabel("添加截图或照片").accessibilityIdentifier("askReceiptMenu")
            } accessory: {
                if voice.recording || (trimmed.isEmpty && (voice.available || voice.permissionDenied)) {
                    Button {
                        if voice.recording { voice.stop() }
                        else { voicePrefix = input.isEmpty ? "" : input + " "; voiceTask = Task { await voice.start() } }
                    } label: {
                        Image(systemName: voice.recording ? "stop.fill" : "mic")
                            .frame(width: YubaiSize.iconButton, height: YubaiSize.iconButton)
                            .foregroundStyle(voice.recording ? YubaiColor.onBrand : YubaiColor.label).background(voice.recording ? YubaiColor.brand : YubaiColor.raised, in: Circle())
                            .yubaiHitTarget()
                    }.accessibilityLabel(voice.recording ? "停止听写" : "语音输入").disabled(voice.permissionDenied)
                }
            }
        }.padding(.horizontal, YubaiSpace.insetPage).padding(.bottom, YubaiSpace.insetPage)
    }
    @ViewBuilder private var availabilityStatus: some View {
        if !configured {
            NavigationLink { IntelligencePrivacyView() } label: { Pill(text: "还没配密钥 ›", variant: .amber, showsDot: false) }
                .buttonStyle(PressButtonStyle()).frame(maxWidth: .infinity).accessibilityHint("打开智能与隐私，配置密钥")
                .accessibilityIdentifier("configureAskKey")
        } else if !connectivity.connected {
            Pill(text: "没联网", variant: .amber, showsDot: false).frame(maxWidth: .infinity)
        } else if !store.preferences.isAIEnabled(for: .answers) {
            NavigationLink { IntelligencePrivacyView() } label: { Pill(text: "云端智能没开 ›", variant: .amber, showsDot: false) }
                .buttonStyle(PressButtonStyle()).frame(maxWidth: .infinity).accessibilityIdentifier("enableAskAI")
        } else if let model = IntelligenceRuntime.cloud.unavailableModel {
            NavigationLink { IntelligencePrivacyView() } label: { Pill(text: "模型不可用 ›", variant: .amber, showsDot: false) }
                .buttonStyle(PressButtonStyle()).accessibilityLabel("模型「\(model)」不可用，换个模型")
        }
        if voice.permissionDenied {
            HStack(spacing: YubaiSpace.space4) {
                Text("没开语音权限").yubaiFont(YubaiFont.caption)
                SystemSettingsButton(title: "去设置", pane: .speech)
            }.foregroundStyle(YubaiColor.amberInk)
        }
    }
    @ViewBuilder private func messageView(_ message: AskMessage, proxy: ScrollViewProxy) -> some View {
        if message.isUser {
            HStack(spacing: YubaiSpace.gapGroup) {
                Spacer(minLength: YubaiSpace.gapSection)
                userBubble(message)
                    .padding(YubaiSpace.insetCard).foregroundStyle(YubaiColor.onBrand)
                    .background(YubaiColor.brand, in: UnevenRoundedRectangle(topLeadingRadius: YubaiRadius.row, bottomLeadingRadius: YubaiRadius.row, bottomTrailingRadius: YubaiRadius.messageTail, topTrailingRadius: YubaiRadius.row))
            }
        } else if let reply = message.reply {
            if let statement = reply.pastedStatement { AskPastedStatementCard(statement: statement) }
            else if showsStandardReply(reply) { standardReplyCard(reply, message: message) }
            ForEach(reply.proposedChangeSets) { change in
                changeCard(change, message: message)
            }
            if isEntryDraftReply(reply) { RememberedRows(notes: reply.rememberedNotes + reply.updatedNotes.map(\.note)) }
            if let questions = reply.purchaseQuestions, !questions.isEmpty {
                purchaseQuestions(questions, reply: reply, message: message, proxy: proxy)
            } else if let purchase = reply.purchaseJudgment {
                SavingPurchaseCard(purchase: purchase, verdict: reply.purchaseVerdict, evidence: reply.evidenceEntryIDs,
                    notes: reply.rememberedNotes + reply.updatedNotes.map(\.note))
            }
        }
    }
    private func purchaseQuestions(_ questions: [PurchaseQuestion], reply: AssistantReply, message: AskMessage, proxy: ScrollViewProxy) -> some View {
        let actionsID = "purchaseActions_" + message.id.uuidString
        return PurchaseQuestionsCard(questions: questions, busy: busy, active: messages.last?.id == message.id,
            actionsID: actionsID, dismissInput: { inputFocused = false },
            selectionChanged: { proxy.scrollTo(actionsID, anchor: .bottom) },
            send: { input = $0; send() }, notes: reply.rememberedNotes + reply.updatedNotes.map(\.note))
    }
    private func showsStandardReply(_ reply: AssistantReply) -> Bool {
        reply.purchaseJudgment == nil && (reply.purchaseQuestions ?? []).isEmpty && !isEntryDraftReply(reply)
    }
    @ViewBuilder private func changeCard(_ change: ChangeSet, message: AskMessage) -> some View {
        let drafts: [EntryDraft] = change.items.compactMap { item in
            guard case .addEntry(let draft) = item else { return nil }
            return draft
        }
        if !drafts.isEmpty && drafts.count == change.items.count { AskEntryDraftCard(change: change, drafts: drafts, image: message.image) }
        else { AskChangeCard(change: change) }
    }
    private func standardReplyCard(_ reply: AssistantReply, message: AskMessage) -> some View {
        AssistantCard {
            VStack(alignment: .leading, spacing: YubaiSpace.space8) {
                HStack(spacing: YubaiSpace.space8) { AssistantMark(size: 14).accessibilityHidden(true); Text("余白").yubaiFont(YubaiFont.meta) }.foregroundStyle(YubaiColor.brandInk)
                Text(store.preferences.hideAmounts ? "金额已隐藏。" : reply.text).yubaiFont(YubaiFont.body).textSelection(.enabled).accessibilityIdentifier("askAnswer")
                if let chart = reply.chart, !store.preferences.hideAmounts { AnswerChartView(chart: chart) }
                replyEvidence(reply, message: message)
                unverifiedAmounts(reply)
                if message.protectedEdit { protectedRecords(message) }
                RememberedRows(notes: reply.rememberedNotes + reply.updatedNotes.map(\.note))
            }
        }
    }
    @ViewBuilder private func replyEvidence(_ reply: AssistantReply, message: AskMessage) -> some View {
        if !message.protectedEdit {
            NavigationLink("明细：\(reply.evidenceEntryIDs.count) 笔 ›") { AskEvidenceView(ids: reply.evidenceEntryIDs) }
                .yubaiFont(YubaiFont.caption).frame(minHeight: YubaiSize.tapMin).accessibilityIdentifier("answerEvidence")
        }
    }
    @ViewBuilder private func unverifiedAmounts(_ reply: AssistantReply) -> some View {
        if !reply.unverifiedAmounts.isEmpty {
            HStack(spacing: YubaiSpace.space8) {
                Text(store.preferences.hideAmounts ? "••••" : reply.unverifiedAmounts.joined(separator: "、"))
                    .yubaiFont(YubaiFont.amountSmall).foregroundStyle(YubaiColor.amberInk)
                NavigationLink { AskRecordLookupView(ids: reply.evidenceEntryIDs) } label: { Pill(text: "核对 ›", variant: .amber, showsDot: false) }
            }.accessibilityElement(children: .contain).accessibilityLabel("回答中有金额尚未核实")
        }
    }
    @ViewBuilder private func protectedRecords(_ message: AskMessage) -> some View {
        if message.protectedRecords.count == 1, let id = message.protectedRecords.first {
            NavigationLink("核对这笔 · 记录详情 ›") { EntryDetailView(entryID: id) }.frame(minHeight: YubaiSize.tapMin).yubaiFont(YubaiFont.caption)
        } else {
            NavigationLink("核对相关记录 ›") { AskRecordLookupView(ids: message.protectedRecords) }.frame(minHeight: YubaiSize.tapMin).yubaiFont(YubaiFont.caption)
        }
    }
    private func isEntryDraftReply(_ reply: AssistantReply) -> Bool {
        !reply.proposedChangeSets.isEmpty && reply.proposedChangeSets.allSatisfy { change in
            !change.items.isEmpty && change.items.allSatisfy { if case .addEntry = $0 { return true }; return false }
        } && reply.unverifiedAmounts.isEmpty
    }
    @ViewBuilder private func userBubble(_ message: AskMessage) -> some View {
        if let statement = message.tableExcerpt {
            VStack(alignment: .leading, spacing: YubaiSpace.space8) {
                Text(store.preferences.hideAmounts ? "账单表格" : (statement.preamble.isEmpty ? "帮我导入这些" : statement.preamble)).yubaiFont(YubaiFont.body)
                Text(store.preferences.hideAmounts ? "金额已隐藏" : statement.text)
                    .yubaiFont(YubaiFont.meta).lineLimit(4).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(YubaiSpace.space8).background(YubaiColor.onBrand.opacity(0.15), in: RoundedRectangle(cornerRadius: YubaiRadius.control))
                Text("共 \(statement.rowCount) 行").yubaiFont(YubaiFont.meta)
            }.accessibilityIdentifier("pastedStatementBubble")
        } else { Text(store.preferences.hideAmounts ? "金额已隐藏" : message.text).yubaiFont(YubaiFont.body) }
    }
    @MainActor private func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard enabled, !busy, !text.isEmpty else { return }
        let ledger = store.current; let image = originalImage
        guard image == nil || canRecognizeReceipt,
              let transport = store.assistantTransport(for: ledger, feature: image == nil ? .answers : .receiptRecognition) else { return }
        input = ""; errorText = ""; busy = true; messages.append(AskMessage(text: text, isUser: true))
        store.recordQuestion(text)
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
        guard canRecognizeReceipt else { return }
        captureTask?.cancel(); reading = true; errorText = ""
        captureTask = Task { @MainActor in await readImage(bytes) }
    }
    @MainActor private func readImage(_ bytes: Data) async {
        guard canRecognizeReceipt else { return }
        let ledgerID = store.current.id
        defer { if !Task.isCancelled { reading = false } }
        do {
            guard bytes.count <= 50 * 1024 * 1024 else { throw YubaiError.invalid("图片请小于 50 MB。") }
            let receipt = try await Task.detached(priority: .userInitiated) { try ReceiptReader.recognize(bytes) }.value
            try Task.checkCancellation()
            guard store.current.id == ledgerID, !store.locked, canRecognizeReceipt else { return }
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
    @Environment(\.dismiss) private var dismiss
    @Environment(AppStore.self) private var store
    let ids: [UUID]
    var body: some View {
        let rows = store.sortedEntries.filter { ids.contains($0.id) && $0.deletedAt == nil }
        Page {
            CardRows(rows) { entry in
                EntryLink(entry: entry, hideAmount: store.preferences.hideAmounts).accessibilityIdentifier("evidenceEntry_" + entry.id.uuidString)
            }
            if rows.isEmpty { EmptyState("doc.questionmark", "记录已移除", action: "返回", onAction: { dismiss() }) }
        }.navigationTitle("明细").yubaiNavigation()
    }
}

private struct AskRecordLookupView: View {
    @Environment(AppStore.self) private var store
    let ids: [UUID]
    @State private var search = ""
    var body: some View {
        Page {
            TextField("搜索", text: $search).frame(minHeight: YubaiSize.tapMin)
                .accessibilityLabel("搜索核对记录").accessibilityHint("打开记录详情，可核对原始账单")
            let rows = store.sortedEntries.filter { $0.deletedAt == nil && (ids.isEmpty || ids.contains($0.id)) && (search.isEmpty || $0.displayTitle.localizedCaseInsensitiveContains(search)) }
            CardRows(rows) { entry in
                EntryLink(entry: entry, hideAmount: store.preferences.hideAmounts)
            }
        }.navigationTitle("核对记录").yubaiNavigation()
    }
}

private struct AskChangeCard: View {
    @Environment(AppStore.self) private var store
    let change: ChangeSet
    @State private var status: String?
    var body: some View {
        if let status { Text(status).yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.brandInk).frame(minHeight: YubaiSize.tapMin) }
        else {
            let count = Set(change.items.flatMap(\.entryIDs)).count
            ProposalCard(title: store.preferences.hideAmounts ? "余白想这样改" : change.reason, lines: store.preferences.hideAmounts ? [] : change.preview(in: store.current, showPreviousValues: true),
                         primaryTitle: count > 0 ? "改好这 \(count) 笔" : "改好这 \(change.items.count) 项", canConfirm: !store.preferences.hideAmounts, confirm: {
                if store.apply(change, label: "问余白修改") {
                    status = "已改好，可撤销上一项修改。" + (store.toast?.contains("；") == true ? (store.toast ?? "") : "")
                }
            }, cancel: {
                if store.update("不改了", { $0.pendingChanges.removeAll { $0.id == change.id } }) { status = "这次不改了。" }
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
                VStack(alignment: .leading, spacing: YubaiSpace.gapGroup) {
                    HStack(spacing: YubaiSpace.space8) { AssistantMark(size: 14); Text("余白").yubaiFont(YubaiFont.meta) }.foregroundStyle(YubaiColor.brandInk)
                    if let summary = statement.summary {
                        Text("\(ImportStatementText.source(summary.source))导出 · \(count) 笔").yubaiFont(YubaiFont.cardTitle)
                        Text(ImportStatementText.range(start: summary.startDate, end: summary.endDate))
                            .yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: YubaiSpace.gapGroup) { total("支出", count: summary.expenseCount, amount: summary.expenseTotal); Spacer(); total("收入", count: summary.incomeCount, amount: summary.incomeTotal) }
                            VStack(alignment: .leading, spacing: YubaiSpace.space8) { total("支出", count: summary.expenseCount, amount: summary.expenseTotal); total("收入", count: summary.incomeCount, amount: summary.incomeTotal) }
                        }
                    } else {
                        Text("账单表格 · \(count) 笔").yubaiFont(YubaiFont.cardTitle)
                        Text(statement.needsColumnMapping ? "请核对表头" : (statement.previewError ?? "日期待核对"))
                            .yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.amberInk)
                    }
                    LocalSourcePill()
                    HStack(spacing: YubaiSpace.space8) {
                        Button("不导入") { cancelled = true }.buttonStyle(SecondaryButtonStyle(background: YubaiColor.raised, compact: true)).accessibilityIdentifier("cancelPastedImport")
                        Button("核对 \(count) 笔") { reviewing = true }.buttonStyle(PrimaryButtonStyle(compact: true)).accessibilityIdentifier("reviewPastedStatement")
                    }
                }
            }.accessibilityIdentifier("pastedStatementCard")
                .sheet(isPresented: $reviewing) { NavigationStack { ImportView(pasted: statement) }.environment(store).appErrors().yubaiSheetBackground() }
        }
    }
    private func total(_ title: String, count: Int, amount: Int64) -> some View {
        HStack(spacing: YubaiSpace.space8) {
            Text("\(title) \(count) 笔").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelMuted)
            AmountLabel(cents: amount, hide: store.preferences.hideAmounts, role: .small, sign: .none)
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
        let day: String = today ? "今天" : ImportStatementText.range(dates)
        let account: String = accounts.count == 1 ? store.accountName(drafts[0].accountID) : "多个账户"
        return day + " · " + account
    }
    var body: some View {
        if savedCount > 0 { Text("已记下 \(savedCount) 笔，可撤销上一项修改。").yubaiFont(YubaiFont.callout).accessibilityIdentifier("draftEntriesSaved") }
        else if cancelled { Text("这次不记了。").yubaiFont(YubaiFont.callout) }
        else {
            Card(style: .compact) {
                VStack(alignment: .leading, spacing: YubaiSpace.gapGroup) {
                    HStack(spacing: YubaiSpace.space8) { AssistantMark(size: 14); Text("余白").yubaiFont(YubaiFont.meta) }.foregroundStyle(YubaiColor.brandInk)
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline, spacing: YubaiSpace.gapGroup) { Text("准备记下 \(chosen.count) 笔").yubaiFont(YubaiFont.cardTitle); Spacer(); Text(summary).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary) }
                        VStack(alignment: .leading, spacing: YubaiSpace.space4) { Text("准备记下 \(chosen.count) 笔").yubaiFont(YubaiFont.cardTitle); Text(summary).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary) }
                    }
                    Card(style: .list, background: YubaiColor.raised) {
                        VStack(spacing: YubaiSpace.none) {
                            ForEach(drafts, id: \.id) { draft in
                                draftRow(draft)
                                if draft.id != drafts.last?.id { Divider().overlay(YubaiColor.separator) }
                            }
                        }
                    }
                    HStack(spacing: YubaiSpace.gapGroup) {
                        Text("合计").yubaiFont(YubaiFont.row)
                        Spacer()
                        if let sum { AmountLabel(cents: sum, hide: store.preferences.hideAmounts, role: .small, sign: .none) }
                        else { Text("金额超出范围").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.amberInk) }
                    }
                    Toggle("金额和原文对得上", isOn: $amountsConfirmed).tint(YubaiColor.toggleOn).yubaiFont(YubaiFont.row).accessibilityIdentifier("confirmDraftAmounts")
                    HStack(spacing: YubaiSpace.space8) {
                        Button("不记了", action: cancelDraft).buttonStyle(SecondaryButtonStyle(background: YubaiColor.raised, compact: true)).accessibilityIdentifier("cancelDraftEntries")
                        Button("记下 \(chosen.count) 笔", action: save).buttonStyle(PrimaryButtonStyle(compact: true))
                            .disabled(!amountsConfirmed || chosen.isEmpty || sum == nil || store.preferences.hideAmounts || chosen.contains { $0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
                            .accessibilityIdentifier("saveDraftEntries")
                    }
                }
            }.accessibilityIdentifier("multiEntryDraftCard")
                .sheet(item: $editing) { selection in
                    NavigationStack { AskDraftEditor(draft: selection.draft) { edited in
                        if let index = drafts.firstIndex(where: { $0.id == edited.id }) { drafts[index] = edited; amountsConfirmed = false }
                    } }.environment(store).yubaiSheetBackground()
                }
        }
    }
    private func draftRow(_ draft: EntryDraft) -> some View {
        HStack(spacing: YubaiSpace.space8) {
            Button {
                if selected.contains(draft.id) { selected.remove(draft.id) } else { selected.insert(draft.id) }
                amountsConfirmed = false
            } label: { Image(systemName: selected.contains(draft.id) ? "checkmark.circle.fill" : "circle").foregroundStyle(selected.contains(draft.id) ? YubaiColor.brand : YubaiColor.labelSecondary).frame(width: YubaiSize.tapMin, height: YubaiSize.tapMin) }
                .buttonStyle(PressButtonStyle()).accessibilityLabel((selected.contains(draft.id) ? "不记" : "记下") + draft.title).accessibilityIdentifier("selectDraft_" + draft.id.uuidString)
            Button { editing = AskDraftEdit(draft: draft) } label: {
                HStack(spacing: YubaiSpace.gapGroup) {
                    VStack(alignment: .leading, spacing: YubaiSpace.space4) {
                        Text(draft.purpose ?? draft.title).yubaiFont(YubaiFont.row)
                        Text(Classification.displayCategory(draft.category) + (draft.subcategory.map { " · " + $0 } ?? "")).yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    AmountLabel(cents: draft.amount, hide: store.preferences.hideAmounts, sign: draft.nature.inflow ? .inflow : .none)
                    Image(systemName: "chevron.right").yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary)
                }.frame(minHeight: YubaiSize.tapMin).contentShape(Rectangle())
            }.buttonStyle(PressButtonStyle()).accessibilityIdentifier("editDraft_" + draft.id.uuidString)
        }
    }
    private func save() {
        guard amountsConfirmed, !chosen.isEmpty, sum != nil, !store.preferences.hideAmounts else { return }
        let chosen = self.chosen
        var confirmed = change
        confirmed.items = chosen.map { draft in var value = draft; value.amountConfirmed = true; return .addEntry(value) }
        if store.apply(confirmed, label: "问余白修改", finishing: { ledger in
            for draft in chosen where draft.categoryUserEdited == true && !Classification.isPending(draft.category) {
                try CategoryModel.confirm(.init(category: draft.category, subcategory: draft.subcategory), entryIDs: [draft.id], in: &ledger)
            }
            if let image {
                let compressed = ImageCompression.compress(image.data, name: image.name)
                let attachment = Attachment(name: compressed.name, data: compressed.data)
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
    let draft: EntryDraft
    let save: (EntryDraft) -> Void
    var body: some View {
        let entry = editableEntry
        EntryEditForm(entry: entry, title: "改这笔", primaryTitle: "放回") { edited in
            var value = draft
            value.amount = edited.amount; value.nature = edited.nature; value.date = edited.date
            value.accountID = edited.accountID; value.otherAccountID = edited.otherAccountID
            value.title = edited.title; value.purpose = edited.purpose
            value.category = edited.category; value.subcategory = edited.subcategory; value.categoryUserEdited = true
            value.partID = edited.partID
            save(value)
        }
    }
    private var editableEntry: Entry {
        var value = Entry(date: draft.date, amount: draft.amount, nature: draft.nature, accountID: draft.accountID,
                          title: draft.title, category: draft.category)
        value.id = draft.id; value.purpose = draft.purpose; value.subcategory = draft.subcategory; value.otherAccountID = draft.otherAccountID
        value.partID = draft.partID
        return value
    }
}

/// Shared text field and send styling; callers supply screenshot and voice controls.
struct ChatInputBar<Leading: View, Accessory: View>: View {
    @Binding var text: String
    var placeholder: String
    var accessibilityLabel: String
    var inputID: String
    var sendID: String
    var enabled = true
    var busy = false
    var showSend = true
    var focus: FocusState<Bool>.Binding? = nil
    var send: () -> Void
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var accessory: () -> Accessory
    @FocusState private var localFocus: Bool
    var body: some View {
        HStack(alignment: .bottom, spacing: YubaiSpace.space8) {
            leading().frame(height: YubaiSize.iconButton)
            TextField(placeholder, text: $text, axis: .vertical)
                .focused(focus ?? $localFocus)
                .lineLimit(1...5).yubaiFont(YubaiFont.navTitle, weight: .regular)
                .padding(.vertical, YubaiSpace.gapGroup).frame(minHeight: YubaiSize.iconButton)
                .accessibilityIdentifier(inputID).accessibilityLabel(accessibilityLabel)
            accessory().frame(height: YubaiSize.iconButton)
            if showSend {
                Button(action: send) {
                    Image(systemName: "arrow.up").fontWeight(.semibold)
                        .frame(width: YubaiSize.iconButton, height: YubaiSize.iconButton)
                        .foregroundStyle(Color.white).background(YubaiColor.brand, in: Circle())
                        .yubaiHitTarget()
                }.accessibilityLabel("发送").accessibilityIdentifier(sendID)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.disabled(!enabled || busy).padding(YubaiSpace.space8).frame(minHeight: YubaiSize.buttonHeight)
            .fixedSize(horizontal: false, vertical: true)
            .buttonStyle(PressButtonStyle()).floatingSurface(in: Capsule(), shadow: YubaiShadow.input)
            .opacity(enabled ? 1 : 0.6)
    }
}

private struct AskPageHeader: ViewModifier {
    let inSheet: Bool
    let showsClear: Bool
    let clear: () -> Void
    @ViewBuilder func body(content: Content) -> some View {
        if inSheet {
            content.manualSheetHeader("问余白", actionTitle: "清空", primary: false, cancelTitle: "关闭", showsAction: showsClear,
                                      actionIdentifier: "clearAskConversation", action: clear)
        } else {
            content.toolbar {
                if showsClear {
                    ToolbarItem(placement: .primaryAction) {
                        Button("清空", action: clear).accessibilityIdentifier("clearAskConversation")
                    }
                }
            }
        }
    }
}
