import XCTest
@testable import YubaiCore

final class CategoryReguessTests: XCTestCase {
    private let now = Dates.parse("2026-11-05 12:00")!
    private func seed() -> Ledger {
        var ledger = Ledger()
        ledger.updatedAt = now
        ledger.accounts = [Account(name: "测试卡", balance: 100_000, at: now)]
        return ledger
    }
    private func row(_ ledger: Ledger, _ title: String = "理发店", category: String = Classification.pendingCategory, nature: Nature = .expense, reason: String = "没分类") -> Entry {
        var entry = Entry(date: now, amount: 1000, nature: nature, accountID: ledger.accounts[0].id, title: title, category: category)
        entry.classificationReason = reason
        return entry
    }

    func testGroupsPendingAndRecordedAutomaticOtherByTargetPath() {
        var ledger = seed()
        ledger.entries = [row(ledger), row(ledger, "造型", category: "其他支出", reason: "导入整理：根据账单用途与关联证据整理"),
                          row(ledger, "差旅报销", category: "其他收入", nature: .income, reason: "导入整理：自动分类"), row(ledger, "啤酒")]
        ledger.entries[1].userEdited = true // ImportOrganizer sets this too.
        let proposals = CategoryReguess.proposals(in: ledger)
        XCTAssertEqual(proposals.map(\.target.path), ["美容个护/理发", "报销", "购物/烟酒"])
        XCTAssertEqual(proposals.map(\.count), [2, 1, 1])
        XCTAssertEqual(proposals[0].entryIDs, Array(ledger.entries.prefix(2)).map(\.id))
        XCTAssertEqual(proposals[0].id, "美容个护/理发")
    }

    func testExplicitOtherMissingReasonAndKnownCategoriesAreIneligible() throws {
        var ledger = seed()
        ledger.entries = [row(ledger, category: "其他支出", reason: "手动选择"), row(ledger, category: "其他支出", reason: ""),
                          row(ledger, category: "其他支出", reason: "用户批量纠正"), row(ledger, category: "其他支出", reason: "问余白：用户确认"),
                          row(ledger, category: "购物", reason: "导入整理：自动分类"),
                          row(ledger, "差旅报销", category: "其他收入", nature: .income, reason: "手动选择")]
        XCTAssertTrue(CategoryReguess.proposals(in: ledger).isEmpty)
        let before = ledger
        let result = try CategoryReguess.apply([], in: &ledger)
        XCTAssertEqual(result.count, 0); XCTAssertEqual(ledger, before)
    }

    func testManualReviewProtectsOtherEvenIfMemoryIsLaterReplaced() throws {
        var ledger = seed()
        ledger.entries = [row(ledger, category: "其他支出", reason: "导入整理：自动分类")]
        var edited = ledger.entries[0]
        edited.note = "用户已检查"
        try ManualBookkeeping.edit(edited, in: &ledger)
        XCTAssertEqual(ledger.classificationMemory["理发店"], "其他支出")
        XCTAssertEqual(ledger.entries[0].classificationReason, "手动选择")
        ledger.classificationMemory["理发店"] = "美容个护/理发"
        XCTAssertTrue(CategoryReguess.proposals(in: ledger).isEmpty)
    }

    func testLegacyExplicitOtherMemoryStillPrecedesKeywords() {
        var ledger = seed()
        ledger.entries = [row(ledger, category: "其他支出", reason: "导入整理：自动分类")]
        ledger.classificationMemory["理发店"] = "其他支出"
        XCTAssertTrue(CategoryReguess.proposals(in: ledger).isEmpty)
    }

    func testManualChangeToOtherClearsAutomaticReasonAndLegacyPendingStaysPending() throws {
        var ledger = seed()
        ledger.entries = [row(ledger, category: "购物", reason: "导入整理：自动分类"), row(ledger, "造型", category: "其他支出")]
        var edited = ledger.entries[0]; edited.category = "其他支出"
        try ManualBookkeeping.edit(edited, in: &ledger)
        XCTAssertEqual(ledger.entries[0].classificationReason, "手动选择")
        var pending = ledger.entries[1]; pending.note = "尚待整理"
        try ManualBookkeeping.edit(pending, in: &ledger)
        XCTAssertTrue(Classification.isPending(ledger.entries[1]))
        XCTAssertEqual(CategoryReguess.proposals(in: ledger).flatMap(\.entryIDs), [pending.id])
    }

    func testDeletedMergedTransfersRefundsAndOtherSpecialNaturesAreIneligible() {
        var ledger = seed()
        var deleted = row(ledger); deleted.deletedAt = now
        var merged = row(ledger); merged.mergedIntoID = UUID()
        ledger.entries = [deleted, merged] + [Nature.transfer, .refund, .repayment, .unknownOut, .unknownIn, .investBuy, .investSell].map { row(ledger, nature: $0) }
        XCTAssertTrue(CategoryReguess.proposals(in: ledger).isEmpty)
    }

    func testLocalMemoryPrecedesKeywordsAndFollowsAliases() throws {
        var ledger = seed()
        ledger.entries = [row(ledger)]
        ledger.classificationMemory["理发店"] = "交通/打车"
        try CategoryModel.rename("交通", to: "出行服务", in: &ledger)
        XCTAssertEqual(CategoryReguess.proposals(in: ledger).first?.target.path, "出行服务/打车")
        let memory = ledger.classificationMemory
        try CategoryReguess.apply(CategoryReguess.proposals(in: ledger), in: &ledger)
        XCTAssertEqual(ledger.entries[0].category, "出行服务"); XCTAssertEqual(ledger.entries[0].subcategory, "打车")
        XCTAssertEqual(ledger.classificationMemory, memory)
    }

