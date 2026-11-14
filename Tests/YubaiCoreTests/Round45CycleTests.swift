import XCTest
@testable import YubaiCore

enum Round45Fixture {
    static func date(_ text: String) -> Date { Dates.parse(text)! }
    static var now: Date { date("2026-11-20 12:00") }
    static func ledger() -> Ledger {
        var ledger = Ledger()
        ledger.updatedAt = now
        ledger.accounts = [Account(name: "Bank", balance: 1_217_400, at: now.addingTimeInterval(-1))]
        ledger.fixedSavings = 500_000; ledger.savingRule = .fixed(200_000); ledger.cycleAnchor = .payday
        var salary = Plan(title: "工资", amount: 801_000, dueDate: date("2026-10-10"), frequency: .monthly, inflow: true, category: "工资奖金", nature: .income)
        salary.accountID = ledger.accounts[0].id
        ledger.plans = [salary, Plan(title: "Bill", amount: 361_000, dueDate: date("2026-11-25"))]
        var income = Entry(date: date("2026-11-10 09:00"), amount: 801_000, nature: .income, accountID: ledger.accounts[0].id, title: "工资", category: "工资奖金")
        income.planID = salary.id; income.occurrence = date("2026-11-10")
        ledger.entries = [income, entry(ledger, amount: 80_000, date: "2026-11-17 12:00"), entry(ledger, amount: 3600, date: "2026-11-20 10:00")]
        return ledger
    }
    static func entry(_ ledger: Ledger, amount: Int64, date text: String, nature: Nature = .expense, title: String = "Meal", category: String = "餐饮") -> Entry {
        Entry(date: date(text), amount: amount, nature: nature, accountID: ledger.accounts[0].id, title: title, category: category)
    }
}
final class Round45CycleTests: XCTestCase {
    let now = Round45Fixture.now
    func d(_ text: String) -> Date { Round45Fixture.date(text) }
    func testUpgradeKeepsCurrentCycleAndOnlyEnablesNextPayday() {
        var l = Round45Fixture.ledger(); let before = Finance.cycleInfo(in: l, now: now)
        Finance.enablePaydayConfirmation(&l, now: now)
        XCTAssertEqual(l.paydayConfirmSince, d("2026-12-10"))
        XCTAssertEqual(Finance.cycleInfo(in: l, now: now), before)
        Finance.enablePaydayConfirmation(&l, now: d("2026-12-12"))
        XCTAssertEqual(l.paydayConfirmSince, d("2026-12-10"))
    }
    func testLateSalaryExtendsCycleAndDoesNotCloseOrShowDaily() {
        var l = Round45Fixture.ledger(); l.paydayConfirmSince = d("2026-12-10")
        let at = d("2026-12-12 12:00"), info = Finance.cycleInfo(in: l, now: at)
        XCTAssertEqual(info.start, d("2026-11-10")); XCTAssertEqual(info.end, d("2026-12-12")); XCTAssertEqual(info.lateSince, d("2026-12-10"))
        XCTAssertEqual(Finance.funds(l, now: at).salaryLateDays, 2); XCTAssertNil(Finance.pace(l, now: at)?.daily)
        XCTAssertEqual(Payday.due(in: l, now: at)?.lateDays, 2)
        Savings.closeCycles(&l, now: at); XCTAssertTrue(l.savingHistory.isEmpty)
        l.plans.append(Plan(title: "Next month", amount: 10_000, dueDate: d("2026-12-13")))
        XCTAssertEqual(Finance.funds(l, now: at).committed, 361_000)
    }
    func testEarlyIncomeAndEarliestOfTwoConfirmationsDefineStartAndDeleteReverts() throws {
        var l = Round45Fixture.ledger(); l.paydayConfirmSince = d("2026-12-10")
        let at = d("2026-12-09 12:00")
        var early = Round45Fixture.entry(l, amount: 400_000, date: "2026-12-09 09:00", nature: .income)
        early.planID = l.plans[0].id; early.occurrence = d("2026-12-10")
        var later = early; later.id = UUID(); later.date = d("2026-12-10 10:00")
        l.entries += [later, early]
        XCTAssertEqual(Finance.cycleInfo(in: l, now: at).start, d("2026-12-09"))
        XCTAssertEqual(Finance.cycleInfo(in: l, now: d("2026-12-08")).end, d("2026-12-08"))
        XCTAssertNil(Payday.due(in: l, now: d("2026-12-10 12:00")))
        l.entries.removeAll { $0.id == early.id || $0.id == later.id }
        XCTAssertEqual(Finance.cycleInfo(in: l, now: d("2026-12-11")).lateSince, d("2026-12-10"))
    }
    func testConfirmAmountsAndPreviewIncludeRealLeftover() throws {
        for (amount, saveExtra) in [(851_000 as Int64, false), (851_000, true), (751_000, false)] {
            var l = Round45Fixture.ledger(); l.paydayConfirmSince = d("2026-12-10")
            let at = d("2026-12-12 12:00"), due = try XCTUnwrap(Payday.due(in: l, now: at))
            let before = Finance.balance(l.accounts[0], in: l, at: at)
            let preview = Payday.preview(due, amount: amount, extraToSavings: saveExtra, in: l, now: at)
            try Payday.confirm(due, amount: amount, extraToSavings: saveExtra, accountID: nil, in: &l, now: at)
            XCTAssertEqual(Finance.balance(l.accounts[0], in: l, at: at), before + amount)
            XCTAssertEqual(Finance.cycleInfo(in: l, now: at).start, d("2026-12-12"))
            XCTAssertNil(Payday.due(in: l, now: at)); XCTAssertNil(Finance.funds(l, now: at).salaryLateDays)
            XCTAssertEqual(l.entries.filter { $0.intoFixedSavings }.reduce(0) { $0 + $1.amount }, saveExtra ? 50_000 : 0)
            Savings.closeCycles(&l, now: at)
            XCTAssertEqual(preview.delta, amount - due.usual); XCTAssertEqual(preview.cycleBudget, Finance.pace(l, now: at)?.budget)
            XCTAssertThrowsError(try Payday.confirm(due, amount: amount, extraToSavings: false, accountID: nil, in: &l, now: at))
        }
    }
    func testMissingPaydayMergesPeriodsAndClosesOnce() throws {
        var l = Round45Fixture.ledger(); l.paydayConfirmSince = d("2026-12-10")
        var entry = Round45Fixture.entry(l, amount: 801_000, date: "2027-01-10 09:00", nature: .income)
        entry.planID = l.plans[0].id; entry.occurrence = d("2027-01-10"); l.entries.append(entry)
        let historical = Finance.cycleInfo(in: l, now: d("2026-12-20"))
        XCTAssertEqual(historical.start, d("2026-11-10")); XCTAssertEqual(historical.end, d("2027-01-09"))
        Savings.closeCycles(&l, now: d("2027-01-10 12:00"))
        XCTAssertEqual(l.savingHistory.count, 1); XCTAssertEqual(l.savingHistory[0].cycleEnd, d("2027-01-09"))
        let closed = l; Savings.closeCycles(&l, now: d("2027-01-11")); XCTAssertEqual(l, closed)
        XCTAssertNil(Payday.due(in: l, now: d("2027-01-10 12:00")))
    }
    func testLeftoverIsAskedOnceKeepOrSaveAndMigration() throws {
        for choice in [LeftoverChoice.keep, .save] {
            var l = Round45Fixture.ledger(); l.plans = []; l.entries = []; l.cycleAnchor = .calendarMonth
            l.savingHistory = [CycleSaving(cycleStart: d("2026-10-01"), cycleEnd: d("2026-10-31"), income: 801_000, target: 200_000, saved: 200_000, unspent: 21_200)]
            l.accounts[0].anchorBalance = 961_200
            XCTAssertEqual(Finance.funds(l, now: now).available, 261_200)
            let pending = try XCTUnwrap(Savings.pendingLeftover(in: l))
            try Savings.resolveLeftover(cycleStart: pending.cycleStart, choice: choice, in: &l)
            XCTAssertEqual(Finance.funds(l, now: now).available, choice == .save ? 240_000 : 261_200)
            XCTAssertEqual(l.savingHistory[0].leftover, choice == .save ? 21_200 : 0)
            XCTAssertNil(Savings.pendingLeftover(in: l))
            XCTAssertThrowsError(try Savings.resolveLeftover(cycleStart: pending.cycleStart, choice: choice, in: &l))
            XCTAssertEqual(try JSONDecoder().decode(Ledger.self, from: JSONEncoder().encode(l)), l)
        }
    }
    func testAutoPaySkipsAnchorOnlyAndCalendarModePreservesBehavior() {
        var l = Round45Fixture.ledger(); l.paydayConfirmSince = d("2026-12-10"); l.plans[0].autoPay = true
        let at = d("2026-12-10 12:00")
        XCTAssertNil(FixedFlows.autoSettle(in: l, now: at))
        l.cycleAnchor = .calendarMonth
        XCTAssertEqual(Finance.cycleInfo(in: l, now: at).start, d("2026-12-01")); XCTAssertNil(Finance.cycleInfo(in: l, now: at).lateSince)
    }
    func testShortMonthPastThresholdSkippedAndUnknown() {
        var l = Round45Fixture.ledger(); l.plans = [Plan(title: "Salary", amount: 100, dueDate: d("2026-01-31"), frequency: .monthly, inflow: true, nature: .income)]
        l.paydayConfirmSince = d("2026-02-28")
        XCTAssertEqual(Finance.cycleInfo(in: l, now: d("2026-03-01")).lateSince, d("2026-02-28"))
        l.plans[0].skippedOccurrences = [d("2026-02-28")]
        XCTAssertNil(Finance.cycleInfo(in: l, now: d("2026-03-01")).lateSince)
        l.plans = []; l.cycleAnchor = nil
        XCTAssertFalse(Finance.cycleInfo(in: l, now: now).known); XCTAssertNil(Finance.pace(l, now: now))
        l.cycleAnchor = .calendarMonth; XCTAssertTrue(Finance.cycleInfo(in: l, now: now).known)
    }
}

