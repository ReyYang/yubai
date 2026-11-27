import Foundation
import XCTest
@testable import YubaiCore

final class EntrySheetLogicTests: XCTestCase {
    private let now = Dates.parse("2026-11-23 14:20:00")!

    private func makeLedger() -> Ledger {
        var ledger = Ledger()
        let start = Dates.parse("2026-11-01 00:00:00")!
        let bank = Account(name: "招行储蓄", kind: .bank, balance: 3_018_000, at: start)
        let wallet = Account(name: "支付宝", kind: .cash, balance: 462_000, at: start)
        let credit = Account(name: "招行信用卡", kind: .credit, balance: -321_680, at: start)
        let invest = Account(name: "基金账户", kind: .investment, balance: 500_000, at: start)
        ledger.accounts = [bank, wallet, credit, invest]
        ledger.cycleAnchor = .payday
        ledger.savingRule = .fixed(200_000)

        let salaryDate = Dates.parse("2026-11-10 09:00:00")!
        let salaryPlan = Plan(title: "工资", amount: 1_850_000, dueDate: salaryDate, frequency: .monthly, inflow: true, category: "工资奖金", nature: .income)
        ledger.plans = [salaryPlan]
        ledger.paydayConfirmSince = salaryDate

        var salaryEntry = Entry(date: salaryDate, amount: 1_850_000, nature: .income, accountID: bank.id, title: "工资", category: "工资奖金")
        salaryEntry.planID = salaryPlan.id
        salaryEntry.occurrence = salaryDate
        salaryEntry.recordedAt = salaryDate
        ledger.entries = [salaryEntry]
        ledger.fixedSavings = 1_000_000
        return ledger
    }

    func testAmountExpressionArithmeticLimitsAndFormatting() {
        var expr = EntryAmountExpression()
        XCTAssertTrue(expr.isEmpty)
        XCTAssertFalse(expr.canSave)
        XCTAssertEqual(expr.formattedDisplay, "0")

        ["4", "2", "+", "1", "8", ".", "5", "0", "9"].forEach { expr.press($0) }
        XCTAssertEqual(expr.expression, "42+18.50")
        XCTAssertEqual(expr.formattedDisplay, "42 + 18.50")
        XCTAssertEqual(expr.evaluatedCents, 6050)
        XCTAssertTrue(expr.canSave)

        expr.press("⌫")
        XCTAssertEqual(expr.expression, "42+18.5")
        expr.press("−")
        expr.press("0")
        expr.press(".")
        expr.press("5")
        XCTAssertEqual(expr.evaluatedCents, 6000)
        XCTAssertEqual(expr.resolve(), 6000)
        XCTAssertEqual(expr.expression, "60.00")

        // Max 9 integer digits enforced
        expr.reset()
        "1234567899".forEach { expr.press(String($0)) }
        XCTAssertEqual(expr.expression, "123456789")
        XCTAssertEqual(expr.formattedDisplay, "123,456,789")

        // 00 behavior
        expr.reset()
        expr.press("00")
        XCTAssertEqual(expr.expression, "0")
        expr.press("5")
        expr.press("00")
        XCTAssertEqual(expr.expression, "500")
        expr.press(".")
        expr.press("00")
        XCTAssertEqual(expr.expression, "500.00")
        expr.press("00")
        XCTAssertEqual(expr.expression, "500.00")

        // Trailing operator preview
        expr.press("+")
        XCTAssertEqual(expr.formattedDisplay, "500.00 +")
        XCTAssertEqual(expr.evaluatedCents, 50_000)
    }

