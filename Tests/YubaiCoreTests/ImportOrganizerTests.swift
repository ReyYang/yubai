import XCTest
@testable import YubaiCore

private actor ImportScript: ChatTransport {
    let reply: @Sendable (ChatRequest) throws -> JSONValue
    var requests: [ChatRequest] = []
    init(_ reply: @escaping @Sendable (ChatRequest) throws -> JSONValue) { self.reply = reply }
    func send(_ request: ChatRequest) async throws -> ChatMessage {
        requests.append(request)
        return ChatMessage(role: .assistant, content: try reply(request).jsonText())
    }
    func count() -> Int { requests.count }
}

private struct ImportEval: Decodable {
    struct Row: Decodable { var key: String; var date: String; var amount: Int64; var nature: Nature; var account: Int; var title: String }
    struct Series: Decodable { var keys: [String]; var frequency: String; var title: String }
    var accounts: [String]; var rows: [Row]; var expectedPairs: [[String]]; var expectedSeries: [Series]
    static func load() throws -> ImportEval {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "import-eval", withExtension: "json", subdirectory: "Fixtures"))
        return try JSONDecoder().decode(ImportEval.self, from: Data(contentsOf: url))
    }
    func imported() throws -> (before: Ledger, imported: Ledger, batch: ImportBatch, ids: [String: UUID]) {
        var ledger = Ledger(); ledger.accounts = accounts.map { Account(name: $0) }
        // Evidence from an earlier import must also be restored on batch undo.
        let old = Set(["move1-in", "sub1", "sub2"])
        var ids: [String: UUID] = [:]
        for row in rows where old.contains(row.key) {
            let e = Entry(date: Dates.parse(row.date)!, amount: row.amount, nature: row.nature,
                          accountID: ledger.accounts[row.account].id, title: row.title, category: "待整理")
            ledger.entries.append(e); ids[row.key] = e.id
        }
        let before = ledger
        let lines = rows.filter { !old.contains($0.key) }.map { row in
            [row.date, row.nature.inflow ? "收入" : "支出", Money.input(row.amount), row.title,
             accounts[row.account], row.nature.label, row.key].map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }.joined(separator: ",")
        }
        let bytes = Data((["时间,收支,金额,名称,账户,性质,交易单号"] + lines).joined(separator: "\n").utf8)
        let mappings = Dictionary(uniqueKeysWithValues: ledger.accounts.map { ($0.name, $0.id) })
        let preview = try BillImporter.preview(data: bytes, filename: "eval.csv", accountID: ledger.accounts[0].id,
                                               ledger: ledger, accountMappings: mappings)
        XCTAssertEqual(preview.selectedEntries.count, rows.count - old.count)
        let batch = try BillImporter.commit(preview, data: bytes, to: &ledger)
        for e in ledger.entries where e.batchID == batch.id { ids[e.externalID] = e.id }
        return (before, ledger, batch, ids)
    }
    func script(ids: [String: UUID]) -> JSONValue {
        let pairs: [JSONValue] = expectedPairs.map { pair in
            .object(["kind": .string("pair_transfer"), "entry": .string(ids[pair[0]]!.uuidString),
                     "other_entry": .string(ids[pair[1]]!.uuidString), "nature": .string("transfer")])
        }
        let series: [JSONValue] = expectedSeries.map { sample in
            .object(["entry_ids": .array(sample.keys.map { .string(ids[$0]!.uuidString) }),
                     "frequency": .string(sample.frequency), "title": .string(sample.title)])
        }
        return .object(["rows": .array([]), "items": .array(pairs), "series": .array(series)])
    }
}

