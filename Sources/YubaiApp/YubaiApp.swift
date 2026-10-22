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
enum AppSheet: Identifiable {
    case account(Account?), imports, accounts, backup, history, fundsCalculation, syncVersions, addEntry, addPlan
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
    private func invalidateDerived() { cachedEntries = nil; refreshTimeDerived() }
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
    func unlock() async {
        let context = LAContext()
        do { if try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "解锁你的余白账本") { locked = false; if syncChoice != nil { sheet = .syncVersions } } }
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
    @State private var hiddenTabBars: [Destination: Bool] = [:]
    @State private var keyboardVisible = false
    @State private var scrolledTab: Destination? = .overview
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
                .appErrors().presentationDragIndicator(.visible)
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
                    .padding(.bottom, YubaiSize.floatingTabbarHeight + YubaiSize.floatingTabbarBottom + YubaiSpace.space12)
                    #else
                    .padding(.bottom, YubaiSize.buttonHeight + YubaiSpace.space24)
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
        .task(id: "\(store.current.id)-\(store.current.preferences.cloudAIEnabled)-\(store.locked)-\(phase)-\(IntelligenceRuntime.isConfigured)-\(IntelligenceRuntime.cloud.model)-\(IntelligenceRuntime.cloud.unavailableModel ?? "")") {
            if phase == .active { await store.organizePendingImports() }
        }
        .task(id: "\(store.current.id)-\(store.current.updatedAt)-\(store.locked)-\(store.organizingBatchID != nil)-\(phase)-\(IntelligenceRuntime.isConfigured)-\(IntelligenceRuntime.cloud.model)-\(IntelligenceRuntime.cloud.unavailableModel ?? "")") {
            if phase == .active { await store.refreshButler() }
        }
        .task(id: store.ledger.preferences.weeklyLetterPush) { await WeeklyPush.sync(enabled: store.ledger.preferences.weeklyLetterPush) }
        .overlay(alignment: .top) {
            if !store.locked, store.syncBusy || store.syncChoice != nil {
                VStack {
                    if store.syncBusy { ProgressView(store.syncStatus ?? "正在从 iCloud 读取…") }
                    if store.syncChoice != nil { Button("选择同步账本版本") { store.sheet = .syncVersions } }
                }.padding().background(YubaiColor.card)
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
        ScrollView(.horizontal) {
            HStack(spacing: 0) {
                ForEach(Destination.allCases) { d in
                    tabNavigation(d).containerRelativeFrame(.horizontal).id(d)
                        .accessibilityHidden(store.destination != d)
                }
            }.scrollTargetLayout()
        }.scrollTargetBehavior(.paging).scrollPosition(id: $scrolledTab, anchor: .center)
            .scrollIndicators(.hidden)
            .scrollDisabled(store.pagingLocked || hiddenTabBars[store.destination] == true || store.sheet != nil || store.pickingInsightDates)
            .scrollClipDisabled()
            .background(YubaiColor.canvas.ignoresSafeArea())
            .onChange(of: scrolledTab) { _, next in
                if let next, next != store.destination { store.destination = next }
            }
            .onChange(of: store.destination) { _, next in
                guard next != scrolledTab else { return }
                withAnimation(YubaiMotion.layout(reduceMotion: reduceMotion)) { scrolledTab = next }
            }
            .onAppear { scrolledTab = store.destination }
            .overlay(alignment: .bottom) {
                if hiddenTabBars[store.destination] != true {
                    FloatingTabBar().padding(.horizontal, YubaiSpace.space18).padding(.bottom, YubaiSize.floatingTabbarBottom)
                        .opacity(keyboardVisible ? 0 : 1).allowsHitTesting(!keyboardVisible).accessibilityHidden(keyboardVisible)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in keyboardVisible = true }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidHideNotification)) { _ in keyboardVisible = false }
        #endif
    }
    #if os(iOS)
    private func tabNavigation(_ d: Destination) -> some View {
        NavigationStack {
            tabRoot(d).background(YubaiColor.canvas.ignoresSafeArea())
        }.toolbarBackground(.hidden, for: .navigationBar)
            .environment(\.yubaiTabBarHidden, Binding(get: { hiddenTabBars[d] ?? false }, set: { hiddenTabBars[d] = $0 }))
            .environment(\.isScrollEnabled, true)
            .scrollClipDisabled(false)
            .background(YubaiColor.canvas.ignoresSafeArea())
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
                }.padding(.horizontal, YubaiSpace.space18).padding(.bottom, 22)
            }
        }.background(YubaiColor.canvas)
        #else
        destination(d).frame(maxWidth: .infinity, maxHeight: .infinity)
            .modifier(TabBarVisibility(hidden: false))
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
        VStack(spacing: YubaiSpace.space24) { BrandMark(); Image(systemName: "lock.shield").yubaiFont(YubaiFont.amountDisplay).foregroundStyle(YubaiColor.labelSecondary); Text("你的账本，只属于你").yubaiFont(YubaiFont.lead); Button("解锁余白") { Task { await store.unlock() } }.buttonStyle(PrimaryButtonStyle()) }.padding(YubaiSpace.space24)
    }
    @ViewBuilder var privacyCover: some View {
        if (phase != .active || store.locked) && store.current.preferences.lockEnabled {
            if phase != .active { ZStack { YubaiColor.canvas.ignoresSafeArea(); VStack(spacing: YubaiSpace.space18) { BrandMark(); Label("个人账本已保护", systemImage: "lock.shield").foregroundStyle(YubaiColor.labelSecondary) } } }
        }
    }
    func recoveryView(_ message: String) -> some View {
        VStack(spacing: YubaiSpace.space20) { Image(systemName: "externaldrive.badge.exclamationmark").yubaiFont(YubaiFont.amountDisplay); Text("账本需要恢复").yubaiFont(YubaiFont.lead); Text(message).foregroundStyle(YubaiColor.labelSecondary); Text("原文件已保留，请选择恢复记录。").yubaiFont(YubaiFont.callout); Button("查看本地恢复记录") { store.sheet = .history }; Button("从备份恢复") { store.sheet = .backup } }.padding(YubaiSpace.space24).frame(maxWidth: 540)
    }
}

