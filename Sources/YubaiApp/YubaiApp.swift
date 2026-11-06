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
    case overview, insights, entries, settings
    var id: Self { self }
    var title: String { switch self { case .overview: "现在"; case .insights: "洞察"; case .entries: "账目"; case .settings: "我" } }
    var symbol: String { switch self { case .overview: "square.righthalf.filled"; case .insights: "chart.pie"; case .entries: "list.bullet"; case .settings: "person" } }
}
enum TabRoute: Hashable {
    case upcomingPayments, fixedFlows, butlerCards, profile, wishlist, letters, accounts
    case quickCapture, importHistory, intelligencePrivacy, backup, storage
    case unsortedGroups(UUID), quickSortUnsorted(UUID), unknownInflows
    case flowRecords(categories: [String], title: String, income: Bool, interval: DateInterval)
    case subcategoryInsights(category: String, income: Bool, interval: DateInterval, periodTitle: String)
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
        if inSheet { NavigationLink(destination: destination, label: label) }
        else { NavigationLink(value: route, label: label) }
        #else
        NavigationLink(destination: destination, label: label)
        #endif
    }
}

enum AppSheet: Identifiable {
    case account(Account?), imports, accounts, backup, history, fundsCalculation, syncVersions, addEntry, addPlan, intelligencePrivacy
    case editEntry(UUID), editPlan(UUID), prefilledEntry(QuickEntryPrefill), screenshotCapture(Data?), screenshotReview(Data)
    case ask(String), capture(Data), wishlist(UUID?)
    case cardEvidence(UUID), cardQuestion(UUID), cardProposal(UUID), letters, letter(UUID), reconcile(UUID)
    var id: String { String(describing: self) }
    var motionSource: String? {
        switch self {
        case .addEntry: nil
        case .ask: "ask"
        case .fundsCalculation: "funds"
        case .cardEvidence(let id), .cardQuestion(let id): "card-" + id.uuidString
        default: nil
        }
    }
}

