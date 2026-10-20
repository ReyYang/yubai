import SwiftUI
import YubaiCore

struct LedgerView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var search = ""; @State private var kind = "全部"; @State private var accountFilter: UUID?
    @State private var selected = Set<UUID>(); @State private var selecting = false; @State private var bulkCategory = "餐饮"
    @State private var showBulk = false; @State private var showDeleted = false; @State private var confirmDelete = false
    @State private var period = "全部时间"; @State private var from = Dates.addDays(-30, to: Date()); @State private var through = Date(); @State private var categoryFilter = "全部分类"
    @State private var searchExpanded: [String] = []
    private var searchTerms: [String] {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        return [q] + searchExpanded
    }
    private func filteredRows() -> [Entry] {
        let bounds = periodBounds; let terms = searchTerms
        return store.sortedEntries.filter { e in
            (showDeleted ? e.deletedAt != nil : e.deletedAt == nil) && (accountFilter == nil || e.accountID == accountFilter || e.otherAccountID == accountFilter) &&
            (bounds.map { e.date >= $0.from && e.date < $0.through } ?? true) && (categoryFilter == "全部分类" || e.category == categoryFilter) &&
            (terms.isEmpty || terms.contains { term in [e.title, e.note, e.category, e.externalID].contains { $0.localizedCaseInsensitiveContains(term) } }) &&
            (kind == "全部" || (kind == "支出" && e.nature == .expense) || (kind == "收入" && e.nature == .income) || (kind == "待明确" && e.nature.uncertain) || (kind == "内部移动" && e.nature.paired))
        }
    }
    private var periodBounds: (from: Date, through: Date)? {
        let today = Dates.day(Date()); let month = Dates.calendar.date(from: Dates.calendar.dateComponents([.year, .month], from: today))!
        switch period {
        case "近 7 天": return (Dates.addDays(-6, to: today), Dates.addDays(1, to: today))
        case "近 30 天": return (Dates.addDays(-29, to: today), Dates.addDays(1, to: today))
        case "本月": return (month, Dates.addMonths(1, to: month))
        case "上月": return (Dates.addMonths(-1, to: month), month)
        case "自定义": return (Dates.day(from), Dates.addDays(1, to: Dates.day(through)))
        default: return nil
        }
    }
    private var emptyTitle: String {
        if !search.isEmpty { return "没有找到匹配记录" }
        return showDeleted ? "回收站是空的" : "这一页，还没有记录"
    }
    var body: some View {
        let rows = filteredRows()
        VStack(spacing: 0) {
            controls
            if rows.isEmpty { EmptyState(showDeleted ? "trash" : "text.book.closed", emptyTitle, "可以更换筛选条件，或导入一份账单。", action: showDeleted ? nil : "导入账单") { store.sheet = .imports }.frame(maxHeight: .infinity) }
            else {
                ScrollView {
                    VStack(alignment: .leading, spacing: YubaiSpace.space8) {
                        Text("\(rows.count) 笔记录" + (selecting ? " · 已选 \(selected.count) 笔" : "")).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                        CardRows(rows) { entry in
                            Button {
                                if selecting { if !selected.insert(entry.id).inserted { selected.remove(entry.id) } }
                                else { store.sheet = .entryDetail(entry.id) }
                            } label: {
                                HStack(spacing: YubaiSpace.space12) {
                                    if selecting { Image(systemName: selected.contains(entry.id) ? "checkmark.circle.fill" : "circle").foregroundStyle(YubaiColor.brand) }
                                    EntryRow(entry: entry)
                                }.contentShape(Rectangle())
                            }.buttonStyle(PressButtonStyle()).accessibilityElement(children: .combine).accessibilityAddTraits(.isButton)
                                .contextMenu { Button("查看记录") { store.sheet = .entryDetail(entry.id) }; if !showDeleted { Button("编辑") { store.sheet = .entry(entry) } } }
                        }
                    }.padding(.horizontal, YubaiSpace.space18).padding(.bottom, YubaiSpace.space24)
                }
            }
            if selecting { bulkBar(rows) }
        }.background(YubaiColor.canvas).navigationTitle(showDeleted ? "回收站" : "账本").yubaiNavigation()
            .searchable(text: $search, prompt: "搜索用途、商户、分类或单号")
            .onChange(of: search) { _, value in Task { await refreshSearchExpansion(value) } }
            .toolbar {
                ToolbarItemGroup {
                    Button(selecting ? "完成选择" : "批量") { selecting.toggle(); selected.removeAll() }.disabled(rows.isEmpty && !selecting)
                    Menu { Button("导入账单") { store.sheet = .imports }; Button(showDeleted ? "返回账本" : "回收站") { showDeleted.toggle(); selected.removeAll() }; Button("分类与规则") { store.sheet = .rules } } label: { Image(systemName: "ellipsis.circle") }
                    Button { store.sheet = .entry(nil) } label: { Image(systemName: "plus") }.accessibilityLabel("记一笔")
                }
            }
            .sheet(isPresented: $showBulk) { NavigationStack { BulkEditView(ids: selected) { selected.removeAll(); selecting = false; showBulk = false } }.environment(store).appErrors().frame(minWidth: 340, minHeight: 360) }
            .confirmationDialog("将选中的 \(selected.count) 笔移至回收站？可以恢复。", isPresented: $confirmDelete) { Button("移至回收站", role: .destructive) { store.update("移至回收站") { l in for i in l.entries.indices where selected.contains(l.entries[i].id) { l.entries[i].deletedAt = Date() } }; selected.removeAll(); selecting = false } }
    }
    var controls: some View {
        VStack(spacing: YubaiSpace.space12) {
            if textSize.isAccessibilitySize {
                Menu {
                    Picker("交易类型", selection: $kind) { ForEach(["全部", "支出", "收入", "待明确", "内部移动"], id: \.self) { Text($0) } }
                    Picker("时间", selection: $period) { ForEach(["全部时间", "近 7 天", "近 30 天", "本月", "上月", "自定义"], id: \.self) { Text($0) } }
                    Picker("分类", selection: $categoryFilter) { Text("全部分类").tag("全部分类"); ForEach(store.entryCategories, id: \.self) { Text($0) } }
                    Picker("账户", selection: $accountFilter) { Text("全部账户").tag(Optional<UUID>.none); ForEach(store.current.accounts) { Text($0.name).tag(Optional($0.id)) } }
                } label: { Label("筛选：" + kind, systemImage: "line.3.horizontal.decrease").frame(maxWidth: .infinity, alignment: .leading) }
                if period == "自定义" { DatePicker("从", selection: $from, displayedComponents: .date); DatePicker("至", selection: $through, in: from..., displayedComponents: .date) }
            } else {
            Picker("交易类型", selection: $kind) { ForEach(["全部", "支出", "收入", "待明确", "内部移动"], id: \.self) { Text($0) } }.pickerStyle(.segmented)
            HStack {
                Menu { ForEach(["全部时间", "近 7 天", "近 30 天", "本月", "上月", "自定义"], id: \.self) { item in Button(item) { period = item } } } label: { Label(period, systemImage: "calendar") }
                Spacer()
                Menu { Button("全部分类") { categoryFilter = "全部分类" }; ForEach(store.entryCategories, id: \.self) { item in Button(item) { categoryFilter = item } } } label: { Text(categoryFilter) }
            }.yubaiFont(YubaiFont.callout)
            if period == "自定义" { HStack { DatePicker("从", selection: $from, displayedComponents: .date); DatePicker("至", selection: $through, in: from..., displayedComponents: .date) }.yubaiFont(YubaiFont.caption) }
            HStack { Menu { Button("全部账户") { accountFilter = nil }; ForEach(store.current.accounts) { a in Button(a.name) { accountFilter = a.id } } } label: { Label(accountFilter == nil ? "全部账户" : store.current.accountName(accountFilter), systemImage: "line.3.horizontal.decrease") }; Spacer(); if showDeleted { Text("删除记录不会因重新导入而复活").yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary) } else { Text("支持逐笔编辑与批量纠正").yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary) } }
            }
        }.padding(YubaiSpace.space16).onChange(of: kind) { _, _ in selected.removeAll() }.onChange(of: accountFilter) { _, _ in selected.removeAll() }.onChange(of: search) { _, _ in selected.removeAll() }.onChange(of: period) { _, _ in selected.removeAll() }.onChange(of: categoryFilter) { _, _ in selected.removeAll() }.onChange(of: from) { _, value in if through < value { through = value }; selected.removeAll() }.onChange(of: through) { _, _ in selected.removeAll() }
    }
    func bulkBar(_ rows: [Entry]) -> some View {
        HStack(spacing: YubaiSpace.space16) { Button(selected.count == rows.count ? "取消全选" : "全选") { selected = selected.count == rows.count ? [] : Set(rows.map(\.id)) }; Spacer(); if showDeleted { Button("恢复所选") { store.update("恢复记录") { l in for i in l.entries.indices where selected.contains(l.entries[i].id) { l.entries[i].deletedAt = nil } }; selected.removeAll(); selecting = false }.disabled(selected.isEmpty) } else { Button("整理") { showBulk = true }.disabled(selected.isEmpty); Button("删除", role: .destructive) { confirmDelete = true }.disabled(selected.isEmpty) } }.yubaiFont(YubaiFont.callout).padding(YubaiSpace.space18).background(YubaiColor.raised).yubaiShadow(YubaiShadow.float)
    }
    @MainActor func refreshSearchExpansion(_ query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let backend = IntelligenceRuntime.backend(for: store.current.preferences) else {
            searchExpanded = []
            return
        }
        do {
            searchExpanded = try await backend.expandSearchQuery(trimmed)
        } catch {
            searchExpanded = []
        }
    }
}

