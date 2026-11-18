import XCTest
@testable import YubaiCore

final class WorldModelFeedbackTests: XCTestCase {
    private func d(_ date: String) -> Date { Dates.parse(date)! }

    private func salaryLedger() -> Ledger {
        var ledger = Ledger()
        let october = d("2026-10-15")
        FirstUse.prepareForEntry(&ledger, now: october)
        let account = ledger.accounts[0].id
        let salary = Plan(title: "工资", amount: 1_450_000, dueDate: october, frequency: .monthly,
                          inflow: true, category: "工资奖金", nature: .income)
        ledger.plans = [salary, Plan(title: "房租", amount: 350_000, dueDate: d("2026-11-25"), frequency: .monthly)]
        ledger.cycleAnchor = .payday
        ledger.paydayConfirmSince = d("2026-11-15")
        var receipt = Entry(date: october, amount: salary.amount, nature: .income, accountID: account,
                            title: "工资", category: salary.category)
        receipt.planID = salary.id; receipt.occurrence = october
        ledger.entries = [receipt, Entry(date: d("2026-11-07"), amount: 1_253_500, accountID: account, title: "上期开销")]
        return ledger
    }

    private func manualSalary(in ledger: Ledger, now: Date, subcategory: String? = nil) throws -> ChangeSet {
        var change = try ManualBookkeeping.change(amount: 1_428_000, nature: .income, accountID: ledger.accounts[0].id,
                                                  day: now, purpose: "", category: "工资奖金", now: now)
        if case .addEntry(var draft) = change.items[0] {
            draft.subcategory = subcategory
            change.items[0] = .addEntry(draft)
        }
        return change
    }

    func testOverdueSalaryPreservesOctoberSurplusAndExcludesNovemberRent() throws {
        let now = d("2026-11-17 12:00")
        for since in ["2026-11-15", "2026-12-15"] {
            var ledger = salaryLedger()
            ledger.paydayConfirmSince = d(since)
            let cycle = Finance.cycleInfo(in: ledger, now: now)
            XCTAssertEqual(cycle.start, d("2026-10-15"), since)
            XCTAssertEqual(cycle.lateSince, d("2026-11-15"), since)
            XCTAssertEqual(cycle.end, d("2026-11-17"), since)
            XCTAssertNil(cycle.nextPayday)
            XCTAssertEqual(Payday.due(in: ledger, now: now)?.occurrence, d("2026-11-15"))
            let breakdown = Finance.spendableBreakdown(ledger, now: now)
            XCTAssertEqual(breakdown.billsRest, 0)
            XCTAssertEqual(breakdown.available, 196_500)
            Savings.closeCycles(&ledger, now: now)
            XCTAssertTrue(ledger.savingHistory.isEmpty)
        }
    }

    func testManualSalaryClosesOctoberAndStartsOnTheActualArrivalDay() throws {
        let nominal = d("2026-11-15")
        for (arrival, threshold) in [
            ("2026-11-13", "2026-11-15"), ("2026-11-15", "2026-11-15"),
            ("2026-11-16", "2026-12-15"), ("2026-11-18", "2026-11-15")
        ] {
            let now = d(arrival + " 12:00")
            var ledger = salaryLedger()
            let plan = ledger.plans[0]
            ledger.paydayConfirmSince = d(threshold)
            let change = try manualSalary(in: ledger, now: now, subcategory: "工资")
            XCTAssertEqual(try ManualBookkeeping.available(after: change, in: ledger, now: now), 1_078_000)
            try change.apply(to: &ledger)
            let entry = try XCTUnwrap(ledger.entries.last)
            XCTAssertEqual(entry.planID, plan.id)
            XCTAssertEqual(entry.occurrence, nominal)
            XCTAssertEqual(entry.amount, 1_428_000)
            XCTAssertTrue(ledger.plans[0].settledOccurrences.contains(nominal))
            let before = Dates.addDays(-1, to: Dates.day(now))
            XCTAssertEqual(Finance.cycleInfo(in: ledger, now: before).end, before)
            XCTAssertEqual(ledger.savingHistory.last?.cycleEnd, before)
            XCTAssertEqual(ledger.savingHistory.last?.leftover, 196_500)
            let breakdown = Finance.spendableBreakdown(ledger, now: now)
            XCTAssertEqual(breakdown.cycleStart, d(arrival))
            XCTAssertEqual(breakdown.cycleEnd, d("2026-12-14"))
            XCTAssertEqual(breakdown.income, 1_428_000)
            XCTAssertEqual(breakdown.billsRest, 350_000)
            XCTAssertEqual(FixedFlows.history(planID: plan.id, in: ledger, now: now).entries.first?.id, entry.id)
            XCTAssertFalse(Finance.occurrences(in: ledger, now: now).contains { $0.planID == plan.id && $0.date == nominal })
            let saved = ledger
            try change.apply(to: &ledger)
            XCTAssertEqual(ledger, saved)
        }
    }

