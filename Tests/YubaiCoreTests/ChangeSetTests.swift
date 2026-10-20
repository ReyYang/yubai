import XCTest
@testable import YubaiCore

final class ChangeSetTests: XCTestCase {
    private let day = Dates.parse("2026-10-03")!
    private func ledger() -> Ledger {
        var l = Ledger(); l.accounts = [Account(name: "银行卡", at: day), Account(name: "零钱", kind: .cash, at: day)]
        l.entries = [Entry(date: day, amount: 4250, accountID: l.accounts[0].id, title: "美团", category: "其他支出"),
                     Entry(date: day, amount: 150000, nature: .unknownIn, accountID: l.accounts[0].id, title: "联系人A 转入")]
        return l
    }
    @discardableResult private func apply(_ items: [ChangeItem], to l: inout Ledger, file: StaticString = #filePath, line: UInt = #line) throws -> [String] {
        let before = l
        var change = ChangeSet(source: "导入整理", reason: "商户和用途已核对", items: items); change.createdAt = day
        let skipped = try change.apply(to: &l)
        for old in before.entries {
            let e = try XCTUnwrap(l.entries.first { $0.id == old.id }, file: file, line: line)
            XCTAssertEqual(e.amount, old.amount, file: file, line: line)
            XCTAssertEqual(e.accountID, old.accountID, file: file, line: line)
            XCTAssertEqual(e.date, old.date, file: file, line: line)
            if e != old { XCTAssertTrue(e.classificationReason.contains("导入整理：商户和用途已核对"), file: file, line: line) }
        }
        XCTAssertNoThrow(try l.validate(), file: file, line: line)
        return skipped
    }
    func testCategoryNaturePurposeAndPreview() throws {
        var l = ledger(); let expense = l.entries[0].id; let inflow = l.entries[1].id
        let change = ChangeSet(source: "问余白", reason: "美团是午餐", items: [.setCategory(entry: expense, category: "餐饮"), .setPurpose(entry: expense, text: "工作日午餐")])
        XCTAssertEqual(change.preview(in: l), ["把 10月3日 美团 −42.50 归为 餐饮", "把 10月3日 美团 −42.50 的用途记为「工作日午餐」"])
        try apply(change.items + [.setNature(entry: inflow, nature: .income, otherAccount: nil)], to: &l)
        XCTAssertEqual(l.entries[0].category, "餐饮"); XCTAssertEqual(l.entries[0].title, "美团")
        XCTAssertEqual(l.entries[0].displayTitle, "工作日午餐"); XCTAssertEqual(l.entries[1].nature, .income)
        XCTAssertTrue(try apply(change.items, to: &l).count == 2)
        // Linking a second account never changes the original account/date/amount.
        try apply([.setNature(entry: expense, nature: .transfer, otherAccount: l.accounts[1].id)], to: &l)
        XCTAssertEqual(l.entries[0].otherAccountID, l.accounts[1].id)
    }
    func testPairTransferPreservesBothOriginalsAndIsIdempotent() throws {
        var l = ledger()
        l.entries[1].amount = l.entries[0].amount; l.entries[1].accountID = l.accounts[1].id
        l.entries[1].date = Dates.addDays(1, to: day)
        let a = l.entries[0].id; let b = l.entries[1].id
        let items: [ChangeItem] = [.pairTransfer(a: a, b: b, nature: .transfer)]
        try apply(items, to: &l)
        XCTAssertEqual(l.activeEntries.count, 1); XCTAssertEqual(l.entries[0].nature, .transfer)
        XCTAssertEqual(l.entries[0].otherDate, Dates.addDays(1, to: day)); XCTAssertEqual(l.entries[1].mergedIntoID, a)
        XCTAssertNotNil(l.entries[1].deletedAt); XCTAssertEqual(try apply(items, to: &l).count, 1)
    }
    func testRefundLinksAndCategoryPropagationMarkAllTouchedEntries() throws {
        var l = ledger(); l.entries[1].amount = 500
        let refund = l.entries[1].id; let original = l.entries[0].id
        try apply([.linkRefund(refund: refund, original: original)], to: &l)
        XCTAssertEqual(l.entries[1].nature, .refund); XCTAssertEqual(l.entries[1].relatedEntryID, original)
        try apply([.setCategory(entry: original, category: "餐饮")], to: &l)
        XCTAssertEqual(l.entries[1].category, "餐饮")
        XCTAssertEqual(try apply([.linkRefund(refund: refund, original: original)], to: &l).count, 1)
    }
    func testPlanAndRentAddLinkEnd() throws {
        var l = ledger()
        let plan = Plan(title: "午餐", amount: 4250, dueDate: day, frequency: .monthly)
        let rent = Rent(monthlyTotal: 300000, personalShare: 150000, startDate: day, nextDueDate: day)
        try apply([.addPlan(plan), .addRent(rent)], to: &l)
        let expense = l.entries[0].id; let inflow = l.entries[1].id
        try apply([.linkPlan(entry: expense, plan: plan.id, occurrence: day),
                   .setNature(entry: inflow, nature: .contribution, otherAccount: nil),
                   .linkRent(entry: inflow, rent: rent.id, period: day),
                   .endPlan(plan.id, Dates.addMonths(2, to: day))], to: &l)
        XCTAssertEqual(l.entries[0].planID, plan.id); XCTAssertEqual(l.entries[0].occurrence, day)
        XCTAssertEqual(l.entries[1].rentID, rent.id)
        XCTAssertEqual(Dates.calendar.component(.day, from: l.entries[1].rentPeriod!), 1)
        XCTAssertEqual(l.plans[0].endDate, Dates.addMonths(2, to: day)); XCTAssertTrue(l.plans[0].active)
        XCTAssertEqual(try apply([.linkPlan(entry: expense, plan: plan.id, occurrence: day), .endPlan(plan.id, day)], to: &l).count, 2)
        // A rent expense retains actual payment amount; the code computes personal spending.
        var payment = Entry(date: day, amount: 300000, accountID: l.accounts[0].id, title: "房租")
        payment.category = "居住"; l.entries.append(payment)
        try apply([.linkRent(entry: payment.id, rent: rent.id, period: day)], to: &l)
        XCTAssertEqual(l.entries.last?.personalExpense, 150000)
    }
    func testDuplicateGoesToTrashWithReason() throws {
        var l = ledger(); var duplicate = l.entries[0]; duplicate.id = UUID(); l.entries.append(duplicate)
        let original = l.entries[0].id
        try apply([.markDuplicate(entry: duplicate.id, of: original)], to: &l)
        XCTAssertNotNil(l.entries.last?.deletedAt)
        XCTAssertTrue(l.entries.last?.classificationReason.contains("重复于 \(original.uuidString)") ?? false)
        XCTAssertEqual(try apply([.markDuplicate(entry: duplicate.id, of: original)], to: &l).count, 1)
    }
    func testConfirmedDraftOnlyAndNoMutationOnFailure() throws {
        var l = ledger()
        var draft = EntryDraft(date: day, amount: 5000, accountID: l.accounts[0].id, title: "书", purpose: "学习")
        let bytes = try LedgerCodec.encode(l)
        XCTAssertThrowsError(try ChangeSet(source: "问余白", reason: "截图补记", items: [.addEntry(draft)]).apply(to: &l))
        XCTAssertEqual(try LedgerCodec.encode(l), bytes)
        draft.amountConfirmed = true
        try apply([.addEntry(draft)], to: &l)
        XCTAssertEqual(l.entries.last?.id, draft.id); XCTAssertEqual(l.entries.last?.displayTitle, "学习")
        XCTAssertEqual(try apply([.addEntry(draft)], to: &l).count, 1)
    }
    func testAllProfileEditsAndRemovals() throws {
        var l = ledger(); let area = ProfileArea(title: "外卖", match: AreaMatch(categories: ["餐饮"], keywords: ["美团"]), note: "加班", softLimit: SoftLimit(perWeekCount: 3, perMonthAmount: 100000))
        try apply([.profile(.upsertArea(area, stance: .restrain)), .profile(.addPrinciple("等 48 小时")), .profile(.setFloorAmount(50000))], to: &l)
        XCTAssertEqual(l.profile.restrain, [area]); XCTAssertEqual(l.profile.floorAmount, 50000)
        var edited = area; edited.title = "工作午餐"
        try apply([.profile(.upsertArea(edited, stance: .generous)), .profile(.editPrinciple(old: "等 48 小时", new: "先借后买"))], to: &l)
        XCTAssertTrue(l.profile.restrain.isEmpty); XCTAssertEqual(l.profile.generous, [edited])
        try apply([.profile(.removeArea(area.id)), .profile(.removePrinciple("先借后买")), .profile(.setFloorAmount(nil))], to: &l)
        XCTAssertTrue(l.profile.generous.isEmpty); XCTAssertTrue(l.profile.principles.isEmpty); XCTAssertNil(l.profile.floorAmount)
        XCTAssertEqual(l.profile.updatedAt, day)
    }
    func testInvalidSetIsByteIdenticalEvenAfterEarlierValidItem() throws {
        var l = ledger(); let id = l.entries[0].id; let original = try LedgerCodec.encode(l)
        let invalidSets: [[ChangeItem]] = [
            [.setCategory(entry: id, category: "餐饮"), .profile(.setFloorAmount(-1))],
            [.setPurpose(entry: id, text: "午餐"), .setNature(entry: id, nature: .income, otherAccount: nil)],
            [.setCategory(entry: id, category: "餐饮"), .setNature(entry: id, nature: .transfer, otherAccount: UUID())],
            [.linkRefund(refund: l.entries[1].id, original: id)], // Refund exceeds original.
            [.addPlan(Plan(title: "无效安排", amount: -1, dueDate: day))],
            [.pairTransfer(a: id, b: l.entries[1].id, nature: .transfer)]
        ]
        for items in invalidSets {
            XCTAssertThrowsError(try ChangeSet(source: "问余白", reason: "核对", items: items).apply(to: &l))
            XCTAssertEqual(try LedgerCodec.encode(l), original)
        }
    }
    func testInvalidPlanOccurrenceAndEmptyCategoryRollback() throws {
        var l = ledger(); let plan = Plan(title: "订阅", amount: 4250, dueDate: day, frequency: .monthly)
        l.plans = [plan]; let before = try LedgerCodec.encode(l)
        let id = l.entries[0].id
        let cases: [[ChangeItem]] = [
            [.linkPlan(entry: id, plan: plan.id, occurrence: Dates.addDays(1, to: day))],
            [.setPurpose(entry: id, text: "午餐"), .setCategory(entry: id, category: " ")]
        ]
        for items in cases {
            XCTAssertThrowsError(try ChangeSet(source: "测试", reason: "日期与分类核对", items: items).apply(to: &l))
            XCTAssertEqual(try LedgerCodec.encode(l), before)
        }
    }
    func testStaleItemsSkipAndReportAlongsideValidItems() throws {
        var l = ledger(); let id = l.entries[0].id
        l.entries[1].deletedAt = day
        let skipped = try apply([.setPurpose(entry: UUID(), text: "午餐"), .setCategory(entry: l.entries[1].id, category: "礼金赠与"), .setCategory(entry: id, category: "餐饮")], to: &l)
        XCTAssertEqual(skipped.count, 2); XCTAssertTrue(skipped.allSatisfy { $0.hasPrefix("已跳过：") })
        XCTAssertEqual(l.entries[0].category, "餐饮")
    }
    func testHistoryRestoresAppliedSetAndPendingProposal() throws {
        var l = ledger(); let change = ChangeSet(source: "问余白", reason: "午餐用途", items: [.setPurpose(entry: l.entries[0].id, text: "午餐")])
        l.pendingChanges = [change]
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("yubai-apply-history-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = LedgerRepository(directory: root); try repo.save(l); let before = l
        try change.apply(to: &l); l.pendingChanges.removeAll { $0.id == change.id }; try repo.save(l, reason: "确认整理")
        XCTAssertEqual(try repo.recover(XCTUnwrap(repo.recoveries().first)), before)
    }
    func testEveryChangeItemAndCardActionRoundTrips() throws {
        var l = ledger(); let a = l.entries[0].id; let b = l.entries[1].id
        let plan = Plan(title: "订阅", amount: 100, dueDate: day)
        let rent = Rent(monthlyTotal: 300000, personalShare: 150000, startDate: day, nextDueDate: day)
        let area = ProfileArea(title: "外卖")
        let items: [ChangeItem] = [.setCategory(entry: a, category: "餐饮"), .setNature(entry: b, nature: .income, otherAccount: nil), .setPurpose(entry: a, text: "午餐"),
            .pairTransfer(a: a, b: b, nature: .transfer), .linkRefund(refund: b, original: a), .linkPlan(entry: a, plan: plan.id, occurrence: day), .linkRent(entry: b, rent: rent.id, period: day),
            .markDuplicate(entry: a, of: b), .addPlan(plan), .endPlan(plan.id, day), .addRent(rent), .addEntry(EntryDraft(date: day, amount: 100, accountID: l.accounts[0].id, title: "书")),
            .profile(.upsertArea(area, stance: .restrain)), .profile(.removeArea(area.id)), .profile(.addPrinciple("借阅")), .profile(.editPrinciple(old: "借阅", new: "购买")), .profile(.removePrinciple("购买")), .profile(.setFloorAmount(nil))]
        let change = ChangeSet(source: "测试", reason: "序列化", items: items); l.pendingChanges = [change]
        XCTAssertEqual(change.preview(in: l).count, items.count); XCTAssertTrue(change.preview(in: l).allSatisfy { !$0.isEmpty })
        let actions: [CardAction] = [.openEvidence, .confirmChangeSet(change.id), .reconcileAccount(l.accounts[0].id), .answerQuestion, .openWish(UUID())]
        l.cards = actions.enumerated().map { i, action in ButlerCard(kind: .followUp, title: "确认", body: "提案", action: action, dedupeKey: "test-\(i)") }
        XCTAssertEqual(try LedgerCodec.decode(LedgerCodec.encode(l)), l)
    }
}
