import SwiftUI
import UniformTypeIdentifiers
import LocalAuthentication
import YubaiCore

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var horizon = 90; @State private var reserve = ""; @State private var living = ""; @State private var values = ""; @State private var preferencesLoaded = false
    var body: some View {
        Form {
            Section {
                let layout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 14)) : AnyLayout(HStackLayout(spacing: 18))
                layout { BrandMark(); if !textSize.isAccessibilitySize { Spacer() }; VStack(alignment: .leading, spacing: 6) { Text("个人资金管理").font(.headline); Text("1.0.0 · 本地优先").font(.caption).foregroundStyle(.secondary) } }.padding(.vertical, 16)
                Button { store.sheet = .accounts } label: { Label("账户与余额核对", systemImage: "wallet.bifold") }
            }
            Section("资金偏好") {
                Picker("从今天向前看", selection: $horizon) { Text("30 天").tag(30); Text("60 天").tag(60); Text("90 天").tag(90); Text("180 天").tag(180); Text("365 天").tag(365) }
                TextField("应急底线金额", text: $reserve).numericInput()
                TextField("每天的日常生活预留", text: $living).numericInput()
                TextField("我希望把钱花在什么上", text: $values, axis: .vertical).lineLimit(2...5)
                Button("保存资金偏好", action: savePreferences)
                Text("日常生活预留用于未逐项列出的零碎开销。不要把同一笔固定付款既列为安排又放进日常预留。调整不会改动真实账单。").font(.caption).foregroundStyle(.secondary)
            }
            Section("整理与保护") {
                Button { store.sheet = .categories } label: { Label("收支分类", systemImage: "square.grid.2x2") }
                Button { store.sheet = .rules } label: { Label("自动分类规则", systemImage: "line.3.horizontal.decrease") }
                Button { store.sheet = .backup } label: { Label("备份、恢复与导出", systemImage: "externaldrive") }
                Button { store.sheet = .history } label: { Label("导入批次与本地恢复", systemImage: "clock.arrow.circlepath") }
                Toggle("使用设备解锁保护账本", isOn: Binding(get: { store.current.preferences.lockEnabled }, set: enableLock))
                Text("使用设备现有的 Face ID、Touch ID 或密码。原始账单和本地账本不会上传。请另存一份加密备份，防止设备丢失。").font(.caption).foregroundStyle(.secondary)
            }
            Section("界面与外观") {
                Picker("外观", selection: Binding(get: { store.current.preferences.appearance }, set: { value in store.update("保存外观") { $0.preferences.appearance = value } })) { Text("跟随系统").tag("system"); Text("浅色").tag("light"); Text("深色").tag("dark") }
                Picker("主题", selection: Binding(get: { YubaiColorTheme(preference: store.current.preferences.colorTheme).rawValue }, set: { value in store.update("保存主题") { $0.preferences.colorTheme = value } })) {
                    ForEach(YubaiColorTheme.allCases) { theme in Text(theme.title).tag(theme.rawValue) }
                }
            }
            Section("智能辅助") {
                Toggle("允许智能辅助", isOn: Binding(get: { store.current.preferences.localAIEnabled }, set: { value in store.update("保存智能辅助总开关") { $0.preferences.localAIEnabled = value } }))
                Toggle("增强智能（云端）", isOn: Binding(get: { store.current.preferences.cloudAIEnabled }, set: { value in store.update("保存云端 AI 偏好") { $0.preferences.cloudAIEnabled = value } }))
                Text(LocalIntelligence.availabilityText(for: store.current.preferences)).font(.caption).foregroundStyle(.secondary)
                Text("规则与资金计算始终在本机。开启「增强智能」后，归类 / 购买短答 / 洞察润色 / 语义搜索可走云端（需配置 DEEPSEEK_API_KEY）；金额、账户与资金性质从不交给模型修改。未配置密钥时自动降级为规则与模板，不会崩溃。").font(.caption).foregroundStyle(.secondary)
                DisclosureGroup("高级选项") {
                    Toggle("尝试使用本机下载模型（实验）", isOn: Binding(get: { store.current.preferences.downloadedModelEnabled }, set: { value in
                        store.update("保存本机模型偏好") { $0.preferences.downloadedModelEnabled = value }
                        if value { IntelligenceRuntime.resetLocalInferenceGate() }
                    }))
                    Toggle("允许系统 Apple 模型", isOn: Binding(get: { store.current.preferences.appleSystemModelEnabled }, set: { value in store.update("保存系统模型偏好") { $0.preferences.appleSystemModelEnabled = value } }))
                    Toggle("实验性 mock 路径", isOn: Binding(get: { store.current.preferences.experimentalMockLocalAI }, set: { value in store.update("保存实验 AI 开关") { $0.preferences.experimentalMockLocalAI = value } }))
                    NavigationLink { ModelWeightsSettingsView() } label: { Label("本机模型（开发者）", systemImage: "wrench.and.screwdriver") }
                    Text("本机大模型在部分真机上可能导致卡顿或退出；默认关闭。仅在明确需要时开启。").font(.caption2).foregroundStyle(.secondary)
                }
            }
            Section("了解余白") {
                Button { store.sheet = .guide } label: { Label("使用指南与计算口径", systemImage: "book.closed") }
                Button(store.isDemo ? "退出示例账本" : "体验独立示例账本") { if store.isDemo { store.endDemo() } else { store.startDemo() } }
                Text("余白 1.0.0\n把钱理清，把生活留给自己。\n不执行转账，不连接银行，不自动交易。") .font(.caption).foregroundStyle(.secondary)
            }
        }.editorForm().navigationTitle("我的余白").onAppear { if !preferencesLoaded { loadPreferences(); preferencesLoaded = true } }.onChange(of: store.isDemo) { _, _ in loadPreferences() }
    }
    func loadPreferences() { let p = store.current.preferences; horizon = p.horizonDays; reserve = Money.input(p.emergencyReserve); living = Money.input(p.dailyLiving); values = p.purchaseValues }
    func savePreferences() {
        do { let emergency = try Money.parse(reserve); let daily = try Money.parse(living); store.update("保存资金偏好") { $0.preferences.horizonDays = horizon; $0.preferences.emergencyReserve = emergency; $0.preferences.dailyLiving = daily; $0.preferences.purchaseValues = values } } catch { store.error = error.localizedDescription }
    }
    func enableLock(_ enabled: Bool) {
        guard enabled else { store.update("关闭账本锁") { $0.preferences.lockEnabled = false }; return }
        let context = LAContext(); var failure: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &failure) else { store.error = "请先为设备设置密码，再开启账本锁。"; return }
        Task { do { if try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "确认你可以解锁余白账本") { store.update("开启账本锁") { $0.preferences.lockEnabled = true } } } catch { store.error = "验证未完成，账本锁尚未开启。" } }
    }
}

