import SwiftUI
import YubaiCore

struct AccountEditor: View {
    @Environment(AppStore.self) private var store; @Environment(\.dismiss) private var dismiss
    var account: Account?
    var startsReconciling = false
    @State private var name = ""; @State private var kind = AccountKind.bank; @State private var amount = ""
    @State private var at = Date(); @State private var verified = true; @State private var note = ""; @State private var limit = ""
    @State private var loaded = false; @State private var reconcileNow = false
    @State private var creditPaymentDay = 0
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
                                  actionIdentifier: "saveAccount", cancel: cancel, action: save).padding(.horizontal, YubaiSpace.space20)
            }
            .entryDiscardGuard(dirty: loaded && signature != initialSignature, amount: (try? Money.parse(amount, allowNegative: true)) ?? 0, confirming: $confirmingDiscard)
            .onAppear {
                guard !loaded else { return }; loaded = true; reconcileNow = startsReconciling
                if let a = account { name = a.name; kind = a.kind; amount = Money.input(a.kind == .credit ? max(0, -store.balance(a)) : store.balance(a)); verified = a.reconciled; note = a.note; limit = a.creditLimit == 0 ? "" : Money.input(a.creditLimit) }
                creditPaymentDay = account?.creditPaymentDay ?? 0
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
    private var signature: String { "\(name)|\(kind)|\(amount)|\(at)|\(verified)|\(note)|\(limit)|\(reconcileNow)|\(creditPaymentDay)" }
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
            a.creditPaymentDay = kind == .credit && creditPaymentDay > 0 ? creditPaymentDay : nil
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
            CardTextFieldRow(title: "名称", text: $name, identifier: "accountName", autofocus: true)
            if !name.isEmpty { InlineFieldError(message: nameError) }
            SuggestionChips(values: ["微信零钱", "支付宝", "招行储蓄卡", "信用卡"], selected: name) { name = $0 }
            Picker("账户类型", selection: $kind) { ForEach(AccountKind.allCases) { Text($0.label).tag($0) } }.disabled(account != nil)
        }.listRowBackground(YubaiColor.card).listRowSeparatorTint(YubaiColor.separator)
    }
    private var balanceSection: some View {
        Section(kind == .credit ? "当前待还款" : kind == .investment ? "当前市值" : "对一下余额") {
            if account != nil { Toggle("本次重新核对真实余额", isOn: $reconcileNow).tint(YubaiColor.toggleOn) }
            MoneyInputRow(title: kind == .credit ? "当前待还款" : "余额", text: $amount, identifier: "accountBalance", allowNegative: kind != .credit)
                .disabled(account != nil && !reconcileNow)
                .accessibilityHint(kind == .credit ? "填写实际欠款，单位元，填写正数" : "填写此刻的真实余额，单位元")
            if !amount.isEmpty { InlineFieldError(message: balanceError) }
            if account == nil || reconcileNow {
                EntryFormRow(title: "上次对账") { EntryDateChip(date: $at, allowsFuture: false); EntryDateChip(date: $at, time: true, allowsFuture: false) }
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
                if kind == .credit {
                    MoneyInputRow(title: "信用额度", text: $limit, identifier: "accountCreditLimit")
                    Picker("还款日", selection: $creditPaymentDay) {
                        Text("未指定").tag(0)
                        ForEach(1...31, id: \.self) { Text("每月 \($0) 号").tag($0) }
                    }.accessibilityIdentifier("accountCreditPaymentDay")
                }
                InlineFieldError(message: limitError)
                CardTextFieldRow(title: "备注", text: $note, identifier: "accountNote")
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
            AmountLabel(cents: hand.reduce(Int64(0)) { $0 + store.balance($1) }, hide: store.preferences.hideAmounts, role: .display)
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
        else if a.kind == .credit {
            detail = "欠的" + (a.creditPaymentDay.map { " · " + FixedFlowPresentation.monthDay(CreditPaymentDate.next(day: $0, now: store.financialNow)) + "还" } ?? "")
        }
        else if a.kind != .cash && a.kind != .bank { detail = a.note.isEmpty ? "看得见，花不了" : a.note }
        else {
            let checked = a.reconciled ? "上次对 " + FixedFlowPresentation.monthDay(a.anchorDate) : "还没对过账"
            detail = a.note.isEmpty ? checked : a.note + " · " + checked
        }
        return VStack(alignment: .leading, spacing: YubaiSpace.space4) {
            Text(a.name).yubaiFont(YubaiFont.rowTitle).lineLimit(1)
            Text(detail).yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary)
        }
    }
    func accountDetail(_ a: Account) -> some View {
        Page {
            Text(a.name).yubaiFont(YubaiFont.cardTitle).fixedSize(horizontal: false, vertical: true)
            AmountLabel(cents: store.balance(a), hide: store.preferences.hideAmounts, role: .display)
            Card(style: .list) {
                VStack(spacing: YubaiSpace.none) {
                    EntryFormRow(title: "类型") { Text(a.kind.label) }
                    EntryFormDivider()
                    EntryFormRow(title: "上次对账") { Text(Dates.text(a.anchorDate, time: true)).fixedSize() }
                    if a.creditLimit > 0 {
                        EntryFormDivider()
                        EntryFormRow(title: "信用额度") { AmountLabel(cents: a.creditLimit, hide: store.preferences.hideAmounts) }
                    }
                    if !a.note.isEmpty { EntryFormDivider(); Text(a.note).frame(minHeight: YubaiSize.rowSingle) }
                }
            }
            Button("对一下余额") { store.sheet = .reconcile(a.id) }.buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("reconcileAccount")
            VStack(alignment: .leading, spacing: YubaiSpace.gapHeading) {
                SectionHeading(title: "关联记录").padding(.horizontal, YubaiSpace.insetCard)
                CardRows(store.accountEntries(a.id)) { e in EntryLink(entry: e, hideAmount: store.preferences.hideAmounts, editable: true) }
            }
            Button(a.archived ? "取消归档" : "归档账户") {
                store.update(a.archived ? "取消归档" : "归档账户") { ledger in
                    if let i = ledger.accounts.firstIndex(where: { $0.id == a.id }) { ledger.accounts[i].archived.toggle() }
                }
            }.buttonStyle(SecondaryButtonStyle())
        }.navigationTitle(a.name).yubaiNavigation().accessibilityIdentifier("accountDetailPage")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    HeaderIconButton(action: { store.sheet = .account(a) }) { size in Image(systemName: "pencil").font(.system(size: size)) }
                        .accessibilityLabel("编辑账户").accessibilityIdentifier("editAccount")
                }
            }
    }
}
