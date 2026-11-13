import SwiftUI
import YubaiCore
#if os(iOS)
import UIKit
#endif

struct QuickEntryView: View {
    var prefill: QuickEntryPrefill? = nil
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.scenePhase) private var scenePhase
    @State private var keypad = EntryKeypad()
    @State private var nature = Nature.expense
    @State private var category = ""
    @State private var subcategory: String?
    @State private var categoryHint: CategoryAssignment?
    @State private var recalls: [EntryHistory.Recall] = []
    @State private var purposeSuggestions: [EntryHistory.Recall] = []
    @State private var confirmingDiscard = false
    @State private var session = ContinuousEntrySession()
    @State private var showingAdded = false
    @State private var editingEntry: Entry?
    @State private var suspendedDraft: AddEntryDraftState?
    @State private var deletedEntryID: UUID?
    @State private var sessionToast: String?
    @State private var voiceOver = false
    @State private var purpose = ""
    @State private var accountID: UUID?
    @State private var otherAccountID: UUID?
    @State private var inlinePanel = AddEntryInlinePanel.none
    @State private var date = Date()
    @State private var loaded = false
    @State private var skipNatureReset = false
    @State private var balances: [UUID: Int64] = [:]
    @State private var suggestion: Occurrence?
    @State private var selectedMatchID: String?
    @State private var intoFixedSavings = false
    @State private var fromReserve = false
    @State private var previewAvailable: Int64 = 0
    @State private var big: BigPurchase?
    @FocusState private var purposeFocused: Bool
    private var accounts: [Account] { store.accounts.filter { !$0.archived || $0.id == prefill?.accountID || $0.id == prefill?.otherAccountID } }
    private var transferAccounts: [Account] { accounts.filter { $0.id != accountID } }
    private var amountCents: Int64 { keypad.amount ?? 0 }
    private var reserveTotal: Int64 { store.funds.fixedSavingsTotal }
    private var useReserve: Bool { nature == .expense && fromReserve && selectedLink == nil }
    private var isBig: Bool { nature == .expense && big != nil && selectedLink == nil }
    private var showsDestination: Bool { isBig || (nature == .expense && (fromReserve || prefill?.fromReserve == true)) }
    private var wishInHeader: Bool { isBig }
    private var reserveEnough: Bool { editingEntry != nil || !useReserve || amountCents <= reserveTotal }
    private var canSave: Bool {
        keypad.canSave && purpose.count <= 4000 && accountID != nil && reserveEnough
            && (nature != .transfer || (otherAccountID != nil && otherAccountID != accountID))
    }
    private var canWish: Bool { keypad.canSave && purpose.count <= 4000 }
    private var sessionEntries: [Entry] { session.entries(in: store.current) }
    private var requiresExplicitFinish: Bool {
        #if DEBUG && targetEnvironment(simulator)
        if UITestSupport.addEntryExplicitFinish { return true }
        #endif
        return voiceOver || reduceMotion
    }
    private var sessionSummary: String? {
        guard !session.entryIDs.isEmpty else { return nil }
        return "已记 \(sessionEntries.count) 笔 · " + amount2(session.total(in: store.current), hide: store.preferences.hideAmounts)
    }
    private var sheetHeight: CGFloat {
        if inlinePanel == .categories { return YubaiSize.entrySheet }
        if isBig { return YubaiSize.entrySheetBig }
        if purposeFocused || nature == .income { return YubaiSize.entrySheetCompact }
        return nature == .transfer ? YubaiSize.entrySheetTransfer : YubaiSize.entrySheet
    }

    var body: some View {
        content
            .animation(YubaiMotion.layout(reduceMotion: reduceMotion), value: purposeFocused)
            .yubaiFont(YubaiFont.body).foregroundStyle(YubaiColor.label)
            .environment(\.yubaiFormSurface, true).paperBackground().yubaiSheetBackground()
            #if os(iOS)
            .presentationDetents(textSize.isAccessibilitySize ? [.large] : [.height(sheetHeight), .large])
            .toolbar(.hidden, for: .navigationBar)
            .onReceive(NotificationCenter.default.publisher(for: UIAccessibility.voiceOverStatusDidChangeNotification)) { _ in
                voiceOver = UIAccessibility.isVoiceOverRunning
                if voiceOver { session.requireExplicitFinish() }
            }
            #endif
            .onAppear(perform: load)
            .onChange(of: store.current.updatedAt) { _, _ in refreshBalances() }
            .task(id: previewInput) { await refreshPreview() }
            .onChange(of: nature) { _, value in natureChanged(value) }
            .onChange(of: accountID) { _, id in
                if nature == .transfer && id == otherAccountID { otherAccountID = accounts.first { $0.id != id }?.id }
            }
            .onChange(of: purposeFocused) { _, focused in if focused { interact(); inlinePanel = .none } }
            .onChange(of: reduceMotion) { _, value in if value { session.requireExplicitFinish() } }
            .onChange(of: scenePhase) { _, value in if value != .active { session.requireExplicitFinish() } }
            .onChange(of: store.current.id) { _, _ in session.requireExplicitFinish(); dismiss() }
            .entryDiscardGuard(dirty: editingEntry == nil && dirty, amount: amountCents, confirming: $confirmingDiscard)
            .task(id: suggestionInput) { await refreshHints() }
            .task(id: session.deadline) { await closeAfterReceipt() }
    }
    @ViewBuilder private var content: some View {
        switch inlinePanel {
        case .categories:
            AddEntryCategories(income: nature.categoryIncome, selection: currentAssignment, suggested: categoryHint?.category,
                               cancel: { inlinePanel = .none }, choose: chooseCategory)
        case .newAccount(let destination):
            AddEntryAccountForm(cancel: { inlinePanel = .none }) { account in
                if destination { otherAccountID = account.id } else { accountID = account.id }
                inlinePanel = .none
            }
        default: composer
        }
    }
    private var composer: some View {
        EntryForm(title: editingEntry == nil ? "记一笔" : "改一笔", actionTitle: editingEntry != nil ? "好" : wishInHeader ? "放心愿单" : "导入", primary: false,
                  enabled: editingEntry != nil ? canSave : wishInHeader ? canWish : true,
                  actionIdentifier: editingEntry != nil ? "saveSessionEdit" : wishInHeader ? "saveEntryWish" : "importFromEntry",
                  cancelTitle: editingEntry != nil || session.entryIDs.isEmpty ? "取消" : "完成",
                  cancelIdentifier: "cancelManualSheet", cancel: cancel, save: headerAction,
                  headerSubtitle: editingEntry == nil ? sessionSummary : nil, subtitleAction: toggleAdded, compactHeader: true) {
            formContent
        }
        .safeAreaInset(edge: .bottom, spacing: YubaiSpace.none) {
            VStack(spacing: YubaiSpace.none) {
                if let sessionToast {
                    Toast(text: HomeButler.privacyText(sessionToast, hidden: store.preferences.hideAmounts), onUndo: deletedEntryID == nil ? nil : undoDeletion, onDismiss: { self.sessionToast = nil }).id(deletedEntryID)
                }
                bottomTray
            }
        }
    }

    // MARK: 内容

    @ViewBuilder private var formContent: some View {
        if accounts.isEmpty {
            EmptyAccountState { store.sheet = .account(nil) }
        } else {
            natureControl
            amountDisplay
            if showsDestination { destinationBlock }
            if !purposeFocused {
                ZStack(alignment: .top) {
                    VStack(spacing: YubaiSpace.gapGroup) {
                        resultBar.dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        categorySection
                    }
                    if showingAdded {
                        EntryAddedList(entries: sessionEntries, edit: editRecorded, remove: deleteRecorded)
                            .frame(maxHeight: YubaiSize.inlineListMaximum).zIndex(1)
                    }
                }
            }
            if editingEntry == nil, let suggestion { matchChip(suggestion) }
        }
    }
    @ViewBuilder private var natureControl: some View {
        if [.expense, .income, .transfer].contains(nature) {
            Segmented(choices: [(Nature.expense, "支出"), (.income, "收入"), (.transfer, "转账")], selection: Binding(get: { nature }, set: { interact(); nature = $0 }),
                          identifier: { "entryNature_" + $0.rawValue })
        } else {
            Text(nature.entryLabel).yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary)
        }
    }
    private var amountDisplay: some View {
        EditableAmountDisplay(amount: keypad.resultText, keypad: keypad, presented: true, selected: false,
                              identifier: "entryKeypadAmount", open: { interact(); purposeFocused = false; inlinePanel = .none },
                              hide: store.preferences.hideAmounts, ink: amountCents == 0 ? YubaiColor.labelSecondary : nature.inflow ? YubaiColor.brandInk : nil)
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            #if os(iOS)
            .contextMenu { Button("粘贴") { pasteAmount() }.accessibilityIdentifier("pasteEntryAmount") }
            #endif
    }
    /// 大件：一行换算和「算这个月的 / 从存着的钱出」。
    private var destinationBlock: some View {
        VStack(alignment: .leading, spacing: YubaiSpace.space8) {
            if let big {
                Text("约 \(big.days) 天的日常").yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary)
                    .accessibilityIdentifier("bigPurchaseDays")
            }
            Segmented(choices: [(false, "算这个月的"), (true, "从存着的钱出")], selection: Binding(get: { fromReserve }, set: { interact(); fromReserve = $0 }),
                          identifier: { $0 ? "bigFromReserve" : "bigFromCycle" })
        }
    }
    @ViewBuilder private var resultBar: some View {
        let hide = store.preferences.hideAmounts
        let compact = textSize.isAccessibilitySize
        if nature == .transfer {
            VStack(spacing: YubaiSpace.space8) {
                EntryTransferCards(accounts: accounts, balances: balances, from: $accountID, to: $otherAccountID,
                                   fallback: AnyView(addTransferAccountChip), selectAccount: openAccounts)
                ResultBar(label: "还能花", value: "不变", identifier: "entrySavingHint")
            }
        } else if editingEntry != nil {
            ResultBar(label: "改完还能花", value: amount2(previewAvailable, hide: hide), identifier: "entrySavingHint")
        } else if let totals = fixedSavingsTotals {
            ResultBar(label: "存下的钱", value: compact ? amount2(totals.new, hide: hide) : ResultBar.change(totals.current, totals.new, hide: hide),
                      identifier: "entrySavingHint")
        } else if useReserve {
            let after = Dates.day(date) > Dates.day(store.financialNow) ? reserveTotal : reserveTotal - amountCents
            ResultBar(label: "存着的钱", value: compact ? amount2(after, hide: hide) : ResultBar.change(reserveTotal, after, hide: hide),
                      amber: after < 0, identifier: "entrySavingHint")
        } else if isBig, let big {
            let daily = big.dailyAfter.map { " · 日均 " + amount2($0, hide: hide) } ?? ""
            let value = amount2(big.availableAfter, hide: hide) + (compact ? "" : daily)
            ResultBar(label: "记下后还能花", value: value, amber: big.tight, identifier: "entrySavingHint")
        } else {
            let before = store.funds.available
            ResultBar(label: session.receiptVisible ? "还能花" : "记下后还能花", value: compact || session.receiptVisible ? amount2(previewAvailable, hide: hide) : ResultBar.change(before, previewAvailable, hide: hide),
                      identifier: "entrySavingHint")
        }
    }
    @ViewBuilder private var categorySection: some View {
        if nature == .expense {
            EntryCategoryGrid(nature: nature, selection: currentAssignment, hint: categoryHint?.category,
                              choose: chooseCategory, more: openCategories)
        } else if nature == .income {
            AddEntryIncomeChips(selection: currentAssignment, hint: categoryHint?.category, choose: chooseCategory, more: openCategories)
        }
    }
    private var currentAssignment: CategoryAssignment { CategoryAssignment(category: category, subcategory: subcategory) }

    // MARK: 键盘上方

    private var bottomTray: some View {
        Group {
            if !accounts.isEmpty {
                EntryKeyboardTray(purpose: Binding(get: { purpose }, set: { interact(); purpose = $0 }), focus: $purposeFocused, compact: true) { trayControls } keys: {
                    if inlinePanel == .calendar {
                        AddEntryCalendar(date: $date, done: { inlinePanel = .none })
                    } else { keypadBlock }
                }
            }
        }
    }
    @ViewBuilder private var trayControls: some View {
        if purposeFocused {
            if purpose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: YubaiSpace.space8) {
                        ForEach(purposeSuggestions) { item in
                            CategoryChoiceChip(title: item.purpose) { recall(item) }
                                .accessibilityIdentifier("suggestPurpose_" + item.purpose)
                        }
                    }
                }
            } else if !recalls.isEmpty {
                ScrollView { EntryRecallList(recalls: recalls, choose: recall) }
                    .frame(maxHeight: textSize.isAccessibilitySize ? YubaiSize.entryInlineHistoryLarge : YubaiSize.entryInlineHistory)
            }
        } else if case .accounts(let destination) = inlinePanel {
            AddEntryAccountChips(accounts: destination ? transferAccounts : accounts, selection: destination ? otherAccountID : accountID) { id in
                if destination { otherAccountID = id } else { accountID = id }
                inlinePanel = .none
            }
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: YubaiSpace.space8) {
                    EntryDayChips(date: Binding(get: { date }, set: { interact(); date = $0 }), pick: { interact(); purposeFocused = false; inlinePanel = .calendar })
                    Rectangle().fill(YubaiColor.grabber).frame(width: YubaiSize.separator, height: YubaiSize.headerIcon).accessibilityHidden(true)
                    Button { openAccounts(false) } label: {
                        Text(store.accountName(accountID)).lineLimit(1)
                            .yubaiFont(YubaiFont.callout).padding(.horizontal, YubaiSpace.gapGroup).frame(minHeight: YubaiSize.trayChip)
                            .background(YubaiColor.keyFn, in: Capsule()).yubaiHitTarget()
                    }.buttonStyle(PressButtonStyle()).accessibilityLabel("账户").accessibilityValue(store.accountName(accountID))
                        .accessibilityIdentifier("entryAccountChip")
                }.padding(.horizontal, YubaiSpace.space2)
            }
        }
    }
    private var keypadBlock: some View {
        AmountKeypad(keypad: $keypad, canSave: canSave, primaryTitle: editingEntry == nil ? "记下" : "好", primaryIdentifier: "saveQuickEntry",
                     save: save, embedded: true, receiptVisible: session.receiptVisible && editingEntry == nil,
                     receiptDeadline: session.deadline, interaction: interact)
    }

    // MARK: 状态

    private func load() {
        guard !loaded else { return }; loaded = true
        #if os(iOS)
        voiceOver = UIAccessibility.isVoiceOverRunning
        #endif
        if store.accounts.isEmpty || !store.preferences.onboardingComplete {
            _ = store.update("开始记账", recordUndo: false, entryMotion: false, showToast: false) { FirstUse.prepareForEntry(&$0, now: Date()) }
        }
        accountID = ManualBookkeeping.defaultAccount(in: store.current)?.id
        if let prefill {
            skipNatureReset = (prefill.nature ?? .expense) != nature
            nature = prefill.nature ?? .expense
            if let selected = prefill.category, !Classification.isPending(selected) { category = selected }
            subcategory = prefill.subcategory
            if let id = prefill.accountID, accounts.contains(where: { $0.id == id }) { accountID = id }
            otherAccountID = prefill.otherAccountID
            intoFixedSavings = nature == .income && prefill.intoFixedSavings
            fromReserve = nature == .expense && prefill.fromReserve
            purpose = prefill.purpose ?? ""
            if let day = prefill.date { date = day }
            if let amount = prefill.amount { keypad.reset(); Money.input(amount).forEach { keypad.press(String($0)) } }
        }
        previewAvailable = store.funds.available
        refreshBalances()
    }
    private func natureChanged(_ value: Nature) {
        if value != .income { intoFixedSavings = false }
        if value != .expense { fromReserve = false; big = nil }
        if skipNatureReset { skipNatureReset = false; return }
        category = ""; categoryHint = nil; subcategory = nil
        if value == .transfer { otherAccountID = accounts.first { $0.id != accountID }?.id }
    }
    private var effectiveCategory: CategoryAssignment {
        if nature == .transfer { return .init(category: "内部移动") }
        return category.isEmpty ? .init(category: Classification.pendingCategory) : .init(category: category, subcategory: subcategory)
    }
    private var suggestionInput: String { "\(store.ledgerRevision)-\(nature.rawValue)-\(category)-\(purpose)" }
    private var dirty: Bool { loaded && (amountCents != 0 || !purpose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || prefill?.screenshot != nil) }
    private func cancel() {
        session.requireExplicitFinish()
        if editingEntry != nil { restoreDraft(); return }
        if dirty { confirmingDiscard = true } else { dismiss() }
    }
    private func headerAction() {
        interact()
        if editingEntry != nil { save(); return }
        if wishInHeader { saveWish(); return }
        store.homeEntrySession = false
        store.sheetSource = nil; store.sheet = prefill?.screenshot.map(AppSheet.screenshotReview) ?? .imports
    }
    @MainActor private func refreshHints() async {
        let ledger = store.current; let text = purpose; let kind = nature; let at = Date(); let chosen = category.isEmpty ? nil : category
        let found = await Task.detached { (EntryHistory.categoryHint(purpose: text, nature: kind, in: ledger, now: at),
                                          EntryHistory.recalls(matching: text, nature: kind, in: ledger, now: at),
                                          EntryHistory.purposeSuggestions(nature: kind, category: chosen, in: ledger, now: at)) }.value
        guard !Task.isCancelled else { return }
        categoryHint = found.0; recalls = found.1; purposeSuggestions = found.2
    }
    /// 点了记过的用途：分类、金额一起填上并选中。
    private func recall(_ item: EntryHistory.Recall) {
        interact()
        let entry = item.entry
        let assignment = store.current.normalizedCategory(for: entry)
        purpose = item.purpose
        category = Classification.isPending(assignment.category) ? "" : assignment.category
        subcategory = category.isEmpty ? nil : assignment.subcategory
        keypad = EntryKeypad(amount: entry.amount)
        purposeFocused = false
    }
    private func matchChip(_ match: Occurrence) -> some View {
        let selected = selectedMatchID == match.id
        let question: String = selected ? "已选 · \(match.title)这期" : "是\(match.title)这期吗"
        let label: String = question + " · " + FixedFlowPresentation.monthDay(match.date)
        return Button { purposeFocused = false; selectedMatchID = selected ? nil : match.id } label: {
            HStack(spacing: YubaiSpace.space8) {
                if selected { Image(systemName: "checkmark") }
                Text(label)
            }.yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.amberStrong)
                .padding(.horizontal, YubaiSpace.gapGroup).padding(.vertical, YubaiSpace.space8).background(YubaiColor.amberTint, in: Capsule())
                .overlay { if selected { Capsule().strokeBorder(YubaiColor.amberDot, lineWidth: YubaiSize.separator) } }
                .frame(minHeight: YubaiSize.tapMin).contentShape(Capsule())
        }.buttonStyle(PressButtonStyle()).accessibilityIdentifier("fixedFlowSuggestion")
            .accessibilityAddTraits(selected ? .isSelected : []).accessibilityHint(selected ? "再点取消关联" : "关联这期账单")
    }
    private var selectedLink: (planID: UUID, occurrence: Date)? {
        guard let suggestion, suggestion.id == selectedMatchID, let id = suggestion.planID else { return nil }
        return (id, suggestion.date)
    }
    private struct PreviewInput: Equatable {
        var expression: String; var nature: Nature; var purpose: String; var category: String
        var subcategory: String?
        var date: Date; var accountID: UUID?; var otherAccountID: UUID?
        var selectedMatchID: String?; var intoFixedSavings: Bool; var fromReserve: Bool; var ledgerUpdatedAt: Date
    }
    private var previewInput: PreviewInput {
        PreviewInput(expression: keypad.expression, nature: nature, purpose: purpose, category: category, subcategory: subcategory, date: date,
                     accountID: accountID, otherAccountID: otherAccountID, selectedMatchID: selectedMatchID,
                     intoFixedSavings: intoFixedSavings, fromReserve: fromReserve, ledgerUpdatedAt: store.current.updatedAt)
    }
    @MainActor private func refreshPreview() async {
        // No ledger work runs in body or the key action. Cancellation coalesces
        // quick input; the expensive unchanged Core calculations run off-main.
        do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
        guard !Task.isCancelled else { return }
        let ledger = store.current; let now = Date(); let fallback = store.funds.available
        let amount = amountCents; let nature = self.nature; let purpose = self.purpose; let day = date; let account = accountID
        let change = canSave && editingEntry == nil ? (try? draftChange(now: now)) : nil
        let edited = editingEntry.map { makeRecordedEdit($0, now: now) }
        let result = await Task.detached(priority: .userInitiated) {
            let match = FixedFlows.suggestions(amount: amount, nature: nature, purpose: purpose, day: day, accountID: account, in: ledger).first
            let available = edited.flatMap { try? ManualBookkeeping.available(after: $0, in: ledger, now: now) }
                ?? change.flatMap { try? ManualBookkeeping.available(after: $0, in: ledger, now: now) } ?? fallback
            let large = nature == .expense && amount > 0 && Dates.day(day) <= Dates.day(now) ? Finance.bigPurchase(ledger, amount: amount, now: now) : nil
            return (match, available, large)
        }.value
        guard !Task.isCancelled else { return }
        if result.0?.id != suggestion?.id { selectedMatchID = nil }
        suggestion = result.0; previewAvailable = result.1; big = result.2
    }
    private var fixedSavingsTotals: (current: Int64, new: Int64)? {
        guard nature == .income, intoFixedSavings else { return nil }
        if Dates.day(date) > Dates.day(store.financialNow) { return (reserveTotal, reserveTotal) }
        let draft = EntryDraft(date: date, amount: amountCents, nature: nature, accountID: accountID ?? UUID(),
                               title: purpose, category: effectiveCategory.category, intoFixedSavings: true)
        if case .fixedSavings(let total) = EntryHint.make(ledger: store.current, draft: draft, isFixedBill: selectedLink != nil) {
            return (store.funds.fixedSavingsTotal, total)
        }
        return nil
    }
    private func saveWish() {
        guard canWish, let amount = keypad.amount else { return }
        let clean = purpose.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = clean.isEmpty ? Classification.displayCategory(effectiveCategory.category) : clean
        let now = Date()
        if store.update("心愿单", entryMotion: false, showToast: false, { ledger in
            let verdict = SubmittedPurchaseVerdict(verdict: .wait, reason: "放心愿单", need: .want, boundReason: "")
            _ = try Wishlist.add(fromVerdict: verdict, title: title, amount: amount, category: effectiveCategory.category,
                                        subcategory: effectiveCategory.subcategory, purpose: purpose, in: &ledger, now: now)
        }) {
            store.toast = "放进心愿单了" + (title.count <= 12 ? " " + title : "") + " " + amount2(amount, hide: store.preferences.hideAmounts)
            dismiss()
        }
    }
    private var addTransferAccountChip: some View {
        Button {
            interact(); purposeFocused = false; inlinePanel = .newAccount(destination: true)
        } label: {
            HStack(spacing: YubaiSpace.space4) {
                Image(systemName: "plus")
                Text("添加账户")
            }.yubaiFont(YubaiFont.callout, weight: .medium).foregroundStyle(YubaiColor.brandInk)
                .padding(.horizontal, YubaiSpace.gapGroup).frame(minHeight: YubaiSize.chipHeight)
                .background(YubaiColor.raised, in: Capsule()).yubaiHitTarget()
        }.buttonStyle(PressButtonStyle()).accessibilityIdentifier("transferAddAccount").accessibilityLabel("添加账户")
    }
    private func draftChange(now: Date) throws -> ChangeSet {
        guard let accountID, let amount = keypad.amount else { throw YubaiError.invalid("请选择账户并填写金额。") }
        var change = try ManualBookkeeping.change(amount: amount, nature: nature, accountID: accountID, otherAccountID: otherAccountID,
                                                  day: date, purpose: purpose, category: effectiveCategory.category, link: selectedLink, now: now,
                                                  intoFixedSavings: intoFixedSavings, fromReserve: useReserve)
        if nature != .transfer {
            let chosen = effectiveCategory
            let known = !Classification.isPending(chosen.category)
            let blank = purpose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            change.items = change.items.map { item in
                guard case .addEntry(var draft) = item else { return item }
                if blank { draft.title = Classification.displayCategory(draft.category) }
                draft.partID = nil
                draft.otherAccountID = nature.paired ? otherAccountID : nil
                draft.subcategory = chosen.subcategory; draft.categoryUserEdited = known
                return .addEntry(draft)
            }
        }
        return change
    }
    private func refreshBalances() {
        balances = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, Finance.balance($0, in: store.current)) })
    }
    private func save() {
        guard canSave else { return }
        if editingEntry != nil { saveRecordedEdit(); return }
        _ = keypad.resolve(); purposeFocused = false
        // Saving may beat the debounce. Revalidate the user's selected match
        // against the final input before constructing its linked payment.
        let match = FixedFlows.suggestions(amount: amountCents, nature: nature, purpose: purpose, day: date,
                                           accountID: accountID, in: store.current).first
        if match?.id != suggestion?.id { selectedMatchID = nil }
        suggestion = match
        do {
            let change = try draftChange(now: Date())
            guard store.apply(change, label: "记一笔", silently: true, finishing: { ledger in
                for case .addEntry(let draft) in change.items where draft.categoryUserEdited == true && !Classification.isPending(draft.category) {
                    let choice = CategoryAssignment(category: draft.category, subcategory: draft.subcategory)
                    if SubcategoryClassifier.valid(choice, in: ledger, nature: draft.nature) { try CategoryModel.confirm(choice, entryIDs: [draft.id], in: &ledger) }
                }
            }) else { return }
            finishSaved(change)
        } catch { store.error = error.localizedDescription }
    }
    private func finishSaved(_ change: ChangeSet) {
        let ids = change.items.compactMap { item -> UUID? in
            guard case .addEntry(let draft) = item else { return nil }; return draft.id
        }
        store.acknowledgeEntryInEditor(ids)
        session.saved(ids, at: Date(), explicitFinish: requiresExplicitFinish)
        showingAdded = false; inlinePanel = .none
        keypad.reset(); purpose = ""; selectedMatchID = nil; suggestion = nil
        categoryHint = nil; big = nil; fromReserve = false; intoFixedSavings = false
        previewAvailable = store.funds.available
        #if os(iOS)
        AccessibilityNotification.Announcement("已记 \(sessionEntries.count) 笔").post()
        #endif
    }
    private func interact() {
        session.interact(); showingAdded = false
    }
    private func toggleAdded() {
        session.interact(); purposeFocused = false
        showingAdded.toggle()
    }
    private func openCategories() {
        interact(); purposeFocused = false; inlinePanel = .categories
    }
    private func chooseCategory(_ choice: CategoryAssignment?) {
        interact(); category = choice?.category ?? ""; subcategory = choice?.subcategory
        purposeFocused = false; inlinePanel = .none
    }
    private func openAccounts(_ destination: Bool) {
        interact(); purposeFocused = false; inlinePanel = .accounts(destination: destination)
    }
    @MainActor private func closeAfterReceipt() async {
        guard let deadline = session.deadline else { return }
        do { try await Task.sleep(for: .seconds(max(0, deadline.timeIntervalSinceNow))) } catch { return }
        guard !Task.isCancelled, session.shouldDismiss(at: Date()), !voiceOver, !reduceMotion else { return }
        dismiss()
    }
    #if os(iOS)
    private func pasteAmount() {
        interact(); purposeFocused = false
        guard let text = UIPasteboard.general.string else { return }
        do { try keypad.paste(text) } catch { store.error = error.localizedDescription }
    }
    #endif
    private func editRecorded(_ entry: Entry) {
        session.interact(); showingAdded = false; purposeFocused = false
        suspendedDraft = AddEntryDraftState(keypad: keypad, nature: nature, category: category, subcategory: subcategory,
                                            purpose: purpose, accountID: accountID, otherAccountID: otherAccountID, date: date,
                                            fromReserve: fromReserve, intoFixedSavings: intoFixedSavings, suggestion: suggestion, selectedMatchID: selectedMatchID)
        editingEntry = entry
        if nature != entry.nature { skipNatureReset = true; nature = entry.nature }
        keypad = EntryKeypad(amount: entry.amount); category = entry.category; subcategory = entry.subcategory
        purpose = entry.displayTitle; date = entry.date; accountID = entry.accountID; otherAccountID = entry.otherAccountID
        fromReserve = entry.fromReserve; intoFixedSavings = entry.intoFixedSavings
        inlinePanel = .none; suggestion = nil; selectedMatchID = nil
    }
    private func makeRecordedEdit(_ original: Entry, now: Date) -> Entry {
        var entry = original
        entry.amount = amountCents; entry.nature = nature; entry.date = ManualBookkeeping.saveDate(for: date, now: now)
        entry.accountID = accountID ?? original.accountID
        entry.otherAccountID = nature.paired ? otherAccountID : nil
        let text = purpose.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.title = text.isEmpty ? Classification.displayCategory(effectiveCategory.category) : text
        entry.purpose = text.isEmpty ? nil : text
        entry.category = effectiveCategory.category; entry.subcategory = effectiveCategory.subcategory
        entry.subcategoryUserEdited = true
        entry.partID = nil; entry.fromReserve = useReserve; entry.intoFixedSavings = nature == .income && intoFixedSavings
        return entry
    }
    private func saveRecordedEdit() {
        guard let original = editingEntry, canSave else { return }
        let edited = makeRecordedEdit(original, now: Date())
        if store.update("改一笔", entryMotion: false, showToast: false, { ledger in
            try ManualBookkeeping.edit(edited, in: &ledger)
        }) { restoreDraft() }
    }
    private func restoreDraft() {
        guard let draft = suspendedDraft else { return }
        if nature != draft.nature { skipNatureReset = true; nature = draft.nature }
        keypad = draft.keypad; category = draft.category; subcategory = draft.subcategory; purpose = draft.purpose
        accountID = draft.accountID; otherAccountID = draft.otherAccountID; date = draft.date
        fromReserve = draft.fromReserve; intoFixedSavings = draft.intoFixedSavings
        suggestion = draft.suggestion; selectedMatchID = draft.selectedMatchID
        editingEntry = nil; suspendedDraft = nil; inlinePanel = .none; showingAdded = true
        previewAvailable = store.funds.available
    }
    private func deleteRecorded(_ entry: Entry) {
        session.interact()
        if store.update("删掉", recordUndo: false, entryMotion: false, showToast: false, { ledger in
            guard let index = ledger.entries.firstIndex(where: { $0.id == entry.id && $0.deletedAt == nil }) else { return }
            ledger.entries[index].deletedAt = Date()
        }) { deletedEntryID = entry.id; sessionToast = "已删掉" }
    }
    private func undoDeletion() {
        guard let id = deletedEntryID else { return }
        if store.update("撤销", recordUndo: false, entryMotion: false, showToast: false, { ledger in
            try RecentlyDeleted.restore(id, in: &ledger)
        }) { deletedEntryID = nil; sessionToast = "已撤销" }
    }
}

private struct AddEntryDraftState {
    var keypad: EntryKeypad; var nature: Nature; var category: String; var subcategory: String?
    var purpose: String; var accountID: UUID?; var otherAccountID: UUID?; var date: Date
    var fromReserve: Bool; var intoFixedSavings: Bool
    var suggestion: Occurrence?; var selectedMatchID: String?
}
