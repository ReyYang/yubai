import XCTest
@testable import YubaiCore

final class Round47HomeTests: XCTestCase {
    private let now = Dates.parse("2026-11-20 20:00")!
    private func date(_ text: String) -> Date { Dates.parse(text)! }
    private func ledger() -> Ledger {
        var value = Ledger()
        value.accounts = [Account(name: "银行卡", kind: .bank, balance: 1_000_000, at: date("2026-01-01"))]
        return value
    }
    private func row(_ ledger: Ledger, _ amount: Int64 = 2800, on day: String = "2026-11-20 12:31", nature: Nature = .expense) -> Entry {
        Entry(date: date(day), amount: amount, nature: nature, accountID: ledger.accounts[0].id, title: "午饭", category: nature == .income ? "工资" : "餐饮")
    }
    private func salary(_ ledger: inout Ledger) {
        var plan = Plan(title: "工资", amount: 801_000, dueDate: date("2026-11-10"), frequency: .monthly, inflow: true, category: "工资", nature: .income)
        plan.accountID = ledger.accounts[0].id; ledger.plans = [plan]
    }
    func testFirstOpenHasNoNumericBudgetAndDoesNotPrepareAnAccount() {
        let value = Ledger(), hero = HomeHero.make(value, now: now)
        XCTAssertTrue(hero.isFirstOpen); XCTAssertTrue(value.accounts.isEmpty)
        XCTAssertFalse(FirstUse.salaryPromptDue(value, now: now))
    }
    func testFirstEntryShowsCalendarMonthSpendingEvenWithNegativeAvailable() {
        var value = ledger(); value.accounts[0].anchorBalance = 0; value.entries = [row(value)]
        XCTAssertLessThan(Finance.funds(value, now: now).available, 0)
        let hero = HomeHero.make(value, now: now)
        XCTAssertFalse(hero.isFirstOpen); XCTAssertFalse(hero.hasSalaryPlan)
        XCTAssertEqual(hero.title, "这个月花了"); XCTAssertEqual(hero.amount, 2800)
        XCTAssertTrue(FirstUse.salaryPromptDue(value, now: now))
        XCTAssertFalse(HomeButler.queue(value, now: now).contains { if case .overspend = $0 { return true }; return false })
    }
    func testNaturalMonthExcludesPastFutureDeletedAndIncomeAndNetsRefunds() {
        var value = ledger()
        var deleted = row(value, 9000); deleted.deletedAt = now
        value.entries = [row(value), row(value, 500, nature: .refund), row(value, 801_000, nature: .income),
                         row(value, 20_000, on: "2026-10-31"), row(value, 10_000, on: "2026-11-21"), deleted]
        XCTAssertEqual(HomeHero.make(value, now: now).amount, 2300)
    }
    func testRefundOnlyMonthNeverShowsNegativeSpent() {
        var value = ledger(); value.entries = [row(value, 2800, nature: .refund)]
        XCTAssertEqual(HomeHero.make(value, now: now).amount, 0)
    }
    func testKnownSalaryUsesFinanceAndDoesNotChangeDailyMath() {
        var value = ledger(); salary(&value); value.entries = [row(value)]
        let before = Finance.pace(value, now: now), hero = HomeHero.make(value, now: now)
        XCTAssertTrue(hero.hasSalaryPlan); XCTAssertEqual(hero.title, "还能花")
        XCTAssertEqual(hero.amount, Finance.funds(value, now: now).available)
        XCTAssertEqual(Finance.pace(value, now: now), before)
        XCTAssertFalse(FirstUse.salaryPromptDue(value, now: now))
    }
    func testKnownSalaryRetainsRealOverspendState() {
        var value = ledger(); value.accounts[0].anchorBalance = 0; salary(&value); value.entries = [row(value)]
        let hero = HomeHero.make(value, now: now)
        XCTAssertEqual(hero.title, "多花了"); XCTAssertEqual(hero.amount, 2800)
        XCTAssertTrue(HomeButler.queue(value, now: now).contains { if case .overspend = $0 { return true }; return false })
    }
    func testDeletedHistoryDoesNotReopenFirstScene() {
        var value = ledger(); var deleted = row(value); deleted.deletedAt = now; value.entries = [deleted]
        XCTAssertFalse(HomeHero.make(value, now: now).isFirstOpen)
    }
    func testPostponePersistsAndDoesNotWakeForExistingIncome() throws {
        var value = ledger(); value.entries = [row(value), row(value, 100_000, nature: .income)]
        FirstUse.deferSalarySetup(&value, now: now)
        let decoded = try LedgerCodec.decode(LedgerCodec.encode(value))
        XCTAssertEqual(decoded.salarySetupDeferral, value.salarySetupDeferral)
        XCTAssertFalse(FirstUse.salaryPromptDue(decoded, now: Dates.addDays(1, to: now)))
    }
    func testNextNewIncomeIncludingBackdatedIncomeWakesPrompt() {
        var value = ledger(); value.entries = [row(value)]
        FirstUse.deferSalarySetup(&value, now: now)
        value.entries.append(row(value, 801_000, on: "2026-11-19", nature: .income))
        XCTAssertTrue(FirstUse.salaryPromptDue(value, now: now))
        FirstUse.deferSalarySetup(&value, now: now)
        XCTAssertFalse(FirstUse.salaryPromptDue(value, now: now))
    }
    func testFutureIncomeOnlyWakesOnPostingDateAndDeletedIncomeDoesNotWake() {
        var value = ledger(); value.entries = [row(value), row(value, 801_000, on: "2026-11-21", nature: .income)]
        FirstUse.deferSalarySetup(&value, now: now)
        XCTAssertFalse(FirstUse.salaryPromptDue(value, now: now))
        XCTAssertTrue(FirstUse.salaryPromptDue(value, now: date("2026-11-21")))
        value.entries[1].deletedAt = now
        XCTAssertFalse(FirstUse.salaryPromptDue(value, now: date("2026-11-21")))
    }
    func testTenthOfNextMonthIsFallbackAndCrossesYear() {
        var value = ledger(); value.entries = [row(value)]
        FirstUse.deferSalarySetup(&value, now: now)
        XCTAssertFalse(FirstUse.salaryPromptDue(value, now: date("2026-12-09 23:59")))
        XCTAssertTrue(FirstUse.salaryPromptDue(value, now: date("2026-12-10")))
        FirstUse.deferSalarySetup(&value, now: date("2026-12-31"))
        XCTAssertEqual(value.salarySetupDeferral?.askAgainOn, date("2027-01-10"))
    }
    func testSalarySetupAlwaysEndsPromptEvenAfterDeadline() {
        var value = ledger(); value.entries = [row(value)]; FirstUse.deferSalarySetup(&value, now: now); salary(&value)
        XCTAssertFalse(FirstUse.salaryPromptDue(value, now: date("2026-12-10")))
    }
    func testOldShapeDecodesWithoutDeferral() throws {
        var value = ledger(); value.entries = [row(value)]; FirstUse.deferSalarySetup(&value, now: now)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: LedgerCodec.encode(value)) as? [String: Any])
        json.removeValue(forKey: "salarySetupDeferral")
        let decoded = try LedgerCodec.decode(JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(decoded.salarySetupDeferral); XCTAssertTrue(FirstUse.salaryPromptDue(decoded, now: now))
    }
    func testDeferralSerializationIsStableAndParticipatesInEquality() throws {
        let old = ledger(); var value = old; value.entries = [row(value)]
        FirstUse.deferSalarySetup(&value, now: now)
        XCTAssertNotEqual(value, old)
        XCTAssertEqual(try LedgerCodec.encode(value), try LedgerCodec.encode(value))
    }
    func testInvalidDeferralDateIsRejected() {
        var value = ledger(); value.salarySetupDeferral = SalarySetupDeferral(deferredAt: .distantFuture, postedIncomeIDs: [])
        XCTAssertThrowsError(try value.validate())
    }
    func testSavingNotStartedEvenWithAnUnfundedWish() {
        var value = ledger(); value.wishlist = [WishItem(title: "相机", amount: 860_000)]
        XCTAssertEqual(HomeSavingCard.make(value, now: now).state, .notStarted)
    }
    func testSavingMonthlyIncludesActualCurrentSetAside() {
        var value = ledger(); value.fixedSavings = 300_000; value.savingRule = .fixed(200_000)
        let facts = HomeSavingCard.make(value, now: now)
        XCTAssertEqual(facts.total, Reserve.overview(value, now: now).total)
        XCTAssertEqual(facts.state, .monthly(200_000))
    }
    func testShareRuleUsesCoreAmountInCents() {
        var value = ledger(); value.savingRule = .share(20); value.entries = [row(value, 801_000, nature: .income)]
        XCTAssertEqual(HomeSavingCard.make(value, now: now).state, .monthly(160_200))
    }
    func testNearestUnfinishedWishUsesOnePotAndStableOrder() {
        var value = ledger(); value.fixedSavings = 500_000
        let camera = WishItem(title: "相机", amount: 860_000), nearer = WishItem(title: "电脑", amount: 700_000)
        var dropped = WishItem(title: "放弃的", amount: 100); dropped.status = .dropped
        var bought = WishItem(title: "买过的", amount: 100); bought.status = .bought
        value.wishlist = [camera, nearer, dropped, bought]
        XCTAssertEqual(HomeSavingCard.make(value, now: now).state,
                       .wish(id: nearer.id, title: "电脑", shortfall: 200_000, progress: 5.0 / 7))
    }
    func testWishReachedCapsProgressAndShowsNoShortfall() {
        var value = ledger(); value.fixedSavings = 500_000
        let wish = WishItem(title: "降噪耳机", amount: 189_900); value.wishlist = [wish]
        XCTAssertEqual(HomeSavingCard.make(value, now: now).state, .wish(id: wish.id, title: wish.title, shortfall: 0, progress: 1))
    }
    func testReceiptEmptyDoesNotBorrowYesterday() {
        var value = ledger(); value.entries = [row(value, on: "2026-11-19")]
        let receipt = DailyReceipt.make(value, now: now)
        XCTAssertEqual(receipt.count, 0); XCTAssertTrue(receipt.entries.isEmpty); XCTAssertEqual(receipt.total, 0)
    }
    func testReceiptLatestSixAreChronologicalAndTotalIncludesOmittedRows() {
        var value = ledger()
        value.entries = (0..<9).map { row(value, Int64(($0 + 1) * 100), on: "2026-11-20 \(String(format: "%02d", $0 + 1)):00") }.reversed()
        let receipt = DailyReceipt.make(value, now: now)
        XCTAssertEqual(receipt.count, 9); XCTAssertEqual(receipt.omittedCount, 3)
        XCTAssertEqual(receipt.entries.map(\.amount), [400, 500, 600, 700, 800, 900]); XCTAssertEqual(receipt.total, 4500)
    }
    func testReceiptExcludesDeletedAndFutureRowsAndNetsRefunds() {
        var value = ledger(); var deleted = row(value, 9900); deleted.deletedAt = now
        value.entries = [row(value), row(value, 500, nature: .refund), deleted, row(value, on: "2026-11-21")]
        let receipt = DailyReceipt.make(value, now: now)
        XCTAssertEqual(receipt.count, 2); XCTAssertEqual(receipt.total, 2300)
        XCTAssertEqual(DailyReceipt.make(value, now: date("2026-11-21")).count, 1)
    }
    func testUndoingOneReceiptLineKeepsLaterChangesAndRecalculatesCountAndTotal() {
        var value = ledger(); value.entries = [row(value), row(value, 1800)]
        value.accounts[0].name = "后来改的账户"
        QuickCapture.undo(entryID: value.entries[1].id, in: &value, now: now)
        let receipt = DailyReceipt.make(value, now: now)
        XCTAssertEqual(receipt.count, 1); XCTAssertEqual(receipt.total, 2800)
        XCTAssertEqual(value.accounts[0].name, "后来改的账户")
    }
    func testHomeTodayFeedbackUsesReceiptOnly() {
        var value = ledger(); let added = row(value); value.entries = [added]
        let feedback = HomeEntryFeedback.make(savedIDs: [added.id], fromHome: true, ledger: value, now: now)
        XCTAssertEqual(feedback.highlightedIDs, [added.id]); XCTAssertFalse(feedback.needsToast)
    }
    func testBackdatedAndOtherOriginsRetainToast() {
        var value = ledger(); let yesterday = row(value, on: "2026-11-19"), today = row(value); value.entries = [yesterday, today]
        let past = HomeEntryFeedback.make(savedIDs: [yesterday.id], fromHome: true, ledger: value, now: now)
        XCTAssertTrue(past.highlightedIDs.isEmpty); XCTAssertTrue(past.needsToast)
        let elsewhere = HomeEntryFeedback.make(savedIDs: [today.id], fromHome: false, ledger: value, now: now)
        XCTAssertTrue(elsewhere.highlightedIDs.isEmpty); XCTAssertTrue(elsewhere.needsToast)
    }
    func testContinuousMixedDatesHighlightTodayAndKeepOtherFeedback() {
        var value = ledger(); let past = row(value, on: "2026-11-19"), today = row(value); value.entries = [past, today]
        let feedback = HomeEntryFeedback.make(savedIDs: [past.id, today.id], fromHome: true, ledger: value, now: now)
        XCTAssertEqual(feedback.highlightedIDs, [today.id]); XCTAssertTrue(feedback.needsToast)
    }
    func testDeletedSessionEntryDoesNotHighlightOrProduceSavedToast() {
        var value = ledger(); var deleted = row(value); deleted.deletedAt = now; value.entries = [deleted]
        let feedback = HomeEntryFeedback.make(savedIDs: [deleted.id], fromHome: true, ledger: value, now: now)
        XCTAssertTrue(feedback.highlightedIDs.isEmpty); XCTAssertFalse(feedback.needsToast)
    }
    func testFutureSessionEntryRetainsToastAndMidnightRollsReceipt() {
        var value = ledger(); let future = row(value, on: "2026-11-21"); value.entries = [future]
        let feedback = HomeEntryFeedback.make(savedIDs: [future.id], fromHome: true, ledger: value, now: now)
        XCTAssertTrue(feedback.highlightedIDs.isEmpty); XCTAssertTrue(feedback.needsToast)
        let posted = HomeEntryFeedback.make(savedIDs: [future.id], fromHome: true, ledger: value, now: date("2026-11-21"))
        XCTAssertEqual(posted.highlightedIDs, [future.id]); XCTAssertFalse(posted.needsToast)
    }

}
