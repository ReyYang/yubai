import SwiftUI
import YubaiCore

struct QuickCaptureSettingsView: View {
    @Environment(AppStore.self) private var store
    @State private var notificationStatus = ""
    private var recent: [Entry] { store.recentCaptures }
    var body: some View {
        Page {
            HStack(alignment: .top, spacing: YubaiSpace.gapSection) {
                statistic("近 7 天", count: recent.count)
                Spacer()
                statistic("没打开 App", count: recent.filter { $0.quickCapture?.withoutOpeningApp == true }.count)
            }
            Card {
                VStack(alignment: .leading, spacing: YubaiSpace.gapGroup) {
                    HStack(spacing: YubaiSpace.space8) {
                        Text("Apple Pay 付完就记").yubaiFont(YubaiFont.rowTitle)
                        Spacer()
                        #if os(iOS)
                        Button {
                            Task { notificationStatus = await CaptureNotifications.requestPermission() ? "通知已开启" : "通知没开" }
                        } label: { Image(systemName: "bell").frame(width: YubaiSize.tapMin, height: YubaiSize.tapMin) }
                            .accessibilityLabel("开启记账通知")
                        #endif
                    }
                    Link("添加到快捷指令", destination: URL(string: "shortcuts://")!)
                        .buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("addCaptureShortcut")
                        .accessibilityHint("打开快捷指令 App，可添加余白的 Apple Pay 记一笔动作；仍需在快捷指令中配置交易自动化")
                    if !notificationStatus.isEmpty { Text(notificationStatus).yubaiFont(YubaiFont.caption) }
                }
            }
            Card(style: .list) {
                VStack(spacing: YubaiSpace.none) {
                    NavigationLink { CaptureRulesView(kind: .card) } label: {
                        line("卡对应的账户", detail: "\(store.preferences.quickCapture.cardAccounts.count) 张", navigates: true)
                    }
                    EntryFormDivider()
                    NavigationLink { CaptureRulesView(kind: .merchant) } label: {
                        line("商户记到哪个分类", detail: "\(store.current.classificationMemory.count) 条", navigates: true)
                    }
                }
            }
            VStack(alignment: .leading, spacing: YubaiSpace.gapHeading) {
                SectionHeading(title: "其他入口")
                Card(style: .list) {
                    VStack(spacing: YubaiSpace.none) {
                        Link(destination: URL(string: "shortcuts://")!) {
                            line("Siri", detail: "「余白记一笔，午饭 32」", thumbnail: .siri, navigates: true)
                        }.accessibilityHint("打开快捷指令 App，查看余白的动作")
                        EntryFormDivider()
                        line("小组件", thumbnail: .widget)
                            .accessibilityLabel("锁屏和主屏小组件，设置图示暂不可用")
                        EntryFormDivider()
                        line("控制中心", thumbnail: .control)
                            .accessibilityLabel("控制中心和操作按钮，设置图示暂不可用")
                        EntryFormDivider()
                        line("轻点背面", thumbnail: .backTap)
                            .accessibilityLabel("轻点背面截图记，设置图示暂不可用")
                    }
                }
            }
            Card(style: .list) {
                NavigationLink { ImportView() } label: { line("支付宝、微信付款", detail: "截图记", navigates: true) }
            }
        }.buttonStyle(PressButtonStyle()).navigationTitle("快速记账").yubaiNavigation()
    }
    private func statistic(_ title: String, count: Int) -> some View {
        VStack(alignment: .leading, spacing: YubaiSpace.space4) {
            Text(title).yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary)
            Text("\(count) 笔").yubaiFont(YubaiFont.amountAccount)
        }
    }
    private func line(_ title: String, detail: String? = nil, thumbnail: CaptureThumbnail.Kind? = nil, navigates: Bool = false) -> some View {
        HStack(spacing: YubaiSpace.gapGroup) {
            if let thumbnail { CaptureThumbnail(kind: thumbnail) }
            Text(title).yubaiFont(YubaiFont.row)
            Spacer(minLength: YubaiSpace.space4)
            if let detail { Text(detail).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary) }
            if navigates {
                Image(systemName: "chevron.right").yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary).accessibilityHidden(true)
            } else {
                Color.clear.frame(width: YubaiFont.meta.size, height: YubaiFont.meta.lineHeight).accessibilityHidden(true)
            }
        }.padding(.vertical, YubaiSpace.space4).frame(maxWidth: .infinity, minHeight: YubaiSize.rowDouble, alignment: .leading).contentShape(Rectangle())
    }
}