    func testManualSalaryInitializesConfirmationAndCalendarModeStaysIndependent() throws {
        let now = d("2026-11-13 12:00")
        var ledger = salaryLedger()
        ledger.paydayConfirmSince = nil
        try manualSalary(in: ledger, now: now).apply(to: &ledger)
        XCTAssertEqual(ledger.paydayConfirmSince, d("2026-11-15"))
        XCTAssertEqual(Finance.cycleInfo(in: ledger, now: now).start, Dates.day(now))
        ledger = salaryLedger()
        ledger.cycleAnchor = .calendarMonth
        try manualSalary(in: ledger, now: now).apply(to: &ledger)
        XCTAssertNil(ledger.entries.last?.planID)
        XCTAssertEqual(Finance.cycleInfo(in: ledger, now: now).start, d("2026-11-01"))
    }

    func testFutureManualSalaryWaitsForPostingAndExplicitBonusDoesNotLink() throws {
        let now = d("2026-11-12 12:00"), arrival = d("2026-11-13")
        var ledger = salaryLedger()
        try manualSalary(in: ledger, now: now, subcategory: "奖金").apply(to: &ledger)
        XCTAssertNil(ledger.entries.last?.planID)
        let change = try ManualBookkeeping.change(amount: 1_428_000, nature: .income, accountID: ledger.accounts[0].id,
                                                  day: arrival, purpose: "工资", category: "工资奖金", now: now)
        try change.apply(to: &ledger)
        XCTAssertEqual(Finance.cycleInfo(in: ledger, now: now).start, d("2026-10-15"))
        XCTAssertEqual(Finance.spendableBreakdown(ledger, now: arrival).income, 1_428_000)
        XCTAssertEqual(Finance.cycleInfo(in: ledger, now: arrival).start, arrival)
    }

    func testSalaryMatchesByClassificationWithinTheFloatingWindow() throws {
        let now = d("2026-12-04 12:00"), nominal = d("2026-11-15")
        var ledger = salaryLedger()
        let plan = ledger.plans[0], account = ledger.accounts[0].id
        let salary = Entry(date: now, amount: 1_428_000, nature: .income, accountID: account, title: "入账", category: "工资奖金")
        let unclassified = Entry(date: nominal, amount: plan.amount, nature: .income, accountID: account, title: "没分类")
        ledger.entries += [salary, unclassified]
        XCTAssertEqual(FixedFlows.matchingEntries(planID: plan.id, occurrence: nominal, in: ledger, now: now).map(\.id), [salary.id])
        XCTAssertTrue(FixedFlows.autoLink(&ledger, addedEntryIDs: [unclassified.id], now: now).isEmpty)
        XCTAssertEqual(FixedFlows.autoLink(&ledger, addedEntryIDs: [salary.id], now: now).first?.occurrence, nominal)
        XCTAssertEqual(FixedFlows.history(planID: plan.id, in: ledger, now: now).entries.first?.id, salary.id)
    }

    func testChangingTheMonthlyDayReplacesTheCurrentUnpaidOccurrence() throws {
        let now = d("2026-11-18")
        var ledger = salaryLedger()
        ledger.plans[0].dueDate = d("2026-10-20")
        ledger.entries[0].occurrence = d("2026-10-20")
        ledger.paydayConfirmSince = d("2026-11-20")
        let plan = ledger.plans[0]
        let change = try FixedFlows.update(planID: plan.id, title: plan.title, amount: plan.amount, frequency: .monthly,
                                          date: d("2026-11-20"), accountID: plan.accountID, category: plan.category,
                                          installments: nil, autoPay: false, estimated: false, in: ledger, now: now, monthlyDay: 15)
        try change.apply(to: &ledger)
        XCTAssertEqual(ledger.plans[0].dueDate, d("2026-11-15"))
        XCTAssertEqual(FixedFlows.month(containing: now, in: ledger).occurrences.filter { $0.planID == plan.id }.map(\.date),
                       [d("2026-11-15")])
        XCTAssertEqual(FixedFlows.month(containing: d("2026-10-25"), in: ledger).occurrences.first?.state, .paid)
        XCTAssertEqual(ledger.paydayConfirmSince, d("2026-11-15"))
        XCTAssertEqual(Payday.due(in: ledger, now: now)?.occurrence, d("2026-11-15"))
    }

