import XCTest
@testable import YubaiCore

private actor ImportScript: ChatTransport {
    let reply: @Sendable (ChatRequest) throws -> JSONValue
    let wrap: @Sendable (String) -> String
    let entries: [Entry]
    var requests: [ChatRequest] = []
    init(entries: [Entry] = [], wrap: @escaping @Sendable (String) -> String = { $0 }, _ reply: @escaping @Sendable (ChatRequest) throws -> JSONValue) {
        self.reply = reply; self.wrap = wrap; self.entries = entries
    }
    func send(_ request: ChatRequest) async throws -> ChatMessage {
        requests.append(request)
        let wire = try ImportWireFixture(request, entries: entries)
        return ChatMessage(role: .assistant, content: try wrap(wire.encode(reply(wire.request)).jsonText()))
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
    let repository: LedgerRepository?
    var checkpoints = 0
    var editAfterCheckpoint: Int?
    var cancelAfterCheckpoint: Int?
    init(_ ledger: Ledger, batchID: UUID, repository: LedgerRepository? = nil) {
        self.ledger = ledger; self.batchID = batchID; self.repository = repository
    }
    func beginRun() throws { try repository?.preserveRecovery(ledger, reason: "导入整理") }
    func snapshot() -> Ledger { ledger }
    func configure(edit: Int? = nil, cancel: Int? = nil) { editAfterCheckpoint = edit; cancelAfterCheckpoint = cancel }
    func check(_ snapshot: Ledger) throws {
        guard ledger == snapshot else { throw YubaiError.invalid(ImportOrganizer.ledgerChangedMessage) }
    }
    func save(_ result: ImportOrganization, ids: [UUID], before: Ledger) throws -> Ledger {
        let prepared = try result.preparingCheckpoint(entryIDs: ids, snapshot: before, current: ledger, batchID: batchID)
        var next = prepared.ledger
        next.updatedAt = next.updatedAt.addingTimeInterval(1)
        try next.validate()
        // Exercise actual Codable round trips between every request.
        if let repository {
            _ = try repository.save(next, reason: "导入整理", requiringUnchanged: true, preservingRecovery: false)
            ledger = try repository.load()
        } else { ledger = try LedgerCodec.decode(LedgerCodec.encode(next)) }
        checkpoints += 1
        if checkpoints == editAfterCheckpoint { ledger.preferences.dailyLiving += 1 }
        if checkpoints == cancelAfterCheckpoint { withUnsafeCurrentTask { $0?.cancel() } }
        return ledger
    }
    func editEntry(_ id: UUID) {
        if let index = ledger.entries.firstIndex(where: { $0.id == id }) {
            ledger.entries[index].purpose = "用户用途"; ledger.entries[index].userEdited = true
        }
    }
    func undo() { BillImporter.undo(batchID: batchID, in: &ledger) }
}

private actor ResumableImportScript: ChatTransport {
    var batches: [[UUID]] = []
    var entries: [Entry] = []
    func useEntries(_ entries: [Entry]) { self.entries = entries }
    var failAt: Int?
    var leaveUncertain = false
    init(entries: [Entry] = [], failAt: Int? = nil, leaveUncertain: Bool = false) { self.entries = entries; self.failAt = failAt; self.leaveUncertain = leaveUncertain }
    func send(_ request: ChatRequest) async throws -> ChatMessage {
        if request.purpose == "导入短评" { return ChatMessage(role: .assistant, content: #"{"cards":[]}"#) }
        XCTAssertEqual(request.purpose, "导入整理")
        XCTAssertEqual(request.timeout, 45)
        XCTAssertEqual(request.maxTokens, 2000)
        XCTAssertNil(request.model)
        XCTAssertEqual(request.thinking, false)
        let wire = try ImportWireFixture(request, entries: entries)
        let input = try JSONValue.parse(wire.request.messages.last!.content!)
        let rows = input["batch"]!.arrayValue!
        XCTAssertLessThanOrEqual(rows.count, 15)
        XCTAssertGreaterThan(rows.count, 0)
        XCTAssertLessThanOrEqual(input["context"]!.arrayValue!.count, 60)
        batches.append(rows.compactMap { $0["id"]?.stringValue.flatMap(UUID.init(uuidString:)) })
        if batches.count == failAt { try await Task.sleep(nanoseconds: 100_000_000); throw DeepSeekError.http(503) }
        let output: [JSONValue] = leaveUncertain ? [] : rows.map {
            .object(["entry": $0["id"]!, "category": .string("餐饮"), "nature": .string("expense"), "purpose": .string("午餐"), "confident": .bool(true)])
        }
        return ChatMessage(role: .assistant, content: try wire.encode(.object(["rows": .array(output)])).jsonText())
    }
    func sentBatches() -> [[UUID]] { batches }
}

final class ImportOrganizerTests: XCTestCase {
    /// Import-shaped metadata, including the IDs/notes used for deduplication and provenance.
    private func largeImport() -> (Ledger, UUID) {
        var ledger = Ledger()
        let date = Dates.parse("2026-11-03")!
        ledger.updatedAt = date
        ledger.accounts = [Account(name: "合成支付宝", at: date)]
        var batch = ImportBatch(filename: "synthetic-4200.csv", importedCount: 4200, duplicateCount: 0, skippedCount: 0)
        batch.importedAt = date; batch.needsOrganization = true; batch.undo = ImportUndo(updatedAt: date)
        let attachment = Attachment(name: batch.filename, data: Data("合成原件".utf8))
        batch.attachmentID = attachment.id
        ledger.attachments = [attachment]; ledger.imports = [batch]
        ledger.entries = (0..<4200).map { index in
            var entry = Entry(date: date.addingTimeInterval(Double(-index * 60)), amount: Int64(100 + index % 10000),
                              accountID: ledger.accounts[0].id, title: "合成商户\(index % 70)")
            entry.batchID = batch.id; entry.attachmentID = attachment.id
            entry.source = "支付宝"; entry.sourceRow = index + 2
            entry.externalID = "202611030000000000\(String(format: "%010d", index))"
            entry.sourceIdentity = entry.source + "|" + entry.accountID.uuidString + "|" + entry.externalID
            entry.fingerprint = LedgerCodec.checksum(Data("合成流水\(index)".utf8))
            entry.note = "对手信息：合成商户\(index % 70)\n原账单状态：交易成功\n收付款方式：余额宝"
            entry.classificationReason = "没分类"
            return entry
        }
        return (ledger, batch.id)
    }

    func test4200EntryMetadataSizeAndUndoRemainBounded() throws {
        var (ledger, batchID) = largeImport()
        let imported = ledger
        let rawBytes = try LedgerCodec.encodeMetadata(ledger)
        let items = ledger.entries.flatMap { entry -> [ChangeItem] in
            [.setCategory(entry: entry.id, category: "餐饮"), .setPurpose(entry: entry.id, text: "午餐")]
        }
        // The production path accumulates changes for the import details screen.
        // Apply 30-row checkpoints, without spending this size test on model/parsing work.
        for start in stride(from: 0, to: ledger.entries.count, by: 30) {
            let before = ledger
            let end = min(start + 30, ledger.entries.count)
            for index in start..<end {
                ledger.entries[index].category = "餐饮"; ledger.entries[index].purpose = "午餐"
                ledger.entries[index].userEdited = true
                ledger.entries[index].classificationReason = "导入整理：根据账单用途与关联证据整理"
            }
            let result = ImportOrganization(changeSet: ChangeSet(source: "导入整理", reason: "根据账单用途与关联证据整理",
                                                                items: Array(items[(start * 2)..<(end * 2)])), questions: [], skipped: [])
            result.finish(batchID: batchID, before: before, in: &ledger, entryIDs: Array(ledger.entries[start..<end].map(\.id)))
        }
        let organizedBytes = try LedgerCodec.encodeMetadata(ledger)
        let compressed = try RecoveryCompression.encode(organizedBytes)
        print("RECOVERY_SIZE_4200 imported=\(rawBytes.count) organized=\(organizedBytes.count) gzip=\(compressed.count) undoEntries=\(ledger.imports[0].undo!.entries.count)")
        XCTAssertLessThan(rawBytes.count, 4_000_000)
        XCTAssertLessThan(organizedBytes.count, 5_000_000)
        XCTAssertEqual(ledger.imports[0].undo?.entries.count, 0, "Rows from this batch are removed on undo, never copied into undo")
        XCTAssertEqual(try LedgerCodec.decode(organizedBytes), ledger)
        BillImporter.undo(batchID: batchID, in: &ledger)
        var expected = imported; expected.entries = []; expected.imports = []; expected.attachments = []
        XCTAssertEqual(ledger, expected)
    }

    private func syntheticImport(count: Int = 200) throws -> (Ledger, Ledger, ImportBatch) {
        var ledger = Ledger(); ledger.accounts = [Account(name: "合成卡")]
        // These tests exercise individual association checkpoints, not grouping.
        ledger.plans = [Plan(title: "合成关联候选", amount: 1000, dueDate: Dates.parse("2040-01-01")!)]
        let before = ledger
        let rows = (0..<count).map { "2026-10-01,支出,10.00,合成用途\($0),合成\($0)" }
        let bytes = Data((["时间,收支,金额,名称,交易单号"] + rows).joined(separator: "\n").utf8)
        let preview = try BillImporter.preview(data: bytes, filename: "synthetic.csv", accountID: ledger.accounts[0].id, ledger: ledger)
        let batch = try BillImporter.commit(preview, data: bytes, to: &ledger)
        return (before, ledger, batch)
    }
    @discardableResult private func resume(_ store: ImportCheckpointStore, script: any ChatTransport, batchID: UUID, beginningRun: Bool = true) async throws -> ImportOrganization {
        if beginningRun { try await store.beginRun() }
        let snapshot = await store.snapshot()
        if let resumable = script as? ResumableImportScript { await resumable.useEntries(snapshot.entries) }
        let organizer = ImportOrganizer { _ in script }
        return try await organizer.organize(ledger: snapshot, entryIDs: ImportOrganizer.pendingEntryIDs(in: snapshot, batchID: batchID)) { result, ids, before in
            try await store.save(result, ids: ids, before: before)
        }
    }
    func testMultiChunkRunKeepsOnePreRunRecoveryAndBatchUndoAfterReload() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("yubai-organize-history-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = LedgerRepository(directory: root)
        let (before, imported, batch) = try syntheticImport(count: 95)
        let initial = try repository.save(imported)
        let store = ImportCheckpointStore(initial, batchID: batch.id, repository: repository)
        try await resume(store, script: ResumableImportScript(), batchID: batch.id)
        let checkpoints = await store.checkpoints
        XCTAssertEqual(checkpoints, 7)
        let history = try repository.recoveries()
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(try repository.readRecovery(XCTUnwrap(history.first)), imported)
        var complete = try LedgerRepository(directory: root).load()
        XCTAssertEqual(complete.imports[0].organizedEntryIDs?.count, 95)
        BillImporter.undo(batchID: batch.id, in: &complete)
        XCTAssertEqual(complete, before)
        // Normal operations immediately resume their original snapshot policy.
        try repository.save(complete, reason: "整批撤销")
        XCTAssertEqual(try repository.recoveries().count, 2)
    }

    func testFailedAndStoppedRunsShareFirstRecoveryWhenResumedWithinWindow() async throws {
        for failing in [true, false] {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("yubai-organize-resume-\(UUID())")
            defer { try? FileManager.default.removeItem(at: root) }
            let repository = LedgerRepository(directory: root)
            let (before, imported, batch) = try syntheticImport(count: 100)
            let store = ImportCheckpointStore(try repository.save(imported), batchID: batch.id, repository: repository)
            if !failing { await store.configure(cancel: 2) }
            let run = Task {
                try await self.resume(store, script: ResumableImportScript(failAt: failing ? 3 : nil), batchID: batch.id)
            }
            if failing { try await run.value }
            else { do { try await run.value; XCTFail("user stop must cancel") } catch { } }
            let partial = try repository.load()
            XCTAssertEqual(partial.imports[0].organizedEntryIDs?.count, failing ? 85 : 30)
            XCTAssertEqual(try repository.recoveries().count, 1)
            XCTAssertEqual(try repository.readRecovery(XCTUnwrap(repository.recoveries().first)), imported)
            await store.configure()
            try await resume(store, script: ResumableImportScript(), batchID: batch.id)
            let history = try repository.recoveries()
            XCTAssertEqual(history.count, 1)
            XCTAssertEqual(try repository.readRecovery(history[0]), imported)
            var undone = try repository.load()
            BillImporter.undo(batchID: batch.id, in: &undone)
            XCTAssertEqual(undone, before)
        }
    }

    func testMultipleImportBatchesInOneRunShareThePreRunRecovery() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("yubai-multi-import-history-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = LedgerRepository(directory: root)
        var (_, imported, first) = try syntheticImport(count: 35)
        var second = ImportBatch(filename: "second.csv", importedCount: 35, duplicateCount: 0, skippedCount: 0)
        second.needsOrganization = true; second.undo = ImportUndo(updatedAt: imported.updatedAt)
        let extra = imported.entries.map { entry -> Entry in
            var entry = entry; entry.id = UUID(); entry.batchID = second.id
            entry.externalID += "-second"; entry.sourceIdentity += "-second"; entry.fingerprint += "-second"
            return entry
        }
        imported.imports.append(second); imported.entries += extra
        var saved = try repository.save(imported)
        for (index, batch) in [first, second].enumerated() {
            let store = ImportCheckpointStore(saved, batchID: batch.id, repository: repository)
            try await resume(store, script: ResumableImportScript(), batchID: batch.id, beginningRun: index == 0)
            saved = await store.snapshot()
        }
        XCTAssertTrue(saved.imports.allSatisfy { $0.needsOrganization == false })
        XCTAssertEqual(try repository.recoveries().count, 1)
        XCTAssertEqual(try repository.readRecovery(XCTUnwrap(repository.recoveries().first)), imported)
    }

    func testUndoDeltaStoresOnlyChangedForeignEntriesAndKeepsTheirFirstValues() throws {
        var before = Ledger(); let date = Dates.parse("2026-11-03")!
        before.updatedAt = date; before.accounts = [Account(name: "合成卡", at: date)]
        before.entries = (0..<200).map { Entry(date: date, amount: Int64(100 + $0), accountID: before.accounts[0].id, title: "旧记录\($0)") }
        var batch = ImportBatch(filename: "diff.csv", importedCount: 1, duplicateCount: 0, skippedCount: 0)
        batch.undo = ImportUndo(updatedAt: before.updatedAt)
        var ledger = before; ledger.imports = [batch]
        var own = Entry(date: date, amount: 99, accountID: before.accounts[0].id, title: "本批记录")
        own.batchID = batch.id; ledger.entries.append(own)
        let imported = ledger
        ledger.entries[0].purpose = "第一次用途"; ledger.entries[1].category = "餐饮"
        var plan = Plan(title: "合成安排", amount: 100, dueDate: date)
        plan.accountID = before.accounts[0].id; ledger.plans.append(plan)
        ledger.cards.append(ButlerCard(kind: .answerQuestion, title: "合成", body: "合成", evidence: [], action: .answerQuestion, dedupeKey: "diff"))
        ImportOrganization.recordUndo(batchID: batch.id, before: imported, in: &ledger)
        let middle = ledger
        ledger.entries[0].purpose = "第二次用途"; ledger.entries[2].note = "合成改动"
        ledger.entries[200].purpose = "本批不用复制"
        ImportOrganization.recordUndo(batchID: batch.id, before: middle, in: &ledger)
        let undo = try XCTUnwrap(ledger.imports[0].undo)
        XCTAssertEqual(undo.entries, Array(before.entries.prefix(3)))
        XCTAssertEqual(undo.planIDs, [plan.id]); XCTAssertEqual(undo.cardIDs, ledger.cards.map(\.id))
        // This is the pre-existing undo JSON shape: full prior values for changed rows,
        // no memoryIDs in older data. Reading and resaving it must preserve batch undo.
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: LedgerCodec.encodeMetadata(ledger)) as? [String: Any])
        var imports = try XCTUnwrap(json["imports"] as? [[String: Any]])
        var legacyUndo = try XCTUnwrap(imports[0]["undo"] as? [String: Any])
        legacyUndo.removeValue(forKey: "memoryIDs"); imports[0]["undo"] = legacyUndo; json["imports"] = imports
        var restored = try LedgerCodec.decode(JSONSerialization.data(withJSONObject: json))
        restored = try LedgerCodec.decode(LedgerCodec.encodeMetadata(restored))
        BillImporter.undo(batchID: batch.id, in: &restored)
        XCTAssertEqual(restored, before)
    }
    func testThirdChunkFailurePersistsTwoChunksResumesOnlyRemainderAndUndoesEntireImport() async throws {
        let (before, imported, batch) = try syntheticImport()
        let store = ImportCheckpointStore(imported, batchID: batch.id)
        let failing = ResumableImportScript(failAt: 3)
        let result = try await resume(store, script: failing, batchID: batch.id)
        XCTAssertEqual(result.failedChunks?.count, 1)
        XCTAssertEqual(result.failedChunks?.first?.entryIDs.count, 15)
        XCTAssertEqual(ImportOrganizer.incompleteMessage(remaining: 15, reason: result.failedChunks!.first!.reason),
                       "15 笔没整理完：DeepSeek 繁忙（HTTP 503）")
        let partial = await store.snapshot()
        XCTAssertEqual(partial.entries.filter { $0.category == "餐饮" }.count, 185)
        XCTAssertEqual(partial.imports[0].organizedEntryIDs?.count, 185)
        XCTAssertEqual(partial.imports[0].needsOrganization, true)
        XCTAssertEqual(partial.imports[0].organization?.categoryCount, 185)
        XCTAssertEqual(PendingImportOrganization(in: partial).count, 15)
        XCTAssertEqual(ImportOrganizer.pendingEntryIDs(in: partial, batchID: batch.id).count, 15)
        let first = await failing.sentBatches()
        XCTAssertEqual(first.count, 14)
        let retry = ResumableImportScript()
        try await resume(store, script: retry, batchID: batch.id)
        let complete = await store.snapshot()
        let retried = await retry.sentBatches()
        XCTAssertEqual(retried.map(\.count).sorted(), [15])
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
        ledger.plans = [Plan(title: "合成关联候选", amount: 100, dueDate: Dates.parse("2040-01-01")!)]
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
        let script = ImportScript(entries: ledger.entries) { request in
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
        XCTAssertEqual(complete.entries.first { $0.id == subscription.id }?.planID, complete.plans.first { $0.title == "合成订阅" }?.id)
        let requests = await script.requests
        XCTAssertEqual(requests.filter { $0.purpose == "导入整理" }.count, 14)
        await store.undo()
        let undone = await store.snapshot()
        XCTAssertEqual(undone, before)
    }
    func testUncertainRowsAreCheckpointedAndNotRequestedAgain() async throws {
        let (_, imported, batch) = try syntheticImport()
        let store = ImportCheckpointStore(imported, batchID: batch.id)
        let result = try await resume(store, script: ResumableImportScript(failAt: 3, leaveUncertain: true), batchID: batch.id)
        XCTAssertEqual(result.failedChunks?.count, 1)
        let partial = await store.snapshot()
        XCTAssertTrue(partial.entries.allSatisfy(Classification.isPending))
        XCTAssertEqual(ImportOrganizer.pendingEntryIDs(in: partial, batchID: batch.id).count, 15)
        let retry = ResumableImportScript(leaveUncertain: true)
        try await resume(store, script: retry, batchID: batch.id)
        let complete = await store.snapshot()
        XCTAssertEqual(complete.imports[0].needsOrganization, false)
        let requests = await retry.sentBatches()
        XCTAssertEqual(requests.count, 1)
    }
    func testCancellationBetweenChunksKeepsSavedResultsAndUndo() async throws {
        let (before, imported, batch) = try syntheticImport()
        let store = ImportCheckpointStore(imported, batchID: batch.id)
        await store.configure(cancel: 2)
        let script = ResumableImportScript()
        let task = Task { try await self.resume(store, script: script, batchID: batch.id) }
        do { try await task.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
        let batches = await script.sentBatches()
        XCTAssertEqual(batches.count, 3)
        let partial = await store.snapshot()
        XCTAssertEqual(partial.imports[0].needsOrganization, true)
        XCTAssertEqual(partial.imports[0].organizedEntryIDs?.count, 30)
        await store.undo()
        let undone = await store.snapshot()
        XCTAssertEqual(undone, before)
    }
    func testUnrelatedUserEditBetweenChunksAndOwnWritesBothContinue() async throws {
        let (_, imported, batch) = try syntheticImport()
        let store = ImportCheckpointStore(imported, batchID: batch.id)
        await store.configure(edit: 2)
        let script = ResumableImportScript()
        try await resume(store, script: script, batchID: batch.id)
        let batches = await script.sentBatches()
        XCTAssertEqual(batches.count, 14)
        let complete = await store.snapshot()
        XCTAssertEqual(complete.imports[0].organizedEntryIDs?.count, 200)
        XCTAssertEqual(complete.preferences.dailyLiving, imported.preferences.dailyLiving + 1)
    }
    func testMalformedJSONUsesTheOrganizerReasonAndDoesNotCheckpoint() async throws {
        struct Malformed: ChatTransport {
            func send(_ request: ChatRequest) async throws -> ChatMessage { ChatMessage(role: .assistant, content: "not JSON") }
        }
        let (_, ledger, batch) = try syntheticImport(count: 2)
        let store = ImportCheckpointStore(ledger, batchID: batch.id)
        let result = try await ImportOrganizer(transport: Malformed()).organize(ledger: ledger, entryIDs: ledger.entries.map(\.id)) { result, ids, before in
            try await store.save(result, ids: ids, before: before)
        }
        XCTAssertEqual(result.failedChunks?.first?.entryIDs, ledger.entries.map(\.id))
        XCTAssertEqual(result.failedChunks?.first?.reason, "整理返回格式无效")
        let after = await store.snapshot()
        XCTAssertEqual(after, ledger)
    }
    func testFencedJSONResponsesAreParsed() async throws {
        let (_, ledger, _) = try syntheticImport(count: 1)
        for fence in ["```json", "```"] {
            let script = ImportScript(entries: ledger.entries, wrap: { " \n\(fence)\n\($0)\n```\n " }) { _ in .object(["rows": .array([])]) }
            let result = try await ImportOrganizer(transport: script).organize(ledger: ledger, entryIDs: ledger.entries.map(\.id))
            XCTAssertEqual(result.questions.flatMap(\.entryIDs), ledger.entries.map(\.id))
        }
    }
    func testJSONWithSurroundingTextIsParsed() async throws {
        let (_, ledger, _) = try syntheticImport(count: 1)
        let script = ImportScript(entries: ledger.entries, wrap: { "整理结果如下：\n\($0)\n以上是整理结果。" }) { _ in .object(["rows": .array([])]) }
        let result = try await ImportOrganizer(transport: script).organize(ledger: ledger, entryIDs: ledger.entries.map(\.id))
        XCTAssertEqual(result.questions.flatMap(\.entryIDs), ledger.entries.map(\.id))
    }
    func testEveryChunkRequestsJSONObjectResponseFormat() async throws {
        let (_, ledger, _) = try syntheticImport(count: ImportOrganizer.chunkSize + 1)
        let script = ImportScript(entries: ledger.entries) { request in
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
        individualCandidates(in: &ledger)
        let ids = ledger.entries.map(\.id)
        let script = ImportScript(entries: ledger.entries) { request in
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
        let script = ImportScript(entries: ledger.entries) { _ in .object(["rows": .array([])]) }
        let result = try await ImportOrganizer(transport: script).organize(ledger: ledger, entryIDs: ids)
        XCTAssertEqual(result.questions.count, 1)
        XCTAssertEqual(result.questions.first?.entryIDs, [ledger.entries[0].id])
    }
    func testFallbacksMergeAcrossTwoCheckpointedChunksRegardlessOfPartyAmountOrDirection() async throws {
        let (base, imported, batch) = try syntheticImport(count: 2 * ImportOrganizer.chunkSize)
        var before = base, ledger = imported
        for i in ledger.entries.indices {
            ledger.entries[i].nature = i < ImportOrganizer.chunkSize ? .unknownOut : .unknownIn
            ledger.entries[i].title = "合成对方\(i)"
            ledger.entries[i].amount = 50_000 + Int64(i) * 100_000
        }
        individualCandidates(in: &ledger)
        before.plans = ledger.plans
        let store = ImportCheckpointStore(ledger, batchID: batch.id)
        let script = ResumableImportScript(entries: ledger.entries, leaveUncertain: true)
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
        let script = ResumableImportScript(entries: imported.entries, leaveUncertain: true)
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
        let result = try await ImportOrganizer(transport: ImportScript(entries: data.imported.entries) { request in
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
        let script = ImportScript(entries: ledger.entries) { request in
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
        let result = try await ImportOrganizer(transport: ImportScript(entries: ledger.entries) { request in
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
        ledger.plans = [2500, 50000].map { Plan(title: "合成关联候选", amount: $0, dueDate: Dates.parse("2040-01-01")!) }
        let before = ledger
        let preview = try BillImporter.preview(data: bytes, filename: "bill.csv", accountID: ledger.accounts[0].id, ledger: ledger)
        let batch = try BillImporter.commit(preview, data: bytes, to: &ledger)
        let raw = ledger; let id = ledger.entries[0].id; let mealID = ledger.entries[1].id
        let script = ImportScript(entries: ledger.entries) { _ in
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
        ledger.entries = [purchase, duplicate]
        ledger.plans = [Plan(title: "合成关联候选", amount: 3000, dueDate: Dates.parse("2040-01-01")!)]
        let before = ledger
        let bytes = Data("时间,收支,金额,名称\n2026-09-20,收入,50.00,部分退款\n2026-09-20,收入,50.00,房租分摊\n2026-09-16,支出,30.00,午餐\n2026-09-20,支出,20.00,未知\n".utf8)
        var preview = try BillImporter.preview(data: bytes, filename: "bill.csv", accountID: ledger.accounts[0].id, ledger: ledger)
        for i in preview.rows.indices where preview.rows[i].status == .possibleDuplicate { preview.rows[i].included = true }
        let batch = try BillImporter.commit(preview, data: bytes, to: &ledger); let raw = ledger
        let rows = ledger.entries.filter { $0.batchID == batch.id }; let rentID = ledger.rents[0].id
        let result = try await ImportOrganizer(transport: ImportScript(entries: ledger.entries) { request in
            let payload = try JSONValue.parse(request.messages.last!.content!)
            if let groups = payload["groups"]?.arrayValue {
                return .object(["groups": .array(groups.map { .object(["group": $0["id"]!,
                    "category": .string("不存在的分类"), "confident": .bool(true)]) })])
            }
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
        let offline = try await ImportOrganizer(transport: ImportScript(entries: ledger.entries) { _ in throw URLError(.notConnectedToInternet) }).organize(ledger: ledger, entryIDs: ids)
        let invalid = try await ImportOrganizer(transport: ImportScript(entries: ledger.entries) { _ in .object([:]) }).organize(ledger: ledger, entryIDs: ids)
        XCTAssertFalse(offline.failedChunks?.isEmpty ?? true)
        XCTAssertFalse(invalid.failedChunks?.isEmpty ?? true)
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

    func testOneAndTwoRowPartiesUseGroupStageWithAllRowsAsSamples() async throws {
        let (ledger, _) = partyImport(counts: [1, 2])
        let script = ImportScript(entries: ledger.entries) { request in
            XCTAssertEqual(request.purpose, "导入整理·按对方")
            let payload = try JSONValue.parse(request.messages.last!.content!)
            let groups = try XCTUnwrap(payload["groups"]?.arrayValue)
            XCTAssertEqual(groups.map { $0["count"]! }, [.number(2), .number(1)])
            for group in groups {
                XCTAssertEqual(group["samples"]?.arrayValue?.count, Int(group["count"]!.numberForTest))
            }
            return .object(["groups": .array(groups.map { .object(["group": $0["id"]!, "category": .string("餐饮"),
                "nature": .string("expense"), "purpose": .string("小店"), "confident": .bool(true)]) })])
        }
        let result = try await ImportOrganizer(transport: script).organize(ledger: ledger, entryIDs: ledger.entries.map(\.id))
        XCTAssertEqual(result.categoryCount, 3); XCTAssertTrue(result.questions.isEmpty)
        let sent = await script.count(); XCTAssertEqual(sent, 1)
    }
    func testPersonalSmallPaymentsRedPacketsAndSemanticPriorityAppearInBothPrompts() {
        for prompt in [ImportOrganizer.partySystemPrompt, ImportOrganizer.systemPrompt] {
            for rule in ["绝不向用户提问", "≥5笔", "中位≤50元", "amount_median.cents≤5000", "高频小额", "个人收款码", "小店", "ok:true",
                         "微信红包", "群收款", "人情家庭", "礼金赠与", "否则其他支出", "大额、低频", "用途语义优先于「像人名」", "掌上生活", "待还款", "信贷", "基金销售", "肯特瑞", "小金库", "每月固定日期"] {
                XCTAssertTrue(prompt.contains(rule), rule)
            }
        }
    }
    func testEveryRepaymentKeywordOverridesPersonalNameWithoutCreatingTransport() async throws {
        let keywords = ["还款", "信用卡", "掌上生活", "白条", "花呗", "借呗", "信贷", "待还款"]
        var (ledger, _) = partyImport(counts: [keywords.count])
        for i in ledger.entries.indices { ledger.entries[i].title = "李明 · " + keywords[i] }
        // Explicit main categories remain unchanged even when nature is corrected.
        ledger.entries[0].category = "其他支出"
        let before = ledger
        let organizer = ImportOrganizer { _ in
            XCTFail("deterministic repayment must not create a transport")
            throw YubaiError.invalid("离线")
        }
        let result = try await organizer.organize(ledger: ledger, entryIDs: ledger.entries.map(\.id))
        _ = try result.changeSet.apply(to: &ledger)
        XCTAssertTrue(ledger.entries.allSatisfy { $0.nature == .repayment && $0.purpose == "还款" })
        XCTAssertEqual(ledger.entries.map(\.category), before.entries.map(\.category))
        XCTAssertEqual(ledger.entries.map(\.amount), before.entries.map(\.amount))
        XCTAssertEqual(ledger.entries.map(\.date), before.entries.map(\.date))
        XCTAssertEqual(ledger.entries.map(\.accountID), before.entries.map(\.accountID))
        XCTAssertTrue(result.questions.isEmpty)
    }
    func testBankWeChatImportsFollowDirectionLocallyEvenWithAssociationCandidates() async throws {
        var ledger = Ledger(); ledger.accounts = [Account(name: "合成银行卡"), Account(name: "另一张卡")]
        let csv = """
        记账日期,货币,交易金额,交易摘要,对手信息
        2025-11-01,CNY,-10.00,快捷支付,微信转账
        2025-12-01,CNY,-10.00,银联快捷支付,微信转账
        2026-01-01,CNY,-10.00,快捷支付,微信转账
        2026-01-02,CNY,10.00,银联快捷支付,微信转账
        2026-01-03,CNY,10.00,快捷退款,微信转账
        2026-01-04,CNY,-11.00,微信转账,财付通
        2026-01-05,CNY,11.00,微信转账,财付通支付科技有限公司
        2026-01-06,CNY,-12.00,微信转账,微信零钱
        2026-01-07,CNY,-13.00,微信转账,微信
        2026-01-08,CNY,-14.00,微信转账,微信支付
        """
        let data = Data(csv.utf8)
        let preview = try BillImporter.preview(data: data, filename: "合成微信.csv", accountID: ledger.accounts[0].id, ledger: ledger)
        let batch = try BillImporter.commit(preview, data: data, to: &ledger)
        let ids = ledger.entries.map(\.id), before = ledger
        ledger.entries.append(Entry(amount: 1000, nature: .income, accountID: ledger.accounts[1].id, title: "反向证据"))
        var plan = Plan(title: "已有固定支出", amount: 1000, dueDate: Dates.parse("2026-01-01")!, frequency: .monthly)
        plan.accountID = ledger.accounts[0].id; ledger.plans.append(plan)
        let estimate = try ImportOrganizer.requestEstimate(ledger: ledger, entryIDs: ids)
        XCTAssertEqual(estimate.localWeChatEntries, 10); XCTAssertEqual(estimate.localRepaymentEntries, 0)
        XCTAssertEqual(estimate.requests, 0)
        let organizer = ImportOrganizer { _ in
            XCTFail("bank WeChat rules must not create any transport, including comments")
            throw YubaiError.invalid("离线")
        }
        let result = try await organizer.organize(ledger: ledger, entryIDs: ids)
        _ = try result.changeSet.apply(to: &ledger)
        let rows = ledger.entries.filter { $0.batchID == batch.id }
        XCTAssertEqual(rows.filter { $0.nature == .expense && $0.category == "其他支出" && $0.purpose == "微信" }.count, 7)
        XCTAssertEqual(rows.filter { $0.nature == .income && $0.category == "其他收入" && $0.purpose == "微信提现" }.count, 2)
        XCTAssertTrue(rows.allSatisfy { $0.otherAccountID == nil && $0.planID == nil && $0.relatedEntryID == nil })
        XCTAssertEqual(rows.map(\.amount), before.entries.map(\.amount))
        XCTAssertEqual(rows.map(\.date), before.entries.map(\.date))
        XCTAssertEqual(rows.map(\.accountID), before.entries.map(\.accountID))
        XCTAssertEqual(rows.map(\.title), before.entries.map(\.title)); XCTAssertEqual(rows.map(\.note), before.entries.map(\.note))
        XCTAssertEqual(ledger.accounts, before.accounts); XCTAssertEqual(ledger.plans.count, 1)
        XCTAssertTrue(result.questions.isEmpty); XCTAssertTrue((result.comments ?? []).isEmpty)
    }
    func testWeChatRuleDoesNotMatchPersonalTransfersRedPacketsOrAlipayTopUps() async throws {
        let titles = ["张三 · 微信转账", "微信转账李明 · 快捷支付", "李明（财付通） · 微信转账",
                      "财付通 · 快捷支付", "财付通 · 微信红包", "微信红包 · 快捷支付", "企业微信红包 · 快捷退款",
                      "支付宝 · 充值", "支付宝充值 · 快捷支付", "微信零钱通 · 微信转账", "微信零钱 · 红包"]
        var (ledger, _) = partyImport(counts: Array(repeating: 1, count: titles.count))
        for i in titles.indices { ledger.entries[i].title = titles[i] }
        let before = ledger.entries
        let estimate = try ImportOrganizer.requestEstimate(ledger: ledger, entryIDs: before.map(\.id))
        XCTAssertEqual(estimate.localWeChatEntries, 0)
        let script = ScriptedChatTransport(Array(repeating: jsonReply(#"{"groups":[]}"#), count: 2))
        let result = try await ImportOrganizer(transport: script).organize(ledger: ledger, entryIDs: before.map(\.id))
        _ = try result.changeSet.apply(to: &ledger)
        XCTAssertEqual(ledger.entries.map(\.nature), before.map(\.nature))
        XCTAssertEqual(ledger.entries.map(\.purpose), before.map(\.purpose))
        for i in [0, 1, 2, 3, 7, 8, 9] { XCTAssertEqual(ledger.entries[i], before[i]) }
        // Existing keyword classification of red packets remains in force.
        for i in [4, 5, 6, 10] { XCTAssertEqual(ledger.entries[i].category, "人情家庭") }
        let requests = await script.recorded(); XCTAssertEqual(requests.map(\.purpose), ["导入整理·按对方", "导入整理·按对方"])
        XCTAssertEqual(Set(result.questions.flatMap(\.entryIDs)), Set(ledger.entries.filter(Classification.isPending).map(\.id)))
    }
    func testWeChatRulePreservesEditedLinkedNonBankAndExistingCategoryRecords() async throws {
        var (ledger, _) = partyImport(counts: [7])
        ledger.accounts.append(Account(name: "现金", kind: .cash))
        for i in ledger.entries.indices { ledger.entries[i].title = "微信转账 · 快捷支付" }
        ledger.entries[0].userEdited = true
        ledger.entries[1].nature = .transfer; ledger.entries[1].otherAccountID = ledger.accounts[1].id
        let plan = Plan(title: "既有计划", amount: 588, dueDate: Date(), frequency: .monthly)
        ledger.plans.append(plan); ledger.entries[2].nature = .expense
        ledger.entries[2].planID = plan.id; ledger.entries[2].occurrence = plan.dueDate
        ledger.entries[3].accountID = ledger.accounts[1].id
        ledger.entries[4].category = "购物"
        ledger.entries[5].nature = .refund; ledger.entries[5].relatedEntryID = ledger.entries[6].id
        ledger.entries[6].nature = .expense
        try ledger.validate()
        let before = ledger.entries, ids = before.map(\.id)
        let estimate = try ImportOrganizer.requestEstimate(ledger: ledger, entryIDs: ids)
        XCTAssertEqual(estimate.localWeChatEntries, 1)
        let script = ImportScript(entries: ledger.entries) { _ in .object(["groups": .array([]), "rows": .array([])]) }
        let result = try await ImportOrganizer(transport: script).organize(ledger: ledger, entryIDs: ids)
        _ = try result.changeSet.apply(to: &ledger)
        for i in [0, 1, 2, 3, 5, 6] { XCTAssertEqual(ledger.entries[i], before[i]) }
        XCTAssertEqual(ledger.entries[4].category, "购物")
        XCTAssertEqual(ledger.entries[4].nature, .expense); XCTAssertEqual(ledger.entries[4].purpose, "微信")
    }
    func testWeChatRowsNeverAppearInModelContextAndCannotBePairedByModel() async throws {
        var (ledger, _) = partyImport(counts: [2, 1])
        for i in 0..<2 { ledger.entries[i].title = "微信转账 · 快捷支付" }
        ledger.entries[1].nature = .unknownIn
        // This wallet expense would create a short-comment candidate if leaked.
        ledger.profile.restrain = [ProfileArea(title: "合成领域", match: AreaMatch(keywords: ["微信"]))]
        // Force the other target down the individual path with a real plan candidate.
        ledger.plans.append(Plan(title: "合成候选", amount: ledger.entries[2].amount, dueDate: Date(), frequency: .monthly))
        let walletIDs = Set(ledger.entries.prefix(2).map(\.id)), otherID = ledger.entries[2].id
        let script = ImportScript(entries: ledger.entries) { request in
            XCTAssertEqual(request.purpose, "导入整理")
            let text = request.messages.last!.content!, payload = try JSONValue.parse(text)
            for id in walletIDs { XCTAssertFalse(text.contains(id.uuidString)) }
            XCTAssertFalse(text.contains("微信转账")); XCTAssertFalse(text.contains("微信提现"))
            XCTAssertEqual(payload["batch"]?.arrayValue?.count, 1); XCTAssertEqual(payload["context"]?.arrayValue?.count, 0)
            return .object(["rows": .array([]), "items": .array(walletIDs.map { .object([
                "kind": .string("pair_transfer"), "entry": .string(otherID.uuidString), "other_entry": .string($0.uuidString), "nature": .string("transfer")
            ]) })])
        }
        let result = try await ImportOrganizer(transport: script).organize(ledger: ledger, entryIDs: ledger.entries.map(\.id))
        _ = try result.changeSet.apply(to: &ledger)
        XCTAssertTrue(ledger.entries.prefix(2).allSatisfy { $0.otherAccountID == nil && !Classification.isPending($0) })
        XCTAssertEqual(Set(result.questions.flatMap(\.entryIDs)), [otherID])
        let sent = await script.count(); XCTAssertEqual(sent, 1)
    }
    func testWeChatCheckpointSurvivesFailureResumesWithoutResendingAndUndoes() async throws {
        var (ledger, batch) = partyImport(counts: [2, 1])
        for i in 0..<2 { ledger.entries[i].title = "微信转账 · 快捷支付" }
        ledger.entries[1].nature = .unknownIn
        let localIDs = Set(ledger.entries.prefix(2).map(\.id))
        let store = ImportCheckpointStore(ledger, batchID: batch.id)
        let bad = ScriptedChatTransport([jsonReply("bad json")])
        let failure = try await resume(store, script: bad, batchID: batch.id)
        XCTAssertEqual(failure.failedChunks?.first?.reason, "整理返回格式无效")
        let saved = await store.snapshot()
        XCTAssertEqual(Set(saved.imports[0].organizedEntryIDs ?? []), localIDs)
        XCTAssertEqual(saved.entries[0].purpose, "微信"); XCTAssertEqual(saved.entries[1].purpose, "微信提现")
        XCTAssertEqual(saved.entries[0].category, "其他支出"); XCTAssertEqual(saved.entries[1].category, "其他收入")
        XCTAssertTrue(saved.imports[0].organization!.questions.isEmpty)
        let estimate = try ImportOrganizer.requestEstimate(ledger: saved, entryIDs: ledger.entries.map(\.id))
        XCTAssertEqual(estimate.localWeChatEntries, 0); XCTAssertEqual(estimate.partyEntries, 1)
        let retry = ScriptedChatTransport([jsonReply(#"{"groups":[]}"#)])
        try await resume(store, script: retry, batchID: batch.id)
        let requests = await retry.recorded()
        XCTAssertEqual(requests.count, 1)
        let text = requests[0].messages.last!.content!
        XCTAssertFalse(text.contains("微信转账")); XCTAssertFalse(text.contains("微信提现"))
        let finished = await store.snapshot()
        XCTAssertFalse(finished.imports[0].needsOrganization!)
        XCTAssertTrue(Set(finished.imports[0].organization!.questions.flatMap(\.entryIDs)).isDisjoint(with: localIDs))
        await store.undo()
        let undone = await store.snapshot()
        XCTAssertTrue(undone.entries.isEmpty); XCTAssertTrue(undone.imports.isEmpty)
        XCTAssertEqual(undone.accounts, ledger.accounts)
    }
    func testMixedPersonalGroupOnlyRepaymentRowsAreLocalAndSurviveFailureResume() async throws {
        var (ledger, batch) = partyImport(counts: [4])
        for i in ledger.entries.indices { ledger.entries[i].title = "李明 · " + (i < 2 ? "掌上生活还款" : "消费") }
        let store = ImportCheckpointStore(ledger, batchID: batch.id)
        let bad = ScriptedChatTransport([jsonReply("bad json")])
        let failure = try await resume(store, script: bad, batchID: batch.id)
        XCTAssertEqual(failure.failedChunks?.first?.reason, "整理返回格式无效")
        let saved = await store.snapshot()
        XCTAssertEqual(Set(saved.imports[0].organizedEntryIDs ?? []), Set(ledger.entries.prefix(2).map(\.id)))
        XCTAssertTrue(saved.entries.prefix(2).allSatisfy { $0.nature == .repayment })
        XCTAssertTrue(saved.entries.suffix(2).allSatisfy { $0.nature == .unknownOut })
        let retry = ScriptedChatTransport([jsonReply(#"{"groups":[]}"#)])
        try await resume(store, script: retry, batchID: batch.id)
        let requests = await retry.recorded()
        let groups = try JSONValue.parse(requests[0].messages.last!.content!)["groups"]!.arrayValue!
        XCTAssertEqual(groups.first?["count"], .number(2))
        let finished = await store.snapshot(); XCTAssertFalse(finished.imports[0].needsOrganization!)
        await store.undo()
        let undone = await store.snapshot(); XCTAssertTrue(undone.entries.isEmpty); XCTAssertTrue(undone.imports.isEmpty)
    }
    func testMonthlyRepaymentsKeepIndividualSeriesAndRejectModelExpenseOverride() async throws {
        var (ledger, _) = partyImport(counts: [3])
        for i in ledger.entries.indices {
            ledger.entries[i].title = "李明 · 信用卡"
            ledger.entries[i].date = Dates.addMonths(i, to: Dates.parse("2026-01-15")!)
        }
        let ids = ledger.entries.map(\.id)
        let script = ImportScript(entries: ledger.entries) { request in
            let payload = try JSONValue.parse(request.messages.last!.content!)
            let rows = try XCTUnwrap(payload["batch"]?.arrayValue)
            XCTAssertTrue(rows.allSatisfy { $0["nature"] == .string("repayment") })
            return .object(["rows": .array(rows.map { .object(["entry": $0["id"]!, "nature": .string("expense"),
                "purpose": .string("转给李明"), "confident": .bool(true)]) }), "items": .array([
                    .object(["kind": .string("set_nature"), "entry": .string(ids[0].uuidString), "nature": .string("expense")])
                ]), "series": .array([.object(["entry_ids": .strings(ids.map(\.uuidString)),
                    "frequency": .string("monthly"), "title": .string("信用卡还款")])])])
        }
        let result = try await ImportOrganizer(transport: script).organize(ledger: ledger, entryIDs: ids)
        _ = try result.changeSet.apply(to: &ledger)
        XCTAssertTrue(ledger.entries.allSatisfy { $0.nature == .repayment && $0.purpose == "还款" && $0.planID != nil })
        XCTAssertEqual(result.recurringCount, 1); XCTAssertTrue(result.questions.isEmpty)
    }
    func testSameAmountOppositeDirectionInSameAccountIsNotTransferCandidate() async throws {
        var (ledger, _) = partyImport(counts: [1, 1])
        ledger.entries[1].nature = .unknownIn; ledger.entries[1].amount = ledger.entries[0].amount
        let estimate = try ImportOrganizer.requestEstimate(ledger: ledger, entryIDs: ledger.entries.map(\.id))
        XCTAssertEqual(estimate.partyGroups, 2); XCTAssertEqual(estimate.individualRequests, 0)
    }
    func testRequestEstimateMatchesActualChunksBudgetsAndCompletedRemainder() async throws {
        var (ledger, _) = partyImport(counts: Array(repeating: 1, count: 65))
        ledger.entries[0].title = "李明 · 花呗"
        let all = ledger.entries.map(\.id)
        ledger.imports[0].organizedEntryIDs = Set(all.suffix(2))
        let estimate = try ImportOrganizer.requestEstimate(ledger: ledger, entryIDs: all)
        XCTAssertEqual(estimate.localRepaymentEntries, 1)
        XCTAssertEqual(estimate.partyGroups, 62); XCTAssertEqual(estimate.partyEntries, 62)
        XCTAssertEqual(estimate.individualRequests, 0); XCTAssertGreaterThan(estimate.partyRequests, 1)
        let script = ImportScript(entries: ledger.entries) { request in
            XCTAssertEqual(request.purpose, "导入整理·按对方")
            let payload = try JSONValue.parse(request.messages.last!.content!)
            let count = payload["groups"]!.arrayValue!.count
            XCTAssertLessThanOrEqual(request.maxTokens, 2000)
            XCTAssertEqual(request.maxTokens, 192 + count * 224)
            XCTAssertLessThanOrEqual(count, 8)
            let bytes = request.messages.compactMap(\.content).reduce(0) { $0 + $1.utf8.count }
            XCTAssertLessThanOrEqual((bytes + 1) / 2, 12_000)
            return .object(["groups": .array([])])
        }
        _ = try await ImportOrganizer(transport: script).organize(ledger: ledger, entryIDs: all)
        let sent = await script.count(); XCTAssertEqual(estimate.requests, sent)
        XCTAssertEqual(try ImportOrganizer.requestEstimate(ledger: ledger, entryIDs: []).requests, 0)
    }

    func testPersonPartyUsesOtherExpenseAndTransferPurpose() async throws {
        var (ledger, _) = partyImport(counts: [3])
        for i in ledger.entries.indices { ledger.entries[i].title = "李明 · 转账" }
        let script = ImportScript(entries: ledger.entries) { request in
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
            XCTAssertTrue(prompt.contains("绝不向用户提问")); XCTAssertTrue(prompt.contains("不输出questions"))
            XCTAssertFalse(prompt.contains("\"questions\":"))
            XCTAssertTrue(prompt.contains("转给<对方>")); XCTAssertTrue(prompt.contains("来自<对方>"))
            XCTAssertTrue(prompt.contains("其他支出")); XCTAssertTrue(prompt.contains("其他收入"))
        }
    }
    func testLegacyQuestionsCannotSuppressConfidentIndividualIncome() async throws {
        var (ledger, _) = partyImport(counts: [1])
        ledger.entries[0].nature = .unknownIn; ledger.entries[0].title = "李明 · 来款"
        individualCandidates(in: &ledger)
        let id = ledger.entries[0].id
        let script = ImportScript(entries: ledger.entries) { _ in .object([
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
        XCTAssertEqual(request.maxTokens, 192 + 224); XCTAssertEqual(request.timeout, 45)
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
        ledger.entries[3].amount = 590
        let script = ScriptedChatTransport([jsonReply(#"{"groups":[],"questions":[{"group":"g0","text":"旧组问题"},{"entry_ids":[],"text":"旧逐笔问题"}]}"#)])
        let result = try await ImportOrganizer(transport: script).organize(ledger: ledger, entryIDs: ledger.entries.map(\.id))
        XCTAssertEqual(result.questions.count, 1); XCTAssertEqual(Set(result.questions[0].entryIDs), Set(ledger.entries.map(\.id)))
        XCTAssertTrue(result.questions[0].isFallback); XCTAssertTrue(result.questions[0].options.isEmpty)
        let requests = await script.recorded()
        XCTAssertEqual(requests.map(\.purpose), ["导入整理·按对方"])
        let groups = try JSONValue.parse(requests[0].messages.last!.content!)["groups"]!.arrayValue!
        XCTAssertEqual(groups.map { $0["count"]! }, [.number(3), .number(1)])
    }
    func testPartyCheckpointCancellationResumeAndRecordProgressNeverResendsGroups() async throws {
        actor ReorderedParties: ChatTransport {
            var requests: [ChatRequest] = []
            func send(_ request: ChatRequest) async throws -> ChatMessage {
                requests.append(request)
                // The first send cannot finish before another request's saved
                // checkpoint cancels it. Exercise completion order on every OS.
                if requests.count == 1 {
                    while true { try await Task.sleep(nanoseconds: 30_000_000_000) }
                }
                return ChatMessage(role: .assistant, content: #"{"groups":[{"group":"g0","category":"餐饮","nature":"expense","confident":true}],"questions":[{"group":"g1","text":"这些是什么用途？","options":[{"title":"日常支出","items":[{"kind":"set_nature","nature":"expense"}]},{"title":"借给别人","items":[{"kind":"set_nature","nature":"lend"}]}]}]}"#)
            }
            func recorded() -> [ChatRequest] { requests }
        }
        let (ledger, batch) = partyImport(counts: Array(repeating: 3, count: 40), singleton: true)
        let store = ImportCheckpointStore(ledger, batchID: batch.id)
        await store.configure(cancel: 1)
        let script = ReorderedParties()
        let task = Task { try await self.resume(store, script: script, batchID: batch.id) }
        do { _ = try await task.value; XCTFail("must stop after saved groups") } catch { XCTAssertTrue(error is CancellationError) }
        let partial = await store.snapshot(), sent = await script.recorded()
        let savedIDs = Set(try XCTUnwrap(partial.imports[0].organizedEntryIDs))
        let savedEntries = ledger.entries.filter { savedIDs.contains($0.id) }
        let names = Set(savedEntries.map(UnsortedGroups.party(for:)))
        let sentGroups = try sent.map { try XCTUnwrap(JSONValue.parse($0.messages.last!.content!)["groups"]?.arrayValue) }
        let firstGroups = try XCTUnwrap(sentGroups.first { groups in
            Set(groups.compactMap { $0["party"]?.stringValue }) == names
        })
        XCTAssertFalse(names.isEmpty)
        XCTAssertTrue(names.isDisjoint(with: sentGroups[0].compactMap { $0["party"]?.stringValue }), "The first send was cancelled, not checkpointed")
        let completed = firstGroups.reduce(0) { sum, group in sum + Int(group["count"]!.numberForTest) }
        XCTAssertEqual(Set(savedEntries.map(\.id)), savedIDs)
        XCTAssertEqual(firstGroups.count, 8); XCTAssertLessThan(firstGroups.count, 40)
        XCTAssertEqual(partial.imports[0].organizedEntryIDs?.count, completed)
        XCTAssertEqual(partial.imports[0].organization?.categoryCount, 3)
        XCTAssertEqual(partial.imports[0].organization?.questions.filter { !$0.isFallback }.count, 0)
        XCTAssertEqual(PendingImportOrganization(in: partial).count, 121 - completed)
        XCTAssertEqual(ImportOrganizationProgress(completed: completed, total: 121).completed, completed)
        let retry = ScriptedChatTransport(Array(repeating: jsonReply(#"{"groups":[]}"#), count: 5))
        await store.configure()
        let snapshot = await store.snapshot()
        _ = try await ImportOrganizer(transport: retry).organize(ledger: snapshot, entryIDs: ImportOrganizer.pendingEntryIDs(in: snapshot, batchID: batch.id)) { result, ids, before in
            let saved = try await store.save(result, ids: ids, before: before)
            let totalCompleted = saved.imports[0].organizedEntryIDs!.count
            XCTAssertGreaterThan(totalCompleted, completed)
            return saved
        }
        let retried = await retry.recorded(), complete = await store.snapshot()
        let remainingGroups = try retried.filter { $0.purpose == "导入整理·按对方" }.flatMap {
            try XCTUnwrap(JSONValue.parse($0.messages.last!.content!)["groups"]?.arrayValue)
        }
        XCTAssertTrue(names.isDisjoint(with: remainingGroups.compactMap { $0["party"]?.stringValue }))
        let remainingNames = Set(ledger.entries.filter { !savedIDs.contains($0.id) }.map(UnsortedGroups.party(for:)))
        XCTAssertEqual(remainingGroups.compactMap { $0["party"]?.stringValue }.count, remainingNames.count)
        XCTAssertEqual(Set(remainingGroups.compactMap { $0["party"]?.stringValue }), remainingNames)
        XCTAssertEqual(complete.imports[0].organizedEntryIDs?.count, 121); XCTAssertEqual(complete.imports[0].needsOrganization, false)
        XCTAssertEqual(complete.imports[0].organization?.questions.count, 1, "Only local fallbacks merge across stages and resume")
        XCTAssertTrue(complete.imports[0].organization?.questions.allSatisfy(\.isFallback) == true)
    }
    func testPartyModelCanDeferToIndividualEvidenceWithoutCompletingIDsEarly() async throws {
        let (ledger, batch) = partyImport(counts: [2, 1])
        let store = ImportCheckpointStore(ledger, batchID: batch.id)
        let script = ScriptedChatTransport([
            jsonReply(#"{"groups":[{"group":"g0","needs_individual":true},{"group":"g1","needs_individual":true}]}"#),
            jsonReply(#"{"rows":[]}"#)
        ])
        try await resume(store, script: script, batchID: batch.id)
        let requests = await script.recorded(), saved = await store.snapshot()
        XCTAssertEqual(requests.map(\.purpose), ["导入整理·按对方", "导入整理"])
        let checkpoints = await store.checkpoints
        XCTAssertEqual(checkpoints, 1)
        XCTAssertEqual(Set(saved.imports[0].organizedEntryIDs ?? []), Set(ledger.entries.map(\.id)))
        let rows = try JSONValue.parse(ImportWireFixture(requests[1], entries: ledger.entries).request.messages.last!.content!)["batch"]!.arrayValue!
        XCTAssertEqual(Set(rows.compactMap { $0["id"]?.stringValue }), Set(ledger.entries.map { $0.id.uuidString }))
    }
    func testAssociationCandidatesStayIndividualWhileSmallGroupsUseSummaries() async throws {
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
        let script = ScriptedChatTransport([jsonReply(#"{"groups":[]}"#), jsonReply(#"{"rows":[]}"#), jsonReply(#"{"rows":[]}"#)])
        _ = try await ImportOrganizer(transport: script).organize(ledger: ledger, entryIDs: targets)
        let requests = await script.recorded()
        XCTAssertEqual(requests.map(\.purpose), ["导入整理·按对方", "导入整理", "导入整理"])
        let groups = try JSONValue.parse(requests[0].messages.last!.content!)["groups"]!.arrayValue!
        XCTAssertEqual(groups.map { $0["count"]! }, [.number(2), .number(2)])
        let groupedIDs = Set(ledger.entries[15..<17].map(\.id) + ledger.entries[18..<20].map(\.id))
        let rows = try requests.dropFirst().flatMap { request in
            try JSONValue.parse(ImportWireFixture(request, entries: ledger.entries).request.messages.last!.content!)["batch"]!.arrayValue!
        }
        XCTAssertEqual(Set(rows.compactMap { $0["id"]?.stringValue }), Set(targets.filter { !groupedIDs.contains($0) }.map(\.uuidString)))
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
        individualCandidates(in: &ledger)
        let entry = ledger.entries[0]
        let result = JSONValue.object(["rows": .array([.object(["entry": .string("r0"), "category": .string("日用购物"), "nature": .string("expense"), "confident": .bool(true)])]),
            "items": .array([.object(["kind": .string("set_category"), "entry": .string("r0"), "category": .string("娱乐旅行")])])])
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
        individualCandidates(in: &ledger)
        let id = "r0"
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
        let transport = ImportScript(entries: ledger.entries) { _ in .object(["rows": .array([.object([
            "entry": .string(id.uuidString), "category": .string("交通"), "confident": .bool(true),
            "nature": .string("expense"), "purpose": .string("周末车票")])])]) }
        let organization = try await ImportOrganizer(transport: transport).organize(ledger: ledger, entryIDs: [id])
        _ = try organization.changeSet.apply(to: &ledger)
        XCTAssertEqual(ledger.entries.first?.category, "其他支出")
        XCTAssertEqual(ledger.entries.first?.purpose, "周末车票")
    }
}

/// Explicit existing-plan candidates keep tests of the row protocol on that path.
private func individualCandidates(in ledger: inout Ledger) {
    for entry in ledger.entries {
        var plan = Plan(title: "合成关联候选", amount: entry.amount, dueDate: Dates.parse("2040-01-01")!, inflow: entry.nature.inflow)
        plan.accountID = entry.accountID; ledger.plans.append(plan)
    }
}

/// Adapts older semantic fixtures to the new wire names. Production still sees
/// and parses only rN/cN; the assertions can keep referring to stable fixture UUIDs.
private struct ImportWireFixture {
    var request: ChatRequest
    var toShort: [String: String] = [:]
    init(_ input: ChatRequest, entries: [Entry]) throws {
        request = input
        guard !entries.isEmpty, let text = input.messages.last?.content,
              var payload = try JSONValue.parse(text).objectValue else { return }
        var dates: [Date: String] = [:]
        let pairs = entries.map { entry -> (String, Entry) in
            let date = dates[entry.date] ?? Dates.text(entry.date, time: true)
            dates[entry.date] = date
            return (entry.title + "|" + date + "|" + String(entry.amount) + "|" + entry.accountID.uuidString, entry)
        }
        let lookup = Dictionary(grouping: pairs, by: { $0.0 }).mapValues { $0.map { $0.1 } }
        var used: Set<UUID> = []
        for key in ["batch", "context"] {
            guard let rows = payload[key]?.arrayValue else { continue }
            payload[key] = .array(rows.map { row in
                guard var fields = row.objectValue, let short = fields["id"]?.stringValue else { return row }
                let title = fields["title"]?.stringValue ?? ""
                let date = fields["date"]?.stringValue ?? ""
                let amount = String(Int64(fields["amount"]?["cents"]?.numberForTest ?? -1))
                let account = fields["account"]?.stringValue ?? ""
                let candidates = lookup[[title, date, amount, account].joined(separator: "|")] ?? []
                guard let e = candidates.first(where: { !used.contains($0.id) && (key != "batch" || $0.batchID != nil) }) ?? candidates.first(where: { !used.contains($0.id) }) else { return row }
                used.insert(e.id)
                toShort[e.id.uuidString] = short; fields["id"] = .string(e.id.uuidString)
                return .object(fields)
            })
        }
        request.messages[request.messages.count - 1].content = try JSONValue.object(payload).jsonText()
    }
    func encode(_ output: JSONValue) -> JSONValue {
        switch output {
        case .string(let text): return .string(toShort[text] ?? text)
        case .array(let values): return .array(values.map(encode))
        case .object(let fields): return .object(fields.mapValues(encode))
        default: return output
        }
    }
}

private actor SpeedTransport: ChatTransport {
    var active = 0, peak = 0, sent = 0, cancelled = 0
    var firstReleased = false
    var remainingReleased = false
    func releaseRemaining() { remainingReleased = true }
    func releaseFirst() { firstReleased = true }
    let holding: Bool
    init(holding: Bool = false) { self.holding = holding }
    func stats() -> (Int, Int, Int) { (peak, sent, cancelled) }
    func send(_ request: ChatRequest) async throws -> ChatMessage {
        if request.purpose == "导入短评" { return ChatMessage(role: .assistant, content: #"{"cards":[]}"#) }
        let number = sent; sent += 1; active += 1; peak = max(peak, active)
        defer { active -= 1 }
        do {
            if number == 0 && !holding {
                while !firstReleased { try await Task.sleep(nanoseconds: 1_000_000) }
            } else {
                let initial = request.purpose == "导入整理·按对方" ? 4 : 2
                while !holding && (sent < initial || (number > 1 && !remainingReleased)) { try await Task.sleep(nanoseconds: 1_000_000) }
                try await Task.sleep(nanoseconds: holding ? 30_000_000_000 : 10_000_000)
            }
        }
        catch { cancelled += 1; throw error }
        let payload = try JSONValue.parse(request.messages.last!.content!)
        let party = payload["groups"]?.arrayValue != nil
        let input = payload[party ? "groups" : "batch"]!.arrayValue!
        let rows = input.map { JSONValue.object([party ? "group" : "entry": $0["id"]!, "cat": .string("餐饮"),
            "nature": .string("expense"), "purpose": .string("req\(number)"), "ok": .bool(true)]) }
        return ChatMessage(role: .assistant, content: try JSONValue.object([party ? "groups" : "rows": .array(rows)]).jsonText())
    }
}
private actor SpeedCheckpointOrder {
    var purposes: [String] = []
    func append(_ result: ImportOrganization) {
        if let text = result.changeSet.items.compactMap({ item -> String? in if case .setPurpose(_, let text) = item { return text }; return nil }).first { purposes.append(text) }
    }
}
extension ImportOrganizerTests {
    func testShortReferencesResolveRowsRelationsSeriesAndRejectForgedNames() throws {
        let a = UUID(), b = UUID(), c = UUID()
        let refs = ImportOrganizer.EntryReferences(batch: [a, b], context: [c])
        XCTAssertEqual(refs.names[a], "r0"); XCTAssertEqual(refs.names[b], "r1"); XCTAssertEqual(refs.names[c], "c0")
        let value = refs.decode(.object(["entry": .string("r1"), "other_entry": .string("c0"), "cat": .string("餐饮"), "ok": .bool(true)]))
        XCTAssertEqual(value?["entry"], .string(b.uuidString)); XCTAssertEqual(value?["other_entry"], .string(c.uuidString))
        XCTAssertEqual(value?["category"], .string("餐饮")); XCTAssertEqual(value?["confident"], .bool(true))
        let series = refs.decode(.object(["entries": .strings(["r0", "r1", "c0"])]), series: true)
        XCTAssertEqual(series?["entry_ids"], .strings([a, b, c].map(\.uuidString)))
        for bad in ["r2", "c1", "r-1", "r00", "R0", "r0 ", a.uuidString, "0", ""] {
            XCTAssertNil(refs.decode(.object(["entry": .string(bad)])), bad)
            XCTAssertNil(refs.decode(.object(["entry": .string("r0"), "other_entry": .string(bad)])), bad)
            XCTAssertNil(refs.decode(.object(["entries": .strings(["r0", bad, "c0"])]), series: true), bad)
        }
    }
    func testShortWireInvalidRowsAreSkippedWithoutLosingValidRows() async throws {
        let (_, ledger, _) = try syntheticImport(count: 2)
        let script = ImportScript { request in
            let input = try JSONValue.parse(request.messages.last!.content!)
            XCTAssertEqual(input["batch"]?.arrayValue?.map { $0["id"]! }, [.string("r0"), .string("r1")])
            XCTAssertFalse(request.messages.last!.content!.contains(ledger.entries[0].id.uuidString))
            return .object(["rows": .array([
                .object(["entry": .string("r0"), "cat": .string("餐饮"), "ok": .bool(true)]),
                .object(["entry": .string("r99"), "cat": .string("餐饮"), "ok": .bool(true)]),
                .object(["entry": .string("r-1"), "cat": .string("餐饮"), "ok": .bool(true)])
            ])])
        }
        let result = try await ImportOrganizer(transport: script).organize(ledger: ledger, entryIDs: ledger.entries.map(\.id))
        XCTAssertEqual(result.categoryCount, 1); XCTAssertEqual(result.skipped, ["已跳过未知记录的整理×2"])
        XCTAssertEqual(result.diagnosticCounts?["已跳过未知记录的整理"], 2)
        XCTAssertEqual(result.questions.flatMap(\.entryIDs), [ledger.entries[1].id])
    }
    func testParallelLimitsAndCompletionOrderForBothPhases() async throws {
        for byParty in [true, false] {
            let ledger = byParty ? partyImport(counts: Array(repeating: 1, count: 40)).0 : try syntheticImport(count: 75).1
            let script = SpeedTransport(), order = SpeedCheckpointOrder()
            _ = try await ImportOrganizer(transport: script).organize(ledger: ledger, entryIDs: ledger.entries.map(\.id)) { result, ids, before in
                await order.append(result)
                if await order.purposes.count == 1 { await script.releaseRemaining() }
                if await order.purposes.count == 4 { await script.releaseFirst() }
                return try result.preparingCheckpoint(entryIDs: ids, snapshot: before, current: before).ledger
            }
            let stats = await script.stats(), purposes = await order.purposes
            XCTAssertEqual(stats.0, byParty ? 4 : 2)
            XCTAssertEqual(stats.1, 5); XCTAssertEqual(stats.2, 0)
            XCTAssertEqual(purposes.first, "req1"); XCTAssertEqual(purposes.last, "req0")
            XCTAssertEqual(Set(purposes), Set((0..<5).map { "req\($0)" }))
        }
    }
    func testStopCancelsEveryInFlightRequestInBothPhases() async throws {
        for byParty in [true, false] {
            let ledger = byParty ? partyImport(counts: Array(repeating: 1, count: 40)).0 : try syntheticImport(count: 75).1
            let script = SpeedTransport(holding: true), limit = byParty ? 4 : 2
            let run = Task { try await ImportOrganizer(transport: script).organize(ledger: ledger, entryIDs: ledger.entries.map(\.id)) }
            for _ in 0..<1000 {
                if await script.stats().1 == limit { break }
                try await Task.sleep(nanoseconds: 1_000_000)
            }
            let start = Date(); run.cancel()
            do { _ = try await run.value; XCTFail("must cancel") } catch { XCTAssertTrue(error is CancellationError) }
            XCTAssertLessThan(Date().timeIntervalSince(start), 0.5)
            let stats = await script.stats()
            XCTAssertEqual(stats.0, limit); XCTAssertEqual(stats.1, limit); XCTAssertEqual(stats.2, limit)
        }
    }
    func testCheckpointSkipsOnlyEditedTargetsAndChangedEvidence() throws {
        let (_, snapshot, batch) = try syntheticImport(count: 4)
        let ids = snapshot.entries.map(\.id)
        let result = ImportOrganization(changeSet: ChangeSet(source: "导入整理", reason: "合成", items: [
            .setCategory(entry: ids[0], category: "餐饮"), .setPurpose(entry: ids[1], text: "午餐"),
            .markDuplicate(entry: ids[2], of: ids[3])
        ]), questions: [], skipped: [])
        var current = snapshot
        current.entries[0].purpose = "用户用途"; current.entries[0].userEdited = true
        current.entries[3].note = "用户改过证据"; current.entries[3].userEdited = true
        current.preferences.dailyLiving += 100
        let prepared = try result.preparingCheckpoint(entryIDs: Array(ids.prefix(3)), snapshot: snapshot, current: current, batchID: batch.id)
        XCTAssertEqual(prepared.ledger.entries[0], current.entries[0]); XCTAssertEqual(prepared.ledger.entries[3], current.entries[3])
        XCTAssertEqual(prepared.ledger.entries[1].purpose, "午餐"); XCTAssertNil(prepared.ledger.entries[2].deletedAt)
        XCTAssertEqual(prepared.ledger.preferences.dailyLiving, current.preferences.dailyLiving)
        XCTAssertEqual(prepared.result.changeSet.items, [.setPurpose(entry: ids[1], text: "午餐")])
        XCTAssertEqual(prepared.result.skipped, [ImportOrganizer.ledgerChangedMessage])
        XCTAssertEqual(Set(prepared.ledger.imports[0].organizedEntryIDs ?? []), Set(ids.prefix(3)))
    }
    func testInvalidSuggestionDoesNotDiscardValidCheckpointRows() throws {
        let (_, snapshot, batch) = try syntheticImport(count: 2)
        let ids = snapshot.entries.map(\.id)
        let result = ImportOrganization(changeSet: ChangeSet(source: "导入整理", reason: "合成", items: [
            .setPurpose(entry: ids[0], text: "午餐"), .setNature(entry: ids[1], nature: .income, otherAccount: nil)
        ]), questions: [], skipped: [])
        let prepared = try result.preparingCheckpoint(entryIDs: ids, snapshot: snapshot, current: snapshot, batchID: batch.id)
        XCTAssertEqual(prepared.ledger.entries[0].purpose, "午餐"); XCTAssertEqual(prepared.ledger.entries[1].nature, snapshot.entries[1].nature)
        XCTAssertEqual(prepared.result.skipped.count, 1); XCTAssertEqual(prepared.result.changeSet.items.count, 1)
    }
    func testHeartbeatAdvancesWithinReservationsAndNeverCompletesUnsavedWork() {
        let id = UUID()
        var progress = ImportOrganizationHeartbeat(progress: .init(completed: 0, total: 100))
        progress.receive(.started(id, entries: 15))
        var last: Int64 = 0
        for _ in 0..<60 {
            progress.tick(); XCTAssertGreaterThan(progress.completedUnits, last); last = progress.completedUnits
            XCTAssertLessThan(progress.completedUnits, 15 * 9_000)
        }
        progress.receive(.finished(id)); XCTAssertEqual(progress.completedUnits, 15 * 9_500)
        progress.update(.init(completed: 15, total: 100)); progress.receive(.checkpointed(id))
        XCTAssertEqual(progress.completedUnits, 15 * 10_000)
        XCTAssertLessThan(progress.completedUnits, progress.totalUnits)
        // Deferral/another request cannot move the system activity backwards.
        let previous = progress.completedUnits; progress.receive(.started(UUID(), entries: 3))
        progress.tick(); XCTAssertGreaterThanOrEqual(progress.completedUnits, previous)
        var final = ImportOrganizationHeartbeat(progress: .init(completed: 100, total: 100))
        final.update(.init(completed: 100, total: 100))
        let wording = UUID(); final.receive(.started(wording, entries: 1))
        let beforeWording = final.completedUnits
        final.tick(); XCTAssertGreaterThan(final.completedUnits, beforeWording)
        XCTAssertLessThan(final.completedUnits, final.totalUnits)
    }
    func testOrganizationFailureCategories() {
        XCTAssertEqual(ImportOrganizer.failureMessage(URLError(.timedOut)), "整理请求网络中断或超时。")
        XCTAssertEqual(ImportOrganizer.failureMessage(DeepSeekError.network), "整理请求网络中断或超时。")
        for status in [400, 401, 403, 404, 429, 503] {
            XCTAssertEqual(ImportOrganizer.failureMessage(DeepSeekError.http(status)), "DeepSeek 返回错误（HTTP \(status)）。")
        }
        XCTAssertEqual(ImportOrganizer.failureMessage(ImportOrganizer.Failure.invalidResponse), "整理返回格式无效。")
        XCTAssertEqual(ImportOrganizer.failureMessage(ImportOrganizer.Failure.backgroundExpired), "系统停止了后台整理。")
        XCTAssertEqual(ImportOrganizer.failureMessage(LedgerSyncError.changed), ImportOrganizer.ledgerChangedMessage)
    }
    func testStorageRejectsStaleCheckpointRevisionAndKeepsManualSave() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("speed-cas-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = LedgerRepository(directory: root)
        let (_, ledger, _) = try syntheticImport(count: 2)
        try repository.save(ledger); let oldRevision = repository.revision
        var manual = ledger; manual.entries[0].purpose = "用户用途"
        try repository.save(manual, requiringUnchanged: true)
        XCTAssertThrowsError(try repository.save(ledger, requiringUnchanged: true, preservingRecovery: false, expectedRevision: oldRevision, markingPendingSync: true)) { XCTAssertTrue($0 is LedgerSyncError) }
        XCTAssertEqual(try repository.load().entries[0].purpose, "用户用途")
        XCTAssertFalse(repository.hasPendingSync)
        try repository.save(manual, requiringUnchanged: true, preservingRecovery: false, expectedRevision: repository.revision, markingPendingSync: true)
        XCTAssertTrue(repository.hasPendingSync)
    }
}

extension ImportOrganizerTests {
    func testManualEditBeforeQueuedSegmentStartsIsNotSentOrOverwritten() async throws {
        let (_, ledger, batch) = try syntheticImport(count: 75)
        let editedID = ledger.entries[30].id
        let store = ImportCheckpointStore(ledger, batchID: batch.id)
        let script = ResumableImportScript(entries: ledger.entries)
        _ = try await ImportOrganizer(snapshotForNextRequest: { await store.snapshot() }, transportForSnapshot: { _ in script }).organize(ledger: ledger, entryIDs: ledger.entries.map(\.id)) { result, ids, before in
            let savedBeforeManualEdit = try await store.save(result, ids: ids, before: before)
            if await store.checkpoints == 1 { await store.editEntry(editedID) }
            return savedBeforeManualEdit
        }
        let saved = await store.snapshot(), sent = await script.sentBatches()
        XCTAssertEqual(saved.entries[30].purpose, "用户用途")
        XCTAssertFalse(sent.flatMap { $0 }.contains(editedID))
        XCTAssertEqual(sent.map(\.count).sorted(), [14, 15, 15, 15, 15])
        XCTAssertEqual(saved.entries.filter { $0.category == "餐饮" }.count, 74)
        XCTAssertEqual(saved.imports[0].needsOrganization, false)
        XCTAssertTrue(saved.imports[0].organization?.skipped.contains(ImportOrganizer.ledgerChangedMessage) == true)
    }
}

extension ImportOrganizerTests {
    func testOrganizerCategoryResolverUsesSubcategoriesKeywordsAliasesAndDirection() {
        let resolver = ImportOrganizer.CategoryResolver(ledger: Ledger())
        let cases: [(String, String, String?)] = [
            ("买菜", "购物", "日用百货"), ("日用", "购物", "日用百货"), ("日用百货", "购物", "日用百货"),
            ("话费", "居住", "网费话费"), ("网费话费", "居住", "网费话费"), ("保险", "其他支出", nil),
            ("外卖", "餐饮", "外卖"), ("餐饮/外卖", "餐饮", "外卖"), ("出行", "交通", nil),
            ("超市", "购物", "日用百货"), ("移动话费充值", "居住", "网费话费"), ("火锅", "餐饮", nil)
        ]
        for (label, main, sub) in cases {
            XCTAssertEqual(resolver.resolve(label, income: false), .init(category: main, subcategory: sub), label)
        }
        XCTAssertEqual(resolver.resolve("人情家庭", income: true)?.category, "礼金赠与")
        XCTAssertEqual(resolver.resolve("餐饮", income: true, evidence: "微信红包")?.category, "礼金赠与")
        XCTAssertEqual(resolver.resolve("餐饮", income: true)?.category, "其他收入")
        XCTAssertEqual(resolver.resolve("工资奖金", income: false)?.category, "其他支出")
        XCTAssertEqual(resolver.resolve("工资", income: false)?.category, "其他支出")
        XCTAssertEqual(resolver.resolve("利息", income: true)?.category, "投资收益")
        XCTAssertEqual(resolver.resolve("利息", income: false)?.category, "利息手续费")
        XCTAssertNil(resolver.resolve("不存在的分类", income: false))
    }
    func testOrganizerCategoryResolverRejectsAmbiguityAndHiddenCategoriesAndHonorsRenames() throws {
        var ledger = Ledger()
        ledger.categories.append(Category("自定义甲", subcategories: ["共同小项"], keywords: ["唯一主项"], subcategoryKeywords: ["共同小项": ["共同关键词"]]))
        ledger.categories.append(Category("自定义乙", subcategories: ["共同小项"], subcategoryKeywords: ["共同小项": ["共同关键词"]]))
        var resolver = ImportOrganizer.CategoryResolver(ledger: ledger)
        XCTAssertNil(resolver.resolve("共同小项", income: false)); XCTAssertNil(resolver.resolve("共同关键词", income: false))
        XCTAssertEqual(resolver.resolve("唯一主项", income: false)?.category, "自定义甲")
        try CategoryModel.rename("购物", to: "生活采购", in: &ledger)
        resolver = .init(ledger: ledger)
        XCTAssertEqual(resolver.resolve("买菜", income: false)?.category, "生活采购")
        try CategoryModel.setHidden(true, category: "生活采购", in: &ledger)
        resolver = .init(ledger: ledger)
        XCTAssertNil(resolver.resolve("买菜", income: false)); XCTAssertNil(resolver.resolve("日用百货", income: false))
    }
    func testBothOrganizerPromptsOnlyUseAvailableMainExamplesAndExposeSubcategories() async throws {
        var (ledger, _) = partyImport(counts: [1, 1])
        try CategoryModel.rename("餐饮", to: "吃喝", in: &ledger)
        try CategoryModel.setHidden(true, category: "购物", in: &ledger)
        let system = ImportOrganizer.prompt(for: ledger, byParty: true)
        XCTAssertTrue(system.contains("美团/饿了么→吃喝/外卖"))
        XCTAssertFalse(system.contains("→买菜")); XCTAssertFalse(system.contains("→日用"))
        XCTAssertFalse(system.contains("→保险")); XCTAssertFalse(system.contains("→话费"))
        XCTAssertFalse(system.contains("购物/日用百货")); XCTAssertFalse(system.contains("$"))
        XCTAssertTrue(system.contains("进账选礼金赠与")); XCTAssertTrue(system.contains("进账不可使用支出分类"))
        XCTAssertTrue(system.contains("只能取categories中的name"))
        let script = ImportScript { request in
            let payload = try JSONValue.parse(request.messages.last!.content!)
            let categories = try XCTUnwrap(payload["categories"]?.arrayValue)
            XCTAssertTrue(categories.allSatisfy { $0["subcategories"]?.arrayValue != nil })
            XCTAssertFalse(categories.contains { $0["name"] == .string("购物") })
            XCTAssertEqual(categories.first { $0["name"] == .string("吃喝") }?["subcategories"], .strings(["早餐", "午餐", "晚餐", "外卖", "咖啡饮品", "零食水果", "聚餐"]))
            return .object(["groups": .array([]), "rows": .array([])])
        }
        _ = try await ImportOrganizer(transport: script).organize(ledger: ledger, entryIDs: ledger.entries.map(\.id))
        individualCandidates(in: &ledger)
        _ = try await ImportOrganizer(transport: script).organize(ledger: ledger, entryIDs: ledger.entries.map(\.id))
        let sent = await script.count(); XCTAssertEqual(sent, 2)
    }
    func testLegacyModelCategoryLabelsAreMappedInBothPhasesWithoutSkipping() async throws {
        for party in [true, false] {
            var (ledger, _) = partyImport(counts: Array(repeating: 1, count: 20))
            for index in stride(from: 0, to: ledger.entries.count, by: 4) { ledger.entries[index].nature = .unknownIn }
            if !party { individualCandidates(in: &ledger) }
            let script = ImportScript { request in
                if request.purpose == "导入短评" { return .object(["cards": .array([])]) }
                let payload = try JSONValue.parse(request.messages.last!.content!)
                let rows = payload[party ? "groups" : "batch"]!.arrayValue!
                let labels = ["买菜", "话费", "保险", "外卖", "出行"]
                return .object([party ? "groups" : "rows": .array(rows.enumerated().map { index, row in
                    let income = row["inflow"] == .bool(true)
                    return .object([party ? "group" : "entry": row["id"]!, "cat": .string(income ? "人情家庭" : labels[index % labels.count]),
                        "nature": .string(income ? "income" : "expense"), "purpose": .string(income ? "红包" : "合成用途"), "ok": .bool(true)])
                })])
            }
            let result = try await ImportOrganizer(transport: script).organize(ledger: ledger, entryIDs: ledger.entries.map(\.id))
            XCTAssertTrue(result.skipped.isEmpty, result.skipped.joined(separator: "；")); XCTAssertEqual(result.categoryCount, 20)
            _ = try result.changeSet.apply(to: &ledger)
            XCTAssertTrue(ledger.entries.filter { $0.nature.inflow }.allSatisfy { $0.category == "礼金赠与" })
            XCTAssertTrue(ledger.entries.allSatisfy { !Classification.isPending($0) })
            for entry in ledger.entries {
                if entry.category == "购物" { XCTAssertEqual(entry.subcategory, "日用百货") }
                if entry.category == "居住" { XCTAssertEqual(entry.subcategory, "网费话费") }
                if entry.category == "餐饮" { XCTAssertEqual(entry.subcategory, "外卖") }
            }
            XCTAssertTrue(ledger.classificationMemory.isEmpty)
        }
    }
    func testRepeatedCategoryDiagnosticsMergeAcrossCheckpointsAndLegacyArchives() async throws {
        let (ledger, batch) = partyImport(counts: Array(repeating: 3, count: 20))
        let store = ImportCheckpointStore(ledger, batchID: batch.id)
        let script = ImportScript { request in
            let groups = try JSONValue.parse(request.messages.last!.content!)["groups"]!.arrayValue!
            return .object(["groups": .array(groups.enumerated().map { index, group in
                .object(["group": group["id"]!, "cat": .string(index.isMultiple(of: 2) ? "无效分类甲" : "无效分类乙"), "ok": .bool(true)])
            })])
        }
        let result = try await ImportOrganizer(transport: script).organize(ledger: ledger, entryIDs: ledger.entries.map(\.id)) { result, ids, before in
            try await store.save(result, ids: ids, before: before)
        }
        let saved = await store.snapshot()
        let organization = try XCTUnwrap(saved.imports[0].organization)
        XCTAssertEqual(result.skipped.count, 1); XCTAssertEqual(organization.skipped.count, 1)
        XCTAssertEqual(organization.skipped, ["已跳过不在当前分类中的分类：无效分类乙×30、无效分类甲×30"])
        XCTAssertEqual(organization.diagnosticCounts?.values.reduce(0, +), 60)
        XCTAssertEqual(organization, try JSONDecoder().decode(ImportOrganization.self, from: JSONEncoder().encode(organization)))
        let legacy = ImportOrganization(changeSet: result.changeSet, questions: [], skipped: Array(repeating: "已跳过不在当前分类中的分类", count: 1314))
        XCTAssertEqual(legacy.compactingDiagnostics().skipped, ["已跳过不在当前分类中的分类×1314"])
        var many = legacy; many.skipped += (0..<50).map { "合成跳过类\($0)" }
        XCTAssertLessThanOrEqual(many.compactingDiagnostics().skipped.count, 6)
        XCTAssertEqual(many.compactingDiagnostics().diagnosticCounts?.values.reduce(0, +), 1364)
    }
}

extension ImportOrganizerTests {
    func testMappedCategoryDoesNotOverwriteUserChosenSmallItem() async throws {
        var (ledger, _) = partyImport(counts: [1])
        ledger.entries[0].category = "餐饮"; ledger.entries[0].subcategory = "咖啡饮品"
        ledger.entries[0].subcategoryUserEdited = true
        let script = ImportScript { request in
            let row = try JSONValue.parse(request.messages.last!.content!)["batch"]!.arrayValue!.first!
            return .object(["rows": .array([.object(["entry": row["id"]!, "cat": .string("外卖"),
                "purpose": .string("午餐"), "ok": .bool(true)])])])
        }
        let result = try await ImportOrganizer(transport: script).organize(ledger: ledger, entryIDs: ledger.entries.map(\.id))
        _ = try result.changeSet.apply(to: &ledger)
        XCTAssertEqual(ledger.entries[0].category, "餐饮"); XCTAssertEqual(ledger.entries[0].subcategory, "咖啡饮品")
        XCTAssertTrue(ledger.entries[0].subcategoryUserEdited); XCTAssertEqual(ledger.entries[0].purpose, "午餐")
    }
}

private actor FailureIsolationTransport: ChatTransport {
    let status: Int?
    let holdsOtherRequests: Bool
    var requests: [ChatRequest] = []
    var cancellations = 0
    init(status: Int? = 503, holdsOtherRequests: Bool = false) {
        self.status = status; self.holdsOtherRequests = holdsOtherRequests
    }
    func send(_ request: ChatRequest) async throws -> ChatMessage {
        if request.purpose == "导入短评" { return ChatMessage(role: .assistant, content: #"{"cards":[]}"#) }
        let index = requests.count; requests.append(request)
        do {
            try await Task.sleep(nanoseconds: index == 0 ? 10_000_000 : holdsOtherRequests ? 30_000_000_000 : 30_000_000)
        } catch { cancellations += 1; throw error }
        if index == 0, let status { throw DeepSeekError.http(status) }
        let payload = try JSONValue.parse(request.messages.last!.content!)
        let party = request.purpose == "导入整理·按对方"
        let input = payload[party ? "groups" : "batch"]!.arrayValue!
        let rows = input.map { JSONValue.object([party ? "group" : "entry": $0["id"]!, "cat": .string("餐饮"), "ok": .bool(true)]) }
        return ChatMessage(role: .assistant, content: try JSONValue.object([party ? "groups" : "rows": .array(rows)]).jsonText())
    }
}

extension ImportOrganizerTests {
    func testOneFailedChunkLeavesOnlyItsRowsPendingWhileOtherInFlightAndQueuedChunksFinishInBothPhases() async throws {
        for party in [true, false] {
            for status in [503, 422] {
                let ledger: Ledger, batch: ImportBatch
                if party { (ledger, batch) = partyImport(counts: Array(repeating: 1, count: 80)) }
                else { let value = try syntheticImport(count: 100); ledger = value.1; batch = value.2 }
                let store = ImportCheckpointStore(ledger, batchID: batch.id)
                let script = FailureIsolationTransport(status: status)
                let result = try await resume(store, script: script, batchID: batch.id)
                let failure = try XCTUnwrap(result.failedChunks?.first)
                let saved = await store.snapshot()
                XCTAssertEqual(result.failedChunks?.count, 1)
                XCTAssertEqual(failure.entryIDs.count, party ? 8 : 15)
                XCTAssertEqual(Set(ImportOrganizer.pendingEntryIDs(in: saved, batchID: batch.id)), Set(failure.entryIDs))
                XCTAssertEqual(PendingImportOrganization(in: saved).count, failure.entryIDs.count)
                XCTAssertEqual(saved.imports[0].organizedEntryIDs?.count, ledger.entries.count - failure.entryIDs.count)
                let cancellations = await script.cancellations
                XCTAssertEqual(cancellations, 0)
                let requests = await script.requests
                XCTAssertGreaterThan(requests.count, party ? 4 : 2, "queued chunks also run")
                let expected = status == 503 ? "DeepSeek 繁忙（HTTP 503）" : "DeepSeek 返回错误（HTTP 422）"
                XCTAssertEqual(ImportOrganizer.incompleteMessage(remaining: failure.entryIDs.count, reason: failure.reason),
                               "\(failure.entryIDs.count) 笔没整理完：" + expected)
                let retry = FailureIsolationTransport(status: nil)
                let resumed = try await resume(store, script: retry, batchID: batch.id)
                XCTAssertNil(resumed.failedChunks)
                let retryRequests = await retry.requests
                XCTAssertEqual(retryRequests.count, 1)
                let finished = await store.snapshot()
                XCTAssertEqual(PendingImportOrganization(in: finished).count, 0)
                XCTAssertEqual(finished.imports[0].organizedEntryIDs?.count, ledger.entries.count)
                await store.undo()
                let undone = await store.snapshot()
                XCTAssertTrue(undone.entries.isEmpty)
            }
        }
    }
    func testAccountErrorsCancelOtherInFlightChunksInBothPhases() async throws {
        for party in [true, false] {
            for status in [401, 402] {
                let ledger = party ? partyImport(counts: Array(repeating: 1, count: 80)).0 : try syntheticImport(count: 100).1
                let script = FailureIsolationTransport(status: status, holdsOtherRequests: true)
                do {
                    _ = try await ImportOrganizer(transport: script).organize(ledger: ledger, entryIDs: ledger.entries.map(\.id))
                    XCTFail("account error must abort")
                } catch { XCTAssertEqual(error as? DeepSeekError, .http(status)) }
                let requests = await script.requests, cancellations = await script.cancellations
                XCTAssertEqual(requests.count, party ? 4 : 2)
                XCTAssertEqual(cancellations, requests.count - 1)
            }
        }
    }
}

private struct StubbedImportTransport: ChatTransport, @unchecked Sendable {
    let stub: CloudTestStub
    func send(_ request: ChatRequest) async throws -> ChatMessage { try await stub.send(request) }
}
private actor RetryHeartbeatProbe {
    var heartbeat: ImportOrganizationHeartbeat
    var started = 0, finished = 0
    init(total: Int) { heartbeat = .init(progress: .init(completed: 0, total: total)) }
    func receive(_ event: ImportOrganizer.RequestEvent) {
        heartbeat.receive(event)
        switch event { case .started: started += 1; case .finished: finished += 1; case .checkpointed: break }
    }
    func tick() -> Int64 { heartbeat.tick(); return heartbeat.completedUnits }
}
extension ImportOrganizerTests {
    func testHeartbeatContinuesThroughActualHTTPBackoffAndStopLeavesAllRowsPending() async throws {
        let (_, ledger, batch) = try syntheticImport(count: 2)
        let store = ImportCheckpointStore(ledger, batchID: batch.id), probe = RetryHeartbeatProbe(total: 2)
        let waiting = expectation(description: "retry waiting"), log = SendLog()
        let stub = CloudTestStub(rawResponse: true, statusCode: 503, sendLog: log, retrySleep: { _ in
            waiting.fulfill()
            try await Task.sleep(nanoseconds: 30_000_000_000)
        }) { _ in "" }
        defer { stub.close() }
        let run = Task {
            try await ImportOrganizer(transport: StubbedImportTransport(stub: stub)).organize(
                ledger: ledger, entryIDs: ledger.entries.map(\.id), checkpoint: { result, ids, before in
                    try await store.save(result, ids: ids, before: before)
                }, activity: { await probe.receive($0) })
        }
        await fulfillment(of: [waiting], timeout: 2)
        let started = await probe.started, finished = await probe.finished
        XCTAssertEqual(started, 1); XCTAssertEqual(finished, 0)
        let firstTick = await probe.tick(), secondTick = await probe.tick()
        XCTAssertGreaterThan(firstTick, 0); XCTAssertGreaterThan(secondTick, firstTick)
        XCTAssertLessThan(secondTick, 20_000)
        let start = Date(); run.cancel()
        do { _ = try await run.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.5)
        let saved = await store.snapshot()
        XCTAssertEqual(saved, ledger)
        XCTAssertEqual(PendingImportOrganization(in: saved).count, 2)
        XCTAssertEqual(log.items.first?.attempts?.count, 1)
    }
}
