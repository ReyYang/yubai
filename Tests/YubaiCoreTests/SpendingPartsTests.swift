import XCTest
@testable import YubaiCore

final class SpendingPartsTests: XCTestCase {
    private let now = Dates.parse("2026-11-09 12:00")!
    private func date(_ text: String) -> Date { Dates.parse(text)! }
    private func ledger(_ balance: Int64 = 1_000_000) -> Ledger {
        var ledger = Ledger()
        ledger.accounts = [Account(name: "银行卡", balance: balance, at: date("2026-07-01"))]
        ledger.spendingParts = [SpendingPart(name: "吃饭", amount: 250_000, share: 4, categories: ["餐饮"]),
                                SpendingPart(name: "玩乐", amount: 100_000, share: 2, categories: ["娱乐", "购物"])]
        return ledger
    }
    private func entry(_ ledger: Ledger, amount: Int64, category: String = "餐饮", at: String = "2026-11-05", nature: Nature = .expense) -> Entry {
        Entry(date: date(at), amount: amount, nature: nature, accountID: ledger.accounts[0].id, title: category, category: category)
    }

    func testOldLedgerAndEntryDecodeAndNewFieldsRoundTrip() throws {
        var l = ledger(); l.entries = [entry(l, amount: 1000)]
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(l)) as? [String: Any])
        for key in ["spendingParts", "partsMode", "partLeftover", "partCarry", "partCarryCycleStart"] { object.removeValue(forKey: key) }
        let old = try JSONDecoder().decode(Ledger.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertTrue(old.spendingParts.isEmpty); XCTAssertEqual(old.partsMode, .amount)
        XCTAssertEqual(old.partLeftover, .mergeIntoFixedSavings); XCTAssertTrue(old.partCarry.isEmpty)
        XCTAssertNil(old.partCarryCycleStart); XCTAssertNil(old.entries[0].partID)
        l.partsMode = .share; l.partLeftover = .rollOver
        l.entries[0].partID = l.spendingParts[1].id
        l.partCarry = [l.spendingParts[0].id: 500]; l.partCarryCycleStart = date("2026-11-01")
        XCTAssertEqual(try JSONDecoder().decode(Ledger.self, from: JSONEncoder().encode(l)), l)
        let clone = l; l.spendingParts[0].amount = 500
        XCTAssertNotEqual(l, clone)
    }

    func testCategorySubcategoryManualOverrideDeletedPartAndUnassigned() {
        var l = ledger(); var row = entry(l, amount: 1000)
        XCTAssertEqual(SpendingParts.part(for: row, in: l)?.id, l.spendingParts[0].id)
        row.subcategory = "午餐"
        XCTAssertEqual(SpendingParts.part(for: row, in: l)?.id, l.spendingParts[0].id)
        row.partID = l.spendingParts[1].id
        XCTAssertEqual(SpendingParts.part(for: row, in: l)?.name, "玩乐")
        row.partID = SpendingPart.unassignedID; XCTAssertNil(SpendingParts.part(for: row, in: l))
        row.partID = l.spendingParts[1].id; l.spendingParts.removeLast()
        XCTAssertNil(SpendingParts.part(for: row, in: l))
        row.partID = nil; row.category = "交通"; XCTAssertNil(SpendingParts.part(for: row, in: l))
    }

    func testUnassignedPaysOverflowAndCanBecomeNegative() {
        var l = ledger(400_000)
        l.entries = [entry(l, amount: 130_000, category: "娱乐"), entry(l, amount: 20_000, category: "交通")]
        let total = Finance.funds(l, now: now).available
        let summary = SpendingParts.summary(l, now: now)
        XCTAssertEqual(summary.parts[0].remaining, 250_000)
        XCTAssertEqual(summary.parts[1].remaining, 0); XCTAssertEqual(summary.parts[1].overflow, 30_000)
        XCTAssertEqual(summary.unassigned, total - 250_000)
        XCTAssertEqual(summary.unassigned, 0)
        l.entries.append(entry(l, amount: 10_000, category: "娱乐"))
        XCTAssertEqual(SpendingParts.summary(l, now: now).unassigned, -10_000)
        XCTAssertEqual(Finance.funds(l, now: now).available, total - 10_000)
    }

    func testOnlyCurrentCycleFlexibleSpendingAndRefundsUseFinanceAmounts() {
        var l = ledger()
        let regular = entry(l, amount: 10_000)
        var bill = entry(l, amount: 30_000); bill.planID = UUID()
        var rent = entry(l, amount: 50_000); rent.rentID = UUID()
        var personal = entry(l, amount: 20_000); personal.personalExpense = 5000
        var refund = entry(l, amount: 1000, category: "其他收入", nature: .refund); refund.relatedEntryID = regular.id
        var billRefund = entry(l, amount: 500, nature: .refund); billRefund.relatedEntryID = bill.id
        var deleted = entry(l, amount: 8000); deleted.deletedAt = now
        l.entries = [regular, bill, rent, personal, refund, billRefund, deleted,
                     entry(l, amount: 1000, at: "2026-10-30"), entry(l, amount: 1000, at: "2026-11-10"),
                     entry(l, amount: 1000, nature: .transfer)]
        let result = SpendingParts.summary(l, now: now)
        XCTAssertEqual(result.parts[0].spent, 14_000)
        XCTAssertEqual(result.base, Finance.funds(l, now: now).available + 14_000)
    }

    func testShareBaseAddsBackSpendingAndFollowsArrivedIncome() {
        var l = ledger(); l.partsMode = .share; l.savingRule = .share(20); l.fixedSavings = 100_000
        l.entries = [entry(l, amount: 100_000, nature: .income), entry(l, amount: 20_000)]
        let summary = SpendingParts.summary(l, now: now)
        XCTAssertEqual(summary.base, 980_000)
        XCTAssertEqual(summary.parts[0].allowance, 392_000); XCTAssertEqual(summary.parts[0].remaining, 372_000)
        l.entries.append(entry(l, amount: 100_000, nature: .income))
        XCTAssertEqual(SpendingParts.summary(l, now: now).parts[0].allowance, 424_000)
        XCTAssertEqual(SpendingParts.fraction(1001, share: 5), 501)
    }

    func testPaydayCycleInsteadOfCalendarMonth() {
        var l = ledger()
        l.plans = [Plan(title: "工资", amount: 800_000, dueDate: date("2026-09-15"), frequency: .monthly, inflow: true, nature: .income)]
        l.entries = [entry(l, amount: 3000, at: "2026-10-14"), entry(l, amount: 5000, at: "2026-10-15")]
        XCTAssertEqual(SpendingParts.summary(l, now: now).parts[0].spent, 5000)
    }

    func testRolloverClosesWithAndWithoutSavingRuleAndSurvivesReload() throws {
        for rule: SavingRule? in [nil, .fixed(10_000)] {
            var l = ledger(); l.partLeftover = .rollOver; l.savingRule = rule
            l.entries = [entry(l, amount: 50_000, at: "2026-10-05")]
            Savings.closeCycles(&l, now: now)
            XCTAssertEqual(l.partCarry[l.spendingParts[0].id], 200_000)
            XCTAssertEqual(l.partCarryCycleStart, date("2026-11-01"))
            XCTAssertEqual(SpendingParts.summary(l, now: now).parts[0].allowance, 450_000)
            XCTAssertEqual(l.fixedSavings ?? 0, rule == nil ? 0 : 10_000)
            XCTAssertEqual(l.savingHistory[0].leftover, 0)
            let closed = l
            Savings.closeCycles(&l, now: now); XCTAssertEqual(l, closed)
            l = try JSONDecoder().decode(Ledger.self, from: JSONEncoder().encode(l))
            Savings.closeCycles(&l, now: now); XCTAssertEqual(l, closed)
            Savings.closeCycles(&l, now: date("2026-12-02"))
            // Close November once, replacing rather than adding to old carry.
            XCTAssertEqual(l.partCarry[l.spendingParts[0].id], 450_000)
            XCTAssertEqual(SpendingParts.summary(l, now: date("2027-01-02")).parts[0].allowance, 250_000)
        }
    }

    func testMergeModeMergesAvailableBeyondTargetOnceAndSurvivesReload() throws {
        var l = ledger(); l.savingRule = .fixed(10_000); l.fixedSavings = 100_000
        l.entries = [entry(l, amount: 50_000, at: "2026-10-05"),
                     entry(l, amount: 200_000, at: "2026-11-05", nature: .income)]
        let close = date("2026-11-01").addingTimeInterval(-0.001)
        XCTAssertEqual(WeeklyLetter.available(l, at: close), 840_000)
        Savings.closeCycles(&l, now: now)
        XCTAssertEqual(l.savingHistory[0].saved, 10_000)
        // Includes both named parts and unassigned funds, excluding the target,
        // existing fixed savings and income received after the closing instant.
        XCTAssertEqual(l.savingHistory[0].leftover, 840_000)
        XCTAssertEqual(l.fixedSavings, 950_000); XCTAssertTrue(l.partCarry.isEmpty)
        XCTAssertNil(l.partCarryCycleStart)
        XCTAssertEqual(Finance.funds(l, now: now).available, 190_000)
        XCTAssertEqual(WeeklyLetter.available(l, at: close), 840_000)
        XCTAssertEqual(SpendingParts.summary(l, now: now).parts[0].allowance, 250_000)
        try l.validate()
        let closed = l
        Savings.closeCycles(&l, now: now); XCTAssertEqual(l, closed)
        l = try JSONDecoder().decode(Ledger.self, from: JSONEncoder().encode(l))
        Savings.closeCycles(&l, now: now); XCTAssertEqual(l, closed)
        Savings.closeCycles(&l, now: date("2026-12-02"))
        XCTAssertEqual(l.savingHistory.count, 2)
        XCTAssertEqual(l.savingHistory[1].saved, 10_000)
        XCTAssertEqual(l.savingHistory[1].leftover, 190_000)
        XCTAssertEqual(l.fixedSavings, 1_150_000)
        XCTAssertEqual(WeeklyLetter.available(l, at: close), 840_000)
        XCTAssertEqual(WeeklyLetter.available(l, at: now), 190_000)
    }

    func testMergeModeWithoutSavingRuleMergesLeftoverOnce() throws {
        var l = ledger()
        l.entries = [entry(l, amount: 50_000, at: "2026-10-05")]
        Savings.closeCycles(&l, now: now)
        XCTAssertEqual(l.fixedSavings, 950_000)
        XCTAssertEqual(l.savingHistory.count, 1)
        XCTAssertEqual(l.savingHistory[0].saved, 0)
        XCTAssertEqual(l.savingHistory[0].target, 0)
        XCTAssertEqual(l.savingHistory[0].leftover, 950_000)
        XCTAssertFalse(l.savingHistory[0].tracked)
        XCTAssertEqual(Finance.funds(l, now: now).available, 0)
        XCTAssertTrue(l.partCarry.isEmpty)
        let closed = l
        Savings.closeCycles(&l, now: now); XCTAssertEqual(l, closed)
        l = try JSONDecoder().decode(Ledger.self, from: JSONEncoder().encode(l))
        Savings.closeCycles(&l, now: now); XCTAssertEqual(l, closed)
        l.savingRule = .fixed(10_000)
        Savings.closeCycles(&l, now: now)
        XCTAssertEqual(l.fixedSavings, 950_000)
        XCTAssertEqual(l.savingHistory.count, 1)
        try l.validate()
    }

    func testClosingWithoutPartsKeepsExistingSavingBehavior() {
        for rule: SavingRule? in [nil, .fixed(10_000)] {
            for mode: PartLeftover in [.mergeIntoFixedSavings, .rollOver] {
                var l = ledger(); l.spendingParts = []; l.savingRule = rule; l.partLeftover = mode
                l.entries = [entry(l, amount: 50_000, at: "2026-10-05")]
                Savings.closeCycles(&l, now: now)
                XCTAssertEqual(l.fixedSavings, rule == nil ? nil : 10_000)
                XCTAssertEqual(l.savingHistory[0].saved, rule == nil ? 0 : 10_000)
                XCTAssertEqual(l.savingHistory[0].leftover, 0)
                XCTAssertEqual(l.savingHistory[0].tracked, rule != nil)
                XCTAssertEqual(Finance.funds(l, now: now).available, rule == nil ? 950_000 : 930_000)
            }
        }
    }

    func testMergeModeNeverMergesNegativeAvailable() {
        for rule: SavingRule? in [nil, .fixed(100_000)] {
            var l = ledger(40_000); l.savingRule = rule
            l.entries = [entry(l, amount: 50_000, at: "2026-10-05")]
            let close = date("2026-11-01").addingTimeInterval(-0.001)
            XCTAssertLessThan(WeeklyLetter.available(l, at: close), 0)
            Savings.closeCycles(&l, now: now)
            XCTAssertEqual(l.savingHistory[0].leftover, 0)
            XCTAssertEqual(l.savingHistory[0].saved, 0)
            XCTAssertEqual(l.fixedSavings ?? 0, 0)
        }
        var l = ledger(40_000); l.savingRule = .fixed(100_000)
        Savings.closeCycles(&l, now: now)
        XCTAssertEqual(l.savingHistory[0].leftover, 0)
        XCTAssertEqual(l.savingHistory[0].saved, 40_000)
        XCTAssertEqual(l.fixedSavings, 40_000)
    }

    func testCycleSavingLeftoverDecodesOldHistoryAndRoundTrips() throws {
        let row = CycleSaving(cycleStart: date("2026-10-01"), cycleEnd: date("2026-10-31"), income: 100_000, target: 10_000, saved: 10_000, leftover: 50_000)
        let data = try JSONEncoder().encode(row)
        XCTAssertEqual(try JSONDecoder().decode(CycleSaving.self, from: data), row)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "leftover"); object.removeValue(forKey: "tracked")
        let old = try JSONDecoder().decode(CycleSaving.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(old.leftover, 0); XCTAssertTrue(old.tracked)
        XCTAssertEqual(old.saved, row.saved); XCTAssertEqual(old.target, row.target)
        var l = ledger(); l.savingHistory = [row]; try l.validate()
        l.savingHistory[0].leftover = -1; XCTAssertThrowsError(try l.validate())
        l.savingHistory[0].leftover = Money.limit + 1; XCTAssertThrowsError(try l.validate())
    }

    func testSuggestionsAverageAvailableCyclesRoundToTenYuanAndIgnoreOverrides() {
        var l = ledger()
        var overridden = entry(l, amount: 10_000, at: "2026-10-05"); overridden.partID = l.spendingParts[1].id
        l.entries = [entry(l, amount: 10_000, at: "2026-09-05"), overridden,
                     entry(l, amount: 2000, category: "娱乐", at: "2026-10-10"), entry(l, amount: 9000)]
        let before = l
        let suggestions = SpendingParts.suggestions(ledger: l, now: now)
        XCTAssertEqual(suggestions.map(\.amount), [10_000, 1000])
        XCTAssertEqual(l, before)
        l.entries = [entry(l, amount: 1550, at: "2026-10-05")]
        XCTAssertEqual(SpendingParts.suggestions(ledger: l, now: now)[0].amount, 2000)
        l.entries = []
        XCTAssertEqual(SpendingParts.suggestions(ledger: l, now: now).map(\.amount), [0, 0])
    }

    func testSuggestedSharesNeverExceedTen() {
        var l = ledger(300_000); l.partsMode = .share
        l.spendingParts = ["餐饮", "娱乐"].map { SpendingPart(name: $0, categories: [$0]) }
        l.entries = [entry(l, amount: 110_000, at: "2026-10-05"), entry(l, amount: 90_000, category: "娱乐", at: "2026-10-05")]
        let suggestions = SpendingParts.suggestions(ledger: l, now: now)
        XCTAssertLessThanOrEqual(suggestions.compactMap(\.share).reduce(0, +), 10)
        XCTAssertEqual(suggestions.compactMap(\.share).reduce(0, +), 10)
        XCTAssertTrue(suggestions.compactMap(\.share).allSatisfy { (1...10).contains($0) })
    }

    func testHintsNormalManualUnassignedOverAndPriority() {
        var l = ledger()
        func hint(_ amount: Int64, _ category: String = "餐饮", partID: UUID? = nil, fixed: Bool = false, nature: Nature = .expense) -> EntryHint {
            EntryHint.make(ledger: l, amount: amount, category: category, isFixedBill: fixed, now: now, nature: nature, partID: partID)
        }
        guard case .normal(let total, _, _, let part) = hint(1000) else { return XCTFail("normal") }
        XCTAssertEqual(total, 999_000); XCTAssertEqual(part?.name, "吃饭"); XCTAssertEqual(part?.after, 249_000)
        guard case .normal(_, _, _, let manual) = hint(1000, partID: l.spendingParts[1].id) else { return XCTFail("manual") }
        XCTAssertEqual(manual?.name, "玩乐")
        guard case .normal(_, _, _, let unassigned) = hint(1000, "交通") else { return XCTFail("unassigned") }
        XCTAssertEqual(unassigned?.name, "没分的"); XCTAssertEqual(unassigned?.after, 649_000)
        guard case .normal(_, _, _, let over) = hint(145_000, "娱乐") else { return XCTFail("part over") }
        XCTAssertEqual(over?.overBy, 45_000); XCTAssertEqual(over?.after, -45_000)
        guard case .big = hint(210_000, "娱乐") else { return XCTFail("big wins") }
        l.profile.restrain = [ProfileArea(title: "玩乐", match: AreaMatch(categories: ["娱乐"]))]
        guard case .restrain = hint(210_000, "娱乐") else { return XCTFail("restrain wins") }
        guard case .normal(_, _, _, nil) = hint(1000, fixed: true) else { return XCTFail("fixed bill") }
        guard case .normal(_, _, _, nil) = hint(1000, nature: .income) else { return XCTFail("income") }
        l.spendingParts = []
        guard case .normal(_, _, _, nil) = hint(1000) else { return XCTFail("legacy") }
    }

    func testPurchasePartReasonWaitAndExistingFinancialBoundaries() {
        var l = ledger(); l.spendingParts[1].amount = 30_000
        let bounds = PurchaseBounds.compute(ledger: l, amount: 45_000, title: "游戏", category: "娱乐", now: now)
        XCTAssertEqual(bounds.allowedVerdicts, [.wait, .skip])
        XCTAssertEqual(bounds.boundReason, "玩乐这月还剩 300，这笔 450 会用掉没分的 150。")
        XCTAssertEqual(PurchaseBounds.compute(ledger: l, amount: 30_000, title: "游戏", category: "娱乐", now: now).allowedVerdicts, Set(PurchaseVerdict.allCases))
        l.spendingParts[1].amount = 900_000
        let assessment = Finance.assessPurchase(l, amount: 400_000, title: "游戏", category: "娱乐", now: now)
        XCTAssertEqual(assessment.verdict, .wait)
        XCTAssertTrue(assessment.reason.hasPrefix("玩乐这月还剩"))
        l.spendingParts[1].amount = 30_000
        l.savingRule = .fixed(990_000)
        XCTAssertEqual(PurchaseBounds.compute(ledger: l, amount: 45_000, title: "游戏", category: "娱乐", now: now).allowedVerdicts, [.wait, .skip])
        l.accounts[0].anchorBalance = 10_000
        XCTAssertEqual(PurchaseBounds.compute(ledger: l, amount: 45_000, title: "游戏", category: "娱乐", now: now).allowedVerdicts, [.skip])
    }

    func testApprovedPartReasonCanBeSubmittedAndInventedNumbersAreRejected() throws {
        var l = ledger(); l.spendingParts[1].amount = 30_000
        let ctx = ToolContext(ledger: l, now: now)
        let judgment = try JudgePurchaseTool().judge(.object(["title": .string("游戏"), "amount": .string("450"), "category": .string("娱乐")]), ctx)
        XCTAssertEqual(judgment.facts["spending_part"]?["remaining"], .money(30_000))
        let reason = try XCTUnwrap(judgment.facts["bound_reason"]?.stringValue)
        func submit(_ reason: String, verdict: String = "wait") throws -> SubmittedPurchaseVerdict {
            try SubmitVerdictTool().submit(.object(["verdict": .string(verdict), "need": .string("want"), "reason": .string(reason)]), judgment: judgment, context: ctx)
        }
        XCTAssertEqual(try submit(reason).verdict, .wait)
        XCTAssertThrowsError(try submit(reason, verdict: "buy"))
        XCTAssertThrowsError(try submit(reason.replacingOccurrences(of: "150", with: "151")))
    }

    func testCategoryRenameMergeAndMovingBetweenPartsStayUnique() throws {
        var l = ledger()
        try CategoryModel.rename("餐饮", to: "三餐", income: false, in: &l)
        XCTAssertEqual(l.spendingParts[0].categories, ["三餐"])
        SpendingParts.assign(category: "三餐", to: l.spendingParts[1].id, in: &l)
        XCTAssertTrue(l.spendingParts[0].categories.isEmpty)
        XCTAssertTrue(l.spendingParts[1].categories.contains("三餐"))
        try CategoryModel.merge("三餐", into: "购物", income: false, in: &l)
        XCTAssertEqual(l.spendingParts.flatMap(\.categories).filter { $0 == "购物" }.count, 1)
        XCTAssertFalse(l.spendingParts.flatMap(\.categories).contains("三餐"))
        SpendingParts.assign(category: "购物", to: nil, in: &l)
        XCTAssertFalse(l.spendingParts.flatMap(\.categories).contains("购物"))
    }

    func testManualDraftAndEditRetainOverride() throws {
        var l = ledger()
        var draft = EntryDraft(date: now, amount: 1000, amountConfirmed: true, accountID: l.accounts[0].id, title: "午饭", category: "餐饮")
        draft.partID = l.spendingParts[1].id
        try ChangeSet(source: "手动", reason: "记一笔", items: [.addEntry(draft)]).apply(to: &l)
        XCTAssertEqual(l.entries[0].partID, draft.partID)
        var edited = l.entries[0]; edited.partID = SpendingPart.unassignedID
        try ManualBookkeeping.edit(edited, in: &l)
        XCTAssertEqual(l.entries[0].partID, SpendingPart.unassignedID)
    }

    func testValidationAndCacheInvalidationOnPartChanges() throws {
        var l = ledger(); try l.validate()
        let original = l
        l.spendingParts[0].share = 11; XCTAssertThrowsError(try l.validate())
        l = original; l.spendingParts[1].categories.append("餐饮"); XCTAssertThrowsError(try l.validate())
        l = original; l.spendingParts[0].amount = -1; XCTAssertThrowsError(try l.validate())
        l = original; l.partCarry[l.spendingParts[0].id] = -1; XCTAssertThrowsError(try l.validate())
    }
}
