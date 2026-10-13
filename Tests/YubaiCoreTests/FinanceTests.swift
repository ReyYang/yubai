import XCTest
@testable import YubaiCore

final class FinanceTests: XCTestCase {
    let now = Dates.parse("2026-10-01 12:00:00")!
    func basic() -> Ledger { var l = Ledger(); l.accounts = [Account(name: "银行", balance: 1_000_000, at: Dates.parse("2026-10-01 00:00:00")!), Account(name: "零钱", kind: .cash, balance: 0, at: Dates.parse("2026-10-01 00:00:00")!), Account(name: "信用卡", kind: .credit, balance: -200_000, at: Dates.parse("2026-10-01 00:00:00")!)]; return l }
    func testMoneyUsesIntegerCents() throws {
        XCTAssertEqual(try Money.parse("￥1,234.56"), 123456)
        XCTAssertEqual(try Money.parse("0.01"), 1)
        XCTAssertEqual(try Money.parse("-1.50", allowNegative: true), -150)
        for bad in ["1.001", "NaN", "1e6", "12,34.00", "", "-4"] { XCTAssertThrowsError(try Money.parse(bad), bad) }
    }
    func testHistoricalAndFutureImportsDoNotChangeCurrentAnchor() {
        var l = basic(); let a = l.accounts[0]
        l.entries = [Entry(date: Dates.addDays(-5, to: now), amount: 50000, nature: .income, accountID: a.id, title: "旧工资"), Entry(date: now, amount: 1234, accountID: a.id, title: "午餐"), Entry(date: Dates.addDays(2, to: now), amount: 99999, accountID: a.id, title: "未来")]
        XCTAssertEqual(Finance.balance(a, in: l, at: now), 998766)
    }
    func testTransferPreservesCashAndDoesNotCountAsSpending() throws {
        var l = basic(); var e = Entry(date: now, amount: 12000, nature: .transfer, accountID: l.accounts[0].id, title: "转零钱"); e.otherAccountID = l.accounts[1].id; l.entries = [e]; try l.validate()
        XCTAssertEqual(Finance.balance(l.accounts[0], in: l, at: now), 988000)
        XCTAssertEqual(Finance.balance(l.accounts[1], in: l, at: now), 12000)
        XCTAssertEqual(Finance.funds(l, now: now).cash, 1_000_000)
        XCTAssertEqual(Finance.review(l, from: Dates.day(now), through: Dates.addDays(1, to: now)).spending, 0)
    }
    func testCreditPurchaseThenRepaymentDoesNotDoubleCountExpenseOrReserve() {
        var l = basic(); l.entries.append(Entry(date: now, amount: 5000, accountID: l.accounts[2].id, title: "消费"))
        var e = Entry(date: now, amount: 200_000, nature: .repayment, accountID: l.accounts[0].id, title: "还信用卡"); e.otherAccountID = l.accounts[2].id; l.entries.append(e)
        l.plans = [Plan(title: "信用卡还款", amount: 5000, dueDate: Dates.addDays(5, to: now), nature: .repayment)]
        let f = Finance.funds(l, now: now)
        XCTAssertEqual(f.cash, 800_000); XCTAssertEqual(f.debt, 5000); XCTAssertEqual(f.available, 795000)
        XCTAssertEqual(Finance.review(l, from: Dates.day(now), through: Dates.addDays(1, to: now)).spending, 5000)
    }
    func testBorrowingChangesCashAndDebtButNotNetWorthOrIncome() {
        var l = basic(); var e = Entry(date: now, amount: 10000, nature: .borrow, accountID: l.accounts[0].id, title: "借入"); e.otherAccountID = l.accounts[2].id; l.entries = [e]
        let f = Finance.funds(l, now: now); XCTAssertEqual(f.cash, 1010000); XCTAssertEqual(f.debt, 210000); XCTAssertEqual(f.netWorth, 800000)
        XCTAssertEqual(Finance.review(l, from: Dates.day(now), through: Dates.addDays(1, to: now)).income, 0)
    }
    func testInvestmentAndCreditLimitAreNotSpendableCash() {
        var l = basic(); l.accounts[2].creditLimit = 9_000_000; l.accounts.append(Account(name: "基金", kind: .investment, balance: 3_000_000, at: now)); l.accounts.append(Account(name: "借出", kind: .receivable, balance: 200_000, at: now))
        let f = Finance.funds(l, now: now); XCTAssertEqual(f.available, 800000); XCTAssertEqual(f.netWorth, 4000000)
    }
    func testExpectedIncomeNeverInflatesConservativeAvailable() {
        var l = basic(); l.plans = [Plan(title: "预计工资", amount: 2_000_000, dueDate: Dates.addDays(3, to: now), inflow: true, nature: .income)]
        let f = Finance.funds(l, now: now); XCTAssertEqual(f.available, 800000); XCTAssertEqual(f.expectedIncome, 2000000); XCTAssertEqual(f.points.last!.expected - f.points.last!.conservative, 2000000)
    }
    func testLateAndPartialPlanPaymentsKeepRemainingObligation() {
        var l = basic(); let p = Plan(title: "付款", amount: 50000, dueDate: Dates.addDays(-2, to: now)); l.plans = [p]
        var e = Entry(date: now, amount: 20000, accountID: l.accounts[0].id, title: "部分付"); e.planID = p.id; e.occurrence = p.dueDate; l.entries = [e]
        let occurrences = Finance.occurrences(in: l, now: now); XCTAssertEqual(occurrences.count, 1); XCTAssertEqual(occurrences[0].amount, 30000); XCTAssertTrue(occurrences[0].overdue)
        XCTAssertEqual(Finance.funds(l, now: now).available, 750000)
    }
    func testMonthEndRecurrenceDoesNotDriftIntoMarch28() {
        var l = basic(); l.plans = [Plan(title: "月末", amount: 1000, dueDate: Dates.parse("2026-01-31")!, frequency: .monthly)]
        let dates = Finance.occurrences(in: l, now: Dates.parse("2026-01-01")!, days: 100).map { Dates.text($0.date) }
        XCTAssertEqual(dates, ["2026-01-31", "2026-02-28", "2026-03-31"])
    }
    func testUnknownIncomingAfterAnchorIsWithheldButHistoricalNotSubtractedTwice() {
        var l = basic(); l.entries = [Entry(date: now, amount: 80000, nature: .unknownIn, accountID: l.accounts[0].id, title: "待明确"), Entry(date: Dates.addDays(-20, to: now), amount: 90000, nature: .unknownIn, accountID: l.accounts[0].id, title: "历史")]
        let f = Finance.funds(l, now: now); XCTAssertEqual(f.uncertainInflow, 80000); XCTAssertEqual(f.available, 800000); XCTAssertTrue(f.warnings.contains { $0.contains("历史未知") })
    }
    func testMonthlyRentContributionAndQuarterlyPayment() {
        var l = basic(); let r = Rent(monthlyTotal: 40000, personalShare: 20000, startDate: Dates.day(now), nextDueDate: Dates.addDays(20, to: now)); l.rents = [r]; l.preferences.horizonDays = 30
        var contribution = Entry(date: now, amount: 15000, nature: .contribution, accountID: l.accounts[0].id, title: "部分分摊"); contribution.rentID = r.id; contribution.rentPeriod = Dates.day(now); l.entries.append(contribution)
        let pending = Finance.occurrences(in: l, now: now).filter { $0.rentMonth != nil }; XCTAssertEqual(pending.first!.amount, 5000)
        XCTAssertEqual(Finance.funds(l, now: now).committed, 120000)
        var paid = Entry(date: now, amount: 120000, accountID: l.accounts[0].id, title: "季度租金"); paid.rentID = r.id; paid.rentPeriod = r.nextDueDate; LedgerOperations.recordPersonalShare(&paid, ledger: l); l.entries.append(paid)
        XCTAssertEqual(Finance.funds(l, now: now).committed, 0)
        let review = Finance.review(l, from: Dates.day(now), through: Dates.addDays(1, to: now)); XCTAssertEqual(review.income, 0); XCTAssertEqual(review.spending, 60000)
        l.rents[0].personalShare = 10000
        XCTAssertEqual(Finance.spendingAmount(paid, ledger: l), 60000, "Changing a future agreement must not rewrite historical personal expense")
    }
    func testRefundOffsetsExpenseAndIsNotIncome() {
        var l = basic(); l.entries = [Entry(date: now, amount: 10000, accountID: l.accounts[0].id, title: "购物", category: "日用购物"), Entry(date: now, amount: 3000, nature: .refund, accountID: l.accounts[0].id, title: "部分退款", category: "日用购物")]
        let r = Finance.review(l, from: Dates.day(now), through: Dates.addDays(1, to: now)); XCTAssertEqual(r.spending, 7000); XCTAssertEqual(r.income, 0); XCTAssertEqual(r.refunds, 3000)
    }
    func testTransferMergeRetainsDifferentPostingDatesAndSourceEvidence() throws {
        var l = basic(); let debitDate = now, creditDate = Dates.addDays(1, to: now)
        let out = Entry(date: debitDate, amount: 10000, nature: .unknownOut, accountID: l.accounts[0].id, title: "转出")
        let incoming = Entry(date: creditDate, amount: 10000, nature: .unknownIn, accountID: l.accounts[1].id, title: "转入")
        l.entries = [out, incoming]; let primary = try LedgerOperations.mergeTransfer(out.id, incoming.id, in: &l, now: now)
        XCTAssertEqual(primary, out.id); XCTAssertEqual(l.activeEntries.count, 1); XCTAssertEqual(l.entries.count, 2)
        XCTAssertEqual(Finance.balance(l.accounts[1], in: l, at: now), 0)
        XCTAssertEqual(Finance.balance(l.accounts[1], in: l, at: creditDate), 10000)
        XCTAssertEqual(Finance.balance(l.accounts[0], in: l, at: now), 990000)
        l.entries[1].deletedAt = nil; XCTAssertThrowsError(try l.validate())
    }
    func testInsufficientCashIsNotCalledAffordable() {
        let assessment = Finance.assessPurchase(basic(), amount: 900000, now: now)
        XCTAssertEqual(assessment.severity, 2); XCTAssertEqual(assessment.afterPurchase, -100000)
    }
    func testBulkNatureEditIsAtomicAndKeepsDirectionAndAmount() throws {
        var l = basic(); let out = Entry(date: now, amount: 5000, nature: .unknownOut, accountID: l.accounts[0].id, title: "待补充")
        let incoming = Entry(date: now, amount: 2000, nature: .unknownIn, accountID: l.accounts[0].id, title: "另一笔"); l.entries = [out, incoming]
        let unchanged = l
        XCTAssertThrowsError(try LedgerOperations.bulkEdit([out.id, incoming.id], category: "餐饮", nature: .expense, in: &l)); XCTAssertEqual(l, unchanged)
        try LedgerOperations.bulkEdit([out.id], category: "餐饮", nature: .expense, in: &l)
        XCTAssertEqual(l.entries[0].amount, 5000); XCTAssertEqual(l.entries[0].nature, .expense); XCTAssertEqual(l.entries[1], incoming)
    }
    func testRentEndsWithoutRemovingPastUnpaidPeriods() {
        var l = basic(); var r = Rent(monthlyTotal: 40000, personalShare: 20000, startDate: Dates.parse("2026-09-01")!, nextDueDate: Dates.parse("2026-09-01")!, monthsPerPayment: 1)
        r.endDate = Dates.parse("2026-09-30")!; l.rents = [r]
        let pending = Finance.occurrences(in: l, now: now)
        XCTAssertEqual(pending.count, 2); XCTAssertTrue(pending.allSatisfy(\.overdue)); XCTAssertEqual(pending.filter { !$0.inflow }.first?.amount, 40000)
    }
    func testSharedExpenseRefundUsesPersonalShareAndProtectsOriginal() throws {
        var l = basic(); var expense = Entry(date: now, amount: 10000, accountID: l.accounts[0].id, title: "共同支出"); expense.personalExpense = 5000
        var refund = Entry(date: now, amount: 4000, nature: .refund, accountID: l.accounts[0].id, title: "部分退款"); refund.relatedEntryID = expense.id
        l.entries = [expense]; LedgerOperations.recordPersonalShare(&refund, ledger: l); l.entries.append(refund); try l.validate()
        XCTAssertEqual(Finance.spendingAmount(refund, ledger: l), -2000)
        l.entries[0].deletedAt = now; XCTAssertThrowsError(try l.validate())
        l.entries[0].deletedAt = nil; l.entries[0].amount = 3000; XCTAssertThrowsError(try l.validate())
    }
}
