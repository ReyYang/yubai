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
    var day = Dates.day(Dates.now)
    var messages: [AskMessage] = []
    var session = AskYubaiSession()
    func expire() {
        if day != Dates.day(Dates.now) { clear() }
    }
    func clear() { day = Dates.day(Dates.now); messages = []; session = AskYubaiSession() }
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
    @State private var conversationDay = Dates.day(Dates.now)
    @State private var conversationLedgerID: UUID?
    private var configured: Bool { IntelligenceRuntime.isConfigured }
    @FocusState private var inputFocused: Bool
    private var cloudAnswersAvailable: Bool { store.cloudAIReady && connectivity.connected }
    private var canRecognizeReceipt: Bool { cloudAnswersAvailable && store.preferences.isAIEnabled(for: .receiptRecognition) }
    private var headerTitle: String {
        let replies = messages.compactMap(\.reply)
        if replies.contains(where: { $0.purchaseJudgment != nil || !($0.purchaseQuestions ?? []).isEmpty }) { return "该不该买" }
        if replies.contains(where: { reply in
            !reply.proposedChangeSets.isEmpty && reply.proposedChangeSets.allSatisfy { change in
                change.items.allSatisfy { if case .addEntry = $0 { return true }; return false }
            }
        }) { return "帮我记" }
        if replies.contains(where: { $0.toolTrace.contains { $0.name == "summarize" } }) { return "钱去哪了" }
        return "问余白"
    }
    private func clearConversation() {
        cancel(); messages = []; session = AskYubaiSession(); store.askConversation.clear()
    }
    @MainActor private func sendPendingQuestion() {
        guard pendingAutoSend, !busy, !input.isEmpty else { return }
        pendingAutoSend = false
        send()
    }
    var body: some View {
        VStack(spacing: YubaiSpace.none) {
            conversation
            inputBar
        }.amountPrivacy(store.preferences.hideAmounts).paperBackground().navigationTitle(headerTitle).yubaiNavigation().accessibilityIdentifier("askPage")
            .surfacePresentations()
            #if DEBUG && targetEnvironment(simulator)
            .uiTestAccessibilityValue(UITestSupport.secondBatchState(in: store.current))
            #endif
            #if os(iOS)
            .toolbarBackground(.hidden, for: .navigationBar)
            #endif
            .modifier(AskPageHeader(inSheet: inSheet, showsClear: !messages.isEmpty, clear: clearConversation))
            .onChange(of: cloudAnswersAvailable) { _, available in if available { sendPendingQuestion() } }
            .task {
                try? await Task.sleep(nanoseconds: 400_000_000)
                if !Task.isCancelled { sendPendingQuestion() }
            }
            .photosPicker(isPresented: $photoPicker, selection: $photo, matching: .images)
            .fileImporter(isPresented: $filePicker, allowedContentTypes: [.image]) { result in
                Task { @MainActor in
                    do {
                        let url = try result.get()
                        let bytes = try await Task.detached(priority: .userInitiated) {
                            let access = url.startAccessingSecurityScopedResource()
                            defer { if access { url.stopAccessingSecurityScopedResource() } }
                            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                            guard size <= 50 * 1024 * 1024 else { throw YubaiError.invalid("图片请小于 50 MB。") }
                            return try Data(contentsOf: url)
                        }.value
                        recognize(bytes)
                    } catch { errorText = error.localizedDescription }
                }
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
            .onAppear { connectivity.start(); voice.refreshPermissions(); IntelligenceRuntime.cloud.refresh(); if !appeared { appeared = true; store.askConversation.expire(); messages = store.askConversation.messages; session = store.askConversation.session; conversationDay = store.askConversation.day; conversationLedgerID = store.current.id; input = initialText; pendingAutoSend = autoSend && !initialText.isEmpty; if let initialImage { recognize(initialImage) } } }
            .onChange(of: IntelligenceRuntime.cloud.unavailableModel) { _, model in if model == nil { errorText = "" } }
            .onDisappear { cancel(); connectivity.stop(); if conversationDay == Dates.day(Dates.now) && conversationLedgerID == store.current.id { store.askConversation.messages = messages; store.askConversation.session = session } }
            .onChange(of: scenePhase) { _, phase in if phase == .active { if conversationDay != Dates.day(Dates.now) { cancel(); messages = []; session = AskYubaiSession(); store.askConversation.clear(); conversationDay = store.askConversation.day }; voice.refreshPermissions() } }
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
                    if messages.isEmpty && !busy && !reading { suggestions }
                    availabilityStatus
                    ForEach(messages) { message in
                        messageView(message, proxy: proxy).messageEntrance(user: message.isUser).id(message.id)
                    }
                    if busy || reading {
                        HStack(spacing: YubaiSpace.gapGroup) { AssistantMark(thinking: true); Text(reading ? "正在读截图…" : "正在查阅…").yubaiFont(YubaiFont.callout) }
                    }
                    if !errorText.isEmpty { InlineNote(text: errorText, style: .attention) }
                    if !voice.errorText.isEmpty && !voice.permissionDenied { InlineNote(text: voice.errorText) }
                    Color.clear.frame(height: YubaiSize.separator).id("latest")
                }.padding(.horizontal, YubaiSpace.insetPage).padding(.vertical, YubaiSpace.space20)
                    .frame(maxWidth: YubaiSize.contentMedium, alignment: .leading).frame(maxWidth: .infinity)
            }.onChange(of: messages.count) { _, _ in
                if let last = messages.last, !(last.reply?.purchaseQuestions ?? []).isEmpty {
                    inputFocused = false
                    proxy.scrollTo(last.id, anchor: .top)
                } else { proxy.scrollTo("latest", anchor: .bottom) }
            }
        }
    }
    private var suggestions: some View {
        ChipFlow {
            ForEach(AskYubai.exampleQuestions(ledger: store.current, occurrences: store.funds.occurrences, now: Dates.now), id: \.self) { question in
                CategoryChoiceChip(title: question) { input = question; send() }
            }
        }
    }
    private var inputBar: some View {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        return ChatInputBar(text: $input, placeholder: messages.isEmpty ? "问一句" : "接着问",
                accessibilityLabel: "问余白", inputID: "askInput", sendID: "sendAsk",
                busy: busy || reading, showSend: !(voice.recording || (trimmed.isEmpty && (voice.available || voice.permissionDenied))), focus: $inputFocused, send: send) {
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
            .padding(.horizontal, YubaiSpace.insetPage).padding(.bottom, YubaiSpace.insetPage)
            .frame(maxWidth: YubaiSize.contentMedium).frame(maxWidth: .infinity)
    }
    @ViewBuilder private var availabilityStatus: some View {
        if !configured {
            NavigationLink { IntelligencePrivacyView() } label: { Pill(text: "配密钥开启深度对话 ›", variant: .amber, showsDot: false) }
                .buttonStyle(PressButtonStyle()).accessibilityHint("打开智能与隐私，配置密钥")
                .accessibilityIdentifier("configureAskKey")
        } else if !connectivity.connected {
            Pill(text: "没联网", variant: .amber, showsDot: false)
        } else if !store.preferences.isAIEnabled(for: .answers) {
            NavigationLink { IntelligencePrivacyView() } label: { Pill(text: "云端智能没开 ›", variant: .amber, showsDot: false) }
                .buttonStyle(PressButtonStyle()).accessibilityIdentifier("enableAskAI")
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
            else if isWhereReply(reply, message: message) { WhereAnswerCard() }
            else if showsStandardReply(reply) { standardReplyCard(message) }
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
        } else { standardReplyCard(message) }
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
    private func isWhereReply(_ reply: AssistantReply, message: AskMessage) -> Bool {
        guard reply.toolTrace.contains(where: { $0.name == "summarize" }),
              let index = messages.firstIndex(where: { $0.id == message.id }) else { return false }
        return messages[..<index].last(where: { $0.isUser })?.text.contains("这个月钱去哪了") == true
    }
    @ViewBuilder private func changeCard(_ change: ChangeSet, message: AskMessage) -> some View {
        let drafts: [EntryDraft] = change.items.compactMap { item in
            guard case .addEntry(let draft) = item else { return nil }
            return draft
        }
        if !drafts.isEmpty && drafts.count == change.items.count { AskEntryDraftCard(change: change, drafts: drafts, image: message.image) }
        else { AskChangeCard(change: change) }
    }
    private func standardReplyCard(_ message: AskMessage) -> some View {
        AssistantCard {
            VStack(alignment: .leading, spacing: YubaiSpace.space8) {
                HStack(spacing: YubaiSpace.space8) { AssistantMark(size: YubaiFont.row.size).accessibilityHidden(true); Text("余白").yubaiFont(YubaiFont.meta) }.foregroundStyle(YubaiColor.brandInk)
                Text(store.preferences.hideAmounts ? "金额已隐藏。" : message.text).yubaiFont(YubaiFont.body).textSelection(.enabled).accessibilityIdentifier("askAnswer")
                if let reply = message.reply {
                    replyEvidence(reply, message: message)
                    unverifiedAmounts(reply)
                    if message.protectedEdit { protectedRecords(message) }
                    RememberedRows(notes: reply.rememberedNotes + reply.updatedNotes.map(\.note))
                }
            }
        }
    }
    @ViewBuilder private func replyEvidence(_ reply: AssistantReply, message: AskMessage) -> some View {
        if !message.protectedEdit {
            NavigationLink("依据：\(reply.evidenceEntryIDs.count) 笔 ›") { AskEvidenceView(ids: reply.evidenceEntryIDs) }
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
                    .padding(YubaiSpace.space8).background(YubaiColor.onBrand.opacity(0.15), in: RoundedRectangle(cornerRadius: YubaiRadius.control, style: .continuous))
                Text("共 \(statement.rowCount) 行").yubaiFont(YubaiFont.meta)
            }.accessibilityIdentifier("pastedStatementBubble")
        } else { Text(store.preferences.hideAmounts ? "金额已隐藏" : message.text).yubaiFont(YubaiFont.body) }
    }
    @MainActor private func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !busy, !reading, !store.locked, !text.isEmpty else { return }
        pendingAutoSend = false
        let ledger = store.current; let image = originalImage
        let feature: AIFeature = image == nil ? .answers : .receiptRecognition
        guard cloudAnswersAvailable, image == nil || canRecognizeReceipt,
              let transport = store.assistantTransport(for: ledger, feature: feature) else {
            let priorPurchase = messages.last.map { !$0.isUser && $0.reply == nil && $0.text == LocalAskAnswer.priceQuestion } == true
                ? messages.last(where: \.isUser)?.text : nil
            let answer = LocalAskAnswer.reply(to: text, pendingPurchase: priorPurchase, in: ledger, now: Dates.now)
            input = ""; errorText = ""; originalImage = nil
            messages.append(contentsOf: [AskMessage(text: text, isUser: true), AskMessage(text: answer)])
            store.recordQuestion(text)
            return
        }
        input = ""; errorText = ""; busy = true; messages.append(AskMessage(text: text, isUser: true))
        store.recordQuestion(text)
        task = Task { @MainActor in
            defer { busy = false }
            do {
                let reply = try await session.ask(text, ledger: ledger, transport: transport)
                try Task.checkCancellation()
                guard store.current == ledger, !store.locked, cloudAnswersAvailable else {
                    errorText = "账本已更新，可以再问一次。"; input = text; session = AskYubaiSession(); return
                }
                let protectedEdit = AskYubai.isProtectedEdit(text)
                let previousIDs = Set(messages.compactMap(\.reply).flatMap { $0.evidenceEntryIDs + $0.proposedChangeSets.flatMap { $0.items.flatMap(\.entryIDs) } })
                let amounts = EntryAmountParser.candidates(in: text)
                let related = ledger.activeEntries.filter { previousIDs.contains($0.id) }
                let matching = related.filter { amounts.contains($0.amount) }
                let recordIDs = (matching.isEmpty ? related : matching).map(\.id)
                let considered = reply.purchaseJudgment.flatMap { purchase in
                    reply.purchaseVerdict != nil && Finance.bigPurchase(ledger, amount: purchase.amount, now: Dates.now) != nil ? purchase : nil
                }
                if !reply.rememberedNotes.isEmpty || !reply.updatedNotes.isEmpty || !reply.usedMemoryIDs.isEmpty || !reply.proposedChangeSets.isEmpty || considered != nil {
                    guard store.update("记下问答", recordUndo: false, { ledger in
                        try Memory.apply(reply, to: &ledger)
                        ledger.pendingChanges.append(contentsOf: reply.proposedChangeSets)
                        if let purchase = considered, let verdict = reply.purchaseVerdict {
                            try Wishlist.keepConsidered(fromVerdict: verdict, title: purchase.title, amount: purchase.amount,
                                                        category: purchase.category, subcategory: purchase.subcategory, in: &ledger, now: Dates.now)
                        }
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
            originalImage = AskImage(data: bytes, name: "截图-" + Dates.text(Dates.now) + "." + ext)
            // OCR runs on device. Only the redacted text enters the conversation.
            input = "这是截图里的文字，帮我记一笔：\n" + Redactor(ledger: store.current).text(receipt.text)
        } catch { if !Task.isCancelled { errorText = error.localizedDescription } }
    }
    @MainActor private func cancel() { task?.cancel(); captureTask?.cancel(); voiceTask?.cancel(); voice.stop(); busy = false; reading = false }
}

private enum LocalAskAnswer {
    static let priceQuestion = "多少钱？"

    static func reply(to text: String, pendingPurchase: String?, in ledger: Ledger, now: Date) -> String {
        let purchase = text.contains("买") ? text : pendingPurchase
        if let purchase {
            if let amount = purchasePrice(in: text) {
                let title = purchaseTitle(purchase)
                let choice = CategoryGuesser.guess(title, nature: .expense, date: now, in: ledger)
                let assessment = Finance.assessPurchase(ledger, amount: amount, title: title, category: choice?.category, subcategory: choice?.subcategory, now: now)
                return ([assessment.verdict.label, assessment.reason] + assessment.facts).joined(separator: "\n")
            }
            if purchase == text { return priceQuestion }
        }
        let breakdown = Finance.spendableBreakdown(ledger, now: now)
        let headline = breakdown.headlineTitle + " " + Money.text(breakdown.headlineAmount)
        if text.contains("上周") {
            let review = SavingInsights.weekly(ledger, now: now)
            return [headline, "上周支出 " + Money.text(review.spending)].joined(separator: "\n")
        }
        let thisWeek = text.contains("这周") || text.contains("本周")
        let start = thisWeek ? (ButlerCards.calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? breakdown.cycleStart) : breakdown.cycleStart
        let flow = Finance.cashFlow(ledger, during: DateInterval(start: start, end: now.addingTimeInterval(0.001)))
        var facts = [headline, (thisWeek ? "这周支出 " : "本期支出 ") + Money.text(flow.spending)]
        if let top = flow.spendingByCategory.first, top.amount > 0 {
            facts.append("花得最多 · " + Classification.displayCategory(top.category) + " " + Money.text(top.amount))
        }
        return facts.joined(separator: "\n")
    }

    private static let number = #"\d+(?:[,，]\d{3})*(?:\.\d{1,2})?"#
    private static let priceUnit = #"[万千](?:元|块)?|元|块"#
    private static let explicitPrice = #"(?<![\d.,，−-])(?:[¥￥]\s*\#(number)(?:\s*(?:\#(priceUnit)))?|\#(number)\s*(?:\#(priceUnit)))(?![\d.])"#

    private static func purchasePrice(in text: String) -> Int64? {
        let query = text.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? text
        if query.range(of: #"(?<![A-Za-z0-9])[−-]\s*[¥￥]?\s*\d"#, options: .regularExpression) != nil { return nil }
        if let range = query.range(of: explicitPrice, options: .regularExpression) {
            guard query[range.upperBound...].range(of: explicitPrice, options: .regularExpression) == nil else { return nil }
            let price = String(query[range])
            let scale: Int64 = price.contains("万") ? 10_000 : (price.contains("千") ? 1_000 : 1)
            let raw = price.filter { !"万千块".contains($0) && !$0.isWhitespace }
            guard let cents = try? Money.parse(raw), cents > 0, cents <= Money.limit / scale else { return nil }
            return cents * scale
        }
        // An affordability question needs a single price, independent of quantities in bookkeeping text.
        let singlePriceQuery = query.replacingOccurrences(of: "[各每]", with: " ", options: .regularExpression)
        let candidates = EntryAmountParser.candidates(in: singlePriceQuery)
        return candidates.count == 1 ? candidates.first : nil
    }

    private static func purchaseTitle(_ text: String) -> String {
        let query = text.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? text
        let price = query.range(of: explicitPrice, options: .regularExpression) == nil ? number : explicitPrice
        return query.replacingOccurrences(of: price, with: " ", options: .regularExpression)
            .replacingOccurrences(of: "该不该买|可以买|买得起|能买|想买|要买|买|多少钱", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }
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
        }.navigationTitle("依据").yubaiNavigation()
    }
}

private struct AskRecordLookupView: View {
    @Environment(AppStore.self) private var store
    let ids: [UUID]
    @State private var search = ""
    var body: some View {
        Page {
            SearchInput(text: $search, identifier: "askRecordSearch", label: "搜索核对记录")
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
            ProposalCard(title: store.preferences.hideAmounts ? "余白的建议" : change.reason, lines: store.preferences.hideAmounts ? [] : change.preview(in: store.current, showPreviousValues: true),
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
    @Environment(\.surfacePresentations) private var presentations
    let statement: PastedStatement
    @State private var cancelled = false
    private var count: Int { statement.summary?.entryCount ?? statement.rowCount }
    var body: some View {
        if cancelled { Text("这次不导入了。").yubaiFont(YubaiFont.callout) }
        else {
            Card(style: .compact) {
                VStack(alignment: .leading, spacing: YubaiSpace.gapGroup) {
                    HStack(spacing: YubaiSpace.space8) { AssistantMark(size: YubaiFont.row.size); Text("余白").yubaiFont(YubaiFont.meta) }.foregroundStyle(YubaiColor.brandInk)
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
                        Button("核对 \(count) 笔") {
                            presentations.presentSheet {
                                NavigationStack { ImportView(pasted: statement) }.environment(store).appErrors().yubaiSheetBackground()
                            }
                        }.buttonStyle(PrimaryButtonStyle(compact: true)).accessibilityIdentifier("reviewPastedStatement")
                    }
                }
            }.accessibilityIdentifier("pastedStatementCard")
        }
    }
    private func total(_ title: String, count: Int, amount: Int64) -> some View {
        HStack(spacing: YubaiSpace.space8) {
            Text("\(title) \(count) 笔").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelMuted)
            AmountLabel(cents: amount, hide: store.preferences.hideAmounts, role: .small, sign: .none)
        }
    }
}

private struct AskEntryDraftCard: View {
    @Environment(AppStore.self) private var store
    @Environment(\.surfacePresentations) private var presentations
    let change: ChangeSet
    @State private var drafts: [EntryDraft]
    let image: AskImage?
    @State private var selected: Set<UUID>
    @State private var savedCount = 0
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
    @State private var availableAfter: Int64?
    var body: some View {
        if savedCount > 0 { Text("已记下 \(savedCount) 笔").yubaiFont(YubaiFont.callout).accessibilityIdentifier("draftEntriesSaved") }
        else {
            AssistantCard {
                VStack(alignment: .leading, spacing: YubaiSpace.space8) {
                    Text("余白").yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary)
                    Text(chosen.count == 2 ? "记这两笔？" : "记这 \(chosen.count) 笔？").yubaiFont(YubaiFont.lead)
                    ForEach(drafts, id: \.id) { draft in
                        draftRow(draft)
                        if draft.id != drafts.last?.id { EntryFormDivider() }
                    }
                    if let availableAfter {
                        ResultBar(label: "记下后还能花", value: ResultBar.change(store.funds.available, availableAfter, hide: store.preferences.hideAmounts), identifier: "draftEntryPreview")
                    }
                    ChipFlow {
                        Button("都记下", action: save).buttonStyle(PrimaryButtonStyle(compact: true))
                            .disabled(chosen.isEmpty || sum == nil || chosen.contains { $0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
                            .accessibilityIdentifier("saveDraftEntries")
                        Button("改一下") { if let first = chosen.first ?? drafts.first { edit(first) } }
                            .buttonStyle(SecondaryButtonStyle(background: YubaiColor.card, compact: true)).accessibilityIdentifier("editDraftEntries")
                    }
                }
            }.accessibilityIdentifier("multiEntryDraftCard")
                .task(id: previewKey) { await refreshPreview() }
        }
    }
    private var previewKey: String { "\(store.ledgerRevision)-" + chosen.map { "\($0.id):\($0.amount):\($0.nature):\($0.date)" }.joined(separator: ",") }
    @MainActor private func refreshPreview() async {
        let ledger = store.current; let drafts = chosen; let now = store.financialNow
        let value = await Task.detached {
            let items = drafts.map { draft -> ChangeItem in var value = draft; value.amountConfirmed = true; return .addEntry(value) }
            let preview = ChangeSet(source: "用户操作", reason: "记一笔", items: items)
            return try? ManualBookkeeping.available(after: preview, in: ledger, now: now)
        }.value
        guard !Task.isCancelled else { return }; availableAfter = value
    }
    private func draftRow(_ draft: EntryDraft) -> some View {
        HStack(spacing: YubaiSpace.space8) {
            Button {
                if selected.contains(draft.id) { selected.remove(draft.id) } else { selected.insert(draft.id) }
            } label: { Image(systemName: selected.contains(draft.id) ? "checkmark.circle.fill" : "circle").foregroundStyle(selected.contains(draft.id) ? YubaiColor.brand : YubaiColor.labelSecondary).frame(width: YubaiSize.tapMin, height: YubaiSize.tapMin) }
                .buttonStyle(PressButtonStyle()).accessibilityLabel((selected.contains(draft.id) ? "不记" : "记下") + draft.title).accessibilityIdentifier("selectDraft_" + draft.id.uuidString)
            Button { edit(draft) } label: {
                HStack(spacing: YubaiSpace.gapGroup) {
                    VStack(alignment: .leading, spacing: YubaiSpace.space4) {
                        Text(draft.purpose ?? draft.title).yubaiFont(YubaiFont.row).lineLimit(1).truncationMode(.tail)
                        Text(Classification.displayCategory(draft.category) + " · " + ManualBookkeeping.dayLabel(draft.date)).yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    AmountLabel(cents: draft.amount, hide: store.preferences.hideAmounts, sign: draft.nature.inflow ? .inflow : .outflow)
                    Image(systemName: "chevron.right").yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary)
                }.frame(minHeight: YubaiSize.tapMin).contentShape(Rectangle())
            }.buttonStyle(PressButtonStyle()).accessibilityIdentifier("editDraft_" + draft.id.uuidString)
        }
    }
    private func edit(_ draft: EntryDraft) {
        presentations.presentSheet {
            NavigationStack { AskDraftEditor(draft: draft) { edited in
                if let index = drafts.firstIndex(where: { $0.id == edited.id }) { drafts[index] = edited }
            } }.environment(store).yubaiSheetBackground()
        }
    }
    private func save() {
        guard !chosen.isEmpty, sum != nil else { return }
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
