import XCTest
@testable import YubaiCore

final class FinanceTests: XCTestCase {
    let now = Dates.parse("2026-10-01 12:00:00")!
    func basic() -> Ledger { var l = Ledger(); l.accounts = [Account(name: "银行", balance: 1_000_000, at: Dates.parse("2026-10-01 00:00:00")!), Account(name: "零钱", kind: .cash, balance: 0, at: Dates.parse("2026-10-01 00:00:00")!), Account(name: "信用卡", kind: .credit, balance: -200_000, at: Dates.parse("2026-10-01 00:00:00")!)]; return l }
    func testFloorTargetDoesNotChangeAvailableOrForecastAndRoomUsesHorizonRemainder() {
        var ledger = basic()
        ledger.plans = [Plan(title: "付款", amount: 70_000, dueDate: Dates.addDays(5, to: now)), Plan(title: "进账", amount: 20_000, dueDate: Dates.addDays(10, to: now), inflow: true)]
        ledger.goals = [Goal(title: "旅行", target: 100_000, reserved: 30_000)]
        ledger.entries = [Entry(date: now, amount: 5000, nature: .unknownIn, accountID: ledger.accounts[0].id, title: "进账")]
        let before = Finance.funds(ledger, now: now)
        XCTAssertEqual(before.available, 700_000); XCTAssertNil(before.floorRoom)
        XCTAssertEqual(before.points.first?.conservative, 770_000); XCTAssertEqual(before.points.last?.conservative, 700_000)
        XCTAssertEqual(before.points.last?.expected, 720_000)
        for floor: Int64? in [nil, 0, 100_000, 700_000, 800_000] {
            ledger.profile.floorAmount = floor
            let funds = Finance.funds(ledger, now: now)
            XCTAssertEqual(funds.available, before.available); XCTAssertEqual(funds.emergency, 0)
            XCTAssertNil(funds.floorRoom)
            XCTAssertEqual(funds.points.map(\.date), before.points.map(\.date))
            XCTAssertEqual(funds.points.map(\.conservative), before.points.map(\.conservative))
            XCTAssertEqual(funds.points.map(\.expected), before.points.map(\.expected))
        }
    }
    func testPurchaseFactsIncludeFixedSavingsAndSavingTarget() {
        var ledger = basic(); ledger.goals = [Goal(title: "旅行", target: 100_000, reserved: 30_000)]
        ledger.fixedSavings = 100_000; ledger.savingRule = .fixed(20_000)
        let facts = Finance.assessPurchase(ledger, amount: 1000, now: now).facts
        XCTAssertTrue(facts.contains("在存钱 \(Money.text(30_000))"))
        XCTAssertTrue(facts.contains("存下的钱 \(Money.text(100_000))"))
        XCTAssertTrue(facts.contains("要攒 \(Money.text(20_000))"))
    }
    private func record(_ ledger: inout Ledger, date: Date, at recordedAt: Date, nature: Nature = .expense) throws {
        let draft = EntryDraft(date: date, amount: 3200, amountConfirmed: true, nature: nature, accountID: ledger.accounts[0].id, title: "补记")
        var change = ChangeSet(source: "问余白", reason: "用户补记", items: [.addEntry(draft)]); change.createdAt = recordedAt
        XCTAssertTrue(try change.apply(to: &ledger).isEmpty)
    }
    func testSameDayChangeSetEntriesChangeBalanceCashAndAvailableByExactAmount() throws {
        for nature in [Nature.expense, .refund, .income] {
            var ledger = Ledger(); ledger.accounts = [Account(name: "银行", balance: 100_000, at: Dates.parse("2026-10-01 08:30")!)]
            let before = Finance.funds(ledger, now: now)
            try record(&ledger, date: Dates.day(now), at: now, nature: nature)
            let delta: Int64 = nature.inflow ? 3200 : -3200
            let after = Finance.funds(ledger, now: now)
            XCTAssertEqual(ledger.entries[0].recordedAt, now); XCTAssertEqual(ledger.entries[0].date, Dates.day(now))
            XCTAssertEqual(Finance.balance(ledger.accounts[0], in: ledger, at: now), 100_000 + delta)
            XCTAssertEqual(after.cash, before.cash + delta); XCTAssertEqual(after.available, before.available + delta)
            XCTAssertEqual(after.living, before.living)
        }
    }
    func testBackdatedChangeSetEntryBeforeAnchorDayDoesNotChangeBalance() throws {
        var ledger = Ledger(); ledger.accounts = [Account(name: "银行", balance: 100_000, at: Dates.parse("2026-10-01 08:30")!)]
        try record(&ledger, date: Dates.addDays(-1, to: Dates.day(now)), at: now)
        XCTAssertEqual(Finance.balance(ledger.accounts[0], in: ledger, at: now), 100_000)
        XCTAssertEqual(Finance.funds(ledger, now: now).cash, 100_000)
    }
    func testSameDayReconciliationExcludesEarlierRecordingsAndIncludesLaterOnes() throws {
        var ledger = Ledger(); ledger.accounts = [Account(name: "银行", balance: 100_000, at: Dates.parse("2026-10-01 08:30")!)]
        try record(&ledger, date: Dates.day(now), at: now)
        XCTAssertEqual(Finance.balance(ledger.accounts[0], in: ledger, at: now), 96_800)
        let reconcile = Dates.parse("2026-10-01 20:00")!
        ledger.accounts[0].anchorBalance = 96_800; ledger.accounts[0].anchorDate = reconcile
        // Recording at exactly the anchor is already included, like recording before it.
        try record(&ledger, date: Dates.day(now), at: reconcile)
        XCTAssertEqual(Finance.balance(ledger.accounts[0], in: ledger, at: reconcile), 96_800)
        try record(&ledger, date: Dates.day(now), at: Dates.parse("2026-10-01 21:00")!)
        let close = Dates.parse("2026-10-01 22:00")!; let funds = Finance.funds(ledger, now: close)
        XCTAssertEqual(Finance.balance(ledger.accounts[0], in: ledger, at: close), 93_600)
        XCTAssertEqual(funds.cash, 93_600); XCTAssertEqual(funds.available, 93_600)
    }
    func testImportedEntriesUseExactPostingTimeOnAnchorDay() {
        var ledger = Ledger(); ledger.accounts = [Account(name: "银行", balance: 100_000, at: Dates.parse("2026-10-01 08:30")!)]
        for time in ["07:00", "08:30", "09:00"] {
            var entry = Entry(date: Dates.parse("2026-10-01 " + time)!, amount: 3200, accountID: ledger.accounts[0].id, title: "导入午饭")
            entry.source = "微信"; XCTAssertNil(entry.recordedAt); ledger.entries.append(entry)
        }
        XCTAssertEqual(Finance.balance(ledger.accounts[0], in: ledger, at: now), 96_800)
        let funds = Finance.funds(ledger, now: now)
        XCTAssertEqual(funds.cash, 96_800); XCTAssertEqual(funds.available, 96_800)
    }
    func testManualTransferUsesEachAccountsAnchorAndKeepsPostingUpperBound() {
        var ledger = Ledger()
        ledger.accounts = [Account(name: "银行", balance: 100_000, at: Dates.parse("2026-10-01 08:30")!), Account(name: "零钱", kind: .cash, at: Dates.parse("2026-10-01 13:00")!)]
        var entry = Entry(date: Dates.day(now), amount: 3200, nature: .transfer, accountID: ledger.accounts[0].id, title: "转零钱")
        entry.recordedAt = now; entry.otherAccountID = ledger.accounts[1].id; ledger.entries = [entry]
        let at = Dates.parse("2026-10-01 14:00")!
        XCTAssertEqual(Finance.balance(ledger.accounts[0], in: ledger, at: at), 96_800)
        XCTAssertEqual(Finance.balance(ledger.accounts[1], in: ledger, at: at), 0)
        XCTAssertEqual(Finance.funds(ledger, now: at).cash, 96_800)
        ledger.accounts[1].anchorDate = ledger.accounts[0].anchorDate
        XCTAssertEqual(Finance.balance(ledger.accounts[1], in: ledger, at: at), 3200)
        XCTAssertEqual(Finance.funds(ledger, now: at).cash, 100_000)
        let tomorrow = Dates.addDays(1, to: Dates.day(now)); ledger.entries[0].otherDate = tomorrow
        XCTAssertEqual(Finance.balance(ledger.accounts[1], in: ledger, at: at), 0)
        XCTAssertEqual(Finance.funds(ledger, now: at).cash, 96_800)
        XCTAssertEqual(Finance.funds(ledger, now: tomorrow).cash, 100_000)
        ledger.entries[0].date = tomorrow
        XCTAssertEqual(Finance.balance(ledger.accounts[0], in: ledger, at: at), 100_000)
        XCTAssertEqual(Finance.funds(ledger, now: at).cash, 100_000)
    }
    func testSameDayUnknownInflowIsWithheldUsingTheSameAnchorRuleAsCash() throws {
        var ledger = Ledger(); ledger.accounts = [Account(name: "银行", balance: 100_000, at: Dates.parse("2026-10-01 08:30")!)]
        try record(&ledger, date: Dates.day(now), at: now, nature: .unknownIn)
        let funds = Finance.funds(ledger, now: now)
        XCTAssertEqual(funds.cash, 103_200); XCTAssertEqual(funds.uncertainInflow, 3200); XCTAssertEqual(funds.available, 100_000)
        let reconcile = Dates.parse("2026-10-01 20:00")!
        ledger.accounts[0].anchorBalance = funds.cash; ledger.accounts[0].anchorDate = reconcile
        XCTAssertEqual(Finance.funds(ledger, now: reconcile).uncertainInflow, 0)
        try record(&ledger, date: Dates.day(now), at: Dates.parse("2026-10-01 21:00")!, nature: .unknownIn)
        let after = Finance.funds(ledger, now: Dates.parse("2026-10-01 22:00")!)
        XCTAssertEqual(after.cash, 106_400); XCTAssertEqual(after.uncertainInflow, 3200); XCTAssertEqual(after.available, 103_200)
    }
    func testRecordedAtRoundTripsAndOldLedgersDecodeWithoutIt() throws {
        var ledger = basic(); try record(&ledger, date: Dates.day(now), at: now)
        let data = try LedgerCodec.encode(ledger)
        XCTAssertEqual(try LedgerCodec.decode(data).entries, ledger.entries)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var entries = try XCTUnwrap(json["entries"] as? [[String: Any]])
        entries[0].removeValue(forKey: "recordedAt"); json["entries"] = entries
        var expected = ledger.entries[0]; expected.recordedAt = nil
        for schema in [1, 2] {
            json["schema"] = schema
            let decoded = try LedgerCodec.decode(JSONSerialization.data(withJSONObject: json))
            XCTAssertEqual(decoded.schema, 4); XCTAssertEqual(decoded.entries, [expected]); XCTAssertNil(decoded.entries[0].recordedAt)
        }
        ledger.entries[0].recordedAt = Date(timeIntervalSince1970: 7_258_118_401)
        XCTAssertThrowsError(try ledger.validate())
    }
    func testMoneyUsesIntegerCents() throws {
        XCTAssertEqual(try Money.parse("￥1,234.56"), 123456)
        XCTAssertEqual(try Money.parse("0.01"), 1)
        XCTAssertEqual(try Money.parse("-1.50", allowNegative: true), -150)
        XCTAssertEqual(try Money.parse("+100.70", allowNegative: true), 10070)
        for bad in ["1.001", "NaN", "1e6", "12,34.00", "", "-4"] { XCTAssertThrowsError(try Money.parse(bad), bad) }
    }
    func testMoneyEditableTextPreservesCentsWithTwoDecimals() throws {
        let cases: [(Int64, String)] = [
            (123_456, "1234.56"), (5, "0.05"), (-5, "-0.05"), (-123_456, "-1234.56"),
            (1_298_600, "12986.00"), (116_800, "1168.00"), (0, "0.00"),
            (Money.limit, "99999999999.99"), (-Money.limit, "-99999999999.99")
        ]
        for (cents, expected) in cases {
            let text = Money.editableText(cents)
            XCTAssertEqual(text, expected)
            XCTAssertEqual(try Money.parse(text, allowNegative: true), cents)
        }
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
        let f = Finance.funds(l, now: now); XCTAssertEqual(f.uncertainInflow, 80000); XCTAssertEqual(f.available, 800000); XCTAssertTrue(f.warnings.contains { $0.contains("没写用途") })
    }
    func testMonthlyRentContributionAndQuarterlyPayment() {
        var l = basic(); let r = Rent(monthlyTotal: 40000, personalShare: 20000, startDate: Dates.day(now), nextDueDate: Dates.addDays(20, to: now)); l.rents = [r]
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
    func testLinkedRefundFollowsRecategorizedExpense() {
        var l = basic(); let expense = Entry(date: now, amount: 161950, accountID: l.accounts[0].id, title: "聚餐", category: "餐饮")
        var refund = Entry(date: now, amount: 2550, nature: .refund, accountID: l.accounts[0].id, title: "部分退款", category: "餐饮"); refund.relatedEntryID = expense.id
        l.entries = [expense, Entry(date: now, amount: 3200, accountID: l.accounts[0].id, title: "午餐", category: "餐饮"), Entry(date: now, amount: 100000, accountID: l.accounts[0].id, title: "购物", category: "日用购物"), refund]
        let before = Finance.review(l, from: Dates.day(now), through: Dates.addDays(1, to: now)); XCTAssertEqual(before.spending, 262600)
        l.entries[0].category = "人情家庭"
        LedgerOperations.syncLinkedRefundCategories(in: &l)
        let r = Finance.review(l, from: Dates.day(now), through: Dates.addDays(1, to: now))
        XCTAssertEqual(r.byCategory.first { $0.category == "人情家庭" }?.amount, 159400); XCTAssertEqual(r.byCategory.first { $0.category == "餐饮" }?.amount, 3200)
        XCTAssertEqual(r.spending, before.spending); XCTAssertEqual(r.refunds, 2550); XCTAssertEqual(r.income, 0); XCTAssertEqual(l.entries[3].category, "人情家庭")
    }
    func testLinkedRefundFollowsBulkRecategorizedExpense() throws {
        var l = basic(); let expense = Entry(date: now, amount: 161950, accountID: l.accounts[0].id, title: "聚餐", category: "餐饮")
        var refund = Entry(date: now, amount: 2550, nature: .refund, accountID: l.accounts[0].id, title: "部分退款", category: "餐饮"); refund.relatedEntryID = expense.id
        l.entries = [expense, Entry(date: now, amount: 3200, accountID: l.accounts[0].id, title: "午餐", category: "餐饮"), Entry(date: now, amount: 100000, accountID: l.accounts[0].id, title: "购物", category: "日用购物"), refund]
        let before = Finance.review(l, from: Dates.day(now), through: Dates.addDays(1, to: now)); XCTAssertEqual(before.spending, 262600)
        try LedgerOperations.bulkEdit([expense.id], category: "人情家庭", nature: nil, in: &l)
        let r = Finance.review(l, from: Dates.day(now), through: Dates.addDays(1, to: now))
        XCTAssertEqual(r.byCategory.first { $0.category == "人情家庭" }?.amount, 159400); XCTAssertEqual(r.byCategory.first { $0.category == "餐饮" }?.amount, 3200)
        XCTAssertEqual(r.spending, before.spending); XCTAssertEqual(r.refunds, 2550); XCTAssertEqual(r.income, 0); XCTAssertEqual(l.entries[3].category, "人情家庭")
    }
    func testUnlinkedRefundKeepsOwnSpendingCategory() {
        var l = basic(); l.entries = [Entry(date: now, amount: 161950, accountID: l.accounts[0].id, title: "聚餐", category: "人情家庭"), Entry(date: now, amount: 3200, accountID: l.accounts[0].id, title: "午餐", category: "餐饮"), Entry(date: now, amount: 2550, nature: .refund, accountID: l.accounts[0].id, title: "未关联退款", category: "餐饮")]
        LedgerOperations.syncLinkedRefundCategories(in: &l); XCTAssertEqual(l.entries[2].category, "餐饮")
        let r = Finance.review(l, from: Dates.day(now), through: Dates.addDays(1, to: now))
        XCTAssertEqual(r.byCategory.first { $0.category == "人情家庭" }?.amount, 161950); XCTAssertEqual(r.byCategory.first { $0.category == "餐饮" }?.amount, 650)
        XCTAssertEqual(r.spending, 162600); XCTAssertEqual(r.refunds, 2550); XCTAssertEqual(r.income, 0)
    }
    func testLinkedRefundUsesExpenseCategoryOutsideReviewPeriod() {
        var l = basic(); let expense = Entry(date: Dates.addDays(-40, to: now), amount: 161950, accountID: l.accounts[0].id, title: "旧支出", category: "人情家庭")
        var refund = Entry(date: now, amount: 2550, nature: .refund, accountID: l.accounts[0].id, title: "部分退款", category: "餐饮"); refund.relatedEntryID = expense.id; l.entries = [expense, refund]
        let r = Finance.review(l, from: Dates.day(now), through: Dates.addDays(1, to: now))
        XCTAssertEqual(r.byCategory.count, 1); XCTAssertEqual(r.byCategory.first?.category, "人情家庭"); XCTAssertEqual(r.byCategory.first?.amount, -2550); XCTAssertEqual(r.spending, -2550)
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
