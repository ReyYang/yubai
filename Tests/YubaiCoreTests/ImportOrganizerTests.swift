import XCTest
@testable import YubaiCore

private actor ImportScript: ChatTransport {
    let reply: @Sendable (ChatRequest) throws -> JSONValue
    let wrap: @Sendable (String) -> String
    var requests: [ChatRequest] = []
    init(wrap: @escaping @Sendable (String) -> String = { $0 }, _ reply: @escaping @Sendable (ChatRequest) throws -> JSONValue) {
        self.reply = reply; self.wrap = wrap
    }
    func send(_ request: ChatRequest) async throws -> ChatMessage {
        requests.append(request)
        return ChatMessage(role: .assistant, content: try wrap(reply(request).jsonText()))
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

/// In-memory persistence with the same compare-and-save contract as AppStore.
private actor ImportCheckpointStore {
    var ledger: Ledger
    let batchID: UUID
    var checkpoints = 0
    var editAfterCheckpoint: Int?
    var cancelAfterCheckpoint: Int?
    init(_ ledger: Ledger, batchID: UUID) { self.ledger = ledger; self.batchID = batchID }
    func snapshot() -> Ledger { ledger }
    func configure(edit: Int? = nil, cancel: Int? = nil) { editAfterCheckpoint = edit; cancelAfterCheckpoint = cancel }
    func check(_ snapshot: Ledger) throws {
        guard ledger == snapshot else { throw YubaiError.invalid(ImportOrganizer.ledgerChangedMessage) }
    }
    func save(_ result: ImportOrganization, ids: [UUID], before: Ledger) throws -> Ledger {
        try check(before)
        var next = ledger
        if !result.changeSet.items.isEmpty { _ = try result.changeSet.apply(to: &next) }
        result.finish(batchID: batchID, before: before, in: &next, entryIDs: ids)
        next.updatedAt = next.updatedAt.addingTimeInterval(1)
        try next.validate()
        // Exercise actual Codable round trips between every request.
        ledger = try LedgerCodec.decode(LedgerCodec.encode(next))
        checkpoints += 1
        let saved = ledger
        if checkpoints == editAfterCheckpoint { ledger.preferences.dailyLiving += 1 }
        if checkpoints == cancelAfterCheckpoint { withUnsafeCurrentTask { $0?.cancel() } }
        return saved
    }
    func undo() { BillImporter.undo(batchID: batchID, in: &ledger) }
}

private actor ResumableImportScript: ChatTransport {
    var batches: [[UUID]] = []
    var failAt: Int?
    var leaveUncertain = false
    init(failAt: Int? = nil, leaveUncertain: Bool = false) { self.failAt = failAt; self.leaveUncertain = leaveUncertain }
    func send(_ request: ChatRequest) async throws -> ChatMessage {
        if request.purpose == "导入短评" { return ChatMessage(role: .assistant, content: #"{"cards":[]}"#) }
        XCTAssertEqual(request.purpose, "导入整理")
        XCTAssertEqual(request.timeout, 180)
        XCTAssertEqual(request.maxTokens, 6000)
        XCTAssertEqual(request.thinking, false)
        let input = try JSONValue.parse(request.messages.last!.content!)
        let rows = input["batch"]!.arrayValue!
        XCTAssertLessThanOrEqual(rows.count, 30)
        XCTAssertGreaterThan(rows.count, 0)
        XCTAssertLessThanOrEqual(input["context"]!.arrayValue!.count, 60)
        batches.append(rows.compactMap { $0["id"]?.stringValue.flatMap(UUID.init(uuidString:)) })
        if batches.count == failAt { throw YubaiError.invalid("云端服务返回错误（HTTP 503）。本机计算结果已保留。") }
        let output: [JSONValue] = leaveUncertain ? [] : rows.map {
            .object(["entry": $0["id"]!, "category": .string("餐饮"), "nature": .string("expense"), "purpose": .string("午餐"), "confident": .bool(true)])
        }
        return ChatMessage(role: .assistant, content: try JSONValue.object(["rows": .array(output)]).jsonText())
    }
    func sentBatches() -> [[UUID]] { batches }
}

final class ImportOrganizerTests: XCTestCase {
    private func syntheticImport(count: Int = 200) throws -> (Ledger, Ledger, ImportBatch) {
        var ledger = Ledger(); ledger.accounts = [Account(name: "合成卡")]
        let before = ledger
        let rows = (0..<count).map { "2026-10-01,支出,10.00,合成用途\($0),合成\($0)" }
        let bytes = Data((["时间,收支,金额,名称,交易单号"] + rows).joined(separator: "\n").utf8)
        let preview = try BillImporter.preview(data: bytes, filename: "synthetic.csv", accountID: ledger.accounts[0].id, ledger: ledger)
        let batch = try BillImporter.commit(preview, data: bytes, to: &ledger)
        return (before, ledger, batch)
    }
    private func resume(_ store: ImportCheckpointStore, script: any ChatTransport, batchID: UUID) async throws {
        let snapshot = await store.snapshot()
        let organizer = ImportOrganizer { expected in
            try await store.check(expected)
            return script
        }
        _ = try await organizer.organize(ledger: snapshot, entryIDs: ImportOrganizer.pendingEntryIDs(in: snapshot, batchID: batchID)) { result, ids, before in
            try await store.save(result, ids: ids, before: before)
        }
    }
    func testThirdChunkFailurePersistsTwoChunksResumesOnlyRemainderAndUndoesEntireImport() async throws {
        let (before, imported, batch) = try syntheticImport()
        let store = ImportCheckpointStore(imported, batchID: batch.id)
        let failing = ResumableImportScript(failAt: 3)
        do { try await resume(store, script: failing, batchID: batch.id); XCTFail("third chunk should fail") } catch { }
        let partial = await store.snapshot()
        XCTAssertEqual(partial.entries.filter { $0.category == "餐饮" }.count, 60)
        XCTAssertEqual(partial.imports[0].organizedEntryIDs?.count, 60)
        XCTAssertEqual(partial.imports[0].needsOrganization, true)
        XCTAssertEqual(partial.imports[0].organization?.categoryCount, 60)
        XCTAssertEqual(PendingImportOrganization(in: partial).count, 140)
        XCTAssertEqual(ImportOrganizer.pendingEntryIDs(in: partial, batchID: batch.id).count, 140)
        let first = await failing.sentBatches()
        XCTAssertEqual(first.map(\.count), [30, 30, 30])
        let retry = ResumableImportScript()
        try await resume(store, script: retry, batchID: batch.id)
        let complete = await store.snapshot()
        let retried = await retry.sentBatches()
        XCTAssertEqual(retried.map(\.count), [30, 30, 30, 30, 20])
        XCTAssertTrue(Set(retried.flatMap { $0 }).isDisjoint(with: first.prefix(2).flatMap { $0 }))
        XCTAssertEqual(Set(retried.flatMap { $0 }), Set(ImportOrganizer.pendingEntryIDs(in: partial, batchID: batch.id)))
        XCTAssertEqual(complete.imports[0].needsOrganization, false)
        XCTAssertEqual(complete.imports[0].organizedEntryIDs?.count, 200)
        XCTAssertEqual(complete.imports[0].organization?.categoryCount, 200)
        XCTAssertTrue(complete.entries.allSatisfy { $0.category == "餐饮" })
        await store.undo()
        let undone = await store.snapshot()
        XCTAssertEqual(undone, before)
    }
    func testChunkContextPreservesTransfersPartialRefundsAndRecurringEvidenceWithUndo() async throws {
        var ledger = Ledger(); ledger.accounts = [Account(name: "合成卡"), Account(name: "合成钱包")]
        let transfer = Entry(date: Dates.parse("2026-03-01")!, amount: 90_000, nature: .unknownIn, accountID: ledger.accounts[1].id, title: "合成转账")
        let original = Entry(date: Dates.parse("2026-02-15")!, amount: 70_000, nature: .expense, accountID: ledger.accounts[0].id, title: "合成商城")
        let subscription = Entry(date: Dates.parse("2026-01-01")!, amount: 2_000, nature: .expense, accountID: ledger.accounts[0].id, title: "合成订阅")
        ledger.entries = [transfer, original, subscription]
        let before = ledger
        var rows = (0..<200).map { "2026-03-01,支出,1.00,合成用途\($0),商户消费,fill\($0)" }
        rows[0] = "2026-03-01,支出,900.00,合成转账,转账,move"
        rows[31] = "2026-02-01,支出,20.00,合成订阅,商户消费,sub2"
        rows[62] = "2026-03-01,支出,20.00,合成订阅,商户消费,sub3"
        rows[93] = "2026-03-01,收入,100.00,合成商城,退款,refund"
        let bytes = Data((["时间,收支,金额,名称,交易类型,交易单号"] + rows).joined(separator: "\n").utf8)
        let preview = try BillImporter.preview(data: bytes, filename: "synthetic-evidence.csv", accountID: ledger.accounts[0].id, ledger: ledger)
        let batch = try BillImporter.commit(preview, data: bytes, to: &ledger)
        let ids = Dictionary(uniqueKeysWithValues: ledger.entries.filter { $0.batchID == batch.id }.map { ($0.externalID, $0.id) })
        let move = ids["move"]!, sub2 = ids["sub2"]!, sub3 = ids["sub3"]!, refund = ids["refund"]!
        let script = ImportScript { request in
            if request.purpose == "导入短评" { return .object(["cards": .array([])]) }
            let payload = try JSONValue.parse(request.messages.last!.content!)
            let targets = Set(payload["batch"]!.arrayValue!.compactMap { $0["id"]?.stringValue })
            let context = Set(payload["context"]!.arrayValue!.compactMap { $0["id"]?.stringValue })
            var items: [JSONValue] = [], series: [JSONValue] = []
            if targets.contains(move.uuidString) {
                XCTAssertTrue(context.contains(transfer.id.uuidString))
                items.append(.object(["kind": .string("pair_transfer"), "entry": .string(move.uuidString), "other_entry": .string(transfer.id.uuidString), "nature": .string("transfer")]))
            }
            if targets.contains(sub3.uuidString) {
                XCTAssertTrue(context.contains(subscription.id.uuidString))
                XCTAssertTrue(context.contains(sub2.uuidString))
                series.append(.object(["entry_ids": .strings([subscription.id, sub2, sub3].map(\.uuidString)), "frequency": .string("monthly"), "title": .string("合成订阅")]))
            }
            if targets.contains(refund.uuidString) {
                XCTAssertTrue(context.contains(original.id.uuidString))
                items.append(.object(["kind": .string("link_refund"), "entry": .string(refund.uuidString), "other_entry": .string(original.id.uuidString)]))
            }
            return .object(["rows": .array([]), "items": .array(items), "series": .array(series)])
        }
        let store = ImportCheckpointStore(ledger, batchID: batch.id)
        try await resume(store, script: script, batchID: batch.id)
        let complete = await store.snapshot()
        XCTAssertEqual(complete.imports[0].needsOrganization, false)
        XCTAssertEqual(complete.imports[0].organization?.pairCount, 1)
        XCTAssertEqual(complete.imports[0].organization?.recurringCount, 1)
        XCTAssertEqual(complete.entries.first { $0.id == refund }?.relatedEntryID, original.id)
        XCTAssertEqual(complete.entries.first { $0.id == transfer.id }?.mergedIntoID, move)
        XCTAssertEqual(complete.entries.first { $0.id == move }?.nature, .transfer)
        XCTAssertEqual(complete.entries.first { $0.id == subscription.id }?.planID, complete.plans.first?.id)
        let requests = await script.requests
        XCTAssertEqual(requests.filter { $0.purpose == "导入整理" }.count, 7)
        await store.undo()
        let undone = await store.snapshot()
        XCTAssertEqual(undone, before)
    }
    func testUncertainRowsAreCheckpointedAndNotRequestedAgain() async throws {
        let (_, imported, batch) = try syntheticImport()
        let store = ImportCheckpointStore(imported, batchID: batch.id)
        do { try await resume(store, script: ResumableImportScript(failAt: 3, leaveUncertain: true), batchID: batch.id); XCTFail() } catch { }
        let partial = await store.snapshot()
        XCTAssertTrue(partial.entries.allSatisfy(Classification.isPending))
        XCTAssertEqual(ImportOrganizer.pendingEntryIDs(in: partial, batchID: batch.id).count, 140)
        let retry = ResumableImportScript(leaveUncertain: true)
        try await resume(store, script: retry, batchID: batch.id)
        let complete = await store.snapshot()
        XCTAssertEqual(complete.imports[0].needsOrganization, false)
        let requests = await retry.sentBatches()
        XCTAssertEqual(requests.count, 5)
    }
    func testCancellationBetweenChunksKeepsSavedResultsAndUndo() async throws {
        let (before, imported, batch) = try syntheticImport()
        let store = ImportCheckpointStore(imported, batchID: batch.id)
        await store.configure(cancel: 2)
        let script = ResumableImportScript()
        let task = Task { try await self.resume(store, script: script, batchID: batch.id) }
        do { try await task.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
        let batches = await script.sentBatches()
        XCTAssertEqual(batches.count, 2)
        let partial = await store.snapshot()
        XCTAssertEqual(partial.imports[0].needsOrganization, true)
        XCTAssertEqual(partial.imports[0].organizedEntryIDs?.count, 60)
        await store.undo()
        let undone = await store.snapshot()
        XCTAssertEqual(undone, before)
    }
    func testUserEditBetweenChunksStopsNextRequestButOwnWritesDoNot() async throws {
        let (_, imported, batch) = try syntheticImport()
        let store = ImportCheckpointStore(imported, batchID: batch.id)
        await store.configure(edit: 2)
        let script = ResumableImportScript()
        do { try await resume(store, script: script, batchID: batch.id); XCTFail() }
        catch { XCTAssertEqual(ImportOrganizer.failureMessage(error), ImportOrganizer.ledgerChangedMessage) }
        let batches = await script.sentBatches()
        XCTAssertEqual(batches.count, 2)
        let partial = await store.snapshot()
        XCTAssertEqual(partial.imports[0].organizedEntryIDs?.count, 60)
        XCTAssertEqual(partial.preferences.dailyLiving, imported.preferences.dailyLiving + 1)
    }
    func testMalformedJSONUsesTheOrganizerReasonAndDoesNotCheckpoint() async throws {
        struct Malformed: ChatTransport {
            func send(_ request: ChatRequest) async throws -> ChatMessage { ChatMessage(role: .assistant, content: "not JSON") }
        }
        let (_, ledger, batch) = try syntheticImport(count: 2)
        let store = ImportCheckpointStore(ledger, batchID: batch.id)
        do {
            _ = try await ImportOrganizer(transport: Malformed()).organize(ledger: ledger, entryIDs: ledger.entries.map(\.id)) { result, ids, before in
                try await store.save(result, ids: ids, before: before)
            }
            XCTFail()
        } catch {
            XCTAssertEqual(ImportOrganizer.failureMessage(error), "整理结果格式无效，记录已保存，稍后可以再整理。")
        }
        let after = await store.snapshot()
        XCTAssertEqual(after, ledger)
    }
    func testFencedJSONResponsesAreParsed() async throws {
        let (_, ledger, _) = try syntheticImport(count: 1)
        for fence in ["```json", "```"] {
            let script = ImportScript(wrap: { " \n\(fence)\n\($0)\n```\n " }) { _ in .object(["rows": .array([])]) }
            let result = try await ImportOrganizer(transport: script).organize(ledger: ledger, entryIDs: ledger.entries.map(\.id))
            XCTAssertEqual(result.questions.flatMap(\.entryIDs), ledger.entries.map(\.id))
        }
    }
    func testJSONWithSurroundingTextIsParsed() async throws {
        let (_, ledger, _) = try syntheticImport(count: 1)
        let script = ImportScript(wrap: { "整理结果如下：\n\($0)\n以上是整理结果。" }) { _ in .object(["rows": .array([])]) }
        let result = try await ImportOrganizer(transport: script).organize(ledger: ledger, entryIDs: ledger.entries.map(\.id))
        XCTAssertEqual(result.questions.flatMap(\.entryIDs), ledger.entries.map(\.id))
    }
    func testEveryChunkRequestsJSONObjectResponseFormat() async throws {
        let (_, ledger, _) = try syntheticImport(count: ImportOrganizer.chunkSize + 1)
        let script = ImportScript { request in
            XCTAssertEqual(request.responseFormat, .object(["type": .string("json_object")]))
            return .object(["rows": .array([])])
        }
        _ = try await ImportOrganizer(transport: script).organize(ledger: ledger, entryIDs: ledger.entries.map(\.id))
        let count = await script.count()
        XCTAssertEqual(count, 2)
    }
    func testLegacyRowQuestionsAreIgnoredAndAllPendingRowsGetFallback() async throws {
        var ledger = Ledger(); ledger.accounts = [Account(name: "卡")]
        ledger.entries = (0..<11).map {
            Entry(amount: 50_000 + Int64($0) * 100_000, nature: .expense, accountID: ledger.accounts[0].id, title: "待明确组\($0)")
        }
        let ids = ledger.entries.map(\.id)
        let script = ImportScript { request in
            if request.purpose == "导入短评" { return .object(["cards": .array([])]) }
            func question(_ id: UUID, valid: Bool = true) -> JSONValue {
                let options: [JSONValue] = ["expense", "lend"].prefix(valid ? 2 : 1).map { nature in
                    .object(["title": .string(nature == "expense" ? "日常消费" : "借给朋友"),
                             "items": .array([.object(["kind": .string("set_nature"), "entry": .string(id.uuidString), "nature": .string(nature)])])])
                }
                return .object(["text": .string("这笔钱是什么用途？"), "entry_ids": .strings([id.uuidString]), "options": .array(options)])
            }
            return .object([
                "rows": .array([
                    .object(["entry": .string(ids[6].uuidString), "confident": .bool(false)]),
                    .object(["entry": .string(ids[7].uuidString), "nature": .string("expense")]),
                    .object(["entry": .string(ids[10].uuidString), "category": .string("餐饮"), "nature": .string("expense"), "confident": .bool(true)])
                ]),
                "questions": .array(ids.prefix(6).map { question($0) } + [question(ids[9], valid: false)])
            ])
        }
        let result = try await ImportOrganizer(transport: script).organize(ledger: ledger, entryIDs: ids)
        try result.changeSet.apply(to: &ledger)
        XCTAssertEqual(ledger.entries[6].nature, .unknownOut)
        XCTAssertEqual(ledger.entries[7].nature, .unknownOut)
        XCTAssertEqual(ledger.entries[10].category, "餐饮")
        XCTAssertEqual(result.questions.count, 1)
        XCTAssertTrue(result.questions.allSatisfy(\.isFallback))
        XCTAssertEqual(Set(result.questions.flatMap(\.entryIDs)), Set(ledger.activeEntries.filter(Classification.isPending).map(\.id)))
        let fallback = try XCTUnwrap(result.questions.first(where: \.isFallback))
        XCTAssertTrue(Set(ids[6...9]).isSubset(of: Set(fallback.entryIDs)), "False/missing confidence, omitted rows and rejected questions must all remain reachable")
        XCTAssertTrue(fallback.options.isEmpty)
        XCTAssertNil(fallback.answer(0, in: ledger))
        XCTAssertEqual(Set(UnsortedGroups.groups(for: fallback, in: ledger).flatMap { $0.entries.map(\.id) }), Set(fallback.entryIDs))
    }
    func testFallbackExcludesLinkedClassifiedDeletedAndContextRows() async throws {
        let (_, imported, _) = try syntheticImport(count: 8)
        var ledger = imported
        ledger.accounts.append(Account(name: "钱包"))
        let date = ledger.entries[0].date
        ledger.plans = [Plan(title: "合成计划", amount: 1_000, dueDate: date)]
        ledger.rents = [Rent(monthlyTotal: 1_000, personalShare: 1_000, startDate: date, nextDueDate: date)]
        ledger.entries[1].nature = .transfer; ledger.entries[1].otherAccountID = ledger.accounts[1].id
        ledger.entries[2].planID = ledger.plans[0].id; ledger.entries[2].occurrence = date
        ledger.entries[3].rentID = ledger.rents[0].id; ledger.entries[3].rentPeriod = date
        ledger.entries[4].nature = .refund; ledger.entries[4].relatedEntryID = ledger.entries[5].id
        ledger.entries[5].category = "餐饮"
        ledger.entries[7].deletedAt = date
        try ledger.validate()
        let ids = ledger.entries.enumerated().filter { $0.offset != 6 }.map { $0.element.id }
        let script = ImportScript { _ in .object(["rows": .array([])]) }
        let result = try await ImportOrganizer(transport: script).organize(ledger: ledger, entryIDs: ids)
        XCTAssertEqual(result.questions.count, 1)
        XCTAssertEqual(result.questions.first?.entryIDs, [ledger.entries[0].id])
    }
    func testFallbacksMergeAcrossTwoCheckpointedChunksRegardlessOfPartyAmountOrDirection() async throws {
        let (before, imported, batch) = try syntheticImport(count: 2 * ImportOrganizer.chunkSize)
        var ledger = imported
        for i in ledger.entries.indices {
            ledger.entries[i].nature = i < ImportOrganizer.chunkSize ? .unknownOut : .unknownIn
            ledger.entries[i].title = "合成对方\(i)"
            ledger.entries[i].amount = 50_000 + Int64(i) * 100_000
        }
        let store = ImportCheckpointStore(ledger, batchID: batch.id)
        let script = ResumableImportScript(leaveUncertain: true)
        let result = try await ImportOrganizer(transport: script).organize(ledger: ledger, entryIDs: ledger.entries.map(\.id)) { result, ids, before in
            try await store.save(result, ids: ids, before: before)
        }
        let saved = await store.snapshot()
        let persisted = try XCTUnwrap(saved.imports[0].organization)
        let sent = await script.sentBatches()
        XCTAssertEqual(sent.count, 2)
        XCTAssertEqual(result.questions.count, 1)
        XCTAssertEqual(persisted.questions.count, 1)
        XCTAssertEqual(saved.cards.filter { $0.importQuestion != nil }.count, 1)
        let expected = Set(ledger.entries.map(\.id))
        XCTAssertEqual(Set(result.questions.flatMap(\.entryIDs)), expected)
        XCTAssertEqual(Set(persisted.questions.flatMap(\.entryIDs)), expected)
        let question = try XCTUnwrap(persisted.questions.first)
        XCTAssertTrue(question.isFallback)
        XCTAssertTrue(question.options.isEmpty)
        XCTAssertNil(question.answer(0, in: saved))
        let groups = UnsortedGroups.groups(for: question, in: saved)
        XCTAssertEqual(Set(groups.flatMap { $0.entries.map(\.id) }), expected)
        XCTAssertTrue(groups.contains { $0.inflow })
        XCTAssertTrue(groups.contains { !$0.inflow })
        await store.undo()
        let undone = await store.snapshot()
        XCTAssertEqual(undone, before)
    }
    func testCheckpointQuestionsStaySavedButHiddenForAllBatchesInTheRun() async throws {
        let (_, imported, batch) = try syntheticImport(count: 2 * ImportOrganizer.chunkSize)
        let store = ImportCheckpointStore(imported, batchID: batch.id)
        let script = ResumableImportScript(leaveUncertain: true)
        _ = try await ImportOrganizer(transport: script).organize(ledger: imported, entryIDs: imported.entries.map(\.id)) { result, ids, before in
            let saved = try await store.save(result, ids: ids, before: before)
            XCTAssertFalse(saved.imports[0].organization?.questions.isEmpty ?? true)
            XCTAssertFalse(saved.cards.filter { $0.importQuestion != nil }.isEmpty)
            XCTAssertTrue(ButlerCards.queued(saved, organizingBatchIDs: [batch.id]).filter { $0.importQuestion != nil }.isEmpty)
            XCTAssertTrue(ButlerCards.visible(saved, organizingBatchIDs: [batch.id]).filter { $0.importQuestion != nil }.isEmpty)
            return saved
        }
        let saved = await store.snapshot()
        XCTAssertEqual(saved.imports[0].needsOrganization, false)
        // A finished batch remains deferred while another batch in this run works.
        XCTAssertTrue(ButlerCards.visible(saved, organizingBatchIDs: [batch.id, UUID()]).isEmpty)
        XCTAssertEqual(ButlerCards.visible(saved).filter { $0.importQuestion != nil }.count, 1)
    }
    func testStoppedOrFailedRunAndRelaunchExposeCheckpointQuestionsWithoutResendingCompletedIDs() throws {
        let (_, imported, batch) = try syntheticImport(count: 2 * ImportOrganizer.chunkSize)
        var saved = imported
        let completed = Array(imported.entries.prefix(ImportOrganizer.chunkSize).map(\.id))
        let question = ImportQuestion(text: "这笔是什么用途？", entryIDs: completed, options: [])
        let checkpoint = ImportOrganization(changeSet: ChangeSet(source: "导入整理", reason: "合成检查点", items: []),
                                            questions: [question], skipped: [])
        checkpoint.finish(batchID: batch.id, before: imported, in: &saved, entryIDs: completed)
        XCTAssertTrue(ButlerCards.visible(saved, organizingBatchIDs: [batch.id]).isEmpty)
        let unchanged = saved
        // Stop/failure clear only the in-memory run set; no ledger rewrite is needed.
        XCTAssertEqual(ButlerCards.visible(saved).first?.importQuestion?.id, question.id)
        XCTAssertEqual(saved, unchanged)
        let restored = try JSONDecoder().decode(Ledger.self, from: JSONEncoder().encode(saved))
        XCTAssertEqual(ButlerCards.visible(restored).first?.importQuestion?.id, question.id)
        XCTAssertEqual(Set(ImportOrganizer.pendingEntryIDs(in: restored, batchID: batch.id)),
                       Set(imported.entries.dropFirst(ImportOrganizer.chunkSize).map(\.id)))
    }
    func testDeferredQuestionsDoNotConsumeWindowOrReleaseCoveredInflowReminders() throws {
        let (_, imported, batch) = try syntheticImport(count: 1)
        var saved = imported
        saved.entries[0].nature = .unknownIn
        let id = saved.entries[0].id
        let question = ImportQuestion(text: "这笔来款是什么？", entryIDs: [id], options: [])
        let checkpoint = ImportOrganization(changeSet: ChangeSet(source: "导入整理", reason: "合成", items: []), questions: [question], skipped: [])
        checkpoint.finish(batchID: batch.id, before: imported, in: &saved, entryIDs: [id])
        let covered = ButlerCard(kind: .unknownInflow, title: "重复进账", body: "", evidence: [id], dedupeKey: "covered")
        saved.cards.append(covered)
        let other = (0..<6).map { ButlerCard(kind: .staleBalance, title: "余额", body: "", dedupeKey: "balance:\($0)") }
        saved.cards += other
        var previousBatch = ImportBatch(filename: "先前.csv", importedCount: 0, duplicateCount: 0, skippedCount: 0)
        let previousQuestion = ImportQuestion(text: "先前的问题", entryIDs: [], options: [])
        previousBatch.organization = ImportOrganization(changeSet: ChangeSet(source: "导入整理", reason: "先前", items: []),
                                                        questions: [previousQuestion], skipped: [])
        saved.imports.append(previousBatch)
        var previousCard = ButlerCard(kind: .answerQuestion, title: "先前的问题", body: "", dedupeKey: "previous")
        previousCard.importQuestion = previousQuestion
        saved.cards.append(previousCard)
        let visible = ButlerCards.visible(saved, organizingBatchIDs: [batch.id])
        XCTAssertEqual(visible.count, 5)
        XCTAssertEqual(visible.first?.id, previousCard.id, "Questions outside this run keep their existing visibility")
        XCTAssertFalse(ButlerCards.queued(saved, organizingBatchIDs: [batch.id]).contains { $0.id == covered.id })
        XCTAssertFalse(ButlerCards.detect(saved, now: Date()).contains { $0.kind == .unknownInflow && $0.evidence.contains(id) })
    }
    func testOrganizationProgressUsesSameThousandsSeparatedCountsForCardAndSystem() {
        let progress = ImportOrganizationProgress(completed: 150, total: 4200)
        XCTAssertEqual(progress.countText, "150 / 4,200")
        XCTAssertEqual(progress.subtitle, "已整理 150 / 4,200")
        XCTAssertEqual(ImportOrganizationProgress(completed: 1200, total: 4200).countText, "1,200 / 4,200")
        XCTAssertEqual(ImportOrganizationProgress(completed: 4200, total: 4200).subtitle, "已整理 4,200 / 4,200")
        XCTAssertEqual(ImportOrganizationProgress(completed: 10, total: 0).countText, "0 / 0")
    }
    func testManualEditsStayExcludedEvenWithAnOldOrganizationReason() throws {
        let (_, imported, batch) = try syntheticImport(count: 2)
        var ledger = imported
        ledger.entries[0].userEdited = true
        // Editing an entry can preserve this earlier reason; it is not proof
        // that its current values were written by the organizer.
        ledger.entries[0].classificationReason = "导入整理：根据账单用途与关联证据整理"
        XCTAssertEqual(ImportOrganizer.pendingEntryIDs(in: ledger, batchID: batch.id), [ledger.entries[1].id])
    }
    func testLegacyImportBatchWithoutCoverageDecodes() throws {
        let (_, ledger, _) = try syntheticImport(count: 2)
        let restored = try LedgerCodec.decode(LedgerCodec.encode(ledger))
        XCTAssertNil(restored.imports[0].organizedEntryIDs)
        XCTAssertEqual(ImportOrganizer.pendingEntryIDs(in: restored, batchID: restored.imports[0].id).count, 2)
    }
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

    func testLegacyPartyQuestionsAreIgnoredWithoutResendingGroups() async throws {
        var ledger = Ledger(); ledger.accounts = [Account(name: "卡")]
        ledger.entries = (0..<90).map { i in
            Entry(amount: 50000 + Int64(i % 6) * 100000, nature: .expense,
                  accountID: ledger.accounts[0].id, title: "待明确组\(i % 6)", category: "待整理")
        }
        let script = ImportScript { request in
            let input = try JSONValue.parse(request.messages.last!.content!)
            let questions: [JSONValue] = (input["groups"]?.arrayValue ?? []).map { row in
                let id = row["id"]!
                func option(_ title: String, nature: String) -> JSONValue {
                    .object(["title": .string(title), "items": .array([.object(["kind": .string("set_nature"), "nature": .string(nature)])])])
                }
                return .object(["text": .string("这笔钱是什么用途？"), "group": id,
                                "options": .array([option("日常消费", nature: "expense"), option("借给朋友", nature: "lend")])])
            }
            return .object(["groups": .array([]), "questions": .array(questions)])
        }
        let result = try await ImportOrganizer(transport: script).organize(ledger: ledger, entryIDs: ledger.entries.map(\.id))
        let count = await script.count(); XCTAssertEqual(count, 1)
        let requests = await script.requests
        XCTAssertEqual(Set(requests.compactMap(\.groupID)).count, 1)
        XCTAssertTrue(requests.allSatisfy { $0.groupID != nil && $0.groupTitle == "整理 90 笔导入记录" })
        XCTAssertEqual(result.questions.count, 1)
        XCTAssertTrue(result.questions.allSatisfy(\.isFallback))
        XCTAssertEqual(Set(result.questions.flatMap(\.entryIDs)), Set(ledger.entries.map(\.id)))
        XCTAssertTrue(result.changeSet.items.isEmpty)
        XCTAssertTrue(ledger.entries.allSatisfy { $0.nature == .expense }, "Ignored questions cannot alter nature")
        XCTAssertTrue(result.questions[0].options.isEmpty)
        XCTAssertNil(result.questions[0].answer(0))
    }

    func testLargeOrganizationIsOneChangeSetBeyondAssistantChatLimit() async throws {
        var ledger = Ledger(); ledger.accounts = [Account(name: "卡")]
        ledger.entries = (0..<81).map { Entry(amount: Int64($0 + 1), nature: .unknownOut, accountID: ledger.accounts[0].id, title: "午餐", category: "待整理") }
        let result = try await ImportOrganizer(transport: ImportScript { request in
            let payload = try JSONValue.parse(request.messages.last!.content!)
            let rows = (payload["groups"]?.arrayValue ?? []).map { row in
                JSONValue.object(["group": row["id"]!, "category": .string("餐饮"), "nature": .string("expense"), "purpose": .string("午餐"), "confident": .bool(true)])
            }
            return .object(["groups": .array(rows)])
        }).organize(ledger: ledger, entryIDs: ledger.entries.map(\.id))
        XCTAssertEqual(result.changeSet.items.count, 243)
        XCTAssertNoThrow(try result.changeSet.apply(to: &ledger))
        XCTAssertTrue(ledger.entries.allSatisfy { $0.nature == .expense && $0.category == "餐饮" && $0.purpose == "午餐" })
    }

    func testIgnoredQuestionsPreserveConfidentNatureAliasesFallbackPersistenceAndUndo() async throws {
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
        XCTAssertEqual(ledger.entries[1].category, "餐饮"); XCTAssertEqual(ledger.entries[0].nature, .expense)
        XCTAssertEqual(ledger.entries[0].amount, 50000)
        ledger = try LedgerCodec.decode(LedgerCodec.encode(ledger))
        XCTAssertEqual(ledger.cards.first?.kind, .answerQuestion)
        let question = try XCTUnwrap(ledger.cards.first?.importQuestion)
        XCTAssertTrue(question.isFallback)
        XCTAssertEqual(question.entryIDs, [id])
        XCTAssertNil(question.answer(0))
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
        XCTAssertTrue(result.questions.allSatisfy(\.isFallback))
    }
}

extension ImportOrganizerTests {
    private func partyImport(counts: [Int], singleton: Bool = false) -> (Ledger, ImportBatch) {
        var ledger = Ledger(); ledger.accounts = [Account(name: "合成卡")]
        var batch = ImportBatch(filename: "合成分组.csv", importedCount: counts.reduce(0, +) + (singleton ? 1 : 0), duplicateCount: 0, skippedCount: 0)
        batch.needsOrganization = true; batch.undo = ImportUndo(updatedAt: ledger.updatedAt)
        ledger.imports = [batch]
        for (group, count) in counts.enumerated() {
            for day in 0..<count {
                var entry = Entry(date: Dates.addDays(day, to: Dates.parse("2026-01-01")!), amount: 588 + Int64(group) * 1000,
                    nature: .unknownOut, accountID: ledger.accounts[0].id, title: "合成对方\(group) · 快捷支付")
                entry.batchID = batch.id; ledger.entries.append(entry)
            }
        }
        if singleton {
            var entry = Entry(amount: 333, nature: .unknownOut, accountID: ledger.accounts[0].id, title: "单笔对方")
            entry.batchID = batch.id; ledger.entries.append(entry)
        }
        return (ledger, batch)
    }
    private func jsonReply(_ json: String) -> ChatMessage { ChatMessage(role: .assistant, content: json) }

    func testPersonPartyUsesOtherExpenseAndTransferPurpose() async throws {
        var (ledger, _) = partyImport(counts: [3])
        for i in ledger.entries.indices { ledger.entries[i].title = "李明 · 转账" }
        let script = ImportScript { request in
            XCTAssertEqual(request.purpose, "导入整理·按对方")
            let input = try JSONValue.parse(request.messages.last!.content!)
            let group = try XCTUnwrap(input["groups"]?.arrayValue?.first)
            XCTAssertEqual(group["party"], .string("李明"))
            XCTAssertTrue(input["categories"]!.arrayValue!.contains { $0["name"] == .string("其他支出") })
            return .object(["groups": .array([.object(["group": group["id"]!, "category": .string("其他支出"),
                "nature": .string("expense"), "purpose": .string("转给李明"), "confident": .bool(true)])])])
        }
        let result = try await ImportOrganizer(transport: script).organize(ledger: ledger, entryIDs: ledger.entries.map(\.id))
        _ = try result.changeSet.apply(to: &ledger)
        XCTAssertTrue(ledger.entries.allSatisfy { $0.category == "其他支出" && $0.nature == .expense && $0.purpose == "转给李明" })
        XCTAssertTrue(result.questions.isEmpty)
        for prompt in [ImportOrganizer.partySystemPrompt, ImportOrganizer.systemPrompt] {
            XCTAssertFalse(prompt.contains("questions")); XCTAssertFalse(prompt.contains("提问")); XCTAssertFalse(prompt.contains("问题"))
            XCTAssertTrue(prompt.contains("转给<对方>")); XCTAssertTrue(prompt.contains("来自<对方>"))
            XCTAssertTrue(prompt.contains("其他支出")); XCTAssertTrue(prompt.contains("其他收入"))
        }
    }
    func testLegacyQuestionsCannotSuppressConfidentIndividualIncome() async throws {
        var (ledger, _) = partyImport(counts: [1])
        ledger.entries[0].nature = .unknownIn; ledger.entries[0].title = "李明 · 来款"
        let id = ledger.entries[0].id
        let script = ImportScript { _ in .object([
            "rows": .array([.object(["entry": .string(id.uuidString), "category": .string("其他收入"),
                "nature": .string("income"), "purpose": .string("来自李明"), "confident": .bool(true)])]),
            "questions": .array([.object(["text": .string("旧模型的问题"), "entry_ids": .strings([id.uuidString]), "options": .array([])])])
        ]) }
        let result = try await ImportOrganizer(transport: script).organize(ledger: ledger, entryIDs: [id])
        _ = try result.changeSet.apply(to: &ledger)
        XCTAssertEqual(ledger.entries[0].category, "其他收入"); XCTAssertEqual(ledger.entries[0].nature, .income)
        XCTAssertEqual(ledger.entries[0].purpose, "来自李明"); XCTAssertTrue(result.questions.isEmpty)
    }
    func testUncertainSkippedAndOmittedGroupsStayOnFallbackWithoutIndividualRequestsOrResumeResends() async throws {
        let (ledger, batch) = partyImport(counts: [3, 3, 3])
        let store = ImportCheckpointStore(ledger, batchID: batch.id)
        let script = ScriptedChatTransport([jsonReply(#"{"groups":[{"group":"g0","skip":true,"category":"餐饮","nature":"expense","confident":true},{"group":"g1","confident":false,"nature":"transfer"}]}"#)])
        try await resume(store, script: script, batchID: batch.id)
        let requests = await script.recorded(), saved = await store.snapshot()
        XCTAssertEqual(requests.map(\.purpose), ["导入整理·按对方"])
        XCTAssertTrue(saved.entries.allSatisfy(Classification.isPending))
        XCTAssertEqual(saved.entries, ledger.entries)
        let fallback = try XCTUnwrap(saved.imports[0].organization?.questions.first)
        XCTAssertTrue(fallback.isFallback); XCTAssertTrue(fallback.options.isEmpty)
        XCTAssertEqual(Set(fallback.entryIDs), Set(ledger.entries.map(\.id)))
        XCTAssertEqual(Set(UnsortedGroups.groups(for: fallback, in: saved).flatMap { $0.entries.map(\.id) }), Set(ledger.entries.map(\.id)))
        XCTAssertEqual(saved.imports[0].needsOrganization, false)
        XCTAssertTrue(ImportOrganizer.pendingEntryIDs(in: saved, batchID: batch.id).isEmpty)
        let retry = ScriptedChatTransport([])
        try await resume(store, script: retry, batchID: batch.id)
        let retried = await retry.recorded(); XCTAssertTrue(retried.isEmpty)
    }

    func testPartySummaryStatisticsRedactionAndAtMostThreeSamples() async throws {
        var (ledger, _) = partyImport(counts: [6])
        let amounts: [Int64] = [588, 588, 600, 588, 1000, 1200], days = [0, 1, 2, 4, 7, 9]
        for i in ledger.entries.indices {
            ledger.entries[i].amount = amounts[i]
            ledger.entries[i].date = Dates.addDays(days[i], to: Dates.parse("2026-01-01")!)
            ledger.entries[i].title = "微信转账李明 · " + (i < 4 ? "快捷支付" : "消费")
            ledger.entries[i].note = "给李明 买菜 13800138000 source-secret"
            ledger.entries[i].externalID = "source-secret"
        }
        let script = ScriptedChatTransport([jsonReply("```json\n{\"groups\":[]}\n```")])
        _ = try await ImportOrganizer(transport: script).organize(ledger: ledger, entryIDs: ledger.entries.map(\.id))
        let requests = await script.recorded()
        let request = try XCTUnwrap(requests.first), text = try XCTUnwrap(request.messages.last?.content)
        let input = try JSONValue.parse(text), group = try XCTUnwrap(input["groups"]?.arrayValue?.first)
        XCTAssertEqual(group["count"], .number(6)); XCTAssertEqual(group["inflow"], .bool(false))
        XCTAssertEqual(group["amount_min"]?["cents"], .number(588))
        XCTAssertEqual(group["amount_median"]?["cents"], .number(594))
        XCTAssertEqual(group["amount_max"]?["cents"], .number(1200))
        XCTAssertEqual(group["amount_mode"]?["cents"], .number(588)); XCTAssertEqual(group["amount_mode_share"], .number(0.5))
        XCTAssertEqual(group["first_date"], .string("2026-01-01")); XCTAssertEqual(group["last_date"], .string("2026-01-10"))
        XCTAssertEqual(group["median_interval_days"], .number(2))
        XCTAssertEqual(group["common_summaries"]?.arrayValue?.first?["text"], .string("快捷支付"))
        XCTAssertEqual(group["common_summaries"]?.arrayValue?.first?["count"], .number(4))
        XCTAssertEqual(group["common_notes"]?.arrayValue?.first?["count"], .number(6))
        XCTAssertEqual(group["samples"]?.arrayValue?.count, 3)
        XCTAssertEqual(group["samples"]?.arrayValue?.map { $0["date"]! }, [.string("2026-01-01"), .string("2026-01-05"), .string("2026-01-10")])
        for secret in ["李明", "13800138000", "source-secret"] + ledger.entries.map({ $0.id.uuidString }) { XCTAssertFalse(text.contains(secret), secret) }
        XCTAssertTrue(group["party"]?.stringValue?.contains("联系人") == true)
        XCTAssertEqual(request.purpose, "导入整理·按对方"); XCTAssertEqual(request.thinking, false)
        XCTAssertEqual(request.responseFormat, .object(["type": .string("json_object")]))
        XCTAssertEqual(request.maxTokens, 512 + 640); XCTAssertEqual(request.timeout, 180)
        for prompt in [ImportOrganizer.partySystemPrompt, ImportOrganizer.systemPrompt] {
            XCTAssertTrue(prompt.contains("高频固定金额的规律本身就是证据")); XCTAssertTrue(prompt.contains("美团/饿了么"))
            XCTAssertFalse(prompt.contains("至多5"))
        }
    }
    func testConfidentPartyExpandsToEveryPendingRowAndPreservesExistingMainAndFacts() async throws {
        var (ledger, _) = partyImport(counts: [4])
        var classified = ledger.entries[0]; classified.id = UUID(); classified.category = "其他支出"
        ledger.entries.append(classified)
        var edited = ledger.entries[0]; edited.id = UUID(); edited.userEdited = true
        ledger.entries.append(edited)
        var outside = ledger.entries[0]; outside.id = UUID(); outside.batchID = nil
        ledger.entries.append(outside)
        let pending = Array(ledger.entries.prefix(4).map(\.id)), before = ledger
        let script = ScriptedChatTransport([
            jsonReply(#"{"groups":[{"group":"g0","category":"餐饮","nature":"expense","purpose":"外卖","confident":true}]}"#),
            jsonReply(#"{"rows":[]}"#)
        ])
        let result = try await ImportOrganizer(transport: script).organize(ledger: ledger, entryIDs: pending + [classified.id, edited.id])
        _ = try result.changeSet.apply(to: &ledger)
        XCTAssertTrue(ledger.entries.prefix(4).allSatisfy { $0.category == "餐饮" && $0.nature == .expense && $0.purpose == "外卖" })
        XCTAssertEqual(ledger.entries[4], classified); XCTAssertEqual(ledger.entries[5], edited); XCTAssertEqual(ledger.entries[6], outside)
        XCTAssertEqual(ledger.entries.map(\.amount), before.entries.map(\.amount)); XCTAssertEqual(ledger.entries.map(\.date), before.entries.map(\.date))
        XCTAssertEqual(ledger.entries.map(\.accountID), before.entries.map(\.accountID))
        let requests = await script.recorded(), payload = try JSONValue.parse(requests[0].messages.last!.content!)
        XCTAssertEqual(payload["groups"]?.arrayValue?.first?["count"], .number(4))
    }
    func testFallbackCoversBeyondOneThousandIDsWhileLegacyPartyQuestionIsIgnored() async throws {
        var (ledger, _) = partyImport(counts: [1088])
        let ids = Set(ledger.entries.map(\.id))
        let script = ScriptedChatTransport([jsonReply(#"{"groups":[],"questions":[{"group":"g0","text":"这些扣款是什么用途？","options":[{"title":"买基金","items":[{"kind":"set_nature","nature":"investBuy"},{"kind":"set_purpose","text":"基金定投"}]},{"title":"日常支出","items":[{"kind":"set_nature","nature":"expense"},{"kind":"set_category","category":"餐饮"}]}]}]}"#)])
        let result = try await ImportOrganizer(transport: script).organize(ledger: ledger, entryIDs: Array(ids))
        let question = try XCTUnwrap(result.questions.first)
        XCTAssertEqual(result.questions.count, 1); XCTAssertTrue(question.isFallback)
        XCTAssertEqual(Set(question.entryIDs), ids)
        XCTAssertTrue(question.options.isEmpty)
        if !result.changeSet.items.isEmpty { _ = try result.changeSet.apply(to: &ledger) }
        XCTAssertTrue(ledger.entries.allSatisfy { $0.nature == .unknownOut && $0.purpose == nil })
        XCTAssertNil(question.answer(0, in: ledger))
        XCTAssertEqual(Set(UnsortedGroups.groups(for: question, in: ledger).flatMap { $0.entries.map(\.id) }), ids)
    }
    func testPartyAndSingletonFallbacksMergeWhileBothLegacyQuestionFormatsAreIgnored() async throws {
        var (ledger, _) = partyImport(counts: [3], singleton: true)
        let single = ledger.entries.last!.id
        // The singleton uses another party but a nearby amount, as in existing group().
        ledger.entries[3].amount = 590
        let option = #""options":[{"title":"日常支出","items":[{"kind":"set_nature","nature":"expense"}]},{"title":"借给别人","items":[{"kind":"set_nature","nature":"lend"}]}]"#
        let script = ScriptedChatTransport([
            jsonReply("{\"groups\":[],\"questions\":[{\"group\":\"g0\",\"text\":\"这些是什么用途？\",\(option)}]}"),
            jsonReply(try JSONValue.object(["rows": .array([]), "questions": .array([.object([
                "text": .string("这笔是什么用途？"), "entry_ids": .strings([single.uuidString]),
                "options": .array([("日常支出", "expense"), ("借给别人", "lend")].map { title, nature in .object([
                    "title": .string(title), "items": .array([.object(["kind": .string("set_nature"), "entry": .string(single.uuidString), "nature": .string(nature)])])]) })
            ])])]).jsonText())
        ])
        let result = try await ImportOrganizer(transport: script).organize(ledger: ledger, entryIDs: ledger.entries.map(\.id))
        XCTAssertEqual(result.questions.count, 1); XCTAssertEqual(Set(result.questions[0].entryIDs), Set(ledger.entries.map(\.id)))
        XCTAssertTrue(result.questions[0].isFallback)
        XCTAssertTrue(result.questions[0].options.isEmpty)
        let requests = await script.recorded()
        XCTAssertEqual(requests.map(\.purpose), ["导入整理·按对方", "导入整理"])
        let rows = try JSONValue.parse(requests[1].messages.last!.content!)["batch"]?.arrayValue
        XCTAssertEqual(rows?.count, 1); XCTAssertEqual(rows?.first?["id"], .string(single.uuidString))
        XCTAssertEqual(Set(requests.compactMap(\.groupID)).count, 1)
    }
    func testPartyCheckpointCancellationResumeAndRecordProgressNeverResendsGroups() async throws {
        let (ledger, batch) = partyImport(counts: Array(repeating: 3, count: 13), singleton: true)
        let store = ImportCheckpointStore(ledger, batchID: batch.id)
        await store.configure(cancel: 1)
        let script = ScriptedChatTransport([jsonReply(#"{"groups":[{"group":"g0","category":"餐饮","nature":"expense","confident":true}],"questions":[{"group":"g1","text":"这些是什么用途？","options":[{"title":"日常支出","items":[{"kind":"set_nature","nature":"expense"}]},{"title":"借给别人","items":[{"kind":"set_nature","nature":"lend"}]}]}]}"#)])
        let task = Task { try await self.resume(store, script: script, batchID: batch.id) }
        do { try await task.value; XCTFail("must stop after saved groups") } catch { XCTAssertTrue(error is CancellationError) }
        let partial = await store.snapshot(), sent = await script.recorded()
        let firstGroups = try JSONValue.parse(sent[0].messages.last!.content!)["groups"]!.arrayValue!
        let completed = firstGroups.reduce(0) { sum, group in sum + Int(group["count"]!.numberForTest) }
        XCTAssertEqual(firstGroups.count, 12); XCTAssertEqual(completed, 36)
        XCTAssertEqual(partial.imports[0].organizedEntryIDs?.count, completed)
        XCTAssertEqual(partial.imports[0].organization?.categoryCount, 3)
        XCTAssertEqual(partial.imports[0].organization?.questions.filter { !$0.isFallback }.count, 0)
        XCTAssertEqual(PendingImportOrganization(in: partial).count, 40 - completed)
        XCTAssertEqual(ImportOrganizationProgress(completed: completed, total: 40).completed, 36)
        let retry = ScriptedChatTransport([jsonReply(#"{"groups":[]}"#), jsonReply(#"{"rows":[]}"#)])
        let snapshot = await store.snapshot()
        _ = try await ImportOrganizer(transport: retry).organize(ledger: snapshot, entryIDs: ImportOrganizer.pendingEntryIDs(in: snapshot, batchID: batch.id)) { result, ids, before in
            let saved = try await store.save(result, ids: ids, before: before)
            let totalCompleted = saved.imports[0].organizedEntryIDs!.count
            XCTAssertEqual(totalCompleted, completed + (ids.count == 3 ? 3 : 4))
            return saved
        }
        let retried = await retry.recorded(), complete = await store.snapshot()
        let remainingGroups = try JSONValue.parse(retried[0].messages.last!.content!)["groups"]!.arrayValue!
        let names = Set(firstGroups.compactMap { $0["party"]?.stringValue })
        XCTAssertTrue(names.isDisjoint(with: remainingGroups.compactMap { $0["party"]?.stringValue }))
        XCTAssertEqual(complete.imports[0].organizedEntryIDs?.count, 40); XCTAssertEqual(complete.imports[0].needsOrganization, false)
        XCTAssertEqual(complete.imports[0].organization?.questions.count, 1, "Only local fallbacks merge across stages and resume")
        XCTAssertTrue(complete.imports[0].organization?.questions.allSatisfy(\.isFallback) == true)
    }
    func testPartyModelCanDeferToIndividualEvidenceWithoutCompletingIDsEarly() async throws {
        let (ledger, batch) = partyImport(counts: [3])
        let store = ImportCheckpointStore(ledger, batchID: batch.id)
        let script = ScriptedChatTransport([
            jsonReply(#"{"groups":[{"group":"g0","needs_individual":true}]}"#),
            jsonReply(#"{"rows":[]}"#)
        ])
        try await resume(store, script: script, batchID: batch.id)
        let requests = await script.recorded(), saved = await store.snapshot()
        XCTAssertEqual(requests.map(\.purpose), ["导入整理·按对方", "导入整理"])
        let checkpoints = await store.checkpoints
        XCTAssertEqual(checkpoints, 1)
        XCTAssertEqual(Set(saved.imports[0].organizedEntryIDs ?? []), Set(ledger.entries.map(\.id)))
        let rows = try JSONValue.parse(requests[1].messages.last!.content!)["batch"]!.arrayValue!
        XCTAssertEqual(Set(rows.compactMap { $0["id"]?.stringValue }), Set(ledger.entries.map { $0.id.uuidString }))
    }
    func testOppositeLegPartialRefundSeriesPlanRentAndSmallGroupsStayIndividual() async throws {
        var (ledger, _) = partyImport(counts: [3, 3, 3, 3, 3, 2, 3])
        ledger.accounts.append(Account(name: "合成钱包"))
        let first = ledger.entries[0]
        ledger.entries.append(Entry(date: first.date, amount: first.amount, nature: .unknownIn, accountID: ledger.accounts[1].id, title: "另一端"))
        ledger.entries.append(Entry(date: first.date, amount: 100, nature: .unknownIn, accountID: first.accountID, title: "合成对方1 · 部分退款"))
        for i in 6..<9 { ledger.entries[i].date = Dates.addMonths(i - 6, to: first.date) }
        var plan = Plan(title: "已有计划", amount: ledger.entries[9].amount, dueDate: first.date)
        plan.accountID = first.accountID; ledger.plans = [plan]
        for i in 12..<15 { ledger.entries[i].amount = 9000 }
        ledger.rents = [Rent(monthlyTotal: 3000, personalShare: 100, startDate: first.date, nextDueDate: first.date)] // Quarterly payment.
        // A pre-existing relation is also ineligible even when the other group
        // members look ordinary; the linked row itself is never bulk classified.
        ledger.entries[17].nature = .repayment
        let targets = ledger.entries.filter { $0.batchID != nil }.map(\.id)
        let script = ScriptedChatTransport([jsonReply(#"{"rows":[]}"#)])
        _ = try await ImportOrganizer(transport: script).organize(ledger: ledger, entryIDs: targets)
        let requests = await script.recorded()
        XCTAssertEqual(requests.map(\.purpose), ["导入整理"])
        let rows = try JSONValue.parse(requests[0].messages.last!.content!)["batch"]!.arrayValue!
        XCTAssertEqual(Set(rows.compactMap { $0["id"]?.stringValue }), Set(targets.map(\.uuidString)))
    }
    func testSamePartyOppositeDirectionsHaveSeparateSummariesAndIgnoreLegacyGroupQuestions() async throws {
        var (ledger, _) = partyImport(counts: [3, 3])
        for i in 3..<6 {
            ledger.entries[i].title = ledger.entries[0].title
            ledger.entries[i].nature = .unknownIn // Larger inflows are not partial refunds of these small outflows.
        }
        let script = ScriptedChatTransport([jsonReply(#"{"groups":[{"group":"g0","category":"不存在的分类","nature":"expense","confident":true}],"questions":[{"group":"g1","text":"这些是什么钱？","options":[{"title":"日常消费","items":[{"kind":"set_nature","nature":"expense","entry":"model-must-not-pick-UUIDs"}]},{"title":"借出","items":[{"kind":"set_nature","nature":"lend"}]}]}]}"#)])
        let result = try await ImportOrganizer(transport: script).organize(ledger: ledger, entryIDs: ledger.entries.map(\.id))
        let requests = await script.recorded(), groups = try JSONValue.parse(requests[0].messages.last!.content!)["groups"]!.arrayValue!
        XCTAssertEqual(groups.count, 2); XCTAssertEqual(Set(groups.compactMap { $0["party"]?.stringValue }).count, 1)
        XCTAssertEqual(groups.map { $0["inflow"]! }, [.bool(true), .bool(false)])
        XCTAssertTrue(result.questions.allSatisfy(\.isFallback))
        XCTAssertEqual(Set(result.questions.flatMap(\.entryIDs)), Set(ledger.entries.map(\.id)))
        XCTAssertFalse(result.skipped.isEmpty)
        XCTAssertFalse(result.changeSet.items.contains { if case .setCategory = $0 { return true }; return false })
    }
}

private extension JSONValue {
    var numberForTest: Double { if case .number(let value) = self { return value }; return -1 }
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
        XCTAssertEqual(ledger.categoryMemory[CategoryMemory.key(entry.title)], "购物")
        try LedgerOperations.bulkEdit([entry.id], category: "餐饮", nature: nil, in: &ledger)
        XCTAssertEqual(ledger.categoryMemory[CategoryMemory.key(entry.title)], "餐饮")
        XCTAssertEqual(try LedgerCodec.decode(LedgerCodec.encode(ledger)).categoryMemory, ledger.categoryMemory)
    }
    func testRememberedCategoryIsAcceptedBeforeModelAndConflictsAreIgnored() async throws {
        let ctx = AssistantFixtures.context(); var ledger = ctx.ledger
        ledger.entries = [Entry(date: ctx.now, amount: 2000, accountID: ledger.accounts[0].id, title: "美团123!", category: Classification.pendingCategory)]
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
        XCTAssertTrue(requests[0].messages.first?.content?.contains("known_categories 是用户记忆、已有主项或分类表已确定的分类") == true)
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

extension ImportOrganizerTests {
    func testExplicitImportCategoryChoiceCannotBeOverwrittenByOrganization() async throws {
        var ledger = Ledger(); ledger.accounts = [Account(name: "卡")]
        let bytes = Data("日期,收支,金额,用途,分类\n2026-10-01,支出,25.00,车票,旅行\n".utf8)
        let preview = try BillImporter.preview(data: bytes, filename: "a.csv", accountID: ledger.accounts[0].id,
            ledger: ledger, categoryMappings: ["旅行": "其他支出"])
        _ = try BillImporter.commit(preview, data: bytes, to: &ledger)
        let id = try XCTUnwrap(ledger.entries.first?.id)
        let transport = ImportScript { _ in .object(["rows": .array([.object([
            "entry": .string(id.uuidString), "category": .string("交通"), "confident": .bool(true),
            "nature": .string("expense"), "purpose": .string("周末车票")])])]) }
        let organization = try await ImportOrganizer(transport: transport).organize(ledger: ledger, entryIDs: [id])
        _ = try organization.changeSet.apply(to: &ledger)
        XCTAssertEqual(ledger.entries.first?.category, "其他支出")
        XCTAssertEqual(ledger.entries.first?.purpose, "周末车票")
    }
}
