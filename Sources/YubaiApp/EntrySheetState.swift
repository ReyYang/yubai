import SwiftUI
import YubaiCore

enum EntryDrawer: Equatable {
    case purpose, currency, calendar, source, destination, more, split

    /// Lists that pop out of a pill above the sheet; only one is open at a time.
    var isPopover: Bool { [.calendar, .source, .destination, .more].contains(self) }
}

/// The two accounts of an existing 转账 and whether it was 存入. While the draft keeps both,
/// it saves the way it was saved; picking another account decides afresh.
struct EntryKeptRoute: Equatable {
    let accountID: UUID?
    let destinationID: UUID?
    let deposit: Bool
}

struct EntrySheetDraft: Equatable {
    /// 支出, 收入 or 转账. A draft never holds `.deposit`: 存入 is a 转账 the route decides (`keptRoute` or the accounts).
    var type: EntryType = .expense
    var expression = EntryAmountExpression()
    var purpose = ""
    var category: String?
    var subcategory: String?
    var accountID: UUID?
    var destinationID: UUID?
    var date = Dates.now
    var screenshot: Data?
    var repeatMonthly = false
    var exception: EntryException?
    var incomeNextCycle = false
    var currency: BillCurrency = .cny
    var exchangeRate = ""
    var personalShare = ""
    var originalNature: Nature?
    var recoveryParticipants: [RecoveryParticipant]?
    var relatedEntryID: UUID?
    var intoFixedSavings = false
    var keptRoute: EntryKeptRoute?

    var nature: Nature {
        if let originalNature { return originalNature }
        switch type {
        case .expense: return .expense
        case .income: return .income
        case .transfer: return .transfer
        case .deposit: return .investBuy
        }
    }
    var isRoute: Bool { type == .transfer || type == .deposit }
    /// The tab that shows this draft: 存入 is a 转账 into a savings account.
    var tab: EntryType { type == .deposit ? .transfer : type }

    /// Reads any `.deposit` in as a 转账 that stays 存入 while its two accounts stay.
    mutating func adoptDepositType() {
        guard type == .deposit else { return }
        type = .transfer
        keptRoute = EntryKeptRoute(accountID: accountID, destinationID: destinationID, deposit: true)
    }
    var hasContent: Bool { !expression.isEmpty || !purpose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    init() {}

    static func dayLabel(for date: Date, now: Date) -> String {
        let day = Dates.day(date)
        if day == Dates.day(now) { return "今天" }
        if day == Dates.day(Dates.addDays(-1, to: now)) { return "昨天" }
        if day == Dates.day(Dates.addDays(-2, to: now)) { return "前天" }
        let parts = Dates.calendar.dateComponents([.month, .day], from: day)
        return "\(parts.month ?? 1)月\(parts.day ?? 1)日"
    }

    init(prefill: QuickEntryPrefill, ledger: Ledger) {
        let nature = prefill.nature ?? .expense
        let deposit = nature == .investBuy || (nature == .transfer && prefill.intoFixedSavings)
        type = nature.paired ? .transfer : nature.inflow ? .income : .expense
        switch nature {
        case .expense, .income, .investBuy, .transfer: break
        default: originalNature = nature
        }
        if let category = prefill.category, !Classification.isPending(category), !isRoute {
            let assignment = ledger.categoryAssignment(category: category, subcategory: prefill.subcategory, income: nature.categoryIncome)
            self.category = assignment.category
            subcategory = assignment.subcategory
        }
        accountID = prefill.accountID
        destinationID = prefill.otherAccountID
        intoFixedSavings = prefill.intoFixedSavings
        // A bill read back (edit, 再记一笔) keeps how it was saved; a fresh 存入 prefill stays 存入.
        if deposit || (prefill.copiedEntry != nil && (nature == .transfer || nature == .investBuy)) {
            keptRoute = EntryKeptRoute(accountID: accountID, destinationID: destinationID, deposit: deposit)
        }
        exception = prefill.fromReserve ? .reserve : nil
        date = prefill.date ?? Dates.now
        relatedEntryID = prefill.relatedEntryID
        purpose = prefill.purpose ?? ""
        screenshot = prefill.screenshot
        expression = EntryAmountExpression(cents: prefill.amount ?? 0)
        if let entry = prefill.copiedEntry {
            if let pending = entry.pendingRecovery {
                exception = pending == .split ? .split : .reimbursement
            }
            recoveryParticipants = entry.recoveryParticipants
            if let share = entry.personalExpense { personalShare = Money.input(share) }
            incomeNextCycle = entry.countsFromCycleStart != nil
            if let currency = entry.originalCurrency, let original = entry.originalAmount, original > 0 {
                // Leave the rate field empty: saving an edit keeps the rate frozen in the entry.
                self.currency = currency
            }
        }
    }
}

/// Which way the money goes and which category is picked: what decides whether 记下 needs a category.
struct EntryCategoryState: Equatable {
    let income: Bool
    let category: String?

