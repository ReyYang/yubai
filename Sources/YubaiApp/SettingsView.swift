import SwiftUI
import UniformTypeIdentifiers
import LocalAuthentication
import YubaiCore

/// 设置: five groups of rows, values live from the ledger.
struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @State private var storageSize: String?
    @State private var unlockName = "面容 ID 解锁"
    @State private var cloudAI = false

    var body: some View {
        let _ = SettingsRenderCounts.hit("settingsBody")
        let ledger = store.current, now = store.financialNow
        let hidden = store.preferences.hideAmounts
        VStack(spacing: .zero) {
            OverviewNavigationBar(title: "设置")
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: SettingsSpec.groupGap) {
                        DSSettingsCard {
                            link(.cycle, "周期起始日", SettingsDisplay.cycleDay(CycleStart.day(in: ledger, now: now)), brand: true, first: true, id: "settingsCycle") { store.settingsSheet = .cycle }
                            link(.saveFirst, "先攒", SettingsDisplay.money(SettingsSummary.savingTarget(in: ledger, now: now), hidden: hidden), brand: true, id: "settingsSaving") { store.settingsSheet = .saving }
                            link(.floor, "底线存款", store.profile.floorAmount.map { SettingsDisplay.money($0, hidden: hidden) } ?? "未设", brand: true, id: "settingsFloor") { store.settingsSheet = .floor }
                        }
                        DSSettingsCard {
                            link(.subscription, "固定订阅", "每月 " + SettingsDisplay.money(SettingsSummary.monthlyFixed(in: ledger, now: now).total, hidden: hidden), first: true, id: "settingsRecurring") { store.tabRouteRequest = .recurring }
                            link(.catAll, "分类", "\(ledger.orderedCategories(income: false).count) 个", id: "openCategories") { store.tabRouteRequest = .categorySettings }
                            link(.acctBalance, "币种", SettingsDisplay.currencies(store.preferences), id: "settingsCurrency") { store.tabRouteRequest = .currency }
                            link(.bolt, "快速记账", "Apple Pay", id: "openQuickCapture") { store.tabRouteRequest = .quickCapture }
                        }
                        DSSettingsCard {
                            link(.ai, "余白的 AI", cloudAI ? "DeepSeek" : "未开", first: true, id: "openIntelligencePrivacy") { store.tabRouteRequest = .aiSettings }
                            link(.memory, "余白记得的", "\(store.settingsSummary.memoryCount) 条", id: "openMemories") { store.tabRouteRequest = .memories }
                            link(.heart, "心愿与回顾", "\(WishesHub.wishCount(in: ledger)) 件心愿", id: "openWishesHub") { store.tabRouteRequest = .wishesHub }
                            link(.bell, "通知", "\(SettingsDisplay.noticeCount(store.preferences)) 项", id: "openNoticeSettings") { store.tabRouteRequest = .notices }
                        }
                        DSSettingsCard {
                            DSSettingsRow(icon: .lock, name: unlockName, accessory: .toggle(Binding(get: { store.preferences.lockEnabled }, set: setLock)), separator: false)
                                .accessibilityIdentifier("settingsLock")
                            if SettingsDisplay.iCloudAvailable {
                                DSSettingsRow(icon: .cloud, name: "iCloud 同步", accessory: .toggle(Binding(get: { store.ledgerLocation == .iCloud }, set: { on in
                                    Task { await store.switchLedgerLocation(to: on ? .iCloud : .local) }
                                })))
                                .accessibilityIdentifier("settingsICloud")
                            }
                            link(.half, "外观", SettingsDisplay.appearance(store.preferences.appearance), id: "settingsAppearance") { store.settingsSheet = .appearance }
                        }
                        DSSettingsCard {
                            link(.clock, "备份与恢复", store.preferences.lastBackupAt.map(SettingsDisplay.monthDay) ?? "未备份", first: true, id: "openBackup") { store.tabRouteRequest = .backup }
                            link(.inbox, "导入记录", store.imports.filter { $0.undoneAt == nil }.map(\.importedAt).max().map(SettingsDisplay.monthDay) ?? "", id: "openImportHistory") { store.tabRouteRequest = .importHistory }
                            link(.export, "导出账单", "CSV", id: "settingsExport") { store.settingsSheet = .export }
                            link(.disk, "存储空间", storageSize ?? "", id: "openStorage") { store.tabRouteRequest = .storage }
                        }
                        Text("余白 " + SettingsDisplay.version).dsText(DS.Font.tCaption).monospacedDigit().foregroundStyle(DS.Color.ink3)
                            .frame(maxWidth: .infinity).id("settingsEnd")
                    }
                    .padding(.horizontal, DS.Space.s16).padding(.top, DS.Space.s4).padding(.bottom, DS.Space.s28)
                }
                .scrollIndicators(.hidden)
                .accessibilityIdentifier("settingsScroll")
                .onAppear { if store.settingsFixture == .mainEnd { proxy.scrollTo("settingsEnd", anchor: .bottom) } }
            }
        }
        .background(DS.Color.bg.ignoresSafeArea())
        .dsEdgeSwipeBack()
        .modifier(SettingsStorageSizeTask(storageSize: $storageSize))
        .task(id: [store.preferences.cloudAIEnabled, IntelligenceRuntime.cloud.hasKeychainKey]) { cloudAI = await SettingsDisplay.cloudAIAvailable(store) }
        .onAppear { unlockName = SettingsDisplay.unlockName() }
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
    }

    private func link(_ icon: DS.Icon, _ name: String, _ value: String, brand: Bool = false, first: Bool = false,
                      id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            DSSettingsRow(icon: icon, name: name, tint: brand ? DS.Color.accentInk : DS.Color.ink2, accessory: .link(value), separator: !first)
        }.dsPressStyle().accessibilityIdentifier(id)
    }

    private func setLock(_ enabled: Bool) {
        guard enabled else { store.update("关闭账本锁") { $0.preferences.lockEnabled = false }; return }
        let context = LAContext(); var failure: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &failure) else { store.error = "这台设备没有设置密码。"; return }
        Task {
            do {
                if try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "确认你可以解锁余白账本") {
                    store.update("开启账本锁") { $0.preferences.lockEnabled = true }
                }
            } catch { store.error = "没有验证，账本锁没开。" }
        }
    }
}

