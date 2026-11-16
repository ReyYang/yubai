import SwiftUI
import YubaiCore

private enum InsightPeriod: String, CaseIterable {
    case current = "这一期", previous = "上一期", year = "今年"
}

struct InsightsTabView: View {
    @Environment(AppStore.self) private var store
    @State private var period = InsightPeriod.current
    @State private var model: InsightsPageModel?
    private var hide: Bool { store.preferences.hideAmounts }
    var body: some View {
        Page(topPadding: YubaiSpace.space4, identifier: "insightsScroll", rootTab: .insights) {
            if store.sortedEntries.allSatisfy({ $0.deletedAt != nil }) {
                EmptyState(.ledger, onAction: { store.requestCaptureSheet(.addEntry) }, onSecondary: { store.tabRouteRequest = .imports })
            } else {
                Segmented(choices: InsightPeriod.allCases.map { ($0, $0.rawValue) }, selection: $period,
                          identifier: { "insightsPeriod_" + $0.rawValue })
                if let model {
                    numbers(model)
                    if !model.categories.isEmpty { categories(model) }
                    if let cash = model.cash { cashCard(cash) }
                } else { ProgressView() }
            }
        }.rootScrollContentMargins(for: .insights)
            .rootPageHeader { RootHeader(title: "洞察") }
            .navigationTitle("洞察").yubaiNavigation().amountPrivacy(hide)
            #if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
            #endif
            .task(id: "\(period.rawValue)-\(store.ledgerRevision)-\(store.financialNow)") {
                let ledger = store.current, now = store.financialNow, choice = period
                let result = await Task.detached(priority: .userInitiated) { InsightsPageModel.make(ledger, period: choice.rawValue, now: now) }.value
                guard !Task.isCancelled else { return }; model = result
            }
    }
    private func numbers(_ model: InsightsPageModel) -> some View {
        Card {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: YubaiSpace.space20) {
                    number("收入", model.income, brand: true); number("支出", model.spending); number("结余", model.balance)
                }
                VStack(alignment: .leading, spacing: YubaiSpace.space12) {
                    number("收入", model.income, brand: true); number("支出", model.spending); number("结余", model.balance)
                }
            }
        }.accessibilityIdentifier("insightsTotals")
    }
    private func number(_ label: String, _ amount: Int64, brand: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: YubaiSpace.space2) {
            Text(label).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
            AmountLabel(cents: amount, hide: hide, role: .summary, currency: false, ink: brand ? YubaiColor.brandInk : YubaiColor.label)
                .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("insightsAmount_" + label)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func categories(_ model: InsightsPageModel) -> some View {
        let status = store.categorySoftLines
        return VStack(alignment: .leading, spacing: YubaiSpace.space8) {
            SectionHeading(title: "钱去了哪").padding(.horizontal, YubaiSpace.space4)
            CardRows(Array(model.categories.enumerated()).map { InsightCategory(index: $0.offset, value: $0.element) }) { row in
                TabNavigationLink(.whereCategory(category: row.value.title, interval: model.interval)) {
                    WhereCategoryView(category: row.value.title, interval: model.interval)
                } label: {
                    VStack(alignment: .leading, spacing: YubaiSpace.space6) {
                        AdaptiveValueRow {
                            VStack(alignment: .leading, spacing: YubaiSpace.space2) {
                                Text(Classification.displayCategory(row.value.title)).yubaiFont(YubaiFont.rowTitle).lineLimit(1)
                                ForEach(status[row.value.title] ?? []) { line in
                                    Text(SoftLineText.status(line, hide: hide, includesTitle: true)).yubaiFont(YubaiFont.caption)
                                        .foregroundStyle(line.isExceeded ? YubaiColor.amberInk : YubaiColor.labelSecondary)
                                        .accessibilityIdentifier("insightSoftLine_" + line.id)
                                }
                            }
                        } value: {
                            HStack(spacing: YubaiSpace.space4) {
                                AmountLabel(cents: row.value.amount, hide: hide, currency: false)
                                Image(systemName: "chevron.right").yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary)
                            }
                        }
                        ProportionalBar(fraction: row.value.share)
                    }.padding(.vertical, YubaiSpace.space8).contentShape(Rectangle())
                }.buttonStyle(PressButtonStyle()).accessibilityIdentifier("insightCategory_\(row.index)")
            }
        }.accessibilityIdentifier("insightsCategories")
    }
    private func cashCard(_ model: CashMonthModel) -> some View {
        VStack(alignment: .leading, spacing: YubaiSpace.space8) {
            SectionHeading(title: "现金这个月").padding(.horizontal, YubaiSpace.space4)
            Card {
                VStack(alignment: .leading, spacing: YubaiSpace.space20) {
                    AdaptiveValueRow {
                        cashNumber("今天手上", model.current)
                    } value: {
                        cashNumber(FixedFlowPresentation.monthDay(model.end) + "大约", model.closing)
                    }
                    if !hide { CashCurve(history: model.history, forecast: model.forecast, start: model.start, end: model.end) }
                    ChipFlow {
                        Text(FixedFlowPresentation.monthDay(model.start))
                        Text("今天")
                        if let bill = model.bill {
                            TabNavigationLink(.billDetail(bill.planID)) { BillDetailView(planID: bill.planID) } label: {
                                Text(FixedFlowPresentation.monthDay(bill.date) + " " + bill.title).lineLimit(1)
                            }.buttonStyle(TextLinkStyle()).accessibilityIdentifier("cashMonthBill")
                        }
                        Text(FixedFlowPresentation.monthDay(model.end))
                    }.yubaiFont(YubaiFont.chartLabel).foregroundStyle(YubaiColor.labelSecondary)
                }
            }
        }.accessibilityIdentifier("cashMonthCard")
    }
    private func cashNumber(_ label: String, _ value: Int64) -> some View {
        VStack(alignment: .leading, spacing: YubaiSpace.space2) {
            Text(label).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
            AmountLabel(cents: value, hide: hide, role: .summary, currency: false)
        }
    }
    private struct InsightCategory: Identifiable {
        let index: Int
        let value: CashFlowSlice
        var id: String { value.title }
    }
}

