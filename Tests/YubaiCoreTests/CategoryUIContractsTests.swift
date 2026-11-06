import XCTest
@testable import YubaiCore

final class CategoryUIContractsTests: XCTestCase {
    private func ledger() -> Ledger {
        var ledger = Ledger()
        ledger.accounts = [Account(name: "现金", kind: .cash)]
        return ledger
    }
    private func row(_ ledger: Ledger, purpose: String? = nil, note: String = "") -> Entry {
        var row = Entry(amount: 1000, accountID: ledger.accounts[0].id, title: "合成记录")
        row.purpose = purpose; row.note = note
        return row
    }
    private func load(_ ledger: Ledger, legacy: Bool = true) throws -> Ledger {
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: LedgerCodec.encode(ledger)) as? [String: Any])
        if legacy { json.removeValue(forKey: "manualNotesMerged") }
        return try LedgerCodec.decode(JSONSerialization.data(withJSONObject: json))
    }

    func testManualNoteMigrationMergesEmptyAndExistingPurposeOnce() throws {
        var ledger = ledger()
        var assistant = row(ledger, purpose: "咖啡", note: "和朋友"); assistant.source = "问余白"
        ledger.entries = [row(ledger, note: "午饭"), row(ledger, purpose: "", note: "晚饭"), assistant,
                          row(ledger, purpose: "原用途")]
        let migrated = try load(ledger)
        XCTAssertEqual(migrated.entries.map(\.purpose), ["午饭", "晚饭", "咖啡 · 和朋友", "原用途"])
        XCTAssertTrue(migrated.entries.allSatisfy { $0.note.isEmpty })
        XCTAssertTrue(migrated.manualNotesMerged)
        XCTAssertEqual(try load(migrated, legacy: false), migrated)
    }

    func testMigrationSkipsEveryImportedProvenanceIncludingEditedSourceLabel() throws {
        var ledger = ledger()
        let imported: [(inout Entry) -> Void] = [
            { $0.source = "文件" }, { $0.source = "BeeCount" }, { $0.source = "微信" },
            { $0.source = "支付宝" }, { $0.source = "截图" }, { $0.batchID = UUID() },
            { $0.sourceRow = 2 }, { $0.externalID = "bank-id" }, { $0.sourceIdentity = "identity" },
            { $0.fingerprint = "fingerprint" }, { $0.source = "Apple Pay" }, { $0.source = "自动扣款" }
        ]
        ledger.entries = imported.map { mark in var value = row(ledger, purpose: "用途", note: "银行原文"); mark(&value); return value }
        XCTAssertEqual(try load(ledger).entries, ledger.entries)
    }

    func testMigrationHonorsValidationLimitAtCharacterBoundaries() throws {
        var ledger = ledger()
        ledger.entries = [row(ledger, purpose: String(repeating: "用", count: 3998), note: "备注"),
                          row(ledger, note: String(repeating: "🧑🏽‍💻", count: 4001))]
        let migrated = try load(ledger)
        XCTAssertEqual(migrated.entries.map { $0.purpose?.count }, [4000, 4000])
        XCTAssertEqual(migrated.entries[0].purpose, String(repeating: "用", count: 3998) + " ·")
        XCTAssertEqual(migrated.entries[1].purpose?.last, "🧑🏽‍💻")
        XCTAssertTrue(migrated.entries.allSatisfy { $0.note.isEmpty })
        try migrated.validate()
    }

    func testMigrationAlsoUpdatesRetainedUndoAndDoesNotMigrateNewNotes() throws {
        var ledger = ledger()
        let old = row(ledger, purpose: "午饭", note: "合成备注")
        var undo = ImportUndo(updatedAt: ledger.updatedAt); undo.entries = [old]
        var batch = ImportBatch(filename: "合成.csv", importedCount: 0, duplicateCount: 0, skippedCount: 0)
        batch.undo = undo; ledger.imports = [batch]; ledger.entries = [old]
        var migrated = try load(ledger)
        XCTAssertEqual(migrated.imports[0].undo?.entries, migrated.entries)
        migrated.entries[0].note = "迁移后写的备注"
        XCTAssertEqual(try load(migrated, legacy: false), migrated)
    }

    func testMigrationPersistsAndDoesNotDoubleAppendOnRepositorySecondLoad() throws {
        var ledger = ledger(); ledger.manualNotesMerged = false
        ledger.entries = [row(ledger, purpose: "用途", note: "备注")]
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = LedgerRepository(directory: directory)
        try repository.save(ledger)
        let first = try repository.load()
        XCTAssertEqual(first.entries[0].purpose, "用途 · 备注")
        try repository.save(first)
        XCTAssertEqual(try repository.load(), first)
    }

    func testColloquialKeywordsResolveBothLevelsAndIncomeDirection() throws {
        let ledger = ledger()
        let cases: [(String, Nature, String)] = [
            ("剪头发", .expense, "美容个护/理发"), ("剪头", .expense, "美容个护/理发"),
            ("洗头", .expense, "美容个护/理发"), ("洗剪吹", .expense, "美容个护/理发"),
            ("理发店", .expense, "美容个护/理发"), ("发廊", .expense, "美容个护/理发"),
            ("洗车", .expense, "交通/养车"), ("保养", .expense, "交通/养车"),
            ("换机油", .expense, "交通/养车"), ("交保险", .expense, "保险税费/保险"),
            ("交税", .expense, "保险税费/税费"), ("买菜", .expense, "餐饮/买菜做饭"),
            ("寄东西", .expense, "购物/快递"), ("请阿姨", .expense, "居住/家政保洁"),
            ("给爸妈", .expense, "人情家庭/孝敬长辈"), ("捐钱", .expense, "人情家庭/捐赠"),
            ("提公积金", .income, "工资奖金/公积金"), ("卖闲置", .income, "二手转卖")
        ]
        for (text, nature, path) in cases {
            XCTAssertEqual(CategoryGuesser.guess(text, nature: nature, in: ledger)?.path, path, text)
        }
        XCTAssertNil(CategoryGuesser.guess("剪头发", nature: .income, in: ledger))
    }

    func testPickerOrderUsesPreferencesStableFallbackAndOtherLast() throws {
        var ledger = ledger()
        ledger.preferences.categoryOrder = ["其他支出", "交通", "美容个护", "交通", "不存在", "工资奖金"]
        try CategoryModel.add(Category("手作"), in: &ledger)
        try CategoryModel.setHidden(true, category: "购物", income: false, in: &ledger)
        let names = ledger.orderedCategories(income: false).map(\.name)
        XCTAssertEqual(Array(names.prefix(3)), ["交通", "美容个护", "餐饮"])
        XCTAssertEqual(names.suffix(2), ["手作", "其他支出"])
        XCTAssertFalse(names.contains("购物")); XCTAssertFalse(names.contains("工资奖金"))
        XCTAssertEqual(ledger.orderedCategories(income: false, hidden: true).map(\.name), ["购物"])
        XCTAssertEqual(ledger.orderedCategories(income: true).last?.name, "其他收入")
    }

    func testExplicitMainOnlyOverridesGuessAndRemembersMainOnly() throws {
        var ledger = ledger()
        var entry = row(ledger, purpose: "剪头发"); entry.title = "合成理发店"
        ledger.entries = [entry]
        let change = ChangeSet(source: "按对方分", reason: "合成确认", items: [.setCategory(entry: entry.id, category: "美容个护")])
        _ = try change.apply(to: &ledger)
        XCTAssertEqual(ledger.entries[0].subcategory, "理发")
        try CategoryModel.confirm(.init(category: "美容个护"), entryIDs: [entry.id], includingParty: true, in: &ledger)
        XCTAssertNil(ledger.entries[0].subcategory); XCTAssertTrue(ledger.entries[0].subcategoryUserEdited)
        XCTAssertEqual(ledger.classificationMemory[CategoryMemory.key("合成理发店")], "美容个护")
        SubcategoryClassifier.classify(&ledger.entries[0], ledger: ledger)
        XCTAssertNil(ledger.entries[0].subcategory)
    }

    func testAdditionAndSubcategoryConfirmAreAtomicAndScopedUndoRestoresRowsAndMemory() throws {
        var ledger = ledger(); let entry = row(ledger); ledger.entries = [entry]
        let before = ledger
        let addition = CategoryAddition(name: "头皮护理", parent: "美容个护", income: false)
        try addition.apply(to: &ledger)
        _ = try ChangeSet(source: "按对方分", reason: "合成确认", items: [.setCategory(entry: entry.id, category: addition.assignment.category)]).apply(to: &ledger)
        try CategoryModel.confirm(addition.assignment, entryIDs: [entry.id], includingParty: true, in: &ledger)
        XCTAssertEqual(ledger.entries[0].subcategory, "头皮护理")
        XCTAssertEqual(ledger.classificationMemory[CategoryMemory.key(entry.title)], addition.assignment.path)
        let undo = UnsortedGroupsUndo(before: before, after: ledger, entryIDs: [entry.id])
        undo.restore(in: &ledger)
        XCTAssertEqual(ledger.entries, before.entries); XCTAssertEqual(ledger.classificationMemory, before.classificationMemory)
        XCTAssertTrue(ledger.categories.first { $0.name == "美容个护" }!.subcategories.contains("头皮护理"))
    }

    func testConfirmRejectsWrongDirectionOrSmallItemWithoutChangingLedger() throws {
        var ledger = ledger(); ledger.entries = [row(ledger)]
        let before = ledger
        XCTAssertThrowsError(try CategoryModel.confirm(.init(category: "工资奖金"), entryIDs: [ledger.entries[0].id], in: &ledger))
        XCTAssertThrowsError(try CategoryModel.confirm(.init(category: "美容个护", subcategory: "不存在"), entryIDs: [ledger.entries[0].id], in: &ledger))
        XCTAssertEqual(ledger, before)
        XCTAssertThrowsError(try CategoryAddition(name: "小项", parent: "其他支出", income: false).apply(to: &ledger))
        XCTAssertEqual(ledger, before)
    }
}