/// Formatting for settings values. Calculations live in YubaiCore.
@MainActor enum SettingsDisplay {
    static var iCloudAvailable: Bool {
        #if YUBAI_ICLOUD
        true
        #else
        false
        #endif
    }

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    static func money(_ cents: Int64, hidden: Bool) -> String { OverviewDisplay.money(cents, hidden: hidden) }

    static func cycleDay(_ day: Int) -> String { day == CycleStart.lastDay ? "每月最后一天" : "每月 \(day) 日" }

    static func monthDay(_ date: Date) -> String {
        let parts = Dates.calendar.dateComponents([.month, .day], from: date)
        return "\(parts.month ?? 0)." + String(format: "%02d", parts.day ?? 0)
    }

    static func range(_ start: Date, _ end: Date) -> String { monthDay(start) + " – " + monthDay(end) }

    static func appearance(_ value: String) -> String {
        switch value {
        case "light": "浅色"
        case "dark": "深色"
        default: "跟随系统"
        }
    }

    static func currencies(_ preferences: Preferences) -> String {
        let foreign = preferences.lastBillCurrency ?? (preferences.billExchangeRates ?? []).first?.currency
        return ([BillCurrency.cny] + [foreign].compactMap { $0 }.filter { $0 != .cny }).map(\.rawValue).joined(separator: " · ")
    }

    static func noticeCount(_ preferences: Preferences) -> Int {
        let notices = preferences.butlerNotices ?? ButlerNoticePreferences()
        return [notices.immediate, notices.ordinary, notices.home, preferences.weeklyLetterPush].filter { $0 }.count
    }

    static func reviewTime(_ time: WeeklyReviewTime) -> String {
        "周" + ["一", "二", "三", "四", "五", "六", "日"][max(0, min(6, time.weekday - 1))] + " " + String(format: "%02d:%02d", time.hour, time.minute)
    }

    static func symbol(_ currency: BillCurrency) -> String {
        switch currency {
        case .cny: "¥"
        case .jpy: "円"
        case .usd: "$"
        default: currency.symbol
        }
    }

    static func categoryIcon(_ name: String) -> DS.Icon {
        switch name {
        case "吃饭", "餐饮": .catFood
        case "咖啡": .catCoffee
        case "交通": .catTransport
        case "买菜", "买菜做饭": .catGrocery
        case "购物": .catShopping
        case "居住": .catHousing
        case "娱乐": .catFun
        case "日用": .catDaily
        case "数码", "数码与电子产品": .catDigital
        default: .catOther
        }
    }

    static func storage(_ bytes: Int64) -> String {
        let megabytes = Double(max(0, bytes)) / 1_000_000
        return megabytes >= 1000 ? StorageSize.text(bytes) : String(format: "%.0f MB", megabytes)
    }

    static func unlockName() -> String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return "面容 ID 解锁"
        case .touchID: return "触控 ID 解锁"
        default: return "密码解锁"
        }
    }

    /// The cloud model state, read through the router; no request is sent.
    static func cloudAIAvailable(_ store: AppStore) async -> Bool {
        let preferences = store.preferences
        if let fixture = store.settingsFixture {
            let router = ModelRouter.configured(preferences: preferences, feature: .answers,
                                                keyStore: APIKeyStore(storage: FixtureKeyStorage(key: fixture.apiKey)), environment: [:])
            return await router.availability() == .available
        }
        return await Task.detached(priority: .utility) {
            await ModelRouter.configured(preferences: preferences, feature: .answers).availability() == .available
        }.value
    }
}

