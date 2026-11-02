import XCTest
@testable import YubaiCore

final class ImportBalanceTests: XCTestCase {
    private func preview(_ text: String) throws -> ImportPreview {
        var ledger = Ledger()
        let account = Account(name: "银行卡")
        ledger.accounts = [account]
        return try BillImporter.preview(data: Data(text.utf8), filename: "bank.csv", accountID: account.id, ledger: ledger)
    }

    func testAnnualStatementRangeCountsAndPreservesOriginalSelection() throws {
        let lines = (0...12).map { offset in
            Dates.text(Dates.addMonths(offset, to: Dates.parse("2025-10-28")!)) + ",支出,10,100"
        }
        let all = try preview((["时间,收支,金额,余额"] + lines).joined(separator: "\n"))
        let start = try XCTUnwrap(all.recentThreeMonthsStart)
        XCTAssertEqual(start, Dates.parse("2026-07-28"))
        let recent = all.selectingEntries(onOrAfter: start)
        XCTAssertEqual(recent.selectedEntries.count, 4)
        XCTAssertEqual(recent.selectedEntries.map(\.date).min(), start)
        XCTAssertEqual(recent.selectedEntries.map(\.date).max(), Dates.parse("2026-10-28"))
        XCTAssertEqual(all.selectedEntries.count, 13)
        XCTAssertEqual(recent.rows.count, all.rows.count)
        XCTAssertEqual(recent.latestBalance, all.latestBalance)
    }

    func testRangeControlRequiresStrictlyMoreThanThreeCalendarMonths() throws {
        let header = "时间,收支,金额,余额\n"
        XCTAssertNil(try preview(header + "2026-07-28 12:00:00,支出,10,100\n2026-10-28 12:00:00,支出,10,90").recentThreeMonthsStart)
        XCTAssertNil(try preview(header + "2026-10-28,支出,10,100").recentThreeMonthsStart)
        var empty = try preview(header + "2026-10-28,支出,10,100")
        empty.rows = []
        XCTAssertNil(empty.recentThreeMonthsStart)
        let longer = try preview(header + "2026-07-28 11:59:59,支出,10,100\n2026-10-28 12:00:00,支出,10,90")
        XCTAssertEqual(longer.recentThreeMonthsStart, Dates.parse("2026-07-28 12:00:00"))
    }

    func testRangeClampsCalendarMonthEndIncludingLeapDay() throws {
        for (year, februaryDay) in [(2026, 28), (2028, 29)] {
            let cutoff = "\(year)-02-\(februaryDay) 12:00:00"
            let all = try preview("时间,收支,金额,余额\n\(year)-02-01,支出,10,100\n\(year)-02-\(februaryDay) 11:59:59,支出,10,90\n\(cutoff),支出,10,80\n\(year)-05-31 12:00:00,支出,10,70")
            let start = try XCTUnwrap(all.recentThreeMonthsStart)
            XCTAssertEqual(start, Dates.parse(cutoff))
            let recent = all.selectingEntries(onOrAfter: start)
            XCTAssertEqual(recent.selectedEntries.count, 2)
            XCTAssertEqual(recent.selectedEntries.first?.date, Dates.parse(cutoff))
            XCTAssertEqual(recent.latestBalance, all.latestBalance)
        }
    }

    func testRangeNeverReselectsReviewedOrDuplicateRowsOrChangesBalanceEvidence() throws {
        var all = try preview("时间,收支,金额,余额\n2025-10-28,支出,10,100\n2026-08-01,支出,10,90\n2026-09-01,支出,10,80\n2026-10-28,支出,10,70")
        all.rows[1].status = .duplicate; all.rows[1].included = false
        all.rows[3].included = false // The latest row is manually unchecked.
        let start = try XCTUnwrap(all.recentThreeMonthsStart)
        let recent = all.selectingEntries(onOrAfter: start)
        XCTAssertEqual(recent.rows.map(\.included), [false, false, true, false])
        XCTAssertEqual(recent.selectedEntries.count, 1)
        XCTAssertEqual(recent.latestBalance?.amount, 7000)
        XCTAssertEqual(recent.latestBalance?.date, Dates.parse("2026-10-28"))
        XCTAssertEqual(all.selectedEntries.count, 2)
        XCTAssertEqual(all.recentThreeMonthsStart, start)
    }

