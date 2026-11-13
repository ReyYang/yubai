import SwiftUI
import Observation
import LocalAuthentication
import YubaiCore
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

enum Destination: String, CaseIterable, Identifiable {
    case now, saving, ledger, yubai
    var id: Self { self }
    var title: String { switch self { case .now: "现在"; case .saving: "存钱"; case .ledger: "账本"; case .yubai: "余白" } }
    /// SF Symbol for the large content viewer and the macOS sidebar fallback.
    var symbol: String { switch self { case .now: "clock"; case .saving: "banknote"; case .ledger: "text.book.closed"; case .yubai: "leaf" } }
}
/// 算式页里可以就地改的三项。
enum FormulaField: Hashable { case fixedSavings, saving, hand }
/// 账本页的两个视图（`ledgerMode_detail` / `ledgerMode_where`）。
enum LedgerMode: String, CaseIterable, Identifiable {
    case detail, whereTo = "where"
    var id: Self { self }
}
/// 其他页面跳到账本页时带的筛选；账本页读到后清空 `AppStore.ledgerPreset`。
struct LedgerPreset: Equatable {
    var mode: LedgerMode = .whereTo
    var interval: DateInterval? = nil
    var category: String? = nil
    var search = ""
    var token = UUID()
}
enum TabRoute: Hashable {
    case fixedFlows, profile, wishlist, accounts
    case triage([UUID])
    case quickCapture, importHistory, intelligencePrivacy, backup, storage
    case unsortedGroups(UUID), quickSortUnsorted(UUID)
    case flowRecords(categories: [String], title: String, income: Bool, interval: DateInterval)
    case subcategoryInsights(category: String, income: Bool, interval: DateInterval, periodTitle: String)
    case formula, budget, billDetail(UUID), todo, settings, categories, savingRule, reserve, saved
    case weekly(UUID?), whereCategory(category: String, interval: DateInterval), memories
    case entryDetail(UUID)
    case allCategories(DateInterval), categoryBudget(String), savingWish(UUID), askQuestion(String)
}

struct TabNavigationLink<Content: View, Label: View>: View {
    @Environment(\.yubaiSheetSurface) private var inSheet
    let route: TabRoute
    let destination: () -> Content
    let label: () -> Label
    init(_ route: TabRoute, @ViewBuilder destination: @escaping () -> Content, @ViewBuilder label: @escaping () -> Label) {
        self.route = route; self.destination = destination; self.label = label
    }
    var body: some View {
        #if os(iOS)
        if inSheet { NavigationLink(destination: destination, label: label).navigationLinkIndicatorVisibility(.hidden) }
        else { NavigationLink(value: route, label: label).navigationLinkIndicatorVisibility(.hidden) }
        #else
        NavigationLink(destination: destination, label: label)
        #endif
    }
}

enum AppSheet: Identifiable {
    case account(Account?), imports, accounts, backup, history, syncVersions, addEntry, addPlan, intelligencePrivacy
    case editEntry(UUID), editPlan(UUID), prefilledEntry(QuickEntryPrefill), screenshotCapture(Data?), screenshotReview(Data)
    case ask(String), wishlist(UUID?)
    case cardEvidence(UUID), cardQuestion(UUID), cardProposal(UUID), letter(UUID), reconcile(UUID)
    case reconcileAll, overspend(CycleCover.Source), paydayAmount
    case billPay(planID: UUID, occurrence: Date), billMatch(planID: UUID, occurrence: Date, entryID: UUID), billLink(planID: UUID, occurrence: Date)
    case formulaEdit(FormulaField), frequentEntries
    case billMove(planID: UUID, occurrence: Date)
    var id: String { String(describing: self) }
    var motionSource: String? {
        switch self {
        case .addEntry: nil
        case .ask: "ask"
        case .cardEvidence(let id), .cardQuestion(let id): "card-" + id.uuidString
        default: nil
        }
    }
}

