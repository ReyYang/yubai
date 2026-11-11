import XCTest
@testable import YubaiCore

final class Round45BillTests: XCTestCase {
    let now = Round45Fixture.now
    func fixture() -> Ledger {
        var l = Round45Fixture.ledger(); l.entries = []
        l.plans = [Plan(title: "Mobile", amount: 16_000, dueDate: Dates.day(now), category: "居家")]
        return l
    }
    func testBillMatchUsesActualAmountWithoutAddingEntryAndUnlinkRestores() throws {
        var l = fixture(); let baseline = Finance.funds(l, now: now).available, id = l.plans[0].id
        var entry = Round45Fixture.entry(l, amount: 15_800, date: "2026-11-20 12:00", title: "Mobile charge")
        entry.recordedAt = now; l.entries.append(entry)
        let matches = FixedFlows.matchingEntries(planID: id, occurrence: Dates.day(now), in: l, now: now)
        XCTAssertEqual(matches.map(\.id), [entry.id])
        let count = l.entries.count
        try FixedFlows.markPaid(planID: id, occurrence: Dates.day(now), with: entry.id, in: &l)
        XCTAssertEqual(l.entries.count, count); XCTAssertEqual(Finance.funds(l, now: now).available, baseline + 200)
        XCTAssertEqual(FixedFlows.month(containing: now, in: l).occurrences.first?.state, .paid)
        XCTAssertEqual(Finance.formula(l, now: now).billsPaid, 1)
        try FixedFlows.unlink(entryID: entry.id, in: &l)
        XCTAssertNil(l.entries[0].planID); XCTAssertTrue(l.plans[0].settledOccurrences.isEmpty)
        XCTAssertEqual(Finance.funds(l, now: now).available, baseline - 15_800)
    }
    func testMatchingRulesLimitAndHistory() throws {
        var l = fixture(); let id = l.plans[0].id
        l.entries = [Round45Fixture.entry(l, amount: 16_000, date: "2026-11-20 11:00", title: "Exact"),
                     Round45Fixture.entry(l, amount: 15_800, date: "2026-11-19", title: "Mobile"),
                     Round45Fixture.entry(l, amount: 17_000, date: "2026-11-18", title: "Mobile"),
                     Round45Fixture.entry(l, amount: 15_000, date: "2026-11-20 10:00", title: "Mobile"),
                     Round45Fixture.entry(l, amount: 12_000, date: "2026-11-20 10:00", title: "Unrelated"),
                     Round45Fixture.entry(l, amount: 16_000, date: "2026-11-24", title: "Future")]
        let matches = FixedFlows.matchingEntries(planID: id, occurrence: now, in: l, now: now)
        XCTAssertEqual(matches.count, 3); XCTAssertEqual(matches.first?.title, "Exact")
        XCTAssertFalse(matches.contains { $0.title == "Unrelated" || $0.title == "Future" })
        XCTAssertEqual(FixedFlows.linkCandidates(planID: id, in: l, now: now).count, 5)
        XCTAssertEqual(FixedFlows.expectedAmount(planID: id, in: l), 16_000)
        let entry = l.entries[1]; try FixedFlows.markPaid(planID: id, occurrence: now, with: entry.id, in: &l)
        XCTAssertEqual(FixedFlows.history(planID: id, in: l).average, 15_800)
        l.plans[0].estimated = true
        XCTAssertEqual(FixedFlows.expectedAmount(planID: id, in: l), 15_800)
    }
    func testAutoLinkUniqueAmbiguousAndAlreadyPaid() throws {
        var l = fixture(); let id = l.plans[0].id
        let entry = Round45Fixture.entry(l, amount: 16_000, date: "2026-11-20 11:00", title: "Mobile")
        l.entries = [entry]
        let result = FixedFlows.autoLink(&l, addedEntryIDs: [entry.id], now: now)
        XCTAssertEqual(result.count, 1); XCTAssertEqual(result.first?.planID, id)
        XCTAssertTrue(FixedFlows.autoLink(&l, addedEntryIDs: [entry.id], now: now).isEmpty)
        var another = entry; another.id = UUID(); l.entries.append(another)
        XCTAssertTrue(FixedFlows.autoLink(&l, addedEntryIDs: [another.id], now: now).isEmpty)
        XCTAssertNil(l.entries.last?.planID)
        l = fixture(); l.entries = [entry]; var plan = l.plans[0]; plan.id = UUID(); l.plans.append(plan)
        XCTAssertTrue(FixedFlows.autoLink(&l, addedEntryIDs: [entry.id], now: now).isEmpty)
        l.plans.removeLast(); l.entries.append(another)
        XCTAssertTrue(FixedFlows.autoLink(&l, addedEntryIDs: [entry.id, another.id], now: now).isEmpty)
    }
    func testImportedSalaryAutoConfirmsAndRespectsAmbiguousPeriods() throws {
        var l = Round45Fixture.ledger(); l.paydayConfirmSince = Round45Fixture.date("2026-12-10")
        let at = Round45Fixture.date("2026-12-11 12:00")
        var income = Round45Fixture.entry(l, amount: 801_000, date: "2026-12-11 09:00", nature: .income, title: "工资")
        income.batchID = UUID(); l.entries.append(income)
        XCTAssertNotNil(Payday.due(in: l, now: at))
        XCTAssertEqual(FixedFlows.autoLink(&l, addedEntryIDs: [income.id], now: at).count, 1)
        XCTAssertNil(Payday.due(in: l, now: at)); XCTAssertEqual(Finance.cycle(in: l, now: at).start, Dates.day(at))
        l = fixture(); l.plans[0].frequency = .weekly
        var row = Round45Fixture.entry(l, amount: 16_000, date: "2026-11-20", title: "Mobile")
        row.planID = UUID(); l.entries = [row]
        XCTAssertTrue(FixedFlows.autoLink(&l, addedEntryIDs: [row.id], now: now).isEmpty)
    }
    func testHistoryUsesLatestTwelveAndAverage() {
        var l = fixture(); let plan = l.plans[0]
        l.entries = (0..<14).map { n in
            var e = Round45Fixture.entry(l, amount: Int64(n + 1) * 100, date: Dates.text(Dates.addDays(-n, to: now)))
            e.planID = plan.id; e.occurrence = plan.dueDate; return e
        }
        let history = FixedFlows.history(planID: plan.id, in: l)
        XCTAssertEqual(history.entries.count, 12); XCTAssertEqual(history.average, 650)
    }
}

