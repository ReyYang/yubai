import Foundation
import XCTest
@testable import YubaiCore

final class Batch2HomeTests: XCTestCase {
    private func date(_ value: String) -> Date { Dates.parse(value)! }

    private func sample() -> (Ledger, Account) {
        let bank = Account(name: "招行储蓄", balance: 400_000, at: date("2026-10-01"))
        var ledger = Ledger()
        ledger.accounts = [bank]
        ledger.cycleAnchor = .calendarMonth
        ledger.fixedSavings = 20_000
        ledger.plans = [Plan(title: "工资", amount: 100_000, dueDate: date("2026-10-01"),
                             frequency: .monthly, inflow: true, category: "工资", nature: .income)]
        ledger.entries = ["2026-10-01", "2026-11-01"].map {
            Entry(date: date($0), amount: 100_000, nature: .income, accountID: bank.id, title: "工资", category: "工资")
        }
        return (ledger, bank)
    }

    func testOverspendIsShownWithoutShrinkingSaving() throws {
        var (ledger, bank) = sample()
        let now = date("2026-11-23")
        ledger.entries[1].amount = 800_000
        ledger.savingRule = .fixed(200_000)
        ledger.fixedSavings = 300_000
        ledger.entries.append(Entry(date: now, amount: 620_000, accountID: bank.id, title: "日常"))
        let over = Finance.spendableBreakdown(ledger, now: now)
        XCTAssertEqual(over.rawR, -20_000)
        XCTAssertEqual(over.plannedSaving, 200_000)
        XCTAssertEqual(over.rows.first { $0.kind == .saving }?.amount, -200_000)
        XCTAssertEqual(over.deficit, 20_000)
        XCTAssertEqual(over.headlineTitle, "超支")
        XCTAssertEqual(over.headlineAmount, 20_000)
        XCTAssertTrue(over.showsSpendableDeficit)
        XCTAssertEqual(over.spendableDisplayAmount, 20_000)
        XCTAssertEqual(over.savingCovered, 180_000)
        let cover = try Reserve.transfer(.take, amount: over.spendableDisplayAmount, in: &ledger, now: now)
        XCTAssertEqual(cover.amount, 20_000)
        XCTAssertEqual(ledger.fixedSavingsTotal(now: now), 280_000)
        let covered = Finance.spendableBreakdown(ledger, now: now)
        XCTAssertFalse(covered.showsSpendableDeficit)
        XCTAssertEqual(covered.headlineTitle, "还能花")
        XCTAssertEqual(covered.spendableDisplayAmount, 0)
        try Reserve.undoTransfer(cover.id, in: &ledger, now: now)
        XCTAssertEqual(Finance.spendableBreakdown(ledger, now: now).spendableDisplayAmount, 20_000)
    }

    func testReimbursementRestoresOnlyThePostingCyclesBucket() throws {
        let prior = date("2026-10-28"), today = date("2026-11-23")
        for originalDate in [today, prior] {
            var (ledger, bank) = sample()
            var original = Entry(date: originalDate, amount: 15_580, accountID: bank.id, title: "出差")
            original.pendingRecovery = .reimbursement
            ledger.entries.append(original)
            let snapshot = ledger
            let before = Finance.spendableBreakdown(ledger, now: today)
            let reserve = Reserve.overview(ledger, now: today).total
            let receipt = try EntryRecovery.receive(originalID: original.id, into: bank.id, in: &ledger, now: today)
            XCTAssertEqual(receipt.relatedEntryID, original.id)
            XCTAssertEqual(receipt.nature, .refund)
            XCTAssertEqual(EntryRecovery.status(for: original, in: ledger, now: today)?.remaining, 0)
            let after = Finance.spendableBreakdown(ledger, now: today)
            XCTAssertEqual(after.spent, originalDate == today ? before.spent - original.amount : before.spent)
            XCTAssertEqual(after.available, originalDate == today ? before.available + original.amount : before.available)
            let expectedReserve = reserve + (originalDate == today ? 0 : original.amount)
            let overview = Reserve.overview(ledger, now: today)
            XCTAssertEqual(overview.total, expectedReserve)
            XCTAssertEqual(overview.lines.first(where: { $0.id == "recovery:" + receipt.id.uuidString })?.amount,
                           originalDate == today ? nil : original.amount)
            XCTAssertEqual(Reserve.overview(ledger, now: date("2026-12-04")).total, expectedReserve)
            XCTAssertThrowsError(try EntryRecovery.receive(originalID: original.id, into: bank.id, in: &ledger, now: today))
            try ledger.validate()

            let index = try XCTUnwrap(ledger.entries.firstIndex(where: { $0.id == receipt.id }))
            ledger.entries[index].deletedAt = today
            try ledger.validate()
            XCTAssertEqual(EntryRecovery.status(for: original, in: ledger, now: today)?.remaining, original.amount)
            XCTAssertEqual(Finance.spendableBreakdown(ledger, now: today).available, before.available)
            XCTAssertEqual(Reserve.overview(ledger, now: today).total, reserve)
            ledger = snapshot
            XCTAssertEqual(EntryRecovery.status(for: original, in: ledger, now: today)?.receipts.count, 0)
        }
    }

