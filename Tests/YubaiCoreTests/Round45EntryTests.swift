import XCTest
@testable import YubaiCore

final class Round45EntryTests: XCTestCase {
    let now = Round45Fixture.now
    func testCategoryHintThreeTwoOneAndNoTimeFallback() {
        var l = Round45Fixture.ledger(); l.entries = []
        XCTAssertNil(EntryHistory.categoryHint(purpose: "   ", nature: .expense, in: l, now: now))
        XCTAssertNotNil(EntryHistory.categoryHint(purpose: "地铁", nature: .expense, in: l, now: now))
        let a = Round45Fixture.entry(l, amount: 1000, date: "2026-11-17", title: "Lunch", category: "餐饮")
        var b = a; b.id = UUID(); b.date = Dates.addDays(1, to: a.date)
        var c = b; c.id = UUID(); c.date = Dates.addDays(1, to: b.date); c.category = "交通"
        l.entries = [a]
        XCTAssertEqual(EntryHistory.categoryHint(purpose: " Lunch ", nature: .expense, in: l, now: now)?.category, "餐饮")
        l.entries = [b, c]; XCTAssertNil(EntryHistory.categoryHint(purpose: "Lunch", nature: .expense, in: l, now: now))
        l.entries = [a, b, c]; XCTAssertEqual(EntryHistory.categoryHint(purpose: "Lunch", nature: .expense, in: l, now: now)?.category, "餐饮")
        c.category = "购物"; b.category = "交通"; l.entries = [a, b, c]
        XCTAssertNil(EntryHistory.categoryHint(purpose: "Lunch", nature: .expense, in: l, now: now))
        XCTAssertNil(EntryHistory.categoryHint(purpose: "Unseen purpose", nature: .expense, in: l, now: now))
    }
    func testRecallFiltersCaseInsensitivelyBeforeLimitAndKeepsLatestAmount() {
        var l = Round45Fixture.ledger(); l.entries = [Round45Fixture.entry(l, amount: 1000, date: "2026-11-17", title: "Coffee"), Round45Fixture.entry(l, amount: 1500, date: "2026-11-19", title: "Coffee"), Round45Fixture.entry(l, amount: 2000, date: "2026-11-19", title: "Lunch")]
        let rows = EntryHistory.recalls(matching: "COF", nature: .expense, in: l, now: now, limit: 1)
        XCTAssertEqual(rows.count, 1); XCTAssertEqual(rows[0].purpose, "Coffee"); XCTAssertEqual(rows[0].count, 2); XCTAssertEqual(rows[0].entry.amount, 1500)
        XCTAssertTrue(EntryHistory.recalls(matching: "zzz", nature: .expense, in: l, now: now).isEmpty)
    }
    func testRepeatsExcludeImportsBillsDeletedAndOldEntries() {
        var l = Round45Fixture.ledger(); l.entries = []
        for title in ["Lunch", "Imported", "Bill", "Old"] {
            for i in 0..<3 {
                var e = Round45Fixture.entry(l, amount: 1000, date: "2026-11-19", title: title)
                e.recordedAt = now; e.date = Dates.addDays(-i, to: e.date)
                if title == "Imported" { e.batchID = UUID() }
                if title == "Bill" { e.planID = l.plans[1].id; e.occurrence = l.plans[1].dueDate }
                if title == "Old" { e.date = Dates.addDays(-31, to: now) }
                l.entries.append(e)
            }
        }
        let rows = EntryHistory.repeats(in: l, now: now)
        XCTAssertEqual(rows.count, 1); XCTAssertEqual(rows[0].purpose, "Lunch"); XCTAssertEqual(rows[0].amount, 1000)
        XCTAssertEqual(rows, EntryHistory.repeats(in: l, now: now))
        XCTAssertTrue(EntryHistory.repeats(in: l, now: now, limit: 0).isEmpty)
    }
    func testBudgetProposalTopThreeFlexibleCategoriesAndRounding() {
        var l = Round45Fixture.ledger(); l.cycleAnchor = .calendarMonth; l.entries = []
        for month in [8, 9, 10] {
            for (category, amount) in [("餐饮", 7600 as Int64), ("购物", 6500), ("交通", 5000), ("娱乐", 1000)] {
                l.entries.append(Round45Fixture.entry(l, amount: amount, date: "2026-\(String(format: "%02d", month))-05", category: category))
            }
            var bill = Round45Fixture.entry(l, amount: 999_000, date: "2026-\(String(format: "%02d", month))-06", category: "居家")
            bill.planID = l.plans[1].id; bill.occurrence = l.plans[1].dueDate; l.entries.append(bill)
            var reserved = bill; reserved.id = UUID(); reserved.planID = nil; reserved.fromReserve = true; reserved.category = "健康"; l.entries.append(reserved)
        }
        let parts = SpendingParts.proposal(ledger: l, now: now)
        XCTAssertEqual(parts.map(\.name), ["餐饮", "购物", "交通"]); XCTAssertEqual(parts.map(\.amount), [10_000, 5000, 5000])
        XCTAssertEqual(parts, SpendingParts.proposal(ledger: l, now: now)); XCTAssertTrue(l.spendingParts.isEmpty)
    }
    func testSuggestedMonthlyUsesCompletedCyclesAndFloorsHundreds() throws {
        var l = Round45Fixture.ledger(); l.cycleAnchor = .calendarMonth; l.entries = []
        XCTAssertNil(Reserve.suggestedMonthly(l, now: now))
        for month in [8, 9, 10] {
            let text = "2026-\(String(format: "%02d", month))-05"
            l.entries.append(Round45Fixture.entry(l, amount: 100_000, date: text, nature: .income))
            l.entries.append(Round45Fixture.entry(l, amount: 7600, date: text))
            var bill = Round45Fixture.entry(l, amount: 1000, date: text); bill.planID = l.plans[1].id; bill.occurrence = l.plans[1].dueDate; l.entries.append(bill)
        }
        let suggestion = try XCTUnwrap(Reserve.suggestedMonthly(l, now: now))
        XCTAssertEqual(suggestion.average, 91_400); XCTAssertEqual(suggestion.suggestion, 90_000)
    }
    func testWhereSpentSeparatesFixedAndUnitemizedButKeepsReserveInSpending() {
        var l = Round45Fixture.ledger(); l.entries = []
        let flex = Round45Fixture.entry(l, amount: 1000, date: "2026-11-19")
        var fixed = flex; fixed.id = UUID(); fixed.amount = 2000; fixed.planID = l.plans[1].id; fixed.occurrence = l.plans[1].dueDate
        var reserve = flex; reserve.id = UUID(); reserve.amount = 3000; reserve.fromReserve = true
        var unknown = flex; unknown.id = UUID(); unknown.amount = 400; unknown.category = Classification.pendingCategory; unknown.spreadFrom = Dates.day(now)
        unknown.date = now
        var refund = flex; refund.id = UUID(); refund.amount = 500; refund.nature = .refund; refund.relatedEntryID = fixed.id
        l.entries = [flex, fixed, reserve, unknown, refund]
        let interval = DateInterval(start: Round45Fixture.date("2026-11-10"), end: Dates.addDays(1, to: now))
        let whereSpent = Finance.whereSpent(l, during: interval)
        XCTAssertEqual(whereSpent.fixed.map(\.id), [fixed.id]); XCTAssertEqual(whereSpent.fixedTotal, 1500)
        XCTAssertEqual(whereSpent.unitemized, 400); XCTAssertEqual(whereSpent.flexible.reduce(0) { $0 + $1.amount }, 4000)
        XCTAssertEqual(Finance.cashFlow(l, during: interval).spending, 5900)
    }
    func testComparisonUsesCycleDayOffsetAndLargestTwoDeltas() throws {
        var l = Round45Fixture.ledger(); l.cycleAnchor = .calendarMonth
        l.entries = [Round45Fixture.entry(l, amount: 10_000, date: "2026-10-03"), Round45Fixture.entry(l, amount: 2000, date: "2026-10-04", category: "购物"), Round45Fixture.entry(l, amount: 900_000, date: "2026-10-25"), Round45Fixture.entry(l, amount: 30_000, date: "2026-11-03"), Round45Fixture.entry(l, amount: 20_000, date: "2026-11-04", category: "购物")]
        let comparison = try XCTUnwrap(Finance.cycleComparison(l, now: now))
        XCTAssertEqual(comparison.spent, 50_000); XCTAssertEqual(comparison.previousSameDay, 12_000)
        XCTAssertEqual(comparison.changes.map(\.category), ["餐饮", "购物"]); XCTAssertEqual(comparison.changes.map(\.delta), [20_000, 18_000])
        XCTAssertEqual(comparison, Finance.cycleComparison(l, now: now))
        l.entries.removeAll { $0.date < Round45Fixture.date("2026-11-01") }
        XCTAssertNil(Finance.cycleComparison(l, now: now))
    }
    func testSetupItems() {
        var l = Ledger(); XCTAssertTrue(Setup.done(l, now: now).isEmpty)
        l.accounts = Round45Fixture.ledger().accounts; XCTAssertEqual(Setup.done(l, now: now), [.hand])
        l.cycleAnchor = .calendarMonth; l.savingRule = .fixed(0)
        l.plans = [Plan(title: "Bill", amount: 100, dueDate: now)]
        XCTAssertEqual(Setup.done(l, now: now), Set(Setup.Item.allCases))
    }
}
