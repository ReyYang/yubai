import SwiftUI
import YubaiCore

struct EntryEditor: View {
    @Environment(AppStore.self) private var store; @Environment(\.dismiss) private var dismiss
    var entry: Entry?
    @State private var amount = ""; @State private var title = ""; @State private var nature: Nature = .expense
    @State private var date = Date(); @State private var accountID: UUID?; @State private var otherID: UUID?
    @State private var category = "自动分类"; @State private var note = ""; @State private var relatedID: UUID?
    @State private var learn = false; @State private var keyword = ""; @State private var showAccount = false
    @State private var loaded = false
    var body: some View {
        Form {
            Section {
                HStack(alignment: .firstTextBaseline) { Text("¥").font(.title2).foregroundStyle(.secondary); TextField("0.00", text: $amount).font(.system(size: 36, weight: .medium, design: .rounded)).numericInput().accessibilityIdentifier("entryAmount") }
                TextField("这笔钱，用来做什么", text: $title).accessibilityIdentifier("entryTitle")
                Picker("性质", selection: $nature) { ForEach(Nature.allCases) { Text($0.label).tag($0) } }
            }
            Section("记到哪里") {
                Picker(nature.inflow ? "入账账户" : "付款账户", selection: $accountID) { Text("请选择").tag(UUID?.none); ForEach(store.current.accounts.filter { !$0.archived || $0.id == accountID }) { a in Text(a.name).tag(Optional(a.id)) } }.accessibilityIdentifier("entryAccount")
                if nature.paired {
                    Picker(nature.inflow ? "资金来源 / 对应债务" : "转入 / 对应资产负债", selection: $otherID) { Text("请选择另一账户").tag(UUID?.none); ForEach(store.current.accounts.filter { $0.id != accountID && !$0.archived }) { a in Text(a.name).tag(Optional(a.id)) } }
                    InlineNote(text: "内部移动只创建一笔双边记录；已导入两边时，请在详情中合并关联，避免重复。")
                }
                Button("添加账户") { showAccount = true }
                DatePicker("发生时间", selection: $date, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
            }
            Section("整理方式") {
                Picker("分类", selection: $category) { Text("自动分类").tag("自动分类"); ForEach(store.current.categories) { Text($0.name).tag($0.name) }; if !store.current.categories.contains(where: { $0.name == category }) && category != "自动分类" { Text(category).tag(category) } }
                if nature == .refund {
                    Picker("关联原支出", selection: $relatedID) { Text("暂不关联").tag(UUID?.none); ForEach(store.current.activeEntries.filter { $0.nature == .expense && $0.id != entry?.id }.sorted { $0.date > $1.date }.prefix(200)) { e in Text(e.title + " · " + Money.text(e.amount)).tag(Optional(e.id)) } }
                }
                TextField("备注（可选）", text: $note, axis: .vertical).lineLimit(2...5)
                if category != "自动分类" && (nature == .expense || nature == .income) {
                    Toggle("以后遇到类似用途，使用这个分类", isOn: $learn)
                    if learn { TextField("匹配关键词，例如：瑞幸", text: $keyword); InlineNote(text: "只学习分类，不修改历史记录、交易金额或收支方向。") }
                }
            }
            if nature.uncertain { Section { InlineNote(text: "可以先保存，之后再补充性质。待明确流入不会被当作可自由支配的钱。", symbol: "questionmark.circle") } }
        }.editorForm().navigationTitle(entry == nil ? "记一笔" : "编辑记录")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("保存", action: save).fontWeight(.semibold).accessibilityIdentifier("saveEntry") } }
            .onAppear(perform: load)
            .sheet(isPresented: $showAccount) { NavigationStack { AccountEditor(account: nil) }.environment(store).appErrors().frame(minWidth: 340, minHeight: 520) }
            .onChange(of: store.current.accounts.count) { _, _ in if accountID == nil { accountID = store.current.accounts.last?.id } }
    }
    func load() {
        guard !loaded else { return }; loaded = true
        if let e = entry { amount = Money.input(e.amount); title = e.title; nature = e.nature; date = e.date; accountID = e.accountID; otherID = e.otherAccountID; category = e.category; note = e.note; relatedID = e.relatedEntryID }
        else { accountID = store.current.accounts.first { !$0.archived && ($0.kind == .cash || $0.kind == .bank) }?.id }
    }
    func save() {
        do {
            let cents = try Money.parse(amount)
            guard cents > 0 else { throw YubaiError.invalid("金额需要大于零。") }
            let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanTitle.isEmpty, let accountID else { throw YubaiError.invalid("请补充用途并选择账户。") }
            if nature.paired && (otherID == nil || otherID == accountID) { throw YubaiError.invalid("请关联另一账户，内部移动才不会重复计算。") }
            var e = entry ?? Entry(amount: cents, accountID: accountID, title: cleanTitle)
            e.amount = cents; e.title = cleanTitle; e.accountID = accountID; e.nature = nature; e.date = date; e.note = note
            e.otherAccountID = nature.paired ? otherID : nil; e.relatedEntryID = nature == .refund ? relatedID : nil
            if category == "自动分类" { let c = Classifier.classify(title: cleanTitle, inflow: nature.inflow, rules: store.current.rules); e.category = store.current.resolveCategory(c.category); e.classificationReason = c.reason }
            else { e.category = category; e.classificationReason = "手动选择" }
            if nature == .refund, let relatedID, let original = store.current.entries.first(where: { $0.id == relatedID }) {
                let refunded = store.current.activeEntries.filter { $0.nature == .refund && $0.relatedEntryID == relatedID && $0.id != e.id }.reduce(Int64(0)) { $0 + $1.amount }
                guard cents <= original.amount - refunded else { throw YubaiError.invalid("退款超过这笔支出剩余可退金额。") }; e.category = original.category
            }
            if learn && keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { throw YubaiError.invalid("请填写要学习的关键词。") }
            if entry?.amount != e.amount || entry?.relatedEntryID != e.relatedEntryID || entry?.nature != e.nature || e.personalExpense == nil { LedgerOperations.recordPersonalShare(&e, ledger: store.current) }
            if store.update("保存记录", { l in
                if let i = l.entries.firstIndex(where: { $0.id == e.id }) { e.userEdited = true; l.entries[i] = e } else { l.entries.append(e) }
                LedgerOperations.syncLinkedRefundCategories(in: &l)
                if learn { l.rules.insert(Rule(keyword: keyword.trimmingCharacters(in: .whitespacesAndNewlines), category: e.category), at: 0) }
            }) { dismiss() }
        } catch { store.error = error.localizedDescription }
    }
}

