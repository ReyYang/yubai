import XCTest
@testable import YubaiCore

final class Round47RevisionTests: XCTestCase {
    func d(_ text: String) -> Date { Dates.parse(text)! }
    var now: Date { d("2026-11-20 12:00") }
    func ledger(spent: Int64 = 83_600) -> Ledger {
        var l = Ledger(); l.updatedAt = now; l.cycleAnchor = .payday
        l.accounts = [Account(name: "银行卡", balance: 300_000, at: d("2026-11-09"))]
        l.fixedSavings = 300_000; l.savingRule = .fixed(200_000)
        var salary = Plan(title: "工资", amount: 801_000, dueDate: d("2026-10-10"), frequency: .monthly, inflow: true, nature: .income)
        salary.accountID = l.accounts[0].id
        l.plans = [salary, Plan(title: "房租", amount: 331_000, dueDate: d("2026-12-05"))]
        var income = Entry(date: d("2026-11-10 09:00"), amount: 801_000, nature: .income, accountID: l.accounts[0].id, title: "工资")
        income.planID = salary.id; income.occurrence = d("2026-11-10")
        l.entries = [income, Entry(date: d("2026-11-19"), amount: spent, accountID: l.accounts[0].id, title: "外卖", category: "餐饮")]
        return l
    }
    func value(_ l: Ledger) -> SpendableBreakdown { Finance.spendableBreakdown(l, now: now) }
    func testBoardStatesTableAndEveryRowIdentity() throws {
        for (spent, available, effective, less, deficit) in [
            (Int64(83_600), Int64(186_400), Int64(200_000), Int64(0), Int64(0)),
            (290_000, 0, 180_000, 20_000, 0), (470_000, 0, 0, 200_000, 0), (505_000, 0, 0, 200_000, 35_000)
        ] {
            let l = ledger(spent: spent), f = value(l)
            XCTAssertEqual(f.available, available); XCTAssertEqual(f.effectiveSaving, effective)
            XCTAssertEqual(f.savingLess, less); XCTAssertEqual(f.deficit, deficit)
            XCTAssertEqual(f.rows.reduce(0) { $0 + $1.amount }, available - deficit)
            XCTAssertGreaterThanOrEqual(f.headlineAmount, 0)
            if deficit > 0 {
                guard case .deficit(_, let bill) = f.state else { return XCTFail("Deficit state") }
                XCTAssertEqual(bill?.title, "房租"); XCTAssertEqual(bill?.date, d("2026-12-05"))
            }
        }
    }
    func testRescueBoard350BecomesZeroAndUndoRestoresDeficit() throws {
        var l = ledger(spent: 505_000); let before = value(l), cash = Finance.funds(l, now: now).cash
        let row = try HomeButler.rescueDeficit(in: &l, now: now)
        XCTAssertEqual(row.amount, 35_000); XCTAssertEqual(value(l).deficit, 0); XCTAssertEqual(value(l).available, 0)
        XCTAssertEqual(value(l).effectiveSaving, 0); XCTAssertEqual(Finance.funds(l, now: now).cash, cash)
        XCTAssertEqual(value(l).rows.last?.transferIDs, [row.id])
        try Reserve.undoTransfer(row.id, in: &l, now: now); XCTAssertEqual(value(l), before)
    }
    func testRescueCapsAtAvailableSavingsAndStaysQueuedWhenInsufficient() throws {
        var l = ledger(spent: 505_000); l.fixedSavings = 10_000
        let row = try HomeButler.rescueDeficit(in: &l, now: now)
        XCTAssertEqual(row.amount, 10_000); XCTAssertEqual(value(l).deficit, 25_000)
        XCTAssertEqual(Reserve.overview(l, now: now).total, 0)
        XCTAssertEqual(HomeButler.queue(l, now: now).first?.priority, 0)
    }
    func testOpeningBalanceTransfersUnknownIncomeAndSavingsIncomeNeverInflatePeriod() {
        var l = ledger(); let before = value(l)
        l.accounts[0].anchorBalance += 900_000
        for nature in [Nature.transfer, .unknownIn, .adjustmentIn, .adjustmentOut] {
            l.entries.append(Entry(date: now, amount: 5000, nature: nature, accountID: l.accounts[0].id, title: "其他"))
        }
        l.entries.append(Entry(date: now, amount: 5000, nature: .income, accountID: l.accounts[0].id, title: "直接存", intoFixedSavings: true))
        XCTAssertEqual(value(l), before)
    }
    func testFutureIncomeWaitsForItsPrecisePostingBoundary() {
        var l = ledger(); let date = now.addingTimeInterval(1), before = value(l)
        let row = Entry(date: date, amount: 1234, nature: .income, accountID: l.accounts[0].id, title: "收入")
        l.entries.append(row); XCTAssertEqual(value(l), before)
        let after = Finance.spendableBreakdown(l, now: date)
        XCTAssertEqual(after.income, before.income + 1234); XCTAssertEqual(after.rows.first?.entryIDs.last, row.id)
    }
    func testRefundsNetSpendingButSavingsPurchaseRefundsStayOutsidePool() {
        var l = ledger(); let before = value(l)
        var refund = Entry(date: now, amount: 1000, nature: .refund, accountID: l.accounts[0].id, title: "退款")
        refund.relatedEntryID = l.entries[1].id; l.entries.append(refund)
        XCTAssertEqual(value(l).spent, before.spent - 1000)
        l.entries[1].fromReserve = true
        XCTAssertEqual(value(l).spent, 0); XCTAssertEqual(value(l).rows.first { $0.kind == .spent }?.entryIDs, [])
    }
    func testFallbackForMissingPlanAndForNoPostedDisposableIncome() {
        var l = ledger(); l.plans.removeAll { $0.inflow }
        XCTAssertEqual(value(l).state, .spentFallback); XCTAssertEqual(value(l).headlineAmount, 83_600)
        XCTAssertNil(value(l).waterBar); XCTAssertFalse(value(l).offersFormula)
        l = ledger(); l.entries[0].intoFixedSavings = true
        XCTAssertEqual(value(l).state, .spentFallback); XCTAssertEqual(HomeHero.make(l, now: now).title, "这个月花了")
        XCTAssertEqual(QuickCaptureSnapshot(ledger: l, now: now).available, 83_600)
    }
    func testWaterFillTickAndFastTable() throws {
        for (spent, expectedFill, fast) in [(Int64(83_600), 83_600.0 / 270_000, false), (162_000, 0.6, true), (290_000, 1, true)] {
            let bar = try XCTUnwrap(value(ledger(spent: spent)).waterBar)
            XCTAssertEqual(bar.fill, expectedFill, accuracy: 0.000001)
            XCTAssertEqual(bar.tick, 11.0/30, accuracy: 0.000001); XCTAssertEqual(bar.fast, fast)
        }
    }
    func testCarryBoard620Gives2484AndUndoConsumesNotice() throws {
        var l = ledger(); let previous = Finance.cycle(in: l, now: d("2026-11-09"))
        l.fixedSavings! += 62_000
        l.savingHistory = [CycleSaving(cycleStart: previous.start, cycleEnd: previous.end, income: 801_000, target: 200_000,
            saved: 200_000, leftover: 62_000, unspent: 62_000, leftoverChoice: .save, autoSaved: true)]
        let before = l.fixedSavingsTotal(now: now)
        let row = try Savings.keepLeftover(cycleStart: previous.start, in: &l, now: now)
        XCTAssertEqual(value(l).carry, 62_000); XCTAssertEqual(value(l).available, 248_400)
        XCTAssertEqual(l.fixedSavingsTotal(now: now), before - 62_000)
        XCTAssertNil(Savings.carryNotice(in: l, now: now)); XCTAssertThrowsError(try Savings.keepLeftover(cycleStart: previous.start, in: &l, now: now))
        try Savings.undoKeepLeftover(row.id, in: &l, now: now)
        XCTAssertEqual(value(l).available, 186_400); XCTAssertEqual(l.fixedSavingsTotal(now: now), before)
        XCTAssertNil(Savings.carryNotice(in: l, now: now))
    }
    func testSettlementAutoSavesEffectivePlusLeftoverOnlyOnce() {
        var l = ledger(); l.plans.removeAll { !$0.inflow }
        let date = d("2026-12-10 12:00")
        Savings.closeCycles(&l, now: date)
        XCTAssertEqual(l.savingHistory.last?.saved, 200_000); XCTAssertEqual(l.savingHistory.last?.leftover, 517_400)
        XCTAssertEqual(l.fixedSavingsTotal(now: date), 1_017_400)
        let once = l; Savings.closeCycles(&l, now: date); XCTAssertEqual(l, once)
        XCTAssertEqual(Savings.carryNotice(in: l, now: date)?.leftover, 517_400)
    }
    func testReconcileFloor400Gives1464AndReplacesRatherThanAccumulates() throws {
        var l = ledger(); let id = l.accounts[0].id
        // Need = saved 5,000 + bills 3,310 + spendable 1,864 = 10,174.
        let preview = Reconciliation.preview(l, actual: [id: 977_400], now: now)
        XCTAssertEqual(preview.floor, 40_000); XCTAssertEqual(preview.spendableAfter.available, 146_400)
        try Reconciliation.apply(&l, actual: [id: 977_400], now: now)
        XCTAssertEqual(value(l).balanceGap, 40_000); XCTAssertEqual(value(l).available, 146_400)
        XCTAssertEqual(l.entries.last?.kind, .adjustment); XCTAssertEqual(l.entries.last?.nature.label, "调整")
        try Reconciliation.apply(&l, actual: [id: 997_400], now: now)
        XCTAssertEqual(value(l).balanceGap, 20_000); XCTAssertEqual(value(l).available, 166_400)
        XCTAssertEqual(l.periodReconciliations.count, 1); XCTAssertEqual(l.lastReconciledAt, now)
        XCTAssertNil(Reconciliation.mismatch(in: l, now: now))
        try Reconciliation.apply(&l, actual: [id: 1_017_400], now: now)
        XCTAssertEqual(value(l).balanceGap, 0); XCTAssertEqual(value(l).available, 186_400)
        XCTAssertFalse(value(l).rows.contains { $0.kind == .balanceGap })
        XCTAssertEqual(l.periodReconciliations.count, 1)
    }
    func testReconcileCoveredDifferenceDoesNotChangePoolAndReducesSettlement() throws {
        var l = ledger(); l.accounts[0].anchorBalance += 500_000
        let before = value(l), book = Finance.balance(l.accounts[0], in: l, at: now)
        try Reconciliation.apply(&l, actual: [l.accounts[0].id: book - 41_200], now: now)
        XCTAssertEqual(value(l), before); XCTAssertEqual(l.periodReconciliations[0].floor, 0)
        let flow = Finance.cashFlow(l, during: before.interval)
        XCTAssertEqual(flow.spending, 83_600); XCTAssertEqual(flow.income, 801_000)
        Savings.closeCycles(&l, now: d("2026-12-10 12:00"))
        XCTAssertEqual(l.savingHistory.last?.settlementAdjustment, 41_200)
    }
    func testReconcileFloorAlsoUsesCreditDebtAndDoesNotLoseDirectSavingsIncome() throws {
        var l = ledger(); l.entries.append(Entry(date: now.addingTimeInterval(-1), amount: 5000, nature: .income, accountID: l.accounts[0].id, title: "存入", intoFixedSavings: true))
        l.accounts.append(Account(name: "信用卡", kind: .credit, balance: -10_000, at: now))
        let saved = l.fixedSavingsTotal(now: now)
        try Reconciliation.apply(&l, actual: [l.accounts[0].id: 1_027_400], now: now)
        XCTAssertEqual(l.fixedSavingsTotal(now: now), saved)
        XCTAssertEqual(value(l).balanceGap, 5000)
    }
    func testReconcileUsesSavingBufferThenDeficitWithoutNegativeHeadline() throws {
        for (cash, less, deficit) in [(Int64(801_000), Int64(30_000), Int64(0)), (500_000, 200_000, 131_000)] {
            let l = ledger(); let f = Reconciliation.preview(l, actual: [l.accounts[0].id: cash], now: now).spendableAfter
            XCTAssertEqual(f.savingLess, less); XCTAssertEqual(f.deficit, deficit); XCTAssertEqual(f.available, 0)
        }
    }
    func testSoftLinesAmountCountRefundAndTypedPreviewArePerPeriod() throws {
        var l = ledger(spent: 48_000)
        l.profile.restrain = [ProfileArea(title: "外卖", match: .init(keywords: ["外卖"]), softLimit: .init(perPeriodAmount: 80_000)),
                             ProfileArea(title: "咖啡", match: .init(keywords: ["咖啡"]), softLimit: .init(perPeriodCount: 5))]
        for day in ["2026-11-10", "2026-11-11"] { l.entries.append(Entry(date: d(day), amount: 1800, accountID: l.accounts[0].id, title: "咖啡")) }
        var refund = Entry(date: now, amount: 1000, nature: .refund, accountID: l.accounts[0].id, title: "退款"); refund.relatedEntryID = l.entries[1].id; l.entries.append(refund)
        let usage = SoftLines.usage(l, now: now)
        XCTAssertEqual(usage[0].remaining, 33_000); XCTAssertEqual(usage[1].remaining, 3)
        let typed = try XCTUnwrap(SoftLines.remainingAfterTyping(3800, category: "餐饮", purpose: "外卖", in: l, now: now))
        XCTAssertEqual(typed.remaining, 29_200)
        XCTAssertEqual(SoftLines.remainingAfterTyping(38_000, category: "餐饮", purpose: "外卖", in: l, now: now)?.exceeded, 5000)
        XCTAssertEqual(SoftLines.remainingAfterTyping(1800, category: "餐饮", purpose: "咖啡", in: l, now: now)?.remaining, 2)
        XCTAssertNil(SoftLines.remainingAfterTyping(3800, category: "交通", in: l, now: now))
        let before = value(l); try Reconciliation.apply(&l, actual: [l.accounts[0].id: 2_000_000], now: now)
        XCTAssertEqual(SoftLines.usage(l, now: now), usage); XCTAssertEqual(value(l), before)
    }
    func testSoftLineNeverDeductsPoolOrBlocksSavingAndCapsNewLinesAtThree() throws {
        var l = ledger(); let before = value(l)
        for i in 0..<3 { try SoftLines.set(ProfileArea(title: "分类\(i)", match: .init(categories: ["餐饮"]), softLimit: .init(perPeriodAmount: 100)), in: &l, now: now) }
        XCTAssertEqual(value(l), before)
        XCTAssertThrowsError(try SoftLines.set(ProfileArea(title: "第四类", softLimit: .init(perPeriodCount: 1)), in: &l, now: now))
        let change = try ManualBookkeeping.change(amount: 1000, nature: .expense, accountID: l.accounts[0].id, day: now, purpose: "外卖", category: "餐饮", now: now)
        try change.apply(to: &l); XCTAssertEqual(value(l).spent, 84_600)
    }
    func testPurchaseBoundsUseSavingBufferAndDeficit() {
        let l = ledger()
        XCTAssertEqual(PurchaseBounds.compute(ledger: l, amount: 200_000, title: "耳机", now: now).allowedVerdicts, [.wait, .skip])
        XCTAssertEqual(PurchaseBounds.compute(ledger: l, amount: 400_000, title: "相机", now: now).allowedVerdicts, [.skip])
        let less = Finance.assessPurchase(l, amount: 200_000, now: now)
        XCTAssertEqual(less.verdict, .wait); XCTAssertEqual(less.afterPurchase, 0); XCTAssertEqual(less.title, "等等再说")
        XCTAssertEqual(less.explanation, "买了以后，这个月少攒 " + Money.text(13_600) + "。")
        let gap = Finance.assessPurchase(l, amount: 400_000, now: now)
        XCTAssertEqual(gap.verdict, .skip); XCTAssertEqual(gap.title, "先别买")
        XCTAssertEqual(gap.explanation, "买了以后，要付的账单还差 " + Money.text(13_600) + "。")
    }
    func testYearlyQuarterlyHeadsUpOncePerOccurrenceAndOnlyDuePeriodDeducts() throws {
        var l = ledger()
        let annual = Plan(title: "车险", amount: 420_000, dueDate: d("2026-12-18"), frequency: .yearly)
        let quarterly = Plan(title: "季付", amount: 90_000, dueDate: d("2026-12-20"), frequency: .quarterly)
        l.plans += [annual, quarterly]
        let notices = HomeButler.billHeadsUps(l, now: now)
        XCTAssertEqual(notices.map(\.title), ["车险", "季付"]); XCTAssertEqual(value(l).billsRest, 331_000)
        HomeButler.answer(HomeTask.billHeadsUp(notices[0]).id, in: &l, now: now)
        XCTAssertEqual(HomeButler.billHeadsUps(l, now: now).map(\.title), ["季付"])
        try FixedFlows.moveOccurrence(planID: annual.id, occurrence: d("2026-12-18"), to: d("2026-12-19"), in: &l, now: now)
        XCTAssertEqual(HomeButler.billHeadsUps(l, now: now).map(\.title), ["季付"])
        let decoded = try JSONDecoder().decode(Ledger.self, from: JSONEncoder().encode(l))
        XCTAssertEqual(HomeButler.billHeadsUps(decoded, now: now).map(\.title), ["季付"])
        XCTAssertEqual(Finance.spendableBreakdown(l, now: d("2026-12-10")).billsRest, 510_000)
    }
    func testQueuePriorityCarryBeforeMismatchAndHeadup() {
        var l = ledger(); l.accounts[0].anchorBalance = -300_000
        let prior = Finance.cycle(in: l, now: d("2026-11-09"))
        l.savingHistory = [CycleSaving(cycleStart: prior.start, cycleEnd: prior.end, income: 801_000, target: 200_000, saved: 200_000, leftover: 62_000, autoSaved: true)]
        l.plans.append(Plan(title: "车险", amount: 420_000, dueDate: d("2026-12-18"), frequency: .yearly))
        let queue = HomeButler.queue(l, now: now)
        XCTAssertEqual(queue.first?.priority, 2)
        XCTAssertTrue(queue.contains { if case .balanceMismatch = $0 { true } else { false } })
        XCTAssertEqual(queue.map(\.priority), queue.map(\.priority).sorted())
    }
    func testOldShapeMigrationKeepsSavedTotalHistoryAndEntries() throws {
        var l = ledger(spent: 290_000)
        let prior = CycleSaving(cycleStart: d("2026-10-10"), cycleEnd: d("2026-11-09"), income: 700_000, target: 100_000, saved: 100_000, unspent: 10_000, leftoverChoice: .keep)
        l.savingHistory = [prior]
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(l)) as? [String: Any])
        for key in ["spendableModelVersion", "carryReleases", "periodReconciliations", "lastReconciledAt"] { object.removeValue(forKey: key) }
        var old = try JSONDecoder().decode(Ledger.self, from: JSONSerialization.data(withJSONObject: object))
        let entries = old.entries; let saved = old.fixedSavingsTotal(now: now) + 200_000
        Savings.closeCycles(&old, now: now)
        XCTAssertEqual(old.entries, entries); XCTAssertEqual(old.savingHistory, [prior])
        XCTAssertEqual(Reserve.overview(old, now: now).total, saved)
        XCTAssertEqual(value(old).state, .savingLess(20_000))
        let once = old; Savings.closeCycles(&old, now: now); XCTAssertEqual(old, once)
        XCTAssertEqual(try JSONDecoder().decode(Ledger.self, from: JSONEncoder().encode(old)), old)
    }
    func testMigrationNeverClipsSavedTotalWhenOldBaseIsAtMoneyLimit() throws {
        var l = ledger(spent: 0); l.fixedSavings = Money.limit; l.savingRule = .fixed(Money.limit)
        l.plans.removeAll { !$0.inflow }; l.entries.removeAll { $0.nature == .expense }; l.entries[0].amount = 1
        l.spendableModelVersion = nil
        try l.validate()
        let oldTotal = Money.limit * 2
        XCTAssertTrue(Savings.migrateSpendableModel(in: &l, now: now))
        XCTAssertEqual(Reserve.overview(l, now: now).total, oldTotal)
        XCTAssertEqual(l.fixedSavings, Money.limit); XCTAssertEqual(l.migratedSavingCredit, Money.limit - 1)
        let saved = l.fixedSavingsTotal(now: now)
        l.setFixedSavingsTotal(saved, now: now)
        XCTAssertEqual(l.fixedSavingsTotal(now: now), saved)
        try l.validate(); XCTAssertEqual(try LedgerCodec.decode(LedgerCodec.encode(l)), l)
        XCTAssertFalse(Savings.migrateSpendableModel(in: &l, now: now))
    }
    func testSoftLineBoardDraft320Minus38AndExceeded18() throws {
        var l = ledger(spent: 48_000)
        l.profile.restrain = [ProfileArea(title: "外卖", match: .init(keywords: ["外卖"]), softLimit: .init(perPeriodAmount: 80_000))]
        let before = l
        XCTAssertEqual(SoftLines.remainingAfterTyping(3800, category: "餐饮", purpose: "外卖", in: l, now: now)?.remaining, 28_200)
        XCTAssertEqual(SoftLines.remainingAfterTyping(33_800, category: "餐饮", purpose: "外卖", in: l, now: now)?.exceeded, 1800)
        XCTAssertEqual(l, before)
    }
    func testNewPeriodLinesFeedButlerProgressWeeklyAndAIFacts() throws {
        var l = ledger(spent: 48_000)
        l.profile.restrain = [ProfileArea(title: "外卖", match: .init(keywords: ["外卖"]), softLimit: .init(perPeriodCount: 1, perPeriodAmount: 40_000))]
        // A prior week in this payday period must still count.
        l.entries[1].date = d("2026-11-11")
        XCTAssertEqual(RestrainProgress.current(ledger: l, now: now).first?.status, .over)
        let card = try XCTUnwrap(ButlerCards.detect(l, now: now).first { $0.kind == .restrain })
        XCTAssertEqual(card.facts.first { $0.label == "本期消费" }?.cents, 48_000)
        XCTAssertEqual(WeeklyLetter.facts(l, weekEnding: now).comparison.value, "1 个 / 1 个")
        let facts = try ReadOnlyTool.getFunds.run(.object([:]), .init(ledger: l, now: now))
        XCTAssertEqual(facts["soft_lines"]?.arrayValue?.first?["used"], .money(48_000))
        let proposed = try ProposalTool.profile.propose(.object(["reason": .string("用户设置"), "operation": .string("upsert_area"), "stance": .string("restrain"), "title": .string("咖啡"), "keywords": .strings(["咖啡"]), "per_period_count": .number(3)]), .init(ledger: l, now: now))
        try proposed.apply(to: &l)
        XCTAssertEqual(l.profile.restrain.last?.softLimit?.perPeriodCount, 3)
    }
    func testThreeLineLimitAlsoAppliesToProfileChangesAndOldExtraLinesStillEdit() throws {
        var l = ledger()
        l.profile.restrain = (0..<4).map { ProfileArea(title: "旧类\($0)", softLimit: .init(perWeekCount: 1)) }
        var edit = l.profile.restrain[0]; edit.softLimit = .init(perPeriodCount: 2)
        try SoftLines.set(edit, in: &l, now: now)
        let before = l
        let fourth = ProfileArea(title: "新类", softLimit: .init(perPeriodAmount: 100))
        var change = ChangeSet(source: "用户操作", reason: "盯住", items: [.profile(.upsertArea(fourth, stance: .restrain))]); change.createdAt = now
        XCTAssertThrowsError(try change.apply(to: &l)); XCTAssertEqual(l, before)
        XCTAssertEqual(try LedgerCodec.decode(LedgerCodec.encode(l)), l)
    }
    func testMismatchDismissPersistsAndNewReconciliationStartsNewLifecycle() throws {
        var l = ledger(); l.lastReconciledAt = d("2026-11-01")
        l.accounts[0].anchorBalance = -300_000
        let task = HomeTask.balanceMismatch(try XCTUnwrap(Reconciliation.mismatch(in: l, now: now)))
        XCTAssertTrue(HomeButler.queue(l, now: now).contains { $0.id == task.id })
        HomeButler.answer(task.id, in: &l, now: now)
        l = try LedgerCodec.decode(LedgerCodec.encode(l))
        XCTAssertFalse(HomeButler.queue(l, now: now).contains { $0.id == task.id })
        try Reconciliation.apply(&l, actual: [l.accounts[0].id: 1_017_400], now: now)
        XCTAssertNil(Reconciliation.mismatch(in: l, now: now))
        let later = d("2026-12-21 12:00")
        let next = try XCTUnwrap(Reconciliation.mismatch(in: l, now: later))
        XCTAssertTrue(next.stale); XCTAssertNotEqual(next.id, task.id)
        XCTAssertTrue(HomeButler.queue(l, now: later).contains { $0.id == next.id })
    }
    func testCarryDismissKeepsMoneySavedAcrossReload() throws {
        var l = ledger(); let prior = Finance.cycle(in: l, now: d("2026-11-09"))
        l.savingHistory = [CycleSaving(cycleStart: prior.start, cycleEnd: prior.end, income: 801_000, target: 200_000, saved: 200_000, leftover: 62_000, autoSaved: true)]
        let before = l.fixedSavingsTotal(now: now)
        let notice = try XCTUnwrap(Savings.carryNotice(in: l, now: now))
        HomeButler.answer(HomeTask.leftover(notice).id, in: &l, now: now)
        l = try LedgerCodec.decode(LedgerCodec.encode(l))
        XCTAssertNil(Savings.carryNotice(in: l, now: now))
        XCTAssertEqual(l.fixedSavingsTotal(now: now), before); XCTAssertEqual(value(l).carry, 0)
    }
    func testNextPeriodHeadsUpUsesKnownEarlyActualSalaryAndQuarterlyRent() {
        var l = ledger(); l.paydayConfirmSince = d("2026-11-10")
        var nextSalary = l.entries[0]; nextSalary.id = UUID(); nextSalary.date = d("2026-12-05"); nextSalary.occurrence = d("2026-12-10")
        l.entries.append(nextSalary)
        l.plans += [Plan(title: "过早", amount: 100, dueDate: d("2026-12-04"), frequency: .yearly),
                    Plan(title: "年费", amount: 100, dueDate: d("2026-12-20"), frequency: .yearly),
                    Plan(title: "太晚", amount: 100, dueDate: d("2027-01-10"), frequency: .yearly)]
        l.rents = [Rent(title: "季付房租", monthlyTotal: 10_000, personalShare: 10_000, startDate: d("2026-12-15"), nextDueDate: d("2026-12-15"), monthsPerPayment: 3)]
        XCTAssertEqual(Finance.cycle(in: l, now: now).end, d("2026-12-04"))
        XCTAssertEqual(HomeButler.billHeadsUps(l, now: now).map(\.title), ["季付房租", "年费"])
    }
    func testLegacyQuickCaptureSnapshotStillDecodesWithoutHeadlineTitle() throws {
        let snapshot = QuickCaptureSnapshot(ledger: ledger(), now: now)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as? [String: Any])
        object.removeValue(forKey: "headlineTitle")
        let old = try JSONDecoder().decode(QuickCaptureSnapshot.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(old.headlineTitle); XCTAssertEqual(old.available, 186_400)
    }
    func testFreshWeeklyCardIsLastDismissibleAndSuppressedWhenHomeNoticesOff() throws {
        var l = ledger(); let date = d("2026-11-18 12:00")
        var card = ButlerCard(kind: .weeklyLetter, title: "每周来信", body: "", action: .openEvidence, dedupeKey: "letter:" + ButlerCards.isoWeek(date))
        card.createdAt = date; l.cards = [card]
        let task = HomeTask.butler(card)
        XCTAssertEqual(task.priority, 7); XCTAssertTrue(task.isDismissible)
        XCTAssertEqual(HomeButler.queue(l, now: date).last?.id, task.id)
        HomeButler.answer(task.id, in: &l, now: date)
        l = try LedgerCodec.decode(LedgerCodec.encode(l))
        XCTAssertFalse(HomeButler.queue(l, now: date).contains { $0.id == task.id })
        l.butlerAnswers = [:]; l.preferences.butlerNotices = ButlerNoticePreferences(); l.preferences.butlerNotices?.home = false
        XCTAssertFalse(HomeButler.queue(l, now: date).contains { $0.id == task.id })
    }
}
