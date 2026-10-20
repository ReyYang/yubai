import SwiftUI
import Observation
import LocalAuthentication
import YubaiCore

enum Destination: String, CaseIterable, Identifiable {
    case overview, settings
    var id: Self { self }
    var title: String { self == .overview ? "现在" : "我" }
    var symbol: String { self == .overview ? "water.waves" : "person.crop.circle" }
}
enum AppSheet: Identifiable {
    case account(Account?), imports, accounts, backup, history, fundsCalculation
    case ask(String), capture(Data), wishlist(UUID?)
    case cardEvidence(UUID), cardQuestion(UUID), cardProposal(UUID), letters, reconcile(UUID)
    var id: String { String(describing: self) }
}

@MainActor @Observable final class AppStore {
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
    var sortedEntries: [Entry] {
        _ = derivedRevision
        if let cachedEntries { return cachedEntries }
        let rows = current.entries.sorted { $0.date > $1.date }
        cachedEntries = rows; return rows
    }
    private func invalidateDerived() { cachedEntries = nil; refreshTimeDerived() }
    func refreshTimeDerived() { cachedFunds = nil; derivedRevision &+= 1 }
    let repository: LedgerRepository
    var destination: Destination = .overview; var sheet: AppSheet?; var error: String?; var toast: String?
    var loadFailure: String?; var locked = false; var importedURL: URL?
    var errorHosts: [UUID] = []
    var organizingBatchID: UUID?
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
        repository = LedgerRepository(directory: directory)
        #if DEBUG && targetEnvironment(simulator)
        do { try UITestSupport.prepare(repository) } catch { loadFailure = error.localizedDescription; return }
        #endif
        do {
            ledger = try repository.load()
            locked = ledger.preferences.lockEnabled
        } catch { loadFailure = error.localizedDescription }
    }

    @discardableResult func update(_ reason: String, preservingUpdatedAt: Bool = false, recordUndo: Bool = true, _ change: (inout Ledger) throws -> Void) -> Bool {
        guard !locked else { error = "请先解锁账本。"; return false }
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
            try repository.save(next, reason: reason); ledger = next
            if recordUndo { undoLedger = before; undoLabel = reason; toast = reason + "完成" }; return true
        } catch { self.error = error.localizedDescription; return false }
    }
    @discardableResult func apply(_ changeSet: ChangeSet, label: String, finishing: (inout Ledger) throws -> Void = { _ in }) -> Bool {
        var skipped: [String] = []
        let saved = update(label) { ledger in
            if !changeSet.items.isEmpty { skipped = try changeSet.apply(to: &ledger) }
            else if changeSet.source != "导入整理" { try changeSet.validateStructure() }
            try finishing(&ledger)
            ledger.pendingChanges.removeAll { $0.id == changeSet.id }
            for i in ledger.cards.indices where ledger.cards[i].action == .confirmChangeSet(changeSet.id) {
                ledger.cards[i].dismissedAt = Date()
            }
        }
        if saved, !skipped.isEmpty { toast = label + "完成；" + skipped.joined(separator: "；") }
        return saved
    }
    func undo() {
        guard let previous = undoLedger else { return }
        do {
            try repository.save(previous, reason: "撤销"); ledger = previous
            undoLedger = nil; undoLabel = nil; toast = "已撤销上一项修改"
        } catch { self.error = error.localizedDescription }
    }
    @discardableResult func restore(_ restored: Ledger) -> Bool {
        guard !locked else { error = "请先解锁账本。"; return false }
        do { try repository.restoreBackup(restored); ledger = restored; loadFailure = nil; undoLedger = nil; undoLabel = nil; toast = "账本已恢复，原账本已保留"; return true }
        catch { self.error = error.localizedDescription; return false }
    }
    @discardableResult func recover(_ recovery: Recovery) -> Bool {
        do { ledger = try repository.recover(recovery); loadFailure = nil; undoLedger = nil; undoLabel = nil; toast = "已恢复到所选版本"; sheet = nil; return true }
        catch { self.error = error.localizedDescription; return false }
    }
    func unlock() async {
        let context = LAContext()
        do { if try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "解锁你的余白账本") { locked = false } }
        catch { self.error = "未能解锁。可以重试 Face ID、Touch ID 或设备密码。" }
    }

}

