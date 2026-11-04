import XCTest
@testable import YubaiCore

final class CashTimelineTests: XCTestCase {
    private let now = Dates.parse("2026-11-04 12:00:00")!
    private func date(_ text: String) -> Date { Dates.parse(text)! }
    private func ledger(balance: Int64 = 1_000_000, daily: Int64 = 0) -> Ledger {
        var ledger = Ledger()
        let bank = Account(name: "合成工资卡", balance: balance, at: now)
        ledger.accounts = [bank]
        if daily > 0 {
            ledger.entries = (1...90).map {
                Entry(date: Dates.addDays(-$0, to: Dates.day(now)), amount: daily, accountID: bank.id, title: "合成日常", category: "餐饮")
            }
        }
        return ledger
    }
    private func point(_ timeline: CashTimeline, _ day: String, forecast: Bool = true) -> CashTimelinePoint? {
        (forecast ? timeline.forecast : timeline.history).first { $0.date == date(day) }
    }
    private func salary(_ day: String = "2026-11-15") -> Plan {
        Plan(title: "工资", amount: 1_310_000, dueDate: date(day), frequency: .monthly, inflow: true, nature: .income)
    }

    func testBackcastsDailyClosingCashFromActualAnchorIncludingPreReconciliationEntries() throws {
        var ledger = ledger(balance: 100_000)
        let id = ledger.accounts[0].id
        let lunch = Entry(date: date("2026-11-04 10:00:00"), amount: 1200, accountID: id, title: "午饭")
        let income = Entry(date: date("2026-11-03"), amount: 5000, nature: .income, accountID: id, title: "工资")
        var deleted = lunch; deleted.deletedAt = now; deleted.amount = 99_999
        let future = Entry(date: date("2026-11-04 18:00:00"), amount: 55_555, accountID: id, title: "尚未发生")
        ledger.entries = [lunch, income, deleted, future]
        let before = ledger
        let timeline = Finance.cashTimeline(ledger, now: now)
        XCTAssertEqual(timeline.history.last?.balance, Finance.funds(ledger, now: now).cash)
        XCTAssertEqual(point(timeline, "2026-11-04", forecast: false)?.balance, 100_000)
        XCTAssertEqual(point(timeline, "2026-11-03", forecast: false)?.balance, 101_200)
        XCTAssertEqual(point(timeline, "2026-11-02", forecast: false)?.balance, 96_200)
        XCTAssertEqual(point(timeline, "2026-11-03", forecast: false)?.events.map(\.title), ["工资"])
        XCTAssertEqual(ledger, before)
    }

    func testPostAnchorEntriesAreNotAddedTwiceAndArchivedCashStillCounts() {
        var ledger = ledger(balance: 100_000)
        ledger.accounts[0].anchorDate = date("2026-11-01")
        ledger.accounts[0].archived = true
        ledger.entries = [Entry(date: date("2026-11-03"), amount: 2000, accountID: ledger.accounts[0].id, title: "支出")]
        let timeline = Finance.cashTimeline(ledger, now: now)
        XCTAssertEqual(timeline.history.last?.balance, 98_000)
        XCTAssertEqual(point(timeline, "2026-11-02", forecast: false)?.balance, 100_000)
    }

    func testCashTransferCancelsButCreditRepaymentAndInvestmentMoveCashOnEachPostingDay() {
        var ledger = ledger(balance: 100_000)
        let bank = ledger.accounts[0]
        let wallet = Account(name: "零钱", kind: .cash, balance: 20_000, at: now)
        let credit = Account(name: "信用卡", kind: .credit, balance: -50_000, at: now)
        let investment = Account(name: "基金", kind: .investment, balance: 500_000, at: now)
        ledger.accounts += [wallet, credit, investment]
        var transfer = Entry(date: date("2026-11-03"), amount: 8000, nature: .transfer, accountID: bank.id, title: "转零钱")
        transfer.otherAccountID = wallet.id
        var repayment = Entry(date: date("2026-11-02"), amount: 5000, nature: .repayment, accountID: bank.id, title: "还信用卡")
        repayment.otherAccountID = credit.id
        var buy = Entry(date: date("2026-11-01"), amount: 9000, nature: .investBuy, accountID: bank.id, title: "申购")
        buy.otherAccountID = investment.id
        ledger.entries = [transfer, repayment, buy]
        let timeline = Finance.cashTimeline(ledger, now: now)
        XCTAssertEqual(timeline.history.last?.balance, 120_000)
        XCTAssertEqual(point(timeline, "2026-11-02", forecast: false)?.balance, 120_000)
        XCTAssertEqual(point(timeline, "2026-11-01", forecast: false)?.balance, 125_000)
        XCTAssertEqual(point(timeline, "2026-10-31", forecast: false)?.balance, 134_000)
        transfer.otherDate = date("2026-11-04 18:00:00")
        ledger.entries = [transfer]
        let delayed = Finance.cashTimeline(ledger, now: now)
        XCTAssertEqual(point(delayed, "2026-11-02", forecast: false)?.balance, 128_000)
    }

