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
        ledger.entries[0].attachmentID = ledger.attachments[0].id
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
            XCTAssertEqual(stored["schema"] as? Int, 3); XCTAssertNil(metadata["data"])
            XCTAssertEqual(metadata["byteCount"] as? Int, 4); XCTAssertNotNil(metadata["checksum"])
            let payload = local.directory.appendingPathComponent("Attachments/" + original.attachments[0].id.uuidString)
            XCTAssertEqual(try Data(contentsOf: payload), original.attachments[0].data)
            let before = try XCTUnwrap(local.recoveries().first)
            XCTAssertEqual(try LedgerCodec.decode(local.recoveryBytes(before.url)), original)
            let preserved = try XCTUnwrap(JSONSerialization.jsonObject(with: local.recoveryBytes(before.url)) as? [String: Any])
            XCTAssertNil((preserved["attachments"] as? [[String: Any]])?.first?["data"])
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
            XCTAssertEqual(try fresh.attachmentData(original.attachments[0].id), original.attachments[0].data)
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
    func testLazyAttachmentReadRejectsMissingAndSameSizeCorruptPayloads() throws {
        try withDirectories { _, local, _ in
            let original = ledger("附件校验"); try local.save(original)
            let id = original.attachments[0].id
            let payload = local.directory.appendingPathComponent("Attachments/" + id.uuidString)
            try Data([9, 9, 9, 9]).write(to: payload)
            XCTAssertTrue(try local.load().attachments[0].data.isEmpty)
            XCTAssertThrowsError(try local.attachmentData(id))
            // Saving metadata does not eagerly read or hash every existing payload.
            XCTAssertNoThrow(try local.save(original))
            let recovery = try XCTUnwrap(local.recoveries().first)
            XCTAssertThrowsError(try local.readRecovery(recovery))
            try FileManager.default.removeItem(at: payload)
            XCTAssertNoThrow(try local.load())
            XCTAssertThrowsError(try local.attachmentData(id))
        }
    }
    func testAttachmentTotalMayExceedMetadataCapacityButIndividualLimitRemains() throws {
        var original = ledger("容量")
        original.attachments.append(Attachment(name: "第二份", data: Data([1])))
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: LedgerCodec.encodeMetadata(original)) as? [String: Any])
        var items = try XCTUnwrap(json["attachments"] as? [[String: Any]])
        for index in items.indices { items[index]["byteCount"] = 130 * 1024 * 1024 }
        json["attachments"] = items
        let metadata = try JSONSerialization.data(withJSONObject: json)
        XCTAssertLessThan(metadata.count, 20_000)
        let decoded = try LedgerCodec.decode(metadata)
        XCTAssertGreaterThan(decoded.attachments.reduce(0) { $0 + $1.byteCount }, LedgerCodec.capacity)
        XCTAssertNoThrow(try LedgerCodec.encodeMetadata(decoded))
        items[0]["byteCount"] = LedgerCodec.capacity + 1; json["attachments"] = items
        XCTAssertThrowsError(try LedgerCodec.decode(JSONSerialization.data(withJSONObject: json)))
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
    func testMemoryPreparationIsPersistedBeforeResolvingAndOriginalRemainsRecoverable() throws {
        try withDirectories { _, repository, _ in
            let chosen = ledger("选定交易")
            var other = chosen; other.entries[0].title = "另一版本交易"; other.categoryMemory["午饭"] = "餐饮"
            let source = Versions([chosen, other]); let versions = try source.versions()
            try repository.save(chosen)
            source.onResolve = { XCTAssertEqual(try repository.load().categoryMemory["午饭"], "餐饮") }
            let result = try repository.resolve(versions, choosing: "0", source: source, prepare: { LedgerMemoryMerge.merge(chosen: $0, others: [other]) })
            XCTAssertEqual(result.entries, chosen.entries); XCTAssertEqual(result.categoryMemory, other.categoryMemory)
            XCTAssertEqual(try repository.load(), result); XCTAssertTrue(source.resolved)
            let recovery = try XCTUnwrap(repository.recoveries().first { $0.name.hasSuffix("同步冲突时的另一版本") })
            XCTAssertEqual(try repository.readRecovery(recovery), other)
        }
    }

}