/// An in-memory key for fixtures; never touches the Keychain.
struct FixtureKeyStorage: APIKeyStorage {
    let key: String?
    func read() throws -> String? { key }
    func write(_ key: String) throws {}
    func delete() throws {}
}
struct NoticeSettingsView: View {
    var body: some View {
        Page {
            ButlerNoticeSettings()
            Card(style: .list) { WeeklyLetterReminder().accessibilityIdentifier("openSettingsWeekly") }
        }.navigationTitle("通知").yubaiNavigation().accessibilityIdentifier("noticeSettingsPage")
    }
}

private struct SettingsStorageSizeTask: ViewModifier {
    @Environment(AppStore.self) private var store
    @Binding var storageSize: String?
    func body(content: Content) -> some View {
        content.task(id: store.current.updatedAt) {
            let repository = store.localRepository
            if let fixture = store.settingsFixture { storageSize = SettingsDisplay.storage(fixture.storageBytes); return }
            do { storageSize = SettingsDisplay.storage(try await Task.detached(priority: .utility) { try repository.storageUsage() }.value.totalBytes) }
            catch { storageSize = nil }
        }
    }
}

struct IntelligencePrivacyView: View {
    @Environment(AppStore.self) private var store
    private var hasKey: Bool { IntelligenceRuntime.cloud.hasKeychainKey }
    private var configured: Bool { IntelligenceRuntime.isConfigured }
    @State private var sendCount = SendLog.shared.groups.flatMap(\.items).filter { Dates.calendar.isDate($0.time, inSameDayAs: Dates.now) }.count
    var body: some View {
        Page(spacing: YubaiSpace.gapSection, topPadding: YubaiSpace.gapGroup, identifier: "intelligencePrivacyPage") {
            if let model = IntelligenceRuntime.cloud.unavailableModel { ModelUnavailableNote(model: model) }
            Card(style: .list) {
                VStack(spacing: YubaiSpace.none) {
                    Toggle("用云端 AI", isOn: Binding(get: { store.preferences.cloudAIEnabled }, set: { value in
                        store.update("保存云端 AI 偏好") { $0.preferences.cloudAIEnabled = value }
                    })).yubaiFont(YubaiFont.rowTitle).tint(YubaiColor.toggleOn).frame(minHeight: YubaiSize.rowDouble).accessibilityIdentifier("cloudAIToggle")
                    separator
                    NavigationLink {
                        Page { Card(style: .list) { CloudModelMenu() } }.navigationTitle("服务").yubaiNavigation()
                    } label: { settingsRow("服务", detail: configured ? "DeepSeek · 已配好" : "DeepSeek · 未配好", chevron: true) }
                        .accessibilityIdentifier("openCloudService")
                    separator
                    NavigationLink { CloudAISettingsSection() } label: {
                        settingsRow("密钥", detail: hasKey ? "只存在这台手机" : (configured ? "使用环境变量" : "未配好"), chevron: true)
                    }.hidesListDisclosure().accessibilityLabel(hasKey ? "密钥，保存在本机钥匙串，不进入账本或备份" : (configured ? "密钥，使用环境变量" : "密钥，未配好"))
                        .accessibilityIdentifier("openCloudKey")
                }.buttonStyle(PressButtonStyle())
            }
            VStack(alignment: .leading, spacing: YubaiSpace.gapHeading) {
                heading("它用来做这些")
                Card(style: .list) {
                    VStack(spacing: YubaiSpace.none) {
                        featureToggle("给导入的账单归类", feature: .importClassification)
                        separator
                        featureToggle("回答你问的问题", feature: .answers)
                        separator
                        featureToggle("写每周来信", feature: .weeklyReview)
                        separator
                        featureToggle("拍小票、认截图", feature: .receiptRecognition)
                        separator
                        featureToggle("管家的建议", feature: .butlerSuggestions).disabled(!configured)
                        separator
                        SettingsRow(title: "上次想", detail: store.current.butlerAI?.lastRunAt.map { FixedFlowPresentation.monthDay($0) } ?? "还没想过", chevron: false)
                            .uiTestAccessibilityValue(butlerScriptState)
                            .accessibilityIdentifier("butlerLastRun")
                    }
                }
            }
            VStack(alignment: .leading, spacing: YubaiSpace.gapHeading) {
                heading("发出去的只有")
                Card(style: .compact, background: YubaiColor.raised) {
                    Text("商户名、金额、日期、分类。不发账户号、不发余额、不发你的名字。").yubaiFont(YubaiFont.callout)
                }
            }
            Card(style: .list) {
                NavigationLink { CloudSendLogView() } label: { settingsRow("看最近发出去了什么", detail: "今天 \(sendCount) 次", chevron: true) }.hidesListDisclosure()
                    .buttonStyle(PressButtonStyle()).accessibilityIdentifier("openCloudSendLog")
            }
        }.navigationTitle("智能与隐私").yubaiNavigation().onAppear {
            IntelligenceRuntime.cloud.refresh()
            sendCount = SendLog.shared.groups.flatMap(\.items).filter { Dates.calendar.isDate($0.time, inSameDayAs: Dates.now) }.count
        }
        .onReceive(NotificationCenter.default.publisher(for: SendLog.didRecord).receive(on: RunLoop.main)) { _ in sendCount = SendLog.shared.groups.flatMap(\.items).filter { Dates.calendar.isDate($0.time, inSameDayAs: Dates.now) }.count }
    }
    private func featureToggle(_ title: String, feature: AIFeature) -> some View {
        Toggle(title, isOn: Binding(get: { store.preferences.isAIEnabled(for: feature) }, set: { enabled in
            if store.update("保存智能偏好", entryMotion: false, showToast: false, { $0.preferences.setAIEnabled(enabled, for: feature) }), !enabled, feature == .importClassification {
                store.stopOrganizingImports()
            }
        })).yubaiFont(YubaiFont.row).tint(YubaiColor.toggleOn)
            .frame(minHeight: YubaiSize.rowDouble).disabled(!store.preferences.cloudAIEnabled)
            .accessibilityIdentifier("aiFeature_" + feature.rawValue)
    }
    private var butlerScriptState: String {
        #if DEBUG && targetEnvironment(simulator)
        "requests=\(UITestRequestLog.shared.count);suggestions=\(store.current.butlerAI?.suggestions.count ?? 0);reviews=\(store.current.butlerAI?.reviews.count ?? 0);memories=\(store.current.memories.count)"
        #else
        ""
        #endif
    }
    private func heading(_ text: String) -> some View { Text(text).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary).padding(.horizontal, YubaiSpace.insetCard) }
    private var separator: some View { Rectangle().fill(YubaiColor.separator).frame(height: YubaiSize.separator).accessibilityHidden(true) }
    private func settingsRow(_ title: String, detail: String, chevron: Bool = false) -> some View {
        SettingsRow(title: title, detail: detail, chevron: chevron)
    }

}