struct AccountEditor: View {
    @Environment(AppStore.self) private var store; @Environment(\.dismiss) private var dismiss
    var account: Account?
    @State private var name = ""; @State private var kind = AccountKind.bank; @State private var amount = ""
    @State private var at = Date(); @State private var verified = true; @State private var note = ""; @State private var limit = ""
    @State private var loaded = false; @State private var reconcileNow = false
    var body: some View {
        Form {
            Section("账户") { TextField("名称，例如：微信零钱 / 招商银行卡", text: $name).accessibilityIdentifier("accountName"); Picker("账户类型", selection: $kind) { ForEach(AccountKind.allCases) { Text($0.label).tag($0) } }.disabled(account != nil); if kind == .credit { TextField("信用额度（可选）", text: $limit).numericInput() } }
            Section(kind == .credit ? "当前待还款" : kind == .investment ? "当前市值" : "核对余额") {
                if account != nil { Toggle("本次重新核对真实余额", isOn: $reconcileNow) }
                TextField(kind == .credit ? "待还总额，填写正数" : "余额", text: $amount).numericInput().accessibilityIdentifier("accountBalance").disabled(account != nil && !reconcileNow)
                if account == nil || reconcileNow {
                    DatePicker("核对时刻", selection: $at, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                    Toggle("已与真实账户核对", isOn: $verified)
                    if let a = account, let entered = try? Money.parse(amount, allowNegative: kind != .credit) {
                        let actual = kind == .credit ? -entered : entered
                        LabeledContent("与账本计算余额的差额", value: Money.text(actual - Finance.balance(a, in: store.current, at: at)))
                    }
                }
                Text(kind == .credit ? "填写实际欠款，不填写可用额度。信用额度不会增加可动用资金。" : "此刻的余额是计算起点。导入这个时刻之前的历史记录，只补全账本，不再重复改变余额。") .font(.caption).foregroundStyle(.secondary)
            }
            Section { TextField("备注（可选）", text: $note, axis: .vertical) }
            if account != nil { Section { InlineNote(text: "重新核对会建立新的余额起点，不会改写或伪造历史收支。之前的账本可从本地历史恢复。") } }
        }.editorForm().navigationTitle(account == nil ? "添加账户" : "核对与编辑账户")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("保存", action: save).fontWeight(.semibold).accessibilityIdentifier("saveAccount") } }
            .onAppear { guard !loaded else { return }; loaded = true; if let a = account { name = a.name; kind = a.kind; amount = Money.input(a.kind == .credit ? max(0, -Finance.balance(a, in: store.current)) : Finance.balance(a, in: store.current)); verified = a.reconciled; note = a.note; limit = a.creditLimit == 0 ? "" : Money.input(a.creditLimit) } }
    }
    func save() {
        do {
            let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else { throw YubaiError.invalid("请给账户起一个名称。") }
            guard !store.current.accounts.contains(where: { $0.name == clean && $0.id != account?.id }) else { throw YubaiError.invalid("已有同名账户，请使用容易区分的名称。") }
            let cents = try Money.parse(amount, allowNegative: kind != .credit)
            var a = account ?? Account(name: clean); a.name = clean; a.kind = kind; a.note = note
            if account == nil || reconcileNow { a.anchorBalance = kind == .credit ? -cents : cents; a.anchorDate = at; a.reconciled = verified }
            a.creditLimit = limit.isEmpty ? 0 : try Money.parse(limit)
            if store.update("保存账户", { l in if let i = l.accounts.firstIndex(where: { $0.id == a.id }) { l.accounts[i] = a } else { l.accounts.append(a) } }) { dismiss() }
        } catch { store.error = error.localizedDescription }
    }
}

