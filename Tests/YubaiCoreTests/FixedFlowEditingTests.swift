import XCTest
@testable import YubaiCore

final class FixedFlowEditingTests: XCTestCase {
    private let now = Dates.parse("2026-11-04 14:00:00")!
    private func day(_ text: String) -> Date { Dates.parse(text)! }
    private func fixture() -> Ledger {
        var ledger = Ledger()
        ledger.accounts = [Account(name: "银行卡", balance: 1_000_000, at: day("2026-01-01")), Account(name: "现金", balance: 100_000, at: day("2026-01-01"))]
        var plan = Plan(title: "房租", amount: 10_000, dueDate: day("2026-09-01"), frequency: .monthly, category: "居住")
        plan.accountID = ledger.accounts[0].id; ledger.plans = [plan]
        return ledger
    }
    private func pay(_ date: String, amount: Int64 = 10_000, in ledger: inout Ledger) {
        let plan = ledger.plans[0]
        var entry = Entry(date: day(date), amount: amount, nature: plan.nature, accountID: ledger.accounts[0].id, title: plan.title, category: plan.category)
        entry.planID = plan.id; entry.occurrence = day(date); entry.recordedAt = day(date)
        ledger.entries.append(entry)
    }
    private func update(_ ledger: Ledger, _ edit: (inout FixedFlowEdit) -> Void) throws -> ChangeSet {
        var value = try XCTUnwrap(FixedFlows.edit(planID: ledger.plans[0].id, in: ledger, now: now))
        edit(&value)
        return try FixedFlows.update(planID: ledger.plans[0].id, title: value.title, amount: value.amount,
                                     frequency: value.frequency, date: value.date, accountID: value.accountID,
                                     category: value.category, installments: value.installments, autoPay: value.autoPay,
                                     estimated: value.estimated, in: ledger, now: now)
    }
    private func apply(_ plan: Plan, to ledger: inout Ledger) throws {
        var change = ChangeSet(source: "用户操作", reason: "修改安排", items: [.updatePlan(plan)]); change.createdAt = now
        try change.apply(to: &ledger)
    }

    func testRenameUsesOneReplacementAndNeverChangesEntries() throws {
        var ledger = fixture(); pay("2026-09-01", in: &ledger)
        let entries = ledger.entries
        let change = try update(ledger) { $0.title = "  新房租\n"; $0.category = "其他支出"; $0.accountID = ledger.accounts[1].id }
        XCTAssertEqual(change.source, "用户操作"); XCTAssertEqual(change.items.count, 1)
        guard case .updatePlan(let replacement) = change.items[0] else { return XCTFail("需要 updatePlan") }
        XCTAssertEqual(replacement.id, ledger.plans[0].id); XCTAssertEqual(replacement.title, "新房租")
        XCTAssertTrue(change.preview(in: ledger)[0].hasPrefix("修改安排「新房租」"))
        try change.apply(to: &ledger)
        XCTAssertEqual(ledger.entries, entries); XCTAssertEqual(ledger.plans[0], replacement)
        XCTAssertEqual(ledger.plans[0].accountID, ledger.accounts[1].id); XCTAssertEqual(ledger.plans[0].category, "其他支出")
    }

    func testDirectChangeItemReplacesWholePlanByID() throws {
        var ledger = fixture(); var plan = ledger.plans[0]
        plan.title = "新安排"; plan.note = "原样保存"; plan.category = "其他支出"; plan.accountID = nil
        try apply(plan, to: &ledger)
        XCTAssertEqual(ledger.plans, [plan])
    }

    func testEditUsesEarliestUnsettledPeriodAndSkipsPaidAndWaived() throws {
        var ledger = fixture(); pay("2026-09-01", in: &ledger)
        ledger.plans[0].skippedOccurrences = [day("2026-10-01")]
        let edit = try XCTUnwrap(FixedFlows.edit(planID: ledger.plans[0].id, in: ledger, now: now))
        XCTAssertEqual(edit.date, day("2026-11-01")); XCTAssertEqual(edit.amount, 10_000)
        XCTAssertFalse(edit.inflow); XCTAssertFalse(edit.stopped)
        XCTAssertNil(FixedFlows.edit(planID: UUID(), in: ledger, now: now))
    }

