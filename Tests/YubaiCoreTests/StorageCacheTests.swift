import XCTest
@testable import YubaiCore

final class StorageCacheTests: XCTestCase {
    private func repository() -> LedgerRepository {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cache-\(UUID())")
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return LedgerRepository(directory: root, recoveryDate: { Date(timeIntervalSince1970: 1000) })
    }
    private func fixture() -> Ledger {
        var ledger = Ledger(); ledger.accounts = [Account(name: "Synthetic")]
        let item = Attachment(name: "Synthetic", data: Data([1, 2, 3]))
        var entry = Entry(amount: 100, accountID: ledger.accounts[0].id, title: "Synthetic")
        entry.attachmentID = item.id; ledger.entries = [entry]; ledger.attachments = [item]
        return ledger
    }
    func testCachedWindowAnchorIsRecheckedWhenSnapshotOrPayloadChanges() throws {
        for damagePayload in [false, true] {
            let repo = repository(); var ledger = try repo.save(fixture())
            ledger.accounts[0].note = "first"; ledger = try repo.save(ledger, reason: "按对方分", requiringUnchanged: true)
            let first = try XCTUnwrap(repo.recoveries().first)
            // Both metadata and payload readability have now been cached.
            if damagePayload {
                let payload = repo.localDirectory.appendingPathComponent("Recovery/Payloads/" + ledger.attachments[0].id.uuidString)
                try Data([9, 9, 9]).write(to: payload, options: .atomic)
            } else { try Data("damaged".utf8).write(to: first.url, options: .atomic) }
            // Lazy metadata saves retain their existing policy. A damaged anchor
            // must never suppress a new snapshot, including damaged payloads.
            ledger.accounts[0].note = "second"
            _ = try repo.save(ledger, reason: "按对方分", requiringUnchanged: true)
            let latest = try XCTUnwrap(repo.recoveries().first)
            XCTAssertNotEqual(latest.url, first.url)
            if damagePayload { XCTAssertThrowsError(try repo.readRecovery(latest)) }
            else { XCTAssertEqual(try repo.readRecovery(latest).accounts[0].note, "first") }
        }
    }
    func testExternalCurrentAttachmentReferencesAreNotCollectedUsingStaleCache() throws {
        let repo = repository(); var current = try repo.save(fixture())
        try repo.preserveRecovery(current, reason: "manual")
        let payload = repo.localDirectory.appendingPathComponent("Recovery/Payloads/" + current.attachments[0].id.uuidString)
        current.accounts[0].note = "external"
        try LedgerCodec.encodeMetadata(current).write(to: repo.file, options: .atomic)
        // Exercise pruneHistory with a cached live digest that is no longer current.
        try repo.preserveRecovery(current, reason: "manual")
        XCTAssertTrue(FileManager.default.fileExists(atPath: payload.path))
        XCTAssertEqual(try repo.readRecovery(XCTUnwrap(repo.recoveries().first)).accounts[0].note, "external")
    }
}
