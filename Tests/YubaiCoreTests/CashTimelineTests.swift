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

    func testForecastEndsBeforePaydayAndKeepsBillsAsVerticalSteps() throws {
        var ledger = ledger(daily: 1000)
        ledger.plans = [salary(), Plan(title: "房租", amount: 200_000, dueDate: date("2026-11-10"))]
        let timeline = Finance.cashTimeline(ledger, now: now)
        XCTAssertEqual(timeline.defaultStart, date("2026-10-15"))
        XCTAssertEqual(timeline.end, date("2026-11-14"))
        XCTAssertEqual(timeline.dailyLiving, 1000)
        XCTAssertEqual(point(timeline, "2026-11-09")?.balance, 995_000)
        XCTAssertEqual(point(timeline, "2026-11-10")?.balance, 794_000)
        XCTAssertEqual(point(timeline, "2026-11-14")?.balance, 790_000)
        XCTAssertEqual(timeline.forecastLine.filter { $0.date == date("2026-11-10") }.map(\.balance), [994_000, 794_000])
        XCTAssertFalse(timeline.forecastLine.contains { $0.date >= date("2026-11-15") })
        XCTAssertFalse(timeline.forecast.flatMap(\.events).contains { $0.title == "工资" })
        XCTAssertEqual(timeline.window().endpoint?.balance, 790_000)
    }

    func testNoSalaryUsesCalendarMonthAndIgnoresFundsHorizon() {
        var ledger = ledger()
        ledger.plans = [Plan(title: "一次收入", amount: 2000, dueDate: date("2026-11-10"), inflow: true, nature: .income)]
        let timeline = Finance.cashTimeline(ledger, now: now, days: 0)
        XCTAssertFalse(timeline.hasPayday)
        XCTAssertEqual(timeline.defaultStart, date("2026-11-01"))
        XCTAssertEqual(timeline.end, date("2026-11-30"))
        XCTAssertEqual(timeline.window().cycle.previousStart, date("2026-10-01"))
        XCTAssertEqual(point(timeline, "2026-11-10")?.balance, 1_002_000)
        XCTAssertEqual(timeline.forecast.count, 27)
    }

    func testUnconfirmedLocalSalaryDetectionSuppliesActualCycleWithoutMutatingLedger() throws {
        var ledger = ledger()
        ledger.entries = ["2026-09-15", "2026-10-16"].map {
            Entry(date: date($0), amount: 1_310_000, nature: .income, accountID: ledger.accounts[0].id, title: "合成公司")
        }
        let before = ledger
        XCTAssertNotNil(SalaryDetection.candidate(in: ledger, now: now))
        let timeline = Finance.cashTimeline(ledger, now: now)
        XCTAssertTrue(timeline.hasPayday)
        XCTAssertEqual(timeline.defaultStart, date("2026-10-16"))
        XCTAssertEqual(timeline.end, date("2026-11-15"))
        XCTAssertEqual(timeline.window().cycle.previousStart, date("2026-09-15"))
        XCTAssertEqual(timeline.window().annotations.first?.amount, 1_310_000)
        XCTAssertEqual(ledger, before)
    }

    func testConfirmedSalaryUsesActualReceiptRatherThanNominalDay() {
        var ledger = ledger()
        let plan = salary(); ledger.plans = [plan]
        var paid = Entry(date: date("2026-10-14"), amount: plan.amount, nature: .income, accountID: ledger.accounts[0].id, title: "合成公司工资")
        paid.planID = plan.id; ledger.entries = [paid]
        let timeline = Finance.cashTimeline(ledger, now: now)
        XCTAssertEqual(timeline.defaultStart, date("2026-10-14"))
        XCTAssertEqual(timeline.end, date("2026-11-14"))
        XCTAssertEqual(timeline.window().annotations.map(\.title), ["合成公司工资"])
    }

    func testConfirmedDetectedSalaryKeepsOriginalCompanyReceiptsWithoutForecastingThemAgain() throws {
        var ledger = ledger()
        ledger.entries = ["2026-09-15", "2026-10-16"].map {
            Entry(date: date($0), amount: 1_310_000, nature: .income, accountID: ledger.accounts[0].id, title: "合成公司")
        }
        let candidate = try XCTUnwrap(SalaryDetection.candidate(in: ledger, now: now))
        XCTAssertNotNil(SalaryDetection.confirm(candidate, in: &ledger, now: now))
        let timeline = Finance.cashTimeline(ledger, now: now)
        XCTAssertEqual(timeline.defaultStart, date("2026-10-16"))
        XCTAssertEqual(timeline.window().annotations.first?.title, "合成公司")
        XCTAssertTrue(timeline.forecast.flatMap(\.events).isEmpty)
        XCTAssertEqual(timeline.window().endpoint?.balance, 1_000_000)
    }

    func testEarlyPaydayReceiptStartsCycleBeforeNominalDateWithoutDuplicatingSalary() {
        var ledger = ledger(); let day = date("2026-11-14 12:00:00")
        let plan = salary(); ledger.plans = [plan]
        ledger.entries = [Entry(date: Dates.day(day), amount: plan.amount, nature: .income, accountID: ledger.accounts[0].id, title: "工资")]
        let timeline = Finance.cashTimeline(ledger, now: day)
        XCTAssertEqual(timeline.defaultStart, date("2026-11-14"))
        XCTAssertEqual(timeline.end, date("2026-12-14"))
        XCTAssertFalse(timeline.forecast.flatMap(\.events).contains { $0.title == "工资" })
    }

    func testWeeklySalaryAndYearCrossingUseOriginalSchedule() {
        var ledger = ledger(); var plan = salary("2027-01-02"); plan.frequency = .weekly; ledger.plans = [plan]
        let timeline = Finance.cashTimeline(ledger, now: date("2026-12-31 12:00:00"))
        XCTAssertEqual(timeline.defaultStart, date("2026-12-26"))
        XCTAssertEqual(timeline.end, date("2027-01-01"))
        XCTAssertEqual(timeline.window().cycle.previousStart, date("2026-12-19"))
        XCTAssertTrue(timeline.cycles.allSatisfy { $0.start >= timeline.start })
    }

    func testMonthlySalaryDoesNotDriftAfterFebruaryIncludingLeapYear() {
        var ledger = ledger(); var plan = salary("2024-01-31"); plan.monthlyDay = 31; ledger.plans = [plan]
        let timeline = Finance.cashTimeline(ledger, now: date("2024-03-10 12:00:00"))
        XCTAssertEqual(timeline.defaultStart, date("2024-02-29"))
        XCTAssertEqual(timeline.end, date("2024-03-30"))
        XCTAssertEqual(timeline.window().cycle.previousStart, date("2024-01-31"))
        XCTAssertEqual(timeline.window().cycle.previousEnd, date("2024-02-28"))
        let april = Finance.cashTimeline(ledger, now: date("2024-04-01 12:00:00"))
        XCTAssertEqual(april.defaultStart, date("2024-03-31"))
        XCTAssertEqual(april.end, date("2024-04-29"))
    }

    func testPaydayTodayStartsNewCycleAndForecastExcludesFollowingSalary() {
        var ledger = ledger(); ledger.plans = [salary("2026-11-04")]
        let timeline = Finance.cashTimeline(ledger, now: now)
        XCTAssertEqual(timeline.defaultStart, Dates.day(now))
        XCTAssertEqual(timeline.end, date("2026-12-03"))
        XCTAssertEqual(timeline.window().history.count, 1)
        // Today's outstanding salary is inside this cycle; next month's is excluded.
        XCTAssertEqual(timeline.forecast.flatMap(\.events).filter { $0.title == "工资" }.count, 1)
        XCTAssertEqual(timeline.forecast.first?.events.first?.date, Dates.day(now))
    }

    func testPreviousCycleAlignsByElapsedDayAndTruncatesLongerMonth() throws {
        var ledger = ledger(daily: 100)
        ledger.plans = [salary()]
        let timeline = Finance.cashTimeline(ledger, now: now), window = timeline.window()
        XCTAssertEqual(window.previous.count, 30) // Sep 15–Oct 14 vs Oct 15–Nov 14 (31 days)
        XCTAssertEqual(window.previous.first?.date, date("2026-10-15"))
        XCTAssertEqual(window.previous.last?.date, date("2026-11-13"))
        let source = timeline.history.first { $0.date == date("2026-10-05") }
        XCTAssertEqual(window.previousPoint(on: now)?.balance, source?.balance)
        XCTAssertNil(window.previousPoint(on: date("2026-11-14")))
        let older = timeline.window(cycleOffset: 1)
        XCTAssertEqual(older.previous.count, 30) // August cycle's day 31 is truncated.
        XCTAssertEqual(older.previous.last?.date, older.end)
        XCTAssertEqual(older.previous.last?.balance, timeline.history.first { $0.date == date("2026-09-13") }?.balance)
        ledger.plans = []
        let calendar = Finance.cashTimeline(ledger, now: now).window()
        XCTAssertEqual(calendar.previous.count, 30)
        XCTAssertEqual(calendar.previous.last?.date, date("2026-11-30"))
    }

    func testTodayDifferenceUsesAlignedActualCashAndPastUsesCompleteCycleClosingCash() throws {
        let ledger = ledger(daily: 100)
        let timeline = Finance.cashTimeline(ledger, now: now)
        XCTAssertEqual(timeline.window().difference, -3000) // Nov 4 actual (no spending yet today) vs Oct 4 closing.
        let older = timeline.window(cycleOffset: 1)
        XCTAssertEqual(older.difference, -3100) // Oct 31 vs Sep 30 (shorter previous cycle).
        XCTAssertTrue(older.forecast.isEmpty)
        XCTAssertTrue(older.forecastLine.isEmpty)
        XCTAssertEqual(older.endpoint?.date, date("2026-10-31"))
    }

    func testMissingAlignedDayDoesNotInventPreviousBalanceOrDifference() {
        let timeline = Finance.cashTimeline(ledger(), now: date("2026-03-31 12:00:00"))
        XCTAssertNil(timeline.window().previousPoint(on: date("2026-03-31")))
        XCTAssertNil(timeline.window().difference)
        XCTAssertEqual(timeline.window().previous.last?.date, date("2026-03-28"))
    }

    func testCycleNavigationClampsAndNeverExposesStartBeforeThreeMonths() {
        var ledger = ledger(); ledger.plans = [salary()]
        ledger.entries = (1...365).map { Entry(date: Dates.addDays(-$0, to: now), amount: 100, accountID: ledger.accounts[0].id, title: "导入") }
        let timeline = Finance.cashTimeline(ledger, now: now)
        XCTAssertEqual(timeline.start, date("2026-08-04"))
        XCTAssertEqual(timeline.cycles.map(\.start), [date("2026-10-15"), date("2026-09-15"), date("2026-08-15")])
        XCTAssertEqual(timeline.window(cycleOffset: 999).start, date("2026-08-15"))
        XCTAssertTrue(timeline.window(cycleOffset: -1).isDefault)
        XCTAssertEqual(timeline.window(cycleOffset: 999).previous.first?.date, date("2026-08-15"))
        XCTAssertLessThan(timeline.history.first!.date, timeline.start) // Previous comparison needs July, read-only.
        XCTAssertTrue(timeline.cycles.allSatisfy { $0.start >= timeline.start })
    }

    func testThreeMonthsMeansCalendarMonthsIncludingLeapAndExactBoundary() {
        let may = Finance.cashTimeline(Ledger(), now: date("2024-05-31 12:00:00"))
        XCTAssertEqual(may.start, date("2024-02-29"))
        XCTAssertEqual(may.cycles.last?.start, date("2024-03-01"))
        let first = Finance.cashTimeline(Ledger(), now: date("2026-11-01 12:00:00"))
        XCTAssertEqual(first.cycles.last?.start, date("2026-08-01"))
        XCTAssertEqual(first.cycles.count, 4)
    }

    func testAnnotationsUseSingleCashOutflowThreeTimesAverageAndRecurringException() {
        var ledger = ledger(); let bank = ledger.accounts[0].id
        let recurring = Plan(title: "月费", amount: 20, dueDate: date("2026-11-01"), frequency: .monthly)
        let once = Plan(title: "一次", amount: 20, dueDate: date("2026-11-01")); ledger.plans = [recurring, once]
        ledger.entries = (1...4).map { Entry(date: date("2026-11-0\($0)"), amount: 100, accountID: bank, title: "日常") }
        ledger.entries += [Entry(date: date("2026-11-02"), amount: 1000, accountID: bank, title: "大额")]
        var fee = Entry(date: date("2026-11-01"), amount: 20, accountID: bank, title: "月费"); fee.planID = recurring.id
        var small = fee; small.id = UUID(); small.planID = once.id; small.title = "一次"
        ledger.entries += [fee, small]
        let window = Finance.cashTimeline(ledger, now: now).window()
        XCTAssertEqual(window.averageSpending, 360)
        XCTAssertEqual(window.annotations.map(\.title), ["月费"]) // 1000 < 3 × 360.
        ledger.entries[4].amount = 1500
        XCTAssertEqual(Finance.cashTimeline(ledger, now: now).window().annotations.map(\.title), ["大额", "月费"])
    }

    func testAnnotationsLimitFourByAbsoluteAmountWithoutLimitingScrubEvents() {
        var ledger = ledger(); let bank = ledger.accounts[0].id
        let recurring = Plan(title: "账单", amount: 1, dueDate: date("2026-11-01"), frequency: .monthly)
        ledger.plans = [salary(), recurring]
        ledger.entries = (1...8).map { i in
            var entry = Entry(date: date("2026-11-02"), amount: Int64(i * 100), accountID: bank, title: "账单\(i)")
            entry.planID = recurring.id; return entry
        }
        ledger.entries.append(Entry(date: date("2026-10-15"), amount: 1_310_000, nature: .income, accountID: bank, title: "工资"))
        let window = Finance.cashTimeline(ledger, now: now).window()
        XCTAssertEqual(window.annotations.map(\.amount), [1_310_000, -800, -700, -600])
        XCTAssertEqual(window.point(on: date("2026-11-02"))?.events.count, 8)
        XCTAssertEqual(window.point(on: date("2026-11-02"))?.events.first?.title, "账单8")
    }

    func testNoncashPurchaseAndInternalTransferAreNotAnnotations() {
        var ledger = ledger(); let bank = ledger.accounts[0].id
        let credit = Account(name: "卡", kind: .credit, balance: 0, at: now), wallet = Account(name: "现金", kind: .cash, balance: 0, at: now)
        ledger.accounts += [credit, wallet]
        var transfer = Entry(date: date("2026-11-02"), amount: 90_000, nature: .transfer, accountID: bank, title: "互转"); transfer.otherAccountID = wallet.id
        ledger.entries = [transfer, Entry(date: date("2026-11-01"), amount: 100_000, accountID: credit.id, title: "信用消费")]
        XCTAssertTrue(Finance.cashTimeline(ledger, now: now).window().annotations.isEmpty)
    }

    func testFloorIsEndpointComparisonOnlyAndEqualityDoesNotWarn() {
        var ledger = ledger(daily: 1000); ledger.plans = [salary()]
        let original = Finance.cashTimeline(ledger, now: now)
        ledger.profile.floorAmount = 990_000
        XCTAssertFalse(Finance.cashTimeline(ledger, now: now).window().belowFloor)
        ledger.profile.floorAmount = 990_001
        let below = Finance.cashTimeline(ledger, now: now)
        XCTAssertTrue(below.window().belowFloor)
        XCTAssertFalse(below.window(cycleOffset: 1).belowFloor)
        XCTAssertEqual(below.history, original.history)
        XCTAssertEqual(below.forecast, original.forecast)
        XCTAssertEqual(below.forecastLine, original.forecastLine)
        // A later in-cycle receipt can lift the endpoint above an earlier trough.
        ledger.plans.append(Plan(title: "入账", amount: 100_000, dueDate: date("2026-11-14"), inflow: true, nature: .income))
        XCTAssertFalse(Finance.cashTimeline(ledger, now: now).window().belowFloor)
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

    func testOutstandingTodayAndInCycleOverdueJumpAfterActualAnchorWithoutDoubleChargingPaidBills() {
        var ledger = ledger()
        let paid = Plan(title: "已付", amount: 10_000, dueDate: date("2026-11-04"))
        var receipt = Entry(date: date("2026-11-04 10:00:00"), amount: 10_000, accountID: ledger.accounts[0].id, title: "已付")
        receipt.planID = paid.id; receipt.occurrence = paid.dueDate
        ledger.entries = [receipt]
        ledger.plans = [paid, Plan(title: "今天要付", amount: 2000, dueDate: date("2026-11-04")),
                        Plan(title: "过期未付", amount: 3000, dueDate: date("2026-11-01")),
                        Plan(title: "上个周期", amount: 40_000, dueDate: date("2026-10-20"))]
        let timeline = Finance.cashTimeline(ledger, now: now)
        XCTAssertEqual(timeline.history.last?.balance, 1_000_000)
        XCTAssertEqual(timeline.forecastLine.first?.balance, 1_000_000)
        XCTAssertEqual(timeline.forecast.first?.balance, 995_000)
        XCTAssertEqual(timeline.forecast.first?.events.count, 2)
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

    func testScaleHasThreeToFiveNiceTicksIncludingNegativeAndZero() {
        for balance: Int64 in [-2_000_000, -100, 0, 100, 12345, 1_999_999, 9_000_000_000] {
            let window = Finance.cashTimeline(ledger(balance: balance), now: now).window()
            let scale = CashTimelineScale(window: window)
            XCTAssertTrue((3...5).contains(scale.ticks.count))
            XCTAssertTrue(scale.ticks.contains(0))
            XCTAssertTrue(scale.domain.contains(Double(balance) / 100))
            let step = scale.ticks[1] - scale.ticks[0]
            let normalized = step / pow(10, floor(log10(step)))
            XCTAssertTrue([1.0, 2, 5].contains { abs($0 - normalized) < 0.000001 })
            XCTAssertEqual(window.showsZero, balance < 0)
        }
        XCTAssertEqual(CashTimelineScale.label(5000), "5k")
        XCTAssertEqual(CashTimelineScale.label(-10000), "−10k")
    }

    func testEmptyLedgerAtMonthEndHasFiniteScaleAndSelectableToday() {
        let day = date("2026-11-30 12:00:00")
        let timeline = Finance.cashTimeline(Ledger(), now: day, days: 0)
        XCTAssertEqual(timeline.end, Dates.day(day))
        XCTAssertEqual(timeline.forecast.count, 1)
        XCTAssertEqual(timeline.window().endpoint?.balance, 0)
        XCTAssertEqual(timeline.window().point(on: day)?.balance, 0)
        XCTAssertFalse(timeline.window().showsZero)
        XCTAssertTrue(CashTimelineScale(window: timeline.window()).domain.upperBound.isFinite)
    }
}
