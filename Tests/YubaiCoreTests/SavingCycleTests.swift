import XCTest
@testable import YubaiCore

final class SavingCycleTests: XCTestCase {
    func date(_ text: String) -> Date { Dates.parse(text)! }
    let now = Dates.parse("2026-11-09 12:00")!
    func ledger(_ balance: Int64 = 1_000_000) -> Ledger {
        var ledger = Ledger()
        ledger.accounts = [Account(name: "银行卡", balance: balance, at: Dates.parse("2026-10-01")!)]
        return ledger
    }
    func testCalendarAndPaydayBoundaries() {
        var l = ledger()
        let month = Finance.cycle(in: l, now: now)
        XCTAssertEqual(month.start, date("2026-11-01")); XCTAssertEqual(month.end, date("2026-11-30")); XCTAssertFalse(month.payday)
        l.plans = [Plan(title: "工资", amount: 800_000, dueDate: date("2026-10-15"), frequency: .monthly, inflow: true, nature: .income)]
        XCTAssertEqual(Finance.cycle(in: l, now: now).start, date("2026-10-15"))
        XCTAssertEqual(Finance.cycle(in: l, now: now).end, date("2026-11-14"))
        XCTAssertEqual(Finance.cycle(in: l, now: date("2026-11-15")).start, date("2026-11-15"))
        l.plans[0].dueDate = date("2026-01-31")
        XCTAssertEqual(Finance.cycle(in: l, now: date("2026-03-01")).start, date("2026-02-28"))
        XCTAssertEqual(Finance.cycle(in: l, now: date("2026-03-01")).end, date("2026-03-30"))
    }
    func testSkippedWeeklyPaydaysNeverPutCycleStartInTheFuture() {
        var l = ledger()
        var plan = Plan(title: "工资", amount: 100_000, dueDate: date("2026-11-02"), frequency: .weekly, inflow: true, nature: .income)
        plan.skippedOccurrences = [date("2026-11-09"), date("2026-11-16"), date("2026-11-23")]
        l.plans = [plan]
        let cycle = Finance.cycle(in: l, now: date("2026-11-03"))
        XCTAssertEqual(cycle.start, date("2026-11-02")); XCTAssertEqual(cycle.end, date("2026-11-29"))
    }
    func testFiveRowsIdentityAndOnlyUnpaidBillsWithinCycle() {
        var l = ledger(); l.fixedSavings = 200_000; l.savingRule = .fixed(100_000)
        let account = l.accounts[0].id
        l.entries = [Entry(date: date("2026-11-02"), amount: 90_000, nature: .income, accountID: account, title: "收入"),
                     Entry(date: date("2026-11-03"), amount: 20_000, accountID: account, title: "支出"),
                     Entry(date: date("2026-11-04"), amount: 5000, nature: .refund, accountID: account, title: "退款"),
                     Entry(date: date("2026-11-05"), amount: 30_000, nature: .unknownIn, accountID: account, title: "未明进账")]
        l.goals = [Goal(title: "旅行", target: 30_000, reserved: 20_000)]
        l.plans = [Plan(title: "月末账单", amount: 40_000, dueDate: date("2026-11-30")), Plan(title: "下月账单", amount: 50_000, dueDate: date("2026-12-01"))]
        for rule: SavingRule? in [nil, .fixed(100_000), .share(20)] {
            l.savingRule = rule
            let f = Finance.funds(l, now: now)
            XCTAssertEqual(f.liquidStart + f.cycleIncome - f.savingTarget - f.cycleSpent - f.dueRest, f.available)
            XCTAssertEqual(f.cycleIncome, 90_000); XCTAssertEqual(f.cycleSpent, 15_000); XCTAssertEqual(f.dueRest, 40_000)
            XCTAssertEqual(f.living, 0); XCTAssertEqual(f.dailyAllowance, max(0, f.available) / 22)
        }
        var paid = Entry(date: date("2026-11-06"), amount: 40_000, accountID: account, title: "月末账单")
        paid.planID = l.plans[0].id; paid.occurrence = date("2026-11-30"); l.entries.append(paid)
        XCTAssertEqual(Finance.funds(l, now: now).dueRest, 0)
    }
    func testShareRoundingAndCacheInvalidation() {
        var l = ledger(); l.savingRule = .share(10)
        l.entries = [Entry(date: now, amount: 1005, nature: .income, accountID: l.accounts[0].id, title: "进账")]
        XCTAssertEqual(Finance.funds(l, now: now).savingTarget, 101)
        l.savingRule = .share(20)
        XCTAssertEqual(Finance.funds(l, now: now).savingTarget, 201)
        let before = Finance.funds(l, now: now).available
        l.fixedSavings = 1000
        XCTAssertEqual(Finance.funds(l, now: now).available, before - 1000)
    }
    func testShortfallAndPurchaseCaps() {
        var l = ledger(150_000); l.savingRule = .fixed(200_000)
        let f = Finance.funds(l, now: now)
        XCTAssertEqual(f.available, -50_000); XCTAssertEqual(f.savingShortfall, 50_000); XCTAssertEqual(f.dailyAllowance, 0)
        XCTAssertEqual(PurchaseBounds.compute(ledger: l, amount: 1000, title: "耳机", now: now).allowedVerdicts, [.wait, .skip])
        XCTAssertEqual(PurchaseBounds.compute(ledger: l, amount: 150_001, title: "耳机", now: now).allowedVerdicts, [.skip])
        l.accounts[0].anchorBalance = -50_000
        XCTAssertEqual(Finance.funds(l, now: now).savingShortfall, 200_000)
    }
    func testCloseCyclesMergesOnlyLatestAndIsIdempotent() throws {
        var l = ledger(150_000); l.savingRule = .fixed(200_000); l.fixedSavings = 20_000
        l.entries = [Entry(date: date("2026-11-03"), amount: 50_000, nature: .income, accountID: l.accounts[0].id, title: "本月收入")]
        Savings.closeCycles(&l, now: now)
        XCTAssertEqual(l.savingHistory.count, 1); XCTAssertEqual(l.savingHistory[0].cycleStart, date("2026-10-01"))
        XCTAssertEqual(l.savingHistory[0].saved, 130_000); XCTAssertEqual(l.fixedSavings, 150_000)
        let closed = l; Savings.closeCycles(&l, now: now); XCTAssertEqual(l, closed)
        try l.validate()
        let encoded = try JSONEncoder().encode(l)
        var restored = try JSONDecoder().decode(Ledger.self, from: encoded)
        Savings.closeCycles(&restored, now: now); XCTAssertEqual(restored.fixedSavings, 150_000)
    }
    func testHistoryFromAnotherTimeZoneRemainsValidAndDoesNotCloseTwice() throws {
        var l = ledger(); l.savingRule = .fixed(100_000)
        Savings.closeCycles(&l, now: now)
        l.savingHistory[0].cycleStart = l.savingHistory[0].cycleStart.addingTimeInterval(8 * 3600)
        l.savingHistory[0].cycleEnd = l.savingHistory[0].cycleEnd.addingTimeInterval(8 * 3600)
        try l.validate()
        let before = l
        Savings.closeCycles(&l, now: now)
        XCTAssertEqual(l, before)
    }
    func testClosePaydayCycleAndRewindReconciliationAndFuturePayments() {
        var l = ledger(300_000); l.savingRule = .share(20)
        l.plans = [Plan(title: "工资", amount: 100_000, dueDate: date("2026-09-15"), frequency: .monthly, inflow: true, nature: .income)]
        l.entries = [Entry(date: date("2026-10-15"), amount: 100_000, nature: .income, accountID: l.accounts[0].id, title: "工资")]
        Savings.closeCycles(&l, now: date("2026-11-15 12:00"))
        XCTAssertEqual(l.savingHistory.last?.cycleStart, date("2026-10-15"))
        XCTAssertEqual(l.savingHistory.last?.target, 20_000); XCTAssertEqual(l.fixedSavings, 20_000)
        Savings.closeCycles(&l, now: date("2026-11-16")); XCTAssertEqual(l.savingHistory.count, 1)
    }
    func testLegacyFloorMigrationAndValidation() throws {
        var l = ledger(); l.profile.floorAmount = 30_000
        let restored = try JSONDecoder().decode(Ledger.self, from: JSONEncoder().encode(l))
        XCTAssertEqual(restored.fixedSavings, 30_000); XCTAssertEqual(restored.profile.floorAmount, 30_000)
        l.fixedSavings = 0
        XCTAssertEqual(try JSONDecoder().decode(Ledger.self, from: JSONEncoder().encode(l)).fixedSavings, 0)
        l.savingRule = .share(91); XCTAssertThrowsError(try l.validate())
        l.savingRule = .fixed(-1); XCTAssertThrowsError(try l.validate())
        l.savingRule = nil; l.fixedSavings = -1; XCTAssertThrowsError(try l.validate())
    }
    func testInsightsTimelineUsesExactlyTheFundsCycle() {
        var l = ledger()
        l.entries = ["2026-08-15", "2026-09-15", "2026-10-13"].map {
            Entry(date: date($0), amount: 800_000, nature: .income, accountID: l.accounts[0].id, title: "公司工资")
        }
        for hasPlan in [false, true] {
            if hasPlan { l.plans = [Plan(title: "工资", amount: 800_000, dueDate: date("2026-08-15"), frequency: .monthly, inflow: true, nature: .income)] }
            let funds = Finance.funds(l, now: now)
            let timeline = Finance.cashTimeline(l, funds: funds, now: now, alignToFundsCycle: true)
            XCTAssertEqual(timeline.defaultStart, funds.cycleStart)
            XCTAssertEqual(timeline.end, funds.cycleEnd)
            XCTAssertNil(timeline.floor)
        }
    }
    func testSharePreviewMatchesFullApplyAndEdit() throws {
        var l = ledger(); l.savingRule = .share(30)
        let draft = EntryDraft(date: now, amount: 1005, amountConfirmed: true, nature: .income, accountID: l.accounts[0].id, title: "收入")
        let change = ChangeSet(source: "手动", reason: "记一笔", items: [.addEntry(draft)])
        let preview = try ManualBookkeeping.available(after: change, in: l, now: now)
        try change.apply(to: &l)
        XCTAssertEqual(preview, Finance.funds(l, now: now).available)
        var edited = l.entries[0]; edited.amount = 2005
        let editedPreview = try ManualBookkeeping.available(after: edited, in: l, now: now)
        try ManualBookkeeping.edit(edited, in: &l)
        XCTAssertEqual(editedPreview, Finance.funds(l, now: now).available)
    }
    func testEntryHintNormalRestrainBigAndOver() {
        var l = ledger(100_000)
        XCTAssertEqual(EntryHint.make(ledger: l, amount: 1000, category: "餐饮", isFixedBill: false, now: now), .normal(after: 99_000, daily: 4500, over: false))
        XCTAssertEqual(EntryHint.make(ledger: l, amount: 30_000, category: "数码", isFixedBill: false, now: now), .big(after: 70_000, daily: 3181, over: false))
        XCTAssertEqual(EntryHint.make(ledger: l, amount: 110_000, category: "数码", isFixedBill: true, now: now), .normal(after: -10_000, daily: 0, over: true))
        XCTAssertEqual(EntryHint.make(ledger: l, amount: 110_000, category: "数码", isFixedBill: false, now: now), .big(after: -10_000, daily: 0, over: true))
        XCTAssertEqual(EntryHint.make(ledger: l, amount: 110_000, category: "工资", isFixedBill: false, now: now, nature: .income), .normal(after: 210_000, daily: 9545, over: false))
        l.profile.restrain = [ProfileArea(title: "外卖", match: .init(categories: ["餐饮"]), softLimit: .init(perWeekCount: 2))]
        XCTAssertEqual(EntryHint.make(ledger: l, amount: 3000, category: "餐饮", isFixedBill: false, now: now), .restrain(areaTitle: "外卖", countThisWeek: 1, limit: 2, weekSpent: 3000))
    }
}