    func testSaveMapperCoversExpenseReserveSplitReimbursementAndForeignCurrency() throws {
        var ledger = makeLedger()
        let credit = ledger.accounts[2]

        // 1. Reserve expense
        let reserveInput = EntrySaveInput(
            type: .expense,
            amountCents: 699_900,
            purpose: "换手机",
            category: "购物",
            subcategory: "数码电器",
            accountID: credit.id,
            date: now,
            exception: .reserve
        )
        let reserveChange = try EntrySaveMapper.makeChange(reserveInput, in: ledger, now: now)
        try reserveChange.apply(to: &ledger)
        let savedReserve = try XCTUnwrap(ledger.entries.last)
        XCTAssertEqual(savedReserve.nature, .expense)
        XCTAssertTrue(savedReserve.fromReserve)
        XCTAssertNil(savedReserve.pendingRecovery)

        // 2. AA Split expense (暂扣 full 78.00 from 还能花, personalExpense = 26.00)
        let beforeAA = Finance.spendableBreakdown(ledger, now: now)
        let aaInput = EntrySaveInput(
            type: .expense,
            amountCents: 7800,
            purpose: "电影票 · IMAX",
            category: "娱乐",
            subcategory: "电影演出",
            accountID: credit.id,
            date: now,
            exception: .split,
            personalExpenseCents: 2600
        )
        let aaChange = try EntrySaveMapper.makeChange(aaInput, in: ledger, now: now)
        try aaChange.apply(to: &ledger)
        let savedAA = try XCTUnwrap(ledger.entries.last)
        XCTAssertEqual(savedAA.pendingRecovery, .split)
        XCTAssertEqual(savedAA.personalExpense, 2600)
        let afterAA = Finance.spendableBreakdown(ledger, now: now)
        XCTAssertEqual(beforeAA.available - afterAA.available, 7800)
        XCTAssertEqual(Finance.spendingAmount(savedAA, ledger: ledger), 2600)

        // 3. Foreign currency reimbursement
        let jpyInput = EntrySaveInput(
            type: .expense,
            amountCents: 328_000, // 3,280 JPY
            currency: .jpy,
            exchangeRate: Decimal(string: "0.0475"),
            purpose: "出差 · 便利店",
            category: "餐饮",
            subcategory: "零食水果",
            accountID: credit.id,
            date: now,
            exception: .reimbursement
        )
        let jpyChange = try EntrySaveMapper.makeChange(jpyInput, in: ledger, now: now)
        try jpyChange.apply(to: &ledger)
        let savedJPY = try XCTUnwrap(ledger.entries.last)
        XCTAssertEqual(savedJPY.amount, 15_580)
        XCTAssertEqual(savedJPY.originalCurrency, .jpy)
        XCTAssertEqual(savedJPY.originalAmount, 328_000)
        XCTAssertEqual(savedJPY.pendingRecovery, .reimbursement)
        let afterJPY = Finance.spendableBreakdown(ledger, now: now)
        XCTAssertEqual(afterAA.available - afterJPY.available, 15_580)
    }

    func testCountsFromCycleStartExcludesCurrentCycleAndIncludesNextCycle() throws {
        var ledger = makeLedger()
        let bank = ledger.accounts[0]
        let dec9 = Dates.parse("2026-12-09 10:00:00")!
        let dec10 = Dates.parse("2026-12-10 00:00:00")!
        let dec15 = Dates.parse("2026-12-15 12:00:00")!

        let before = Finance.spendableBreakdown(ledger, now: dec9)
        let incomeInput = EntrySaveInput(
            type: .income,
            amountCents: 1_850_000,
            purpose: "工资",
            category: "工资奖金",
            subcategory: "工资",
            accountID: bank.id,
            date: dec9,
            incomeNextCycle: true
        )
        let change = try EntrySaveMapper.makeChange(incomeInput, in: ledger, now: dec9)
        try change.apply(to: &ledger)
        let saved = try XCTUnwrap(ledger.entries.last)
        XCTAssertEqual(saved.countsFromCycleStart, dec10)

        // Excluded on Dec 9 (current cycle)
        let onDec9 = Finance.spendableBreakdown(ledger, now: dec9)
        XCTAssertEqual(onDec9.income, before.income)
        XCTAssertEqual(onDec9.available, before.available)

        // Included from Dec 10 onwards (next cycle)
        let onDec10 = Finance.spendableBreakdown(ledger, now: dec10)
        XCTAssertEqual(onDec10.income, 1_850_000)

        let onDec15 = Finance.spendableBreakdown(ledger, now: dec15)
        XCTAssertEqual(onDec15.income, 1_850_000)

        // An unpaid payday keeps the previous cycle open. Record January's
        // actual salary receipt to advance the configured confirmation cycle.
        let jan10 = Dates.parse("2027-01-10 09:00:00")!
        var januarySalary = Entry(date: jan10, amount: 1_800_000, nature: .income,
                                  accountID: bank.id, title: "工资", category: "工资奖金")
        januarySalary.planID = ledger.plans[0].id
        januarySalary.occurrence = Dates.day(jan10)
        januarySalary.recordedAt = jan10
        ledger.entries.append(januarySalary)
        let jan12 = Dates.parse("2027-01-12 10:00:00")!
        let onJan12 = Finance.spendableBreakdown(ledger, now: jan12)
        XCTAssertEqual(onJan12.cycleStart, Dates.day(jan10))
        XCTAssertEqual(onJan12.income, januarySalary.amount)
    }

