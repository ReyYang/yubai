import SwiftUI
import Observation
import UserNotifications
import YubaiCore

/// What opens 问余白: text to fill or send now.
struct AskRequest: Identifiable, Equatable {
    var id = UUID()
    var text = ""
    var send = false
}

/// One turn in today's conversation. Lives in the store so a request keeps running
/// after the sheet closes (the 余白在算 pill) and the thread survives reopening.
struct AskMessage: Identifiable {
    enum Kind {
        case user(String)
        case reply(AssistantReply, question: String)
        case local(AskLocal.Answer, needsAI: Bool)
    }
    let id = UUID()
    let kind: Kind
}

@MainActor @Observable final class AskController {
    private(set) var messages: [AskMessage] = []
    private(set) var busy = false
    private(set) var runningLabel = ""
    /// The last request failed; the header shows 「AI 未连接」 until one succeeds.
    private(set) var failed = false
    var draft = ""
    @ObservationIgnored private var session = AskYubaiSession()
    @ObservationIgnored private var day = Dates.day(Dates.now)
    @ObservationIgnored private var ledgerID: UUID?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored let connectivity = AskConnectivity()

    func expireIfNeeded(ledgerID current: UUID) {
        if day != Dates.day(Dates.now) || (ledgerID != nil && ledgerID != current) { reset() }
        ledgerID = current
    }

    func reset() {
        cancel(); messages = []; session = AskYubaiSession(); day = Dates.day(Dates.now); failed = false; draft = ""
    }

    func cancel() { task?.cancel(); task = nil; busy = false }

    /// Fixture boards only.
    func seed(_ messages: [AskMessage], failed: Bool = false, busy: Bool = false, label: String = "") {
        self.messages = messages; self.failed = failed; self.busy = busy; runningLabel = label
    }

    func available(_ store: AppStore, feature: AIFeature = .answers) -> Bool {
        store.aiAvailability(for: feature) == .available && connectivity.connected && !failed
            && IntelligenceRuntime.cloud.unavailableModel == nil
    }

    func send(_ raw: String, store: AppStore) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !busy, !store.locked, !text.isEmpty else { return }
        expireIfNeeded(ledgerID: store.current.id)
        let ledger = store.current, now = store.financialNow
        let feature = AIFeature.answers
        draft = ""
        messages.append(AskMessage(kind: .user(text)))
        store.recordQuestion(text)
        let days = HomeDisplay.daysLeft(Finance.spendableBreakdown(ledger, now: now))
        func answerLocally() {
            let answer = AskLocal.answer(text, in: ledger, daysLeft: days, now: now)
            if case .purchase = answer { messages.append(AskMessage(kind: .local(answer, needsAI: true))) }
            else { messages.append(AskMessage(kind: .local(answer, needsAI: false))) }
        }
        failed = false
        guard available(store, feature: feature), let transport = store.assistantTransport(for: ledger, feature: feature) else {
            answerLocally(); return
        }
        let question = text
        busy = true; runningLabel = AskLocal.runningLabel(question, in: ledger, now: now)
        let session = session, tone = store.preferences.tone
        task = Task { @MainActor in
            defer { busy = false }
            do {
                let reply = try await session.ask(question, ledger: ledger, transport: transport, tone: tone)
                try Task.checkCancellation()
                // The ledger, the lock and the AI switch must be what they were when the question left.
                guard store.current == ledger, !store.locked, available(store, feature: feature) else {
                    draft = text; self.session = AskYubaiSession(); return
                }
                let considered = reply.purchaseJudgment.flatMap { purchase in
                    reply.purchaseVerdict != nil && Finance.bigPurchase(ledger, amount: purchase.amount, now: now) != nil ? purchase : nil
                }
                if !reply.rememberedNotes.isEmpty || !reply.updatedNotes.isEmpty || !reply.usedMemoryIDs.isEmpty || !reply.proposedChangeSets.isEmpty || considered != nil {
                    guard store.update("记下问答", recordUndo: false, entryMotion: false, showToast: false, { ledger in
                        try Memory.apply(reply, to: &ledger)
                        ledger.pendingChanges.append(contentsOf: reply.proposedChangeSets)
                        if let purchase = considered, let verdict = reply.purchaseVerdict {
                            try Wishlist.keepConsidered(fromVerdict: verdict, title: purchase.title, amount: purchase.amount,
                                                        category: purchase.category, subcategory: purchase.subcategory, in: &ledger, now: now)
                        }
                    }) else { draft = text; self.session = AskYubaiSession(); return }
                }
                messages.append(AskMessage(kind: .reply(reply, question: text)))
            } catch is CancellationError {
                if !Task.isCancelled { draft = text; self.session = AskYubaiSession() }
            } catch {
                failed = true
                answerLocally()
            }
        }
    }
}