extension Round45CycleTests {
    func testEarlyBoundaryDoesNotCloseOverlappingHistoryAgain() throws {
        var l = Round45Fixture.ledger(); l.paydayConfirmSince = d("2026-12-10")
        l.savingHistory = [CycleSaving(cycleStart: d("2026-11-10"), cycleEnd: d("2026-12-09"), income: 801_000, target: 200_000, saved: 200_000)]
        var early = Round45Fixture.entry(l, amount: 801_000, date: "2026-12-09 09:00", nature: .income)
        early.planID = l.plans[0].id; early.occurrence = d("2026-12-10"); l.entries.append(early)
        let before = l
        Savings.closeCycles(&l, now: d("2026-12-09 12:00"))
        XCTAssertEqual(l, before)
        l.savingHistory[0].cycleStart = l.savingHistory[0].cycleStart.addingTimeInterval(8 * 3600)
        l.savingHistory[0].cycleEnd = l.savingHistory[0].cycleEnd.addingTimeInterval(8 * 3600)
        let shifted = l; Savings.closeCycles(&l, now: d("2026-12-10")); XCTAssertEqual(l, shifted)
    }
}

extension Round45CycleTests {
    func testFullNewCycleStoryCarries212ThenSavingItReturnsBudgetTo2400() throws {
        for (amount, extraToSavings, budget) in [(801_000 as Int64, false, 261_200 as Int64), (851_000, false, 311_200), (851_000, true, 261_200), (751_000, false, 211_200)] {
            var l = Round45Fixture.ledger(); l.paydayConfirmSince = d("2026-12-10")
            l.accounts[0].anchorDate = d("2026-12-09 12:00"); l.accounts[0].anchorBalance = 721_200
            l.plans[1].frequency = .monthly
            var bill = Round45Fixture.entry(l, amount: 361_000, date: "2026-11-25 12:00", title: "Bill")
            bill.planID = l.plans[1].id; bill.occurrence = d("2026-11-25")
            l.entries = [l.entries[0], bill, Round45Fixture.entry(l, amount: 218_800, date: "2026-12-08")]
            XCTAssertEqual(Finance.funds(l, now: d("2026-12-09 12:00")).available, 21_200)
            let at = d("2026-12-10 12:00"), due = try XCTUnwrap(Payday.due(in: l, now: at))
            XCTAssertEqual(Payday.preview(due, amount: amount, extraToSavings: extraToSavings, in: l, now: at).cycleBudget, budget)
            try Payday.confirm(due, amount: amount, extraToSavings: extraToSavings, accountID: nil, in: &l, now: at)
            Savings.closeCycles(&l, now: at)
            XCTAssertEqual(l.savingHistory.last?.saved, 200_000); XCTAssertEqual(l.savingHistory.last?.unspent, 21_200)
            XCTAssertEqual(Finance.funds(l, now: at).available, budget)
            try Savings.resolveLeftover(cycleStart: l.savingHistory.last!.cycleStart, choice: .save, in: &l)
            XCTAssertEqual(Finance.funds(l, now: at).available, budget - 21_200)
            let overview = Reserve.overview(l, now: at)
            let monthly = overview.lines.first { if case .monthly(_, pending: false) = $0.kind { return true }; return false }
            XCTAssertEqual(monthly?.date, d("2026-11-10")); XCTAssertEqual(monthly?.amount, 200_000)
            let leftover = overview.lines.first { $0.kind == .leftover }
            XCTAssertEqual(leftover?.date, d("2026-12-10")); XCTAssertEqual(leftover?.amount, 21_200)
        }
    }
}
