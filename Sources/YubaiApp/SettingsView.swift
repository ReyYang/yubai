import SwiftUI
import UniformTypeIdentifiers
import LocalAuthentication
import YubaiCore

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @State private var storageSize: String?
    var body: some View {
        Page(spacing: YubaiSpace.gapSection, topPadding: YubaiSpace.space8) {
            group("账本") {
                TabNavigationLink(.accounts) { AccountsView() } label: { SettingsRow(title: "账户", detail: "\(store.accounts.filter { !$0.archived }.count) 个") }.accessibilityIdentifier("openAccounts")
                EntryFormDivider()
                TabNavigationLink(.fixedFlows) { FixedFlowsView() } label: { SettingsRow(title: "固定账单", detail: "\(store.plans.filter { $0.active }.count) 项") }.accessibilityIdentifier("openFixedFlows")
                EntryFormDivider()
                TabNavigationLink(.budget) { BudgetView() } label: { SettingsRow(title: "预算", detail: "\(store.current.spendingParts.count) 项") }.accessibilityIdentifier("openSpendingParts")
                EntryFormDivider()
                TabNavigationLink(.categories) { CategoriesView() } label: { SettingsRow(title: "分类") }.accessibilityIdentifier("openCategories")
                EntryFormDivider()
                TabNavigationLink(.weekly(nil)) { WeeklyReviewView() } label: { SettingsRow(title: "周回顾", detail: "每周一") }.accessibilityIdentifier("openSettingsWeekly")
            }
            group("记账") {
                TabNavigationLink(.quickCapture) { QuickCaptureSettingsView() } label: { SettingsRow(title: "快速记账", detail: "Apple Pay 后自动记") }.accessibilityIdentifier("openQuickCapture")
                EntryFormDivider()
                TabNavigationLink(.importHistory) { ImportHistoryView() } label: { SettingsRow(title: "导入记录", detail: lastImport) }.accessibilityIdentifier("openImportHistory")
            }
            group("余白") {
                TabNavigationLink(.intelligencePrivacy) { IntelligencePrivacyView() } label: {
                    SettingsRow(title: "智能与隐私", detail: IntelligenceRuntime.isConfigured ? "DeepSeek · 已配好" : "未配好")
                }.accessibilityIdentifier("openIntelligencePrivacy")
                EntryFormDivider()
                NavigationLink { NoticeSettingsView() } label: { SettingsRow(title: "通知") }.accessibilityIdentifier("openNoticeSettings")
            }
            group("数据") {
                TabNavigationLink(.backup) { BackupView() } label: { SettingsRow(title: "备份与恢复", detail: backupDetail) }.accessibilityIdentifier("openBackup")
                EntryFormDivider()
                TabNavigationLink(.storage) { StorageView() } label: { SettingsRow(title: "存储空间", detail: storageSize) }.accessibilityIdentifier("openStorage")
                EntryFormDivider()
                NavigationLink { DeviceSettingsView() } label: { SettingsRow(title: "设备与界面") }.accessibilityIdentifier("openDeviceSettings")
            }
        }.buttonStyle(PressButtonStyle()).amountPrivacy(store.preferences.hideAmounts).accessibilityIdentifier("settingsScroll")
            .modifier(SettingsStorageSizeTask(storageSize: $storageSize)).navigationTitle("设置").yubaiNavigation()
    }
    private func group<Rows: View>(_ title: String, @ViewBuilder rows: () -> Rows) -> some View {
        VStack(alignment: .leading, spacing: YubaiSpace.gapHeading) {
            SectionHeading(title: title).padding(.horizontal, YubaiSpace.insetCard)
            Card(style: .list) { VStack(spacing: YubaiSpace.none, content: rows) }
        }
    }
    private var lastImport: String? {
        store.imports.filter { $0.undoneAt == nil }.map(\.importedAt).max().map { "上次 " + FixedFlowPresentation.monthDay($0) }
    }
    private var backupDetail: String { store.preferences.lastBackupAt.map(FixedFlowPresentation.monthDay) ?? "还没备份" }
}

struct NoticeSettingsView: View {
    var body: some View {
        Page {
            ButlerNoticeSettings()
            Card(style: .list) { WeeklyLetterReminder() }
        }.navigationTitle("通知").yubaiNavigation()
    }
}

private struct SettingsStorageSizeTask: ViewModifier {
    @Environment(AppStore.self) private var store
    @Binding var storageSize: String?
    func body(content: Content) -> some View {
        content.task(id: store.current.updatedAt) {
            let repository = store.localRepository
            do { storageSize = StorageSize.text(try await Task.detached(priority: .utility) { try repository.storageUsage() }.value.totalBytes) }
            catch { storageSize = nil }
        }
    }
}

