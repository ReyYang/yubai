import XCTest
@testable import YubaiCore

final class PastedStatementTests: XCTestCase {
    private func beeText() throws -> String {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "beecount-sample", withExtension: "csv", subdirectory: "Fixtures"))
        return String(decoding: try Data(contentsOf: url), as: UTF8.self)
    }
    private func ledger() -> Ledger {
        var ledger = Ledger(); ledger.accounts = [Account(name: "银行卡"), Account(name: "微信")]
        return ledger
    }

    func testBeeCountWithPreambleReturnsLocalSummaryWithoutTransportOrHistory() async throws {
        let ledger = ledger(), before = ledger, table = try beeText()
        let text = "帮我导入这些\n\n" + table
        let detected = try XCTUnwrap(PastedStatement.detect(text))
        XCTAssertEqual(detected.filename, "pasted.csv"); XCTAssertEqual(detected.preamble, "帮我导入这些")
        XCTAssertEqual(detected.rowCount, 8); XCTAssertTrue(String(decoding: detected.data, as: UTF8.self).hasPrefix("\u{FEFF}类型,"))
        let session = AskYubaiSession()
        let script = ScriptedChatTransport([ChatMessage(role: .assistant, content: "可以聊聊。"), ChatMessage(role: .assistant, content: "继续聊聊。")])
        _ = try await session.ask("聊聊用途", ledger: ledger, transport: script)
        let reply = try await session.ask(text, ledger: ledger, transport: script)
        let callsBeforeFollowUp = await script.recorded()
        XCTAssertEqual(callsBeforeFollowUp.count, 1, "The paste must not use transport")
        let statement = try XCTUnwrap(reply.pastedStatement), summary = try XCTUnwrap(statement.summary)
        XCTAssertEqual(statement.data, detected.data); XCTAssertFalse(statement.needsColumnMapping); XCTAssertNil(statement.previewError)
        XCTAssertEqual(summary.source, "BeeCount"); XCTAssertEqual(summary.entryCount, 8); XCTAssertEqual(summary.issueCount, 0)
        XCTAssertEqual(summary.startDate, Dates.parse("2026-04-02 18:00:00"))
        XCTAssertEqual(summary.endDate, Dates.parse("2026-04-03 10:30:00"))
        XCTAssertEqual(summary.expenseCount, 5); XCTAssertEqual(summary.expenseTotal, 15170)
        XCTAssertEqual(summary.incomeCount, 2); XCTAssertEqual(summary.incomeTotal, 1245025)
        XCTAssertTrue(reply.text.contains("蜜蜂记账导出，8 笔"))
        XCTAssertTrue(reply.proposedChangeSets.isEmpty); XCTAssertTrue(reply.toolTrace.isEmpty)
        _ = try await session.ask("继续聊", ledger: ledger, transport: script)
        let requests = await script.recorded()
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[1].messages.filter { $0.role == .user }.map(\.content), ["聊聊用途", "继续聊"])
        let sent = requests.flatMap(\.messages).compactMap(\.content).joined()
        for privateText in ["帮我导入这些", "转出账户,转入账户", "豆浆套餐", "键盘腕托", "蜜蜂记账导出，8 笔"] {
            XCTAssertFalse(sent.contains(privateText))
        }
        XCTAssertEqual(ledger, before)
    }

    func testTSVBeeCountAndExplicitTSVDelimiterWithManyCommas() async throws {
        let ledger = ledger()
        let tsv = try beeText().replacingOccurrences(of: ",", with: "\t").replacingOccurrences(of: "\n", with: "\r\n")
        let script = ScriptedChatTransport([])
        let reply = try await AskYubaiSession().ask("帮我导入这些\r\n" + tsv, ledger: ledger, transport: script)
        let statement = try XCTUnwrap(reply.pastedStatement)
        XCTAssertEqual(statement.filename, "pasted.tsv"); XCTAssertEqual(statement.summary?.entryCount, 8)
        XCTAssertEqual(statement.summary?.expenseTotal, 15170); XCTAssertEqual(statement.summary?.incomeTotal, 1245025)
        let calls = await script.recorded(); XCTAssertTrue(calls.isEmpty)
        let commaHeavy = "日期\t金额\t收支\t名称\n2026-04-03\t12.50\t支出\t早餐,a,b,c,d,e,f,g,h"
        let detected = try XCTUnwrap(PastedStatement.detect(commaHeavy))
        XCTAssertEqual(detected.filename, "pasted.tsv")
        let preview = try BillImporter.preview(data: detected.data, filename: detected.filename, accountID: ledger.accounts[0].id, ledger: ledger)
        XCTAssertEqual(preview.readyCount, 1); XCTAssertEqual(preview.selectedEntries.first?.amount, 1250)
        XCTAssertEqual(preview.selectedEntries.first?.title, "早餐,a,b,c,d,e,f,g,h")
    }

    func testSentencesAndHeaderlessOrInconsistentRowsAreNotTables() async throws {
        for text in ["午饭 32、打车 15", "午饭 32,打车 15", "午饭 32\t打车 15", "午饭 32\n打车 15",
                     "日期,金额", "日期,金额,名称\n2026-04-03,12.50", "2026-04-03,12.50\n2026-04-04,18.00"] {
            XCTAssertNil(PastedStatement.detect(text), text)
        }
        let script = ScriptedChatTransport([ChatMessage(role: .assistant, content: "请核对这两笔。")])
        let reply = try await AskYubaiSession().ask("午饭 32、打车 15", ledger: ledger(), transport: script)
        XCTAssertNil(reply.pastedStatement)
        let calls = await script.recorded(); XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.messages.last?.content, "午饭 32、打车 15")
    }

    func testQuotedCSVCellsAndMultilineNotesExcludeSurroundingProse() throws {
        let table = "\u{FEFF}\"日期\",金额,收支,名称,备注,\n2026-04-03,12.50,支出,\"面包,豆浆\",\"第一行\n第二行含\"\"引号\"\"\","
        let result = try XCTUnwrap(PastedStatement.detect("帮我导入这些\n" + table + "\n以上是账单"))
        XCTAssertEqual(String(decoding: result.data, as: UTF8.self), table)
        XCTAssertEqual(result.preamble, "帮我导入这些"); XCTAssertEqual(result.rowCount, 1)
        let ledger = ledger()
        let preview = try BillImporter.preview(data: result.data, filename: result.filename, accountID: ledger.accounts[0].id, ledger: ledger)
        XCTAssertEqual(preview.selectedEntries.first?.title, "面包,豆浆")
        XCTAssertEqual(preview.selectedEntries.first?.note, "第一行\n第二行含\"引号\"")
    }

    func testUnknownHeadersStayLocalThenUseOnlyFiveRedactedSamplesForMapping() async throws {
        let ledger = ledger(), session = AskYubaiSession(), noCloud = ScriptedChatTransport([])
        let rows = (1...8).map { "2026-04-0\($0)\t-25.00\t午餐\t转账给张三 13800138000" }
        let table = (["日戳\t数值\t内容\t附言"] + rows).joined(separator: "\n")
        let reply = try await session.ask("帮我导入这些\n" + table, ledger: ledger, transport: noCloud)
        let statement = try XCTUnwrap(reply.pastedStatement)
        XCTAssertTrue(statement.needsColumnMapping); XCTAssertNil(statement.summary); XCTAssertNil(statement.previewError)
        XCTAssertEqual(statement.rowCount, 8); XCTAssertEqual(statement.preamble, "帮我导入这些")
        XCTAssertEqual(statement.data, Data(table.utf8)); XCTAssertEqual(statement.filename, "pasted.tsv")
        let calls = await noCloud.recorded(); XCTAssertTrue(calls.isEmpty)
        let log = SendLog()
        let stub = CloudTestStub(sendLog: log) { request in
            let payload = try JSONValue.parse(try XCTUnwrap(CloudTestStub.messages(in: request).last?["content"]))
            XCTAssertEqual(payload["headers"], .strings(["日戳", "数值", "内容", "附言"]))
            XCTAssertEqual(payload["samples"]?.arrayValue?.count, 5)
            let sent = try payload.jsonText()
            XCTAssertFalse(sent.contains("张三")); XCTAssertFalse(sent.contains("13800138000"))
            XCTAssertFalse(sent.contains("2026-04-06")); XCTAssertFalse(sent.contains("帮我导入这些"))
            return #"{"date":0,"amount":1,"description":2,"note":3}"#
        }
        defer { stub.close() }
        let preview = try await BillImporter.preview(data: statement.data, filename: statement.filename,
            accountID: ledger.accounts[0].id, ledger: ledger, columnMapper: AIImportColumnMapper(transport: stub.backend))
        XCTAssertEqual(preview.readyCount, 8); XCTAssertEqual(preview.selectedEntries.first?.amount, 2500)
        XCTAssertTrue(preview.selectedEntries.first?.note.contains("张三") == true)
        XCTAssertEqual(log.groups.count, 1); XCTAssertEqual(log.groups.first?.purpose, "导入·识别列")
        let followUp = ScriptedChatTransport([ChatMessage(role: .assistant, content: "可以继续。")])
        _ = try await session.ask("继续", ledger: ledger, transport: followUp)
        let later = await followUp.recorded()
        XCTAssertEqual(later[0].messages.filter { $0.role == .user }.map(\.content), ["继续"])
        XCTAssertFalse(later[0].messages.compactMap(\.content).joined().contains("日戳"))
    }

    func testSummaryWorksWithoutAccountsAndDoesNotLoseReimportedRows() async throws {
        let noCloud = ScriptedChatTransport([]), table = try beeText()
        let emptyReply = try await AskYubaiSession().ask(table, ledger: Ledger(), transport: noCloud)
        XCTAssertEqual(emptyReply.pastedStatement?.summary?.entryCount, 8)
        var ledger = ledger()
        let preview = try BillImporter.preview(data: Data(table.utf8), filename: "bee.csv", accountID: ledger.accounts[0].id, ledger: ledger)
        _ = try BillImporter.commit(preview, data: Data(table.utf8), to: &ledger)
        let reply = try await AskYubaiSession().ask(table, ledger: ledger, transport: noCloud)
        XCTAssertEqual(reply.pastedStatement?.summary?.entryCount, 8)
        XCTAssertEqual(reply.pastedStatement?.summary?.expenseCount, 5)
    }
}