struct AccountsView: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        List {
            Section { Text("核对真实余额，让余白的判断有依据。账户归档后保留历史和资产负债，不会凭空清零。").font(.callout).foregroundStyle(.secondary) }
            ForEach(AccountKind.allCases) { kind in
                let accounts = store.current.accounts.filter { $0.kind == kind }
                if !accounts.isEmpty { Section(kind.label) { ForEach(accounts) { a in NavigationLink { accountDetail(a) } label: { HStack { IconTile(symbol: a.kind.symbol); VStack(alignment: .leading, spacing: 5) { Text(a.name + (a.archived ? " · 已归档" : "")); Text(a.reconciled ? "核对于 \(Dates.text(a.anchorDate))" : "尚未核对").font(.caption).foregroundStyle(.secondary) }; Spacer(); AmountLabel(cents: Finance.balance(a, in: store.current)) } } } } }
            }
            Section { NavigationLink { AccountEditor(account: nil) } label: { Label("添加账户", systemImage: "plus.circle") } }
        }.navigationTitle("我的账户").toolbar { CloseButton() }
    }
    func accountDetail(_ a: Account) -> some View {
        List {
            Section { AmountLabel(cents: Finance.balance(a, in: store.current), large: true).padding(.vertical, 12); LabeledContent("类型", value: a.kind.label); LabeledContent("余额锚点", value: Dates.text(a.anchorDate, time: true)); if a.creditLimit > 0 { LabeledContent("信用额度", value: Money.text(a.creditLimit)) }; if !a.note.isEmpty { Text(a.note) }; NavigationLink("重新核对 / 编辑") { AccountEditor(account: a) } }
            Section("关联记录") { ForEach(Array(store.current.activeEntries.filter { $0.accountID == a.id || $0.otherAccountID == a.id }.sorted { $0.date > $1.date }.prefix(100))) { e in NavigationLink { EntryDetailView(entryID: e.id) } label: { EntryRow(entry: e) } } }
            Section { Button(a.archived ? "取消归档" : "归档账户") { store.update(a.archived ? "取消归档" : "归档账户") { l in if let i = l.accounts.firstIndex(where: { $0.id == a.id }) { l.accounts[i].archived.toggle() } } } }
        }.navigationTitle(a.name)
    }
}

