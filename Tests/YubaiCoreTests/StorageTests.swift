import XCTest
@testable import YubaiCore

final class StorageTests: XCTestCase {
    func sample() -> Ledger { var l = SampleData.ledger(now: Dates.parse("2026-10-01")!); l.attachments = [Attachment(name: "账单原件.csv", data: Data([0, 1, 2, 0xFF]))]; return l }
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
            XCTAssertEqual(restored.schema, 2)
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
        let readback = try fresh.load(); XCTAssertEqual(readback.accounts, l.accounts); XCTAssertEqual(readback.entries, l.entries); XCTAssertEqual(readback.attachments[0].data, l.attachments[0].data)
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
        XCTAssertTrue(try repo.recoveries().contains { try LedgerCodec.decode(Data(contentsOf: $0.url)).accounts[0].name == "新名称" })
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
        XCTAssertEqual(try history.map { try Data(contentsOf: $0.url) }, Array(previous.suffix(20).reversed()))
        for revision in history { XCTAssertNoThrow(try LedgerCodec.decode(Data(contentsOf: revision.url))) }
        XCTAssertEqual(try repo.load(), ledger)
        let reopened = LedgerRepository(directory: root); _ = try reopened.load()
        let last = try Data(contentsOf: repo.file); try reopened.save(ledger)
        XCTAssertEqual(try reopened.recoveries().count, 20)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(reopened.recoveries().first).url), last)
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
        let preserved = try Data(contentsOf: newest.url)
        XCTAssertEqual(preserved, external); XCTAssertEqual(try LedgerCodec.decode(preserved), externalLedger)
        XCTAssertEqual(try Data(contentsOf: repo.file), try LedgerCodec.encodeMetadata(ledger)); XCTAssertEqual(try repo.load(), ledger)
    }
    func testFirstSaveVerifiesUnrecognizedCurrentFile() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("yubai-unrecognized-\(UUID())"); defer { try? FileManager.default.removeItem(at: root) }
        let writer = LedgerRepository(directory: root); var ledger = sample(); try writer.save(ledger)
        let original = try Data(contentsOf: writer.file); let repo = LedgerRepository(directory: root); try repo.save(ledger)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(repo.recoveries().first).url), original)
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
