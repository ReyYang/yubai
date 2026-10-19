import SwiftUI
import YubaiCore

struct PlansView: View {
    @Environment(AppStore.self) private var store
    @State private var filter = "接下来"; @State private var occurrenceToLink: Occurrence?
    var occurrences: [Occurrence] { store.funds.occurrences }
    var body: some View {
        Page {
            VStack(alignment: .leading, spacing: 8) { Text("先照顾必须的，\n再留给想要的。").font(.system(.title, design: .serif).weight(.medium)); Text("安排跟随日期和实际发生的收支，不按月清零。").font(.callout).foregroundStyle(.secondary) }
            Picker("内容", selection: $filter) { ForEach(["接下来", "房租分摊", "我的目标", "全部约定"], id: \.self) { Text($0) } }.pickerStyle(.segmented)
            switch filter {
            case "房租分摊": rents
            case "我的目标": goals
            case "全部约定": allPlans
            default: upcoming
            }
        }.navigationTitle("资金安排").toolbar { Menu { Button("收入或付款") { store.sheet = .plan(nil) }; Button("房租分摊") { store.sheet = .rent(nil) }; Button("储蓄目标") { store.sheet = .goal(nil) } } label: { Label("添加", systemImage: "plus") } }
            .sheet(item: $occurrenceToLink) { item in NavigationStack { LinkOccurrenceView(occurrence: item) }.environment(store).appErrors().frame(minWidth: 340, minHeight: 480) }
    }
    var upcoming: some View {
        VStack(spacing: 18) {
            if occurrences.isEmpty { Card { EmptyState("calendar.badge.checkmark", "为未来留个位置", "添加房租、信用还款、订阅或已知收入。它们会自动出现在资金预测里。", action: "添加安排") { store.sheet = .plan(nil) } } }
            ForEach(occurrences) { item in
                Card {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 13) { IconTile(symbol: item.rentID != nil ? "house" : (item.inflow ? "arrow.down.left" : "calendar")); VStack(alignment: .leading, spacing: 5) { Text(item.title).font(.headline); Text(Dates.text(item.date) + (item.overdue ? " · 已到期" : "")).font(.caption).foregroundStyle(item.overdue ? YubaiTheme.amber : .secondary) }; Spacer(); Text((item.inflow ? "+" : "−") + Money.text(item.amount)).font(.system(.title3, design: .rounded).weight(.medium)) }
                        HStack { Text(item.inflow ? "预计到账，尚未计入可动用资金" : "已纳入资金安排").font(.caption).foregroundStyle(.secondary); Spacer(); Menu(item.inflow ? "登记到账" : "登记付款") { Button("新建一笔真实记录") { newEntry(item) }; Button("关联已有记录") { occurrenceToLink = item } } }
                    }
                }
            }
        }
    }
    var rents: some View {
        VStack(spacing: 18) {
            if store.current.rents.isEmpty { Card { EmptyState("house.and.flag", "月月收，按季付，也能理清", "记录双方承担与真实付款日，分别看已收分摊和需要准备的租金。", action: "建立房租分摊") { store.sheet = .rent(nil) } } }
            ForEach(store.current.rents) { rent in Button { store.sheet = .rentDetail(rent.id) } label: { Card { VStack(alignment: .leading, spacing: 16) { HStack { IconTile(symbol: "house"); Text(rent.title).font(.headline); Spacer(); Image(systemName: "chevron.right").foregroundStyle(.tertiary) }; HStack { VStack(alignment: .leading, spacing: 6) { Text("每月总额").font(.caption).foregroundStyle(.secondary); AmountLabel(cents: rent.monthlyTotal) }; Spacer(); VStack(alignment: .trailing, spacing: 6) { Text("我承担").font(.caption).foregroundStyle(.secondary); AmountLabel(cents: rent.personalShare) } }; Text("每 \(rent.monthsPerPayment) 个月付一次 · " + (rent.active ? "持续跟踪" : "已暂停")).font(.caption).foregroundStyle(.secondary) } } }.buttonStyle(.plain) }
            Button { store.sheet = .rent(nil) } label: { Label("添加房租约定", systemImage: "plus") }.padding(.top, 6)
        }
    }
    var goals: some View {
        VStack(spacing: 18) {
            if store.current.goals.isEmpty { Card { EmptyState("leaf", "给重要的事，留出余白", "一场旅行、一段学习，或者更踏实的应急储备。由你决定现在为它保留多少。", action: "添加目标") { store.sheet = .goal(nil) } } }
            ForEach(store.current.goals) { goal in
                Card {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack {
                            Text(goal.title).font(.headline)
                            Spacer()
                            Menu {
                                Button("调整目标") { store.sheet = .goal(goal) }
                                Button("释放预留并移除", role: .destructive) {
                                    store.update("移除目标") { $0.goals.removeAll { $0.id == goal.id } }
                                }
                            } label: { Image(systemName: "ellipsis") }
                        }
                        HStack(alignment: .firstTextBaseline) {
                            AmountLabel(cents: goal.reserved)
                            Text("/ " + Money.text(goal.target)).font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Text("\(Int(Double(goal.reserved) / Double(max(1, goal.target)) * 100))%").font(.caption.monospacedDigit())
                        }
                        ProgressView(value: Double(goal.reserved), total: Double(max(1, goal.target))).tint(YubaiTheme.jade)
                        if !goal.note.isEmpty { Text(goal.note).font(.callout).foregroundStyle(.secondary) }
                        if let date = goal.dueDate { Text("期待在 \(Dates.text(date))").font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
            Button { store.sheet = .goal(nil) } label: { Label("添加目标", systemImage: "plus") }
        }
    }
    var allPlans: some View {
        VStack(spacing: 15) {
            ForEach(store.current.plans) { plan in
                Card {
                    HStack(spacing: 14) {
                        IconTile(symbol: plan.inflow ? "arrow.down.left" : "calendar")
                        VStack(alignment: .leading, spacing: 6) {
                            Text(plan.title).font(.headline)
                            Text("\(plan.frequency.label) · \(Money.text(plan.amount))" + (plan.active ? "" : " · 已暂停")).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Menu {
                            Button("编辑") { store.sheet = .plan(plan) }
                            Button(plan.active ? "停止跟踪并解除预留" : "继续跟踪约定") {
                                store.update("调整安排状态") { l in
                                    if let i = l.plans.firstIndex(where: { $0.id == plan.id }) { l.plans[i].active.toggle() }
                                }
                            }
                        } label: { Image(systemName: "ellipsis.circle") }
                    }
                }
            }
            if store.current.plans.isEmpty { EmptyState("calendar", "还没有约定", "已经完成的记录会保留，暂停只影响未来安排。") }
            Button("添加收入或付款") { store.sheet = .plan(nil) }
        }
    }
    func newEntry(_ item: Occurrence) {
        guard let cash = store.current.accounts.first(where: { !$0.archived && ($0.kind == .cash || $0.kind == .bank) }) else { store.error = "先添加一个收付款账户。"; return }
        let plan = store.current.plans.first { $0.id == item.planID }
        let nature = plan?.nature ?? (item.inflow ? .contribution : .expense)
        var e = Entry(date: min(Date(), item.date), amount: item.amount, nature: nature, accountID: nature == .repayment ? cash.id : (plan?.accountID ?? cash.id), title: item.title, category: plan?.category ?? "居住")
        if nature == .repayment { e.otherAccountID = plan?.accountID }
        e.planID = item.planID; e.occurrence = item.date; e.rentID = item.rentID; e.rentPeriod = item.rentID != nil ? (item.rentMonth ?? item.date) : nil
        store.sheet = .entry(e)
    }
}

struct LinkOccurrenceView: View {
    @Environment(AppStore.self) private var store; @Environment(\.dismiss) private var dismiss
    var occurrence: Occurrence
    @State private var search = ""
    var rows: [Entry] { store.current.activeEntries.filter { e in
        guard e.planID == nil, e.rentID == nil, e.relatedEntryID == nil, search.isEmpty || e.title.localizedCaseInsensitiveContains(search) else { return false }
        if let p = store.current.plans.first(where: { $0.id == occurrence.planID }), p.nature == .repayment { return e.nature == .repayment && e.otherAccountID == p.accountID }
        return !e.nature.paired && (occurrence.inflow ? [.income, .unknownIn, .contribution].contains(e.nature) : [.expense, .unknownOut].contains(e.nature))
    }.sorted { $0.date > $1.date } }
    var body: some View {
        List { Section { Text("把已导入的真实记录关联到“\(occurrence.title)”。不会创建第二笔记录或再次扣款。").font(.callout).foregroundStyle(.secondary) }; Section("可关联的记录") { ForEach(rows) { e in Button { link(e) } label: { EntryRow(entry: e) }.buttonStyle(.plain) } } }.searchable(text: $search, prompt: "搜索记录").navigationTitle("关联已有记录").toolbar { CloseButton() }
    }
    func link(_ entry: Entry) {
        if store.update("关联资金安排", { l in
            guard let i = l.entries.firstIndex(where: { $0.id == entry.id }) else { return }
            guard entry.amount <= occurrence.amount else { throw YubaiError.invalid("这笔金额超过本期剩余金额，请先核对是否包含了其他用途或多个期次。") }
            if let p = l.plans.first(where: { $0.id == occurrence.planID }), p.nature == .repayment, entry.nature != .repayment { throw YubaiError.invalid("请先把这笔记录明确为信用还款，并关联对应信用账户。") }
            l.entries[i].planID = occurrence.planID; l.entries[i].occurrence = occurrence.date
            if let p = l.plans.first(where: { $0.id == occurrence.planID }) { l.entries[i].nature = p.nature }
            l.entries[i].rentID = occurrence.rentID; l.entries[i].rentPeriod = occurrence.rentID != nil ? (occurrence.rentMonth ?? occurrence.date) : nil
            if occurrence.rentID != nil { l.entries[i].nature = occurrence.inflow ? .contribution : .expense; l.entries[i].category = occurrence.inflow ? "房租分摊" : "居住"; var e = l.entries[i]; LedgerOperations.recordPersonalShare(&e, ledger: l); l.entries[i] = e }
            l.entries[i].userEdited = true
        }) { dismiss() }
    }
}

struct RentDetailView: View {
    @Environment(AppStore.self) private var store
    var rentID: UUID
    @State private var editor: Entry?; @State private var editRent = false; @State private var linkMonth: Date?
    var rent: Rent? { store.current.rents.first { $0.id == rentID } }
    var body: some View {
        Group {
            if let r = rent {
                List {
                    Section {
                        HStack { VStack(alignment: .leading, spacing: 8) { Text("每月应收分摊").font(.caption).foregroundStyle(.secondary); AmountLabel(cents: r.monthlyTotal - r.personalShare, large: true) }; Spacer() }.padding(.vertical, 10)
                        LabeledContent("每月总租金", value: Money.text(r.monthlyTotal)); LabeledContent("我每月承担", value: Money.text(r.personalShare)); LabeledContent("付款约定", value: "每 \(r.monthsPerPayment) 个月 · " + Money.text(r.monthlyTotal * Int64(r.monthsPerPayment)))
                        Text("未收分摊不是可花的钱。下次向房东付款的全额已计入资金安排。").font(.caption).foregroundStyle(.secondary)
                    }
                    Section("分摊收款 · 按月份核对") {
                        ForEach(months(r), id: \.self) { month in monthRow(r, month) }
                    }
                    Section("已关联记录") { ForEach(store.current.activeEntries.filter { $0.rentID == r.id }.sorted { $0.date > $1.date }) { entry in NavigationLink { EntryDetailView(entryID: entry.id) } label: { EntryRow(entry: entry) } } }
                    Section { Button("编辑房租约定") { editRent = true }; if let end = r.endDate { Text("约定截止 \(Dates.text(end))").font(.caption).foregroundStyle(.secondary) }; Button(r.active ? "停止跟踪并解除租金预留" : "继续跟踪租金") { store.update("调整房租状态") { l in if let i = l.rents.firstIndex(where: { $0.id == r.id }) { l.rents[i].active.toggle() } } } }
                }.navigationTitle(r.title)
                    .sheet(isPresented: $editRent) { NavigationStack { RentEditor(rent: r) }.environment(store).appErrors().frame(minWidth: 340, minHeight: 560) }
            } else { EmptyState("house", "找不到房租约定", "记录可能已在另一版本账本中。") }
        }.toolbar { CloseButton() }
            .sheet(item: $editor) { e in NavigationStack { EntryEditor(entry: e) }.environment(store).appErrors().frame(minWidth: 340, minHeight: 550) }
            .sheet(isPresented: Binding(get: { linkMonth != nil }, set: { if !$0 { linkMonth = nil } })) { if let month = linkMonth { NavigationStack { LinkRentContributionView(rentID: rentID, month: month) }.environment(store).appErrors().frame(minWidth: 340, minHeight: 500) } }
    }
    func months(_ r: Rent) -> [Date] {
        let start = Dates.calendar.date(from: Dates.calendar.dateComponents([.year, .month], from: r.startDate))!
        let count = max(0, min(120, Dates.calendar.dateComponents([.month], from: start, to: min(Date(), r.endDate ?? Date())).month ?? 0))
        return (0...count).map { Dates.addMonths($0, to: start) }.reversed()
    }
    func monthRow(_ r: Rent, _ month: Date) -> some View {
        let received = store.current.activeEntries.filter { $0.rentID == r.id && $0.nature == .contribution && $0.rentPeriod.map { Dates.calendar.isDate($0, equalTo: month, toGranularity: .month) } == true }.reduce(Int64(0)) { $0 + $1.amount }
        let expected = r.monthlyTotal - r.personalShare
        return VStack(alignment: .leading, spacing: 12) { HStack { Text(month, format: .dateTime.year().month(.wide)).font(.headline); Spacer(); Text(received >= expected ? "已收齐" : "待收 " + Money.text(expected - received)).font(.caption).foregroundStyle(received >= expected ? YubaiTheme.jade : YubaiTheme.amber) }; HStack { Text("已收 \(Money.text(received)) / \(Money.text(expected))").font(.caption).foregroundStyle(.secondary); Spacer(); Menu("登记") { Button("新建收款记录") { newContribution(r, month, max(0, expected - received)) }; Button("关联已有流入") { linkMonth = month } } } }.padding(.vertical, 7)
    }
    func newContribution(_ r: Rent, _ month: Date, _ amount: Int64) {
        guard let a = store.current.accounts.first(where: { !$0.archived && ($0.kind == .cash || $0.kind == .bank) }) else { store.error = "先添加收款账户。"; return }
        var e = Entry(amount: max(1, amount), nature: .contribution, accountID: a.id, title: r.title + " · 分摊收款", category: "房租分摊")
        e.rentID = r.id; e.rentPeriod = month; e.note = "对应 \(Dates.text(month)) 所在月份，不计作收入"; editor = e
    }
}
struct LinkRentContributionView: View {
    @Environment(AppStore.self) private var store; @Environment(\.dismiss) private var dismiss
    var rentID: UUID; var month: Date
    var body: some View {
        List { Section { Text("选择已经收到的转账，记为本月房租分摊。原来的收入性质将更正为分摊，不会再增加现金。").font(.callout).foregroundStyle(.secondary) }; ForEach(store.current.activeEntries.filter { $0.nature.inflow && !$0.nature.paired && $0.rentID == nil && $0.planID == nil }.sorted { $0.date > $1.date }) { e in Button { if store.update("关联房租分摊", { l in if let i = l.entries.firstIndex(where: { $0.id == e.id }) { l.entries[i].rentID = rentID; l.entries[i].rentPeriod = month; l.entries[i].nature = .contribution; l.entries[i].category = "房租分摊"; l.entries[i].userEdited = true } }) { dismiss() } } label: { EntryRow(entry: e) }.buttonStyle(.plain) } }.navigationTitle("关联分摊收款").toolbar { CloseButton() }
    }
}
