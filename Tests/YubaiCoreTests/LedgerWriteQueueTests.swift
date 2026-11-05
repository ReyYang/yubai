import XCTest
@testable import YubaiCore

final class LedgerWriteQueueTests: XCTestCase {
    private func repository() -> LedgerRepository {
        LedgerRepository(directory: FileManager.default.temporaryDirectory.appendingPathComponent("writer-\(UUID())"))
    }
    func testFIFOManualEditCheckpointRebaseAndFlush() async throws {
        let repo = repository(); defer { try? FileManager.default.removeItem(at: repo.directory) }
        var seed = Ledger(); seed.accounts = [Account(name: "Synthetic")]
        seed = try repo.save(seed)
        let snapshot = seed
        let diskRevision = repo.revision
        let writer = LedgerWriteQueue()
        var manual = seed; manual.accounts[0].note = "manual"
        let manualLedger = manual
        let write = writer.submit { try repo.save(manualLedger, requiringUnchanged: true) }
        let stale = writer.submit(invalidatingOnFailure: false) {
            try repo.save(snapshot, requiringUnchanged: true, preservingRecovery: false, expectedRevision: diskRevision)
        }
        _ = try await write.value
        do { _ = try await stale.value; XCTFail("Stale checkpoint overwrote a manual save") }
        catch { XCTAssertTrue(error is LedgerSyncError) }
        let latest = try repo.load(), revision = repo.revision
        var rebased = latest; rebased.accounts[0].name = "checkpoint"
        let rebasedLedger = rebased
        let checkpoint = writer.submit(invalidatingOnFailure: false) {
            try repo.save(rebasedLedger, requiringUnchanged: true, preservingRecovery: false, expectedRevision: revision)
        }
        _ = try await checkpoint.value; await writer.flush()
        let disk = try repo.load()
        XCTAssertEqual(disk.accounts[0].note, "manual"); XCTAssertEqual(disk.accounts[0].name, "checkpoint")
    }
    func testManualSnapshotAfterInFlightCheckpointAndRebasedReplyKeepBothEdits() async throws {
        let repo = repository(); defer { try? FileManager.default.removeItem(at: repo.directory) }
        var seed = Ledger(); seed.accounts = [Account(name: "Synthetic")]; seed = try repo.save(seed)
        let writer = LedgerWriteQueue(), revision = repo.revision
        var organized = seed; organized.accounts[0].note = "checkpoint"
        let reply = organized
        let checkpoint = writer.submit(invalidatingOnFailure: false) { try repo.save(reply, requiringUnchanged: true, preservingRecovery: false, expectedRevision: revision) }
        var edited = seed; edited.accounts[0].name = "manual"
        let edit = edited
        let manual = writer.submit { try repo.save(edit, requiringUnchanged: true) }
        _ = try await checkpoint.value; _ = try await manual.value
        // AppStore detects ledgerRevision changed and reapplies only the reply.
        var rebased = try repo.load(); rebased.accounts[0].note = reply.accounts[0].note
        let combined = rebased
        _ = try await writer.submit(invalidatingOnFailure: false) { try repo.save(combined, requiringUnchanged: true, preservingRecovery: false) }.value
        XCTAssertEqual(try repo.load(), combined)
    }
    func testFailedWriteRejectsDependentSnapshotsUntilDurableReload() async throws {
        let repo = repository(); defer { try? FileManager.default.removeItem(at: repo.directory) }
        var seed = Ledger(); seed.accounts = [Account(name: "Durable")]; seed = try repo.save(seed)
        let writer = LedgerWriteQueue()
        let failed: LedgerWriteReceipt<Ledger> = writer.submit { throw YubaiError.invalid("Synthetic disk failure") }
        var dependent = seed; dependent.accounts[0].name = "Must not survive"
        let uncommitted = dependent
        let skipped = writer.submit { try repo.save(uncommitted, requiringUnchanged: true) }
        do { _ = try await failed.value; XCTFail() } catch {}
        do { _ = try await skipped.value; XCTFail() } catch {}
        let durable = try await writer.reset { try repo.load() }.value
        XCTAssertEqual(durable, seed)
        var retried = durable; retried.accounts[0].name = "Retry"
        let retry = retried
        _ = try await writer.submit { try repo.save(retry, requiringUnchanged: true) }.value
        writer.flushBlocking()
        XCTAssertEqual(try repo.load(), retry)
    }
    func testExternalCASFailureRollsBackToExternalDiskRatherThanOptimisticSnapshot() async throws {
        let repo = repository(); defer { try? FileManager.default.removeItem(at: repo.directory) }
        var seed = Ledger(); seed.accounts = [Account(name: "Original")]; seed = try repo.save(seed)
        var external = seed; external.accounts[0].name = "External"
        try LedgerCodec.encodeMetadata(external).write(to: repo.file, options: .atomic)
        let writer = LedgerWriteQueue(), optimistic = seed
        do { _ = try await writer.submit { try repo.save(optimistic, requiringUnchanged: true) }.value; XCTFail() }
        catch { XCTAssertTrue(error is LedgerSyncError) }
        let disk = try await writer.reset { try repo.load() }.value
        XCTAssertEqual(disk, external)
    }
}