    func testMidMonthStartingBudgetWorksWithBillsSpendingAndSavingRules() throws {
        let now = d("2026-11-18 12:00"), nominal = d("2026-11-10")
        for rule: SavingRule? in [nil, .fixed(25_000), .share(20)] {
            var ledger = Ledger()
            FirstUse.prepareForEntry(&ledger, now: now)
            let account = ledger.accounts[0].id
            ledger.savingRule = rule
            ledger.entries = [Entry(date: now, amount: 4380, accountID: account, title: "买菜", category: "餐饮")]
            ledger.plans = [Plan(title: "房租", amount: 350_000, dueDate: d("2026-11-25"), frequency: .monthly),
                            Plan(title: "未付话费", amount: 2000, dueDate: d("2026-11-09"))]
            try Payday.configure(day: 10, amount: 1_450_000, accountID: account,
                                 currentPeriodAvailable: 450_000, in: &ledger, now: now)
            let salary = try XCTUnwrap(Finance.anchorPlan(in: ledger, now: now))
            XCTAssertEqual(salary.category, "工资奖金")
            XCTAssertEqual(salary.dueDate, nominal)
            XCTAssertEqual(salary.monthlyDay, 10)
            XCTAssertEqual(ledger.paydayConfirmSince, d("2026-12-10"))
            let breakdown = Finance.spendableBreakdown(ledger, now: now)
            XCTAssertTrue(breakdown.offersFormula)
            XCTAssertEqual(breakdown.available, 450_000)
            XCTAssertEqual(breakdown.cycleStart, nominal)
            XCTAssertEqual(breakdown.cycleEnd, d("2026-12-09"))
            XCTAssertEqual(breakdown.billsRest, 352_000)
            XCTAssertEqual(breakdown.spent, 4380)
            let opening = try XCTUnwrap(ledger.entries.last)
            XCTAssertEqual(opening.title, "本期起点")
            XCTAssertEqual(opening.planID, salary.id)
            XCTAssertEqual(opening.occurrence, nominal)
            XCTAssertEqual(opening.date, nominal)
            XCTAssertEqual(opening.amount, 450_000 + breakdown.billsRest + breakdown.spent + breakdown.plannedSaving)
            XCTAssertEqual(FixedFlows.month(containing: now, in: ledger).occurrences.first { $0.planID == salary.id }?.state, .paid)
            XCTAssertEqual(Payday.due(in: ledger, now: d("2026-12-10"))?.occurrence, d("2026-12-10"))
            try Payday.configure(day: 10, amount: 1_450_000, accountID: account,
                                 currentPeriodAvailable: 450_000, in: &ledger, now: now)
            XCTAssertEqual(ledger.plans.filter(\.inflow).map(\.id), [salary.id])
            XCTAssertEqual(ledger.entries.count, 2)
            XCTAssertEqual(ledger.paydayConfirmSince, d("2026-12-10"))
            XCTAssertNoThrow(try ledger.validate())
        }
    }

    func testConfigureWithoutStartingBudgetReusesRecordedSalaryAndWaitsForNovember() throws {
        let now = d("2026-11-18 12:00")
        var ledger = salaryLedger()
        ledger.entries[0].planID = nil; ledger.entries[0].occurrence = nil
        ledger.plans[0].dueDate = d("2026-12-15")
        ledger.paydayConfirmSince = d("2026-12-15")
        let id = ledger.plans[0].id
        ledger.categories.removeAll { $0.income && $0.name == "工资奖金" }
        ledger.categories.append(Category("工资", income: true))
        try Payday.configure(day: 15, amount: 1_450_000, accountID: ledger.accounts[0].id, in: &ledger, now: now)
        XCTAssertEqual(ledger.plans[0].id, id)
        XCTAssertEqual(ledger.plans[0].category, "工资")
        XCTAssertEqual(ledger.plans[0].dueDate, d("2026-11-15"))
        XCTAssertEqual(ledger.entries[0].planID, id)
        XCTAssertEqual(ledger.paydayConfirmSince, d("2026-11-15"))
        XCTAssertEqual(Finance.spendableBreakdown(ledger, now: now).available, 196_500)
        XCTAssertEqual(Payday.due(in: ledger, now: now)?.occurrence, d("2026-11-15"))
        XCTAssertNoThrow(try ledger.validate())
    }