    init(_ draft: EntrySheetDraft) {
        income = draft.nature.categoryIncome
        category = draft.category
    }
}

@MainActor @Observable final class EntrySheetViewModel: Identifiable {
    let id = UUID()
    @ObservationIgnored private weak var store: AppStore?
    private var fixtureLedger: Ledger
    let settled: Bool
    let isPrefilled: Bool
    let fixtureNow: Date?
    let editingID: UUID?
    let categoryOnly: Bool
    var draft: EntrySheetDraft
    var drawer: EntryDrawer?
    var categoryPanel = false
    /// 分类管理 pushed over the panel; the draft stays.
    var managingCategories = false
    /// The category row whose subcategories are open in the panel.
    var expandedCategory: String?
    /// 记下 was pressed without a category: the row keeps its amber ring until one is picked.
    var needsCategory = false
    var amountPulse = 0
    var suggestion: CategoryAssignment?
    var effect: EntryEffect?
    /// 算作存入: what this cycle will have saved once this transfer lands.
    var depositedThisCycle: Int64?
    var categoryPulse = 0
    var failure: String?
    @ObservationIgnored private var previewTask: Task<Void, Never>?
    private var fixtureBaseline: EntrySheetDraft?
    var fixtureTopCategories: [String] = []
    var routeShowsBalance = false
    var fixtureDayLabel: String?
    var fixtureRepeatDay: Int?
    var fixtureSplitNames: [String] = []
    private(set) var didSave = false
    @ObservationIgnored private var shouldReplacePrefill = false
    /// An edited bill's direction and category as it opened: untouched 待整理 may be saved as it was.
    @ObservationIgnored private var initialCategory: EntryCategoryState?
    /// What `suggestion` was guessed from; a suggestion for other words is never saved.
    @ObservationIgnored private var suggestionSource: String?

    init(store: AppStore, prefill: QuickEntryPrefill?, editingID: UUID? = nil, categoryOnly: Bool = false) {
        self.store = store
        fixtureLedger = Ledger()
        settled = false
        isPrefilled = prefill != nil
        fixtureNow = store.overviewFixture?.now ?? store.settingsFixture?.now ?? HomeFixture.current?.now
        self.editingID = editingID
        self.categoryOnly = categoryOnly
        categoryPanel = categoryOnly
        shouldReplacePrefill = editingID != nil
        if let prefill {
            draft = EntrySheetDraft(prefill: prefill, ledger: store.current)
            if let participants = prefill.copiedEntry?.recoveryParticipants {
                fixtureSplitNames = ["我"] + participants.map(\.name)
            }
        } else if let retained = store.retainedEntryDraft {
            draft = retained
        } else {
            draft = EntrySheetDraft()
            draft.date = HomeFixture.current?.now ?? Dates.now
            draft.type = store.lastEntryType == .deposit ? .transfer : store.lastEntryType
            if store.accounts.contains(where: { $0.id == store.lastEntryAccountID && !$0.archived }) {
                draft.accountID = store.lastEntryAccountID
            }
        }
        draft.adoptDepositType()
        initialCategory = editingID == nil ? nil : EntryCategoryState(draft)
        normalizeAccounts()
    }