@MainActor @Observable final class AppStore {
    static let shared = AppStore()
    var tabRouteRequest: TabRoute?
    private(set) var ledger = Ledger() {
        didSet {
            if oldValue.id != ledger.id {
                askConversation = AskConversationState()
                resetRootNavigation()
            }
            if oldValue != ledger { invalidateDerived() }
        }
    }
    var current: Ledger { ledger }
    // These slices never register access to ledger when a view reads them.
    private(set) var preferences = Preferences()
    private(set) var accounts: [Account] = []
    private(set) var cards: [ButlerCard] = []
    private(set) var profile = SpendingProfile()
    private(set) var plans: [Plan] = []
    private(set) var rents: [Rent] = []
    private(set) var imports: [ImportBatch] = []
    private(set) var lastRecordedEntry: Entry?
    private(set) var mutedTopics: [String] = []
    private(set) var categoryAliases: [String: String] = [:]
    func resolveCategory(_ category: String, income: Bool) -> String {
        _ = categoryAliases
        return derivedSource.resolveCategory(category, income: income)
    }
    func subcategoryBreakdown(category: String, income: Bool, during interval: DateInterval) -> [Breakdown] {
        _ = ledgerRevision
        return presentationCache.subcategoryBreakdown(in: derivedSource, category: category, income: income, during: interval, revision: sourceRevision)
    }
    func evidenceEntries(_ ids: Set<UUID>, activeOnly: Bool = false) -> [Entry] {
        // Resolve only the requested IDs, retaining sortedEntries' stable order
        // for equal dates (including deleted rows where the caller allowed them).
        _ = ledgerRevision
        return presentationCache.evidenceEntries(in: derivedSource, ids: ids, activeOnly: activeOnly, revision: sourceRevision)
    }
    @ObservationIgnored private var derivedSource = Ledger()
    @ObservationIgnored private var sourceRevision: UInt64 = 0
    @ObservationIgnored private var preparedDerived: LedgerDerivedSnapshot?
    @ObservationIgnored private var preparedPending: PendingImportOrganization?
    @ObservationIgnored private var preparedSalary: (day: Date, value: SalaryCandidate?)?
    private var fundsRevision = 0
    private var entriesRevision = 0
    private var manualPurposesRevision = 0
    private var entryTimelineRevision = 0
    private var pendingRevision = 0
    private var visibilityRevision = 0
    private var progressRevision = 0
    private var salaryRevision = 0
    @ObservationIgnored private var visibilityBatches: Set<UUID> = []
    @ObservationIgnored private var presentationCache = LedgerPresentationCache()
    @ObservationIgnored private var cachedManualPurposes: [UUID: String]?
    var manualNotePurposes: [UUID: String] {
        _ = manualPurposesRevision
        if let cachedManualPurposes { return cachedManualPurposes }
        let value = EntryNotePresentation.manualPurposes(derivedSource.entries)
        cachedManualPurposes = value; return value
    }
    var savingsTotals: LedgerSavingsTotals {
        _ = ledgerRevision
        return presentationCache.savings(in: derivedSource, revision: sourceRevision)
    }
    var recentCaptures: [Entry] {
        _ = ledgerRevision
        return presentationCache.recentCaptures(in: derivedSource, revision: sourceRevision)
    }
    private struct AssessmentKey: Hashable {
        let amount: Int64; let title: String; let category: String?; let subcategory: String?
    }
    @ObservationIgnored private var cachedAssessments: [AssessmentKey: (at: Date, value: PurchaseAssessment)] = [:]
    func purchaseAssessment(_ purchase: PurchaseJudgment) -> PurchaseAssessment {
        _ = ledgerRevision
        _ = funds
        let at = cachedFunds!.at
        let key = AssessmentKey(amount: purchase.amount, title: purchase.title, category: purchase.category, subcategory: purchase.subcategory)
        if let cached = cachedAssessments[key], cached.at == at { return cached.value }
        let value = Finance.assessPurchase(derivedSource, amount: purchase.amount, title: purchase.title, category: purchase.category, subcategory: purchase.subcategory)
        if cachedAssessments.count >= 32 { cachedAssessments.removeAll(keepingCapacity: true) }
        cachedAssessments[key] = (at, value); return value
    }
    func cashFlow(during interval: DateInterval) -> CashFlowSummary {
        _ = ledgerRevision
        return presentationCache.cashFlow(in: derivedSource, during: interval, revision: sourceRevision)
    }
    func cashFlowSlices(during interval: DateInterval, income: Bool) -> [CashFlowSlice] {
        _ = ledgerRevision
        return presentationCache.cashFlowSlices(in: derivedSource, during: interval, income: income, revision: sourceRevision)
    }
    func flowRecords(categories: [String], income: Bool, interval: DateInterval, subcategory: String? = nil) -> [Entry] {
        _ = ledgerRevision
        return presentationCache.flowRecords(in: derivedSource, categories: categories, income: income,
                                             interval: interval, subcategory: subcategory, revision: sourceRevision)
    }
    var subscriptionCandidates: [SubscriptionCandidate] {
        _ = ledgerRevision
        return presentationCache.subscriptions(in: derivedSource, revision: sourceRevision)
    }
    var settingsSummary: LedgerSettingsSummary {
        _ = ledgerRevision
        return presentationCache.settings(in: derivedSource, revision: sourceRevision)
    }
    func accountName(_ id: UUID?) -> String { accounts.first { $0.id == id }?.name ?? "未指定账户" }
    var freshLetter: ButlerCard? {
        _ = mutedTopics
        return cards.first { card in
            WeeklyLetter.isFresh(card, now: Date()) && !ButlerCards.isMuted(card.dedupeKey, in: derivedSource)
        }
    }
    @ObservationIgnored var preparingImportOrganization = false
    @ObservationIgnored private var derivedRevision = 0
    private(set) var ledgerRevision: UInt64 = 0
    // Cache writes during rendering are unobserved; the revision notifies readers when their inputs change.
    @ObservationIgnored private var cachedFunds: (value: Funds, at: Date, expires: Date, zone: TimeZone)?
    @ObservationIgnored private var cachedEntries: [Entry]?
    @ObservationIgnored private var cachedEntriesByID: [UUID: Entry]?
    @ObservationIgnored private var cachedAccountEntries: [UUID: [Entry]] = [:]
    @ObservationIgnored private var cachedBalances: [UUID: (at: Date, value: Int64)] = [:]
    @ObservationIgnored private var cachedFixedMonth: FixedFlowMonth?
    @ObservationIgnored private var cachedRestrainProgress: [RestrainProgress]?
    let ledgerWriter = LedgerWriteQueue()
    @ObservationIgnored var persistenceTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored var persistenceEpoch: UInt64 = 0
    @ObservationIgnored var lastUploadedPersistenceRevision: UInt64 = 0
    #if os(macOS)
    @ObservationIgnored private var terminationObserver: NSObjectProtocol?
    #endif
    var recoveringWriteFailure = false
    @ObservationIgnored private var cachedEntryTimeline: (month: Date, search: String, filter: EntryTimeline.Filter, allMonths: Bool, calendar: Calendar, value: EntryTimeline.Snapshot)?
    @ObservationIgnored private var cachedPendingOrganization: PendingImportOrganization?
    @ObservationIgnored private var cachedSalary: (day: Date, value: SalaryCandidate?)?
    var pendingOrganization: PendingImportOrganization {
        _ = pendingRevision
        return pendingOrganizationValue()
    }
    private func pendingOrganizationValue() -> PendingImportOrganization {
        if let cachedPendingOrganization { return cachedPendingOrganization }
        let value = PendingImportOrganization(in: derivedSource); cachedPendingOrganization = value; return value
    }
    var nowSalaryCandidate: SalaryCandidate? {
        _ = salaryRevision
        return salaryValue()
    }
    private func salaryValue() -> SalaryCandidate? {
        let day = Dates.day(Date())
        if let cachedSalary, cachedSalary.day == day { return cachedSalary.value }
        let value = SalaryDetection.candidate(in: derivedSource); cachedSalary = (day, value); return value
    }
    @ObservationIgnored private var cachedButlerVisibility: (revision: Int, day: Date, batches: Set<UUID>, value: SavingCardVisibility.Snapshot)?
    var butlerVisibility: SavingCardVisibility.Snapshot {
        _ = visibilityRevision
        return visibilityValue()
    }
    private func visibilityValue() -> SavingCardVisibility.Snapshot {
        let day = Dates.day(Date()), batches = visibilityBatches
        if let cached = cachedButlerVisibility, cached.revision == derivedRevision, cached.day == day, cached.batches == batches { return cached.value }
        let value = SavingCardVisibility.snapshot(in: derivedSource, organizingBatchIDs: batches, progress: progressValue(),
                                                 fallbackEntryCount: { question in
            self.cachedUnsortedGroups.snapshot(for: question.id, revision: self.sourceRevision, in: self.derivedSource)?.entryCount ?? 0
        })
        cachedButlerVisibility = (derivedRevision, day, batches, value); return value
    }
    @ObservationIgnored private var cachedUnsortedGroups = UnsortedGroupsCache()
    func unsortedGroups(questionID: UUID) -> UnsortedGroupsSnapshot? {
        cachedUnsortedGroups.snapshot(for: questionID, revision: ledgerRevision, in: current)
    }
    func unsortedEntryCount(for question: ImportQuestion) -> Int {
        guard question.isFallback else { return 0 }
        return unsortedGroups(questionID: question.id)?.entryCount ?? 0
    }
    func unsortedChangeSet(questionID: UUID, groupID: String, use: UnsortedUse,
                          category: String?, otherAccount: UUID?, entryIDs: Set<UUID>? = nil,
                          purpose: String? = nil) -> ChangeSet? {
        cachedUnsortedGroups.changeSet(groupID: groupID, questionID: questionID, use: use,
                                      category: category, otherAccount: otherAccount, entryIDs: entryIDs,
                                      purpose: purpose, revision: ledgerRevision, in: current)
    }
    func unsortedChangeSet(questionID: UUID, groupIDs: Set<String>, use: UnsortedUse,
                          category: String?, otherAccount: UUID?) -> ChangeSet? {
        cachedUnsortedGroups.changeSet(groupIDs: groupIDs, questionID: questionID, use: use,
                                      category: category, otherAccount: otherAccount, revision: ledgerRevision, in: current)
    }
    var funds: Funds {
        _ = fundsRevision
        return fundsValue()
    }
    private func fundsValue() -> Funds {
        let now = Date(); let zone = TimeZone.current
        if let cached = cachedFunds, cached.zone == zone, now >= cached.at, now < cached.expires { return cached.value }
        let ledger = derivedSource; var expires = Dates.addDays(1, to: Dates.day(now))
        for entry in ledger.entries where entry.deletedAt == nil {
            if entry.date > now { expires = min(expires, entry.date) }
            if let date = entry.otherDate, date > now { expires = min(expires, date) }
        }
        for account in ledger.accounts {
            let stale = account.anchorDate.addingTimeInterval(14 * 86400)
            if stale >= now { expires = min(expires, stale) }
        }
        let value = Finance.funds(ledger, now: now)
        cachedFunds = (value, now, expires, zone); return value
    }
    var restrainProgress: [RestrainProgress] {
        _ = progressRevision
        return progressValue()
    }
    private func progressValue() -> [RestrainProgress] {
        if let cachedRestrainProgress { return cachedRestrainProgress }
        let value = RestrainProgress.current(ledger: derivedSource); cachedRestrainProgress = value; return value
    }
    // MARK: Round 45 derived values
    // Every slot is keyed on the funds cache's timestamp, so a value is recomputed once per ledger
    // change or per day, never while a view body is evaluated twice. Only `pace` is prepared off-main.
    private let paceSlot = TimedSlot<CyclePace?>()
    private let homeTasksSlot = TimedSlot<[HomeTask]>()
    private let butlerSavedSlot = TimedSlot<Int64>()
    private let formulaSlot = TimedSlot<SpendableFormula>()
    private let reserveSlot = TimedSlot<ReserveOverview>()
    private let paybackOffersSlot = TimedSlot<[ReservePaybackOffer]>()
    private let paybackProgressSlot = TimedSlot<[ReservePaybackProgress]>()
    private let paydaySlot = TimedSlot<Payday.Due?>()
    private let gapSlot = TimedSlot<Reconciliation.Gap?>()
    private let leftoverSlot = TimedSlot<CycleSaving?>()
    private let overspendSlot = TimedSlot<Overspend.Options?>()
    private var timeRevision = 0
    private func derived<Value>(_ slot: TimedSlot<Value>, _ compute: (Ledger, Date) -> Value) -> Value {
        _ = timeRevision
        _ = fundsValue()
        let at = cachedFunds?.at ?? Date()
        let source = derivedSource
        return slot.value(at: at) { compute(source, at) }
    }
    /// 日均；`nil` = 还不知道发薪日。
    var pace: CyclePace? { derived(paceSlot) { Finance.pace($0, now: $1) } }
    var homeTasks: [HomeTask] {
        _ = visibilityRevision
        let batches = organizingImportBatchIDs
        return derived(homeTasksSlot) { HomeButler.queue($0, now: $1, organizingBatchIDs: batches) }
    }
    var butlerSaved: Int64 { derived(butlerSavedSlot) { ButlerSavings.total($0, now: $1) } }
    /// 算式页四行（`Finance.formula`）。
    var formula: SpendableFormula { derived(formulaSlot) { Finance.formula($0, now: $1) } }
    /// 存钱页：存下的总额与最近进出。
    var reserve: ReserveOverview { derived(reserveSlot) { Reserve.overview($0, now: $1) } }
    var paybackOffers: [ReservePaybackOffer] { derived(paybackOffersSlot) { Reserve.paybackOffers($0, now: $1) } }
    var paybackProgress: [ReservePaybackProgress] { derived(paybackProgressSlot) { Reserve.paybackProgress($0, now: $1) } }
    var financialNow: Date { _ = timeRevision; _ = fundsValue(); return cachedFunds?.at ?? Date() }
    /// 发薪日到了或晚了、还没确认到账。
    var paydayDue: Payday.Due? { derived(paydaySlot) { Payday.due(in: $0, now: $1) } }
    /// 几天没记。
    var recordGap: Reconciliation.Gap? { derived(gapSlot) { Reconciliation.gap(in: $0, now: $1) } }
    /// 上个周期剩下的钱，还没问怎么处理。
    var pendingLeftover: CycleSaving? { derived(leftoverSlot) { ledger, _ in Savings.pendingLeftover(in: ledger) } }
    /// 周期超了的两条补法；没超为 `nil`。
    var overspend: Overspend.Options? { derived(overspendSlot) { Overspend.options($0, now: $1) } }

