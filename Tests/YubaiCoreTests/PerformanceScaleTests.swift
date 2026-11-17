import XCTest
@testable import YubaiCore

final class PerformanceScaleTests: XCTestCase {
    private let now = Dates.parse("2026-11-05 12:00:00")!
    private func fixture() -> Ledger {
        var ledger = Ledger()
        ledger.accounts = [Account(name: "Bank", balance: 2_000_000, at: Dates.addDays(-45, to: now)),
                           Account(name: "Wallet", kind: .cash, balance: 90_000, at: now),
                           Account(name: "Credit", kind: .credit, balance: -80_000, at: Dates.addDays(-120, to: now))]
        ledger.accounts[1].archived = true
        let bank = ledger.accounts[0].id, wallet = ledger.accounts[1].id
        ledger.entries = (0..<4200).map { index in
            var entry = Entry(date: Dates.addDays(index % 150 - 140, to: now), amount: Int64(index % 70 + 1) * 100,
                              nature: index % 11 == 0 ? .income : .expense, accountID: bank, title: "Synthetic", category: "餐饮")
            if index % 17 == 0 { entry.nature = .transfer; entry.otherAccountID = wallet; entry.otherDate = entry.date.addingTimeInterval(86400) }
            if index % 19 == 0 { entry.deletedAt = now }
            return entry
        }
        ledger.plans = [Plan(title: "Bill", amount: 20_000, dueDate: Dates.addDays(-60, to: now), frequency: .monthly),
                        Plan(title: "Variable", amount: 12_000, dueDate: Dates.addDays(-30, to: now), frequency: .monthly),
                        Plan(title: "Salary", amount: 600_000, dueDate: Dates.addDays(10, to: now), frequency: .monthly, inflow: true, nature: .income)]
        ledger.plans[1].estimated = true
        var refund = Entry(date: Dates.addDays(-2, to: now), amount: 50, nature: .refund, accountID: bank, title: "Refund")
        refund.relatedEntryID = ledger.entries[1].id
        ledger.entries[2] = refund
        return ledger
    }
    func test4200EntryIncrementalPreviewMatchesFullApplyAndFunds() throws {
        let ledger = fixture(); try ledger.validate()
        let before = try LedgerCodec.encodeMetadata(ledger)
        let natures: [Nature] = [.expense, .income, .transfer, .refund, .unknownIn, .repayment]
        for nature in natures {
            for offset in [-120, -90, -89, -30, -1, 0, 1] {
                for amount in [Int64(1), 50_000, 50_001] {
                    var draft = EntryDraft(date: Dates.addDays(offset, to: now), amount: amount, amountConfirmed: true,
                                           nature: nature, accountID: ledger.accounts[nature == .expense ? 2 : 0].id, title: "Preview", category: "餐饮")
                    if nature.paired { draft.otherAccountID = ledger.accounts[nature == .repayment ? 2 : 1].id }
                    let change = ChangeSet(source: "手动", reason: "记一笔", items: [.addEntry(draft)])
                    var full = ledger; try change.apply(to: &full)
                    XCTAssertEqual(try ManualBookkeeping.available(after: change, in: ledger, now: now), Finance.funds(full, now: now).available, "\(nature) \(offset) \(amount)")
                }
            }
        }
        for plan in ledger.plans {
            for amount in [Int64(100), plan.amount, plan.amount + 100] {
                var draft = EntryDraft(date: Dates.addDays(1, to: now), amount: amount, amountConfirmed: true,
                                       nature: plan.nature, accountID: ledger.accounts[0].id, title: "Linked", category: "餐饮")
                draft.planID = plan.id; draft.occurrence = plan.dueDate
                let change = ChangeSet(source: "手动", reason: "记一笔", items: [.addEntry(draft)])
                var full = ledger; try change.apply(to: &full)
                XCTAssertEqual(try ManualBookkeeping.available(after: change, in: ledger, now: now), Finance.funds(full, now: now).available)
            }
        }
        XCTAssertEqual(try LedgerCodec.encodeMetadata(ledger), before)
    }
    func test4200EntryEditPreviewMatchesFullEditIncludingRefundAndFixedFlows() throws {
        var ledger = fixture()
        let now = self.now
        let rent = Rent(title: "Rent", monthlyTotal: 40_000, personalShare: 20_000, startDate: Dates.addDays(-60, to: now), nextDueDate: Dates.addDays(-30, to: now), monthsPerPayment: 1, receiveDay: 5)
        ledger.rents = [rent]
        var linked = ledger.entries[3]; linked.planID = ledger.plans[0].id; linked.occurrence = ledger.plans[0].dueDate
        ledger.entries[3] = linked
        var rented = ledger.entries[4]; rented.rentID = rent.id; rented.rentPeriod = Dates.day(now)
        ledger.entries[4] = rented
        for index in [1, 2, 3, 4, 5] {
            for offset in [-90, -1, 0, 1] {
                var edited = ledger.entries[index]
                edited.amount = max(100, edited.amount + 100); edited.date = Dates.addDays(offset, to: now)
                var full = ledger; try ManualBookkeeping.edit(edited, in: &full)
                XCTAssertEqual(try ManualBookkeeping.available(after: edited, in: ledger, now: now), Finance.funds(full, now: now).available)
            }
        }
    }
    func testIncrementalEditRejectsInvalidRefundsAndLinksLikeFullEdit() throws {
        let ledger = fixture()
        var belowRefund = ledger.entries[1]; belowRefund.amount = 1
        var excessRefund = ledger.entries[2]; excessRefund.amount = ledger.entries[1].amount + 1
        var missingOriginal = ledger.entries[2]; missingOriginal.relatedEntryID = UUID()
        var wrongNature = ledger.entries[1]; wrongNature.nature = .income
        var missingPlan = ledger.entries[3]; missingPlan.planID = UUID(); missingPlan.occurrence = now
        for edited in [belowRefund, excessRefund, missingOriginal, wrongNature, missingPlan] {
            var full = ledger
            XCTAssertThrowsError(try ManualBookkeeping.edit(edited, in: &full))
            XCTAssertThrowsError(try ManualBookkeeping.available(after: edited, in: ledger, now: now))
        }
    }
    func test4200EntryLivingMatchesOriginalAlgorithm() throws {
        let priorZone = NSTimeZone.default
        defer { NSTimeZone.default = priorZone }
        for zone in ["Asia/Shanghai", "America/New_York"] {
            NSTimeZone.default = TimeZone(identifier: zone)!
            var ledger = fixture()
            for hasSalary in [false, true] {
                if !hasSalary { ledger.plans.removeAll { $0.inflow } }
                else { ledger.plans.append(Plan(title: "Salary", amount: 600_000, dueDate: Dates.addDays(10, to: now), frequency: .monthly, inflow: true, nature: .income)) }
                let funds = Finance.funds(ledger, now: now)
                XCTAssertEqual(Finance.estimatedDailyLiving(ledger, now: now), Finance.referenceEstimatedDailyLiving(ledger, now: now))
            }
        }
    }
    func testValidationCacheAlsoTracksTimeZoneForCalendarConstraints() throws {
        let prior = NSTimeZone.default
        defer { NSTimeZone.default = prior }
        NSTimeZone.default = TimeZone(secondsFromGMT: 0)!
        var ledger = Ledger(); ledger.lastSubcategoryBatchDay = "2011-12-30"
        try ledger.validate()
        NSTimeZone.default = TimeZone(identifier: "Pacific/Apia")!
        var fresh = ledger; fresh.calculations = LedgerCalculations()
        XCTAssertEqual((try? ledger.validate()) != nil, (try? fresh.validate()) != nil)
    }
    func testCalculationCacheInvalidatesAcrossCopiesNestedEditsAndTimeBoundaries() throws {
        let ledger = fixture(); try ledger.validate()
        var draft = EntryDraft(date: now, amount: 100, amountConfirmed: true, nature: .expense, accountID: ledger.accounts[0].id, title: "Test", category: "餐饮")
        let change = ChangeSet(source: "手动", reason: "记一笔", items: [.addEntry(draft)])
        _ = try ManualBookkeeping.available(after: change, in: ledger, now: now)
        var copy = ledger; copy.entries[0].amount = 0
        XCTAssertThrowsError(try copy.validate()); XCTAssertNoThrow(try ledger.validate())
        copy = ledger; copy.lastSubcategoryBatchDay = "invalid"; XCTAssertThrowsError(try copy.validate())
        for time in [now.addingTimeInterval(-100), now.addingTimeInterval(86400 * 2)] {
            var full = ledger; try change.apply(to: &full)
            XCTAssertEqual(try ManualBookkeeping.available(after: change, in: ledger, now: time), Finance.funds(full, now: time).available)
        }
        var changed = ledger; changed.accounts[0].anchorBalance += 1000
        draft.amount += 100
        var full = changed; try change.apply(to: &full)
        XCTAssertEqual(try ManualBookkeeping.available(after: change, in: changed, now: now), Finance.funds(full, now: now).available)
    }
}

// Frozen pre-optimization implementation: independent equivalence oracle.
private extension Finance {
    static func referenceEstimatedDailyLiving(_ ledger: Ledger, now: Date) -> Int64 {
        let end = Dates.day(now); let start = Dates.addDays(-90, to: end)
        let entries = ledger.activeEntries.filter { $0.date < end }
        var refunds: [UUID: Int64] = [:]
        for e in entries where e.nature == .refund {
            if let id = e.relatedEntryID { refunds[id, default: 0] += e.amount }
        }
        var windows = Array(repeating: Int64(0), count: 9)
        for e in entries where e.date >= start {
            let day = Dates.calendar.dateComponents([.day], from: start, to: Dates.day(e.date)).day ?? -1
            guard (0..<90).contains(day) else { continue }
            if e.nature == .expense, e.planID == nil, e.rentID == nil, e.amount <= 50_000 {
                windows[day / 10] += max(0, e.amount - refunds[e.id, default: 0])
            } else if e.nature == .refund, e.relatedEntryID == nil {
                windows[day / 10] -= e.amount
            }
        }
        return min(Money.limit / 366, max(0, windows.sorted()[4]) / 10)
    }

}
