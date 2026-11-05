import XCTest
@testable import YubaiCore

final class PerformanceProfileTests: XCTestCase {
    func t(_ name: String, _ n: Int = 1, _ body: () throws -> Void) rethrows {
        let s = Date(); for _ in 0..<n { try body() }
        let elapsed = Date().timeIntervalSince(s) * 1000 / Double(n)
        if name == "save preservingRecovery (记一笔)" { XCTAssertLessThan(elapsed, 500) }
        if name == "cashTimeline" { XCTAssertLessThan(elapsed, 40) }
        if name == "available(after:)" || name == "available(edit:)" { XCTAssertLessThan(elapsed, 12) }
        print(String(format: "PROF %-40@ %8.1f ms", name as NSString, elapsed))
    }
    func testProfile() throws {
        guard let csvPath = ProcessInfo.processInfo.environment["PROF_CSV"] else { return }
        let csv = try Data(contentsOf: URL(fileURLWithPath: csvPath))
        var ledger = Ledger(); ledger.accounts = [Account(name: "银行卡")]
        let preview = try BillImporter.preview(data: csv, filename: "m.csv", accountID: ledger.accounts[0].id, ledger: ledger)
        _ = try BillImporter.commit(preview, data: csv, to: &ledger)
        print("PROF entries", ledger.entries.count)
        XCTAssertGreaterThanOrEqual(ledger.entries.count, 8)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("yubai-performance-\(UUID())")
        defer { try? FileManager.default.removeItem(at: dir) }
        let repo = LedgerRepository(directory: dir)
        try repo.save(Ledger())
        ledger = try repo.save(ledger, reason: "导入")
        for i in 0..<7 { var l = ledger; l.entries[i].purpose = "x\(i)"; ledger = try repo.save(l, reason: "改\(i)") }
        print("PROF recoveries", try repo.recoveries().count)
        try t("encodeMetadata") { _ = try LedgerCodec.encodeMetadata(ledger) }
        let bytes = try LedgerCodec.encodeMetadata(ledger); print("PROF bytes", bytes.count)
        try t("decode") { _ = try LedgerCodec.decode(bytes) }
        try t("save preservingRecovery (记一笔)", 3) { var l = ledger; l.entries[7].purpose = UUID().uuidString; ledger = try repo.save(l, reason: "记一笔", requiringUnchanged: true) }
        try t("save merged recovery", 3) { var l = ledger; l.entries[7].purpose = UUID().uuidString; ledger = try repo.save(l, reason: "按对方分", requiringUnchanged: true) }
        try t("save no recovery", 3) { var l = ledger; l.entries[7].purpose = UUID().uuidString; ledger = try repo.save(l, reason: "x", requiringUnchanged: true, preservingRecovery: false) }
        let acct = ledger.accounts[0]
        t("Finance.funds cold") { _ = Finance.funds(ledger) }
        t("Finance.funds", 3) { _ = Finance.funds(ledger) }
        let funds = Finance.funds(ledger)
        t("cashTimeline", 3) { _ = Finance.cashTimeline(ledger, funds: funds, now: Date()) }
        t("Finance.balance", 3) { _ = Finance.balance(acct, in: ledger) }
        t("RestrainProgress", 3) { _ = RestrainProgress.current(ledger: ledger) }
        t("ButlerCards.queued", 3) { _ = ButlerCards.queued(ledger) }
        t("SalaryDetection", 3) { _ = SalaryDetection.candidate(in: ledger) }
        t("PendingImportOrganization", 3) { _ = PendingImportOrganization(in: ledger) }
        t("FixedFlows.month", 3) { _ = FixedFlows.month(containing: Date(), in: ledger) }
        t("FixedFlows.autoSettle", 3) { _ = FixedFlows.autoSettle(in: ledger) }
        t("FixedFlows.suggestions", 3) { _ = FixedFlows.suggestions(amount: 3000, nature: .expense, purpose: "午饭", day: Date(), accountID: acct.id, in: ledger) }
        t("categories", 3) { _ = ManualBookkeeping.categories(in: ledger, nature: .expense, frequentOnly: true) }
        t("guessCategory", 3) { _ = ManualBookkeeping.guessCategory("美团外卖", nature: .expense, in: ledger) }
        t("defaultAccount", 3) { _ = ManualBookkeeping.defaultAccount(in: ledger) }
        let change = try ManualBookkeeping.change(amount: 3000, nature: .expense, accountID: acct.id, day: Date(), purpose: "午饭", category: "餐饮")
        try t("available(after:) cold") { _ = try ManualBookkeeping.available(after: change, in: ledger) }
        try t("available(after:)", 10) { _ = try ManualBookkeeping.available(after: change, in: ledger) }
        var edited = ledger.entries[7]; edited.amount += 1
        try t("available(edit:)", 3) { _ = try ManualBookkeeping.available(after: edited, in: ledger) }
        try t("changeSet.apply", 3) { var l = ledger; _ = try change.apply(to: &l) }
        try t("validate", 3) { try ledger.validate() }
        let sorted = ledger.entries.sorted { $0.date > $1.date }
        t("sort entries", 3) { _ = ledger.entries.sorted { $0.date > $1.date } }
        t("EntryTimeline.snapshot", 3) { _ = EntryTimeline.snapshot(sortedEntries: sorted, ledger: ledger, month: Date(), calendar: Dates.calendar) }
        t("activeEntries", 3) { _ = ledger.activeEntries }
        t("ledger ==", 3) { _ = ledger == ledger }
        t("QuickCaptureSnapshot", 3) { _ = QuickCaptureSnapshot(ledger: ledger) }
    }
}