    init(fixtureLedger: Ledger, draft: EntrySheetDraft, now: Date, editingID: UUID? = nil) {
        store = nil
        self.fixtureLedger = fixtureLedger
        self.draft = draft
        settled = true
        isPrefilled = false
        fixtureNow = now
        self.editingID = editingID
        categoryOnly = false
        self.draft.adoptDepositType()
        initialCategory = editingID == nil ? nil : EntryCategoryState(self.draft)
        fixtureBaseline = self.draft
        normalizeAccounts()
        effect = input(category: selectedCategory).flatMap { EntrySaveMapper.effect(for: $0, in: fixtureLedger, now: now) }
    }

    var ledger: Ledger { store?.current ?? fixtureLedger }
    var now: Date { fixtureNow ?? Dates.now }
    var hasReceipt: Bool { draft.screenshot != nil }
    var hidesKeypad: Bool { drawer == .purpose }
    var hidesAmounts: Bool { store?.preferences.hideAmounts == true }
    /// The rate shown and used for the preview: typed, else frozen (editing), else Settings or synced.
    var signedRate: Decimal? {
        if let typed = typedRate { return typed }
        guard draft.exchangeRate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        if let id = editingID, let entry = ledger.entries.first(where: { $0.id == id }),
           entry.originalCurrency == draft.currency, let original = entry.originalAmount, original > 0 {
            return entry.exchangeRate?.cnyPerUnit ?? Decimal(entry.amount) / Decimal(original)
        }
        return ExchangeRates.rate(for: draft.currency, in: ledger, now: now)?.cnyPerUnit
    }
    /// Only a rate typed for this entry is sent as a manual rate.
    var typedRate: Decimal? {
        let clean = draft.exchangeRate.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty { return nil }
        let separator = Locale.current.decimalSeparator ?? "."
        let normalized = clean.replacingOccurrences(of: separator, with: ".")
        guard normalized.allSatisfy({ "0123456789.".contains($0) }),
              normalized.filter({ $0 == "." }).count <= 1 else { return nil }
        return Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX"))
    }
    var canRepeat: Bool {
        guard editingID == nil else { return false }
        return draft.originalNature == nil && (draft.type == .income || draft.type == .expense ||
            (savesAsDeposit && account(draft.destinationID)?.kind == .investment))
    }
    var money: Int64 { draft.expression.evaluatedCents ?? 0 }
    /// 存入: cash or a bank account into an investment (savings) account. A bill read back keeps
    /// how it was saved until one of its two accounts changes. Credit, 借出待收 or investment to
    /// investment stay a plain 转账.
    var savesAsDeposit: Bool {
        guard draft.isRoute, draft.originalNature == nil else { return false }
        if let kept = draft.keptRoute, kept.accountID == draft.accountID, kept.destinationID == draft.destinationID {
            return kept.deposit
        }
        guard let source = account(draft.accountID), let destination = account(draft.destinationID) else { return false }
        return (source.kind == .cash || source.kind == .bank) && destination.kind == .investment
    }
    /// What 记下 needs: an amount, and a category unless the money only moves between accounts.
    /// Editing keeps an untouched 待整理 bill as it was; a changed direction or a cleared category asks again.
    var categoryReady: Bool {
        draft.isRoute || draft.relatedEntryID != nil || selectedCategory != nil || (editingID == nil && suggestion != nil)
            || (initialCategory != nil && initialCategory?.category == nil && initialCategory == EntryCategoryState(draft))
    }
    var canSave: Bool { draft.expression.canSave && money > 0 && categoryReady }
    var localMoney: Int64? {
        guard draft.currency != .cny else { return money }
        guard let rate = signedRate else { return nil }
        return ManualExchangeRate(currency: draft.currency, cnyPerUnit: rate, updatedAt: now).convert(money)
    }
    var splitCount: Int64 { Int64(max(2, fixtureSplitNames.count)) }
    var myShare: Int64 {
        let total = localMoney ?? 0
        let defaultShare = (total + splitCount - 1) / splitCount
        let entered = try? Money.parse(draft.personalShare)
        return min(total, max(0, entered ?? defaultShare))
    }