/// Presentation sampling of existing Finance cash balances and conservative
/// forecast points. All aggregation/forecast calculations remain in Core.
struct InsightsPageModel: Sendable {
    var interval: DateInterval
    var income: Int64
    var spending: Int64
    var balance: Int64
    var categories: [CashFlowSlice]
    var cash: CashMonthModel?
    static func make(_ ledger: Ledger, period: String, now: Date) -> Self {
        let cycle = Finance.cycle(in: ledger, now: now)
        let interval: DateInterval
        if period == "上一期" {
            interval = Finance.pastCycles(ledger, now: now, limit: 1).first ?? DateInterval(start: Dates.addMonths(-1, to: cycle.start), end: cycle.start)
        } else if period == "今年" {
            interval = DateInterval(start: Dates.calendar.dateInterval(of: .year, for: now)!.start, end: now.addingTimeInterval(0.001))
        } else { interval = DateInterval(start: cycle.start, end: now.addingTimeInterval(0.001)) }
        var posted = ledger
        posted.entries.removeAll { $0.date > now }
        let flow = Finance.cashFlow(posted, during: interval)
        return Self(interval: interval, income: flow.income, spending: flow.spending, balance: flow.balance,
                    categories: SavingInsights.categoryShares(posted, during: interval).sorted { $0.amount > $1.amount },
                    cash: CashMonthModel.make(ledger, now: now))
    }
}

struct CashMonthModel: Sendable {
    struct Bill: Sendable { var planID: UUID; var title: String; var date: Date }
    var start: Date
    var end: Date
    var current: Int64
    var closing: Int64
    var history: [CashCurvePoint]
    var forecast: [CashCurvePoint]
    var bill: Bill?
    static func make(_ ledger: Ledger, now: Date) -> Self? {
        let accounts = ledger.accounts.filter { $0.kind == .cash || $0.kind == .bank }
        guard !accounts.isEmpty else { return nil }
        let funds = Finance.funds(ledger, now: now)
        let today = Dates.day(now), start = funds.cycleStart, end = funds.cycleEnd
        let count = max(0, Dates.calendar.dateComponents([.day], from: start, to: today).day ?? 0)
        let history = (0...count).map { offset -> CashCurvePoint in
            let day = Dates.addDays(offset, to: start)
            let at = min(now, Dates.addDays(1, to: day).addingTimeInterval(-0.001))
            return CashCurvePoint(date: day, amount: accounts.reduce(0) { $0 + Finance.balance($1, in: ledger, at: at) })
        }
        let current = history.last?.amount ?? funds.cash
        let baseline = funds.points.first?.conservative ?? current
        let forecast = [CashCurvePoint(date: today, amount: current)] + funds.points.filter { $0.date > today && $0.date <= end }.map {
            CashCurvePoint(date: $0.date, amount: current + $0.conservative - baseline)
        }
        let bill = funds.occurrences.filter { !$0.inflow && $0.planID != nil && $0.date <= end }.max { $0.amount < $1.amount }
        return Self(start: start, end: end, current: current, closing: forecast.last?.amount ?? current,
                    history: history, forecast: forecast,
                    bill: bill.flatMap { row in row.planID.map { Bill(planID: $0, title: row.title, date: row.date) } })
    }
}
