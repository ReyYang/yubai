import SwiftUI
import Observation
import LocalAuthentication
import YubaiCore

enum Destination: String, CaseIterable, Identifiable {
    case overview, ledger, plans, insights, settings
    var id: Self { self }
    var title: String { switch self { case .overview: "现在"; case .ledger: "账本"; case .plans: "安排"; case .insights: "洞察"; case .settings: "我的" } }
    var symbol: String { switch self { case .overview: "water.waves"; case .ledger: "text.book.closed"; case .plans: "calendar"; case .insights: "chart.xyaxis.line"; case .settings: "person.crop.circle" } }
}
enum AppSheet: Identifiable {
    case entry(Entry?), account(Account?), plan(Plan?), goal(Goal?), rent(Rent?), imports, accounts, advice, categories, rules, backup, history, rentDetail(UUID), entryDetail(UUID), guide, fundsCalculation
    var id: String { String(describing: self) }
}

@MainActor @Observable final class AppStore {
    private(set) var ledger = Ledger(); private(set) var demo: Ledger?
    var current: Ledger { demo ?? ledger }; var isDemo: Bool { demo != nil }
    let repository: LedgerRepository
    var destination: Destination = .overview; var sheet: AppSheet?; var error: String?; var toast: String?
    var loadFailure: String?; var locked = false; var importedURL: URL?
    var errorHosts: [UUID] = []
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
        // XCTest supplies synthetic fixtures to the simulator's own Documents folder.
        // Release builds do not compile this fixture setup path.
        if let i = args.firstIndex(of: "--test-ledger"), args.indices.contains(i + 1), UUID(uuidString: args[i + 1]) != nil {
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            for (key, name) in [("YUBAI_UI_STATEMENT", "余白验证账单.csv"), ("YUBAI_UI_RECEIPT", "余白验证截图.png")] {
                if let encoded = ProcessInfo.processInfo.environment[key], let bytes = Data(base64Encoded: encoded), bytes.count < 1_000_000 {
                    try? FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
                    try? bytes.write(to: documents.appendingPathComponent(name), options: .atomic)
                }
            }
        }
        #endif
        do {
            ledger = try repository.load()
            locked = ledger.preferences.lockEnabled
            applyLocalGGUFSoftDisableMigrationIfNeeded()
        } catch { loadFailure = error.localizedDescription }
        if args.contains("--demo") { demo = SampleData.ledger(); locked = false }
    }

    /// One-shot: old default had `downloadedModelEnabled = true`, which eager-loaded GGUF and crashed devices.
    /// Turn it off once so cloud / rules become the safe path; users can re-enable under 高级选项.
    private func applyLocalGGUFSoftDisableMigrationIfNeeded() {
        let key = "yubai.migrated.localGGUFSoftDisable.v1"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        guard ledger.preferences.downloadedModelEnabled else { return }
        do {
            var next = ledger
            next.preferences.downloadedModelEnabled = false
            next.updatedAt = Date()
            try repository.save(next, reason: "本机模型默认关闭（稳定性）")
            ledger = next
            IntelligenceRuntime.resetLocalInferenceGate()
        } catch {
            // Non-fatal: routing still gates load; preference may stay true until next save.
        }
    }
    @discardableResult func update(_ reason: String, _ change: (inout Ledger) throws -> Void) -> Bool {
        guard !locked || isDemo else { error = "请先解锁账本。"; return false }
        guard loadFailure == nil || isDemo else { error = "请先恢复账本，原文件将保持不变。"; return false }
        let before = current; var next = before
        do {
            try change(&next); next.updatedAt = Date(); try next.validate()
            if isDemo { demo = next } else { try repository.save(next, reason: reason); ledger = next }
            undoLedger = before; undoLabel = reason; toast = reason + "完成"; return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func undo() {
        guard let previous = undoLedger else { return }
        do {
            if isDemo { demo = previous } else { try repository.save(previous, reason: "撤销"); ledger = previous }
            undoLedger = nil; undoLabel = nil; toast = "已撤销上一项修改"
        } catch { self.error = error.localizedDescription }
    }
    func startDemo() { demo = SampleData.ledger(); undoLedger = nil; undoLabel = nil; destination = .overview; sheet = nil }
    func endDemo() { demo = nil; undoLedger = nil; undoLabel = nil; destination = .overview; sheet = nil; locked = ledger.preferences.lockEnabled }
    @discardableResult func restore(_ restored: Ledger) -> Bool {
        guard !restored.isSample, !locked else { error = "请先解锁真实账本；示例备份不能覆盖真实数据。"; return false }
        do { try repository.restoreBackup(restored); ledger = restored; demo = nil; loadFailure = nil; undoLedger = nil; undoLabel = nil; toast = "账本已恢复，原账本已保留"; return true }
        catch { self.error = error.localizedDescription; return false }
    }
    func recover(_ recovery: Recovery) {
        do { ledger = try repository.recover(recovery); loadFailure = nil; toast = "已恢复到所选版本"; sheet = nil }
        catch { self.error = error.localizedDescription }
    }
    func unlock() async {
        let context = LAContext()
        do { if try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "解锁你的余白账本") { locked = false } }
        catch { self.error = "未能解锁。可以重试 Face ID、Touch ID 或设备密码。" }
    }
    func saveEntry(_ entry: Entry) -> Bool {
        update("保存记录") { l in
            if let i = l.entries.firstIndex(where: { $0.id == entry.id }) { var edited = entry; edited.userEdited = true; l.entries[i] = edited }
            else { l.entries.append(entry) }
        }
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
                Button("记一笔") { store.sheet = .entry(nil) }.keyboardShortcut("n").disabled(store.locked || !store.current.preferences.onboardingComplete)
                Button("导入账单") { store.sheet = .imports }.keyboardShortcut("i").disabled(store.locked || !store.current.preferences.onboardingComplete)
                Button("购买前想一想") { store.sheet = .advice }.keyboardShortcut("k").disabled(store.locked || !store.current.preferences.onboardingComplete)
            }
            CommandGroup(replacing: .undoRedo) { Button("撤销上一项修改") { store.undo() }.keyboardShortcut("z").disabled(store.undoLabel == nil || store.locked) }
        }
        #endif
    }
}

struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.scenePhase) private var phase
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        @Bindable var store = store
        Group {
            if store.locked { lockedView }
            else if let failure = store.loadFailure, !store.isDemo { recoveryView(failure) }
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
                    #if os(iOS)
                    .padding(.bottom, YubaiSize.tabbarHeight + YubaiSpace.space2)
                    #endif
                    .transition(.asymmetric(insertion: .identity, removal: .opacity.animation(YubaiMotion.toastOut(reduceMotion: reduceMotion))))
            }
        }
        .onChange(of: phase) { _, newValue in if newValue == .background && store.current.preferences.lockEnabled && !store.isDemo { store.sheet = nil; store.toast = nil; store.locked = true } }
        .overlay { privacyCover }
        .onOpenURL { url in guard url.isFileURL else { return }; store.importedURL = url; if !store.locked { store.sheet = url.pathExtension.lowercased() == "yubaibackup" ? .backup : .imports } }
        .onChange(of: store.locked) { _, value in if !value, let url = store.importedURL { store.sheet = url.pathExtension.lowercased() == "yubaibackup" ? .backup : .imports } }
    }
    @ViewBuilder var mainContent: some View {
        @Bindable var store = store
        #if os(macOS)
        NavigationSplitView {
            VStack(alignment: .leading, spacing: YubaiSpace.space24) {
                BrandMark(variant: .mark).padding(.top, YubaiSpace.space24).padding(.horizontal, YubaiSpace.space20)
                List(Destination.allCases, selection: $store.destination) { d in Label(d.title, systemImage: d.symbol).yubaiFont(YubaiFont.rowTitle).padding(.vertical, YubaiSpace.space8).tag(d) }.listStyle(.sidebar).scrollContentBackground(.hidden).background(YubaiColor.canvas)
                VStack(alignment: .leading, spacing: YubaiSpace.space10) { Label("留白，给真正重要的事", systemImage: "leaf").yubaiFont(YubaiFont.caption); Text("本地账本 · 由你掌握").yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary) }.padding(YubaiSpace.space20)
            }.background(YubaiColor.canvas).navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 250)
        } detail: { NavigationStack { destination(store.destination) } }
        #else
        TabView(selection: $store.destination) {
            ForEach(Destination.allCases) { d in NavigationStack { destination(d) }.toolbarBackground(YubaiColor.raised, for: .tabBar).toolbarBackground(.visible, for: .tabBar).tabItem { Label(d.title, systemImage: d.symbol) }.tag(d) }
        }.tint(YubaiColor.label)
        #endif
    }
    @ViewBuilder func destination(_ d: Destination) -> some View {
        Group { switch d { case .overview: OverviewView(); case .ledger: LedgerView(); case .plans: PlansView(); case .insights: InsightsView(); case .settings: SettingsView() } }
            .safeAreaInset(edge: .top, spacing: 0) {
                if store.isDemo { HStack { Text(textSize.isAccessibilitySize ? "示例账本" : "示例账本 · 不含你的真实数据").accessibilityLabel("示例账本，不含你的真实数据"); Spacer(); Button(textSize.isAccessibilitySize ? "退出" : "退出示例") { store.endDemo() } }.yubaiFont(YubaiFont.caption).padding(.horizontal, YubaiSpace.space20).padding(.vertical, YubaiSpace.space8).foregroundStyle(YubaiColor.labelMuted).background(YubaiColor.card) }
            }
    }
    @ViewBuilder func sheetView(_ sheet: AppSheet) -> some View {
        switch sheet {
        case .entry(let entry): EntryEditor(entry: entry)
        case .account(let account): AccountEditor(account: account)
        case .plan(let plan): PlanEditor(plan: plan)
        case .goal(let goal): GoalEditor(goal: goal)
        case .rent(let rent): RentEditor(rent: rent)
        case .imports: ImportView()
        case .accounts: AccountsView()
        case .advice: AdviceView()
        case .categories: CategoriesView()
        case .rules: RulesView()
        case .backup: BackupView()
        case .history: HistoryView()
        case .rentDetail(let id): RentDetailView(rentID: id)
        case .entryDetail(let id): EntryDetailView(entryID: id)
        case .guide: GuideView()
        case .fundsCalculation: FundsCalculationView()
        }
    }
    var lockedView: some View {
        VStack(spacing: YubaiSpace.space24) { BrandMark(); Image(systemName: "lock.shield").yubaiFont(YubaiFont.amountDisplay).foregroundStyle(YubaiColor.labelSecondary); Text("你的账本，只属于你").yubaiFont(YubaiFont.lead); Button("解锁余白") { Task { await store.unlock() } }.buttonStyle(PrimaryButtonStyle()) }.padding(YubaiSpace.space24)
    }
    @ViewBuilder var privacyCover: some View {
        if (phase != .active || store.locked) && store.current.preferences.lockEnabled && !store.isDemo {
            if phase != .active { ZStack { YubaiColor.canvas.ignoresSafeArea(); VStack(spacing: YubaiSpace.space18) { BrandMark(); Label("个人账本已保护", systemImage: "lock.shield").foregroundStyle(YubaiColor.labelSecondary) } } }
        }
    }
    func recoveryView(_ message: String) -> some View {
        VStack(spacing: YubaiSpace.space20) { Image(systemName: "externaldrive.badge.exclamationmark").yubaiFont(YubaiFont.amountDisplay); Text("账本需要恢复").yubaiFont(YubaiFont.lead); Text(message).foregroundStyle(YubaiColor.labelSecondary); Text("原文件已保留，余白不会用空账本覆盖它。").yubaiFont(YubaiFont.callout); Button("查看本地恢复记录") { store.sheet = .history }; Button("从备份恢复") { store.sheet = .backup } }.padding(YubaiSpace.space24).frame(maxWidth: 540)
    }
}