extension UTType { static let yubaiBackup = UTType(exportedAs: "app.yubai.backup", conformingTo: .data) }
struct ExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.data, .json, .yubaiBackup, .commaSeparatedText] }
    var data: Data
    init(data: Data = Data()) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct BackupView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var password = ""; @State private var restorePassword = ""; @State private var exportDocument = ExportDocument()
    @State private var exporting = false; @State private var importing = false; @State private var exportName = ""
    @State private var pendingRestore: Ledger?; @State private var restoreData: Data?; @State private var busy = false; @State private var message: String?
    @State private var exportedLedgerID: UUID?; @State private var exportedAt: Date?
    @State private var encryptedRestore = false
    @State private var exportExpanded = false
    #if DEBUG && targetEnvironment(simulator)
    @State private var backupFileCount = 0
    #endif
    @State private var csvExport = false
    @State private var choosingBackupFolder = false
    @State private var backupFolderLedgerID: UUID?
    @State private var galleryRestoreStarted = false
    private struct BackupHeader: Decodable { let format: String; let version: Int; let encrypted: Bool }
    @FocusState private var passwordFocus: Bool
    var body: some View {
        Page(spacing: YubaiSpace.gapSection) {
            lastBackup
            if busy { ProgressView("正在本机处理…") }
            if let message { Text(message).yubaiFont(YubaiFont.callout).textSelection(.enabled) }
            Card(style: .list) {
                VStack(spacing: YubaiSpace.none) {
                    if store.preferences.lastBackupAt != nil {
                        Button { exportExpanded.toggle() } label: { backupRow("备份到文件", detail: "存到「文件」或隔空投送") }.accessibilityIdentifier("backupToFile")
                        EntryFormDivider()
                    }
                    Button { passwordFocus = false; importing = true } label: { backupRow("从备份恢复", detail: nil) }.disabled(busy).accessibilityIdentifier("restoreFromBackup")
                    EntryFormDivider()
                    Button(action: exportCSV) { backupRow("导出成表格", detail: "CSV") }.disabled(busy).accessibilityIdentifier("exportEntriesCSV")
                }
            }
            if exportExpanded { exportSection }
            if encryptedRestore { restoreSection }
            Card(style: .list) { weeklyBackupToggle }
            if let pendingRestore { restorePreview(pendingRestore) }
            Card(style: .list) {
                VStack(spacing: YubaiSpace.none) {
                    NavigationLink { RecentlyDeletedView() } label: { SettingsRow(title: "最近删除", detail: "\(RecentlyDeleted.entries(in: store.current).count) 笔") }.accessibilityIdentifier("recentlyDeleted")
                    EntryFormDivider()
                    NavigationLink { RecoveryVersionsView() } label: { SettingsRow(title: "恢复版本") }.accessibilityIdentifier("openRecoveryVersions")
                    EntryFormDivider()
                    NavigationLink { Form { LedgerSyncSection() }.editorForm().navigationTitle("账本位置").yubaiNavigation() } label: { SettingsRow(title: "账本位置") }.accessibilityIdentifier("openLedgerLocation")
                }
            }
            EraseAllDataButton()
        }.buttonStyle(PressButtonStyle()).navigationTitle("备份与恢复").yubaiNavigation()
            .manualSheetHeader("备份与恢复", cancelTitle: "关闭", showsAction: false).accessibilityIdentifier("backupPage")
            .fileExporter(isPresented: $exporting, document: exportDocument, contentType: csvExport ? .commaSeparatedText : .yubaiBackup, defaultFilename: exportName) { result in
                switch result {
                case .success:
                    message = "已保存"
                    if !csvExport, let exportedLedgerID, let exportedAt {
                        store.recordSuccessfulBackup(of: exportedLedgerID, at: exportedAt)
                    }
                case .failure(let error): message = error.localizedDescription
                }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.yubaiBackup, .json, .data]) { result in do { let url = try result.get(); Task { await acceptBackup(url) } } catch { message = error.localizedDescription } }
            .task { await store.configureSync() }
            .onAppear { if let url = store.importedURL, url.pathExtension.lowercased() == "yubaibackup" { store.importedURL = nil; Task { await acceptBackup(url) } } }
            #if DEBUG && targetEnvironment(simulator)
            .task { await prepareGalleryRestore() }
            .task(id: store.preferences.lastBackupAt) {
                let count = await Task.detached(priority: .utility) { UITestSupport.secondBatchBackupFileCount }.value
                if !Task.isCancelled { backupFileCount = count }
            }
            #endif
    }
    #if DEBUG && targetEnvironment(simulator)
    private func prepareGalleryRestore() async {
        guard !galleryRestoreStarted, UITestSupport.script == "gallery", ProcessInfo.processInfo.environment["YUBAI_GALLERY_RESTORE"] == "1" else { return }
        galleryRestoreStarted = true
        let ledger = store.current
        do {
            let url = store.localRepository.directory.appendingPathComponent("gallery-restore.yubaibackup")
            try await Task.detached {
                try Backup.export(ledger, password: "GalleryOnly123").write(to: url, options: .atomic)
            }.value
            guard !Task.isCancelled else { return }
            await acceptBackup(url)
            _ = await Task.detached { try? FileManager.default.removeItem(at: url) }.value
        } catch { message = error.localizedDescription }
    }
    #endif
    func acceptBackup(_ url: URL) async {
        pendingRestore = nil; restoreData = nil; restorePassword = ""; encryptedRestore = false; message = nil; busy = true
        do {
            let result = try await Task.detached(priority: .userInitiated) {
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= LedgerCodec.backupCapacity else { throw YubaiError.invalid("备份文件过大。") }
                let data = try Data(contentsOf: url)
                let header = try? JSONDecoder().decode(BackupHeader.self, from: data)
                return (data, header?.format == "yubai-backup" && header?.version == 1 && header?.encrypted == true)
            }.value
            restoreData = result.0; busy = false
            if result.1 { encryptedRestore = true; passwordFocus = true }
            else { readBackup() }
        } catch { message = error.localizedDescription; busy = false }
    }
    func exportBackup() {
        passwordFocus = false
        let ledger = store.current; let password = password; busy = true; message = nil
        csvExport = false; exportedLedgerID = ledger.id; exportedAt = Dates.now
        Task { do { let data = try await Task.detached { try Backup.export(ledger, password: password) }.value; exportDocument = ExportDocument(data: data); exportName = "余白备份-" + Dates.text(Dates.now) + ".yubaibackup"; exporting = true; busy = false } catch { message = error.localizedDescription; busy = false } }
    }
    private func exportCSV() {
        passwordFocus = false
        let ledger = store.current
        busy = true; message = nil; csvExport = true; exportedLedgerID = nil; exportedAt = nil
        Task { @MainActor in
            let data = await Task.detached(priority: .userInitiated) { LedgerBackup.entriesCSV(ledger) }.value
            exportDocument = ExportDocument(data: data)
            exportName = "余白账目-" + Dates.text(Dates.now) + ".csv"
            busy = false; exporting = true
        }
    }
    private var weeklyBackupToggle: some View {
        Toggle("每周自动备份一次", isOn: Binding(get: { store.preferences.weeklyAutoBackup == true }, set: { enabled in
            if !enabled {
                store.update("保存备份偏好", entryMotion: false, showToast: false) { $0.preferences.weeklyAutoBackup = nil }
            } else if WeeklyBackupAccess.shared.hasFolder(for: store.current.id) {
                if store.update("保存备份偏好", entryMotion: false, showToast: false, { $0.preferences.weeklyAutoBackup = true }) { store.runAutomaticBackupIfDue() }
            } else {
                backupFolderLedgerID = store.current.id; choosingBackupFolder = true
            }
        })).yubaiFont(YubaiFont.row).tint(YubaiColor.toggleOn).frame(minHeight: YubaiSize.rowDouble)
            .accessibilityIdentifier("weeklyAutoBackup")
            .onAppear {
                if store.preferences.weeklyAutoBackup == true && !WeeklyBackupAccess.shared.hasFolder(for: store.current.id) {
                    backupFolderLedgerID = store.current.id; choosingBackupFolder = true
                }
            }
            .fileImporter(isPresented: $choosingBackupFolder, allowedContentTypes: [.folder]) { result in
                Task {
                    do {
                        let folder = try result.get(), ledgerID = store.current.id
                        guard backupFolderLedgerID == ledgerID else { return }
                        try await WeeklyBackupAccess.shared.remember(folder, for: ledgerID)
                        guard store.current.id == ledgerID else { return }
                        if store.update("保存备份偏好", entryMotion: false, showToast: false, { $0.preferences.weeklyAutoBackup = true }) { store.runAutomaticBackupIfDue() }
                    } catch {
                        if (error as NSError).code != NSUserCancelledError { message = error.localizedDescription }
                    }
                }
            }
    }
    func readBackup() {
        passwordFocus = false
        guard let restoreData else { return }; let password = restorePassword; busy = true; pendingRestore = nil; message = nil
        Task { do { let restored = try await Task.detached { try Backup.restore(restoreData, password: password) }.value; pendingRestore = restored; busy = false } catch { message = error.localizedDescription; busy = false } }
    }

    private var exportSection: some View {
        VStack(spacing: YubaiSpace.gapGroup) {
            Card(style: .list) {
                CardTextFieldRow(title: "备份密码", text: $password, identifier: "backupPassword", hidesValue: true,
                                 focus: $passwordFocus, autofocus: true, error: !password.isEmpty && password.count < 8 ? "密码至少 8 位" : nil)
            }
            Button("导出完整备份", action: exportBackup).buttonStyle(PrimaryButtonStyle()).disabled(busy || password.count < 8)
                .accessibilityIdentifier("exportEncryptedBackup")
        }
    }
    private var restoreSection: some View {
        VStack(spacing: YubaiSpace.gapGroup) {
            Card(style: .list) {
                CardTextFieldRow(title: "备份密码", text: $restorePassword, identifier: "restorePassword", hidesValue: true, focus: $passwordFocus, autofocus: true)
                    .accessibilityHint("填写创建这份加密备份时使用的密码")
            }
            Button("读取备份", action: readBackup).buttonStyle(PrimaryButtonStyle()).disabled(busy || restorePassword.isEmpty).accessibilityIdentifier("readBackupFile")
        }
    }
    private func restorePreview(_ ledger: Ledger) -> some View {
        Card {
            VStack(alignment: .leading, spacing: YubaiSpace.gapGroup) {
                Text("已验证的备份").yubaiFont(YubaiFont.navTitle)
                Text("\(ledger.accounts.count) 个账户 · \(ledger.activeEntries.count) 笔有效记录 · \(ledger.attachments.count) 份附件")
                Text("最后修改：\(Dates.text(ledger.updatedAt, time: true))").yubaiFont(YubaiFont.caption)
                Button("确认恢复这份账本") {
                    if store.restore(ledger) { pendingRestore = nil; restoreData = nil; encryptedRestore = false; restorePassword = ""; message = "已恢复" }
                }.buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("confirmBackupRestore")
                Button("取消恢复") { pendingRestore = nil; restoreData = nil; encryptedRestore = false; restorePassword = "" }.buttonStyle(SecondaryButtonStyle())
            }
        }.accessibilityIdentifier("validatedBackupPreview")
    }
    private var lastBackup: some View {
        VStack(alignment: .leading, spacing: YubaiSpace.space4) {
            if let date = store.preferences.lastBackupAt {
                Text("上次备份").yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary)
                let days = max(0, Dates.calendar.dateComponents([.day], from: Dates.day(date), to: Dates.day(Dates.now)).day ?? 0)
                let layout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: YubaiSpace.space4)) : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: YubaiSpace.space8))
                layout {
                    Text(FixedFlowPresentation.monthDay(date)).yubaiFont(YubaiFont.amountLarge)
                    Text(days == 0 ? "今天" : "\(days) 天前").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                }
            } else { EmptyState("square.and.arrow.up", "还没备份过", action: "备份到文件", actionIdentifier: "backupToFile", onAction: { exportExpanded.toggle() }) }
        }.frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .contain).accessibilityIdentifier("lastBackup")
            #if DEBUG && targetEnvironment(simulator)
            .uiTestAccessibilityValue("files=\(backupFileCount);csv=\(csvExport && exportDocument.data.starts(with: [0xEF, 0xBB, 0xBF]) ? 1 : 0)")
            #endif
    }
    private func backupRow(_ title: String, detail: String?) -> some View {
        let layout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: YubaiSpace.space4)) : AnyLayout(HStackLayout(spacing: YubaiSpace.gapGroup))
        return layout {
            Text(title).yubaiFont(YubaiFont.row).foregroundStyle(YubaiColor.label)
            if !textSize.isAccessibilitySize { Spacer(minLength: YubaiSpace.space8) }
            if let detail { Text(detail).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary) }
            Image(systemName: "chevron.right").yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary)
        }.frame(minHeight: YubaiSize.rowDouble).contentShape(Rectangle())
    }
}

