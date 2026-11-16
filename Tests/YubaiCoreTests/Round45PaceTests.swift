import XCTest
@testable import YubaiCore

final class Round45PaceTests: XCTestCase {
    let now = Round45Fixture.now
    func testStorylineAndTodayPurchasesAdvanceWaterFill() throws {
        var l = Round45Fixture.ledger(); let before = Finance.spendableBreakdown(l, now: now)
        XCTAssertEqual(before.start, Round45Fixture.date("2026-11-10")); XCTAssertEqual(before.end, Round45Fixture.date("2026-12-09"))
        XCTAssertEqual(before.income, 801_000); XCTAssertEqual(before.spent, 83_600)
        let change = try ManualBookkeeping.change(amount: 3200, nature: .expense, accountID: l.accounts[0].id, day: now, purpose: "Lunch", category: "餐饮", now: now)
        try change.apply(to: &l)
        let after = Finance.spendableBreakdown(l, now: now)
        XCTAssertEqual(after.available, before.available - 3200); XCTAssertEqual(after.spent, 86_800)
        XCTAssertEqual(after.waterBar?.tick, before.waterBar?.tick)
        XCTAssertGreaterThan(after.waterBar!.fill, before.waterBar!.fill)
    }
    func testWaterTickCountsTodayAndRespectsFinalDay() {
        let l = Round45Fixture.ledger()
        for (date, tick) in [("2026-11-10 12:00", 1.0/30), ("2026-11-20 12:00", 11.0/30), ("2026-12-09 12:00", 1.0)] {
            XCTAssertEqual(Finance.spendableBreakdown(l, now: Round45Fixture.date(date)).waterBar!.tick, tick, accuracy: 0.00001)
        }
    }
    func testFastThresholdHasStrictFifteenPercentBoundary() {
        for (spend, fast) in [(Int64(45_000), false), (45_001, true)] {
            var l = Round45Fixture.ledger(); l.plans.removeAll { !$0.inflow }; l.savingRule = nil
            l.entries[0].amount = 100_000; l.entries = [l.entries[0], Round45Fixture.entry(l, amount: spend, date: "2026-11-17")]
            let bar = Finance.spendableBreakdown(l, now: Round45Fixture.date("2026-11-18")).waterBar!
            XCTAssertEqual(bar.fast, fast)
            XCTAssertEqual(bar.fill, Double(spend)/100_000, accuracy: 0.00001)
        }
    }
    func testNoIncomeAndUnknownPlanHideTheWaterBar() {
        var l = Round45Fixture.ledger(); l.entries.removeAll { $0.nature == .income }
        XCTAssertNil(Finance.spendableBreakdown(l, now: now).waterBar)
        l = Round45Fixture.ledger(); l.plans.removeAll { $0.inflow }
        XCTAssertNil(Finance.spendableBreakdown(l, now: now).waterBar)
    }
    func testRefundsAndPaidBillsUseAllPeriodSpending() {
        var l = Round45Fixture.ledger(); let before = Finance.spendableBreakdown(l, now: now)
        var refund = Round45Fixture.entry(l, amount: 1000, date: "2026-11-20 11:00", nature: .refund)
        refund.relatedEntryID = l.entries[1].id; l.entries.append(refund)
        XCTAssertEqual(Finance.spendableBreakdown(l, now: now).spent, before.spent - 1000)
        var bill = Round45Fixture.entry(l, amount: 1000, date: "2026-11-20 11:00")
        bill.planID = l.plans[1].id; bill.occurrence = l.plans[1].dueDate; l.entries.append(bill)
        XCTAssertEqual(Finance.spendableBreakdown(l, now: now).spent, before.spent)
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
        let pace = Finance.spendableBreakdown(ledger, now: at)
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