    func testEditExhaustedInstallmentsFallsBackToNextPeriod() throws {
        var ledger = fixture(); ledger.plans[0].installments = 2
        pay("2026-09-01", in: &ledger); pay("2026-10-01", in: &ledger)
        XCTAssertEqual(FixedFlows.edit(planID: ledger.plans[0].id, in: ledger, now: now)?.date, day("2026-12-01"))
    }

    func testEditPrepaidFutureInstallmentsUsesPeriodAfterLastPaid() throws {
        var ledger = fixture(); ledger.plans[0].dueDate = day("2026-11-01"); ledger.plans[0].installments = 2
        pay("2026-11-01", in: &ledger); pay("2026-12-01", in: &ledger)
        XCTAssertEqual(FixedFlows.edit(planID: ledger.plans[0].id, in: ledger, now: now)?.date, day("2027-01-01"))
    }

    func testNoChangesIsRecognizableIncludingEstimatedAmountAndClampedMonthlyDay() throws {
        var ledger = fixture(); ledger.plans[0].estimated = true; ledger.plans[0].monthlyDay = 31
        ledger.plans[0].dueDate = day("2026-09-30"); pay("2026-09-30", amount: 12_000, in: &ledger)
        XCTAssertEqual(FixedFlows.edit(planID: ledger.plans[0].id, in: ledger, now: now)?.amount, 12_000)
        XCTAssertThrowsError(try update(ledger) { _ in }) { XCTAssertEqual($0 as? FixedFlowEditError, .noChanges) }
        try update(ledger) { $0.title = "租金" }.apply(to: &ledger)
        XCTAssertEqual(ledger.plans[0].dueDate, day("2026-09-30")); XCTAssertEqual(ledger.plans[0].monthlyDay, 31)
        XCTAssertEqual(ledger.plans[0].amount, 10_000); XCTAssertEqual(FixedFlowPayments(in: ledger).amount(for: ledger.plans[0]), 12_000)
    }

    func testAmountIncreaseKeepsPaidPeriodAndRecalculatesPartialRemainder() throws {
        var ledger = fixture(); pay("2026-09-01", in: &ledger); pay("2026-10-01", amount: 4000, in: &ledger)
        let entries = ledger.entries
        try update(ledger) { $0.amount = 15_000 }.apply(to: &ledger)
        let plan = ledger.plans[0]; let payments = FixedFlowPayments(in: ledger)
        XCTAssertEqual(payments.remaining(for: plan, on: day("2026-09-01")), 0)
        XCTAssertEqual(payments.remaining(for: plan, on: day("2026-10-01")), 11_000)
        XCTAssertEqual(payments.remaining(for: plan, on: day("2026-11-01")), 15_000)
        let row = try XCTUnwrap(FixedFlows.month(containing: day("2026-09-10"), in: ledger).occurrences.first)
        XCTAssertEqual(row.state, .paid); XCTAssertEqual(row.amount, 10_000); XCTAssertEqual(ledger.entries, entries)
        try update(ledger) { $0.amount = 20_000 }.apply(to: &ledger)
        XCTAssertEqual(FixedFlowPayments(in: ledger).remaining(for: ledger.plans[0], on: day("2026-09-01")), 0)
    }

