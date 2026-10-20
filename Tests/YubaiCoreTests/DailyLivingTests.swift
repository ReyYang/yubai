import XCTest
@testable import YubaiCore

final class DailyLivingTests: XCTestCase {
    private let now = Dates.parse("2026-10-20 12:00:00")!
    private func dailyLedger() -> Ledger {
        var ledger = Ledger(); ledger.accounts = [Account(name: "卡", balance: 1_000_000, at: now)]
        for day in 0..<90 {
            ledger.entries.append(Entry(date: Dates.addDays(-day, to: now), amount: 3000, accountID: ledger.accounts[0].id, title: "日常"))
        }
        return ledger
    }
    func testMedianEstimateResistsLargeAndOccasionalSpending() {
        var ledger = dailyLedger(); let account = ledger.accounts[0].id
        XCTAssertEqual(Finance.estimatedDailyLiving(ledger, now: now), 3000)
        for day in 0..<90 {
            ledger.entries.append(Entry(date: Dates.addDays(-day, to: now), amount: 50001, accountID: account, title: "大额"))
        }
        ledger.entries.append(Entry(date: now, amount: 50000, accountID: account, title: "偶尔购物"))
        ledger.entries.append(Entry(date: Dates.addDays(-90, to: now), amount: 20000, accountID: account, title: "窗口外"))
        ledger.entries.append(Entry(date: Dates.addDays(1, to: now), amount: 20000, accountID: account, title: "未来"))
        XCTAssertEqual(Finance.estimatedDailyLiving(ledger, now: now), 3000)
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
    func testFundsAndForecastUseEstimateUnlessUserHasSetValue() {
        var ledger = dailyLedger()
        ledger.profile.floorAmount = 12345
        let estimated = Finance.funds(ledger, now: now)
        XCTAssertTrue(estimated.livingEstimated); XCTAssertEqual(estimated.living, 3000 * 90)
        XCTAssertEqual(estimated.emergency, 12345)
        XCTAssertFalse(estimated.warnings.contains { $0.contains("日常生活预留") })
        XCTAssertEqual(estimated.points.first!.conservative - estimated.points.last!.conservative, 3000 * 90)
        ledger.preferences.dailyLiving = 4567
        let chosen = Finance.funds(ledger, now: now)
        XCTAssertFalse(chosen.livingEstimated); XCTAssertEqual(chosen.living, 4567 * 90)
        XCTAssertEqual(chosen.points.first!.conservative - chosen.points.last!.conservative, 4567 * 90)
    }
    func testEmptySparseAndDeletedHistory() {
        var ledger = Ledger(); XCTAssertEqual(Finance.estimatedDailyLiving(ledger, now: now), 0)
        ledger.accounts = [Account(name: "卡")]
        ledger.entries = [Entry(date: now, amount: 20000, accountID: ledger.accounts[0].id, title: "一笔")]
        XCTAssertEqual(Finance.estimatedDailyLiving(ledger, now: now), 0)
        ledger = dailyLedger()
        for i in ledger.entries.indices { ledger.entries[i].deletedAt = now }
        XCTAssertEqual(Finance.estimatedDailyLiving(ledger, now: now), 0)
    }
}