/// 问余白: a self-drawn sheet over the page, top at 62, swipe or scrim to close.
struct AskSheetOverlay: View {
    let request: AskRequest
    let close: () -> Void
    @State private var motion = EntrySheetMotion(settled: AskFixture.current != nil)
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.dsReduceMotionOverride) private var reduceMotionOverride
    @Environment(\.dsAnimationsEnabled) private var animationsEnabled

    private var reduced: Bool { !animationsEnabled || (reduceMotionOverride ?? systemReduceMotion) }

    var body: some View {
        let _ = AskRenderCounts.hit("askOverlay")
        ZStack(alignment: .bottom) {
            EntryScrimView(motion: motion, color: DS.Color.scrim, close: dismiss).ignoresSafeArea()
            AskSheetContent(request: request, dismiss: dismiss, closeNow: close,
                            drag: { motion.drag($0) }, release: { motion.release($0, reduced: reduced, onClose: close) })
                .background(DS.Color.bg)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: DS.Radius.sheet, topTrailingRadius: DS.Radius.sheet, style: .continuous))
                // The page behind is hidden from VoiceOver by the root; not .isModal, so the undo toast stays reachable.
                .accessibilityElement(children: .contain)
                .accessibilityAction(.escape, dismiss)
                .modifier(EntrySheetPositionModifier(motion: motion, reduced: reduced, onClose: close, fill: DS.Color.bg))
                .padding(.top, AskSpec.sheetTop)
        }.ignoresSafeArea(.container, edges: [.top, .bottom])
            .accessibilityIdentifier("askSheet")
    }

    private func dismiss() { motion.close(reduced: reduced, onClose: close) }
}

private struct AskSheetContent: View {
    let request: AskRequest
    let dismiss: () -> Void
    let closeNow: () -> Void
    let drag: (DragGesture.Value) -> Void
    let release: (DragGesture.Value) -> Void
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bottomInset: CGFloat = 0
    @FocusState private var focused: Bool

    var body: some View {
        let _ = AskRenderCounts.hit("askSheetBody")
        @Bindable var controller = store.ask
        VStack(spacing: .zero) {
            header
            AskThread(onSend: { controller.send($0, store: store) }, openSettings: openSettings)
            AskComposer(text: $controller.draft, focus: $focused,
                        onSend: { controller.send(controller.draft, store: store) })
                .padding(.bottom, bottomInset > 0 ? AskSpec.composerKeyboardGap : .zero)
                .frame(minHeight: bottomInset > 0 ? nil : AskSpec.composerHeight, alignment: .top)
        }
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom } action: { bottomInset = $0 }
        .onAppear {
            store.ask.connectivity.start(); IntelligenceRuntime.cloud.refresh()
            store.ask.expireIfNeeded(ledgerID: store.current.id)
            if !request.text.isEmpty {
                if request.send { store.ask.send(request.text, store: store) } else { store.ask.draft = request.text }
            }
        }
        .onDisappear { store.ask.connectivity.stop() }
        .onChange(of: store.locked) { _, locked in if locked { store.ask.cancel(); closeNow() } }
    }

    private var header: some View {
        VStack(spacing: .zero) {
            EntryGrabber()
            ZStack {
                Text("问余白").dsText(DS.Font.tTitle).foregroundStyle(DS.Color.ink).accessibilityAddTraits(.isHeader)
                HStack {
                    Spacer(minLength: AskSpec.headerSide)
                    if !store.ask.available(store) {
                        Text("AI 未连接").dsText(AskSpec.badge).foregroundStyle(DS.Color.warnInk)
                            .padding(.horizontal, AskSpec.headerInset).frame(height: AskSpec.badgeHeight)
                            .dsPill(DS.Color.warnSoft).fixedSize().accessibilityIdentifier("askOffline")
                    }
                }.padding(.trailing, AskSpec.headerInset + AskSpec.headerInset)
            }.frame(height: AskSpec.headerHeight)
        }.contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: EntrySpec.dragMinimum, coordinateSpace: .global)
                .onChanged(drag).onEnded(release))
    }

    private func openSettings() {
        closeNow()
        store.tabRouteRequest = .aiSettings
    }
}

