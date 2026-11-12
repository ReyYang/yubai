import SwiftUI
import YubaiCore

struct AccountEditor: View {
    @Environment(AppStore.self) private var store; @Environment(\.dismiss) private var dismiss
    var account: Account?
    var startsReconciling = false
    @State private var name = ""; @State private var kind = AccountKind.bank; @State private var amount = ""
    @State private var at = Date(); @State private var verified = true; @State private var note = ""; @State private var limit = ""
    @State private var loaded = false; @State private var reconcileNow = false
    @State private var confirmingDiscard = false
    @State private var initialSignature = ""
    var body: some View {
        Form {
            accountSection
            balanceSection
            noteSection
        }.editorForm().manualSheetNavigation()
            .safeAreaInset(edge: .top) {
                ManualSheetHeader(title: account == nil ? "添加账户" : "对一下余额", enabled: validationError == nil,
                                  actionIdentifier: "saveAccount", cancel: cancel, action: save).padding(.horizontal, 20)
            }
            .entryDiscardGuard(dirty: loaded && signature != initialSignature, amount: (try? Money.parse(amount, allowNegative: true)) ?? 0, confirming: $confirmingDiscard)
            .onAppear {
                guard !loaded else { return }; loaded = true; reconcileNow = startsReconciling
                if let a = account { name = a.name; kind = a.kind; amount = Money.input(a.kind == .credit ? max(0, -store.balance(a)) : store.balance(a)); verified = a.reconciled; note = a.note; limit = a.creditLimit == 0 ? "" : Money.input(a.creditLimit) }
                initialSignature = signature
            }
    }
    private var cleanName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var nameError: String? {
        if cleanName.isEmpty { return "填写账户名称" }
        return store.accounts.contains { $0.name == cleanName && $0.id != account?.id } ? "已有同名账户" : nil
    }
    private var balanceError: String? { (try? Money.parse(amount, allowNegative: kind != .credit)) == nil ? "填写有效金额" : nil }
    private var limitError: String? { !limit.isEmpty && (try? Money.parse(limit)) == nil ? "填写有效金额" : nil }
    private var validationError: String? { nameError ?? balanceError ?? limitError }
    private var signature: String { "\(name)|\(kind)|\(amount)|\(at)|\(verified)|\(note)|\(limit)|\(reconcileNow)" }
    private func cancel() { if signature != initialSignature { confirmingDiscard = true } else { dismiss() } }
    func save() {
        do {
            let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else { throw YubaiError.invalid("请给账户起一个名称。") }
            guard !store.accounts.contains(where: { $0.name == clean && $0.id != account?.id }) else { throw YubaiError.invalid("已有同名账户，请使用容易区分的名称。") }
            let cents = try Money.parse(amount, allowNegative: kind != .credit)
            var a = account ?? Account(name: clean); a.name = clean; a.kind = kind; a.note = note
            if account == nil || reconcileNow { a.anchorBalance = kind == .credit ? -cents : cents; a.anchorDate = at; a.reconciled = verified }
            a.creditLimit = limit.isEmpty ? 0 : try Money.parse(limit)
            if store.update("保存账户", { ledger in
                if let i = ledger.accounts.firstIndex(where: { $0.id == a.id }) { ledger.accounts[i] = a }
                else { ledger.accounts.append(a) }
                if account != nil && reconcileNow && verified {
                    for i in ledger.cards.indices where ledger.cards[i].action == .reconcileAccount(a.id) {
                        ledger.cards[i].dismissedAt = Date()
                    }
                }
            }) { dismiss() }
        } catch { store.error = error.localizedDescription }
    }

