import XCTest
@testable import YubaiCore

final class LedgerSyncTests: XCTestCase {
    private final class Versions: LedgerVersionSource, @unchecked Sendable {
        let candidates: [LedgerVersion]
        var stale = false
        var resolved = false
        var onResolve: (() throws -> Void)?
        init(_ ledgers: [Ledger]) {
            candidates = ledgers.enumerated().map { LedgerVersion(id: String($0.offset), ledger: $0.element, deviceName: "测试设备") }
        }
        func versions() throws -> [LedgerVersion] { candidates }
        func validate() throws { if stale { throw LedgerSyncError.changed } }
        func markResolved() throws { try onResolve?(); resolved = true }
    }
    private func withDirectories(_ body: (URL, LedgerRepository, LedgerLocations) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("yubai-sync-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let local = LedgerRepository(directory: root.appendingPathComponent("local"))
        let locations = LedgerLocations(local: local, cloudDirectory: root.appendingPathComponent("cloud"))
        try body(root, local, locations)
    }
    private func ledger(_ title: String) -> Ledger {
        var ledger = Ledger(); let account = Account(name: "现金"); ledger.accounts = [account]
        ledger.entries = [Entry(amount: 1234, accountID: account.id, title: title)]
        ledger.attachments = [Attachment(name: title + ".csv", data: Data([0, 1, 2, 255]))]
        return ledger
    }
    func testEmbeddedAttachmentMigratesOnLoadWithoutChangingSchemaOrLosingSource() throws {
        try withDirectories { _, local, _ in
            let original = ledger("旧账单")
            var json = try XCTUnwrap(JSONSerialization.jsonObject(with: LedgerCodec.encode(original)) as? [String: Any])
            var attachments = try XCTUnwrap(json["attachments"] as? [[String: Any]])
            attachments[0].removeValue(forKey: "byteCount"); json["attachments"] = attachments
            let old = try JSONSerialization.data(withJSONObject: json)
            try FileManager.default.createDirectory(at: local.directory, withIntermediateDirectories: true)
            try old.write(to: local.file)
            XCTAssertEqual(try local.load(), original)
            let stored = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: local.file)) as? [String: Any])
            let metadata = try XCTUnwrap((stored["attachments"] as? [[String: Any]])?.first)
            XCTAssertEqual(stored["schema"] as? Int, 2); XCTAssertNil(metadata["data"])
            XCTAssertEqual(metadata["byteCount"] as? Int, 4); XCTAssertNotNil(metadata["checksum"])
            let payload = local.directory.appendingPathComponent("Attachments/" + original.attachments[0].id.uuidString)
            XCTAssertEqual(try Data(contentsOf: payload), original.attachments[0].data)
            let before = try XCTUnwrap(local.recoveries().first)
            XCTAssertEqual(try Data(contentsOf: before.url), old)
            XCTAssertEqual(try LedgerRepository(directory: local.directory).load(), original)
            XCTAssertEqual(try local.recoveries().count, 1) // Migration is idempotent.
        }
    }
    func testSplitLedgerEncryptedBackupContainsBytesAndRestoresIntoFreshDirectory() throws {
        try withDirectories { root, local, _ in
            let original = ledger("原件"); try local.save(original)
            let reopened = try LedgerRepository(directory: local.directory).load()
            let backup = try Backup.export(reopened, password: "sync-test-password")
            let restored = try Backup.restore(backup, password: "sync-test-password")
            let fresh = LedgerRepository(directory: root.appendingPathComponent("fresh"))
            try fresh.restoreBackup(restored)
            XCTAssertEqual(try fresh.load(), original)
            XCTAssertEqual(try fresh.load().attachments[0].data, original.attachments[0].data)
            let metadataOnly = try LedgerCodec.decode(Data(contentsOf: local.file))
            XCTAssertThrowsError(try Backup.export(metadataOnly)) // Cannot silently export missing bytes.
        }
    }
    func testRecoveryRemainsCompleteWhenLiveAttachmentIsGone() throws {
        try withDirectories { _, local, _ in
            let original = ledger("保留原件"); try local.save(original)
            var next = original; next.entries[0].title = "改过"; next.attachments = []
            try local.save(next)
            let recovery = try XCTUnwrap(local.recoveries().first)
            try FileManager.default.removeItem(at: local.directory.appendingPathComponent("Attachments"))
            XCTAssertEqual(try local.recover(recovery), original)
            XCTAssertEqual(try local.load(), original)
        }
    }
    func testMissingAndSameSizeCorruptAttachmentsFailBeforeReplacement() throws {
        try withDirectories { _, local, _ in
            let original = ledger("附件校验"); try local.save(original)
            let payload = local.directory.appendingPathComponent("Attachments/" + original.attachments[0].id.uuidString)
            let before = try Data(contentsOf: local.file)
            try Data([9, 9, 9, 9]).write(to: payload)
            XCTAssertThrowsError(try local.load()); XCTAssertThrowsError(try local.save(original))
            XCTAssertEqual(try Data(contentsOf: local.file), before)
            XCTAssertTrue(try local.recoveries().isEmpty)
            try FileManager.default.removeItem(at: payload)
            XCTAssertThrowsError(try local.load()); XCTAssertThrowsError(try local.save(original))
            XCTAssertEqual(try Data(contentsOf: local.file), before)
        }
    }
    func testAttachmentTotalIsCheckedSeparatelyFromSmallMetadata() throws {
        var original = ledger("容量")
        original.attachments.append(Attachment(name: "第二份", data: Data([1])))
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: LedgerCodec.encodeMetadata(original)) as? [String: Any])
        var items = try XCTUnwrap(json["attachments"] as? [[String: Any]])
        for index in items.indices { items[index]["byteCount"] = 130 * 1024 * 1024 }
        json["attachments"] = items
        let smallMetadata = try JSONSerialization.data(withJSONObject: json)
        XCTAssertLessThan(smallMetadata.count, 20_000)
        XCTAssertThrowsError(try LedgerCodec.decode(smallMetadata))
    }
    func testEitherConflictChoicePreservesTheOtherCompleteVersionBeforeResolving() throws {
        for chosen in ["0", "1"] {
            try withDirectories { _, local, locations in
                let first = ledger("iPhone"); let second = ledger("Mac")
                let source = Versions([first, second]); let versions = try source.versions()
                let cloud = try locations.repository(for: .iCloud)
                try cloud.save(first)
                source.onResolve = {
                    let saved = try XCTUnwrap(local.recoveries().first)
                    XCTAssertEqual(try local.readRecovery(saved), chosen == "0" ? second : first)
                }
                let selected = try cloud.resolve(versions, choosing: chosen, source: source)
                let expected = chosen == "0" ? first : second
                let other = chosen == "0" ? second : first
                XCTAssertEqual(selected, expected); XCTAssertEqual(try cloud.load(), expected)
                XCTAssertTrue(source.resolved)
                let recovery = try XCTUnwrap(local.recoveries().first { $0.name.hasSuffix("同步冲突时的另一版本") })
                XCTAssertEqual(recovery.url.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL,
                               local.directory.appendingPathComponent("Recovery", isDirectory: true).resolvingSymlinksInPath().standardizedFileURL)
                XCTAssertEqual(try local.recover(recovery), other)
                XCTAssertFalse(FileManager.default.fileExists(atPath: cloud.directory.appendingPathComponent("Recovery").path))
            }
        }
    }
    func testRecoveryAcceptsSymlinkedLedgerDirectoryAndRejectsAnotherLedger() throws {
        try withDirectories { root, local, _ in
            let original = ledger("原始版本"); try local.save(original)
            var next = original; next.entries[0].title = "新版本"; try local.save(next)
            let recovery = try XCTUnwrap(local.recoveries().first)
            let alias = root.appendingPathComponent("linked-local", isDirectory: true)
            try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: local.directory)
            let linked = LedgerRepository(directory: alias)
            XCTAssertEqual(try linked.readRecovery(recovery), original)
            var linkedRecovery = recovery
            linkedRecovery.url = alias.appendingPathComponent("Recovery", isDirectory: true).appendingPathComponent(recovery.url.lastPathComponent)
            XCTAssertEqual(try local.readRecovery(linkedRecovery), original)

            let other = LedgerRepository(directory: root.appendingPathComponent("other"))
            try other.preserveRecovery(ledger("其他账本"), reason: "测试版本")
            let foreign = try XCTUnwrap(other.recoveries().first)
            XCTAssertThrowsError(try linked.readRecovery(foreign))
            XCTAssertEqual(try local.load(), next)
            XCTAssertEqual(try linked.recover(recovery), original)
            XCTAssertEqual(try local.load(), original)
        }
    }
    func testStaleOrInvalidConflictChoiceCannotReplaceLedgerOrResolveVersions() throws {
        try withDirectories { _, local, _ in
            let original = ledger("当前"); try local.save(original)
            let source = Versions([original, ledger("另一份")]); let versions = try source.versions()
            XCTAssertThrowsError(try local.resolve(versions, choosing: "missing", source: source))
            source.stale = true
            XCTAssertThrowsError(try local.resolve(versions, choosing: "1", source: source))
            XCTAssertFalse(source.resolved); XCTAssertEqual(try local.load(), original)
            XCTAssertTrue(try local.recoveries().isEmpty)
        }
    }
    func testEmptyCloudSwitchCopiesLedgerAndAttachments() throws {
        try withDirectories { _, local, locations in
            let original = ledger("本机"); try local.save(original)
            let change = try locations.previewSwitch(to: .iCloud, current: original)
            XCTAssertFalse(change.needsChoice)
            XCTAssertEqual(try locations.completeSwitch(change, choosing: change.versions[0].id), original)
            XCTAssertEqual(try locations.repository(for: .iCloud).load(), original)
            XCTAssertEqual(try local.load(), original)
        }
    }
    func testDifferentCloudRequiresChoiceAndUnchosenLocalVersionIsRecoverable() throws {
        try withDirectories { _, local, locations in
            let original = ledger("本机"); let remote = ledger("云端")
            try local.save(original); try locations.repository(for: .iCloud).save(remote)
            let change = try locations.previewSwitch(to: .iCloud, current: original)
            XCTAssertTrue(change.needsChoice); XCTAssertEqual(change.versions.count, 2)
            XCTAssertEqual(try locations.repository(for: .iCloud).load(), remote) // Preview never overwrites.
            XCTAssertEqual(try locations.completeSwitch(change, choosing: "current"), remote)
            let recovery = try XCTUnwrap(local.recoveries().first)
            XCTAssertTrue(recovery.name.hasSuffix("切换存储时的另一版本"))
            XCTAssertEqual(try local.recover(recovery), original)
        }
    }
    func testSwitchBackCopiesCurrentCloudLedgerLocallyWithoutASecondChoice() throws {
        try withDirectories { _, local, locations in
            let old = ledger("旧本机"); let current = ledger("现在云端")
            try local.save(old); try locations.repository(for: .iCloud).save(current)
            let change = try locations.previewSwitch(to: .local, current: current)
            XCTAssertFalse(change.needsChoice)
            _ = try locations.completeSwitch(change, choosing: change.versions[0].id)
            XCTAssertEqual(try local.load(), current)
            XCTAssertEqual(try locations.repository(for: .iCloud).load(), current)
            XCTAssertFalse(try local.recoveries().isEmpty)
        }
    }
    func testChangedDestinationAfterPreviewIsNotOverwritten() throws {
        try withDirectories { _, local, locations in
            let original = ledger("本机"); let remote = ledger("远端")
            try local.save(original)
            let cloud = try locations.repository(for: .iCloud); try cloud.save(remote)
            let change = try locations.previewSwitch(to: .iCloud, current: original)
            var newer = remote; newer.entries[0].title = "选择期间又更新"
            try cloud.save(newer)
            XCTAssertThrowsError(try locations.completeSwitch(change, choosing: "device"))
            XCTAssertEqual(try cloud.load(), newer)
        }
    }
    func testOptimisticSaveKeepsExternalRevisionUntilUserChooses() throws {
        try withDirectories { _, local, _ in
            var original = ledger("基线"); try local.save(original); _ = try local.load()
            let other = LedgerRepository(directory: local.directory)
            var remote = original; remote.entries[0].title = "外部编辑"; try other.save(remote)
            original.entries[0].title = "本机尚未同步"
            XCTAssertThrowsError(try local.save(original, requiringUnchanged: true))
            XCTAssertEqual(try other.load(), remote)
        }
    }
    func testPendingUploadMarkerSurvivesRestartAndStaysLocal() throws {
        try withDirectories { _, local, locations in
            try local.markPendingSync(true)
            try local.save(ledger("待上传"))
            let reopened = LedgerRepository(directory: local.directory)
            XCTAssertTrue(reopened.hasPendingSync)
            let cloud = try locations.repository(for: .iCloud)
            XCTAssertFalse(FileManager.default.fileExists(atPath: cloud.directory.appendingPathComponent(".icloud-pending").path))
            try reopened.markPendingSync(false)
            XCTAssertFalse(local.hasPendingSync)
        }
    }
    func testUnavailableCloudKeepsDefaultLocalRepositoryAPI() throws {
        try withDirectories { _, local, _ in
            let locations = LedgerLocations(local: local, cloudDirectory: nil)
            XCTAssertEqual(LedgerLocation.local.label, "仅本机")
            XCTAssertThrowsError(try locations.repository(for: .iCloud))
            let original = ledger("离线")
            try locations.repository(for: .local).save(original)
            XCTAssertEqual(try local.load(), original)
        }
    }
}
