import XCTest
@testable import YubaiCore

final class Round45BReserveTests: XCTestCase {
    let now = Round45BFixture.now
    func d(_ text: String) -> Date { Round45BFixture.d(text) }
    func withdrawn(_ amount: Int64 = 120_000) -> Ledger {
        var ledger = Round45BFixture.ledger()
        var entry = Round45BFixture.entry(ledger, date: "2026-11-19", amount: amount, title: "大衣", category: "衣着")
        entry.fromReserve = true; ledger.entries = [entry]; return ledger
    }
    func testAcceptRaisesTargetAndDeclineIsAskedOnce() throws {
        for cycles in [nil, 3] as [Int?] {
            var ledger = withdrawn()
            let offer = try XCTUnwrap(Reserve.paybackOffers(ledger, now: now).first)
            XCTAssertEqual(offer.amount, 120_000); XCTAssertEqual(offer.title, "大衣")
            try Reserve.answerPayback(offer.withdrawal, cycles: cycles, in: &ledger, now: now)
            XCTAssertTrue(Reserve.paybackOffers(ledger, now: now).isEmpty)
            XCTAssertEqual(Finance.funds(ledger, now: now).savingTarget, cycles == nil ? 100_000 : 140_000)
            XCTAssertThrowsError(try Reserve.answerPayback(offer.withdrawal, cycles: 3, in: &ledger, now: now))
            XCTAssertEqual(try JSONDecoder().decode(Ledger.self, from: JSONEncoder().encode(ledger)), ledger)
        }
    }
    func testPaybackFinishesAfterThreeActualClosedCyclesAndLinesDoNotDoubleCount() throws {
        var ledger = withdrawn()
        try Reserve.answerPayback(.purchase(ledger.entries[0].id), cycles: 3, in: &ledger, now: now)
        for date in ["2026-12-01 12:00", "2027-01-01 12:00", "2027-02-01 12:00"] {
            Savings.closeCycles(&ledger, now: d(date))
            let once = ledger; Savings.closeCycles(&ledger, now: d(date)); XCTAssertEqual(ledger, once)
        }
        let progress = try XCTUnwrap(Reserve.paybackProgress(ledger, now: d("2027-02-02")).first)
        XCTAssertEqual(progress.paid, 120_000); XCTAssertEqual(progress.remaining, 0); XCTAssertTrue(progress.completed)
        XCTAssertEqual(Finance.funds(ledger, now: d("2027-02-02")).savingTarget, 100_000)
        XCTAssertEqual(ledger.reservePaybacks?.first?.payments?.count, 3)
        let overview = Reserve.overview(ledger, now: d("2027-02-02"))
        XCTAssertEqual(overview.lines.filter { $0.paybackID != nil }.reduce(0) { $0 + $1.amount }, 120_000)
        XCTAssertEqual(overview.lines.filter { $0.amount > 0 }.reduce(0) { $0 + $1.amount }, 520_000)
    }
    func testPaybackRemainderCentsAndNoSavingRule() throws {
        var ledger = withdrawn(100); ledger.savingRule = nil
        try Reserve.answerPayback(.purchase(ledger.entries[0].id), cycles: 3, in: &ledger, now: now)
        XCTAssertEqual(Finance.funds(ledger, now: now).savingTarget, 34)
        Savings.closeCycles(&ledger, now: d("2026-12-01")); Savings.closeCycles(&ledger, now: d("2027-01-01"))
        XCTAssertEqual(Finance.funds(ledger, now: d("2027-01-02")).savingTarget, 32)
        Savings.closeCycles(&ledger, now: d("2027-02-01"))
        XCTAssertEqual(Reserve.paybackProgress(ledger, now: d("2027-02-02")).first?.remaining, 0)
    }
    func testCoverOfferAndInvalidCountAreAtomic() throws {
        var ledger = Round45BFixture.ledger()
        try Overspend.cover(&ledger, source: .fromReserve, amount: 60_000, now: now)
        let before = ledger, offer = try XCTUnwrap(Reserve.paybackOffers(ledger, now: now).first)
        XCTAssertEqual(offer.withdrawal, .cover(ledger.cycleCovers[0].id))
        for count in [0, -3, 121] {
            XCTAssertThrowsError(try Reserve.answerPayback(offer.withdrawal, cycles: count, in: &ledger, now: now))
            XCTAssertEqual(ledger, before)
        }
        try Reserve.answerPayback(offer.withdrawal, cycles: 2, in: &ledger, now: now)
        XCTAssertEqual(Finance.funds(ledger, now: now).savingTarget, 130_000)
    }
    func testRefundAndDeletingSourceReducePaybackWithoutAskingAgain() throws {
        var ledger = withdrawn()
        let source = ledger.entries[0]
        try Reserve.answerPayback(.purchase(source.id), cycles: 3, in: &ledger, now: now)
        var refund = Round45BFixture.entry(ledger, date: "2026-11-20 10:00", amount: 110_000, nature: .refund)
        refund.relatedEntryID = source.id; ledger.entries.append(refund)
        XCTAssertEqual(Finance.funds(ledger, now: now).savingTarget, 110_000)
        ledger.entries.removeLast(); ledger.entries[0].deletedAt = now
        XCTAssertEqual(Finance.funds(ledger, now: now).savingTarget, 100_000)
        XCTAssertTrue(Reserve.paybackOffers(ledger, now: now).isEmpty)
        ledger.entries[0].deletedAt = nil
        XCTAssertTrue(Reserve.paybackOffers(ledger, now: now).isEmpty)
    }
    func testUnderfundingExtendsPaybackInsteadOfClaimingCompletion() throws {
        var ledger = withdrawn(12_000); ledger.fixedSavings = 0; ledger.savingRule = nil
        ledger.accounts[0].anchorBalance = 0
        try Reserve.answerPayback(.purchase(ledger.entries[0].id), cycles: 3, in: &ledger, now: now)
        // Reserve withdrawal cancels the balance decrease, leaving no cash for saving.
        Savings.closeCycles(&ledger, now: d("2026-12-01"))
        XCTAssertNil(ledger.reservePaybacks?.first?.payments)
        XCTAssertFalse(Reserve.paybackProgress(ledger, now: d("2026-12-02")).first!.completed)
        XCTAssertEqual(Finance.funds(ledger, now: d("2026-12-02")).savingTarget, 4000)
    }
    func testPaybackWaitsThroughLateSalaryAndUsesActualNextCycle() throws {
        var ledger = Round45Fixture.ledger(); ledger.paydayConfirmSince = d("2026-12-10")
        var purchase = Round45BFixture.entry(ledger, date: "2026-11-19", amount: 12_000)
        purchase.fromReserve = true; ledger.entries.append(purchase)
        try Reserve.answerPayback(.purchase(purchase.id), cycles: 3, in: &ledger, now: now)
        Savings.closeCycles(&ledger, now: d("2026-12-12")); XCTAssertTrue(ledger.savingHistory.isEmpty)
        let at = d("2026-12-13 12:00"), due = try XCTUnwrap(Payday.due(in: ledger, now: at))
        try Payday.confirm(due, amount: due.usual, extraToSavings: false, accountID: nil, in: &ledger, now: at)
        Savings.closeCycles(&ledger, now: at)
        XCTAssertEqual(ledger.reservePaybacks?.first?.payments?.first?.cycleStart, d("2026-11-10"))
        XCTAssertEqual(Reserve.paybackProgress(ledger, now: at).first?.thisCycle, 4000)
    }
}
