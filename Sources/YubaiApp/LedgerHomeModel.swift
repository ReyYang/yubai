import Foundation
import YubaiCore

/// The ledger hero consumes the canonical period model, including its fallback.
struct LedgerHomeModel: Equatable {
    var isFirstOpen: Bool
    var headlineLabel: String
    var headlineAmount: Int64
    var headlineIsAmber: Bool
    var periodLine: String
    var showsFormula: Bool
    var waterFill: Double?
    var waterTick: Double
    var waterFast: Bool
    var savedTotal: Int64?
    var statusLine: String?
    var gapBillText: String?
    var categorySoftLineStatus: [String: String]

    @MainActor static func make(_ store: AppStore) -> Self {
        let funds = store.funds
        let value = Finance.spendableBreakdown(store.current, now: store.financialNow)
        let saving = store.homeSaving
        let gapBill: String?
        if case .deficit(_, let bill) = value.state {
            gapBill = bill.map { FixedFlowPresentation.monthDay($0.date) + " " + $0.title }
        } else { gapBill = nil }
        let period: String
        if funds.cycleIsPayday && Dates.day(value.cycleStart) == Dates.day(store.financialNow) {
            period = "今天发工资"
        } else if funds.cycleIsPayday, let late = funds.salaryLateDays {
            period = late == 0 ? "今天发工资" : "工资晚了 \(late) 天"
        } else if funds.cycleIsPayday {
            period = FixedFlowPresentation.monthDay(Dates.addDays(1, to: value.cycleEnd)) + "发工资 · 还有 \(value.daysLeft) 天"
        } else { period = "还有 \(value.daysLeft) 天" }
        let less: String?
        if case .savingLess(let amount) = value.state {
            less = "这个月少攒 " + (store.current.preferences.hideAmounts ? "¥••••" : Money.text(amount))
        }
        else { less = nil }
        var statuses: [String: String] = [:]
        for (category, lines) in store.categorySoftLines {
            statuses[category] = lines.map { SoftLineText.status($0, hide: false, includesTitle: true) }.joined(separator: " · ")
        }
        return Self(isFirstOpen: store.homeHero.isFirstOpen,
                    headlineLabel: value.headlineTitle, headlineAmount: value.headlineAmount,
                    headlineIsAmber: value.deficit > 0, periodLine: value.offersFormula ? period : "",
                    showsFormula: value.offersFormula, waterFill: value.waterBar?.fill,
                    waterTick: value.waterBar?.tick ?? 0, waterFast: value.waterBar?.fast ?? false,
                    savedTotal: saving.started ? saving.total : nil, statusLine: less,
                    gapBillText: gapBill, categorySoftLineStatus: statuses)
    }
}
