import SwiftUI
import YubaiCore

struct AccountEditor: View {
    @Environment(AppStore.self) private var store; @Environment(\.dismiss) private var dismiss
    var account: Account?
    var startsReconciling = false
    @State private var name = ""; @State private var kind = AccountKind.bank; @State private var amount = ""
    @State private var at = Date(); @State private var verified = true; @State private var note = ""; @State private var limit = ""
    @State private var loaded = false; @State private var reconcileNow = false
    var body: some View {
        Form {
            accountSection
            balanceSection
            noteSection
            if account != nil { Section { InlineNote(text: "重新核对会建立新的余额起点，不会改写或伪造历史收支。之前的账本可从本地历史恢复。") }.listRowBackground(YubaiColor.card).listRowSeparatorTint(YubaiColor.separator) }
        }.editorForm().navigationTitle(account == nil ? "添加账户" : "核对与编辑账户").yubaiNavigation()
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("保存", action: save).foregroundStyle(YubaiColor.brandInk).fontWeight(.semibold).accessibilityIdentifier("saveAccount") } }
            .onAppear { guard !loaded else { return }; loaded = true; reconcileNow = startsReconciling; if let a = account { name = a.name; kind = a.kind; amount = Money.input(a.kind == .credit ? max(0, -Finance.balance(a, in: store.current)) : Finance.balance(a, in: store.current)); verified = a.reconciled; note = a.note; limit = a.creditLimit == 0 ? "" : Money.input(a.creditLimit) } }
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

    private var accountSection: some View {
        Section("账户") { TextField("名称，例如：微信零钱 / 招商银行卡", text: $name).accessibilityIdentifier("accountName"); Picker("账户类型", selection: $kind) { ForEach(AccountKind.allCases) { Text($0.label).tag($0) } }.disabled(account != nil); if kind == .credit { TextField("信用额度（可选）", text: $limit).numericInput().yubaiFont(YubaiFont.amountInput) } }.listRowBackground(YubaiColor.card).listRowSeparatorTint(YubaiColor.separator)
    }
    private var balanceSection: some View {
        Section(kind == .credit ? "当前待还款" : kind == .investment ? "当前市值" : "核对余额") {
            if account != nil { Toggle("本次重新核对真实余额", isOn: $reconcileNow).tint(YubaiColor.toggleOn) }
            TextField(kind == .credit ? "待还总额，填写正数" : "余额", text: $amount).numericInput().yubaiFont(YubaiFont.amountInput).accessibilityIdentifier("accountBalance").disabled(account != nil && !reconcileNow)
            if account == nil || reconcileNow {
                DatePicker("核对时刻", selection: $at, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                Toggle("已与真实账户核对", isOn: $verified).tint(YubaiColor.toggleOn)
                if let a = account, let entered = try? Money.parse(amount, allowNegative: kind != .credit) {
                    let actual = kind == .credit ? -entered : entered
                    LabeledContent("与账本计算余额的差额", value: Money.text(actual - Finance.balance(a, in: store.current, at: at)))
                }
            }
            Text(kind == .credit ? "填写实际欠款，不填写可用额度。信用额度不会增加可动用资金。" : "此刻的余额是计算起点。导入这个时刻之前的历史记录，只补全账本，不再重复改变余额。") .yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
        }.listRowBackground(YubaiColor.card).listRowSeparatorTint(YubaiColor.separator)
    }
    private var noteSection: some View {
        Section { TextField("备注（可选）", text: $note, axis: .vertical) }.listRowBackground(YubaiColor.card).listRowSeparatorTint(YubaiColor.separator)
    }
}

