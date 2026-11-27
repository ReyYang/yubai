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

    private func history(_ amounts: [String: Int64], account: Account, months: [String] = ["2026-08", "2026-09", "2026-10"]) -> [Entry] {
        months.flatMap { month in amounts.map { expense($0.value, $0.key, account: account, at: month + "-12") } }
    }

    func testAnomalyUsesThreePeriodBaselineAndLargestExcess() {
        var (ledger, account) = sample()
        ledger.entries = history(["吃饭": 100_000, "购物": 200_000, "交通": 9_000], account: account) + [
            expense(160_000, "吃饭", account: account),   // +60%, 多 600
            expense(300_000, "购物", account: account),   // +50%, 多 1,000 → largest excess wins
            expense(12_900, "交通", account: account)     // +43% but only 39 more
        ]
        let result = OverviewAnalytics.review(in: ledger, selection: .current, now: now)
        XCTAssertEqual(result.anomaly?.category, "购物")
        XCTAssertEqual(result.anomaly?.amount, 300_000)
        XCTAssertEqual(result.anomaly?.previous, 200_000)
        XCTAssertEqual(result.anomalyBaselineCycles, 3)
        XCTAssertEqual(result.slices.filter(\.isAnomaly).map(\.category), ["购物"])
        XCTAssertTrue(OverviewAnalytics.categoryDrill(in: ledger, title: "购物", categories: ["购物"], isOther: false, selection: .current, now: now).isAnomaly)
    }

    func testAnomalyDrillMatchesTheCardAndLeavesExcludedBillsOut() {
        var (ledger, account) = sample()
        var fixed = expense(70_000, "购物", account: account); fixed.planID = UUID()
        var pending = expense(40_000, "购物", account: account); pending.pendingRecovery = .reimbursement
        ledger.entries = history(["购物": 200_000], account: account) + [
            expense(180_000, "购物", account: account, subcategory: "衣服"),
            expense(120_000, "购物", account: account, subcategory: "数码"),
            fixed, pending
        ]
        let card = OverviewAnalytics.review(in: ledger, selection: .current, now: now)
        let anomaly = try! XCTUnwrap(card.anomaly)
        let drill = try! XCTUnwrap(OverviewAnalytics.anomalyDrill(in: ledger, category: "购物", selection: .current, now: now))
        XCTAssertEqual(drill.amount, anomaly.amount)
        XCTAssertEqual(drill.amount, 300_000, "the planned bill and the pending reimbursement stay out")
        XCTAssertEqual(drill.previous, anomaly.previous)
        XCTAssertEqual(drill.baselineCycles, card.anomalyBaselineCycles)
        XCTAssertEqual(drill.entries.count, 2)
        XCTAssertEqual(drill.slices.map(\.category), ["衣服", "数码"])
        XCTAssertNil(OverviewAnalytics.anomalyDrill(in: ledger, category: "吃饭", selection: .current, now: now))
        // The plain category page still counts everything in 购物.
        XCTAssertEqual(OverviewAnalytics.categoryDrill(in: ledger, title: "购物", categories: ["购物"], isOther: false,
                                                       selection: .current, now: now).amount, 410_000)
    }

    func testUnsortedListsTheEntriesToOrganize() {
        var (ledger, bank) = sample()
        let pending = expense(50_000, Classification.pendingCategory, account: bank)
        ledger.entries = [pending, expense(80_000, "购物", account: bank)]
        XCTAssertEqual(OverviewAnalytics.review(in: ledger, selection: .current, now: now).unsortedEntryIDs, [pending.id])
    }

    func testAnomalyNeedsExcessOverThirtyPercentAndAtLeastOneHundred() {
        var (ledger, account) = sample()
        ledger.entries = history(["吃饭": 100_000, "交通": 9_000], account: account)
            + [expense(148_000, "吃饭", account: account), expense(12_900, "交通", account: account)]
        let result = OverviewAnalytics.review(in: ledger, selection: .current, now: now)
        XCTAssertEqual(result.anomaly?.category, "吃饭")
        XCTAssertEqual(result.anomaly.map { $0.amount - $0.previous }, 48_000)
        ledger.entries[ledger.entries.count - 2].amount = 130_000
        XCTAssertNil(OverviewAnalytics.review(in: ledger, selection: .current, now: now).anomaly)
    }

    func testRentFixedBillsAndPendingRecoveryNeverBecomeAnAnomaly() {
        var (ledger, account) = sample()
        var rent = expense(331_000, "居住", account: account); rent.rentID = UUID()
        var fixed = expense(80_000, "会员订阅", account: account); fixed.planID = UUID()
        var aa = expense(90_000, "吃饭", account: account); aa.pendingRecovery = .split
        ledger.entries = history(["居住": 10_000, "会员订阅": 10_000, "吃饭": 100_000], account: account)
            + [rent, fixed, aa, expense(100_000, "吃饭", account: account)]
        XCTAssertNil(OverviewAnalytics.review(in: ledger, selection: .current, now: now).anomaly)
    }

    func testCatchAllAndExcludedBillsNeverShapeAnomaly() {
        var (ledger, account) = sample()
        ledger.entries = history(["其他支出": 20_000], account: account) + [expense(35_000, "其他支出", account: account)]
        XCTAssertNil(OverviewAnalytics.review(in: ledger, selection: .current, now: now).anomaly)
        var bill = expense(80_000, "居住", account: account, at: "2026-08-12"); bill.planID = UUID()
        ledger.entries = history(["吃饭": 50_000], account: account, months: ["2026-09", "2026-10"]) + [bill, expense(55_000, "吃饭", account: account)]
        let result = OverviewAnalytics.review(in: ledger, selection: .current, now: now)
        XCTAssertNil(result.anomaly); XCTAssertEqual(result.anomalyBaselineCycles, 0)
    }

    func testAnomalyThresholdUsesTheExactAverage() {
        var (ledger, account) = sample()
        ledger.entries = history(["吃饭": 40_000], account: account, months: ["2026-09"])
            + history(["吃饭": 40_001], account: account, months: ["2026-10"]) + [expense(52_001, "吃饭", account: account)]
        let result = OverviewAnalytics.review(in: ledger, selection: .current, now: now)
        XCTAssertEqual(result.anomaly?.category, "吃饭"); XCTAssertEqual(result.anomaly?.previous, 40_001)
    }

    func testAnomalyNeedsTwoEarlierPeriodsAndANonzeroBaseline() {
        var (ledger, account) = sample()
        ledger.entries = history(["吃饭": 100_000], account: account, months: ["2026-10"])
            + [expense(200_000, "吃饭", account: account)]
        XCTAssertNil(OverviewAnalytics.review(in: ledger, selection: .current, now: now).anomaly)
        ledger.entries += history(["吃饭": 100_000], account: account, months: ["2026-09"])
        XCTAssertEqual(OverviewAnalytics.review(in: ledger, selection: .current, now: now).anomalyBaselineCycles, 2)
        ledger.entries.append(expense(50_000, "旅行", account: account))
        XCTAssertEqual(OverviewAnalytics.review(in: ledger, selection: .current, now: now).anomaly?.category, "吃饭")
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
        let drill = OverviewAnalytics.categoryDrill(in: ledger, title: other.category, categories: other.categories, isOther: true, selection: .current, now: now)
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
        let drill = OverviewAnalytics.categoryDrill(in: ledger, title: "购物", categories: ["购物"], isOther: false, selection: .current, now: now)
        XCTAssertEqual(drill.amount, 13_000)
        XCTAssertEqual(drill.entries.map(\.amount), [1_000, 12_000])
        XCTAssertEqual(drill.slices.first?.changePercent, 100)
        XCTAssertEqual(drill.slices.last?.category, "未分类")
        XCTAssertFalse(drill.isAnomaly) // one earlier period is not enough for 多花
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

    func testLegacyFloorIsAPartitionOfDecodedSavings() throws {
        var (ledger, _) = sample()
        ledger.profile.floorAmount = 500_000
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(ledger)) as? [String: Any])
        json.removeValue(forKey: "fixedSavings")
        let legacy = try JSONDecoder().decode(Ledger.self, from: JSONSerialization.data(withJSONObject: json))
        let assets = OverviewAnalytics.assets(in: legacy, now: now)
        XCTAssertEqual(assets.liquidCash, 500_000)
        XCTAssertEqual(assets.floorAmount, 500_000)
        XCTAssertEqual(assets.reserveAmount, 0)

        ledger.fixedSavings = 125_000
        XCTAssertEqual(OverviewAnalytics.assets(in: ledger, now: now).floorAmount, 125_000)
    }

    func testClosedSavingsFallbackAndMixedPartialHistory() {
        var (ledger, bank) = sample()
        ledger.savingRule = .fixed(20_000)
        ledger.entries = ["2026-09-12", "2026-10-12", "2026-11-12"].map {
            Entry(date: date($0), amount: 100_000, nature: .income, accountID: bank.id, title: "工资", category: "工资奖金")
        }
        let withoutHistory = OverviewAnalytics.review(in: ledger, selection: .previous, now: now)
        XCTAssertEqual(withoutHistory.saved, 20_000)

        ledger.savingHistory = [
            CycleSaving(cycleStart: date("2026-09-01"), cycleEnd: date("2026-09-30"),
                        income: 100_000, target: 12_000, saved: 12_000),
        ]
        let partial = OverviewAnalytics.review(in: ledger, selection: .custom(start: date("2026-09-15"), end: date("2026-11-15")), now: now)
        XCTAssertEqual(partial.saved, 52_000, "Each overlapping cycle contributes its set-aside once")
        let activeOnly = OverviewAnalytics.review(in: ledger, selection: .custom(start: date("2026-11-15"), end: date("2026-11-17")), now: now)
        XCTAssertEqual(activeOnly.saved, 20_000)
    }

    func testPreviousUsesRecordedCycleAfterAnchorChange() {
        var (ledger, bank) = sample()
        ledger.savingHistory = [
            CycleSaving(cycleStart: date("2026-09-24 02:00:00"), cycleEnd: date("2026-10-24"),
                        income: 90_000, target: 18_000, saved: 17_000),
        ]
        ledger.entries = [expense(5_000, "购物", account: bank, at: "2026-09-25"),
                          expense(4_000, "购物", account: bank, at: "2026-10-25")]
        let previous = OverviewAnalytics.review(in: ledger, selection: .previous, now: now)
        XCTAssertEqual(previous.window.interval.start, date("2026-09-24 02:00:00"))
        XCTAssertEqual(previous.window.displayedRange.upperBound, date("2026-10-24"))
        XCTAssertEqual(previous.saved, 17_000)
        XCTAssertEqual(previous.spent, 5_000)
    }

    func testCurrentIncludesNowAndDepositsUseDestinationPosting() {
        var (ledger, bank) = sample()
        let reserve = Account(name: "存款", at: date("2026-10-01"))
        ledger.accounts.append(reserve)
        var transfer = Entry(date: date("2026-10-31"), amount: 7_000, nature: .transfer, accountID: bank.id, title: "存入")
        transfer.otherAccountID = reserve.id
        transfer.otherDate = now
        transfer.intoFixedSavings = true
        ledger.entries = [transfer, expense(3_000, "购物", account: bank, at: "2026-11-23 12:00:00"),
                          expense(1_000, "购物", account: bank, at: "2026-11-23 12:00:01")]
        let result = OverviewAnalytics.review(in: ledger, selection: .current, now: now)
        XCTAssertEqual(result.spent, 3_000)
        XCTAssertEqual(result.saved, 7_000)
        let drill = OverviewAnalytics.categoryDrill(in: ledger, title: "购物", categories: ["购物"], isOther: false, selection: .current, now: now)
        XCTAssertTrue(drill.entries.allSatisfy { $0.date < drill.window.interval.end })
        XCTAssertEqual(drill.totalCount, 1)
    }

    func testSingleMemberOtherKeepsItsCategoryNameAndNoBudget() {
        var (ledger, bank) = sample()
        ledger.spendingParts = [SpendingPart(name: "购物", amount: 50_000, categories: ["购物"])]
        ledger.entries = [expense(5_000, "购物", account: bank, subcategory: "衣服")]
        let result = OverviewAnalytics.categoryDrill(in: ledger, title: "其他 1 类", categories: ["购物"], isOther: true, selection: .current, now: now)
        XCTAssertEqual(result.slices.map(\.category), ["购物"])
        XCTAssertNil(result.budget)
    }

    func testPendingCategoryNeverBecomesAnAnomalyAndLargeShareIsReported() {
        var (ledger, bank) = sample()
        let pending = Classification.pendingCategory
        ledger.entries = history([pending: 5_000, "购物": 40_000], account: bank)
            + [expense(50_000, pending, account: bank), expense(80_000, "购物", account: bank)]
        let result = OverviewAnalytics.review(in: ledger, selection: .current, now: now)
        XCTAssertEqual(result.anomaly?.category, "购物")
        XCTAssertEqual(result.unsorted?.count, 1); XCTAssertEqual(result.unsorted?.amount, 50_000)
        ledger.entries[ledger.entries.count - 2].amount = 30_000
        XCTAssertNil(OverviewAnalytics.review(in: ledger, selection: .current, now: now).unsorted)
    }

    func testRecentEntriesUseAccountPostingAndHighlightIgnoresAdjustments() {
        var (ledger, bank) = sample()
        let source = Account(name: "来源", at: date("2026-10-01"))
        ledger.accounts.append(source)
        func transfer(title: String, posting: String, amount: Int64 = 4_000) -> Entry {
            var row = Entry(date: date("2026-11-01"), amount: amount, nature: .transfer, accountID: source.id, title: title)
            row.otherAccountID = bank.id
            row.otherDate = date(posting)
            return row
        }
        ledger.entries = [
            transfer(title: "稍早到账", posting: "2026-11-19"),
            transfer(title: "转账到账", posting: "2026-11-20", amount: 5_000),
            transfer(title: "未到账", posting: "2026-11-24"),
            Entry(date: date("2026-11-21"), amount: 50_000, nature: .adjustmentIn, accountID: bank.id, title: "调整"),
        ]
        let result = OverviewAnalytics.balanceSeries(for: bank, in: ledger, now: now)
        XCTAssertEqual(result.recentEntries.map(\.title), ["调整", "转账到账", "稍早到账"])
        XCTAssertEqual(result.highlightLabel, "11.20 转账到账")
    }

    func testNonCashReconciliationsPreserveCashMismatchAndSettlement() throws {
        var (ledger, bank) = sample()
        let credit = Account(name: "信用卡", kind: .credit, balance: -10_000, at: date("2026-10-01"))
        let receivable = Account(name: "待收", kind: .receivable, balance: 30_000, at: date("2026-10-01"))
        ledger.accounts += [credit, receivable]
        ledger.entries = [Entry(date: date("2026-10-05"), amount: 100_000, nature: .income, accountID: bank.id, title: "工资")]
        ledger.lastReconciledAt = date("2026-09-30")
        ledger.savingRule = .fixed(20_000)
        var expected = ledger
        Savings.closeCycles(&expected, now: now)
        let october = date("2026-10-20")
        try Reconciliation.reconcileAccount(&ledger, accountID: credit.id, actualBalance: -40_000, now: october)
        try Reconciliation.reconcileAccount(&ledger, accountID: receivable.id, actualBalance: 5_000, now: october)
        XCTAssertEqual(ledger.entries.suffix(2).map(\.source), ["账户校准", "账户校准"])
        XCTAssertEqual(ledger.lastReconciledAt, date("2026-09-30"))
        XCTAssertEqual(Reconciliation.mismatch(in: ledger, now: now)?.lastReconciledAt, date("2026-09-30"))

        // A ledger written by the initial overview build can still contain the old source.
        for index in ledger.entries.indices.dropFirst() { ledger.entries[index].source = "对余额" }
        Savings.closeCycles(&ledger, now: now)
        XCTAssertNotNil(expected.savingHistory.last)
        XCTAssertEqual(ledger.savingHistory, expected.savingHistory)
    }

    func testCreditReconciliationSupportsEitherSignAndZero() throws {
        var (ledger, _) = sample()
        let credit = Account(name: "信用卡", kind: .credit, balance: -10_000, at: date("2026-10-01"))
        ledger.accounts.append(credit)
        for (offset, actual, delta) in [(1, Int64(2_000), Int64(12_000)), (2, -2_000, -4_000), (3, 0, 2_000)] {
            let at = Dates.addDays(offset, to: now)
            let entry = try Reconciliation.reconcileAccount(&ledger, accountID: credit.id, actualBalance: actual, now: at)
            XCTAssertEqual(entry?.delta(for: credit.id), delta)
            XCTAssertEqual(ledger.accounts.last?.anchorBalance, actual)
        }
    }

}