    func testRefundReducesCategorySpendingAndWaterFill() throws {
        let now = d("2026-10-19 12:00")
        var ledger = salaryLedger()
        let account = ledger.accounts[0].id
        try ManualBookkeeping.change(amount: 48_000, nature: .expense, accountID: account,
                                     day: now, purpose: "聚餐", category: "餐饮", now: now).apply(to: &ledger)
        let before = Finance.spendableBreakdown(ledger, now: now)
        try ManualBookkeeping.change(amount: 36_000, nature: .refund, accountID: account,
                                     day: now, purpose: "AA", category: "餐饮", now: now).apply(to: &ledger)
        let after = Finance.spendableBreakdown(ledger, now: now)
        let flow = Finance.cashFlow(ledger, during: after.interval)
        XCTAssertEqual(flow.spendingByCategory.first { $0.category == "餐饮" }?.amount, 12_000)
        XCTAssertEqual(after.spent, 12_000)
        XCTAssertEqual(after.income, before.income)
        XCTAssertLessThan(try XCTUnwrap(after.waterBar).fill, try XCTUnwrap(before.waterBar).fill)
    }

    func testPureFlowHasNoMismatchAndInflowDefaultIgnoresCredit() throws {
        let now = d("2026-11-18 12:00")
        var ledger = Ledger()
        FirstUse.prepareForEntry(&ledger, now: now)
        let cash = ledger.accounts[0], credit = Account(name: "信用卡", kind: .credit, balance: -457_000, at: now)
        ledger.accounts.append(credit)
        try ManualBookkeeping.change(amount: 4380, nature: .expense, accountID: credit.id,
                                     day: now, purpose: "买菜", category: "餐饮", now: now).apply(to: &ledger)
        XCTAssertNil(Reconciliation.mismatch(in: ledger, now: d("2026-11-19")))
        XCTAssertEqual(ManualBookkeeping.defaultAccount(in: ledger, nature: .expense)?.id, credit.id)
        XCTAssertEqual(ManualBookkeeping.defaultAccount(in: ledger, nature: .income)?.id, cash.id)
        XCTAssertEqual(ManualBookkeeping.defaultAccount(in: ledger, nature: .refund)?.id, cash.id)
        ledger.accounts[0].archived = true
        XCTAssertEqual(ManualBookkeeping.defaultAccount(in: ledger, nature: .income)?.id, credit.id)
    }

    func testReconciliationIgnoresCreditDebtAndKeepsAnUnchangedPreview() throws {
        let now = d("2026-11-18 12:00")
        var ledger = salaryLedger()
        let account = ledger.accounts[0].id
        ledger.accounts.append(Account(name: "信用卡", kind: .credit, balance: -457_000, at: now))
        let book = Finance.balance(ledger.accounts[0], in: ledger, at: now)
        let before = Finance.spendableBreakdown(ledger, now: now)
        let unchanged = Reconciliation.preview(ledger, actual: [account: book], now: now)
        XCTAssertEqual(unchanged.floor, 0)
        XCTAssertEqual(unchanged.spendableAfter, before)
        let edited = Reconciliation.preview(ledger, actual: [account: book - 52_000], now: now)
        XCTAssertEqual(edited.missing, 52_000)
        XCTAssertEqual(edited.floor, 52_000)
        XCTAssertEqual(edited.spendableAfter.available, 144_500)
        try Reconciliation.apply(&ledger, actual: [account: book - 52_000], now: now)
        XCTAssertEqual(Finance.spendableBreakdown(ledger, now: now).available, 144_500)
        let unchangedAfter = Reconciliation.preview(ledger, actual: [account: book - 52_000], now: now)
        XCTAssertEqual(unchangedAfter.floor, 52_000)
        XCTAssertEqual(unchangedAfter.spendableAfter.available, 144_500)
        XCTAssertFalse(unchangedAfter.changesSpendable)
    }

    func testUnchangedCashBelowTheFormulaDoesNotIntroduceAFloor() throws {
        let now = d("2026-11-18 12:00")
        var ledger = salaryLedger()
        ledger.accounts[0].anchorDate = now
        ledger.accounts[0].anchorBalance = 50_000
        let unchanged = Reconciliation.preview(ledger, actual: [ledger.accounts[0].id: 50_000], now: now)
        XCTAssertEqual(unchanged.floor, 0)
        XCTAssertEqual(unchanged.spendableAfter.available, 196_500)
        XCTAssertFalse(unchanged.changesSpendable)
    }
}
