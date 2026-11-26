import XCTest
@testable import YubaiCore

final class SettingsCoreTests: XCTestCase {
    private func d(_ text: String) -> Date { Dates.parse(text)! }

    // MARK: Weekend payday shift

    func testWeekendShiftMovesSaturdayAndSundayToFriday() {
        XCTAssertEqual(CycleStart.shifted(d("2026-11-28")), d("2026-11-27"))
        XCTAssertEqual(CycleStart.shifted(d("2026-11-29")), d("2026-11-27"))
        XCTAssertEqual(CycleStart.shifted(d("2026-11-30")), d("2026-11-30"))
    }

    func testCycleOffKeepsNominalDayAndOnStartsOnFridayBeforeASaturdayPayday() {
        let off = CycleStart.cycle(day: 10, weekendShift: false, now: d("2026-10-09 12:00"))
        XCTAssertEqual(off.start, d("2026-09-10")); XCTAssertEqual(off.end, d("2026-10-09"))
        let on = CycleStart.cycle(day: 10, weekendShift: true, now: d("2026-10-09 12:00"))
        XCTAssertEqual(on.start, d("2026-10-09")); XCTAssertEqual(on.end, d("2026-11-09"))
        let plain = CycleStart.cycle(day: 10, weekendShift: true, now: d("2026-11-23 12:00"))
        XCTAssertEqual(plain.start, d("2026-11-10")); XCTAssertEqual(plain.end, d("2026-12-09"))
        let next = CycleStart.nextCycle(day: 10, weekendShift: false, now: d("2026-11-23 12:00"))
        XCTAssertEqual(next.start, d("2026-12-10")); XCTAssertEqual(next.end, d("2027-01-09"))
    }

    func testLastDayOptionClampsToMonthEndAndShiftsSundayAndSaturday() {
        let off = CycleStart.cycle(day: CycleStart.lastDay, weekendShift: false, now: d("2026-02-15"))
        XCTAssertEqual(off.start, d("2026-01-31")); XCTAssertEqual(off.end, d("2026-02-27"))
        let on = CycleStart.cycle(day: CycleStart.lastDay, weekendShift: true, now: d("2026-02-15"))
        XCTAssertEqual(on.start, d("2026-01-30")); XCTAssertEqual(on.end, d("2026-02-26"))
        let sunday = CycleStart.cycle(day: CycleStart.lastDay, weekendShift: true, now: d("2026-05-30"))
        XCTAssertEqual(sunday.start, d("2026-05-29")); XCTAssertEqual(sunday.end, d("2026-06-29"))
    }

    func testLedgerCycleUsesStoredDayAndShiftWithoutASalaryPlan() throws {
        var ledger = Ledger()
        try CycleStart.set(day: 10, weekendShift: true, in: &ledger, now: d("2026-10-01"))
        XCTAssertEqual(ledger.cycleAnchor, .payday)
        XCTAssertEqual(CycleStart.day(in: ledger, now: d("2026-10-01")), 10)
        let cycle = Finance.cycle(in: ledger, now: d("2026-10-09 12:00"))
        XCTAssertEqual(cycle.start, d("2026-10-09")); XCTAssertEqual(cycle.end, d("2026-11-09"))
        XCTAssertTrue(Finance.cycleInfo(in: ledger, now: d("2026-10-09 12:00")).known)
        ledger.preferences.paydayWeekendShift = nil
        XCTAssertEqual(Finance.cycle(in: ledger, now: d("2026-10-09 12:00")).start, d("2026-09-10"))
        XCTAssertThrowsError(try CycleStart.set(day: 0, weekendShift: false, in: &ledger, now: d("2026-10-01")))
    }