/// The scrolling thread. Reads only the messages, so the composer's typing does not rebuild it.
private struct AskThread: View {
    let onSend: (String) -> Void
    let openSettings: () -> Void
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let _ = AskRenderCounts.hit("askThread")
        let messages = store.ask.messages
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: AskSpec.contentGap) {
                    ForEach(messages) { message in
                        AskMessageView(message: message, latest: message.id == messages.last?.id, onSend: onSend, openSettings: openSettings)
                            .id(message.id)
                    }
                }.padding(.horizontal, DS.Space.s16).padding(.top, DS.Space.s8).padding(.bottom, DS.Space.s16)
            }.scrollIndicators(.hidden).scrollDismissesKeyboard(.interactively)
                .accessibilityIdentifier("askScroll")
                // Reopening lands on the latest turn; a short thread does not move.
                .onAppear { if let last = messages.last { proxy.scrollTo(last.id, anchor: .bottom) } }
                .onChange(of: messages.count) { _, _ in
                    guard let last = messages.last else { return }
                    withAnimation(reduceMotion ? nil : DSMotion.smoothAnimation) { proxy.scrollTo(last.id, anchor: .bottom) }
                }
        }
    }
}

private struct AskMessageView: View {
    let message: AskMessage
    let latest: Bool
    let onSend: (String) -> Void
    let openSettings: () -> Void
    @Environment(AppStore.self) private var store

    var body: some View {
        switch message.kind {
        case let .user(text):
            AskUserBubble(text: store.preferences.hideAmounts ? "金额已隐藏" : text)
                .frame(maxWidth: .infinity, alignment: .trailing)
        case let .reply(reply, question):
            AskReplyView(messageID: message.id, reply: reply, question: question, latest: latest, onSend: onSend)
        case let .local(answer, needsAI):
            AskLocalCard(answer: answer, needsAI: needsAI, openSettings: openSettings)
        }
    }
}

struct AskUserBubble: View {
    let text: String
    var body: some View {
        Text(text).dsText(AskSpec.body).foregroundStyle(DS.Color.ink)
            .padding(.vertical, AskSpec.bubbleVertical).padding(.horizontal, AskSpec.bubbleHorizontal)
            .background(DS.Color.surface, in: UnevenRoundedRectangle(topLeadingRadius: AskSpec.bubbleRadius, bottomLeadingRadius: AskSpec.bubbleRadius,
                                                                     bottomTrailingRadius: AskSpec.bubbleTail, topTrailingRadius: AskSpec.bubbleRadius, style: .continuous))
            .frame(maxWidth: AskSpec.bubbleWidth, alignment: .trailing)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("askUserBubble")
    }
}

/// Picks the card for a model reply. Every number on it comes from YubaiCore.
private struct AskReplyView: View {
    let messageID: UUID
    let reply: AssistantReply
    let question: String
    let latest: Bool
    let onSend: (String) -> Void
    @Environment(AppStore.self) private var store

    var body: some View {
        if let judgment = reply.purchaseJudgment, let verdict = reply.purchaseVerdict {
            AskPurchaseVerdict(judgment: judgment, verdict: verdict, expandable: !(reply.purchaseQuestions ?? []).isEmpty)
        }
        ForEach(reply.proposedChangeSets) { change in
            if change.items.allSatisfy({ if case .addEntry = $0 { return true }; return false }) {
                AskBatchCard(change: change)
            } else {
                AskApprovalView(change: change)
            }
        }
        if let questions = reply.purchaseQuestions, !questions.isEmpty {
            AskFollowUp(questions: questions, active: latest && !store.ask.busy, onSend: onSend)
        } else if reply.purchaseVerdict == nil && reply.proposedChangeSets.isEmpty && !reply.text.isEmpty {
            AskAnswerCard(text: store.preferences.hideAmounts ? "金额已隐藏" : reply.text, unverified: reply.unverifiedAmounts)
        }
    }
}