struct EntryDetailView: View {
    @Environment(AppStore.self) private var store; @Environment(\.dismiss) private var dismiss
    var entryID: UUID
    @State private var edit = false; @State private var delete = false; @State private var disconnect = false
    private var entry: Entry? { store.current.entries.first { $0.id == entryID } }
    var body: some View {
        Group {
            if let e = entry {
                Page {
                    VStack(alignment: .leading, spacing: YubaiSpace.space12) { Text(e.title).yubaiFont(YubaiFont.lead); AmountLabel(cents: e.amount, role: .display, sign: e.nature.inflow ? .inflow : .outflow, fractionDigits: 2); Text(e.nature.label).yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelMuted) }
                    ledgerInformation(e)
                    sourceInformation(e)
                    associations(e)
                    entryActions(e)
                }
                .sheet(isPresented: $edit) { NavigationStack { EntryEditor(entry: e) }.environment(store).appErrors().frame(minWidth: 340, minHeight: 540) }
                .confirmationDialog("删除后可在回收站恢复", isPresented: $delete) { Button("移至回收站", role: .destructive) { store.update("移至回收站") { l in if let i = l.entries.firstIndex(where: { $0.id == entryID }) { l.entries[i].deletedAt = Date() } }; dismiss() } }
                .confirmationDialog("确认解除关联？原来的安排将重新显示待完成。", isPresented: $disconnect) { Button("解除关联") { store.update("解除安排关联") { l in if let i = l.entries.firstIndex(where: { $0.id == entryID }) { l.entries[i].planID = nil; l.entries[i].occurrence = nil; l.entries[i].rentID = nil; l.entries[i].rentPeriod = nil; l.entries[i].personalExpense = nil; l.entries[i].userEdited = true } } } }
            } else { EmptyState("doc.questionmark", "记录已不存在", "可能已从备份恢复了另一个账本。") }
        }.navigationTitle("记录详情").yubaiNavigation().toolbar { CloseButton() }
    }
    private func ledgerInformation(_ e: Entry) -> some View {
        Card(style: .list) { VStack(alignment: .leading, spacing: 0) {
            SectionHeading(title: "账本信息").padding(.vertical, YubaiSpace.space12)
            detailRow("时间", Dates.text(e.date, time: true))
            detailRow("账户", store.current.accountName(e.accountID))
            if let other = e.otherAccountID { detailRow("关联账户", store.current.accountName(other)) }
            detailRow("分类", e.category, separator: !e.note.isEmpty)
            if !e.note.isEmpty { Text(e.note).yubaiFont(YubaiFont.body).padding(.vertical, YubaiSpace.space12) }
        } }
    }
    private func sourceInformation(_ e: Entry) -> some View {
        Card(style: .list) { VStack(alignment: .leading, spacing: 0) {
            SectionHeading(title: "来源与依据").padding(.vertical, YubaiSpace.space12)
            detailRow("来源", e.source)
            if let row = e.sourceRow { detailRow("原文件行号", String(row)) }
            if !e.externalID.isEmpty { detailRow("交易单号", e.externalID).textSelection(.enabled) }
            Text(e.classificationReason).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary).padding(.vertical, YubaiSpace.space12)
            if e.userEdited { Label("你的修改优先于重新导入", systemImage: "person.crop.circle.badge.checkmark").yubaiFont(YubaiFont.caption).padding(.bottom, YubaiSpace.space12) }
        } }
    }
    private func detailRow(_ title: String, _ value: String, separator: Bool = true) -> some View {
        VStack(spacing: 0) {
            LabeledContent { Text(value).foregroundStyle(YubaiColor.labelMuted) } label: { Text(title) }.yubaiFont(YubaiFont.row).frame(minHeight: YubaiSize.buttonHeight)
            if separator { Rectangle().fill(YubaiColor.separator).frame(height: 1).accessibilityHidden(true) }
        }
    }
    @ViewBuilder private func associations(_ e: Entry) -> some View {
        if e.deletedAt == nil && e.otherAccountID == nil && e.planID == nil && e.rentID == nil { Card(style: .list) { NavigationLink("关联另一账户的转账记录") { TransferLinkView(entryID: e.id) }.yubaiFont(YubaiFont.row).frame(minHeight: YubaiSize.buttonHeight) } }
        if let merged = e.mergedIntoID { Card { VStack(alignment: .leading, spacing: YubaiSpace.space12) { NavigationLink("这笔来源已合并，查看完整转账") { EntryDetailView(entryID: merged) }; Text("它是另一笔转账的原始证据，不能单独恢复为重复记录。撤销合并请用上一步撤销或本地恢复历史。").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary) }.yubaiFont(YubaiFont.row) } }
        if let rentID = e.rentID { Card { VStack(alignment: .leading, spacing: YubaiSpace.space8) { Text("已关联：" + (store.current.rents.first { $0.id == rentID }?.title ?? "房租安排")).yubaiFont(YubaiFont.row); if let period = e.rentPeriod { Text("对应期次：\(Dates.text(period))").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary) } } } }
        if let planID = e.planID { Card { VStack(alignment: .leading, spacing: YubaiSpace.space8) { Text("已关联：" + (store.current.plans.first { $0.id == planID }?.title ?? "资金安排")).yubaiFont(YubaiFont.row); if let date = e.occurrence { Text("对应期次：\(Dates.text(date))").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary) } } } }
    }
    @ViewBuilder private func entryActions(_ e: Entry) -> some View {
        if e.deletedAt == nil && (e.planID != nil || e.rentID != nil) { Card { VStack(alignment: .leading, spacing: YubaiSpace.space12) { Button("解除与安排的关联") { disconnect = true }.yubaiFont(YubaiFont.row).frame(minHeight: YubaiSize.tapMin); Text("解除后，这一期会重新显示待完成；租金付款恢复按全额计入个人消费，实际账户余额不变。").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary) } } }
        if e.deletedAt == nil {
            Button("编辑记录") { edit = true }.buttonStyle(PrimaryButtonStyle())
            Button("移至回收站", role: .destructive) { delete = true }.frame(minHeight: YubaiSize.buttonHeight)
        } else {
            Text("这笔记录已在回收站，不计入任何汇总。").yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary)
            if e.mergedIntoID == nil { Button("恢复记录") { if store.update("恢复记录", { l in if let i = l.entries.firstIndex(where: { $0.id == entryID }) { l.entries[i].deletedAt = nil } }) { dismiss() } }.buttonStyle(SecondaryButtonStyle()) }
        }
    }

}

