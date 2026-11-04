import XCTest
@testable import YubaiCore

/// Opt-in, entirely offline measurement. The masked input and generated ledgers stay outside the repo.
final class StorageProfileTests: XCTestCase {
    func testMaskedImportStorageProfile() throws {
        guard let csvPath = ProcessInfo.processInfo.environment["YUBAI_STORAGE_PROFILE_CSV"],
              let output = ProcessInfo.processInfo.environment["YUBAI_STORAGE_PROFILE_OUTPUT"] else { return }
        let root = URL(fileURLWithPath: output, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let csv = try Data(contentsOf: URL(fileURLWithPath: csvPath))
        let seed = root.deletingLastPathComponent().appendingPathComponent("import-seed.json")
        var imported: Ledger
        if FileManager.default.fileExists(atPath: seed.path) {
            imported = try LedgerCodec.decode(Data(contentsOf: seed))
        } else {
            imported = Ledger(); imported.accounts = [Account(name: "合成银行卡")]
            let preview = try BillImporter.preview(data: csv, filename: "masked.csv", accountID: imported.accounts[0].id, ledger: imported)
            _ = try BillImporter.commit(preview, data: csv, to: &imported)
            try LedgerCodec.encode(imported).write(to: seed)
        }
        XCTAssertEqual(imported.entries.count, 4200)
        let repository = LedgerRepository(directory: root.appendingPathComponent("repository"))
        try repository.save(Ledger())
        var ledger = try repository.save(imported, reason: "导入账单")
        let batchID = try XCTUnwrap(ledger.imports.first?.id)
        var counts: [Int] = []
        // Four runs (initial + three retries), each with persisted partial progress.
        for run in 0..<4 {
            try repository.preserveRecovery(ledger, reason: "导入整理")
            let ids = Array(ledger.entries[(run * 1050)..<((run + 1) * 1050)].map(\.id))
            let items = ids.flatMap { id in
                [ChangeItem.setCategory(entry: id, category: "其他支出"), .setPurpose(entry: id, text: "合成整理用途")]
            }
            // Keep income categories valid while exercising the production checkpoint/undo path.
            let byID = Dictionary(uniqueKeysWithValues: ledger.entries.map { ($0.id, $0) })
            let validItems = items.map { item -> ChangeItem in
                if case .setCategory(let id, _) = item { return .setCategory(entry: id, category: byID[id]!.nature.inflow ? "其他收入" : "其他支出") }
                return item
            }
            let result = ImportOrganization(changeSet: ChangeSet(source: "导入整理", reason: "合成离线整理", items: validItems), questions: [], skipped: [])
            let before = ledger
            _ = try result.changeSet.apply(to: &ledger)
            result.finish(batchID: batchID, before: before, in: &ledger, entryIDs: ids)
            ledger = try repository.save(ledger, reason: "导入整理", preservingRecovery: false)
            counts.append(try repository.recoveries().count)
        }
        // Legacy questions are still answerable, even though new model questions are disabled.
        for index in 0..<4 {
            let question = ImportQuestion(text: "合成历史问题", entryIDs: [ledger.entries[index].id],
                options: [ImportAnswer(title: "合成用途", items: [.setPurpose(entry: ledger.entries[index].id, text: "合成回答用途")])])
            ledger.imports[0].organization?.questions.append(question)
            let before = ledger
            _ = try XCTUnwrap(question.answer(0, in: ledger)).apply(to: &ledger)
            ledger.imports[0].organization?.questions.removeAll { $0.id == question.id }
            ImportOrganization.recordUndo(batchID: batchID, before: before, in: &ledger)
            ledger = try repository.save(ledger, reason: "回答整理问题")
        }
        for reason in ["整理", "批量记账"] {
            for index in 0..<4 {
                let before = ledger
                let change = ChangeSet(source: reason, reason: "合成离线应用", items: [.setPurpose(entry: ledger.entries[index + 4].id, text: "合成批量用途")])
                _ = try change.apply(to: &ledger)
                ImportOrganization.recordUndo(batchID: batchID, before: before, in: &ledger)
                ledger = try repository.save(ledger, reason: reason)
            }
        }
        let metadata = try LedgerCodec.encodeMetadata(ledger)
        func size(_ value: Any) throws -> Int { try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .sortedKeys]).count }
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: metadata) as? [String: Any])
        let entries = json["entries"] as! [[String: Any]]
        let organization = (json["imports"] as! [[String: Any]])[0]["organization"] as! [String: Any]
        var fields: [String: Int] = [:]
        for key in Set(entries.flatMap(\.keys)) {
            fields[key] = try entries.reduce(0) { total, entry in
                guard let value = entry[key] else { return total }
                return total + (try size([key: value])) - 1 // field, colon and separating comma
            }
        }
        let versions = try repository.recoveries()
        let report: [String: Any] = [
            "entries": ledger.entries.count, "ledgerBytes": metadata.count,
            "topLevelValueBytes": try json.mapValues(size), "entryFieldBytes": fields,
            "organizationFieldBytes": try organization.mapValues(size),
            "importFieldBytes": try (json["imports"] as! [[String: Any]])[0].mapValues(size),
            "recoveryCount": versions.count, "recoveryBytes": try repository.storageUsage().recoveryBytes,
            "snapshotBytes": try versions.map { try Data(contentsOf: $0.url).count },
            "runRecoveryCounts": counts, "sharedCSVBytes": csv.count
        ]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: root.appendingPathComponent("metrics.json"))
        try metadata.write(to: root.appendingPathComponent("synthetic-ledger.json"))
        var undone = try repository.load(); BillImporter.undo(batchID: batchID, in: &undone)
        XCTAssertTrue(undone.entries.isEmpty)
        print("STORAGE_PROFILE count=\(versions.count) recoveryBytes=\(try repository.storageUsage().recoveryBytes) ledgerBytes=\(metadata.count)")
    }
}
