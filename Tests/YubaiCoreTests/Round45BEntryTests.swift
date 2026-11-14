import XCTest
@testable import YubaiCore

final class Round45BEntryTests: XCTestCase {
    let now = Round45BFixture.now
    func d(_ text: String) -> Date { Round45BFixture.d(text) }
    func testFutureEntryLeavesAllCurrentNumbersUnchangedAndPostsAtCycleEdge() throws {
        var ledger = Round45BFixture.ledger()
        let before = Finance.funds(ledger, now: now), pace = Finance.pace(ledger, now: now)
        let change = try ManualBookkeeping.change(amount: 1200, nature: .expense, accountID: ledger.accounts[0].id,
            day: d("2026-12-01"), purpose: "午饭", category: "餐饮", now: now)
        XCTAssertEqual(try ManualBookkeeping.available(after: change, in: ledger, now: now), before.available)
        try change.apply(to: &ledger)
        XCTAssertEqual(Finance.funds(ledger, now: now), before)
        XCTAssertEqual(Finance.pace(ledger, now: now), pace)
        XCTAssertEqual(Finance.upcomingEntries(in: ledger, now: now, days: 20).count, 1)
        XCTAssertEqual(Finance.upcomingEntries(in: ledger, now: now, days: -1), [])
        let justBefore = d("2026-12-01").addingTimeInterval(-0.001), arrives = d("2026-12-01")
        XCTAssertEqual(Finance.balance(ledger.accounts[0], in: ledger, at: justBefore), 1_000_000)
        XCTAssertEqual(Finance.balance(ledger.accounts[0], in: ledger, at: arrives), 998_800)
        XCTAssertEqual(Finance.pace(ledger, now: arrives)?.spent, 1200)
        XCTAssertTrue(Finance.upcomingEntries(in: ledger, now: arrives).isEmpty)
    }
    func testFutureReserveAndEarmarkedIncomeDoNotChangePocketOrOverview() throws {
        var ledger = Round45BFixture.ledger()
        let before = Reserve.overview(ledger, now: now)
        for (nature, reserve, saved) in [(Nature.expense, true, false), (.income, false, true)] {
            let change = try ManualBookkeeping.change(amount: 12_000, nature: nature, accountID: ledger.accounts[0].id,
                day: d("2026-11-22"), purpose: "大衣", category: nature == .income ? "工资奖金" : "衣着",
                now: now, intoFixedSavings: saved, fromReserve: reserve)
            try change.apply(to: &ledger)
        }
        XCTAssertEqual(Reserve.overview(ledger, now: now), before)
        XCTAssertTrue(Reserve.paybackOffers(ledger, now: now).isEmpty)
        XCTAssertEqual(Reserve.paybackOffers(ledger, now: d("2026-11-22")).count, 1)
        XCTAssertEqual(Reserve.overview(ledger, now: d("2026-11-22")).total, before.total)
    }
    func testFutureLinkedBillDoesNotMarkPaidOrChangeBudgetUntilDate() throws {
        var ledger = Round45BFixture.ledger()
        var bill = Plan(title: "会员", amount: 2000, dueDate: d("2026-11-25"))
        bill.accountID = ledger.accounts[0].id; bill.autoPay = true; ledger.plans = [bill]
        let before = Finance.funds(ledger, now: now).available
        let change = try ManualBookkeeping.change(amount: 2000, nature: .expense, accountID: ledger.accounts[0].id,
            day: d("2026-11-26"), purpose: "会员", category: "订阅会员", link: (bill.id, bill.dueDate), now: now)
        try change.apply(to: &ledger)
        XCTAssertEqual(Finance.funds(ledger, now: now).available, before)
        XCTAssertEqual(Finance.formula(ledger, now: now).bills.first?.state, .upcoming)
        XCTAssertEqual(Finance.formula(ledger, now: d("2026-11-25")).bills.first?.state, .due)
        XCTAssertNil(FixedFlows.autoSettle(in: ledger, now: d("2026-11-25")))
        XCTAssertEqual(Finance.formula(ledger, now: d("2026-11-26")).bills.first?.state, .paid)
        XCTAssertEqual(Finance.funds(ledger, now: d("2026-11-26")).available, before)
    }
    func testFutureSalaryDoesNotCloseCycleOrClearDueEarly() throws {
        var ledger = Round45Fixture.ledger(); ledger.paydayConfirmSince = d("2026-12-10")
        let before = Finance.cycleInfo(in: ledger, now: now), id = ledger.plans[0].id
        let change = try ManualBookkeeping.change(amount: 801_000, nature: .income, accountID: ledger.accounts[0].id,
            day: d("2026-12-12"), purpose: "工资", category: "工资奖金", link: (id, d("2026-12-10")), now: now)
        try change.apply(to: &ledger)
        XCTAssertEqual(Finance.cycleInfo(in: ledger, now: now), before)
        XCTAssertNotNil(Payday.due(in: ledger, now: d("2026-12-11")))
        XCTAssertEqual(Finance.cycleInfo(in: ledger, now: d("2026-12-11")).lateSince, d("2026-12-10"))
        XCTAssertEqual(Finance.cycleInfo(in: ledger, now: d("2026-12-12")).start, d("2026-12-12"))
        XCTAssertNil(Payday.due(in: ledger, now: d("2026-12-12")))
        var early = ledger
        let at = d("2026-12-11"), pendingID = try XCTUnwrap(early.entries.last?.id)
        let due = try XCTUnwrap(Payday.due(in: early, now: at))
        try Payday.confirm(due, amount: due.usual, extraToSavings: false, accountID: nil, in: &early, now: at)
        XCTAssertEqual(early.entries.count, ledger.entries.count)
        XCTAssertEqual(early.entries.last?.id, pendingID)
        XCTAssertEqual(Finance.cycleInfo(in: early, now: at).start, at)
    }
    func testFutureZeroNegativeAndInvalidDateAreRejected() {
        let ledger = Round45BFixture.ledger()
        for amount in [0, -1, Money.limit + 1] {
            XCTAssertThrowsError(try ManualBookkeeping.change(amount: amount, nature: .expense, accountID: ledger.accounts[0].id,
                day: d("2026-12-01"), purpose: "午饭", category: "餐饮", now: now))
        }
        XCTAssertThrowsError(try ManualBookkeeping.change(amount: 1, nature: .expense, accountID: ledger.accounts[0].id,
            day: .distantFuture, purpose: "午饭", category: "餐饮", now: now))
    }
    func testReceiptSeparateAndMergedSelectionUsesShopAndExactCents() throws {
        let ledger = Round45BFixture.ledger()
        let lines = ReceiptTextParser.drafts(lines: ["2026-11-19", "苹果 ¥12.34", "纸巾 ¥5.67"], now: now)
        XCTAssertEqual(lines.count, 2)
        let separate = try ReceiptTextParser.entryDrafts(from: lines, shopName: "超市", mode: .separate, in: ledger, accountID: ledger.accounts[0].id)
        XCTAssertEqual(separate.map(\.amount), [1234, 567]); XCTAssertTrue(separate.allSatisfy(\.amountConfirmed))
        let merged = try ReceiptTextParser.entryDrafts(from: lines, shopName: " 超市 ", mode: .merged, in: ledger, accountID: ledger.accounts[0].id)
        XCTAssertEqual(merged.count, 1); XCTAssertEqual(merged.first?.title, "超市"); XCTAssertEqual(merged.first?.amount, 1801)
        XCTAssertTrue(try ReceiptTextParser.entryDrafts(from: [], shopName: "", mode: .merged, in: ledger, accountID: ledger.accounts[0].id).isEmpty)
        XCTAssertEqual(try ReceiptTextParser.entryDrafts(from: [lines[0]], shopName: "超市", mode: .merged, in: ledger, accountID: ledger.accounts[0].id).first?.amount, 1234)
    }
    func testReceiptInvalidAmountsMixedDirectionsAndOverflow() {
        let ledger = Round45BFixture.ledger(), account = ledger.accounts[0].id
        func line(_ amount: Int64, _ nature: Nature = .expense) -> ReceiptTextParser.Draft {
            .init(date: now, amount: amount, title: "苹果", nature: nature, dateNeedsReview: false, directionNeedsReview: false)
        }
        for lines in [[line(0)], [line(-1)], [line(Money.limit), line(1)], [line(1), line(1, .income)]] {
            XCTAssertThrowsError(try ReceiptTextParser.entryDrafts(from: lines, shopName: "超市", mode: .merged, in: ledger, accountID: account))
        }
    }
    func reconciled() throws -> (Ledger, UUID) {
        var ledger = Round45BFixture.ledger()
        ledger.entries = [Round45BFixture.entry(ledger, date: "2026-11-17", amount: 1000)]
        let book = Finance.balance(ledger.accounts[0], in: ledger, at: now)
        let ids = try Reconciliation.apply(&ledger, actual: [ledger.accounts[0].id: book - 41_200], now: now)
        return (ledger, ids[0])
    }
    func testPartialSplitRetainsSpreadAndBalanceAndUndo() throws {
        var (ledger, id) = try reconciled()
        let before = ledger, balance = Finance.balance(ledger.accounts[0], in: ledger, at: now)
        let draft = EntryDraft(date: d("2026-11-18 12:00"), amount: 10_000, amountConfirmed: true, accountID: ledger.accounts[0].id, title: "聚餐", category: "餐饮")
        let split = try Reconciliation.split(entryID: id, into: [draft], in: &ledger, now: now)
        XCTAssertEqual(split.remainder.amount, 31_200); XCTAssertEqual(split.remainder.spreadFrom, d("2026-11-18"))
        XCTAssertNil(split.entries[0].spreadFrom)
        XCTAssertEqual(Finance.balance(ledger.accounts[0], in: ledger, at: now), balance)
        XCTAssertEqual(Finance.funds(ledger, now: now).available, Finance.funds(before, now: now).available)
        try Reconciliation.undoSplit(split, in: &ledger, now: now)
        XCTAssertEqual(ledger, before)
    }
    func testFullSplitAndInvalidSumsAreAtomic() throws {
        var (ledger, id) = try reconciled(); let before = ledger
        func draft(_ amount: Int64) -> EntryDraft {
            EntryDraft(date: d("2026-11-18 12:00"), amount: amount, amountConfirmed: true, accountID: ledger.accounts[0].id, title: "聚餐", category: "餐饮")
        }
        for rows in [[], [draft(0)], [draft(-1)], [draft(41_201)], [draft(30_000), draft(30_000)]] {
            XCTAssertThrowsError(try Reconciliation.split(entryID: id, into: rows, in: &ledger, now: now))
            XCTAssertEqual(ledger, before)
        }
        let split = try Reconciliation.split(entryID: id, into: [draft(20_000), draft(21_200)], in: &ledger, now: now)
        XCTAssertNotNil(split.remainder.deletedAt)
        XCTAssertFalse(ledger.activeEntries.contains { $0.id == id })
        try Reconciliation.undoSplit(split, in: &ledger, now: now); XCTAssertEqual(ledger, before)
    }
    func testSplitUndoDoesNotOverwriteLaterEdits() throws {
        var (ledger, id) = try reconciled()
        let draft = EntryDraft(date: d("2026-11-18 12:00"), amount: 1000, amountConfirmed: true, accountID: ledger.accounts[0].id, title: "午饭", category: "餐饮")
        let split = try Reconciliation.split(entryID: id, into: [draft], in: &ledger, now: now)
        ledger.entries[ledger.entries.firstIndex { $0.id == draft.id }!].amount = 900
        let edited = ledger
        XCTAssertThrowsError(try Reconciliation.undoSplit(split, in: &ledger, now: now)); XCTAssertEqual(ledger, edited)
    }
}