struct ImportHistoryView: View {
    @Environment(AppStore.self) private var store
    @State private var undoBatch: ImportBatch?
    @State private var document = ExportDocument()
    @State private var exporting = false
    @State private var filename = ""
    var body: some View {
        Page {
            DSSettingsCard {
                Button { store.sheet = .imports } label: {
                    HStack(spacing: DS.Space.s12) {
                        DSIconView(icon: .inbox, size: DS.Size.icon, color: DS.Color.accentInk)
                        Text("导入账单").dsText(DS.Font.tLabel).foregroundStyle(DS.Color.accentInk).dsFillWidth()
                    }.frame(minHeight: SettingsSpec.row).contentShape(Rectangle())
                }.dsPressStyle().accessibilityIdentifier("importBills")
            }
            CardRows(Array(store.imports.reversed())) { batch in
                VStack(alignment: .leading, spacing: YubaiSpace.space8) {
                    NavigationLink {
                        ImportResultPage(batchID: batch.id, hasNext: false, next: {}, restart: { store.sheet = .imports })
                            .navigationTitle("导入结果").yubaiNavigation()
                    } label: { Text(batch.filename).yubaiFont(YubaiFont.rowTitle).lineLimit(1).truncationMode(.tail).frame(maxWidth: .infinity, minHeight: YubaiSize.tapMin, alignment: .leading) }
                        .disabled(batch.undoneAt != nil).accessibilityIdentifier("openImportBatch_" + batch.id.uuidString)
                    Text("\(Dates.text(batch.importedAt, time: true)) · \(batch.importedCount) 笔" + (batch.undoneAt == nil ? "" : " · 已撤销"))
                        .yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary)
                    if batch.undoneAt == nil {
                        Button("整批撤销") { undoBatch = batch }
                            .disabled(store.organizingBatchID != nil).frame(minHeight: YubaiSize.tapMin).accessibilityIdentifier("undoImportBatch")
                    }
                    if let attachment = store.current.attachments.first(where: { $0.id == batch.attachmentID }) {
                        Button("导出原文件") {
                            let repository = store.localRepository, id = attachment.id
                            Task {
                                do {
                                    let data = try await Task.detached(priority: .userInitiated) { try repository.attachmentData(id) }.value
                                    document = ExportDocument(data: data); filename = attachment.name; exporting = true
                                } catch { store.error = error.localizedDescription }
                            }
                        }
                            .frame(minHeight: YubaiSize.tapMin).accessibilityIdentifier("exportImportOriginal_" + batch.id.uuidString)
                    }
                }.buttonStyle(.borderless).padding(.vertical, YubaiSpace.space8)
            }
        }.navigationTitle("导入记录").yubaiNavigation().accessibilityIdentifier("importHistoryPage")
            .sheet(item: $undoBatch) { batch in
                ConfirmationSheet(title: "撤销这批 \(batch.importedCount) 笔？", consequence: "整理产生的关联和安排也会还原。") {
                    Button("撤销这一批") { store.undoImport(batch.id); undoBatch = nil }.buttonStyle(DestructiveButtonStyle())
                }.environment(store)
            }
            .fileExporter(isPresented: $exporting, document: document, contentType: .data, defaultFilename: filename) { result in
                if case .failure(let error) = result { store.error = error.localizedDescription }
            }
    }
}

