import XCTest
@testable import YubaiCore

final class PresentationCacheTests: XCTestCase {
    private let start = Dates.parse("2026-10-01 00:00:00")!
    private let accountID = UUID()
    private func entry(_ amount: Int64, _ nature: Nature = .expense, _ category: String = "餐饮", offset: TimeInterval = 10) -> Entry {
        Entry(date: start.addingTimeInterval(offset), amount: amount, nature: nature, accountID: accountID, title: category, category: category)
    }
    func testLiveCashFlowEndKeepsHalfOpenBoundariesWithoutRounding() {
        var ledger = Ledger(); ledger.entries = [entry(100), entry(200, offset: 20)]
        var cache = LedgerPresentationCache()
        for (offset, expected) in [(9.0, Int64(0)), (10, 0), (10.001, 100), (19.999, 100), (20, 100), (20.001, 300)] {
            let interval = DateInterval(start: start, end: start.addingTimeInterval(offset))
            XCTAssertEqual(cache.cashFlow(in: ledger, during: interval, revision: 1).spending, expected)
            XCTAssertEqual(cache.cashFlowSlices(in: ledger, during: interval, income: false, revision: 1).reduce(0) { $0 + $1.amount }, expected)
            XCTAssertTrue(cache.cashFlowSlices(in: ledger, during: interval, income: true, revision: 1).isEmpty)
        }
    }
    func testCashFlowStartAndEndAreIndependentKeys() {
        var ledger = Ledger(); ledger.entries = [entry(100), entry(200, offset: 20)]
        var cache = LedgerPresentationCache()
        for (from, to, expected) in [(0.0, 30.0, Int64(300)), (11, 30, 200), (11, 20, 0), (10, 20, 100), (10, 10, 0)] {
            let interval = DateInterval(start: start.addingTimeInterval(from), end: start.addingTimeInterval(to))
            XCTAssertEqual(cache.cashFlow(in: ledger, during: interval, revision: 1).spending, expected)
        }
    }
    func testRevisionInvalidatesEvenWhenUpdatedAtIsUnchangedAndOnUndo() {
        var ledger = Ledger(); ledger.entries = [entry(100)]
        let before = ledger
        var cache = LedgerPresentationCache()
        let interval = DateInterval(start: start, duration: 30)
        XCTAssertEqual(cache.cashFlow(in: ledger, during: interval, revision: 1).spending, 100)
        ledger.entries[0].amount = 250
        XCTAssertEqual(ledger.updatedAt, before.updatedAt)
        XCTAssertEqual(cache.cashFlow(in: ledger, during: interval, revision: 2).spending, 250)
        XCTAssertEqual(cache.cashFlow(in: before, during: interval, revision: 3).spending, 100)
    }
    func testDifferentLedgerWithSameRevisionDiscardsAllCaches() {
        var a = Ledger(); a.entries = [entry(100)]
        var b = Ledger(); b.entries = [entry(200)]
        var cache = LedgerPresentationCache()
        let interval = DateInterval(start: start, duration: 30)
        XCTAssertEqual(cache.cashFlow(in: a, during: interval, revision: 1).spending, 100)
        XCTAssertEqual(cache.flowRecords(in: a, categories: ["餐饮"], income: false, interval: interval, revision: 1).first?.amount, 100)
        XCTAssertEqual(cache.cashFlow(in: b, during: interval, revision: 1).spending, 200)
        XCTAssertEqual(cache.flowRecords(in: b, categories: ["餐饮"], income: false, interval: interval, revision: 1).first?.amount, 200)
    }
    func testFlowRecordsFollowRefundOriginalOutsideIntervalAndCategoryAliases() {
        var ledger = Ledger()
        var original = entry(500, .expense, "旧名", offset: -10); original.subcategory = "早餐"
        var refund = entry(100, .refund, "无关"); refund.relatedEntryID = original.id
        var deleted = entry(100); deleted.deletedAt = start
        ledger.entries = [original, refund, deleted, entry(300, .income, "餐饮"), entry(100, .transfer)]
        ledger.categoryAliases = ["旧名": "餐饮"]
        var cache = LedgerPresentationCache()
        let interval = DateInterval(start: start, duration: 20)
        XCTAssertEqual(cache.flowRecords(in: ledger, categories: ["旧名"], income: false, interval: interval, revision: 1).map(\.id), [refund.id])
        XCTAssertEqual(cache.flowRecords(in: ledger, categories: ["餐饮"], income: false, interval: interval, subcategory: "早餐", revision: 1).map(\.id), [refund.id])
        XCTAssertTrue(cache.flowRecords(in: ledger, categories: ["餐饮"], income: false, interval: interval, subcategory: "其他", revision: 1).isEmpty)
        XCTAssertEqual(cache.flowRecords(in: ledger, categories: ["餐饮"], income: true, interval: interval, revision: 1).map(\.amount), [300])
    }
    func testRecordsAndEvidenceRetainStableDateOrderAndDeletedPolicy() {
        let a = entry(100), b = entry(200), c = entry(300, offset: 11)
        var deleted = entry(400); deleted.deletedAt = start
        var ledger = Ledger(); ledger.entries = [a, b, c, deleted]
        var cache = LedgerPresentationCache()
        let interval = DateInterval(start: start, duration: 20)
        XCTAssertEqual(cache.flowRecords(in: ledger, categories: ["餐饮"], income: false, interval: interval, revision: 1).map(\.id), [c.id, a.id, b.id])
        let ids = Set(ledger.entries.map(\.id))
        XCTAssertEqual(cache.evidenceEntries(in: ledger, ids: ids, activeOnly: false, revision: 1).map(\.id), [c.id, a.id, b.id, deleted.id])
        XCTAssertEqual(cache.evidenceEntries(in: ledger, ids: ids, activeOnly: true, revision: 1).map(\.id), [c.id, a.id, b.id])
    }
    func testSettingsBalanceExpiresAtFuturePostingAndClockReversal() {
        var ledger = Ledger(); let account = Account(name: "银行", balance: 1000, at: start)
        ledger.accounts = [account]
        ledger.entries = [Entry(date: start.addingTimeInterval(20), amount: 250, accountID: account.id, title: "餐饮")]
        var cache = LedgerPresentationCache()
        XCTAssertEqual(cache.settings(in: ledger, revision: 1, now: start.addingTimeInterval(10)).cashBalances, [1000])
        XCTAssertEqual(cache.settings(in: ledger, revision: 1, now: start.addingTimeInterval(20)).cashBalances, [750])
        XCTAssertEqual(cache.settings(in: ledger, revision: 1, now: start.addingTimeInterval(10)).cashBalances, [1000])
    }
    func testSettingsFollowUpThresholdAndWeekRollover() {
        var ledger = Ledger(); var wish = WishItem(title: "耳机", amount: 100)
        wish.status = .bought; wish.followUpAt = start.addingTimeInterval(20)
        ledger.wishlist = [wish, WishItem(title: "键盘", amount: 200)]
        ledger.memories = [MemoryNote(text: "事实", kind: .life, source: .user, createdAt: start)]
        var cache = LedgerPresentationCache()
        let before = cache.settings(in: ledger, revision: 1, now: start.addingTimeInterval(10))
        XCTAssertEqual(before.thinkingCount, 1); XCTAssertEqual(before.followUpCount, 0)
        XCTAssertEqual(before.memoryCount, 1); XCTAssertEqual(before.weeklyMemoryCount, 1)
        XCTAssertEqual(cache.settings(in: ledger, revision: 1, now: start.addingTimeInterval(20)).followUpCount, 1)
        XCTAssertEqual(cache.settings(in: ledger, revision: 1, now: Dates.addDays(8, to: start)).weeklyMemoryCount, 0)
    }
    func testSubscriptionsRefreshOnPlanChangesAndRestore() {
        var ledger = Ledger(); var plan = Plan(title: "订阅", amount: 1000, dueDate: start, frequency: .monthly)
        ledger.plans = [plan]; let before = ledger
        var cache = LedgerPresentationCache()
        XCTAssertEqual(cache.subscriptions(in: ledger, revision: 1).map(\.amount), [1000])
        plan.amount = 2000; ledger.plans = [plan]
        XCTAssertEqual(cache.subscriptions(in: ledger, revision: 2).map(\.amount), [2000])
        XCTAssertEqual(cache.subscriptions(in: before, revision: 3).map(\.amount), [1000])
    }
    func testSubcategoryBreakdownInvalidatesWithClassificationRevision() {
        var ledger = Ledger(); var row = entry(100); row.subcategory = "早餐"; ledger.entries = [row]
        var cache = LedgerPresentationCache(); let interval = DateInterval(start: start, duration: 30)
        XCTAssertEqual(cache.subcategoryBreakdown(in: ledger, category: "餐饮", during: interval, revision: 1).map(\.category), ["早餐"])
        ledger.entries[0].subcategory = "午餐"
        XCTAssertEqual(cache.subcategoryBreakdown(in: ledger, category: "餐饮", during: interval, revision: 2).map(\.category), ["午餐"])
    }
    func testSavingsRetainsDistinctStrictMonthlyAndMillisecondTotalBoundaries() {
        var ledger = Ledger(); var wish = WishItem(title: "没买", amount: 100)
        let event = start.addingTimeInterval(20)
        wish.status = .dropped; wish.droppedAt = event; ledger.wishlist = [wish]
        var cache = LedgerPresentationCache()
        for moment in [event.addingTimeInterval(-0.002), event.addingTimeInterval(-0.001), event.addingTimeInterval(-0.0005), event, event.addingTimeInterval(0.001), start] {
            let value = cache.savings(in: ledger, revision: 1, now: moment)
            XCTAssertEqual(value.total, Savings.total(ledger: ledger, now: moment))
            XCTAssertEqual(value.month, Savings.summary(ledger: ledger, from: start, to: moment, now: moment).total)
        }
    }
    func testStoppedSavingsAccrueAtScheduleTimeAndUndoInvalidates() {
        var ledger = Ledger()
        let plan = Plan(title: "订阅", amount: 1000, dueDate: start.addingTimeInterval(20), frequency: .monthly)
        ledger.stoppedSubscriptions = [StoppedSubscription(plan: plan, stoppedAt: start)]
        var cache = LedgerPresentationCache()
        XCTAssertEqual(cache.savings(in: ledger, revision: 1, now: start.addingTimeInterval(10)).total, 0)
        let due = cache.savings(in: ledger, revision: 1, now: start.addingTimeInterval(20))
        XCTAssertEqual(due.total, 1000); XCTAssertEqual(due.month, 0)
        let after = cache.savings(in: ledger, revision: 1, now: start.addingTimeInterval(21))
        XCTAssertEqual(after.total, 1000); XCTAssertEqual(after.month, 1000)
        ledger.stoppedSubscriptions = []
        XCTAssertEqual(cache.savings(in: ledger, revision: 2, now: start.addingTimeInterval(21)).total, 0)
    }
    func testRecentCaptureEligibilityUsesRecordedAtFutureTimeAndDayRollover() {
        var ledger = Ledger()
        var recent = entry(100); recent.quickCapture = QuickCaptureOrigin(withoutOpeningApp: true)
        recent.recordedAt = start.addingTimeInterval(20)
        var old = entry(200); old.quickCapture = QuickCaptureOrigin(withoutOpeningApp: false)
        old.recordedAt = Dates.addDays(-6, to: start)
        ledger.entries = [recent, old, entry(300)]
        var cache = LedgerPresentationCache()
        XCTAssertEqual(cache.recentCaptures(in: ledger, revision: 1, now: start.addingTimeInterval(10)).map(\.id), [old.id])
        XCTAssertEqual(cache.recentCaptures(in: ledger, revision: 1, now: start.addingTimeInterval(20)).map(\.id), [recent.id, old.id])
        XCTAssertEqual(cache.recentCaptures(in: ledger, revision: 1, now: Dates.addDays(1, to: start)).map(\.id), [recent.id])
        XCTAssertEqual(cache.recentCaptures(in: ledger, revision: 1, now: start.addingTimeInterval(10)).map(\.id), [old.id])
    }

}
