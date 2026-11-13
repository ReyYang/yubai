import SwiftUI
import YubaiCore

/// A single derivation; every source row leads to its editable records.
struct FormulaView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var derivation: SpendingDerivation?
    private var hide: Bool { store.preferences.hideAmounts }
    var body: some View {
        Page(spacing: YubaiSpace.gapGroup, topPadding: YubaiSpace.space8) {
            if let value = derivation {
                VStack(alignment: .leading, spacing: YubaiSpace.space4) {
                    AmountLabel(cents: value.available, hide: hide, role: .display, currency: true)
                        .accessibilityIdentifier("formulaResult")
                    Text(horizon).yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary)
                }
                Card(style: .list) { sources(value) }
                Card(style: .list) { result(value) }
            }
        }.navigationTitle("还能花").yubaiNavigation().amountPrivacy(hide).accessibilityIdentifier("formulaPage")
            .task(id: "\(store.ledgerRevision)-\(store.financialNow)") {
                let ledger = store.current, now = store.financialNow
                let value = await Task.detached(priority: .userInitiated) { Finance.spendingDerivation(ledger, now: now) }.value
                guard !Task.isCancelled else { return }; derivation = value
            }
    }
    private var horizon: String {
        guard let pace = store.pace else { return "这个月" }
        if let late = pace.lateDays { return late == 0 ? "今天发工资" : "工资晚了 \(late) 天" }
        if textSize.isAccessibilitySize || !store.funds.cycleIsPayday { return "还有 \(pace.daysLeft) 天" }
        return "到 " + NowFormat.monthDay(Dates.addDays(1, to: pace.end)) + "发工资 · 还有 \(pace.daysLeft) 天"
    }
    private func sources(_ value: SpendingDerivation) -> some View {
        let salary = value.salary.flatMap { value.income == $0.amount ? $0 : nil }
        return VStack(spacing: YubaiSpace.none) {
            if value.otherFunds != 0 {
                TabNavigationLink(.accounts) { AccountsView() } label: {
                    row("手上的钱", amount: value.otherFunds)
                }.buttonStyle(PressButtonStyle()).accessibilityIdentifier("formulaRow_hand")
                EntryFormDivider()
            }
            Button {
                if let salary { store.sheet = .editEntry(salary.id) }
                else { showEntries(value.interval) }
            } label: {
                row(salary.map { NowFormat.monthDay($0.date) + "的工资" } ?? "这个周期收入", amount: value.income)
            }.buttonStyle(PressButtonStyle()).accessibilityIdentifier("formulaRow_income")
            if value.fixedSavings != 0 { source("存着不动", amount: value.fixedSavings, id: "formulaRow_fixedSavings") { store.sheet = .formulaEdit(.fixedSavings) } }
            if value.creditDebt != 0 { source("信用卡欠款", amount: value.creditDebt, id: "formulaRow_creditDebt") { store.sheet = .accounts } }
            if value.goals != 0 { source("在存钱", amount: value.goals, id: "formulaRow_goals") { store.destination = .saving; store.resetRootNavigation(); store.destination = .saving } }
            if value.uncertainInflow != 0 { source("没写用途的进账", amount: value.uncertainInflow, id: "formulaRow_uncertainInflow") { showEntries(value.interval) } }
            source("先存起来", detail: "每月先存", amount: value.saving, id: "formulaRow_saving") { store.sheet = .formulaEdit(.saving) }
            if store.plans.contains(where: { $0.active && !$0.inflow && $0.frequency == .yearly }) {
                EntryFormDivider()
                TabNavigationLink(.yearlyBills) { YearlyBillsView() } label: {
                    row("每月先留", amount: -value.yearlySetAside)
                }.buttonStyle(PressButtonStyle()).accessibilityIdentifier("formulaRow_yearlySetAside")
            }
            EntryFormDivider()
            TabNavigationLink(.fixedFlows) { FixedFlowsView() } label: {
                row("要付的账单", detail: billDetail(value.billNames), amount: -value.bills)
            }.buttonStyle(PressButtonStyle()).accessibilityIdentifier("formulaRow_bills")
            EntryFormDivider()
            Button { showEntries(value.interval) } label: { row("这个周期能花", amount: value.budget, chevron: false, strong: true) }
                .buttonStyle(PressButtonStyle()).accessibilityIdentifier("formulaCycleBudget")
        }.accessibilityElement(children: .contain).accessibilityIdentifier("formulaCard")
    }
    private func result(_ value: SpendingDerivation) -> some View {
        VStack(spacing: YubaiSpace.none) {
            Button { showEntries(value.interval) } label: { row("已经花了", detail: "\(value.entryIDs.count) 笔", amount: -value.spent) }
                .buttonStyle(PressButtonStyle()).accessibilityIdentifier("formulaRow_spent")
            EntryFormDivider()
            Button { showEntries(value.interval) } label: {
                row("还能花", amount: value.available, chevron: false, strong: true, ink: value.available < 0 ? YubaiColor.amberInk : YubaiColor.brandInk)
            }.buttonStyle(PressButtonStyle()).accessibilityIdentifier("formulaRow_available")
            if let daily = value.daily {
                EntryFormDivider()
                TabNavigationLink(.savingRule) { SavingsView() } label: { row("日均", amount: daily, chevron: false) }
                    .buttonStyle(PressButtonStyle()).accessibilityIdentifier("formulaRow_daily")
            }
        }
    }
    private func billDetail(_ names: [String]) -> String? {
        let unique = Array(Set(names)).sorted()
        guard !unique.isEmpty else { return nil }
        return unique.prefix(2).joined(separator: "、") + "等 \(unique.count) 样"
    }
    private func source(_ title: String, detail: String? = nil, amount: Int64, id: String, action: @escaping () -> Void) -> some View {
        VStack(spacing: YubaiSpace.none) {
            EntryFormDivider()
            Button(action: action) { row(title, detail: detail, amount: -amount) }
                .buttonStyle(PressButtonStyle()).accessibilityIdentifier(id)
        }
    }
    private func row(_ title: String, detail: String? = nil, amount: Int64, chevron: Bool = true, strong: Bool = false, ink: Color = YubaiColor.label) -> some View {
        let layout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: YubaiSpace.space4)) : AnyLayout(HStackLayout(spacing: YubaiSpace.space8))
        return layout {
            VStack(alignment: .leading, spacing: YubaiSpace.space2) {
                Text(title).yubaiFont(YubaiFont.rowTitle, weight: strong ? .semibold : .regular).lineLimit(1)
                if let detail { Text(detail).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary).lineLimit(1) }
            }.frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: YubaiSpace.space8) {
                AmountLabel(cents: amount, hide: hide, role: strong ? .summary : .amount, ink: ink).fixedSize()
                if chevron { Image(systemName: "chevron.right").yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary).accessibilityHidden(true) }
            }
        }.frame(maxWidth: .infinity, minHeight: YubaiSize.rowDouble, alignment: .leading).padding(.vertical, YubaiSpace.space2).contentShape(Rectangle())
    }
    private func showEntries(_ interval: DateInterval) {
        store.resetRootNavigation(); store.ledgerPreset = LedgerPreset(mode: .detail, interval: interval); store.destination = .ledger
    }
}
