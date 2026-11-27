import SwiftUI
import YubaiCore

enum EntryDrawer: Equatable {
    case purpose, currency, rate, calendar, source, destination, more, split

    /// Lists that pop out of a pill above the sheet; only one is open at a time.
    var isPopover: Bool { [.currency, .rate, .calendar, .source, .destination, .more].contains(self) }
    /// 币种 and 汇率 hang under the amount (S-Entry-Ccy, S-Entry-Rate); the others rise above their pill.
    var opensBelow: Bool { self == .currency || self == .rate }
}

/// The two accounts of a 转账 read back, its nature and whether it was 存入. While the draft keeps
/// both accounts an edited bill saves exactly as it was; picking another account decides afresh.
struct EntryKeptRoute: Equatable {
    let accountID: UUID?
    let destinationID: UUID?
    let nature: Nature
    let intoFixedSavings: Bool
    /// nil: a copy (再记一笔), which decides 存入 by its accounts like any new bill.
    let deposit: Bool?
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
    /// The person picked a 从 or 到 account in this sheet; until then an edited 转账 replays its own route.
    var routeTouched = false

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
        keptRoute = EntryKeptRoute(accountID: accountID, destinationID: destinationID, nature: .investBuy,
                                   intoFixedSavings: intoFixedSavings, deposit: true)
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
        // A 转账 read back keeps how it was saved while its accounts stay; a fresh 存入 prefill stays 存入.
        if nature.paired || deposit {
            keptRoute = EntryKeptRoute(accountID: accountID, destinationID: destinationID, nature: nature,
                                       intoFixedSavings: prefill.intoFixedSavings,
                                       deposit: deposit || prefill.copiedEntry != nil ? deposit : nil)
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
    let route: Bool
    let nature: Nature
    let category: String?

    init(_ draft: EntrySheetDraft) {
        route = draft.isRoute
        nature = draft.nature
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
    var ratePulse = 0
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
    /// This edit changed the direction or the category at least once; 待整理 then has to be picked again.
    private(set) var categoryTouched = false

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
        if editingID == nil, prefill?.copiedEntry != nil, let kept = draft.keptRoute {
            // 再记一笔 is a new bill: 存入 or not follows its accounts.
            draft.keptRoute = EntryKeptRoute(accountID: kept.accountID, destinationID: kept.destinationID, nature: kept.nature,
                                             intoFixedSavings: kept.intoFixedSavings, deposit: nil)
        }
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
        return autoRate
    }
    /// The rate this entry gets without a typed one: frozen (editing), else Settings' fixed, else synced.
    var autoRate: Decimal? {
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
        guard draft.isRoute else { return false }
        if let deposit = keptRouteHit?.deposit { return deposit }
        guard draft.originalNature == nil else { return false }
        guard let source = account(draft.accountID), let destination = account(draft.destinationID) else { return false }
        return (source.kind == .cash || source.kind == .bank) && destination.kind == .investment
    }
    /// The kept route, until the person picks another 从 or 到 account.
    var keptRouteHit: EntryKeptRoute? {
        guard draft.isRoute, !draft.routeTouched, let kept = draft.keptRoute else { return nil }
        return kept
    }

    /// An edited 转账 whose accounts were left alone saves its own nature, second account (even none)
    /// and 存入 mark exactly as they were, so its plan and refund links stay.
    var replaysRoute: Bool { editingID != nil && keptRouteHit != nil }

    /// What 记下 needs: an amount, and a category unless the money only moves between accounts.
    /// Editing keeps an untouched 待整理 bill as it was; a changed direction or a cleared category asks again.
    var categoryReady: Bool {
        draft.isRoute || draft.relatedEntryID != nil || selectedCategory != nil || (editingID == nil && shownSuggestion != nil)
            || (!categoryTouched && initialCategory?.route == false && initialCategory?.category == nil
                && initialCategory == EntryCategoryState(draft))
    }
    var canSave: Bool { draft.expression.canSave && money > 0 && (draft.currency == .cny || (localMoney ?? 0) > 0) && categoryReady }
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
        if let name = draft.category ?? shownSuggestion?.category,
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
        // An edited one-sided record (imported 申购, 还款…) gets no second account it never had.
        guard draft.isRoute, !replaysRoute else { return }
        let destinations = accounts(destination: true)
        if !destinations.contains(where: { $0.id == draft.destinationID }) {
            draft.destinationID = destinations.first?.id
        }
    }
    func select(_ type: EntryType) {
        guard type != draft.tab else { return }
        categoryTouched = true
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
        categoryTouched = true
        draft.category = category
        draft.subcategory = subcategory
        suggestion = nil
        needsCategory = false
    }

