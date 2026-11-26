import Foundation
import XCTest
@testable import YubaiCore

final class OverviewAnalyticsTests: XCTestCase {
    private let now = Dates.parse("2026-11-23 12:00:00")!

    private func date(_ value: String) -> Date { Dates.parse(value)! }

    private func sample() -> (Ledger, Account) {
        let account = Account(name: "储蓄卡", balance: 900_000, at: date("2026-09-30"))
        var ledger = Ledger()
        ledger.accounts = [account]
        ledger.cycleAnchor = .calendarMonth
        return (ledger, account)
    }

    private func expense(_ amount: Int64, _ category: String, account: Account, at day: String = "2026-11-12",
                         subcategory: String? = nil) -> Entry {
        var entry = Entry(date: date(day), amount: amount, accountID: account.id, title: subcategory ?? category, category: category)
        entry.subcategory = subcategory
        return entry
    }

    func testSpendableSpendingAndSavingCompareTheSameElapsedDays() {
        var (ledger, account) = sample()
        ledger.savingRule = .fixed(20_000)
        let income = Entry(date: date("2026-11-01"), amount: 200_000, nature: .income, accountID: account.id, title: "工资", category: "工资奖金")
        var deposit = income
        deposit.id = UUID()
        deposit.amount = 3_000
        deposit.intoFixedSavings = true
        var reserve = expense(8_000, "购物", account: account)
        reserve.fromReserve = true
        var deleted = expense(7_000, "购物", account: account)
        deleted.deletedAt = now
        let original = expense(25_000, "购物", account: account)
        var refund = Entry(date: date("2026-11-13"), amount: 5_000, nature: .refund, accountID: account.id, title: "退款", category: "购物")
        refund.relatedEntryID = original.id
        var reserveRefund = refund
        reserveRefund.id = UUID()
        reserveRefund.recoveryIntoReserve = true
        let investment = Account(name: "基金", kind: .investment, at: date("2026-09-30"))
        ledger.accounts.append(investment)
        var purchase = Entry(date: date("2026-11-13"), amount: 2_000, nature: .investBuy, accountID: account.id, title: "基金")
        purchase.otherAccountID = investment.id
        ledger.entries = [income, deposit, reserve, deleted, original, refund, reserveRefund, purchase,
                          expense(12_000, "购物", account: account, at: "2026-10-23 11:59:00"),
                          expense(9_000, "购物", account: account, at: "2026-10-23 12:01:00")]
        ledger.savingHistory = [CycleSaving(cycleStart: date("2026-10-01"), cycleEnd: date("2026-10-31"),
                                           income: 80_000, target: 15_000, saved: 15_000)]
        let result = OverviewAnalytics.review(in: ledger, selection: .current, now: now)
        XCTAssertEqual(result.spent, Finance.spendableBreakdown(ledger, now: now).spent)
        XCTAssertEqual(result.spent, 20_000)
        XCTAssertEqual(result.previousSpent, 12_000)
        XCTAssertEqual(result.saved, 25_000)
        XCTAssertEqual(result.previousSaved, 15_000)
        XCTAssertEqual(result.savedDelta, 10_000)
    }

    func testAnomalyUsesLargestRealCategoryAndStrictThreshold() {
        var (ledger, account) = sample()
        ledger.entries = [
            expense(13_000, "购物", account: account),
            expense(10_000, "购物", account: account, at: "2026-10-12"),
            expense(9_000, "吃饭", account: account),
            expense(6_000, "吃饭", account: account, at: "2026-10-12"),
            expense(8_000, "买菜", account: account),
            expense(1_000, "买菜", account: account, at: "2026-10-12")
        ]
        let result = OverviewAnalytics.review(in: ledger, selection: .current, now: now)
        XCTAssertEqual(result.anomaly?.category, "吃饭")
        XCTAssertEqual(result.slices.first?.changePercent, 30)
        XCTAssertEqual(result.slices.filter(\.isAnomaly).count, 1)
    }

    func testTopFiveAndOtherAreSortedAfterAggregation() throws {
        var (ledger, account) = sample()
        ledger.entries = [("居住", 200_010), ("购物", 131_800), ("吃饭", 126_400), ("买菜", 98_000),
                          ("娱乐", 57_800), ("交通", 31_200), ("学习", 20_650), ("医疗健康", 12_000), ("运动", 6_700)]
            .map { expense(Int64($0.1), $0.0, account: account) }
        let result = OverviewAnalytics.review(in: ledger, selection: .current, now: now)
        XCTAssertEqual(result.slices.map(\.amount), [200_010, 131_800, 126_400, 98_000, 70_550, 57_800])
        let other = try XCTUnwrap(result.slices.first(where: \.isOther))
        XCTAssertEqual(other.category, "其他 4 类")
        XCTAssertEqual(other.categories.count, 4)
        let drill = OverviewAnalytics.categoryDrill(in: ledger, title: other.category, categories: other.categories, selection: .current, now: now)
        XCTAssertEqual(drill.slices.map(\.category), other.categories)
        XCTAssertEqual(drill.totalCount, 4)
        XCTAssertNil(drill.budget)
    }