final class SavingRuleLaterTests: XCTestCase {
    func testRuleSetAfterAClosedCycleIsNotAppliedRetroactively() throws {
        var ledger = Ledger()
        let calendar = Dates.calendar
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 12))!
        Savings.closeCycles(&ledger, now: now)
        XCTAssertEqual(ledger.savingHistory.count, 1)
        XCTAssertFalse(ledger.savingHistory[0].tracked)
        XCTAssertNil(ledger.fixedSavings)
        ledger.savingRule = .fixed(200_000)
        Savings.closeCycles(&ledger, now: now)
        XCTAssertEqual(ledger.savingHistory.count, 1)
        XCTAssertNil(ledger.fixedSavings)
        let data = try JSONEncoder().encode(ledger)
        let decoded = try JSONDecoder().decode(Ledger.self, from: data)
        XCTAssertFalse(decoded.savingHistory[0].tracked)
    }
}


extension SavingCycleTests {
    func testCycleAnchorRoundTripLegacyEqualityAndInvalidValue() throws {
        var l = ledger()
        let automatic = l
        XCTAssertNil(try JSONDecoder().decode(Ledger.self, from: JSONEncoder().encode(l)).cycleAnchor)
        for anchor in [CycleAnchor.calendarMonth, .payday] {
            l.cycleAnchor = anchor
            XCTAssertNotEqual(l, automatic)
            try l.validate()
            XCTAssertEqual(try JSONDecoder().decode(Ledger.self, from: JSONEncoder().encode(l)), l)
        }
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(l)) as? [String: Any])
        object.removeValue(forKey: "cycleAnchor")
        XCTAssertNil(try JSONDecoder().decode(Ledger.self, from: JSONSerialization.data(withJSONObject: object)).cycleAnchor)
        object["cycleAnchor"] = "invalid"
        XCTAssertThrowsError(try JSONDecoder().decode(Ledger.self, from: JSONSerialization.data(withJSONObject: object)))
    }

    func testExplicitCalendarAnchorOverridesSalaryAndInvalidatesFunds() {
        var l = ledger(); l.savingRule = .share(20)
        l.plans = [Plan(title: "工资", amount: 800_000, dueDate: date("2026-09-15"), frequency: .monthly, inflow: true, nature: .income)]
        l.spendingParts = [SpendingPart(name: "餐饮", amount: 50_000, categories: ["餐饮"])]
        l.entries = [Entry(date: date("2026-10-20"), amount: 100_000, nature: .income, accountID: l.accounts[0].id, title: "收入"),
                     Entry(date: date("2026-10-21"), amount: 12_000, accountID: l.accounts[0].id, title: "吃饭", category: "餐饮")]
        XCTAssertEqual(Finance.funds(l, now: now).cycleIncome, 100_000)
        XCTAssertEqual(SpendingParts.summary(l, now: now).parts[0].spent, 12_000)
        let automatic = l
        l.cycleAnchor = .calendarMonth
        let funds = Finance.funds(l, now: now)
        XCTAssertFalse(funds.cycleIsPayday)
        XCTAssertEqual(funds.cycleStart, date("2026-11-01")); XCTAssertEqual(funds.cycleEnd, date("2026-11-30"))
        XCTAssertEqual(funds.cycleIncome, 0); XCTAssertEqual(funds.savingTarget, 0)
        XCTAssertEqual(SpendingParts.summary(l, now: now).parts[0].spent, 0)
        XCTAssertEqual(WeeklyLetter.available(l, at: now), funds.available)
        l.cycleAnchor = .payday
        XCTAssertEqual(Finance.funds(l, now: now), Finance.funds(automatic, now: now))
    }

    func testExplicitPaydayNeedsMonthlyIncomeAndPreservesEndOfMonth() {
        var l = ledger(); l.cycleAnchor = .payday
        XCTAssertFalse(Finance.cycle(in: l, now: now).payday)
        l.plans = [Plan(title: "每周收入", amount: 5000, dueDate: date("2026-11-01"), frequency: .weekly, inflow: true, nature: .income)]
        XCTAssertFalse(Finance.cycle(in: l, now: now).payday)
        l.plans.append(Plan(title: "工资", amount: 800_000, dueDate: date("2026-01-31"), frequency: .monthly, inflow: true, nature: .income))
        let cycle = Finance.cycle(in: l, now: date("2026-03-01"))
        XCTAssertTrue(cycle.payday); XCTAssertEqual(cycle.start, date("2026-02-28")); XCTAssertEqual(cycle.end, date("2026-03-30"))
        l.plans[1].active = false
        XCTAssertFalse(Finance.cycle(in: l, now: now).payday)
    }

    func testCalendarAnchorClosesCalendarPeriodWithSalaryOnlyOnce() {
        var l = ledger(); l.cycleAnchor = .calendarMonth; l.savingRule = .fixed(10_000)
        l.plans = [Plan(title: "工资", amount: 800_000, dueDate: date("2026-09-15"), frequency: .monthly, inflow: true, nature: .income)]
        Savings.closeCycles(&l, now: now)
        XCTAssertEqual(l.savingHistory.first?.cycleStart, date("2026-10-01"))
        XCTAssertEqual(l.savingHistory.first?.cycleEnd, date("2026-10-31"))
        let saved = l; Savings.closeCycles(&l, now: now); XCTAssertEqual(l, saved)
    }
}

