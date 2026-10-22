import SwiftUI
import YubaiCore
#if os(iOS)
import UserNotifications
#endif

struct QuickCaptureSettingsView: View {
    @Environment(AppStore.self) private var store
    private var recent: [Entry] {
        let start = Dates.addDays(-6, to: Dates.day(Date()))
        return store.current.activeEntries.filter { $0.quickCapture != nil && ($0.recordedAt ?? $0.date) >= start && ($0.recordedAt ?? $0.date) <= Date() }
    }
    var body: some View {
        Page {
            Text("近 7 天").yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(recent.count)").yubaiFont(YubaiFont.amountAccount)
                Text("笔，\(recent.filter { $0.quickCapture?.withoutOpeningApp == true }.count) 笔没打开 App").yubaiFont(YubaiFont.callout)
            }
            Card(style: .list) {
                NavigationLink { ApplePaySetupView() } label: { line("Apple Pay 付款后自动记", "在快捷指令的「自动化 › 钱包」里建一次", detail: "去设置") }
            }
            Card(style: .list) {
                VStack(spacing: 0) {
                    NavigationLink { CaptureRulesView(kind: .card) } label: {
                        line("卡对应的账户", cardSummary, detail: "\(store.current.preferences.quickCapture.cardAccounts.count) 张")
                    }
                    EntryFormDivider()
                    NavigationLink { CaptureRulesView(kind: .merchant) } label: {
                        line("商户记到哪个分类", merchantSummary, detail: "\(store.current.preferences.quickCapture.merchantCategories.count) 条")
                    }
                }
            }
            Text("其他入口").yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary)
            Card(style: .list) {
                VStack(spacing: 0) {
                    line("Siri 和快捷指令", "说「余白记一笔，午饭 32」", detail: "已可用")
                    EntryFormDivider()
                    line("锁屏和主屏小组件", "长按锁屏或主屏 › 添加小组件 › 余白")
                    EntryFormDivider()
                    line("控制中心和操作按钮", "记一笔、截图记")
                    EntryFormDivider()
                    line("轻点背面截图记", "辅助功能 › 触控 › 轻点背面 › 余白 · 截图记")
                }
            }
            Text("支付宝、微信付款不经过钱包，用截图记。").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
        }.navigationTitle("快速记账").yubaiNavigation()
    }
    private var cardSummary: String {
        let rules = store.current.preferences.quickCapture.cardAccounts
        return rules.keys.sorted().prefix(2).map { $0 + " → " + store.current.accountName(rules[$0]) }.joined(separator: "；")
    }
    private var merchantSummary: String {
        let rules = store.current.preferences.quickCapture.merchantCategories
        return rules.keys.sorted().prefix(2).map { $0 + " → " + Classification.displayCategory(rules[$0]!) }.joined(separator: "，")
    }
    private func line(_ title: String, _ subtitle: String, detail: String? = nil) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).yubaiFont(YubaiFont.rowTitle)
                if !subtitle.isEmpty { Text(subtitle).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary) }
            }
            Spacer(minLength: 4)
            if let detail { Text(detail).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary) }
        }.frame(minHeight: 56).padding(.vertical, 6).contentShape(Rectangle())
    }
}
private struct ApplePaySetupView: View {
    @State private var notificationStatus = ""
    var body: some View {
        Page {
            Text("Apple Pay 付款后自动记").yubaiFont(YubaiFont.cardTitle)
            Text("1. 打开快捷指令，选择「自动化」，添加「交易」钱包触发器。")
            Text("2. 选择付款卡，设为立即运行，添加「余白 · Apple Pay 记一笔」。")
            Text("3. 商户、金额、卡名分别选择交易的商户、金额、卡；付款时间可选交易日期。")
            #if os(iOS)
            Link("打开快捷指令", destination: URL(string: "shortcuts://")!).buttonStyle(PrimaryButtonStyle())
            Button("开启记账通知") { Task { notificationStatus = await CaptureNotifications.requestPermission() ? "通知已开启" : "通知未开启" } }.buttonStyle(SecondaryButtonStyle())
            if !notificationStatus.isEmpty { Text(notificationStatus).yubaiFont(YubaiFont.caption) }
            #endif
        }.navigationTitle("Apple Pay").yubaiNavigation()
    }
}
private enum CaptureRuleKind { case card, merchant; var title: String { self == .card ? "卡对应的账户" : "商户记到哪个分类" } }
private struct CaptureRulesView: View {
    @Environment(AppStore.self) private var store
    let kind: CaptureRuleKind
    @State private var editing: CaptureRuleSelection?
    private var names: [String] {
        kind == .card ? store.current.preferences.quickCapture.cardAccounts.keys.sorted() : store.current.preferences.quickCapture.merchantCategories.keys.sorted()
    }
    var body: some View {
        List {
            ForEach(names, id: \.self) { name in
                Button { editing = CaptureRuleSelection(name: name) } label: {
                    HStack { Text(name); Spacer(); Text(value(name)).foregroundStyle(YubaiColor.labelSecondary) }.contentShape(Rectangle())
                }.foregroundStyle(YubaiColor.label)
            }.onDelete { offsets in
                let deleted = offsets.map { names[$0] }
                store.update("删除映射") { ledger in
                    for name in deleted {
                        if kind == .card { ledger.preferences.quickCapture.cardAccounts.removeValue(forKey: name) }
                        else { ledger.preferences.quickCapture.merchantCategories.removeValue(forKey: name) }
                    }
                }
            }
        }.navigationTitle(kind.title).yubaiNavigation()
            .overlay { if names.isEmpty { ContentUnavailableView("还没有映射", systemImage: kind == .card ? "creditcard" : "tag") } }
            .toolbar { ToolbarItem(placement: .primaryAction) { Button("添加", systemImage: "plus") { editing = CaptureRuleSelection(name: nil) } } }
            .sheet(item: $editing) { selected in NavigationStack { CaptureRuleEditor(kind: kind, original: selected.name) }.environment(store).appErrors() }
    }
    private func value(_ name: String) -> String {
        if kind == .card { return store.current.accountName(store.current.preferences.quickCapture.cardAccounts[name]) }
        return Classification.displayCategory(store.current.preferences.quickCapture.merchantCategories[name] ?? "")
    }
}
private struct CaptureRuleSelection: Identifiable { var id = UUID(); var name: String? }
private struct CaptureRuleEditor: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let kind: CaptureRuleKind; let original: String?
    @State private var name = ""
    @State private var account: UUID?
    @State private var category = "餐饮"
    private var accounts: [Account] { store.current.accounts.filter { !$0.archived } }
    var body: some View {
        Form {
            TextField(kind == .card ? "卡名" : "商户", text: $name)
            if kind == .card {
                Picker("账户", selection: $account) { ForEach(accounts) { Text($0.name).tag(Optional($0.id)) } }
            } else {
                Picker("分类", selection: $category) { ForEach(ManualBookkeeping.categories(in: store.current, nature: .expense), id: \.self) { Text(Classification.displayCategory($0)).tag($0) } }
            }
            if let original { Button("删除", role: .destructive) { if store.update("删除映射", { remove(original, in: &$0) }) { dismiss() } } }
        }.navigationTitle(original == nil ? "添加映射" : "修改映射")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("好了", action: save).disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (kind == .card && account == nil)) }
            }
            .onAppear {
                name = original ?? ""
                account = original.flatMap { store.current.preferences.quickCapture.cardAccounts[$0] }.flatMap { id in accounts.first { $0.id == id }?.id } ?? accounts.first?.id
                category = original.flatMap { store.current.preferences.quickCapture.merchantCategories[$0] } ?? "餐饮"
            }
    }
    private func remove(_ name: String, in ledger: inout Ledger) {
        if kind == .card { ledger.preferences.quickCapture.cardAccounts.removeValue(forKey: name) }
        else { ledger.preferences.quickCapture.merchantCategories.removeValue(forKey: name) }
    }
    private func save() {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if store.update("保存映射", { ledger in
            if let original { remove(original, in: &ledger) }
            if kind == .card, let account {
                let old = ledger.preferences.quickCapture.cardAccounts.keys.filter { QuickCapture.key($0) == QuickCapture.key(clean) }
                for name in old { ledger.preferences.quickCapture.cardAccounts.removeValue(forKey: name) }
                ledger.preferences.quickCapture.cardAccounts[clean] = account
            } else { try QuickCapture.remember(merchant: clean, category: category, in: &ledger) }
        }) { dismiss() }
    }
}