struct CategoriesView: View {
    @Environment(AppStore.self) private var store
    @State private var name = ""; @State private var income = false; @State private var selected: String?; @State private var rename = ""
    var body: some View {
        Form {
            Section("添加分类") { TextField("分类名称", text: $name); Toggle("用于收入", isOn: $income); Button("添加") { let clean = name.trimmingCharacters(in: .whitespacesAndNewlines); guard !clean.isEmpty else { return }; if store.update("添加分类", { l in guard !l.categories.contains(where: { $0.name == clean }) else { throw YubaiError.invalid("已有同名分类。") }; l.categories.append(Category(clean, income ? "arrow.down.left" : "square.grid.2x2", income: income)) }) { name = "" } } }
            Section("已有分类 · 点击重命名") { ForEach(store.current.categories) { c in Button { selected = c.name; rename = c.name } label: { HStack { Label(c.name, systemImage: c.symbol); Spacer(); Text(c.income ? "收入" : "支出").font(.caption).foregroundStyle(.secondary) } }.buttonStyle(.plain) } }
            Section { InlineNote(text: "重命名会同步更新记录、规则与安排中的分类，可以撤销。系统初始分类保留兜底用途。") }
        }.editorForm().navigationTitle("收支分类").toolbar { CloseButton() }
            .alert("重命名分类", isPresented: Binding(get: { selected != nil }, set: { if !$0 { selected = nil } })) { TextField("名称", text: $rename); Button("取消", role: .cancel) { selected = nil }; Button("保存") { renameCategory() } }
    }
    func renameCategory() {
        guard let old = selected else { return }; let new = rename.trimmingCharacters(in: .whitespacesAndNewlines)
        if store.update("重命名分类", { l in
            guard !new.isEmpty, !l.categories.contains(where: { $0.name == new && $0.name != old }) else { throw YubaiError.invalid("分类名称为空或已存在。") }
            if let i = l.categories.firstIndex(where: { $0.name == old }) { l.categories[i].name = new }
            for key in l.categoryAliases.keys where l.categoryAliases[key] == old { l.categoryAliases[key] = new }; l.categoryAliases[old] = new
            for i in l.entries.indices where l.entries[i].category == old { l.entries[i].category = new }
            for i in l.rules.indices where l.rules[i].category == old { l.rules[i].category = new }
            for i in l.plans.indices where l.plans[i].category == old { l.plans[i].category = new }
        }) { selected = nil }
    }
}