    func testEstimatedToggleAndExplicitEstimatePreservePaidPeriodsAndLearnNewPayment() throws {
        var ledger = fixture(); ledger.plans[0].estimated = true
        pay("2026-09-01", amount: 13_000, in: &ledger)
        try update(ledger) { $0.amount = 16_000 }.apply(to: &ledger)
        XCTAssertEqual(FixedFlowPayments(in: ledger).amount(for: ledger.plans[0]), 16_000)
        pay("2026-10-01", amount: 1000, in: &ledger)
        try update(ledger) { $0.estimated = false; $0.amount = 20_000 }.apply(to: &ledger)
        let payments = FixedFlowPayments(in: ledger)
        XCTAssertEqual(payments.remaining(for: ledger.plans[0], on: day("2026-09-01")), 0)
        XCTAssertEqual(payments.remaining(for: ledger.plans[0], on: day("2026-10-01")), 0)
        try update(ledger) { $0.estimated = true }.apply(to: &ledger)
        var settlement = try FixedFlows.settle(planID: ledger.plans[0].id, occurrence: day("2026-11-01"), amount: 17_000, in: ledger, now: Dates.addDays(1, to: now))
        settlement.createdAt = Dates.addDays(1, to: now); try settlement.apply(to: &ledger)
        XCTAssertEqual(FixedFlowPayments(in: ledger).amount(for: ledger.plans[0]), 17_000)
    }

    func testExplicitEstimateCanReturnToStoredFallbackAmount() throws {
        var ledger = fixture(); ledger.plans[0].estimated = true; pay("2026-09-01", amount: 13_000, in: &ledger)
        let change = try update(ledger) { $0.amount = 10_000 }
        XCTAssertTrue(change.preview(in: ledger)[0].contains("金额："))
        try change.apply(to: &ledger)
        XCTAssertEqual(FixedFlowPayments(in: ledger).amount(for: ledger.plans[0]), 10_000)
        XCTAssertEqual(FixedFlowPayments(in: ledger).remaining(for: ledger.plans[0], on: day("2026-09-01")), 0)
    }

    func testRescheduleRetainsPaidRowsDropsOldUnrecordedAndAvoidsMonthlyDuplicates() throws {
        var ledger = fixture(); ledger.plans[0].dueDate = day("2026-09-04")
        pay("2026-09-04", in: &ledger); pay("2026-11-04", in: &ledger)
        let entries = ledger.entries
        try update(ledger) { $0.date = day("2026-11-20"); $0.amount = 15_000 }.apply(to: &ledger)
        let plan = ledger.plans[0]
        XCTAssertEqual(plan.monthlyDay, 20); XCTAssertNil(plan.occurrenceIndex(on: day("2026-10-04")))
        XCTAssertTrue(Finance.occurrences(in: ledger, now: now, days: 60).allSatisfy { $0.date >= day("2026-11-20") })
        let rows = FixedFlows.month(containing: now, in: ledger).occurrences
        XCTAssertEqual(rows.map(\.date), [day("2026-11-04"), day("2026-11-20")])
        XCTAssertEqual(rows.map(\.state), [.paid, .upcoming]); XCTAssertEqual(rows.map(\.amount), [10_000, 15_000])
        XCTAssertEqual(Set(rows.map(\.id)).count, rows.count); XCTAssertEqual(ledger.entries, entries)
        XCTAssertEqual(FixedFlows.month(containing: day("2026-09-10"), in: ledger).occurrences.first?.state, .paid)
        XCTAssertTrue(FixedFlows.month(containing: day("2026-10-10"), in: ledger).occurrences.isEmpty)
        ledger = try LedgerCodec.decode(LedgerCodec.encode(ledger))
        XCTAssertEqual(FixedFlows.month(containing: now, in: ledger).occurrences.map(\.state), [.paid, .upcoming])
    }

