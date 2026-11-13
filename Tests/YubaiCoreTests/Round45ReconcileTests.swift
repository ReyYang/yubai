import XCTest
@testable import YubaiCore

final class Round45ReconcileTests: XCTestCase {
    let now = Round45Fixture.now
    func fixture() -> Ledger {
        var l = Round45Fixture.ledger()
        l.accounts[0].anchorDate = Round45Fixture.date("2026-11-17 12:00"); l.accounts[0].anchorBalance = 921_400
        l.entries = [Round45Fixture.entry(l, amount: 100, date: "2026-11-17 12:00")]
        l.plans[1].amount = 51_000
        return l
    }
    func testReconBoardBalanceAvailableAndSpreadTail() throws {
        var l = fixture(); let account = l.accounts[0].id
        let gap = try XCTUnwrap(Reconciliation.gap(in: l, now: now))
        XCTAssertEqual(gap.days, 3); XCTAssertEqual(gap.from, Round45Fixture.date("2026-11-18")); XCTAssertEqual(gap.through, Dates.day(now))
        XCTAssertEqual(Finance.funds(l, now: now).available, 170_400)
        let result = Reconciliation.preview(l, actual: [account: 880_200], now: now)
        XCTAssertEqual(result.missing, 41_200); XCTAssertEqual(result.from, gap.from)
        let added = try Reconciliation.apply(&l, actual: [account: 880_200], now: now)
        XCTAssertEqual(added.count, 1); XCTAssertEqual(Finance.balance(l.accounts[0], in: l, at: now), 880_200)
        XCTAssertEqual(Finance.funds(l, now: now).available, 129_200)
        let entry = l.entries.last!
        XCTAssertEqual(entry.title, "没细记"); XCTAssertEqual(entry.source, "对余额"); XCTAssertNil(entry.recordedAt)
        XCTAssertTrue(Classification.isPending(entry)); XCTAssertTrue(entry.isUnitemized); XCTAssertLessThan(entry.date, now)
        let pace = try XCTUnwrap(Finance.pace(l, now: now)); XCTAssertEqual(pace.daily, 6460)
        let dailySpending = (0..<3).map { offset in
            let day = Dates.addDays(offset, to: gap.from)
            return Finance.cashFlow(l, during: DateInterval(start: day, end: Dates.addDays(1, to: day))).spending
        }
        // Ledger totals retain the actual recording date. The deleted pace
        // graph's interpolated points are no longer part of this contract.
        XCTAssertEqual(dailySpending, [0, 0, 41_200])
        XCTAssertNil(Reconciliation.gap(in: l, now: now))
        let flow = Finance.cashFlow(l, during: DateInterval(start: gap.from, end: Dates.addDays(1, to: Dates.day(now))))
        XCTAssertEqual(flow.spendingByCategory, [Breakdown(category: "没细记", amount: 41_200, count: 1)])
        XCTAssertEqual(try JSONDecoder().decode(Ledger.self, from: JSONEncoder().encode(l)), l)
        l.entries[l.entries.count - 1].category = "购物"
        XCTAssertTrue(l.entries.last!.isUnitemized)
        XCTAssertEqual(Finance.cashFlow(l, during: DateInterval(start: gap.from, end: Dates.addDays(1, to: now))).spendingByCategory.first?.category, "购物")
    }
    func testSurplusIsAdjustmentAndMultiAccountNetDifference() throws {
        var l = fixture(); l.accounts.append(Account(name: "Cash", kind: .cash, balance: 10_000, at: Round45Fixture.date("2026-11-17")))
        let bank = l.accounts[0].id, cash = l.accounts[1].id
        XCTAssertEqual(Reconciliation.preview(l, actual: [bank: 920_400, cash: 10_300], now: now).missing, 700)
        let ids = try Reconciliation.apply(&l, actual: [bank: 920_400, cash: 10_300], now: now)
        XCTAssertEqual(ids.count, 2)
        let surplus = try XCTUnwrap(l.entries.first { $0.accountID == cash })
        XCTAssertEqual(surplus.nature, .adjustmentIn); XCTAssertEqual(surplus.amount, 300)
        XCTAssertEqual(Finance.balance(l.accounts[0], in: l, at: now), 920_400)
        XCTAssertEqual(Finance.balance(l.accounts[1], in: l, at: now), 10_300)
    }
    func testEqualBalancesOnlyUpdateAnchorsAndRejectInvalidAccountsAtomically() throws {
        var l = fixture(); let count = l.entries.count, id = l.accounts[0].id
        XCTAssertTrue(try Reconciliation.apply(&l, actual: [id: 921_400], now: now).isEmpty)
        XCTAssertEqual(l.entries.count, count); XCTAssertEqual(l.accounts[0].anchorDate, now); XCTAssertTrue(l.accounts[0].reconciled)
        XCTAssertNil(Reconciliation.gap(in: l, now: now)); XCTAssertNil(Reconciliation.gap(in: Ledger(), now: now))
        let before = l; XCTAssertThrowsError(try Reconciliation.apply(&l, actual: [UUID(): 1], now: now)); XCTAssertEqual(l, before)
        XCTAssertThrowsError(try Reconciliation.apply(&l, actual: [id: Money.limit + 1], now: now))
    }
    func testThresholdRowsAndNoGapUsesToday() throws {
        var l = fixture(); XCTAssertNil(Reconciliation.gap(in: l, now: Dates.addDays(-1, to: now)))
        XCTAssertNotNil(Reconciliation.gap(in: l, now: Dates.addDays(-1, to: now), minimumDays: 2))
        l.accounts.append(Account(name: "Credit", kind: .credit, balance: -1000, at: now))
        var archived = Account(name: "Archived", balance: 1, at: now); archived.archived = true; l.accounts.append(archived)
        XCTAssertEqual(Reconciliation.rows(in: l, now: now).map(\.id), [l.accounts[0].id])
        l.entries = []
        let actual: [UUID: Int64] = [l.accounts[0].id: 921_000]
        XCTAssertEqual(Reconciliation.preview(l, actual: actual, now: now).from, Dates.day(now))
        try Reconciliation.apply(&l, actual: actual, now: now)
        XCTAssertEqual(l.entries.last?.spreadFrom, Dates.day(now))
    }
}

extension Round45ReconcileTests {
    func testReconciliationLaterOnSameRecordingDaySuppressesThatGap() throws {
        var l = fixture()
        l.accounts[0].anchorDate = Round45Fixture.date("2026-11-17 13:00")
        XCTAssertNil(Reconciliation.gap(in: l, now: now))
        l = fixture()
        try Reconciliation.apply(&l, actual: [l.accounts[0].id: 880_200], now: now)
        XCTAssertNil(Reconciliation.gap(in: l, now: Dates.addDays(4, to: now)))
    }
}