private struct CaptureThumbnail: View {
    enum Kind { case siri, widget, control, backTap }
    let kind: Kind
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: YubaiRadius.control).fill(YubaiColor.canvas)
            switch kind {
            case .siri:
                AssistantMark(size: YubaiSize.barMax)
            case .widget:
                VStack(alignment: .leading, spacing: YubaiSpace.space2) {
                    Capsule().fill(YubaiColor.labelSecondary).frame(width: YubaiSpace.gapGroup, height: YubaiSpace.space2)
                    Capsule().fill(YubaiColor.label).frame(width: YubaiSpace.insetCard, height: YubaiSpace.space4)
                    Capsule().fill(YubaiColor.brand).frame(height: YubaiSpace.space8)
                }.padding(YubaiSpace.space8)
            case .control:
                Image(systemName: "plus").yubaiFont(YubaiFont.caption)
                    .foregroundStyle(YubaiColor.onBrand).frame(width: YubaiSize.barMax, height: YubaiSize.barMax)
                    .background(YubaiColor.brand, in: Circle())
            case .backTap:
                Image(systemName: "iphone").yubaiFont(YubaiFont.lead).foregroundStyle(YubaiColor.label)
                    .overlay { Circle().fill(YubaiColor.brand).frame(width: YubaiSpace.space4, height: YubaiSpace.space4) }
            }
        }.frame(width: YubaiSize.rowIcon, height: YubaiSize.rowIcon).accessibilityHidden(true)
    }
}
private enum CaptureRuleKind { case card, merchant; var title: String { self == .card ? "卡对应的账户" : "商户记到哪个分类" } }
private struct CaptureRulesView: View {
    @Environment(AppStore.self) private var store
    let kind: CaptureRuleKind
    @State private var editing: CaptureRuleSelection?
    private var names: [String] {
        kind == .card ? store.preferences.quickCapture.cardAccounts.keys.sorted() : store.current.classificationMemory.keys.sorted()
    }
    var body: some View {
        List {
            ForEach(names, id: \.self) { name in
                Button { editing = CaptureRuleSelection(name: name) } label: {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: YubaiSpace.gapGroup) { Text(kind == .card ? name : CategoryNamespace.split(name).name).lineLimit(1).fixedSize(); Spacer(); Text(value(name)).lineLimit(1).fixedSize().foregroundStyle(YubaiColor.labelSecondary) }
                        VStack(alignment: .leading, spacing: YubaiSpace.space8) { Text(kind == .card ? name : CategoryNamespace.split(name).name).lineLimit(1).fixedSize(); Text(value(name)).lineLimit(1).fixedSize().foregroundStyle(YubaiColor.labelSecondary) }
                    }.contentShape(Rectangle())
                }.foregroundStyle(YubaiColor.label)
            }.onDelete { offsets in
                let deleted = offsets.map { names[$0] }
                store.update("删除映射") { ledger in
                    for name in deleted {
                        if kind == .card { ledger.preferences.quickCapture.cardAccounts.removeValue(forKey: name) }
                        else { ledger.classificationMemory.removeValue(forKey: name) }
                    }
                }
            }
        }.navigationTitle(kind.title).yubaiNavigation()
            .overlay { if names.isEmpty { EmptyState(kind == .card ? "creditcard" : "tag", "还没有映射", action: "添加", onAction: { editing = CaptureRuleSelection(name: nil) }) } }
            .toolbar { ToolbarItem(placement: .primaryAction) { Button("添加", systemImage: "plus") { editing = CaptureRuleSelection(name: nil) } } }
            .sheet(item: $editing) { selected in NavigationStack { CaptureRuleEditor(kind: kind, original: selected.name) }.environment(store).appErrors().yubaiSheetBackground() }
    }
    private func value(_ name: String) -> String {
        if kind == .card { return store.accountName(store.preferences.quickCapture.cardAccounts[name]) }
        let choice = CategoryAssignment(path: store.current.classificationMemory[name] ?? "")
        let resolved = store.current.categoryAssignment(category: choice.category, subcategory: choice.subcategory, income: captureRuleIncome(name, ledger: store.current))
        return Classification.displayCategory(resolved.category) + (resolved.subcategory.map { " · " + $0 } ?? "")
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
    @State private var income = false
    private var accounts: [Account] { store.accounts.filter { !$0.archived } }
    var body: some View {
        Form {
            TextField(kind == .card ? "卡名" : "商户", text: $name)
            if kind == .card {
                Picker("账户", selection: $account) { ForEach(accounts) { Text($0.name).tag(Optional($0.id)) } }
            } else {
                CategoryPickerField(income: income,
                                    selection: CategoryAssignment(path: category), allowsDirectionChange: true,
                                    identifier: "captureRuleCategory", directionChanged: { income = $0 }) { category = $0.path }
            }
            if let original { Button("删掉") { if store.update("删除映射", { remove(original, in: &$0) }) { dismiss() } }.buttonStyle(DestructiveButtonStyle()) }
        }.navigationTitle(original == nil ? "添加映射" : "修改映射")
            .manualSheetHeader(original == nil ? "添加映射" : "修改映射", enabled: !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (kind != .card || account != nil), action: save)
            .onAppear {
                name = original.map { kind == .card ? $0 : CategoryNamespace.split($0).name } ?? ""
                let direction = original.map { captureRuleIncome($0, ledger: store.current) } ?? false
                income = direction
                account = original.flatMap { store.preferences.quickCapture.cardAccounts[$0] }.flatMap { id in accounts.first { $0.id == id }?.id } ?? accounts.first?.id
                category = original.flatMap { store.current.classificationMemory[$0] }.map { raw in
                    let choice = CategoryAssignment(path: raw)
                    return store.current.categoryAssignment(category: choice.category, subcategory: choice.subcategory, income: direction).path
                } ?? "餐饮"
            }
    }
    private func remove(_ name: String, in ledger: inout Ledger) {
        if kind == .card { ledger.preferences.quickCapture.cardAccounts.removeValue(forKey: name) }
        else { ledger.classificationMemory.removeValue(forKey: name) }
    }
    private func save() {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if store.update("保存映射", { ledger in
            if let original { remove(original, in: &ledger) }
            if kind == .card, let account {
                let old = ledger.preferences.quickCapture.cardAccounts.keys.filter { QuickCapture.cardKey($0) == QuickCapture.cardKey(clean) }
                for name in old { ledger.preferences.quickCapture.cardAccounts.removeValue(forKey: name) }
                ledger.preferences.quickCapture.cardAccounts[clean] = account
            } else { try QuickCapture.remember(merchant: clean, category: category, income: income, in: &ledger) }
        }) { dismiss() }
    }
}

private func captureRuleIncome(_ key: String, ledger: Ledger) -> Bool {
    if let income = CategoryNamespace.split(key).income { return income }
    let value = CategoryAssignment(path: ledger.classificationMemory[key] ?? "")
    let expense = ledger.categoryAssignment(category: value.category, subcategory: value.subcategory, income: false)
    return !ledger.categories.contains { $0.name == expense.category && !$0.income }
}