    func testSalaryPlanScheduleShiftsWeekendPaydayOnlyWhenOn() {
        var ledger = Ledger()
        let bank = Account(name: "Bank", balance: 100_000, at: d("2026-08-01"))
        ledger.accounts = [bank]; ledger.cycleAnchor = .payday
        var salary = Plan(title: "工资", amount: 800_000, dueDate: d("2026-08-10"), frequency: .monthly, inflow: true, category: "工资奖金", nature: .income)
        salary.accountID = bank.id
        ledger.plans = [salary]
        XCTAssertEqual(Finance.cycle(in: ledger, now: d("2026-10-09 12:00")).start, d("2026-09-10"))
        ledger.preferences.paydayWeekendShift = true
        let shifted = Finance.cycle(in: ledger, now: d("2026-10-09 12:00"))
        XCTAssertEqual(shifted.start, d("2026-10-09")); XCTAssertEqual(shifted.end, d("2026-11-09"))
    }

    func testChangingDayKeepsSalaryAmountAndAccount() throws {
        var ledger = Ledger()
        let bank = Account(name: "Bank", balance: 100_000, at: d("2026-08-01"))
        ledger.accounts = [bank]
        try Payday.configure(day: 10, amount: 1_850_000, accountID: bank.id, in: &ledger, now: d("2026-11-23 12:00"))
        try CycleStart.set(day: 15, weekendShift: false, in: &ledger, now: d("2026-11-23 12:00"))
        let plan = try XCTUnwrap(Finance.anchorPlan(in: ledger, now: d("2026-11-23 12:00")))
        XCTAssertEqual(plan.monthlyDay, 15); XCTAssertEqual(plan.amount, 1_850_000); XCTAssertEqual(plan.accountID, bank.id)
        XCTAssertEqual(CycleStart.day(in: ledger, now: d("2026-11-23 12:00")), 15)
    }

    // MARK: Monthly fixed total and chips

    func testMonthlyFixedTotalConvertsYearlyAndForeignCurrency() throws {
        var ledger = Ledger()
        let now = d("2026-11-23 12:00")
        try FixedFlows.setRate(ManualExchangeRate(currency: .usd, cnyPerUnit: Decimal(string: "7.2")!, updatedAt: d("2026-11-01")), in: &ledger)
        let gym = Plan(title: "超级猩猩", amount: 30_000, dueDate: d("2026-12-15"), frequency: .monthly)
        let yearly = Plan(title: "域名", amount: 12_000, dueDate: d("2027-03-01"), frequency: .yearly)
        var usd = Plan(title: "Claude", amount: 2_000, dueDate: d("2026-12-01"), frequency: .monthly); usd.currency = .usd
        var stopped = Plan(title: "停了", amount: 99_900, dueDate: d("2026-12-01"), frequency: .monthly); stopped.active = false
        let salary = Plan(title: "工资", amount: 1_850_000, dueDate: d("2026-12-10"), frequency: .monthly, inflow: true, category: "工资奖金", nature: .income)
        let once = Plan(title: "一次", amount: 5_000, dueDate: d("2026-12-01"))
        ledger.plans = [gym, yearly, usd, stopped, salary, once]
        let total = SettingsSummary.monthlyFixed(in: ledger, now: now)
        XCTAssertEqual(total.count, 3)
        XCTAssertEqual(total.total, 30_000 + 1_000 + 14_400)
        XCTAssertEqual(SettingsSummary.subscriptions(in: ledger, now: now).map(\.plan.title), ["Claude", "超级猩猩", "域名"])
        let december = DateInterval(start: d("2026-12-01"), end: d("2027-01-01"))
        XCTAssertEqual(SettingsSummary.occurrences(of: gym, in: december), [d("2026-12-15")])
        XCTAssertEqual(SettingsSummary.occurrences(of: yearly, in: december), [])
    }

    func testFloorChipsAreThreeAndSixMonthsOfAverageSpend() {
        var ledger = Ledger()
        let bank = Account(name: "Bank", balance: 0, at: d("2026-01-01")); ledger.accounts = [bank]
        for (day, amount) in [("2026-08-05", Int64(900_000)), ("2026-09-05", 800_000), ("2026-10-05", 700_000), ("2026-11-05", 50_000)] {
            ledger.entries.append(Entry(date: d(day), amount: amount, accountID: bank.id, title: "x", category: "餐饮"))
        }
        ledger.entries.append(Entry(date: d("2026-10-06"), amount: 999_999, nature: .income, accountID: bank.id, title: "工资", category: "工资奖金"))
        XCTAssertEqual(SettingsSummary.averageMonthlySpend(in: ledger, now: d("2026-11-23")), 800_000)
        XCTAssertEqual(SettingsSummary.floorChips(in: ledger, now: d("2026-11-23")), [2_400_000, 4_800_000])
        XCTAssertEqual(SettingsSummary.floorChips(in: Ledger(), now: d("2026-11-23")), [])
        XCTAssertEqual(SettingsSummary.savingChips(takeHome: 1_850_000), [185_000, 370_000])
    }