struct IntelligencePrivacyView: View {
    @Environment(AppStore.self) private var store
    @State private var hasKey = APIKeyStore.shared.hasKeychainKey
    @State private var configured = IntelligenceRuntime.isConfigured
    @State private var sendCount = SendLog.shared.groups.flatMap(\.items).filter { Dates.calendar.isDateInToday($0.time) }.count
    var body: some View {
        Page(spacing: YubaiSpace.gapSection, topPadding: YubaiSpace.gapGroup) {
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
                        featureToggle("写周回顾", feature: .weeklyReview)
                        separator
                        featureToggle("拍小票、认截图", feature: .receiptRecognition)
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
        }.navigationTitle("智能与隐私").yubaiNavigation().accessibilityIdentifier("intelligencePrivacyPage").onAppear {
            IntelligenceRuntime.cloud.refresh(); hasKey = APIKeyStore.shared.hasKeychainKey
            configured = IntelligenceRuntime.isConfigured; sendCount = SendLog.shared.groups.flatMap(\.items).filter { Dates.calendar.isDateInToday($0.time) }.count
        }
        .onReceive(NotificationCenter.default.publisher(for: SendLog.didRecord).receive(on: RunLoop.main)) { _ in sendCount = SendLog.shared.groups.flatMap(\.items).filter { Dates.calendar.isDateInToday($0.time) }.count }
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
    private func heading(_ text: String) -> some View { Text(text).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary).padding(.horizontal, YubaiSpace.insetCard) }
    private var separator: some View { Rectangle().fill(YubaiColor.separator).frame(height: YubaiSize.separator).accessibilityHidden(true) }
    private func settingsRow(_ title: String, detail: String, chevron: Bool = false) -> some View {
        SettingsRow(title: title, detail: detail, chevron: chevron)
    }

}