struct RulesView: View {
    @Environment(AppStore.self) private var store
    @State private var keyword = ""; @State private var category = "餐饮"; @State private var applyExisting = false
    private var matches: [Entry] { guard !keyword.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }; return store.current.activeEntries.filter { [.expense, .income].contains($0.nature) && ($0.title + " " + $0.note).localizedCaseInsensitiveContains(keyword) } }
    var body: some View {
        Form {
            Section("建立可重复使用的规则") { TextField("用途或商户关键词", text: $keyword); Picker("归入分类", selection: $category) { ForEach(store.current.categories) { Text($0.name).tag($0.name) } }; Toggle("同时纠正已有 \(matches.count) 笔匹配记录", isOn: $applyExisting); Button("保存规则") { saveRule() }; Text("新规则优先匹配。只改分类，不更改交易金额、账户或性质；任何批量纠正都可撤销。").font(.caption).foregroundStyle(.secondary) }
            Section("已学会的规则") {
                if store.current.rules.isEmpty { Text("还没有规则。纠正一次，之后就能少做一些。").foregroundStyle(.secondary) }
                ForEach(store.current.rules) { rule in HStack { VStack(alignment: .leading, spacing: 6) { Text(rule.keyword).font(.headline); Text("归入：" + rule.category).font(.caption).foregroundStyle(.secondary) }; Spacer(); Toggle("启用", isOn: Binding(get: { store.current.rules.first { $0.id == rule.id }?.enabled ?? false }, set: { value in store.update("调整分类规则") { l in if let i = l.rules.firstIndex(where: { $0.id == rule.id }) { l.rules[i].enabled = value } } })).labelsHidden(); Button { store.update("移除分类规则") { $0.rules.removeAll { $0.id == rule.id } } } label: { Image(systemName: "trash") }.buttonStyle(.borderless).accessibilityLabel("删除规则 " + rule.keyword) } }
            }
        }.editorForm().navigationTitle("自动分类规则").toolbar { CloseButton() }
    }
    func saveRule() {
        let clean = keyword.trimmingCharacters(in: .whitespacesAndNewlines); guard !clean.isEmpty else { store.error = "请填写一个关键词。"; return }; let ids = Set(matches.map(\.id))
        if store.update("保存分类规则", { l in l.rules.insert(Rule(keyword: clean, category: category), at: 0); if applyExisting { for i in l.entries.indices where ids.contains(l.entries[i].id) { l.entries[i].category = category; l.entries[i].userEdited = true; l.entries[i].classificationReason = "用户应用规则：\(clean)" } } }) { keyword = ""; applyExisting = false }
    }
}