    func testAAReceiptsRoundTripAndRecoverPartiallyThenFullyAcrossCycles() throws {
        let october = date("2026-10-28"), november = date("2026-11-23")
        var (ledger, bank) = sample()
        let people = [RecoveryParticipant(name: "周", amount: 2_600), RecoveryParticipant(name: "林", amount: 2_600)]
        var input = EntrySaveInput(type: .expense, amountCents: 7_800, purpose: "电影票", category: "娱乐",
                                   accountID: bank.id, date: october, exception: .split, personalExpenseCents: 2_600)
        input.recoveryParticipants = people
        let change = try EntrySaveMapper.makeChange(input, in: ledger, now: october)
        _ = try change.apply(to: &ledger)
        let original = try XCTUnwrap(ledger.entries.last)
        XCTAssertEqual(original.recoveryParticipants, people)
        XCTAssertEqual(Finance.spendableBreakdown(ledger, now: october).spent, 7_800)

        let first = try EntryRecovery.receive(originalID: original.id, participantID: people[0].id, into: bank.id, in: &ledger, now: october)
        XCTAssertEqual(Finance.spendableBreakdown(ledger, now: october).spent, 5_200)
        let octoberReport = DateInterval(start: date("2026-10-01"), end: date("2026-11-01"))
        XCTAssertEqual(Finance.cashFlow(ledger, during: octoberReport).spending, 2_600)
        let partial = ledger
        XCTAssertEqual(EntryRecovery.status(for: original, in: ledger, now: october)?.remaining, 2_600)
        XCTAssertThrowsError(try EntryRecovery.receive(originalID: original.id, participantID: people[0].id, into: bank.id, in: &ledger, now: november))

        let second = try EntryRecovery.receive(originalID: original.id, participantID: people[1].id, into: bank.id, in: &ledger, now: november)
        XCTAssertEqual(Finance.spendableBreakdown(ledger, now: november).spent, 0)
        XCTAssertEqual(Reserve.overview(ledger, now: november).total, 22_600)
        let decoded = try JSONDecoder().decode(Ledger.self, from: JSONEncoder().encode(ledger))
        let full = try XCTUnwrap(EntryRecovery.status(for: original, in: decoded, now: november))
        XCTAssertEqual(full.people.compactMap(\.receipt?.id), [first.id, second.id])
        XCTAssertEqual(full.remaining, 0)
        ledger = partial
        XCTAssertNil(EntryRecovery.status(for: original, in: ledger, now: november)?.people.last?.receipt)
        XCTAssertEqual(Reserve.overview(ledger, now: november).total, 20_000)
    }

    func testBudgetOrderPercentAndRemovingAPartReturnCategoryToUnset() throws {
        var (ledger, bank) = sample()
        let now = date("2026-11-23")
        let names = ledger.orderedCategories(income: false).prefix(5).map(\.name)
        for category in names.prefix(4) { try HomeBudgets.set(10_000, category: category, in: &ledger, now: now) }
        ledger.entries.append(Entry(date: now, amount: 11_000, accountID: bank.id, title: "今日", category: names[0]))
        var budgets = HomeBudgets(in: ledger, now: now)
        XCTAssertEqual(budgets.home.count, 3)
        XCTAssertEqual(budgets.other.count, 1)
        let first = try XCTUnwrap(budgets.home.first)
        XCTAssertEqual(first.remaining, 0)
        XCTAssertEqual(first.over, 1_000)
        XCTAssertEqual(first.fraction, 1.1)
        HomeBudgets.move(first.id, to: budgets.home[2].id, in: &ledger)
        budgets = HomeBudgets(in: ledger, now: now)
        XCTAssertEqual(budgets.home.last?.id, first.id)
        try HomeBudgets.set(20_000, id: first.id, in: &ledger, now: now)
        budgets = HomeBudgets(in: ledger, now: now)
        XCTAssertEqual(budgets.home.last?.remaining, 9_000)
        try HomeBudgets.set(nil, id: first.id, in: &ledger, now: now)
        budgets = HomeBudgets(in: ledger, now: now)
        XCTAssertTrue(budgets.unbudgeted.contains(names[0]))
        XCTAssertEqual(budgets.other.count, 0)
        try ledger.validate()
    }