struct DeviceSettingsView: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        Page {
            Card(style: .list) {
                VStack(spacing: YubaiSpace.none) {
                    Toggle("使用设备解锁保护账本", isOn: Binding(get: { store.preferences.lockEnabled }, set: enableLock)).tint(YubaiColor.toggleOn).frame(minHeight: YubaiSize.headerHeight)
                    separator
                    Picker("外观", selection: Binding(get: { store.preferences.appearance }, set: { value in
                        store.update("保存外观") { $0.preferences.appearance = value }
                    })) { Text("跟随系统").tag("system"); Text("浅色").tag("light"); Text("深色").tag("dark") }.frame(minHeight: YubaiSize.rowSingle)
                }
            }
        }.navigationTitle("设备与界面").yubaiNavigation().accessibilityIdentifier("deviceSettingsPage")
    }
    private var separator: some View { EntryFormDivider() }
    private func enableLock(_ enabled: Bool) {
        guard enabled else { store.update("关闭账本锁") { $0.preferences.lockEnabled = false }; return }
        let context = LAContext(); var failure: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &failure) else { store.error = "请先为设备设置密码，再开启账本锁。"; return }
        Task {
            do { if try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "确认你可以解锁余白账本") { store.update("开启账本锁") { $0.preferences.lockEnabled = true } } }
            catch { store.error = "验证未完成，账本锁尚未开启。" }
        }
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
                    Button { exportExpanded.toggle() } label: { backupRow("备份到文件", detail: "存到「文件」或隔空投送") }.accessibilityIdentifier("backupToFile")
                    EntryFormDivider()
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
            .fileImporter(isPresented: $importing, allowedContentTypes: [.yubaiBackup, .json, .data]) { result in do { acceptBackup(try result.get()) } catch { message = error.localizedDescription } }
            .task { await store.configureSync() }
            .onAppear { if let url = store.importedURL, url.pathExtension.lowercased() == "yubaibackup" { store.importedURL = nil; acceptBackup(url) } }
            #if DEBUG && targetEnvironment(simulator)
            .task { await prepareGalleryRestore() }
            #endif
    }
    #if DEBUG && targetEnvironment(simulator)
    private func prepareGalleryRestore() async {
        guard !galleryRestoreStarted, UITestSupport.script == "gallery", ProcessInfo.processInfo.environment["YUBAI_GALLERY_RESTORE"] == "1" else { return }
        galleryRestoreStarted = true
        let ledger = store.current
        do {
            let data = try await Task.detached { try Backup.export(ledger, password: "GalleryOnly123") }.value
            guard !Task.isCancelled else { return }
            let url = store.localRepository.directory.appendingPathComponent("gallery-restore.yubaibackup")
            try data.write(to: url, options: .atomic)
            defer { try? FileManager.default.removeItem(at: url) }
            acceptBackup(url)
        } catch { message = error.localizedDescription }
    }
    #endif
    func acceptBackup(_ url: URL) {
        pendingRestore = nil; restoreData = nil; restorePassword = ""; encryptedRestore = false; message = nil
        do {
            let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= LedgerCodec.backupCapacity else { throw YubaiError.invalid("备份文件过大。") }
            let data = try Data(contentsOf: url)
            restoreData = data
            if let header = try? JSONDecoder().decode(BackupHeader.self, from: data), header.format == "yubai-backup", header.version == 1, header.encrypted {
                encryptedRestore = true; passwordFocus = true
            } else { readBackup() }
        } catch { message = error.localizedDescription }
    }
    func exportBackup() {
        passwordFocus = false
        let ledger = store.current; let password = password; busy = true; message = nil
        csvExport = false; exportedLedgerID = ledger.id; exportedAt = Date()
        Task { do { let data = try await Task.detached { try Backup.export(ledger, password: password) }.value; exportDocument = ExportDocument(data: data); exportName = "余白备份-" + Dates.text(Date()) + ".yubaibackup"; exporting = true; busy = false } catch { message = error.localizedDescription; busy = false } }
    }
    private func exportCSV() {
        passwordFocus = false
        let ledger = store.current
        busy = true; message = nil; csvExport = true; exportedLedgerID = nil; exportedAt = nil
        Task { @MainActor in
            let data = await Task.detached(priority: .userInitiated) { LedgerBackup.entriesCSV(ledger) }.value
            exportDocument = ExportDocument(data: data)
            exportName = "余白账目-" + Dates.text(Date()) + ".csv"
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
                do {
                    let folder = try result.get()
                    guard backupFolderLedgerID == store.current.id else { return }
                    try WeeklyBackupAccess.shared.remember(folder, for: store.current.id)
                    if store.update("保存备份偏好", entryMotion: false, showToast: false, { $0.preferences.weeklyAutoBackup = true }) { store.runAutomaticBackupIfDue() }
                } catch {
                    if (error as NSError).code != NSUserCancelledError { message = error.localizedDescription }
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
            Text("上次备份").yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary)
            if let date = store.preferences.lastBackupAt {
                let days = max(0, Dates.calendar.dateComponents([.day], from: Dates.day(date), to: Dates.day(Date())).day ?? 0)
                let layout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: YubaiSpace.space4)) : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: YubaiSpace.space8))
                layout {
                    Text(FixedFlowPresentation.monthDay(date)).yubaiFont(YubaiFont.amountLarge)
                    Text(days == 0 ? "今天" : "\(days) 天前").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                }
            } else { Text("还没备份过").yubaiFont(YubaiFont.amountLarge) }
        }.frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .combine).accessibilityIdentifier("lastBackup")
            #if DEBUG && targetEnvironment(simulator)
            .uiTestAccessibilityValue("files=\(UITestSupport.secondBatchBackupFileCount);csv=\(csvExport && exportDocument.data.starts(with: [0xEF, 0xBB, 0xBF]) ? 1 : 0)")
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
            if store.imports.isEmpty { EmptyState("square.and.arrow.down", "还没有导入记录", action: "导入账单", onAction: { store.sheet = .imports }).accessibilityIdentifier("emptyImportHistory") }
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
                        Button("导出原文件") { do { document = ExportDocument(data: try store.localRepository.attachmentData(attachment.id)); filename = attachment.name; exporting = true } catch { store.error = error.localizedDescription } }
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
            .onAppear { do { recoveries = try store.repository.recoveries() } catch { store.error = error.localizedDescription } }
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
            if rows.isEmpty { EmptyState("trash", "最近删除里没有账目", action: "记一笔", onAction: { store.sheet = .addEntry }) }
            group("今天", rows: rows.filter { Dates.calendar.isDateInToday($0.deletedAt!) })
            group("更早", rows: rows.filter { !Dates.calendar.isDateInToday($0.deletedAt!) })
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
            if !Dates.calendar.isDateInToday(entry.deletedAt!) { Text("\(RecentlyDeleted.daysRemaining(entry)) 天后清掉").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary) }
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
        Dates.calendar.isDateInToday(date) ? date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)) : ManualBookkeeping.dayLabel(date)
    }
}