    var categories: [YubaiCore.Category] {
        ledger.orderedCategories(income: draft.nature.categoryIncome)
    }
    var topCategories: [YubaiCore.Category] {
        let available = categories
        if let initial = fixtureBaseline, draft.type == initial.type, !fixtureTopCategories.isEmpty {
            return fixtureTopCategories.compactMap { name in available.first { $0.name == name } }
        }
        let currentLedger = ledger
        let counts = currentLedger.activeEntries.reduce(into: [String: Int]()) { counts, entry in
            guard entry.nature == draft.nature else { return }
            counts[entry.category, default: 0] += 1
        }
        var ranked = available.enumerated().sorted {
            let left = counts[$0.element.name, default: 0], right = counts[$1.element.name, default: 0]
            return left == right ? $0.offset < $1.offset : left > right
        }.map(\.element)
        if let name = draft.category ?? suggestion?.category,
           let selected = ranked.firstIndex(where: { $0.name == name }), selected >= DSLayout.categoryRow - 1 {
            let category = ranked.remove(at: selected)
            ranked.insert(category, at: DSLayout.categoryRow - 2)
        }
        return Array(ranked.prefix(DSLayout.categoryRow - 1))
    }
    var subcategories: [String] {
        categories.first(where: { $0.name == draft.category })?.subcategories ?? []
    }

    func account(_ id: UUID?) -> Account? { ledger.accounts.first { $0.id == id } }
    func accounts(destination: Bool) -> [Account] {
        let original = editingID.flatMap { id in ledger.entries.first { $0.id == id } }
        let originalID = destination ? original?.otherAccountID : original?.accountID
        let selectedID = destination ? draft.destinationID : draft.accountID
        return EntrySaveMapper.selectableAccounts(in: ledger, keeping: originalID).filter { account in
            if account.id == originalID && account.id == selectedID { return true }
            if destination { return draft.isRoute && account.id != draft.accountID }
            return true
        }
    }

    private func normalizeAccounts() {
        let sources = accounts(destination: false)
        if !sources.contains(where: { $0.id == draft.accountID }) {
            let suggested = ManualBookkeeping.defaultAccount(in: ledger, nature: draft.nature)?.id
            let alternatives = sources.filter { $0.id != draft.destinationID }
            draft.accountID = alternatives.first(where: { $0.id == suggested })?.id
                ?? alternatives.first?.id ?? sources.first?.id
        }
        guard draft.isRoute else { return }
        let destinations = accounts(destination: true)
        if !destinations.contains(where: { $0.id == draft.destinationID }) {
            draft.destinationID = destinations.first?.id
        }
    }
    func select(_ type: EntryType) {
        guard type != draft.tab else { return }
        needsCategory = false
        draft.type = type
        draft.originalNature = nil
        draft.relatedEntryID = nil
        draft.intoFixedSavings = false
        draft.keptRoute = nil
        draft.destinationID = nil
        draft.category = nil
        draft.subcategory = nil
        draft.exception = nil
        draft.repeatMonthly = false
        draft.incomeNextCycle = false
        draft.personalShare = ""
        draft.recoveryParticipants = nil
        fixtureSplitNames = []
        suggestion = nil
        drawer = nil
        normalizeAccounts()
    }
    func select(category: String, subcategory: String? = nil) {
        draft.category = category
        draft.subcategory = subcategory
        suggestion = nil
        needsCategory = false
    }

    /// A tap on a category circle in the sheet: picks it, or clears it when it was already picked.
    func toggle(category: String) {
        if draft.category == category {
            draft.category = nil
            draft.subcategory = nil
        } else {
            select(category: category)
        }
    }

