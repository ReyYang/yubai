import XCTest
@testable import YubaiCore

final class ManualBookkeepingTests: XCTestCase {
    private let now = Dates.parse("2026-10-21 12:16:00")!
    private func fixture() -> Ledger {
        var ledger = Ledger()
        ledger.accounts = [Account(name: "微信零钱", kind: .cash, balance: 125_000, at: now.addingTimeInterval(-60)), Account(name: "工资卡", balance: 500_000, at: now.addingTimeInterval(-60))]
        return ledger
    }
    func testKeypadArithmeticDecimalsBackspaceAndReset() {
        var pad = EntryKeypad()
        XCTAssertFalse(pad.canSave)
        ["3", "2", "+", "1", "8", ".", "5", "0", "9"].forEach { pad.press($0) }
        XCTAssertEqual(pad.expression, "32+18.50"); XCTAssertEqual(pad.amount, 5050)
        XCTAssertEqual(pad.displayText, "50.5")
        pad.press("⌫"); XCTAssertEqual(pad.expression, "32+18.5")
        pad.press("−"); pad.press("2"); XCTAssertEqual(pad.resolve(), 4850)
        XCTAssertEqual(pad.expression, "48.5"); pad.reset(); XCTAssertEqual(pad.expression, "0")
        pad.press("."); pad.press("5"); pad.press("."); pad.press("2"); pad.press("3")
        XCTAssertEqual(pad.amount, 52)
    }
    func testKeypadBoundsOperatorReplacementAndNonpositiveResults() throws {
        XCTAssertEqual(try EntryKeypad.evaluate("0.1+0.2"), 30)
        XCTAssertEqual(try EntryKeypad.evaluate("32−18+2"), 1600)
        XCTAssertThrowsError(try EntryKeypad.evaluate("99999999999.99+0.01"))
        XCTAssertThrowsError(try EntryKeypad.evaluate("1.001"))
        XCTAssertThrowsError(try EntryKeypad.evaluate("1*2"))
        var pad = EntryKeypad()
        "99999999999.99".forEach { pad.press(String($0)) }
        pad.press("9"); XCTAssertEqual(pad.amount, Money.limit)
        pad.press("+"); pad.press("1"); XCTAssertEqual(pad.amount, Money.limit)
        pad.reset(); ["3", "+", "−", "5"].forEach { pad.press($0) }
        XCTAssertEqual(pad.amount, -200); XCTAssertFalse(pad.canSave)
        pad.press("+"); pad.press("7"); XCTAssertEqual(pad.resolve(), 500)
    }
    func testFrequentCategoriesIgnoreDeletedAndOtherNaturesAndFillDefaults() {
        var ledger = fixture(); let id = ledger.accounts[0].id
        ledger.entries = [Entry(date: now, amount: 100, accountID: id, title: "地铁", category: "交通"), Entry(date: now, amount: 100, accountID: id, title: "早餐", category: "餐饮"), Entry(date: now, amount: 100, accountID: id, title: "公交", category: "交通")]
        var deleted = Entry(amount: 100, accountID: id, title: "书", category: "学习"); deleted.deletedAt = now
        ledger.entries.append(deleted)
        ledger.entries.append(Entry(amount: 100, nature: .income, accountID: id, title: "工资", category: "工资"))
        XCTAssertEqual(ManualBookkeeping.categories(in: ledger, nature: .expense, frequentOnly: true), ["交通", "餐饮", "日用", "购物", "娱乐"])
        XCTAssertEqual(ManualBookkeeping.categories(in: ledger, nature: .income, frequentOnly: true).first, "工资")
        XCTAssertEqual(ManualBookkeeping.guessCategory("午饭", nature: .expense, in: ledger), "餐饮")
        ledger.categoryMemory[CategoryMemory.key("午饭")] = "工作餐"
        XCTAssertEqual(ManualBookkeeping.guessCategory("午饭", nature: .expense, in: ledger), "工作餐")
        XCTAssertNil(ManualBookkeeping.guessCategory("午饭", nature: .income, in: fixture()))
    }
    func testDefaultAccountPrefersLatestInAppRecordingAndSkipsArchived() {
        var ledger = fixture(); let a = ledger.accounts[0].id; let b = ledger.accounts[1].id
        XCTAssertEqual(ManualBookkeeping.defaultAccount(in: ledger)?.id, a)
        var manual = Entry(date: Dates.addDays(-3, to: now), amount: 100, accountID: b, title: "补记")
        manual.recordedAt = now; ledger.entries = [manual, Entry(date: now, amount: 100, accountID: a, title: "导入")]
        XCTAssertEqual(ManualBookkeeping.defaultAccount(in: ledger)?.id, b)
        ledger.accounts[1].archived = true
        XCTAssertEqual(ManualBookkeeping.defaultAccount(in: ledger)?.id, a)
    }
    func testSavePreviewUsesActualChangeSetWithoutMutatingAndStampsTime() throws {
        var ledger = fixture(); let original = ledger
        let change = try ManualBookkeeping.change(amount: 3200, nature: .expense, accountID: ledger.accounts[0].id, day: now, purpose: "午饭", category: "餐饮", now: now)
        let available = Finance.funds(ledger, now: now).available
        XCTAssertEqual(try ManualBookkeeping.available(after: change, in: ledger, now: now), available - 3200)
        XCTAssertEqual(ledger, original)
        try change.apply(to: &ledger)
        let entry = try XCTUnwrap(ledger.entries.last)
        XCTAssertEqual(entry.date, now); XCTAssertEqual(entry.recordedAt, now); XCTAssertEqual(entry.source, "手动")
        XCTAssertEqual(entry.displayTitle, "午饭"); XCTAssertTrue(entry.userEdited)
        let yesterday = Dates.addDays(-1, to: now)
        XCTAssertEqual(Dates.calendar.component(.hour, from: ManualBookkeeping.entryDate(for: yesterday, now: now)), 12)
        XCTAssertThrowsError(try ManualBookkeeping.change(amount: 0, nature: .expense, accountID: entry.accountID, day: now, purpose: "", category: "餐饮", now: now))
        XCTAssertThrowsError(try ManualBookkeeping.change(amount: 100, nature: .expense, accountID: entry.accountID, day: Dates.addDays(1, to: now), purpose: "", category: "餐饮", now: now))
    }
    func testTransferPreviewAndBlankPurposeFallback() throws {
        var ledger = fixture(); let before = Finance.funds(ledger, now: now).available
        let a = ledger.accounts[0].id; let b = ledger.accounts[1].id
        XCTAssertThrowsError(try ManualBookkeeping.change(amount: 3200, nature: .transfer, accountID: a, otherAccountID: a, day: now, purpose: "", category: "内部移动", now: now))
        let change = try ManualBookkeeping.change(amount: 3200, nature: .transfer, accountID: a, otherAccountID: b, day: now, purpose: "", category: "内部移动", now: now)
        XCTAssertEqual(try ManualBookkeeping.available(after: change, in: ledger, now: now), before)
        try change.apply(to: &ledger)
        XCTAssertEqual(ledger.entries.last?.otherAccountID, b)
        XCTAssertEqual(ledger.entries.last?.displayTitle, "内部移动")
        XCTAssertEqual(Finance.balance(ledger.accounts[0], in: ledger, at: now), 121_800)
        XCTAssertEqual(Finance.balance(ledger.accounts[1], in: ledger, at: now), 503_200)
    }
    func testTimelineSearchDayNetAndMonthlyCashFlowUseSameRules() throws {
        var ledger = fixture(); let a = ledger.accounts[0].id
        ledger.entries = [Entry(date: now, amount: 3200, accountID: a, title: "午饭", category: "餐饮"), Entry(date: Dates.addDays(-1, to: now), amount: 800_000, nature: .income, accountID: a, title: "工资", category: "工资"), Entry(date: Dates.addDays(-1, to: now), amount: 238_000, nature: .repayment, accountID: a, title: "还款"), Entry(date: now, amount: 200, nature: .refund, accountID: a, title: "退款", category: "餐饮")]
        ledger.entries[0].note = "工作日"; ledger.entries[0].purpose = "外卖"
        var deleted = Entry(date: now, amount: 100, accountID: a, title: "删了"); deleted.deletedAt = now; ledger.entries.append(deleted)
        let sorted = ledger.entries.sorted { $0.date > $1.date }
        let months = EntryTimeline.months(sortedEntries: sorted, ledger: ledger)
        XCTAssertEqual(months.count, 1); XCTAssertEqual(months[0].days.count, 2)
        XCTAssertEqual(months[0].days[0].net, -3000); XCTAssertEqual(months[0].days[1].net, 562_000)
        let summary = Finance.cashFlow(ledger, during: Dates.calendar.dateInterval(of: .month, for: now)!)
        XCTAssertEqual(months[0].spending, summary.spending); XCTAssertEqual(months[0].income, summary.income)
        for query in ["午饭", "外卖", "工作日", "餐饮", "微信零钱", "32", "32.00", "−32.00", "-32.00", "¥32.00"] {
            XCTAssertTrue(EntryTimeline.months(sortedEntries: sorted, ledger: ledger, search: query).flatMap(\.days).flatMap(\.entries).contains { $0.id == ledger.entries[0].id }, query)
        }
        let today = TodayEntries(in: ledger, now: now)
        XCTAssertEqual(today.count, 2); XCTAssertEqual(today.net, -3000)
        XCTAssertEqual(ManualBookkeeping.dayLabel(now, now: now, includeTodayDate: true), "今天 · 10月21日")
        let midnight = Entry(date: Dates.day(now), amount: 100, accountID: a, title: "旧记录")
        XCTAssertFalse(EntryTimeline.metadata(midnight, accountNames: [a: "零钱"]).contains("00:00"))
    }
    func testManualEditKeepsProvenanceAndRejectsInvalidAmountAtomically() throws {
        var ledger = fixture()
        let change = try ManualBookkeeping.change(amount: 3200, nature: .expense, accountID: ledger.accounts[0].id, day: now, purpose: "午饭", category: "餐饮", now: now)
        try change.apply(to: &ledger)
        var edited = ledger.entries[0]; edited.amount = 3500; edited.source = "换来源"; edited.recordedAt = nil; edited.note = "补充"
        try ManualBookkeeping.edit(edited, in: &ledger)
        XCTAssertEqual(ledger.entries[0].source, "手动"); XCTAssertEqual(ledger.entries[0].recordedAt, now)
        XCTAssertEqual(ledger.entries[0].id, edited.id); XCTAssertEqual(ledger.entries[0].amount, 3500)
        let before = ledger; edited.amount = 0
        XCTAssertThrowsError(try ManualBookkeeping.edit(edited, in: &ledger)); XCTAssertEqual(ledger, before)
    }
    func testFixedFlowPreviewUsesOccurrencesExcludesRepaymentAndKeepsUnpaidObligations() {
        var ledger = fixture()
        ledger.plans = [Plan(title: "信用卡", amount: 2000, dueDate: now, nature: .repayment), Plan(title: "过期", amount: 1000, dueDate: Dates.addDays(-2, to: now))]
        let plan = Plan(title: "订阅", amount: 2500, dueDate: now, frequency: .monthly)
        let rows = FixedFlows.occurrences(in: ledger, adding: plan, now: now)
        XCTAssertEqual(rows.filter { $0.planID == plan.id }.count, 3)
        XCTAssertEqual(rows.reduce(Int64(0)) { $0 + $1.amount }, 8500)
        XCTAssertEqual(ledger.plans.count, 2)
    }
    func testFixedFlowRowsKeepUpcomingAmountsAndDropEndedArrangements() throws {
        var ledger = fixture()
        var plan = Plan(title: "订阅", amount: 2500, dueDate: now, frequency: .monthly)
        plan.accountID = ledger.accounts[0].id
        ledger.plans = [plan]
        var paid = Entry(date: now, amount: 500, accountID: ledger.accounts[0].id, title: "部分扣款")
        paid.planID = plan.id; paid.occurrence = Dates.day(now); ledger.entries = [paid]
        let row = try XCTUnwrap(FixedFlowArrangement.rows(in: ledger, now: now).first)
        XCTAssertEqual(row.amount, 2000)
        XCTAssertEqual(row.detail, "每月 21 日 · 微信零钱")
        let end = ChangeSet(source: "用户操作", reason: "结束", items: [.endPlan(plan.id, now)])
        try end.apply(to: &ledger)
        XCTAssertTrue(FixedFlowArrangement.rows(in: ledger, now: now.addingTimeInterval(1)).isEmpty)
        XCTAssertEqual(ledger.entries.count, 1)
    }
    func testDraftWithoutOtherAccountStillDecodesAndTransferPersistsIt() throws {
        let ledger = fixture()
        let draft = EntryDraft(date: now, amount: 100, amountConfirmed: true, accountID: ledger.accounts[0].id, title: "旧草稿")
        let data = try JSONEncoder().encode(draft)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "otherAccountID")
        let oldData = try JSONSerialization.data(withJSONObject: json)
        XCTAssertNil(try JSONDecoder().decode(EntryDraft.self, from: oldData).otherAccountID)
    }
    func testRentRowUsesPaymentRatherThanEarlierIncomingShare() throws {
        var ledger = fixture()
        var rent = Rent(title: "房租", monthlyTotal: 450_000, personalShare: 225_000, startDate: now,
                        nextDueDate: Dates.addDays(10, to: now), monthsPerPayment: 3, receiveDay: 21)
        rent.accountID = ledger.accounts[0].id; ledger.rents = [rent]
        let first = try XCTUnwrap(Finance.occurrences(in: ledger, now: now).first)
        XCTAssertTrue(first.inflow)
        let row = try XCTUnwrap(FixedFlowArrangement.rows(in: ledger, now: now).first)
        XCTAssertFalse(row.inflow); XCTAssertEqual(row.amount, 1_350_000)
    }
    func testPaidOneTimeArrangementIsCompleteButLaterArrangementStaysVisible() {
        var ledger = fixture()
        let once = Plan(title: "一次付款", amount: 2500, dueDate: now)
        let later = Plan(title: "明年付款", amount: 3500, dueDate: Dates.addDays(365, to: now))
        ledger.plans = [once, later]
        var payment = Entry(date: now, amount: 2500, accountID: ledger.accounts[0].id, title: "付完")
        payment.planID = once.id; payment.occurrence = Dates.day(now); ledger.entries = [payment]
        XCTAssertEqual(FixedFlowArrangement.rows(in: ledger, now: now).map(\.id), [later.id])
        XCTAssertTrue(FixedFlows.occurrences(in: ledger, now: now).isEmpty)
    }
    func testTimelineLargeLedgerGroupsAllRowsAndSearchesWithoutPerRowLedgerLookups() {
        var ledger = fixture(); let id = ledger.accounts[0].id
        ledger.entries = (0..<20_000).map { index in
            Entry(date: now.addingTimeInterval(-Double(index)), amount: 100, accountID: id, title: "记录 \(index)", category: "餐饮")
        }
        let months = EntryTimeline.months(sortedEntries: ledger.entries, ledger: ledger)
        XCTAssertEqual(months.flatMap(\.days).reduce(0) { $0 + $1.entries.count }, 20_000)
        XCTAssertEqual(months.reduce(Int64(0)) { $0 + $1.spending }, 2_000_000)
        let matching = EntryTimeline.months(sortedEntries: ledger.entries, ledger: ledger, search: "记录 19999")
        XCTAssertEqual(matching.flatMap(\.days).flatMap(\.entries).count, 1)
    }
}