    /// A tap on a category circle in the sheet: picks it, or clears it when it was already picked.
    func toggle(category: String) {
        if draft.category == category {
            categoryTouched = true
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
        draft.routeTouched = true
        normalizeAccounts()
        // A 还款 / 借出 / 赎回 moved to other accounts is decided afresh, like any 转账.
        if draft.originalNature?.paired == true, draft.keptRoute != nil { draft.originalNature = nil }
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
        if let store {
            guard store.update(reason, recordUndo: false, entryMotion: false, showToast: false, update) else { return false }
            // An older whole-ledger snapshot would now roll this edit back too; drop it. The delete bar stays.
            store.clearUndo()
            return true
        }
        do { try update(&fixtureLedger); return true }
        catch { failure = error.localizedDescription; return false }
    }

    /// The draft's pick is this category in this direction: names alone repeat across 支出 and 收入.
    func draftUses(category name: String, income: Bool) -> Bool {
        draft.category == name && !draft.isRoute && draft.nature.categoryIncome == income
    }

    /// Bills a category (or one of its subcategories) holds, 最近删除 included: what deleting it moves.
    func entryCount(category name: String, subcategory: String? = nil, income: Bool) -> Int {
        let ledger = ledger
        let byID = Dictionary(uniqueKeysWithValues: ledger.entries.map { ($0.id, $0) })
        return ledger.entries.filter { entry in
            guard entry.nature.categoryIncome == income else { return false }
            let assignment = ledger.normalizedCategory(for: entry, entriesByID: byID)
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
        input.keepsRoute = replaysRoute
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

    /// The suggestion on screen, only while it was guessed from these words and is still a category here.
    var shownSuggestion: CategoryAssignment? {
        guard let suggestion, suggestionSource == suggestionKey,
              categories.contains(where: { $0.name == suggestion.category }) else { return nil }
        return suggestion
    }

    /// Guess at once whenever the words or direction change, so what 记下 saves is what is shown.
    private func refreshSuggestion() {
        let key = suggestionKey
        guard suggestionSource != key else { return }
        let purpose = draft.purpose.trimmingCharacters(in: .whitespacesAndNewlines)
        let needsGuess = !draft.isRoute && editingID == nil && selectedCategory == nil && !purpose.isEmpty
        suggestion = needsGuess ? CategoryGuesser.guess(purpose, nature: draft.nature, date: draft.date, in: ledger) : nil
        suggestionSource = key
    }

    func schedulePreview() {
        previewTask?.cancel()
        refreshSuggestion()
        let ledger = ledger
        let now = now
        let selection = selectedCategory ?? (draft.isRoute ? nil : shownSuggestion)
        var currentInput = input(category: selection)
        // Preview with the rate the amount line shows (typed, frozen or synced); saving sends only a typed one.
        currentInput?.exchangeRate = signedRate
        let date = draft.date
        let deposit = savesAsDeposit && editingID == nil
        let amount = localMoney ?? 0
        if !deposit { depositedThisCycle = nil }
        if currentInput?.exception == nil, currentInput?.repeatMonthly != true { effect = nil }
        previewTask = Task { [weak self] in
            do { try await Task.sleep(for: EntrySpec.inputDebounce) }
            catch { return }
            let computation = Task.detached(priority: .userInitiated) {
                let deposited = deposit
                    ? EntrySaveMapper.depositedThisCycle(in: ledger, now: now, adding: amount, on: date)
                    : nil
                return (currentInput.flatMap { EntrySaveMapper.effect(for: $0, in: ledger, now: now) }, deposited)
            }
            let (preview, deposited) = await withTaskCancellationHandler {
                await computation.value
            } onCancel: { computation.cancel() }
            guard !Task.isCancelled else { return }
            self?.effect = preview
            self?.depositedThisCycle = deposited
        }
    }

    func cancelPreview() {
        previewTask?.cancel()
        previewTask = nil
    }

    func pressAmountKey(_ key: String) {
        // With the rate open, the sheet's own keypad types the rate (no system keyboard over the sheet).
        if drawer == .rate { pressRateKey(key); return }
        if shouldReplacePrefill && (key.first?.isNumber == true || key == ".") { draft.expression.reset() }
        shouldReplacePrefill = false
        draft.expression.press(key)
    }

    /// Why 记下 did nothing, so the sheet can point at the row that needs it.
    enum SaveBlock { case amount, rate, category }

    func blockedSave() -> SaveBlock? {
        if !draft.expression.canSave || money <= 0 { return .amount }
        if draft.currency != .cny, (localMoney ?? 0) <= 0 { return .rate }
        if !categoryReady { return .category }
        return nil
    }

    /// The ≈ line has a rate to show; otherwise it asks for one (X-entry-norate).
    var hasRate: Bool { draft.currency == .cny || signedRate != nil }

    /// Where the rate on the ≈ line comes from, said under the rate field.
    var rateSource: String {
        if typedRate != nil { return "只用于这一笔" }
        if let id = editingID, let entry = ledger.entries.first(where: { $0.id == id }), entry.originalCurrency == draft.currency {
            return "记下时的汇率"
        }
        if FixedFlows.exchangeRate(for: draft.currency, in: ledger, now: now) != nil { return "设置里的固定汇率" }
        if let fetched = ledger.preferences.syncedRates?.fetchedAt { return CurrencySettings.syncTime(fetched, now: now) + " 同步" }
        return ""
    }

    /// Typing a rate for this entry: digits, one point, up to four decimals; ⌫ back to the synced one.
    func pressRateKey(_ key: String) {
        var text = draft.exchangeRate
        switch key {
        case "⌫": text = String(text.dropLast())
        case ".": if !text.contains(".") { text = (text.isEmpty ? "0" : text) + "." }
        case "+", "−": return
        default:
            for digit in key where digit.isNumber {
                let decimals = text.split(separator: ".", omittingEmptySubsequences: false).dropFirst().first?.count ?? 0
                guard text.count < 12, !(text.contains(".") && decimals >= 4) else { break }
                text = text == "0" ? String(digit) : text + String(digit)
            }
        }
        draft.exchangeRate = text
    }

    func pickCurrency(_ currency: BillCurrency) {
        if draft.currency != currency { draft.exchangeRate = "" }
        draft.currency = currency
        drawer = nil
    }

    func save() -> Bool {
        guard !didSave else { return false }
        switch blockedSave() {
        case .amount:
            amountPulse &+= 1
            AccessibilityNotification.Announcement("先输入金额").post()
            return false
        case .rate:
            ratePulse &+= 1
            AccessibilityNotification.Announcement("先填汇率").post()
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
            guard store.current.entries.contains(where: { $0.id == editingID && $0.deletedAt == nil }) else {
                failure = "这笔账单已删除。"
                return false
            }
            let result = store.update("改分类") { try CategoryModel.confirm(selection, entryIDs: [editingID], in: &$0) }
            didSave = result
            return result
        }
        let selection = selectedCategory ?? (draft.isRoute || editingID != nil ? nil : shownSuggestion)
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
