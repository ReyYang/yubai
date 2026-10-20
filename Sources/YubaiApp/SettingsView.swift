import SwiftUI
import UniformTypeIdentifiers
import LocalAuthentication
import YubaiCore

struct SettingsView: View {
    var body: some View {
        Form {
            Section {
                NavigationLink { ProfileView() } label: { Label("我的消费观", systemImage: "leaf") }.accessibilityIdentifier("openProfile")
                NavigationLink { WishlistView() } label: { Label("心愿单", systemImage: "heart") }
                NavigationLink { AccountsView() } label: { Label("账户", systemImage: "wallet.bifold") }
                NavigationLink { ImportHistoryView() } label: { Label("导入记录", systemImage: "clock.arrow.circlepath") }.accessibilityIdentifier("openImportHistory")
                NavigationLink { IntelligencePrivacyView() } label: { Label("智能与隐私", systemImage: "lock.shield") }
                NavigationLink { BackupView() } label: { Label("备份与同步", systemImage: "externaldrive") }.accessibilityIdentifier("openBackup")
                NavigationLink { GuideView() } label: { Label("使用指南", systemImage: "book.closed") }
            }.listRowBackground(YubaiColor.card).listRowSeparatorTint(YubaiColor.separator)
        }.editorForm().navigationTitle("我").yubaiNavigation()
    }
}

struct IntelligencePrivacyView: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        Form {
            CloudAISettingsSection()
            Section("来信") {
                Toggle("每周来信提醒", isOn: Binding(get: { store.current.preferences.weeklyLetterPush }, set: { enabled in
                    Task { await store.setWeeklyLetterPush(enabled) }
                })).tint(YubaiColor.toggleOn).disabled(store.updatingWeeklyPush)
                Text("每周一上午 9 点提醒一次，通知不含金额。打开余白后再写这周的来信。")
                    .yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
            }.listRowBackground(YubaiColor.card)
            Section("设备与界面") {
                Toggle("使用设备解锁保护账本", isOn: Binding(get: { store.current.preferences.lockEnabled }, set: enableLock)).tint(YubaiColor.toggleOn)
                Picker("外观", selection: Binding(get: { store.current.preferences.appearance }, set: { value in
                    store.update("保存外观") { $0.preferences.appearance = value }
                })) { Text("跟随系统").tag("system"); Text("浅色").tag("light"); Text("深色").tag("dark") }
            }.listRowBackground(YubaiColor.card)
        }.editorForm().navigationTitle("智能与隐私").yubaiNavigation()
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
                    Button("确认恢复这份账本") { if store.restore(pendingRestore) { self.pendingRestore = nil; restoreData = nil; message = "恢复操作已完成，原账本保留在本地恢复历史。" } }
                    Button("取消恢复", role: .cancel) { self.pendingRestore = nil; restoreData = nil }
                }.listRowBackground(YubaiColor.card).listRowSeparatorTint(YubaiColor.separator)
            }
            Section { NavigationLink("恢复版本") { RecoveryVersionsView() } }.listRowBackground(YubaiColor.card)
        }.editorForm().navigationTitle("备份与同步").yubaiNavigation().toolbar { CloseButton() }
            .fileExporter(isPresented: $exporting, document: exportDocument, contentType: .yubaiBackup, defaultFilename: exportName) { result in switch result { case .success: message = "文件已保存到你选择的位置。"; case .failure(let error): message = error.localizedDescription } }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.yubaiBackup, .json, .data]) { result in do { acceptBackup(try result.get()) } catch { message = error.localizedDescription } }
            .task { await store.configureSync() }
            .onAppear { if let url = store.importedURL, url.pathExtension.lowercased() == "yubaibackup" { store.importedURL = nil; acceptBackup(url) } }
    }
    func acceptBackup(_ url: URL) {
        do { let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }; let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0; guard size <= LedgerCodec.backupCapacity else { throw YubaiError.invalid("备份文件过大。") }; restoreData = try Data(contentsOf: url); readBackup() } catch { message = error.localizedDescription }
    }
    func exportBackup() {
        passwordFocus = nil
        let ledger = store.current; let password = password; busy = true; message = nil
        Task { do { let data = try await Task.detached { try Backup.export(ledger, password: password) }.value; exportDocument = ExportDocument(data: data); exportName = "余白备份-" + Dates.text(Date()) + ".yubaibackup"; exporting = true; busy = false } catch { message = error.localizedDescription; busy = false } }
    }
    func readBackup() {
        passwordFocus = nil
        guard let restoreData else { return }; let password = restorePassword; busy = true; pendingRestore = nil; message = nil
        Task { do { let restored = try await Task.detached { try Backup.restore(restoreData, password: password) }.value; pendingRestore = restored; busy = false } catch { message = error.localizedDescription; busy = false } }
    }

    private var exportSection: some View {
        Section("完整备份") {
            Text("包括账户、记录、安排、目标和原始账单附件。备份包含所有附件，可通过系统分享或文件传递；可用时可在上方选择 iCloud 同步。").yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary)
            SecureField("备份密码（至少 8 位）", text: $password).focused($passwordFocus, equals: .export)
            Button("导出完整备份", action: exportBackup).disabled(busy || password.count < 8)
            Text("完整备份使用密码加密。密码无法找回，请妥善保存；文件只写到你选择的位置。").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
        }.listRowBackground(YubaiColor.card).listRowSeparatorTint(YubaiColor.separator)
    }
    private var restoreSection: some View {
        Section("恢复到这台设备") {
            SecureField("如果备份已加密，填写密码", text: $restorePassword).focused($passwordFocus, equals: .restore)
            Button("选择备份文件") { passwordFocus = nil; importing = true }.disabled(busy)
            if restoreData != nil { Button("使用当前密码重新读取", action: readBackup).disabled(busy) }
            Text("先验证备份，再由你确认切换。当前账本会先保留到恢复版本，不会合并为两份重复记录。").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
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
            if store.current.imports.isEmpty { Text("还没有导入记录。").yubaiFont(YubaiFont.callout).accessibilityIdentifier("emptyImportHistory") }
            CardRows(Array(store.current.imports.reversed())) { batch in
                VStack(alignment: .leading, spacing: YubaiSpace.space8) {
                    Text(batch.filename).yubaiFont(YubaiFont.rowTitle)
                    Text("\(Dates.text(batch.importedAt, time: true)) · \(batch.importedCount) 笔" + (batch.undoneAt == nil ? "" : " · 已撤销"))
                        .yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary)
                    if batch.undoneAt == nil {
                        if batch.needsOrganization == true || !(batch.organization?.questions.isEmpty ?? true) {
                            Button("继续整理") { store.sheet = .imports }.frame(minHeight: YubaiSize.tapMin)
                        }
                        Button("整批撤销", role: .destructive) { undoBatch = batch }
                            .disabled(store.organizingBatchID != nil).frame(minHeight: YubaiSize.tapMin).accessibilityIdentifier("undoImportBatch")
                    }
                    if let attachment = store.current.attachments.first(where: { $0.id == batch.attachmentID }) {
                        Button("导出原文件") { document = ExportDocument(data: attachment.data); filename = attachment.name; exporting = true }
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
            Text("修改前的完整账本，最多保留 20 份。恢复前会再保留当前版本。")
                .yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary)
            CardRows(recoveries) { recovery in
                Button { target = recovery } label: {
                    VStack(alignment: .leading, spacing: YubaiSpace.space4) {
                        Text(Dates.text(recovery.date, time: true)).yubaiFont(YubaiFont.rowTitle)
                        Text(recovery.name).yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, YubaiSpace.space8)
                }.buttonStyle(PressButtonStyle())
            }
        }.navigationTitle("恢复版本").yubaiNavigation().toolbar { CloseButton() }
            .onAppear { do { recoveries = try store.repository.recoveries() } catch { store.error = error.localizedDescription } }
            .confirmationDialog("恢复到这个版本？当前账本会先保留。", isPresented: Binding(get: { target != nil }, set: { if !$0 { target = nil } })) {
                Button("恢复所选版本") { if let target, store.recover(target) { dismiss() }; target = nil }
            }
    }
}

