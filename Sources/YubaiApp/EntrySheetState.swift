import SwiftUI
import YubaiCore

enum EntryDrawer: Equatable {
    case purpose, currency, time, calendar, source, destination, subcategory, newCategory, renameCategory, split
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
    var explicitTime = false
    var screenshot: Data?
    var repeatMonthly = false
    var exception: EntryException?
    var incomeNextCycle = false
    var currency: BillCurrency = .cny
    var exchangeRate = ""
    var personalShare = ""
    var originalNature: Nature?
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
    var hasContent: Bool { !expression.isEmpty || !purpose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    init() {}

    init(prefill: QuickEntryPrefill, ledger: Ledger) {
        let nature = prefill.nature ?? .expense
        switch nature {
        case .investBuy: type = .deposit
        case .transfer where prefill.intoFixedSavings: type = .deposit
        default: type = nature.paired ? .transfer : nature.inflow ? .income : .expense
        }
        switch nature {
        case .expense, .income, .investBuy, .transfer, .repayment: break
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
    }
}

struct EntryResult: Equatable, Sendable {
    var title: String
    var value: String = ""
    var note = ""
    var warning = false
    var fraction: Double? = nil
}

@MainActor @Observable final class EntrySheetViewModel: Identifiable {
    let id = UUID()
    @ObservationIgnored private weak var store: AppStore?
    private var fixtureLedger: Ledger
    let settled: Bool
    let isPrefilled: Bool
    let fixtureNow: Date?
    var draft: EntrySheetDraft
    var drawer: EntryDrawer?
    var categoryPanel = false
    var categoryEditing = false
    var inputText = ""
    var suggestion: CategoryAssignment?
    var result = EntryResult(title: "记下后还能花")
    var categoryPulse = 0
    var failure: String?
    @ObservationIgnored private var previewTask: Task<Void, Never>?
    private var fixtureResult: EntryResult?
    private var fixtureBaseline: EntrySheetDraft?
    var fixtureTopCategories: [String] = []
    var routeShowsBalance = false
    var autoFocusSubcategory = true
    var fixtureDayLabel: String?
    var fixtureRepeatDay: Int?
    var fixtureSplitNames: [String] = []
    private(set) var didSave = false

    init(store: AppStore, prefill: QuickEntryPrefill?) {
        self.store = store
        fixtureLedger = Ledger()
        settled = false
        isPrefilled = prefill != nil
        fixtureNow = nil
        if let prefill {
            draft = EntrySheetDraft(prefill: prefill, ledger: store.current)
        } else if let retained = store.retainedEntryDraft {
            draft = retained
        } else {
            draft = EntrySheetDraft()
            draft.type = store.lastEntryType
            if store.accounts.contains(where: { $0.id == store.lastEntryAccountID && !$0.archived }) {
                draft.accountID = store.lastEntryAccountID
            }
        }
        normalizeAccounts()
    }

    init(fixtureLedger: Ledger, draft: EntrySheetDraft, now: Date, result: EntryResult) {
        store = nil
        self.fixtureLedger = fixtureLedger
        self.draft = draft
        settled = true
        isPrefilled = false
        fixtureNow = now
        self.result = result
        fixtureResult = result
        fixtureBaseline = draft
        normalizeAccounts()
    }

    var ledger: Ledger { store?.current ?? fixtureLedger }
    var now: Date { fixtureNow ?? Dates.now }
    var hasReceipt: Bool { draft.screenshot != nil }
    var hidesKeypad: Bool { drawer == .purpose || drawer == .calendar || (drawer == .subcategory && !categoryPanel) }
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
        draft.originalNature == nil && (draft.type == .income || draft.type == .expense ||
            (draft.type == .deposit && account(draft.destinationID)?.kind == .investment))
    }
    var money: Int64 { draft.expression.evaluatedCents ?? 0 }
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
        ledger.accounts.filter { account in
            guard !account.archived else { return false }
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
        guard type != draft.type else { return }
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
        suggestion = nil
        drawer = nil
        normalizeAccounts()
    }
    func select(category: String) {
        if draft.category != category { draft.subcategory = nil }
        draft.category = category
        suggestion = nil
        if drawer == .subcategory { drawer = nil }
    }

    func toggleDrawer(_ target: EntryDrawer) {
        inputText = ""
        if target == .subcategory { autoFocusSubcategory = true }
        drawer = drawer == target ? nil : target
    }

    func toggleRepeat() {
        draft.repeatMonthly.toggle()
        if draft.repeatMonthly { draft.exception = nil }
        fixtureRepeatDay = nil
        drawer = nil
    }

    func cycleException() {
        switch draft.exception {
        case nil: draft.exception = .reserve
        case .reserve: draft.exception = .reimbursement
        case .reimbursement: draft.exception = .split
        case .split: draft.exception = nil
        }
        if draft.exception != nil { draft.repeatMonthly = false }
        if drawer == .split && draft.exception != .split { drawer = nil }
    }

    func setDay(_ offset: Int) {
        draft.date = Dates.addDays(offset, to: now)
        draft.explicitTime = false
        fixtureDayLabel = nil
        drawer = nil
    }

    var dayLabel: String {
        if let fixtureDayLabel { return fixtureDayLabel }
        let day = Dates.day(draft.date)
        if !draft.explicitTime {
            if day == Dates.day(now) { return "今天" }
            if day == Dates.day(Dates.addDays(-1, to: now)) { return "昨天" }
            if day == Dates.day(Dates.addDays(-2, to: now)) { return "前天" }
        }
        let parts = Dates.calendar.dateComponents([.month, .day, .hour, .minute], from: draft.date)
        let label = "\(parts.month ?? 1)月\(parts.day ?? 1)日"
        guard draft.explicitTime else { return label }
        return label + String(format: " %02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    func setDate(_ value: Date) {
        draft.date = value
        draft.explicitTime = true
        fixtureDayLabel = nil
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
        drawer = nil
        categoryEditing = false
        categoryPanel = false
    }

    func renameCategory() {
        let name = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let category = draft.category, !name.isEmpty else { return }
        if name == category { drawer = nil; return }
        let income = draft.nature.categoryIncome
        if mutateLedger("编辑分类", { try CategoryModel.rename(category, to: name, income: income, in: &$0) }) {
            draft.category = name
            drawer = nil
        }
    }

    func addCategory() {
        let name = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let new = YubaiCore.Category(name, income: draft.nature.categoryIncome)
        if mutateLedger("添加分类", { try CategoryModel.add(new, in: &$0) }) {
            select(category: name)
            drawer = nil
        }
    }

    func addSubcategory() {
        let name = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let category = draft.category, !name.isEmpty else { return }
        let income = draft.nature.categoryIncome
        if mutateLedger("添加小类", { try CategoryModel.addSubcategory(name, to: category, income: income, in: &$0) }) {
            draft.subcategory = name
            drawer = nil
        }
    }

    private func mutateLedger(_ reason: String, _ update: (inout Ledger) throws -> Void) -> Bool {
        if let store { return store.update(reason, entryMotion: false, showToast: false, update) }
        do { try update(&fixtureLedger); return true }
        catch { failure = error.localizedDescription; return false }
    }

    private func input(category: CategoryAssignment?) -> EntrySaveInput? {
        guard let accountID = draft.accountID, draft.expression.canSave else { return nil }
        guard draft.currency == .cny || (signedRate != nil && (localMoney ?? 0) > 0) else { return nil }
        return EntrySaveInput(type: draft.type, amountCents: money, currency: draft.currency, exchangeRate: signedRate,
            purpose: draft.purpose, category: category?.category ?? Classification.pendingCategory,
            subcategory: category?.subcategory, accountID: accountID, destinationAccountID: draft.destinationID,
            date: draft.date, repeatMonthly: draft.repeatMonthly && canRepeat, exception: draft.exception,
            incomeNextCycle: draft.incomeNextCycle, personalExpenseCents: myShare, recordedNature: draft.originalNature,
            relatedEntryID: draft.relatedEntryID, keepInFixedSavings: draft.intoFixedSavings, preserveTime: draft.explicitTime)
    }

    private var selectedCategory: CategoryAssignment? {
        draft.category.map { CategoryAssignment(category: $0, subcategory: draft.subcategory) }
    }

    func schedulePreview() {
        previewTask?.cancel()
        if draft == fixtureBaseline, let fixtureResult {
            result = fixtureResult
            return
        }
        let ledger = ledger
        let now = now
        let selection = selectedCategory
        let currentInput = input(category: selection)
        let purpose = draft.purpose
        let date = draft.date
        let nature = draft.nature
        let needsGuess = !draft.isRoute && selection == nil && !purpose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if !needsGuess { suggestion = nil }
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
                return (guess, Self.project(resolved, ledger: ledger, now: now))
            }
            let (guess, preview) = await withTaskCancellationHandler {
                await computation.value
            } onCancel: { computation.cancel() }
            guard !Task.isCancelled else { return }
            self?.suggestion = guess
            self?.result = preview
        }
    }

