import Foundation
import XCTest
@testable import YubaiCore

/// 撤销 on a home deletion brings back that deletion only.
final class BillDeleteUndoTests: XCTestCase {
    private let now = Dates.parse("2026-11-23 14:20:00")!

    func testUndoRestoresOnlyTheEntriesOfThatDeletion() throws {
        var ledger = Ledger()
        let bank = Account(name: "招行储蓄", kind: .bank, balance: 100_000, at: Dates.parse("2026-11-01")!)
        ledger.accounts = [bank]
        var taxi = Entry(date: now, amount: 3_650, accountID: bank.id, title: "打车", category: "交通")
        taxi.pendingRecovery = .reimbursement
        ledger.entries = [taxi, Entry(date: now, amount: 1_200, accountID: bank.id, title: "午饭", category: "吃饭")]
        let lunchID = ledger.entries[1].id
        let receipt = try EntryRecovery.receive(originalID: taxi.id, into: bank.id, in: &ledger, now: now)

        let deleted = try EntryRecovery.delete(taxi.id, from: &ledger, now: now)
        XCTAssertEqual(deleted, [taxi.id, receipt.id])

        // What happens between the delete and its 撤销 stays: a renamed category, another deletion.
        try CategoryModel.add(Category("夜宵", income: false), in: &ledger)
        try CategoryModel.rename("夜宵", to: "宵夜", income: false, in: &ledger)
        try EntryRecovery.delete(lunchID, from: &ledger, now: now.addingTimeInterval(2))

        try EntryRecovery.undoDelete(deleted, deletedAt: now, in: &ledger)
        let active = Set(ledger.activeEntries.map(\.id))
        XCTAssertTrue(active.contains(taxi.id))
        XCTAssertTrue(active.contains(receipt.id))
        XCTAssertFalse(active.contains(lunchID), "the later deletion is not this bar's to undo")
        XCTAssertTrue(ledger.categories.contains { $0.name == "宵夜" && !$0.income }, "the rename made in between stays")
    }

    func testUndoAfterTheBillCameBackOtherwiseChangesNothing() throws {
        var ledger = Ledger()
        let bank = Account(name: "招行储蓄", kind: .bank, at: Dates.parse("2026-11-01")!)
        ledger.accounts = [bank]
        ledger.entries = [Entry(date: now, amount: 1_200, accountID: bank.id, title: "午饭", category: "吃饭")]
        let id = ledger.entries[0].id
        let deleted = try EntryRecovery.delete(id, from: &ledger, now: now)
        ledger.entries[0].deletedAt = nil
        let before = ledger
        XCTAssertThrowsError(try EntryRecovery.undoDelete(deleted, deletedAt: now, in: &ledger))
        XCTAssertEqual(ledger, before)
    }
}