    func testPrefilledRefundKeepsTheLinkAndTheExplicitTime() throws {
        var ledger = makeLedger()
        let bank = ledger.accounts[0]
        let purchase = Entry(date: Dates.addDays(-1, to: now), amount: 6_000, accountID: bank.id,
                             title: "午饭", category: "餐饮")
        ledger.entries.append(purchase)
        let refundDate = try XCTUnwrap(Dates.parse("2026-11-23 09:15:00"))
        let input = EntrySaveInput(type: .income, amountCents: 2_000, purpose: "午饭退款", accountID: bank.id,
                                   date: refundDate, recordedNature: .refund, relatedEntryID: purchase.id,
                                   preserveTime: true)
        let change = try EntrySaveMapper.makeChange(input, in: ledger, now: now)
        try change.apply(to: &ledger)
        let refund = try XCTUnwrap(ledger.entries.last)
        XCTAssertEqual(refund.nature, .refund)
        XCTAssertEqual(refund.relatedEntryID, purchase.id)
        XCTAssertEqual(refund.category, purchase.category)
        XCTAssertEqual(refund.date, refundDate)
        XCTAssertEqual(Finance.spendingAmount(refund, ledger: ledger), -2_000)
    }

    func testTransferRepaymentDepositAndMonthlyRepeatMapping() throws {
        var ledger = makeLedger()
        let bank = ledger.accounts[0]
        let wallet = ledger.accounts[1]
        let credit = ledger.accounts[2]
        let invest = ledger.accounts[3]

        // Transfer to credit => repayment
        let repayChange = try EntrySaveMapper.makeChange(
            EntrySaveInput(type: .transfer, amountCents: 321_680, purpose: "还信用卡", accountID: bank.id, destinationAccountID: credit.id, date: now),
            in: ledger,
            now: now
        )
        try repayChange.apply(to: &ledger)
        XCTAssertEqual(ledger.entries.last?.nature, .repayment)
        XCTAssertEqual(ledger.entries.last?.otherAccountID, credit.id)

        // Transfer to cash/bank => transfer
        let moveChange = try EntrySaveMapper.makeChange(
            EntrySaveInput(type: .transfer, amountCents: 200_000, purpose: "转到支付宝", accountID: bank.id, destinationAccountID: wallet.id, date: now),
            in: ledger,
            now: now
        )
        try moveChange.apply(to: &ledger)
        XCTAssertEqual(ledger.entries.last?.nature, .transfer)

        // Deposit to investment => investBuy (with monthly repeat)
        let investChange = try EntrySaveMapper.makeChange(
            EntrySaveInput(type: .deposit, amountCents: 100_000, purpose: "基金定投", accountID: bank.id, destinationAccountID: invest.id, date: now, repeatMonthly: true),
            in: ledger,
            now: now
        )
        try investChange.apply(to: &ledger)
        XCTAssertEqual(ledger.entries.last?.nature, .investBuy)
        XCTAssertEqual(ledger.entries.last?.otherAccountID, invest.id)
        XCTAssertEqual(ledger.plans.last?.nature, .investBuy)

        // Deposit to non-investment => transfer + intoFixedSavings
        let beforeFixed = ledger.fixedSavingsTotal(now: now)
        let savingsChange = try EntrySaveMapper.makeChange(
            EntrySaveInput(type: .deposit, amountCents: 100_000, purpose: "存钱", accountID: bank.id, destinationAccountID: wallet.id, date: now),
            in: ledger,
            now: now
        )
        try savingsChange.apply(to: &ledger)
        XCTAssertEqual(ledger.entries.last?.nature, .transfer)
        XCTAssertTrue(ledger.entries.last?.intoFixedSavings == true)
        XCTAssertEqual(ledger.fixedSavingsTotal(now: now), beforeFixed + 100_000)

        // Additive Codable round-trip & legacy decode compatibility
        let data = try LedgerCodec.encode(ledger)
        let decoded = try LedgerCodec.decode(data)
        XCTAssertEqual(decoded.entries, ledger.entries)

        let legacyJSON = #"{"date":0,"amount":4200,"nature":"expense","accountID":"\#(bank.id.uuidString)","title":"午饭","category":"餐饮"}"#.data(using: .utf8)!
        let legacyEntry = try JSONDecoder().decode(Entry.self, from: legacyJSON)
        XCTAssertNil(legacyEntry.pendingRecovery)
        XCTAssertNil(legacyEntry.countsFromCycleStart)
        XCTAssertNil(legacyEntry.originalCurrency)
        XCTAssertNil(legacyEntry.originalAmount)
    }
    func testInvestmentPlanPostsBothLegsOnFutureManualAndAutomaticPayments() throws {
        var ledger = makeLedger()
        let bank = ledger.accounts[0]
        let investment = ledger.accounts[3]
        let change = try EntrySaveMapper.makeChange(
            EntrySaveInput(type: .deposit, amountCents: 100_000, purpose: "定投", accountID: bank.id,
                           destinationAccountID: investment.id, date: now, repeatMonthly: true),
            in: ledger, now: now
        )
        try change.apply(to: &ledger)
        let plan = try XCTUnwrap(ledger.plans.last)
        XCTAssertEqual(plan.otherAccountID, investment.id)
        let decoded = try LedgerCodec.decode(LedgerCodec.encode(ledger))
        XCTAssertEqual(decoded.plans.last?.otherAccountID, investment.id)
        let nextDate = try XCTUnwrap(Dates.parse("2026-12-23 14:20:00"))
        let priorBalance = Finance.balance(investment, in: ledger, at: nextDate)

        func verify(_ result: Ledger) {
            XCTAssertEqual(result.entries.last?.otherAccountID, investment.id)
            XCTAssertEqual(result.entries.last?.planID, plan.id)
            XCTAssertEqual(Finance.balance(investment, in: result, at: nextDate), priorBalance + 100_000)
            XCTAssertEqual(Finance.balance(bank, in: result, at: nextDate),
                           Finance.balance(bank, in: ledger, at: nextDate) - 100_000)
        }

        var manual = decoded
        let settlement = try FixedFlows.settle(planID: plan.id, occurrence: nextDate, in: manual, now: nextDate)
        try settlement.apply(to: &manual)
        verify(manual)

        var automatic = decoded
        let index = try XCTUnwrap(automatic.plans.firstIndex(where: { $0.id == plan.id }))
        automatic.plans[index].autoPay = true
        let autopay = try XCTUnwrap(FixedFlows.autoSettle(in: automatic, now: nextDate))
        try autopay.apply(to: &automatic)
        verify(automatic)
        XCTAssertNil(FixedFlows.autoSettle(in: automatic, now: nextDate))

        var legacy = decoded
        legacy.plans[index].otherAccountID = nil
        legacy = try LedgerCodec.decode(LedgerCodec.encode(legacy))
        XCTAssertNil(legacy.plans[index].otherAccountID)
        let legacySettlement = try FixedFlows.settle(planID: plan.id, occurrence: nextDate, in: legacy, now: nextDate)
        try legacySettlement.apply(to: &legacy)
        verify(legacy)
    }