    func testSubcategoryDrillSharesComparisonAndKeepsBillOrder() {
        var (ledger, account) = sample()
        ledger.spendingParts = [SpendingPart(name: "购物", amount: 50_000, categories: ["购物"])]
        ledger.entries = [
            expense(12_000, "购物", account: account, subcategory: "服饰鞋包"),
            expense(6_000, "购物", account: account, at: "2026-10-12", subcategory: "服饰鞋包"),
            expense(1_000, "购物", account: account, at: "2026-11-17")
        ]
        let drill = OverviewAnalytics.categoryDrill(in: ledger, title: "购物", categories: ["购物"], selection: .current, now: now)
        XCTAssertEqual(drill.amount, 13_000)
        XCTAssertEqual(drill.entries.map(\.amount), [1_000, 12_000])
        XCTAssertEqual(drill.slices.first?.changePercent, 100)
        XCTAssertEqual(drill.slices.last?.category, "未分类")
        XCTAssertTrue(drill.slices.first?.isAnomaly == true)
        XCTAssertEqual(drill.budget?.name, "购物")
    }

    func testCustomRangeAndQuickRangesUseCalendarDays() {
        let (ledger, _) = sample()
        let selection = OverviewPeriodSelection.custom(start: date("2026-11-01"), end: date("2026-11-03"))
        let window = OverviewAnalytics.periodWindow(selection: selection, in: ledger, now: now)
        XCTAssertEqual(window.interval, DateInterval(start: date("2026-11-01"), end: date("2026-11-04")))
        XCTAssertEqual(window.comparison, DateInterval(start: date("2026-10-29"), end: date("2026-11-01")))
        XCTAssertEqual(OverviewQuickRange.lastThreeCycles.selection(in: ledger, now: now),
                       .custom(start: date("2026-09-01"), end: date("2026-11-23")))
        XCTAssertEqual(OverviewQuickRange.thisYear.selection(in: ledger, now: now),
                       .custom(start: date("2026-01-01"), end: date("2026-11-23")))
        XCTAssertEqual(OverviewQuickRange.samePeriodLastYear.selection(in: ledger, now: now),
                       .custom(start: date("2025-11-01"), end: date("2025-11-23")))
    }

    func testBalanceSeriesReconstructsBothSidesOfAReconciliation() throws {
        var (ledger, account) = sample()
        ledger.entries = [
            expense(1_000, "购物", account: account, at: "2026-10-25"),
            Entry(date: date("2026-11-10"), amount: 15_000, nature: .income, accountID: account.id, title: "工资", category: "工资奖金"),
            expense(3_000, "购物", account: account, at: "2026-11-20")
        ]
        try Reconciliation.reconcileAccount(&ledger, accountID: account.id, actualBalance: 910_000, now: date("2026-11-15"))
        account = try XCTUnwrap(ledger.accounts.first)
        let series = OverviewAnalytics.balanceSeries(for: account, in: ledger, now: now)
        XCTAssertEqual(series.points.count, 31)
        XCTAssertEqual(series.points[0], 900_000)
        XCTAssertEqual(series.points[1], 899_000)
        XCTAssertEqual(series.points[17], 914_000)
        XCTAssertEqual(series.points[22], 910_000)
        XCTAssertEqual(series.points.last, Finance.balance(account, in: ledger, at: now))
        XCTAssertEqual(series.highlightIndex, 17)
        XCTAssertEqual(series.highlightLabel, "11.10 工资")
        XCTAssertEqual(series.recentEntries.first?.date, date("2026-11-20"))
    }

    func testReconciliationWritesAdjustmentAndDismissesOnlyMatchingCard() throws {
        var (ledger, bank) = sample()
        let credit = Account(name: "信用卡", kind: .credit, balance: -10_000, at: date("2026-10-01"))
        ledger.accounts.append(credit)
        ledger.cards = [bank, credit].map {
            ButlerCard(kind: .staleBalance, title: $0.name, body: "", action: .reconcileAccount($0.id), dedupeKey: $0.name)
        }
        let preview = Reconciliation.preview(ledger, actual: [bank.id: 895_000], now: now)
        let adjustment = try Reconciliation.reconcileAccount(&ledger, accountID: bank.id, actualBalance: 895_000, now: now)
        XCTAssertEqual(adjustment?.amount, 5_000)
        XCTAssertEqual(adjustment?.nature, .adjustmentOut)
        XCTAssertEqual(adjustment?.source, "对余额")
        XCTAssertEqual(ledger.periodReconciliations.last?.floor, preview.floor)
        XCTAssertEqual(ledger.cards[0].dismissedAt, now)
        XCTAssertNil(ledger.cards[1].dismissedAt)
        let creditAdjustment = try Reconciliation.reconcileAccount(&ledger, accountID: credit.id, actualBalance: -7_500, now: now)
        XCTAssertEqual(creditAdjustment?.nature, .adjustmentIn)
        XCTAssertEqual(creditAdjustment?.amount, 2_500)
        XCTAssertEqual(ledger.cards[1].dismissedAt, now)
        XCTAssertEqual(OverviewAnalytics.assets(in: ledger, now: now).accounts.last?.lastReconciledAt, now)
    }

    func testInvestmentRevaluationDoesNotChangeSpendableOrCreateEntries() throws {
        var (ledger, _) = sample()
        let investment = Account(name: "基金", kind: .investment, balance: 4_123_600, at: date("2026-11-01"))
        ledger.accounts.append(investment)
        let before = Finance.spendableBreakdown(ledger, now: now)
        let delta = try Reconciliation.revalueInvestment(&ledger, accountID: investment.id, newValue: 4_201_850, now: now)
        XCTAssertEqual(delta, 78_250)
        XCTAssertEqual(ledger.entries.count, 0)
        XCTAssertEqual(Finance.spendableBreakdown(ledger, now: now), before)
        let assets = OverviewAnalytics.assets(in: ledger, now: now)
        XCTAssertEqual(assets.investments.first?.amount, 4_201_850)
        XCTAssertEqual(assets.investments.first?.updatedAt, now)
    }
}