struct TransferLinkView: View {
    @Environment(AppStore.self) private var store; @Environment(\.dismiss) private var dismiss
    var entryID: UUID
    @State private var nature = Nature.transfer; @State private var candidate: Entry?
    private var original: Entry? { store.current.activeEntries.first { $0.id == entryID } }
    private var matches: [Entry] {
        guard let e = original else { return [] }
        return store.current.activeEntries.filter { $0.id != e.id && $0.accountID != e.accountID && $0.amount == e.amount && $0.nature.inflow != e.nature.inflow && $0.otherAccountID == nil && $0.planID == nil && $0.rentID == nil }.sorted { abs($0.date.timeIntervalSince(e.date)) < abs($1.date.timeIntervalSince(e.date)) }
    }
    var body: some View {
        Page {
            Text("选择同一笔资金在另一账户的记录。金额相同只是线索，请核对用途与日期。合并后两边余额各变化一次，原始来源仍保留。").yubaiFont(YubaiFont.body).foregroundStyle(YubaiColor.labelMuted)
            Card { Picker("这笔钱的性质", selection: $nature) { ForEach(Nature.allCases.filter(\.paired)) { Text($0.label).tag($0) } }.yubaiFont(YubaiFont.row) }
            SectionHeading(title: "同金额、反方向的候选")
            if matches.isEmpty { Text("没有合适的另一侧记录。可以在编辑中直接指定另一账户，但不要同时保留另一笔独立记录。").yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelMuted) }
            CardRows(matches) { e in Button { candidate = e } label: { EntryRow(entry: e) }.buttonStyle(PressButtonStyle()) }
        }.navigationTitle("关联资金移动").yubaiNavigation()
            .confirmationDialog("确认这两笔是同一笔资金移动？合并后两侧保持各自的实际入账日期。", isPresented: Binding(get: { candidate != nil }, set: { if !$0 { candidate = nil } })) { Button("确认关联") { guard let e = candidate else { return }; if store.update("合并资金移动", { l in try LedgerOperations.mergeTransfer(entryID, e.id, nature: nature, in: &l) }) { dismiss() }; candidate = nil } }
    }
}

