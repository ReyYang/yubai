import XCTest
@testable import YubaiCore

final class SavingsWorkedExampleTests: XCTestCase {
    private func d(_ value: String) -> Date { Dates.parse(value)! }
    private var now: Date { d("2026-11-20 12:00") }
    private func ledger() -> Ledger {
        var value = Ledger()
        value.accounts = [Account(name: "工资卡", balance: 300_000, at: d("2026-11-09"))]
        value.fixedSavings = 300_000; value.savingRule = .fixed(200_000); value.cycleAnchor = .payday
        var salary = Plan(title: "工资", amount: 801_000, dueDate: d("2026-10-10"), frequency: .monthly, inflow: true, category: "工资", nature: .income)
        salary.accountID = value.accounts[0].id; value.plans = [salary]
        var income = Entry(date: d("2026-11-10 09:00"), amount: 801_000, nature: .income, accountID: value.accounts[0].id, title: "工资", category: "工资")
        income.planID = salary.id; income.occurrence = d("2026-11-10"); value.entries = [income]
        value.entries.append(Entry(date: d("2026-11-19"), amount: 83_600, accountID: value.accounts[0].id, title: "日常", category: "购物"))
        value.plans.append(Plan(title: "房租", amount: 331_000, dueDate: d("2026-11-25")))
        var yearly = Plan(title: "年付", amount: 360_000, dueDate: d("2027-10-01"), frequency: .yearly)
        yearly.yearlyReserveSince = d("2026-11-01"); value.plans.append(yearly)
        return value
    }
    private func assertIdentity(_ value: Ledger, at date: Date? = nil, file: StaticString = #filePath, line: UInt = #line) {
        let f = Finance.spendableBreakdown(value, now: date ?? now)
        XCTAssertEqual(f.rows.reduce(0) { $0 + $1.amount }, f.available - f.deficit, file: file, line: line)
        XCTAssertEqual(f.rawR, f.income + f.carry - f.plannedSaving - f.billsRest - f.spent + f.withdrawal - f.balanceGap, file: file, line: line)
    }
    func testWorkedExerciseMatchesBoardWithoutAnnualReserve() {
        let value = ledger(), formula = Finance.spendableBreakdown(value, now: now)
        XCTAssertEqual(formula.income, 801_000); XCTAssertEqual(formula.plannedSaving, 200_000)
        XCTAssertEqual(formula.billsRest, 331_000); XCTAssertEqual(formula.rows.map(\.kind), [.income, .saving, .bills, .spent])
        XCTAssertEqual(formula.spent, 83_600); XCTAssertEqual(formula.available, 186_400)
        assertIdentity(value)
    }
    func testWorkedExerciseShowsOverspendWithoutShrinkingSaving() {
        var value = ledger(); value.entries.append(Entry(date: now, amount: 200_000, accountID: value.accounts[0].id, title: "旅行", category: "旅行"))
        let f = Finance.spendableBreakdown(value, now: now)
        XCTAssertEqual(f.available, 0); XCTAssertEqual(f.deficit, 13_600); XCTAssertEqual(f.headlineTitle, "超支")
        XCTAssertEqual(f.rows.first { $0.kind == .saving }?.amount, -200_000); assertIdentity(value)
    }
    func testIncomeSourceResolvesTheActualPostedEntry() {
        let value = ledger(), formula = Finance.spendableBreakdown(value, now: now)
        XCTAssertEqual(formula.rows.first?.entryIDs, [value.entries[0].id]); XCTAssertEqual(formula.income, 801_000)
    }
    private func preparedExercise(_ ledger: Ledger, at now: Date) -> SpendableBreakdown { Finance.spendableBreakdown(ledger, now: now) }
    func testPreparedExerciseRefreshesAfterSalaryEditAndSavingsTransfer() throws {
        var value = ledger(); let before = preparedExercise(value, at: now)
        value.entries[0].amount += 50_000
        let edited = preparedExercise(value, at: now)
        XCTAssertEqual(edited.income, 851_000); XCTAssertEqual(edited.available, before.available + 50_000)
        try Reserve.transfer(.take, amount: 25_000, in: &value, now: now)
        let taken = preparedExercise(value, at: now)
        XCTAssertEqual(taken.available, edited.available + 25_000); assertIdentity(value)
    }
    func testPreparedExerciseRefreshesAtPostingBoundaryAndHandlesFallback() {
        var value = ledger(); let posting = now.addingTimeInterval(3600)
        let future = Entry(date: posting, amount: 1234, accountID: value.accounts[0].id, title: "晚饭", category: "餐饮")
        value.entries.append(future)
        let before = preparedExercise(value, at: now), after = preparedExercise(value, at: posting)
        XCTAssertFalse(before.rows.first { $0.kind == .spent }!.entryIDs.contains(future.id))
        XCTAssertTrue(after.rows.first { $0.kind == .spent }!.entryIDs.contains(future.id))
        XCTAssertEqual(after.available, before.available - 1234)
        let unknown = Finance.spendableBreakdown(Ledger(), now: now)
        XCTAssertEqual(unknown.state, .spentFallback); XCTAssertNil(unknown.waterBar); XCTAssertFalse(unknown.offersFormula)
    }
    func testOtherIncomeKeepsItsEntryIntervalAndSource() {
        var value = ledger(); value.entries[0].title = "收入"; value.entries[0].category = "其他收入"
        value.entries[0].planID = nil; value.entries[0].occurrence = nil
        let formula = Finance.spendableBreakdown(value, now: now)
        XCTAssertEqual(formula.rows.first?.entryIDs, [value.entries[0].id]); XCTAssertTrue(formula.interval.contains(value.entries[0].date)); assertIdentity(value)
    }
    func testWorkedExerciseIgnoresAnchorsProtectedBalancesAndTransfers() throws {
        var value = ledger(); let before = Finance.spendableBreakdown(value, now: now)
        value.accounts.append(Account(name: "另一张卡", balance: 80_000, at: now))
        value.accounts.append(Account(name: "信用卡", kind: .credit, balance: -5000, at: now))
        value.goals = [Goal(title: "旧目标", target: 20_000, reserved: 10_000)]
        value.entries.append(Entry(date: now, amount: 1234, nature: .unknownIn, accountID: value.accounts[0].id, title: "进账"))
        XCTAssertEqual(Finance.spendableBreakdown(value, now: now), before)
        try Reserve.transfer(.take, amount: 50_000, in: &value, now: now); assertIdentity(value)
        try Reserve.transfer(.putBack, amount: 20_000, in: &value, now: now); assertIdentity(value)
    }
    func testWorkedExercisePaidBillMovesFromDueToSpentOnlyOnce() throws {
        var value = ledger(); let before = Finance.spendableBreakdown(value, now: now)
        var expense = Entry(date: now, amount: 331_000, accountID: value.accounts[0].id, title: "房租", category: "居住")
        expense.planID = value.plans[1].id; expense.occurrence = value.plans[1].dueDate; value.entries.append(expense)
        let after = Finance.spendableBreakdown(value, now: now)
        XCTAssertEqual(after.billsRest, 0); XCTAssertEqual(after.spent, 414_600); XCTAssertEqual(after.available, before.available); assertIdentity(value)
    }
    func testTakingUpdatesSavingsSpendableCardAndRecordsWithoutCashPosting() throws {
        var value = ledger(); let cash = Finance.funds(value, now: now).cash, count = value.entries.count
        let preview = Reserve.transferPreview(value, direction: .take, amount: 50_000, now: now)
        XCTAssertTrue(preview.valid); XCTAssertEqual(preview.savedBefore, 500_000); XCTAssertEqual(preview.savedAfter, 450_000)
        let row = try Reserve.transfer(.take, amount: 50_000, in: &value, now: now)
        XCTAssertEqual(value.entries.count, count); XCTAssertEqual(Finance.funds(value, now: now).cash, cash)
        XCTAssertEqual(Finance.funds(value, now: now).available, 236_400)
        XCTAssertEqual(Reserve.overview(value, now: now).total, 450_000)
        XCTAssertEqual(HomeSavingCard.make(value, now: now).total, 450_000)
        XCTAssertEqual(Reserve.overview(value, now: now).lines.first { $0.id == "transfer:" + row.id.uuidString }?.amount, -50_000)
        assertIdentity(value)
    }
    func testPuttingBackUpdatesBothTotalsAndRecords() throws {
        var value = ledger()
        let row = try Reserve.transfer(.putBack, amount: 50_000, in: &value, now: now)
        XCTAssertEqual(Reserve.overview(value, now: now).total, 550_000)
        XCTAssertEqual(HomeSavingCard.make(value, now: now).total, 550_000)
        XCTAssertEqual(Finance.funds(value, now: now).available, 136_400)
        XCTAssertEqual(Reserve.overview(value, now: now).lines.first { $0.id == "transfer:" + row.id.uuidString }?.amount, 50_000)
        XCTAssertEqual(value.savingRule, .fixed(200_000)); assertIdentity(value)
    }
    func testLimitsRejectInvalidTransfersAtomically() throws {
        for direction in [SavingsTransfer.Direction.take, .putBack] {
            let maximum: Int64 = direction == .take ? 500_000 : 186_400
            for amount in [0, -1, maximum + 1, Money.limit + 1, Int64.min, Int64.max] {
                var value = ledger(); let before = value
                XCTAssertFalse(Reserve.transferPreview(value, direction: direction, amount: amount, now: now).valid)
                XCTAssertThrowsError(try Reserve.transfer(direction, amount: amount, in: &value, now: now))
                XCTAssertEqual(value, before)
            }
            var value = ledger(); try Reserve.transfer(direction, amount: maximum, in: &value, now: now)
            XCTAssertEqual(direction == .take ? Reserve.overview(value, now: now).total : Finance.funds(value, now: now).available, 0)
        }
    }
    func testNoDepositIsAllowedWhileOverspentButTakingCanRestoreSpendable() throws {
        var value = ledger(); value.entries.append(Entry(date: now, amount: 200_000, accountID: value.accounts[0].id, title: "消费"))
        XCTAssertFalse(Reserve.transferPreview(value, direction: .putBack, amount: 1, now: now).valid)
        try Reserve.transfer(.take, amount: 50_000, in: &value, now: now)
        XCTAssertEqual(Finance.funds(value, now: now).available, 36_400); assertIdentity(value)
    }
    func testTakingCanReleasePendingSavingsAndNeverMakesSavedTotalNegative() throws {
        var value = ledger()
        let row = try Reserve.transfer(.take, amount: 450_000, in: &value, now: now)
        XCTAssertEqual(row.fromSetAside, 150_000)
        XCTAssertEqual(value.fixedSavingsTotal(now: now), 0)
        XCTAssertEqual(Finance.funds(value, now: now).savingTarget, 50_000)
        XCTAssertEqual(Reserve.overview(value, now: now).total, 50_000)
        XCTAssertEqual(Finance.funds(value, now: now).available, 636_400); assertIdentity(value)
    }
    func testClosingCycleDoesNotDeductTakenPendingMoneyAgain() throws {
        var value = ledger(); try Reserve.transfer(.take, amount: 450_000, in: &value, now: now)
        Savings.closeCycles(&value, now: d("2026-12-10 12:00"))
        XCTAssertEqual(value.savingHistory.last?.saved, 50_000)
        // The 3,310.00 bill is still unpaid when this period closes.
        XCTAssertEqual(value.fixedSavingsTotal(now: d("2026-12-10 12:00")), 686_400)
        let once = value; Savings.closeCycles(&value, now: d("2026-12-11")); XCTAssertEqual(value, once)
        assertIdentity(value, at: d("2026-12-11"))
    }
    func testUndoTakeAndPutBackRestoresFundsAndHistory() throws {
        for direction in [SavingsTransfer.Direction.take, .putBack] {
            var value = ledger(); let before = Finance.funds(value, now: now), overview = Reserve.overview(value, now: now)
            let row = try Reserve.transfer(direction, amount: 50_000, in: &value, now: now)
            try Reserve.undoTransfer(row.id, in: &value, now: now)
            XCTAssertEqual(Finance.funds(value, now: now), before); XCTAssertEqual(Reserve.overview(value, now: now), overview)
            XCTAssertTrue(value.savingsTransfers.isEmpty)
        }
    }
    func testFloorIsOptionalEditableAndDoesNotRestrictTaking() throws {
        var value = ledger(); let before = Finance.funds(value, now: now)
        try Reserve.setFloor(300_000, in: &value, now: now)
        XCTAssertEqual(value.profile.floorAmount, 300_000); XCTAssertEqual(Finance.funds(value, now: now), before)
        try Reserve.transfer(.take, amount: 450_000, in: &value, now: now)
        XCTAssertEqual(Reserve.overview(value, now: now).total, 50_000)
        try Reserve.setFloor(nil, in: &value, now: now); XCTAssertNil(value.profile.floorAmount)
        try Reserve.setFloor(0, in: &value, now: now); XCTAssertNil(value.profile.floorAmount)
    }
    func testFloorOnNewLedgerNeverBecomesASecondSavingsBalanceOnDecode() throws {
        var value = Ledger(); try Reserve.setFloor(300_000, in: &value, now: now)
        let decoded = try JSONDecoder().decode(Ledger.self, from: JSONEncoder().encode(value))
        XCTAssertEqual(decoded.fixedSavings, 0); XCTAssertEqual(decoded.profile.floorAmount, 300_000)
        XCTAssertEqual(decoded.fixedSavingsTotal(now: now), 0)
    }
    func testOldLedgerWithoutNewFieldsDecodesAndKeepsExistingFloorAndPlans() throws {
        var value = ledger(); value.profile.floorAmount = 300_000
        let encoded = try JSONEncoder().encode(value)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        json.removeValue(forKey: "savingsTransfers"); json.removeValue(forKey: "savingsTopupDecisions")
        let decoded = try JSONDecoder().decode(Ledger.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(decoded, value); XCTAssertTrue(decoded.savingsTransfers.isEmpty); XCTAssertTrue(decoded.savingsTopupDecisions.isEmpty)
    }
    func testTransfersRoundTripAndHistoricalQueriesIgnoreFutureTransfers() throws {
        var value = ledger(); try Reserve.transfer(.take, amount: 50_000, in: &value, now: now)
        value = try LedgerCodec.decode(LedgerCodec.encode(value))
        XCTAssertEqual(Finance.funds(value, now: now).available, 236_400)
        XCTAssertEqual(Reserve.overview(value, now: d("2026-11-20 11:00")).total, 500_000)
    }
    func testQuestionWaitsForFirstPaydayAndAggregatesWithdrawals() throws {
        var value = ledger()
        try Reserve.transfer(.take, amount: 30_000, in: &value, now: now)
        try Reserve.transfer(.take, amount: 20_000, in: &value, now: d("2026-11-21"))
        XCTAssertNil(Reserve.topupOffer(value, now: now)); XCTAssertNil(Reserve.topupOffer(value, now: d("2026-12-09")))
        let offer = try XCTUnwrap(Reserve.topupOffer(value, now: d("2026-12-10")))
        XCTAssertEqual(offer.amount, 50_000); XCTAssertEqual(offer.withdrawals.count, 2); XCTAssertEqual(offer.payday, d("2026-12-10"))
    }
    func testQuestionQueuesAlongsideOtherButlerItems() throws {
        var value = ledger(); try Reserve.transfer(.take, amount: 50_000, in: &value, now: now)
        let queue = HomeButler.queue(value, now: d("2026-12-10 12:00"))
        XCTAssertEqual(queue.filter { if case .savingsTopup = $0 { return true }; return false }.count, 1)
        XCTAssertTrue(queue.contains { if case .payday = $0 { return true }; return false })
    }
    func testAllThreeAnswersConsumeThoseWithdrawalsPermanently() throws {
        for amount in [Int64(0), 20_000, 50_000] {
            var value = ledger(); try Reserve.transfer(.take, amount: 50_000, in: &value, now: now)
            let payday = d("2026-12-10 12:00"); value.entries.append(Entry(date: payday, amount: 801_000, nature: .income, accountID: value.accounts[0].id, title: "工资")); let offer = try XCTUnwrap(Reserve.topupOffer(value, now: payday))
            let before = Finance.funds(value, now: payday).available, saved = Reserve.overview(value, now: payday).total
            try Reserve.answerTopup(offer, amount: amount, in: &value, now: payday)
            value = try LedgerCodec.decode(LedgerCodec.encode(value))
            XCTAssertNil(Reserve.topupOffer(value, now: payday)); XCTAssertNil(Reserve.topupOffer(value, now: d("2027-01-10")))
            XCTAssertEqual(Finance.funds(value, now: payday).available, before - amount)
            XCTAssertEqual(Reserve.overview(value, now: payday).total, saved + amount)
            XCTAssertEqual(value.savingsTopupDecisions.first?.amount, amount)
            XCTAssertThrowsError(try Reserve.answerTopup(offer, amount: amount, in: &value, now: payday))
        }
    }
    func testQuestionOnlyIncludesPreviousWithdrawalsAndNewOnesCanAskNextMonth() throws {
        var value = ledger(); try Reserve.transfer(.take, amount: 50_000, in: &value, now: now)
        let payday = d("2026-12-10 12:00"); value.entries.append(Entry(date: payday, amount: 801_000, nature: .income, accountID: value.accounts[0].id, title: "工资")); let offer = try XCTUnwrap(Reserve.topupOffer(value, now: payday))
        try Reserve.transfer(.take, amount: 10_000, in: &value, now: payday)
        XCTAssertEqual(Reserve.topupOffer(value, now: payday), offer)
        try Reserve.answerTopup(offer, amount: 0, in: &value, now: payday)
        XCTAssertNil(Reserve.topupOffer(value, now: payday))
        XCTAssertEqual(Reserve.topupOffer(value, now: d("2027-01-10"))?.amount, 10_000)
    }
    func testTopupLimitAndStaleOfferAreAtomic() throws {
        var value = ledger(); try Reserve.transfer(.take, amount: 50_000, in: &value, now: now)
        let payday = d("2026-12-10"), offer = try XCTUnwrap(Reserve.topupOffer(value, now: payday))
        for amount in [Int64(-1), 50_001] {
            let before = value; XCTAssertThrowsError(try Reserve.answerTopup(offer, amount: amount, in: &value, now: payday)); XCTAssertEqual(value, before)
        }
        value.entries.append(Entry(date: payday, amount: 2_000_000, accountID: value.accounts[0].id, title: "消费"))
        let before = value
        XCTAssertThrowsError(try Reserve.answerTopup(offer, amount: 50_000, in: &value, now: payday)); XCTAssertEqual(value, before)
        try Reserve.answerTopup(offer, amount: 0, in: &value, now: payday); XCTAssertNil(Reserve.topupOffer(value, now: payday))
    }
    func testExistingPurchaseCoverAndLegacyAnswerAreRecognized() throws {
        var value = ledger()
        value.entries[1].fromReserve = true
        let cover = CycleCover(cycleStart: d("2026-11-10"), date: now, source: .fromReserve, amount: 1000)
        value.cycleCovers = [cover]
        let offer = try XCTUnwrap(Reserve.topupOffer(value, now: d("2026-12-10")))
        XCTAssertEqual(Set(offer.withdrawals), [.purchase(value.entries[1].id), .cover(cover.id)])
        try Reserve.answerPayback(.purchase(value.entries[1].id), cycles: nil, in: &value, now: now)
        XCTAssertEqual(Reserve.topupOffer(value, now: d("2026-12-10"))?.withdrawals, [.cover(cover.id)])
    }
    func testFullRefundOrDeletingPurchaseRemovesItFromQuestion() throws {
        var value = ledger(); value.entries[1].fromReserve = true
        var refund = Entry(date: now, amount: value.entries[1].amount, nature: .refund, accountID: value.accounts[0].id, title: "退回")
        refund.relatedEntryID = value.entries[1].id; value.entries.append(refund)
        XCTAssertNil(Reserve.topupOffer(value, now: d("2026-12-10")))
        value.entries.removeLast(); value.entries[1].deletedAt = now
        XCTAssertNil(Reserve.topupOffer(value, now: d("2026-12-10")))
    }
    func testEarlyActualPaydayAndMovedPaydayTriggerTheQuestion() throws {
        var value = ledger(); try Reserve.transfer(.take, amount: 50_000, in: &value, now: now)
        value.paydayConfirmSince = d("2026-12-10")
        let early = d("2026-12-08 09:00")
        try Payday.confirm(Payday.Due(planID: value.plans[0].id, occurrence: d("2026-12-10"), title: "工资", usual: 801_000, lateDays: 0), amount: 801_000, extraToSavings: false, accountID: nil, in: &value, now: early)
        XCTAssertEqual(Reserve.topupOffer(value, now: early)?.payday, d("2026-12-08"))
        var moved = ledger(); try Reserve.transfer(.take, amount: 50_000, in: &moved, now: now)
        try FixedFlows.moveOccurrence(planID: moved.plans[0].id, occurrence: d("2026-12-10"), to: d("2026-12-08"), in: &moved, now: early)
        XCTAssertEqual(Reserve.topupOffer(moved, now: early)?.payday, d("2026-12-08"))
    }
    func testNoSalaryPlanDoesNotInventPaydayQuestion() throws {
        var value = ledger(); value.plans.removeAll { $0.inflow }; value.entries[0].planID = nil; value.entries[0].occurrence = nil
        try Reserve.transfer(.take, amount: 50_000, in: &value, now: now)
        XCTAssertNil(Reserve.topupOffer(value, now: d("2027-01-10")))
    }
    func testSharedSnapshotUndoRestoresTopupDecisionAndTransferTogether() throws {
        var value = ledger(); try Reserve.transfer(.take, amount: 50_000, in: &value, now: now)
        let payday = d("2026-12-10"); value.entries.append(Entry(date: payday, amount: 801_000, nature: .income, accountID: value.accounts[0].id, title: "工资")); let before = value, offer = try XCTUnwrap(Reserve.topupOffer(value, now: payday))
        try Reserve.answerTopup(offer, amount: 20_000, in: &value, now: payday)
        XCTAssertNil(Reserve.topupOffer(value, now: payday))
        value = before
        XCTAssertEqual(Reserve.topupOffer(value, now: payday), offer)
        XCTAssertEqual(Finance.funds(value, now: payday), Finance.funds(before, now: payday))
    }
    func testDuplicateTransferAndRepeatedQuestionDecisionAreRejected() throws {
        var value = ledger(); let row = try Reserve.transfer(.take, amount: 50_000, in: &value, now: now)
        value.savingsTransfers.append(row); XCTAssertThrowsError(try value.validate()); value.savingsTransfers.removeLast()
        let payday = d("2026-12-10"), offer = try XCTUnwrap(Reserve.topupOffer(value, now: payday))
        try Reserve.answerTopup(offer, amount: 0, in: &value, now: payday)
        value.savingsTopupDecisions.append(value.savingsTopupDecisions[0]); XCTAssertThrowsError(try value.validate())
    }
    func testTakingPendingSavingsDoesNotDoubleCountMonthlyRecords() throws {
        var value = ledger()
        let before = SavingInsights.monthlyIncrease(value, now: now)
        try Reserve.transfer(.take, amount: 450_000, in: &value, now: now)
        XCTAssertEqual(SavingInsights.monthlyIncrease(value, now: now), before - 450_000)
        let lines = Reserve.overview(value, now: now).lines
        XCTAssertEqual(lines.filter { if case .monthly = $0.kind { return true }; return false }.reduce(0) { $0 + $1.amount }, 200_000)
    }
    func testClosedCycleRecordsKeepReleasedTargetAndWithdrawalExactlyOnce() throws {
        var value = ledger(); try Reserve.transfer(.take, amount: 450_000, in: &value, now: now)
        let end = d("2026-12-10 12:00")
        Savings.closeCycles(&value, now: end)
        let oldLines = Reserve.overview(value, now: end).lines.filter { $0.date < d("2026-12-10") }
        XCTAssertEqual(oldLines.reduce(0) { $0 + $1.amount }, -250_000)
        XCTAssertEqual(value.fixedSavingsTotal(now: end), 686_400)
    }
    func testNewAnswerAlsoSuppressesLegacyPaybackOffers() throws {
        var value = ledger(); try Reserve.transfer(.take, amount: 50_000, in: &value, now: now)
        let payday = d("2026-12-10"), offer = try XCTUnwrap(Reserve.topupOffer(value, now: payday))
        try Reserve.answerTopup(offer, amount: 0, in: &value, now: payday)
        XCTAssertTrue(Reserve.paybackOffers(value, now: payday).isEmpty)
    }

    func testClearedLegacyFloorDoesNotReturnAfterReload() throws {
        var value = ledger(); value.preferences.emergencyReserve = 300_000; value.profile.floorAmount = 300_000
        try Reserve.setFloor(nil, in: &value, now: now)
        let decoded = try JSONDecoder().decode(Ledger.self, from: JSONEncoder().encode(value))
        XCTAssertNil(decoded.profile.floorAmount); XCTAssertEqual(decoded.preferences.emergencyReserve, 0)
        XCTAssertEqual(decoded.fixedSavingsTotal(now: now), 300_000)
    }

}
