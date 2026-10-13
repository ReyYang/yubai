import XCTest
@testable import YubaiCore

final class StorageTests: XCTestCase {
    func sample() -> Ledger { var l = SampleData.ledger(now: Dates.parse("2026-10-01")!); l.attachments = [Attachment(name: "账单原件.csv", data: Data([0, 1, 2, 0xFF]))]; return l }
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
    }
}