    func cancelPreview() {
        previewTask?.cancel()
        previewTask = nil
    }

    nonisolated private static func project(_ input: EntrySaveInput?, ledger: Ledger, now: Date) -> EntryResult {
        let before = Finance.spendableBreakdown(ledger, now: now)
        guard let input,
              let change = try? EntrySaveMapper.makeChange(input, in: ledger, now: now) else {
            return EntryResult(title: before.offersFormula ? "本月还能花" : before.headlineTitle,
                               value: Money.text(before.headlineAmount))
        }
        var updated = ledger
        guard (try? change.apply(to: &updated)) != nil else { return EntryResult(title: "记下后还能花") }
        let after = Finance.spendableBreakdown(updated, now: now)
        let delta = EntrySaveMapper.cnyAmount(for: input, in: ledger, now: now) ?? 0
        let unchanged = after.headlineAmount == before.headlineAmount && after.state == before.state
        let title = after.offersFormula ? (input.type == .deposit ? "存入后本月可花" : "记下后还能花") : after.headlineTitle
        var result = EntryResult(title: title, value: unchanged ? "不变" : Money.text(after.headlineAmount))
        if after.deficit > 0 {
            result.title = "缺口"
            result.warning = true
        }
        if let entry = change.items.compactMap({ item -> UUID? in
            guard case .addEntry(let draft) = item else { return nil }
            return draft.id
        }).first,
           let line = SoftLines.usage(updated, now: now).first(where: { $0.entryIDs.contains(entry) }) {
            let remaining = line.isExceeded ? line.exceeded : line.remaining
            let formatted = line.mode == .count ? "\(remaining) 次" : Money.text(remaining, currency: false)
            result.note = "\(line.title)\(line.isExceeded ? "超" : "剩") \(formatted)"
            result.warning = result.warning || line.isExceeded
            result.fraction = line.fraction
        }
        if input.type == .deposit {
            let saved = updated.activeEntries.lazy.filter {
                $0.date >= after.cycleStart && $0.date <= now &&
                    ($0.nature == .investBuy || ($0.intoFixedSavings && ($0.nature == .income || $0.nature == .transfer)))
            }.reduce(Int64(0)) { $0 + $1.amount }
            result.note = "本期已攒下 " + Money.text(saved, currency: false)
        } else if input.exception == .split {
            result.note = "待收回 " + Money.text(max(0, delta - (input.personalExpenseCents ?? 0)), currency: false)
        } else if input.exception == .reimbursement {
            result.note = "暂扣 " + Money.text(delta, currency: false)
        } else if input.exception == .reserve {
            result.note = "机动余钱 → " + Money.text(updated.fixedSavingsTotal(now: now), currency: false)
        } else if input.repeatMonthly && input.type == .expense {
            result.note = "下期起期初预扣 " + Money.text(delta, currency: false)
        } else if input.repeatMonthly && input.type == .income {
            result.note = "下期起每月计入 " + Money.text(delta, currency: false)
        } else if input.incomeNextCycle {
            result.note = "本期不变"
        }
        return result
    }

    func save() -> Bool {
        guard !didSave, draft.expression.canSave else { return false }
        let selection = selectedCategory ?? (draft.isRoute ? nil :
            CategoryGuesser.guess(draft.purpose, nature: draft.nature, date: draft.date, in: ledger))
        if !draft.isRoute, selection == nil, draft.relatedEntryID == nil {
            categoryPulse &+= 1
            return false
        }
        guard let input = input(category: selection) else {
            failure = draft.accountID == nil ? "先选择一个账户。" : "请核对金额或汇率。"
            return false
        }
        let now = now
        let userSelected = selectedCategory != nil
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
        normalizeAccounts()
    }
    #endif

    func retainDraft() {
        guard let store, !didSave, !isPrefilled || draft.hasContent else { return }
        store.retainedEntryDraft = draft.hasContent ? draft : nil
    }
}