/// A plain answer from the model, with amounts the tools did not confirm in amber.
private struct AskAnswerCard: View {
    let text: String
    let unverified: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s8) {
            Text(text).dsText(AskSpec.body).foregroundStyle(DS.Color.ink).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("askAnswer")
            if !unverified.isEmpty {
                Text("未核实 " + unverified.joined(separator: "、")).dsText(DS.Font.tPill).monospacedDigit().foregroundStyle(DS.Color.warnInk)
            }
        }.askCard()
    }
}

private struct AskPurchaseVerdict: View {
    let judgment: PurchaseJudgment
    let verdict: SubmittedPurchaseVerdict
    let expandable: Bool
    @Environment(AppStore.self) private var store
    @State private var reminded = false

    var body: some View {
        let ledger = store.current, now = store.financialNow
        let hide = store.preferences.hideAmounts
        let card = AskPurchaseCard.make(ledger: ledger, title: judgment.title, amount: judgment.amount, category: judgment.category,
                                        subcategory: judgment.subcategory, verdict: verdict.verdict,
                                        daysLeft: HomeDisplay.daysLeft(Finance.spendableBreakdown(ledger, now: now)), now: now)
        let line = AskDisplay.change(card.headline, hidden: hide)
        AskVerdictCard(word: card.word, tone: card.verdict, change: (line.label, line.from, line.to, card.headline.overrun),
                       reason: hide ? "" : verdict.reason,
                       expanders: expandable ? [
                           .init(id: "changes", title: "账上还有 \(card.changes.count) 项变化",
                                 rows: card.changes.map { change in let d = AskDisplay.change(change, hidden: hide); return AskFact(key: d.label, value: d.from + " → " + d.to) }),
                           .init(id: "worth", title: "值不值 · \(card.worth.count) 条", rows: card.worth),
                       ] : [],
                       remind: card.remindOn.map { (reminded ? "已设 " : "") + AskDisplay.monthDay($0) + (reminded ? " 提醒" : " 提醒我") },
                       onRemind: { toggleReminder(card.remindOn, title: judgment.title) })
    }

    private func toggleReminder(_ date: Date?, title: String) {
        guard let date else { return }
        let id = "yubai.ask.remind." + judgment.title + "." + Dates.text(date)
        if reminded { AskReminder.cancel(id); reminded = false; return }
        Task { reminded = await AskReminder.schedule(id: id, title: title, on: date) }
    }
}

/// 追问: one choice per question, all sent together with 发送 as 「题目：选项」 lines.
/// The picks live here, so a tap redraws only this block.
private struct AskFollowUp: View {
    let questions: [PurchaseQuestion]
    let active: Bool
    let onSend: (String) -> Void
    @State private var picks: [String: String]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(questions: [PurchaseQuestion], active: Bool, onSend: @escaping (String) -> Void, picks: [String: String] = [:]) {
        self.questions = questions; self.active = active; self.onSend = onSend
        _picks = State(initialValue: picks)
    }

    private var complete: Bool { questions.allSatisfy { picks[$0.text] != nil } }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s12) {
            ForEach(questions, id: \.text) { question in
                VStack(alignment: .leading, spacing: .zero) {
                    Text(question.text).dsText(AskSpec.question).foregroundStyle(DS.Color.ink).fixedSize(horizontal: false, vertical: true)
                    AskFlow {
                        ForEach(question.options, id: \.self) { option in
                            AskChip(title: option, selected: picks[question.text] == option) { pick(option, for: question.text) }
                                .disabled(!active).accessibilityIdentifier("askChip_" + option)
                        }
                    }.padding(.top, AskSpec.chipRowTop)
                }
            }
            if active {
                Button(action: send) {
                    Text("发送").dsText(DS.Font.tLabelStrong).foregroundStyle(complete ? DS.Color.onAccent : DS.Color.ink3)
                        .frame(maxWidth: .infinity, minHeight: DS.Size.tapMin).dsPill(complete ? DS.Color.accent : DS.Color.surface)
                }.dsPressStyle().disabled(!complete).accessibilityIdentifier("askFollowSend")
            }
        }.padding(.top, AskSpec.followTop).padding(.horizontal, DS.Space.s4)
            .animation(reduceMotion ? nil : DSMotion.snappyAnimation, value: picks)
    }

    private func pick(_ option: String, for question: String) {
        picks[question] = picks[question] == option ? nil : option
    }

    private func send() {
        guard complete else { return }
        onSend(questions.compactMap { question in picks[question.text].map { question.text + "：" + $0 } }.joined(separator: "\n"))
    }
}