extension UTType { static let yubaiBackup = UTType(exportedAs: "app.yubai.backup", conformingTo: .data) }
struct ExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.data, .json, .commaSeparatedText, .yubaiBackup] }
    var data: Data
    init(data: Data = Data()) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct BackupView: View {
    @Environment(AppStore.self) private var store
    @State private var password = ""; @State private var restorePassword = ""; @State private var exportDocument = ExportDocument()
    @State private var exporting = false; @State private var importing = false; @State private var exportType = UTType.yubaiBackup; @State private var exportName = ""
    @State private var pendingRestore: Ledger?; @State private var restoreData: Data?; @State private var busy = false; @State private var message: String?
    private enum PasswordField: Hashable { case export, restore }
    @FocusState private var passwordFocus: PasswordField?
    var body: some View {
        Form {
            if busy { Section { ProgressView("正在本机处理…") } }
            if let message { Section { Text(message).font(.callout).textSelection(.enabled) } }
            Section("完整备份") {
                Text("包括账户、记录、规则、安排、目标和原始账单附件。设备之间可通过系统分享或文件传递备份；当前没有自动云同步。").font(.callout).foregroundStyle(.secondary)
                SecureField("备份密码（推荐，至少 8 位）", text: $password).focused($passwordFocus, equals: .export)
                Button("导出完整备份", action: exportBackup).disabled(busy)
                Text("不填密码将导出未加密备份。密码无法找回，请妥善保存。备份只写到你选择的位置。").font(.caption).foregroundStyle(.secondary)
            }
            Section("恢复到这台设备") {
                SecureField("如果备份已加密，填写密码", text: $restorePassword).focused($passwordFocus, equals: .restore)
                Button("选择备份文件") { passwordFocus = nil; importing = true }.disabled(busy || store.isDemo)
                if restoreData != nil { Button("使用当前密码重新读取", action: readBackup).disabled(busy) }
                Text(store.isDemo ? "示例模式不能覆盖真实账本，请先退出示例。" : "先验证备份，再由你确认切换。当前账本会先保留到本地恢复历史，不会合并为两份重复记录。").font(.caption).foregroundStyle(.secondary)
            }
            if let pendingRestore {
                Section("已验证的备份") {
                    Text("\(pendingRestore.accounts.count) 个账户 · \(pendingRestore.activeEntries.count) 笔有效记录 · \(pendingRestore.attachments.count) 份附件")
                    Text("最后修改：\(Dates.text(pendingRestore.updatedAt, time: true))").font(.caption)
                    Button("确认恢复这份账本") { if store.restore(pendingRestore) { self.pendingRestore = nil; restoreData = nil; message = "恢复操作已完成，原账本保留在本地恢复历史。" } }
                    Button("取消恢复", role: .cancel) { self.pendingRestore = nil; restoreData = nil }
                }
            }
            Section("通用数据") { Button("导出全部记录为 CSV") { exportDocument = ExportDocument(data: CSV.export(store.current)); exportType = .commaSeparatedText; exportName = "余白记录-\(Dates.text(Date())).csv"; exporting = true }; Button("下载导入模板") { let sample = "时间,收支,金额,名称,分类,备注\n2026-10-01 12:30:00,支出,28.00,午餐,餐饮,示例行请替换\n"; exportDocument = ExportDocument(data: Data(("\u{FEFF}" + sample).utf8)); exportType = .commaSeparatedText; exportName = "余白导入模板.csv"; exporting = true }; Text("CSV 用于查阅和外部整理，不包含附件、安排与账户锚点。迁移或恢复请使用完整备份。").font(.caption).foregroundStyle(.secondary) }
        }.editorForm().navigationTitle("备份、恢复与导出").toolbar { CloseButton() }
            .fileExporter(isPresented: $exporting, document: exportDocument, contentType: exportType, defaultFilename: exportName) { result in switch result { case .success: message = "文件已保存到你选择的位置。"; case .failure(let error): message = error.localizedDescription } }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.yubaiBackup, .json, .data]) { result in do { acceptBackup(try result.get()) } catch { message = error.localizedDescription } }
            .onAppear { if let url = store.importedURL, url.pathExtension.lowercased() == "yubaibackup" { store.importedURL = nil; acceptBackup(url) } }
    }
    func acceptBackup(_ url: URL) {
        do { let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }; let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0; guard size <= 350 * 1024 * 1024 else { throw YubaiError.invalid("备份文件过大。") }; restoreData = try Data(contentsOf: url); readBackup() } catch { message = error.localizedDescription }
    }
    func exportBackup() {
        passwordFocus = nil
        let ledger = store.current; let password = password; busy = true; message = nil
        Task { do { let data = try await Task.detached { try Backup.export(ledger, password: password) }.value; exportDocument = ExportDocument(data: data); exportType = .yubaiBackup; exportName = (store.isDemo ? "余白示例-" : "余白备份-") + Dates.text(Date()) + ".yubaibackup"; exporting = true; busy = false } catch { message = error.localizedDescription; busy = false } }
    }
    func readBackup() {
        passwordFocus = nil
        guard let restoreData else { return }; let password = restorePassword; busy = true; pendingRestore = nil; message = nil
        Task { do { let restored = try await Task.detached { try Backup.restore(restoreData, password: password) }.value; guard !restored.isSample else { throw YubaiError.invalid("这是示例账本备份，不会覆盖你的真实账本。") }; pendingRestore = restored; busy = false } catch { message = error.localizedDescription; busy = false } }
    }
}