final class ImportOrganizerTests: XCTestCase {
    func testFreeAnswerAndMemoryPersistTogetherAndBatchUndoRemovesOnlyItsMemories() throws {
        let fixture = try ImportEval.load(); let data = try fixture.imported()
        var ledger = data.imported
        let entry = try XCTUnwrap(ledger.entries.first { $0.batchID == data.batch.id })
        let question = ImportQuestion(text: "这笔钱是什么用途？", entryIDs: [entry.id], options: [])
        let organization = ImportOrganization(changeSet: ChangeSet(source: "导入整理", reason: "补充用途",
            items: [.setPurpose(entry: entry.id, text: "待明确")]), questions: [question], skipped: [])
        let before = ledger
        try organization.changeSet.apply(to: &ledger)
        organization.finish(batchID: data.batch.id, before: before, in: &ledger)
        let unanswered = ledger
        XCTAssertThrowsError(try question.describe("两行\n用途", batchID: data.batch.id, in: &ledger))
        XCTAssertEqual(ledger, unanswered)
        var samePurpose = unanswered
        let sameIndex = try XCTUnwrap(samePurpose.entries.firstIndex { $0.id == entry.id })
        samePurpose.entries[sameIndex].purpose = "已经写过的用途"
        XCTAssertNoThrow(try question.describe("已经写过的用途", batchID: data.batch.id, in: &samePurpose))
        XCTAssertTrue(samePurpose.imports[0].organization?.questions.isEmpty == true)
        try question.describe("和张三合租，房租我出六成", batchID: data.batch.id, in: &ledger)
        let memory = try XCTUnwrap(ledger.memories.first)
        XCTAssertEqual(memory.source, .importAnswer); XCTAssertEqual(memory.kind, .life)
        XCTAssertEqual(memory.evidence, [entry.id]); XCTAssertFalse(memory.text.contains("张三"))
        XCTAssertEqual(ledger.entries.first { $0.id == entry.id }?.purpose, "和张三合租，房租我出六成")
        XCTAssertTrue(ledger.imports[0].organization?.questions.isEmpty == true)
        XCTAssertEqual(ledger.imports[0].undo?.memoryIDs, [memory.id])
        let answered = ledger
        XCTAssertThrowsError(try question.describe("再次回答", batchID: data.batch.id, in: &ledger))
        XCTAssertEqual(ledger, answered)
        let unrelated = MemoryNote(text: "另一条聊天记忆", kind: .plan, source: .chat)
        ledger.memories.append(unrelated)
        ledger = try LedgerCodec.decode(LedgerCodec.encode(ledger))
        BillImporter.undo(batchID: data.batch.id, in: &ledger)
        var expected = data.before; expected.memories = [unrelated]
        XCTAssertEqual(ledger, expected)
    }
    func testLegacyImportUndoWithoutMemoryIDsDecodes() throws {
        let old = ImportUndo(updatedAt: Date())
        let data = try JSONEncoder().encode(old)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("memoryIDs"))
        XCTAssertNil(try JSONDecoder().decode(ImportUndo.self, from: data).memoryIDs)
    }
    func testFixtureProposalsFinancialInvariantsAndByteIdenticalBatchUndo() async throws {
        let fixture = try ImportEval.load(); let data = try fixture.imported()
        let scripted = fixture.script(ids: data.ids)
        let result = try await ImportOrganizer(transport: ImportScript { request in
            let text = request.messages.last?.content ?? ""
            XCTAssertFalse(text.contains("externalID")); XCTAssertFalse(text.contains("fingerprint"))
            XCTAssertFalse(text.contains("attachment")); XCTAssertFalse(text.contains("move1-out"))
            return scripted
        }).organize(ledger: data.imported, entryIDs: data.imported.entries.filter { $0.batchID == data.batch.id }.map(\.id))
        XCTAssertEqual(result.pairCount, 2); XCTAssertEqual(result.recurringCount, 3)
        XCTAssertTrue(result.skipped.isEmpty, result.skipped.joined(separator: "\n"))
        let plans = result.changeSet.items.compactMap { item -> Plan? in if case .addPlan(let plan) = item { return plan }; return nil }
        let card = try XCTUnwrap(plans.first { $0.title == "信用卡账单" })
        XCTAssertEqual(card.amount, 120000); XCTAssertEqual(card.accountID, data.imported.accounts[0].id)
        XCTAssertEqual(card.dueDate, Dates.parse("2026-07-10"))
        var ledger = data.imported
        try result.changeSet.apply(to: &ledger)
        result.finish(batchID: data.batch.id, before: data.imported, in: &ledger)
        XCTAssertEqual(ledger.imports[0].needsOrganization, false)
        for (before, after) in zip(data.imported.entries, ledger.entries) {
            XCTAssertEqual(before.amount, after.amount); XCTAssertEqual(before.accountID, after.accountID); XCTAssertEqual(before.date, after.date)
        }
        // Exercise persistence of the undo delta, not only its in-memory value.
        ledger = try LedgerCodec.decode(LedgerCodec.encode(ledger))
        BillImporter.undo(batchID: data.batch.id, in: &ledger)
        XCTAssertEqual(try LedgerCodec.encode(ledger), try LedgerCodec.encode(data.before))
    }

    func testBatchingGroupingFiveQuestionLimitAndAnswerItems() async throws {
        var ledger = Ledger(); ledger.accounts = [Account(name: "卡")]
        ledger.entries = (0..<90).map { i in
            Entry(amount: 50000 + Int64(i % 6) * 100000, nature: .expense,
                  accountID: ledger.accounts[0].id, title: "待明确组\(i % 6)", category: "待整理")
        }
        let script = ImportScript { request in
            let input = try JSONValue.parse(request.messages.last!.content!)
            let questions: [JSONValue] = (input["batch"]?.arrayValue ?? []).map { row in
                let id = row["id"]!
                func option(_ title: String, nature: String) -> JSONValue {
                    .object(["title": .string(title), "items": .array([.object(["kind": .string("set_nature"), "entry": id, "nature": .string(nature)])])])
                }
                return .object(["text": .string("这笔钱是什么用途？"), "entry_ids": .array([id]),
                                "options": .array([option("日常消费", nature: "expense"), option("借给朋友", nature: "lend")])])
            }
            return .object(["rows": .array([]), "questions": .array(questions)])
        }
        let result = try await ImportOrganizer(transport: script).organize(ledger: ledger, entryIDs: ledger.entries.map(\.id))
        let count = await script.count(); XCTAssertEqual(count, 2)
        let requests = await script.requests
        XCTAssertEqual(Set(requests.compactMap(\.groupID)).count, 1)
        XCTAssertTrue(requests.allSatisfy { $0.groupID != nil && $0.groupTitle == "整理 90 笔导入记录" })
        XCTAssertEqual(result.questions.count, 5)
        XCTAssertTrue(result.questions.prefix(4).allSatisfy { $0.entryIDs.count == 15 })
        XCTAssertEqual(Set(result.questions.flatMap(\.entryIDs)), Set(ledger.entries.map(\.id)))
        try result.changeSet.apply(to: &ledger)
        XCTAssertTrue(ledger.entries.allSatisfy { $0.nature == .unknownOut }, "Overflow questions must also withhold uncertain nature")
        let question = try XCTUnwrap(result.questions.first)
        let answer = try XCTUnwrap(question.answer(0))
        XCTAssertEqual(Set(answer.items.flatMap(\.entryIDs)), Set(question.entryIDs))
        try answer.apply(to: &ledger)
        XCTAssertTrue(ledger.entries.filter { question.entryIDs.contains($0.id) }.allSatisfy { $0.nature == .expense })
        XCTAssertNil(question.answer(99))
    }

    func testLargeOrganizationIsOneChangeSetBeyondAssistantChatLimit() async throws {
        var ledger = Ledger(); ledger.accounts = [Account(name: "卡")]
        ledger.entries = (0..<81).map { Entry(amount: Int64($0 + 1), nature: .unknownOut, accountID: ledger.accounts[0].id, title: "午餐", category: "待整理") }
        let result = try await ImportOrganizer(transport: ImportScript { request in
            let payload = try JSONValue.parse(request.messages.last!.content!)
            let rows = (payload["batch"]?.arrayValue ?? []).map { row in
                JSONValue.object(["entry": row["id"]!, "category": .string("餐饮"), "nature": .string("expense"), "purpose": .string("午餐"), "confident": .bool(true)])
            }
            return .object(["rows": .array(rows)])
        }).organize(ledger: ledger, entryIDs: ledger.entries.map(\.id))
        XCTAssertEqual(result.changeSet.items.count, 243)
        XCTAssertNoThrow(try result.changeSet.apply(to: &ledger))
        XCTAssertTrue(ledger.entries.allSatisfy { $0.nature == .expense && $0.category == "餐饮" && $0.purpose == "午餐" })
    }

    func testQuestionPersistenceAndCategoryAliasesWhileInvalidItemsAreSkipped() async throws {
        var ledger = Ledger(); ledger.accounts = [Account(name: "卡")]; ledger.categoryAliases["吃饭"] = "餐饮"
        let bytes = Data("时间,收支,金额,名称\n2026-10-01,支出,500.00,不明\n2026-10-01,支出,25.00,午餐\n".utf8)
        let before = ledger
        let preview = try BillImporter.preview(data: bytes, filename: "bill.csv", accountID: ledger.accounts[0].id, ledger: ledger)
        let batch = try BillImporter.commit(preview, data: bytes, to: &ledger)
        let raw = ledger; let id = ledger.entries[0].id; let mealID = ledger.entries[1].id
        let script = ImportScript { _ in
            func item(_ nature: String) -> JSONValue { .object(["kind": .string("set_nature"), "entry": .string(id.uuidString), "nature": .string(nature)]) }
            return .object([
                "rows": .array([
                    .object(["entry": .string(id.uuidString), "nature": .string("expense"), "confident": .bool(true)]),
                    .object(["entry": .string(mealID.uuidString), "category": .string("吃饭"), "nature": .string("expense"), "purpose": .string("日常用餐"), "confident": .bool(true)])
                ]),
                "items": .array([.object(["kind": .string("set_nature"), "entry": .string(id.uuidString), "nature": .string("income"), "amount": .number(999)])]),
                "questions": .array([.object(["text": .string("这 500 是什么钱？"), "entry_ids": .strings([id.uuidString]),
                    "options": .array([.object(["title": .string("用餐"), "items": .array([item("expense")])]),
                                       .object(["title": .string("借出"), "items": .array([item("lend")])])])])])
            ])
        }
        let result = try await ImportOrganizer(transport: script).organize(ledger: ledger, entryIDs: [id, mealID])
        XCTAssertFalse(result.skipped.isEmpty)
        try result.changeSet.apply(to: &ledger); result.finish(batchID: batch.id, before: raw, in: &ledger)
        XCTAssertEqual(ledger.entries[1].category, "餐饮"); XCTAssertEqual(ledger.entries[0].nature, .unknownOut)
        XCTAssertEqual(ledger.entries[0].amount, 50000)
        ledger = try LedgerCodec.decode(LedgerCodec.encode(ledger))
        XCTAssertEqual(ledger.cards.first?.kind, .answerQuestion)
        let question = try XCTUnwrap(ledger.cards.first?.importQuestion)
        let answerBefore = ledger
        try XCTUnwrap(question.answer(0)).apply(to: &ledger)
        ImportOrganization.recordUndo(batchID: batch.id, before: answerBefore, in: &ledger)
        BillImporter.undo(batchID: batch.id, in: &ledger)
        XCTAssertEqual(try LedgerCodec.encode(ledger), try LedgerCodec.encode(before))
    }

    func testRefundRentDuplicateAndUnknownCategoryWithCompleteUndo() async throws {
        var ledger = Ledger(); ledger.accounts = [Account(name: "卡")]
        ledger.rents = [Rent(monthlyTotal: 10000, personalShare: 5000, startDate: Dates.parse("2026-09-01")!, nextDueDate: Dates.parse("2026-10-01")!)]
        let purchase = Entry(date: Dates.parse("2026-09-15")!, amount: 10000, accountID: ledger.accounts[0].id, title: "网购", category: "日用购物")
        let duplicate = Entry(date: Dates.parse("2026-09-16")!, amount: 3000, accountID: ledger.accounts[0].id, title: "午餐", category: "餐饮")
        ledger.entries = [purchase, duplicate]; let before = ledger
        let bytes = Data("时间,收支,金额,名称\n2026-09-20,收入,50.00,部分退款\n2026-09-20,收入,50.00,房租分摊\n2026-09-16,支出,30.00,午餐\n2026-09-20,支出,20.00,未知\n".utf8)
        var preview = try BillImporter.preview(data: bytes, filename: "bill.csv", accountID: ledger.accounts[0].id, ledger: ledger)
        for i in preview.rows.indices where preview.rows[i].status == .possibleDuplicate { preview.rows[i].included = true }
        let batch = try BillImporter.commit(preview, data: bytes, to: &ledger); let raw = ledger
        let rows = ledger.entries.filter { $0.batchID == batch.id }; let rentID = ledger.rents[0].id
        let result = try await ImportOrganizer(transport: ImportScript { request in
            let payload = try JSONValue.parse(request.messages.last!.content!)
            let evidence = payload["context"]?.arrayValue?.compactMap { $0["id"]?.stringValue } ?? []
            XCTAssertTrue(evidence.contains(purchase.id.uuidString), "A partial refund needs a larger original expense")
            return .object([
                "rows": .array([
                    .object(["entry": .string(rows[1].id.uuidString), "nature": .string("contribution"), "confident": .bool(true)]),
                    .object(["entry": .string(rows[3].id.uuidString), "category": .string("不存在的分类"), "confident": .bool(true)])
                ]),
                "items": .array([
                    .object(["kind": .string("link_refund"), "entry": .string(rows[0].id.uuidString), "other_entry": .string(purchase.id.uuidString)]),
                    .object(["kind": .string("link_rent"), "entry": .string(rows[1].id.uuidString), "rent": .string(rentID.uuidString), "date": .string("2026-09-01")]),
                    .object(["kind": .string("mark_duplicate"), "entry": .string(rows[2].id.uuidString), "other_entry": .string(duplicate.id.uuidString)])
                ])
            ])
        }).organize(ledger: ledger, entryIDs: rows.map(\.id))
        XCTAssertEqual(result.duplicateCount, 1); XCTAssertFalse(result.skipped.isEmpty)
        try result.changeSet.apply(to: &ledger); result.finish(batchID: batch.id, before: raw, in: &ledger)
        XCTAssertEqual(ledger.entries.first { $0.id == rows[0].id }?.relatedEntryID, purchase.id)
        XCTAssertEqual(ledger.entries.first { $0.id == rows[1].id }?.rentID, rentID)
        XCTAssertNotNil(ledger.entries.first { $0.id == rows[2].id }?.deletedAt)
        XCTAssertEqual(ledger.entries.first { $0.id == rows[3].id }?.category, "待整理")
        BillImporter.undo(batchID: batch.id, in: &ledger)
        XCTAssertEqual(try LedgerCodec.encode(ledger), try LedgerCodec.encode(before))
    }

    func testOfflineAndMalformedReplyLeavePendingImportUntouched() async throws {
        let data = try ImportEval.load().imported(); var ledger = data.imported
        let ids = ledger.entries.filter { $0.batchID == data.batch.id }.map(\.id)
        do {
            _ = try await ImportOrganizer(transport: ImportScript { _ in throw URLError(.notConnectedToInternet) }).organize(ledger: ledger, entryIDs: ids)
            XCTFail("Expected offline failure")
        } catch { }
        do {
            _ = try await ImportOrganizer(transport: ImportScript { _ in .object([:]) }).organize(ledger: ledger, entryIDs: ids)
            XCTFail("Expected malformed reply failure")
        } catch { }
        XCTAssertEqual(ledger.imports[0].needsOrganization, true)
        XCTAssertEqual(ledger, data.imported)
        BillImporter.undo(batchID: data.batch.id, in: &ledger)
        XCTAssertEqual(try LedgerCodec.encode(ledger), try LedgerCodec.encode(data.before))
    }

    func testLiveImportEvalOnlyWhenExplicitlyEnabled() async throws {
        guard ProcessInfo.processInfo.environment["YUBAI_LIVE_EVAL"] == "1", let client = DeepSeekClient.configured() else {
            throw XCTSkip("Set YUBAI_LIVE_EVAL=1 with a configured key; synthetic import only.")
        }
        let fixture = try ImportEval.load(); let data = try fixture.imported()
        let result = try await ImportOrganizer(transport: client).organize(ledger: data.imported, entryIDs: data.imported.entries.filter { $0.batchID == data.batch.id }.map(\.id))
        for pair in fixture.expectedPairs {
            XCTAssertTrue(result.changeSet.items.contains { item in
                if case let .pairTransfer(a, b, _) = item { return Set([a, b]) == Set(pair.compactMap { data.ids[$0] }) }; return false
            }, "Missing transfer pair: \(pair)")
        }
        for series in fixture.expectedSeries {
            let expected = Set(series.keys.compactMap { data.ids[$0] })
            let plans = result.changeSet.items.compactMap { item -> Plan? in
                if case let .addPlan(plan) = item, plan.frequency.rawValue == series.frequency { return plan }; return nil
            }
            XCTAssertTrue(plans.contains { plan in
                let linked = Set(result.changeSet.items.compactMap { item -> UUID? in
                    if case let .linkPlan(id, planID, _) = item, planID == plan.id { return id }; return nil
                })
                return expected.isSubset(of: linked)
            }, "Missing recurring evidence: \(series.title)")
        }
        XCTAssertLessThanOrEqual(result.questions.count, 5)
    }
}