    /// The panel only picks: a category without subcategories is chosen at once,
    /// one with subcategories opens its row; a subcategory chip chooses and closes.
    func pickInPanel(_ category: YubaiCore.Category) {
        if category.subcategories.isEmpty {
            select(category: category.name)
            dismissCategoryPanel()
        } else {
            expandedCategory = expandedCategory == category.name ? nil : category.name
        }
    }

    func pickInPanel(_ category: String, subcategory: String?) {
        select(category: category, subcategory: subcategory)
        dismissCategoryPanel()
    }

    func toggleDrawer(_ target: EntryDrawer) {
        drawer = drawer == target ? nil : target
    }

    /// 「每月」 only switches; the calendar stays open.
    func toggleRepeat() {
        draft.repeatMonthly.toggle()
        if draft.repeatMonthly { draft.exception = nil }
        fixtureRepeatDay = nil
    }

    /// The ··· list: pick one to set it, pick the current one again to clear it. Either way the list closes.
    func choose(_ exception: EntryException) {
        draft.exception = draft.exception == exception ? nil : exception
        if draft.exception != nil { draft.repeatMonthly = false }
        drawer = nil
    }

    func clearException() {
        draft.exception = nil
        if drawer == .split { drawer = nil }
    }

    var dayLabel: String {
        fixtureDayLabel ?? EntrySheetDraft.dayLabel(for: draft.date, now: now)
    }

    func setDate(_ value: Date) {
        draft.date = value
        fixtureDayLabel = nil
        drawer = nil
    }

    func selectAccount(_ id: UUID, destination: Bool) {
        if destination {
            draft.destinationID = id
        } else {
            if draft.isRoute && draft.destinationID == id { draft.destinationID = draft.accountID }
            draft.accountID = id
        }
        normalizeAccounts()
        if !canRepeat { draft.repeatMonthly = false }
        drawer = nil
    }

    func dismissCategoryPanel() {
        expandedCategory = nil
        managingCategories = false
        categoryPanel = false
    }

    /// Category management edits the ledger; a renamed or removed pick follows along.
    @discardableResult func mutateLedger(_ reason: String, _ update: (inout Ledger) throws -> Void) -> Bool {
        // Never an undo snapshot: it would replace a delete's 撤销 with this edit.
        if let store { return store.update(reason, recordUndo: false, entryMotion: false, showToast: false, update) }
        do { try update(&fixtureLedger); return true }
        catch { failure = error.localizedDescription; return false }
    }

    /// The draft's pick is this category in this direction: names alone repeat across 支出 and 收入.
    func draftUses(category name: String, income: Bool) -> Bool {
        draft.category == name && !draft.isRoute && draft.nature.categoryIncome == income
    }

    /// Bills a category (or one of its subcategories) holds: what deleting it moves.
    func entryCount(category name: String, subcategory: String? = nil, income: Bool) -> Int {
        let ledger = ledger
        return ledger.activeEntries.filter { entry in
            guard entry.nature.categoryIncome == income else { return false }
            let assignment = ledger.normalizedCategory(for: entry)
            return assignment.category == name && (subcategory == nil || assignment.subcategory == subcategory)
        }.count
    }

    /// 删除分类: its bills move to the catch-all; a draft that picked it picks again.
    @discardableResult func deleteCategory(_ name: String, income: Bool) -> Bool {
        let fallback = income ? "其他收入" : "其他支出"
        guard name != fallback,
              mutateLedger("删除分类", { try CategoryModel.merge(name, into: fallback, income: income, in: &$0) }) else { return false }
        if draftUses(category: name, income: income) {
            draft.category = nil
            draft.subcategory = nil
        }
        return true
    }

    /// Reorders the categories on screen. Hidden ones keep their slots in the saved order.
    func reorderVisibleCategories(_ visible: [String], income: Bool) {
        let current = ledger
        let allowed = current.categories.filter { !$0.system && $0.income == income }.map(\.name)
        let allowedSet = Set(allowed)
        var seen = Set<String>()
        let saved = (current.categoryOrder(income: income) + allowed).filter { allowedSet.contains($0) && seen.insert($0).inserted }
        let moving = Set(visible)
        var queue = visible[...]
        var order = saved.map { name in moving.contains(name) ? queue.popFirst() ?? name : name }
        order += queue
        mutateLedger("分类排序") { try CategoryModel.setOrder(order, income: income, in: &$0) }
    }