struct AccountsView: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        Page {
            Text("核对真实余额，让余白的判断有依据。账户归档后保留历史和资产负债，不会凭空清零。").yubaiFont(YubaiFont.body).foregroundStyle(YubaiColor.labelMuted)
            ForEach(AccountKind.allCases) { kind in
                let accounts = store.current.accounts.filter { $0.kind == kind }
                if !accounts.isEmpty {
                    SectionHeading(title: kind.label)
                    CardRows(accounts) { a in
                        NavigationLink { accountDetail(a) } label: {
                            ViewThatFits(in: .horizontal) {
                                HStack(spacing: YubaiSpace.space12) { accountName(a); Spacer(); AmountLabel(cents: Finance.balance(a, in: store.current), fractionDigits: 2) }
                                VStack(alignment: .leading, spacing: YubaiSpace.space8) { accountName(a); AmountLabel(cents: Finance.balance(a, in: store.current), fractionDigits: 2) }
                            }.padding(.vertical, YubaiSpace.space8)
                        }.buttonStyle(PressButtonStyle())
                    }
                }
            }
            NavigationLink { AccountEditor(account: nil) } label: { Label("添加账户", systemImage: "plus.circle") }.buttonStyle(SecondaryButtonStyle())
        }.navigationTitle("我的账户").yubaiNavigation().toolbar { CloseButton() }
    }
    private func accountName(_ a: Account) -> some View {
        VStack(alignment: .leading, spacing: YubaiSpace.space4) { Text(a.name + (a.archived ? " · 已归档" : "")).yubaiFont(YubaiFont.rowTitle); Text(a.reconciled ? "核对于 \(Dates.text(a.anchorDate))" : "尚未核对").yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary) }
    }
    func accountDetail(_ a: Account) -> some View {
        Page {
            AmountLabel(cents: Finance.balance(a, in: store.current), role: .display, fractionDigits: 2)
            Card(style: .list) { VStack(spacing: 0) {
                LabeledContent("类型", value: a.kind.label).frame(minHeight: YubaiSize.buttonHeight)
                Divider().overlay(YubaiColor.separator)
                LabeledContent("余额锚点", value: Dates.text(a.anchorDate, time: true)).frame(minHeight: YubaiSize.buttonHeight)
                if a.creditLimit > 0 { Divider().overlay(YubaiColor.separator); LabeledContent("信用额度", value: Money.text(a.creditLimit)).frame(minHeight: YubaiSize.buttonHeight) }
                if !a.note.isEmpty { Divider().overlay(YubaiColor.separator); Text(a.note).frame(minHeight: YubaiSize.buttonHeight) }
                Divider().overlay(YubaiColor.separator)
                NavigationLink("核对余额") { AccountEditor(account: a, startsReconciling: true) }
                NavigationLink("编辑账户") { AccountEditor(account: a) }.frame(minHeight: YubaiSize.buttonHeight)
            }.yubaiFont(YubaiFont.row) }
            SectionHeading(title: "关联记录")
            CardRows(Array(store.current.activeEntries.filter { $0.accountID == a.id || $0.otherAccountID == a.id }.sorted { $0.date > $1.date }.prefix(100))) { e in EntryLink(entry: e, hideAmount: store.current.preferences.hideAmounts, editable: true) }
            Button(a.archived ? "取消归档" : "归档账户") { store.update(a.archived ? "取消归档" : "归档账户") { l in if let i = l.accounts.firstIndex(where: { $0.id == a.id }) { l.accounts[i].archived.toggle() } } }.buttonStyle(SecondaryButtonStyle())
        }.navigationTitle(a.name).yubaiNavigation()
    }
}

struct GoalEditor: View {
    @Environment(AppStore.self) private var store; @Environment(\.dismiss) private var dismiss
    var goal: Goal?
    var updateLabel = "保存目标"
    @State private var title = ""; @State private var target = ""; @State private var reserved = ""; @State private var date = Date(); @State private var hasDate = false; @State private var note = ""; @State private var loaded = false
    var body: some View {
        Form { goalSection; reservationSection }.editorForm().navigationTitle(goal == nil ? "留给重要的事" : "调整目标").yubaiNavigation()
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("保存", action: save).foregroundStyle(YubaiColor.brandInk) } }
            .onAppear { guard !loaded else { return }; loaded = true; if let g = goal { title = g.title; target = Money.input(g.target); reserved = Money.input(g.reserved); hasDate = g.dueDate != nil; date = g.dueDate ?? Date(); note = g.note } }
    }
    func save() {
        do { let total = try Money.parse(target); let saved = reserved.isEmpty ? 0 : try Money.parse(reserved); guard saved <= total, total > 0, !title.trimmingCharacters(in: .whitespaces).isEmpty else { throw YubaiError.invalid("请填写名称；预留不能超过目标金额。") }; var g = goal ?? Goal(title: title, target: total); g.title = title; g.target = total; g.reserved = saved; g.dueDate = hasDate ? date : nil; g.note = note; if store.update(updateLabel, { l in if let i = l.goals.firstIndex(where: { $0.id == g.id }) { l.goals[i] = g } else { l.goals.append(g) } }) { dismiss() } } catch { store.error = error.localizedDescription }
    }

    private var goalSection: some View {
        Section { TextField("真正想做的事", text: $title); TextField("目标金额", text: $target).numericInput().yubaiFont(YubaiFont.amountInput); TextField("现在为它保留多少", text: $reserved).numericInput().yubaiFont(YubaiFont.amountInput); Toggle("设定期待日期", isOn: $hasDate).tint(YubaiColor.toggleOn); if hasDate { DatePicker("期待日期", selection: $date, displayedComponents: .date) }; TextField("为什么重要（可选）", text: $note, axis: .vertical) }.listRowBackground(YubaiColor.card).listRowSeparatorTint(YubaiColor.separator)
    }
    private var reservationSection: some View {
        Section { InlineNote(text: "预留是一种资金用途，不会创建收入、支出或真实转账。已预留金额从可动用资金中扣除。") }.listRowBackground(YubaiColor.card).listRowSeparatorTint(YubaiColor.separator)
    }
}
