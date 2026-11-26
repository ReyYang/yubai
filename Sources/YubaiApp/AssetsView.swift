import SwiftUI
import YubaiCore

struct AssetsView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let _ = OverviewRenderCounts.hit("assetsBody")
        let data = OverviewAnalytics.assets(in: store.current, now: store.financialNow)
        let hidden = store.preferences.hideAmounts
        VStack(alignment: .leading, spacing: DS.Space.s20) {
            cash(data, hidden: hidden)
            accounts(data.accounts, hidden: hidden)
            if !data.investments.isEmpty { investments(data.investments, hidden: hidden) }
        }.padding(.top, OverviewSpec.totalsTop)
            .accessibilityElement(children: .contain).accessibilityIdentifier("assetsPage")
    }

    private func cash(_ data: OverviewAssetsSnapshot, hidden: Bool) -> some View {
        VStack(alignment: .leading, spacing: .zero) {
            Text("流动现金").dsText(DS.Font.tSub).foregroundStyle(DS.Color.ink2)
            Text(OverviewDisplay.money(data.liquidCash, hidden: hidden, currency: true)).dsText(DS.Font.nHero)
                .foregroundStyle(DS.Color.ink).lineLimit(1).minimumScaleFactor(HomeSpec.numberMinimumScale)
                .padding(.top, OverviewSpec.headingGap).accessibilityIdentifier("overviewLiquidCash")
            DSStackedBar(segments: [
                .init(id: "floor", value: Double(data.floorAmount), color: DS.Color.accentInk),
                .init(id: "reserve", value: Double(data.reserveAmount), color: DS.Color.chart3),
            ], kind: .assets).padding(.top, OverviewSpec.assetsBarTop)
            HStack(spacing: DS.Space.s12) {
                cashLink("底线存款", amount: data.floorAmount, total: data.liquidCash, color: DS.Color.accentInk,
                         hidden: hidden, identifier: "overviewFloor") { store.present(.savingsFloor) }
                cashLink("机动余钱", amount: data.reserveAmount, total: data.liquidCash, color: DS.Color.chart3,
                         hidden: hidden, identifier: "overviewReserve") { store.tabRouteRequest = .reserve }
            }.padding(.top, DS.Space.s12)
        }.dsFillWidth()
    }

    private func cashLink(_ title: String, amount: Int64, total: Int64, color: Color,
                          hidden: Bool, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: OverviewSpec.headingGap) {
                HStack(alignment: .firstTextBaseline, spacing: OverviewSpec.inlineGap) {
                    DSOverviewSwatch(color: color, size: DS.Space.s8)
                        .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] }
                    Text(title)
                    if !hidden { Text(OverviewDisplay.share(amount, of: total)).monospacedDigit() }
                }.dsText(DS.Font.tCaption).foregroundStyle(DS.Color.ink3)
                    .lineLimit(1).minimumScaleFactor(HomeSpec.numberMinimumScale)
                Text(OverviewDisplay.money(amount, hidden: hidden)).dsText(DS.Font.tTitle).monospacedDigit()
                    .foregroundStyle(DS.Color.ink).lineLimit(1).minimumScaleFactor(HomeSpec.numberMinimumScale)
            }.frame(maxWidth: .infinity, minHeight: DS.Size.tapMin, alignment: .leading)
                .contentShape(Rectangle()).accessibilityElement(children: .combine)
        }.dsPressStyle().accessibilityIdentifier(identifier)
    }

    private func accounts(_ balances: [OverviewAssetsSnapshot.Balance], hidden: Bool) -> some View {
        VStack(alignment: .leading, spacing: .zero) {
            HStack {
                Text("账户").dsText(DS.Font.tBody).fontWeight(.semibold).foregroundStyle(DS.Color.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: .zero)
                Button { store.present(.account(nil)) } label: {
                    DSIconView(icon: .add, size: DS.Size.icon, color: DS.Color.accentInk)
                        .frame(width: DS.Size.tapMin, height: DS.Size.tapMin).contentShape(Rectangle())
                }.dsPressStyle().accessibilityLabel("添加账户").accessibilityIdentifier("overviewAddAccount")
            }.frame(height: DS.Size.chipH)
            if !balances.isEmpty {
                VStack(spacing: .zero) {
                    ForEach(Array(balances.enumerated()), id: \.element.id) { index, balance in
                        let account = balance.account
                        Button { store.tabRouteRequest = .accountDetail(account.id) } label: {
                            HStack(spacing: DS.Space.s12) {
                                DSIconView(icon: icon(account), size: DS.Size.icon, color: DS.Color.ink2)
                                Text(account.name).dsText(DS.Font.tBody).foregroundStyle(DS.Color.ink2).lineLimit(1)
                                Spacer(minLength: .zero)
                                Text(OverviewDisplay.money(balance.amount, hidden: hidden)).dsText(DS.Font.nSpine).foregroundStyle(DS.Color.ink)
                                    .lineLimit(1).minimumScaleFactor(HomeSpec.numberMinimumScale).layoutPriority(1)
                            }
                            .frame(minHeight: OverviewSpec.accountRowHeight).contentShape(Rectangle())
                            .overlay(alignment: .top) {
                                if index > 0 { DS.Color.separator.frame(height: DS.Stroke.hairline) }
                            }
                            .accessibilityElement(children: .combine)
                        }.dsPressStyle().accessibilityIdentifier("overviewAccount_" + account.name)
                    }
                }.padding(.horizontal, DS.Space.s16).dsSurface(DS.Color.raised, radius: DS.Radius.m)
            }
        }
    }

    private func investments(_ balances: [OverviewAssetsSnapshot.Balance], hidden: Bool) -> some View {
        VStack(alignment: .leading, spacing: .zero) {
            Text("投资").dsText(DS.Font.tSub).foregroundStyle(DS.Color.ink3)
                .frame(minHeight: DS.Space.s28).accessibilityAddTraits(.isHeader)
            ForEach(Array(balances.enumerated()), id: \.element.id) { index, balance in
                HStack(spacing: DS.Space.s12) {
                    DSIconView(icon: .acctInvest, size: DS.Size.icon, color: DS.Color.ink3)
                    VStack(alignment: .leading, spacing: OverviewSpec.headingGap) {
                        Text(balance.account.name).dsText(DS.Font.tLabel).foregroundStyle(DS.Color.ink2).lineLimit(1)
                        Text(OverviewAnalytics.monthDay(balance.updatedAt) + " 更新")
                            .dsText(DS.Font.tCaption).monospacedDigit().foregroundStyle(DS.Color.ink3)
                            .accessibilityIdentifier("overviewInvestmentDate_" + balance.account.name)
                    }
                    Spacer(minLength: .zero)
                    Text(OverviewDisplay.money(balance.amount, hidden: hidden)).dsText(DS.Font.tLabel).monospacedDigit()
                        .foregroundStyle(DS.Color.ink2).lineLimit(1).minimumScaleFactor(HomeSpec.numberMinimumScale)
                        .accessibilityIdentifier("overviewInvestmentValue_" + balance.account.name)
                    Button { store.openAccountValuation(.invest(balance.id)) } label: {
                        Text("更新").dsText(DS.Font.tPill).fontWeight(.semibold).foregroundStyle(DS.Color.ink2)
                            .lineLimit(1).minimumScaleFactor(HomeSpec.numberMinimumScale)
                            .padding(.horizontal, OverviewSpec.investButtonInset).frame(minHeight: DS.Size.iconTile)
                            .dsPill().frame(minHeight: DS.Size.tapMin).contentShape(Rectangle())
                    }.dsPressStyle().accessibilityIdentifier("overviewInvest_" + balance.account.name)
                }.frame(minHeight: OverviewSpec.investRowHeight)
                    .overlay(alignment: .top) {
                        if index > 0 { DS.Color.separator.frame(height: DS.Stroke.hairline) }
                    }
            }
        }
    }

    private func icon(_ account: Account) -> DS.Icon {
        switch account.kind {
        case .bank: .acctDebit
        case .credit: .acctCredit
        case .cash:
            if account.name.contains("支付宝") { .acctBalance }
            else if account.name.contains("微信") { .acctWallet }
            else { .acctCash }
        case .receivable: .acctBalance
        case .investment: .acctInvest
        }
    }
}
