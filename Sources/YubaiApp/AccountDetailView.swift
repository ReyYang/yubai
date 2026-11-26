import SwiftUI
import YubaiCore

struct AccountDetailView: View {
    let accountID: UUID
    @Environment(AppStore.self) private var store

    var body: some View {
        let _ = OverviewRenderCounts.hit("accountBody")
        if let account = store.accounts.first(where: { $0.id == accountID }) {
            let now = store.financialNow
            let hidden = store.preferences.hideAmounts
            let series = OverviewAnalytics.balanceSeries(for: account, in: store.current, now: now)
            let balance = store.balance(account, at: now)
            VStack(spacing: .zero) {
                OverviewNavigationBar(title: account.name) { store.present(.account(account)) }
                ScrollView {
                    VStack(alignment: .leading, spacing: .zero) {
                        header(account, balance: balance, hidden: hidden)
                        if !account.archived {
                            actions(account).padding(.top, OverviewSpec.totalsTop)
                        }
                        DSBalanceChart(values: series.points, startLabel: series.startLabel, highlightLabel: series.highlightLabel,
                                       highlightIndex: series.highlightIndex, endLabel: series.endLabel, hidesAmounts: hidden)
                            .padding(.top, DS.Space.s20)
                        recent(series.recentEntries.filter { store.overviewFixture == nil || $0.source != OverviewFixture.chartClearingSource },
                               now: now, hidden: hidden).padding(.top, DS.Space.s16)
                    }.padding(.horizontal, DS.Space.s20).padding(.bottom, DS.Space.s20)
                }.accessibilityIdentifier("overviewAccountScroll")
            }.background(DS.Color.bg.ignoresSafeArea())
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("accountDetailPage")
                .dsEdgeSwipeBack()
                #if os(iOS)
                .toolbar(.hidden, for: .navigationBar)
                #endif
        }
    }

    private func header(_ account: Account, balance: Int64, hidden: Bool) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            Text(OverviewDisplay.money(balance, hidden: hidden)).dsText(DS.Font.nHero)
                .foregroundStyle(DS.Color.ink).lineLimit(1).minimumScaleFactor(HomeSpec.numberMinimumScale)
                .accessibilityLabel(hidden ? "金额已隐藏" : OverviewDisplay.money(balance, hidden: false))
                .accessibilityIdentifier("overviewAccountBalance")
            if account.kind != .investment, let date = account.lastReconciledAt {
                Text(OverviewAnalytics.monthDay(date) + " 核对过")
                    .dsText(DS.Font.tSub).monospacedDigit().foregroundStyle(DS.Color.ink3)
                    .accessibilityIdentifier("overviewAccountReconciled")
            }
        }.padding(.top, OverviewSpec.drillTop).dsFillWidth()
    }

    @ViewBuilder private func actions(_ account: Account) -> some View {
        if account.kind == .investment {
            DSButton("更新") { store.openAccountValuation(.invest(account.id)) }
                .accessibilityIdentifier("overviewInvest_" + account.name)
        } else {
            GeometryReader { geometry in
                let width = max(0, geometry.size.width - DS.Space.s12) * OverviewSpec.accountPrimaryShare
                HStack(spacing: DS.Space.s12) {
                    action("核对余额", icon: .done, primary: true, identifier: "reconcileAccount") {
                        store.openAccountValuation(.reconcile(account.id))
                    }.frame(width: width)
                    action("转账", icon: .transfer, primary: false, identifier: "overviewTransfer") {
                        store.openEntrySheet(QuickEntryPrefill(category: nil, amount: nil, purpose: nil,
                                                               nature: .transfer, accountID: account.id, date: store.financialNow))
                    }
                }
            }.frame(height: OverviewSpec.accountActionHeight)
        }
    }

    private func action(_ title: String, icon: DS.Icon, primary: Bool, identifier: String,
                        tap: @escaping () -> Void) -> some View {
        let tint = primary ? DS.Color.onAccent : DS.Color.ink
        return Button(action: tap) {
            HStack(spacing: DS.Space.s8) {
                DSIconView(icon: icon, size: DS.Size.brandTile, color: tint)
                Text(title).dsText(DS.Font.tLabel).fontWeight(primary ? .semibold : .medium)
                    .foregroundStyle(tint).lineLimit(1).minimumScaleFactor(HomeSpec.numberMinimumScale)
            }
            .frame(maxWidth: .infinity, minHeight: OverviewSpec.accountActionHeight)
            .dsSurface(primary ? DS.Color.accent : DS.Color.raised, radius: DS.Radius.s)
            .overlay {
                if !primary {
                    RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous)
                        .strokeBorder(DS.Color.separator, lineWidth: DS.Stroke.hairline)
                }
            }
        }.dsPressStyle().accessibilityIdentifier(identifier)
    }

    private func recent(_ entries: [Entry], now: Date, hidden: Bool) -> some View {
        VStack(alignment: .leading, spacing: .zero) {
            Text("最近流水").dsText(DS.Font.tSub).foregroundStyle(DS.Color.ink2)
                .frame(minHeight: DS.Size.chipH).accessibilityAddTraits(.isHeader)
            ForEach(Array(entries.prefix(5).enumerated()), id: \.element.id) { index, entry in
                OverviewBillRow(entry: entry, amount: HomeDisplay.signed(entry.delta(for: accountID), hidden: hidden),
                                date: OverviewDisplay.day(entry.postingDate(for: accountID), now: now),
                                tint: entry.nature == .income ? DS.Color.accentInk : DS.Color.ink,
                                separator: index > 0) { store.billCardID = entry.id }
            }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("overviewRecentEntries")
    }
}

#if DEBUG
#Preview("账户详情") {
    RootView().environment(AppStore(overviewFixture: .account))
}
#endif