struct RecoveryVersionsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var recoveries: [Recovery] = []
    @State private var target: Recovery?
    var body: some View {
        Page {
            // Matches LedgerRepository.historyCountLimit (internal to YubaiCore).
            Text("最近 8 份账本")
                .yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary)
            CardRows(recoveries) { recovery in
                Button { target = recovery } label: {
                    VStack(alignment: .leading, spacing: YubaiSpace.space4) {
                        Text(Dates.text(recovery.date, time: true)).yubaiFont(YubaiFont.rowTitle)
                        Text(recovery.name.replacingOccurrences(of: "\u{6309}\u{5bf9}\u{65b9}\u{5206}", with: "按商户整理"))
                            .yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, YubaiSpace.space8).contentShape(Rectangle())
                }.buttonStyle(PressButtonStyle()).accessibilityIdentifier("recoveryVersion_" + recovery.name)
            }
        }.navigationTitle("恢复版本").yubaiNavigation().manualSheetHeader("恢复版本", cancelTitle: "关闭", showsAction: false)
            .task {
                let repository = store.repository
                do {
                    let result = try await Task.detached(priority: .utility) { try repository.recoveries() }.value
                    guard !Task.isCancelled else { return }
                    recoveries = result
                } catch { if !Task.isCancelled { store.error = error.localizedDescription } }
            }
            .sheet(item: $target) { recovery in
                ConfirmationSheet(title: "恢复到这个版本？", consequence: "当前账本会先保留。") {
                    Button("恢复所选版本") { if store.recover(recovery) { target = nil; dismiss() } }.buttonStyle(PrimaryButtonStyle())
                }.environment(store)
            }
    }
}