    // MARK: 今天先不问
    private(set) var snoozeRevision = 0
    private func snoozeStorageKey(_ key: String, forever: Bool) -> String {
        "yubai.snooze." + derivedSource.id.uuidString + "." + (forever ? "-" : Dates.text(Date())) + "." + key
    }
    /// 记在本机，不进账本。默认只到今天结束；`forever` 用于「这段空档不再提」这类按内容记住的。
    func snooze(_ key: String, forever: Bool = false) {
        UserDefaults.standard.set(true, forKey: snoozeStorageKey(key, forever: forever))
        snoozeRevision &+= 1
    }
    func isSnoozed(_ key: String, forever: Bool = false) -> Bool {
        _ = snoozeRevision
        return UserDefaults.standard.bool(forKey: snoozeStorageKey(key, forever: forever))
    }

    // MARK: 最近问过的（只存问题文字和时间，本机）
    private(set) var questionsRevision = 0
    private var recentQuestionsKey: String { "yubai.recentQuestions." + derivedSource.id.uuidString }
    var recentQuestions: [(text: String, date: Date)] {
        _ = questionsRevision
        let raw = UserDefaults.standard.array(forKey: recentQuestionsKey) as? [[String: Any]] ?? []
        return raw.compactMap { item -> (text: String, date: Date)? in
            guard let text = item["t"] as? String, let stamp = item["d"] as? Double else { return nil }
            return (text: text, date: Date(timeIntervalSince1970: stamp))
        }
    }
    func recordQuestion(_ text: String, at date: Date = Date()) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        var rows = recentQuestions.filter { $0.text != clean }
        rows.insert((text: clean, date: date), at: 0)
        let stored: [[String: Any]] = rows.prefix(10).map { ["t": $0.text, "d": $0.date.timeIntervalSince1970] }
        UserDefaults.standard.set(stored, forKey: recentQuestionsKey)
        questionsRevision &+= 1
    }

    var fixedFlowMonth: FixedFlowMonth {
        _ = ledgerRevision
        if let cachedFixedMonth { return cachedFixedMonth }
        let now = financialNow
        let value = FixedFlows.month(containing: now, in: derivedSource, asOf: now); cachedFixedMonth = value; return value
    }
    var entriesByID: [UUID: Entry] {
        _ = ledgerRevision
        if let cachedEntriesByID { return cachedEntriesByID }
        let value = Dictionary(uniqueKeysWithValues: derivedSource.entries.map { ($0.id, $0) })
        cachedEntriesByID = value; return value
    }
    func accountEntries(_ id: UUID) -> [Entry] {
        _ = ledgerRevision
        if let cached = cachedAccountEntries[id] { return cached }
        let value = Array(sortedEntries.lazy.filter { $0.deletedAt == nil && ($0.accountID == id || $0.otherAccountID == id) }.prefix(100))
        cachedAccountEntries[id] = value; return value
    }
    func balance(_ account: Account, at: Date? = nil) -> Int64 {
        _ = ledgerRevision
        // Default balances share the funds cache's expiry (future posting dates).
        let moment = at ?? { _ = funds; return cachedFunds!.at }()
        if let cached = cachedBalances[account.id], cached.at == moment { return cached.value }
        let value = Finance.balance(account, in: derivedSource, at: moment)
        cachedBalances[account.id] = (moment, value); return value
    }
    var sortedEntries: [Entry] {
        _ = entriesRevision
        return sortedEntriesValue()
    }
    private func sortedEntriesValue() -> [Entry] {
        if let cachedEntries { return cachedEntries }
        let rows = derivedSource.entries.sorted { $0.date > $1.date }
        cachedEntries = rows; return rows
    }
    func entryTimeline(month: Date, search: String, filter: EntryTimeline.Filter, allMonths: Bool = false) -> EntryTimeline.Snapshot {
        _ = entryTimelineRevision
        return entryTimelineValue(month: month, search: search, filter: filter, allMonths: allMonths)
    }
    private func entryTimelineValue(month: Date, search: String, filter: EntryTimeline.Filter, allMonths: Bool = false) -> EntryTimeline.Snapshot {
        let calendar = Dates.calendar
        if let cached = cachedEntryTimeline, cached.month == month, cached.search == search, cached.filter == filter, cached.allMonths == allMonths, cached.calendar == calendar { return cached.value }
        let value = EntryTimeline.snapshot(sortedEntries: sortedEntriesValue(), ledger: derivedSource, month: month, search: search, filter: filter, calendar: calendar, allMonths: allMonths)
        cachedEntryTimeline = (month, search, filter, allMonths, calendar, value)
        return value
    }
    private func invalidateDerived() {
        let previousEntries = derivedSource.entries
        derivedSource = ledger
        if preferences != ledger.preferences { preferences = ledger.preferences }
        if accounts != ledger.accounts { accounts = ledger.accounts }
        if cards != ledger.cards { cards = ledger.cards }
        if profile != ledger.profile { profile = ledger.profile }
        if plans != ledger.plans { plans = ledger.plans }
        if rents != ledger.rents { rents = ledger.rents }
        if imports != ledger.imports { imports = ledger.imports }
        if mutedTopics != ledger.mutedTopics { mutedTopics = ledger.mutedTopics }
        if categoryAliases != ledger.categoryAliases { categoryAliases = ledger.categoryAliases }
        sourceRevision &+= 1
        ledgerRevision = sourceRevision
        let oldTimeline = cachedEntryTimeline
        if previousEntries != ledger.entries {
            let last = ledger.entries.filter { $0.deletedAt == nil }.max {
                let a = $0.recordedAt ?? $0.date, b = $1.recordedAt ?? $1.date
                return a == b ? $0.id.uuidString < $1.id.uuidString : a < b
            }
            if lastRecordedEntry != last { lastRecordedEntry = last }
            let oldEntries = cachedEntries, oldPurposes = cachedManualPurposes
            cachedEntries = preparedDerived?.entries
            cachedEntriesByID = preparedDerived?.entriesByID
            cachedAccountEntries = [:]; cachedManualPurposes = nil
            if let oldEntries, sortedEntriesValue() != oldEntries { entriesRevision &+= 1 }
            if let oldPurposes {
                let next = EntryNotePresentation.manualPurposes(derivedSource.entries)
                cachedManualPurposes = next
                if oldPurposes != next { manualPurposesRevision &+= 1 }
            }
        }
        cachedEntryTimeline = nil
        if let oldTimeline {
            let next = entryTimelineValue(month: oldTimeline.month, search: oldTimeline.search, filter: oldTimeline.filter, allMonths: oldTimeline.allMonths)
            if next != oldTimeline.value { entryTimelineRevision &+= 1 }
        }
        let oldPending = cachedPendingOrganization
        cachedPendingOrganization = preparedPending
        if let oldPending, pendingOrganizationValue() != oldPending { pendingRevision &+= 1 }
        refreshTimeDerived()
        preparedDerived = nil; preparedPending = nil; preparedSalary = nil
    }
    func refreshTimeDerived() {
        let oldFunds = cachedFunds?.value
        let oldProgress = cachedRestrainProgress, oldSalary = cachedSalary
        let oldVisibility = cachedButlerVisibility?.value
        cachedFunds = preparedDerived.map { ($0.funds, $0.at, $0.expires, $0.zone) }
        cachedBalances = [:]; cachedAssessments = [:]; cachedFixedMonth = preparedDerived?.fixedMonth
        cachedRestrainProgress = preparedDerived?.progress; cachedSalary = preparedSalary
        if let preparedDerived { paceSlot.prime(at: preparedDerived.at, preparedDerived.pace) } else { paceSlot.clear() }
        formulaSlot.clear(); reserveSlot.clear(); paydaySlot.clear(); gapSlot.clear()
        paybackOffersSlot.clear(); paybackProgressSlot.clear()
        leftoverSlot.clear(); overspendSlot.clear(); homeTasksSlot.clear(); butlerSavedSlot.clear()
        timeRevision &+= 1
        derivedRevision &+= 1
        cachedButlerVisibility = nil
        if let preparedDerived, preparedDerived.organizingBatchIDs == visibilityBatches {
            cachedButlerVisibility = (derivedRevision, Dates.day(preparedDerived.at), visibilityBatches, preparedDerived.visibility)
        }
        if let oldFunds, fundsValue() != oldFunds { fundsRevision &+= 1 }
        if let oldProgress, progressValue() != oldProgress { progressRevision &+= 1 }
        if let oldSalary, salaryValue() != oldSalary.value { salaryRevision &+= 1 }
        if let oldVisibility, visibilityValue() != oldVisibility { visibilityRevision &+= 1 }
        CaptureSnapshotBridge.publish(ledger)
    }
    private func refreshVisibility() {
        homeTasksSlot.clear()
        visibilityBatches = organizingImportBatchIDs
        let previous = cachedButlerVisibility?.value
        cachedButlerVisibility = nil
        if let previous, visibilityValue() != previous { visibilityRevision &+= 1 }
    }
    let localRepository: LedgerRepository
    var locations: LedgerLocations
    var ledgerLocation: LedgerLocation = .local
    var repository: LedgerRepository { (try? locations.repository(for: ledgerLocation)) ?? localRepository }
    let syncAllowed: Bool
    var syncBusy = false
    var checkingCloudAvailability = false
    var syncRefreshRequested = false
    var syncAvailabilityNeedsRefresh = false
    var switchingLedgerLocation = false
    var choosingSyncVersion = false
    var syncStatus: String?
    var syncChoice: SyncChoice?
    var pendingUpload: Ledger?
    var pendingUploadPreservingRecovery = true
    var pendingUploadRecoveryReason = "修改"
    @ObservationIgnored var syncMonitor: CloudLedgerMonitor?
    var iCloudAvailable: Bool { locations.cloud != nil }
    var destination: Destination = .now
    private(set) var navigationRevision: UInt64 = 0
    func resetRootNavigation() {
        destination = .now; pickingInsightDates = false; ledgerPreset = nil
        homeReceipt = nil
        unsortedUndo = nil; unsortedUndoRestoration = nil
        #if os(iOS)
        if pagingLocked { pagingLocked = false }
        #endif
        navigationRevision &+= 1
    }
    #if os(iOS)
    var pagingLocked = false
    #endif
    var askConversation = AskConversationState()
    var rootScrollRequest: [Destination: Int] = [:]
    var sheet: AppSheet?; var error: String?; var toast: String?
    var homeReceipt: ButlerReceipt?
    var butlerFocusID: String?
    var pendingButlerTaskID: String?
    var unsortedUndo: UnsortedUndoNotice?
    var unsortedUndoRestoration: UnsortedUndoRestoration?
    var sheetSource: String?
    var entrySaveTrigger = 0; var entryDeleteTrigger = 0; var undoTrigger = 0; var floorWarningTrigger = 0
    var fixedFlowSettleTrigger = 0
    var freshEntryIDs: Set<UUID> = []
    var pendingEntrySave = false
    @ObservationIgnored private var pendingSaveToast: String?
    @ObservationIgnored private var saveToastTask: Task<Void, Never>?
    var loadFailure: String?; var locked = false; var importedURL: URL?
    var pendingQuickSheet: AppSheet?
    var errorHosts: [UUID] = []
    var pickingInsightDates = false
    var organizingBatchID: UUID?
    /// Progress across all batches in the current explicit run.
    var organizationProgress: ImportOrganizationProgress?
    var organizingImportBatchIDs: Set<UUID> = [] { didSet { if oldValue != organizingImportBatchIDs { refreshVisibility() } } }
    @ObservationIgnored var organizationExecution: ImportOrganizationExecution?
    var organizationContinuesInBackground = false
    var organizingPendingImports = false
    @ObservationIgnored var pendingOrganizationTask: Task<Void, Never>?
    @ObservationIgnored var importOrganizationTask: Task<Void, Never>?
    var hiddenSalaryKeys: Set<String> = []
    var hiddenPendingImportKeys: Set<String> = []
    var entryFilterRequest: UUID?
    /// 「看花在哪」等入口：`destination = .ledger` 同时设置；账本页读后清空。
    var ledgerPreset: LedgerPreset?
    var entryFilterDate: Date?
    var reflectingMemories = false
    var updatingWeeklyPush = false
    var organizationErrors: [UUID: String] = [:]
    private var undoLedger: Ledger?; var undoLabel: String?
    init() {
        CloudNetworking.clearLegacyCache()
        let args = ProcessInfo.processInfo.arguments
        let directory: URL
        if let i = args.firstIndex(of: "--test-ledger"), args.indices.contains(i + 1), UUID(uuidString: args[i+1]) != nil { directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("YubaiUITests/" + args[i+1], isDirectory: true) }
        else if let i = args.firstIndex(of: "--data-directory"), args.indices.contains(i + 1) { directory = URL(fileURLWithPath: args[i+1], isDirectory: true) }
        else if let path = ProcessInfo.processInfo.environment["YUBAI_DATA_DIR"] { directory = URL(fileURLWithPath: path, isDirectory: true) }
        else { directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("app.yubai.personal", isDirectory: true) }
        localRepository = LedgerRepository(directory: directory)
        locations = LedgerLocations(local: localRepository, cloudDirectory: nil)
        syncAllowed = !args.contains("--test-ledger") && !args.contains("--data-directory") && ProcessInfo.processInfo.environment["YUBAI_DATA_DIR"] == nil
        defer { invalidateDerived() }
        #if DEBUG && targetEnvironment(simulator)
        do { try UITestSupport.prepare(localRepository) } catch { loadFailure = error.localizedDescription; return }
        #endif
        do {
            ledger = try localRepository.load()
            locked = ledger.preferences.lockEnabled
            #if DEBUG && targetEnvironment(simulator)
            if UITestSupport.script == "v46-busy" {
                organizingPendingImports = true
                organizationProgress = ImportOrganizationProgress(completed: 120, total: 214)
            }
            #endif
        } catch { loadFailure = error.localizedDescription }
        CaptureSnapshotBridge.publish(ledger)
        #if os(macOS)
        terminationObserver = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [writer = ledgerWriter] _ in writer.flushBlocking() }
        #endif
        #if os(iOS)
        CaptureNotifications.register()
        #endif
    }

    /// 升级后第一次：发薪日改成「确认到账才开新周期」，只对下一个发薪日起生效，当前周期不变。
    func enablePaydayConfirmationIfNeeded() {
        guard !locked, loadFailure == nil, !switchingLedgerLocation, !choosingSyncVersion,
              current.paydayConfirmSince == nil, Finance.anchorPlan(in: current, now: Date()) != nil else { return }
        _ = update("发薪确认", recordUndo: false, entryMotion: false, showToast: false) { Finance.enablePaydayConfirmation(&$0, now: Date()) }
    }
    /// 启动、解锁、回到前台后各一次。顺序固定：先开启发薪确认，再自动记账单，最后结算周期。
    func runCycleMaintenance() {
        enablePaydayConfirmationIfNeeded()
        autoSettleFixedFlows()
        closeSavingCycles()
        runAutomaticBackupIfDue()
    }
    /// 在前台跨过预记账目的日期或午夜时，也刷新并重新关联。
    func refreshAtPostingDates() async {
        while !Task.isCancelled && !locked {
            _ = fundsValue()
            let next = cachedFunds?.expires ?? Dates.addDays(1, to: Dates.day(Date()))
            do { try await Task.sleep(for: .seconds(max(1, next.timeIntervalSinceNow))) } catch { return }
            guard !Task.isCancelled, !locked else { return }
            refreshTimeDerived()
            runCycleMaintenance()
        }
    }
    func closeSavingCycles() {
        guard !locked, loadFailure == nil else { return }
        var next = current
        Savings.closeCycles(&next)
        guard next != current else { return }
        _ = update("攒钱", recordUndo: false, entryMotion: false, showToast: false) { Savings.closeCycles(&$0) }
    }
    @discardableResult func update(_ reason: String, preservingUpdatedAt: Bool = false, preservingRecovery: Bool = true, undoSnapshot: Ledger? = nil, recordUndo: Bool = true, reportError: Bool = true, entryMotion: Bool = true, allowLockedCapture: Bool = false, showToast: Bool = true, recoveryReason: String? = nil, _ change: (inout Ledger) throws -> Void) -> Bool {
        guard canEditLedger(allowLockedCapture: allowLockedCapture) else { return false }
        guard loadFailure == nil else { error = "请先恢复账本，原文件将保持不变。"; return false }
        let before = current; var next = before
        do {
            try change(&next)
            ButlerSavings.synchronize(&next, now: Date())
            if next.entries.count > before.entries.count {
                let oldIDs = Set(before.entries.map(\.id))
                let addedIDs = Set(next.entries.lazy.filter { !oldIDs.contains($0.id) }.map(\.id))
                if next.wishlist.contains(where: { $0.status == .thinking }) { Wishlist.autoLink(&next, addedEntryIDs: addedIDs, now: Date()) }
                FixedFlows.autoLink(&next, addedEntryIDs: addedIDs, now: Date())
            }
            if !preservingUpdatedAt { next.updatedAt = Date() }
            next = try persist(next, reason: recoveryReason ?? reason, preservingRecovery: preservingRecovery)
            let motion = MotionEntryChange(previous: before.entries.map(\.id), previousActive: before.activeEntries.map(\.id), currentActive: next.activeEntries.map(\.id))
            if entryMotion && !motion.saved.isEmpty { freshEntryIDs = motion.saved; pendingEntrySave = true }
            if entryMotion && !motion.deleted.isEmpty { entryDeleteTrigger &+= 1 }
            ledger = next
            if allowLockedCapture { undoLedger = nil; undoLabel = nil; toast = nil }
            if recordUndo {
                unsortedUndo = nil
                undoLedger = undoSnapshot ?? before; undoLabel = reason
                if showToast {
                    if entryMotion && !motion.saved.isEmpty { saveToastTask?.cancel(); pendingSaveToast = resultToast(reason, before: before, after: next); toast = nil }
                    else { toast = resultToast(reason, before: before, after: next) }
                }
            }
            return true
        } catch { if reportError { self.error = error.localizedDescription }; return false }
    }
    private func resultToast(_ reason: String, before: Ledger, after: Ledger) -> String {
        let old = Dictionary(uniqueKeysWithValues: before.entries.map { ($0.id, $0) })
        if let deleted = after.entries.first(where: { $0.deletedAt != nil && old[$0.id]?.deletedAt == nil }) {
            return "已删掉 · " + deleted.displayTitle + " " + (preferences.hideAmounts ? "••••" : AmountLabel.text(deleted.amount))
        }
        if let account = after.accounts.first(where: { a in !before.accounts.contains { $0.id == a.id } }) { return "已加好 · " + account.name }
        if let plan = after.plans.first(where: { p in p.stoppedAt != nil && before.plans.first { $0.id == p.id }?.stoppedAt == nil }) { return "已停掉 · " + plan.title }
        if let entry = after.entries.first(where: { old[$0.id]?.deletedAt != nil && $0.deletedAt == nil }) { return "已放回 · " + entry.displayTitle }
        if reason == "保存账户", let account = after.accounts.first(where: { a in before.accounts.first { $0.id == a.id } != a }) { return "已改好 · " + account.name }
        if reason == "清掉最近删除" { return "已清掉最近删除" }
        if reason.hasPrefix("删除") { return "已删掉 · " + String(reason.dropFirst(2)) }
        if reason.hasPrefix("添加") { return "已加好 · " + String(reason.dropFirst(2)) }
        return "已改好 · " + reason
    }
    func purgeExpiredEntries() {
        var next = current
        guard RecentlyDeleted.purge(in: &next) > 0 else { return }
        if update("清掉过期账目", recordUndo: false, entryMotion: false, showToast: false, { $0 = next }) { clearUndo() }
    }
    /// Prepare the full import off the main actor, then publish one atomic update.
    func commitImport(_ preview: ImportPreview?, data: Data?, confirmedNewCategories: Set<String> = []) async throws -> ImportBatch? {
        let before = current
        let now = Date()
        let preparation = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            var next = before
            let batch: ImportBatch?
            if let preview, let data, !preview.selectedEntries.isEmpty {
                batch = try BillImporter.commit(preview, data: data, confirmedNewCategories: confirmedNewCategories, to: &next, now: now)
            } else { batch = nil }
            try next.validate()
            try Task.checkCancellation()
            return (ledger: next, batch: batch)
        }
        let prepared = try await withTaskCancellationHandler {
            try await preparation.value
        } onCancel: { preparation.cancel() }
        try Task.checkCancellation()
        guard current == before, !locked else {
            throw YubaiError.invalid("账本刚有变化，请重试这一步。")
        }
        guard update("导入账单", { $0 = prepared.ledger }) else { return nil }
        return prepared.batch
    }
    @discardableResult func apply(_ changeSet: ChangeSet, label: String, silently: Bool = false, continuingImportOrganization: Bool = false, finishing: (inout Ledger) throws -> Void = { _ in }) -> Bool {
        guard !continuingImportOrganization || organizationExecution != nil else { return false }
        var skipped: [String] = []
        let batchCapture = changeSet.items.count > 1 && changeSet.items.allSatisfy { if case .addEntry = $0 { return true }; return false }
        let saved = update(label, preservingRecovery: !continuingImportOrganization,
                           undoSnapshot: continuingImportOrganization ? organizationExecution?.before : nil, entryMotion: !silently,
                           allowLockedCapture: locked && continuingImportOrganization && organizationContinuesInBackground,
                           showToast: !silently, recoveryReason: batchCapture ? "批量记账" : nil) { ledger in
            if !changeSet.items.isEmpty { skipped = try changeSet.apply(to: &ledger) }
            else if changeSet.source != "导入整理" { try changeSet.validateStructure() }
            try finishing(&ledger)
            ledger.pendingChanges.removeAll { $0.id == changeSet.id }
            for i in ledger.cards.indices where ledger.cards[i].action == .confirmChangeSet(changeSet.id) {
                ledger.cards[i].dismissedAt = Date()
            }
        }
        if saved, !silently, !skipped.isEmpty { toast = "已改好 · " + label + "；" + skipped.joined(separator: "；") }
        return saved
    }
    func publishOrganizationCheckpoint(_ next: Ledger, pending: PendingImportOrganization, salary: SalaryCandidate?, day: Date, derived: LedgerDerivedSnapshot) {
        if ledger != next {
            preparedDerived = derived; preparedPending = pending; preparedSalary = (day, salary)
            ledger = next
        }
        undoLedger = organizationExecution?.before; undoLabel = "导入整理"
    }
    func autoSettleFixedFlows() {
        guard !locked, loadFailure == nil, syncChoice == nil, !switchingLedgerLocation, !choosingSyncVersion else { return }
        let now = Date()
        let posted = Set(current.entries.filter { entry in
            entry.deletedAt == nil && entry.date <= now && entry.recordedAt.map { $0 < entry.date } == true
        }.map(\.id))
        if !posted.isEmpty {
            var next = current
            FixedFlows.autoLink(&next, addedEntryIDs: posted, now: now)
            if next != current { _ = update("固定账单", recordUndo: false, entryMotion: false, showToast: false) { $0 = next } }
        }
        guard let change = FixedFlows.autoSettle(in: current, now: now) else { return }
        cancelEntrySaveMotion()
        if apply(change, label: "自动记下", silently: true) { toast = nil }
    }
    func clearUndo() {
        undoLedger = nil; undoLabel = nil
    }

    func undo() {
        if let notice = unsortedUndo { _ = undoUnsorted(notice.id); return }
        guard canEditLedger(), let previous = undoLedger else { return }
        do {
            ledger = try persist(previous, reason: "撤销")
            cancelEntrySaveMotion()
            undoTrigger &+= 1; undoLedger = nil; undoLabel = nil; toast = "已撤销上一项修改"
        } catch { self.error = error.localizedDescription }
    }
    func present(_ sheet: AppSheet, from source: String) { sheetSource = source; self.sheet = sheet }
    func setEntrySaveToast(_ message: String) {
        if pendingEntrySave { pendingSaveToast = message }
        else { toast = message }
    }
    func cancelEntrySaveMotion() { saveToastTask?.cancel(); pendingEntrySave = false; pendingSaveToast = nil; freshEntryIDs = [] }
    func finishEntrySaveMotion() {
        guard pendingEntrySave, sheet == nil, !locked else { return }
        pendingEntrySave = false; entrySaveTrigger &+= 1
        let message = pendingSaveToast; pendingSaveToast = nil
        let trigger = entrySaveTrigger
        saveToastTask?.cancel()
        saveToastTask = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(YubaiMotion.saveToastDelay)) } catch { return }
            guard !Task.isCancelled, entrySaveTrigger == trigger, !locked, sheet == nil, toast == nil else { return }
            toast = message
        }
    }
    @discardableResult func restore(_ restored: Ledger) -> Bool {
        guard canEditLedger() else { return false }
        do { let saved = try persist(restored, reason: "恢复前", restoring: true); cancelEntrySaveMotion(); ledger = saved; resetRootNavigation(); loadFailure = nil; undoLedger = nil; undoLabel = nil; toast = "账本已恢复，原账本已保留"; return true }
        catch { self.error = error.localizedDescription; return false }
    }
    @discardableResult func recover(_ recovery: Recovery) -> Bool {
        guard canEditLedger() else { return false }
        let revision = ledgerRevision, repository = localRepository
        let read = ledgerWriter.submit(invalidatingOnFailure: false) { try repository.readRecovery(recovery) }
        Task { @MainActor in
            do {
                let restored = try await read.value
                guard ledgerRevision == revision else { throw YubaiError.invalid("账本刚有变化，请重试这一步。") }
                let saved = try persist(restored, reason: "恢复版本", restoring: true)
                cancelEntrySaveMotion(); ledger = saved; resetRootNavigation(); loadFailure = nil
                clearUndo(); toast = "已恢复到所选版本"; sheet = nil
            } catch { self.error = error.localizedDescription }
        }
        return true
    }
    func adoptPersistedPayloads(_ next: Ledger) { ledger = next }
    func adoptSyncedLedger(_ next: Ledger) {
        cancelEntrySaveMotion(); ledger = next; loadFailure = nil; undoLedger = nil; undoLabel = nil
    }
    func recordSuccessfulBackup(of ledgerID: UUID, at date: Date) {
        guard current.id == ledgerID else { return }
        if update("记录备份时间", preservingUpdatedAt: true, recordUndo: false, entryMotion: false, showToast: false, { LedgerBackup.recordDone(in: &$0.preferences, now: date) }) {
            // Undoing the preceding edit must not forget a successfully exported backup.
            if var previous = undoLedger {
                LedgerBackup.recordDone(in: &previous.preferences, now: date)
                undoLedger = previous
            }
        }
    }
    @discardableResult func deleteOldScreenshots(months: Int, now: Date) -> Bool {
        guard canEditLedger(), loadFailure == nil else { return false }
        let count = StorageAttachments.oldScreenshots(in: current, months: months, now: now).count
        guard count > 0 else { return false }
        ledgerWriter.flushBlocking()
        let wasPending = localRepository.hasPendingSync
        do {
            if ledgerLocation == .iCloud { try localRepository.markPendingSync(true) }
            let saved = try localRepository.deleteOldScreenshots(from: current, months: months, now: now)
            cancelEntrySaveMotion(); ledger = saved; undoLedger = nil; undoLabel = nil
            if ledgerLocation == .iCloud { pendingUpload = saved; pendingUploadPreservingRecovery = true; pendingUploadRecoveryReason = "删除旧截图"; Task { await synchronizeLedger() } }
            toast = "已删掉 · \(count) 张截图"
            return true
        } catch {
            if !wasPending { try? localRepository.markPendingSync(false) }
            self.error = error.localizedDescription; return false
        }
    }
    @discardableResult func clearStorageHistory() -> Bool {
        guard canEditLedger() else { return false }
        guard !syncBusy else { error = "请等同步完成后再清除恢复历史。"; return false }
        ledgerWriter.flushBlocking()
        do {
            try localRepository.clearRecoveryHistory()
            // A pre-clear undo snapshot may refer to payloads that no longer exist.
            undoLedger = nil; undoLabel = nil; toast = "已清除恢复历史"; return true
        } catch { self.error = error.localizedDescription; return false }
    }
    @discardableResult func eraseAllDeviceData() -> Bool {
        guard canEditLedger() else { return false }
        guard !syncBusy, !checkingCloudAvailability else { error = "请等同步完成后再抹掉本机数据。"; return false }
        do {
            try eraseLocalStorageAndResetLocation()
            cancelEntrySaveMotion(); ledger = Ledger(); undoLedger = nil; undoLabel = nil
            loadFailure = nil; locked = false; importedURL = nil; sheet = nil; sheetSource = nil; pendingQuickSheet = nil
            destination = .now; toast = nil; organizationErrors.removeAll(); pickingInsightDates = false; ledgerPreset = nil
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func unlock(useBiometrics: Bool = true) async {
        let context = LAContext()
        context.localizedFallbackTitle = "用设备密码"
        let policy: LAPolicy = useBiometrics ? .deviceOwnerAuthenticationWithBiometrics : .deviceOwnerAuthentication
        var failure: NSError?
        let available = context.canEvaluatePolicy(policy, error: &failure)
        do {
            if try await context.evaluatePolicy(available ? policy : .deviceOwnerAuthentication, localizedReason: "解锁你的余白账本") {
                locked = false; if syncChoice != nil { sheet = .syncVersions }
            }
        } catch let error as LAError where error.code == .userFallback { await unlock(useBiometrics: false) }
        catch { self.error = "未能解锁。可以重试 Face ID、Touch ID 或设备密码。" }
    }

}

@main struct YubaiApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(HomeActionDelegate.self) private var homeActionDelegate
    #endif
    @State private var store = AppStore.shared
    private var colorScheme: ColorScheme? {
        switch store.preferences.appearance {
        case "dark": .dark
        case "light": .light
        default: nil
        }
    }
    var body: some Scene {
        WindowGroup {
            // A ledger boundary discards ALL tab NavigationPaths and
            // pager state together, rather than only changing its selected tab.
            RootView().id(store.navigationRevision).environment(store).tint(YubaiColor.brandInk)
                .preferredColorScheme(colorScheme)
                #if os(macOS)
                .frame(minWidth: 920, minHeight: 680)
                #endif
        }
        #if os(macOS)
        .defaultSize(width: 1240, height: 850)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("记一笔") { store.present(.addEntry, from: "add") }.keyboardShortcut("n").disabled(store.locked)
                Button("问余白") { store.sheet = .ask("") }.keyboardShortcut("k").disabled(store.locked)
            }
            CommandGroup(replacing: .undoRedo) { Button("撤销上一项修改") { store.undo() }.keyboardShortcut("z").disabled(store.undoLabel == nil || store.locked) }
        }
        #endif
    }
}

struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.scenePhase) private var phase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var motionNamespace
    #if os(iOS)
    @State private var tabPaths: [Destination: NavigationPath] = [:]
    @State private var keyboardVisible = false
    @State private var quickMenuShown = false
    private var tabBarHidden: Bool { tabPaths[store.destination]?.isEmpty == false }
    #endif
    var body: some View {
        @Bindable var store = store
        Group {
            if store.locked { lockedView }
            else if let failure = store.loadFailure { recoveryView(failure) }
            else { mainContent }
        }
        .sheet(item: $store.sheet) { sheet in
            NavigationStack { sheetView(sheet) }.environment(store).tint(YubaiColor.brandInk)
                .environment(\.yubaiSheetSurface, true).environment(\.yubaiZoomNamespace, motionNamespace)
                .yubaiZoomDestination(store.sheetSource ?? sheet.motionSource)
                .appErrors().presentationDragIndicator(.visible).yubaiSheetBackground()
                .overlay { LedgerPrivacyCover() }
                #if os(macOS)
                .frame(minWidth: 540, idealWidth: 620, minHeight: 600, idealHeight: 720)
                #endif
        }
        .yubaiFont(YubaiFont.body).foregroundStyle(YubaiColor.label).background { PaperCanvas() }
        .environment(\.yubaiZoomNamespace, motionNamespace)
        .appErrors()
        .overlay(alignment: .bottom) {
            if !store.locked, let notice = store.unsortedUndo {
                UnsortedUndoBar(notice: notice)
                    .id(notice.id)
                    .padding(.horizontal, YubaiSpace.insetPage)
                    .padding(.bottom, YubaiSize.buttonHeight + YubaiSpace.gapSection)
                    .transition(YubaiMotion.toastTransition(reduceMotion: reduceMotion))
            } else if let toast = store.toast {
                Toast(text: toast, onUndo: store.undoLabel == nil ? nil : { store.undo() }, onDismiss: { if store.toast == toast { store.toast = nil } })
                    .id(toast)
                    #if os(iOS)
                    .padding(.bottom, YubaiSize.floatingTabbarHeight + YubaiSize.floatingTabbarBottom + YubaiSpace.gapGroup)
                    #else
                    .padding(.bottom, YubaiSize.buttonHeight + YubaiSpace.gapSection)
                    #endif
                    .transition(.asymmetric(insertion: .identity, removal: .opacity.animation(YubaiMotion.toastOut(reduceMotion: reduceMotion))))
            }
        }
        .onChange(of: store.pendingEntrySave) { _, pending in if pending { store.finishEntrySaveMotion() } }
        .onChange(of: store.sheet?.id) { _, id in if id == nil { store.sheetSource = nil; store.finishEntrySaveMotion() } }
        #if os(iOS)
        .sensoryFeedback(.success, trigger: store.entrySaveTrigger)
        .sensoryFeedback(.impact(weight: .medium), trigger: store.entryDeleteTrigger)
        .sensoryFeedback(.impact(weight: .light), trigger: store.undoTrigger)
        .sensoryFeedback(.impact(weight: .light), trigger: store.fixedFlowSettleTrigger)
        .sensoryFeedback(.warning, trigger: store.floorWarningTrigger)
        #endif
        .onChange(of: phase) { _, newValue in if newValue == .background { store.ledgerWriter.flushBlocking() }; if newValue == .active { store.purgeExpiredEntries(); store.askConversation.expire(); store.refreshTimeDerived(); Task { await store.configureSync(); store.runCycleMaintenance() } }; if newValue == .background && store.preferences.lockEnabled { store.cancelEntrySaveMotion(); store.sheet = nil; store.pickingInsightDates = false; store.toast = nil; store.locked = true } }
        .task(id: phase == .active && !store.locked) {
            guard phase == .active, !store.locked else { return }
            await store.refreshAtPostingDates()
        }
        .task {
            store.purgeExpiredEntries()
            if !store.locked, let pending = store.pendingQuickSheet { store.pendingQuickSheet = nil; store.sheet = pending }
            await store.configureSync(); store.runCycleMaintenance()
        }
        .modifier(ButlerRefreshTask())
        .modifier(WeeklyPushTask())
        .modifier(ButlerNoticeSyncTask())
        .overlay(alignment: .top) {
            if !store.locked, store.syncBusy || store.syncChoice != nil {
                VStack(spacing: YubaiSpace.gapGroup) {
                    if store.syncBusy { ProgressView(store.syncStatus ?? "正在从 iCloud 读取…") }
                    if store.syncChoice != nil { Button("选择同步账本版本") { store.sheet = .syncVersions } }
                }.padding(YubaiSpace.insetCard).background(YubaiColor.raised)
            }
        }
        .overlay { LedgerPrivacyCover() }
        .onOpenURL { url in
            if url.scheme?.lowercased() == "yubai" { store.handleCaptureURL(url); return }
            guard url.isFileURL else { return }; store.importedURL = url
            if !store.locked { store.sheet = url.pathExtension.lowercased() == "yubaibackup" ? .backup : .imports }
        }
        .onChange(of: store.locked) { _, value in if !value { Task { await store.configureSync(); store.runCycleMaintenance() }; if let pending = store.pendingQuickSheet { store.pendingQuickSheet = nil; store.sheet = pending }
            else if let url = store.importedURL { store.sheet = url.pathExtension.lowercased() == "yubaibackup" ? .backup : .imports } } }
    }
    @ViewBuilder var mainContent: some View {
        @Bindable var store = store
        #if os(macOS)
        NavigationSplitView {
            List(Destination.allCases, selection: $store.destination) { d in
                Label { Text(d.title) } icon: {
                    DestinationGlyph(destination: d, selected: store.destination == d, size: 20)
                }.tag(d).accessibilityIdentifier("tab_" + d.rawValue)
            }.listStyle(.sidebar).navigationTitle("余白")
                .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 250)
        } detail: {
            NavigationStack { tabRoot(store.destination) }.id(store.destination)
        }
        #else
        let generation = store.navigationRevision
        ZStack {
            ForEach(Destination.allCases) { destination in
                tabNavigation(destination, generation: generation, hidden: store.destination != destination)
                    .opacity(store.destination == destination ? 1 : 0)
                    .allowsHitTesting(store.destination == destination)
                    .accessibilityHidden(store.destination != destination)
            }
        }.id(generation)
            .overlay { quickMenuScrim }
            .overlay(alignment: .bottom) { tabBarOverlay }
            .onChange(of: store.sheet?.id) { _, _ in quickMenuShown = false }
            .onChange(of: store.destination) { _, _ in quickMenuShown = false }
            .onChange(of: store.navigationRevision) { _, _ in tabPaths = [:] }
            .onChange(of: store.tabRouteRequest) { _, route in
                guard let route else { return }
                tabPaths[store.destination, default: NavigationPath()].append(route)
                store.tabRouteRequest = nil
            }
            .onChange(of: store.butlerFocusID) { _, id in
                guard id != nil, !store.locked else { return }
                var path = NavigationPath(); path.append(TabRoute.todo); tabPaths[.now] = path
            }
            .onChange(of: store.locked) { _, locked in
                if !locked, let id = store.pendingButlerTaskID { store.pendingButlerTaskID = nil; store.openButlerNotice(id) }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in keyboardVisible = true }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidHideNotification)) { _ in keyboardVisible = false }
        #endif
    }
    #if os(iOS)
    @ViewBuilder private var quickMenuScrim: some View {
        if quickMenuShown && store.sheet == nil {
            Color.black.opacity(0.001).ignoresSafeArea().contentShape(Rectangle())
                .onTapGesture { quickMenuShown = false }
                .accessibilityHidden(true)
        }
    }
    @ViewBuilder private var tabBarOverlay: some View {
        if !tabBarHidden && store.sheet == nil && !store.pickingInsightDates {
            VStack(alignment: .center, spacing: YubaiSpace.gapGroup) {
                if quickMenuShown {
                    QuickRepeatMenu { quickMenuShown = false }
                        .transition(YubaiMotion.toastTransition(reduceMotion: reduceMotion))
                }
                tabBar
            }
            .padding(.horizontal, 16).padding(.bottom, YubaiSize.floatingTabbarBottom)
            .background(alignment: .bottom) {
                YubaiColor.canvas.frame(height: YubaiSize.floatingTabbarHeight + YubaiSize.floatingTabbarBottom)
                    .overlay(alignment: .top) { PageFade(edge: .bottom).offset(y: -40) }
                    .ignoresSafeArea(edges: .bottom).allowsHitTesting(false)
            }
            .opacity(keyboardVisible ? 0 : 1).allowsHitTesting(!keyboardVisible).accessibilityHidden(keyboardVisible)
        }
    }
    private var tabBar: some View {
        FloatingTabBar(select: selectTab, add: addEntry, quick: showQuickMenu)
            .uiTestAccessibilityValue("destination=\(store.destination.rawValue)")
    }
    private func selectTab(_ selected: Destination) {
        quickMenuShown = false
        if selected == store.destination {
            store.rootScrollRequest[selected, default: 0] += 1
        } else {
            withAnimation(YubaiMotion.control(reduceMotion: reduceMotion)) { store.destination = selected }
        }
    }
    private func addEntry() {
        quickMenuShown = false
        if store.accounts.isEmpty { store.beginFirstEntry() }
        else { store.sheetSource = nil; store.sheet = .addEntry }
    }
    private func showQuickMenu() {
        withAnimation(YubaiMotion.control(reduceMotion: reduceMotion)) { quickMenuShown.toggle() }
    }
    private func tabNavigation(_ d: Destination, generation: UInt64, hidden: Bool) -> some View {
        NavigationStack(path: Binding(get: { tabPaths[d] ?? NavigationPath() }, set: {
            guard generation == store.navigationRevision else { return }
            tabPaths[d] = $0
        })) {
            tabRoot(d).background(YubaiColor.canvas.ignoresSafeArea())
                .accessibilityHidden(hidden)
                .navigationDestination(for: TabRoute.self) { tabDestination($0).accessibilityHidden(hidden) }
        }.toolbarBackground(.hidden, for: .navigationBar)
            .accessibilityElement(children: .contain).accessibilityIdentifier("rootPage_" + d.rawValue)
            .environment(\.isScrollEnabled, true)
            .scrollClipDisabled(false)
            .background(YubaiColor.canvas.ignoresSafeArea())
    }
    @ViewBuilder private func tabDestination(_ route: TabRoute) -> some View {
        switch route {
        case .fixedFlows: FixedFlowsView()
        case .triage(let ids): LetterTriageView(entryIDs: ids)
        case .unsortedGroups(let id): UnsortedGroupsView(questionID: id)
        case .quickSortUnsorted(let id): UnsortedQuickSortView(questionID: id)
        case .profile: ProfileView()
        case .wishlist: WishlistView()
        case .accounts: AccountsView()
        case .formula: FormulaView()
        case .entryDetail(let id): EntryDetailView(entryID: id)
        case .allCategories(let interval): AllCategoriesView(interval: interval)
        case .categoryBudget(let category): BudgetView(initialCategory: category)
        case .savingWish(let id): WishlistView(focusedWishID: id)
        case .askQuestion(let text): AskYubaiView(initialText: text, autoSend: true)
        case .budget: BudgetView()
        case .billDetail(let id): BillDetailView(planID: id)
        case .todo: TodoView()
        case .settings: SettingsView()
        case .categories: CategoriesView()
        case .savingRule: SavingsView()
        case .reserve: ReserveView()
        case .saved: SavedView()
        case .weekly(let id): weeklyDestination(id)
        case let .whereCategory(category, interval): WhereCategoryView(category: category, interval: interval)
        case .memories: MemoryView()
        case .quickCapture: QuickCaptureSettingsView()
        case .importHistory: ImportHistoryView()
        case .intelligencePrivacy: IntelligencePrivacyView()
        case .backup: BackupView()
        case .storage: StorageView()
        case let .flowRecords(categories, title, income, interval): FlowRecordsView(categories: categories, title: title, income: income, interval: interval)
        case let .subcategoryInsights(category, income, interval, periodTitle): SubcategoryInsightsView(category: category, income: income, interval: interval, periodTitle: periodTitle)
        }
    }
    @ViewBuilder private func weeklyDestination(_ id: UUID?) -> some View {
        if let id { LetterDetailView(cardID: id) } else { WeeklyReviewView() }
    }
    #endif
    private func tabRoot(_ d: Destination) -> some View {
        #if os(macOS)
        ZStack(alignment: .bottom) {
            destination(d).frame(maxWidth: .infinity, maxHeight: .infinity)
            if d == .now && store.sheet == nil && !store.pickingInsightDates {
                HStack(spacing: YubaiSpace.space8) {
                    Spacer()
                    AddEntryButton { store.present(.addEntry, from: "add") }.yubaiZoomSource("add")
                }.padding(.horizontal, YubaiSpace.insetPage).padding(.bottom, YubaiSpace.gapSection)
            }
        }.background(YubaiColor.canvas)
        #else
        destination(d).frame(maxWidth: .infinity, maxHeight: .infinity)
        #endif
    }
    @ViewBuilder func destination(_ d: Destination) -> some View {
        switch d {
        case .now: NowView()
        case .saving: SavingTabView()
        case .ledger: LedgerTabView()
        case .yubai: YubaiTabView()
        }
    }
    @ViewBuilder func sheetView(_ sheet: AppSheet) -> some View {
        switch sheet {
        case .addEntry: QuickEntryView()
        case .prefilledEntry(let prefill): QuickEntryView(prefill: prefill)
        case .screenshotCapture(let data): ScreenshotCaptureView(imageData: data)
        case .screenshotReview(let data): ScreenshotCaptureView(imageData: data)
        case .editEntry(let id): EntryEditView(entryID: id)
        case .addPlan: FixedFlowEditor()
        case .editPlan(let id): FixedFlowEditor(planID: id)
        case .account(let account): AccountEditor(account: account)
        case .imports: ImportView()
        case .accounts: AccountsView()
        case .ask(let text): AskYubaiView(initialText: text)
        case .wishlist(let id): WishlistView(focusedWishID: id).manualSheetHeader("心愿单", cancelTitle: "关闭", showsAction: false)
        case .backup: BackupView()
        case .history: RecoveryVersionsView()
        case .syncVersions: SyncVersionsView()
        case .reconcileAll: ReconcileView()
        case .overspend(let source): OverspendSheet(source: source)
        case .paydayAmount: PaydaySheet()
        case .billPay(let planID, let occurrence): BillPaySheet(planID: planID, occurrence: occurrence)
        case .billMatch(let planID, let occurrence, let entryID): BillMatchSheet(planID: planID, occurrence: occurrence, entryID: entryID)
        case .billLink(let planID, let occurrence): BillLinkSheet(planID: planID, occurrence: occurrence)
        case .billMove(let planID, let occurrence): BillMoveSheet(planID: planID, occurrence: occurrence)
        case .formulaEdit(let field): FormulaEditSheet(field: field)
        case .frequentEntries: FrequentEntriesView().manualSheetHeader("整理常用", cancelTitle: "关闭", showsAction: false)
        case .intelligencePrivacy: IntelligencePrivacyView().manualSheetHeader("智能与隐私", cancelTitle: "关闭", showsAction: false)
        case .cardEvidence(let id): ButlerEvidenceView(cardID: id)
        case .cardQuestion(let id): ButlerQuestionView(cardID: id)
        case .cardProposal(let id): ButlerProposalView(changeID: id)
        case .letter(let id): LetterDetailView(cardID: id)
        case .reconcile(let id):
            if let account = store.accounts.first(where: { $0.id == id }) { AccountEditor(account: account, startsReconciling: true) }
        }
    }
    var lockedView: some View {
        VStack(spacing: YubaiSpace.space8) {
            Spacer()
            BrandMark(size: YubaiSize.tapMin * 2 + YubaiSpace.space8).accessibilityLabel("余白，账本已锁定")
            Spacer()
            Button("解锁") { Task { await store.unlock() } }.buttonStyle(PrimaryButtonStyle())
            #if os(iOS)
            Button("用手机密码") { Task { await store.unlock(useBiometrics: false) } }
                .frame(minHeight: YubaiSize.tapMin).accessibilityHint("打开设备身份验证，可使用手机密码解锁")
            #else
            Button("用设备密码") { Task { await store.unlock(useBiometrics: false) } }.frame(minHeight: YubaiSize.tapMin)
            #endif
        }.padding(YubaiSpace.insetPage).accessibilityIdentifier("lockedPage")
    }
    func recoveryView(_ message: String) -> some View {
        VStack(spacing: YubaiSpace.gapSection) { Image(systemName: "externaldrive.badge.exclamationmark").yubaiFont(YubaiFont.amountDisplay); Text("账本需要恢复").yubaiFont(YubaiFont.lead); Text(message).foregroundStyle(YubaiColor.labelSecondary); Button("查看本地恢复记录") { store.sheet = .history }; Button("从备份恢复") { store.sheet = .backup } }.padding(YubaiSpace.gapSection).frame(maxWidth: 540)
    }
}