    // MARK: Export

    func testCSVExportFiltersByCycleRange() throws {
        var ledger = Ledger()
        let bank = Account(name: "Bank", balance: 0, at: d("2026-01-01")); ledger.accounts = [bank]
        try CycleStart.set(day: 10, weekendShift: false, in: &ledger, now: d("2026-11-23"))
        for day in ["2026-10-12", "2026-11-09", "2026-11-10", "2026-11-22"] {
            ledger.entries.append(Entry(date: d(day + " 12:00"), amount: 1_000, accountID: bank.id, title: day, category: "餐饮"))
        }
        var deleted = Entry(date: d("2026-11-20"), amount: 1, accountID: bank.id, title: "gone", category: "餐饮"); deleted.deletedAt = d("2026-11-21")
        ledger.entries.append(deleted)
        let now = d("2026-11-23 12:00")
        let current = ExportRange.current.interval(in: ledger, now: now)
        let previous = ExportRange.previous.interval(in: ledger, now: now)
        XCTAssertEqual(current, d("2026-11-10")...d("2026-12-09"))
        XCTAssertEqual(previous, d("2026-10-10")...d("2026-11-09"))
        XCTAssertEqual(LedgerBackup.exportCount(ledger, in: current), 2)
        XCTAssertEqual(LedgerBackup.exportCount(ledger, in: previous), 2)
        XCTAssertEqual(LedgerBackup.exportCount(ledger, in: nil), 4)
        let csv = String(decoding: LedgerBackup.entriesCSV(ledger, in: current), as: UTF8.self)
        XCTAssertTrue(csv.contains("2026-11-22")); XCTAssertFalse(csv.contains("2026-11-09")); XCTAssertFalse(csv.contains("gone"))
        XCTAssertEqual(csv.components(separatedBy: "\r\n").filter { !$0.isEmpty }.count, 3)
    }

    // MARK: Tolerant decoding