    func testRescheduleOntoPaidDateMergesOneRowAndCanBeRepeated() throws {
        var ledger = fixture(); pay("2026-09-01", in: &ledger); pay("2026-11-01", in: &ledger)
        try update(ledger) { $0.date = day("2026-11-01") }.apply(to: &ledger)
        XCTAssertEqual(FixedFlows.month(containing: now, in: ledger).occurrences.count, 1)
        XCTAssertEqual(FixedFlows.month(containing: now, in: ledger).occurrences.first?.state, .paid)
        try update(ledger) { $0.date = day("2026-12-15") }.apply(to: &ledger)
        XCTAssertEqual(FixedFlows.month(containing: now, in: ledger).occurrences.count, 1)
        XCTAssertEqual(FixedFlows.month(containing: now, in: ledger).occurrences.first?.state, .paid)
    }

    func testRescheduleRetainsPartialPaymentAndItsNewRemainder() throws {
        var ledger = fixture(); pay("2026-10-01", amount: 4000, in: &ledger)
        try update(ledger) { $0.date = day("2026-11-20"); $0.amount = 12_000 }.apply(to: &ledger)
        let row = try XCTUnwrap(FixedFlows.month(containing: day("2026-10-10"), in: ledger).occurrences.first)
        XCTAssertEqual(row.state, .due); XCTAssertEqual(row.amount, 8000)
        try FixedFlows.settle(planID: ledger.plans[0].id, occurrence: day("2026-10-01"), in: ledger, now: now).apply(to: &ledger)
        XCTAssertEqual(FixedFlowPayments(in: ledger).remaining(for: ledger.plans[0], on: day("2026-10-01")), 0)
    }

    func testFrequencyChangeStartsAtSelectedDateAndKeepsPaidHistory() throws {
        var ledger = fixture(); pay("2026-09-01", in: &ledger)
        try update(ledger) { $0.frequency = .weekly; $0.date = day("2026-11-06") }.apply(to: &ledger)
        XCTAssertNil(ledger.plans[0].monthlyDay)
        XCTAssertEqual(FixedFlows.month(containing: now, in: ledger).occurrences.map(\.date), [day("2026-11-06"), day("2026-11-13"), day("2026-11-20"), day("2026-11-27")])
        XCTAssertEqual(FixedFlows.month(containing: day("2026-09-10"), in: ledger).occurrences.first?.state, .paid)
    }

    func testFrequencyOnlyChangeUsesEditDateRatherThanOriginalStart() throws {
        var ledger = fixture(); pay("2026-09-01", in: &ledger); pay("2026-10-01", in: &ledger)
        try update(ledger) { $0.frequency = .quarterly }.apply(to: &ledger)
        XCTAssertEqual(ledger.plans[0].dueDate, day("2026-11-01"))
        XCTAssertEqual(FixedFlows.month(containing: day("2027-02-10"), in: ledger).occurrences.first?.date, day("2027-02-01"))
    }

    func testIncomingPlanKeepsDirectionAndNewDateBecomesPayday() throws {
        var ledger = fixture(); ledger.plans[0].inflow = true; ledger.plans[0].nature = .income
        pay("2026-09-01", in: &ledger)
        try update(ledger) { $0.title = "工资"; $0.date = day("2026-11-20"); $0.amount = 800_000; $0.category = "工资奖金" }.apply(to: &ledger)
        XCTAssertTrue(ledger.plans[0].inflow); XCTAssertEqual(ledger.plans[0].nature, .income)
        XCTAssertEqual(Finance.nextPayday(in: ledger, now: now)?.date, day("2026-11-20"))
        XCTAssertEqual(FixedFlows.month(containing: day("2026-09-10"), in: ledger).occurrences.first?.state, .paid)
    }

    func testStoppedRescheduledIncomeWithPrepaidFutureHistoryDoesNotSetPayday() throws {
        var ledger = fixture(); ledger.plans[0].inflow = true; ledger.plans[0].nature = .income
        pay("2026-12-01", in: &ledger)
        try update(ledger) { $0.date = day("2026-11-01") }.apply(to: &ledger)
        try FixedFlows.stop(planID: ledger.plans[0].id, resolution: .skip, in: ledger, now: now).apply(to: &ledger)
        XCTAssertTrue(ledger.plans[0].active); XCTAssertEqual(ledger.plans[0].endDate, now)
        XCTAssertNil(Finance.nextPayday(in: ledger, now: now))
    }