final class LedgerMemoryMergeTests: XCTestCase {
    private let now = Dates.parse("2026-06-17 12:00")!
    func testNewestAreaAndStanceWinAndChosenTransactionsAndFloorStay() throws {
        var chosen = AssistantFixtures.context().ledger
        chosen.profile.updatedAt = Dates.addDays(-10, to: now)
        let area = ProfileArea(title: "外卖", note: "原话", confirmedAt: Dates.addDays(-20, to: now))
        chosen.profile.restrain = [area]
        var other = chosen; other.profile.updatedAt = now
        var updated = area; updated.note = "新的取舍"; updated.confirmedAt = now
        other.profile.restrain = []; other.profile.generous = [updated]
        other.profile.floorAmount = 50_000; other.entries = []
        let result = LedgerMemoryMerge.merge(chosen: chosen, others: [other])
        XCTAssertTrue(result.profile.restrain.isEmpty); XCTAssertEqual(result.profile.generous, [updated])
        XCTAssertEqual(result.profile.updatedAt, now); XCTAssertEqual(result.profile.floorAmount, chosen.profile.floorAmount)
        XCTAssertEqual(result.entries, chosen.entries); XCTAssertEqual(result.accounts, chosen.accounts)
        XCTAssertEqual(LedgerMemoryMerge.merge(chosen: result, others: [other]), result)
        XCTAssertNoThrow(try result.validate())
    }
    func testNewerDeletionDoesNotResurrectAreasOrPrinciplesButNewerAdditionsMerge() throws {
        var chosen = AssistantFixtures.context().ledger; chosen.profile.updatedAt = Dates.addDays(-5, to: now)
        chosen.profile.principles = ["保留"]; chosen.profile.principleDates = ["保留": Dates.addDays(-10, to: now)]
        var old = chosen; old.profile.updatedAt = Dates.addDays(-10, to: now)
        old.profile.restrain = [ProfileArea(title: "已删除", confirmedAt: old.profile.updatedAt)]
        old.profile.principles += ["旧原则"]; old.profile.principleDates["旧原则"] = old.profile.updatedAt
        var newer = old; newer.profile.updatedAt = now
        newer.profile.generous = [ProfileArea(title: "新领域", confirmedAt: now)]
        newer.profile.principles += ["新原则"]; newer.profile.principleDates["新原则"] = now
        newer.profile.principleDates["保留"] = now
        let result = LedgerMemoryMerge.merge(chosen: chosen, others: [old, newer])
        XCTAssertEqual(result.profile.generous.map(\.title), ["新领域"]); XCTAssertTrue(result.profile.restrain.isEmpty)
        XCTAssertEqual(result.profile.principles, ["保留", "新原则"]); XCTAssertNil(result.profile.principleDates["旧原则"])
        XCTAssertEqual(result.profile.principleDates["保留"], now)
        let reverse = LedgerMemoryMerge.merge(chosen: chosen, others: [newer, old])
        XCTAssertEqual(result.profile, reverse.profile)
        XCTAssertNoThrow(try result.validate())
    }
    func testFeedbackEarliestTimeDismissalUnionAndCategoryChosenPriority() throws {
        var chosen = AssistantFixtures.context().ledger
        var card = ButlerCard(kind: .restrain, title: "观察", body: "正文", dedupeKey: "test:memory")
        card.feedback = .regret; card.feedbackAt = now; card.dismissedAt = now
        chosen.cards = [card]; chosen.categoryMemory = ["咖啡": "餐饮"]; chosen.mutedTopics = ["restrain:a"]
        var other = chosen
        other.cards[0].feedback = .worth; other.cards[0].feedbackAt = Dates.addDays(-2, to: now)
        other.cards[0].dismissedAt = Dates.addDays(-1, to: now)
        let proposalID = UUID(); other.cards[0].feedbackProposalID = proposalID
        let second = ButlerCard(kind: .offCharacter, title: "另一观察", body: "", dedupeKey: "test:other")
        other.cards.append(second); other.mutedTopics += ["off:b"]
        other.categoryMemory = ["咖啡": "其他支出", "书": "学习"]
        let result = LedgerMemoryMerge.merge(chosen: chosen, others: [other])
        XCTAssertEqual(result.cards.count, 2); XCTAssertEqual(result.cards[0].feedback, .worth)
        XCTAssertEqual(result.cards[0].feedbackAt, Dates.addDays(-2, to: now))
        XCTAssertEqual(result.cards[0].dismissedAt, Dates.addDays(-1, to: now)); XCTAssertEqual(result.cards[0].feedbackProposalID, proposalID)
        XCTAssertEqual(Set(result.mutedTopics), Set(["restrain:a", "off:b"]))
        XCTAssertEqual(result.categoryMemory, ["咖啡": "餐饮", "书": "学习"])
        var withoutFeedback = chosen; withoutFeedback.cards[0].feedback = nil; withoutFeedback.cards[0].feedbackAt = nil
        XCTAssertEqual(LedgerMemoryMerge.merge(chosen: withoutFeedback, others: [other]).cards[0].feedback, .worth)
        XCTAssertNoThrow(try result.validate())
        var foreign = other; foreign.id = UUID()
        XCTAssertEqual(LedgerMemoryMerge.merge(chosen: chosen, others: [foreign]), chosen)
    }
}

extension LedgerSyncTests {
    func testConcurrentCrossRepositoryHistoryCopiesDoNotInvertLedgerLocks() throws {
        try withDirectories { _, local, locations in
            let cloud = try locations.repository(for: .iCloud)
            let first = try local.save(ledger("本机附件"))
            let second = try cloud.save(ledger("云端附件"))
            let done = DispatchGroup()
            for (repository, snapshot) in [(local, second), (cloud, first)] {
                done.enter()
                DispatchQueue.global().async {
                    defer { done.leave() }
                    do { try repository.preserveRecovery(snapshot, reason: "并发副本") }
                    catch { XCTFail(error.localizedDescription) }
                }
            }
            XCTAssertEqual(done.wait(timeout: .now() + 5), .success)
            XCTAssertEqual(try local.recoveries().count, 2)
        }
    }
}