final class CategoryMemoryTests: XCTestCase {
    func testKeysAndConfirmedCategoryEditsPersistButImportDoesNotTeach() throws {
        XCTAssertEqual(CategoryMemory.key("  美团-订单123，ABC!  "), "美团订单abc")
        XCTAssertEqual(CategoryMemory.key("123？！"), "")
        var ledger = AssistantFixtures.context().ledger
        let entry = ledger.entries[0]
        var change = ChangeSet(source: "导入整理", reason: "模型分类", items: [.setCategory(entry: entry.id, category: "日用购物")])
        try change.apply(to: &ledger); XCTAssertTrue(ledger.categoryMemory.isEmpty)
        change.source = "问余白"; change.items = [.setCategory(entry: entry.id, category: "餐饮")]
        try change.apply(to: &ledger)
        XCTAssertEqual(ledger.categoryMemory[CategoryMemory.key(entry.title)], "餐饮")
        change.source = "回答整理问题"; change.items = [.setCategory(entry: entry.id, category: "日用购物")]
        try change.apply(to: &ledger)
        XCTAssertEqual(ledger.categoryMemory[CategoryMemory.key(entry.title)], "日用购物")
        try LedgerOperations.bulkEdit([entry.id], category: "餐饮", nature: nil, in: &ledger)
        XCTAssertEqual(ledger.categoryMemory[CategoryMemory.key(entry.title)], "餐饮")
        XCTAssertEqual(try LedgerCodec.decode(LedgerCodec.encode(ledger)).categoryMemory, ledger.categoryMemory)
    }
    func testRememberedCategoryIsAcceptedBeforeModelAndConflictsAreIgnored() async throws {
        let ctx = AssistantFixtures.context(); var ledger = ctx.ledger
        ledger.entries = [Entry(date: ctx.now, amount: 2000, accountID: ledger.accounts[0].id, title: "美团123!", category: "其他支出")]
        ledger.categoryMemory[CategoryMemory.key("美团456")] = "餐饮"
        let entry = ledger.entries[0]
        let result = JSONValue.object(["rows": .array([.object(["entry": .string(entry.id.uuidString), "category": .string("日用购物"), "nature": .string("expense"), "confident": .bool(true)])]),
            "items": .array([.object(["kind": .string("set_category"), "entry": .string(entry.id.uuidString), "category": .string("娱乐旅行")])])])
        let script = ScriptedChatTransport([ChatMessage(role: .assistant, content: try result.jsonText()), ChatMessage(role: .assistant, content: "{}")])
        let organized = try await ImportOrganizer(transport: script).organize(ledger: ledger, entryIDs: [entry.id], now: ctx.now)
        let categories = organized.changeSet.items.compactMap { item -> String? in if case .setCategory(_, let category) = item { return category }; return nil }
        XCTAssertEqual(categories, ["餐饮"])
        let requests = await script.recorded()
        let input = try JSONValue.parse(try XCTUnwrap(requests[0].messages.last?.content))
        XCTAssertEqual(input["known_categories"], .array([.object(["title": .string(entry.title), "category": .string("餐饮")])]))
        XCTAssertEqual(input["batch"]?.arrayValue?.first?["category"], .string("餐饮"))
        XCTAssertTrue(requests[0].messages.first?.content?.contains("known_categories 是用户确认过的分类") == true)
        let memory = ledger.categoryMemory
        try organized.changeSet.apply(to: &ledger)
        XCTAssertEqual(ledger.entries[0].category, "餐饮"); XCTAssertEqual(ledger.categoryMemory, memory)
    }
    func testMissingRememberedCategoryFallsBackToModel() async throws {
        let ctx = AssistantFixtures.context(); var ledger = ctx.ledger
        ledger.entries = [Entry(date: ctx.now, amount: 100, accountID: ledger.accounts[0].id, title: "普通商户")]
        ledger.categoryMemory["普通商户"] = "已删除分类"
        let id = ledger.entries[0].id.uuidString
        let script = ScriptedChatTransport([ChatMessage(role: .assistant, content: try JSONValue.object(["rows": .array([.object(["entry": .string(id), "category": .string("餐饮"), "confident": .bool(true), "nature": .string("expense")])])]).jsonText()), ChatMessage(role: .assistant, content: "{}")])
        let result = try await ImportOrganizer(transport: script).organize(ledger: ledger, entryIDs: [ledger.entries[0].id], now: ctx.now)
        XCTAssertTrue(result.changeSet.items.contains(.setCategory(entry: ledger.entries[0].id, category: "餐饮")))
        let requests = await script.recorded()
        XCTAssertEqual(try JSONValue.parse(requests[0].messages.last!.content!)["known_categories"], .array([]))
    }
}