struct PlanEditor: View {
    @Environment(AppStore.self) private var store; @Environment(\.dismiss) private var dismiss
    var plan: Plan?
    @State private var title = ""; @State private var amount = ""; @State private var date = Date(); @State private var frequency = Frequency.once
    @State private var inflow = false; @State private var isRepayment = false; @State private var category = "其他支出"; @State private var accountID: UUID?
    @State private var note = ""; @State private var hasEnd = false; @State private var endDate = Date(); @State private var loaded = false
    var historyLocked: Bool { plan.map { p in store.current.entries.contains { $0.planID == p.id } } ?? false }
    var body: some View {
        Form {
            Section { TextField("安排名称，例如：信用卡还款", text: $title); TextField("金额", text: $amount).numericInput(); Toggle("这是预计收入", isOn: $inflow); if !inflow { Toggle("信用本金还款", isOn: $isRepayment) }; DatePicker("首次到期日", selection: $date, displayedComponents: .date); Picker("重复", selection: $frequency) { ForEach(Frequency.allCases) { Text($0.label).tag($0) } } }.disabled(historyLocked)
            if frequency != .once { Section("约定期限") { Toggle("设定结束日期", isOn: $hasEnd); if hasEnd { DatePicker("结束日期", selection: $endDate, in: date..., displayedComponents: .date) } } }
            if historyLocked { Section { InlineNote(text: "这个约定已关联真实记录，金额与周期已固定。若下一期发生变化，请设定旧约定结束日期，再添加新约定；已付与未付的历史期次会继续保留。") } }
            Section { Picker(isRepayment && !inflow ? "待还信用账户" : "关联账户", selection: $accountID) { Text("付款时再选").tag(UUID?.none); ForEach(store.current.accounts.filter { !$0.archived }) { Text($0.name).tag(Optional($0.id)) } }; Picker("分类", selection: $category) { ForEach(store.current.categories) { Text($0.name).tag($0.name) } }; TextField("备注", text: $note, axis: .vertical) }
            Section { InlineNote(text: "预计收入不会提前加入保守可动用金额。安排到期后仍需登记真实发生的交易；不会自动扣钱。信用本金已按待还负债预留，不重复扣除。") }
        }.editorForm().navigationTitle(plan == nil ? "添加资金安排" : "编辑资金安排")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("保存", action: save) } }
            .onAppear { guard !loaded else { return }; loaded = true; if let p = plan { title = p.title; amount = Money.input(p.amount); date = p.dueDate; frequency = p.frequency; inflow = p.inflow; isRepayment = p.nature == .repayment; category = p.category; accountID = p.accountID; note = p.note; hasEnd = p.endDate != nil; endDate = p.endDate ?? Date() } }
    }
    func save() {
        do { let cents = try Money.parse(amount); guard cents > 0, !title.trimmingCharacters(in: .whitespaces).isEmpty else { throw YubaiError.invalid("请补充名称和有效金额。") }
            if isRepayment && !inflow && store.current.accounts.first(where: { $0.id == accountID })?.kind != .credit { throw YubaiError.invalid("信用本金还款需要关联对应信用账户。") }
            if historyLocked, let original = plan, (cents != original.amount || date != original.dueDate || frequency != original.frequency || inflow != original.inflow || (isRepayment != (original.nature == .repayment))) { throw YubaiError.invalid("这个约定已有真实记录，请结束旧约定并建立新的金额或周期。") }
            var p = plan ?? Plan(title: title, amount: cents, dueDate: date); p.title = title; p.amount = cents; p.dueDate = date; p.frequency = frequency; p.inflow = inflow; p.category = category; p.accountID = accountID; p.note = note; p.endDate = hasEnd && frequency != .once ? endDate : nil; p.nature = inflow ? .income : (isRepayment ? .repayment : .expense)
            if store.update("保存安排", { l in if let i = l.plans.firstIndex(where: { $0.id == p.id }) { l.plans[i] = p } else { l.plans.append(p) } }) { dismiss() }
        } catch { store.error = error.localizedDescription }
    }
}

struct GoalEditor: View {
    @Environment(AppStore.self) private var store; @Environment(\.dismiss) private var dismiss
    var goal: Goal?
    @State private var title = ""; @State private var target = ""; @State private var reserved = ""; @State private var date = Date(); @State private var hasDate = false; @State private var note = ""; @State private var loaded = false
    var body: some View {
        Form { Section { TextField("真正想做的事", text: $title); TextField("目标金额", text: $target).numericInput(); TextField("现在为它保留多少", text: $reserved).numericInput(); Toggle("设定期待日期", isOn: $hasDate); if hasDate { DatePicker("期待日期", selection: $date, displayedComponents: .date) }; TextField("为什么重要（可选）", text: $note, axis: .vertical) }; Section { InlineNote(text: "预留是一种资金用途，不会创建收入、支出或真实转账。已预留金额从可动用资金中扣除。") } }.editorForm().navigationTitle(goal == nil ? "留给重要的事" : "调整目标")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("保存", action: save) } }
            .onAppear { guard !loaded else { return }; loaded = true; if let g = goal { title = g.title; target = Money.input(g.target); reserved = Money.input(g.reserved); hasDate = g.dueDate != nil; date = g.dueDate ?? Date(); note = g.note } }
    }
    func save() {
        do { let total = try Money.parse(target); let saved = reserved.isEmpty ? 0 : try Money.parse(reserved); guard saved <= total, total > 0, !title.trimmingCharacters(in: .whitespaces).isEmpty else { throw YubaiError.invalid("请填写名称；预留不能超过目标金额。") }; var g = goal ?? Goal(title: title, target: total); g.title = title; g.target = total; g.reserved = saved; g.dueDate = hasDate ? date : nil; g.note = note; if store.update("保存目标", { l in if let i = l.goals.firstIndex(where: { $0.id == g.id }) { l.goals[i] = g } else { l.goals.append(g) } }) { dismiss() } } catch { store.error = error.localizedDescription }
    }
}