    func testUserSelectedSmallItemAndExplicitNoSmallItemArePreserved() throws {
        var ledger = seed()
        var selected = row(ledger); selected.subcategory = "用户小项"; selected.subcategoryUserEdited = true
        var noSmall = row(ledger, "造型"); noSmall.subcategoryUserEdited = true
        ledger.entries = [selected, noSmall]
        let proposals = CategoryReguess.proposals(in: ledger)
        XCTAssertEqual(proposals.map(\.target.path), ["美容个护"])
        XCTAssertEqual(proposals.flatMap(\.entryIDs), [noSmall.id])
        let result = try CategoryReguess.apply(proposals, in: &ledger)
        XCTAssertEqual(result.count, 1); XCTAssertEqual(ledger.entries[0], selected)
        XCTAssertEqual(ledger.entries[1].category, "美容个护")
        XCTAssertNil(ledger.entries[1].subcategory); XCTAssertTrue(ledger.entries[1].subcategoryUserEdited)
    }

    func testApplyAndUndoRoundTripWithRefundLinkageAndNoMemoryWrites() throws {
        var ledger = seed()
        let expense = row(ledger)
        var refund = row(ledger, "退理发费", nature: .refund); refund.relatedEntryID = expense.id
        ledger.entries = [expense, row(ledger, "啤酒"), refund]
        let before = ledger
        let changes = try CategoryReguess.apply(CategoryReguess.proposals(in: ledger), in: &ledger)
        XCTAssertEqual(changes.source, "本机重新归类"); XCTAssertEqual(changes.count, 2)
        XCTAssertEqual(ledger.entries.map(\.category), ["美容个护", "购物", "美容个护"])
        XCTAssertEqual(ledger.entries.map(\.subcategory), ["理发", "烟酒", "理发"])
        XCTAssertEqual(ledger.entries[2].relatedEntryID, expense.id)
        XCTAssertEqual(ledger.entries.map(\.amount), before.entries.map(\.amount))
        XCTAssertEqual(ledger.entries.map(\.nature), before.entries.map(\.nature))
        XCTAssertEqual(ledger.classificationMemory, before.classificationMemory)
        XCTAssertTrue(CategoryReguess.proposals(in: ledger).isEmpty)
        changes.undo(in: &ledger)
        XCTAssertEqual(ledger, before)
    }

    func testLinkedRefundsKeepExplicitSmallItemsAndDeletedRefundsUntouched() throws {
        var ledger = seed()
        let expense = row(ledger)
        var refund = row(ledger, nature: .refund)
        refund.relatedEntryID = expense.id; refund.subcategoryUserEdited = true; refund.subcategory = "旧小项"
        var deletedRefund = refund; deletedRefund.id = UUID(); deletedRefund.deletedAt = now
        ledger.entries = [expense, refund, deletedRefund]
        let before = ledger
        let changes = try CategoryReguess.apply(CategoryReguess.proposals(in: ledger), in: &ledger)
        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(ledger.entries[1].subcategory, "旧小项"); XCTAssertTrue(ledger.entries[1].subcategoryUserEdited)
        XCTAssertEqual(ledger.entries[2], deletedRefund)
        XCTAssertEqual(ledger.entries[1].relatedEntryID, expense.id)
        changes.undo(in: &ledger); XCTAssertEqual(ledger, before)
    }

    func testSelectedProposalGroupsApplyOnceAndCanBeUndoneTogether() throws {
        var ledger = seed()
        ledger.entries = [row(ledger), row(ledger, "造型"), row(ledger, "啤酒")]
        let before = ledger
        let proposals = CategoryReguess.proposals(in: ledger)
        let changes = try CategoryReguess.apply([proposals[0], proposals[0]], in: &ledger)
        XCTAssertEqual(changes.count, 2)
        XCTAssertEqual(ledger.entries[2], before.entries[2])
        changes.undo(in: &ledger); XCTAssertEqual(ledger, before)
    }

    func testApplySkipsStaleRowsEvidenceAndHiddenTargets() throws {
        var ledger = seed()
        ledger.entries = [row(ledger), row(ledger, "造型"), row(ledger, "啤酒")]
        let proposals = CategoryReguess.proposals(in: ledger)
        ledger.entries[0].note = "预览之后改过"
        ledger.classificationMemory["造型"] = "交通/打车"
        try CategoryModel.setHidden(true, category: "购物", in: &ledger)
        let before = ledger
        let changes = try CategoryReguess.apply(proposals, in: &ledger)
        XCTAssertEqual(changes.count, 0); XCTAssertEqual(ledger, before)
        var otherLedger = before; otherLedger.id = UUID()
        XCTAssertEqual(try CategoryReguess.apply(proposals, in: &otherLedger).count, 0)
    }

    func testUndoPreservesLaterEditsAndUnrelatedCheckpoints() throws {
        var ledger = seed()
        ledger.entries = [row(ledger), row(ledger, "造型")]
        let original = ledger.entries[1]
        let changes = try CategoryReguess.apply(CategoryReguess.proposals(in: ledger), in: &ledger)
        ledger.entries[0].note = "更新后的备注"
        let later = ledger.entries[0]
        ledger.entries.append(row(ledger, "后来新增的记录"))
        ledger.classificationMemory["其他商户"] = "购物/日用百货"
        changes.undo(in: &ledger)
        XCTAssertEqual(ledger.entries[0], later); XCTAssertEqual(ledger.entries[1], original)
        XCTAssertEqual(ledger.entries.count, 3); XCTAssertEqual(ledger.classificationMemory["其他商户"], "购物/日用百货")
    }
}
