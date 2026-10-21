import XCTest
@testable import YubaiCore

final class Schema2Tests: XCTestCase {
    private func fixture(_ name: String = "ledger-schema-1") throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }
    func testMigrationAndStableSchema2RoundTrip() throws {
        let old = try fixture(); let ledger = try LedgerCodec.decode(old)
        XCTAssertEqual(ledger.schema, 2)
        XCTAssertEqual(ledger.goals.first?.reserved, 180000)
        XCTAssertEqual(ledger.rents.first?.monthlyTotal, 480000)
        XCTAssertEqual(ledger.profile.principles, ["超过 2,000 的东西等 48 小时"])
        XCTAssertEqual(ledger.preferences.purchaseValues, ledger.profile.principles[0])
        let wish = try XCTUnwrap(ledger.wishlist.first)
        XCTAssertEqual(wish.id.uuidString, "00000000-0000-4000-8000-000000000007")
        XCTAssertEqual(wish.createdAt, Date(timeIntervalSinceReferenceDate: 812592000 - 86400))
        XCTAssertEqual(wish.status, .thinking); XCTAssertEqual(wish.judgment, "等两天，先确认使用频率。")
        XCTAssertEqual(wish.purpose, "通勤阅读")
        XCTAssertEqual(ledger.advice.first?.result, wish.judgment)
        let bytes = try LedgerCodec.encode(ledger)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        XCTAssertEqual(json["schema"] as? Int, 2); XCTAssertNil(json["advice"]); XCTAssertNil(json["rules"])
        let again = try LedgerCodec.decode(bytes)
        XCTAssertEqual(again, ledger); XCTAssertEqual(try LedgerCodec.encode(again), bytes)
        // Old purchase UI writes through the compatibility property into persistent wishes.
        var edited = again
        edited.advice.insert(AdviceRecord(title: "书", amount: 5000, result: "先借阅", note: "学习"), at: 0)
        XCTAssertEqual(try LedgerCodec.decode(LedgerCodec.encode(edited)), edited)
    }
    func testLegacyEmergencyReserveMigratesToFloorForBothSchemas() throws {
        let schema1 = try LedgerCodec.decode(fixture())
        XCTAssertEqual(schema1.profile.floorAmount, 50000)
        XCTAssertEqual(Finance.funds(schema1, now: schema1.updatedAt).emergency, 50000)
        var oldSchema2 = schema1; oldSchema2.profile.floorAmount = nil
        let schema2 = try LedgerCodec.decode(LedgerCodec.encode(oldSchema2))
        XCTAssertEqual(schema2.profile.floorAmount, 50000)
        XCTAssertEqual(Finance.funds(schema2, now: schema2.updatedAt).emergency, 50000)
    }
    func testLegacyEmergencyReserveDoesNotOverrideExplicitFloor() throws {
        var ledger = try LedgerCodec.decode(fixture())
        for floor in [Int64(150000), 0] {
            ledger.profile.floorAmount = floor
            let decoded = try LedgerCodec.decode(LedgerCodec.encode(ledger))
            XCTAssertEqual(decoded.profile.floorAmount, floor)
            XCTAssertEqual(Finance.funds(decoded, now: decoded.updatedAt).emergency, floor)
        }
    }
    func testDefaultPurchaseValuesDoNotBecomePrincipleAndNewFieldsHaveDefaults() throws {
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: fixture()) as? [String: Any])
        var preferences = try XCTUnwrap(json["preferences"] as? [String: Any])
        preferences["purchaseValues"] = Preferences().purchaseValues; json["preferences"] = preferences
        let ledger = try LedgerCodec.decode(JSONSerialization.data(withJSONObject: json))
        XCTAssertTrue(ledger.profile.principles.isEmpty); XCTAssertTrue(ledger.cards.isEmpty)
        XCTAssertTrue(ledger.pendingChanges.isEmpty); XCTAssertTrue(ledger.mutedTopics.isEmpty)
        var legacy = ledger; legacy.schema = 1; XCTAssertNoThrow(try legacy.validate())
        XCTAssertEqual(try LedgerCodec.decode(LedgerCodec.encode(legacy)).schema, 2)
    }
    func testFirstMigrationSavePreservesExactOriginalAndOnlyLabelsOnce() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("yubai-migrate-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let repo = LedgerRepository(directory: root); let old = try fixture(); try old.write(to: repo.file)
        var ledger = try repo.load(); XCTAssertEqual(try repo.recoveries().count, 1)
        ledger.entries[0].category = "日用购物"; try repo.save(ledger, reason: "修改分类")
        let history = try repo.recoveries(); let before = try XCTUnwrap(history.first { $0.name.hasSuffix("升级前版本") })
        XCTAssertTrue(before.name.hasSuffix("升级前版本")); XCTAssertEqual(try repo.recoveryBytes(before.url), old)
        try repo.save(ledger)
        XCTAssertEqual(try repo.recoveries().filter { $0.name.hasSuffix("升级前版本") }.count, 1)
        XCTAssertEqual(try repo.recover(before).entries[0].category, "餐饮")
    }
    func testMigratedLedgerSavedToNewRepositoryRetainsSource() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("yubai-migrate-fresh-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let bytes = try fixture(); let repo = LedgerRepository(directory: root)
        try repo.save(LedgerCodec.decode(bytes))
        let recovery = try XCTUnwrap(repo.recoveries().first)
        XCTAssertTrue(recovery.name.hasSuffix("升级前版本"))
        XCTAssertEqual(try repo.recoveryBytes(recovery.url), bytes)
    }
    func testOldEncryptedBackupRestoresMigratesAndPreservesLegacySource() throws {
        // Fixed synthetic v1 backup created independently with PBKDF2-SHA256/AES-GCM.
        let data = try fixture("ledger-schema-1-encrypted")
        let restored = try Backup.restore(data, password: "legacy-test-password")
        XCTAssertEqual(restored, try LedgerCodec.decode(fixture()))
        XCTAssertThrowsError(try Backup.restore(data, password: "incorrect"))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("yubai-legacy-backup-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = LedgerRepository(directory: root); try repo.restoreBackup(restored)
        XCTAssertEqual(try repo.load(), restored)
        let recovery = try XCTUnwrap(repo.recoveries().first { $0.name.hasSuffix("升级前版本") })
        XCTAssertEqual(try repo.recoveryBytes(recovery.url), try fixture())
        XCTAssertEqual(try Backup.restore(Backup.export(restored, password: "new-test-password"), password: "new-test-password"), restored)
    }
    func testSchema2RelationshipsAndValidation() throws {
        var ledger = try LedgerCodec.decode(fixture())
        let change = ChangeSet(source: "测试", reason: "整理", items: [.profile(.addPrinciple("先借后买"))])
        ledger.pendingChanges = [change]
        var card = ButlerCard(kind: .followUp, title: "待确认", body: "画像", evidence: [UUID()], action: .confirmChangeSet(change.id), dedupeKey: "profile")
        card.feedback = .worth; ledger.cards = [card]; ledger.mutedTopics = ["coffee"]
        ledger.wishlist[0].status = .bought; ledger.wishlist[0].boughtEntryID = ledger.entries[0].id
        ledger.wishlist[0].followUpAt = ledger.updatedAt; ledger.wishlist[0].followUpAnswer = "值得"
        XCTAssertEqual(try LedgerCodec.decode(LedgerCodec.encode(ledger)), ledger) // Missing evidence is tolerated.
        var invalid = ledger; invalid.cards.append(card); XCTAssertThrowsError(try invalid.validate())
        invalid = ledger; invalid.pendingChanges.append(change); XCTAssertThrowsError(try invalid.validate())
        invalid = ledger; invalid.wishlist.append(ledger.wishlist[0]); XCTAssertThrowsError(try invalid.validate())
        invalid = ledger; invalid.mutedTopics.append("coffee"); XCTAssertThrowsError(try invalid.validate())
        invalid = ledger; invalid.profile.floorAmount = -1; XCTAssertThrowsError(try invalid.validate())
        var area = ProfileArea(title: "外卖", softLimit: SoftLimit(perWeekCount: -1))
        invalid = ledger; invalid.profile.restrain = [area]; XCTAssertThrowsError(try invalid.validate())
        area.softLimit = nil; invalid.profile.restrain = [area]; invalid.profile.generous = [area]
        XCTAssertThrowsError(try invalid.validate())
        invalid = ledger; invalid.cards = Array(repeating: card, count: 5001); XCTAssertThrowsError(try invalid.validate())
    }
    func testFinanceFloorOverridesEmergencyEverywhereAndGoalsStayReserved() throws {
        var ledger = try LedgerCodec.decode(fixture()); let now = ledger.updatedAt
        let before = Finance.funds(ledger, now: now)
        ledger.profile.floorAmount = 150000
        let after = Finance.funds(ledger, now: now)
        XCTAssertEqual(after.emergency, 150000); XCTAssertEqual(after.goals, before.goals)
        XCTAssertEqual(after.available, before.available - 100000)
        for (a, b) in zip(after.points, before.points) {
            XCTAssertEqual(a.conservative, b.conservative - 100000); XCTAssertEqual(a.expected, b.expected - 100000)
        }
        ledger.profile.floorAmount = 0; XCTAssertEqual(Finance.funds(ledger, now: now).emergency, 0)
        ledger.profile.floorAmount = nil; XCTAssertEqual(Finance.funds(ledger, now: now).available, before.available + before.emergency)
    }
}