    func testLegacyBudgetAmountsAppearAndCanBeEdited() throws {
        var (ledger, _) = sample()
        let now = date("2026-11-23")
        let category = try XCTUnwrap(ledger.orderedCategories(income: false).first?.name)
        let watch = ProfileArea(title: category, match: .init(categories: [category]), softLimit: .init(perMonthAmount: 20_000))
        ledger.profile.restrain = [watch]
        XCTAssertEqual(HomeBudgets(in: ledger, now: now).home.first?.amount, 20_000)
        try HomeBudgets.set(12_000, id: watch.id, in: &ledger, now: now)
        XCTAssertEqual(HomeBudgets(in: ledger, now: now).home.first?.amount, 12_000)
        try HomeBudgets.set(nil, id: watch.id, in: &ledger, now: now)
        XCTAssertTrue(HomeBudgets(in: ledger, now: now).home.isEmpty)
    }

    func testFixedEditPreservesOtherLegacyPercentageBudgets() throws {
        var (ledger, _) = sample()
        let now = date("2026-11-23")
        let names = ledger.orderedCategories(income: false).prefix(2).map(\.name)
        ledger.partsMode = .share
        ledger.spendingParts = names.map { SpendingPart(name: $0, share: 2, categories: [$0]) }
        let original = HomeBudgets(in: ledger, now: now)
        try HomeBudgets.set(12_000, id: original.home[0].id, in: &ledger, now: now)
        XCTAssertEqual(ledger.partsMode, .share)
        let edited = HomeBudgets(in: ledger, now: now)
        XCTAssertEqual(edited.home[0].amount, 12_000)
        XCTAssertEqual(edited.home[1], original.home[1])
    }

    func testBillEditAndDeletionPreserveLinkedRecoveryInvariants() throws {
        var (ledger, bank) = sample()
        let now = date("2026-11-23")
        var entry = Entry(date: now, amount: 7_800, accountID: bank.id, title: "电影票", category: "娱乐")
        entry.pendingRecovery = .split
        entry.personalExpense = 2_600
        entry.note = "IMAX"
        let person = RecoveryParticipant(name: "林", amount: 5_200)
        entry.recoveryParticipants = [person]
        ledger.entries.append(entry)
        let receipt = try EntryRecovery.receive(originalID: entry.id, participantID: person.id, into: bank.id, in: &ledger, now: now)
        let input = EntrySaveInput(type: .expense, amountCents: 9_000, purpose: "电影", category: "娱乐",
                                   accountID: bank.id, date: now, exception: .split, personalExpenseCents: 3_800)
        try EntrySaveMapper.edit(entry.id, input: input, in: &ledger, now: now)
        let edited = try XCTUnwrap(ledger.entries.first { $0.id == entry.id })
        XCTAssertEqual(edited.amount, 9_000)
        XCTAssertEqual(edited.note, "IMAX")
        XCTAssertEqual(edited.personalExpense, 3_800)
        XCTAssertEqual(edited.recoveryParticipants, [person])
        let beforeDelete = ledger
        try EntryRecovery.delete(entry.id, from: &ledger, now: now)
        XCTAssertFalse(ledger.activeEntries.contains { $0.id == entry.id || $0.id == receipt.id })
        ledger = beforeDelete
        XCTAssertEqual(EntryRecovery.status(for: edited, in: ledger, now: now)?.people.first?.receipt?.id, receipt.id)
    }

    func testBookedRecoveryBucketsSurviveAnchorChangeAndCodableRoundTrip() throws {
        let now = date("2026-11-03")
        for anchor in [CycleAnchor.calendarMonth, .payday] {
            var (ledger, bank) = sample()
            ledger.plans[0].dueDate = date("2026-10-10")
            ledger.cycleAnchor = anchor
            var original = Entry(date: date("2026-10-28"), amount: 5_000, accountID: bank.id, title: "报销")
            original.pendingRecovery = .reimbursement
            ledger.entries.append(original)
            let receipt = try EntryRecovery.receive(originalID: original.id, into: bank.id, in: &ledger, now: now)
            let bookedToReserve = anchor == .calendarMonth
            XCTAssertEqual(receipt.recoveryIntoReserve, bookedToReserve)
            ledger = try JSONDecoder().decode(Ledger.self, from: JSONEncoder().encode(ledger))
            ledger.cycleAnchor = bookedToReserve ? .payday : .calendarMonth
            XCTAssertEqual(ledger.fixedSavingsTotal(now: now), bookedToReserve ? 25_000 : 20_000)
            XCTAssertEqual(Finance.spendableBreakdown(ledger, now: now).spent, bookedToReserve ? 5_000 : -5_000)
            try ledger.validate()
        }
    }

