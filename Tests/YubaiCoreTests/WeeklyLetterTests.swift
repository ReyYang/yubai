import XCTest
@testable import YubaiCore

final class WeeklyLetterTests: XCTestCase {
    private let sunday = Dates.parse("2026-06-14 12:00")!
    private func seed() -> Ledger {
        var ledger = Ledger()
        ledger.accounts = [Account(name: "合成账户", balance: 500_000, at: Dates.parse("2026-05-01")!)]
        ledger.preferences.dailyLiving = 1000; ledger.preferences.emergencyReserve = 20_000
        let meal = Entry(date: Dates.parse("2026-06-10 12:00")!, amount: 6000, accountID: ledger.accounts[0].id, title: "用餐", category: "餐饮")
        var refund = Entry(date: Dates.parse("2026-06-13 12:00")!, amount: 1000, nature: .refund, accountID: ledger.accounts[0].id, title: "退款")
        refund.relatedEntryID = meal.id
        ledger.entries = [meal, refund]
        return ledger
    }
    func testFactsEqualFinanceSpendingSeriesAndWeeklyDifference() {
        let ledger = seed(); let facts = WeeklyLetter.facts(ledger, weekEnding: sunday)
        let start = Dates.parse("2026-06-08")!; let end = Dates.parse("2026-06-15")!
        XCTAssertEqual(facts.spending, Finance.review(ledger, from: start, through: end).spending)
        XCTAssertEqual(facts.spending, 5000); XCTAssertEqual(facts.comparison.cents, 5000)
        XCTAssertEqual(facts.series.count, 7)
        for point in facts.series {
            let close = Dates.addDays(1, to: point.date).addingTimeInterval(-0.001)
            // No later anchors/plans in this ledger, so Finance can directly verify each day.
            XCTAssertEqual(point.available, Finance.funds(ledger, now: close).available)
        }
        XCTAssertEqual(facts.availableChange, facts.series.last!.available - Finance.funds(ledger, now: start.addingTimeInterval(-0.001)).available)
        XCTAssertEqual(facts.numbers.count, 3)
    }
    func testLaterReconciliationIsRewoundAndFuturePaymentNotMarkedPaidEarly() {
        var ledger = seed(); let end = Dates.parse("2026-06-14 23:59")!
        let old = Finance.funds(ledger, now: end).available
        ledger.accounts[0].anchorBalance = Finance.balance(ledger.accounts[0], in: ledger, at: end)
        ledger.accounts[0].anchorDate = end
        let earlier = Dates.parse("2026-06-09 23:59")!
        XCTAssertEqual(WeeklyLetter.available(ledger, at: earlier), 500_000 - 20_000 - 90_000)
        XCTAssertEqual(WeeklyLetter.available(ledger, at: end), old)
        let plan = Plan(title: "房租", amount: 30_000, dueDate: Dates.parse("2026-06-11")!)
        ledger.plans = [plan]
        var paid = Entry(date: plan.dueDate, amount: plan.amount, accountID: ledger.accounts[0].id, title: "房租")
        paid.planID = plan.id; paid.occurrence = plan.dueDate
        ledger.entries.append(paid)
        // Rewind the recorded payment as well as reserve it at the earlier date.
        XCTAssertEqual(WeeklyLetter.available(ledger, at: earlier), 500_000 - 20_000 - 90_000)
    }
    func testRestrainedThirdNumberAndFreshLetterDedupeFallback() async throws {
        var ledger = seed()
        ledger.profile.restrain = [ProfileArea(title: "用餐", match: AreaMatch(categories: ["餐饮"]), softLimit: SoftLimit(perWeekCount: 1))]
        XCTAssertEqual(WeeklyLetter.facts(ledger, weekEnding: sunday).comparison.value, "1 个 / 1 个")
        let monday = Dates.parse("2026-06-15 10:00")!
        let candidate = try XCTUnwrap(WeeklyLetter.candidate(ledger, now: monday))
        XCTAssertEqual(candidate.dedupeKey, "letter:" + ButlerCards.isoWeek(monday))
        let template = await ButlerWording.word([candidate], ledger: ledger, transport: nil)
        XCTAssertEqual(template, [candidate])
        XCTAssertTrue(ButlerCards.refresh(&ledger, candidates: template, now: monday))
        let card = try XCTUnwrap(ledger.cards.first)
        XCTAssertTrue(WeeklyLetter.isFresh(card, now: monday))
        XCTAssertTrue(WeeklyLetter.isFresh(card, now: Dates.addDays(2, to: monday)))
        XCTAssertFalse(WeeklyLetter.isFresh(card, now: Dates.addDays(3, to: monday)))
        XCTAssertNil(WeeklyLetter.candidate(ledger, now: monday))
        XCTAssertEqual(try LedgerCodec.decode(LedgerCodec.encode(ledger)).cards.first?.letter, card.letter)
    }
    func testWeeklyPushDefaultsOffForOldPreferences() throws {
        let ledger = seed()
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: LedgerCodec.encode(ledger)) as? [String: Any])
        var preferences = try XCTUnwrap(json["preferences"] as? [String: Any])
        preferences.removeValue(forKey: "weeklyLetterPush"); json["preferences"] = preferences
        XCTAssertFalse(try LedgerCodec.decode(JSONSerialization.data(withJSONObject: json)).preferences.weeklyLetterPush)
        var enabled = ledger; enabled.preferences.weeklyLetterPush = true
        XCTAssertTrue(try LedgerCodec.decode(LedgerCodec.encode(enabled)).preferences.weeklyLetterPush)
    }
    func testLetterUnverifiedAmountFallsBackAndStableMuteSuppressesNextWeek() async throws {
        var ledger = seed(); let monday = Dates.parse("2026-06-15 10:00")!
        let candidate = try XCTUnwrap(WeeklyLetter.candidate(ledger, now: monday))
        let script = ScriptedChatTransport([ChatMessage(role: .assistant, content: try JSONValue.object(["cards": .array([
            .object(["key": .string("c0"), "title": .string("这周的来信"), "body": .string("这周消费 ¥123456.78。")])])]).jsonText())])
        let worded = await ButlerWording.word([candidate], ledger: ledger, transport: script)
        XCTAssertEqual(worded, [candidate])
        ButlerCards.refresh(&ledger, candidates: worded, now: monday)
        ButlerCards.mute(ledger.cards[0].id, in: &ledger, now: monday)
        XCTAssertEqual(ledger.mutedTopics, ["letter"])
        XCTAssertNil(WeeklyLetter.candidate(ledger, now: Dates.addDays(7, to: monday)))
    }
}
