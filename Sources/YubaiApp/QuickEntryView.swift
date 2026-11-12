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
    @State private var keypad = EntryKeypad()
    @State private var nature = Nature.expense
    @State private var category = ""
    @State private var subcategory: String?
    @State private var categoryHint: CategoryAssignment?
    @State private var recalls: [EntryHistory.Recall] = []
    @State private var confirmingDiscard = false
    @State private var addedRows: [EntryAddedRow] = []
    @State private var addedDay = Date()
    @State private var purpose = ""
    @State private var accountID: UUID?
    @State private var otherAccountID: UUID?
    @State private var showingTransferAccountEditor = false
    @State private var showingMoreCategories = false
    @State private var accountIDsBeforeAdding: Set<UUID> = []
    @State private var date = Date()
    @State private var loaded = false
    @State private var skipNatureReset = false
    @State private var balances: [UUID: Int64] = [:]
    @State private var suggestion: Occurrence?
    @State private var selectedMatchID: String?
    @State private var intoFixedSavings = false
    @State private var fromReserve = false
    @State private var repeatsMonthly = false
    @State private var previewAvailable: Int64 = 0
    @State private var big: BigPurchase?
    @FocusState private var purposeFocused: Bool
    private var accounts: [Account] { store.accounts.filter { !$0.archived || $0.id == prefill?.accountID || $0.id == prefill?.otherAccountID } }
    private var transferAccounts: [Account] { accounts.filter { $0.id != accountID } }
    private var amountCents: Int64 { keypad.amount ?? 0 }
    private var reserveTotal: Int64 { store.funds.fixedSavingsTotal }
    private var useReserve: Bool { nature == .expense && fromReserve && !repeatsMonthly && selectedLink == nil }
    private var isBig: Bool { nature == .expense && big != nil && !repeatsMonthly && selectedLink == nil }
    private var showsDestination: Bool { isBig || (nature == .expense && (fromReserve || prefill?.fromReserve == true)) }
    private var wishInHeader: Bool { isBig }
    private var reserveEnough: Bool { !useReserve || amountCents <= reserveTotal }
    private var canSave: Bool {
        keypad.canSave && purpose.count <= 4000 && accountID != nil && reserveEnough
            && (nature != .transfer || (otherAccountID != nil && otherAccountID != accountID))
    }

    var body: some View {
        EntryForm(title: "记一笔", actionTitle: wishInHeader ? "放心愿单" : "导入", primary: false,
                  enabled: wishInHeader ? canSave : true,
                  actionIdentifier: wishInHeader ? "saveEntryWish" : "importFromEntry",
                  cancelTitle: addedRows.isEmpty ? "取消" : "完成", cancel: cancel, save: headerAction) {
            formContent
        }
        .safeAreaInset(edge: .bottom, spacing: YubaiSpace.none) { bottomTray }
        .animation(YubaiMotion.layout(reduceMotion: reduceMotion), value: purposeFocused)
        .yubaiFont(YubaiFont.body).foregroundStyle(YubaiColor.label)
        .environment(\.yubaiFormSurface, true).paperBackground().yubaiSheetBackground()
        #if os(iOS)
        .presentationDetents([.large])
        .toolbar(.hidden, for: .navigationBar)
        #endif
        .sheet(isPresented: $showingTransferAccountEditor, onDismiss: selectAddedTransferAccount) {
            NavigationStack { AccountEditor(account: nil) }
                .environment(store).tint(YubaiColor.brandInk).appErrors()
                .presentationDragIndicator(.visible).yubaiSheetBackground().frame(minWidth: 340, minHeight: 520)
        }
        .sheet(isPresented: $showingMoreCategories) { moreCategorySheet }
        .onAppear(perform: load)
        .onChange(of: store.current.updatedAt) { _, _ in refreshBalances() }
        .task(id: previewInput) { await refreshPreview() }
        .onChange(of: nature) { _, value in natureChanged(value) }
        .onChange(of: accountID) { _, id in
            if nature == .transfer && id == otherAccountID { otherAccountID = accounts.first { $0.id != id }?.id }
        }
        .entryDiscardGuard(dirty: dirty, amount: amountCents, confirming: $confirmingDiscard)
        .task(id: suggestionInput) { await refreshHints() }
    }

    // MARK: 内容

    @ViewBuilder private var formContent: some View {
        if accounts.isEmpty {
            EmptyAccountState { store.sheet = .account(nil) }
        } else {
            if !addedRows.isEmpty { EntryAddedList(dayTitle: ManualBookkeeping.dayLabel(addedDay), rows: addedRows) }
            natureControl
            amountDisplay
            if showsDestination { destinationBlock }
            resultBar
            categorySection
            if let suggestion { matchChip(suggestion) }
        }
    }
    @ViewBuilder private var natureControl: some View {
        if [.expense, .income, .transfer].contains(nature) {
            SegmentedWide(choices: [(Nature.expense, "支出"), (.income, "收入"), (.transfer, "转账")], selection: $nature,
                          identifier: { "entryNature_" + $0.rawValue })
        } else {
            Text(nature.entryLabel).yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary)
        }
    }
    private var amountDisplay: some View {
        EditableAmountDisplay(amount: keypad.resultText, keypad: keypad, presented: true, selected: false,
                              identifier: "entryKeypadAmount", open: { purposeFocused = false })
    }
    /// 大件：一行换算和「算这个月的 / 从存着的钱出」。
    private var destinationBlock: some View {
        VStack(alignment: .leading, spacing: YubaiSpace.space8) {
            if let big {
                Text("约 \(big.days) 天的日常").yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary)
                    .accessibilityIdentifier("bigPurchaseDays")
            }
            SegmentedWide(choices: [(false, "算这个月的"), (true, "从存着的钱出")], selection: $fromReserve,
                          identifier: { $0 ? "bigFromReserve" : "bigFromCycle" })
        }
    }
    @ViewBuilder private var resultBar: some View {
        let hide = store.preferences.hideAmounts
        let compact = textSize.isAccessibilitySize
        if nature == .transfer {
            ResultBar(label: "还能花", value: "不变", identifier: "entrySavingHint")
        } else if let totals = fixedSavingsTotals {
            ResultBar(label: "存着不动", value: compact ? amount2(totals.new, hide: hide) : ResultBar.change(totals.current, totals.new, hide: hide),
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
            ResultBar(label: "记下后还能花", value: compact ? amount2(previewAvailable, hide: hide) : ResultBar.change(before, previewAvailable, hide: hide),
                      identifier: "entrySavingHint")
        }
    }
    @ViewBuilder private var categorySection: some View {
        if nature == .expense {
            EntryCategoryGrid(nature: nature, selection: currentAssignment, hint: categoryHint?.category,
                              choose: { choice in
                                  category = choice?.category ?? ""; subcategory = choice?.subcategory; purposeFocused = false
                              }, more: { purposeFocused = false; showingMoreCategories = true })
                .simultaneousGesture(TapGesture().onEnded { purposeFocused = false })
        } else if nature == .income {
            EntryCategoryChips(frequent: ManualBookkeeping.categories(in: store.current, nature: nature, frequentOnly: true),
                               income: true, selection: category.isEmpty ? (categoryHint ?? currentAssignment) : currentAssignment,
                               suggestionOnly: category.isEmpty, allowsDirectionChange: false,
                               suggest: { categoryHint?.category }) { choice in
                category = choice.category; subcategory = choice.subcategory; purposeFocused = false
            }.simultaneousGesture(TapGesture().onEnded { purposeFocused = false })
        } else if nature == .transfer {
            EntryTransferCards(accounts: accounts, balances: balances, from: $accountID, to: $otherAccountID,
                               fallback: AnyView(addTransferAccountChip))
        }
    }
    private var currentAssignment: CategoryAssignment { CategoryAssignment(category: category, subcategory: subcategory) }
    private var moreCategorySheet: some View {
        EntryMoreCategorySheet(income: nature == .income, selection: currentAssignment, suggested: categoryHint?.category,
                               choose: { choice in
                                   category = choice.category; subcategory = choice.subcategory; showingMoreCategories = false
                               }, dismiss: { showingMoreCategories = false })
    }

    // MARK: 键盘上方

    private var bottomTray: some View {
        Group {
            if !accounts.isEmpty {
                EntryKeyboardTray(purpose: $purpose, focus: $purposeFocused) { trayControls } keys: { keypadBlock }
            }
        }
    }
    @ViewBuilder private var trayControls: some View {
        if purposeFocused && !recalls.isEmpty && !purpose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            EntryRecallList(recalls: recalls, choose: recall)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: YubaiSpace.space8) {
                    EntryDayChips(date: $date, allowsFuture: true)
                    Rectangle().fill(YubaiColor.grabber).frame(width: 1, height: 20).accessibilityHidden(true)
                    EntryAccountMenu(accounts: accounts, balances: balances, selection: $accountID, inTray: true, identifier: "entryAccountChip")
                    if nature == .income { EntryFixedSavingsChip(selected: $intoFixedSavings, action: { purposeFocused = false }) }
                    if nature != .transfer && selectedLink == nil {
                        EntryRepeatChip(selected: repeatsMonthly, value: repeatsMonthly ? "每月 \(Dates.calendar.component(.day, from: date)) 号" : "不重复", inTray: true) {
                            purposeFocused = false; repeatsMonthly.toggle()
                        }
                    }
                }.padding(.horizontal, YubaiSpace.space2)
            }
        }
    }
    private var keypadBlock: some View {
        AmountKeypad(keypad: $keypad, canSave: canSave, primaryTitle: "记下", primaryIdentifier: "saveQuickEntry",
                     save: save, embedded: true)
    }

    // MARK: 状态

    private func load() {
        guard !loaded else { return }; loaded = true
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
    private var suggestionInput: String { "\(store.ledgerRevision)-\(nature.rawValue)-\(purpose)" }
    private var dirty: Bool { loaded && (amountCents != 0 || !purpose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || prefill?.screenshot != nil) }
    private func cancel() { if dirty { confirmingDiscard = true } else { dismiss() } }
    private func headerAction() {
        if wishInHeader { saveWish(); return }
        store.sheetSource = nil; store.sheet = prefill?.screenshot.map(AppSheet.screenshotReview) ?? .imports
    }
    @MainActor private func refreshHints() async {
        let ledger = store.current; let text = purpose; let kind = nature; let at = Date()
        let found = await Task.detached { (EntryHistory.categoryHint(purpose: text, nature: kind, in: ledger, now: at),
                                          EntryHistory.recalls(matching: text, nature: kind, in: ledger, now: at)) }.value
        guard !Task.isCancelled else { return }
        categoryHint = found.0; recalls = found.1
    }
    /// 点了记过的用途：分类、金额一起填上并选中。
    private func recall(_ item: EntryHistory.Recall) {
        let entry = item.entry
        purpose = item.purpose
        category = Classification.isPending(entry.category) ? "" : entry.category
        subcategory = category.isEmpty ? nil : entry.subcategory
        keypad = EntryKeypad(amount: entry.amount)
        if accounts.contains(where: { $0.id == entry.accountID }) { accountID = entry.accountID }
        purposeFocused = false
    }
    private func matchChip(_ match: Occurrence) -> some View {
        let selected = selectedMatchID == match.id
        let question: String = selected ? "已选 · \(match.title)这期" : "是\(match.title)这期吗"
        let label: String = question + " · " + FixedFlowPresentation.monthDay(match.date)
        return Button { purposeFocused = false; selectedMatchID = selected ? nil : match.id; if !selected { repeatsMonthly = false } } label: {
            HStack(spacing: YubaiSpace.space8) {
                if selected { Image(systemName: "checkmark") }
                Text(label)
            }.yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.amberStrong)
                .padding(.horizontal, YubaiSpace.gapGroup).padding(.vertical, YubaiSpace.space8).background(YubaiColor.amberTint, in: Capsule())
                .overlay { if selected { Capsule().strokeBorder(YubaiColor.amberDot, lineWidth: 1) } }
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
        var selectedMatchID: String?; var repeatsMonthly: Bool; var intoFixedSavings: Bool; var fromReserve: Bool; var ledgerUpdatedAt: Date
    }
    private var previewInput: PreviewInput {
        PreviewInput(expression: keypad.expression, nature: nature, purpose: purpose, category: category, subcategory: subcategory, date: date,
                     accountID: accountID, otherAccountID: otherAccountID, selectedMatchID: selectedMatchID,
                     repeatsMonthly: repeatsMonthly, intoFixedSavings: intoFixedSavings, fromReserve: fromReserve, ledgerUpdatedAt: store.current.updatedAt)
    }
    @MainActor private func refreshPreview() async {
        // No ledger work runs in body or the key action. Cancellation coalesces
        // quick input; the expensive unchanged Core calculations run off-main.
        do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
        guard !Task.isCancelled else { return }
        let ledger = store.current; let now = Date(); let fallback = store.funds.available
        let amount = amountCents; let nature = self.nature; let purpose = self.purpose; let day = date; let account = accountID
        let change = canSave ? (try? draftChange(now: now)) : nil
        let result = await Task.detached(priority: .userInitiated) {
            let match = FixedFlows.suggestions(amount: amount, nature: nature, purpose: purpose, day: day, accountID: account, in: ledger).first
            let available = change.flatMap { try? ManualBookkeeping.available(after: $0, in: ledger, now: now) } ?? fallback
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
        if case .fixedSavings(let total) = EntryHint.make(ledger: store.current, draft: draft, isFixedBill: repeatsMonthly || selectedLink != nil) {
            return (store.funds.fixedSavingsTotal, total)
        }
        return nil
    }
    private func saveWish() {
        guard canSave, let amount = keypad.amount else { return }
        let clean = purpose.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = clean.isEmpty ? Classification.displayCategory(effectiveCategory.category) : clean
        let now = Date()
        if store.update("心愿单", entryMotion: false, showToast: false, { ledger in
            let verdict = SubmittedPurchaseVerdict(verdict: .wait, reason: "先放心愿单 · 7 天后再问", need: .want, boundReason: "")
            let wish = try Wishlist.add(fromVerdict: verdict, title: title, amount: amount, category: effectiveCategory.category,
                                        subcategory: effectiveCategory.subcategory, purpose: purpose, in: &ledger, now: now)
            if let i = ledger.wishlist.firstIndex(where: { $0.id == wish.id }) { ledger.wishlist[i].coolUntil = Dates.addDays(7, to: now) }
        }) {
            store.toast = "放进心愿单了 · " + title + " " + amount2(amount, hide: store.preferences.hideAmounts)
            dismiss()
        }
    }
    private var addTransferAccountChip: some View {
        Button {
            purposeFocused = false
            accountIDsBeforeAdding = Set(store.accounts.map(\.id))
            showingTransferAccountEditor = true
        } label: {
            HStack(spacing: YubaiSpace.space4) {
                Image(systemName: "plus")
                Text("添加账户")
            }.yubaiFont(YubaiFont.callout, weight: .medium).foregroundStyle(YubaiColor.brandInk)
                .padding(.horizontal, YubaiSpace.gapGroup).frame(minHeight: YubaiSize.chipHeight)
                .background(YubaiColor.raised, in: Capsule()).yubaiHitTarget()
        }.buttonStyle(PressButtonStyle()).accessibilityIdentifier("transferAddAccount").accessibilityLabel("添加账户")
    }
    private func selectAddedTransferAccount() {
        defer { accountIDsBeforeAdding.removeAll() }
        guard let added = transferAccounts.first(where: { !accountIDsBeforeAdding.contains($0.id) }) else { return }
        otherAccountID = added.id
    }
    private func draftChange(now: Date) throws -> ChangeSet {
        guard let accountID, let amount = keypad.amount else { throw YubaiError.invalid("请选择账户并填写金额。") }
        var change: ChangeSet
        if repeatsMonthly && nature != .transfer && selectedLink == nil {
            change = try FixedFlows.monthlyEntryChange(amount: amount, nature: nature, accountID: accountID, day: date,
                                                       purpose: purpose, category: effectiveCategory.category, now: now, intoFixedSavings: intoFixedSavings)
        } else {
            change = try ManualBookkeeping.change(amount: amount, nature: nature, accountID: accountID, otherAccountID: otherAccountID,
                                                  day: date, purpose: purpose, category: effectiveCategory.category, link: selectedLink, now: now,
                                                  intoFixedSavings: intoFixedSavings, fromReserve: useReserve)
        }
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
        _ = keypad.resolve(); purposeFocused = false
        // Saving may beat the debounce. Revalidate the user's selected match
        // against the final input before constructing its linked payment.
        let match = FixedFlows.suggestions(amount: amountCents, nature: nature, purpose: purpose, day: date,
                                           accountID: accountID, in: store.current).first
        if match?.id != suggestion?.id { selectedMatchID = nil }
        suggestion = match
        do {
            let change = try draftChange(now: Date())
            guard store.apply(change, label: "记一笔", finishing: { ledger in
                for case .addEntry(let draft) in change.items where draft.categoryUserEdited == true && !Classification.isPending(draft.category) {
                    let choice = CategoryAssignment(category: draft.category, subcategory: draft.subcategory)
                    if SubcategoryClassifier.valid(choice, in: ledger, nature: draft.nature) { try CategoryModel.confirm(choice, entryIDs: [draft.id], in: &ledger) }
                }
            }) else { return }
            finishSaved(change)
        } catch { store.error = error.localizedDescription }
    }
    /// 日期选了昨天、前天，说明在补账：不收起，清空等下一笔，上面列出刚补的。今天的记一笔就收起。
    private func finishSaved(_ change: ChangeSet) {
        let title = purpose.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = title.isEmpty ? Classification.displayCategory(effectiveCategory.category) : title
        let backfill = Dates.day(date) < Dates.day(Date()) && nature == .expense
        if backfill {
            // Continuous entry keeps the sheet open, so the root's deferred
            // sheet-dismissal success must be delivered here exactly once.
            store.cancelEntrySaveMotion()
            let label = Classification.displayCategory(effectiveCategory.category)
            let rows = change.items.compactMap { item -> EntryAddedRow? in
                guard case .addEntry(let draft) = item else { return nil }
                return EntryAddedRow(id: draft.id, title: name, category: label, amount: draft.amount)
            }
            addedRows.insert(contentsOf: rows.reversed(), at: 0); addedDay = date
            #if os(iOS)
            AccessibilityNotification.Announcement("已记 \(addedRows.count) 笔").post()
            #endif
            keypad.reset(); purpose = ""; intoFixedSavings = false; fromReserve = false; selectedMatchID = nil; repeatsMonthly = false
            category = ""; subcategory = nil; categoryHint = nil; big = nil
        } else {
            let sign: AmountLabel.Sign = nature.inflow ? .inflow : .outflow
            let amount = store.preferences.hideAmounts ? "••••" : AmountLabel.text(amountCents, sign: sign)
            let repeatSuffix = repeatsMonthly && nature != .transfer && selectedLink == nil ? " · 每月 \(Dates.calendar.component(.day, from: date)) 号" : ""
            store.setEntrySaveToast("已记下 · " + name + " " + amount + " · " + store.accountName(accountID) + repeatSuffix)
            dismiss()
        }
    }
}
