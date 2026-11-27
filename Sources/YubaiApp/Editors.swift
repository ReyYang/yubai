import SwiftUI
import YubaiCore

struct AccountsView: View {
    @Environment(AppStore.self) private var store
    private var handAccounts: [Account] { store.accounts.filter { !$0.archived && ($0.kind == .cash || $0.kind == .bank) } }
    private var otherAccounts: [Account] { store.accounts.filter { $0.archived || ($0.kind != .cash && $0.kind != .bank) } }
    var body: some View {
        let hand = handAccounts, other = otherAccounts
        Page(spacing: YubaiSpace.gapSection, topPadding: YubaiSpace.gapGroup) {
            if store.accounts.isEmpty { EmptyState("creditcard", "还没有账户", action: "添加账户", actionIdentifier: "addAccount", onAction: { store.settingsSheet = .accountAdd(nil, onboarding: false) }) }
            if !hand.isEmpty { totalBlock(hand) }
            if !hand.isEmpty { accountGroup(hand, heading: nil) }
            if !other.isEmpty { accountGroup(other, heading: "不算在手上的") }
            actions(hasHand: !hand.isEmpty)
        }.amountPrivacy(store.preferences.hideAmounts).accessibilityIdentifier("accountsPage")
            .navigationTitle("手上的钱").yubaiNavigation().manualSheetHeader("手上的钱", cancelTitle: "关闭", showsAction: false)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { store.settingsSheet = .accountAdd(nil, onboarding: false) } label: {
                        Image(systemName: "plus").yubaiHitTarget().accessibilityHidden(true)
                    }.buttonStyle(TextLinkStyle()).accessibilityLabel("添加账户").accessibilityIdentifier("addAccountToolbar")
                }
            }
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
        let balance = AmountLabel(cents: store.balance(a), hide: store.preferences.hideAmounts, role: .amount).fixedSize(horizontal: false, vertical: true)
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: YubaiSpace.gapGroup) { accountName(a); Spacer(minLength: YubaiSpace.space8); balance }
            VStack(alignment: .leading, spacing: YubaiSpace.space8) { accountName(a); balance }
        }
    }
    @ViewBuilder private func actions(hasHand: Bool) -> some View {
        if hasHand || !store.accounts.isEmpty {
            ChipFlow {
                if hasHand {
                    Button("对一下余额") { store.openBalanceReconciliation() }
                        .buttonStyle(SecondaryButtonStyle(compact: true)).accessibilityIdentifier("reconcileAll")
                }
                if !store.accounts.isEmpty {
                    Button { store.settingsSheet = .accountAdd(nil, onboarding: false) } label: { Text("加一个账户") }
                        .buttonStyle(SecondaryButtonStyle(background: YubaiColor.raised, compact: true)).accessibilityIdentifier("addAccount")
                }
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
            let checked = a.reconciled ? "上次对 " + Dates.monthDay(a.anchorDate) : "还没对过账"
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
                    EntryFormRow(title: "上次对账") { Text(Dates.monthDay(a.anchorDate) + " " + a.anchorDate.formatted(.dateTime.hour().minute().locale(Locale(identifier: "zh_CN")))).fixedSize() }
                    if a.creditLimit > 0 {
                        EntryFormDivider()
                        EntryFormRow(title: "信用额度") { AmountLabel(cents: a.creditLimit, hide: store.preferences.hideAmounts) }
                    }
                    if !a.note.isEmpty { EntryFormDivider(); Text(a.note).frame(minHeight: YubaiSize.rowSingle) }
                }
            }
            Button("对一下余额") { store.openAccountValuation(a.kind == .investment ? .invest(a.id) : .reconcile(a.id)) }.buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("reconcileAccount")
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
                    HeaderIconButton(action: { store.tabRouteRequest = .accountEdit(a.id) }) { size in Image(systemName: "pencil").font(.system(size: size)) }
                        .accessibilityLabel("编辑账户").accessibilityIdentifier("editAccount")
                }
            }
    }
}
