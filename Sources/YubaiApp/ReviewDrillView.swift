import SwiftUI
import YubaiCore

struct ReviewDrillView: View {
    let title: String
    let categories: [String]
    let isOther: Bool
    let selection: OverviewPeriodSelection
    /// Opened from the 多花 card: same 口径 as the card, or the plain category page once it is no longer 多花.
    var anomaly = false
    @Environment(AppStore.self) private var store

    var body: some View {
        let _ = OverviewRenderCounts.hit("drillBody")
        let now = store.financialNow
        let data = (anomaly ? OverviewAnalytics.anomalyDrill(in: store.current, category: title, selection: selection, now: now) : nil)
            ?? OverviewAnalytics.categoryDrill(in: store.current, title: title, categories: categories, isOther: isOther, selection: selection, now: now)
        let hidden = store.preferences.hideAmounts
        // The 退款 row is money back, not a share of the spending: neutral, and outside the bar.
        let colors = DSChartPalette.colors(anomalies: data.slices.filter { $0.amount > 0 }.map(\.isAnomaly))
            + data.slices.filter { $0.amount < 0 }.map { _ in DS.Color.track }
        VStack(spacing: .zero) {
            OverviewNavigationBar(title: data.title)
            ScrollView {
                VStack(alignment: .leading, spacing: .zero) {
                    header(data, hidden: hidden)
                    if !data.slices.isEmpty {
                        subcategories(data.slices, colors: colors, hidden: hidden).padding(.top, OverviewSpec.sectionTop)
                    }
                    bills(data, colors: colors, now: now, hidden: hidden).padding(.top, OverviewSpec.drillBillsTop)
                    if let budget = data.budget {
                        budgetLink(budget, hidden: hidden).padding(.top, DS.Space.s4)
                    }
                }.padding(.horizontal, DS.Space.s20).padding(.bottom, DS.Space.s20)
            }.accessibilityIdentifier("overviewDrillScroll")
        }
        .background(DS.Color.bg.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("reviewDrillPage")
        .dsEdgeSwipeBack()
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
    }

    private func header(_ data: OverviewCategoryDrill, hidden: Bool) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            Text(OverviewDisplay.money(data.amount, hidden: hidden)).dsText(DS.Font.nHero)
                .foregroundStyle(DS.Color.ink).lineLimit(1).minimumScaleFactor(HomeSpec.numberMinimumScale)
                .accessibilityLabel(hidden ? "金额已隐藏" : OverviewDisplay.money(data.amount, hidden: false))
                .accessibilityIdentifier("overviewDrillAmount")
            if let cycles = data.baselineCycles {
                let difference = data.amount - data.previous
                Text("近 \(cycles) 期同期平均 " + OverviewDisplay.money(data.previous, hidden: hidden)
                     + (hidden ? "" : " · 多 " + OverviewDisplay.money(difference, hidden: false)))
                    .dsText(DS.Font.tPill).monospacedDigit().fontWeight(.semibold).foregroundStyle(DS.Color.warnInk)
                    .accessibilityIdentifier("overviewDrillBaseline")
            } else if !hidden, let change = data.changePercent {
                let difference = data.amount - data.previous
                Text("比上期同期 " + OverviewDisplay.percent(change)
                     + (difference == 0 ? "" : (difference < 0 ? " · 少 " : " · 多 ") + OverviewDisplay.money(abs(difference), hidden: false)))
                    .dsText(DS.Font.tPill).monospacedDigit().fontWeight(data.isAnomaly ? .semibold : .regular)
                    .foregroundStyle(data.isAnomaly ? DS.Color.warnInk : DS.Color.ink3)
            }
        }.padding(.top, OverviewSpec.drillTop)
    }

    private func subcategories(_ rows: [OverviewCategorySlice], colors: [Color], hidden: Bool) -> some View {
        let total = rows.reduce(Int64(0)) { $0 + max(0, $1.amount) }
        return VStack(alignment: .leading, spacing: .zero) {
            Text("小类").dsText(DS.Font.tSubStrong).foregroundStyle(DS.Color.ink3)
                .accessibilityAddTraits(.isHeader).padding(.bottom, DS.Space.s8)
            DSStackedBar(segments: rows.enumerated().filter { $0.element.amount > 0 }.map { index, row in
                .init(id: row.id, value: Double(row.amount), color: colors[index])
            }, hidesAmounts: hidden).padding(.bottom, DS.Space.s4)
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                DSOverviewLegendRow(name: row.category, amount: OverviewDisplay.money(row.amount, hidden: hidden), color: colors[index],
                                    share: hidden || row.amount < 0 ? nil : OverviewDisplay.share(row.amount, of: total),
                                    delta: hidden ? nil : row.changePercent.map(OverviewDisplay.percent),
                                    isAnomaly: row.isAnomaly, isDrill: true)
                    .frame(minHeight: OverviewSpec.drillRowHeight)
                    .overlay(alignment: .top) {
                        if index > 0 { DS.Color.separator.frame(height: DS.Stroke.hairline) }
                    }.accessibilityIdentifier("overviewSubcategory_" + row.id)
            }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("overviewDrillBreakdown")
    }

    private func bills(_ data: OverviewCategoryDrill, colors: [Color], now: Date, hidden: Bool) -> some View {
        let byGroup = Dictionary(uniqueKeysWithValues: zip(data.slices.map(\.id), colors))
        return VStack(alignment: .leading, spacing: .zero) {
            let choice: String = switch selection {
            case .current: "本期"
            case .previous: "上期"
            case .custom: ""
            }
            Text("\(choice)\(data.title)账单 · \(data.totalCount.formatted()) 笔")
                .dsText(DS.Font.tSubStrong).foregroundStyle(DS.Color.ink3)
                .accessibilityAddTraits(.isHeader).padding(.bottom, DS.Space.s4)
            ForEach(Array(data.entries.prefix(5).enumerated()), id: \.element.id) { index, entry in
                let color = data.entryGroups[entry.id].flatMap { byGroup[$0] } ?? DS.Color.track
                OverviewBillRow(entry: entry, amount: HomeDisplay.billAmount(entry, hidden: hidden),
                                date: OverviewDisplay.day(entry.date, now: now),
                                tint: entry.nature.inflow ? DS.Color.accentInk : DS.Color.ink,
                                swatch: color, separator: index > 0) { store.billCardID = entry.id }
            }
            if data.totalCount > 0 {
                Button {
                    store.tabRouteRequest = .overviewBills(Set(categories), data.window.interval, Set(data.entries.map(\.id)))
                } label: {
                    HStack(spacing: DS.Space.s4) {
                        Text("看全部 \(data.totalCount.formatted()) 笔").dsText(DS.Font.tLabelStrong)
                        DSIconView(icon: .chevron, size: DS.Space.s12, color: DS.Color.accentInk)
                    }
                    .foregroundStyle(DS.Color.accentInk).frame(minHeight: DS.Size.tapMin)
                    .contentShape(Rectangle())
                }.dsPressStyle().accessibilityIdentifier("overviewSeeAll")
            }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("whereCategoryEntries")
    }

    private func budgetLink(_ budget: HomeBudget, hidden: Bool) -> some View {
        Button { store.tabRouteRequest = .formula } label: {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s4) {
                Text("预算还剩").dsText(DS.Font.tPill).foregroundStyle(DS.Color.ink2)
                Spacer(minLength: .zero)
                Text(OverviewDisplay.money(budget.remaining, hidden: hidden)).dsText(DS.Font.tPill)
                    .monospacedDigit().fontWeight(.semibold)
                    .foregroundStyle(budget.fraction >= DSInteraction.warningFraction ? DS.Color.warnInk : DS.Color.ink)
                Text("/ " + OverviewDisplay.money(budget.amount, hidden: hidden)).dsText(DS.Font.tCaption)
                    .monospacedDigit().foregroundStyle(DS.Color.ink3)
            }.lineLimit(1).minimumScaleFactor(HomeSpec.numberMinimumScale)
                .padding(.horizontal, OverviewSpec.budgetInset).frame(minHeight: OverviewSpec.drillRowHeight)
                .dsSurface(DS.Color.surface, radius: DS.Radius.s)
        }.dsPressStyle().accessibilityIdentifier("overviewBudget")
    }
}
