import XCTest
@testable import YubaiCore

final class Round45BImportTests: XCTestCase {
    let now = Round45BFixture.now
    func d(_ text: String) -> Date { Round45BFixture.d(text) }
    func recognitionLedger() -> (Ledger, UUID) {
        var ledger = Round45BFixture.ledger()
        var batch = ImportBatch(filename: "流水.csv", importedCount: 6, duplicateCount: 0, skippedCount: 0)
        batch.importedAt = now; batch.undo = ImportUndo(updatedAt: ledger.updatedAt); ledger.imports = [batch]
        for date in ["2026-09-10", "2026-10-10", "2026-11-10"] {
            var entry = Round45BFixture.entry(ledger, date: date, amount: 800_000, title: "公司", category: "工资奖金", nature: .income)
            entry.batchID = batch.id; ledger.entries.append(entry)
        }
        for (index, date) in ["2026-09-05", "2026-10-05", "2026-11-05"].enumerated() {
            var entry = Round45BFixture.entry(ledger, date: date, amount: 16_000 + Int64(index) * 100, title: "电费", category: "居家")
            entry.batchID = batch.id; ledger.entries.append(entry)
        }
        return (ledger, batch.id)
    }
    func testRecognitionIsPureDeterministicAndAddsAllWithLinks() throws {
        var (ledger, batch) = recognitionLedger(); let before = ledger
        let candidates = ImportRecognition.plans(batchID: batch, in: ledger, now: now)
        XCTAssertEqual(candidates.count, 2); XCTAssertEqual(candidates, ImportRecognition.plans(batchID: batch, in: ledger, now: now))
        XCTAssertEqual(ledger, before); XCTAssertEqual(candidates.first?.kind, .salary)
        XCTAssertEqual(candidates.last?.plan.estimated, true)
        let plans = try ImportRecognition.addAll(batchID: batch, in: &ledger, now: now)
        XCTAssertEqual(plans.count, 2); XCTAssertEqual(ledger.entries.filter { $0.planID != nil }.count, 6)
        XCTAssertTrue(ImportRecognition.plans(batchID: batch, in: ledger, now: now).isEmpty)
        XCTAssertTrue(try ImportRecognition.addAll(batchID: batch, in: &ledger, now: now).isEmpty)
        XCTAssertEqual(ledger.imports[0].undo?.planIDs.count, 2)
        BillImporter.undo(batchID: batch, in: &ledger, now: now)
        XCTAssertTrue(ledger.plans.isEmpty); XCTAssertTrue(ledger.entries.isEmpty); XCTAssertTrue(ledger.imports.isEmpty)
    }
    func testRecognitionRejectsInsufficientIrregularFutureAndUnknownBatch() {
        var (ledger, batch) = recognitionLedger()
        ledger.entries.removeAll { $0.nature == .income }
        ledger.entries[1].date = d("2026-10-20")
        XCTAssertTrue(ImportRecognition.plans(batchID: batch, in: ledger, now: now).isEmpty)
        XCTAssertTrue(ImportRecognition.plans(batchID: UUID(), in: ledger, now: now).isEmpty)
        ledger.entries = Array(ledger.entries.prefix(2))
        XCTAssertTrue(ImportRecognition.plans(batchID: batch, in: ledger, now: now).isEmpty)
        (ledger, batch) = recognitionLedger()
        XCTAssertTrue(ImportRecognition.plans(batchID: batch, in: ledger, now: d("2026-09-01")).isEmpty)
    }
    func testSalaryRecognitionSurvivesPayrollAccountChange() throws {
        var (ledger, batch) = recognitionLedger()
        let newAccount = Account(name: "新工资卡", balance: 0, at: d("2026-08-01"))
        ledger.accounts.append(newAccount)
        ledger.entries[2].accountID = newAccount.id
        let salary = try XCTUnwrap(ImportRecognition.plans(batchID: batch, in: ledger, now: now).first { $0.kind == .salary })
        XCTAssertEqual(salary.plan.accountID, newAccount.id)
        XCTAssertEqual(salary.links.map(\.entryID), [ledger.entries[2].id])
        XCTAssertEqual(try ImportRecognition.addAll(batchID: batch, in: &ledger, now: now).count, 2)
        XCTAssertNil(ledger.entries[0].planID); XCTAssertNil(ledger.entries[1].planID)
        XCTAssertNotNil(ledger.entries[2].planID)
    }
    func testAddAllValidationFailureLeavesEntireLedgerUntouched() {
        var (ledger, batch) = recognitionLedger()
        ledger.plans = [Plan(title: "一笔安排", amount: Money.limit, dueDate: now)]
        let before = ledger
        XCTAssertThrowsError(try ImportRecognition.addAll(batchID: batch, in: &ledger, now: now))
        XCTAssertEqual(ledger, before)
    }
    func preview(_ text: String, in ledger: Ledger) throws -> (Data, ImportPreview) {
        let data = Data(text.utf8)
        return (data, try BillImporter.preview(data: data, filename: "流水.csv", accountID: ledger.accounts[0].id, ledger: ledger))
    }
    func manual(_ ledger: Ledger, date: String = "2026-11-19 12:00") -> Entry {
        var row = Round45BFixture.entry(ledger, date: date, amount: 3200, title: "和朋友午饭", category: "餐饮")
        row.purpose = "和朋友午饭"; row.recordedAt = now; row.userEdited = true; return row
    }
    func testImportMergeKeepsManualPurposeCategoryIDAndUndoesWithBatch() throws {
        var ledger = Round45BFixture.ledger(); let original = manual(ledger); ledger.entries = [original]
        let before = ledger
        let (data, preview) = try preview("日期,金额,收支,用途\n2026-11-20 10:00,32.00,支出,某某技术有限公司\n", in: ledger)
        let batch = try BillImporter.commit(preview, data: data, to: &ledger, now: now)
        XCTAssertEqual(ledger.activeEntries.count, 1)
        let result = try XCTUnwrap(ledger.activeEntries.first)
        XCTAssertEqual(result.id, original.id); XCTAssertEqual(result.purpose, original.purpose)
        XCTAssertEqual(result.category, original.category); XCTAssertEqual(result.title, "某某技术有限公司")
        XCTAssertEqual(result.batchID, batch.id); XCTAssertFalse(result.fingerprint.isEmpty)
        XCTAssertEqual(batch.undo?.entries, [original])
        XCTAssertEqual(try BillImporter.preview(data: data, filename: "流水.csv", accountID: ledger.accounts[0].id, ledger: ledger).duplicateCount, 1)
        BillImporter.undo(batchID: batch.id, in: &ledger, now: now); XCTAssertEqual(ledger, before)
    }
    func testSameTimestampManualRowIsReadyForMerge() throws {
        var ledger = Round45BFixture.ledger(); ledger.entries = [manual(ledger)]
        let (_, result) = try preview("日期,金额,收支,用途\n2026-11-19 12:00,32.00,支出,商户\n", in: ledger)
        XCTAssertEqual(result.readyCount, 1); XCTAssertEqual(result.selectedEntries.count, 1)
    }
    func testManualMatchingAccountUnknownAmbiguityAndDayBoundary() {
        var ledger = Round45BFixture.ledger(); let row = manual(ledger, date: "2026-11-19 23:59"); ledger.entries = [row]
        var imported = Round45BFixture.entry(ledger, date: "2026-11-20 00:01", amount: 3200)
        XCTAssertEqual(BillImporter.manualMergeCandidate(for: imported, in: ledger)?.id, row.id)
        imported.date = d("2026-11-21"); XCTAssertNil(BillImporter.manualMergeCandidate(for: imported, in: ledger))
        imported.date = now; imported.accountID = UUID()
        XCTAssertNil(BillImporter.manualMergeCandidate(for: imported, in: ledger))
        XCTAssertEqual(BillImporter.manualMergeCandidate(for: imported, accountIsUnknown: true, in: ledger)?.id, row.id)
        var another = row; another.id = UUID(); ledger.entries.append(another)
        XCTAssertNil(BillImporter.manualMergeCandidate(for: imported, accountIsUnknown: true, in: ledger))
        imported.amount = 0; XCTAssertNil(BillImporter.manualMergeCandidate(for: imported, accountIsUnknown: true, in: ledger))
        imported.amount = -3200; XCTAssertNil(BillImporter.manualMergeCandidate(for: imported, accountIsUnknown: true, in: ledger))
    }
    func testMergePaidBillAndUndoRestoresExactPlanAndHandRecord() throws {
        var ledger = Round45BFixture.ledger(); var row = manual(ledger)
        var plan = Plan(title: "电费", amount: 3200, dueDate: d("2026-11-20"), frequency: .monthly)
        plan.accountID = row.accountID; plan.settledOccurrences = [plan.dueDate]
        row.planID = plan.id; row.occurrence = plan.dueDate; ledger.plans = [plan]; ledger.entries = [row]
        let before = ledger
        let (data, result) = try preview("日期,金额,收支,用途\n2026-11-20,32.00,支出,电费\n", in: ledger)
        let batch = try BillImporter.commit(result, data: data, to: &ledger, now: now)
        XCTAssertEqual(ledger.activeEntries.count, 1); XCTAssertEqual(ledger.activeEntries[0].planID, plan.id)
        XCTAssertEqual(FixedFlows.month(containing: now, in: ledger).occurrences.first?.state, .paid)
        BillImporter.undo(batchID: batch.id, in: &ledger, now: now); XCTAssertEqual(ledger, before)
    }
    func testAutoLinkAddsPlanCompletionToBatchUndo() throws {
        var ledger = Round45BFixture.ledger()
        var plan = Plan(title: "电费", amount: 3200, dueDate: d("2026-11-20"), frequency: .monthly)
        plan.accountID = ledger.accounts[0].id; ledger.plans = [plan]
        let before = ledger
        let (data, result) = try preview("日期,金额,收支,用途\n2026-11-20,32.00,支出,电费\n", in: ledger)
        let batch = try BillImporter.commit(result, data: data, to: &ledger, now: now)
        XCTAssertEqual(ledger.activeEntries[0].planID, plan.id)
        XCTAssertEqual(ledger.imports[0].undo?.plans, [plan])
        BillImporter.undo(batchID: batch.id, in: &ledger, now: now); XCTAssertEqual(ledger, before)
    }
    func testTwoImportedRowsCannotConsumeOneManualRecord() throws {
        var ledger = Round45BFixture.ledger(); ledger.entries = [manual(ledger)]
        let (data, result) = try preview("日期,金额,收支,用途\n2026-11-20 10:00,32.00,支出,商户甲\n2026-11-20 11:00,32.00,支出,商户乙\n", in: ledger)
        _ = try BillImporter.commit(result, data: data, to: &ledger, now: now)
        XCTAssertEqual(ledger.activeEntries.count, 3)
    }
}
