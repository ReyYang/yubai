import XCTest
@testable import YubaiCore

final class FixedSavingsIncomeTests: XCTestCase {
    private let now = Dates.parse("2026-11-10 12:00")!
    private func date(_ text: String) -> Date { Dates.parse(text)! }
    private func ledger() -> Ledger {
        var ledger = Ledger()
        ledger.accounts = [Account(name: "银行卡", balance: 1_000_000, at: date("2026-09-01"))]
        ledger.fixedSavings = 100_000
        ledger.savingRule = .share(20)
        ledger.entries = [Entry(date: date("2026-11-02"), amount: 800_000, nature: .income,
                                accountID: ledger.accounts[0].id, title: "工资")]
        return ledger
    }
    private func subsidy(in ledger: Ledger, amount: Int64 = 500_000) -> EntryDraft {
        EntryDraft(date: now, amount: amount, amountConfirmed: true, nature: .income,
                   accountID: ledger.accounts[0].id, title: "住房补贴", intoFixedSavings: true)
    }
    private func change(_ draft: EntryDraft) -> ChangeSet {
        var change = ChangeSet(source: "手动", reason: "记一笔", items: [.addEntry(draft)])
        change.createdAt = now
        return change
    }
    private func assertIdentity(_ funds: Funds, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(funds.liquidStart + funds.cycleIncome - funds.savingTarget - funds.cycleSpent - funds.dueRest,
                       funds.available, file: file, line: line)
    }
    private func withoutKeys<T: Codable>(_ value: T, _ keys: [String]) throws -> T {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
        for key in keys { object.removeValue(forKey: key) }
        return try JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: object))
    }

    func testSavingModeRestoresBothValuesAndDefaults() throws {
        var ledger = ledger()
        ledger.savingRule = .fixed(500_000)
        ledger.switchSavingMode(sharing: true)
        XCTAssertEqual(ledger.savingRule, .share(20))
        XCTAssertEqual(Finance.funds(ledger, now: now).savingTarget, 160_000)
        ledger.switchSavingMode(sharing: false)
        XCTAssertEqual(ledger.savingRule, .fixed(500_000))
        ledger.savingRule = .share(30)
        ledger.switchSavingMode(sharing: false)
        ledger.switchSavingMode(sharing: true)
        XCTAssertEqual(ledger.savingRule, .share(30))
        ledger = try LedgerCodec.decode(LedgerCodec.encode(ledger))
        ledger.switchSavingMode(sharing: false)
        XCTAssertEqual(ledger.savingRule, .fixed(500_000))
        var empty = Ledger()
        empty.switchSavingMode(sharing: true)
        XCTAssertEqual(empty.savingRule, .share(20))
        empty.switchSavingMode(sharing: false)
        XCTAssertEqual(empty.savingRule, .fixed(0))
        empty = Ledger(); empty.switchSavingMode(sharing: false)
        XCTAssertEqual(empty.savingRule, .fixed(0))
        empty.savingRule = nil
        XCTAssertEqual(empty.lastFixedSavingTarget, 0)
    }

    func testOldLedgerSeedsActiveRuleMemoryAndValidatesBothMemories() throws {
        for rule: SavingRule in [.fixed(500_000), .share(30)] {
            var ledger = ledger(); ledger.savingRule = rule
            var decoded = try withoutKeys(ledger, ["lastFixedSavingTarget", "lastSavingSharePercent"])
            decoded.switchSavingMode(sharing: rule == .fixed(500_000))
            decoded.switchSavingMode(sharing: rule != .fixed(500_000))
            XCTAssertEqual(decoded.savingRule, rule)
        }
        var ledger = Ledger(); try ledger.validate()
        let original = ledger
        ledger.lastFixedSavingTarget = 1
        XCTAssertNotEqual(ledger, original)
        XCTAssertNotEqual(try LedgerCodec.encode(ledger), try LedgerCodec.encode(original))
        ledger.lastFixedSavingTarget = -1; XCTAssertThrowsError(try ledger.validate())
        ledger.lastFixedSavingTarget = Money.limit + 1; XCTAssertThrowsError(try ledger.validate())
        ledger.lastFixedSavingTarget = 0; ledger.lastSavingSharePercent = 0
        XCTAssertThrowsError(try ledger.validate())
        ledger.lastSavingSharePercent = 91; XCTAssertThrowsError(try ledger.validate())
        ledger.lastSavingSharePercent = 90; XCTAssertNoThrow(try ledger.validate())
    }

    func testDirectIncomeLeavesAvailableAndShareUnchangedThenDeleteReverts() throws {
        var ledger = ledger()
        let before = Finance.funds(ledger, now: now)
        let draft = subsidy(in: ledger)
        XCTAssertEqual(try ManualBookkeeping.available(after: change(draft), in: ledger, now: now), before.available)
        try change(draft).apply(to: &ledger)
        let after = Finance.funds(ledger, now: now)
        XCTAssertEqual(after.cash, before.cash + 500_000)
        XCTAssertEqual(after.available, before.available)
        XCTAssertEqual(after.cycleIncome, before.cycleIncome)
        XCTAssertEqual(after.savingTarget, before.savingTarget)
        XCTAssertEqual(after.liquidStart, before.liquidStart)
        XCTAssertEqual(after.fixedSavingsTotal, before.fixedSavingsTotal + 500_000)
        XCTAssertEqual(ledger.fixedSavings, 100_000)
        assertIdentity(after)
        ledger.entries[1].deletedAt = now
        XCTAssertEqual(ledger.fixedSavingsTotal(now: now), before.fixedSavingsTotal)
        XCTAssertEqual(Finance.funds(ledger, now: now).available, before.available)
        ledger.entries[1].deletedAt = nil
        XCTAssertEqual(ledger.fixedSavingsTotal(now: now), before.fixedSavingsTotal + 500_000)
    }

    func testAmountEditsAndUntickingMatchIncrementalPreview() throws {
        var ledger = ledger(); let before = Finance.funds(ledger, now: now)
        try change(subsidy(in: ledger)).apply(to: &ledger)
        var edited = ledger.entries[1]; edited.amount = 600_000
        XCTAssertEqual(try ManualBookkeeping.available(after: edited, in: ledger, now: now), before.available)
        try ManualBookkeeping.edit(edited, in: &ledger)
        XCTAssertEqual(ledger.fixedSavingsTotal(now: now), 700_000)
        XCTAssertEqual(Finance.funds(ledger, now: now).available, before.available)
        edited.intoFixedSavings = false
        let preview = try ManualBookkeeping.available(after: edited, in: ledger, now: now)
        try ManualBookkeeping.edit(edited, in: &ledger)
        let after = Finance.funds(ledger, now: now)
        XCTAssertEqual(after.fixedSavingsTotal, 100_000)
        XCTAssertEqual(after.cycleIncome, before.cycleIncome + 600_000)
        XCTAssertEqual(after.savingTarget, before.savingTarget + 120_000)
        XCTAssertEqual(after.available, before.available + 480_000)
        XCTAssertEqual(preview, after.available)
        assertIdentity(after)
    }

    func testFutureIncomeWaitsForPostingAndInvalidatesCachedFunds() throws {
        var ledger = ledger(); let before = Finance.funds(ledger, now: now)
        var draft = subsidy(in: ledger); draft.date = now.addingTimeInterval(60)
        try change(draft).apply(to: &ledger)
        XCTAssertEqual(ledger.fixedSavingsTotal(now: now), before.fixedSavingsTotal)
        XCTAssertEqual(Finance.funds(ledger, now: now).available, before.available)
        let posted = Finance.funds(ledger, now: draft.date)
        XCTAssertEqual(posted.fixedSavingsTotal, before.fixedSavingsTotal + draft.amount)
        XCTAssertEqual(posted.available, before.available)
        XCTAssertEqual(posted.savingTarget, before.savingTarget)
        assertIdentity(posted)
    }

    func testReconciliationAndAccountKindsUseCashPostingRules() throws {
        var ledger = ledger(); ledger.accounts[0].anchorDate = now
        var entry = Entry(date: now, amount: 500_000, nature: .income, accountID: ledger.accounts[0].id,
                          title: "补贴", intoFixedSavings: true)
        ledger.entries = [entry]
        XCTAssertEqual(ledger.fixedSavingsTotal(now: now), 100_000)
        entry.recordedAt = now.addingTimeInterval(1)
        ledger.entries = [entry]; ledger.accounts[0].archived = true
        XCTAssertEqual(ledger.fixedSavingsTotal(now: now.addingTimeInterval(1)), 600_000)
        entry.date = Dates.addDays(-1, to: now); ledger.entries = [entry]
        XCTAssertEqual(ledger.fixedSavingsTotal(now: now), 100_000)
        for kind: AccountKind in [.investment, .receivable, .credit] {
            ledger.accounts[0].kind = kind; ledger.accounts[0].anchorDate = date("2026-09-01")
            XCTAssertEqual(ledger.fixedSavingsTotal(now: now), 100_000)
        }
        ledger.accounts[0].kind = .cash
        XCTAssertEqual(ledger.fixedSavingsTotal(now: now), 600_000)
    }

    func testSettingTotalClampsToFlaggedIncomeAndChecksCombinedLimit() throws {
        var ledger = ledger(); try change(subsidy(in: ledger)).apply(to: &ledger)
        ledger.setFixedSavingsTotal(800_000, now: now)
        XCTAssertEqual(ledger.fixedSavings, 300_000)
        XCTAssertEqual(ledger.fixedSavingsTotal(now: now), 800_000)
        ledger.setFixedSavingsTotal(200_000, now: now)
        XCTAssertEqual(ledger.fixedSavings, 0)
        XCTAssertEqual(ledger.fixedSavingsTotal(now: now), 500_000)
        XCTAssertNoThrow(try ledger.validate())
        ledger.setFixedSavingsTotal(-1, now: now)
        XCTAssertEqual(ledger.fixedSavingsTotal(now: now), 500_000)
        ledger.setFixedSavingsTotal(Money.limit, now: now)
        XCTAssertNoThrow(try ledger.validate())
        ledger.fixedSavings! += 1
        XCTAssertThrowsError(try ledger.validate())
        ledger.fixedSavings = 0; ledger.entries[1].amount = Money.limit
        ledger.entries[1].date = Dates.addDays(1, to: now); ledger.fixedSavings = 1
        XCTAssertThrowsError(try ledger.validate()) // Future totals are bounded too.
    }

    func testPreviewRejectsCombinedSavingsOverflowAndAssistantSetsTotal() throws {
        var ledger = ledger(); try change(subsidy(in: ledger)).apply(to: &ledger)
        ledger.fixedSavings = Money.limit - 500_000
        let extra = change(subsidy(in: ledger, amount: 1))
        XCTAssertThrowsError(try ManualBookkeeping.available(after: extra, in: ledger, now: now))
        var copy = ledger; XCTAssertThrowsError(try extra.apply(to: &copy))
        var edited = ledger.entries[1]; edited.amount += 1
        XCTAssertThrowsError(try ManualBookkeeping.available(after: edited, in: ledger, now: now))
        var setting = ChangeSet(source: "问余白", reason: "设置存款总额", items: [.profile(.setFloorAmount(800_000))])
        setting.createdAt = now
        try setting.apply(to: &ledger)
        XCTAssertEqual(ledger.fixedSavings, 300_000)
        XCTAssertEqual(ledger.fixedSavingsTotal(now: now), 800_000)
        setting.items = [.profile(.setFloorAmount(nil))]
        XCTAssertEqual(setting.preview(in: ledger), ["存着不动 " + Money.text(500_000)])
        try setting.apply(to: &ledger)
        XCTAssertEqual(ledger.fixedSavingsTotal(now: now), 500_000)
    }

    func testPlanSettlementAutoSettlementAndRepeatPreserveDestination() throws {
        var ledger = ledger()
        var plan = Plan(title: "住房补贴", amount: 500_000, dueDate: now, inflow: true, nature: .income, intoFixedSavings: true)
        plan.accountID = ledger.accounts[0].id
        ledger.plans = [plan]
        let before = Finance.funds(ledger, now: now)
        let settlement = try FixedFlows.settle(planID: plan.id, occurrence: now, in: ledger, now: now)
        try settlement.apply(to: &ledger)
        XCTAssertTrue(ledger.entries[1].intoFixedSavings)
        XCTAssertEqual(ledger.entries[1].planID, plan.id)
        XCTAssertEqual(Finance.funds(ledger, now: now).available, before.available)
        XCTAssertEqual(try FixedFlows.monthlyPlan(from: ledger.entries[1]).intoFixedSavings, true)

        ledger = self.ledger(); plan.autoPay = true; plan.accountID = ledger.accounts[0].id; ledger.plans = [plan]
        let automatic = try XCTUnwrap(FixedFlows.autoSettle(in: ledger, now: now))
        try automatic.apply(to: &ledger)
        XCTAssertTrue(ledger.entries[1].intoFixedSavings)
        XCTAssertNil(FixedFlows.autoSettle(in: ledger, now: now))

        ledger = self.ledger()
        let repeated = try FixedFlows.monthlyEntryChange(amount: 500_000, nature: .income, accountID: ledger.accounts[0].id,
            day: now, purpose: "补贴", category: Classification.pendingCategory, now: now, intoFixedSavings: true)
        try repeated.apply(to: &ledger)
        XCTAssertTrue(ledger.plans[0].intoFixedSavings)
        XCTAssertTrue(ledger.entries[1].intoFixedSavings)
    }

    func testCycleClosingAndHistoricalSnapshotNeverMergeDirectIncomeTwice() throws {
        for mergeLeftover in [false, true] {
            var ledger = ledger()
            ledger.entries[0].date = date("2026-10-02")
            var draft = subsidy(in: ledger); draft.date = date("2026-10-10")
            try change(draft).apply(to: &ledger)
            if mergeLeftover { ledger.spendingParts = [SpendingPart(name: "日常", amount: 10_000)] }
            let close = date("2026-11-01").addingTimeInterval(-0.001)
            let previous = Finance.funds(WeeklyLetter.snapshot(ledger, at: close), now: close)
            XCTAssertEqual(previous.cycleIncome, 800_000)
            XCTAssertEqual(previous.savingTarget, 160_000)
            let base = ledger.fixedSavings ?? 0
            Savings.closeCycles(&ledger, now: now)
            let history = try XCTUnwrap(ledger.savingHistory.last)
            XCTAssertEqual(history.income, 800_000); XCTAssertEqual(history.target, 160_000)
            XCTAssertEqual(history.saved, 160_000)
            XCTAssertEqual(ledger.fixedSavings, base + history.saved + history.leftover)
            XCTAssertEqual(ledger.fixedSavingsTotal(now: now), base + history.saved + history.leftover + 500_000)
            XCTAssertEqual(WeeklyLetter.available(ledger, at: close), previous.available)
            let closed = ledger; Savings.closeCycles(&ledger, now: now)
            XCTAssertEqual(ledger, closed)
            try ledger.validate()
        }
    }

    func testHintAndTimelineExposeDirectSavingsWithoutSpendingReceipt() throws {
        var ledger = ledger(); let draft = subsidy(in: ledger)
        XCTAssertEqual(EntryHint.make(ledger: ledger, draft: draft, isFixedBill: false, now: now), .fixedSavings(newTotal: 600_000))
        var ordinary = draft; ordinary.intoFixedSavings = false
        XCTAssertEqual(EntryHint.make(ledger: ledger, draft: ordinary, isFixedBill: false, now: now),
                       .receipt(EntryHint.make(ledger: ledger, amount: ordinary.amount, category: ordinary.category, isFixedBill: false, now: now, nature: .income)))
        try change(draft).apply(to: &ledger)
        let rows = EntryTimeline.snapshot(sortedEntries: ledger.entries, ledger: ledger, month: now, search: "住房补贴").days.flatMap(\.entries)
        XCTAssertEqual(rows.count, 1); XCTAssertTrue(rows[0].intoFixedSavings)
        let funds = try ReadOnlyTool.getFunds.run(.object([:]), ToolContext(ledger: ledger, now: now))
        XCTAssertEqual(funds["fixed_savings"]?["cents"], .number(600_000))
        let profile = try ReadOnlyTool.getProfile.run(.object([:]), ToolContext(ledger: ledger, now: now))
        XCTAssertEqual(profile["fixed_savings"]?["cents"], .number(600_000))
        let queried = try ReadOnlyTool.queryEntries.run(.object(["keyword": .string("住房补贴")]), ToolContext(ledger: ledger, now: now))
        XCTAssertEqual(queried["entries"]?.arrayValue?.first?["into_fixed_savings"], .bool(true))
    }

    func testCodableAndLegacyDefaultsForEntriesDraftsPlansAndBackup() throws {
        var ledger = ledger(); let draft = subsidy(in: ledger)
        try change(draft).apply(to: &ledger)
        let plan = Plan(title: "补贴", amount: 500_000, dueDate: now, inflow: true, nature: .income, intoFixedSavings: true)
        ledger.plans = [plan]; ledger.pendingChanges = [change(draft)]
        XCTAssertEqual(try LedgerCodec.decode(LedgerCodec.encode(ledger)), ledger)
        XCTAssertEqual(try Backup.restore(Backup.export(ledger)), ledger)
        XCTAssertEqual(try JSONDecoder().decode(EntryDraft.self, from: JSONEncoder().encode(draft)), draft)
        XCTAssertFalse(try withoutKeys(ledger.entries[1], ["intoFixedSavings"]).intoFixedSavings)
        XCTAssertFalse(try withoutKeys(draft, ["intoFixedSavings"]).intoFixedSavings)
        XCTAssertFalse(try withoutKeys(plan, ["intoFixedSavings"]).intoFixedSavings)
        var invalidJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(ledger.entries[1])) as? [String: Any])
        invalidJSON["nature"] = "expense"
        let normalized = try JSONDecoder().decode(Entry.self, from: JSONSerialization.data(withJSONObject: invalidJSON))
        XCTAssertFalse(normalized.intoFixedSavings)
    }

    func testNatureChangesClearFlagAcrossEditPaths() throws {
        var ledger = ledger(); try change(subsidy(in: ledger)).apply(to: &ledger)
        let id = ledger.entries[1].id
        var reclassify = ChangeSet(source: "用户操作", reason: "性质更正", items: [.setNature(entry: id, nature: .unknownIn, otherAccount: nil)])
        reclassify.createdAt = now
        var changed = ledger; try reclassify.apply(to: &changed)
        XCTAssertFalse(changed.entries[1].intoFixedSavings)
        changed = ledger; try LedgerOperations.bulkEdit([id], category: nil, nature: .unknownIn, in: &changed)
        XCTAssertFalse(changed.entries[1].intoFixedSavings)
        var entry = ledger.entries[1]; entry.nature = .expense; entry.intoFixedSavings = true
        XCTAssertFalse(entry.intoFixedSavings)
        var draft = subsidy(in: ledger); draft.nature = .refund; draft.intoFixedSavings = true
        XCTAssertFalse(draft.intoFixedSavings)
        var plan = Plan(title: "补贴", amount: 500_000, dueDate: now, inflow: true, nature: .income, intoFixedSavings: true)
        plan.nature = .expense; XCTAssertFalse(plan.intoFixedSavings)
        plan.intoFixedSavings = true; XCTAssertFalse(plan.intoFixedSavings)
        plan.nature = .income; plan.intoFixedSavings = true; plan.inflow = false
        XCTAssertFalse(plan.intoFixedSavings)
    }

    func testProposalParsesSingleBatchAndPlanFlagsAndRejectsNonIncomeOrNonBoolean() throws {
        let ledger = ledger()
        let ctx = ToolContext(ledger: ledger, now: now, confirmedEntryAmount: 500_000, parsedEntryAmounts: [500_000])
        var fields: [String: JSONValue] = ["reason": .string("住房补贴存着不动"), "title": .string("住房补贴"), "amount": .string("5000"),
            "date": .string("2026-11-10"), "account": .string(ledger.accounts[0].id.uuidString), "nature": .string("income"), "into_fixed_savings": .bool(true)]
        let single = try ProposalTool.entry.propose(.object(fields), ctx)
        guard case .addEntry(let draft) = single.items[0] else { return XCTFail("missing entry") }
        XCTAssertTrue(draft.intoFixedSavings)
        XCTAssertTrue(single.preview(in: ledger)[0].hasSuffix("，存着不动"))
        var batch = fields; batch.removeValue(forKey: "reason")
        let grouped = try ProposalTool.entry.propose(.object(["reason": .string("补贴"), "entries": .array([.object(batch)])]), ctx)
        guard case .addEntry(let batchDraft) = grouped.items[0] else { return XCTFail("missing batch draft") }
        XCTAssertTrue(batchDraft.intoFixedSavings)
        fields["operation"] = .string("add_plan"); fields["frequency"] = .string("once")
        let planned = try ProposalTool.plan.propose(.object(fields), ctx)
        guard case .addPlan(let plan) = planned.items[0] else { return XCTFail("missing plan") }
        XCTAssertTrue(plan.intoFixedSavings)
        XCTAssertTrue(planned.preview(in: ledger)[0].hasSuffix("，存着不动"))
        for flag: JSONValue in [.bool(true), .bool(false), .string("true")] {
            fields["nature"] = .string("expense"); fields["into_fixed_savings"] = flag
            XCTAssertThrowsError(try ProposalTool.plan.propose(.object(fields), ctx))
            var expense = fields; expense.removeValue(forKey: "operation"); expense.removeValue(forKey: "frequency")
            XCTAssertThrowsError(try ProposalTool.entry.propose(.object(expense), ctx))
        }
        fields["nature"] = .string("income"); fields["into_fixed_savings"] = .string("true")
        XCTAssertThrowsError(try ProposalTool.plan.propose(.object(fields), ctx))
    }

    func testColdStartRecognizesSavingsFromIncomeAlone() async throws {
        var ledger = ledger(); ledger.fixedSavings = nil; ledger.savingRule = nil
        try change(subsidy(in: ledger)).apply(to: &ledger)
        let script = ScriptedChatTransport([ChatMessage(role: .assistant, content: "想聊哪件事？")])
        _ = try await ProfileColdStart(transport: script).next(ledger: ledger, messages: [], now: now)
        let requests = await script.recorded()
        XCTAssertTrue(requests[0].messages[0].content?.contains("这是再聊") == true)
    }
}