    func testForecastIncludesPaydayAndBillsAsVerticalStepsAndDailyLivingAsSlope() throws {
        var ledger = ledger(daily: 1000)
        ledger.plans = [salary(), Plan(title: "房租", amount: 200_000, dueDate: date("2026-11-10"))]
        let timeline = Finance.cashTimeline(ledger, now: now)
        XCTAssertEqual(timeline.end, date("2026-11-15"))
        XCTAssertEqual(timeline.dailyLiving, 1000)
        XCTAssertEqual(point(timeline, "2026-11-09")?.balance, 995_000)
        XCTAssertEqual(point(timeline, "2026-11-10")?.balance, 794_000)
        XCTAssertEqual(point(timeline, "2026-11-15")?.balance, 2_099_000)
        let jump = timeline.forecastLine.filter { $0.date == date("2026-11-15") }
        XCTAssertEqual(jump.map(\.balance), [790_000, 2_100_000, 2_099_000])
        XCTAssertEqual(jump[1].lower - jump[0].lower, 1_310_000)
        XCTAssertEqual(jump[1].upper - jump[0].upper, 1_310_000)
        XCTAssertEqual(point(timeline, "2026-11-15")?.events.first?.amount, 1_310_000)
        XCTAssertFalse(timeline.forecast.contains { $0.date > timeline.end })
    }

    func testOnlyDailyLivingWidensScenarioBand() throws {
        var ledger = ledger(daily: 1000)
        ledger.plans = [salary()]
        let timeline = Finance.cashTimeline(ledger, now: now)
        let today = try XCTUnwrap(timeline.forecast.first)
        XCTAssertEqual(today.lower, today.balance); XCTAssertEqual(today.upper, today.balance)
        let future = try XCTUnwrap(point(timeline, "2026-11-08"))
        XCTAssertEqual(future.balance - future.lower, 1000)
        XCTAssertEqual(future.upper - future.balance, 1000)
        ledger.entries = []
        let fixedOnly = Finance.cashTimeline(ledger, now: now)
        XCTAssertTrue(fixedOnly.forecast.allSatisfy { $0.balance == $0.lower && $0.balance == $0.upper })
    }

    func testMinimumUsesForecastIncludingTodayAndEarliestDayWinsTies() {
        var ledger = ledger(daily: 1000)
        ledger.plans = [salary()]
        let timeline = Finance.cashTimeline(ledger, now: now)
        XCTAssertEqual(timeline.window().minimum?.date, date("2026-11-14"))
        XCTAssertEqual(timeline.window().minimum?.balance, 990_000)
        XCTAssertEqual(timeline.window().minimum?.balance, timeline.forecastLine.map(\.balance).min())
        ledger.entries = []
        XCTAssertEqual(Finance.cashTimeline(ledger, now: now).window().minimum?.date, Dates.day(now))
        // A large historical receipt creates a past trough; the default minimum
        // must still use only the forecast, while the older window uses its dates.
        ledger.entries = [Entry(date: date("2026-10-15"), amount: 2_000_000, nature: .income, accountID: ledger.accounts[0].id, title: "工资")]
        let withHistory = Finance.cashTimeline(ledger, now: now)
        XCTAssertEqual(withHistory.window().minimum?.balance, 1_000_000)
        let older = withHistory.window(startingAt: withHistory.start)
        XCTAssertLessThan(older.end, Dates.day(now))
        XCTAssertEqual(older.minimum?.balance, -1_000_000)
        XCTAssertEqual(older.minimum?.date, older.start)
        XCTAssertTrue(older.showsZero)
    }

