import XCTest
@testable import YubaiCore

final class AssistantToolTests: XCTestCase {
    private let ctx = AssistantFixtures.context()
    private func run(_ tool: ReadOnlyTool, _ args: String = "{}") throws -> JSONValue {
        try tool.run(JSONValue.parse(args), ctx)
    }
    private func cents(_ value: JSONValue?) -> Int64? {
        guard let value, let cents = value["cents"], case .number(let number) = cents else { return nil }
        return Int64(number)
    }
    func testFundsMatchFinanceParts() throws {
        let output = try run(.getFunds)
        let f = Finance.funds(ctx.ledger, now: ctx.now)
        let expected = ["available": f.available, "cash": f.cash, "debt": f.debt, "committed": f.committed,
                        "goals": f.goals, "emergency": f.emergency, "living": f.living, "uncertain": f.uncertainInflow, "expected_income": f.expectedIncome]
        for (key, amount) in expected {
            XCTAssertEqual(cents(output[key]), amount, key)
            XCTAssertEqual(output[key]?["text"]?.stringValue, Money.text(amount), key)
        }
        XCTAssertEqual(output["warnings"], .strings(f.warnings))
        XCTAssertEqual(f.available, 78500)
    }
    func testForecastMatchesFinanceAndShortfall() throws {
        let output = try run(.forecast, #"{"days":5,"amount":"800"}"#)
        let f = Finance.funds(ctx.ledger, now: ctx.now, days: 6)
        XCTAssertEqual(cents(output["conservative"]), f.points[5].conservative)
        XCTAssertEqual(cents(output["expected"]), f.points[5].expected)
        XCTAssertEqual(cents(output["expected"]), 98500) // Income at noon on the target day is included.
        XCTAssertEqual(cents(output["short_by"]), 1500)
        XCTAssertEqual(output["enough"], .bool(false))
        XCTAssertEqual(output["known_payments"]?.arrayValue?.count, f.occurrences.filter { !$0.inflow }.count)
        XCTAssertEqual(try run(.forecast, #"{"date":"2026-06-20","amount":"800"}"#), output)
        XCTAssertThrowsError(try run(.forecast, #"{"days":366}"#))
        XCTAssertThrowsError(try run(.forecast, #"{"date":"2026-06-10"}"#))
        XCTAssertThrowsError(try run(.forecast, #"{"date":"2026-06-20","days":5}"#))
    }
    func testQueryFiltersRawAmountsNotesDirectionsAndDateBounds() throws {
        let coffee = try run(.queryEntries, #"{"start_date":"2026-06-13","end_date":"2026-06-14","category":"餐饮","nature":"spending","keyword":"咖啡","min_amount":"20","max_amount":30,"limit":1}"#)
        XCTAssertEqual(coffee["matched_count"], .number(2)); XCTAssertEqual(coffee["truncated"], .bool(true))
        XCTAssertEqual(cents(coffee["entries"]?.arrayValue?.first?["amount"]), 3000)
        let note = try run(.queryEntries, #"{"keyword":"加班"}"#)
        XCTAssertEqual(note["entry_ids"], .strings([ctx.ledger.entries[1].id.uuidString]))
        XCTAssertEqual(try run(.queryEntries, #"{"nature":"income"}"#)["matched_count"], .number(1))
        XCTAssertEqual(try run(.queryEntries, #"{"nature":"transfer"}"#)["matched_count"], .number(1))
        let alias = ctx.redactor.text("微信转账-张三")
        let aliased = try ReadOnlyTool.queryEntries.run(.object(["keyword": .string(alias)]), ctx)
        XCTAssertEqual(aliased["matched_count"], .number(1))
        XCTAssertThrowsError(try run(.queryEntries, #"{"limit":51}"#))
        XCTAssertThrowsError(try run(.queryEntries, #"{"limit":0}"#))
        XCTAssertThrowsError(try run(.queryEntries, #"{"nature":"invalid"}"#))
        XCTAssertThrowsError(try run(.queryEntries, #"{"start_date":"2026-06-15","end_date":"2026-06-10"}"#))
    }
    func testSummariesUseFinanceRefundAndPersonalRentSemantics() throws {
        let review = Finance.review(ctx.ledger, from: Dates.addDays(-100, to: ctx.now), through: Dates.addDays(1, to: ctx.now))
        for group in ["day", "week", "month", "category"] {
            let output = try run(.summarize, "{\"group_by\":\"\(group)\"}")
            XCTAssertEqual(cents(output["spending"]), review.spending)
            XCTAssertEqual(cents(output["income"]), review.income)
            XCTAssertEqual(output["count"], .number(Double(review.count)))
            if group == "category" {
                for item in review.byCategory {
                    let result = output["groups"]?.arrayValue?.first { $0["group"]?.stringValue == item.category }
                    XCTAssertEqual(cents(result?["spending"]), item.amount)
                }
            }
        }
        let spending = try run(.summarize, #"{"nature":"spending"}"#)
        XCTAssertEqual(cents(spending["spending"]), 8500)
        let refunds = try run(.summarize, #"{"category":"餐饮","start_date":"2026-06-15"}"#)
        XCTAssertEqual(cents(refunds["spending"]), -500)
    }
    func testHabitUsesPastExpensesAndReportsPosition() throws {
        let output = try run(.compareToHabit, #"{"category":"餐饮","amount":"30"}"#)
        let expenses = ctx.ledger.entries.filter { $0.nature == .expense && $0.category == "餐饮" }
        let total = expenses.reduce(Int64(0)) { $0 + Finance.spendingAmount($1, ledger: ctx.ledger) }
        XCTAssertEqual(cents(output["average"]), total / Int64(expenses.count))
        XCTAssertEqual(cents(output["median"]), 2500)
        XCTAssertEqual(output["count"], .number(2)); XCTAssertEqual(output["count_per_week"], .number(2.0 * 7 / 90))
        XCTAssertEqual(output["percentile"], .number(100))
        XCTAssertEqual(output["recent"]?.arrayValue?.count, 2)
        let empty = try run(.compareToHabit, #"{"keyword":"不存在","amount":"30"}"#)
        XCTAssertEqual(empty["average"], .null); XCTAssertEqual(empty["median"], .null); XCTAssertEqual(empty["percentile"], .null)
        XCTAssertThrowsError(try run(.compareToHabit))
    }
    func testProfileContractAndNoPrivateFieldsInAnyToolOutput() throws {
        XCTAssertNil(try run(.getProfile)["purchaseValues"])
        XCTAssertEqual(try run(.getProfile)["principles"], .strings(ctx.ledger.profile.principles))
        for tool in ReadOnlyTool.allCases {
            let args: String
            switch tool {
            case .forecast: args = #"{"days":5}"#
            case .compareToHabit: args = #"{"category":"餐饮"}"#
            default: args = "{}"
            }
            let json = try run(tool, args).jsonText()
            for forbidden in ["externalID", "sourceIdentity", "fingerprint", "attachment", "external_PRIVATE", "source_PRIVATE", "fingerprint_PRIVATE", "张三"] {
                XCTAssertFalse(json.contains(forbidden), "\(tool.name): \(forbidden)")
            }
        }
    }
    func testSummaryDoesNotInheritQueryLimitAndDeletedRowsAreExcluded() throws {
        var ledger = ctx.ledger
        let account = ledger.accounts[0]
        ledger.entries = (0..<60).map { _ in Entry(date: ctx.now, amount: 100, accountID: account.id, title: "饭", category: "餐饮") }
        var removed = ledger.entries[0]; removed.id = UUID(); removed.deletedAt = ctx.now; ledger.entries.append(removed)
        let context = ToolContext(ledger: ledger, now: ctx.now)
        let summary = try ReadOnlyTool.summarize.run(.object([:]), context)
        XCTAssertEqual(cents(summary["spending"]), 6000); XCTAssertEqual(summary["count"], .number(60))
        XCTAssertEqual(summary["entry_ids"]?.arrayValue?.count, 50)
        let query = try ReadOnlyTool.queryEntries.run(.object(["limit": .number(50)]), context)
        XCTAssertEqual(query["entries"]?.arrayValue?.count, 50)
    }
}