struct HistoryView: View {
    @Environment(AppStore.self) private var store
    @State private var recoveries: [Recovery] = []; @State private var target: Recovery?; @State private var undoBatch: ImportBatch?
    @State private var document = ExportDocument(); @State private var exporting = false; @State private var filename = ""
    var body: some View {
        List {
            Section("导入批次") {
                if store.current.imports.isEmpty { Text("还没有导入记录。").foregroundStyle(.secondary) }
                ForEach(store.current.imports.reversed()) { batch in VStack(alignment: .leading, spacing: 12) { Text(batch.filename).font(.headline); Text("\(Dates.text(batch.importedAt, time: true)) · \(batch.importedCount) 笔" + (batch.undoneAt == nil ? "" : " · 已撤销")).font(.caption).foregroundStyle(.secondary); HStack { if let attachment = store.current.attachments.first(where: { $0.id == batch.attachmentID }) { Button("导出原文件") { document = ExportDocument(data: attachment.data); filename = attachment.name; exporting = true } }; Spacer(); if batch.undoneAt == nil { Button("撤销整批", role: .destructive) { undoBatch = batch } } } }.padding(.vertical, 5) }
            }
            Section("修改前的完整版本 · 最多保留 20 份") {
                if store.isDemo { Text("示例操作只在内存中，不生成真实账本历史。").font(.caption).foregroundStyle(.secondary) }
                else { ForEach(recoveries) { r in Button { target = r } label: { VStack(alignment: .leading, spacing: 5) { Text(Dates.text(r.date, time: true)).font(.callout); Text(r.name).font(.caption2).foregroundStyle(.secondary).lineLimit(2) } }.buttonStyle(.plain) } }
            }
        }.navigationTitle("导入与恢复历史").toolbar { CloseButton() }
            .onAppear { reload() }
            .confirmationDialog("恢复到这个版本？当前账本会先保留。", isPresented: Binding(get: { target != nil }, set: { if !$0 { target = nil } })) { Button("恢复所选版本") { if let target { store.recover(target) }; self.target = nil }; Button("取消", role: .cancel) { target = nil } }
            .confirmationDialog("撤销本批次全部 \(undoBatch?.importedCount ?? 0) 笔？包括之后编辑过的记录，将移入回收站。", isPresented: Binding(get: { undoBatch != nil }, set: { if !$0 { undoBatch = nil } })) { Button("撤销这一批", role: .destructive) { if let batch = undoBatch { store.update("撤销导入批次") { BillImporter.undo(batchID: batch.id, in: &$0) }; reload() }; undoBatch = nil } }
            .fileExporter(isPresented: $exporting, document: document, contentType: .data, defaultFilename: filename) { result in if case .failure(let e) = result { store.error = e.localizedDescription } }
    }
    func reload() { do { recoveries = try store.repository.recoveries() } catch { store.error = error.localizedDescription } }
}