    func testWindowsClampToThreeCalendarMonthsEvenWithOneYearOfImportedEntries() {
        var ledger = ledger()
        ledger.plans = [salary()]
        ledger.entries = (1...365).map { Entry(date: Dates.addDays(-$0, to: now), amount: 100, accountID: ledger.accounts[0].id, title: "导入") }
        let timeline = Finance.cashTimeline(ledger, now: now)
        XCTAssertEqual(timeline.start, date("2026-08-04"))
        XCTAssertEqual(timeline.history.first?.date, timeline.start)
        XCTAssertEqual(timeline.history.count, 93)
        XCTAssertEqual(timeline.window().start, date("2026-09-04"))
        XCTAssertEqual(timeline.window().end, date("2026-11-15"))
        XCTAssertEqual(timeline.window(startingAt: date("2000-01-01")).start, timeline.start)
        XCTAssertTrue(timeline.window(startingAt: date("2030-01-01")).isDefault)
        for offset in -365...365 {
            let window = timeline.window(startingAt: Dates.addDays(offset, to: timeline.today))
            XCTAssertGreaterThanOrEqual(window.start, timeline.start)
            XCTAssertLessThanOrEqual(window.end, timeline.end)
            XCTAssertTrue((window.history + window.forecast).allSatisfy { $0.date >= window.start && $0.date <= window.end })
            XCTAssertGreaterThanOrEqual(window.indicatorStart, 0)
            XCTAssertLessThanOrEqual(window.indicatorStart + window.indicatorLength, 1.000001)
        }
        XCTAssertEqual(timeline.window(startingAt: timeline.start).indicatorStart, 0)
        XCTAssertEqual(timeline.window().indicatorStart + timeline.window().indicatorLength, 1, accuracy: 0.000001)
    }

    func testNoPaydayUsesExistingHorizonAndOneOffIncomeDoesNotShortenIt() {
        var ledger = ledger()
        ledger.plans = [Plan(title: "一次收入", amount: 2000, dueDate: date("2026-11-10"), inflow: true, nature: .income)]
        let timeline = Finance.cashTimeline(ledger, now: now)
        XCTAssertEqual(timeline.end, Dates.addDays(Finance.observationDays, to: Dates.day(now)))
        XCTAssertEqual(timeline.forecast.count, 91)
        XCTAssertEqual(point(timeline, "2026-11-10")?.balance, 1_002_000)
        let short = Finance.cashTimeline(ledger, now: now, days: 12)
        XCTAssertEqual(short.end, Dates.addDays(12, to: Dates.day(now)))
        XCTAssertEqual(short.forecast.count, 13)
    }

    func testFloorIsComparisonOnlyAndEqualityDoesNotWarn() {
        var ledger = ledger()
        let original = Finance.cashTimeline(ledger, now: now)
        XCTAssertFalse(original.window().belowFloor)
        ledger.profile.floorAmount = 1_000_000
        XCTAssertFalse(Finance.cashTimeline(ledger, now: now).window().belowFloor)
        ledger.profile.floorAmount = 1_000_001
        let below = Finance.cashTimeline(ledger, now: now)
        XCTAssertTrue(below.window().belowFloor)
        XCTAssertEqual(below.history, original.history)
        XCTAssertEqual(below.forecast, original.forecast)
        XCTAssertEqual(below.forecastLine, original.forecastLine)
        XCTAssertFalse(below.window().showsZero)
    }

    func testCashForecastDoesNotSubtractDebtGoalsOrUncertainIncomeReserves() {
        var ledger = ledger()
        ledger.accounts.append(Account(name: "信用卡", kind: .credit, balance: -200_000, at: now))
        ledger.goals = [Goal(title: "目标", target: 300_000, reserved: 100_000)]
        ledger.accounts[0].anchorDate = date("2026-11-01")
        ledger.entries = [Entry(date: date("2026-11-03"), amount: 5000, nature: .unknownIn, accountID: ledger.accounts[0].id, title: "不明进账")]
        let timeline = Finance.cashTimeline(ledger, now: now)
        XCTAssertEqual(timeline.forecast.first?.balance, 1_005_000)
        XCTAssertEqual(timeline.history.last?.balance, 1_005_000)
        XCTAssertNotEqual(timeline.forecast.first?.balance, Finance.funds(ledger, now: now).available)
    }