    func testCashDepositCountsOnceAcrossCycleClose() throws {
        var ledger = Ledger()
        let anchor = try XCTUnwrap(Dates.parse("2026-11-01 00:00:00"))
        let bank = Account(name: "银行", kind: .bank, at: anchor)
        let wallet = Account(name: "现金", kind: .cash, at: anchor)
        ledger.accounts = [bank, wallet]
        ledger.cycleAnchor = .calendarMonth
        ledger.entries = [Entry(date: Dates.addDays(1, to: anchor), amount: 100_000, nature: .income,
                                accountID: bank.id, title: "收入", category: "工资奖金")]
        XCTAssertEqual(Finance.spendableBreakdown(ledger, now: now).available, 100_000)
        let deposit = try EntrySaveMapper.makeChange(
            EntrySaveInput(type: .deposit, amountCents: 30_000, accountID: bank.id,
                           destinationAccountID: wallet.id, date: now),
            in: ledger, now: now
        )
        try deposit.apply(to: &ledger)
        XCTAssertEqual(ledger.fixedSavingsTotal(now: now), 30_000)
        let projected = Finance.spendableBreakdown(ledger, now: now)
        XCTAssertEqual(projected.available, 70_000)
        XCTAssertEqual(projected.rows.first(where: { $0.kind == .deposit })?.amount, -30_000)
        let nextCycle = try XCTUnwrap(Dates.parse("2026-12-01 12:00:00"))
        var reconciled = ledger
        let reconciliationDate = Dates.addDays(1, to: now)
        try Reconciliation.apply(&reconciled, actual: [wallet.id: 30_000], now: reconciliationDate)
        XCTAssertEqual(reconciled.fixedSavings, 30_000)
        XCTAssertEqual(Finance.spendableBreakdown(reconciled, now: reconciliationDate).available, 70_000)
        Savings.closeCycles(&reconciled, now: nextCycle)
        XCTAssertEqual(reconciled.savingHistory.last?.leftover, 70_000)
        XCTAssertEqual(reconciled.fixedSavingsTotal(now: nextCycle), 100_000)

        Savings.closeCycles(&ledger, now: nextCycle)
        XCTAssertEqual(ledger.savingHistory.last?.leftover, 70_000)
        XCTAssertEqual(ledger.fixedSavings, 70_000)
        XCTAssertEqual(ledger.fixedSavingsTotal(now: nextCycle), 100_000)
        Savings.closeCycles(&ledger, now: nextCycle)
        XCTAssertEqual(ledger.fixedSavingsTotal(now: nextCycle), 100_000)
    }

