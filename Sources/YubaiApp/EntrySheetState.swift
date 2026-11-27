import SwiftUI
import YubaiCore

enum EntryDrawer: Equatable {
    case purpose, currency, calendar, source, destination, more, split

    /// Lists that pop out of a pill above the sheet; only one is open at a time.
    var isPopover: Bool { [.calendar, .source, .destination, .more].contains(self) }
}

struct EntrySheetDraft: Equatable {
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
        switch nature {
        case .investBuy: type = .deposit
        case .transfer where prefill.intoFixedSavings: type = .deposit
        default: type = nature.paired ? .transfer : nature.inflow ? .income : .expense
        }
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
                self.currency = currency
                exchangeRate = NSDecimalNumber(decimal: Decimal(entry.amount) / Decimal(original)).stringValue
            }
        }
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
            draft.type = store.lastEntryType
            if store.accounts.contains(where: { $0.id == store.lastEntryAccountID && !$0.archived }) {
                draft.accountID = store.lastEntryAccountID
            }
        }
        normalizeAccounts()
    }

    init(fixtureLedger: Ledger, draft: EntrySheetDraft, now: Date) {
        store = nil
        self.fixtureLedger = fixtureLedger
        self.draft = draft
        settled = true
        isPrefilled = false
        fixtureNow = now
        editingID = nil
        categoryOnly = false
        fixtureBaseline = draft
        normalizeAccounts()
        effect = input(category: selectedCategory).flatMap { EntrySaveMapper.effect(for: $0, in: fixtureLedger, now: now) }
    }

    var ledger: Ledger { store?.current ?? fixtureLedger }
    var now: Date { fixtureNow ?? Dates.now }
    var hasReceipt: Bool { draft.screenshot != nil }
    var hidesKeypad: Bool { drawer == .purpose }
    var hidesAmounts: Bool { store?.preferences.hideAmounts == true }
    var signedRate: Decimal? {
        let clean = draft.exchangeRate.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty { return FixedFlows.exchangeRate(for: draft.currency, in: ledger, now: now)?.cnyPerUnit }
        let separator = Locale.current.decimalSeparator ?? "."
        let normalized = clean.replacingOccurrences(of: separator, with: ".")
        guard normalized.allSatisfy({ "0123456789.".contains($0) }),
              normalized.filter({ $0 == "." }).count <= 1 else { return nil }
        return Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX"))
    }
    var canRepeat: Bool {
        guard editingID == nil else { return false }
        return draft.originalNature == nil && (draft.type == .income || draft.type == .expense ||
            (draft.type == .deposit && account(draft.destinationID)?.kind == .investment))
    }
    var money: Int64 { draft.expression.evaluatedCents ?? 0 }
    /// A 转账 into a savings account is saved as 存入.
    var savesAsDeposit: Bool {
        draft.type == .deposit || (draft.type == .transfer && account(draft.destinationID)?.kind == .investment)
    }
    /// What 记下 needs: an amount, and a category unless the money only moves between accounts.
    var categoryReady: Bool { draft.isRoute || editingID != nil || draft.relatedEntryID != nil || selectedCategory != nil || suggestion != nil }
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
            if destination {
                guard draft.isRoute, account.id != draft.accountID else { return false }
                return draft.type != .deposit || [.investment, .bank, .cash].contains(account.kind)
            }
            return draft.type != .deposit || account.kind == .bank || account.kind == .cash
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
            let preferred = draft.type == .deposit ? destinations.first(where: { $0.kind == .investment }) : nil
            draft.destinationID = preferred?.id ?? destinations.first?.id
        }
    }
    func select(_ type: EntryType) {
        guard type != draft.tab else { return }
        needsCategory = false
        draft.type = type
        draft.originalNature = nil
        draft.relatedEntryID = nil
        draft.intoFixedSavings = false
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
        if let store { return store.update(reason, entryMotion: false, showToast: false, update) }
        do { try update(&fixtureLedger); return true }
        catch { failure = error.localizedDescription; return false }
    }

    private func input(category: CategoryAssignment?) -> EntrySaveInput? {
        guard let accountID = draft.accountID, draft.expression.canSave else { return nil }
        guard draft.currency == .cny || (signedRate != nil && (localMoney ?? 0) > 0) else { return nil }
        var input = EntrySaveInput(type: savesAsDeposit ? .deposit : draft.type, amountCents: money, currency: draft.currency, exchangeRate: signedRate,
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

    func schedulePreview() {
        previewTask?.cancel()
        let ledger = ledger
        let now = now
        let selection = selectedCategory
        let currentInput = input(category: selection)
        let purpose = draft.purpose
        let date = draft.date
        let nature = draft.nature
        let deposit = savesAsDeposit && editingID == nil
        let amount = localMoney ?? 0
        if !deposit { depositedThisCycle = nil }
        let needsGuess = !draft.isRoute && selection == nil && !purpose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
                    ? (Finance.spendableBreakdown(ledger, now: now).rows.first { $0.kind == .deposit }?.amount ?? 0) + amount
                    : nil
                return (guess, resolved.flatMap { EntrySaveMapper.effect(for: $0, in: ledger, now: now) }, deposited)
            }
            let (guess, preview, deposited) = await withTaskCancellationHandler {
                await computation.value
            } onCancel: { computation.cancel() }
            guard !Task.isCancelled else { return }
            self?.suggestion = guess
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
        switch blockedSave() {
        case .amount:
            amountPulse &+= 1
            return false
        case .category:
            needsCategory = true
            categoryPulse &+= 1
            return false
        case nil: break
        }
        if let store, let editingID, categoryOnly {
            guard let selection = selectedCategory else { return false }
            let result = store.update("改分类") { try CategoryModel.confirm(selection, entryIDs: [editingID], in: &$0) }
            didSave = result
            return result
        }
        let selection = selectedCategory ?? (draft.isRoute ? nil : suggestion)
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
                    store.lastEntryType = draft.type
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