/// Ledger-dependent task identity stays outside the pager's observation scope.
private struct ButlerRefreshTask: ViewModifier {
    @Environment(AppStore.self) private var store
    @Environment(\.scenePhase) private var phase
    func body(content: Content) -> some View {
        content.task(id: "\(store.current.id)-\(store.current.updatedAt)-\(store.locked)-\(store.organizingBatchID != nil)-\(phase)-\(IntelligenceRuntime.isConfigured)-\(IntelligenceRuntime.cloud.model)-\(IntelligenceRuntime.cloud.unavailableModel ?? "")") {
            if phase == .active { await store.refreshButler() }
        }
    }
}
private struct WeeklyPushTask: ViewModifier {
    @Environment(AppStore.self) private var store
    func body(content: Content) -> some View {
        content.task(id: store.preferences.weeklyLetterPush) { await WeeklyPush.sync(enabled: store.preferences.weeklyLetterPush) }
    }
}
private struct LedgerPrivacyCover: View {
    @Environment(AppStore.self) private var store
    @Environment(\.scenePhase) private var phase
    var body: some View {
        if (phase != .active || store.locked) && store.preferences.lockEnabled {
            if phase != .active { ZStack { YubaiColor.canvas.ignoresSafeArea(); BrandMark(size: YubaiSize.tapMin * 2 + YubaiSpace.space8).accessibilityLabel("账本已保护") } }
        }
    }
}