struct BulkEditView: View {
    @Environment(AppStore.self) private var store; @Environment(\.dismiss) private var dismiss
    let ids: Set<UUID>; var onDone: () -> Void
    @State private var category = "保持不变"; @State private var nature: Nature?
    var body: some View {
        Form {
            Section("已选 \(ids.count) 笔") {
                Picker("分类", selection: $category) { Text("保持不变").tag("保持不变"); ForEach(store.current.categories) { Text($0.name).tag($0.name) } }
                Picker("资金性质", selection: $nature) { Text("保持不变").tag(Nature?.none); ForEach(Nature.allCases.filter { !$0.paired }) { Text($0.label).tag(Optional($0)) } }
            }.listRowBackground(YubaiColor.card).listRowSeparatorTint(YubaiColor.separator)
            Section { Text("金额与账户保留。修改性质时，所选记录必须同方向且尚未关联安排或其他交易；内部移动需要逐笔关联两边账户。保存后可撤销。").yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary) }.listRowBackground(YubaiColor.card).listRowSeparatorTint(YubaiColor.separator)
        }.editorForm().navigationTitle("批量整理").yubaiNavigation()
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("应用") { if store.update("批量整理", { l in try LedgerOperations.bulkEdit(ids, category: category == "保持不变" ? nil : category, nature: nature, in: &l) }) { onDone() } }.foregroundStyle(YubaiColor.brandInk).disabled(category == "保持不变" && nature == nil) } }
    }
}