struct RentEditor: View {
    @Environment(AppStore.self) private var store; @Environment(\.dismiss) private var dismiss
    var rent: Rent?
    @State private var title = "合租房租"; @State private var total = ""; @State private var personal = ""; @State private var months = 3
    @State private var hasEnd = false; @State private var endDate = Date()
    @State private var start = Date(); @State private var due = Date(); @State private var receiveDay = 1; @State private var note = ""; @State private var loaded = false
    var historyLocked: Bool { rent.map { r in store.current.entries.contains { $0.rentID == r.id } } ?? false }
    var body: some View {
        Form {
            Section("共同承担") { TextField("名称", text: $title); TextField("每月房租总额", text: $total).numericInput(); TextField("其中我每月承担", text: $personal).numericInput(); Text("其余部分作为应收分摊。无需建立人物档案。").font(.caption).foregroundStyle(.secondary) }.disabled(historyLocked)
            Section("真实约定") { DatePicker("从哪天开始记分摊", selection: $start, displayedComponents: .date); DatePicker("下一笔租金付款日", selection: $due, displayedComponents: .date); Stepper("每 \(months) 个月付一次", value: $months, in: 1...12); Stepper("每月 \(receiveDay) 日收分摊", value: $receiveDay, in: 1...28) }.disabled(historyLocked)
            Section("约定期限") { Toggle("设定结束日期", isOn: $hasEnd); if hasEnd { DatePicker("结束日期", selection: $endDate, in: start..., displayedComponents: .date) }; TextField("备注", text: $note, axis: .vertical) }
            if historyLocked { Section { InlineNote(text: "已发生的分摊与付款按原约定保留。租金、承担比例或周期变化时，设定本约定的结束日期，再新建接续约定。结束日期之后不再生成新期次，已到期欠款继续显示。") } }
            Section { InlineNote(text: "预留的是向房东支付的全部租金，尚未收到的分摊不会提前算作现金。登记实收后增加现金；消费统计只计你承担的比例。") }
        }.editorForm().navigationTitle(rent == nil ? "建立房租分摊" : "编辑房租约定")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("保存", action: save) } }
            .onAppear { guard !loaded else { return }; loaded = true; if let r = rent { title = r.title; total = Money.input(r.monthlyTotal); personal = Money.input(r.personalShare); months = r.monthsPerPayment; start = r.startDate; due = r.nextDueDate; receiveDay = r.receiveDay; note = r.note; hasEnd = r.endDate != nil; endDate = r.endDate ?? Date() } }
    }
    func save() {
        do { let all = try Money.parse(total); let own = try Money.parse(personal); guard all > 0, own <= all, !title.trimmingCharacters(in: .whitespaces).isEmpty else { throw YubaiError.invalid("请核对租金：个人承担不能超过总额。") }; if historyLocked, let original = rent, (all != original.monthlyTotal || own != original.personalShare || start != original.startDate || due != original.nextDueDate || months != original.monthsPerPayment || receiveDay != original.receiveDay) { throw YubaiError.invalid("这个房租约定已有真实记录，请结束旧约定并建立新的金额或周期。") }; var r = rent ?? Rent(monthlyTotal: all, personalShare: own, startDate: start, nextDueDate: due); r.title = title; r.monthlyTotal = all; r.personalShare = own; r.startDate = start; r.nextDueDate = due; r.monthsPerPayment = months; r.receiveDay = receiveDay; r.note = note; r.endDate = hasEnd ? endDate : nil; if store.update("保存房租约定", { l in if let i = l.rents.firstIndex(where: { $0.id == r.id }) { l.rents[i] = r } else { l.rents.append(r) } }) { dismiss() } } catch { store.error = error.localizedDescription }
    }
}