struct GuideView: View {
    var body: some View {
        List {
            Section("第一次用") { Text("1. 添加实际持有资金或欠款的账户，填写此刻真实余额。\n2. 在资金偏好里设置应急底线、生活预留和观察天数。\n3. 添加房租、信用还款和已知付款。\n4. 导入历史账单，检查少量例外；完成后可以直接离开。\n5. 导出一份加密备份，保存到你控制的位置。") }
            Section("余额与可动用资金") { Text("余额从最近一次核对时刻开始，加上此后实际发生的账户流入流出。历史导入用于统计，不重新累加到当前余额。保守可动用 = 现金 − 信用待还 − 已知付款 − 目标预留 − 应急底线 − 日常预留 − 待明确流入。未来收入、投资市值、借出待收不提前当现金。所有判断依赖账单完整度。") }
            Section("信用、借款与投资") { Text("信用消费记在信用账户，消费时增加欠款；还款使用双边记录关联现金账户与信用账户，不再次计作消费。借入/归还借款关联信用与借款账户；借出/收回本金关联借出待收账户。投资申赎关联现金与投资账户；市值变化在账户核对中更新，已实现收益单独记作投资收益。信用额度不是资产。") }
            Section("导入与重复") { Text("微信或支付宝里的银行卡支付应记入实际银行卡，渠道不自动等于资金账户。交易单号优先去重，缺失时按同来源、账户、时间、金额和用途识别。跨来源同时间同金额只提示疑似重复，由你确认。被删除的原记录重新导入不会复活，用户修改也不会被覆盖。未识别行保留在预览；批次原文件可随时导出。") }
            Section("房租分摊") { Text("月度分摊按月登记，允许部分收款和漏收。季度付款按与房东的真实约定预留全额；未收分摊不算现金。消费统计按付款发生日计入本人承担比例，现金流显示实际全额付款。房租已导入时关联已有记录，避免重复记一笔。") }
            Section("隐私与 AI") { Text("CSV/XLSX、截图 OCR、去重、规则分类和资金计算都在本机完成。智能辅助默认使用规则与模板；「增强智能（云端）」默认关闭，开启后仅对所选短任务发送说明范围内的摘要。金额计算仍在本机，金额/账户/资金性质从不交模型修改。本机大模型为实验选项，默认关闭。账本锁使用系统认证；备份可用密码加密，密码无法找回。") }
            Section("跨设备与恢复") { Text("iPhone 与 Mac 共用同一备份格式。导出完整备份，再在另一台设备恢复；恢复是切换到所选完整账本，不是自动双向合并。请一次只在一台设备编辑，再交接备份。恢复前会保留原账本，修改前自动保留最近 20 个完整版本。示例账本不会写入真实账本。") }
            Section("金额与范围") { Text("当前版本统一使用人民币，不自动换汇；金额按整数分计算。消费退款冲减消费，本金和内部移动不计日常收支。余白不连接银行、不执行转账、授信或投资交易。原始账单应与你的机构账单一起核对。") }
        }.font(.callout).navigationTitle("使用指南").toolbar { CloseButton() }
    }
}