#if os(iOS)
private struct FloatingTabBar: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selection
    var body: some View {
        HStack(spacing: 0) {
            tab(.overview); tab(.insights)
            Button { store.sheetSource = nil; store.sheet = .addEntry } label: {
                Image(systemName: "plus").yubaiFont(YubaiFont.addIcon).foregroundStyle(YubaiColor.white)
                    .frame(width: 54, height: 54).background(YubaiColor.brand, in: Circle())
                    .shadow(color: YubaiColor.brandInk.opacity(0.3), radius: 6, y: 4)
            }.buttonStyle(.plain).padding(.horizontal, 4)
                .accessibilityLabel("记一笔").accessibilityIdentifier("addEntry")
            tab(.entries); tab(.settings)
        }.padding(.horizontal, 6).frame(height: YubaiSize.floatingTabbarHeight)
            .background(YubaiColor.raised, in: Capsule())
            .overlay { Capsule().strokeBorder(YubaiColor.separator, lineWidth: 1).allowsHitTesting(false) }
            .yubaiShadow(YubaiShadow.float)
            .animation(YubaiMotion.layout(reduceMotion: reduceMotion), value: store.destination)
            .accessibilityElement(children: .contain).accessibilityLabel("主导航").accessibilityIdentifier("mainNavigation")
    }
    private func tab(_ d: Destination) -> some View {
        let selected = store.destination == d
        return Button { store.destination = d } label: {
            VStack(spacing: 2) {
                Group {
                    if d == .overview { Image("TabWaterMark").renderingMode(.template).resizable().scaledToFit().frame(width: 20, height: 20) }
                    else { Image(systemName: d.symbol).symbolVariant(.none).yubaiFont(YubaiFont.tabIcon, weight: selected ? .semibold : .regular).frame(height: 20) }
                }
                Text(d.title).yubaiFont(YubaiFont.tabLabel, weight: selected ? .semibold : .regular).lineLimit(1)
            }.foregroundStyle(selected ? YubaiColor.brandInk : YubaiColor.labelSecondary)
                .frame(maxWidth: .infinity).frame(height: 50).contentShape(Capsule())
                .background {
                    if selected { Capsule().fill(YubaiColor.card).matchedGeometryEffect(id: "selection", in: selection) }
                }
        }.buttonStyle(.plain).accessibilityLabel(d.title).accessibilityIdentifier("tab_" + d.rawValue)
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
#endif