struct GuideView: View {
    var body: some View {
        Page {
            explanation("现在", "这里有每周来信、管家卡片、保守可动用和接下来要付的钱。先添加账户并核对真实余额，再导入历史账单。旧账单不会重复增加当前余额。")
            explanation("保守可动用", "看未来 90 天：现金扣去信用待还、已知付款、储蓄目标、你写下的底线、估算的日常生活费，以及余额核对后待明确的流入。未来收入和投资市值不提前当现金。点金额可看计算依据；记录少或余额过旧时，判断也会有缺口。")
            explanation("管家什么时候开口", "碰到你想克制的消费，或钱不够覆盖付款时，管家才主动提醒。整理中的疑问、需要核对的余额和心愿回访也会留成卡片。觉得不需要，可以选「知道了」；选「以后别提」，这个话题以后就不再出现。")
            explanation("问余白", "问数字、看依据，也可以说一句话补记或上传截图。数字来自你的账本；回答中的「依据」能打开原始记录。修改先列出来，等你确认。AI 不会改动已有记录的金额、主账户和原始日期，补记金额也要由你核对。")
            explanation("我的消费观", "在「我」写下愿意多花、想克制的领域和自己的原则，也可以留储蓄目标与始终留着的底线。它们是你的选择，随时能改；「你常花的」只是账本里的习惯。")
            explanation("导入账单", "支持 CSV、TSV 和 XLSX。对应好实际付款账户，保存后自动整理分类、用途和关联，最多问五个问题，稍后答也可以。云端不可用时先保存，下次继续。需要反悔，可在「我 → 导入记录」整批撤销。")
            explanation("智能与隐私", "云端智能默认关闭。开启后，DeepSeek 会收到你的提问、消费观及任务所需的记录摘要：日期、金额、分类、用途和有限关联证据。截图先在本机识别，只发送脱敏文字；不发送原始图片、账单文件、交易单号或来源指纹，账户使用本地标识，长号码遮盖，部分转账姓名替换为别名。商户和备注仍可能出现在摘要里，脱敏不能识别所有姓名。到「我 → 智能与隐私 → 发给云端的内容」查看本次打开期间最近 50 次发送。密钥保存在本机 Keychain，不进入账本或备份。")
            explanation("备份与同步", "在「我 → 备份与同步」设置至少 8 位密码，保存加密的完整备份，包含原始账单附件。密码请自己留好。恢复先验证，再等你确认；修改前的最近 20 份完整版本也能找回。iPhone 和 Mac 用同一格式；默认仅本机，iCloud 可用时，可在「备份与同步」选择共享账本。同步冲突会保留各版本，由你选择，不自动合并。")
        }.navigationTitle("使用指南").yubaiNavigation().toolbar { CloseButton() }
    }
    private func explanation(_ title: String, _ text: String) -> some View {
        Card { VStack(alignment: .leading, spacing: YubaiSpace.space12) {
            SectionHeading(title: title)
            Text(text).yubaiFont(YubaiFont.body).foregroundStyle(YubaiColor.labelMuted)
        } }
    }
}
