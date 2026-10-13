import XCTest
@testable import YubaiCore

final class ImportTests: XCTestCase {
    func ledger() -> Ledger { var l = Ledger(); l.accounts = [Account(name: "银行卡")]; return l }
    func file(_ name: String) throws -> Data { try Data(contentsOf: Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures")!) }
    func testQuotedCSVMultilineAndBOM() throws {
        let text = "\u{FEFF}日期,名称,金额\r\n2026-09-20,\"咖啡,\"\"双份\"\"\n第二行\",22.00\r\n"
        let rows = try CSV.parse(CSV.decode(Data(text.utf8))); XCTAssertEqual(rows.count, 2); let last = try XCTUnwrap(rows.last); XCTAssertGreaterThan(last.count, 1); if last.count > 1 { XCTAssertEqual(last[1], "咖啡,\"双份\"\n第二行") }
        XCTAssertThrowsError(try CSV.parse("a,b\n\"broken"))
    }
    func testWeChatPreambleIDsAndIncompleteRows() throws {
        let l = ledger(); let p = try BillImporter.preview(data: file("wechat.csv"), filename: "wechat.csv", accountID: l.accounts[0].id, ledger: l)
        XCTAssertEqual(p.source, "微信"); XCTAssertEqual(p.readyCount, 3)
        XCTAssertEqual(p.rows.filter { $0.status == .skipped }.count, 1)
        XCTAssertEqual(p.rows.filter { $0.status == .invalid }.count, 1)
        XCTAssertEqual(p.selectedEntries.first?.amount, 2800)
        XCTAssertEqual(p.selectedEntries.first?.category, "餐饮")
        XCTAssertEqual(p.selectedEntries.last?.nature, .unknownIn)
    }
    func testReimportKeepsUserEditsAndDeletedTombstones() throws {
        var l = ledger(); let bytes = try file("wechat.csv")
        let first = try BillImporter.preview(data: bytes, filename: "wechat.csv", accountID: l.accounts[0].id, ledger: l)
        let batch = try BillImporter.commit(first, data: bytes, to: &l)
        l.entries[0].amount = 2900; l.entries[0].category = "我的餐食"; l.entries[0].userEdited = true
        l.entries[1].deletedAt = Date()
        let second = try BillImporter.preview(data: bytes, filename: "wechat.csv", accountID: l.accounts[0].id, ledger: l)
        XCTAssertEqual(second.duplicateCount, 3); XCTAssertEqual(second.readyCount, 0); XCTAssertEqual(l.entries[0].amount, 2900)
        BillImporter.undo(batchID: batch.id, in: &l); XCTAssertEqual(l.activeEntries.count, 0)
        XCTAssertEqual(l.attachments[0].data, bytes)
    }
    func testSourceIdAmountConflictDoesNotOverwrite() throws {
        var l = ledger(); let bytes = try file("wechat.csv"); let first = try BillImporter.preview(data: bytes, filename: "wechat.csv", accountID: l.accounts[0].id, ledger: l); _ = try BillImporter.commit(first, data: bytes, to: &l)
        let changed = String(data: bytes, encoding: .utf8)!.replacingOccurrences(of: "28.00", with: "88.00")
        let p = try BillImporter.preview(data: Data(changed.utf8), filename: "wechat.csv", accountID: l.accounts[0].id, ledger: l)
        XCTAssertEqual(p.rows.filter { $0.status == .conflict }.count, 1); XCTAssertEqual(l.entries[0].amount, 2800)
    }
    func testCrossSourceSimilarTransactionNeedsConfirmation() throws {
        var l = ledger(); var e = Entry(date: Dates.parse("2026-09-20 12:30:00")!, amount: 2800, accountID: l.accounts[0].id, title: "手动午餐"); e.source = "手动"; l.entries = [e]
        let p = try BillImporter.preview(data: file("wechat.csv"), filename: "wechat.csv", accountID: l.accounts[0].id, ledger: l)
        XCTAssertEqual(p.rows[0].status, .possibleDuplicate); XCTAssertFalse(p.rows[0].included)
    }
    func testGB18030Alipay() throws {
        let l = ledger(); let p = try BillImporter.preview(data: file("alipay-gb18030.csv"), filename: "alipay.csv", accountID: l.accounts[0].id, ledger: l)
        XCTAssertEqual(p.source, "支付宝"); XCTAssertEqual(p.selectedEntries.count, 2); XCTAssertEqual(p.selectedEntries[0].amount, 123456); XCTAssertEqual(p.selectedEntries[1].nature, .refund)
    }
    func testRealXLSXZipSharedStringsAndNumericDates() throws {
        let l = ledger(); let p = try BillImporter.preview(data: file("bank.xlsx"), filename: "bank.xlsx", accountID: l.accounts[0].id, ledger: l)
        XCTAssertEqual(p.selectedEntries.count, 2); XCTAssertEqual(p.selectedEntries[0].amount, 3200); XCTAssertEqual(Dates.text(p.selectedEntries[0].date), "2026-09-20")
        XCTAssertEqual(p.selectedEntries[1].nature, .income)
    }
    func testCorruptedSpreadsheetIsRejected() throws {
        var data = try file("bank.xlsx"); data[45] ^= 0xFF
        XCTAssertThrowsError(try XLSX.read(data))
        XCTAssertThrowsError(try XLSX.read(Data("not a zip".utf8)))
    }
    func testExportEscapesFormulaInjectionAndKeepsDecimalPrecision() throws {
        var l = ledger(); l.entries = [Entry(amount: 1, accountID: l.accounts[0].id, title: "=HYPERLINK(\"x\")")]
        let exported = String(data: CSV.export(l), encoding: .utf8)!
        XCTAssertTrue(exported.contains("'=")); XCTAssertTrue(exported.contains("\"0.01\""))
    }
    func testBatchOf4000AndSecondImport() throws {
        var l = ledger(); let rows = (0..<4000).map { i in "2026-09-20 12:30:00,支出,\(i + 1).01,午餐\(i),bill\(i)" }
        let data = Data((["时间,收支,金额,名称,交易单号"] + rows).joined(separator: "\n").utf8)
        let start = Date(); let preview = try BillImporter.preview(data: data, filename: "4000.csv", accountID: l.accounts[0].id, ledger: l)
        XCTAssertEqual(preview.selectedEntries.count, 4000); _ = try BillImporter.commit(preview, data: data, to: &l)
        let repeatImport = try BillImporter.preview(data: data, filename: "4000.csv", accountID: l.accounts[0].id, ledger: l)
        XCTAssertEqual(repeatImport.duplicateCount, 4000); XCTAssertEqual(l.activeEntries.count, 4000)
        print("PERF 4000 parse + commit + reimport: \(Date().timeIntervalSince(start)) seconds")
    }
    func testIdenticalLegitimateRowsAreNotSilentlyDiscarded() throws {
        var l = ledger(); let bytes = Data("时间,收支,金额,名称\n2026-09-20,支出,10.00,早餐\n2026-09-20,支出,10.00,早餐\n".utf8)
        let p = try BillImporter.preview(data: bytes, filename: "bank.csv", accountID: l.accounts[0].id, ledger: l)
        XCTAssertEqual(p.selectedEntries.count, 2); _ = try BillImporter.commit(p, data: bytes, to: &l)
        let again = try BillImporter.preview(data: bytes, filename: "bank.csv", accountID: l.accounts[0].id, ledger: l)
        XCTAssertEqual(again.duplicateCount, 2)
        let distinct = Data("时间,收支,金额,名称,交易单号\n2026-09-20,支出,10.00,早餐,A\n2026-09-20,支出,10.00,早餐,B\n".utf8)
        let fresh = ledger(); XCTAssertEqual(try BillImporter.preview(data: distinct, filename: "bank.csv", accountID: fresh.accounts[0].id, ledger: fresh).selectedEntries.count, 2)
    }
    func testBankLocalIdsAreScopedToAccountAndRefundCanShareOriginalId() throws {
        var l = ledger(); l.accounts.append(Account(name: "另一银行")); let bytes = Data("时间,收支,金额,名称,交易单号\n2026-09-20,支出,10.00,早餐,1\n".utf8)
        let p = try BillImporter.preview(data: bytes, filename: "bank.csv", accountID: l.accounts[0].id, ledger: l); _ = try BillImporter.commit(p, data: bytes, to: &l)
        let second = try BillImporter.preview(data: bytes, filename: "bank2.csv", accountID: l.accounts[1].id, ledger: l); XCTAssertEqual(second.selectedEntries.count, 1)
        let refund = Data("时间,收支,金额,名称,交易单号,类型\n2026-09-21,收入,10.00,早餐退款,1,退款\n".utf8)
        XCTAssertEqual(try BillImporter.preview(data: refund, filename: "bank.csv", accountID: l.accounts[0].id, ledger: l).selectedEntries.count, 1)
    }
    func testUnsupportedCurrencyAndChangedLedgerCannotSilentlyCommit() throws {
        var l = ledger(); let foreign = Data("时间,收支,金额,名称,币种\n2026-09-20,支出,10.00,购物,USD\n".utf8)
        let p = try BillImporter.preview(data: foreign, filename: "bank.csv", accountID: l.accounts[0].id, ledger: l); XCTAssertEqual(p.rows.first?.status, .invalid)
        let data = try file("wechat.csv"); let first = try BillImporter.preview(data: data, filename: "wechat.csv", accountID: l.accounts[0].id, ledger: l)
        _ = try BillImporter.commit(first, data: data, to: &l); let before = l
        XCTAssertThrowsError(try BillImporter.commit(first, data: data, to: &l)); XCTAssertEqual(l, before)
    }
    func testMixedPaymentMethodsRequireMappingAndPostToRealAccounts() throws {
        var l = ledger(); l.accounts.append(Account(name: "微信零钱", kind: .cash)); let bytes = try file("wechat.csv")
        let unassigned = try BillImporter.preview(data: bytes, filename: "wechat.csv", accountID: l.accounts[0].id, ledger: l, requireAccountMapping: true)
        XCTAssertEqual(unassigned.paymentMethods, ["银行卡", "零钱"]); XCTAssertEqual(unassigned.selectedEntries.count, 0)
        XCTAssertEqual(unassigned.rows.filter { $0.status == .needsAccount }.count, 3)
        let mapping = ["银行卡": l.accounts[0].id, "零钱": l.accounts[1].id]
        let assigned = try BillImporter.preview(data: bytes, filename: "wechat.csv", accountID: l.accounts[0].id, ledger: l, accountMappings: mapping, requireAccountMapping: true)
        XCTAssertEqual(assigned.selectedEntries.map(\.accountID), [l.accounts[1].id, l.accounts[0].id, l.accounts[1].id])
        _ = try BillImporter.commit(assigned, data: bytes, to: &l)
        let repeated = try BillImporter.preview(data: bytes, filename: "wechat.csv", accountID: l.accounts[0].id, ledger: l, accountMappings: mapping, requireAccountMapping: true)
        XCTAssertEqual(repeated.duplicateCount, 3); XCTAssertEqual(l.activeEntries.count, 3)
    }
    func testBankSeparateDebitCreditAndAmbiguousRows() throws {
        let l = ledger(); let bytes = Data("交易日期,支出金额,收入金额,摘要\n2026-09-20,32.00,,早餐\n2026-09-21,0.00,18000.00,工资\n2026-09-22,10.00,20.00,无法判定\n".utf8)
        let p = try BillImporter.preview(data: bytes, filename: "bank.csv", accountID: l.accounts[0].id, ledger: l)
        XCTAssertEqual(p.selectedEntries.map(\.amount), [3200, 1800000]); XCTAssertEqual(p.selectedEntries.map(\.nature), [.expense, .income])
        XCTAssertEqual(p.rows.last?.status, .invalid)
    }
    func testWorkbook1904EpochUsesCorrectDate() throws {
        let l = ledger(); let p = try BillImporter.preview(data: file("bank-1904.xlsx"), filename: "bank-1904.xlsx", accountID: l.accounts[0].id, ledger: l)
        XCTAssertEqual(p.selectedEntries.count, 2); XCTAssertEqual(Dates.text(p.selectedEntries[0].date), "2026-09-20")
    }
    func testCategoryRulesCannotReclassifyRefundOrUnresolvedTransferAsIncome() throws {
        let rules = [Rule(keyword: "咖啡", category: "餐饮"), Rule(keyword: "银行", category: "工资奖金")]
        XCTAssertEqual(Classifier.classify(title: "咖啡退款", inflow: true, rules: rules).nature, .refund)
        XCTAssertEqual(Classifier.classify(title: "银行转账", inflow: true, rules: rules).nature, .unknownIn)
        XCTAssertEqual(Classifier.classify(title: "银行信用卡还款", inflow: false, rules: rules).nature, .repayment)
    }
    func testDeviceModelSuggestionsCannotOverrideRulesMoneyNatureOrCategoryDirection() throws {
        let l = ledger()
        let data = Data("时间,收支,金额,名称\n2026-09-20,支出,23.45,未匹配用途\n2026-09-20,支出,28.00,午餐\n2026-09-20,收入,300.00,朋友转账\n2026-09-20,收入,300.00,未匹配收入\n".utf8)
        var p = try BillImporter.preview(data: data, filename: "test.csv", accountID: l.accounts[0].id, ledger: l)
        let before = p.selectedEntries
        p.applyCategorySuggestions(Dictionary(uniqueKeysWithValues: before.map { ($0.id, "学习工作") }), categories: l.categories)
        XCTAssertEqual(p.selectedEntries.map(\.amount), before.map(\.amount))
        XCTAssertEqual(p.selectedEntries.map(\.nature), before.map(\.nature))
        XCTAssertEqual(p.selectedEntries.map(\.accountID), before.map(\.accountID))
        XCTAssertEqual(p.selectedEntries.map(\.category), ["学习工作", "餐饮", "待明确", "其他收入"])
    }
    func testCSVResourceLimitsRejectHugeFieldsAndWideSheets() throws {
        XCTAssertThrowsError(try CSV.parse(String(repeating: "字", count: 33_334)))
        XCTAssertThrowsError(try CSV.parse(Array(repeating: "x", count: 257).joined(separator: ",")))
        XCTAssertThrowsError(try XLSX.readWorkbook(file("wide-invalid.xlsx")))
        XCTAssertEqual(try CSV.parse("\"\""), [[""]])
    }
}