    func testInstallmentsRemainTotalWithCorrectOrdinalsAndPaidCountAfterDateChange() throws {
        var ledger = fixture(); ledger.plans[0].installments = 6
        pay("2026-09-01", in: &ledger); pay("2026-10-01", in: &ledger)
        try update(ledger) { $0.date = day("2026-11-20") }.apply(to: &ledger)
        let arrangement = try XCTUnwrap(FixedFlowArrangement.rows(in: ledger, now: now).first)
        XCTAssertEqual(arrangement.total, 6); XCTAssertEqual(arrangement.paidCount, 2)
        let row = try XCTUnwrap(FixedFlows.month(containing: now, in: ledger).occurrences.first)
        XCTAssertEqual(row.installment?.index, 3); XCTAssertEqual(row.installment?.total, 6)
        XCTAssertEqual(ledger.plans[0].schedule(through: day("2027-12-31")).map(\.date), [day("2026-09-01"), day("2026-10-01"), day("2026-11-20"), day("2026-12-20"), day("2027-01-20"), day("2027-02-20")])
        XCTAssertNil(ledger.plans[0].occurrenceIndex(on: day("2027-03-20")))
        try update(ledger) { $0.date = day("2026-12-05"); $0.installments = 5 }.apply(to: &ledger)
        XCTAssertEqual(FixedFlows.month(containing: day("2026-12-10"), in: ledger).occurrences.first?.installment?.index, 3)
        XCTAssertEqual(FixedFlowArrangement.rows(in: ledger, now: now).first?.paidCount, 2)
        XCTAssertThrowsError(try update(ledger) { $0.installments = 1 })
    }

    func testFuturePaidInstallmentOnNewScheduleCountsOnceInChronologicalOrder() throws {
        var ledger = fixture(); ledger.plans[0].installments = 4; pay("2026-12-01", in: &ledger)
        try update(ledger) { $0.date = day("2026-11-01") }.apply(to: &ledger)
        XCTAssertEqual(ledger.plans[0].schedule(through: day("2027-12-31")).map(\.date), [day("2026-11-01"), day("2026-12-01"), day("2027-01-01"), day("2027-02-01")])
        let row = try XCTUnwrap(FixedFlows.month(containing: day("2026-12-10"), in: ledger).occurrences.first)
        XCTAssertEqual(row.state, .paid); XCTAssertEqual(row.installment?.index, 2)
    }

    func testRescheduleRetainsOnlySkippedDatesOnNewScheduleAndResetsMonthDay() throws {
        var ledger = fixture(); ledger.plans[0].monthlyDay = 1
        ledger.plans[0].skippedOccurrences = [day("2026-10-01"), day("2026-12-01")]
        try update(ledger) { $0.date = day("2026-11-01") }.apply(to: &ledger)
        XCTAssertEqual(ledger.plans[0].skippedOccurrences, [day("2026-12-01")])
        try update(ledger) { $0.date = day("2026-11-30") }.apply(to: &ledger)
        XCTAssertTrue(ledger.plans[0].skippedOccurrences.isEmpty); XCTAssertEqual(ledger.plans[0].monthlyDay, 30)
    }

    func testReducingTotalPrunesWaivedPeriodsBeyondNewEnd() throws {
        var ledger = fixture(); ledger.plans[0].installments = 6
        ledger.plans[0].skippedOccurrences = [day("2027-02-01")]
        try update(ledger) { $0.installments = 3 }.apply(to: &ledger)
        XCTAssertTrue(ledger.plans[0].skippedOccurrences.isEmpty)
        XCTAssertEqual(ledger.plans[0].schedule(through: day("2027-12-31")).count, 3)
    }

