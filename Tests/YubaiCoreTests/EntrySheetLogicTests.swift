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
}
