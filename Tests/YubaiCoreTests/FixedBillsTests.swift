import XCTest
@testable import YubaiCore

final class FixedBillsTests: XCTestCase {
    private let now = Dates.parse("2026-10-22 14:00:00")!
    private func date(_ text: String) -> Date { Dates.parse(text)! }
    private func fixture() -> Ledger {
        var ledger = Ledger(); ledger.accounts = [Account(name: "银行卡", balance: 2_000_000, at: date("2026-07-01"))]
        return ledger
    }
    private func salary() -> Plan {
        Plan(title: "工资", amount: 800_000, dueDate: date("2026-10-10 18:00:00"), frequency: .monthly, inflow: true, category: "工资", nature: .income)
    }
    private func payment(_ plan: Plan, on day: Date, amount: Int64? = nil, in ledger: Ledger) -> Entry {
        var entry = Entry(date: day, amount: amount ?? plan.amount, nature: plan.nature, accountID: ledger.accounts[0].id, title: plan.title, category: plan.category)
        entry.planID = plan.id; entry.occurrence = Dates.day(day); return entry
    }
    private func dailySpending(in ledger: inout Ledger) {
        ledger.entries += (1...90).map { Entry(date: Dates.addDays(-$0, to: Dates.day(now)), amount: 1000, accountID: ledger.accounts[0].id, title: "午饭") }
    }
    func testPaydayWindowIncludesOverdueAndPaydayBillsButKeepsFullForecast() throws {
        var ledger = fixture(); dailySpending(in: &ledger)
        let salary = salary()
        ledger.plans = [salary, Plan(title: "逾期", amount: 1000, dueDate: date("2026-10-20")),
                        Plan(title: "房租", amount: 2000, dueDate: date("2026-11-09")),
                        Plan(title: "订阅", amount: 3000, dueDate: date("2026-11-10 23:00:00")),
                        Plan(title: "之后付款", amount: 9_000_000, dueDate: date("2026-11-11"))]
        // Receiving the next salary early cannot move the schedule's next payday.
        ledger.entries.append(payment(salary, on: date("2026-11-10"), in: ledger))
        let next = try XCTUnwrap(Finance.nextPayday(in: ledger, now: now))
        XCTAssertEqual(next.date, date("2026-11-10")); XCTAssertEqual(next.title, "工资")
        let funds = Finance.funds(ledger, now: now)
        XCTAssertEqual(funds.horizonEnd, next.date); XCTAssertEqual(funds.horizonDays, 19)
        XCTAssertEqual(funds.paydayTitle, "工资"); XCTAssertEqual(funds.payday, next.date)
        XCTAssertEqual(funds.committed, 6000); XCTAssertEqual(funds.living, 19_000)
        XCTAssertEqual(funds.available, funds.cash - 6000 - 19_000)
        XCTAssertEqual(funds.occurrences.filter { !$0.inflow }.count, 4)
        XCTAssertEqual(funds.points.count, 91); XCTAssertEqual(funds.expectedIncome, 2_400_000)
        XCTAssertLessThan(funds.points.last!.conservative, 0)
        XCTAssertTrue(ButlerCards.detect(ledger, now: now).contains { $0.kind == .shortfall && $0.facts.contains(CardFact("付款", "之后付款")) })
        let tool = try ReadOnlyTool.getFunds.run(.object([:]), ToolContext(ledger: ledger, now: now))
        XCTAssertEqual(tool["horizon_days"], .number(19)); XCTAssertEqual(tool["payday"], .string("2026-11-10"))
        XCTAssertEqual(tool["payday_title"], .string("工资"))
        XCTAssertTrue(Finance.assessPurchase(ledger, amount: 100, now: now).facts.contains { $0.hasPrefix("发工资前已知付款 ") })
    }
    func testNoPaydayMatchesNinetyDayCalculationAndCustomHorizon() throws {
        var ledger = fixture(); dailySpending(in: &ledger)
        ledger.plans = [Plan(title: "房租", amount: 100_000, dueDate: date("2026-10-10"), frequency: .monthly)]
        ledger.goals = [Goal(title: "旅行", target: 20_000, reserved: 10_000)]; ledger.profile.floorAmount = 50_000
        for days in [90, 20] {
            let funds = Finance.funds(ledger, now: now, days: days)
            let occurrences = Finance.occurrences(in: ledger, now: now, days: days)
            let committed = occurrences.reduce(Int64(0)) { $0 + $1.amount }
            let living = Finance.estimatedDailyLiving(ledger, now: now) * Int64(days)
            XCTAssertNil(funds.payday); XCTAssertNil(funds.paydayTitle)
            XCTAssertEqual(funds.horizonDays, days); XCTAssertEqual(funds.horizonEnd, Dates.addDays(days, to: Dates.day(now)))
            XCTAssertEqual(funds.committed, committed); XCTAssertEqual(funds.living, living)
            XCTAssertEqual(funds.available, funds.cash - funds.debt - committed - funds.goals - funds.emergency - living - funds.uncertainInflow)
            XCTAssertEqual(funds.points.last!.conservative, funds.available)
        }
        XCTAssertTrue(Finance.assessPurchase(ledger, amount: 100, now: now).facts.contains { $0.hasPrefix("到 1月20日已知付款 ") })
        let tool = try ReadOnlyTool.getFunds.run(.object([:]), ToolContext(ledger: ledger, now: now))
        XCTAssertEqual(tool["horizon_days"], .number(90)); XCTAssertNil(tool["payday"]); XCTAssertNil(tool["payday_title"])
    }
    func testPaydaySkipsEndedOnceInactiveExhaustedAndDistantIncome() {
        var ledger = fixture()
        var ended = salary(); ended.endDate = date("2026-10-10 18:00:00")
        var inactive = salary(); inactive.active = false
        var exhausted = salary(); exhausted.installments = 1
        var once = salary(); once.frequency = .once; once.dueDate = date("2026-11-01")
        let distant = Plan(title: "年终奖", amount: 1000, dueDate: date("2027-02-01"), frequency: .yearly, inflow: true, nature: .income)
        var other = salary(); other.nature = .contribution
        var outflow = salary(); outflow.inflow = false
        ledger.plans = [ended, inactive, exhausted, once, distant, other, outflow]
        XCTAssertNil(Finance.nextPayday(in: ledger, now: now))
        ledger.plans.append(salary())
        XCTAssertEqual(Finance.nextPayday(in: ledger, now: date("2026-11-10 08:00:00"))?.date, date("2026-12-10"))
        let earlier = Plan(title: "兼职", amount: 1000, dueDate: date("2026-10-25"), frequency: .monthly, inflow: true, nature: .income)
        ledger.plans.append(earlier)
        XCTAssertEqual(Finance.nextPayday(in: ledger, now: now)?.title, "兼职")
    }
    func testPaydayWindowIsIndependentOfRequestedChartLength() {
        var ledger = fixture(); dailySpending(in: &ledger)
        ledger.plans = [salary(), Plan(title: "订阅", amount: 3000, dueDate: date("2026-11-09"))]
        let funds = Finance.funds(ledger, now: now, days: 7)
        XCTAssertEqual(funds.points.count, 8); XCTAssertFalse(funds.occurrences.contains { $0.title == "订阅" })
        XCTAssertEqual(funds.horizonDays, 19); XCTAssertEqual(funds.committed, 3000); XCTAssertEqual(funds.living, 19_000)
    }
    func testRecurringIncomeChangesNinetyDayFallbackAfterSaveAndStopRestoresIt() throws {
        var ledger = fixture()
        XCTAssertNil(Finance.funds(ledger, now: now).payday)
        XCTAssertEqual(Finance.funds(ledger, now: now).horizonDays, 90)
        let plan = salary()
        try ChangeSet(source: "用户操作", reason: "添加工资", items: [.addPlan(plan)]).apply(to: &ledger)
        ledger = try LedgerCodec.decode(LedgerCodec.encode(ledger))
        let funds = Finance.funds(ledger, now: now)
        XCTAssertEqual(funds.payday, date("2026-11-10")); XCTAssertEqual(funds.paydayTitle, "工资")
        XCTAssertEqual(funds.horizonDays, 19)
        try ChangeSet(source: "用户操作", reason: "停掉工资", items: [.endPlan(plan.id, now)]).apply(to: &ledger)
        XCTAssertNil(Finance.funds(ledger, now: now).payday)
        XCTAssertEqual(Finance.funds(ledger, now: now).horizonDays, 90)
    }
    func testStoppedWeeklyBillsKeepPaidAndDueRowsThroughStopDayOnly() throws {
        var ledger = fixture()
        var plan = Plan(title: "每周订阅", amount: 1000, dueDate: date("2026-10-01"), frequency: .weekly)
        plan.accountID = ledger.accounts[0].id; plan.autoPay = true; ledger.plans = [plan]
        ledger.entries = [payment(plan, on: plan.dueDate, in: ledger), payment(plan, on: date("2026-10-15"), in: ledger)]
        let originalEntries = ledger.entries
        XCTAssertTrue(FixedFlows.month(containing: now, in: ledger).occurrences.contains { $0.date == date("2026-10-29") })
        try ChangeSet(source: "用户操作", reason: "停掉", items: [.endPlan(plan.id, now)]).apply(to: &ledger)
        let month = FixedFlows.month(containing: now, in: ledger)
        XCTAssertEqual(month.occurrences.map(\.date), ["2026-10-01", "2026-10-08", "2026-10-15", "2026-10-22"].map(date))
        XCTAssertEqual(month.occurrences.map(\.state), [.paid, .due, .paid, .due])
        XCTAssertEqual(month.remainingOutflow, 2000); XCTAssertEqual(month.remainingInflow, 0)
        XCTAssertTrue(FixedFlows.month(containing: date("2026-11-01"), in: ledger).occurrences.isEmpty)
        XCTAssertTrue(Finance.occurrences(in: ledger, now: now).allSatisfy { $0.date <= now })
        XCTAssertEqual(ledger.entries, originalEntries)
        let stopped = try XCTUnwrap(FixedFlowArrangement.stopped(in: ledger, now: now).first)
        XCTAssertEqual(stopped.id, plan.id); XCTAssertEqual(stopped.title, plan.title)
        XCTAssertEqual(stopped.stoppedAt, now); XCTAssertEqual(stopped.amount, 1000); XCTAssertFalse(stopped.canEnd)
        XCTAssertTrue(FixedFlowArrangement.rows(in: ledger, now: now).isEmpty)
        let automatic = try XCTUnwrap(FixedFlows.autoSettle(in: ledger, now: date("2026-11-01")))
        try automatic.apply(to: &ledger)
        XCTAssertEqual(ledger.entries.suffix(2).map(\.occurrence), [date("2026-10-08"), date("2026-10-22")])
        XCTAssertNil(FixedFlows.autoSettle(in: ledger, now: date("2026-11-01")))
    }
    func testStoppingBeforeFirstDueDatePersistsDateAndRemovesThisMonthOccurrence() throws {
        var ledger = fixture()
        let plan = Plan(title: "尚未开始", amount: 8000, dueDate: date("2026-10-29"), frequency: .monthly)
        let rent = Rent(title: "下月房租", monthlyTotal: 20_000, personalShare: 10_000, startDate: date("2026-11-01"), nextDueDate: date("2026-11-01"))
        ledger.plans = [plan]; ledger.rents = [rent]
        try ChangeSet(source: "用户操作", reason: "停掉", items: [.endPlan(plan.id, now), .endPlan(rent.id, now)]).apply(to: &ledger)
        ledger = try LedgerCodec.decode(LedgerCodec.encode(ledger))
        XCTAssertTrue(FixedFlows.month(containing: now, in: ledger).occurrences.isEmpty)
        XCTAssertTrue(Finance.occurrences(in: ledger, now: now).isEmpty)
        XCTAssertNil(FixedFlows.autoSettle(in: ledger, now: date("2026-12-01")))
        let rows = FixedFlowArrangement.stopped(in: ledger, now: now)
        XCTAssertEqual(Set(rows.map(\.id)), [plan.id, rent.id])
        XCTAssertTrue(rows.allSatisfy { $0.stoppedAt == now && !$0.canEnd })
        XCTAssertEqual(rows.first { $0.id == plan.id }?.amount, 8000)
        XCTAssertEqual(rows.first { $0.id == rent.id }?.amount, 60_000)
        XCTAssertTrue(FixedFlowArrangement.stopped(in: ledger, now: now.addingTimeInterval(-1)).isEmpty)
        let change = ChangeSet(source: "用户操作", reason: "再次停掉", items: [.endPlan(plan.id, date("2026-10-23"))])
        XCTAssertEqual(try change.apply(to: &ledger).count, 1); XCTAssertEqual(ledger.plans[0].stoppedAt, now)
    }
    func testStoppedListIncludesLegacyEndDatesAndLatestEstimatedAmount() throws {
        var ledger = fixture(); var plan = salary()
        plan.endDate = date("2026-10-20"); plan.estimated = true
        var future = salary(); future.endDate = date("2026-11-20")
        ledger.plans = [plan, future]
        ledger.entries = [payment(plan, on: date("2026-10-10"), amount: 750_000, in: ledger)]
        let rows = FixedFlowArrangement.stopped(in: ledger, now: now)
        XCTAssertEqual(rows.map(\.id), [plan.id]); XCTAssertEqual(rows[0].stoppedAt, plan.endDate)
        XCTAssertEqual(rows[0].amount, 750_000); XCTAssertTrue(rows[0].inflow)
        XCTAssertEqual(FixedFlows.month(containing: now, in: ledger).occurrences.first { $0.planID == plan.id }?.state, .paid)
    }
    func testLegacyInactiveArrangementsRemainQueryableWithUnknownStopDate() throws {
        var ledger = fixture(); var plan = salary(); plan.active = false
        var rent = Rent(monthlyTotal: 20_000, personalShare: 10_000, startDate: now, nextDueDate: now); rent.active = false
        ledger.plans = [plan]; ledger.rents = [rent]
        ledger = try LedgerCodec.decode(LedgerCodec.encode(ledger))
        let rows = FixedFlowArrangement.stopped(in: ledger, now: now)
        XCTAssertEqual(Set(rows.map(\.id)), [plan.id, rent.id]); XCTAssertTrue(rows.allSatisfy { $0.stoppedAt == nil })
        XCTAssertTrue(FixedFlows.month(containing: now, in: ledger).occurrences.isEmpty)
    }
    func testResumeStoppedPlanPreservesPaymentsScheduleAndSettingsThroughPersistence() throws {
        var ledger = fixture()
        var plan = Plan(title: "每周订阅", amount: 1000, dueDate: date("2026-10-01"), frequency: .weekly)
        plan.accountID = ledger.accounts[0].id; plan.autoPay = true; plan.autoPaySince = plan.dueDate
        plan.installments = 8; plan.estimated = true; plan.note = "保留原安排"
        ledger.plans = [plan]; ledger.entries = [payment(plan, on: plan.dueDate, amount: 1200, in: ledger)]
        let originalEntries = ledger.entries
        try ChangeSet(source: "用户操作", reason: "停掉", items: [.endPlan(plan.id, now)]).apply(to: &ledger)
        let stoppedSnapshot = try LedgerCodec.encode(ledger)
        let change = try FixedFlows.resume(id: plan.id, in: ledger, now: now)
        XCTAssertEqual(change.source, "用户操作"); XCTAssertEqual(change.reason, "恢复「每周订阅」")
        XCTAssertEqual(change.createdAt, now); XCTAssertEqual(change.preview(in: ledger), ["恢复「每周订阅」"])
        let decoded = try JSONDecoder().decode(ChangeSet.self, from: JSONEncoder().encode(change))
        XCTAssertEqual(decoded, change); XCTAssertTrue(try decoded.apply(to: &ledger).isEmpty)
        ledger = try LedgerCodec.decode(LedgerCodec.encode(ledger))
        XCTAssertEqual(ledger.plans, [plan]); XCTAssertEqual(ledger.entries, originalEntries)
        XCTAssertTrue(FixedFlowArrangement.stopped(in: ledger, now: now).isEmpty)
        XCTAssertEqual(FixedFlowArrangement.rows(in: ledger, now: now).map(\.id), [plan.id])
        let rows = FixedFlows.month(containing: now, in: ledger).occurrences
        XCTAssertEqual(rows.first?.state, .paid); XCTAssertEqual(rows.first?.amount, 1200)
        XCTAssertEqual(rows.last?.date, date("2026-10-29")); XCTAssertEqual(rows.last?.state, .upcoming)
        XCTAssertEqual(rows.last?.installment?.index, 5)
        XCTAssertEqual(try change.apply(to: &ledger).count, 1)
        let undone = try LedgerCodec.decode(stoppedSnapshot)
        XCTAssertEqual(FixedFlowArrangement.stopped(in: undone, now: now).map(\.id), [plan.id])
        XCTAssertFalse(FixedFlows.month(containing: now, in: undone).occurrences.contains { $0.date == date("2026-10-29") })
    }
    func testResumePlansAndRentsStoppedBeforeTheirFirstDateRestoresOriginalArrangements() throws {
        var ledger = fixture()
        let plan = Plan(title: "尚未开始", amount: 8000, dueDate: date("2026-10-29"), frequency: .monthly)
        let rent = Rent(title: "下月房租", monthlyTotal: 20_000, personalShare: 10_000, startDate: date("2026-11-01"), nextDueDate: date("2026-11-01"))
        ledger.plans = [plan]; ledger.rents = [rent]
        try ChangeSet(source: "用户操作", reason: "停掉", items: [.endPlan(plan.id, now), .endPlan(rent.id, now)]).apply(to: &ledger)
        XCTAssertFalse(ledger.plans[0].active); XCTAssertFalse(ledger.rents[0].active)
        for id in [plan.id, rent.id] { try FixedFlows.resume(id: id, in: ledger, now: now).apply(to: &ledger) }
        ledger = try LedgerCodec.decode(LedgerCodec.encode(ledger))
        XCTAssertEqual(ledger.plans, [plan]); XCTAssertEqual(ledger.rents, [rent])
        XCTAssertTrue(FixedFlowArrangement.stopped(in: ledger, now: now).isEmpty)
        XCTAssertEqual(Set(FixedFlowArrangement.rows(in: ledger, now: now).map(\.id)), [plan.id, rent.id])
        XCTAssertTrue(FixedFlows.month(containing: now, in: ledger).occurrences.contains { $0.planID == plan.id })
        XCTAssertTrue(FixedFlows.month(containing: date("2026-11-01"), in: ledger).occurrences.contains { $0.rentID == rent.id })
    }
    func testResumeLegacyEndedAndInactiveArrangements() throws {
        var ledger = fixture(); var plan = salary(); plan.endDate = date("2026-10-20")
        var rent = Rent(monthlyTotal: 20_000, personalShare: 10_000, startDate: date("2026-09-01"), nextDueDate: date("2026-10-01"))
        rent.endDate = date("2026-10-20")
        var inactive = salary(); inactive.active = false
        var inactiveRent = rent; inactiveRent.id = UUID(); inactiveRent.endDate = nil; inactiveRent.active = false
        ledger.plans = [plan, inactive]; ledger.rents = [rent, inactiveRent]
        for id in [plan.id, inactive.id, rent.id, inactiveRent.id] { try FixedFlows.resume(id: id, in: ledger, now: now).apply(to: &ledger) }
        XCTAssertTrue(ledger.plans.allSatisfy { $0.active && $0.endDate == nil && $0.stoppedAt == nil })
        XCTAssertTrue(ledger.rents.allSatisfy { $0.active && $0.endDate == nil && $0.stoppedAt == nil })
        XCTAssertEqual(FixedFlowArrangement.rows(in: ledger, now: now).count, 4)
    }
    func testResumeRejectsMissingActiveAndFutureEndedPlansAndKeepsChangesAtomic() throws {
        var ledger = fixture(); let active = salary(); var future = salary(); future.endDate = date("2026-11-20")
        var stopped = salary(); stopped.stoppedAt = now; stopped.endDate = now
        ledger.plans = [active, future, stopped]
        for id in [UUID(), active.id, future.id] { XCTAssertThrowsError(try FixedFlows.resume(id: id, in: ledger, now: now)) }
        var stale = ChangeSet(source: "用户操作", reason: "恢复", items: [.resumePlan(UUID()), .resumePlan(active.id), .resumePlan(future.id)])
        stale.createdAt = now
        let before = ledger
        XCTAssertEqual(try stale.apply(to: &ledger).count, 3); XCTAssertEqual(ledger, before)
        var change = try FixedFlows.resume(id: stopped.id, in: ledger, now: now)
        change.items.append(.addEntry(EntryDraft(date: now, amount: 100, accountID: ledger.accounts[0].id, title: "未确认")))
        XCTAssertThrowsError(try change.apply(to: &ledger)); XCTAssertEqual(ledger, before)
    }
    func testSettleOutflowMovesCashOnceRemovesOverdueAndSnapshotUndoRestoresState() throws {
        var ledger = fixture(); let plan = Plan(title: "房租", amount: 100_000, dueDate: date("2026-10-10"))
        ledger.plans = [plan]
        let before = ledger; let undoSnapshot = try LedgerCodec.encode(ledger); let funds = Finance.funds(ledger, now: now)
        XCTAssertTrue(Finance.occurrences(in: ledger, now: now)[0].overdue)
        let change = try FixedFlows.settle(planID: plan.id, occurrence: plan.dueDate, in: ledger, now: now)
        XCTAssertEqual(change.source, "用户操作"); XCTAssertEqual(change.reason, "「房租」10月10日这期付了"); XCTAssertEqual(change.items.count, 1)
        XCTAssertTrue(change.preview(in: ledger)[0].contains("关联为 2026-10-10 房租"))
        XCTAssertTrue(try change.apply(to: &ledger).isEmpty)
        XCTAssertEqual(ledger.entries.count, 1); XCTAssertEqual(ledger.entries[0].planID, plan.id)
        XCTAssertEqual(ledger.entries[0].occurrence, Dates.day(plan.dueDate)); XCTAssertEqual(ledger.entries[0].title, plan.title)
        XCTAssertEqual(ledger.entries[0].date, date("2026-10-10 12:00:00"))
        XCTAssertTrue(Finance.occurrences(in: ledger, now: now).isEmpty)
        let after = Finance.funds(ledger, now: now)
        XCTAssertEqual(after.cash, funds.cash - plan.amount); XCTAssertEqual(after.committed, 0)
        XCTAssertEqual(after.available, funds.available); XCTAssertFalse(after.warnings.contains { $0.contains("已到期") })
        XCTAssertEqual(try change.apply(to: &ledger).count, 1); XCTAssertEqual(ledger.entries.count, 1)
        XCTAssertThrowsError(try FixedFlows.settle(planID: plan.id, occurrence: plan.dueDate, in: ledger, now: now))
        // AppStore undo persists the entire ledger saved before applying a ChangeSet.
        ledger = try LedgerCodec.decode(undoSnapshot)
        XCTAssertEqual(ledger, before); XCTAssertEqual(Finance.funds(ledger, now: now).available, funds.available)
        XCTAssertTrue(Finance.occurrences(in: ledger, now: now)[0].overdue)
    }
    func testSettleInflowAndEarlyPaymentUseActualRecordingDay() throws {
        var ledger = fixture(); var plan = salary(); plan.frequency = .once
        ledger.plans = [plan]; let before = Finance.funds(ledger, now: now)
        let change = try FixedFlows.settle(planID: plan.id, occurrence: plan.dueDate, in: ledger, now: now)
        XCTAssertEqual(change.reason, "「工资」10月10日这期收到了")
        try change.apply(to: &ledger)
        XCTAssertEqual(ledger.entries[0].nature, .income); XCTAssertEqual(ledger.entries[0].category, "工资奖金"); XCTAssertEqual(ledger.entries[0].subcategory, "工资")
        XCTAssertEqual(Finance.funds(ledger, now: now).cash, before.cash + plan.amount)
        XCTAssertEqual(Finance.funds(ledger, now: now).available, before.available + plan.amount)
        XCTAssertTrue(Finance.occurrences(in: ledger, now: now).isEmpty)
        let future = Plan(title: "提前付", amount: 1000, dueDate: date("2026-10-25")); ledger.plans.append(future)
        try FixedFlows.settle(planID: future.id, occurrence: future.dueDate, in: ledger, now: now).apply(to: &ledger)
        XCTAssertEqual(ledger.entries.last?.date, now); XCTAssertEqual(ledger.entries.last?.occurrence, future.dueDate)
    }
    func testSettleDefaultsToRemainingAndValidatesAccountAndSchedule() throws {
        var ledger = fixture(); var plan = Plan(title: "分次付", amount: 10_000, dueDate: date("2026-10-20"))
        plan.accountID = ledger.accounts[0].id; ledger.plans = [plan]
        ledger.entries = [payment(plan, on: plan.dueDate, amount: 3000, in: ledger)]
        let before = Finance.funds(ledger, now: now)
        try FixedFlows.settle(planID: plan.id, occurrence: plan.dueDate, in: ledger, now: now).apply(to: &ledger)
        XCTAssertEqual(ledger.entries.last?.amount, 7000); XCTAssertEqual(Finance.funds(ledger, now: now).cash, before.cash - 7000)
        XCTAssertEqual(Finance.funds(ledger, now: now).available, before.available)
        XCTAssertThrowsError(try FixedFlows.settle(planID: plan.id, occurrence: Dates.addDays(1, to: plan.dueDate), in: ledger, now: now))
        var empty = Ledger(); empty.plans = [Plan(title: "无账户", amount: 1000, dueDate: now)]
        XCTAssertThrowsError(try FixedFlows.settle(planID: empty.plans[0].id, occurrence: now, in: empty, now: now)) { error in
            XCTAssertEqual(error as? YubaiError, .invalid("先添加一个收付款账户。"))
        }
    }
    func testManualBookkeepingCanLinkAndDraftRejectsInvalidOrDoubleLinksAtomically() throws {
        var ledger = fixture(); var plan = Plan(title: "房租", amount: 10_000, dueDate: date("2026-10-22"), frequency: .monthly)
        plan.accountID = ledger.accounts[0].id; plan.installments = 2; ledger.plans = [plan]
        let change = try ManualBookkeeping.change(amount: 10_000, nature: .expense, accountID: ledger.accounts[0].id,
                                                   day: now, purpose: "房租", category: "居住", link: (plan.id, plan.dueDate), now: now)
        try change.apply(to: &ledger)
        XCTAssertEqual(ledger.entries[0].planID, plan.id); XCTAssertEqual(ledger.entries[0].occurrence, plan.dueDate)
        XCTAssertEqual(Finance.occurrences(in: ledger, now: now).count, 1)
        let duplicate = ChangeSet(source: "用户操作", reason: "再次关联", items: [.linkPlan(entry: ledger.entries[0].id, plan: plan.id, occurrence: date("2026-11-22"))])
        XCTAssertEqual(try duplicate.apply(to: &ledger).count, 1); XCTAssertEqual(ledger.entries[0].occurrence, plan.dueDate)
        var draft = EntryDraft(date: now, amount: 100, amountConfirmed: true, accountID: ledger.accounts[0].id, title: "房租", planID: plan.id, occurrence: plan.dueDate)
        ledger.accounts.append(Account(name: "零钱", at: now))
        let before = ledger
        func rejected(_ draft: EntryDraft) {
            XCTAssertThrowsError(try ChangeSet(source: "用户操作", reason: "无效关联", items: [.addEntry(draft)]).apply(to: &ledger))
            XCTAssertEqual(ledger, before)
        }
        draft.nature = .income; rejected(draft); draft.nature = .expense
        draft.accountID = ledger.accounts[1].id; rejected(draft); draft.accountID = plan.accountID!
        draft.occurrence = date("2026-12-22"); rejected(draft)
        draft.occurrence = date("2026-10-23"); rejected(draft)
        draft.occurrence = nil; rejected(draft)
        draft.planID = nil; draft.occurrence = plan.dueDate; rejected(draft)
    }
    func testSuggestionsAmountDateNameDirectionAndPaidExclusion() throws {
        var ledger = fixture(); var plan = Plan(title: "房 租", amount: 10_000, dueDate: date("2026-10-20"))
        plan.accountID = ledger.accounts[0].id; ledger.plans = [plan]
        func suggestions(_ amount: Int64 = 10_000, _ purpose: String = "别的", _ day: Date? = nil, _ nature: Nature = .expense, _ account: UUID? = nil) -> [Occurrence] {
            FixedFlows.suggestions(amount: amount, nature: nature, purpose: purpose, day: day ?? now, accountID: account, in: ledger, now: now)
        }
        XCTAssertEqual(suggestions().map(\.planID), [plan.id])
        XCTAssertEqual(suggestions(10_000, "", date("2026-10-23")).count, 1)
        XCTAssertTrue(suggestions(10_000, "房租", date("2026-10-24")).isEmpty)
        XCTAssertEqual(suggestions(11_000, "十月房租").count, 1); XCTAssertEqual(suggestions(9000, "房租").count, 1)
        XCTAssertTrue(suggestions(11_001, "房租").isEmpty); XCTAssertTrue(suggestions(9000, "吃饭").isEmpty)
        XCTAssertTrue(suggestions(10_000, "房租", nil, .income).isEmpty); XCTAssertTrue(suggestions(10_000, "房租", nil, .transfer).isEmpty)
        XCTAssertTrue(suggestions(10_000, "房租", nil, .expense, UUID()).isEmpty)
        ledger.plans[0].estimated = true
        XCTAssertEqual(suggestions(50_000, "房租").count, 1); XCTAssertTrue(suggestions(50_000, "吃饭").isEmpty)
        try FixedFlows.settle(planID: plan.id, occurrence: plan.dueDate, in: ledger, now: now).apply(to: &ledger)
        XCTAssertTrue(suggestions().isEmpty)
    }
    func testSuggestionsRankExactThenOverlapThenDistanceAndLimitToThree() {
        var ledger = fixture()
        let far = Plan(title: "别的", amount: 10_000, dueDate: date("2026-10-19"))
        let near = Plan(title: "其他", amount: 10_000, dueDate: date("2026-10-21"))
        let named = Plan(title: "房租", amount: 10_000, dueDate: date("2026-10-20"))
        let approximate = Plan(title: "房租", amount: 10_500, dueDate: date("2026-10-22"))
        ledger.plans = [approximate, far, named, near]
        let matches = FixedFlows.suggestions(amount: 10_000, nature: .expense, purpose: "房租", day: now, accountID: nil, in: ledger, now: now)
        XCTAssertEqual(matches.map(\.planID), [named.id, near.id, far.id])
        ledger.plans = [approximate, named]
        XCTAssertEqual(FixedFlows.suggestions(amount: 10_000, nature: .expense, purpose: "房租", day: now, accountID: nil, in: ledger, now: now).map(\.planID), [named.id, approximate.id])
    }
    func testAutoPayOnlySettlesSinceActivationThroughTodayAndIsIdempotent() throws {
        var ledger = fixture()
        var plan = Plan(title: "订阅", amount: 10_000, dueDate: date("2026-07-22 20:00:00"), frequency: .monthly)
        plan.autoPay = true; plan.autoPaySince = date("2026-09-22 23:00:00"); plan.accountID = ledger.accounts[0].id
        var noAccount = plan; noAccount.id = UUID(); noAccount.accountID = nil
        var disabled = plan; disabled.id = UUID(); disabled.autoPay = false
        ledger.plans = [plan, noAccount, disabled]
        let change = try XCTUnwrap(FixedFlows.autoSettle(in: ledger, now: now))
        XCTAssertEqual(change.source, "自动扣款"); XCTAssertEqual(change.items.count, 2)
        try change.apply(to: &ledger)
        XCTAssertEqual(ledger.entries.map(\.occurrence), [date("2026-09-22"), date("2026-10-22")])
        XCTAssertEqual(ledger.entries.last?.date, now); XCTAssertTrue(ledger.entries.allSatisfy { $0.source == "自动扣款" && $0.planID == plan.id })
        XCTAssertNil(FixedFlows.autoSettle(in: ledger, now: now))
        let remaining = Finance.occurrences(in: ledger, now: now).filter { $0.planID == plan.id }
        XCTAssertEqual(remaining.filter(\.overdue).map { Dates.day($0.date) }, [date("2026-07-22"), date("2026-08-22")])
        XCTAssertTrue(remaining.contains { Dates.day($0.date) == date("2026-11-22") })
    }
    func testAutoPayInflowRespectsEndDateAndInstallmentLimit() throws {
        var ledger = fixture(); var plan = salary()
        plan.autoPay = true; plan.accountID = ledger.accounts[0].id; plan.installments = 2; plan.endDate = date("2026-11-15")
        ledger.plans = [plan]; let later = date("2027-02-01")
        let before = Finance.funds(ledger, now: later).cash
        let change = try XCTUnwrap(FixedFlows.autoSettle(in: ledger, now: later))
        XCTAssertEqual(change.items.count, 2)
        try change.apply(to: &ledger)
        XCTAssertEqual(Finance.funds(ledger, now: later).cash, before + 1_600_000)
        XCTAssertTrue(ledger.entries.allSatisfy { $0.nature == .income }); XCTAssertNil(FixedFlows.autoSettle(in: ledger, now: later))
    }
    func testSuggestionsIncludeTimedThirdDayAndIgnoreNameCaseAndWhitespace() {
        var ledger = fixture()
        let plan = Plan(title: "Cloud Bill", amount: 10_000, dueDate: date("2026-10-25 23:00:00"))
        ledger.plans = [plan]
        let matches = FixedFlows.suggestions(amount: 10_500, nature: .expense, purpose: " cloud\nBILL ", day: now, accountID: nil, in: ledger, now: now)
        XCTAssertEqual(matches.map(\.planID), [plan.id])
    }
    func testSettleUsesExplicitThenPlanThenDefaultAccountAndSupportsPartialAmounts() throws {
        var ledger = fixture(); ledger.accounts.append(Account(name: "零钱", kind: .cash, at: date("2026-07-01")))
        var plan = Plan(title: "订阅", amount: 10_000, dueDate: date("2026-10-22")); plan.accountID = ledger.accounts[1].id
        let other = Plan(title: "水费", amount: 3000, dueDate: plan.dueDate)
        let fallback = Plan(title: "电费", amount: 2000, dueDate: plan.dueDate); ledger.plans = [plan, other, fallback]
        XCTAssertThrowsError(try FixedFlows.settle(planID: plan.id, occurrence: plan.dueDate, accountID: ledger.accounts[0].id, in: ledger, now: now))
        try FixedFlows.settle(planID: plan.id, occurrence: plan.dueDate, amount: 4000, in: ledger, now: now).apply(to: &ledger)
        XCTAssertEqual(ledger.entries[0].accountID, ledger.accounts[1].id)
        XCTAssertEqual(Finance.occurrences(in: ledger, now: now).first { $0.planID == plan.id }?.amount, 6000)
        try FixedFlows.settle(planID: other.id, occurrence: other.dueDate, accountID: ledger.accounts[0].id, in: ledger, now: now).apply(to: &ledger)
        XCTAssertEqual(ledger.entries.last?.accountID, ledger.accounts[0].id)
        let defaultAccount = ManualBookkeeping.defaultAccount(in: ledger)?.id
        try FixedFlows.settle(planID: fallback.id, occurrence: fallback.dueDate, in: ledger, now: now).apply(to: &ledger)
        XCTAssertEqual(ledger.entries.last?.accountID, defaultAccount)
    }
    func testPaydayIncludesNinetiethDayAndMonthlyScheduleKeepsOriginalMonthEnd() {
        var ledger = fixture()
        let edge = Dates.addDays(90, to: Dates.day(now)).addingTimeInterval(23 * 3600)
        ledger.plans = [Plan(title: "收入", amount: 1000, dueDate: edge, frequency: .yearly, inflow: true, nature: .income)]
        XCTAssertEqual(Finance.nextPayday(in: ledger, now: now)?.date, Dates.day(edge))
        ledger.plans[0].dueDate = Dates.addDays(1, to: edge)
        XCTAssertNil(Finance.nextPayday(in: ledger, now: now))
        var plan = Plan(title: "月末工资", amount: 1000, dueDate: date("2026-01-31"), frequency: .monthly, inflow: true, nature: .income)
        plan.installments = 3; ledger.plans = [plan]
        XCTAssertEqual(Finance.nextPayday(in: ledger, now: date("2026-02-22"))?.date, date("2026-02-28"))
        XCTAssertEqual(Finance.nextPayday(in: ledger, now: date("2026-02-28"))?.date, date("2026-03-31"))
        XCTAssertNil(Finance.nextPayday(in: ledger, now: date("2026-03-31")))
        ledger.plans = [Plan(title: "每周收入", amount: 1000, dueDate: Dates.addDays(-2800 * 7, to: Dates.day(now)), frequency: .weekly, inflow: true, nature: .income)]
        XCTAssertEqual(Finance.nextPayday(in: ledger, now: now)?.date, Dates.addDays(7, to: Dates.day(now)))
    }
    func testInstallmentsStopAtTotalAndMonthAndArrangementReportProgress() throws {
        var ledger = fixture(); var plan = Plan(title: "分期", amount: 10_000, dueDate: date("2026-08-22"), frequency: .monthly)
        plan.installments = 12; ledger.plans = [plan]
        XCTAssertEqual(Finance.occurrences(in: ledger, now: plan.dueDate, days: 366).count, 12)
        ledger.entries = [payment(plan, on: date("2026-08-22"), in: ledger), payment(plan, on: date("2026-09-22"), in: ledger)]
        let row = try XCTUnwrap(FixedFlows.month(containing: now, in: ledger).occurrences.first)
        XCTAssertEqual(row.installment?.index, 3); XCTAssertEqual(row.installment?.total, 12)
        let arrangement = try XCTUnwrap(FixedFlowArrangement.rows(in: ledger, now: now).first)
        XCTAssertEqual(arrangement.paidCount, 2); XCTAssertEqual(arrangement.total, 12); XCTAssertTrue(arrangement.canEnd)
        let invalid = ChangeSet(source: "用户操作", reason: "超出分期", items: [.linkPlan(entry: ledger.entries[0].id, plan: plan.id, occurrence: date("2027-08-22"))])
        ledger.entries[0].planID = nil; ledger.entries[0].occurrence = nil
        XCTAssertThrowsError(try invalid.apply(to: &ledger))
    }
    func testEstimatedReserveUsesMostRecentActualAndAnyLinkedAmountPaysOccurrence() throws {
        var ledger = fixture(); var plan = Plan(title: "电费", amount: 10_000, dueDate: date("2026-08-22"), frequency: .monthly)
        plan.estimated = true; ledger.plans = [plan]
        XCTAssertTrue(Finance.occurrences(in: ledger, now: now).allSatisfy { $0.amount == 10_000 })
        let august = payment(plan, on: date("2026-08-22"), amount: 12_000, in: ledger)
        let september = payment(plan, on: date("2026-09-22"), amount: 8000, in: ledger)
        var removed = payment(plan, on: date("2026-10-01"), amount: 50_000, in: ledger); removed.deletedAt = now
        ledger.entries = [september, removed, august]
        XCTAssertTrue(Finance.occurrences(in: ledger, now: now).allSatisfy { $0.amount == 8000 })
        XCTAssertFalse(Finance.occurrences(in: ledger, now: now).contains { $0.overdue })
        let row = try XCTUnwrap(FixedFlows.month(containing: date("2026-09-25"), in: ledger).occurrences.first)
        XCTAssertEqual(row.state, .paid); XCTAssertEqual(row.amount, 8000); XCTAssertTrue(row.estimated)
        try FixedFlows.settle(planID: plan.id, occurrence: date("2026-10-22"), amount: 7000, in: ledger, now: now).apply(to: &ledger)
        XCTAssertFalse(Finance.occurrences(in: ledger, now: now).contains { Dates.day($0.date) == date("2026-10-22") })
        XCTAssertTrue(Finance.occurrences(in: ledger, now: now).allSatisfy { $0.amount == 7000 })
    }
    func testLegacyPlanAndDraftDecodeWithoutNewKeysAndNewFieldsRoundTrip() throws {
        let legacyPlan = #"{"id":"D2B1F585-7829-44B6-A1AE-C3D1847F45A5","title":"房租","amount":10000,"dueDate":0,"frequency":"monthly","inflow":false,"category":"居住","nature":"expense","active":true,"note":""}"#
        var plan = try JSONDecoder().decode(Plan.self, from: Data(legacyPlan.utf8))
        XCTAssertFalse(plan.autoPay); XCTAssertNil(plan.autoPaySince); XCTAssertNil(plan.installments); XCTAssertFalse(plan.estimated); XCTAssertNil(plan.stoppedAt)
        plan.autoPay = true; plan.autoPaySince = now; plan.installments = 12; plan.estimated = true; plan.stoppedAt = now
        XCTAssertEqual(try JSONDecoder().decode(Plan.self, from: JSONEncoder().encode(plan)), plan)
        let legacyDraft = #"{"id":"D2B1F585-7829-44B6-A1AE-C3D1847F45A5","date":0,"amount":10000,"amountConfirmed":true,"nature":"expense","accountID":"D2B1F585-7829-44B6-A1AE-C3D1847F45A5","title":"房租","category":"居住"}"#
        var draft = try JSONDecoder().decode(EntryDraft.self, from: Data(legacyDraft.utf8))
        XCTAssertNil(draft.planID); XCTAssertNil(draft.occurrence); XCTAssertNil(draft.otherAccountID)
        draft.planID = plan.id; draft.occurrence = now
        XCTAssertEqual(try JSONDecoder().decode(EntryDraft.self, from: JSONEncoder().encode(draft)), draft)
    }
    func testMonthShowsPaidDueUpcomingAndRemainingTotalsIncludingRent() throws {
        var ledger = fixture()
        var paid = Plan(title: "已付", amount: 1000, dueDate: date("2026-10-05")); paid.autoPay = true; paid.estimated = true
        let due = Plan(title: "今天到期", amount: 2000, dueDate: date("2026-10-22 22:00:00"))
        let upcoming = Plan(title: "稍后付款", amount: 3000, dueDate: date("2026-10-31 23:00:00"))
        let income = Plan(title: "待收", amount: 4000, dueDate: date("2026-10-25"), inflow: true, nature: .income)
        ledger.plans = [paid, due, upcoming, income, Plan(title: "下月", amount: 9000, dueDate: date("2026-11-01"))]
        ledger.entries = [payment(paid, on: paid.dueDate, amount: 1100, in: ledger)]
        let rent = Rent(title: "合租", monthlyTotal: 10_000, personalShare: 6000, startDate: date("2026-10-01"), nextDueDate: date("2026-10-15"), monthsPerPayment: 1, receiveDay: 2)
        ledger.rents = [rent]
        let month = FixedFlows.month(containing: now, in: ledger)
        XCTAssertEqual(month.date, date("2026-10-01")); XCTAssertEqual(month.occurrences.count, 6)
        let paidRow = try XCTUnwrap(month.occurrences.first { $0.planID == paid.id })
        XCTAssertEqual(paidRow.state, .paid); XCTAssertEqual(paidRow.amount, 1100); XCTAssertTrue(paidRow.autoPay)
        XCTAssertEqual(month.occurrences.first { $0.planID == due.id }?.state, .due)
        XCTAssertEqual(month.occurrences.first { $0.planID == upcoming.id }?.state, .upcoming)
        XCTAssertEqual(month.remainingOutflow, 15_000); XCTAssertEqual(month.remainingInflow, 8000)
        var rentPayment = Entry(date: date("2026-10-15"), amount: 10_000, accountID: ledger.accounts[0].id, title: "合租")
        rentPayment.rentID = rent.id; rentPayment.rentPeriod = date("2026-10-15")
        var share = Entry(date: date("2026-10-02"), amount: 4000, nature: .contribution, accountID: ledger.accounts[0].id, title: "分摊")
        share.rentID = rent.id; share.rentPeriod = date("2026-10-01"); ledger.entries += [rentPayment, share]
        let after = FixedFlows.month(containing: now, in: ledger)
        XCTAssertTrue(after.occurrences.filter { $0.rentID == rent.id }.allSatisfy { $0.state == .paid && !$0.autoPay })
        XCTAssertEqual(after.remainingOutflow, 5000); XCTAssertEqual(after.remainingInflow, 4000)
        ledger.entries.append(payment(due, on: Dates.day(now), amount: 500, in: ledger))
        let partial = FixedFlows.month(containing: now, in: ledger)
        // A partly paid fixed-amount bill still asks 付了吗 for the rest.
        XCTAssertEqual(partial.occurrences.first { $0.planID == due.id }?.state, .due)
        XCTAssertEqual(partial.occurrences.first { $0.planID == due.id }?.amount, 1500)
        XCTAssertEqual(partial.remainingOutflow, 4500)
    }
}