/// 审批卡 for any proposed change. Applied only on 确认; undone with the app's undo toast.
private struct AskApprovalView: View {
    let change: ChangeSet
    @Environment(AppStore.self) private var store

    var body: some View {
        let pending = store.current.pendingChanges.contains { $0.id == change.id }
        if pending {
            let card = YubaiCore.AskApproval.make(change, ledger: store.current, now: store.financialNow)
            let line = AskDisplay.change(card.change, hidden: store.preferences.hideAmounts, currency: true)
            AskApprovalCard(title: store.preferences.hideAmounts ? "余白的建议" : card.title, change: card.change.deferredTo == nil ? (line.label, line.from, line.to, card.change.better) : nil,
                            facts: store.preferences.hideAmounts ? [] : card.facts, action: card.action,
                            onEdit: { if let id = card.editEntryID { store.requestCaptureSheet(.editEntry(id)) } },
                            onConfirm: { confirm(card) })
        } else {
            AskDoneLine(text: change.items.contains { if case .linkRefund = $0 { return true }; return false } ? "已冲抵" : "已改好")
        }
    }

    private func confirm(_ card: YubaiCore.AskApproval) {
        // The generic entry toast would read 已记下 1 笔; this change is an offset.
        if store.apply(change.confirmingAmounts(), label: "问余白修改", silently: true) {
            store.toast = card.action == "确认" ? "已改好" : card.action.replacingOccurrences(of: "确认", with: "已")
        }
    }
}

/// The one-line result after a card is applied.
private struct AskDoneLine: View {
    let text: String
    var body: some View {
        Text(text).dsText(DS.Font.tLabel).foregroundStyle(DS.Color.accentInk)
            .frame(minHeight: DS.Size.tapMin).padding(.horizontal, DS.Space.s4)
            .accessibilityIdentifier("askDone")
    }
}

/// 批量记账: the drafts a reply proposed, each checked unless it looks like a duplicate.
private struct AskBatchCard: View {
    let change: ChangeSet
    @Environment(AppStore.self) private var store
    @State private var checked: Set<UUID>?
    @State private var savedCount: Int?

    private var drafts: [EntryDraft] {
        change.items.compactMap { if case .addEntry(let draft) = $0 { return draft }; return nil }
    }

