import XCTest
@testable import YubaiCore

final class Round46SavingInsightsTests: XCTestCase {
    private let now = Dates.parse("2026-11-20")!.addingTimeInterval(12 * 3600)
    private func date(_ value: String) -> Date { Dates.parse(value)! }
    private func ledger() -> Ledger {
        var ledger = Ledger(); ledger.cycleAnchor = .calendarMonth
        ledger.accounts = [Account(name: "银行卡", kind: .bank, balance: 2_000_000, at: date("2026-07-01"))]
        ledger.fixedSavings = 300_000
        return ledger
    }
    private func entry(_ ledger: Ledger, _ amount: Int64, _ day: String, title: String = "午饭", category: String = "餐饮", subcategory: String? = nil, nature: Nature = .expense) -> Entry {
        var entry = Entry(date: date(day), amount: amount, nature: nature, accountID: ledger.accounts[0].id, title: title, category: category)
        entry.subcategory = subcategory; entry.subcategoryUserEdited = true
        return entry
    }
    func testNoHistoryHasNoComparisonButShowsKnownMonthlyCharges() {
        var ledger = ledger()
        ledger.entries = [entry(ledger, 2800, "2026-11-19")]
        ledger.plans = [Plan(title: "视频会员", amount: 2500, dueDate: date("2026-12-03"), frequency: .monthly, category: "会员订阅")]
        let result = SavingInsights.opportunities(ledger, now: now)
        XCTAssertEqual(result.previousCycleCount, 0); XCTAssertTrue(result.comparisons.isEmpty)
        XCTAssertEqual(result.chargesTotal, 2500); XCTAssertEqual(result.entryCount, 1)
        XCTAssertNil(result.charges.first?.lastUsed)
    }
    func testUsualUsesThreePreviousCyclesThroughSameDayAndSubcategory() throws {
        var ledger = ledger()
        for month in [8, 9, 10] {
            let prefix = "2026-\(String(format: "%02d", month))"
            ledger.entries.append(entry(ledger, 9200, prefix + "-10", title: "打车", category: "交通", subcategory: "打车"))
            ledger.entries.append(entry(ledger, 90_000, prefix + "-25", title: "打车", category: "交通", subcategory: "打车"))
        }
        ledger.entries.append(entry(ledger, 13_200, "2026-11-15", title: "打车", category: "交通", subcategory: "打车"))
        let result = SavingInsights.opportunities(ledger, now: now)
        let row = try XCTUnwrap(result.comparisons.first { $0.subcategory == "打车" })
        XCTAssertEqual(row.usual, 9200); XCTAssertEqual(row.amount, 13_200); XCTAssertEqual(row.difference, 4000)
        XCTAssertEqual(result.previousCycleCount, 3)
    }
    func testOnePreviousCycleDoesNotInventTwoZeroCycles() throws {
        var ledger = ledger(); ledger.entries = [entry(ledger, 18_000, "2026-10-15", subcategory: "外卖"), entry(ledger, 9600, "2026-11-15", subcategory: "外卖")]
        let result = SavingInsights.opportunities(ledger, now: now)
        XCTAssertEqual(result.previousCycleCount, 1)
        let row = try XCTUnwrap(result.comparisons.first)
        XCTAssertEqual(row.usual, 18_000); XCTAssertEqual(row.difference, -8400)
    }
    func testRefundUsesOriginalCategoryAndDoesNotBecomeItsOwnComparison() throws {
        var ledger = ledger()
        let original = entry(ledger, 12_000, "2026-11-10", title: "打车", category: "交通", subcategory: "打车")
        var refund = entry(ledger, 4000, "2026-11-11", category: "其他收入", nature: .refund); refund.relatedEntryID = original.id
        ledger.entries = [entry(ledger, 6000, "2026-10-10", category: "交通", subcategory: "打车"), original, refund]
        let rows = SavingInsights.opportunities(ledger, now: now).comparisons
        XCTAssertEqual(rows.count, 1); XCTAssertEqual(rows.first?.amount, 8000); XCTAssertEqual(rows.first?.difference, 2000)
    }
    func testUnclassifiedFixedDeletedAndFutureRowsCannotSkewUsual() {
        var ledger = ledger()
        var fixed = entry(ledger, 100_000, "2026-10-01"); fixed.planID = UUID()
        var deleted = entry(ledger, 100_000, "2026-10-02"); deleted.deletedAt = now
        ledger.entries = [fixed, deleted, entry(ledger, 100_000, "2026-12-01"), entry(ledger, 6000, "2026-11-10", category: Classification.pendingCategory)]
        XCTAssertTrue(SavingInsights.opportunities(ledger, now: now).comparisons.isEmpty)
    }
    func testMonthlyChargesExcludeIncomeStoppedEndedAndNonMonthly() {
        var ledger = ledger()
        let plan = Plan(title: "会员", amount: 2500, dueDate: date("2026-11-03"), frequency: .monthly, category: "会员订阅")
        var income = plan; income.id = UUID(); income.inflow = true; income.nature = .income
        var stopped = plan; stopped.id = UUID(); stopped.stoppedAt = date("2026-11-01")
        var ended = plan; ended.id = UUID(); ended.endDate = date("2026-11-01")
        var yearly = plan; yearly.id = UUID(); yearly.frequency = .yearly
        var inactive = plan; inactive.id = UUID(); inactive.active = false
        ledger.plans = [plan, income, stopped, ended, yearly, inactive]
        XCTAssertEqual(SavingInsights.opportunities(ledger, now: now).charges.map(\.id), [plan.id])
    }
    func testPayingDoesNotProveUsageButAnExplicitSeparateVisitDoes() throws {
        var ledger = ledger()
        let plan = Plan(title: "健身房", amount: 19_900, dueDate: date("2026-11-03"), frequency: .monthly, category: "会员订阅")
        ledger.plans = [plan]
        var payment = entry(ledger, 19_900, "2026-11-03", title: "健身房"); payment.planID = plan.id
        ledger.entries = [payment, entry(ledger, 19_900, "2026-11-10", title: "健身房")]
        XCTAssertNil(SavingInsights.opportunities(ledger, now: now).charges.first?.lastUsed)
        ledger.entries.append(entry(ledger, 5000, "2026-10-03", title: "健身房 · 私教课"))
        let charge = try XCTUnwrap(SavingInsights.opportunities(ledger, now: now).charges.first)
        XCTAssertEqual(charge.lastUsed, date("2026-10-03"))
    }
    func testFixedWishForecastRoundsUpAndStartsAtNextCycle() {
        var ledger = ledger(); ledger.savingRule = .fixed(200_000)
        let wish = WishItem(title: "相机", amount: 860_000)
        let value = SavingInsights.funding(for: wish, ledger: ledger, now: now)
        XCTAssertEqual(value.shortfall, 360_000); XCTAssertEqual(value.enoughOn, date("2027-01-01"))
        XCTAssertEqual(value.monthly, 200_000); XCTAssertEqual(value.progress, 500_000.0 / 860_000.0, accuracy: 0.00001)
    }
    func testAffordableWishReportsRemainderWithoutAnotherSavingDate() {
        var ledger = ledger(); ledger.savingRule = .fixed(200_000)
        let value = SavingInsights.funding(for: WishItem(title: "耳机", amount: 189_900), ledger: ledger, now: now)
        XCTAssertEqual(value.shortfall, 0); XCTAssertEqual(value.remainingAfterPurchase, 310_100)
        XCTAssertNil(value.enoughOn); XCTAssertEqual(value.progress, 1)
    }
    func testIrregularShareIncomeHasNoInventedFundingDate() {
        var ledger = ledger(); ledger.savingRule = .share(20)
        let value = SavingInsights.funding(for: WishItem(title: "相机", amount: 860_000), ledger: ledger, now: now)
        XCTAssertGreaterThan(value.shortfall, 0); XCTAssertNil(value.monthly); XCTAssertNil(value.enoughOn)
    }
    func testZeroMonthlySavingNeverDividesByZero() {
        var ledger = ledger(); ledger.savingRule = .fixed(0)
        let value = SavingInsights.funding(for: WishItem(title: "相机", amount: 860_000), ledger: ledger, now: now)
        XCTAssertEqual(value.shortfall, 560_000); XCTAssertNil(value.enoughOn)
    }
    func testMonthlySuggestionRequiresThreeCompletedCycles() {
        var ledger = ledger()
        ledger.entries = [entry(ledger, 800_000, "2026-10-05", category: "工资奖金", nature: .income), entry(ledger, 20_000, "2026-10-06")]
        XCTAssertNil(Reserve.suggestedMonthly(ledger, now: now))
        XCTAssertTrue(SpendingParts.proposal(ledger: ledger, now: now).isEmpty)
    }
    func testHugeWishAmountCapsOnlyProgressAndDoesNotOverflowDate() {
        var ledger = ledger(); ledger.savingRule = .fixed(1)
        let value = SavingInsights.funding(for: WishItem(title: "大件", amount: Money.limit), ledger: ledger, now: now)
        XCTAssertEqual(value.shortfall, Money.limit - 300_001); XCTAssertNil(value.enoughOn)
        XCTAssertGreaterThanOrEqual(value.progress, 0); XCTAssertLessThanOrEqual(value.progress, 1)
    }
    func testWishSavingsOnlyCountsExplicitDatedDroppedWishes() {
        var ledger = ledger()
        var old = WishItem(title: "咖啡机", amount: 248_000); old.status = .dropped; old.droppedAt = date("2026-10-20")
        var current = WishItem(title: "耳机", amount: 189_900); current.status = .dropped; current.droppedAt = date("2026-11-19")
        var future = current; future.id = UUID(); future.droppedAt = date("2026-12-01")
        var noDate = current; noDate.id = UUID(); noDate.droppedAt = nil
        ledger.wishlist = [old, current, future, noDate, WishItem(title: "在想", amount: 10_000)]
        ledger.butlerSavings = [ButlerSaving(id: "refund", item: "退回的重复扣款", amount: 2500, cadence: .once, date: now, undoable: false)]
        let value = SavingInsights.wishSavings(ledger, now: now)
        XCTAssertEqual(value.total, 437_900); XCTAssertEqual(value.month, 189_900)
    }
    func testWeeklyReviewUsesLastCompleteMondayToSunday() {
        var ledger = ledger()
        ledger.entries = [entry(ledger, 41_200, "2026-11-09"), entry(ledger, 27_400, "2026-11-15", category: "交通"), entry(ledger, 76_000, "2026-11-04"), entry(ledger, 999_999, "2026-11-16")]
        var wish = WishItem(title: "咖啡机", amount: 248_000); wish.status = .dropped; wish.droppedAt = date("2026-11-12"); ledger.wishlist = [wish]
        let value = SavingInsights.weekly(ledger, now: now)
        XCTAssertEqual(value.interval.start, date("2026-11-09")); XCTAssertEqual(value.interval.end, date("2026-11-16"))
        XCTAssertEqual(value.spending, 68_600); XCTAssertEqual(value.previousSpending, 76_000)
        XCTAssertEqual(value.largestCategory, "餐饮"); XCTAssertEqual(value.largestAmount, 41_200); XCTAssertEqual(value.droppedWishes, 248_000)
    }
    func testSpendingAnswerGroundsConclusionAndFrequentMerchantInEntries() {
        var ledger = ledger()
        ledger.entries = [entry(ledger, 62_400, "2026-10-10"), entry(ledger, 52_000, "2026-11-10", title: "公司楼下午饭"), entry(ledger, 19_600, "2026-11-11", title: "打车", category: "交通")]
        let answer = SavingInsights.spendingAnswer(ledger, now: now)
        XCTAssertEqual(answer.conclusion, "一大半吃掉了，但比上个月少。")
        XCTAssertEqual(answer.comparisons.first?.usual, 62_400); XCTAssertEqual(answer.comparisons.first?.amount, 52_000)
        XCTAssertEqual(answer.frequentPlace?.title, "公司楼下午饭"); XCTAssertEqual(answer.frequentPlace?.count, 1)
    }
    func testSpendingAnswerDoesNotClaimLessWhenHistoryIsMissing() {
        var ledger = ledger(); ledger.entries = [entry(ledger, 52_000, "2026-11-10")]
        XCTAssertEqual(SavingInsights.spendingAnswer(ledger, now: now).conclusion, "花得最多 · 餐饮")
        XCTAssertFalse(SavingInsights.spendingAnswer(ledger, now: now).hasPreviousCycle)
    }
    func testCategorySharesKeepEveryCategoryAndNegativeRefundSeparate() {
        var ledger = ledger()
        ledger.entries = [entry(ledger, 6000, "2026-11-10"), entry(ledger, 4000, "2026-11-11", category: "交通"), entry(ledger, 5000, "2026-11-12", category: "购物", nature: .refund)]
        let rows = SavingInsights.categoryShares(ledger, during: DateInterval(start: date("2026-11-01"), end: now))
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows.first { $0.title == "餐饮" }?.share, 0.6)
        XCTAssertEqual(rows.first { $0.title == "交通" }?.share, 0.4)
        XCTAssertEqual(rows.first { $0.title == "购物" }?.share, 0)
        XCTAssertEqual(rows.first { $0.title == "购物" }?.amount, -5000)
    }
    func testMonthlyIncreaseIncludesWithdrawalsAndRefundsOnce() {
        var ledger = ledger(); ledger.savingRule = .fixed(200_000)
        var purchase = entry(ledger, 120_000, "2026-11-10", title: "大衣", category: "购物"); purchase.fromReserve = true
        var refund = entry(ledger, 20_000, "2026-11-11", category: "购物", nature: .refund); refund.relatedEntryID = purchase.id
        ledger.entries = [purchase, refund]
        ledger.reserveAdjustments = [ReserveAdjustment(date: date("2026-10-31"), delta: 999_999), ReserveAdjustment(date: date("2026-11-05"), delta: 1000)]
        XCTAssertEqual(SavingInsights.monthlyIncrease(ledger, now: now), 101_000)
    }
    func testConsideredPurchaseKeepsOneWishAndTheOriginalWaitingDate() throws {
        var ledger = ledger(); ledger.profile.principles = ["超过 2,000 等 48 小时"]
        let verdict = SubmittedPurchaseVerdict(verdict: .wait, reason: "存着的钱够。", need: .want, boundReason: "")
        let first = try Wishlist.keepConsidered(fromVerdict: verdict, title: "相机", amount: 248_000, category: "购物", in: &ledger, now: now)
        let repeated = try Wishlist.keepConsidered(fromVerdict: verdict, title: " 相机 ", amount: 248_000, category: "购物", in: &ledger, now: Dates.addDays(1, to: now))
        XCTAssertEqual(first.id, repeated.id); XCTAssertEqual(ledger.wishlist.count, 1)
        XCTAssertEqual(repeated.coolUntil, now.addingTimeInterval(48 * 3600))
    }
    func testConsideredDifferentItemOrDroppedWishDoesNotSuppressNewWish() throws {
        var ledger = ledger()
        let verdict = SubmittedPurchaseVerdict(verdict: .wait, reason: "等等再说。", need: .want, boundReason: "")
        var old = WishItem(title: "相机", amount: 248_000); old.status = .dropped; old.droppedAt = now
        ledger.wishlist = [old, WishItem(title: "相机镜头", amount: 248_000)]
        let fresh = try Wishlist.keepConsidered(fromVerdict: verdict, title: "相机", amount: 248_000, in: &ledger, now: now)
        XCTAssertEqual(ledger.wishlist.count, 3); XCTAssertNotEqual(fresh.id, old.id)
    }
}
