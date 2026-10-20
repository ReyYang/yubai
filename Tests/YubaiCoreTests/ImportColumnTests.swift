import XCTest
@testable import YubaiCore

private struct ScriptedColumns: ImportColumnMapper {
    let mapping: ImportColumnMapping
    func map(headers: [String], samples: [[String]]) async throws -> ImportColumnMapping { mapping }
}

final class ImportColumnTests: XCTestCase {
    func testUnknownHeadersUseScriptedAIIndicesWithRedactedSamples() async throws {
        var ledger = Ledger(); ledger.accounts = [Account(name: "银行卡")]
        let csv = "日戳,时分,借记,贷记,内容,附言,资金位置\n2026-09-01,12:30:00,25.00,,午餐,转账给张三 13800138000,银行卡\n"
        let stub = CloudTestStub { request in
            let messages = try CloudTestStub.messages(in: request)
            let user = messages.last!["content"]!
            XCTAssertFalse(user.contains("张三")); XCTAssertFalse(user.contains("13800138000"))
            let payload = try JSONValue.parse(user)
            XCTAssertEqual(payload["samples"]?.arrayValue?.count, 1)
            return #"{"date":0,"time":1,"outflow":2,"inflow":3,"description":4,"note":5,"account":6}"#
        }
        defer { stub.close() }
        let result = try await BillImporter.preview(data: Data(csv.utf8), filename: "unknown.csv", accountID: ledger.accounts[0].id,
            ledger: ledger, accountMappings: ["银行卡": ledger.accounts[0].id], requireAccountMapping: true,
            columnMapper: AIImportColumnMapper(transport: stub.backend))
        let entry = try XCTUnwrap(result.selectedEntries.first)
        XCTAssertEqual(entry.amount, 2500); XCTAssertEqual(entry.accountID, ledger.accounts[0].id)
        XCTAssertEqual(entry.date, Dates.parse("2026-09-01 12:30:00"))
        XCTAssertTrue(entry.note.contains("张三")) // Redaction is outbound only.
    }
    func testOutOfRangeAndUnparseableMappingAreRejected() async throws {
        var ledger = Ledger(); ledger.accounts = [Account(name: "卡")]
        let csv = Data("日戳,数值,详情\n2026-09-01,-25.00,午餐\n".utf8)
        for json in [#"{"date":99,"amount":1,"description":2}"#, #"{"date":1,"amount":0,"description":2}"#,
                     #"{"date":0,"amount":0,"description":2}"#, #"{"date":0,"description":2}"#] {
            let mapping = try JSONDecoder().decode(ImportColumnMapping.self, from: Data(json.utf8))
            do {
                _ = try await BillImporter.preview(data: csv, filename: "unknown.csv", accountID: ledger.accounts[0].id,
                    ledger: ledger, columnMapper: ScriptedColumns(mapping: mapping))
                XCTFail("Invalid mapping should fail: \(json)")
            } catch { }
        }
        XCTAssertThrowsError(try BillImporter.preview(data: csv, filename: "unknown.csv", accountID: ledger.accounts[0].id, ledger: ledger))
    }
    func testKnownFormatNeverCallsMapperAndMappingSamplesAreBounded() async throws {
        var ledger = Ledger(); ledger.accounts = [Account(name: "卡")]
        let stub = CloudTestStub { request in
            let messages = try CloudTestStub.messages(in: request)
            let value = try JSONValue.parse(messages.last!["content"]!)
            XCTAssertEqual(value["samples"]?.arrayValue?.count, 5)
            return #"{"date":0,"amount":1,"description":2}"#
        }
        defer { stub.close() }
        let known = Data("时间,金额,名称,收支\n2026-09-01,25.00,午餐,支出\n".utf8)
        let mapper = AIImportColumnMapper(transport: stub.backend)
        let parsed = try await BillImporter.preview(data: known, filename: "known.csv", accountID: ledger.accounts[0].id, ledger: ledger, columnMapper: mapper)
        XCTAssertEqual(parsed.selectedEntries.first?.amount, 2500)
        let rows = (0..<8).map { "2026-09-\(String(format: "%02d", $0 + 1)),-25.00,午餐" }
        let unknown = Data((["日戳,数值,详情"] + rows).joined(separator: "\n").utf8)
        let unknownResult = try await BillImporter.preview(data: unknown, filename: "unknown.csv", accountID: ledger.accounts[0].id, ledger: ledger, columnMapper: mapper)
        XCTAssertEqual(unknownResult.selectedEntries.count, 8)
    }
}
