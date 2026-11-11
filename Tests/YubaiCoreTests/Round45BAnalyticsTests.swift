import XCTest
@testable import YubaiCore

enum Round45BFixture {
    static func d(_ text: String) -> Date { Dates.parse(text)! }
    static let now = d("2026-11-20 12:00")
    static func ledger() -> Ledger {
        var ledger = Ledger(); ledger.updatedAt = now; ledger.cycleAnchor = .calendarMonth
        ledger.accounts = [Account(name: "银行卡", balance: 1_000_000, at: d("2026-08-01"))]
        ledger.fixedSavings = 300_000; ledger.savingRule = .fixed(100_000)
        return ledger
    }
    static func entry(_ ledger: Ledger, date: String, amount: Int64 = 1000, title: String = "午饭", category: String = "餐饮", nature: Nature = .expense) -> Entry {
        Entry(date: d(date), amount: amount, nature: nature, accountID: ledger.accounts[0].id, title: title, category: category)
    }
}
final class Round45BAnalyticsTests: XCTestCase {
    let now = Round45BFixture.now
    func d(_ text: String) -> Date { Round45BFixture.d(text) }
    func testPastCyclesNewestFirstAndEmptyLimit() {
        var ledger = Round45BFixture.ledger()
        ledger.entries = [Round45BFixture.entry(ledger, date: "2026-08-20")]
        XCTAssertEqual(Finance.pastCycles(ledger, now: now).map(\.start), [d("2026-10-01"), d("2026-09-01"), d("2026-08-01")])
        XCTAssertTrue(Finance.pastCycles(ledger, now: now, limit: -1).isEmpty)
        XCTAssertTrue(Finance.pastCycles(Round45BFixture.ledger(), now: now).isEmpty)
    }
    func testSavedHistoryStillPagesWithoutSurvivingEntries() {
        var ledger = Round45BFixture.ledger()
        ledger.savingHistory = [CycleSaving(cycleStart: d("2026-10-01"), cycleEnd: d("2026-10-31"), income: 100, target: 0, saved: 0)]
        XCTAssertEqual(Finance.pastCycles(ledger, now: now).count, 1)
    }
    func testClosedFormulaIdentityAndStoredSettlementAmounts() throws {
        var ledger = Round45BFixture.ledger()
        ledger.entries = [Round45BFixture.entry(ledger, date: "2026-10-05", amount: 800_000, nature: .income),
                          Round45BFixture.entry(ledger, date: "2026-10-15", amount: 20_000)]
        var bill = Plan(title: "房租", amount: 200_000, dueDate: d("2026-10-10"))
        bill.accountID = ledger.accounts[0].id; ledger.plans = [bill]
        var payment = Round45BFixture.entry(ledger, date: "2026-10-10", amount: 200_000)
        payment.planID = bill.id; payment.occurrence = bill.dueDate; ledger.entries.append(payment)
        Savings.closeCycles(&ledger, now: now)
        let formula = Finance.closedFormula(ledger, cycleStart: d("2026-10-01"))
        XCTAssertEqual(formula.hand - formula.fixedSavings - formula.saving - formula.bills - formula.spent, formula.remaining)
        XCTAssertEqual(formula.income, 800_000); XCTAssertEqual(formula.saving, 100_000)
        XCTAssertEqual(formula.bills, 200_000); XCTAssertEqual(formula.spent, 20_000)
        XCTAssertEqual(formula.remaining, ledger.savingHistory[0].unspent)
        let before = formula
        try Savings.resolveLeftover(cycleStart: formula.cycleStart, choice: .save, in: &ledger)
        XCTAssertEqual(Finance.closedFormula(ledger, cycleStart: formula.cycleStart), before)
    }
    func testClosedFormulaAbsorbsTransfersReserveAndNegativeRemainder() {
        var ledger = Round45BFixture.ledger()
        ledger.accounts[0].anchorBalance = 1000; ledger.fixedSavings = 0; ledger.savingRule = nil
        ledger.entries = [Round45BFixture.entry(ledger, date: "2026-10-12", amount: 2000)]
        let formula = Finance.closedFormula(ledger, cycleStart: d("2026-10-01"))
        XCTAssertEqual(formula.remaining, -1000)
        XCTAssertEqual(formula.hand - formula.fixedSavings - formula.saving - formula.bills - formula.spent, -1000)
        Savings.closeCycles(&ledger, now: now)
        XCTAssertEqual(ledger.savingHistory.first?.unspent, 0)
        XCTAssertEqual(Finance.closedFormula(ledger, cycleStart: d("2026-10-01")).remaining, -1000)
    }
    func testCategoryUsesSameOffsetAndFrequentPurposesWithRefunds() {
        var ledger = Round45BFixture.ledger()
        ledger.entries = [Round45BFixture.entry(ledger, date: "2026-10-10", amount: 3000),
                          Round45BFixture.entry(ledger, date: "2026-10-25", amount: 99_000),
                          Round45BFixture.entry(ledger, date: "2026-11-10", amount: 2000),
                          Round45BFixture.entry(ledger, date: "2026-11-11", amount: 2000),
                          Round45BFixture.entry(ledger, date: "2026-11-12", amount: 5000, title: "咖啡")]
        var refund = Round45BFixture.entry(ledger, date: "2026-11-15", amount: 1000, nature: .refund)
        refund.relatedEntryID = ledger.entries[2].id; ledger.entries.append(refund)
        ledger.entries.append(Round45BFixture.entry(ledger, date: "2026-11-21", amount: 999_000))
        let result = Finance.categoryDetail(ledger, category: "餐饮", now: now)
        XCTAssertEqual(result.cycles.map(\.amount), [8000, 3000])
        XCTAssertEqual(result.cycles.last?.through, d("2026-10-20"))
        XCTAssertEqual(result.frequentPlaces.first?.title, "午饭")
        XCTAssertEqual(result.frequentPlaces.first?.count, 2); XCTAssertEqual(result.frequentPlaces.first?.amount, 3000)
        XCTAssertEqual(result.entries.count, 4)
        XCTAssertEqual(Finance.categoryDetail(ledger, category: "不存在", now: now).cycles.first?.amount, 0)
    }
    func testLongLateSalaryCategoryCycleAndPaging() {
        var ledger = Round45Fixture.ledger(); ledger.paydayConfirmSince = d("2026-12-10")
        var income = Round45BFixture.entry(ledger, date: "2027-01-12", amount: 800_000, nature: .income)
        income.planID = ledger.plans[0].id; income.occurrence = d("2027-01-10"); ledger.entries.append(income)
        let past = Finance.pastCycles(ledger, now: d("2027-01-15"), limit: 1)
        XCTAssertEqual(past.first?.start, d("2026-11-10")); XCTAssertEqual(past.first?.end, d("2027-01-12"))
        let detail = Finance.categoryDetail(ledger, category: "餐饮", now: d("2027-01-15"))
        XCTAssertEqual(detail.cycles.dropFirst().first?.through, d("2026-11-13"))
    }
}