    func testImportMergePreservesManualRecoveryDeferredIncomeAndCurrency() throws {
        let account = try XCTUnwrap(makeLedger().accounts.first)
        let deferred = Dates.addDays(3, to: now)
        for nature in [Nature.expense, .income] {
            var manual = Entry(date: now, amount: 25_000, nature: nature, accountID: account.id,
                               title: "手记", category: nature == .income ? "工资奖金" : "餐饮")
            manual.recordedAt = now
            if nature == .expense { manual.pendingRecovery = .split; manual.personalExpense = 10_000 }
            if nature == .income { manual.countsFromCycleStart = deferred }
            manual.originalCurrency = .usd
            manual.originalAmount = 3_500

            let imported = Entry(date: Dates.addDays(1, to: now), amount: manual.amount, nature: nature,
                                 accountID: account.id, title: "导入", category: Classification.pendingCategory)
            XCTAssertTrue(BillImporter.manualMatches(manual, imported: imported, accountIsUnknown: false))
            let merged = BillImporter.mergedImport(imported, preserving: manual, accountIsUnknown: false)
            XCTAssertEqual(merged.id, manual.id)
            XCTAssertEqual(merged.date, imported.date)
            XCTAssertEqual(merged.pendingRecovery, nature == .expense ? .split : nil)
            XCTAssertEqual(merged.personalExpense, nature == .expense ? 10_000 : nil)
            XCTAssertEqual(merged.countsFromCycleStart, nature == .income ? deferred : nil)
            XCTAssertEqual(merged.originalCurrency, .usd)
            XCTAssertEqual(merged.originalAmount, 3_500)
        }
    }