    func testRecoveryAccountPrefersOriginalThenIncomePlanOverRecentWallet() {
        var (ledger, bank) = sample()
        let now = date("2026-11-23")
        let salary = Account(name: "工资卡", at: now)
        let wallet = Account(name: "微信", kind: .cash, at: now)
        let credit = Account(name: "信用卡", kind: .credit, at: now)
        ledger.accounts += [salary, wallet, credit]
        ledger.plans[0].accountID = salary.id
        var recent = Entry(date: now, amount: 100, accountID: wallet.id, title: "咖啡")
        recent.recordedAt = now
        ledger.entries.append(recent)
        var original = Entry(date: now, amount: 2_600, accountID: credit.id, title: "电影")
        XCTAssertEqual(EntryRecovery.defaultAccount(for: original, in: ledger)?.id, salary.id)
        original.accountID = bank.id
        XCTAssertEqual(EntryRecovery.defaultAccount(for: original, in: ledger)?.id, bank.id)
        ledger.accounts[0].archived = true
        XCTAssertEqual(EntryRecovery.defaultAccount(for: original, in: ledger)?.id, salary.id)
    }

    func testAAEditsEvenlyRedistributeUnpaidAmountsAndKeepReceivedAmounts() throws {
        let now = date("2026-11-23")
        var (ledger, bank) = sample()
        var original = Entry(date: now, amount: 7_800, accountID: bank.id, title: "电影", category: "娱乐")
        original.pendingRecovery = .split
        original.personalExpense = 2_600
        let first = RecoveryParticipant(name: "周", amount: 2_600)
        let second = RecoveryParticipant(name: "林", amount: 2_600)
        original.recoveryParticipants = [first, second]
        ledger.entries.append(original)
        func edit(_ personal: Int64, in ledger: inout Ledger) throws {
            let input = EntrySaveInput(type: .expense, amountCents: 7_800, purpose: "电影", category: "娱乐",
                                       accountID: bank.id, date: now, exception: .split, personalExpenseCents: personal)
            try EntrySaveMapper.edit(original.id, input: input, in: &ledger, now: now)
        }
        try edit(1_001, in: &ledger)
        XCTAssertEqual(ledger.entries.last?.recoveryParticipants?.map(\.amount), [3_400, 3_399])
        try edit(4_000, in: &ledger)
        XCTAssertEqual(ledger.entries.last?.recoveryParticipants?.map(\.amount), [1_900, 1_900])
        var fullyPersonal = ledger
        try edit(7_800, in: &fullyPersonal)
        XCTAssertNil(fullyPersonal.entries.last?.recoveryParticipants)
        try EntryRecovery.receive(originalID: original.id, participantID: first.id, into: bank.id, in: &ledger, now: now)
        try edit(1_000, in: &ledger)
        let edited = try XCTUnwrap(ledger.entries.first { $0.id == original.id })
        XCTAssertEqual(edited.recoveryParticipants?.map(\.amount), [1_900, 4_900])
        let snapshot = ledger
        XCTAssertThrowsError(try edit(6_000, in: &ledger))
        XCTAssertEqual(ledger, snapshot)
    }

    func testOrdinaryLinkedRefundSettlesAAWithoutIndividualReceipts() throws {
        let now = date("2026-11-23")
        var (ledger, bank) = sample()
        var original = Entry(date: now, amount: 7_800, accountID: bank.id, title: "电影")
        original.pendingRecovery = .split
        original.personalExpense = 2_600
        let person = RecoveryParticipant(name: "周", amount: 5_200)
        original.recoveryParticipants = [person]
        var refund = Entry(date: now, amount: 5_200, nature: .refund, accountID: bank.id, title: "退款")
        refund.relatedEntryID = original.id
        ledger.entries += [original, refund]
        try ledger.validate()
        let status = try XCTUnwrap(EntryRecovery.status(for: original, in: ledger, now: now))
        XCTAssertTrue(status.isSettled)
        XCTAssertNil(status.people.first?.receipt)
        XCTAssertThrowsError(try EntryRecovery.receive(originalID: original.id, participantID: person.id, into: bank.id, in: &ledger, now: now))
    }