    func testStoppedPlanRemainsStoppedAfterRenameAmountAndFutureDateChange() throws {
        var ledger = fixture(); ledger.plans[0].installments = 6; pay("2026-09-01", in: &ledger)
        try FixedFlows.stop(planID: ledger.plans[0].id, resolution: .skip, in: ledger, now: now).apply(to: &ledger)
        let stopped = ledger.plans[0]
        try update(ledger) { $0.title = "已停房租"; $0.amount = 13_000; $0.date = day("2026-12-20") }.apply(to: &ledger)
        XCTAssertEqual(ledger.plans[0].active, stopped.active); XCTAssertEqual(ledger.plans[0].stoppedAt, stopped.stoppedAt)
        XCTAssertEqual(ledger.plans[0].endDate, stopped.endDate); XCTAssertTrue(FixedFlows.edit(planID: stopped.id, in: ledger, now: now)?.stopped == true)
        XCTAssertTrue(FixedFlows.month(containing: now, in: ledger).occurrences.isEmpty)
        XCTAssertEqual(FixedFlowArrangement.stopped(in: ledger, now: now).first?.paidCount, 1)
        try ledger.validate()
        ledger.plans[0].active = false
        try update(ledger) { $0.title = "取消的房租" }.apply(to: &ledger)
        XCTAssertFalse(ledger.plans[0].active)
    }

    func testDirectionCannotChangeThroughEitherFieldAndFailuresAreAtomic() throws {
        let original = fixture()
        for field in 0..<3 {
            var ledger = original; var plan = ledger.plans[0]
            if field != 1 { plan.inflow = true }; if field != 0 { plan.nature = .income }
            XCTAssertThrowsError(try apply(plan, to: &ledger)) { XCTAssertEqual($0.localizedDescription, "不能把要付改为要收，或把要收改为要付。") }
            XCTAssertEqual(ledger, original)
        }
    }

    func testMissingPlanAccountBlankTitleInvalidAmountAndDatesThrowChineseErrors() throws {
        let original = fixture()
        for field in 0..<8 {
            var ledger = original; var plan = ledger.plans[0]
            switch field {
            case 0: plan.id = UUID()
            case 1: plan.accountID = UUID()
            case 2: plan.title = " \n\t"
            case 3: plan.amount = 0
            case 4: plan.amount = -1
            case 5: plan.dueDate = Date(timeIntervalSince1970: .infinity)
            case 6: plan.dueDate = Date(timeIntervalSince1970: .nan)
            default: plan.amount = Money.limit + 1
            }
            XCTAssertThrowsError(try apply(plan, to: &ledger)) { XCTAssertNotNil($0 as? YubaiError) }
            XCTAssertEqual(ledger, original)
        }
        XCTAssertThrowsError(try update(original) { $0.accountID = UUID() }) { XCTAssertEqual($0.localizedDescription, "资金安排的账户不存在。") }
        XCTAssertThrowsError(try update(original) { $0.autoPay = true; $0.accountID = nil }) { XCTAssertEqual($0.localizedDescription, "自动记需要选择账户。") }
        var ledger = original; var plan = ledger.plans[0]; plan.accountID = nil; plan.autoPay = true
        XCTAssertThrowsError(try apply(plan, to: &ledger))
    }

    func testAutoPayStartsTodayDoesNotBackfillAndPreservesOriginalStartWhileOn() throws {
        var ledger = fixture()
        try update(ledger) { $0.autoPay = true }.apply(to: &ledger)
        XCTAssertEqual(ledger.plans[0].autoPaySince, Dates.day(now)); XCTAssertNil(FixedFlows.autoSettle(in: ledger, now: now))
        try update(ledger) { $0.title = "自动房租" }.apply(to: &ledger)
        XCTAssertEqual(ledger.plans[0].autoPaySince, Dates.day(now))
        ledger.plans[0].autoPaySince = day("2026-09-15")
        try update(ledger) { $0.amount = 12_000 }.apply(to: &ledger)
        XCTAssertEqual(ledger.plans[0].autoPaySince, day("2026-09-15"))
        try update(ledger) { $0.autoPay = false }.apply(to: &ledger)
        try update(ledger) { $0.autoPay = true }.apply(to: &ledger)
        XCTAssertEqual(ledger.plans[0].autoPaySince, Dates.day(now))
    }