    private func input(category: CategoryAssignment?) -> EntrySaveInput? {
        guard let accountID = draft.accountID, draft.expression.canSave else { return nil }
        guard draft.currency == .cny || (signedRate != nil && (localMoney ?? 0) > 0) else { return nil }
        var input = EntrySaveInput(type: savesAsDeposit ? .deposit : draft.type, amountCents: money, currency: draft.currency, exchangeRate: typedRate,
            purpose: draft.purpose, category: category?.category ?? Classification.pendingCategory,
            subcategory: category?.subcategory, accountID: accountID, destinationAccountID: draft.destinationID,
            date: draft.date, repeatMonthly: draft.repeatMonthly && canRepeat, exception: draft.exception,
            incomeNextCycle: draft.incomeNextCycle, personalExpenseCents: myShare, recordedNature: draft.originalNature,
            relatedEntryID: draft.relatedEntryID, keepInFixedSavings: draft.intoFixedSavings, preserveTime: editingID != nil)
        if let people = draft.recoveryParticipants, let localMoney,
           people.reduce(Int64(0), { $0 + $1.amount }) == localMoney - myShare {
            input.recoveryParticipants = editingID == nil
                ? people.map { RecoveryParticipant(name: $0.name, amount: $0.amount) }
                : people
        }
        return input
    }

    private var selectedCategory: CategoryAssignment? {
        draft.category.map { CategoryAssignment(category: $0, subcategory: draft.subcategory) }
    }

    /// The words and direction a suggestion is guessed from.
    private var suggestionKey: String {
        draft.purpose.trimmingCharacters(in: .whitespacesAndNewlines) + "|" + draft.nature.rawValue
    }

    /// 记下 never saves a guess made for other words: re-guess now if the debounced one is behind.
    private func refreshSuggestionIfStale() {
        guard !draft.isRoute, editingID == nil, selectedCategory == nil, suggestionSource != suggestionKey else { return }
        let purpose = draft.purpose.trimmingCharacters(in: .whitespacesAndNewlines)
        suggestion = purpose.isEmpty ? nil : CategoryGuesser.guess(purpose, nature: draft.nature, date: draft.date, in: ledger)
        suggestionSource = suggestion == nil ? nil : suggestionKey
    }

    func schedulePreview() {
        previewTask?.cancel()
        let source = suggestionKey
        if suggestionSource != source { suggestion = nil; suggestionSource = nil }
        let ledger = ledger
        let now = now
        let selection = selectedCategory
        let currentInput = input(category: selection)
        let purpose = draft.purpose
        let date = draft.date
        let nature = draft.nature
        let deposit = savesAsDeposit && editingID == nil
        let amount = localMoney ?? 0
        let isEditing = editingID != nil
        if !deposit { depositedThisCycle = nil }
        let needsGuess = !draft.isRoute && !isEditing && selection == nil && !purpose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if !needsGuess { suggestion = nil }
        if currentInput?.exception == nil, currentInput?.repeatMonthly != true { effect = nil }
        previewTask = Task { [weak self] in
            do { try await Task.sleep(for: EntrySpec.inputDebounce) }
            catch { return }
            let computation = Task.detached(priority: .userInitiated) {
                let guess = needsGuess ? CategoryGuesser.guess(purpose, nature: nature, date: date, in: ledger) : nil
                var resolved = currentInput
                if let guess {
                    resolved?.category = guess.category
                    resolved?.subcategory = guess.subcategory
                }
                let deposited = deposit
                    ? EntrySaveMapper.depositedThisCycle(in: ledger, now: now, adding: amount, on: date)
                    : nil
                return (guess, resolved.flatMap { EntrySaveMapper.effect(for: $0, in: ledger, now: now) }, deposited)
            }
            let (guess, preview, deposited) = await withTaskCancellationHandler {
                await computation.value
            } onCancel: { computation.cancel() }
            guard !Task.isCancelled else { return }
            self?.suggestion = guess
            self?.suggestionSource = guess == nil ? nil : source
            self?.effect = preview
            self?.depositedThisCycle = deposited
        }
    }

