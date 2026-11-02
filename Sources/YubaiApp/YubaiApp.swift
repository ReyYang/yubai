import SwiftUI
import Observation
import LocalAuthentication
import YubaiCore
#if os(iOS)
import UIKit
#endif

enum Destination: String, CaseIterable, Identifiable {
    case overview, insights, entries, settings
    var id: Self { self }
    var title: String { switch self { case .overview: "现在"; case .insights: "洞察"; case .entries: "账目"; case .settings: "我" } }
    var symbol: String { switch self { case .overview: "water.waves"; case .insights: "chart.pie"; case .entries: "list.bullet"; case .settings: "person" } }
}
enum TabRoute: Hashable {
    case forecast, upcomingPayments, fixedFlows, butlerCards, profile, wishlist, letters, accounts
    case quickCapture, importHistory, intelligencePrivacy, backup, storage
    case unsortedGroups(UUID), unknownInflows
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
    case editEntry(UUID), prefilledEntry(QuickEntryPrefill), screenshotCapture(Data?), screenshotReview(Data)
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
    private(set) var ledger = Ledger() { didSet { invalidateDerived() } }
    var current: Ledger { ledger }
    private var derivedRevision = 0
    // Cache writes during rendering are unobserved; the revision notifies readers when their inputs change.
    @ObservationIgnored private var cachedFunds: (value: Funds, at: Date, expires: Date, zone: TimeZone)?
    @ObservationIgnored private var cachedEntries: [Entry]?
    @ObservationIgnored private var cachedEntryTimeline: (month: Date, search: String, filter: EntryTimeline.Filter, calendar: Calendar, value: EntryTimeline.Snapshot)?
    var funds: Funds {
        _ = derivedRevision
        let now = Date(); let zone = TimeZone.current
        if let cached = cachedFunds, cached.zone == zone, now >= cached.at, now < cached.expires { return cached.value }
        let ledger = current; var expires = Dates.addDays(1, to: Dates.day(now))
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
    var fixedFlowMonth: FixedFlowMonth { _ = derivedRevision; return FixedFlows.month(containing: Date(), in: current) }
    var sortedEntries: [Entry] {
        _ = derivedRevision
        if let cachedEntries { return cachedEntries }
        let rows = current.entries.sorted { $0.date > $1.date }
        cachedEntries = rows; return rows
    }
    func entryTimeline(month: Date, search: String, filter: EntryTimeline.Filter) -> EntryTimeline.Snapshot {
        _ = derivedRevision
        let calendar = Dates.calendar
        if let cached = cachedEntryTimeline, cached.month == month, cached.search == search, cached.filter == filter, cached.calendar == calendar { return cached.value }
        let value = EntryTimeline.snapshot(sortedEntries: sortedEntries, ledger: current, month: month, search: search, filter: filter, calendar: calendar)
        cachedEntryTimeline = (month, search, filter, calendar, value)
        return value
    }
    private func invalidateDerived() { cachedEntries = nil; cachedEntryTimeline = nil; refreshTimeDerived() }
    func refreshTimeDerived() { cachedFunds = nil; derivedRevision &+= 1; CaptureSnapshotBridge.publish(ledger) }
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
    @ObservationIgnored var syncMonitor: CloudLedgerMonitor?
    var iCloudAvailable: Bool { locations.cloud != nil }
    var destination: Destination = .overview {
        didSet { if destination == .overview && oldValue != .overview { overviewVisit &+= 1 } }
    }
    var overviewVisit = 0
    #if os(iOS)
    var pagingLocked = false
    #endif
    @ObservationIgnored var forecastMotion = MotionVisitState()
    var sheet: AppSheet?; var error: String?; var toast: String?
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
    var organizationProgress: (completed: Int, total: Int)?
    var organizingPendingImports = false
    @ObservationIgnored var pendingOrganizationTask: Task<Void, Never>?
    @ObservationIgnored var importOrganizationTask: Task<Void, Never>?
    var hiddenSalaryKeys: Set<String> = []
    var entryFilterRequest: UUID?
    var entryFilterDate: Date?
    var reflectingMemories = false
    var updatingWeeklyPush = false
    var organizationErrors: [UUID: String] = [:]
    private var undoLedger: Ledger?; var undoLabel: String?
    init() {
        let args = ProcessInfo.processInfo.arguments
        let directory: URL
        if let i = args.firstIndex(of: "--test-ledger"), args.indices.contains(i + 1), UUID(uuidString: args[i+1]) != nil { directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("YubaiUITests/" + args[i+1], isDirectory: true) }
        else if let i = args.firstIndex(of: "--data-directory"), args.indices.contains(i + 1) { directory = URL(fileURLWithPath: args[i+1], isDirectory: true) }
        else if let path = ProcessInfo.processInfo.environment["YUBAI_DATA_DIR"] { directory = URL(fileURLWithPath: path, isDirectory: true) }
        else { directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("app.yubai.personal", isDirectory: true) }
        localRepository = LedgerRepository(directory: directory)
        locations = LedgerLocations(local: localRepository, cloudDirectory: nil)
        syncAllowed = !args.contains("--test-ledger") && !args.contains("--data-directory") && ProcessInfo.processInfo.environment["YUBAI_DATA_DIR"] == nil
        #if DEBUG && targetEnvironment(simulator)
        do { try UITestSupport.prepare(localRepository) } catch { loadFailure = error.localizedDescription; return }
        #endif
        do {
            ledger = try localRepository.load()
            locked = ledger.preferences.lockEnabled
        } catch { loadFailure = error.localizedDescription }
        CaptureSnapshotBridge.publish(ledger)
        #if os(iOS)
        CaptureNotifications.register()
        #endif
    }

    @discardableResult func update(_ reason: String, preservingUpdatedAt: Bool = false, recordUndo: Bool = true, reportError: Bool = true, entryMotion: Bool = true, allowLockedCapture: Bool = false, showToast: Bool = true, _ change: (inout Ledger) throws -> Void) -> Bool {
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
            next = try persist(next, reason: reason)
            let motion = MotionEntryChange(previous: before.entries.map(\.id), previousActive: before.activeEntries.map(\.id), currentActive: next.activeEntries.map(\.id))
            if entryMotion && !motion.saved.isEmpty { freshEntryIDs = motion.saved; pendingEntrySave = true }
            if entryMotion && !motion.deleted.isEmpty { entryDeleteTrigger &+= 1 }
            ledger = next
            if allowLockedCapture { undoLedger = nil; undoLabel = nil; toast = nil }
            if recordUndo {
                undoLedger = before; undoLabel = reason
                if showToast {
                    if entryMotion && !motion.saved.isEmpty { saveToastTask?.cancel(); pendingSaveToast = reason + "完成"; toast = nil }
                    else { toast = reason + "完成" }
                }
            }
            return true
        } catch { if reportError { self.error = error.localizedDescription }; return false }
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
    @discardableResult func apply(_ changeSet: ChangeSet, label: String, silently: Bool = false, finishing: (inout Ledger) throws -> Void = { _ in }) -> Bool {
        var skipped: [String] = []
        let saved = update(label, entryMotion: !silently, showToast: !silently) { ledger in
            if !changeSet.items.isEmpty { skipped = try changeSet.apply(to: &ledger) }
            else if changeSet.source != "导入整理" { try changeSet.validateStructure() }
            try finishing(&ledger)
            ledger.pendingChanges.removeAll { $0.id == changeSet.id }
            for i in ledger.cards.indices where ledger.cards[i].action == .confirmChangeSet(changeSet.id) {
                ledger.cards[i].dismissedAt = Date()
            }
        }
        if saved, !silently, !skipped.isEmpty { toast = label + "完成；" + skipped.joined(separator: "；") }
        return saved
    }
    func autoSettleFixedFlows() {
        guard !locked, loadFailure == nil, syncChoice == nil, !switchingLedgerLocation, !choosingSyncVersion,
              let change = FixedFlows.autoSettle(in: current) else { return }
        cancelEntrySaveMotion()
        if apply(change, label: "自动记下", silently: true) { toast = nil }
    }
    func undo() {
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
        do { let saved = try persist(restored, reason: "恢复前", restoring: true); cancelEntrySaveMotion(); ledger = saved; loadFailure = nil; undoLedger = nil; undoLabel = nil; toast = "账本已恢复，原账本已保留"; return true }
        catch { self.error = error.localizedDescription; return false }
    }
    @discardableResult func recover(_ recovery: Recovery) -> Bool {
        guard canEditLedger() else { return false }
        do { let restored = try localRepository.readRecovery(recovery); let saved = try persist(restored, reason: "恢复版本", restoring: true); cancelEntrySaveMotion(); ledger = saved; loadFailure = nil; undoLedger = nil; undoLabel = nil; toast = "已恢复到所选版本"; sheet = nil; return true }
        catch { self.error = error.localizedDescription; return false }
    }
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
        let wasPending = localRepository.hasPendingSync
        do {
            if ledgerLocation == .iCloud { try localRepository.markPendingSync(true) }
            let saved = try localRepository.deleteOldScreenshots(from: current, months: months, now: now)
            cancelEntrySaveMotion(); ledger = saved; undoLedger = nil; undoLabel = nil
            if ledgerLocation == .iCloud { pendingUpload = saved; Task { await synchronizeLedger() } }
            toast = "已删除 \(count) 张截图"
            return true
        } catch {
            if !wasPending { try? localRepository.markPendingSync(false) }
            self.error = error.localizedDescription; return false
        }
    }
    @discardableResult func clearStorageHistory() -> Bool {
        guard canEditLedger() else { return false }
        guard !syncBusy else { error = "请等同步完成后再清除恢复历史。"; return false }
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
    @State private var store = AppStore.shared
    private var colorScheme: ColorScheme? {
        switch store.current.preferences.appearance {
        case "dark": .dark
        case "light": .light
        default: nil
        }
    }
    var body: some Scene {
        WindowGroup {
            RootView().environment(store).tint(YubaiColor.brandInk)
                .preferredColorScheme(colorScheme)
                #if os(macOS)
                .frame(minWidth: 920, minHeight: 680)
                #endif
        }
        #if os(macOS)
        .defaultSize(width: 1240, height: 850)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("记一笔") { store.present(.addEntry, from: "add") }.keyboardShortcut("n").disabled(store.locked || !store.current.preferences.onboardingComplete)
                Button("问余白") { store.sheet = .ask("") }.keyboardShortcut("k").disabled(store.locked || !store.current.preferences.onboardingComplete)
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
    private struct PagingPosition: Equatable {
        let destination: Destination
        let aligned: Bool
    }
    private var tabBarHidden: Bool { tabPaths[store.destination]?.isEmpty == false }
    #endif
    var body: some View {
        @Bindable var store = store
        Group {
            if store.locked { lockedView }
            else if let failure = store.loadFailure { recoveryView(failure) }
            else if !store.current.preferences.onboardingComplete { NavigationStack { WelcomeView() } }
            else { mainContent }
        }
        .sheet(item: $store.sheet) { sheet in
            NavigationStack { sheetView(sheet) }.environment(store).tint(YubaiColor.brandInk)
                .environment(\.yubaiSheetSurface, true).environment(\.yubaiZoomNamespace, motionNamespace)
                .yubaiZoomDestination(store.sheetSource ?? sheet.motionSource)
                .appErrors().presentationDragIndicator(.visible).yubaiSheetBackground()
                .overlay { privacyCover }
                #if os(macOS)
                .frame(minWidth: 540, idealWidth: 620, minHeight: 600, idealHeight: 720)
                #endif
        }
        .yubaiFont(YubaiFont.body).foregroundStyle(YubaiColor.label).background(YubaiColor.canvas.ignoresSafeArea())
        .environment(\.yubaiZoomNamespace, motionNamespace)
        .appErrors()
        .overlay(alignment: .bottom) {
            if let toast = store.toast {
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
        .onChange(of: phase) { _, newValue in if newValue == .active { store.refreshTimeDerived(); Task { await store.configureSync(); store.autoSettleFixedFlows() } }; if newValue == .background && store.current.preferences.lockEnabled { store.cancelEntrySaveMotion(); store.sheet = nil; store.pickingInsightDates = false; store.toast = nil; store.locked = true } }
        .task { await store.configureSync(); store.autoSettleFixedFlows() }
        .task(id: "\(store.current.id)-\(store.current.updatedAt)-\(store.locked)-\(store.organizingBatchID != nil)-\(phase)-\(IntelligenceRuntime.isConfigured)-\(IntelligenceRuntime.cloud.model)-\(IntelligenceRuntime.cloud.unavailableModel ?? "")") {
            if phase == .active { await store.refreshButler() }
        }
        .task(id: store.ledger.preferences.weeklyLetterPush) { await WeeklyPush.sync(enabled: store.ledger.preferences.weeklyLetterPush) }
        .overlay(alignment: .top) {
            if !store.locked, store.syncBusy || store.syncChoice != nil {
                VStack(spacing: YubaiSpace.gapGroup) {
                    if store.syncBusy { ProgressView(store.syncStatus ?? "正在从 iCloud 读取…") }
                    if store.syncChoice != nil { Button("选择同步账本版本") { store.sheet = .syncVersions } }
                }.padding(YubaiSpace.insetCard).background(YubaiColor.card)
            }
        }
        .overlay { privacyCover }
        .onOpenURL { url in
            if url.scheme?.lowercased() == "yubai" { store.handleCaptureURL(url); return }
            guard url.isFileURL else { return }; store.importedURL = url
            if !store.locked { store.sheet = url.pathExtension.lowercased() == "yubaibackup" ? .backup : .imports }
        }
        .onChange(of: store.locked) { _, value in if !value { Task { await store.configureSync(); store.autoSettleFixedFlows() }; if let pending = store.pendingQuickSheet { store.pendingQuickSheet = nil; store.sheet = pending }
            else if let url = store.importedURL { store.sheet = url.pathExtension.lowercased() == "yubaibackup" ? .backup : .imports } } }
    }
    @ViewBuilder var mainContent: some View {
        @Bindable var store = store
        #if os(macOS)
        NavigationSplitView {
            List(Destination.allCases, selection: $store.destination) { d in
                Label(d.title, systemImage: d.symbol).tag(d).accessibilityIdentifier("tab_" + d.rawValue)
            }.listStyle(.sidebar).navigationTitle("余白")
                .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 250)
        } detail: {
            NavigationStack { tabRoot(store.destination) }.id(store.destination)
        }
        #else
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: YubaiSpace.none) {
                    ForEach(Destination.allCases) { d in
                        tabNavigation(d).containerRelativeFrame(.horizontal).id(d)
                            .accessibilityHidden(store.destination != d)
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
                    return PagingPosition(destination: destination, aligned: width > 0 && abs(offset - CGFloat(index) * width) <= 1)
                } action: { _, next in
                    visibleTab = next.destination; pagingAligned = next.aligned
                    if pagingPhase == .idle && store.destination != next.destination { store.destination = next.destination }
                }
                .onScrollPhaseChange { _, phase in
                    pagingPhase = phase
                    if phase == .idle && store.destination != visibleTab { store.destination = visibleTab }
                }
                .onChange(of: store.destination) { _, next in
                    if next != visibleTab { scrollTo(next, using: proxy) }
                }
                .onAppear { proxy.scrollTo(store.destination, anchor: .leading) }
                .overlay(alignment: .bottom) {
                    if !tabBarHidden {
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
        guard d != store.destination || d != visibleTab || pagingPhase != .idle || !pagingAligned else { return }
        withAnimation(YubaiMotion.layout(reduceMotion: reduceMotion)) { proxy.scrollTo(d, anchor: .leading) }
    }
    private func tabNavigation(_ d: Destination) -> some View {
        NavigationStack(path: Binding(get: { tabPaths[d] ?? NavigationPath() }, set: { tabPaths[d] = $0 })) {
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
        case .forecast: Page { ForecastChart(funds: store.funds, height: 150) }.navigationTitle("现金会怎么走").yubaiNavigation()
        case .upcomingPayments: Page { UpcomingPaymentsView() }.navigationTitle("接下来要付的").yubaiNavigation()
        case .fixedFlows: FixedFlowsView()
        case .butlerCards: ButlerListView()
        case .unsortedGroups(let id): UnsortedGroupsView(questionID: id)
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
        case .account(let account): AccountEditor(account: account)
        case .imports: ImportView()
        case .accounts: AccountsView()
        case .ask(let text): AskYubaiView(initialText: text)
        case .capture(let data): AskYubaiView(initialImage: data)
        case .wishlist(let id): WishlistView(focusedWishID: id)
        case .backup: BackupView()
        case .history: RecoveryVersionsView()
        case .syncVersions: SyncVersionsView()
        case .fundsCalculation: FundsCalculationView()
        case .intelligencePrivacy: IntelligencePrivacyView().toolbar { CloseButton() }
        case .cardEvidence(let id): ButlerEvidenceView(cardID: id)
        case .cardQuestion(let id): ButlerQuestionView(cardID: id)
        case .cardProposal(let id): ButlerProposalView(changeID: id)
        case .letters: LettersView()
        case .letter(let id): LetterDetailView(cardID: id).toolbar { CloseButton() }
        case .reconcile(let id):
            if let account = store.current.accounts.first(where: { $0.id == id }) { AccountEditor(account: account, startsReconciling: true) }
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
    @ViewBuilder var privacyCover: some View {
        if (phase != .active || store.locked) && store.current.preferences.lockEnabled {
            if phase != .active { ZStack { YubaiColor.canvas.ignoresSafeArea(); BrandMark(size: YubaiSize.tapMin * 2 + YubaiSpace.space8).accessibilityLabel("账本已保护") } }
        }
    }
    func recoveryView(_ message: String) -> some View {
        VStack(spacing: YubaiSpace.gapSection) { Image(systemName: "externaldrive.badge.exclamationmark").yubaiFont(YubaiFont.amountDisplay); Text("账本需要恢复").yubaiFont(YubaiFont.lead); Text(message).foregroundStyle(YubaiColor.labelSecondary); Button("查看本地恢复记录") { store.sheet = .history }; Button("从备份恢复") { store.sheet = .backup } }.padding(YubaiSpace.gapSection).frame(maxWidth: 540)
    }
}

#if os(iOS)
private struct FloatingTabBar: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .title3) private var scaledIconSize = YubaiSize.tabIcon
    @ScaledMetric(relativeTo: .title2) private var scaledAddSize = YubaiFont.addIcon.size
    @Namespace private var selection
    var select: (Destination) -> Void
    var body: some View {
        HStack(spacing: YubaiSpace.none) {
            tab(.overview); tab(.insights)
            Button { store.sheetSource = nil; store.sheet = .addEntry } label: {
                Image(systemName: "plus").font(.system(size: min(scaledAddSize, YubaiFont.amountLarge.size), weight: YubaiFont.addIcon.weight)).foregroundStyle(YubaiColor.white)
                    .frame(width: YubaiSize.tabAdd, height: YubaiSize.tabAdd).background(YubaiColor.brand, in: Circle())
                    .shadow(color: YubaiColor.brandInk.opacity(0.3), radius: 6, y: 4)
            }.buttonStyle(.plain).padding(.horizontal, YubaiSpace.space8)
                .accessibilityLabel("记一笔").accessibilityIdentifier("addEntry")
            tab(.entries); tab(.settings)
        }.padding(.horizontal, YubaiSpace.space8).frame(height: YubaiSize.tabBarHeight)
            .background(YubaiColor.raised, in: Capsule())
            .overlay { Capsule().strokeBorder(YubaiColor.separator, lineWidth: 1).allowsHitTesting(false) }
            .yubaiShadow(YubaiShadow.float)
            .animation(YubaiMotion.layout(reduceMotion: reduceMotion), value: store.destination)
            .accessibilityElement(children: .contain).accessibilityLabel("主导航").accessibilityIdentifier("mainNavigation")
    }
    private func tab(_ d: Destination) -> some View {
        let selected = store.destination == d
        let iconSize = min(scaledIconSize, YubaiSize.barMax)
        return Button { select(d) } label: {
            VStack(spacing: YubaiSpace.space4) {
                Group {
                    if d == .overview { Image("TabWaterMark").renderingMode(.template).resizable().scaledToFit() }
                    else { Image(systemName: d.symbol).symbolVariant(.none).font(.system(size: iconSize, weight: selected ? .semibold : .regular)) }
                }
                .frame(width: iconSize, height: iconSize)
                Text(d.title).yubaiFont(YubaiFont.tabLabel, weight: selected ? .semibold : .regular).lineLimit(1)
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
