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
    private func register(_ question: ImportQuestion, in ledger: inout Ledger) {
        var batch = ImportBatch(filename: "合成.csv", importedCount: question.entryIDs.count, duplicateCount: 0, skippedCount: 0)
        batch.organization = ImportOrganization(changeSet: ChangeSet(source: "导入整理", reason: "合成", items: []), questions: [question], skipped: [])
        ledger.imports.append(batch)
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
    func testSelectedSubsetAndPurposeOnlyChangeCheckedEntries() throws {
        var (ledger, question) = fixture()
        ledger.entries[1].purpose = "原有用途"
        let before = ledger
        let selected = ledger.entries[0].id
        let change = try XCTUnwrap(UnsortedGroups.changeSet(groupID: "out:商店", question: question, use: .expense,
                                                          category: "餐饮", entryIDs: [selected], purpose: "  给爸妈\n", in: ledger))
        XCTAssertEqual(change.items.count, 3)
        XCTAssertEqual(Set(change.items.flatMap(\.entryIDs)), [selected])
        XCTAssertTrue(change.items.contains(.setPurpose(entry: selected, text: "给爸妈")))
        XCTAssertEqual(change.reason, "1 笔记为 餐饮")
        XCTAssertTrue(try change.apply(to: &ledger).isEmpty)
        XCTAssertEqual(ledger.entries[0].nature, .expense)
        XCTAssertEqual(ledger.entries[0].category, "餐饮")
        XCTAssertEqual(ledger.entries[0].purpose, "给爸妈")
        XCTAssertEqual(Array(ledger.entries.dropFirst()), Array(before.entries.dropFirst()), "Unchecked rows must remain byte-for-byte equivalent")
        XCTAssertEqual(ledger.entries.map(\.amount), before.entries.map(\.amount))
        XCTAssertEqual(ledger.entries.map(\.date), before.entries.map(\.date))
        XCTAssertEqual(UnsortedGroups.entries(for: question, in: ledger).count, 3)
        let remaining = try XCTUnwrap(UnsortedGroups.groups(for: question, in: ledger).first { $0.id == "out:商店" })
        XCTAssertEqual(remaining.entries.map(\.id), [before.entries[1].id])
        XCTAssertEqual(UnsortedGroups.groups(for: question, in: before)[0].entries.count, 2, "Undo restores the entire group")
    }

    func testSelectingOtherExpenseConfirmsLegacyPendingCategoryOnlyForCheckedRow() throws {
        var (ledger, question) = fixture()
        for index in 0..<2 {
            ledger.entries[index].nature = .expense
            ledger.entries[index].category = "其他支出"
            ledger.entries[index].classificationReason = "没分类"
        }
        let before = ledger
        let selected = ledger.entries[0].id
        let change = try XCTUnwrap(UnsortedGroups.changeSet(groupID: "out:商店", question: question, use: .expense,
                                                          category: "其他支出", entryIDs: [selected], in: ledger))
        XCTAssertEqual(change.items, [.setCategory(entry: selected, category: "其他支出")])
        XCTAssertTrue(try change.apply(to: &ledger).isEmpty)
        XCTAssertEqual(ledger.entries[0].category, "其他支出")
        XCTAssertFalse(Classification.isPending(ledger.entries[0]))
        XCTAssertTrue(ledger.entries[0].userEdited)
        XCTAssertEqual(Array(ledger.entries.dropFirst()), Array(before.entries.dropFirst()))
        XCTAssertEqual(UnsortedGroups.entries(for: question, in: ledger).count, 3)
        XCTAssertEqual(UnsortedGroups.groups(for: question, in: ledger).first { $0.id == "out:商店" }?.entries.map(\.id), [before.entries[1].id])
    }

    func testPurposeAppliesToAllSelectedRowsAndBlankInputPreservesExistingPurposes() throws {
        let (base, question) = fixture()
        for purpose: String? in [nil, "", " \n ", "生活费"] {
            var ledger = base
            ledger.entries[0].purpose = "午餐原用途"; ledger.entries[1].purpose = "晚餐原用途"
            let change = try XCTUnwrap(UnsortedGroups.changeSet(groupID: "out:商店", question: question, use: .expense,
                                                              category: "其他支出", purpose: purpose, in: ledger))
            let purposeItems = change.items.filter { if case .setPurpose = $0 { true } else { false } }
            XCTAssertEqual(purposeItems.count, purpose == "生活费" ? 2 : 0)
            XCTAssertTrue(try change.apply(to: &ledger).isEmpty)
            XCTAssertEqual(ledger.entries.prefix(2).map(\.purpose), purpose == "生活费" ? ["生活费", "生活费"] : ["午餐原用途", "晚餐原用途"])
            XCTAssertTrue(ledger.entries.prefix(2).allSatisfy { $0.category == "其他支出" })
        }
        XCTAssertNil(UnsortedGroups.changeSet(groupID: "out:商店", question: question, use: .expense,
                                              category: "餐饮", purpose: String(repeating: "长", count: 4001), in: base))
    }

    func testSubsetConfirmationIntersectsLiveGroupAndRejectsEmptyOrForeignSelection() throws {
        var (ledger, question) = fixture()
        register(question, in: &ledger)
        var cache = UnsortedGroupsCache()
        let snapshot = try XCTUnwrap(cache.snapshot(for: question.id, revision: 0, in: ledger))
        let originalIDs = Set(try XCTUnwrap(snapshot.groupsByID["out:商店"]).entries.map(\.id))
        ledger.entries[0].category = "交通" // Classified elsewhere after selection.
        let before = ledger
        let requested = originalIDs.union([ledger.entries[2].id, UUID()])
        let change = try XCTUnwrap(cache.changeSet(groupID: "out:商店", questionID: question.id, use: .expense,
                                                  category: "餐饮", entryIDs: requested, purpose: "晚餐", revision: 1, in: ledger))
        XCTAssertEqual(Set(change.items.flatMap(\.entryIDs)), [ledger.entries[1].id])
        XCTAssertTrue(try change.apply(to: &ledger).isEmpty)
        XCTAssertEqual(ledger.entries[0], before.entries[0])
        XCTAssertEqual(Array(ledger.entries.suffix(2)), Array(before.entries.suffix(2)))
        XCTAssertEqual(ledger.entries[1].purpose, "晚餐")
        for ids: Set<UUID> in [[], [before.entries[0].id], [before.entries[2].id, UUID()]] {
            XCTAssertNil(UnsortedGroups.changeSet(groupID: "out:商店", question: question, use: .expense,
                                                  category: "餐饮", entryIDs: ids, purpose: "不应写入", in: before))
            XCTAssertNil(cache.changeSet(groupID: "out:商店", questionID: question.id, use: .expense,
                                        category: "餐饮", entryIDs: ids, purpose: "不应写入", revision: 1, in: before))
        }
    }

    func testNonDailyChoicesRejectCategoryAndOnlyApplyNatureAndPurposeToSelectedRows() throws {
        var (base, question) = fixture()
        let other = Account(name: "另一个账户", at: now); base.accounts.append(other)
        for group in UnsortedGroups.groups(for: question, in: base) {
            for use in UnsortedGroups.uses(for: group, in: base).filter({ !$0.needsCategory }) {
                let account = use == .transfer ? other.id : nil
                XCTAssertFalse(UnsortedGroups.canApply(to: group, use: use, category: "餐饮", otherAccount: account, in: base))
                XCTAssertNil(UnsortedGroups.changeSet(groupID: group.id, question: question, use: use,
                                                      category: "餐饮", otherAccount: account, in: base))
                var ledger = base
                let selected = group.entries[0].id
                let change = try XCTUnwrap(UnsortedGroups.changeSet(groupID: group.id, question: question, use: use,
                                                                  otherAccount: account, entryIDs: [selected], purpose: "本金", in: ledger))
                XCTAssertEqual(change.items.count, 2)
                XCTAssertFalse(change.items.contains { if case .setCategory = $0 { true } else { false } })
                XCTAssertTrue(try change.apply(to: &ledger).isEmpty)
                let changed = try XCTUnwrap(ledger.entries.first { $0.id == selected })
                XCTAssertEqual(changed.nature, use.nature); XCTAssertEqual(changed.purpose, "本金")
                XCTAssertEqual(ledger.entries.filter { $0.id != selected }, base.entries.filter { $0.id != selected })
                XCTAssertEqual(ledger.entries.map { $0.delta(for: base.accounts[0].id) }, base.entries.map { $0.delta(for: base.accounts[0].id) })
            }
        }
    }

    func testSourceFieldsFollowImportedRowAndPreserveBankColumnsAndMultilineNotes() throws {
        var ledger = Ledger(); ledger.accounts = [Account(name: "合成银行卡", at: now)]
        let csv = """
        合成银行流水
        记账日期,交易金额,联机余额,交易摘要,对手信息,附言
        2026-10-09 21:16,-1500.00,6320.18,转账,合成对方 6222****1234,"房租,10月
        第二行"
        2026-10-22 09:00,-200.00,6120.18,转账,合成对方 6222****1234,生活费
        """
        let data = Data(csv.utf8)
        let preview = try BillImporter.preview(data: data, filename: "合成.csv", accountID: ledger.accounts[0].id, ledger: ledger)
        _ = try BillImporter.commit(preview, data: data, to: &ledger)
        XCTAssertEqual(ledger.entries.map(\.sourceRow), [3, 4])
        XCTAssertEqual(ledger.entries[0].attachmentID, ledger.attachments[0].id)
        let fields = try UnsortedEntryPresentation.sourceFields(data: data, filename: "合成.csv", sourceRow: XCTUnwrap(ledger.entries[0].sourceRow))
        XCTAssertEqual(fields.map(\.key), ["记账日期", "交易金额", "联机余额", "交易摘要", "对手信息", "附言"])
        XCTAssertEqual(fields.map(\.value), ["2026-10-09 21:16", "-1500.00", "6320.18", "转账", "合成对方 6222****1234", "房租,10月\n第二行"])
        let second = try UnsortedEntryPresentation.sourceFields(data: data, filename: "合成.csv", sourceRow: XCTUnwrap(ledger.entries[1].sourceRow))
        XCTAssertEqual(second.last?.value, "生活费", "sourceRow counts parsed rows, not physical lines")
        XCTAssertTrue(try UnsortedEntryPresentation.sourceFields(data: data, filename: "合成.csv", sourceRow: 0).isEmpty)
        XCTAssertTrue(try UnsortedEntryPresentation.sourceFields(data: data, filename: "合成.csv", sourceRow: 99).isEmpty)
    }

    func testSourceFieldsSupportMappedTSVHeadersAndSummaryFallbackFacts() throws {
        let data = Data("日戳\t数值\t内容\t\n2026-10-09\t-25.00\t晚餐\t原始备注\n".utf8)
        let fields = try UnsortedEntryPresentation.sourceFields(data: data, filename: "合成.TSV", sourceRow: 2)
        XCTAssertEqual(fields.map(\.key), ["日戳", "数值", "内容", "4"])
        XCTAssertEqual(fields.map(\.value), ["2026-10-09", "-25.00", "晚餐", "原始备注"])
        let (ledger, _) = fixture()
        var entry = ledger.entries[0]; entry.note = "附言：生活费\n原账单状态：成功"
        XCTAssertEqual(UnsortedEntryPresentation.summary(entry), "午餐 · 商店 · 附言：生活费")
        entry.title = "只有商户"; entry.note = ""
        XCTAssertEqual(UnsortedEntryPresentation.summary(entry), "只有商户")
        let fallback = UnsortedEntryPresentation.fallbackFields(entry, account: "合成银行卡", hideAmounts: false)
        XCTAssertEqual(fallback.map(\.key), ["时间", "金额", "账户", "明细", "备注"])
        XCTAssertEqual(fallback.map(\.value), [Dates.text(entry.date, time: true), "-¥12.00", "合成银行卡", "只有商户", ""])
        XCTAssertEqual(UnsortedEntryPresentation.fallbackFields(entry, account: "合成银行卡", hideAmounts: true)[1].value, "••••")
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

    func testCacheSharesOneProjectionAcrossCountSearchAndGroupLookup() throws {
        var (ledger, question) = fixture()
        question.entryIDs.append(question.entryIDs[0]) // Old duplicate coverage must not duplicate rows.
        register(question, in: &ledger)
        var cache = UnsortedGroupsCache()
        let snapshot = try XCTUnwrap(cache.snapshot(for: question.id, revision: 1, in: ledger))
        XCTAssertEqual(snapshot.entryCount, 4)
        XCTAssertEqual(snapshot.batchID, ledger.imports[0].id)
        XCTAssertEqual(snapshot.groups, UnsortedGroups.groups(for: question, in: ledger))
        XCTAssertEqual(snapshot.groupsByID["out:商店"], snapshot.groups[0])
        XCTAssertEqual(snapshot.matching(" 商店\n").map(\.id), ["out:商店", "in:商店"])
        XCTAssertEqual(snapshot.matching(" \n"), snapshot.groups)
        XCTAssertTrue(snapshot.matching("不存在").isEmpty)
        for _ in 0..<100 {
            XCTAssertTrue(cache.snapshot(for: question.id, revision: 1, in: ledger) === snapshot)
        }
        var other = question; other.id = UUID(); other.entryIDs = [question.entryIDs[3]]
        ledger.imports[0].organization?.questions.append(other)
        let second = try XCTUnwrap(cache.snapshot(for: other.id, revision: 2, in: ledger))
        XCTAssertEqual(second.entryCount, 1)
        XCTAssertEqual(second.groups.map(\.id), ["out:咖啡店"])
        XCTAssertEqual(cache.snapshot(for: question.id, revision: 2, in: ledger)?.entryCount, 4)
    }

    func testCacheInvalidatesForClassificationDeletionAndUndoWithUnchangedTimestamp() throws {
        var (ledger, question) = fixture()
        register(question, in: &ledger)
        let before = ledger
        var cache = UnsortedGroupsCache()
        let original = try XCTUnwrap(cache.snapshot(for: question.id, revision: 0, in: ledger))
        ledger.entries[0].category = "餐饮" // A background checkpoint while the group is open.
        let changed = try XCTUnwrap(cache.snapshot(for: question.id, revision: 1, in: ledger))
        XCTAssertFalse(original === changed)
        XCTAssertEqual(changed.entryCount, 3)
        let change = try XCTUnwrap(cache.changeSet(groupID: "out:商店", questionID: question.id, use: .expense,
                                                  category: "餐饮", revision: 1, in: ledger))
        XCTAssertEqual(Set(change.items.flatMap(\.entryIDs)), [ledger.entries[1].id], "Confirmation must exclude a row sorted elsewhere")
        ledger.entries[1].deletedAt = now
        let removed = try XCTUnwrap(cache.snapshot(for: question.id, revision: 2, in: ledger))
        XCTAssertEqual(removed.entryCount, 2)
        XCTAssertNil(removed.groupsByID["out:商店"], "The destination should dismiss when its live group disappears")
        XCTAssertNil(cache.changeSet(groupID: "out:商店", questionID: question.id, use: .expense,
                                    category: "餐饮", revision: 2, in: ledger))
        XCTAssertEqual(ledger.updatedAt, before.updatedAt)
        ledger = before // Undo must rebuild even if updatedAt goes backwards or stays unchanged.
        let restored = try XCTUnwrap(cache.snapshot(for: question.id, revision: 3, in: ledger))
        XCTAssertEqual(restored.groups, original.groups)
        XCTAssertFalse(restored === original)
        XCTAssertFalse(restored === removed)
    }

    func testFallbackCardVisibilityUsesTheSameRevisionCacheAndStillDefersDuringOrganization() throws {
        var (ledger, question) = fixture()
        register(question, in: &ledger)
        var card = ButlerCard(kind: .answerQuestion, title: "问题", body: "", dedupeKey: "fallback")
        card.importQuestion = question; ledger.cards = [card]
        var cache = UnsortedGroupsCache()
        let snapshot = try XCTUnwrap(cache.snapshot(for: question.id, revision: 1, in: ledger))
        let cached = ButlerCards.visible(ledger, fallbackEntryCount: {
            let value = cache.snapshot(for: $0.id, revision: 1, in: ledger)
            XCTAssertTrue(value === snapshot)
            return value?.entryCount ?? 0
        })
        XCTAssertEqual(cached, ButlerCards.visible(ledger))
        XCTAssertEqual(cached.map(\.id), [card.id])
        XCTAssertTrue(ButlerCards.queued(ledger, organizingBatchIDs: [ledger.imports[0].id], fallbackEntryCount: { _ in
            XCTFail("Run-local deferral must happen before reading the fallback count"); return 4
        }).isEmpty)
        for i in ledger.entries.indices { ledger.entries[i].category = "餐饮" }
        XCTAssertTrue(ButlerCards.visible(ledger, fallbackEntryCount: {
            cache.snapshot(for: $0.id, revision: 2, in: ledger)?.entryCount ?? 0
        }).isEmpty)
        XCTAssertEqual(snapshot.entryCount, 4, "An outgoing destination can retain its immutable transition frame")
    }

    func testCacheRefreshesCoverageLinksAndQuestionOrLedgerReplacement() throws {
        var (ledger, question) = fixture()
        register(question, in: &ledger)
        var cache = UnsortedGroupsCache()
        XCTAssertEqual(cache.snapshot(for: question.id, revision: 0, in: ledger)?.entryCount, 4)
        let added = Entry(date: now, amount: 99, nature: .unknownIn, accountID: ledger.accounts[0].id, title: "New Party · 来款")
        ledger.entries.append(added)
        ledger.imports[0].organization?.questions[0].entryIDs = [added.id, ledger.entries[0].id]
        let updated = try XCTUnwrap(cache.snapshot(for: question.id, revision: 1, in: ledger))
        XCTAssertEqual(updated.entryCount, 2)
        XCTAssertEqual(updated.matching("new PARTY").map(\.id), ["in:New Party"])
        ledger.entries[1].relatedEntryID = ledger.entries[0].id
        XCTAssertEqual(cache.snapshot(for: question.id, revision: 2, in: ledger)?.entryCount, 1)
        ledger.entries[1].deletedAt = now
        XCTAssertEqual(cache.snapshot(for: question.id, revision: 3, in: ledger)?.entryCount, 2, "Deleted references must stop suppressing rows")
        ledger.imports[0].undoneAt = now
        XCTAssertNil(cache.snapshot(for: question.id, revision: 4, in: ledger))
        ledger.imports[0].undoneAt = nil
        ledger.imports[0].organization?.questions.removeAll()
        XCTAssertNil(cache.snapshot(for: question.id, revision: 5, in: ledger))
        ledger.id = UUID(); register(question, in: &ledger)
        XCTAssertEqual(cache.snapshot(for: question.id, revision: 5, in: ledger)?.entryCount, 3, "A different ledger cannot reuse the old revision's index")
    }

    func testLightweightValidationAgreesWithChangesAndRejectsInvalidSelections() throws {
        var (ledger, question) = fixture()
        let source = ledger.accounts[0].id
        let other = Account(name: "合成钱包", at: now)
        var archived = Account(name: "已归档", at: now); archived.archived = true
        ledger.accounts += [other, archived]
        let groups = UnsortedGroups.groups(for: question, in: ledger)
        for group in groups {
            XCTAssertFalse(UnsortedGroups.canApply(to: group, use: nil, in: ledger))
            for use in UnsortedUse.allCases {
                for category: String? in [nil, "餐饮", "工资奖金", "不存在"] {
                    for account: UUID? in [nil, source, other.id, archived.id, UUID()] {
                        let valid = UnsortedGroups.canApply(to: group, use: use, category: category, otherAccount: account, in: ledger)
                        let change = UnsortedGroups.changeSet(groupID: group.id, question: question, use: use,
                                                             category: category, otherAccount: account, in: ledger)
                        XCTAssertEqual(valid, change != nil, "\(group.id) / \(use)")
                    }
                }
            }
        }
        let expense = try XCTUnwrap(groups.first { $0.id == "out:商店" })
        var mixedAccounts = ledger; mixedAccounts.entries[1].accountID = other.id
        let mixedGroup = try XCTUnwrap(UnsortedGroups.groups(for: question, in: mixedAccounts).first { $0.id == expense.id })
        XCTAssertTrue(UnsortedGroups.otherAccounts(for: mixedGroup, in: mixedAccounts).isEmpty)
        XCTAssertFalse(UnsortedGroups.uses(for: mixedGroup, in: mixedAccounts).contains(.transfer))
        XCTAssertFalse(UnsortedGroups.canApply(to: mixedGroup, use: .transfer, otherAccount: other.id, in: mixedAccounts))
        ledger.categories[try XCTUnwrap(ledger.categories.firstIndex { $0.name == "餐饮" })].hidden = true
        XCTAssertFalse(UnsortedGroups.canApply(to: expense, use: .expense, category: "餐饮", in: ledger))
        register(question, in: &ledger)
        var cache = UnsortedGroupsCache()
        XCTAssertNotNil(cache.changeSet(groupID: expense.id, questionID: question.id, use: .transfer,
                                       otherAccount: other.id, revision: 1, in: ledger))
        ledger.accounts[1].archived = true
        XCTAssertNil(cache.changeSet(groupID: expense.id, questionID: question.id, use: .transfer,
                                    otherAccount: other.id, revision: 2, in: ledger))
        ledger.imports[0].organization?.questions[0].groupsByParty = false
        XCTAssertNil(cache.snapshot(for: question.id, revision: 3, in: ledger))
    }

    func test4200RowProjectionAndRepeatedSelectionsStayWithinHalfASecond() throws {
        var (ledger, question) = fixture()
        let accountID = ledger.accounts[0].id
        ledger.entries = (0..<4200).map { index in
            Entry(date: now, amount: Int64(index + 1), nature: .unknownOut,
                  accountID: accountID, title: "合成大组 · 明细\(index)")
        }
        question.entryIDs = ledger.entries.map(\.id)
        register(question, in: &ledger)
        var cache = UnsortedGroupsCache()
        let start = ProcessInfo.processInfo.systemUptime
        let snapshot = try XCTUnwrap(cache.snapshot(for: question.id, revision: 1, in: ledger))
        let group = try XCTUnwrap(snapshot.groupsByID["out:合成大组"])
        XCTAssertEqual(snapshot.entryCount, 4200)
        XCTAssertEqual(group.total, Int64(4200 * 4201 / 2))
        XCTAssertEqual(UnsortedGroups.entries(for: question, in: ledger).count, 4200)
        for _ in 0..<1000 {
            XCTAssertTrue(cache.snapshot(for: question.id, revision: 1, in: ledger) === snapshot)
            XCTAssertTrue(UnsortedGroups.canApply(to: group, use: .expense, category: "餐饮", in: ledger))
            XCTAssertFalse(UnsortedGroups.canApply(to: group, use: .expense, in: ledger))
        }
        let change = try XCTUnwrap(cache.changeSet(groupID: group.id, questionID: question.id, use: .expense,
                                                  category: "餐饮", revision: 1, in: ledger))
        XCTAssertEqual(change.items.count, 8400)
        XCTAssertEqual(Set(change.items.flatMap(\.entryIDs)), Set(question.entryIDs))
        let elapsed = ProcessInfo.processInfo.systemUptime - start
        print("4200-row projection + 1000 cached selections + ChangeSet: \(elapsed)s")
        XCTAssertLessThan(elapsed, 0.5)
    }
}
