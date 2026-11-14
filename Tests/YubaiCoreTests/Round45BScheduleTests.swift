import XCTest
@testable import YubaiCore

final class Round45BScheduleTests: XCTestCase {
    let now = Round45BFixture.now
    func d(_ text: String) -> Date { Round45BFixture.d(text) }
    func billLedger() -> Ledger {
        var ledger = Round45BFixture.ledger()
        var bill = Plan(title: "电费", amount: 18_000, dueDate: d("2026-11-25"), frequency: .monthly)
        bill.accountID = ledger.accounts[0].id; ledger.plans = [bill]; return ledger
    }
    func testMoveAcrossCycleBoundaryChangesOnlyOnePeriodAndClearRestores() throws {
        var ledger = billLedger(); let id = ledger.plans[0].id
        let base = Finance.funds(ledger, now: now).available
        try FixedFlows.moveOccurrence(planID: id, occurrence: d("2026-11-25"), to: d("2026-12-02"), in: &ledger, now: now)
        XCTAssertEqual(Finance.funds(ledger, now: now).available, base + 18_000)
        XCTAssertEqual(Finance.formula(ledger, now: now).billCount, 0)
        XCTAssertTrue(FixedFlows.month(containing: now, in: ledger).occurrences.isEmpty)
        let december = FixedFlows.month(containing: d("2026-12-10"), in: ledger).occurrences
        XCTAssertEqual(december.map(\.date), [d("2026-12-02"), d("2026-12-25")])
        XCTAssertNil(ledger.plans[0].occurrenceIndex(on: d("2026-11-25")))
        try FixedFlows.clearOccurrenceMove(planID: id, occurrence: d("2026-12-02"), in: &ledger, now: now)
        XCTAssertNil(ledger.plans[0].occurrenceDateOverrides)
        XCTAssertEqual(Finance.funds(ledger, now: now).available, base)
    }
    func testMoveEarlierFromFuturePeriodIsFoundAndUsesSameInstallmentIndex() throws {
        var ledger = billLedger(); ledger.plans[0].installments = 2
        let id = ledger.plans[0].id
        try FixedFlows.moveOccurrence(planID: id, occurrence: d("2026-12-25"), to: d("2026-11-22"), in: &ledger, now: now)
        let rows = FixedFlows.month(containing: now, in: ledger).occurrences
        XCTAssertEqual(rows.map(\.date), [d("2026-11-22"), d("2026-11-25")])
        XCTAssertEqual(rows.first?.installment?.index, 2)
        XCTAssertEqual(ledger.plans[0].nextScheduledDate(after: now), d("2026-11-22"))
    }
    func testMoveMigratesPaidAndSkippedReferencesAndRoundTrips() throws {
        var ledger = billLedger(); let id = ledger.plans[0].id
        let entry = Round45BFixture.entry(ledger, date: "2026-11-20", amount: 18_000)
        ledger.entries = [entry]
        try FixedFlows.markPaid(planID: id, occurrence: d("2026-11-25"), with: entry.id, in: &ledger)
        try FixedFlows.moveOccurrence(planID: id, occurrence: d("2026-11-25"), to: d("2026-11-29"), in: &ledger, now: now)
        XCTAssertEqual(ledger.entries[0].occurrence, d("2026-11-29"))
        XCTAssertEqual(ledger.plans[0].settledOccurrences, [d("2026-11-29")])
        XCTAssertEqual(FixedFlows.month(containing: now, in: ledger).occurrences.first?.state, .paid)
        XCTAssertEqual(try JSONDecoder().decode(Ledger.self, from: JSONEncoder().encode(ledger)), ledger)
        try FixedFlows.unlink(entryID: entry.id, in: &ledger)
        ledger.plans[0].skippedOccurrences = [d("2026-11-29")]
        try FixedFlows.clearOccurrenceMove(planID: id, occurrence: d("2026-11-29"), in: &ledger, now: now)
        XCTAssertEqual(ledger.plans[0].skippedOccurrences, [d("2026-11-25")])
        XCTAssertTrue(Finance.occurrences(in: ledger, now: now, days: 10).isEmpty)
    }
    func testMoveMatchesAndAutoLinksAtNewDate() throws {
        var ledger = billLedger(); let id = ledger.plans[0].id
        try FixedFlows.moveOccurrence(planID: id, occurrence: d("2026-11-25"), to: d("2026-11-20"), in: &ledger, now: now)
        let entry = Round45BFixture.entry(ledger, date: "2026-11-20 10:00", amount: 18_000)
        ledger.entries = [entry]
        XCTAssertEqual(FixedFlows.matchingEntries(planID: id, occurrence: d("2026-11-20"), in: ledger, now: now).map(\.id), [entry.id])
        XCTAssertEqual(FixedFlows.autoLink(&ledger, addedEntryIDs: [entry.id], now: now).first?.occurrence, d("2026-11-20"))
        XCTAssertEqual(Finance.formula(ledger, now: now).billsPaid, 1)
    }
    func testMovedSalaryDueAndCycleUseReplacementDay() throws {
        var ledger = Round45Fixture.ledger(); ledger.paydayConfirmSince = d("2026-12-10")
        let id = ledger.plans[0].id
        try FixedFlows.moveOccurrence(planID: id, occurrence: d("2026-12-10"), to: d("2026-12-13"), in: &ledger, now: now)
        XCTAssertNil(Payday.due(in: ledger, now: d("2026-12-12")))
        XCTAssertEqual(Finance.cycleInfo(in: ledger, now: d("2026-12-12")).end, d("2026-12-12"))
        let at = d("2026-12-15 12:00"), due = try XCTUnwrap(Payday.due(in: ledger, now: at))
        XCTAssertEqual(due.occurrence, d("2026-12-13")); XCTAssertEqual(due.lateDays, 2)
        try Payday.confirm(due, amount: due.usual, extraToSavings: false, accountID: nil, in: &ledger, now: at)
        XCTAssertEqual(Finance.cycleInfo(in: ledger, now: at).start, d("2026-12-15"))
        XCTAssertEqual(Finance.cycleInfo(in: ledger, now: d("2026-12-14")).end, d("2026-12-14"))
    }
    func testInvalidMovesAndCollisionsAreAtomic() {
        var ledger = billLedger(); let before = ledger, id = ledger.plans[0].id
        for date in [d("2026-12-25"), Date.distantFuture] {
            XCTAssertThrowsError(try FixedFlows.moveOccurrence(planID: id, occurrence: d("2026-11-25"), to: date, in: &ledger, now: now))
            XCTAssertEqual(ledger, before)
        }
        XCTAssertThrowsError(try FixedFlows.moveOccurrence(planID: id, occurrence: d("2026-11-24"), to: now, in: &ledger, now: now))
        XCTAssertEqual(ledger, before)
    }
    func testOriginalMonthEndDoesNotDriftAfterMove() throws {
        var ledger = billLedger(); ledger.plans[0].dueDate = d("2026-01-31"); ledger.plans[0].monthlyDay = 31
        let id = ledger.plans[0].id
        try FixedFlows.moveOccurrence(planID: id, occurrence: d("2026-02-28"), to: d("2026-03-02"), in: &ledger, now: now)
        XCTAssertNotNil(ledger.plans[0].occurrenceIndex(on: d("2026-03-31")))
        XCTAssertNil(ledger.plans[0].occurrenceIndex(on: d("2026-02-28")))
    }
}