#if os(iOS)
/// 四个标签和独立的 ＋。底栏不随动态字号放大（固定 `.large`），改用大字号预览（Large Content Viewer）。
private struct FloatingTabBar: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Namespace private var selectionNamespace
    let select: (Destination) -> Void
    let add: () -> Void
    let quick: () -> Void
    private static let addSize: CGFloat = 68
    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 0) {
                tab(.now); tab(.saving); tab(.ledger); tab(.yubai)
            }.padding(.horizontal, 6).frame(height: YubaiSize.floatingTabbarHeight)
                .background { barSurface }
                .overlay { Capsule().strokeBorder(Color.white.opacity(0.6), lineWidth: 1).allowsHitTesting(false) }
                .accessibilityIdentifier("navigationCapsule")
            Color.clear.frame(width: Self.addSize, height: Self.addSize)
                .overlay {
                    if store.destination == .now {
                        addButton.transition(reduceMotion ? .opacity : .scale(scale: 0.8).combined(with: .opacity))
                    }
                }.accessibilityHidden(store.destination != .now)
        }.animation(YubaiMotion.control(reduceMotion: reduceMotion), value: store.destination)
            .dynamicTypeSize(.large)
            .accessibilityElement(children: .contain).accessibilityLabel("主导航").accessibilityIdentifier("mainNavigation")
    }
    private var barSurface: some View {
        Capsule().fill(reduceTransparency ? AnyShapeStyle(YubaiColor.raised) : AnyShapeStyle(.ultraThinMaterial))
            .overlay { if !reduceTransparency { Capsule().fill(YubaiColor.glassBar) } }
            .yubaiShadow(YubaiShadow.float)
    }
    private var addButton: some View {
        Image(systemName: "plus").font(.system(size: 26, weight: .medium)).foregroundStyle(YubaiColor.onBrand)
            .frame(width: Self.addSize, height: Self.addSize)
            .background { Circle().fill(YubaiColor.brand).yubaiShadow(YubaiShadow.ask) }
            .frame(width: Self.addSize, height: YubaiSize.floatingTabbarHeight)
            .contentShape(Rectangle())
            .onTapGesture(perform: add)
            .onLongPressGesture(minimumDuration: 0.4, perform: quick)
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton).accessibilityLabel("记一笔").accessibilityIdentifier("addEntry")
            .accessibilityAction(.default, add)
            .accessibilityAction(named: "常用", quick)
            .accessibilityShowsLargeContentViewer { Label("记一笔", systemImage: "plus") }
    }
    private func tab(_ destination: Destination) -> some View {
        let selected = store.destination == destination
        return Button { select(destination) } label: {
            VStack(spacing: 2) {
                DestinationGlyph(destination: destination, selected: selected, size: 20).frame(width: 20, height: 20)
                Text(destination.title).yubaiFont(YubaiFont.tabLabel, weight: selected ? .medium : .regular).lineLimit(1)
            }.foregroundStyle(selected ? YubaiColor.brandInk : YubaiColor.labelSecondary)
                .frame(maxWidth: .infinity).frame(height: YubaiSize.tapMin + YubaiSpace.space8)
                .background {
                    if selected {
                        Capsule().fill(YubaiColor.card)
                            .matchedGeometryEffect(id: "selection", in: selectionNamespace)
                    }
                }.contentShape(Capsule())
        }.buttonStyle(.plain).accessibilityLabel(destination.title).accessibilityIdentifier("tab_" + destination.rawValue)
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityShowsLargeContentViewer { Label(destination.title, systemImage: destination.symbol) }
    }
}

