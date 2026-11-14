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
        XCTAssertEqual(pad.displayText, "50.50")
        pad.press("⌫"); XCTAssertEqual(pad.expression, "32+18.5")
        pad.press("−"); pad.press("2"); XCTAssertEqual(pad.resolve(), 4850)
        XCTAssertEqual(pad.expression, "48.5"); pad.reset(); XCTAssertEqual(pad.expression, "0")
        pad.press("."); pad.press("5"); pad.press("."); pad.press("2"); pad.press("3")
        XCTAssertEqual(pad.amount, 52)
    }
    func testKeypadResultTextUsesTwoDecimalsWithoutChangingTypedInput() {
        for (input, result) in [("0", "0.00"), ("32", "32.00"), ("38", "38.00"), ("38.", "38.00"),
                                ("38.5", "38.50"), ("38.50", "38.50"), ("0.05", "0.05"),
                                ("1234.56", "1234.56"), ("99999999999.99", "99999999999.99")] {
            var pad = EntryKeypad()
            input.forEach { pad.press(String($0)) }
            XCTAssertEqual(pad.resultText, result)
            XCTAssertEqual(pad.displayText, input)
            XCTAssertEqual(pad.expression, input)
            XCTAssertNil(pad.expressionText)
        }
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
        XCTAssertEqual(pad.resultText, "-2.00"); XCTAssertEqual(pad.displayText, "-2.00")
        pad.press("+"); pad.press("7"); XCTAssertEqual(pad.resolve(), 500)
    }
    func testKeypadPendingOperatorClearsOnDigitAndDecimalPoint() {
        var pad = EntryKeypad()
        XCTAssertNil(pad.pendingOperator)
        pad.press("1"); pad.press("2"); pad.press("+")
        XCTAssertEqual(pad.pendingOperator, "+"); XCTAssertEqual(pad.displayText, "12.00")
        pad.press("3"); XCTAssertNil(pad.pendingOperator); XCTAssertEqual(pad.displayText, "15.00")
        pad.press("−"); XCTAssertEqual(pad.pendingOperator, "−")
        pad.press("."); XCTAssertNil(pad.pendingOperator); XCTAssertEqual(pad.expressionText, "12 + 3 − 0.")
    }
    func testKeypadOperatorSwapAndBackspaceAfterOperator() {
        var pad = EntryKeypad()
        ["3", "8", "+", "−"].forEach { pad.press($0) }
        XCTAssertEqual(pad.pendingOperator, "−"); XCTAssertEqual(pad.expressionText, "38 −")
        pad.press("+"); XCTAssertEqual(pad.pendingOperator, "+"); XCTAssertEqual(pad.expressionText, "38 +")
        pad.press("⌫"); XCTAssertNil(pad.pendingOperator); XCTAssertNil(pad.expressionText)
        XCTAssertEqual(pad.expression, "38"); XCTAssertEqual(pad.amount, 3800)
        ["−", "2", "+", "⌫"].forEach { pad.press($0) }
        XCTAssertNil(pad.pendingOperator); XCTAssertEqual(pad.expressionText, "38 − 2"); XCTAssertEqual(pad.amount, 3600)
    }
    func testKeypadExpressionTextPreservesDecimalsAndFormatsOperators() {
        var pad = EntryKeypad()
        XCTAssertNil(pad.expressionText)
        "38.50".forEach { pad.press(String($0)) }
        XCTAssertNil(pad.expressionText)
        pad.press("+"); XCTAssertEqual(pad.expressionText, "38.50 +")
        XCTAssertEqual(pad.resultText, "38.50"); XCTAssertEqual(pad.displayText, "38.50")
        "12".forEach { pad.press(String($0)) }
        XCTAssertEqual(pad.expressionText, "38.50 + 12"); XCTAssertEqual(pad.resultText, "50.50")
        pad.press("-"); XCTAssertEqual(pad.pendingOperator, "−"); XCTAssertEqual(pad.expressionText, "38.50 + 12 −")
        "0.25".forEach { pad.press(String($0)) }
        XCTAssertEqual(pad.expressionText, "38.50 + 12 − 0.25"); XCTAssertEqual(pad.displayText, "50.25")
        XCTAssertEqual(pad.resolve(), 5025); XCTAssertNil(pad.expressionText); XCTAssertNil(pad.pendingOperator)
    }
    func testKeypadLeadingNegativeIsNotAnOperatorAndResetClearsState() {
        var pad = EntryKeypad()
        ["3", "−", "5"].forEach { pad.press($0) }
        XCTAssertEqual(pad.resolve(), -200); XCTAssertEqual(pad.expression, "-2")
        XCTAssertEqual(pad.resultText, "-2.00"); XCTAssertEqual(pad.displayText, "-2")
        XCTAssertNil(pad.expressionText); XCTAssertNil(pad.pendingOperator)
        pad.press("+"); XCTAssertEqual(pad.expressionText, "−2 +"); XCTAssertEqual(pad.pendingOperator, "+")
        pad.reset(); XCTAssertEqual(pad.expression, "0"); XCTAssertNil(pad.expressionText); XCTAssertNil(pad.pendingOperator)
        ["3", "−", "5"].forEach { pad.press($0) }; pad.resolve(); pad.press("⌫")
        XCTAssertEqual(pad.expression, "-"); XCTAssertNil(pad.expressionText); XCTAssertNil(pad.pendingOperator)
    }
    func testFrequentCategoriesIgnoreDeletedAndOtherNaturesAndFillDefaults() {
        var ledger = fixture(); let id = ledger.accounts[0].id
        ledger.entries = [Entry(date: now, amount: 100, accountID: id, title: "地铁", category: "交通"), Entry(date: now, amount: 100, accountID: id, title: "早餐", category: "餐饮"), Entry(date: now, amount: 100, accountID: id, title: "公交", category: "交通")]
        var deleted = Entry(amount: 100, accountID: id, title: "书", category: "学习"); deleted.deletedAt = now
        ledger.entries.append(deleted)
        ledger.entries.append(Entry(amount: 100, nature: .income, accountID: id, title: "工资", category: "工资"))
        XCTAssertEqual(ManualBookkeeping.categories(in: ledger, nature: .expense, frequentOnly: true), ["餐饮", "购物", "交通", "居住", "医疗健康"])
        XCTAssertEqual(ManualBookkeeping.categories(in: ledger, nature: .income, frequentOnly: true).first, "工资奖金")
        XCTAssertEqual(ManualBookkeeping.guessCategory("午饭", nature: .expense, in: ledger), "餐饮")
        ledger.categories.append(Category("工作餐"))
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
        let future = try ManualBookkeeping.change(amount: 100, nature: .expense, accountID: entry.accountID, day: Dates.addDays(1, to: now), purpose: "", category: "餐饮", now: now)
        XCTAssertEqual(try ManualBookkeeping.available(after: future, in: ledger, now: now), Finance.funds(ledger, now: now).available)
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
    func testTimelineFiltersCombineWithSearchAndOnlyIncludeUncategorizedEntries() {
        var ledger = fixture(); let account = ledger.accounts[0].id
        let categories = ["", " \n ", Classification.pendingCategory, "其他支出", "餐饮"]
        ledger.entries = categories.enumerated().map { index, category in
            Entry(date: now.addingTimeInterval(Double(-index)), amount: 3200, accountID: account, title: "午饭", category: category)
        }
        ledger.entries[3].classificationReason = "没分类"; ledger.entries[4].note = "朋友聚餐"
        ledger.categoryAliases["餐饮"] = "吃喝"
        let income = Entry(date: now.addingTimeInterval(-10), amount: 5000, nature: .income, accountID: account, title: "奖金", category: "奖金")
        var deleted = ledger.entries[0]; deleted.id = UUID(); deleted.deletedAt = now
        ledger.entries += [income, deleted]
        func ids(_ filter: EntryTimeline.Filter, _ query: String = "") -> [UUID] {
            EntryTimeline.months(sortedEntries: ledger.entries, ledger: ledger, search: query, filter: filter).flatMap(\.days).flatMap(\.entries).map(\.id)
        }
        XCTAssertEqual(ids(.all).count, 6)
        XCTAssertEqual(ids(.uncategorized), Array(ledger.entries.prefix(4)).map(\.id))
        XCTAssertEqual(ids(.expense), Array(ledger.entries.prefix(5)).map(\.id))
        XCTAssertEqual(ids(.income), [income.id]); XCTAssertEqual(ids(.income, "32"), [])
        XCTAssertEqual(ids(.expense, "朋友"), [ledger.entries[4].id])
        XCTAssertEqual(ids(.uncategorized, "32.00").count, 4)
        XCTAssertEqual(ids(.uncategorized, "没分类").count, 4)
        XCTAssertEqual(ids(.expense, "吃喝"), [ledger.entries[4].id])
        XCTAssertFalse(EntryTimeline.isUncategorized(Entry(date: now, amount: 100, accountID: account, title: "其他", category: "其他支出")))
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
        XCTAssertEqual(months[0].days[0].spending, 3000); XCTAssertEqual(months[0].days[1].spending, 0)
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
    func testSnapshotSearch4200RowsMatchesAllMonthsAndFilteredTotals() throws {
        var ledger = fixture(); let account = ledger.accounts[0].id
        ledger.entries = (0..<4200).map { index -> Entry in
            let date = Dates.addDays(-(index % 21), to: now).addingTimeInterval(-Double(index))
            let amount: Int64 = index % 3 == 0 ? 500 : 1200
            let nature: Nature = index % 7 == 0 ? .income : .expense
            let category = index % 11 == 0 ? Classification.pendingCategory : "餐饮"
            return Entry(date: date, amount: amount, nature: nature, accountID: account, title: "流水\(index)", category: category)
        }
        var deleted = ledger.entries[0]; deleted.id = UUID(); deleted.deletedAt = now
        let outside = Entry(date: Dates.addMonths(-1, to: now), amount: 500, accountID: account, title: "上月")
        ledger.entries += [deleted, outside]
        let before = ledger
        let sorted = ledger.entries.sorted { $0.date > $1.date }
        let snapshot = EntryTimeline.snapshot(sortedEntries: sorted, ledger: ledger, month: now, search: "5.00")
        let expectedIDs = sorted.filter { $0.deletedAt == nil && $0.amount == 500 }.map(\.id)
        XCTAssertEqual(snapshot.days.flatMap(\.entries).map(\.id), expectedIDs)
        XCTAssertEqual(expectedIDs.count, 1401)
        XCTAssertEqual(Set(snapshot.days.flatMap(\.entries).map(\.id)).count, 1401)
        let matchingSummary = EntryTimeline.months(sortedEntries: sorted, ledger: ledger, search: "5.00")
        XCTAssertEqual(snapshot.spending, matchingSummary.reduce(0) { $0 + $1.spending }); XCTAssertEqual(snapshot.income, matchingSummary.reduce(0) { $0 + $1.income })
        for filter in EntryTimeline.Filter.allCases {
            for query in ["5.00", "−5.00", "-5.00", "¥5.00", "微信零钱", "没分类", "不存在"] {
                let groups = EntryTimeline.months(sortedEntries: sorted, ledger: ledger, search: query, filter: filter)
                let expected = groups.flatMap(\.days)
                let actual = EntryTimeline.snapshot(sortedEntries: sorted, ledger: ledger, month: now, search: query, filter: filter)
                XCTAssertEqual(actual.days.map(\.id), expected.map(\.id))
                XCTAssertEqual(actual.days.map(\.spending), expected.map(\.spending))
                XCTAssertEqual(actual.days.flatMap(\.entries).map(\.id), expected.flatMap(\.entries).map(\.id))
                XCTAssertEqual(actual.spending, groups.reduce(0) { $0 + $1.spending }); XCTAssertEqual(actual.income, groups.reduce(0) { $0 + $1.income })
            }
        }
        XCTAssertEqual(snapshot, EntryTimeline.snapshot(sortedEntries: sorted, ledger: ledger, month: now, search: "5.00"))
        XCTAssertEqual(ledger, before)
    }
    func testSnapshotProjectsOnlyRowValuesAndUsesChangedLedgerWithoutTimestampChanges() throws {
        var ledger = fixture(); let account = ledger.accounts[0].id
        ledger.categoryAliases["旧餐饮"] = "餐饮"
        ledger.entries = [Entry(date: now, amount: 500, accountID: account, title: "餐饮", category: "旧餐饮"),
                          Entry(date: now.addingTimeInterval(-1), amount: 700, nature: .income, accountID: account, title: "原用途")]
        ledger.entries[1].purpose = "新用途"; ledger.entries[1].note = "备注优先"
        let first = EntryTimeline.snapshot(sortedEntries: ledger.entries, ledger: ledger, month: now)
        let rows = first.days.flatMap(\.entries)
        XCTAssertEqual(rows[0].categoryName, "餐饮"); XCTAssertEqual(rows[0].note, "")
        XCTAssertEqual(rows[0].symbol, ledger.categories.first { $0.name == "餐饮" }?.symbol)
        XCTAssertFalse(rows[0].inflow); XCTAssertFalse(rows[0].uncategorized)
        XCTAssertEqual(rows[1].categoryName, "没分类"); XCTAssertEqual(rows[1].note, "备注优先")
        XCTAssertTrue(rows[1].inflow); XCTAssertTrue(rows[1].uncategorized)
        let stamp = ledger.updatedAt
        ledger.entries[0].amount = 600; ledger.entries[0].note = "改过"
        let next = EntryTimeline.snapshot(sortedEntries: ledger.entries, ledger: ledger, month: now, search: "6.00")
        XCTAssertEqual(next.days.flatMap(\.entries).map(\.id), [rows[0].id])
        XCTAssertEqual(next.days.first?.entries.first?.note, "改过")
        XCTAssertEqual(next.spending, 600); XCTAssertEqual(first.spending, 500)
        XCTAssertEqual(ledger.updatedAt, stamp)
        ledger.accounts[0].name = "新账户"
        XCTAssertTrue(EntryTimeline.snapshot(sortedEntries: ledger.entries, ledger: ledger, month: now, search: "微信零钱").days.isEmpty)
        ledger.categoryAliases["旧餐饮"] = "新主项"
        XCTAssertEqual(EntryTimeline.snapshot(sortedEntries: ledger.entries, ledger: ledger, month: now).days.first?.entries.first?.categoryName, "新主项")
    }
    func testSnapshotPreservesRentSharesRefundsAndMonthCalendarBoundaries() {
        var ledger = fixture(); let account = ledger.accounts[0].id
        let rent = Rent(monthlyTotal: 30_000, personalShare: 10_000, startDate: now, nextDueDate: now)
        ledger.rents = [rent]
        var payment = Entry(date: now, amount: 90_000, accountID: account, title: "房租", category: "居住"); payment.rentID = rent.id
        var refund = Entry(date: now, amount: 1500, nature: .refund, accountID: account, title: "退回"); refund.personalExpense = 1000
        let income = Entry(date: now, amount: 20_000, nature: .income, accountID: account, title: "收入")
        let transfer = Entry(date: now, amount: 3000, nature: .transfer, accountID: account, title: "转账")
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let month = calendar.dateInterval(of: .month, for: now)!
        let boundary = Entry(date: month.start, amount: 500, accountID: account, title: "月初")
        let nextMonth = Entry(date: month.end, amount: 500, accountID: account, title: "下月")
        ledger.entries = [payment, refund, income, transfer, boundary, nextMonth].sorted { $0.date > $1.date }
        let value = EntryTimeline.snapshot(sortedEntries: ledger.entries, ledger: ledger, month: now, search: "¥5.00", calendar: calendar)
        XCTAssertEqual(value.spending, 1000); XCTAssertEqual(value.income, 0)
        XCTAssertEqual(value.days.flatMap(\.entries).map(\.id), [nextMonth.id, boundary.id])
        XCTAssertEqual(value.months.map(\.date), [month.end, month.start])
        let unsearched = EntryTimeline.snapshot(sortedEntries: ledger.entries, ledger: ledger, month: now, calendar: calendar)
        XCTAssertEqual(unsearched.spending, 29_500); XCTAssertEqual(unsearched.income, 20_000)
        var west = calendar; west.timeZone = TimeZone(secondsFromGMT: -8 * 3600)!
        let shifted = EntryTimeline.snapshot(sortedEntries: ledger.entries, ledger: ledger, month: now, search: "¥5.00", calendar: west)
        XCTAssertEqual(shifted.days.flatMap(\.entries).map(\.id), [nextMonth.id, boundary.id])
        XCTAssertNotEqual(shifted.days.map(\.date), value.days.map(\.date))
    }
}

final class EntryRepetitionTests: XCTestCase {
    private let now = Dates.parse("2026-11-05 14:30:00")!
    private func day(_ text: String) -> Date { Dates.parse(text)! }
    private func fixture() -> Ledger {
        var ledger = Ledger()
        ledger.accounts = [Account(name: "银行卡", balance: 100_000, at: day("2026-01-01"))]
        return ledger
    }
    private func entry(in ledger: Ledger, nature: Nature = .expense) -> Entry {
        var entry = Entry(date: now, amount: 3850, nature: nature, accountID: ledger.accounts[0].id, title: "旧标题", category: nature.inflow ? "工资奖金" : "餐饮")
        entry.purpose = " 午饭 \n"
        return entry
    }
    func testMonthlyPlanCopiesAmountDateAccountCategoryAndTrimmedPurpose() throws {
        let source = entry(in: fixture())
        let plan = try FixedFlows.monthlyPlan(from: source)
        XCTAssertEqual(plan.title, "午饭"); XCTAssertEqual(plan.amount, 3850)
        XCTAssertEqual(plan.frequency, .monthly); XCTAssertEqual(plan.dueDate, Dates.day(now)); XCTAssertEqual(plan.monthlyDay, 5)
        XCTAssertEqual(plan.accountID, source.accountID); XCTAssertEqual(plan.category, source.category)
        XCTAssertEqual(plan.nature, .expense); XCTAssertFalse(plan.inflow)
        XCTAssertFalse(plan.autoPay); XCTAssertFalse(plan.estimated); XCTAssertTrue(plan.active)
        XCTAssertNil(plan.installments); XCTAssertNil(plan.endDate)
    }
    func testEmptyPurposeFallsBackToCategoryIncludingWhitespaceAndNil() throws {
        var source = entry(in: fixture())
        for purpose in [nil, "", " \n "] as [String?] {
            source.purpose = purpose
            XCTAssertEqual(try FixedFlows.monthlyPlan(from: source).title, "餐饮")
        }
    }
    func testIncomePlanAndFirstPaymentHaveIncomeDirection() throws {
        var ledger = fixture()
        let change = try FixedFlows.monthlyEntryChange(amount: 50_000, nature: .income, accountID: ledger.accounts[0].id,
                                                      day: now, purpose: "劳务", category: "兼职劳务", now: now)
        try change.apply(to: &ledger)
        XCTAssertEqual(ledger.plans.count, 1); XCTAssertEqual(ledger.entries.count, 1)
        XCTAssertTrue(ledger.plans[0].inflow); XCTAssertEqual(ledger.plans[0].nature, .income)
        XCTAssertEqual(ledger.entries[0].nature, .income)
        XCTAssertEqual(FixedFlows.month(containing: now, in: ledger).occurrences.first?.state, .paid)
        XCTAssertEqual(Finance.occurrences(in: ledger, now: now, days: 40).first?.inflow, true)
    }
    func testNontransferSpecialNatureRetainsLedgerLinkInvariant() throws {
        var ledger = fixture(); var source = entry(in: ledger, nature: .refund)
        source.category = "餐饮"; ledger.entries = [source]
        try FixedFlows.repeatMonthly(source, in: &ledger)
        XCTAssertEqual(ledger.plans[0].nature, .refund); XCTAssertTrue(ledger.plans[0].inflow)
        XCTAssertEqual(ledger.entries[0].nature, ledger.plans[0].nature)
        XCTAssertNoThrow(try ledger.validate())
    }
    func testOneChangeSetAddsPlanAndLinkedFirstPeriodAndLeavesNextMonthUnpaid() throws {
        var ledger = fixture()
        let change = try FixedFlows.monthlyEntryChange(amount: 3850, nature: .expense, accountID: ledger.accounts[0].id,
                                                      day: now, purpose: "午饭", category: "餐饮", now: now)
        XCTAssertEqual(change.items.count, 2)
        guard case .addPlan(let proposed) = change.items[0], case .addEntry(let draft) = change.items[1] else {
            return XCTFail("Plan and payment must be atomic")
        }
        XCTAssertEqual(draft.planID, proposed.id); XCTAssertEqual(draft.occurrence, Dates.day(now))
        try change.apply(to: &ledger)
        XCTAssertEqual(ledger.entries[0].planID, ledger.plans[0].id)
        XCTAssertEqual(ledger.entries[0].occurrence, Dates.day(now)); XCTAssertEqual(ledger.entries[0].date, now)
        let month = FixedFlows.month(containing: now, in: ledger)
        XCTAssertEqual(month.occurrences.first?.state, .paid); XCTAssertEqual(month.remainingOutflow, 0)
        let next = try XCTUnwrap(Finance.occurrences(in: ledger, now: now, days: 40).first)
        XCTAssertEqual(next.planID, ledger.plans[0].id); XCTAssertEqual(next.date, day("2026-12-05")); XCTAssertEqual(next.amount, 3850)
        XCTAssertThrowsError(try FixedFlows.settle(planID: proposed.id, occurrence: now, in: ledger, now: now))
    }
    func testMonthEndRecoversOriginalDayAfterFebruary() throws {
        var ledger = fixture(); var source = entry(in: ledger)
        source.date = day("2027-01-31"); source.purpose = "房租"; ledger.entries = [source]
        try FixedFlows.repeatMonthly(source, in: &ledger)
        let dates = Finance.occurrences(in: ledger, now: source.date, days: 65).map(\.date)
        XCTAssertEqual(Array(dates.prefix(2)), [day("2027-02-28"), day("2027-03-31")])
    }
    func testEditedEntryAndPlanSaveTogetherWithoutAddingAnotherPayment() throws {
        var ledger = fixture(); let source = entry(in: ledger); ledger.entries = [source]
        var edited = source; edited.amount = 4200; edited.date = day("2026-11-04"); edited.purpose = "晚饭"
        try FixedFlows.repeatMonthly(edited, in: &ledger)
        XCTAssertEqual(ledger.entries.count, 1); XCTAssertEqual(ledger.plans.count, 1)
        XCTAssertEqual(ledger.plans[0].title, "晚饭"); XCTAssertEqual(ledger.plans[0].amount, 4200)
        XCTAssertEqual(ledger.entries[0].amount, 4200); XCTAssertTrue(ledger.entries[0].userEdited)
        XCTAssertEqual(ledger.entries[0].occurrence, day("2026-11-04"))
        XCTAssertEqual(FixedFlows.month(containing: now, in: ledger).occurrences.first?.state, .paid)
    }
    func testRepeatEditRejectsAlreadyLinkedEntryAndMissingEntryAtomically() throws {
        var ledger = fixture(); let source = entry(in: ledger); ledger.entries = [source]
        try FixedFlows.repeatMonthly(source, in: &ledger)
        let before = ledger
        XCTAssertThrowsError(try FixedFlows.repeatMonthly(ledger.entries[0], in: &ledger)); XCTAssertEqual(ledger, before)
        XCTAssertThrowsError(try FixedFlows.repeatMonthly(source, in: &ledger)); XCTAssertEqual(ledger, before)
        XCTAssertThrowsError(try FixedFlows.repeatMonthly(entry(in: ledger), in: &ledger)); XCTAssertEqual(ledger, before)
    }
    func testTransferAndInvalidAmountsAreRejectedWithoutChanges() throws {
        var ledger = fixture(); let source = entry(in: ledger, nature: .transfer); ledger.entries = [source]
        let before = ledger
        XCTAssertThrowsError(try FixedFlows.monthlyPlan(from: source))
        XCTAssertThrowsError(try FixedFlows.repeatMonthly(source, in: &ledger)); XCTAssertEqual(ledger, before)
        XCTAssertThrowsError(try FixedFlows.monthlyEntryChange(amount: 100, nature: .transfer, accountID: source.accountID,
                                                             day: now, purpose: "", category: "转账", now: now))
        for amount in [Int64(0), -1, Money.limit + 1] {
            var invalid = source; invalid.nature = .expense; invalid.amount = amount
            XCTAssertThrowsError(try FixedFlows.monthlyPlan(from: invalid))
        }
    }
    func testRecentPurposesExcludeCategoryAndSmallItemNamesBeforeLimiting() {
        var ledger = fixture()
        ledger.categories.append(Category("自定义", subcategories: ["小分类"]))
        let titles = ["餐饮", "交通", "购物", "小分类", "没分类", "自定义", "午饭", "午饭", "车票", "书店", "其他用途"]
        var entries = titles.map { Entry(date: now, amount: 100, accountID: ledger.accounts[0].id, title: $0) }
        var deleted = entries[6]; deleted.deletedAt = now; deleted.purpose = "不该出现"; entries.insert(deleted, at: 0)
        XCTAssertEqual(ManualBookkeeping.recentPurposes(sortedEntries: entries, categories: ledger.categories), ["午饭", "车票", "书店"])
        XCTAssertEqual(ManualBookkeeping.recentPurposes(sortedEntries: entries, categories: ledger.categories, limit: 0), [])
        entries[1].purpose = " 餐饮 \n"
        XCTAssertEqual(ManualBookkeeping.recentPurposes(sortedEntries: entries, categories: ledger.categories, limit: 1), ["午饭"])
    }
    func testSelectedAmountIsReplacedByDigitsOrDecimalAndEditedByDeleteOrOperator() {
        var pad = EntryKeypad(amount: 3850)
        pad.press("2", replacingAmount: true); XCTAssertEqual(pad.amount, 200)
        pad = EntryKeypad(amount: 3850); pad.press(".", replacingAmount: true)
        XCTAssertEqual(pad.expression, "0."); pad.press("5"); XCTAssertEqual(pad.amount, 50)
        pad = EntryKeypad(amount: 3850); let expression = pad.expression
        pad.press("⌫", replacingAmount: true); XCTAssertEqual(pad.expression, String(expression.dropLast()))
        for key in ["+", "−"] {
            pad = EntryKeypad(amount: 3850); pad.press(key, replacingAmount: true)
            XCTAssertEqual(pad.amount, 3850); XCTAssertEqual(pad.pendingOperator, key)
        }
        XCTAssertEqual(EntryKeypad(amount: -250).amount, -250)
    }
    func testTouchPredictionRejectsEmptyDeleteOperatorsDecimalsAndOverflowWithoutMutating() {
        for key in ["⌫", "+", "−"] {
            let pad = EntryKeypad(); var next = pad; next.press(key)
            XCTAssertEqual(next, pad)
        }
        for (amount, key) in [(Int64(123), "4"), (Money.limit, "9")] {
            let pad = EntryKeypad(amount: amount); var next = pad; next.press(key)
            XCTAssertEqual(next, pad); XCTAssertEqual(pad.amount, amount)
        }
        var pad = EntryKeypad(amount: 3850); pad.press("+"); pad.press("2"); pad.reset()
        XCTAssertEqual(pad, EntryKeypad()); XCTAssertNil(pad.expressionText); XCTAssertNil(pad.pendingOperator)
    }
}
