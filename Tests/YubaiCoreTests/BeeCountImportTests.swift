import XCTest
@testable import YubaiCore

private struct FailingColumnMapper: ImportColumnMapper {
    func map(headers: [String], samples: [[String]]) async throws -> ImportColumnMapping {
        XCTFail("A structured export must never use cloud column mapping")
        throw ImportColumnError.invalid
    }
}

final class BeeCountImportTests: XCTestCase {
    private func fixture() throws -> Data {
        try Data(contentsOf: XCTUnwrap(Bundle.module.url(forResource: "beecount-sample", withExtension: "csv", subdirectory: "Fixtures")))
    }
    private func ledger() -> Ledger {
        var ledger = Ledger(); ledger.accounts = [Account(name: "银行卡"), Account(name: "微信")]
        ledger.categoryAliases = ["早餐": "餐饮", "公交": "交通", "数码": "购物"]
        return ledger
    }
    func testLocalBOMWhitespaceFallbacksTransferAndReimport() throws {
        var ledger = ledger(); let bytes = try fixture()
        XCTAssertTrue(bytes.starts(with: [0xEF, 0xBB, 0xBF]))
        let preview = try BillImporter.preview(data: bytes, filename: "beecount.csv", accountID: ledger.accounts[0].id, ledger: ledger)
        XCTAssertEqual(preview.source, "BeeCount"); XCTAssertEqual(preview.readyCount, 8); XCTAssertEqual(preview.issueCount, 0)
        let entries = preview.selectedEntries
        XCTAssertEqual(entries.map(\.amount), [2350, 1280, 45025, 1200000, 8990, 30000, 200, 2350])
        XCTAssertEqual(entries.map(\.nature), [.expense, .expense, .income, .income, .expense, .transfer, .expense, .expense])
        XCTAssertEqual(entries.map(\.title), ["餐饮", "豆浆套餐", "春季奖励", "工资", "键盘腕托", "日常备用金", "公交", "餐饮"])
        XCTAssertEqual(entries.map(\.category), ["餐饮", "餐饮", "工资奖金", "工资奖金", "购物", "账户往来", "交通", "餐饮"])
        XCTAssertEqual(entries[1].subcategory, "早餐"); XCTAssertEqual(entries[2].subcategory, "奖金"); XCTAssertEqual(entries[3].subcategory, "工资")
        XCTAssertTrue(entries.allSatisfy { $0.source == "BeeCount" && $0.accountID == ledger.accounts[0].id })
        XCTAssertEqual(entries[0].date, Dates.parse("2026-04-03 08:10:30"))
        XCTAssertEqual(entries[5].otherAccountID, ledger.accounts[1].id)
        XCTAssertEqual(entries[5].delta(for: ledger.accounts[0].id), -30000)
        XCTAssertEqual(entries[5].delta(for: ledger.accounts[1].id), 30000)
        _ = try BillImporter.commit(preview, data: bytes, to: &ledger)
        let second = try BillImporter.preview(data: bytes, filename: "same-file.csv", accountID: ledger.accounts[0].id, ledger: ledger)
        XCTAssertEqual(second.duplicateCount, 8); XCTAssertTrue(second.selectedEntries.isEmpty)
        XCTAssertTrue(second.rows.allSatisfy { $0.status == .duplicate })
    }
    func testKnownExportDoesNotCallMapper() async throws {
        let ledger = ledger()
        let result = try await BillImporter.preview(data: fixture(), filename: "bee.csv", accountID: ledger.accounts[0].id,
            ledger: ledger, columnMapper: FailingColumnMapper())
        XCTAssertEqual(result.readyCount, 8)
    }
    func testUnknownTransferAccountsNeedExplicitMappingAndNeverGuess() throws {
        var ledger = ledger(); ledger.accounts[1].name = "微信零钱"
        let bytes = try fixture()
        let first = try BillImporter.preview(data: bytes, filename: "bee.csv", accountID: ledger.accounts[0].id, ledger: ledger)
        XCTAssertEqual(first.rows[5].status, .needsAccount); XCTAssertFalse(first.rows[5].included)
        XCTAssertNil(first.rows[5].entry?.otherAccountID)
        let mapped = try BillImporter.preview(data: bytes, filename: "bee.csv", accountID: ledger.accounts[0].id, ledger: ledger,
            accountMappings: ["微信": ledger.accounts[1].id])
        XCTAssertEqual(mapped.readyCount, 8); XCTAssertEqual(mapped.rows[5].entry?.otherAccountID, ledger.accounts[1].id)
        ledger.accounts.append(Account(name: "银行卡"))
        let ambiguous = try BillImporter.preview(data: bytes, filename: "bee.csv", accountID: ledger.accounts[0].id, ledger: ledger,
            accountMappings: ["微信": ledger.accounts[1].id])
        XCTAssertEqual(ambiguous.rows[5].status, .needsAccount)
    }
    func testGenericAliasesAndDirectionValues() throws {
        let ledger = ledger()
        for (date, direction, category, subcategory, account, note) in [
            ("日期", "收支类型", "一级分类", "二级分类", "账户", "备注"),
            ("记账时间", "类型", "类别", "子分类", "帐户", "说明"),
            ("date", "flow", "category", "subcategory", "account", "memo")
        ] {
            let csv = "\(date),\(direction),\(category),\(subcategory),金额,\(account),\(note)\n2026-04-03,收入,职业收入,奖金,25.25,,\n"
            let preview = try BillImporter.preview(data: Data(csv.utf8), filename: "generic.csv", accountID: ledger.accounts[0].id, ledger: ledger)
            XCTAssertEqual(preview.readyCount, 1); XCTAssertEqual(preview.selectedEntries.first?.nature, .income)
            XCTAssertEqual(preview.selectedEntries.first?.title, "奖金"); XCTAssertEqual(preview.selectedEntries.first?.category, "工资奖金")
        }
    }
}

