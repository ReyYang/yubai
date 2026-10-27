import XCTest
@testable import YubaiCore

final class DailyLivingTests: XCTestCase {
    private let now = Dates.parse("2026-10-20 12:00:00")!
    private func dailyLedger() -> Ledger {
        var ledger = Ledger(); ledger.accounts = [Account(name: "卡", balance: 1_000_000, at: now)]
        for day in 1...90 {
            ledger.entries.append(Entry(date: Dates.addDays(-day, to: now), amount: 3000, accountID: ledger.accounts[0].id, title: "日常"))
        }
        return ledger
    }
    func testMedianEstimateResistsLargeAndOccasionalSpending() {
        var ledger = dailyLedger(); let account = ledger.accounts[0].id
        XCTAssertEqual(Finance.estimatedDailyLiving(ledger, now: now), 3000)
        for day in 1...90 {
            ledger.entries.append(Entry(date: Dates.addDays(-day, to: now), amount: 50001, accountID: account, title: "大额"))
        }
        ledger.entries.append(Entry(date: Dates.addDays(-1, to: now), amount: 50000, accountID: account, title: "偶尔购物"))
        ledger.entries.append(Entry(date: Dates.addDays(-91, to: now), amount: 20000, accountID: account, title: "窗口外"))
        ledger.entries.append(Entry(date: Dates.addDays(1, to: now), amount: 20000, accountID: account, title: "未来"))
        XCTAssertEqual(Finance.estimatedDailyLiving(ledger, now: now), 3000)
    }
    func testWindowIncludesNinetiethDayAndAllOfYesterday() {
        var ledger = Ledger(); ledger.accounts = [Account(name: "卡", at: now)]
        let totals: [Int64] = [5000, 1000, 2000, 3000, 4000, 6000, 7000, 8000, 9000]
        for (window, amount) in totals.enumerated() {
            let date = window == 8 ? Dates.parse("2026-10-19 23:59:59")! : Dates.addDays(-90 + window * 10, to: Dates.day(now))
            ledger.entries.append(Entry(date: date, amount: amount, accountID: ledger.accounts[0].id, title: "窗口消费"))
        }
        ledger.entries.append(Entry(date: Dates.addDays(-91, to: now), amount: 50_000, accountID: ledger.accounts[0].id, title: "窗口外"))
        ledger.entries.append(Entry(date: Dates.addDays(1, to: now), amount: 50_000, accountID: ledger.accounts[0].id, title: "未来"))
        XCTAssertEqual(Finance.estimatedDailyLiving(ledger, now: Dates.day(now)), 500)
        XCTAssertEqual(Finance.estimatedDailyLiving(ledger, now: now), 500)
    }
    func testTodaysExpenseIncomeAndRefundsLeaveEstimateAndReserveStable() {
        var ledger = Ledger(); ledger.accounts = [Account(name: "卡", balance: 100_000, at: Dates.parse("2026-10-20 08:30")!)]
        // The latest window is the median: including today's ¥32 would move it.
        let totals: [Int64] = [1000, 2000, 3000, 4000, 6000, 7000, 8000, 9000, 5000]
        for (window, amount) in totals.enumerated() {
            ledger.entries.append(Entry(date: Dates.addDays(-85 + window * 10, to: Dates.day(now)), amount: amount, accountID: ledger.accounts[0].id, title: "窗口消费"))
        }
        let before = Finance.funds(ledger, now: now)
        XCTAssertEqual(Finance.estimatedDailyLiving(ledger, now: now), 500)
        for nature in [Nature.expense, .income, .refund] {
            var changed = ledger
            var entry = Entry(date: Dates.day(now), amount: 3200, nature: nature, accountID: ledger.accounts[0].id, title: "今天补记")
            entry.recordedAt = now; changed.entries.append(entry)
            let after = Finance.funds(changed, now: now)
            XCTAssertEqual(Finance.estimatedDailyLiving(changed, now: now), 500); XCTAssertEqual(after.living, before.living)
            XCTAssertEqual(after.available - before.available, nature.inflow ? 3200 : -3200)
            if nature == .refund {
                changed.entries[changed.entries.count - 1].relatedEntryID = ledger.entries.last!.id
                XCTAssertEqual(Finance.estimatedDailyLiving(changed, now: now), 500)
                XCTAssertEqual(Finance.funds(changed, now: now).available, before.available + 3200)
            }
            XCTAssertEqual(Finance.estimatedDailyLiving(changed, now: Dates.parse("2026-10-20 23:59:59")!), 500)
        }
    }
    func testPlansRentTransfersAndRefundsAreExcludedOrOffset() {
        var ledger = dailyLedger(); let original = ledger.entries
        let account = ledger.accounts[0].id
        let plan = Plan(title: "固定付款", amount: 1000, dueDate: Dates.addDays(-90, to: now), frequency: .monthly)
        ledger.plans = [plan]
        ledger.rents = [Rent(monthlyTotal: 100000, personalShare: 50000, startDate: Dates.addDays(-90, to: now), nextDueDate: now)]
        for row in original {
            var refund = Entry(date: row.date, amount: 1000, nature: .refund, accountID: account, title: "退款")
            refund.relatedEntryID = row.id; ledger.entries.append(refund)
            var linked = Entry(date: row.date, amount: 1000, accountID: account, title: "固定付款")
            linked.planID = plan.id; linked.occurrence = row.date; ledger.entries.append(linked)
            linked.id = UUID(); linked.planID = nil; linked.occurrence = nil; linked.rentID = ledger.rents[0].id; linked.rentPeriod = row.date; ledger.entries.append(linked)
            ledger.entries.append(Entry(date: row.date, amount: 1000, nature: .transfer, accountID: account, title: "内部移动"))
        }
        XCTAssertEqual(Finance.estimatedDailyLiving(ledger, now: now), 2000)
        for row in original { ledger.entries.append(Entry(date: row.date, amount: 1000, nature: .refund, accountID: account, title: "未关联退款")) }
        XCTAssertEqual(Finance.estimatedDailyLiving(ledger, now: now), 1000)
    }
    func testFundsAndForecastIgnoreLegacyPreferencesAndTreatProfileFloorAsTarget() {
        var ledger = dailyLedger()
        ledger.profile.floorAmount = 12345
        let estimated = Finance.funds(ledger, now: now)
        XCTAssertTrue(estimated.livingEstimated); XCTAssertEqual(estimated.living, 3000 * 90)
        XCTAssertEqual(estimated.emergency, 12345)
        XCTAssertFalse(estimated.warnings.contains { $0.contains("日常生活预留") })
        XCTAssertEqual(estimated.points.first!.conservative - estimated.points.last!.conservative, 3000 * 90)
        ledger.preferences.dailyLiving = 4567
        ledger.preferences.horizonDays = 7; ledger.preferences.emergencyReserve = 99999
        let chosen = Finance.funds(ledger, now: now)
        XCTAssertTrue(chosen.livingEstimated); XCTAssertEqual(chosen.living, 3000 * 90)
        XCTAssertEqual(chosen.available, estimated.available); XCTAssertEqual(chosen.emergency, 12345)
        XCTAssertEqual(chosen.points.count, 91)
        XCTAssertEqual(chosen.points.first!.conservative - chosen.points.last!.conservative, 3000 * 90)
        ledger.profile.floorAmount = nil
        let unset = Finance.funds(ledger, now: now)
        XCTAssertEqual(unset.emergency, 0); XCTAssertNil(unset.floorRoom); XCTAssertEqual(unset.available, estimated.available)
        XCTAssertEqual(unset.points.map(\.conservative), estimated.points.map(\.conservative))
        XCTAssertEqual(unset.points.map(\.expected), estimated.points.map(\.expected))
    }
    func testEmptySparseAndDeletedHistory() {
        var ledger = Ledger(); XCTAssertEqual(Finance.estimatedDailyLiving(ledger, now: now), 0)
        ledger.accounts = [Account(name: "卡")]
        ledger.entries = [Entry(date: Dates.addDays(-1, to: now), amount: 20000, accountID: ledger.accounts[0].id, title: "一笔")]
        XCTAssertEqual(Finance.estimatedDailyLiving(ledger, now: now), 0)
        ledger = dailyLedger()
        for i in ledger.entries.indices { ledger.entries[i].deletedAt = now }
        XCTAssertEqual(Finance.estimatedDailyLiving(ledger, now: now), 0)
    }
}