    func testNewOptionalFieldsDecodeFromOldAndMalformedLedgers() throws {
        var ledger = Ledger()
        let bank = Account(name: "Bank", kind: .credit, balance: -10, at: d("2026-01-01")); ledger.accounts = [bank]
        ledger.plans = [Plan(title: "Netflix", amount: 100, dueDate: d("2026-12-01"), frequency: .monthly)]
        let data = try JSONEncoder().encode(ledger)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var preferences = try XCTUnwrap(json["preferences"] as? [String: Any])
        for key in ["paydayWeekendShift", "cycleStartDay", "assistantTone", "weeklyReviewTime"] { XCTAssertNil(preferences[key]) }
        let old = try JSONDecoder().decode(Ledger.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(old.preferences.paydayWeekendShift); XCTAssertFalse(old.preferences.shiftsWeekendPayday)
        XCTAssertEqual(old.preferences.tone, .gentle); XCTAssertEqual(old.preferences.reviewTime, .standard)
        XCTAssertNil(old.plans[0].iconSlug); XCTAssertNil(old.accounts[0].creditStatementDay)

        preferences["paydayWeekendShift"] = "yes"; preferences["assistantTone"] = "shouty"
        preferences["weeklyReviewTime"] = ["weekday": 9, "hour": 21, "minute": 0]; preferences["cycleStartDay"] = 40
        json["preferences"] = preferences
        let malformed = try JSONDecoder().decode(Ledger.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(malformed.preferences.paydayWeekendShift); XCTAssertNil(malformed.preferences.assistantTone)
        XCTAssertNil(malformed.preferences.weeklyReviewTime); XCTAssertNil(malformed.preferences.cycleStartDay)

        var updated = ledger
        updated.preferences.paydayWeekendShift = true; updated.preferences.assistantTone = .direct
        updated.preferences.weeklyReviewTime = WeeklyReviewTime(weekday: 5, hour: 8, minute: 30)
        updated.plans[0].iconSlug = "netflix"; updated.accounts[0].creditStatementDay = 5
        let round = try JSONDecoder().decode(Ledger.self, from: JSONEncoder().encode(updated))
        XCTAssertEqual(round.preferences.paydayWeekendShift, true); XCTAssertEqual(round.preferences.tone, .direct)
        XCTAssertEqual(round.preferences.reviewTime, WeeklyReviewTime(weekday: 5, hour: 8, minute: 30))
        XCTAssertEqual(round.plans[0].iconSlug, "netflix"); XCTAssertEqual(round.accounts[0].creditStatementDay, 5)

        updated.accounts[0].creditStatementDay = 32
        XCTAssertThrowsError(try updated.validate())
    }

    func testBrandCatalogHasAColourForEveryEntry() {
        XCTAssertFalse(BrandIcons.catalog.isEmpty)
        for icon in BrandIcons.catalog {
            let hex = icon.hex ?? ""
            XCTAssertNotNil(hex.range(of: "^#[0-9A-Fa-f]{6}$", options: .regularExpression), icon.slug)
        }
    }

    // MARK: Accounts and onboarding

    func testAccountsAddUpdateAndArchive() throws {
        var ledger = Ledger()
        let now = d("2026-11-23 12:00")
        let id = try Accounts.add(.init(name: "招行信用卡", kind: .credit, balance: -321_680), in: &ledger, now: now)
        XCTAssertThrowsError(try Accounts.add(.init(name: "招行信用卡", kind: .bank, balance: 0), in: &ledger, now: now))
        XCTAssertThrowsError(try Accounts.add(.init(name: "  ", kind: .bank, balance: 0), in: &ledger, now: now))
        try Accounts.update(id, .init(creditLimit: 3_000_000, statementDay: .some(5), paymentDay: .some(23)), in: &ledger, now: now)
        XCTAssertEqual(ledger.accounts[0].creditStatementDay, 5); XCTAssertEqual(ledger.accounts[0].creditPaymentDay, 23)
        XCTAssertEqual(ledger.accounts[0].anchorBalance, -321_680)
        try Accounts.update(id, .init(name: "信用卡"), in: &ledger, now: now)
        XCTAssertEqual(ledger.accounts[0].name, "信用卡"); XCTAssertEqual(ledger.accounts[0].creditLimit, 3_000_000)
        try Accounts.archive(id, in: &ledger, now: now)
        XCTAssertTrue(ledger.accounts[0].archived)
    }

    func testOnboardingWritesCycleSavingAndAccountsInOneSave() throws {
        var ledger = Ledger()
        let now = d("2026-11-23 12:00")
        try Onboarding.finish(day: 10, takeHome: 1_850_000, saving: 500_000, floor: nil, accounts: [
            .init(name: "招行储蓄", kind: .bank, balance: 3_218_000),
            .init(name: "支付宝", kind: .cash, balance: 2_499_960),
            .init(name: "信用卡", kind: .credit, balance: -321_680),
        ], in: &ledger, now: now)
        XCTAssertTrue(ledger.preferences.onboardingComplete)
        XCTAssertEqual(ledger.accounts.map(\.name), ["招行储蓄", "支付宝", "信用卡"])
        XCTAssertEqual(ledger.savingRule, .fixed(500_000))
        XCTAssertEqual(CycleStart.day(in: ledger, now: now), 10)
        XCTAssertEqual(Finance.anchorPlan(in: ledger, now: now)?.amount, 1_850_000)
        XCTAssertEqual(Finance.cycle(in: ledger, now: now).start, d("2026-11-10"))

        var failing = Ledger()
        XCTAssertThrowsError(try Onboarding.finish(day: 10, takeHome: 0, saving: 0, floor: nil, accounts: [
            .init(name: "A", kind: .bank, balance: 0), .init(name: "A", kind: .cash, balance: 0),
        ], in: &failing, now: now))
        XCTAssertTrue(failing.accounts.isEmpty)
    }
}