    var body: some View {
        let pending = store.current.pendingChanges.contains { $0.id == change.id }
        if pending {
            let ledger = store.current, hide = store.preferences.hideAmounts
            let rows = drafts
            let selected = checked ?? AskBatch.initiallyChecked(drafts, in: ledger)
            let total = AskBatch.total(rows, checked: selected, in: ledger, now: store.financialNow)
            let line = AskDisplay.change(total, hidden: hide, currency: true)
            VStack(alignment: .leading, spacing: .zero) {
                VStack(spacing: .zero) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, draft in
                        AskBatchRow(name: draft.purpose ?? draft.title,
                                    detail: Classification.displayCategory(draft.category) + " · " + (draft.nature.inflow && draft.purpose != nil ? draft.title : AskDisplay.monthDay(draft.date, chinese: true)),
                                    amount: AskDisplay.signed(draft, hidden: hide), checked: selected.contains(draft.id),
                                    duplicate: AskBatch.isLikelyDuplicate(draft, in: ledger), income: draft.nature.inflow,
                                    separator: index > 0, onToggle: { toggle(draft.id, from: selected) })
                            .accessibilityIdentifier("askBatchRow_\(index)")
                    }
                }.padding(.top, -DS.Space.s4)
                // A batch dated after today leaves 还能花 where it is, so the line is left out.
                if total.deferredTo == nil {
                    AskChangeLine(label: line.label, from: line.from, to: line.to, toColor: DS.Color.accentInk)
                        .padding(.top, DS.Space.s12)
                        .overlay(alignment: .top) { DS.Color.ink.frame(height: DS.Stroke.hairline) }
                        .accessibilityIdentifier("askBatchTotal")
                }
                AskTwoButtons(primary: "记下 \(selected.count) 笔", enabled: !selected.isEmpty, onEdit: { edit(rows, selected: selected) },
                              onPrimary: { save(rows, selected: selected) })
            }.askCard().accessibilityElement(children: .contain).accessibilityIdentifier("askBatchCard")
        } else {
            AskDoneLine(text: "已记下 \(savedCount ?? drafts.count) 笔")
        }
    }

    private func toggle(_ id: UUID, from selected: Set<UUID>) {
        var next = selected
        if next.contains(id) { next.remove(id) } else { next.insert(id) }
        checked = next
    }

    private func edit(_ drafts: [EntryDraft], selected: Set<UUID>) {
        guard let first = drafts.first(where: { selected.contains($0.id) }) ?? drafts.first else { return }
        store.requestCaptureSheet(.prefilledEntry(.init(category: first.category, amount: first.amount, purpose: first.purpose ?? first.title,
                                                        nature: first.nature, subcategory: first.subcategory, accountID: first.accountID)))
    }

    private func save(_ drafts: [EntryDraft], selected: Set<UUID>) {
        let chosen = drafts.filter { selected.contains($0.id) }
        guard !chosen.isEmpty else { return }
        var confirmed = change
        confirmed.items = chosen.map { draft in var value = draft; value.amountConfirmed = true; return .addEntry(value) }
        if store.apply(confirmed, label: "问余白记下", finishing: { ledger in
            for draft in chosen where draft.categoryUserEdited == true && !Classification.isPending(draft.category) {
                try CategoryModel.confirm(.init(category: draft.category, subcategory: draft.subcategory), entryIDs: [draft.id], in: &ledger)
            }
        }) { savedCount = chosen.count }
    }
}

/// Code-only answers while AI is not connected.
private struct AskLocalCard: View {
    let answer: AskLocal.Answer
    let needsAI: Bool
    let openSettings: () -> Void
    @Environment(AppStore.self) private var store

    var body: some View {
        let hide = store.preferences.hideAmounts
        switch answer {
        case .budget(let budget):
            let warning = budget.fraction >= DSInteraction.warningFraction
            let tint = warning ? DS.Color.warnInk : DS.Color.ink
            VStack(alignment: .leading, spacing: .zero) {
                HStack(alignment: .firstTextBaseline) {
                    Text(budget.name + (budget.over > 0 ? "超出" : "还剩")).dsText(DS.Font.tLabel).foregroundStyle(tint)
                    Spacer(minLength: DS.Space.s8)
                    Text(HomeDisplay.money(budget.over > 0 ? budget.over : budget.remaining, hidden: hide)).dsText(DS.Font.nSpineLg).foregroundStyle(tint)
                }
                GeometryReader { proxy in
                    Capsule(style: .continuous).fill(DS.Color.track)
                        .overlay(alignment: .leading) {
                            Rectangle().fill(warning ? DS.Color.warn : DS.Color.fillCalm)
                                .frame(width: proxy.size.width * min(1, budget.fraction))
                        }.clipShape(Capsule(style: .continuous))
                }.frame(height: DS.Size.barAmber).padding(.top, AskSpec.barTop)
                HStack {
                    Text("已花 " + HomeDisplay.money(budget.spent, hidden: hide))
                    Spacer(minLength: DS.Space.s8)
                    Text("预算 " + HomeDisplay.money(budget.amount, hidden: hide))
                }.dsText(DS.Font.tCaption).monospacedDigit().foregroundStyle(DS.Color.ink3).padding(.top, AskSpec.rowsGap)
            }.askCard().accessibilityElement(children: .combine).accessibilityIdentifier("askBudgetCard")
        case let .purchase(_, _, _, lines):
            VStack(alignment: .leading, spacing: .zero) {
                VStack(spacing: AskSpec.rowsGap) {
                    ForEach(lines) { line in
                        HStack(alignment: .firstTextBaseline) {
                            Text(line.label).dsText(DS.Font.tPill).foregroundStyle(DS.Color.ink2).dsFillWidth()
                            Text(AskDisplay.value(line.to, hidden: hide)).dsText(AskSpec.number14Strong)
                                .foregroundStyle(line.overrun ? DS.Color.warnInk : DS.Color.ink)
                        }.accessibilityElement(children: .combine)
                    }
                }
                if needsAI { AskNeedsAIRow(openSettings: openSettings).padding(.top, AskSpec.buttonsTop) }
            }.askCard().accessibilityElement(children: .contain).accessibilityIdentifier("askPurchaseFacts")
        case .summary(let facts):
            VStack(alignment: .leading, spacing: AskSpec.rowsGap) {
                ForEach(facts, id: \.self) { Text(hide ? "金额已隐藏" : $0).dsText(AskSpec.body).monospacedDigit().foregroundStyle(DS.Color.ink) }
            }.askCard().accessibilityElement(children: .combine).accessibilityIdentifier("askSummary")
        }
    }
}

