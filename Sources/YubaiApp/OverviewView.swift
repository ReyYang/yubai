import SwiftUI
import YubaiCore

struct OverviewView: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        let funds = store.funds
        Page {
            HStack {
                Text("给生活，留一点余白").yubaiFont(YubaiFont.lead)
                Spacer()
                Button { store.update("切换金额显示") { $0.preferences.hideAmounts.toggle() } } label: {
                    Image(systemName: store.current.preferences.hideAmounts ? "eye.slash" : "eye")
                        .frame(width: YubaiSize.tapMin, height: YubaiSize.tapMin)
                }.accessibilityLabel("隐藏或显示总览金额")
            }
            ButlerSection()
            if store.current.accounts.isEmpty {
                EmptyState("wallet.bifold", "从真实余额开始", "添加账户，填写此刻真实余额。导入历史账单不会让余额重复增加。")
                Button("添加第一个账户") { store.sheet = .account(nil) }
                    .buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("addFirstAccount")
            } else {
                HeroCard(available: funds.available, payable: funds.debt + funds.committed,
                         reserved: funds.goals + funds.emergency + funds.living + funds.uncertainInflow,
                         attentionCount: funds.warnings.count, hideAmount: store.current.preferences.hideAmounts,
                         title: "保守可动用", onDetails: { store.sheet = .fundsCalculation }, onAttention: { store.sheet = .accounts })
                Text("看未来 90 天，先留出已知付款、目标、底线与日常生活的钱。未到账收入不提前算入。")
                    .yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelMuted)
                UpcomingPaymentsView()
            }
            Button { store.sheet = .imports } label: { Label("导入账单", systemImage: "square.and.arrow.down") }
                .buttonStyle(SecondaryButtonStyle()).accessibilityIdentifier("importBills")
        }.navigationTitle("现在").yubaiNavigation()
    }
}

/// The same Finance occurrences appear on Now and under the funds breakdown.
struct UpcomingPaymentsView: View {
    @Environment(AppStore.self) private var store
    @State private var ending: Occurrence?
    private var payments: [Occurrence] { store.funds.occurrences.filter { !$0.inflow } }
    var body: some View {
        VStack(alignment: .leading, spacing: YubaiSpace.space12) {
            SectionHeading(title: "接下来要付的", subtitle: "未来 90 天，也保留已到期的付款。")
            if payments.isEmpty { Text("没有待完成的付款。新的安排可以告诉余白，确认后再记下。")
                .yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary) }
            CardRows(payments) { item in
                VStack(alignment: .leading, spacing: YubaiSpace.space8) {
                    ViewThatFits(in: .horizontal) {
                        HStack { title(item); Spacer(); amount(item) }
                        VStack(alignment: .leading, spacing: YubaiSpace.space8) { title(item); amount(item) }
                    }
                    if canEnd(item) {
                        Button("结束这个安排") { ending = item }.yubaiFont(YubaiFont.caption)
                            .frame(minHeight: YubaiSize.tapMin).accessibilityIdentifier("endArrangement_" + item.id)
                    }
                }.padding(.vertical, YubaiSpace.space8)
            }
        }.confirmationDialog("结束「\(ending?.title ?? "这个安排")」？已到期付款和历史记录继续保留。",
                             isPresented: Binding(get: { ending != nil }, set: { if !$0 { ending = nil } })) {
            Button("结束这个安排", role: .destructive) {
                if let item = ending, let id = item.planID ?? item.rentID {
                    let change = ChangeSet(source: "用户操作", reason: "从现在起结束「\(item.title)」", items: [.endPlan(id, Date())])
                    store.apply(change, label: "结束安排")
                }
                ending = nil
            }
        }
    }
    private func title(_ item: Occurrence) -> some View {
        VStack(alignment: .leading, spacing: YubaiSpace.space4) {
            Text(item.title).yubaiFont(YubaiFont.rowTitle)
            Text(Dates.text(item.date) + (item.overdue ? " · 已到期，请核对" : ""))
                .yubaiFont(YubaiFont.meta).foregroundStyle(item.overdue ? YubaiColor.amberInk : YubaiColor.labelSecondary)
        }
    }
    private func amount(_ item: Occurrence) -> some View {
        AmountLabel(cents: item.amount, hide: store.current.preferences.hideAmounts, sign: .outflow)
    }
    private func canEnd(_ item: Occurrence) -> Bool {
        if let id = item.planID, let plan = store.current.plans.first(where: { $0.id == id }) { return plan.endDate == nil }
        if let id = item.rentID, let rent = store.current.rents.first(where: { $0.id == id }) { return rent.endDate == nil }
        return false
    }
}

struct FundsCalculationView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dynamicTypeSize) private var textSize
    var body: some View {
        let funds = store.funds
        Page {
            Text("从现在的现金里，留出已经有用途的钱").yubaiFont(YubaiFont.lead)
            Text("未来 90 天").yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelMuted)
            Card(style: .list) {
                VStack(spacing: 0) {
                    formula("可支配现金", funds.cash); formula("减：全部信用待还", -funds.debt); formula("减：已知付款", -funds.committed)
                    formula("减：目标预留", -funds.goals); formula("减：始终留着的底线", -funds.emergency); formula("减：日常生活预留", -funds.living)
                    Text("日常生活按近 90 天的小额支出估算，排除已关联的固定付款；记录少时可能偏低。")
                        .yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                    if funds.uncertainInflow > 0 { formula("减：性质待明确流入", -funds.uncertainInflow) }
                    formula("保守可动用", funds.available)
                }
            }
            ForEach(funds.warnings, id: \.self) { InlineNote(text: $0, style: .attention) }
            InlineNote(text: "未来收入、投资市值和借出待收不提前当现金；信用本金不重复预留。判断依赖账单和余额是否完整。")
            UpcomingPaymentsView()
        }.navigationTitle("计算依据").yubaiNavigation().toolbar { CloseButton() }
    }
    private func formula(_ title: String, _ amount: Int64) -> some View {
        let layout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: YubaiSpace.space6)) : AnyLayout(HStackLayout())
        return VStack(spacing: 0) {
            layout { Text(title).yubaiFont(YubaiFont.row); if !textSize.isAccessibilitySize { Spacer() }; AmountLabel(cents: amount, hide: store.current.preferences.hideAmounts) }.frame(minHeight: YubaiSize.buttonHeight)
            if title != "保守可动用" { Rectangle().fill(YubaiColor.separator).frame(height: 1).accessibilityHidden(true) }
        }
    }
}
