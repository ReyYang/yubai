import XCTest
@testable import YubaiCore

final class StorageTests: XCTestCase {
    func sample() -> Ledger { var l = SampleData.ledger(now: Dates.parse("2026-10-01")!); l.attachments = [Attachment(name: "账单原件.csv", data: Data([0, 1, 2, 0xFF]))]; l.entries[0].attachmentID = l.attachments[0].id; return l }
    func testLegacyLedgerDefaultsToVividThemeWithoutChangingPreferences() throws {
        var ledger = sample()
        ledger.preferences.appearance = "dark"
        ledger.preferences.hideAmounts = true
        ledger.preferences.cloudAIEnabled = true
        var json = try JSONSerialization.jsonObject(with: LedgerCodec.encode(ledger)) as! [String: Any]
        var preferences = json["preferences"] as! [String: Any]
        preferences.removeValue(forKey: "colorTheme")
        json["preferences"] = preferences
        let restored = try LedgerCodec.decode(JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(restored.preferences.colorTheme, "jade-vivid")
        XCTAssertEqual(restored, ledger)
    }
    func testLegacyAIPreferencesDecodeAndMigrateWithoutReencodingOldKeys() throws {
        let original = sample()
        let oldKeys = ["localAIEnabled", "downloadedModelEnabled", "appleSystemModelEnabled", "experimentalMockLocalAI"]
        // A missing legacy master switch means enabled; missing cloud always means off.
        let cases: [(cloud: Bool?, master: Bool?, expected: Bool)] = [
            (true, true, true), (true, false, false), (false, true, false), (false, false, false),
            (nil, true, false), (nil, false, false), (true, nil, true), (false, nil, false), (nil, nil, false)
        ]
        for testCase in cases {
            var json = try XCTUnwrap(JSONSerialization.jsonObject(with: LedgerCodec.encode(original)) as? [String: Any])
            var preferences = try XCTUnwrap(json["preferences"] as? [String: Any])
            if let cloud = testCase.cloud { preferences["cloudAIEnabled"] = cloud }
            else { preferences.removeValue(forKey: "cloudAIEnabled") }
            if let master = testCase.master { preferences["localAIEnabled"] = master }
            else { preferences.removeValue(forKey: "localAIEnabled") }
            // Retired switches are ignored, even if their values no longer match the former type.
            preferences["downloadedModelEnabled"] = true
            preferences["appleSystemModelEnabled"] = "ignored"
            preferences["experimentalMockLocalAI"] = true
            json["preferences"] = preferences
            let restored = try LedgerCodec.decode(JSONSerialization.data(withJSONObject: json))
            var expected = original
            expected.preferences.cloudAIEnabled = testCase.expected
            XCTAssertEqual(restored, expected)
            XCTAssertEqual(restored.schema, 3)
            let encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: LedgerCodec.encode(restored)) as? [String: Any])
            let current = try XCTUnwrap(encoded["preferences"] as? [String: Any])
            XCTAssertEqual(current["cloudAIEnabled"] as? Bool, testCase.expected)
            for key in oldKeys { XCTAssertNil(current[key], key) }
            XCTAssertEqual(try LedgerCodec.decode(LedgerCodec.encode(restored)), restored)
        }
    }
    func testColorThemesSurviveLedgerRoundTrip() throws {
        for theme in ["jade-vivid", "jade-current", "ocean"] {
            var ledger = sample()
            ledger.preferences.colorTheme = theme
            XCTAssertEqual(try LedgerCodec.decode(LedgerCodec.encode(ledger)), ledger)
        }
    }
    func testEncryptedBackupRoundTripPreservesAllRelationshipsAndAttachments() throws {
        let l = sample(); let bytes = try Backup.export(l, password: "a strong password 123")
        XCTAssertFalse(String(data: bytes, encoding: .utf8)!.contains("工资卡"))
        let restored = try Backup.restore(bytes, password: "a strong password 123"); XCTAssertEqual(restored, l)
        XCTAssertThrowsError(try Backup.restore(bytes, password: "wrong password"))
        XCTAssertThrowsError(try Backup.restore(bytes))
    }
    func testEncryptedBackupV1CompatibilityVectors() throws {
        // Python hashlib.pbkdf2_hmac("sha256") + cryptography AESGCM；固定盐、nonce 与 v1 AAD。
        let plain = Data(#"{"schema":2,"id":"00000000-0000-0000-0000-000000000001","updatedAt":0,"accounts":[],"entries":[],"plans":[],"goals":[],"rents":[],"categories":[],"imports":[],"attachments":[],"preferences":{"horizonDays":90,"emergencyReserve":0,"dailyLiving":0,"hideAmounts":false,"lockEnabled":false,"appearance":"system","purchaseValues":"compatibility","onboardingComplete":false}}"#.utf8)
        let expected = try LedgerCodec.decode(plain)
        let vectors: [(Int, String)] = [
            (100_000, "EBESExQVFhcYGRobzl2jIUaMo5ORlggUqttVqrF65XHAQjCjcqVHg+lHd3NWsuaybFMDfBx/BWGWeOJJ2wgAGaqhhqhR/8+ADQ7wDfnteIh/QV5ppyQwlTqTpsdR7oOPN5gP/qPvFeh2n/QQAXz3HzfqsYfR06Bzt842BhL+xk9Ki9Zv4v6GeGj6FNQWABevOrz6ZCZmeYIsqDR4AJoFyox4D3uAXBxkZxCTmNDe1p2AgaN3NzBxdHTz1zalllQ+KFbJxkSHGnQ9oYacEsfU4iZ47KrCNi8TFw+80vAze8WgD/NLlBg2N3MlAuCvDjLGSyeEUqmYI8pqXAEaF+8x0Ll08Z1TLKkf9bEfEXLzVPGILWiFXLDRsqaExFMOg0njhEOnLB3SjplMlI/oTjMdKDy5fygFYUoFILO2096uonCjKuvW/FkymugAOCaTu76qb0qP4TLpeGldrC9pBDk6E9+swu3y50akM9rwRyYzBqptZgSduk+MGsHpRSmxNg5JIv8yk1O9CJvQ8zlO"),
            (210_000, "EBESExQVFhcYGRobAzYZB+zeVTcQXbQ03pO89hOwC2czvR5saOFKW8pQgVCGqoxy0Ed6fcvle+kkMcv8sv0BolxPuJQEHyXEnRFtCKd+CIRD/QwZqfsC4b0694OLc4NXcjYsS2kNVD7Qer1LnF9uHWT6goFGriDjArPOLPM/2dv2IvxyYOFRt+aacvDdi8XQ00KxzRCoqFkvbfwTDKV0cXW2QHn7ak/AtGJnb1X/TFv4dzGBjFRswNSZyRMw90Evv6foRAsSIRAKD0WcgG0BNXjK+sqdUcHDwC0XCukgW1a5RwtrW0/7LDrlz0GKeofi55QZiy9wM2MbjrqtznhOByQLD9KZpfH13dc+yJ8AvV5Pt/e+LDFtgiObvZAUAYFGx2jcud4eFdKHv3OGeS6VJuDfNDcPRYIl7utFwsZ5ub4bFmBiWZq0xWdR6ErnLqcyHF7Ef6q95FRMnvr5Poiq/yRkUWPbdHbvSkhZ2DE4/anQsp2O9B9t2XEdW/WtYOj8wkOmYMVucCIQH8c+"),
            (1_000_000, "EBESExQVFhcYGRob/QvFSvAiG4776BYcQ0pIAz6ei/Foua5JlyUyIcAxPM4KQ+QF/3xD4BuLDewc8vNWLIcqgWKvT4gdFQmKGbbjT4Fvt9LByCwEVL90lfmrlbiHpQ/rozQELmvv4KAh6JnCmrf5kBOUQo4UzFJqtoUgdkxxClYIBaoyuV+7dhKZz6wMlKtFVsKdlq1EDxGoP1SWtHS7HJGUwIAFXhg80b/Rel7J0mw4tD/B2tuJUPNIKHcgSGDkOgDAcL+dDiP9ruHOWB01JhC00boVzzqJzD6hbX9f1sZqIxxL/4KanS63OVCPUdXngc+0sWxWqsQj/cSLRN4IsIIK/ik02UoCM2iZmc/MS8IRyVCP6stLxkie2eQtfsxe4k7qmnvPHy9zi1XQnHivokpJVmgLL1MJI/45BpOfmN+G+k3dicUmX6iyhVEW5LQ2p6/M1xprt6z9uEU1vdrtQx944r63GH8PnGZopGaduSYiWQBL5qAlVECXWba6xIeYm4yIZd4uUrjYLhdu")
        ]
        for (rounds, payload) in vectors {
            let envelope: [String: Any] = [
                "format": "yubai-backup", "version": 1, "createdAt": 0, "encrypted": true,
                "salt": "AAECAwQFBgcICQoLDA0ODw==", "rounds": rounds, "payload": payload,
                "checksum": "2b9edd31f6dd6b0821ef255a4b4b62fb907264d9b44edf6e33e561b3453da938"
            ]
            let bytes = try JSONSerialization.data(withJSONObject: envelope)
            XCTAssertEqual(try Backup.restore(bytes, password: "备份\0密码🔐123"), expected, "\(rounds) rounds")
            var damaged = envelope
            var combined = try XCTUnwrap(Data(base64Encoded: payload)); combined[combined.count - 1] ^= 1
            damaged["payload"] = combined.base64EncodedString()
            XCTAssertThrowsError(try Backup.restore(JSONSerialization.data(withJSONObject: damaged), password: "备份\0密码🔐123"))
        }
    }
    func testEncryptedBackupExportsV1ParametersAndRejectsInvalidParameters() throws {
        let ledger = sample(); let password = "portable-backup-password"
        let bytes = try Backup.export(ledger, password: password)
        let envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        XCTAssertEqual(envelope["version"] as? Int, 1); XCTAssertEqual(envelope["rounds"] as? Int, 210_000)
        let salt = try XCTUnwrap((envelope["salt"] as? String).flatMap { Data(base64Encoded: $0) })
        let payload = try XCTUnwrap((envelope["payload"] as? String).flatMap { Data(base64Encoded: $0) })
        XCTAssertEqual(salt.count, 16); XCTAssertEqual(payload.count, try LedgerCodec.encode(ledger).count + 12 + 16)
        for rounds in [99_999, 1_000_001] {
            var invalid = envelope; invalid["rounds"] = rounds
            XCTAssertThrowsError(try Backup.restore(JSONSerialization.data(withJSONObject: invalid), password: password))
        }
        var invalid = envelope; invalid["salt"] = Data([0]).base64EncodedString()
        XCTAssertThrowsError(try Backup.restore(JSONSerialization.data(withJSONObject: invalid), password: password))
    }
    func testPlainBackupChecksumAndVersionChecks() throws {
        let l = sample(); let bytes = try Backup.export(l); XCTAssertEqual(try Backup.restore(bytes), l)
        var json = try JSONSerialization.jsonObject(with: bytes) as! [String: Any]; json["checksum"] = "bad"
        XCTAssertThrowsError(try Backup.restore(JSONSerialization.data(withJSONObject: json)))
        var future = l; future.schema = 99; XCTAssertThrowsError(try LedgerCodec.encode(future))
        XCTAssertThrowsError(try Backup.export(l, password: "short"))
    }
    func testRestartAndIndependentRestoreToFreshDirectory() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("yubai-test-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = LedgerRepository(directory: root.appendingPathComponent("original")); let l = sample(); try repo.save(l)
        let reopened = LedgerRepository(directory: repo.directory); XCTAssertEqual(try reopened.load(), l)
        let backup = try Backup.export(l, password: "restore-check")
        let fresh = LedgerRepository(directory: root.appendingPathComponent("fresh")); try fresh.restoreBackup(Backup.restore(backup, password: "restore-check"))
        let readback = try fresh.load(); XCTAssertEqual(readback.accounts, l.accounts); XCTAssertEqual(readback.entries, l.entries); XCTAssertEqual(try fresh.attachmentData(l.attachments[0].id), l.attachments[0].data)
        XCTAssertEqual(Finance.funds(readback, now: Dates.parse("2026-10-01")!).netWorth, Finance.funds(l, now: Dates.parse("2026-10-01")!).netWorth)
    }
    func testCorruptionDoesNotBecomeEmptyLedgerAndCannotBeOverwritten() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("yubai-test-\(UUID())"); defer { try? FileManager.default.removeItem(at: root) }
        let repo = LedgerRepository(directory: root); try repo.save(sample()); try Data("corrupt".utf8).write(to: repo.file)
        XCTAssertThrowsError(try repo.load()); XCTAssertThrowsError(try repo.save(Ledger()))
        XCTAssertEqual(try String(contentsOf: repo.file, encoding: .utf8), "corrupt")
        let restored = sample(); try repo.restoreBackup(restored); XCTAssertEqual(try repo.load(), restored)
    }
    func testHistoryAndRestorePreservePreviousLedger() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("yubai-test-\(UUID())"); defer { try? FileManager.default.removeItem(at: root) }
        let repo = LedgerRepository(directory: root); var l = sample(); try repo.save(l); let original = l
        l.accounts[0].name = "新名称"; try repo.save(l, reason: "重命名"); let history = try repo.recoveries(); XCTAssertEqual(history.count, 1)
        XCTAssertEqual(try repo.recover(history[0]), original)
        XCTAssertTrue(try repo.recoveries().contains { try LedgerCodec.decode(repo.recoveryBytes($0.url)).accounts[0].name == "新名称" })
        let another = Ledger(); try repo.restoreBackup(another); XCTAssertEqual(try repo.load(), another); XCTAssertFalse(try repo.recoveries().isEmpty)
    }
    func testRepeatedSavesKeepExactPreviousBytesAndLatestTwentyRevisions() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("yubai-history-\(UUID())"); defer { try? FileManager.default.removeItem(at: root) }
        let repo = LedgerRepository(directory: root); let copy = repo; var ledger = sample(); try repo.save(ledger)
        var previous: [Data] = []
        for index in 0..<26 {
            previous.append(try Data(contentsOf: repo.file))
            ledger.accounts[0].name = "Revision \(index / 2)"
            try copy.save(ledger, reason: "Repeated/save")
        }
        let history = try repo.recoveries(); XCTAssertEqual(history.count, 20)
        XCTAssertEqual(try history.map { try repo.recoveryBytes($0.url) }, Array(previous.suffix(20).reversed()))
        for revision in history { XCTAssertNoThrow(try LedgerCodec.decode(repo.recoveryBytes(revision.url))) }
        XCTAssertEqual(try repo.load(), ledger)
        let reopened = LedgerRepository(directory: root); _ = try reopened.load()
        let last = try Data(contentsOf: repo.file); try reopened.save(ledger)
        XCTAssertEqual(try reopened.recoveries().count, 20)
        XCTAssertEqual(try reopened.recoveryBytes(XCTUnwrap(reopened.recoveries().first).url), last)
    }
    func testLoadedRepositoryVerifiesAndPreservesValidExternalChangesBeforeSaving() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("yubai-external-\(UUID())"); defer { try? FileManager.default.removeItem(at: root) }
        let writer = LedgerRepository(directory: root); let ledger = sample(); try writer.save(ledger); try writer.save(ledger)
        let repo = LedgerRepository(directory: root); XCTAssertEqual(try repo.load(), ledger); let copy = repo
        let previous = try XCTUnwrap(repo.recoveries().first)
        var externalLedger = ledger; externalLedger.accounts[0].name = "External edit"
        let external = Data(" \n".utf8) + (try LedgerCodec.encode(externalLedger))
        try external.write(to: repo.file, options: .atomic)
        try copy.save(ledger)
        let history = try repo.recoveries(); XCTAssertEqual(history.count, 2)
        let newest = try XCTUnwrap(history.first); XCTAssertGreaterThan(newest.date, previous.date)
        let preserved = try repo.recoveryBytes(newest.url)
        XCTAssertEqual(preserved, try LedgerCodec.encodeMetadata(externalLedger)); XCTAssertEqual(try LedgerCodec.decode(preserved), externalLedger)
        XCTAssertEqual(try Data(contentsOf: repo.file), try LedgerCodec.encodeMetadata(ledger)); XCTAssertEqual(try repo.load(), ledger)
    }
    func testFirstSaveVerifiesUnrecognizedCurrentFile() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("yubai-unrecognized-\(UUID())"); defer { try? FileManager.default.removeItem(at: root) }
        let writer = LedgerRepository(directory: root); var ledger = sample(); try writer.save(ledger)
        let original = try Data(contentsOf: writer.file); let repo = LedgerRepository(directory: root); try repo.save(ledger)
        XCTAssertEqual(try repo.recoveryBytes(XCTUnwrap(repo.recoveries().first).url), original)
        var invalidJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: LedgerCodec.encode(ledger)) as? [String: Any])
        invalidJSON["schema"] = 99
        let invalid = try JSONSerialization.data(withJSONObject: invalidJSON); try invalid.write(to: repo.file, options: .atomic)
        XCTAssertThrowsError(try LedgerRepository(directory: root).save(sample()))
        XCTAssertEqual(try Data(contentsOf: repo.file), invalid); XCTAssertEqual(try repo.recoveries().count, 1)
    }
    func testCachedDigestRejectsSameSizeCorruptionAndAllowsSavingAfterRemoval() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("yubai-digest-\(UUID())"); defer { try? FileManager.default.removeItem(at: root) }
        let repo = LedgerRepository(directory: root); let ledger = sample(); try repo.save(ledger)
        let original = try Data(contentsOf: repo.file); let corrupt = Data(repeating: 0x78, count: original.count)
        let modified = try FileManager.default.attributesOfItem(atPath: repo.file.path)[.modificationDate] as! Date
        try corrupt.write(to: repo.file); try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: repo.file.path)
        XCTAssertThrowsError(try repo.save(ledger)); XCTAssertEqual(try Data(contentsOf: repo.file), corrupt)
        XCTAssertThrowsError(try LedgerRepository(directory: root).save(ledger)); XCTAssertTrue(try repo.recoveries().isEmpty)
        try FileManager.default.removeItem(at: repo.file); try repo.save(ledger)
        XCTAssertEqual(try Data(contentsOf: repo.file), original); XCTAssertEqual(try repo.load(), ledger)
        XCTAssertTrue(try repo.recoveries().isEmpty)
    }
    func testInvalidSaveLeavesCurrentRevisionAndHistoryUnchanged() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("yubai-invalid-\(UUID())"); defer { try? FileManager.default.removeItem(at: root) }
        let repo = LedgerRepository(directory: root); var ledger = sample(); try repo.save(ledger)
        let bytes = try Data(contentsOf: repo.file); ledger.entries[0].amount = -1
        XCTAssertThrowsError(try repo.save(ledger)); XCTAssertEqual(try Data(contentsOf: repo.file), bytes); XCTAssertTrue(try repo.recoveries().isEmpty)
    }
    func testInvalidReferencesAndNegativeAmountsCannotPersist() throws {
        var l = Ledger(); l.entries = [Entry(amount: 100, accountID: UUID(), title: "无账户")]; XCTAssertThrowsError(try LedgerCodec.encode(l))
        l.accounts = [Account(name: "现金")]; l.entries = [Entry(amount: -1, accountID: l.accounts[0].id, title: "负值")]; XCTAssertThrowsError(try LedgerCodec.encode(l))
        l.entries = []; var g = Goal(title: "目标", target: 100); g.reserved = 101; l.goals = [g]; XCTAssertThrowsError(try l.validate())
    }
    func testPersistedLedgerAndRecoveryArePrivateToDeviceUser() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("yubai-private-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = LedgerRepository(directory: root); var l = sample(); try repo.save(l)
        l.accounts[0].name = "Reconciled"; try repo.save(l)
        let history = try repo.recoveries()
        for file in [repo.file] + history.map(\.url) {
            XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        }
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: root.path)[.posixPermissions] as? NSNumber)?.intValue, 0o700)
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: root.appendingPathComponent("Recovery").path)[.posixPermissions] as? NSNumber)?.intValue, 0o700)
    }
}

