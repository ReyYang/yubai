import SwiftUI
import UniformTypeIdentifiers
import LocalAuthentication
import YubaiCore

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var storageSize: String?
    private var thinkingCount: Int { store.settingsSummary.thinkingCount }
    private var followUpCount: Int { store.settingsSummary.followUpCount }
    var body: some View {
        Page(spacing: YubaiSpace.gapSection, topPadding: YubaiSpace.none) {
            TabNavigationLink(.profile) { ProfileView() } label: {
                Card {
                    VStack(alignment: .leading, spacing: YubaiSpace.space8) {
                        HStack(spacing: YubaiSpace.gapGroup) {
                            Text("我的消费观").yubaiFont(YubaiFont.cardTitle)
                            Spacer(minLength: YubaiSpace.space8)
                            Text("\(store.settingsSummary.memoryCount) 条").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                                .accessibilityLabel("余白记得的，" + memoryCount)
                            chevron
                        }
                        profileLine("想克制", store.profile.restrain.map(\.title).joined(separator: "、"))
                        profileLine("愿意多花", store.profile.generous.map(\.title).joined(separator: "、"))
                        if let floor = store.profile.floorAmount { profileLine("始终留着", store.preferences.hideAmounts ? "••••" : Money.text(floor, currency: false)) }
                    }
                }
            }.buttonStyle(PressButtonStyle()).accessibilityIdentifier("openProfile")
                .accessibilityHint(store.profile.restrain.isEmpty && store.profile.generous.isEmpty && store.profile.floorAmount == nil ? "还没写消费观，可进入添加" : "查看和编辑消费观")
            Card(style: .list) {
                VStack(spacing: YubaiSpace.none) {
                    TabNavigationLink(.wishlist) { WishlistView() } label: {
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: YubaiSpace.gapGroup) { wishlistTitle; Spacer(); followUp; chevron }
                            VStack(alignment: .leading, spacing: YubaiSpace.space8) { wishlistTitle; followUp }
                        }.frame(minHeight: YubaiSize.rowDouble).contentShape(Rectangle())
                    }.accessibilityIdentifier("openWishlist")
                    separator
                    TabNavigationLink(.letters) { LettersView() } label: { row("每周来信", detail: latestLetter) }
                }
            }.buttonStyle(PressButtonStyle())
            TabNavigationLink(.accounts) { AccountsView() } label: { accountsCard }.buttonStyle(PressButtonStyle())
            Card(style: .list) {
                VStack(spacing: YubaiSpace.none) {
                    TabNavigationLink(.fixedFlows) { FixedFlowsView() } label: { row("会回来的账单", detail: fixedFlowsDetail) }
                        .accessibilityIdentifier("openFixedFlows")
                    separator
                    NavigationLink(value: CategorySettingsRoute.categories) { row("分类") }
                        .accessibilityIdentifier("openCategories")
                }
            }.buttonStyle(PressButtonStyle())
            Card(style: .list) {
                VStack(spacing: YubaiSpace.none) {
                    TabNavigationLink(.quickCapture) { QuickCaptureSettingsView() } label: { row("快速记账") }.accessibilityIdentifier("openQuickCapture")
                    separator
                    TabNavigationLink(.importHistory) { ImportHistoryView() } label: { row("导入记录") }.accessibilityIdentifier("openImportHistory")
                    separator
                    TabNavigationLink(.intelligencePrivacy) { IntelligencePrivacyView() } label: {
                        HStack(spacing: YubaiSpace.gapGroup) {
                            Text("智能与隐私").yubaiFont(YubaiFont.row); Spacer()
                            if store.preferences.cloudAIEnabled && IntelligenceRuntime.isConfigured {
                                Pill(text: "DeepSeek · 已配好", variant: .brand, height: YubaiSize.tagHeight, showsDot: false)
                            } else { Text("未配好").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary) }
                            chevron
                        }.frame(minHeight: YubaiSize.rowSingle).contentShape(Rectangle())
                    }.accessibilityIdentifier("openIntelligencePrivacy")
                    separator
                    TabNavigationLink(.backup) { BackupView() } label: { row("备份与恢复") }.accessibilityIdentifier("openBackup")
                    separator
                    TabNavigationLink(.storage) { StorageView() } label: { row("存储空间", detail: storageSize) }.accessibilityIdentifier("openStorage")
                }
            }.buttonStyle(PressButtonStyle())
        }.amountPrivacy(store.preferences.hideAmounts).rootScrollContentMargins().rootTabScroll(.settings).accessibilityIdentifier("settingsScroll")
            .navigationDestination(for: CategorySettingsRoute.self) { _ in CategoriesView() }
            .rootPageHeader { TabRootHeader(title: "我") }.navigationTitle("我")
            .modifier(SettingsStorageSizeTask(storageSize: $storageSize))
            #if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
            #endif
    }
    private var latestLetter: String? {
        store.cards.filter { $0.kind == .weeklyLetter }.max(by: { $0.createdAt < $1.createdAt })?.createdAt.formatted(.dateTime.month().day().locale(Locale(identifier: "zh_CN")))
    }
    private var fixedFlowsDetail: String {
        let titles = store.settingsSummary.fixedFlowTitles
        return (titles.isEmpty ? "" : titles.prefix(2).joined(separator: "、") + "等 ") + "\(titles.count) 项"
    }
    private var memoryCount: String {
        let added = store.settingsSummary.weeklyMemoryCount
        return "\(store.settingsSummary.memoryCount) 条 · 这周新记了 \(added) 条"
    }
    private var wishlistTitle: some View {
        VStack(alignment: .leading, spacing: YubaiSpace.space4) {
            Text("心愿单").yubaiFont(YubaiFont.rowTitle)
            Text("\(thinkingCount) 件在想").yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary)
        }
    }
    @ViewBuilder private var followUp: some View {
        if followUpCount > 0 { Pill(text: "\(followUpCount) 件买了一个月", variant: .amber, showsDot: false) }
    }
    private var accountsCard: some View {
        let summary = store.settingsSummary
        let cash = summary.cashAccounts
        let values = summary.cashBalances.map { max(0, $0) }
        let total = values.reduce(Int64(0), +)
        return Card {
            VStack(alignment: .leading, spacing: YubaiSpace.space8) {
                HStack(spacing: YubaiSpace.gapGroup) { Text("账户").yubaiFont(YubaiFont.rowTitle); Spacer(); Text("\(store.accounts.count) 个账户").yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary); chevron }
                AmountLabel(cents: store.funds.cash, hide: store.preferences.hideAmounts, role: .account)
                if !store.preferences.hideAmounts && total > 0 {
                    GeometryReader { geometry in
                        HStack(spacing: YubaiSpace.space4) {
                            ForEach(values.indices, id: \.self) { i in
                                let colors = [YubaiColor.brand, YubaiColor.series2, YubaiColor.series3, YubaiColor.neutralStrong, YubaiColor.neutralSoft]
                                let gapWidth = CGFloat(max(0, values.count - 1)) * YubaiSpace.space4
                                let availableWidth = max(CGFloat(0), geometry.size.width - gapWidth)
                                let share = CGFloat(values[i]) / CGFloat(total)
                                colors[min(i, colors.count - 1)].frame(width: availableWidth * share)
                            }
                        }.clipShape(Capsule())
                    }.frame(height: 8).accessibilityElement(children: .ignore)
                        .accessibilityLabel("现金分布：" + cash.indices.map { cash[$0].name + " " + Money.text(summary.cashBalances[$0]) }.joined(separator: "；"))
                }
            }
        }
    }
    @ViewBuilder private func profileLine(_ title: String, _ value: String) -> some View {
        if !value.isEmpty {
            let layout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: YubaiSpace.space4)) : AnyLayout(HStackLayout(alignment: .top, spacing: YubaiSpace.space8))
            layout { Text(title).foregroundStyle(YubaiColor.labelSecondary); Text(value) }.yubaiFont(YubaiFont.callout)
        }
    }
    private func row(_ title: String, detail: String? = nil) -> some View {
        HStack(spacing: YubaiSpace.gapGroup) { Text(title).yubaiFont(YubaiFont.row); Spacer(); if let detail { Text(detail).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary) }; chevron }.frame(minHeight: YubaiSize.rowSingle).contentShape(Rectangle())
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
            VStack(alignment: .leading, spacing: YubaiSpace.gapHeading) {
                heading("云端智能")
                Card(style: .list) {
                    VStack(spacing: YubaiSpace.none) {
                        Toggle("打开云端智能", isOn: Binding(get: { store.preferences.cloudAIEnabled }, set: { value in
                            store.update("保存云端 AI 偏好") { $0.preferences.cloudAIEnabled = value }
                        })).tint(YubaiColor.toggleOn).frame(minHeight: YubaiSize.headerHeight)
                        separator
                        settingsRow("服务", detail: "DeepSeek")
                        separator
                        CloudModelMenu()
                        separator
                        NavigationLink { Form { CloudAISettingsSection() }.editorForm().navigationTitle("密钥").yubaiNavigation() } label: {
                            settingsRow("密钥", detail: hasKey ? "钥匙串 ✓" : (configured ? "环境变量" : "未配好"), chevron: true)
                        }.accessibilityLabel(hasKey ? "密钥，保存在本机钥匙串，不进入账本或备份" : (configured ? "密钥，使用环境变量" : "密钥，未配好"))
                    }.buttonStyle(PressButtonStyle())
                }
            }
            privacyChips("会发给云端", values: ["问题", "金额", "日期", "分类", "商户", "备注", "转账姓名 → 联系人A"])
            privacyChips("不发", values: ["账户名", "卡号", "交易单号", "附件"], excluded: true)
            Card(style: .list) {
                NavigationLink { CloudSendLogView() } label: { settingsRow("发给云端的内容", detail: "本次打开 \(sendCount) 次", chevron: true) }
                    .buttonStyle(PressButtonStyle())
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
    private struct BackupHeader: Decodable { let format: String; let version: Int; let encrypted: Bool }
    private enum PasswordField: Hashable { case export, restore }
    @FocusState private var passwordFocus: PasswordField?
    var body: some View {
        Form {
            if busy { Section { ProgressView("正在本机处理…") }.listRowBackground(YubaiColor.card).listRowSeparatorTint(YubaiColor.separator) }
            if let message { Section { Text(message).yubaiFont(YubaiFont.callout).textSelection(.enabled) }.listRowBackground(YubaiColor.card).listRowSeparatorTint(YubaiColor.separator) }
            LedgerSyncSection()
            exportSection
            restoreSection
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
        Section("完整备份") {
            SecureField("备份密码（至少 8 位）", text: $password).focused($passwordFocus, equals: .export)
            Button("导出完整备份", action: exportBackup).disabled(busy || password.count < 8)
            Text("密码无法找回，请妥善保存。").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
        }.listRowBackground(YubaiColor.card).listRowSeparatorTint(YubaiColor.separator)
    }
    private var restoreSection: some View {
        Section("恢复到这台设备") {
            Button("选择备份文件") { passwordFocus = nil; importing = true }.disabled(busy)
            if encryptedRestore {
                SecureField("备份密码", text: $restorePassword).focused($passwordFocus, equals: .restore)
                    .accessibilityHint("填写创建这份加密备份时使用的密码")
                Button("读取备份", action: readBackup).disabled(busy || restorePassword.isEmpty)
            }
        }.listRowBackground(YubaiColor.card).listRowSeparatorTint(YubaiColor.separator)
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
