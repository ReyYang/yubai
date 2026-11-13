import Foundation
import YubaiCore

/// Folder access belongs to this device, never to the portable ledger or its backups.
@MainActor final class WeeklyBackupAccess {
    static let shared = WeeklyBackupAccess()
    private var task: Task<Void, Never>?
    private func key(_ ledgerID: UUID) -> String { "Yubai.weeklyBackupFolder." + ledgerID.uuidString }

    func hasFolder(for ledgerID: UUID) -> Bool { UserDefaults.standard.data(forKey: key(ledgerID)) != nil }

    func remember(_ folder: URL, for ledgerID: UUID) throws {
        let access = folder.startAccessingSecurityScopedResource()
        defer { if access { folder.stopAccessingSecurityScopedResource() } }
        #if os(macOS)
        let options: URL.BookmarkCreationOptions = .withSecurityScope
        #else
        let options: URL.BookmarkCreationOptions = .minimalBookmark
        #endif
        let bookmark = try folder.bookmarkData(options: options, includingResourceValuesForKeys: nil, relativeTo: nil)
        UserDefaults.standard.set(bookmark, forKey: key(ledgerID))
    }

    func start(in store: AppStore) {
        let now = Date()
        guard task == nil, !store.locked, store.loadFailure == nil,
              !store.syncBusy, store.syncChoice == nil, !store.switchingLedgerLocation, !store.choosingSyncVersion,
              LedgerBackup.isAutoBackupDue(store.preferences, now: now),
              let bookmark = UserDefaults.standard.data(forKey: key(store.current.id)) else { return }
        task = Task { @MainActor [weak self, weak store] in
            defer { self?.task = nil }
            guard let self, let store else { return }
            let ledgerID = store.current.id
            await store.flushPersistence()
            guard !Task.isCancelled, store.current.id == ledgerID, !store.locked,
                  LedgerBackup.isAutoBackupDue(store.preferences, now: now) else { return }
            let ledger = store.current
            do {
                let refreshedBookmark = try await Task.detached(priority: .utility) {
                    try Self.write(ledger, bookmark: bookmark, at: now)
                }.value
                if let refreshedBookmark { UserDefaults.standard.set(refreshedBookmark, forKey: self.key(ledgerID)) }
                store.recordSuccessfulBackup(of: ledgerID, at: now)
            } catch { if store.current.id == ledgerID { store.error = error.localizedDescription } }
        }
    }

    nonisolated private static func write(_ ledger: Ledger, bookmark: Data, at date: Date) throws -> Data? {
        var stale = false
        #if os(macOS)
        let resolving: URL.BookmarkResolutionOptions = [.withSecurityScope, .withoutUI]
        let creating: URL.BookmarkCreationOptions = .withSecurityScope
        #else
        let resolving: URL.BookmarkResolutionOptions = .withoutUI
        let creating: URL.BookmarkCreationOptions = .minimalBookmark
        #endif
        let folder = try URL(resolvingBookmarkData: bookmark, options: resolving, relativeTo: nil, bookmarkDataIsStale: &stale)
        let access = folder.startAccessingSecurityScopedResource()
        defer { if access { folder.stopAccessingSecurityScopedResource() } }
        let data = try Backup.export(ledger)
        let filename = "余白备份-" + Dates.text(date) + "-" + UUID().uuidString + ".yubaibackup"
        let target = folder.appendingPathComponent(filename)
        var coordinationError: NSError?
        var writeError: Error?
        var wrote = false
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: target, options: [], error: &coordinationError) { url in
            do { try data.write(to: url, options: .atomic); wrote = true }
            catch { writeError = error }
        }
        if let coordinationError { throw coordinationError }
        if let writeError { throw writeError }
        guard wrote else { throw CocoaError(.fileWriteUnknown) }
        return stale ? try? folder.bookmarkData(options: creating, includingResourceValuesForKeys: nil, relativeTo: nil) : nil
    }
}

@MainActor extension AppStore {
    func runAutomaticBackupIfDue() { WeeklyBackupAccess.shared.start(in: self) }
}