    func testCommittingEitherRangePreservesFullStatementLatestBalanceAndOriginalFile() throws {
        let bytes = Data("时间,收支,金额,余额\n2025-10-28,支出,10,100\n2026-07-28,支出,10,90\n2026-08-28,支出,10,80\n2026-10-28 21:14:00,支出,10,70".utf8)
        var account = Account(name: "新银行卡")
        var base = Ledger(); base.accounts = [account]
        let all = try BillImporter.preview(data: bytes, filename: "bank.csv", accountID: account.id, ledger: base)
        let start = try XCTUnwrap(all.recentThreeMonthsStart)
        let balance = try XCTUnwrap(all.latestBalance)
        account.anchorBalance = balance.amount; account.anchorDate = balance.date
        for (selection, count) in [(all.selectingEntries(onOrAfter: start), 2), (all, 4)] {
            var ledger = Ledger(); ledger.accounts = [account]
            let batch = try BillImporter.commit(selection, data: bytes, to: &ledger)
            XCTAssertEqual(batch.importedCount, count)
            XCTAssertEqual(ledger.activeEntries.count, count)
            XCTAssertEqual(selection.latestBalance, balance)
            XCTAssertEqual(Finance.balance(account, in: ledger, at: Dates.addDays(1, to: balance.date)), balance.amount)
            XCTAssertEqual(ledger.attachments.first?.data, bytes)
        }
    }

    func testAscendingStatementUsesLatestDate() throws {
        let p = try preview("""
        时间,收支,金额,余额
        2026-10-25 12:00:00,支出,10,100
        2026-10-26 21:14:00,收入,20,120.25
        """)
        XCTAssertEqual(p.latestBalance?.amount, 12_025)
        XCTAssertEqual(p.latestBalance?.date, Dates.parse("2026-10-26 21:14:00"))
        XCTAssertEqual(p.readyCount, 2)
    }

    func testDescendingStatementUsesLatestDateRatherThanLastRow() throws {
        let p = try preview("""
        时间,收支,金额,余额
        2026-10-26 21:14:00,收入,20,120
        2026-10-25 12:00:00,支出,10,100
        """)
        XCTAssertEqual(p.latestBalance?.amount, 12_000)
        XCTAssertEqual(p.latestBalance?.date, Dates.parse("2026-10-26 21:14:00"))
    }

    func testAscendingTiedLatestTimeUsesLaterFileRow() throws {
        let p = try preview("""
        时间,收支,金额,余额
        2026-10-25 12:00:00,支出,10,100
        2026-10-26 21:14:00,收入,20,120
        2026-10-26 21:14:00,支出,5,115
        """)
        XCTAssertEqual(p.latestBalance?.amount, 11_500)
    }

    func testDescendingTiedLatestTimeUsesEarlierFileRow() throws {
        let p = try preview("""
        时间,收支,金额,余额
        2026-10-26 21:14:00,支出,5,115
        2026-10-26 21:14:00,收入,20,120
        2026-10-25 12:00:00,支出,10,100
        """)
        XCTAssertEqual(p.latestBalance?.amount, 11_500)
    }

    func testAllTimesEqualFallsBackToLaterFileRow() throws {
        let p = try preview("""
        时间,收支,金额,余额
        2026-10-26 21:14:00,收入,20,120
        2026-10-26 21:14:00,支出,5,115
        """)
        XCTAssertEqual(p.latestBalance?.amount, 11_500)
    }

    func testEmptyBalancesStillEstablishDescendingDirection() throws {
        let p = try preview("""
        时间,收支,金额,余额
        2026-10-27 12:00:00,支出,10,
        2026-10-26 21:14:00,支出,5,115
        2026-10-26 21:14:00,收入,20,120
        2026-10-25 12:00:00,支出,10,
        """)
        XCTAssertEqual(p.latestBalance?.amount, 11_500)
        XCTAssertEqual(p.latestBalance?.date, Dates.parse("2026-10-26 21:14:00"))
    }

    func testEmptyOrInvalidBalanceAndInvalidDatesAreIgnored() throws {
        let p = try preview("""
        时间,收支,金额,余额
        2026-10-25 12:00:00,支出,10,-12.34
        2026-10-26 21:14:00,收入,20,
        2026-10-27 12:00:00,支出,5,--
        不是日期,支出,5,9999
        """)
        XCTAssertEqual(p.latestBalance?.amount, -1234)
        XCTAssertEqual(p.latestBalance?.date, Dates.parse("2026-10-25 12:00:00"))
        XCTAssertNil(try preview("时间,收支,金额,余额\n2026-10-26,支出,10,\n2026-10-27,支出,10,--").latestBalance)
    }

    func testAllBalanceAliasesUseExistingHeaderNormalization() throws {
        for header in ["余额", "账户余额", "联机余额", "可用余额", "当前余额", "交易后余额", "余额(元)", " 余额（元） ", " BALANCE "] {
            let p = try preview("时间,收支,金额,\(header)\n2026-10-26,支出,10,0.00")
            XCTAssertEqual(p.latestBalance?.amount, 0, header)
        }
    }