    private var accountSection: some View {
        Section("账户") {
            TextField("名称", text: $name).accessibilityIdentifier("accountName").accessibilityLabel("账户名称")
            if !name.isEmpty { InlineFieldError(message: nameError) }
            SuggestionChips(values: ["微信零钱", "支付宝", "招行储蓄卡", "信用卡"], selected: name) { name = $0 }
            Picker("账户类型", selection: $kind) { ForEach(AccountKind.allCases) { Text($0.label).tag($0) } }.disabled(account != nil)
        }.listRowBackground(YubaiColor.card).listRowSeparatorTint(YubaiColor.separator)
    }
    private var balanceSection: some View {
        Section(kind == .credit ? "当前待还款" : kind == .investment ? "当前市值" : "对一下余额") {
            if account != nil { Toggle("本次重新核对真实余额", isOn: $reconcileNow).tint(YubaiColor.toggleOn) }
            TextField(kind == .credit ? "当前待还款" : "余额", text: $amount).numericInput().yubaiFont(YubaiFont.amountInput)
                .accessibilityIdentifier("accountBalance").disabled(account != nil && !reconcileNow)
                .accessibilityHint(kind == .credit ? "填写实际欠款，单位元，填写正数" : "填写此刻的真实余额，单位元")
            if !amount.isEmpty { InlineFieldError(message: balanceError) }
            if account == nil || reconcileNow {
                DatePicker("上次对账", selection: $at, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                Toggle("已与真实账户核对", isOn: $verified).tint(YubaiColor.toggleOn)
                if let a = account, let entered = try? Money.parse(amount, allowNegative: kind != .credit) {
                    let actual = kind == .credit ? -entered : entered
                    LabeledContent("与账本计算余额的差额", value: Money.text(actual - store.balance(a, at: at)))
                }
            }
        }.listRowBackground(YubaiColor.card).listRowSeparatorTint(YubaiColor.separator)
    }
    private var noteSection: some View {
        Section {
            DisclosureGroup("更多") {
                if kind == .credit { TextField("信用额度", text: $limit).numericInput().yubaiFont(YubaiFont.amountInput).accessibilityHint("单位元，可留空") }
                InlineFieldError(message: limitError)
                TextField("备注", text: $note, axis: .vertical)
            }
        }.listRowBackground(YubaiColor.card).listRowSeparatorTint(YubaiColor.separator)
    }
}

struct AccountsView: View {
    @Environment(AppStore.self) private var store
    private var handAccounts: [Account] { store.accounts.filter { !$0.archived && ($0.kind == .cash || $0.kind == .bank) } }
    private var otherAccounts: [Account] { store.accounts.filter { $0.archived || ($0.kind != .cash && $0.kind != .bank) } }
    var body: some View {
        let hand = handAccounts, other = otherAccounts
        Page(spacing: YubaiSpace.gapSection, topPadding: YubaiSpace.gapGroup) {
            if store.accounts.isEmpty { EmptyState("creditcard", "还没有账户", action: "添加账户", onAction: { store.sheet = .account(nil) }) }
            if !hand.isEmpty { totalBlock(hand) }
            if !hand.isEmpty { accountGroup(hand, heading: nil) }
            if !other.isEmpty { accountGroup(other, heading: "不算在手上的") }
            actions(hasHand: !hand.isEmpty)
        }.amountPrivacy(store.preferences.hideAmounts).accessibilityIdentifier("accountsPage")
            .navigationTitle("手上的钱").yubaiNavigation().manualSheetHeader("手上的钱", cancelTitle: "关闭", showsAction: false)
    }
    private func totalBlock(_ hand: [Account]) -> some View {
        let names = ["零", "一", "两", "三", "四", "五", "六", "七", "八", "九", "十"]
        let count = hand.count < names.count ? names[hand.count] : String(hand.count)
        return VStack(alignment: .leading, spacing: YubaiSpace.space4) {
            Text(count + "个账户一共").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
            AmountLabel(cents: store.formula.hand, hide: store.preferences.hideAmounts, role: .display)
        }.padding(.horizontal, YubaiSpace.space4).accessibilityElement(children: .combine).accessibilityIdentifier("accountsTotal")
    }
    private func accountGroup(_ accounts: [Account], heading: String?) -> some View {
        VStack(alignment: .leading, spacing: YubaiSpace.gapHeading) {
            if let heading {
                Text(heading).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary).padding(.leading, YubaiSpace.insetCard)
            }
            CardRows(accounts) { a in
                NavigationLink { accountDetail(a) } label: {
                    HStack(spacing: YubaiSpace.gapGroup) { accountRow(a); chevron }
                        .padding(.vertical, YubaiSpace.space4).frame(minHeight: YubaiSize.rowDouble).contentShape(Rectangle())
                }.buttonStyle(PressButtonStyle()).accessibilityIdentifier("accountRow_" + a.name)
            }
        }
    }
    private var chevron: some View {
        Image(systemName: "chevron.right").yubaiFont(YubaiFont.caption, weight: .medium)
            .foregroundStyle(YubaiColor.labelSecondary).accessibilityHidden(true)
    }
    private func accountRow(_ a: Account) -> some View {
        let balance = AmountLabel(cents: store.balance(a), hide: store.preferences.hideAmounts, role: .amount).fixedSize(horizontal: true, vertical: false)
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: YubaiSpace.gapGroup) { accountName(a); Spacer(minLength: YubaiSpace.space8); balance }
            VStack(alignment: .leading, spacing: YubaiSpace.space8) { accountName(a); balance }
        }
    }
    private func actions(hasHand: Bool) -> some View {
        VStack(spacing: YubaiSpace.space8) {
            if hasHand {
                Button("对一下余额") { store.sheetSource = nil; store.sheet = .reconcileAll }
                    .buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("reconcileAll")
            }
            if !store.accounts.isEmpty {
                NavigationLink { AccountEditor(account: nil) } label: { Text("加一个账户") }
                    .buttonStyle(SecondaryButtonStyle()).accessibilityIdentifier("addAccount")
            }
        }
    }
    private func accountName(_ a: Account) -> some View {
        let detail: String
        if a.archived { detail = "已归档" }
        else if a.kind == .credit { detail = "欠的" }
        else if a.kind != .cash && a.kind != .bank { detail = a.note.isEmpty ? "看得见，花不了" : a.note }
        else {
            let checked = a.reconciled ? "上次对 " + FixedFlowPresentation.monthDay(a.anchorDate) : "还没对过账"
            detail = a.note.isEmpty ? checked : a.note + " · " + checked
        }
        return VStack(alignment: .leading, spacing: YubaiSpace.space4) {
            Text(a.name).yubaiFont(YubaiFont.rowTitle)
            Text(detail).yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary)
        }
    }
    func accountDetail(_ a: Account) -> some View {
        Page {
            AmountLabel(cents: store.balance(a), role: .display)
            Card(style: .list) { VStack(spacing: YubaiSpace.none) {
                LabeledContent("类型", value: a.kind.label).frame(minHeight: YubaiSize.rowSingle)
                Divider().overlay(YubaiColor.separator)
                LabeledContent("上次对账", value: Dates.text(a.anchorDate, time: true)).frame(minHeight: YubaiSize.rowSingle)
                if a.creditLimit > 0 { Divider().overlay(YubaiColor.separator); LabeledContent("信用额度", value: Money.text(a.creditLimit)).frame(minHeight: YubaiSize.rowSingle) }
                if !a.note.isEmpty { Divider().overlay(YubaiColor.separator); Text(a.note).frame(minHeight: YubaiSize.rowSingle) }
                Divider().overlay(YubaiColor.separator)
                NavigationLink("对一下余额") { AccountEditor(account: a, startsReconciling: true) }.frame(minHeight: YubaiSize.rowSingle)
                NavigationLink("编辑账户") { AccountEditor(account: a) }.frame(minHeight: YubaiSize.rowSingle).accessibilityIdentifier("editAccount")
            }.yubaiFont(YubaiFont.row) }
            VStack(alignment: .leading, spacing: YubaiSpace.gapHeading) {
                SectionHeading(title: "关联记录").padding(.horizontal, YubaiSpace.insetCard)
                CardRows(store.accountEntries(a.id)) { e in EntryLink(entry: e, hideAmount: store.preferences.hideAmounts, editable: true) }
            }
            Button(a.archived ? "取消归档" : "归档账户") { store.update(a.archived ? "取消归档" : "归档账户") { l in if let i = l.accounts.firstIndex(where: { $0.id == a.id }) { l.accounts[i].archived.toggle() } } }.buttonStyle(SecondaryButtonStyle())
        }.navigationTitle(a.name).yubaiNavigation().accessibilityIdentifier("accountDetailPage")
    }
}