struct RecentlyDeletedView: View {
    @Environment(AppStore.self) private var store
    @State private var confirmingClear = false
    var body: some View {
        let rows = RecentlyDeleted.entries(in: store.current)
        Page(spacing: YubaiSpace.gapSection) {
            if rows.isEmpty { EmptyState("trash", "最近删除里没有账目", action: "记一笔", onAction: { store.requestCaptureSheet(.addEntry) }) }
            group("今天", rows: rows.filter { Dates.calendar.isDate($0.deletedAt!, inSameDayAs: Dates.now) })
            group("更早", rows: rows.filter { !Dates.calendar.isDate($0.deletedAt!, inSameDayAs: Dates.now) })
            if !rows.isEmpty {
                Button("全部清掉") { confirmingClear = true }.buttonStyle(DestructiveButtonStyle()).accessibilityIdentifier("clearRecentlyDeleted")
            }
        }.navigationTitle("最近删除").yubaiNavigation().accessibilityIdentifier("recentlyDeletedList")
            .sheet(isPresented: $confirmingClear) {
                ConfirmationSheet(title: "全部清掉", consequence: "全部清掉后无法放回。") {
                    Button("全部清掉") {
                        if store.update("清掉最近删除", recordUndo: false, entryMotion: false, { RecentlyDeleted.clear(in: &$0) }) { store.clearUndo(); confirmingClear = false }
                    }.buttonStyle(DestructiveButtonStyle())
                }.environment(store)
            }
    }
    @ViewBuilder private func group(_ title: String, rows: [Entry]) -> some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: YubaiSpace.space8) {
                Text(title).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary).padding(.leading, YubaiSpace.space16)
                CardRows(rows) { entry in
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: YubaiSpace.space12) { summary(entry); Spacer(); restore(entry) }
                        VStack(alignment: .leading, spacing: YubaiSpace.space8) { summary(entry); restore(entry) }
                    }.padding(.vertical, YubaiSpace.space8)
                }
            }
        }
    }
    private func summary(_ entry: Entry) -> some View {
        VStack(alignment: .leading, spacing: YubaiSpace.space4) {
            Text(Classification.displayCategory(entry.category) + " · " + entry.displayTitle).yubaiFont(YubaiFont.row, weight: .medium).foregroundStyle(YubaiColor.labelMuted)
            Text("删于 " + deletedTime(entry.deletedAt!) + " · 原记 " + ManualBookkeeping.dayLabel(entry.date)).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
            if !Dates.calendar.isDate(entry.deletedAt!, inSameDayAs: Dates.now) { Text("\(RecentlyDeleted.daysRemaining(entry)) 天后清掉").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary) }
            Text(store.preferences.hideAmounts ? "••••" : AmountLabel.text(entry.amount, sign: entry.nature.inflow ? .inflow : .outflow))
                .yubaiFont(YubaiFont.amountSmall).foregroundStyle(YubaiColor.labelSecondary).strikethrough()
        }
    }
    private func restore(_ entry: Entry) -> some View {
        Button {
            _ = store.update("放回去", entryMotion: false) { try RecentlyDeleted.restore(entry.id, in: &$0) }
        } label: {
            Text("放回去").yubaiFont(YubaiFont.callout).padding(.horizontal, YubaiSpace.space12).frame(minHeight: YubaiSize.chipHeight)
                .background(YubaiColor.raised, in: Capsule()).fixedSize().yubaiHitTarget()
        }.buttonStyle(PressButtonStyle()).accessibilityIdentifier("restoreDeleted_" + entry.id.uuidString)
    }
    private func deletedTime(_ date: Date) -> String {
        Dates.calendar.isDate(date, inSameDayAs: Dates.now) ? date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)) : ManualBookkeeping.dayLabel(date)
    }
}