    func testCategoriesReuseLedgerDirectionVisibilityAndCustomCategories() {
        var ledger = fixture()
        ledger.categories += [Category("自定支出"), Category("自定收入", income: true), Category("隐藏支出", hidden: true)]
        XCTAssertEqual(FixedFlows.categories(inflow: false, in: ledger), ledger.categoryNames(income: false))
        XCTAssertEqual(FixedFlows.categories(inflow: true, in: ledger), ledger.categoryNames(income: true))
        XCTAssertTrue(FixedFlows.categories(inflow: false, in: ledger).contains("自定支出"))
        XCTAssertFalse(FixedFlows.categories(inflow: false, in: ledger).contains("自定收入"))
        XCTAssertFalse(FixedFlows.categories(inflow: false, in: ledger).contains("隐藏支出"))
        XCTAssertEqual(Plan(title: "新安排", amount: 100, dueDate: now).category, Classification.pendingCategory)
    }

    func testPreviewDescribesEveryEditableField() throws {
        let ledger = fixture()
        let change = try update(ledger) {
            $0.title = "新租金"; $0.amount = 12_000; $0.frequency = .quarterly; $0.date = day("2026-11-20")
            $0.accountID = ledger.accounts[1].id; $0.category = "其他支出"; $0.installments = 6; $0.autoPay = true; $0.estimated = true
        }
        for showPrevious in [false, true] {
            let line = try XCTUnwrap(change.preview(in: ledger, showPreviousValues: showPrevious).first)
            for field in ["修改安排「新租金」", "名字：", "金额：", "日期/频率：", "账户：", "分类：", "共几期：", "自动记：", "金额会变："] {
                XCTAssertTrue(line.contains(field), line)
            }
        }
    }

    func testSnapshotUndoRestoresSchedulePaymentsAndAllMetadata() throws {
        var ledger = fixture(); ledger.plans[0].installments = 6; pay("2026-09-01", in: &ledger)
        let original = ledger; let snapshot = try LedgerCodec.encode(ledger)
        let change = try update(ledger) { $0.title = "改过"; $0.amount = 15_000; $0.date = day("2026-11-20"); $0.autoPay = true }
        let decoded = try JSONDecoder().decode(ChangeSet.self, from: JSONEncoder().encode(change))
        XCTAssertEqual(decoded, change); try decoded.apply(to: &ledger); XCTAssertNotEqual(ledger, original)
        ledger = try LedgerCodec.decode(snapshot)
        XCTAssertEqual(ledger, original); XCTAssertEqual(ledger.plans[0].dueDate, day("2026-09-01"))
        XCTAssertTrue(ledger.plans[0].settledOccurrences.isEmpty); XCTAssertTrue(ledger.plans[0].previousOccurrences.isEmpty)
    }