    func testExpressionRejectsTotalsBeyondNineIntegerDigits() throws {
        XCTAssertEqual(try EntryAmountExpression.evaluate("999999999.98+0.01"), 99_999_999_999)
        XCTAssertThrowsError(try EntryAmountExpression.evaluate("999999999.99+0.01"))
        XCTAssertThrowsError(try EntryAmountExpression.evaluate("-999999999.99-0.01"))
        var expression = EntryAmountExpression(expression: "999999999.99+")
        expression.press("1")
        XCTAssertEqual(expression.expression, "999999999.99+")
        XCTAssertEqual(expression.evaluatedCents, 99_999_999_999)
    }

    func testRepeatingIncomeDoesNotShowMoneySetAside() {
        let ledger = makeLedger()
        let input = EntrySaveInput(type: .income, amountCents: 5_800, accountID: ledger.accounts[0].id,
                                   date: now, repeatMonthly: true)

        XCTAssertNil(EntrySaveMapper.effect(for: input, in: ledger, now: now))
    }

    func testEntryEffectShowsOnlyMoneySetAsideOrRecovered() throws {
        var ledger = makeLedger()
        ledger.fixedSavings = 842_000
        let bank = ledger.accounts[0]
        let wallet = ledger.accounts[1]
        let fund = ledger.accounts[3]
        var input = EntrySaveInput(type: .expense, amountCents: 699_900, category: "购物",
                                   accountID: bank.id, date: now)
        func effect(_ input: EntrySaveInput) -> EntryEffect? {
            EntrySaveMapper.effect(for: input, in: ledger, now: now)
        }

        XCTAssertNil(effect(input))
        input.exception = .reserve
        let reserve = try XCTUnwrap(effect(input))
        XCTAssertEqual(reserve, .reserve(142_100))
        XCTAssertEqual(reserve.text, "机动余钱还剩 1,421.00")
        XCTAssertEqual(reserve.displayText(hidesAmount: true), "••••")
        XCTAssertFalse(reserve.warning)

        input.exception = nil
        input.amountCents = 5_800
        input.repeatMonthly = true
        XCTAssertEqual(effect(input)?.text, "下期起每月先留 58.00")

        input.repeatMonthly = false
        input.exception = .split
        input.amountCents = 7_800
        input.personalExpenseCents = 2_600
        XCTAssertEqual(effect(input)?.text, "待收回 52.00")
        XCTAssertTrue(effect(input)?.warning == true)
        input.exception = .reimbursement
        input.currency = .jpy
        input.exchangeRate = Decimal(string: "0.0475")
        input.amountCents = 328_000
        XCTAssertEqual(effect(input)?.text, "待收回 155.80")
        XCTAssertTrue(effect(input)?.warning == true)

        input = EntrySaveInput(type: .income, amountCents: 5_800, accountID: bank.id,
                               date: now, incomeNextCycle: true)
        XCTAssertNil(effect(input))
        input.type = .transfer
        input.destinationAccountID = wallet.id
        XCTAssertNil(effect(input))
        input.type = .deposit
        XCTAssertNil(effect(input))
        input.repeatMonthly = true
        XCTAssertNil(effect(input))
        input.destinationAccountID = fund.id
        XCTAssertEqual(effect(input), .monthly(5_800))
    }

}