@main struct YubaiApp: App {
    @State private var store = AppStore()
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
            CommandGroup(after: .newItem) {
                Button("导入账单") { store.sheet = .imports }.keyboardShortcut("i").disabled(store.locked || !store.current.preferences.onboardingComplete)
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
                .appErrors()
                .overlay { privacyCover }
                #if os(macOS)
                .frame(minWidth: 540, idealWidth: 620, minHeight: 600, idealHeight: 720)
                #endif
        }
        .yubaiFont(YubaiFont.body).foregroundStyle(YubaiColor.label).background(YubaiColor.canvas.ignoresSafeArea())
        .appErrors()
        .overlay(alignment: .bottom) {
            if let toast = store.toast {
                Toast(text: toast, onUndo: store.undoLabel == nil ? nil : { store.undo() }, onDismiss: { if store.toast == toast { store.toast = nil } })
                    .id(toast)
                    .padding(.bottom, YubaiSize.buttonHeight + YubaiSpace.space24)
                    #if os(iOS)
                    .padding(.bottom, YubaiSize.tabbarHeight)
                    #endif
                    .transition(.asymmetric(insertion: .identity, removal: .opacity.animation(YubaiMotion.toastOut(reduceMotion: reduceMotion))))
            }
        }
        .onChange(of: phase) { _, newValue in if newValue == .active { store.refreshTimeDerived() }; if newValue == .background && store.current.preferences.lockEnabled { store.sheet = nil; store.toast = nil; store.locked = true } }
        .task(id: "\(store.current.id)-\(store.current.preferences.cloudAIEnabled)-\(store.locked)-\(phase)") {
            if phase == .active { await store.organizePendingImports() }
        }
        .task(id: "\(store.current.id)-\(store.current.updatedAt)-\(store.locked)-\(store.organizingBatchID != nil)-\(phase)") {
            if phase == .active { await store.refreshButler() }
        }
        .task(id: store.ledger.preferences.weeklyLetterPush) { await WeeklyPush.sync(enabled: store.ledger.preferences.weeklyLetterPush) }
        .overlay { privacyCover }
        .onOpenURL { url in guard url.isFileURL else { return }; store.importedURL = url; if !store.locked { store.sheet = url.pathExtension.lowercased() == "yubaibackup" ? .backup : .imports } }
        .onChange(of: store.locked) { _, value in if !value, let url = store.importedURL { store.sheet = url.pathExtension.lowercased() == "yubaibackup" ? .backup : .imports } }
    }
    @ViewBuilder var mainContent: some View {
        @Bindable var store = store
        #if os(macOS)
        NavigationSplitView {
            List(Destination.allCases, selection: $store.destination) { d in
                Label(d.title, systemImage: d.symbol).tag(d)
            }.listStyle(.sidebar).navigationTitle("余白")
                .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 250)
        } detail: {
            NavigationStack { destination(store.destination) }.safeAreaInset(edge: .bottom, spacing: 0) { askAccessory }
        }
        #else
        TabView(selection: $store.destination) {
            ForEach(Destination.allCases) { d in
                NavigationStack { destination(d) }.safeAreaInset(edge: .bottom, spacing: 0) { askAccessory }
                    .toolbarBackground(YubaiColor.raised, for: .tabBar).toolbarBackground(.visible, for: .tabBar)
                    .tabItem { Label(d.title, systemImage: d.symbol) }.tag(d)
            }
        }.tint(YubaiColor.label)
        #endif
    }
    // Attach to the navigation container, so pushed pages keep the same entry point.
    private var askAccessory: some View {
        Button { store.sheet = .ask("") } label: { Label("问余白", systemImage: "sparkle") }
            .buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("askYubai")
            .frame(maxWidth: 420).padding(.horizontal, YubaiSpace.space18).padding(.vertical, YubaiSpace.space8)
            .frame(maxWidth: .infinity).background(YubaiColor.canvas)
    }
    @ViewBuilder func destination(_ d: Destination) -> some View {
        switch d { case .overview: OverviewView(); case .settings: SettingsView() }
    }
    @ViewBuilder func sheetView(_ sheet: AppSheet) -> some View {
        switch sheet {
        case .account(let account): AccountEditor(account: account)
        case .imports: ImportView()
        case .accounts: AccountsView()
        case .ask(let text): AskYubaiView(initialText: text)
        case .capture(let data): AskYubaiView(initialImage: data)
        case .wishlist(let id): WishlistView(focusedWishID: id)
        case .backup: BackupView()
        case .history: RecoveryVersionsView()
        case .fundsCalculation: FundsCalculationView()
        case .cardEvidence(let id): ButlerEvidenceView(cardID: id)
        case .cardQuestion(let id): ButlerQuestionView(cardID: id)
        case .cardProposal(let id): ButlerProposalView(changeID: id)
        case .letters: LettersView()
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
        VStack(spacing: YubaiSpace.space20) { Image(systemName: "externaldrive.badge.exclamationmark").yubaiFont(YubaiFont.amountDisplay); Text("账本需要恢复").yubaiFont(YubaiFont.lead); Text(message).foregroundStyle(YubaiColor.labelSecondary); Text("原文件已保留，余白不会用空账本覆盖它。").yubaiFont(YubaiFont.callout); Button("查看本地恢复记录") { store.sheet = .history }; Button("从备份恢复") { store.sheet = .backup } }.padding(YubaiSpace.space24).frame(maxWidth: 540)
    }
}
