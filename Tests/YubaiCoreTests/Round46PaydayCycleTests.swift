import XCTest
@testable import YubaiCore

final class Round46PaydayCycleTests: XCTestCase {
    private func d(_ value: String) -> Date { Dates.parse(value)! }
    private func ledger() -> Ledger {
        var value = Ledger()
        value.accounts = [Account(name: "Bank", balance: 1_000_000, at: d("2026-11-12"))]
        value.fixedSavings = 200_000; value.savingRule = .fixed(100_000)
        value.cycleAnchor = .payday; value.paydayConfirmSince = d("2026-11-15")
        var salary = Plan(title: "工资", amount: 800_000, dueDate: d("2026-10-15"), frequency: .monthly,
                          inflow: true, category: "工资奖金", nature: .income)
        salary.accountID = value.accounts[0].id
        value.plans = [salary]
        return value
    }
    private func record(_ day: String, occurrence: String = "2026-11-15", in value: inout Ledger) throws {
        let due = Payday.Due(planID: value.plans[0].id, occurrence: d(occurrence), title: "工资", usual: 800_000, lateDays: 0)
        try Payday.confirm(due, amount: 800_000, extraToSavings: false, accountID: nil, in: &value, now: d(day + " 09:00"))
    }
    private func assertCycle(_ value: Ledger, at day: String, start: String, end: String,
                             file: StaticString = #filePath, line: UInt = #line) {
        let info = Finance.cycleInfo(in: value, now: d(day + " 12:00"))
        XCTAssertEqual(info.start, d(start), file: file, line: line)
        XCTAssertEqual(info.end, d(end), file: file, line: line)
        XCTAssertEqual(info.nextPayday, Dates.addDays(1, to: d(end)), file: file, line: line)
        XCTAssertNil(info.lateSince, file: file, line: line)
    }

    func testEarlyArrivalConsumesTheFifteenthAndKeepsTheFullCycle() throws {
        var value = ledger(); try record("2026-11-13", in: &value)
        for day in ["2026-11-13", "2026-11-14", "2026-11-15", "2026-12-14"] {
            assertCycle(value, at: day, start: "2026-11-13", end: "2026-12-14")
            XCTAssertNil(Payday.due(in: value, now: d(day + " 12:00")))
        }
        XCTAssertEqual(Finance.cycleInfo(in: value, now: d("2026-11-12")).end, d("2026-11-12"))
    }

    func testLateArrivalExtendsTheOldCycleUntilTheSeventeenth() throws {
        var value = ledger()
        let late = Finance.cycleInfo(in: value, now: d("2026-11-16 12:00"))
        XCTAssertEqual(late.start, d("2026-10-15")); XCTAssertEqual(late.end, d("2026-11-16"))
        XCTAssertEqual(late.lateSince, d("2026-11-15")); XCTAssertNil(Finance.pace(value, now: d("2026-11-16"))?.daily)
        try record("2026-11-17", in: &value)
        assertCycle(value, at: "2026-11-17", start: "2026-11-17", end: "2026-12-14")
        XCTAssertEqual(Finance.cycleInfo(in: value, now: d("2026-11-16")).end, d("2026-11-16"))
    }

    func testOwnerMovesOnlyThisPaydayEarlierAndConfirmationStillRequired() throws {
        var value = ledger()
        try FixedFlows.moveOccurrence(planID: value.plans[0].id, occurrence: d("2026-11-15"),
                                      to: d("2026-11-13"), in: &value, now: d("2026-11-13"))
        let unpaid = Finance.cycleInfo(in: value, now: d("2026-11-13 08:00"))
        XCTAssertEqual(unpaid.start, d("2026-10-15")); XCTAssertEqual(unpaid.lateSince, d("2026-11-13"))
        XCTAssertEqual(Payday.due(in: value, now: d("2026-11-13"))?.occurrence, d("2026-11-13"))
        try record("2026-11-13", occurrence: "2026-11-13", in: &value)
        assertCycle(value, at: "2026-11-13", start: "2026-11-13", end: "2026-12-14")
    }

    func testOwnerMovesAnAlreadyRecordedPaydayAndCanRestoreItsSchedule() throws {
        var value = ledger(); try record("2026-11-13", in: &value)
        try FixedFlows.moveOccurrence(planID: value.plans[0].id, occurrence: d("2026-11-15"),
                                      to: d("2026-11-13"), in: &value, now: d("2026-11-13 12:00"))
        XCTAssertEqual(value.entries[0].occurrence, d("2026-11-13"))
        assertCycle(value, at: "2026-11-15", start: "2026-11-13", end: "2026-12-14")
        try FixedFlows.clearOccurrenceMove(planID: value.plans[0].id, occurrence: d("2026-11-13"),
                                           in: &value, now: d("2026-11-16"))
        assertCycle(value, at: "2026-11-16", start: "2026-11-13", end: "2026-12-14")
        XCTAssertNil(Payday.due(in: value, now: d("2026-11-16")))
    }

    func testNextMonthReturnsToScheduledDayAfterEarlyLateOrMovedArrival() throws {
        for (day, moved) in [("2026-11-13", false), ("2026-11-17", false), ("2026-11-13", true)] {
            var value = ledger()
            if moved {
                try FixedFlows.moveOccurrence(planID: value.plans[0].id, occurrence: d("2026-11-15"),
                                              to: d(day), in: &value, now: d(day))
            }
            try record(day, occurrence: moved ? day : "2026-11-15", in: &value)
            XCTAssertEqual(Payday.due(in: value, now: d("2026-12-15"))?.occurrence, d("2026-12-15"))
            try record("2026-12-15", occurrence: "2026-12-15", in: &value)
            assertCycle(value, at: "2026-12-15", start: "2026-12-15", end: "2027-01-14")
            assertCycle(value, at: "2026-11-20", start: day, end: "2026-12-14")
        }
    }