    func testEditingArchivedTransferKeepsBothOriginalAccountsSelectable() throws {
        let now = date("2026-11-23")
        var (ledger, bank) = sample()
        let destination = Account(name: "旧银行卡", at: now)
        ledger.accounts += [destination, Account(name: "新银行卡", at: now)]
        ledger.accounts[0].archived = true
        ledger.accounts[1].archived = true
        var original = Entry(date: now, amount: 2_000, nature: .transfer, accountID: bank.id, title: "转账")
        original.otherAccountID = destination.id
        ledger.entries.append(original)
        XCTAssertEqual(EntrySaveMapper.selectableAccounts(in: ledger, keeping: original.accountID).map(\.id), [bank.id, ledger.accounts[2].id])
        XCTAssertEqual(EntrySaveMapper.selectableAccounts(in: ledger, keeping: original.otherAccountID).map(\.id), [destination.id, ledger.accounts[2].id])
        let input = EntrySaveInput(type: .transfer, amountCents: 3_000, purpose: "移到账户", accountID: bank.id,
                                   destinationAccountID: destination.id, date: now)
        try EntrySaveMapper.edit(original.id, input: input, in: &ledger, now: now)
        XCTAssertEqual(ledger.entries.last?.accountID, bank.id)
        XCTAssertEqual(ledger.entries.last?.otherAccountID, destination.id)
        XCTAssertEqual(ledger.entries.last?.amount, 3_000)
    }

    func testPartMigrationConsumesOnlyWholeCategoryAmountWatches() throws {
        let now = date("2026-11-23")
        var (ledger, _) = sample()
        let names = ledger.orderedCategories(income: false).prefix(2).map(\.name)
        let plain = ProfileArea(title: names[0], match: .init(categories: [names[0]]), softLimit: .init(perPeriodCount: 3, perPeriodAmount: 10_000))
        let specific = ProfileArea(title: "通勤", match: .init(categories: [names[0]], keywords: ["地铁"], subcategories: [names[0] + "/地铁"]),
                                   softLimit: .init(perPeriodAmount: 5_000))
        ledger.profile.restrain = [plain, specific]
        try HomeBudgets.set(12_000, category: names[1], in: &ledger, now: now)
        XCTAssertEqual(ledger.spendingParts.count, 2)
        XCTAssertNil(ledger.profile.restrain[0].softLimit?.periodAmount)
        XCTAssertEqual(ledger.profile.restrain[0].softLimit?.periodCount, 3)
        XCTAssertEqual(ledger.profile.restrain[1], specific)
        for part in ledger.spendingParts {
            try HomeBudgets.set(nil, id: part.id, in: &ledger, now: now)
        }
        XCTAssertEqual(HomeBudgets(in: ledger, now: now).ordered.map(\.id), [specific.id])
    }

    func testDailySpendingAndSearchUseActualLedgerEntries() throws {
        var (ledger, bank) = sample()
        let now = date("2026-11-23 16:00")
        var entry = Entry(date: now, amount: 4_200, accountID: bank.id, title: "Taxi", category: "交通")
        entry.purpose = "打车"
        entry.subcategory = "网约车"
        entry.note = "赶飞机"
        ledger.entries.append(entry)
        var deleted = entry
        deleted.id = UUID()
        deleted.deletedAt = now
        ledger.entries.append(deleted)
        var future = entry
        future.id = UUID()
        future.date = date("2026-11-24")
        ledger.entries.append(future)

        let period = Finance.spendableBreakdown(ledger, now: now)
        let daily = DailySpending(in: ledger, period: period)
        XCTAssertEqual(daily.amounts.count, 30)
        XCTAssertEqual(daily.today, 22)
        XCTAssertEqual(daily.amounts[22], 4_200)
        XCTAssertEqual(daily.amounts[23], 0)
        XCTAssertEqual(daily.evenPace, period.budget / 30)
        for term in ["taxi", "打车", "交通", "网约车", "赶飞机", "打车 赶飞机"] {
            XCTAssertEqual(ledger.searchBills(term, now: now).map(\.id), [entry.id], term)
        }
        XCTAssertTrue(ledger.searchBills("打车 机票", now: now).isEmpty)
        XCTAssertTrue(ledger.searchBills("   ", now: now).isEmpty)
    }
}
