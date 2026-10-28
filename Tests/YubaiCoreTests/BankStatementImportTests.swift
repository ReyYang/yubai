import XCTest
@testable import YubaiCore

final class BankStatementImportTests: XCTestCase {
    private func ledger() -> Ledger {
        var ledger = Ledger(); ledger.accounts = [Account(name: "银行卡")]; return ledger
    }
    private func preview(_ csv: String, ledger: Ledger) throws -> ImportPreview {
        try BillImporter.preview(data: Data(csv.utf8), filename: "bank.csv", accountID: ledger.accounts[0].id, ledger: ledger)
    }
    private let statement = """
    记账日期,货币,交易金额,联机余额,交易摘要,对手信息,交易单号
    2025-10-25,CNY,-200.00,16896.37,快捷支付,源源烧烤 6845123456789012,TX001
    2025-10-25,CNY,-42.00,16826.37,快捷支付,刘氏便利店 5012345678,TX002
    2025-10-26,CNY,-19.90,16806.47,银联快捷支付,广州市动景计算机科技有限公司 6225880000000000,TX003
    2025-10-26,CNY,-5.88,16800.59,快捷支付,蚂蚁（杭州）基金销售有限公司 2088000000000000,TX004
    2025-10-26,CNY,-5.90,16794.69,快捷支付,Cotti+Coffee 2088111111111111,TX005
    2025-10-26,CNY,-6.00,16788.69,银联快捷支付,蜜雪冰城 4000000000,TX006
    2025-10-27,CNY,100.70,16210.45,银联快捷支付,杭州崇宇信息科技有限公司 1234567890,TX007
    2025-10-27,CNY,-16.80,16109.75,快捷支付,杭州全家便利店 7000000000,TX008
    2025-10-27,CNY,-12.18,16087.87,快捷支付,luckincoffee 2088222222222222,TX009
    """
    func testSignedBankStatementTitlesCategoriesAndReimport() throws {
        var ledger = ledger(); let first = try preview(statement, ledger: ledger)
        XCTAssertEqual(first.source, "文件"); XCTAssertEqual(first.readyCount, 9); XCTAssertEqual(first.issueCount, 0)
        let entries = first.selectedEntries
        XCTAssertEqual(entries.map(\.amount), [20000, 4200, 1990, 588, 590, 600, 10070, 1680, 1218])
        XCTAssertEqual(entries.map(\.nature), [.expense, .expense, .expense, .expense, .expense, .expense, .income, .expense, .expense])
        let merchants = ["源源烧烤", "刘氏便利店", "广州市动景计算机科技有限公司", "蚂蚁（杭州）基金销售有限公司", "Cotti+Coffee", "蜜雪冰城", "杭州崇宇信息科技有限公司", "杭州全家便利店", "luckincoffee"]
        for i in entries.indices {
            let summary = [2, 5, 6].contains(i) ? "银联快捷支付" : "快捷支付"
            XCTAssertEqual(entries[i].title, merchants[i] + " · " + summary)
            XCTAssertEqual(entries[i].externalID, String(format: "TX%03d", i + 1))
        }
        XCTAssertEqual(entries[0].category, "餐饮")
        for i in [1, 7] { XCTAssertEqual(entries[i].category, "购物"); XCTAssertEqual(entries[i].subcategory, "日用百货") }
        for i in [4, 8] { XCTAssertEqual(entries[i].category, "餐饮"); XCTAssertEqual(entries[i].subcategory, "咖啡饮品") }
        XCTAssertTrue(Classification.isPending(entries[3])); XCTAssertNil(entries[3].subcategory)
        XCTAssertTrue(Classification.isPending(entries[5]))
        XCTAssertEqual(entries[0].note, "对手信息：源源烧烤 6845123456789012")
        XCTAssertEqual(first.latestBalance?.amount, 1608787)
        _ = try BillImporter.commit(first, data: Data(statement.utf8), to: &ledger)
        let again = try preview(statement, ledger: ledger)
        XCTAssertEqual(again.duplicateCount, 9); XCTAssertTrue(again.selectedEntries.isEmpty)
        XCTAssertTrue(again.rows.allSatisfy { $0.status == .duplicate })
    }
    func testAllPositiveAmountsWithoutDirectionStayAmbiguous() throws {
        let result = try preview("记账日期,交易金额,交易摘要\n2025-10-25,+100.70,退款\n2025-10-26,5000.00,工资", ledger: ledger())
        XCTAssertEqual(result.rows.count, 2); XCTAssertTrue(result.selectedEntries.isEmpty)
        XCTAssertTrue(result.rows.allSatisfy { $0.status == .invalid && $0.message == "缺少收入/支出方向，请使用模板的收支列" })
    }
    func testSignedEvidenceAppliesToEarlierPositiveRowsAndBlankDirections() throws {
        for header in ["记账日期,交易金额,交易摘要", "记账日期,交易金额,交易摘要,资金流向"] {
            let result = try preview(header + "\n2025-10-25,+100.70,工资,\n2025-10-26,-20.00,快捷支付,", ledger: ledger())
            XCTAssertEqual(result.readyCount, 2); XCTAssertEqual(result.selectedEntries.map(\.nature), [.income, .expense])
        }
    }
    func testOnlyParsedNonzeroNegativeTransactionAmountsEstablishSignedColumn() throws {
        let result = try preview("日期,金额,余额\n2025-10-25,10.00,-100.00\n2025-10-26,-0.00,-90.00\n2025-10-27,-坏金额,-90.00", ledger: ledger())
        XCTAssertEqual(result.rows.count, 3); XCTAssertTrue(result.selectedEntries.isEmpty)
        XCTAssertEqual(result.rows.first?.message, "缺少收入/支出方向，请使用模板的收支列")
        XCTAssertTrue(result.rows.allSatisfy { $0.status == .invalid })
    }
    func testSummaryHintsRefundSalaryAndMoneyMovementWithoutUsingMerchantHints() throws {
        let summaries = ["消费退款", "退货入账", "工资发放", "快捷支付", "银联快捷支付", "转账", "提现", "还款"]
        let amounts = ["+20.00", "10.00", "5000.00", "-1.00", "-2.00", "-3.00", "-4.00", "-5.00"]
        let rows = summaries.indices.map { "2025-10-25,\(amounts[$0]),\(summaries[$0]),退款转账商户 123456" }
        let result = try preview("记账日期,交易金额,交易摘要,对手信息\n" + rows.joined(separator: "\n"), ledger: ledger())
        XCTAssertEqual(result.readyCount, 8)
        XCTAssertEqual(result.selectedEntries.map(\.nature), [.refund, .refund, .income, .expense, .expense, .unknownOut, .unknownOut, .repayment])
        let explicit = try preview("记账日期,交易金额,交易摘要,类型\n2025-10-25,20.00,退款,收入", ledger: ledger())
        XCTAssertEqual(explicit.selectedEntries.first?.nature, .income)
    }
    func testExplicitDirectionsTakePriorityOverSigns() throws {
        let result = try preview("日期,金额,收支\n2025-10-25,-10.00,收入\n2025-10-26,20.00,支出", ledger: ledger())
        XCTAssertEqual(result.selectedEntries.map(\.nature), [.income, .expense])
    }
    func testSummaryAndMerchantAreNeverInferredAsTransferDirectionColumns() throws {
        for (summary, nature) in [("转账", Nature.unknownOut), ("提现", .unknownOut), ("还款", .repayment), ("快捷支付", .expense)] {
            let result = try preview("日期,金额,交易摘要,对手信息\n2025-10-25,-1.00,\(summary),转账", ledger: ledger())
            XCTAssertEqual(result.readyCount, 1, summary); XCTAssertEqual(result.selectedEntries.first?.nature, nature, summary)
        }
    }
    func testCounterpartyCleanupIsConservativeAndPreservesRawNotes() throws {
        let names = ["源源烧烤 6225****1234", "便利店\t12xxXX34", "商户 12345", "商户123456", "商户 ABC123456", "Studio 54", "商户 123456 分店"]
        let cleaned = ["源源烧烤", "便利店", "商户 12345", "商户123456", "商户 ABC123456", "Studio 54", "商户 123456 分店"]
        let rows = names.map { "2025-10-25,-1.00,\($0),原备注" }
        let result = try preview("日期,金额,对手信息,备注\n" + rows.joined(separator: "\n"), ledger: ledger())
        XCTAssertEqual(result.selectedEntries.map(\.title), cleaned)
        XCTAssertEqual(result.selectedEntries.map(\.note), names.map { "原备注\n对手信息：" + $0 })
    }
    func testTransactionIDsStillDeduplicateLegacyFallbackTitles() throws {
        var ledger = ledger(); let first = try preview(statement, ledger: ledger)
        ledger.entries = first.selectedEntries.map { entry in
            var old = entry; old.title = "账单记录"; old.fingerprint = "old-" + old.externalID
            old.sourceIdentity = ""; return old
        }
        let again = try preview(statement, ledger: ledger)
        XCTAssertEqual(again.duplicateCount, 9); XCTAssertTrue(again.selectedEntries.isEmpty)
    }
    func testFingerprintReimportWithoutTransactionIDs() throws {
        var ledger = ledger(); let csv = "日期,金额,对手信息\n2025-10-25,-1.00,Cotti+Coffee 123456\n2025-10-25,-1.00,Cotti+Coffee 123456"
        let first = try preview(csv, ledger: ledger)
        XCTAssertEqual(first.readyCount, 2); XCTAssertEqual(Set(first.selectedEntries.map(\.fingerprint)).count, 2)
        _ = try BillImporter.commit(first, data: Data(csv.utf8), to: &ledger)
        XCTAssertEqual(try preview(csv, ledger: ledger).duplicateCount, 2)
    }
    func testAlipayCategoryAndSourceDetection() throws {
        let result = try preview("支付宝交易记录\n交易创建时间,交易分类,交易对方,商品说明,收/支,金额,交易订单号\n2025-10-25 12:00:00,餐饮美食,普通商户,订单,支出,20.00,A1", ledger: ledger())
        XCTAssertEqual(result.source, "支付宝"); XCTAssertEqual(result.readyCount, 1)
        XCTAssertEqual(result.selectedEntries.first?.category, "餐饮"); XCTAssertEqual(result.rows.first?.sourceCategory, "餐饮美食")
    }
    func testHeaderAliasesAndNormalization() throws {
        let ledger = ledger()
        for header in ["交易摘要", "摘要", "交易说明", "交易描述", "交易用途", "用途", "附言", "交易附言", "商品说明", "说明", "交易内容", "描述", "description", "summary", "交易名称"] {
            let entry = try XCTUnwrap(preview("日期,金额,\(header),备注\n2025-10-25,-1.00,早餐,原备注", ledger: ledger).selectedEntries.first)
            XCTAssertEqual(entry.title, "早餐", header); XCTAssertEqual(entry.note, "原备注", header)
        }
        for header in ["对手信息", "交易对手", "对方信息", "对方名称", "对方户名", "对方账户名", "对方账户名称", "收款方", "收款人", "付款方", "商户", "商户名称", "商户名", "交易对方", "对方", "counterparty", "payee"] {
            let entry = try XCTUnwrap(preview("日期,金额,交易摘要,\(header)\n2025-10-25,-1.00,快捷支付,商户 123456", ledger: ledger).selectedEntries.first)
            XCTAssertEqual(entry.title, "商户 · 快捷支付", header); XCTAssertEqual(entry.note, "对手信息：商户 123456", header)
        }
        for header in ["收/付", "借贷", "借贷方向", "借贷标志", "资金方向", "资金流向", "交易方向", "出入账", "收支类别"] {
            let result = try preview("日期,金额,\(header)\n2025-10-25,1.00,贷\n2025-10-26,2.00,借", ledger: ledger)
            XCTAssertEqual(result.selectedEntries.map(\.nature), [.income, .expense], header)
        }
        for header in ["交易分类", "消费分类", "账单分类", "收支分类", "分类"] {
            XCTAssertEqual(try preview("日期,金额,\(header)\n2025-10-25,-1.00,餐饮美食", ledger: ledger).selectedEntries.first?.category, "餐饮", header)
        }
        for header in ["交易时间", "记账日期", "交易日期", "入账时间", "入账日期", "交易发生日期", "账务日期", "时间"] {
            XCTAssertEqual(try preview("\(header),金额\n2025-10-25,-1.00", ledger: ledger).readyCount, 1, header)
        }
        for header in ["交易金额", "发生金额", "金额", "交易金额(元)", "人民币金额", " 交易金额（元） "] {
            XCTAssertEqual(try preview("日期,\(header)\n2025-10-25,-1.00", ledger: ledger).selectedEntries.first?.amount, 100, header)
        }
        for header in ["交易流水号", "流水号", "交易参考号", "凭证号", "交易序号", "商户单号"] {
            XCTAssertEqual(try preview("日期,金额,\(header)\n2025-10-25,-1.00,ID1", ledger: ledger).selectedEntries.first?.externalID, "ID1", header)
        }
        let preferred = try preview("日期,金额,商户单号,交易单号\n2025-10-25,-1.00,merchant1,TX1", ledger: ledger)
        XCTAssertEqual(preferred.selectedEntries.first?.externalID, "TX1")
    }
}
