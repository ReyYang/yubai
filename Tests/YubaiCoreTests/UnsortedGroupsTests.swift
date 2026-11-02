import XCTest
@testable import YubaiCore

final class UnsortedGroupsTests: XCTestCase {
    private let now = Dates.parse("2026-10-29")!
    private func fixture() -> (Ledger, ImportQuestion) {
        var ledger = Ledger()
        let account = Account(name: "合成银行卡", at: now)
        ledger.accounts = [account]
        ledger.entries = [
            Entry(date: now, amount: 1200, nature: .unknownOut, accountID: account.id, title: "商店 · 午餐"),
            Entry(date: Dates.addDays(-1, to: now), amount: 2300, nature: .unknownOut, accountID: account.id, title: "商店 · 晚餐"),
            Entry(date: now, amount: 4000, nature: .unknownIn, accountID: account.id, title: "商店 · 来款"),
            Entry(date: now, amount: 500, nature: .expense, accountID: account.id, title: "咖啡店")
        ]
        let question = ImportQuestion(text: "4 笔还没分类", entryIDs: ledger.entries.map(\.id), options: [], groupsByParty: true)
        return (ledger, question)
    }
    func testGroupsSplitDirectionsSortByCountAndSumCentsWithStableIDs() {
        let (ledger, question) = fixture()
        let groups = UnsortedGroups.groups(for: question, in: ledger)
        XCTAssertEqual(groups.map(\.id), ["out:商店", "in:商店", "out:咖啡店"])
        XCTAssertEqual(groups.map(\.total), [3500, 4000, 500])
        XCTAssertEqual(groups[0].entries.map(\.date), [now, Dates.addDays(-1, to: now)])
        var reversed = ledger; reversed.entries.reverse()
        XCTAssertEqual(UnsortedGroups.groups(for: question, in: reversed), groups)
        XCTAssertEqual(groups[0].entries[0].title, "商店 · 午餐")
    }
    func testLiveCoverageExcludesClassifiedDeletedLinkedSpecialAndUncoveredEntries() {
        var (ledger, question) = fixture()
        ledger.entries[0].category = "餐饮"
        ledger.entries[1].deletedAt = now
        ledger.entries[2].nature = .investSell
        ledger.entries[3].relatedEntryID = ledger.entries[2].id
        ledger.entries.append(Entry(date: now, amount: 100, accountID: ledger.accounts[0].id, title: "未覆盖"))
        XCTAssertTrue(UnsortedGroups.groups(for: question, in: ledger).isEmpty)
        question.entryIDs.append(ledger.entries.last!.id)
        XCTAssertEqual(UnsortedGroups.entries(for: question, in: ledger).count, 1)
    }
    func testOldFallbackDecodesWithoutMarkerButCannotApplyOldMassAnswers() throws {
        let (ledger, question) = fixture()
        let old = ImportQuestion(text: "其余这 4 笔是什么钱？", entryIDs: question.entryIDs, options: [
            ImportAnswer(title: "都是日常收支", items: [.setNature(entry: ledger.entries[0].id, nature: .expense, otherAccount: nil)]),
            ImportAnswer(title: "稍后写用途", items: [])
        ])
        let data = try JSONEncoder().encode(old)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("groupsByParty"))
        let restored = try JSONDecoder().decode(ImportQuestion.self, from: data)
        XCTAssertNil(restored.groupsByParty); XCTAssertTrue(restored.isFallback)
        XCTAssertNil(restored.answer(0, in: ledger))
        XCTAssertEqual(UnsortedGroups.groups(for: restored, in: ledger).count, 3)
        var ordinary = restored; ordinary.text = "这几笔是什么？"
        XCTAssertFalse(ordinary.isFallback)
    }
    func testFallbackMergeKeepsIdentityAndAllCoverageAfterCheckpointAndOverflow() {
        let (ledger, question) = fixture()
        var second = question; second.id = UUID(); second.entryIDs = Array(question.entryIDs.suffix(2))
        var first = question; first.entryIDs = Array(question.entryIDs.prefix(2))
        let merged = ImportOrganizer.group([first, second], ledger: ledger)
        XCTAssertEqual(merged.count, 1); XCTAssertEqual(merged[0].id, first.id)
        XCTAssertEqual(Set(merged[0].entryIDs), Set(question.entryIDs)); XCTAssertTrue(merged[0].options.isEmpty)
    }
    func testOrdinaryGroupRequiresSelectableMainCategoryThenOneChangeSetRemovesOnlyThatGroup() throws {
        var (ledger, question) = fixture()
        let groupID = "out:商店"
        XCTAssertNil(UnsortedGroups.changeSet(groupID: groupID, question: question, use: .expense, in: ledger))
        XCTAssertNil(UnsortedGroups.changeSet(groupID: groupID, question: question, use: .expense, category: "工资奖金", in: ledger))
        XCTAssertNil(UnsortedGroups.changeSet(groupID: groupID, question: question, use: .income, category: "工资奖金", in: ledger))
        let before = ledger
        let change = try XCTUnwrap(UnsortedGroups.changeSet(groupID: groupID, question: question, use: .expense, category: "餐饮", in: ledger))
        XCTAssertEqual(Set(change.items.flatMap(\.entryIDs)), Set(question.entryIDs.prefix(2)))
        XCTAssertTrue(try change.apply(to: &ledger).isEmpty)
        XCTAssertEqual(UnsortedGroups.groups(for: question, in: ledger).count, 2)
        XCTAssertEqual(UnsortedGroups.entries(for: question, in: ledger).count, 2)
        XCTAssertTrue(ledger.entries.prefix(2).allSatisfy { $0.nature == .expense && $0.category == "餐饮" && $0.userEdited })
        XCTAssertEqual(ledger.entries.map(\.amount), before.entries.map(\.amount))
        XCTAssertEqual(ledger.entries.map(\.date), before.entries.map(\.date))
        XCTAssertEqual(UnsortedGroups.entries(for: question, in: before).count, 4, "Store undo restores the original projection")
        XCTAssertNil(UnsortedGroups.changeSet(groupID: groupID, question: question, use: .expense, category: "餐饮", in: ledger))
    }
    func testEverySpecialUseAndIncomeApplyWithoutCategoryAndPreserveOriginalAccountDelta() throws {
        let (base, question) = fixture()
        for (groupID, uses) in [("out:商店", [UnsortedUse.investBuy, .repayment, .lend]), ("in:商店", [.investSell, .loanRecovery, .income])] {
            for use in uses {
                var ledger = base
                let change = try XCTUnwrap(UnsortedGroups.changeSet(groupID: groupID, question: question, use: use,
                                                                   category: use == .income ? "工资奖金" : nil, in: ledger))
                XCTAssertTrue(try change.apply(to: &ledger).isEmpty)
                XCTAssertFalse(UnsortedGroups.groups(for: question, in: ledger).contains { $0.id == groupID })
                XCTAssertEqual(ledger.entries.map { $0.delta(for: base.accounts[0].id) }, base.entries.map { $0.delta(for: base.accounts[0].id) })
            }
        }
    }
    func testTransferRequiresOtherActiveAccountForBothDirectionsAndPreservesIncomingLeg() throws {
        let (base, question) = fixture()
        let original = base.accounts[0].id
        XCTAssertFalse(UnsortedGroups.uses(for: UnsortedGroups.groups(for: question, in: base)[0], in: base).contains(.transfer))
        for groupID in ["out:商店", "in:商店"] {
            var ledger = base
            let other = Account(name: "合成钱包", at: now)
            ledger.accounts.append(other)
            var archived = Account(name: "已归档", at: now); archived.archived = true; ledger.accounts.append(archived)
            XCTAssertNil(UnsortedGroups.changeSet(groupID: groupID, question: question, use: .transfer, in: ledger))
            XCTAssertNil(UnsortedGroups.changeSet(groupID: groupID, question: question, use: .transfer, otherAccount: original, in: ledger))
            XCTAssertNil(UnsortedGroups.changeSet(groupID: groupID, question: question, use: .transfer, otherAccount: archived.id, in: ledger))
            let change = try XCTUnwrap(UnsortedGroups.changeSet(groupID: groupID, question: question, use: .transfer, otherAccount: other.id, in: ledger))
            XCTAssertTrue(try change.apply(to: &ledger).isEmpty)
            XCTAssertEqual(ledger.entries.map { $0.delta(for: original) }, base.entries.map { $0.delta(for: original) })
            for entry in ledger.entries where entry.nature == .transfer {
                XCTAssertEqual(entry.delta(for: original) + entry.delta(for: other.id), 0)
                XCTAssertEqual(entry.postingDate(for: original), base.entries.first { $0.id == entry.id }?.date)
            }
            XCTAssertFalse(UnsortedGroups.groups(for: question, in: ledger).contains { $0.id == groupID })
        }
    }
    func testQuestionPrioritySuppressesCoveredInflowsIncludingBeyondEvidenceCapAndZeroFallback() {
        var (ledger, question) = fixture()
        var batch = ImportBatch(filename: "合成.csv", importedCount: 4, duplicateCount: 0, skippedCount: 0)
        batch.organization = ImportOrganization(changeSet: ChangeSet(source: "导入整理", reason: "合成", items: []), questions: [question], skipped: [])
        ledger.imports = [batch]
        var card = ButlerCard(kind: .answerQuestion, title: "问题", body: "", evidence: [], dedupeKey: "question")
        card.importQuestion = question; card.priority = 5
        let covered = ledger.entries[2]
        ledger.cards = (0..<8).map { index in
            let entry = Entry(date: Dates.addDays(-5, to: now), amount: 100, nature: .unknownIn, accountID: ledger.accounts[0].id, title: "来款\(index)")
            ledger.entries.append(entry)
            return ButlerCard(kind: .unknownInflow, title: "进账", body: "", evidence: [entry.id], dedupeKey: "in:\(index)")
        }
        ledger.cards.insert(ButlerCard(kind: .unknownInflow, title: "重复进账", body: "", evidence: [covered.id], dedupeKey: "covered"), at: 0)
        ledger.cards.append(card)
        var specific = ButlerCard(kind: .answerQuestion, title: "具体问题", body: "", dedupeKey: "specific")
        specific.createdAt = Dates.addDays(-1, to: card.createdAt)
        specific.importQuestion = ImportQuestion(text: "这笔是什么？", entryIDs: [], options: [])
        ledger.cards.append(specific)
        XCTAssertEqual(ButlerCards.visible(ledger).prefix(2).map(\.id), [specific.id, card.id], "Specific questions precede the newer fallback")
        XCTAssertEqual(ButlerCards.queued(ledger).filter { $0.kind == .unknownInflow }.count, 8)
        XCTAssertFalse(ButlerCards.detect(ledger, now: now).contains { $0.evidence.contains(covered.id) })
        for i in ledger.entries.indices where question.entryIDs.contains(ledger.entries[i].id) { ledger.entries[i].category = "餐饮" }
        XCTAssertFalse(ButlerCards.visible(ledger).contains { $0.id == card.id })
        question.entryIDs = []
        XCTAssertTrue(UnsortedGroups.groups(for: question, in: ledger).isEmpty)
    }
    func testLargeLedgerGroupsAll4200RowsWithoutCoverageLimit() {
        var (ledger, question) = fixture()
        let accountID = ledger.accounts[0].id
        ledger.entries = (0..<4200).map { index -> Entry in
            let date = Dates.addDays(-(index % 300), to: now)
            let nature: Nature = index % 3 == 0 ? .unknownIn : .unknownOut
            return Entry(date: date, amount: Int64(index + 1), nature: nature,
                         accountID: accountID, title: "对方\(index % 100) · 明细\(index)")
        }
        question.entryIDs = ledger.entries.map(\.id)
        let groups = UnsortedGroups.groups(for: question, in: ledger)
        XCTAssertEqual(groups.count, 200)
        XCTAssertEqual(groups.reduce(0) { $0 + $1.entries.count }, 4200)
        XCTAssertEqual(groups.reduce(Int64(0)) { $0 + $1.total }, Int64(4200 * 4201 / 2))
    }
}