    func testOutstandingTodayAndOverdueJumpAfterActualAnchorWithoutDroppingOrDoubleChargingPaidBills() {
        var ledger = ledger()
        let paid = Plan(title: "已付", amount: 10_000, dueDate: date("2026-11-04"))
        var receipt = Entry(date: date("2026-11-04 10:00:00"), amount: 10_000, accountID: ledger.accounts[0].id, title: "已付")
        receipt.planID = paid.id; receipt.occurrence = paid.dueDate
        ledger.entries = [receipt]
        ledger.plans = [paid, Plan(title: "今天要付", amount: 2000, dueDate: date("2026-11-04")),
                        Plan(title: "过期未付", amount: 3000, dueDate: date("2026-11-01"))]
        let timeline = Finance.cashTimeline(ledger, now: now)
        XCTAssertEqual(timeline.history.last?.balance, 1_000_000)
        XCTAssertEqual(timeline.forecastLine.first?.balance, 1_000_000)
        XCTAssertEqual(timeline.forecast.first?.balance, 995_000)
        XCTAssertEqual(timeline.forecast.first?.events.count, 2)
        XCTAssertEqual(timeline.forecast.first?.events.first { $0.title == "过期未付" }?.date, date("2026-11-01"))
        XCTAssertEqual(timeline.window().minimum?.balance, 995_000)
        XCTAssertEqual(timeline.window().point(on: now)?.balance, 1_000_000)
    }

    func testRepaymentIsDatedCashMovementWhileCreditPurchaseIsNot() {
        var ledger = ledger()
        let credit = Account(name: "信用卡", kind: .credit, balance: -200_000, at: now)
        ledger.accounts.append(credit)
        var purchase = Plan(title: "信用订阅", amount: 4000, dueDate: date("2026-11-06")); purchase.accountID = credit.id
        var repay = Plan(title: "还卡", amount: 200_000, dueDate: date("2026-11-08"), nature: .repayment); repay.accountID = credit.id
        ledger.plans = [purchase, repay, salary()]
        let timeline = Finance.cashTimeline(ledger, now: now)
        XCTAssertEqual(point(timeline, "2026-11-06")?.balance, 1_000_000)
        XCTAssertEqual(point(timeline, "2026-11-08")?.balance, 800_000)
    }

    func testPartPaidSkippedStoppedAndFutureLinkedBillsFollowRemainingSchedule() {
        var ledger = ledger()
        let partial = Plan(title: "部分已付", amount: 10_000, dueDate: date("2026-11-08"))
        var paid = Entry(date: date("2026-11-03"), amount: 3000, accountID: ledger.accounts[0].id, title: "先付")
        paid.planID = partial.id; paid.occurrence = partial.dueDate
        var future = Entry(date: date("2026-11-08"), amount: 7000, accountID: ledger.accounts[0].id, title: "未来流水")
        future.planID = partial.id; future.occurrence = partial.dueDate
        var skipped = Plan(title: "跳过", amount: 9999, dueDate: date("2026-11-09")); skipped.skippedOccurrences = [skipped.dueDate]
        var stopped = skipped; stopped.id = UUID(); stopped.active = false
        ledger.entries = [paid, future]; ledger.plans = [partial, skipped, stopped, salary()]
        let timeline = Finance.cashTimeline(ledger, now: now)
        XCTAssertEqual(point(timeline, "2026-11-08")?.balance, 993_000)
        XCTAssertEqual(point(timeline, "2026-11-09")?.balance, 993_000)
    }

    func testThreeMonthsMeansCalendarMonthsIncludingLeapAndMonthEnd() {
        let endOfMay = date("2024-05-31 12:00:00")
        let timeline = Finance.cashTimeline(Ledger(), now: endOfMay)
        XCTAssertEqual(timeline.start, date("2024-02-29"))
        XCTAssertEqual(timeline.defaultStart, date("2024-03-31"))
        XCTAssertEqual(timeline.window(startingAt: date("2023-01-01")).start, date("2024-02-29"))
    }

    func testEmptyLedgerAndZeroDayHorizonRemainSelectableAndFinite() {
        let timeline = Finance.cashTimeline(Ledger(), now: now, days: 0)
        XCTAssertEqual(timeline.end, Dates.day(now))
        XCTAssertEqual(timeline.forecast.count, 1)
        XCTAssertEqual(timeline.window().minimum?.balance, 0)
        XCTAssertEqual(timeline.window().point(on: now)?.balance, 0)
        XCTAssertFalse(timeline.window().showsZero)
        XCTAssertTrue(timeline.window().indicatorLength.isFinite)
    }
}