    func testOldLedgerAndOldAddPlanChangeSetDecodeWithoutNewKeys() throws {
        let ledger = fixture(); let plan = ledger.plans[0]
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: LedgerCodec.encode(ledger)) as? [String: Any])
        var oldPlan = try XCTUnwrap((object["plans"] as? [[String: Any]])?.first)
        for key in ["previousOccurrences", "settledOccurrences", "estimatedAmountSince", "autoPay", "autoPaySince", "estimated", "installments", "skippedOccurrences", "monthlyDay"] { oldPlan.removeValue(forKey: key) }
        object["plans"] = [oldPlan]
        let decoded = try LedgerCodec.decode(JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(decoded.plans[0].id, plan.id); XCTAssertFalse(decoded.plans[0].autoPay)
        XCTAssertTrue(decoded.plans[0].previousOccurrences.isEmpty); XCTAssertTrue(decoded.plans[0].settledOccurrences.isEmpty)
        XCTAssertNil(decoded.plans[0].estimatedAmountSince)
        let change = ChangeSet(source: "用户操作", reason: "旧添加", items: [.addPlan(plan)])
        var oldChange = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(change)) as? [String: Any])
        // Dates in the plain ChangeSet use JSONEncoder's reference-date strategy.
        var payload = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(plan)) as? [String: Any])
        for key in ["previousOccurrences", "settledOccurrences", "estimatedAmountSince"] { payload.removeValue(forKey: key) }
        oldChange["items"] = [["addPlan": ["_0": payload]], ["endPlan": ["_0": plan.id.uuidString, "_1": now.timeIntervalSinceReferenceDate]]]
        let restored = try JSONDecoder().decode(ChangeSet.self, from: JSONSerialization.data(withJSONObject: oldChange))
        XCTAssertEqual(restored.items, [.addPlan(plan), .endPlan(plan.id, now)])
        var empty = ledger; empty.plans = []
        try restored.apply(to: &empty); XCTAssertEqual(empty.plans[0].id, plan.id)
    }

    func testCategoryRenameRewritesPendingUpdatePlan() throws {
        var ledger = fixture(); ledger.plans[0].category = "会员订阅"
        ledger.pendingChanges = [try update(ledger) { $0.title = "订阅新名" }]
        try CategoryModel.rename("会员订阅", to: "会员", income: false, in: &ledger)
        guard case .updatePlan(let plan) = ledger.pendingChanges[0].items[0] else { return XCTFail("需要 updatePlan") }
        XCTAssertEqual(plan.category, "会员")
    }
}


extension FixedFlowEditingTests {
    func testIncomeDestinationCanBeTheOnlyEditAndDoesNotRewriteSettledEntries() throws {
        var l = fixture()
        l.plans[0].inflow = true; l.plans[0].nature = .income; l.plans[0].category = "补贴"
        pay("2026-09-01", in: &l)
        let history = l.entries
        let value = try XCTUnwrap(FixedFlows.edit(planID: l.plans[0].id, in: l, now: now))
        XCTAssertFalse(value.intoFixedSavings)
        let change = try FixedFlows.update(planID: l.plans[0].id, title: value.title, amount: value.amount,
            frequency: value.frequency, date: value.date, accountID: value.accountID, category: value.category,
            installments: value.installments, autoPay: value.autoPay, estimated: value.estimated, in: l, now: now, intoFixedSavings: true)
        try change.apply(to: &l)
        XCTAssertTrue(l.plans[0].intoFixedSavings)
        XCTAssertTrue(try XCTUnwrap(FixedFlows.edit(planID: l.plans[0].id, in: l, now: now)).intoFixedSavings)
        XCTAssertEqual(l.entries, history)
        try FixedFlows.settle(planID: l.plans[0].id, occurrence: value.date, in: l, now: now).apply(to: &l)
        XCTAssertTrue(try XCTUnwrap(l.entries.last).intoFixedSavings)
        XCTAssertEqual(l.fixedSavingsTotal(now: now), value.amount)
        let after = try XCTUnwrap(FixedFlows.edit(planID: l.plans[0].id, in: l, now: now))
        let turnOff = try FixedFlows.update(planID: l.plans[0].id, title: after.title, amount: after.amount,
            frequency: after.frequency, date: after.date, accountID: after.accountID, category: after.category,
            installments: after.installments, autoPay: after.autoPay, estimated: after.estimated, in: l, now: now, intoFixedSavings: false)
        try turnOff.apply(to: &l)
        XCTAssertFalse(l.plans[0].intoFixedSavings)
        XCTAssertTrue(try XCTUnwrap(l.entries.last).intoFixedSavings)
    }
}
