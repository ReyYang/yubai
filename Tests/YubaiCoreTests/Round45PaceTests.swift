import XCTest
@testable import YubaiCore

final class Round45PaceTests: XCTestCase {
    let now = Round45Fixture.now
    func testStorylineAndTodayPurchasesFreezeDaily() throws {
        var l = Round45Fixture.ledger(); let pace = try XCTUnwrap(Finance.pace(l, now: now))
        XCTAssertEqual(pace.start, Round45Fixture.date("2026-11-10")); XCTAssertEqual(pace.end, Round45Fixture.date("2026-12-09"))
        XCTAssertEqual(pace.available, 156_400); XCTAssertEqual(pace.spent, 83_600); XCTAssertEqual(pace.budget, 240_000)
        XCTAssertEqual(pace.daysLeft, 20); XCTAssertEqual(pace.daysTotal, 30); XCTAssertEqual(pace.morningAvailable, 160_000)
        XCTAssertEqual(pace.daily, 8000); XCTAssertEqual(pace.baseDaily, 8000); XCTAssertEqual(pace.evenToDate, 80_000)
        let change = try ManualBookkeeping.change(amount: 3200, nature: .expense, accountID: l.accounts[0].id, day: now, purpose: "Lunch", category: "餐饮", now: now)
        try change.apply(to: &l)
        XCTAssertEqual(Finance.pace(l, now: now)?.daily, 8000); XCTAssertEqual(Finance.pace(l, now: now)?.available, 153_200)
        XCTAssertEqual(Finance.pace(l, now: now)?.spent, 86_800)
    }
    func testWeekTableRoundsToCentsAndNeverShowsNegativeDaily() {
        let rows: [(Int64, Int, Int64)] = [(160_000, 20, 8000), (147_400, 19, 7758), (144_000, 18, 8000), (136_000, 17, 8000), (128_000, 16, 8000), (118_900, 15, 7927)]
        for (available, days, daily) in rows {
            var l = Round45Fixture.ledger(); l.entries = []
            let at = Dates.addDays(20 - days, to: now)
            l.accounts[0].anchorDate = at; l.accounts[0].anchorBalance = 1_061_000 + available
            XCTAssertEqual(Finance.pace(l, now: at)?.daily, daily)
        }
        var l = Round45Fixture.ledger(); l.accounts[0].anchorBalance = 0
        XCTAssertNil(Finance.pace(l, now: now)?.daily)
        XCTAssertNil(Finance.pace(l, now: now)?.dailyAfterSpending(1))
    }
    func testFastThresholdAndBothBursts() throws {
        for spent in [104_000 as Int64, 104_001] {
            var l = Round45Fixture.ledger()
            l.entries = [Round45Fixture.entry(l, amount: spent, date: "2026-11-19")]
            l.accounts[0].anchorBalance = 1_061_000 + 240_000 - spent
            let pace = try XCTUnwrap(Finance.pace(l, now: now))
            XCTAssertEqual(pace.isFast, spent > 104_000)
            XCTAssertEqual(pace.burst?.kind, spent > 104_000 ? .lastDays(3) : nil)
        }
        var l = Round45Fixture.ledger(); l.entries = [Round45Fixture.entry(l, amount: 150_000, date: "2026-11-15")]
        l.accounts[0].anchorBalance = 1_151_000; l.accounts[0].anchorDate = Round45Fixture.date("2026-11-17")
        let weekend = try XCTUnwrap(Finance.pace(l, now: Round45Fixture.date("2026-11-17 12:00")))
        XCTAssertEqual(weekend.burst?.kind, .weekend); XCTAssertEqual(weekend.burst?.amount, 150_000)
    }
    func testPreviewIsTomorrowAndLastDayIsNil() throws {
        var l = Round45Fixture.ledger(); let at = Dates.addDays(1, to: now)
        l.accounts[0].anchorBalance = 1_208_400; l.accounts[0].anchorDate = at; l.entries = []
        let pace = try XCTUnwrap(Finance.pace(l, now: at))
        XCTAssertEqual(pace.available, 147_400); XCTAssertEqual(pace.dailyAfterSpending(120_000), 1522)
        XCTAssertNil(Finance.pace(l, now: Round45Fixture.date("2026-12-09"))?.dailyAfterSpending(1))
    }
    func testRefundsOffsetFlexibleOnlyAndPlanChangesApplyImmediately() throws {
        var l = Round45Fixture.ledger(); let before = Finance.pace(l, now: now)!
        l.savingRule = .fixed(250_000)
        XCTAssertEqual(Finance.pace(l, now: now)?.daily, 5500)
        l.savingRule = .fixed(200_000)
        var refund = Round45Fixture.entry(l, amount: 1000, date: "2026-11-20 11:00", nature: .refund)
        refund.relatedEntryID = l.entries[1].id; l.entries.append(refund)
        l.accounts[0].anchorBalance += 1000
        XCTAssertEqual(Finance.pace(l, now: now)?.daily, before.daily)
        XCTAssertEqual(Finance.pace(l, now: now)?.spent, before.spent - 1000)
        var bill = Round45Fixture.entry(l, amount: 1000, date: "2026-11-20 11:00")
        bill.planID = l.plans[1].id; bill.occurrence = l.plans[1].dueDate; l.entries.append(bill)
        XCTAssertEqual(Finance.pace(l, now: now)?.spent, before.spent - 1000)
    }
}

extension PerformanceScaleTests {
    func testRound45PaceAt200000EntriesIsNoSlowerThanPartsSummary() throws {
        let at = Round45Fixture.now
        var ledger = Ledger(); ledger.cycleAnchor = .calendarMonth
        ledger.accounts = [Account(name: "Bank", balance: 50_000_000, at: at)]
        ledger.spendingParts = [SpendingPart(name: "Food", amount: 10_000_000, categories: ["餐饮"])]
        let days = (1...19).map { Dates.addDays(-$0, to: at) }
        ledger.entries = (0..<200_000).map { i in Entry(date: days[i % days.count], amount: 100, accountID: ledger.accounts[0].id, title: "Meal", category: "餐饮") }
        _ = Finance.funds(ledger, now: at)
        let startSummary = ProcessInfo.processInfo.systemUptime
        let summary = SpendingParts.summary(ledger, now: at)
        let summaryTime = ProcessInfo.processInfo.systemUptime - startSummary
        let startPace = ProcessInfo.processInfo.systemUptime
        let pace = try XCTUnwrap(Finance.pace(ledger, now: at))
        let paceTime = ProcessInfo.processInfo.systemUptime - startPace
        XCTAssertEqual(pace.spent, summary.parts[0].spent)
        XCTAssertLessThanOrEqual(paceTime, max(1, summaryTime * 1.25))
        let startFormula = ProcessInfo.processInfo.systemUptime
        let formula = Finance.formula(ledger, now: at)
        let formulaTime = ProcessInfo.processInfo.systemUptime - startFormula
        let startReserve = ProcessInfo.processInfo.systemUptime
        let reserve = Reserve.overview(ledger, now: at)
        let reserveTime = ProcessInfo.processInfo.systemUptime - startReserve
        XCTAssertEqual(formula.available, pace.available); XCTAssertEqual(reserve.total, 0)
        XCTAssertLessThanOrEqual(formulaTime, max(1, summaryTime * 1.25))
        XCTAssertLessThanOrEqual(reserveTime, max(1, summaryTime * 1.25))
        print("Round45 200000 entries: pace=\(paceTime)s formula=\(formulaTime)s reserve=\(reserveTime)s summary=\(summaryTime)s")
    }
}
