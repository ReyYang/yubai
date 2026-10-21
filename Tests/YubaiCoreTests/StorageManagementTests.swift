import XCTest
@testable import YubaiCore

final class StorageManagementTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian); value.timeZone = TimeZone(secondsFromGMT: 0)!; return value
    }
    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: 12))! }
    private func fixture() -> Ledger {
        var ledger = Ledger()
        let account = Account(name: "测试账户", at: now); ledger.accounts = [account]
        for months in [13, 7, 4, 2] {
            var item = Attachment(name: "截图-\(months).png", data: Data(repeating: UInt8(months), count: months * 100))
            item.createdAt = calendar.date(byAdding: .month, value: -months, to: now)!
            ledger.attachments.append(item)
            var entry = Entry(date: now, amount: 100, accountID: account.id, title: "测试记录")
            entry.attachmentID = item.id; ledger.entries.append(entry)
        }
        var original = Attachment(name: "账单原件.png", data: Data(repeating: 42, count: 800))
        original.createdAt = calendar.date(byAdding: .month, value: -24, to: now)!
        var batch = ImportBatch(filename: original.name, importedCount: 1, duplicateCount: 0, skippedCount: 0)
        batch.attachmentID = original.id
        ledger.imports = [batch]; ledger.attachments.append(original)
        ledger.preferences.onboardingComplete = true
        return ledger
    }
    private func withRepository(_ body: (LedgerRepository) throws -> Void) throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent("yubai-storage-\(UUID())")
        defer { try? FileManager.default.removeItem(at: parent) }
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        try body(LedgerRepository(directory: parent.appendingPathComponent("ledger")))
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: parent.path).contains { $0.hasPrefix(".yubai-storage-") })
    }
    private func bytes(_ url: URL) throws -> Int64 {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
        if values.isDirectory != true { return Int64(values.fileSize ?? 0) }
        return try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil).reduce(0) { try $0 + bytes($1) }
    }
    func testUsageSeparatesMetadataAttachmentsAndHistoryIncludingSharedAndLegacyPayloads() throws {
        try withRepository { repository in
            let ledger = try repository.save(fixture())
            try repository.save(ledger)
            try repository.save(ledger)
            try repository.markPendingSync(true)
            let recovery = repository.directory.appendingPathComponent("Recovery")
            let legacy = recovery.appendingPathComponent("legacy.attachments")
            try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
            try Data(repeating: 7, count: 123).write(to: legacy.appendingPathComponent("payload"))
            let usage = try repository.storageUsage()
            XCTAssertEqual(usage.ledgerBytes, try bytes(repository.file) + 7)
            XCTAssertEqual(usage.attachmentBytes, Int64(ledger.attachments.reduce(0) { $0 + $1.byteCount }))
            XCTAssertEqual(usage.recoveryBytes, try bytes(recovery))
            XCTAssertEqual(usage.recoveryCount, 2)
            XCTAssertEqual(usage.oldestRecovery, try repository.recoveries().last?.date)
            XCTAssertEqual(usage.totalBytes, try bytes(repository.directory))
        }
    }
    func testClassificationUsesReferencesAndProtectsEvenUndoneImportOriginals() {
        var ledger = fixture()
        // One original is also referenced by an entry, and the import has been undone.
        ledger.entries[0].attachmentID = ledger.imports[0].attachmentID
        ledger.imports[0].undoneAt = now
        ledger.entries[1].deletedAt = now
        let orphan = Attachment(name: "孤立截图.jpg", data: Data([1])); ledger.attachments.append(orphan)
        let classified = StorageAttachments.classify(in: ledger)
        XCTAssertEqual(Set(classified.screenshots.map(\.id)), Set(ledger.attachments[1...3].map(\.id)))
        XCTAssertEqual(classified.originals.map(\.id), [ledger.imports[0].attachmentID!])
        XCTAssertEqual(classified.oldest, ledger.attachments[4].createdAt)
        XCTAssertFalse(classified.screenshots.contains { $0.id == orphan.id })
    }
    func testCalendarMonthSelectionsAndExactCutoffIsKept() {
        for (months, expected) in [(3, 3), (6, 2), (12, 1)] {
            var ledger = fixture()
            var boundary = Attachment(name: "边界截图.png", data: Data([2]))
            boundary.createdAt = calendar.date(byAdding: .month, value: -months, to: now)!
            ledger.attachments.append(boundary)
            var entry = ledger.entries[0]; entry.id = UUID(); entry.attachmentID = boundary.id; ledger.entries.append(entry)
            let selection = StorageAttachments.oldScreenshots(in: ledger, months: months, now: now, calendar: calendar)
            XCTAssertEqual(selection.count, expected)
            XCTAssertFalse(selection.contains { $0.id == boundary.id })
        }
        XCTAssertTrue(StorageAttachments.oldScreenshots(in: fixture(), months: 0, now: now).isEmpty)
    }
    func testPureRemovalKeepsEntriesAndClearsAllReferencesIncludingUndo() {
        var ledger = fixture()
        var duplicate = ledger.entries[0]; duplicate.id = UUID(); duplicate.deletedAt = now
        ledger.entries.append(duplicate)
        ledger.imports[0].undo = ImportUndo(updatedAt: now)
        ledger.imports[0].undo!.entries = [duplicate]
        let originalEntries = ledger.entries
        let originalID = ledger.imports[0].attachmentID
        let removed = StorageAttachments.removeOldScreenshots(from: &ledger, months: 6, now: now, calendar: calendar)
        let ids = Set(removed.map(\.id))
        XCTAssertEqual(ledger.entries.count, originalEntries.count)
        for (before, after) in zip(originalEntries, ledger.entries) {
            var expected = before
            if before.attachmentID.map(ids.contains) == true { expected.attachmentID = nil }
            XCTAssertEqual(after, expected)
        }
        XCTAssertNil(ledger.imports[0].undo!.entries[0].attachmentID)
        XCTAssertEqual(ledger.imports[0].attachmentID, originalID)
    }
    func testDeletePersistsMetadataRemovesMainPayloadAndPreservesRecoveryForEveryPeriod() throws {
        for (months, expected) in [(3, 3), (6, 2), (12, 1)] {
            try withRepository { repository in
                let before = try repository.save(fixture())
                let removed = StorageAttachments.oldScreenshots(in: before, months: months, now: now, calendar: calendar)
                let after = try repository.deleteOldScreenshots(from: before, months: months, now: now, calendar: calendar)
                XCTAssertEqual(removed.count, expected)
                XCTAssertEqual(after.entries.count, before.entries.count)
                XCTAssertEqual(try repository.load(), after)
                for item in removed {
                    XCTAssertFalse(after.attachments.contains { $0.id == item.id })
                    XCTAssertNil(after.entries.first { $0.id == before.entries.first { $0.attachmentID == item.id }!.id }?.attachmentID)
                    XCTAssertFalse(FileManager.default.fileExists(atPath: repository.directory.appendingPathComponent("Attachments/\(item.id)").path))
                }
                let recovery = try XCTUnwrap(repository.recoveries().first)
                XCTAssertTrue(recovery.name.hasSuffix("删除旧截图"))
                XCTAssertEqual(try repository.readRecovery(recovery), before)
                // A complete backup still reads the original screenshot from shared history.
                XCTAssertEqual(try Backup.restore(Backup.export(repository.readRecovery(recovery))).attachments.count, before.attachments.count)
            }
        }
    }
    func testFailedDeletionRollsBackLedgerHistoryAndPayloads() throws {
        try withRepository { repository in
            let before = try repository.save(fixture())
            let metadata = try Data(contentsOf: repository.file)
            var changed = before
            // Same immutable ID with different contents fails after preserving the old version.
            changed.attachments[3].data = Data(repeating: 99, count: changed.attachments[3].byteCount)
            XCTAssertThrowsError(try repository.deleteOldScreenshots(from: changed, months: 6, now: now, calendar: calendar)) { error in
                XCTAssertTrue(error.localizedDescription.contains("同一附件标识的内容不同"))
            }
            XCTAssertEqual(try Data(contentsOf: repository.file), metadata)
            XCTAssertTrue(try repository.recoveries().isEmpty)
            XCTAssertEqual(try repository.load(), before)
            XCTAssertEqual(try Backup.restore(Backup.export(repository.load())).attachments.count, before.attachments.count)
        }
    }
    func testStaleDeleteDoesNotOverwriteNewerLedger() throws {
        try withRepository { repository in
            let original = try repository.save(fixture())
            let other = LedgerRepository(directory: repository.directory)
            var newer = try other.load(); newer.accounts[0].name = "新名称"; try other.save(newer)
            XCTAssertThrowsError(try repository.deleteOldScreenshots(from: original, months: 6, now: now, calendar: calendar))
            XCTAssertEqual(try repository.load(), newer)
        }
    }
    func testClearHistoryRemovesSharedPayloadsAndLeavesCurrentLedgerReadable() throws {
        try withRepository { repository in
            let before = try repository.save(fixture()); try repository.save(before)
            XCTAssertGreaterThan(try repository.storageUsage().recoveryBytes, 0)
            try repository.clearRecoveryHistory()
            XCTAssertTrue(try repository.recoveries().isEmpty)
            XCTAssertEqual(try repository.storageUsage().recoveryBytes, 0)
            XCTAssertFalse(FileManager.default.fileExists(atPath: repository.directory.appendingPathComponent("Recovery/Payloads").path))
            XCTAssertEqual(try repository.load(), before)
            XCTAssertEqual(try Backup.restore(Backup.export(repository.load())).attachments.count, before.attachments.count)
            try repository.clearRecoveryHistory()
            try repository.save(before)
            XCTAssertEqual(try repository.recoveries().count, 1)
        }
    }
    func testEraseLeavesEmptyDirectoryAndLoadReturnsFreshLedger() throws {
        try withRepository { repository in
            let before = try repository.save(fixture()); try repository.save(before); try repository.markPendingSync(true)
            try repository.eraseAllLocalData()
            XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: repository.directory.path).isEmpty)
            let fresh = try repository.load()
            XCTAssertTrue(fresh.entries.isEmpty); XCTAssertTrue(fresh.accounts.isEmpty); XCTAssertTrue(fresh.attachments.isEmpty)
            XCTAssertFalse(fresh.preferences.onboardingComplete); XCTAssertFalse(repository.hasPendingSync)
            XCTAssertEqual(try repository.storageUsage().totalBytes, 0)
            XCTAssertNotEqual(fresh.id, before.id)
            try repository.save(fresh, requiringUnchanged: true)
            XCTAssertTrue(try repository.recoveries().isEmpty)
        }
    }
    func testCloudRepositoryEraseOnlyDeletesLocalDirectory() throws {
        try withRepository { local in
            let cloudDirectory = local.directory.deletingLastPathComponent().appendingPathComponent("cloud")
            let cloud = local.relocated(to: cloudDirectory)
            let ledger = try local.save(fixture()); try cloud.save(ledger)
            let remoteBytes = try Data(contentsOf: cloud.file)
            try cloud.eraseAllLocalData()
            XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: local.directory.path).isEmpty)
            XCTAssertEqual(try Data(contentsOf: cloud.file), remoteBytes)
            XCTAssertEqual(try cloud.load(), ledger)
            // A relocated erase also resets the original local repository's digest.
            XCTAssertNoThrow(try local.save(Ledger(), requiringUnchanged: true))
        }
    }
    func testSizeFormattingAndOptionalBackupDateCompatibility() throws {
        XCTAssertEqual(StorageSize.text(999_000), "999.0 KB")
        XCTAssertEqual(StorageSize.text(1_000_000), "1.0 MB")
        XCTAssertEqual(StorageSize.text(1_250_000_000), "1.2 GB")
        XCTAssertEqual(StorageSize.text(0), "0.0 KB")
        var ledger = fixture(); XCTAssertNil(try LedgerCodec.decode(LedgerCodec.encode(ledger)).preferences.lastBackupAt)
        ledger.preferences.lastBackupAt = now
        XCTAssertEqual(try LedgerCodec.decode(LedgerCodec.encode(ledger)).preferences.lastBackupAt, now)
    }
}