extension BeeCountImportTests {
    func testCategoryOverridesPersistThroughCommitWithoutChangingSourceIdentity() throws {
        var ledger = Ledger(); ledger.accounts = [Account(name: "银行卡")]
        ledger.categoryAliases = ["周游": "旅行"]
        let bytes = Data("日期,收支,金额,用途,分类\n2026-10-01,支出,24.80,车票,周游\n2026-10-02,收入,10.00,礼物,礼金赠与\n".utf8)
        let original = try BillImporter.preview(data: bytes, filename: "a.csv", accountID: ledger.accounts[0].id, ledger: ledger)
        let mapped = try BillImporter.preview(data: bytes, filename: "a.csv", accountID: ledger.accounts[0].id,
            ledger: ledger, categoryMappings: ["旅行": "其他支出"])
        XCTAssertEqual(original.selectedEntries[0].category, "旅行")
        XCTAssertEqual(mapped.rows.map(\.sourceCategory), ["旅行", "礼金赠与"])
        XCTAssertEqual(mapped.selectedEntries.map(\.category), ["其他支出", "礼金赠与"])
        XCTAssertTrue(mapped.selectedEntries[0].userEdited); XCTAssertFalse(mapped.selectedEntries[1].userEdited)
        XCTAssertEqual(original.selectedEntries.map(\.fingerprint), mapped.selectedEntries.map(\.fingerprint))
        _ = try BillImporter.commit(mapped, data: bytes, to: &ledger)
        XCTAssertEqual(ledger.entries.map(\.category), ["其他支出", "礼金赠与"])
        XCTAssertEqual(ledger.categoryAliases, ["周游": "旅行"])
        let again = try BillImporter.preview(data: bytes, filename: "a.csv", accountID: ledger.accounts[0].id,
            ledger: ledger, categoryMappings: ["旅行": "旅行"])
        XCTAssertEqual(again.duplicateCount, 2)
        XCTAssertTrue(again.selectedEntries.isEmpty)
        XCTAssertThrowsError(try BillImporter.preview(data: bytes, filename: "a.csv", accountID: ledger.accounts[0].id,
            ledger: ledger, categoryMappings: ["旅行": " "]))
    }
    func testNewCategoryAndKnownExportOverridesStayLocal() async throws {
        var ledger = Ledger(); ledger.accounts = [Account(name: "银行卡")]
        let bytes = Data("日期,收支,金额,用途,分类\n2026-10-01,支出,24.80,车票,旅行\n".utf8)
        let preview = try await BillImporter.preview(data: bytes, filename: "a.csv", accountID: ledger.accounts[0].id,
            ledger: ledger, categoryMappings: ["旅行": "旅行"], columnMapper: FailingColumnMapper())
        ledger.categories.append(Category("旅行"))
        _ = try BillImporter.commit(preview, data: bytes, to: &ledger)
        XCTAssertEqual(ledger.entries.first?.category, "旅行"); XCTAssertTrue(ledger.entries.first?.userEdited == true)
    }
}

extension BeeCountImportTests {
    func testScreenshotIdentitySurvivesMissingDateCorrectionAndKeepsEqualAmountRowsSeparate() throws {
        var ledger = Ledger(); ledger.accounts = [Account(name: "卡")]
        let image = Data("synthetic image bytes".utf8)
        func preview(_ day: String, ledger: Ledger) throws -> ImportPreview {
            let bytes = Data("日期,收支,金额,用途\n\(day),支出,18.00,咖啡\n\(day),支出,18.00,咖啡\n".utf8)
            let parsed = try BillImporter.preview(data: bytes, filename: "screenshot.png", accountID: ledger.accounts[0].id, ledger: ledger)
            return BillImporter.screenshotPreview(parsed, original: image, ledger: ledger)
        }
        var first = try preview("2026-10-01", ledger: ledger)
        XCTAssertTrue(first.selectedEntries.isEmpty); XCTAssertEqual(first.readyCount, 2)
        XCTAssertEqual(Set(first.rows.compactMap { $0.entry?.fingerprint }).count, 2)
        first.rows[0].included = true
        first.rows[0].entry?.date = try XCTUnwrap(Dates.parse("2026-09-01"))
        _ = try BillImporter.commit(first, data: image, to: &ledger)
        let nextDay = try preview("2026-10-02", ledger: ledger)
        XCTAssertEqual(nextDay.rows.map(\.status), [.duplicate, .ready])
        XCTAssertTrue(nextDay.selectedEntries.isEmpty)
        XCTAssertEqual(nextDay.rows[0].entry?.fingerprint, first.rows[0].entry?.fingerprint)
        BillImporter.undo(batchID: ledger.imports[0].id, in: &ledger)
        XCTAssertEqual(try preview("2026-10-03", ledger: ledger).readyCount, 2)
    }
}