    func testWeChatAndAlipayWithoutBalanceReturnNil() throws {
        for filename in ["wechat.csv", "alipay-gb18030.csv"] {
            let url = try XCTUnwrap(Bundle.module.url(forResource: filename, withExtension: nil, subdirectory: "Fixtures"))
            var ledger = Ledger(); ledger.accounts = [Account(name: "银行卡")]
            let p = try BillImporter.preview(data: Data(contentsOf: url), filename: filename, accountID: ledger.accounts[0].id, ledger: ledger)
            XCTAssertNil(p.latestBalance, filename)
            XCTAssertFalse(p.selectedEntries.isEmpty)
        }
    }

    func testDebitCreditBankStatementWithOnlineBalance() throws {
        let p = try preview("""
        交易日期,借方发生额,贷方发生额,联机余额,摘要
        2026-10-25,32.00,0,968.00,午餐
        2026-10-26,0,200.00,1168.00,工资
        """)
        XCTAssertEqual(p.selectedEntries.map(\.amount), [3200, 20_000])
        XCTAssertEqual(p.selectedEntries.map(\.nature), [.expense, .income])
        XCTAssertEqual(p.latestBalance?.amount, 116_800)
    }

    func testBalanceEvidenceSurvivesDuplicatesSkippedInvalidAndDeselectedRows() throws {
        let bytes = Data("时间,收支,金额,余额,状态\n2026-10-25,支出,10,100,成功\n2026-10-26,支出,10,90,交易关闭\n2026-10-27,支出,坏金额,80,成功".utf8)
        var ledger = Ledger(); ledger.accounts = [Account(name: "银行卡")]
        let first = try BillImporter.preview(data: bytes, filename: "bank.csv", accountID: ledger.accounts[0].id, ledger: ledger)
        _ = try BillImporter.commit(first, data: bytes, to: &ledger)
        let again = try BillImporter.preview(data: bytes, filename: "bank.csv", accountID: ledger.accounts[0].id, ledger: ledger)
        XCTAssertEqual(again.rows.map(\.status), [.duplicate, .skipped, .invalid])
        XCTAssertEqual(again.latestBalance?.amount, 8000)
        var deselected = first
        for i in deselected.rows.indices { deselected.rows[i].included = false }
        XCTAssertEqual(deselected.latestBalance, first.latestBalance)
        let skippedLatest = try preview("时间,收支,金额,余额,状态\n2026-10-25,支出,10,100,成功\n2026-10-26,支出,10,90,交易关闭")
        XCTAssertEqual(skippedLatest.latestBalance?.amount, 9000)
        let duplicateBytes = Data("时间,收支,金额,余额\n2026-10-25,支出,10,100".utf8)
        let duplicate = try BillImporter.preview(data: duplicateBytes, filename: "bank.csv", accountID: ledger.accounts[0].id, ledger: ledger)
        XCTAssertEqual(duplicate.rows.first?.status, .duplicate)
        XCTAssertEqual(duplicate.latestBalance?.amount, 10_000)
    }

    func testUnsortedStatementStillChoosesMaximumDate() throws {
        let p = try preview("时间,收支,金额,余额\n2026-10-25,支出,10,100\n2026-10-27,支出,10,80\n2026-10-26,支出,10,90")
        XCTAssertEqual(p.latestBalance?.amount, 8000)
    }

    func testImportedBalanceAnchorDoesNotCountOldTransactionsAgain() throws {
        let bytes = Data("时间,收支,金额,余额\n2026-10-25,支出,32,968\n2026-10-26 21:14:00,收入,200,1168".utf8)
        var ledger = Ledger()
        var account = Account(name: "新银行卡")
        var temporary = ledger; temporary.accounts.append(account)
        let p = try BillImporter.preview(data: bytes, filename: "bank.csv", accountID: account.id, ledger: temporary)
        let balance = try XCTUnwrap(p.latestBalance)
        account.anchorBalance = balance.amount; account.anchorDate = balance.date
        ledger.accounts.append(account)
        let batch = try BillImporter.commit(p, data: bytes, to: &ledger)
        ledger.preferences.onboardingComplete = true
        XCTAssertEqual(Finance.balance(account, in: ledger, at: Dates.addDays(1, to: balance.date)), balance.amount)
        XCTAssertEqual(ledger.entries.count, 2)
        XCTAssertTrue(ledger.entries.allSatisfy { $0.accountID == account.id && $0.recordedAt == nil && $0.batchID == batch.id })
        XCTAssertEqual(ledger.attachments.first?.data, bytes)
        XCTAssertEqual(try BillImporter.preview(data: bytes, filename: "bank.csv", accountID: account.id, ledger: ledger).duplicateCount, 2)
        BillImporter.undo(batchID: batch.id, in: &ledger)
        XCTAssertTrue(ledger.activeEntries.isEmpty)
        XCTAssertTrue(ledger.attachments.isEmpty)
        XCTAssertEqual(Finance.balance(account, in: ledger), balance.amount)
    }
}