struct GoalEditor: View {
    @Environment(AppStore.self) private var store; @Environment(\.dismiss) private var dismiss
    var goal: Goal?
    var updateLabel = "保存存钱"
    @State private var title = ""; @State private var target = ""; @State private var reserved = ""; @State private var date = Date(); @State private var hasDate = false; @State private var note = ""; @State private var loaded = false
    var body: some View {
        Form { goalSection; reservationSection }.editorForm().manualSheetHeader(goal == nil ? "在存钱" : "调整存钱", actionTitle: "保存", enabled: validationError == nil, action: save)
            .onAppear { guard !loaded else { return }; loaded = true; if let g = goal { title = g.title; target = Money.input(g.target); reserved = Money.input(g.reserved); hasDate = g.dueDate != nil; date = g.dueDate ?? Date(); note = g.note } }
    }
    private var validationError: String? {
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "填写名称" }
        guard let total = try? Money.parse(target), total > 0 else { return "想存金额须大于 0.00 元" }
        guard let saved = try? Money.parse(reserved.isEmpty ? "0" : reserved), saved <= total else { return "已存金额不能超过想存金额" }
        return nil
    }
    func save() {
        do { let total = try Money.parse(target); let saved = reserved.isEmpty ? 0 : try Money.parse(reserved); guard saved <= total, total > 0, !title.trimmingCharacters(in: .whitespaces).isEmpty else { throw YubaiError.invalid("请填写名称；已存金额不能超过想存金额。") }; var g = goal ?? Goal(title: title, target: total); g.title = title; g.target = total; g.reserved = saved; g.dueDate = hasDate ? date : nil; g.note = note; if store.update(updateLabel, { l in if let i = l.goals.firstIndex(where: { $0.id == g.id }) { l.goals[i] = g } else { l.goals.append(g) } }) { dismiss() } } catch { store.error = error.localizedDescription }
    }

    private var goalSection: some View {
        Section {
            TextField("真正想做的事", text: $title)
            TextField("想存多少（元）", text: $target).numericInput().yubaiFont(YubaiFont.amountInput)
            if !target.isEmpty && ((try? Money.parse(target)).map { $0 <= 0 } ?? true) { InlineFieldError(message: "想存金额须大于 0.00 元") }
            TextField("已存多少（元）", text: $reserved).numericInput().yubaiFont(YubaiFont.amountInput)
            if !reserved.isEmpty {
                InlineFieldError(message: (try? Money.parse(reserved)) == nil ? "填写有效金额" : ((try? Money.parse(reserved)) ?? 0) > ((try? Money.parse(target)) ?? 0) ? "已存金额不能超过想存金额" : nil)
            }
            Toggle("设定期待日期", isOn: $hasDate).tint(YubaiColor.toggleOn)
            if hasDate { DatePicker("期待日期", selection: $date, displayedComponents: .date) }
            DisclosureGroup("更多") { TextField("为什么重要", text: $note, axis: .vertical) }
        }.listRowBackground(YubaiColor.card).listRowSeparatorTint(YubaiColor.separator)
    }
    private var reservationSection: some View {
        EmptyView()
    }
}