extension SavingCycleTests {
    func testChangingCycleAnchorNeverMergesAnOverlappingClosedPeriodTwice() {
        var l = ledger(); l.savingRule = .fixed(10_000); l.cycleAnchor = .calendarMonth
        l.plans = [Plan(title: "工资", amount: 800_000, dueDate: date("2026-09-10"), frequency: .monthly, inflow: true, nature: .income)]
        Savings.closeCycles(&l, now: date("2026-11-20"))
        let base = l.fixedSavings, history = l.savingHistory
        l.cycleAnchor = .payday
        Savings.closeCycles(&l, now: date("2026-11-20"))
        XCTAssertEqual(l.fixedSavings, base); XCTAssertEqual(l.savingHistory, history)
        Savings.closeCycles(&l, now: date("2026-12-20"))
        XCTAssertEqual(l.savingHistory.count, 2)
        XCTAssertEqual(l.savingHistory.last?.cycleStart, date("2026-11-10"))
        XCTAssertEqual(l.savingHistory.last?.cycleEnd, date("2026-12-09"))
        let closed = l; Savings.closeCycles(&l, now: date("2026-12-20")); XCTAssertEqual(l, closed)
        l.cycleAnchor = .calendarMonth
        Savings.closeCycles(&l, now: date("2026-12-20"))
        XCTAssertEqual(l.fixedSavings, closed.fixedSavings); XCTAssertEqual(l.savingHistory, closed.savingHistory)
    }
}