#endif

/// Checkpoint preparation computes every costly home input on the disk worker.
struct LedgerDerivedSnapshot: Sendable {
    let at: Date, expires: Date
    let zone: TimeZone
    let funds: Funds
    let entries: [Entry]
    let entriesByID: [UUID: Entry]
    let fixedMonth: FixedFlowMonth
    let progress: [RestrainProgress]
    let visibility: SavingCardVisibility.Snapshot
    let pace: CyclePace?
    let organizingBatchIDs: Set<UUID>
    init(_ ledger: Ledger, now: Date = Date(), organizingBatchIDs: Set<UUID> = []) {
        self.organizingBatchIDs = organizingBatchIDs
        at = now; zone = .current
        var expiry = Dates.addDays(1, to: Dates.day(now))
        for entry in ledger.entries where entry.deletedAt == nil {
            if entry.date > now { expiry = min(expiry, entry.date) }
            if let date = entry.otherDate, date > now { expiry = min(expiry, date) }
        }
        for account in ledger.accounts {
            let stale = account.anchorDate.addingTimeInterval(14 * 86400)
            if stale >= now { expiry = min(expiry, stale) }
        }
        expires = expiry
        funds = Finance.funds(ledger, now: now)
        entries = ledger.entries.sorted { $0.date > $1.date }
        entriesByID = Dictionary(uniqueKeysWithValues: ledger.entries.map { ($0.id, $0) })
        fixedMonth = FixedFlows.month(containing: now, in: ledger, asOf: now)
        pace = Finance.pace(ledger, now: now)
        progress = RestrainProgress.current(ledger: ledger, now: now)
        visibility = SavingCardVisibility.snapshot(in: ledger, organizingBatchIDs: organizingBatchIDs, progress: progress,
                                                  fallbackEntryCount: { UnsortedGroups.entries(for: $0, in: ledger).count })
    }
}

/// One cached value per AppStore derived property, valid for one funds timestamp.
private final class TimedSlot<Value> {
    private var stored: (at: Date, value: Value)?
    func value(at: Date, compute: () -> Value) -> Value {
        if let stored, stored.at == at { return stored.value }
        let value = compute(); stored = (at, value); return value
    }
    func prime(at: Date, _ value: Value) { stored = (at, value) }
    func clear() { stored = nil }
}