extension StorageTests {
    private func withRepository(_ body: (LedgerRepository) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("yubai-payloads-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        try body(LedgerRepository(directory: root))
    }
    func testSavedAndLoadedAttachmentsAreLazyAndImmutablePayloadsAreNotRewritten() throws {
        try withRepository { repo in
            let original = sample(); var saved = try repo.save(original)
            XCTAssertTrue(saved.attachments[0].data.isEmpty)
            let id = original.attachments[0].id
            XCTAssertEqual(try repo.attachmentData(id), original.attachments[0].data)
            saved = try repo.save(saved)
            let main = repo.directory.appendingPathComponent("Attachments/" + id.uuidString)
            let shared = repo.directory.appendingPathComponent("Recovery/Payloads/" + id.uuidString)
            let old = Date(timeIntervalSince1970: 100)
            for file in [main, shared] { try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: file.path) }
            for _ in 0..<3 { saved = try repo.save(saved) }
            for file in [main, shared] {
                XCTAssertEqual(try file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, old)
                XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber)?.intValue, 0o600)
            }
            let loaded = try LedgerRepository(directory: repo.directory).load()
            XCTAssertTrue(loaded.attachments[0].data.isEmpty); XCTAssertEqual(loaded, original)
            try Data([9, 9, 9, 9]).write(to: main)
            // An ordinary metadata save neither reads nor rehashes the existing payload.
            XCTAssertNoThrow(try repo.save(loaded))
            XCTAssertThrowsError(try repo.attachmentData(id))
            var changed = loaded; changed.attachments[0].data = Data([4, 3, 2, 1])
            XCTAssertThrowsError(try repo.save(changed))
        }
    }
    func testRecoverySharesOnePayloadAndCollectsItAfterLastReferenceIsPruned() throws {
        try withRepository { repo in
            var ledger = try repo.save(sample())
            let id = ledger.attachments[0].id
            let shared = repo.directory.appendingPathComponent("Recovery/Payloads", isDirectory: true)
            let payload = shared.appendingPathComponent(id.uuidString)
            for _ in 0..<23 { ledger = try repo.save(ledger) }
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: shared.path), [id.uuidString])
            XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: shared.deletingLastPathComponent().path).contains { $0.hasSuffix(".attachments") })
            ledger.entries[0].attachmentID = nil
            ledger = try repo.save(ledger)
            XCTAssertTrue(ledger.attachments.isEmpty)
            XCTAssertFalse(FileManager.default.fileExists(atPath: repo.directory.appendingPathComponent("Attachments/" + id.uuidString).path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: payload.path))
            for _ in 0..<21 { ledger = try repo.save(ledger) }
            XCTAssertEqual(try repo.recoveries().count, 20)
            XCTAssertFalse(FileManager.default.fileExists(atPath: payload.path))
        }
    }
    func testOrphanCleanupKeepsSoftDeletedEntriesImportsAndPendingEntryReferences() throws {
        try withRepository { repo in
            var ledger = sample(); ledger.entries[0].deletedAt = Date()
            let batchFile = Attachment(name: "批次.csv", data: Data([2]))
            var batch = ImportBatch(filename: batchFile.name, importedCount: 0, duplicateCount: 0, skippedCount: 0); batch.attachmentID = batchFile.id
            ledger.imports.append(batch); ledger.attachments.append(batchFile)
            let undoFile = Attachment(name: "撤销原件.csv", data: Data([5]))
            var previous = ledger.entries[2]; previous.attachmentID = undoFile.id
            var undo = ImportUndo(updatedAt: ledger.updatedAt); undo.entries = [previous]
            ledger.imports[0].undo = undo; ledger.attachments.append(undoFile)
            let pendingFile = Attachment(name: "待确认.jpg", data: Data([3]))
            ledger.entries[1].attachmentID = pendingFile.id; ledger.attachments.append(pendingFile)
            ledger.pendingChanges = [ChangeSet(source: "测试", reason: "待确认", items: [.setPurpose(entry: ledger.entries[1].id, text: "核对")])]
            let orphan = Attachment(name: "无引用", data: Data([4])); ledger.attachments.append(orphan)
            let saved = try repo.save(ledger)
            XCTAssertEqual(saved.attachments.count, 4)
            XCTAssertFalse(saved.attachments.contains { $0.id == orphan.id })
            XCTAssertEqual(try repo.attachmentData(batchFile.id), batchFile.data)
            XCTAssertEqual(try repo.attachmentData(pendingFile.id), pendingFile.data)
            XCTAssertEqual(try repo.attachmentData(undoFile.id), undoFile.data)
            XCTAssertEqual(try repo.attachmentData(ledger.attachments[0].id), ledger.attachments[0].data)
        }
    }
    func testUndoSnapshotCanCopyRemovedPayloadBackFromSharedRecovery() throws {
        try withRepository { repo in
            let before = try repo.save(sample()); var next = before
            next.entries[0].attachmentID = nil; next = try repo.save(next)
            XCTAssertTrue(next.attachments.isEmpty)
            let saved = try repo.save(before)
            XCTAssertEqual(saved, before)
            XCTAssertEqual(try repo.attachmentData(before.attachments[0].id), sample().attachments[0].data)
        }
    }
    func testCompressedAndLegacySidecarVersionsReadRecoverAndPrune() throws {
        try withRepository { repo in
            let original = sample(); try repo.save(original)
            let history = repo.directory.appendingPathComponent("Recovery", isDirectory: true)
            try FileManager.default.createDirectory(at: history, withIntermediateDirectories: true)
            let legacy = history.appendingPathComponent("1000-legacy-旧版本.json")
            let sidecar = legacy.deletingPathExtension().appendingPathExtension("attachments")
            try FileManager.default.createDirectory(at: sidecar, withIntermediateDirectories: true)
            try LedgerCodec.encodeMetadata(original).write(to: legacy)
            try original.attachments[0].data.write(to: sidecar.appendingPathComponent(original.attachments[0].id.uuidString))
            let old = try XCTUnwrap(repo.recoveries().first)
            XCTAssertEqual(old.date, Date(timeIntervalSince1970: 1))
            XCTAssertEqual(try repo.readRecovery(old), original)
            XCTAssertEqual(try repo.recover(old), original)
            let newest = try XCTUnwrap(repo.recoveries().first)
            XCTAssertTrue(newest.url.lastPathComponent.hasSuffix(".json.gz"))
            let bytes = try Data(contentsOf: newest.url)
            XCTAssertEqual(Array(bytes.prefix(2)), [0x1f, 0x8b]); XCTAssertLessThan(bytes.count, try repo.recoveryBytes(newest.url).count)
            XCTAssertEqual(try repo.readRecovery(newest), original)
            for _ in 0..<22 { try repo.save(original) }
            XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path)); XCTAssertFalse(FileManager.default.fileExists(atPath: sidecar.path))
        }
    }
    func testGzipRejectsTruncationAndDamagedChecksum() throws {
        let bytes = try RecoveryCompression.encode(Data(String(repeating: "账本元数据", count: 200).utf8))
        XCTAssertThrowsError(try RecoveryCompression.decode(Data(bytes.dropLast())))
        var corrupt = bytes; corrupt[corrupt.count - 8] ^= 1
        XCTAssertThrowsError(try RecoveryCompression.decode(corrupt))
    }
    func testImageCompressionFailurePreservesBytesAndName() {
        let bytes = Data([0, 1, 2, 3]); let result = ImageCompression.compress(bytes, name: "截图.png")
        XCTAssertEqual(result.data, bytes); XCTAssertEqual(result.name, "截图.png")
    }
}