@MainActor @Observable final class AppStore {
    static let shared = AppStore()
    private(set) var ledger = Ledger() {
        didSet {
            if oldValue.id != ledger.id || oldValue.preferences.onboardingComplete != ledger.preferences.onboardingComplete {
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
    func resolveCategory(_ category: String) -> String {
        _ = categoryAliases
        return derivedSource.resolveCategory(category)
    }
    func subcategoryBreakdown(category: String, during interval: DateInterval) -> [Breakdown] {
        _ = ledgerRevision
        return presentationCache.subcategoryBreakdown(in: derivedSource, category: category, during: interval, revision: sourceRevision)
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
    private var cashRevision = 0
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
    @ObservationIgnored private var cachedCashTimeline: (at: Date, value: CashTimeline)?
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
    @ObservationIgnored private var cachedEntryTimeline: (month: Date, search: String, filter: EntryTimeline.Filter, calendar: Calendar, value: EntryTimeline.Snapshot)?
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
    var cashTimeline: CashTimeline {
        _ = cashRevision
        return cashTimelineValue()
    }
    private func cashTimelineValue() -> CashTimeline {
        let funds = fundsValue()
        let at = cachedFunds?.at ?? Date()
        if let cachedCashTimeline, cachedCashTimeline.at == at { return cachedCashTimeline.value }
        let value = Finance.cashTimeline(derivedSource, funds: funds, now: at)
        cachedCashTimeline = (at, value); return value
    }
    var restrainProgress: [RestrainProgress] {
        _ = progressRevision
        return progressValue()
    }
    private func progressValue() -> [RestrainProgress] {
        if let cachedRestrainProgress { return cachedRestrainProgress }
        let value = RestrainProgress.current(ledger: derivedSource); cachedRestrainProgress = value; return value
    }
    var fixedFlowMonth: FixedFlowMonth {
        _ = ledgerRevision
        if let cachedFixedMonth { return cachedFixedMonth }
        let value = FixedFlows.month(containing: Date(), in: derivedSource); cachedFixedMonth = value; return value
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
    func entryTimeline(month: Date, search: String, filter: EntryTimeline.Filter) -> EntryTimeline.Snapshot {
        _ = entryTimelineRevision
        return entryTimelineValue(month: month, search: search, filter: filter)
    }
    private func entryTimelineValue(month: Date, search: String, filter: EntryTimeline.Filter) -> EntryTimeline.Snapshot {
        let calendar = Dates.calendar
        if let cached = cachedEntryTimeline, cached.month == month, cached.search == search, cached.filter == filter, cached.calendar == calendar { return cached.value }
        let value = EntryTimeline.snapshot(sortedEntries: sortedEntriesValue(), ledger: derivedSource, month: month, search: search, filter: filter, calendar: calendar)
        cachedEntryTimeline = (month, search, filter, calendar, value)
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
            let next = entryTimelineValue(month: oldTimeline.month, search: oldTimeline.search, filter: oldTimeline.filter)
            if next != oldTimeline.value { entryTimelineRevision &+= 1 }
        }
        let oldPending = cachedPendingOrganization
        cachedPendingOrganization = preparedPending
        if let oldPending, pendingOrganizationValue() != oldPending { pendingRevision &+= 1 }
        refreshTimeDerived()
        preparedDerived = nil; preparedPending = nil; preparedSalary = nil
    }
    func refreshTimeDerived() {
        let oldFunds = cachedFunds?.value, oldCash = cachedCashTimeline?.value
        let oldProgress = cachedRestrainProgress, oldSalary = cachedSalary
        let oldVisibility = cachedButlerVisibility?.value
        cachedFunds = preparedDerived.map { ($0.funds, $0.at, $0.expires, $0.zone) }
        cachedCashTimeline = preparedDerived.map { ($0.at, $0.timeline) }
        cachedBalances = [:]; cachedAssessments = [:]; cachedFixedMonth = preparedDerived?.fixedMonth
        cachedRestrainProgress = preparedDerived?.progress; cachedSalary = preparedSalary
        derivedRevision &+= 1
        cachedButlerVisibility = nil
        if let preparedDerived, preparedDerived.organizingBatchIDs == visibilityBatches {
            cachedButlerVisibility = (derivedRevision, Dates.day(preparedDerived.at), visibilityBatches, preparedDerived.visibility)
        }
        if let oldFunds, fundsValue() != oldFunds { fundsRevision &+= 1 }
        if let oldCash, cashTimelineValue() != oldCash { cashRevision &+= 1 }
        if let oldProgress, progressValue() != oldProgress { progressRevision &+= 1 }
        if let oldSalary, salaryValue() != oldSalary.value { salaryRevision &+= 1 }
        if let oldVisibility, visibilityValue() != oldVisibility { visibilityRevision &+= 1 }
        CaptureSnapshotBridge.publish(ledger)
    }
    private func refreshVisibility() {
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
    var destination: Destination = .overview
    private(set) var navigationRevision: UInt64 = 0
    func resetRootNavigation() {
        destination = .overview; pickingInsightDates = false
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
        } catch { loadFailure = error.localizedDescription }
        CaptureSnapshotBridge.publish(ledger)
        #if os(macOS)
        terminationObserver = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [writer = ledgerWriter] _ in writer.flushBlocking() }
        #endif
        #if os(iOS)
        CaptureNotifications.register()
        #endif
    }

    @discardableResult func update(_ reason: String, preservingUpdatedAt: Bool = false, preservingRecovery: Bool = true, undoSnapshot: Ledger? = nil, recordUndo: Bool = true, reportError: Bool = true, entryMotion: Bool = true, allowLockedCapture: Bool = false, showToast: Bool = true, recoveryReason: String? = nil, _ change: (inout Ledger) throws -> Void) -> Bool {
        guard canEditLedger(allowLockedCapture: allowLockedCapture) else { return false }
        guard loadFailure == nil else { error = "请先恢复账本，原文件将保持不变。"; return false }
        let before = current; var next = before
        do {
            try change(&next)
            if next.entries.count > before.entries.count, next.wishlist.contains(where: { $0.status == .thinking }) {
                let oldIDs = Set(before.entries.map(\.id))
                let addedIDs = Set(next.entries.lazy.filter { !oldIDs.contains($0.id) }.map(\.id))
                Wishlist.autoLink(&next, addedEntryIDs: addedIDs, now: Date())
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
    func commitImport(_ preview: ImportPreview?, data: Data?, confirmedNewCategories: Set<String> = [],
                      account: Account? = nil, completingOnboarding: Bool = false) async throws -> ImportBatch? {
        let before = current
        let preparation = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            var next = before
            if let account { next.accounts.append(account) }
            let batch: ImportBatch?
            if let preview, let data, !preview.selectedEntries.isEmpty {
                batch = try BillImporter.commit(preview, data: data, confirmedNewCategories: confirmedNewCategories, to: &next)
            } else { batch = nil }
            if completingOnboarding { next.preferences.onboardingComplete = true }
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
        guard update(completingOnboarding ? "建立账本" : "导入账单", { $0 = prepared.ledger }) else { return nil }
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
        guard !locked, loadFailure == nil, syncChoice == nil, !switchingLedgerLocation, !choosingSyncVersion,
              let change = FixedFlows.autoSettle(in: current) else { return }
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
        if update("记录备份时间", preservingUpdatedAt: true, recordUndo: false, { $0.preferences.lastBackupAt = date }) {
            // Undoing the preceding edit must not forget a successfully exported backup.
            undoLedger?.preferences.lastBackupAt = date
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
            destination = .overview; toast = nil; organizationErrors.removeAll(); pickingInsightDates = false
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
            // A ledger/onboarding boundary discards ALL tab NavigationPaths and
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
                Button("记一笔") { store.present(.addEntry, from: "add") }.keyboardShortcut("n").disabled(store.locked || !store.preferences.onboardingComplete)
                Button("问余白") { store.sheet = .ask("") }.keyboardShortcut("k").disabled(store.locked || !store.preferences.onboardingComplete)
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
    @State private var visibleTab: Destination = .overview
    @State private var pagingPhase: ScrollPhase = .idle
    @State private var pagingAligned = false
    @State private var pagingTarget: Destination?
    @State private var needsInitialScroll = true
    private struct PagingPosition: Equatable {
        let destination: Destination
        let aligned: Bool
        let ready: Bool
    }
    private var tabBarHidden: Bool { tabPaths[visibleTab]?.isEmpty == false }
    #endif
    var body: some View {
        @Bindable var store = store
        Group {
            if store.locked { lockedView }
            else if let failure = store.loadFailure { recoveryView(failure) }
            else if !store.preferences.onboardingComplete { NavigationStack { WelcomeView() } }
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
        .onChange(of: phase) { _, newValue in if newValue == .background { store.ledgerWriter.flushBlocking() }; if newValue == .active { store.purgeExpiredEntries(); store.askConversation.expire(); store.refreshTimeDerived(); Task { await store.configureSync(); store.autoSettleFixedFlows() } }; if newValue == .background && store.preferences.lockEnabled { store.cancelEntrySaveMotion(); store.sheet = nil; store.pickingInsightDates = false; store.toast = nil; store.locked = true } }
        .task {
            store.purgeExpiredEntries()
            if !store.locked && store.preferences.onboardingComplete, let pending = store.pendingQuickSheet { store.pendingQuickSheet = nil; store.sheet = pending }
            await store.configureSync(); store.autoSettleFixedFlows()
        }
        .modifier(ButlerRefreshTask())
        .modifier(WeeklyPushTask())
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
        .onChange(of: store.locked) { _, value in if !value { Task { await store.configureSync(); store.autoSettleFixedFlows() }; if store.preferences.onboardingComplete, let pending = store.pendingQuickSheet { store.pendingQuickSheet = nil; store.sheet = pending }
            else if let url = store.importedURL { store.sheet = url.pathExtension.lowercased() == "yubaibackup" ? .backup : .imports } } }
    }
    @ViewBuilder var mainContent: some View {
        @Bindable var store = store
        #if os(macOS)
        NavigationSplitView {
            List(Destination.allCases, selection: $store.destination) { d in
                Label { Text(d.title) } icon: {
                    if d == .overview { BrandMark(size: 20, background: store.destination == d ? YubaiColor.card : YubaiColor.canvas) }
                    else { Image(systemName: d.symbol) }
                }.tag(d).accessibilityIdentifier("tab_" + d.rawValue)
            }.listStyle(.sidebar).navigationTitle("余白")
                .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 250)
        } detail: {
            NavigationStack { tabRoot(store.destination) }.id(store.destination)
        }
        #else
        let generation = store.navigationRevision
        let appearanceTarget = store.destination
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: YubaiSpace.none) {
                    ForEach(Destination.allCases) { d in
                        tabNavigation(d, generation: generation).containerRelativeFrame(.horizontal).id(d)
                            .accessibilityHidden(visibleTab != d)
                    }
                }.scrollTargetLayout()
            }.accessibilityIdentifier("rootPager").scrollTargetBehavior(.paging)
                .scrollIndicators(.hidden)
                .scrollDisabled(store.pagingLocked || tabBarHidden || store.sheet != nil || store.pickingInsightDates)
                .scrollClipDisabled()
                .background(YubaiColor.canvas.ignoresSafeArea())
                .onScrollGeometryChange(for: PagingPosition.self) { geometry in
                    let destination = tab(at: geometry)
                    let width = geometry.containerSize.width
                    let offset = geometry.contentOffset.x + geometry.contentInsets.leading
                    let index = Destination.allCases.firstIndex(of: destination) ?? 0
                    return PagingPosition(destination: destination, aligned: width > 0 && abs(offset - CGFloat(index) * width) <= 1, ready: width > 0)
                } action: { _, next in
                    guard generation == store.navigationRevision else { return }
                    if visibleTab != next.destination { visibleTab = next.destination }; if pagingAligned != next.aligned { pagingAligned = next.aligned }
                    if needsInitialScroll {
                        guard next.ready else { return }
                        needsInitialScroll = false; pagingTarget = appearanceTarget
                        proxy.scrollTo(appearanceTarget, anchor: .leading)
                    }
                    if let target = pagingTarget, next.destination != target || !next.aligned { return }
                    if pagingTarget != nil { pagingTarget = nil }
                    if pagingPhase == .idle && store.destination != next.destination { store.destination = next.destination }
                }
                .onScrollPhaseChange { _, phase in
                    guard generation == store.navigationRevision else { return }
                    if pagingPhase != phase { pagingPhase = phase }
                    if phase == .interacting { if pagingTarget != nil { pagingTarget = nil } }
                    if phase == .idle && pagingTarget == nil && store.destination != visibleTab { store.destination = visibleTab }
                }
                .onChange(of: store.destination) { _, next in
                    if next != visibleTab { scrollTo(next, using: proxy) }
                }
                .onAppear {
                    guard generation == store.navigationRevision else { return }
                    pagingTarget = appearanceTarget
                    proxy.scrollTo(appearanceTarget, anchor: .leading)
                }
                .onDisappear {
                    guard generation == store.navigationRevision else { return }
                    needsInitialScroll = true; if pagingTarget != nil { pagingTarget = nil }
                }
                .task {
                    // Retry after the first layout; an onAppear scroll may run
                    // before the pager has a usable width or registered targets.
                    await Task.yield()
                    guard !Task.isCancelled, generation == store.navigationRevision else { return }
                    proxy.scrollTo(appearanceTarget, anchor: .leading)
                    if visibleTab == appearanceTarget && pagingAligned { if pagingTarget != nil { pagingTarget = nil } }
                }
                .overlay(alignment: .bottom) {
                    if !tabBarHidden && store.sheet == nil && !store.pickingInsightDates {
                        FloatingTabBar { scrollTo($0, using: proxy) }
                            .uiTestAccessibilityValue("destination=\(store.destination.rawValue); visible=\(visibleTab.rawValue); phase=\(pagingPhase == .idle ? "idle" : "moving"); locked=\(store.pagingLocked ? 1 : 0)")
                            .padding(.horizontal, YubaiSpace.insetPage).padding(.bottom, YubaiSize.floatingTabbarBottom)
                            .opacity(keyboardVisible ? 0 : 1).allowsHitTesting(!keyboardVisible).accessibilityHidden(keyboardVisible)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in keyboardVisible = true }
                .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidHideNotification)) { _ in keyboardVisible = false }
        }
        #endif
    }
    #if os(iOS)
    private func tab(at geometry: ScrollGeometry) -> Destination {
        guard geometry.containerSize.width > 0 else { return store.destination }
        let index = Int(((geometry.contentOffset.x + geometry.contentInsets.leading) / geometry.containerSize.width).rounded())
        return Destination.allCases[max(0, min(Destination.allCases.count - 1, index))]
    }
    private func scrollTo(_ d: Destination, using proxy: ScrollViewProxy) {
        // Reselecting an already settled page has no scroll transition to perform.
        if d == store.destination && d == visibleTab && pagingPhase == .idle && pagingAligned {
            if tabPaths[d]?.isEmpty == false { tabPaths[d] = NavigationPath() }
            else { store.rootScrollRequest[d, default: 0] += 1 }
            return
        }
        pagingTarget = d
        withAnimation(YubaiMotion.layout(reduceMotion: reduceMotion)) { proxy.scrollTo(d, anchor: .leading) }
    }
    private func tabNavigation(_ d: Destination, generation: UInt64) -> some View {
        NavigationStack(path: Binding(get: { tabPaths[d] ?? NavigationPath() }, set: {
            guard generation == store.navigationRevision else { return }
            tabPaths[d] = $0
        })) {
            tabRoot(d).background(YubaiColor.canvas.ignoresSafeArea())
                .navigationDestination(for: TabRoute.self) { tabDestination($0) }
        }.toolbarBackground(.hidden, for: .navigationBar)
            .accessibilityElement(children: .contain).accessibilityIdentifier("rootPage_" + d.rawValue)
            .environment(\.isScrollEnabled, true)
            .scrollClipDisabled(false)
            .background(YubaiColor.canvas.ignoresSafeArea())
    }
    @ViewBuilder private func tabDestination(_ route: TabRoute) -> some View {
        switch route {
        case .upcomingPayments: Page { UpcomingPaymentsView() }.navigationTitle("接下来要付的").yubaiNavigation()
        case .fixedFlows: FixedFlowsView()
        case .butlerCards: ButlerListView()
        case .unsortedGroups(let id): UnsortedGroupsView(questionID: id)
        case .quickSortUnsorted(let id): UnsortedQuickSortView(questionID: id)
        case .unknownInflows: ButlerListView(unknownInflowsOnly: true)
        case .profile: ProfileView()
        case .wishlist: WishlistView()
        case .letters: LettersView()
        case .accounts: AccountsView()
        case .quickCapture: QuickCaptureSettingsView()
        case .importHistory: ImportHistoryView()
        case .intelligencePrivacy: IntelligencePrivacyView()
        case .backup: BackupView()
        case .storage: StorageView()
        case let .flowRecords(categories, title, income, interval): FlowRecordsView(categories: categories, title: title, income: income, interval: interval)
        case let .subcategoryInsights(category, income, interval, periodTitle): SubcategoryInsightsView(category: category, income: income, interval: interval, periodTitle: periodTitle)
        }
    }
    #endif
    private func tabRoot(_ d: Destination) -> some View {
        #if os(macOS)
        ZStack(alignment: .bottom) {
            destination(d).frame(maxWidth: .infinity, maxHeight: .infinity)
            if store.sheet == nil && !store.pickingInsightDates {
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
        switch d { case .overview: OverviewView(); case .insights: InsightsView(); case .entries: EntriesView(); case .settings: SettingsView() }
    }
    @ViewBuilder func sheetView(_ sheet: AppSheet) -> some View {
        switch sheet {
        case .addEntry: QuickEntryView()
        case .prefilledEntry(let prefill): QuickEntryView(prefill: prefill)
        case .screenshotCapture(let data): ScreenshotCaptureView(imageData: data)
        case .screenshotReview(let data): ImportView(initialScreenshot: data)
        case .editEntry(let id): EntryEditView(entryID: id)
        case .addPlan: FixedFlowEditor()
        case .editPlan(let id): FixedFlowEditor(planID: id)
        case .account(let account): AccountEditor(account: account)
        case .imports: ImportView()
        case .accounts: AccountsView()
        case .ask(let text): AskYubaiView(initialText: text)
        case .capture(let data): AskYubaiView(initialImage: data)
        case .wishlist(let id): WishlistView(focusedWishID: id).manualSheetHeader("心愿单", cancelTitle: "关闭", showsAction: false)
        case .backup: BackupView()
        case .history: RecoveryVersionsView()
        case .syncVersions: SyncVersionsView()
        case .fundsCalculation: FundsCalculationView()
        case .intelligencePrivacy: IntelligencePrivacyView().manualSheetHeader("智能与隐私", cancelTitle: "关闭", showsAction: false)
        case .cardEvidence(let id): ButlerEvidenceView(cardID: id)
        case .cardQuestion(let id): ButlerQuestionView(cardID: id)
        case .cardProposal(let id): ButlerProposalView(changeID: id)
        case .letters: LettersView()
        case .letter(let id): LetterDetailView(cardID: id).manualSheetHeader("每周来信", cancelTitle: "关闭", showsAction: false)
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
        }.padding(YubaiSpace.insetPage)
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
private struct FloatingTabBar: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var scheme
    @State private var tagJump = 0
    @ScaledMetric(relativeTo: .title3) private var scaledIconSize = YubaiSize.tabIcon
    @ScaledMetric(relativeTo: .title2) private var scaledAddSize = YubaiFont.addIcon.size
    @Namespace private var selection
    var select: (Destination) -> Void
    var body: some View {
        HStack(spacing: YubaiSpace.none) {
            tab(.overview); tab(.insights)
            Button { store.sheetSource = nil; store.sheet = .addEntry } label: {
                Image(systemName: "plus").font(.system(size: min(scaledAddSize, YubaiFont.amountLarge.size), weight: YubaiFont.addIcon.weight)).foregroundStyle(YubaiColor.onBrand)
                    .frame(width: YubaiSize.tabAdd, height: YubaiSize.tabAdd).background { Circle().fill(YubaiColor.brand).yubaiShadow(YubaiShadow.ask) }
            }.buttonStyle(RoundPressStyle()).padding(.horizontal, YubaiSpace.space8)
                .accessibilityLabel("记一笔").accessibilityIdentifier("addEntry")
                .contextMenu {
                    Button("截图记一笔", systemImage: "photo") { store.requestCaptureSheet(.screenshotCapture(nil)) }
                    Button("导入账单", systemImage: "square.and.arrow.down") { store.requestCaptureSheet(.imports) }
                    if let last = store.lastRecordedEntry {
                        Button("再记一笔「" + last.displayTitle + " " + (store.preferences.hideAmounts ? "••••" : AmountLabel.text(last.amount)) + "」", systemImage: "plus") {
                            store.requestCaptureSheet(.prefilledEntry(QuickEntryPrefill(entry: last)))
                        }
                    }
                }
            tab(.entries); tab(.settings)
        }.padding(.horizontal, YubaiSpace.space8).frame(height: YubaiSize.tabBarHeight)
            .background {
                Capsule().fill(reduceTransparency ? AnyShapeStyle(YubaiColor.raised) : AnyShapeStyle(.ultraThinMaterial))
                    .overlay { if !reduceTransparency { Capsule().fill(YubaiColor.glassBar) } }
                    .yubaiShadow(YubaiShadow.float)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
            .overlay { Capsule().strokeBorder(reduceTransparency ? YubaiColor.separator : Color.white.opacity(scheme == .dark ? 0.08 : 0.6), lineWidth: 1).allowsHitTesting(false) }
            .animation(YubaiMotion.layout(reduceMotion: reduceMotion), value: store.destination)
            .onChange(of: store.destination) { _, destination in if destination == .overview { tagJump &+= 1 } }
            .accessibilityElement(children: .contain).accessibilityLabel("主导航").accessibilityIdentifier("mainNavigation")
    }
    private func tab(_ d: Destination) -> some View {
        let selected = store.destination == d
        let iconSize = min(scaledIconSize, YubaiSize.barMax)
        return Button { select(d) } label: {
            VStack(spacing: YubaiSpace.space2) {
                Group {
                    if d == .overview { BrandMark(size: iconSize, background: selected ? YubaiColor.card : YubaiColor.raised, jumpTrigger: tagJump) }
                    else { Image(systemName: d.symbol).symbolVariant(.none).font(.system(size: iconSize, weight: selected ? .medium : .regular)) }
                }
                .frame(width: iconSize, height: iconSize)
                Text(d.title).yubaiFont(YubaiFont.tabLabel, weight: selected ? .medium : .regular).lineLimit(1)
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            }.foregroundStyle(selected ? YubaiColor.brandInk : YubaiColor.labelSecondary)
                .frame(maxWidth: .infinity).frame(height: YubaiSize.tabSelectionHeight)
                .contentShape(RoundedRectangle(cornerRadius: YubaiSize.tabSelectionRadius))
                .background {
                    if selected { RoundedRectangle(cornerRadius: YubaiSize.tabSelectionRadius).fill(YubaiColor.card).matchedGeometryEffect(id: "selection", in: selection) }
                }
        }.buttonStyle(.plain).accessibilityLabel(d.title).accessibilityIdentifier("tab_" + d.rawValue)
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
#endif

/// Checkpoint preparation computes every costly home input on the disk worker.
struct LedgerDerivedSnapshot: Sendable {
    let at: Date, expires: Date
    let zone: TimeZone
    let funds: Funds
    let timeline: CashTimeline
    let entries: [Entry]
    let entriesByID: [UUID: Entry]
    let fixedMonth: FixedFlowMonth
    let progress: [RestrainProgress]
    let visibility: SavingCardVisibility.Snapshot
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
        timeline = Finance.cashTimeline(ledger, funds: funds, now: now)
        entries = ledger.entries.sorted { $0.date > $1.date }
        entriesByID = Dictionary(uniqueKeysWithValues: ledger.entries.map { ($0.id, $0) })
        fixedMonth = FixedFlows.month(containing: now, in: ledger)
        progress = RestrainProgress.current(ledger: ledger, now: now)
        visibility = SavingCardVisibility.snapshot(in: ledger, organizingBatchIDs: organizingBatchIDs, progress: progress,
                                                  fallbackEntryCount: { UnsortedGroups.entries(for: $0, in: ledger).count })
    }
}