/// 「值不值，接上 AI 才能评」 + 去设置.
struct AskNeedsAIRow: View {
    let openSettings: () -> Void
    var body: some View {
        HStack(spacing: AskSpec.gap10) {
            Text("值不值，接上 AI 才能评").dsText(DS.Font.tPill).foregroundStyle(DS.Color.ink2).dsFillWidth()
            Button(action: openSettings) {
                Text("去设置").dsText(DS.Font.tSubStrong).foregroundStyle(DS.Color.ink)
                    .padding(.horizontal, DS.Space.s12).frame(height: AskSpec.goHeight)
                    .background(DS.Color.raised, in: Capsule(style: .continuous))
                    .overlay(Capsule(style: .continuous).strokeBorder(DS.Color.separator, lineWidth: DS.Stroke.hairline))
                    .frame(minHeight: DS.Size.tapMin).contentShape(Rectangle())
            }.dsPressStyle().accessibilityIdentifier("askGoSettings")
        }.padding(.vertical, AskSpec.insetAroundTap).padding(.horizontal, DS.Space.s12)
            .background(DS.Color.surface, in: .rect(cornerRadius: AskSpec.thumbRadius, style: .continuous))
    }
}

/// Number formatting for the cards. Values themselves come from YubaiCore.
enum AskDisplay {
    static func value(_ cents: Int64, hidden: Bool, currency: Bool = false) -> String {
        cents < 0 ? "超 " + HomeDisplay.money(-cents, hidden: hidden) : HomeDisplay.money(cents, hidden: hidden, currency: currency)
    }

    static func change(_ change: AskChange, hidden: Bool, currency: Bool = false) -> (label: String, from: String, to: String) {
        (change.label, HomeDisplay.money(change.from, hidden: hidden), value(change.to, hidden: hidden, currency: currency))
    }

    static func signed(_ draft: EntryDraft, hidden: Bool) -> String {
        guard !hidden else { return HomeDisplay.money(draft.amount, hidden: true) }
        return (draft.nature.inflow ? "+" : "-") + Money.text(draft.amount, currency: false)
    }

    static func monthDay(_ date: Date, chinese: Bool = false) -> String {
        let parts = Dates.calendar.dateComponents([.month, .day], from: date)
        return chinese ? "\(parts.month ?? 1)月\(parts.day ?? 1)日" : "\(parts.month ?? 1)." + String(format: "%02d", parts.day ?? 1)
    }
}

/// 「<date> 提醒我」: one local notification on the day the next cycle starts.
@MainActor enum AskReminder {
    static func schedule(id: String, title: String, on date: Date) async -> Bool {
        let center = UNUserNotificationCenter.current()
        guard (try? await center.requestAuthorization(options: [.alert])) == true else { return false }
        let content = UNMutableNotificationContent()
        content.title = "余白"; content.body = title
        var parts = Dates.calendar.dateComponents([.year, .month, .day], from: date); parts.hour = 9
        let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        return (try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))) != nil
    }

    static func cancel(_ id: String) { UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id]) }
}

#Preview("追问 · 两题已选") {
    AskFollowUp(questions: AskFixture.purchaseQuestions, active: true, onSend: { _ in },
                picks: ["现在用的耳机是哪里不满意？": "降噪不够", "一周戴几次？": "通勤才戴"])
        .padding(DS.Space.s16).background(DS.Color.bg)
}