extension StorageTests {
    func testPlainBackupFromLazyLedgerRestoresAttachmentsAndRepairsCorruptLivePayload() throws {
        try withRepository { repo in
            let original = sample(); let lazy = try repo.save(original)
            let backup = try Backup.export(lazy)
            let restored = try Backup.restore(backup)
            XCTAssertEqual(restored.attachments[0].data, original.attachments[0].data)
            let id = original.attachments[0].id
            let file = repo.directory.appendingPathComponent("Attachments/" + id.uuidString)
            try Data([9, 9, 9, 9]).write(to: file)
            XCTAssertThrowsError(try repo.attachmentData(id))
            let saved = try repo.restoreBackup(restored)
            XCTAssertTrue(saved.attachments[0].data.isEmpty)
            XCTAssertEqual(try repo.attachmentData(id), original.attachments[0].data)
            // Missing live payloads must not block restoring a complete backup either.
            try FileManager.default.removeItem(at: file)
            try FileManager.default.removeItem(at: repo.directory.appendingPathComponent("Recovery/Payloads/" + id.uuidString))
            XCTAssertNoThrow(try repo.restoreBackup(restored))
            XCTAssertEqual(try repo.attachmentData(id), original.attachments[0].data)
        }
    }
}

extension StorageTests {
    func testEmbeddedLegacyRecoveryReturnsLazyAttachmentsAndNewHistoryIsMetadataOnly() throws {
        try withRepository { repo in
            let original = sample()
            let history = repo.directory.appendingPathComponent("Recovery", isDirectory: true)
            try FileManager.default.createDirectory(at: history, withIntermediateDirectories: true)
            let legacy = history.appendingPathComponent("1000-inline-旧内嵌版本.json")
            try LedgerCodec.encode(original).write(to: legacy)
            let version = try XCTUnwrap(repo.recoveries().first)
            let lazy = try repo.readRecovery(version)
            XCTAssertEqual(lazy, original); XCTAssertTrue(lazy.attachments[0].data.isEmpty)
            _ = try repo.recover(version); try repo.save(lazy)
            let newest = try XCTUnwrap(repo.recoveries().first)
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: repo.recoveryBytes(newest.url)) as? [String: Any])
            XCTAssertNil((json["attachments"] as? [[String: Any]])?.first?["data"])
            XCTAssertEqual(try repo.attachmentData(original.attachments[0].id), original.attachments[0].data)
        }
    }
}