    func testScheduledDayArrivalIsUnchanged() throws {
        var value = ledger(); try record("2026-11-15", in: &value)
        assertCycle(value, at: "2026-11-15", start: "2026-11-15", end: "2026-12-14")
        XCTAssertEqual(Finance.pace(value, now: d("2026-11-15 12:00"))?.daysTotal, 30)
    }

    func testAllCycleReadersUseTheUnpaidNextMonthAndReserveBillsOnce() throws {
        var value = ledger()
        value.plans.append(Plan(title: "Rent", amount: 20_000, dueDate: d("2026-11-25")))
        var yearly = Plan(title: "Annual", amount: 120_000, dueDate: d("2026-12-01"), frequency: .yearly)
        yearly.yearlyReserveSince = d("2026-01-01"); value.plans.append(yearly)
        try record("2026-11-13", in: &value)
        let now = d("2026-11-13 12:00"), funds = Finance.funds(value, now: now)
        XCTAssertEqual(funds.cycleStart, d("2026-11-13")); XCTAssertEqual(funds.horizonEnd, d("2026-12-14"))
        XCTAssertEqual(funds.payday, d("2026-12-15")); XCTAssertEqual(funds.horizonDays, 31)
        XCTAssertEqual(funds.committed, 140_000); XCTAssertEqual(funds.yearlySetAside, 0)
        XCTAssertEqual(funds.available, 1_360_000)
        let pace = try XCTUnwrap(Finance.pace(value, now: now))
        XCTAssertEqual(pace.daysTotal, 32); XCTAssertEqual(pace.daysLeft, 32); XCTAssertEqual(pace.daily, 42_500)
        let derivation = Finance.spendingDerivation(value, now: now)
        XCTAssertEqual(derivation.available, funds.available); XCTAssertEqual(derivation.daily, pace.daily)
        XCTAssertEqual(derivation.interval.start, d("2026-11-13"))
        XCTAssertEqual(derivation.interval.end, now.addingTimeInterval(0.001))
        XCTAssertFalse(HomeButler.queue(value, now: d("2026-11-15 12:00")).contains { if case .payday = $0 { return true }; return false })
        let rows = YearlyBillReserves.rows(in: value, now: now, committedThrough: funds.horizonEnd)
        XCTAssertEqual(rows.first?.reserved, 0)
    }

    func testSavingsClosesAtActualArrivalsAndNeverAtTheConsumedPayday() throws {
        var value = ledger(); try record("2026-11-13", in: &value)
        Savings.closeCycles(&value, now: d("2026-11-13 12:00"))
        XCTAssertEqual(value.savingHistory.count, 1); XCTAssertEqual(value.savingHistory[0].cycleEnd, d("2026-11-12"))
        let closed = value
        Savings.closeCycles(&value, now: d("2026-11-15 12:00")); XCTAssertEqual(value, closed)
        Savings.closeCycles(&value, now: d("2026-12-15 08:00")); XCTAssertEqual(value, closed)
        try record("2026-12-15", occurrence: "2026-12-15", in: &value)
        Savings.closeCycles(&value, now: d("2026-12-15 12:00"))
        XCTAssertEqual(value.savingHistory.count, 2)
        XCTAssertEqual(value.savingHistory.last?.cycleStart, d("2026-11-13"))
        XCTAssertEqual(value.savingHistory.last?.cycleEnd, d("2026-12-14"))
        let next = value; Savings.closeCycles(&value, now: d("2026-12-16")); XCTAssertEqual(value, next)
    }

    func testNextArrivalCanMoveTheBoundaryAgain() throws {
        for (next, previous) in [("2026-12-12", "2026-12-11"), ("2026-12-17", "2026-12-16")] {
            var value = ledger(); try record("2026-11-13", in: &value)
            if next == "2026-12-17" {
                let late = Finance.cycleInfo(in: value, now: d(previous))
                XCTAssertEqual(late.start, d("2026-11-13")); XCTAssertEqual(late.lateSince, d("2026-12-15"))
                XCTAssertNil(Finance.pace(value, now: d(previous))?.daily)
            }
            try record(next, occurrence: "2026-12-15", in: &value)
            assertCycle(value, at: previous, start: "2026-11-13", end: previous)
            assertCycle(value, at: next, start: next, end: "2027-01-14")
        }
    }

    func testDeletingEarlyReceiptRestoresTheUnpaidPeriod() throws {
        var value = ledger(); try record("2026-11-13", in: &value)
        value.entries[0].deletedAt = d("2026-11-14")
        let info = Finance.cycleInfo(in: value, now: d("2026-11-16"))
        XCTAssertEqual(info.start, d("2026-10-15")); XCTAssertEqual(info.lateSince, d("2026-11-15"))
        XCTAssertEqual(Payday.due(in: value, now: d("2026-11-16"))?.lateDays, 1)
    }

    func testCalendarMonthIgnoresEarlySalaryBoundaries() throws {
        var value = ledger(); value.cycleAnchor = .calendarMonth; try record("2026-11-13", in: &value)
        let info = Finance.cycleInfo(in: value, now: d("2026-11-13 12:00"))
        XCTAssertEqual(info.start, d("2026-11-01")); XCTAssertEqual(info.end, d("2026-11-30"))
        XCTAssertNil(Payday.due(in: value, now: d("2026-11-15")))
    }
}