extension Round45BillTests {
    func testEstimatedManualCandidatesAreBroaderThanAutomaticLinksAndSortByDay() throws {
        var l = fixture(); l.plans[0].estimated = true
        let id = l.plans[0].id
        let exact = Round45Fixture.entry(l, amount: 16_000, date: "2026-11-19 23:59", title: "Exact")
        let sameDay = Round45Fixture.entry(l, amount: 16_000, date: "2026-11-20 11:00", title: "Exact")
        let unrelated = Round45Fixture.entry(l, amount: 9000, date: "2026-11-20 10:00", title: "Unrecognized merchant")
        l.entries = [exact, unrelated, sameDay]
        let matches = FixedFlows.matchingEntries(planID: id, occurrence: now, in: l, now: now)
        XCTAssertEqual(matches.first?.id, sameDay.id); XCTAssertTrue(matches.contains { $0.id == unrelated.id })
        XCTAssertTrue(FixedFlows.autoLink(&l, addedEntryIDs: [unrelated.id], now: now).isEmpty)
        XCTAssertNil(l.entries[1].planID)
    }
    func testManualLinkCanFinishExistingPartialPayment() throws {
        var l = fixture(); let id = l.plans[0].id
        var partial = Round45Fixture.entry(l, amount: 10_000, date: "2026-11-20 10:00")
        partial.planID = id; partial.occurrence = Dates.day(now)
        let remainder = Round45Fixture.entry(l, amount: 5800, date: "2026-11-20 11:00")
        l.entries = [partial, remainder]
        try FixedFlows.markPaid(planID: id, occurrence: now, with: remainder.id, in: &l)
        XCTAssertEqual(FixedFlows.month(containing: now, in: l).occurrences.first?.state, .paid)
    }
}
