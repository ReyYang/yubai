import SwiftUI
import UniformTypeIdentifiers
import LocalAuthentication
import YubaiCore

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @State private var storageSize: String?
    var body: some View {
        Page(spacing: YubaiSpace.gapGroup, topPadding: YubaiSpace.space8) {
            Card(style: .list) {
                VStack(spacing: YubaiSpace.none) {
                    TabNavigationLink(.categories) { CategoriesView() } label: { row("分类") }.accessibilityIdentifier("openCategories")
                    separator
                    TabNavigationLink(.quickCapture) { QuickCaptureSettingsView() } label: { row("常记的几笔", detail: repeatCount) }
                        .accessibilityIdentifier("openQuickCapture")
                    separator
                    TabNavigationLink(.importHistory) { ImportHistoryView() } label: { row("导入记录", detail: lastImport) }
                        .accessibilityIdentifier("openImportHistory")
                }
            }
            Card(style: .list) { intelligenceRow }
            Card(style: .list) {
                VStack(spacing: YubaiSpace.none) {
                    TabNavigationLink(.backup) { BackupView() } label: { row("备份与恢复", detail: backupDetail) }.accessibilityIdentifier("openBackup")
                    separator
                    TabNavigationLink(.storage) { StorageView() } label: { row("存储空间", detail: storageSize) }.accessibilityIdentifier("openStorage")
                }
            }
        }.buttonStyle(PressButtonStyle()).amountPrivacy(store.preferences.hideAmounts).accessibilityIdentifier("settingsScroll")
            .modifier(SettingsStorageSizeTask(storageSize: $storageSize))
            .navigationTitle("设置").yubaiNavigation()
    }
    private var repeatCount: String {
        "\(EntryHistory.repeats(in: store.current, now: Date()).count) 笔"
    }
    private var lastImport: String? {
        guard let date = store.imports.filter({ $0.undoneAt == nil }).map(\.importedAt).max() else { return nil }
        return "上次 " + FixedFlowPresentation.monthDay(date)
    }
    private var backupDetail: String {
        guard let date = store.preferences.lastBackupAt else { return "仅本机" }
        return FixedFlowPresentation.monthDay(date)
    }
    private var intelligenceRow: some View {
        TabNavigationLink(.intelligencePrivacy) { IntelligencePrivacyView() } label: {
            HStack(spacing: YubaiSpace.gapGroup) {
                Text("智能与隐私").yubaiFont(YubaiFont.row); Spacer(minLength: YubaiSpace.space8)
                if store.preferences.cloudAIEnabled && IntelligenceRuntime.isConfigured {
                    Pill(text: "DeepSeek · 已配好", variant: .brand, height: YubaiSize.tagHeight, showsDot: false)
                } else { Text("未配好").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary) }
                chevron
            }.frame(minHeight: YubaiSize.rowDouble).contentShape(Rectangle())
        }.accessibilityIdentifier("openIntelligencePrivacy")
    }
    private func row(_ title: String, detail: String? = nil) -> some View {
        HStack(spacing: YubaiSpace.gapGroup) {
            Text(title).yubaiFont(YubaiFont.row); Spacer(minLength: YubaiSpace.space8)
            if let detail { Text(detail).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary) }
            chevron
        }.frame(minHeight: YubaiSize.rowDouble).contentShape(Rectangle())
    }
    private var chevron: some View { Image(systemName: "chevron.right").yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary) }
    private var separator: some View { Rectangle().fill(YubaiColor.separator).frame(height: 1).accessibilityHidden(true) }
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
    @State private var sendCount = SendLog.shared.totalCount
    var body: some View {
        Page(spacing: YubaiSpace.gapSection, topPadding: YubaiSpace.gapGroup) {
            if let model = IntelligenceRuntime.cloud.unavailableModel { ModelUnavailableNote(model: model) }
            Card(style: .list) {
                VStack(spacing: YubaiSpace.none) {
                    Toggle("用云端 AI", isOn: Binding(get: { store.preferences.cloudAIEnabled }, set: { value in
                        store.update("保存云端 AI 偏好") { $0.preferences.cloudAIEnabled = value }
                    })).yubaiFont(YubaiFont.rowTitle).tint(YubaiColor.toggleOn).frame(minHeight: YubaiSize.rowDouble).accessibilityIdentifier("cloudAIToggle")
                    separator
                    HStack(spacing: YubaiSpace.space8) {
                        Text("服务").yubaiFont(YubaiFont.row); Spacer(minLength: YubaiSpace.space8)
                        if configured { Pill(text: "已配好", variant: .brand, height: YubaiSize.tagHeight, showsDot: false) }
                        Text("DeepSeek").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                    }.frame(minHeight: YubaiSize.rowDouble)
                    separator
                    CloudModelMenu()
                    separator
                    NavigationLink { CloudAISettingsSection() } label: {
                        settingsRow("密钥", detail: hasKey ? "只存在这台手机" : (configured ? "使用环境变量" : "未配好"), chevron: true)
                    }.hidesListDisclosure().accessibilityLabel(hasKey ? "密钥，保存在本机钥匙串，不进入账本或备份" : (configured ? "密钥，使用环境变量" : "密钥，未配好"))
                        .accessibilityIdentifier("openCloudKey")
                }.buttonStyle(PressButtonStyle())
            }
            VStack(alignment: .leading, spacing: YubaiSpace.gapHeading) {
                heading("发出去的只有")
                Card(style: .compact, background: YubaiColor.raised) {
                    Text("商户名、金额、日期、分类。不发账户号、不发余额、不发你的名字。").yubaiFont(YubaiFont.callout)
                }
            }
            Card(style: .list) {
                NavigationLink { CloudSendLogView() } label: { settingsRow("看最近发出去了什么", detail: "本次打开 \(sendCount) 次", chevron: true) }.hidesListDisclosure()
                    .buttonStyle(PressButtonStyle()).accessibilityIdentifier("openCloudSendLog")
            }
            // Retain the existing device and notification preferences below the cloud/privacy groups.
            Card(style: .list) {
                WeeklyLetterReminder()
            }
            VStack(alignment: .leading, spacing: YubaiSpace.gapHeading) {
                heading("设备与界面")
                Card(style: .list) {
                    VStack(spacing: YubaiSpace.none) {
                        Toggle("使用设备解锁保护账本", isOn: Binding(get: { store.preferences.lockEnabled }, set: enableLock)).tint(YubaiColor.toggleOn).frame(minHeight: YubaiSize.headerHeight)
                        separator
                        Picker("外观", selection: Binding(get: { store.preferences.appearance }, set: { value in
                            store.update("保存外观") { $0.preferences.appearance = value }
                        })) { Text("跟随系统").tag("system"); Text("浅色").tag("light"); Text("深色").tag("dark") }.frame(minHeight: YubaiSize.rowSingle)
                    }
                }
            }
        }.navigationTitle("智能与隐私").yubaiNavigation().accessibilityIdentifier("intelligencePrivacyPage").onAppear {
            IntelligenceRuntime.cloud.refresh(); hasKey = APIKeyStore.shared.hasKeychainKey
            configured = IntelligenceRuntime.isConfigured; sendCount = SendLog.shared.totalCount
        }
        .onReceive(NotificationCenter.default.publisher(for: SendLog.didRecord).receive(on: RunLoop.main)) { _ in sendCount = SendLog.shared.totalCount }
    }
    private func privacyChips(_ title: String, values: [String], excluded: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: YubaiSpace.gapHeading) {
            heading(title)
            Card {
                ChipFlow {
                    ForEach(values, id: \.self) { value in
                        Text(value).yubaiFont(YubaiFont.caption).lineLimit(1).truncationMode(.tail).strikethrough(excluded)
                            .foregroundStyle(excluded ? YubaiColor.labelSecondary : YubaiColor.label)
                            .padding(.horizontal, YubaiSpace.gapGroup).padding(.vertical, YubaiSpace.space8)
                            .background(excluded ? Color.clear : YubaiColor.raised, in: Capsule())
                            .overlay { if excluded { Capsule().strokeBorder(YubaiColor.borderDashed) } }
                    }
                }
            }.accessibilityElement(children: .combine).accessibilityLabel(title + "：" + values.joined(separator: "、"))
        }
    }
    private func heading(_ text: String) -> some View { Text(text).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary).padding(.horizontal, YubaiSpace.insetCard) }
    private var separator: some View { Rectangle().fill(YubaiColor.separator).frame(height: 1).accessibilityHidden(true) }
    private func settingsRow(_ title: String, detail: String, numeric: Bool = false, chevron: Bool = false) -> some View {
        HStack(spacing: YubaiSpace.space8) {
            Text(title).yubaiFont(YubaiFont.row); Spacer(minLength: YubaiSpace.space8)
            Text(detail).yubaiFont(numeric ? YubaiFont.amountSmall : YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
            if chevron { Image(systemName: "chevron.right").yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary) }
        }.frame(minHeight: YubaiSize.rowSingle).contentShape(Rectangle())
    }
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
    static var readableContentTypes: [UTType] { [.data, .json, .yubaiBackup] }
    var data: Data
    init(data: Data = Data()) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct BackupView: View {
    @Environment(AppStore.self) private var store
    @State private var password = ""; @State private var restorePassword = ""; @State private var exportDocument = ExportDocument()
    @State private var exporting = false; @State private var importing = false; @State private var exportName = ""
    @State private var pendingRestore: Ledger?; @State private var restoreData: Data?; @State private var busy = false; @State private var message: String?
    @State private var exportedLedgerID: UUID?; @State private var exportedAt: Date?
    @State private var encryptedRestore = false
    @State private var exportExpanded = false
    private struct BackupHeader: Decodable { let format: String; let version: Int; let encrypted: Bool }
    private enum PasswordField: Hashable { case export, restore }
    @FocusState private var passwordFocus: PasswordField?
    var body: some View {
        Form {
            Section { lastBackup }.listRowBackground(Color.clear).listRowSeparator(.hidden)
            if busy { Section { ProgressView("正在本机处理…") }.listRowBackground(YubaiColor.card).listRowSeparatorTint(YubaiColor.separator) }
            if let message { Section { Text(message).yubaiFont(YubaiFont.callout).textSelection(.enabled) }.listRowBackground(YubaiColor.card).listRowSeparatorTint(YubaiColor.separator) }
            Section {
                Button { exportExpanded.toggle() } label: { backupRow("备份到文件", detail: "存到「文件」或隔空投送") }
                    .accessibilityIdentifier("backupToFile")
                Button { passwordFocus = nil; importing = true } label: { backupRow("从备份恢复", detail: nil) }
                    .disabled(busy).accessibilityIdentifier("restoreFromBackup")
            }.listRowBackground(YubaiColor.card).listRowSeparatorTint(YubaiColor.separator)
            if exportExpanded { exportSection }
            if encryptedRestore { restoreSection }
            LedgerSyncSection()
            if let pendingRestore {
                Section("已验证的备份") {
                    Text("\(pendingRestore.accounts.count) 个账户 · \(pendingRestore.activeEntries.count) 笔有效记录 · \(pendingRestore.attachments.count) 份附件")
                    Text("最后修改：\(Dates.text(pendingRestore.updatedAt, time: true))").yubaiFont(YubaiFont.caption)
                    Button("确认恢复这份账本") { if store.restore(pendingRestore) { self.pendingRestore = nil; restoreData = nil; encryptedRestore = false; restorePassword = ""; message = "恢复操作已完成，原账本保留在本地恢复历史。" } }
                    Button("取消恢复", role: .cancel) { self.pendingRestore = nil; restoreData = nil; encryptedRestore = false; restorePassword = "" }
                }.listRowBackground(YubaiColor.card).listRowSeparatorTint(YubaiColor.separator)
            }
            Section {
                NavigationLink("最近删除 \(RecentlyDeleted.entries(in: store.current).count) 笔") { RecentlyDeletedView() }.accessibilityIdentifier("recentlyDeleted")
                NavigationLink("恢复版本") { RecoveryVersionsView() }
            }.listRowBackground(YubaiColor.card)
            Section { EraseAllDataButton() }.listRowBackground(Color.clear).listRowSeparator(.hidden)
        }.editorForm().navigationTitle("备份与恢复").yubaiNavigation().manualSheetHeader("备份与恢复", cancelTitle: "关闭", showsAction: false)
            .fileExporter(isPresented: $exporting, document: exportDocument, contentType: .yubaiBackup, defaultFilename: exportName) { result in
                switch result {
                case .success:
                    message = "文件已保存到你选择的位置。"
                    if let exportedLedgerID, let exportedAt {
                        store.recordSuccessfulBackup(of: exportedLedgerID, at: exportedAt)
                    }
                case .failure(let error): message = error.localizedDescription
                }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.yubaiBackup, .json, .data]) { result in do { acceptBackup(try result.get()) } catch { message = error.localizedDescription } }
            .task { await store.configureSync() }
            .onAppear { if let url = store.importedURL, url.pathExtension.lowercased() == "yubaibackup" { store.importedURL = nil; acceptBackup(url) } }
    }
    func acceptBackup(_ url: URL) {
        pendingRestore = nil; restoreData = nil; restorePassword = ""; encryptedRestore = false; message = nil
        do {
            let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= LedgerCodec.backupCapacity else { throw YubaiError.invalid("备份文件过大。") }
            let data = try Data(contentsOf: url)
            restoreData = data
            if let header = try? JSONDecoder().decode(BackupHeader.self, from: data), header.format == "yubai-backup", header.version == 1, header.encrypted {
                encryptedRestore = true; passwordFocus = .restore
            } else { readBackup() }
        } catch { message = error.localizedDescription }
    }
    func exportBackup() {
        passwordFocus = nil
        let ledger = store.current; let password = password; busy = true; message = nil
        exportedLedgerID = ledger.id; exportedAt = Date()
        Task { do { let data = try await Task.detached { try Backup.export(ledger, password: password) }.value; exportDocument = ExportDocument(data: data); exportName = "余白备份-" + Dates.text(Date()) + ".yubaibackup"; exporting = true; busy = false } catch { message = error.localizedDescription; busy = false } }
    }
    func readBackup() {
        passwordFocus = nil
        guard let restoreData else { return }; let password = restorePassword; busy = true; pendingRestore = nil; message = nil
        Task { do { let restored = try await Task.detached { try Backup.restore(restoreData, password: password) }.value; pendingRestore = restored; busy = false } catch { message = error.localizedDescription; busy = false } }
    }

    private var exportSection: some View {
        Section {
            SecureField("备份密码（至少 8 位）", text: $password).focused($passwordFocus, equals: .export)
            Button("导出完整备份", action: exportBackup).disabled(busy || password.count < 8)
            Text("密码无法找回，请妥善保存。").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
        }.listRowBackground(YubaiColor.card).listRowSeparatorTint(YubaiColor.separator)
    }
    private var restoreSection: some View {
        Section {
            SecureField("备份密码", text: $restorePassword).focused($passwordFocus, equals: .restore)
                .accessibilityHint("填写创建这份加密备份时使用的密码")
            Button("读取备份", action: readBackup).disabled(busy || restorePassword.isEmpty)
        }.listRowBackground(YubaiColor.card).listRowSeparatorTint(YubaiColor.separator)
    }
    private var lastBackup: some View {
        VStack(alignment: .leading, spacing: YubaiSpace.space4) {
            Text("上次备份").yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary)
            if let date = store.preferences.lastBackupAt {
                let days = max(0, Dates.calendar.dateComponents([.day], from: Dates.day(date), to: Dates.day(Date())).day ?? 0)
                HStack(alignment: .firstTextBaseline, spacing: YubaiSpace.space8) {
                    Text(FixedFlowPresentation.monthDay(date)).yubaiFont(YubaiFont.amountLarge)
                    Text(days == 0 ? "今天" : "\(days) 天前").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                }
            } else { Text("还没备份过").yubaiFont(YubaiFont.amountLarge) }
        }.frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .combine).accessibilityIdentifier("lastBackup")
    }
    private func backupRow(_ title: String, detail: String?) -> some View {
        HStack(spacing: YubaiSpace.gapGroup) {
            Text(title).yubaiFont(YubaiFont.row).foregroundStyle(YubaiColor.label)
            Spacer(minLength: YubaiSpace.space8)
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
                    Text(batch.filename).yubaiFont(YubaiFont.rowTitle)
                    Text("\(Dates.text(batch.importedAt, time: true)) · \(batch.importedCount) 笔" + (batch.undoneAt == nil ? "" : " · 已撤销"))
                        .yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary)
                    if batch.undoneAt == nil {
                        if batch.needsOrganization == true || !(batch.organization?.questions.isEmpty ?? true) {
                            Button("继续整理") { store.sheet = .imports }.frame(minHeight: YubaiSize.rowSingle)
                        }
                        Button("整批撤销", role: .destructive) { undoBatch = batch }
                            .disabled(store.organizingBatchID != nil).frame(minHeight: YubaiSize.tapMin).accessibilityIdentifier("undoImportBatch")
                    }
                    if let attachment = store.current.attachments.first(where: { $0.id == batch.attachmentID }) {
                        Button("导出原文件") { do { document = ExportDocument(data: try store.localRepository.attachmentData(attachment.id)); filename = attachment.name; exporting = true } catch { store.error = error.localizedDescription } }
                            .frame(minHeight: YubaiSize.tapMin)
                    }
                }.buttonStyle(.borderless).padding(.vertical, YubaiSpace.space8)
            }
        }.navigationTitle("导入记录").yubaiNavigation()
            .confirmationDialog("撤销这批 \(undoBatch?.importedCount ?? 0) 笔？整理产生的关联和安排也会还原。",
                                isPresented: Binding(get: { undoBatch != nil }, set: { if !$0 { undoBatch = nil } })) {
                Button("撤销这一批", role: .destructive) { if let batch = undoBatch { store.undoImport(batch.id) }; undoBatch = nil }
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
                        Text(recovery.name).yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, YubaiSpace.space8).contentShape(Rectangle())
                }.buttonStyle(PressButtonStyle())
            }
        }.navigationTitle("恢复版本").yubaiNavigation().manualSheetHeader("恢复版本", cancelTitle: "关闭", showsAction: false)
            .onAppear { do { recoveries = try store.repository.recoveries() } catch { store.error = error.localizedDescription } }
            .confirmationDialog("恢复到这个版本？当前账本会先保留。", isPresented: Binding(get: { target != nil }, set: { if !$0 { target = nil } })) {
                Button("恢复所选版本") { if let target, store.recover(target) { dismiss() }; target = nil }
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
            .confirmationDialog("全部清掉后无法放回", isPresented: $confirmingClear, titleVisibility: .visible) {
                Button("全部清掉", role: .destructive) {
                    if store.update("清掉最近删除", recordUndo: false, entryMotion: false, { RecentlyDeleted.clear(in: &$0) }) { store.clearUndo() }
                }
                Button("取消", role: .cancel) {}
            }
    }
    @ViewBuilder private func group(_ title: String, rows: [Entry]) -> some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary).padding(.leading, 16)
                CardRows(rows) { entry in
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) { summary(entry); Spacer(); restore(entry) }
                        VStack(alignment: .leading, spacing: 8) { summary(entry); restore(entry) }
                    }.padding(.vertical, 8)
                }
            }
        }
    }
    private func summary(_ entry: Entry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
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
            Text("放回去").yubaiFont(YubaiFont.callout).padding(.horizontal, 12).frame(minHeight: 32)
                .background(YubaiColor.raised, in: Capsule()).fixedSize().yubaiHitTarget()
        }.buttonStyle(PressButtonStyle()).accessibilityIdentifier("restoreDeleted_" + entry.id.uuidString)
    }
    private func deletedTime(_ date: Date) -> String {
        Dates.calendar.isDateInToday(date) ? date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)) : ManualBookkeeping.dayLabel(date)
    }
}