    func cancelPreview() {
        previewTask?.cancel()
        previewTask = nil
    }

    func pressAmountKey(_ key: String) {
        if shouldReplacePrefill && (key.first?.isNumber == true || key == ".") { draft.expression.reset() }
        shouldReplacePrefill = false
        draft.expression.press(key)
    }

    /// Why 记下 did nothing, so the sheet can point at the row that needs it.
    enum SaveBlock { case amount, category }

    func blockedSave() -> SaveBlock? {
        if !draft.expression.canSave || money <= 0 { return .amount }
        if !categoryReady { return .category }
        return nil
    }

    func save() -> Bool {
        guard !didSave else { return false }
        refreshSuggestionIfStale()
        switch blockedSave() {
        case .amount:
            amountPulse &+= 1
            AccessibilityNotification.Announcement("先输入金额").post()
            return false
        case .category:
            needsCategory = true
            categoryPulse &+= 1
            AccessibilityNotification.Announcement("先选分类").post()
            return false
        case nil: break
        }
        if let store, let editingID, categoryOnly {
            guard let selection = selectedCategory else { return false }
            let result = store.update("改分类") { try CategoryModel.confirm(selection, entryIDs: [editingID], in: &$0) }
            didSave = result
            return result
        }
        let selection = selectedCategory ?? (draft.isRoute || editingID != nil ? nil : suggestion)
        guard let input = input(category: selection) else {
            failure = draft.accountID == nil ? "先选择一个账户。" : "请核对金额或汇率。"
            return false
        }
        let now = now
        let userSelected = selectedCategory != nil
        if let store, let editingID {
            let result = store.update("编辑") { try EntrySaveMapper.edit(editingID, input: input, in: &$0, now: now) }
            didSave = result
            return result
        }
        do {
            let change = try EntrySaveMapper.makeChange(input, in: ledger, now: now)
            func apply(_ ledger: inout Ledger) throws {
                _ = try change.apply(to: &ledger)
                guard userSelected, let selection else { return }
                for case .addEntry(let added) in change.items {
                    guard ledger.entries.first(where: { $0.id == added.id })?.relatedEntryID == nil,
                          SubcategoryClassifier.valid(selection, in: ledger, nature: added.nature) else { continue }
                    try CategoryModel.confirm(selection, entryIDs: [added.id], in: &ledger)
                }
            }
            let saved: Bool
            if let store {
                saved = store.update("记一笔", apply)
                if saved {
                    if !isPrefilled { store.retainedEntryDraft = nil }
                    store.lastEntryType = draft.tab
                    store.lastEntryAccountID = draft.accountID
                }
            } else {
                try apply(&fixtureLedger)
                saved = true
            }
            didSave = saved
            return saved
        } catch {
            failure = error.localizedDescription
            return false
        }
    }

    #if DEBUG
    func restoreFixtureDraft(_ previous: EntrySheetViewModel) {
        fixtureLedger = previous.fixtureLedger
        if previous.didSave || !previous.draft.hasContent {
            var fresh = EntrySheetDraft()
            fresh.type = previous.draft.type
            fresh.accountID = previous.draft.accountID
            fresh.date = now
            draft = fresh
        } else {
            draft = previous.draft
        }
        drawer = nil
        categoryPanel = false
        managingCategories = false
        needsCategory = false
        normalizeAccounts()
    }
    #endif

    func retainDraft() {
        guard let store, editingID == nil, !didSave, !isPrefilled || draft.hasContent else { return }
        store.retainedEntryDraft = draft.hasContent ? draft : nil
    }
}
