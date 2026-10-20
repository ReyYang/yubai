import XCTest
@testable import YubaiCore

final class CashFlowTests: XCTestCase {
    private let start = Dates.parse("2026-10-01")!
    private let end = Dates.parse("2026-11-01")!
    private func entry(_ amount: Int64, _ nature: Nature = .expense, _ category: String = "餐饮", at: Date? = nil) -> Entry {
        Entry(date: at ?? start, amount: amount, nature: nature, accountID: UUID(), title: category, category: category)
    }
    func testBothDirectionsExcludeInternalMovementsAndUseHalfOpenWindow() {
        var ledger = Ledger()
        var deleted = entry(9000); deleted.deletedAt = start
        ledger.entries = [entry(10_000, .income, "工资"), entry(2000, .income, "奖金"),
                          entry(500, .income, "奖金"), entry(3000), entry(1000, .refund),
                          entry(8000, .transfer), entry(8000, .repayment), entry(8000, .contribution),
                          entry(8000, .unknownIn), entry(8000, .unknownOut), deleted,
                          entry(9999, at: start.addingTimeInterval(-1)), entry(9999, at: end)]
        let flow = Finance.cashFlow(ledger, during: DateInterval(start: start, end: end))
        XCTAssertEqual(flow.income, 12_500); XCTAssertEqual(flow.spending, 2000); XCTAssertEqual(flow.balance, 10_500)
        XCTAssertEqual(flow.incomeByCategory.map(\.category), ["工资", "奖金"])
        XCTAssertEqual(flow.incomeByCategory.map(\.amount), [10_000, 2500])
        XCTAssertEqual(flow.incomeByCategory.last?.count, 2)
        XCTAssertEqual(flow.spendingByCategory.map(\.amount), [2000])
    }
    func testCrossPeriodRefundAndPersonalShareAgreeWithReviewAndLetter() {
        var ledger = Ledger()
        var original = entry(10_000, .expense, "共同支出", at: Dates.addDays(-10, to: start))
        original.personalExpense = 5000
        var refund = entry(4000, .refund, "旧分类")
        refund.relatedEntryID = original.id; refund.personalExpense = 2000
        var personal = entry(12_000); personal.personalExpense = 6000
        ledger.entries = [original, refund, personal]
        let interval = DateInterval(start: start, end: Dates.addDays(7, to: start))
        let flow = Finance.cashFlow(ledger, during: interval)
        let review = Finance.review(ledger, from: interval.start, through: interval.end)
        let letter = WeeklyLetter.facts(ledger, weekEnding: Dates.addDays(6, to: start))
        XCTAssertEqual(flow.spending, 4000); XCTAssertEqual(flow.spending, review.spending)
        XCTAssertEqual(flow.spending, letter.spending); XCTAssertEqual(flow.income, 0)
        XCTAssertEqual(flow.spendingByCategory.first { $0.category == "共同支出" }?.amount, -2000)
        XCTAssertEqual(flow.spendingByCategory.reduce(Int64(0)) { $0 + $1.amount }, flow.spending)
    }
    func testSixSectorLimitKeepsAllCategoriesAndAmounts() {
        var ledger = Ledger()
        ledger.entries = (1...9).map { entry(Int64($0 * 100), .expense, "分类\($0)") }
        let flow = Finance.cashFlow(ledger, during: DateInterval(start: start, end: end))
        let slices = flow.slices(income: false)
        XCTAssertEqual(slices.count, 6)
        XCTAssertEqual(slices.last?.title, "其他 4 类")
        XCTAssertEqual(Set(slices.flatMap(\.categories)).count, 9)
        XCTAssertEqual(slices.reduce(Int64(0)) { $0 + $1.amount }, flow.spending)
        XCTAssertEqual(slices.reduce(0.0) { $0 + $1.share }, 1, accuracy: 0.000001)
        XCTAssertEqual(flow.slices(income: true).count, 0)
    }
    func testEmptyAndTiesAreDeterministicWithoutMutatingLedger() {
        var ledger = Ledger()
        let interval = DateInterval(start: start, end: end)
        XCTAssertEqual(Finance.cashFlow(ledger, during: interval).balance, 0)
        XCTAssertTrue(Finance.cashFlow(ledger, during: interval).spendingByCategory.isEmpty)
        ledger.entries = [entry(100, .income, "B"), entry(100, .income, "A"), entry(50, .expense, "B"), entry(50, .expense, "A")]
        let before = ledger
        let flow = Finance.cashFlow(ledger, during: interval)
        XCTAssertEqual(flow.incomeByCategory.map(\.category), ["A", "B"])
        XCTAssertEqual(flow.spendingByCategory.map(\.category), ["A", "B"])
        XCTAssertEqual(ledger, before)
    }
}
