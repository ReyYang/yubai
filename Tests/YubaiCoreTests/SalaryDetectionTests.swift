import XCTest
@testable import YubaiCore

final class SalaryDetectionTests: XCTestCase {
    private let now = Dates.parse("2026-10-28 12:00:00")!
    private func date(_ text: String) -> Date { Dates.parse(text)! }
    private func ledger(amounts: [Int64] = [800_000, 800_000, 800_000], dates: [String] = ["2026-08-10", "2026-09-10", "2026-10-10"], title: String = "合成公司") -> Ledger {
        var ledger = Ledger()
        let account = Account(name: "银行卡", balance: 200_000, at: now)
        ledger.accounts = [account]
        ledger.entries = zip(dates, amounts).map { Entry(date: date($0), amount: $1, nature: .income, accountID: account.id, title: title) }
        return ledger
    }
    func testThreeMonthlyPaymentsAndLatestEvidence() throws {
        let ledger = ledger()
        let candidate = try XCTUnwrap(SalaryDetection.candidate(in: ledger, now: now))
        XCTAssertEqual(candidate.key, "合成公司"); XCTAssertEqual(candidate.payer, "合成公司")
        XCTAssertEqual(candidate.amount, 800_000); XCTAssertEqual(candidate.dayOfMonth, 10)
        XCTAssertEqual(candidate.recentDates, ledger.entries.map(\.date))
        XCTAssertEqual(candidate.entryIDs, ledger.entries.map(\.id)); XCTAssertEqual(candidate.accountID, ledger.accounts[0].id)
    }
    func testFivePercentVariationPassesTwentyPercentFails() throws {
        XCTAssertEqual(SalaryDetection.candidate(in: ledger(amounts: [760_000, 800_000, 840_000]), now: now)?.amount, 840_000)
        XCTAssertNil(SalaryDetection.candidate(in: ledger(amounts: [640_000, 800_000, 960_000]), now: now))
        XCTAssertNotNil(SalaryDetection.candidate(in: ledger(amounts: [720_000, 800_000, 880_000]), now: now))
        XCTAssertNil(SalaryDetection.candidate(in: ledger(amounts: [719_999, 800_000, 880_000]), now: now))
    }
    func testTwelveSalariesIgnoreFourIrregularSmallRemittances() throws {
        let dates = ["2025-11-15", "2025-12-15", "2026-01-15", "2026-02-13", "2026-03-13", "2026-04-15", "2026-05-15", "2026-06-15", "2026-07-15", "2026-08-14", "2026-09-15", "2026-10-15"]
        let amounts: [Int64] = (0..<12).map { 1_600_000 + Int64($0) * 5000 }
        var ledger = ledger(amounts: amounts, dates: dates)
        let salaryIDs = ledger.entries.map(\.id)
        ledger.entries += zip(["2026-04-23", "2026-07-22", "2026-09-15", "2026-10-20"], [150_000, 123_000, 47_800, 60_000] as [Int64]).map {
            Entry(date: date($0), amount: $1, nature: .income, accountID: ledger.accounts[0].id, title: "合成公司")
        }
        let candidate = try XCTUnwrap(SalaryDetection.candidate(in: ledger, now: now))
        XCTAssertEqual(candidate.entryIDs, salaryIDs)
        XCTAssertEqual(candidate.dayOfMonth, 15)
        XCTAssertEqual(candidate.amount, amounts.last)
        for i in 0..<12 { ledger.entries[i].amount = [1_280_000, 1_600_000, 1_920_000][i % 3] }
        XCTAssertNil(SalaryDetection.candidate(in: ledger, now: now))
    }
    func testStableRunMayStartAfterAnEarlyAmountOutlierButMustCoverMostMonths() throws {
        let dates = (1...10).map { String(format: "2026-%02d-15", $0) }
        var ledger = ledger(amounts: [1_400_000] + Array(repeating: 1_750_000, count: 9), dates: dates)
        let candidate = try XCTUnwrap(SalaryDetection.candidate(in: ledger, now: now))
        XCTAssertEqual(candidate.entryIDs, ledger.entries.dropFirst().map(\.id))
        // A couple of similar months cannot rescue a volatile payment history.
        ledger.entries[2].amount = 2_200_000
        ledger.entries[5].amount = 1_200_000
        XCTAssertNil(SalaryDetection.candidate(in: ledger, now: now))
    }
    func testOnePaymentDoesNotQualify() {
        XCTAssertNil(SalaryDetection.candidate(in: ledger(amounts: [800_000], dates: ["2026-10-10"]), now: now))
    }
    func testLargestLatestAmountWins() {
        var ledger = ledger()
        let other = self.ledger(amounts: [1_200_000, 1_200_000, 1_200_000], title: "另一公司")
        ledger.entries += other.entries
        XCTAssertEqual(SalaryDetection.candidate(in: ledger, now: now)?.payer, "另一公司")
    }
    func testMonthEndsAndLeapYear() throws {
        for dates in [["2026-01-31", "2026-02-28", "2026-03-31", "2026-04-30"], ["2024-01-31", "2024-02-29", "2024-03-31"]] {
            let ledger = ledger(amounts: Array(repeating: 800_000, count: dates.count), dates: dates)
            let candidate = try XCTUnwrap(SalaryDetection.candidate(in: ledger, now: now))
            XCTAssertEqual(candidate.dayOfMonth, 31)
            XCTAssertEqual(candidate.recentDates, Array(ledger.entries.suffix(3).map(\.date)))
        }
        XCTAssertEqual(SalaryDetection.nextPayday(day: 31, after: date("2026-01-31 12:00:00")), date("2026-02-28"))
        XCTAssertEqual(SalaryDetection.nextPayday(day: 31, after: date("2024-01-31")), date("2024-02-29"))
        XCTAssertEqual(SalaryDetection.nextPayday(day: 31, after: date("2026-04-29")), date("2026-04-30"))
        XCTAssertEqual(SalaryDetection.nextPayday(day: 10, after: date("2026-10-10")), date("2026-11-10"))
    }
    func testIntervalsAndDaysMustBothMatch() {
        XCTAssertNil(SalaryDetection.candidate(in: ledger(dates: ["2026-08-10", "2026-09-10", "2026-10-15"]), now: now))
        XCTAssertNil(SalaryDetection.candidate(in: ledger(dates: ["2026-08-10", "2026-08-20", "2026-10-10"]), now: now))
        XCTAssertNotNil(SalaryDetection.candidate(in: ledger(dates: ["2026-08-10", "2026-09-13", "2026-10-10"]), now: now))
    }
    func testConfirmationInFebruaryKeepsThirtyFirstForLaterMonthsAndBackup() throws {
        var ledger = ledger(dates: ["2025-11-30", "2025-12-31", "2026-01-31"])
        let now = date("2026-01-31 12:00:00")
        let candidate = try XCTUnwrap(SalaryDetection.candidate(in: ledger, now: now))
        let plan = try XCTUnwrap(SalaryDetection.confirm(candidate, in: &ledger, now: now))
        XCTAssertEqual(plan.dueDate, date("2026-02-28"))
        XCTAssertEqual(Finance.nextPayday(in: ledger, now: date("2026-02-28"))?.date, date("2026-03-31"))
        XCTAssertEqual(plan.schedule(through: date("2026-04-30")).map(\.date), [date("2026-02-28"), date("2026-03-31"), date("2026-04-30")])
        let restored = try JSONDecoder().decode(Ledger.self, from: JSONEncoder().encode(ledger))
        try restored.validate()
        XCTAssertEqual(restored.plans[0].monthlyDay, 31)
        XCTAssertEqual(Finance.nextPayday(in: restored, now: date("2026-02-28"))?.date, date("2026-03-31"))
    }
    func testOnlyActiveIncomeAndNotFutureOrDeletedEntries() {
        var ledger = ledger()
        ledger.entries[0].deletedAt = now
        ledger.entries[1].nature = .unknownIn
        XCTAssertNil(SalaryDetection.candidate(in: ledger, now: now))
        ledger = self.ledger(dates: ["2026-10-10", "2026-11-10", "2026-12-10"])
        XCTAssertNil(SalaryDetection.candidate(in: ledger, now: now))
    }
    func testPayerNormalizationForManualAndImportedEntries() throws {
        var ledger = ledger()
        ledger.entries[0].title = " 合成 公司 622200001234 "
        ledger.entries[1].title = "合成公司（622200005678）"
        ledger.entries[1].source = "文件"
        ledger.entries[2].title = "合成公司"
        let candidate = try XCTUnwrap(SalaryDetection.candidate(in: ledger, now: now))
        XCTAssertEqual(candidate.key, "合成公司"); XCTAssertEqual(candidate.payer, "合成公司")
    }
    func testExistingActiveMonthlyIncomeSuppressesCandidate() {
        var ledger = ledger()
        var plan = Plan(title: "收入", amount: 100, dueDate: now, frequency: .monthly, inflow: true, nature: .income)
        ledger.plans = [plan]
        XCTAssertNil(SalaryDetection.candidate(in: ledger, now: now))
        plan.active = false; ledger.plans = [plan]
        XCTAssertNotNil(SalaryDetection.candidate(in: ledger, now: now))
        plan.active = true; plan.frequency = .once; ledger.plans = [plan]
        XCTAssertNotNil(SalaryDetection.candidate(in: ledger, now: now))
    }
    func testDismissalPersistsAndOldLedgerDefaultsToEmpty() throws {
        var ledger = ledger()
        let before = ledger
        SalaryDetection.dismiss(try XCTUnwrap(SalaryDetection.candidate(in: ledger, now: now)), in: &ledger)
        XCTAssertNil(SalaryDetection.candidate(in: ledger, now: now)); XCTAssertNotEqual(ledger, before)
        let data = try JSONEncoder().encode(ledger)
        let restored = try JSONDecoder().decode(Ledger.self, from: data)
        XCTAssertEqual(restored.dismissedSalaryKeys, ["合成公司"])
        XCTAssertNil(SalaryDetection.candidate(in: restored, now: now))
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "dismissedSalaryKeys")
        let legacy = try JSONDecoder().decode(Ledger.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertTrue(legacy.dismissedSalaryKeys.isEmpty)
        XCTAssertNotNil(SalaryDetection.candidate(in: legacy, now: now))
    }
    func testConfirmationShortensFundsHorizonAndCanBeWhollyUndone() throws {
        var ledger = ledger()
        ledger.preferences.dailyLiving = 5_000
        for day in 1...90 { ledger.entries.append(Entry(date: Dates.addDays(-day, to: now), amount: 5_000, accountID: ledger.accounts[0].id, title: "日常支出", category: "餐饮")) }
        let before = ledger; let original = Finance.funds(ledger, now: now)
        let candidate = try XCTUnwrap(SalaryDetection.candidate(in: ledger, now: now))
        let plan = try XCTUnwrap(SalaryDetection.confirm(candidate, in: &ledger, now: now))
        try ledger.validate()
        XCTAssertEqual(plan.title, "工资"); XCTAssertEqual(plan.amount, 800_000)
        XCTAssertEqual(plan.accountID, ledger.accounts[0].id); XCTAssertEqual(plan.category, "工资奖金")
        XCTAssertEqual(plan.frequency, .monthly); XCTAssertTrue(plan.inflow); XCTAssertEqual(plan.nature, .income)
        let after = Finance.funds(ledger, now: now)
        XCTAssertEqual(after.payday, date("2026-11-10")); XCTAssertEqual(after.horizonDays, 12)
        XCTAssertGreaterThan(after.horizonDays, original.horizonDays); XCTAssertEqual(after.available, original.available)
        XCTAssertNil(SalaryDetection.candidate(in: ledger, now: now))
        XCTAssertNil(SalaryDetection.confirm(candidate, in: &ledger, now: now)); XCTAssertEqual(ledger.plans.count, 1)
        ledger = before
        XCTAssertEqual(Finance.funds(ledger, now: now).available, original.available)
        XCTAssertEqual(Finance.funds(ledger, now: now).horizonDays, original.horizonDays)
        XCTAssertEqual(SalaryDetection.candidate(in: ledger, now: now), candidate)
    }
    func testConfirmationUsesLatestAccountAndIncomeFallback() throws {
        var ledger = ledger()
        let account = Account(name: "新工资卡", at: now); ledger.accounts.append(account)
        ledger.entries[2].accountID = account.id
        ledger.categories.removeAll { $0.name == "工资奖金" }
        let plan = try XCTUnwrap(SalaryDetection.confirm(try XCTUnwrap(SalaryDetection.candidate(in: ledger, now: now)), in: &ledger, now: now))
        XCTAssertEqual(plan.accountID, account.id)
        XCTAssertEqual(plan.category, "其他收入")
    }
    func testPendingImportsExcludeUndoneDeletedAndManuallyClassifiedRows() {
        var ledger = ledger()
        var first = ImportBatch(filename: "一.csv", importedCount: 3, duplicateCount: 0, skippedCount: 0); first.needsOrganization = true
        var second = ImportBatch(filename: "二.csv", importedCount: 1, duplicateCount: 0, skippedCount: 0); second.needsOrganization = true; second.undoneAt = now
        ledger.imports = [first, second]
        for i in ledger.entries.indices { ledger.entries[i].batchID = first.id }
        ledger.entries[0].deletedAt = now
        ledger.entries[1].userEdited = true; ledger.entries[1].category = "工资奖金"
        let summary = PendingImportOrganization(in: ledger)
        XCTAssertEqual(summary.batchIDs, [first.id]); XCTAssertEqual(summary.count, 1)
        XCTAssertEqual(summary.entryIDs, [ledger.entries[2].id]); XCTAssertEqual(summary.accountIDs, [ledger.accounts[0].id])
    }
}
