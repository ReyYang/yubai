import Foundation
import Observation
import YubaiCore

struct SyncChoice {
    var versions: [LedgerVersion]
    var source: FileLedgerVersionSource
    var target: LedgerLocation
    var switching: Bool
}

@MainActor final class CloudLedgerMonitor {
    #if YUBAI_ICLOUD
    private let query = NSMetadataQuery()
    private var observers: [NSObjectProtocol] = []
    private var gathered = false
    init(directory: URL, changed: @escaping @MainActor ([URL]) -> Void, identityChanged: @escaping @MainActor () -> Void) {
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        query.predicate = NSPredicate(value: true)
        for name in [Notification.Name.NSMetadataQueryDidFinishGathering, Notification.Name.NSMetadataQueryDidUpdate] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: query, queue: .main) { [weak self] notification in
                Task { @MainActor in
                    guard let self else { return }
                    self.query.disableUpdates(); defer { self.query.enableUpdates() }
                    let files = (self.query.results as? [NSMetadataItem] ?? []).compactMap { $0.value(forAttribute: NSMetadataItemURLKey) as? URL }
                        .filter { $0.standardizedFileURL.path.hasPrefix(directory.standardizedFileURL.path + "/") }
                    changed(files)
                    if notification.name == Notification.Name.NSMetadataQueryDidFinishGathering { self.gathered = true }
                }
            })
        }
        observers.append(NotificationCenter.default.addObserver(forName: .NSUbiquityIdentityDidChange, object: nil, queue: .main) { _ in Task { @MainActor in identityChanged() } })
        query.start()
    }
    func waitForDiscovery() async throws {
        for _ in 0..<300 {
            if gathered { return }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        throw YubaiError.invalid("iCloud 文件列表尚未读取完成，请联网后重试。")
    }
    deinit {
        query.stop()
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }
    #else
    init(directory: URL, changed: @escaping @MainActor ([URL]) -> Void, identityChanged: @escaping @MainActor () -> Void) {}
    func waitForDiscovery() async throws {}
    #endif
    static func availableDirectory() async -> URL? {
        #if YUBAI_ICLOUD
        return await Task.detached(priority: .utility) {
            FileManager.default.url(forUbiquityContainerIdentifier: "iCloud.app.yubai.personal")?
                .appendingPathComponent("Documents/Yubai", isDirectory: true)
        }.value
        #else
        return nil
        #endif
    }
}

extension AppStore {
    private var locationKey: String { "ledgerLocation:" + localRepository.directory.path }
    func canEditLedger() -> Bool {
        guard !locked else { error = "请先解锁账本。"; return false }
        guard syncChoice == nil, !switchingLedgerLocation, !choosingSyncVersion else { error = "请先完成账本位置或同步版本的选择。"; return false }
        return true
    }
    func persist(_ next: Ledger, reason: String, restoring: Bool = false) throws -> Ledger {
        var saved: Ledger
        let wasPending = localRepository.hasPendingSync
        if ledgerLocation == .iCloud { try localRepository.markPendingSync(true) }
        do {
            if restoring { saved = try localRepository.restoreBackup(next) }
            else { saved = try localRepository.save(next, reason: reason) }
        } catch {
            if !wasPending { try? localRepository.markPendingSync(false) }; throw error
        }
        if ledgerLocation == .iCloud {
            pendingUpload = saved
            Task { await synchronizeLedger() }
        }
        return saved
    }
    func configureSync() async {
        guard syncAllowed, loadFailure == nil else { return }
        guard !syncBusy, !checkingCloudAvailability else { syncAvailabilityNeedsRefresh = true; return }
        checkingCloudAvailability = true; syncAvailabilityNeedsRefresh = false
        defer {
            checkingCloudAvailability = false
            if syncAvailabilityNeedsRefresh, !syncBusy { Task { await configureSync() } }
        }
        let directory = await CloudLedgerMonitor.availableDirectory()
        guard !syncBusy else { syncAvailabilityNeedsRefresh = true; return }
        guard let directory else {
            // The latest accepted/upload-pending ledger already lives in Application Support.
            if ledgerLocation == .iCloud { syncStatus = "iCloud 不可用，继续使用本机账本。" }
            ledgerLocation = .local; pendingUpload = nil; syncChoice = nil
            if case .syncVersions? = sheet { sheet = nil }
            UserDefaults.standard.set(LedgerLocation.local.rawValue, forKey: locationKey)
            try? localRepository.markPendingSync(false)
            locations = LedgerLocations(local: localRepository, cloudDirectory: nil); syncMonitor = nil
            return
        }
        guard syncChoice == nil else { return }
        if locations.cloud?.directory != directory {
            locations = LedgerLocations(local: localRepository, cloudDirectory: directory, ubiquitous: true)
            syncMonitor = CloudLedgerMonitor(directory: directory, changed: { [weak self] files in
                self?.locations.cloud?.updateDiscoveredFiles(files)
                Task { await self?.synchronizeLedger() }
            }, identityChanged: { [weak self] in
                Task { await self?.configureSync() }
            })
        }
        if UserDefaults.standard.string(forKey: locationKey) == LedgerLocation.iCloud.rawValue {
            ledgerLocation = .iCloud
            if localRepository.hasPendingSync { pendingUpload = current }
            await synchronizeLedger()
        }
    }
    func switchLedgerLocation(to target: LedgerLocation) async {
        guard canEditLedger(), !syncBusy, target != ledgerLocation else { return }
        guard pendingUpload == nil || target == .local else { error = "本机修改还未同步，请重试同步或选择冲突版本后再切换。"; return }
        let locations = locations; var before = current
        if target == .iCloud { before.preferences.lockEnabled = false }
        switchingLedgerLocation = true
        defer { switchingLedgerLocation = false; finishSyncOperation() }
        syncBusy = true; syncStatus = target == .iCloud ? "正在从 iCloud 读取…" : "正在保存到本机…"
        do {
            if target == .iCloud { try await syncMonitor?.waitForDiscovery() }
            let change = try await Task.detached { try locations.previewSwitch(to: target, current: before) }.value
            syncBusy = false
            let choice = SyncChoice(versions: change.versions, source: change.source, target: target, switching: true)
            if change.needsChoice { presentSyncChoice(choice) }
            else { await chooseSyncVersion(choice, id: change.versions[0].id) }
        } catch { syncBusy = false; syncStatus = error.localizedDescription; self.error = error.localizedDescription }
    }
    private func presentSyncChoice(_ choice: SyncChoice) {
        syncChoice = choice; syncStatus = "两份账本都已保留，请选择继续使用哪一份。"
        if !locked, sheet == nil { sheet = .syncVersions }
    }
    func cancelSyncLocationChoice() {
        guard syncChoice?.switching == true, !syncBusy else { return }
        syncChoice = nil; sheet = nil; syncStatus = "已保留当前账本位置。"
    }
    func chooseSyncVersion(_ choice: SyncChoice, id: String) async {
        guard !locked, !syncBusy else { return }
        let destination: LedgerRepository
        do { destination = try locations.repository(for: choice.target) }
        catch { self.error = error.localizedDescription; return }
        choosingSyncVersion = true
        defer { choosingSyncVersion = false; finishSyncOperation() }
        syncBusy = true; syncStatus = "正在保存所选账本…"
        do {
            var selected = try await Task.detached {
                try destination.resolve(choice.versions, choosing: id, source: choice.source,
                                        reason: choice.switching ? "切换存储时的另一版本" : "同步冲突时的另一版本",
                                        prepare: { LedgerMemoryMerge.merge(chosen: $0, others: choice.versions.filter { $0.id != id }.map(\.ledger)) })
            }.value
            selected.preferences.lockEnabled = current.preferences.lockEnabled
            if choice.target == .iCloud { selected = try localRepository.restoreBackup(selected) }
            adoptSyncedLedger(selected)
            ledgerLocation = choice.target; syncChoice = nil; pendingUpload = nil
            UserDefaults.standard.set(choice.target.rawValue, forKey: locationKey)
            try? localRepository.markPendingSync(false)
            sheet = nil; syncStatus = "已使用所选账本，另一版本在本机恢复历史中。"; syncBusy = false
        } catch LedgerSyncError.changed {
            syncBusy = false; syncChoice = nil
            self.error = "账本又有更新，请查看最新版本后重新选择。"
            if choice.switching { Task { await switchLedgerLocation(to: choice.target) } }
            else { Task { await synchronizeLedger() } }
        } catch { syncBusy = false; syncStatus = error.localizedDescription; self.error = error.localizedDescription }
    }
    private func finishSyncOperation() {
        syncBusy = false
        if syncAvailabilityNeedsRefresh {
            if !checkingCloudAvailability { Task { await configureSync() } }
        } else if syncRefreshRequested, syncChoice == nil {
            syncRefreshRequested = false
            Task { await synchronizeLedger() }
        }
    }
    private enum SyncResult: Sendable {
        case uploaded(Ledger), loaded(Ledger), conflict([LedgerVersion])
    }
    func synchronizeLedger() async {
        guard ledgerLocation == .iCloud, syncChoice == nil, !locked, let repository = locations.cloud else { return }
        guard !syncBusy else { syncRefreshRequested = true; return }
        syncRefreshRequested = false
        syncBusy = true
        defer { finishSyncOperation() }
        syncStatus = "正在从 iCloud 读取…"
        let submitted = pendingUpload; let before = current
        let source = FileLedgerVersionSource(repository: repository)
        do {
            try await syncMonitor?.waitForDiscovery()
            let result = try await Task.detached { () throws -> SyncResult in
                if let submitted {
                    var shared = submitted; shared.preferences.lockEnabled = false
                    do { try repository.save(shared); return .uploaded(submitted) }
                    catch LedgerSyncError.changed { return .conflict(try source.versions()) }
                }
                let versions = try source.versions()
                if versions.count > 1 { return .conflict(versions) }
                // An absent remote ledger is never silently replaced by an empty ledger.
                guard !versions.isEmpty else { throw YubaiError.invalid("iCloud 账本暂不可读，本机副本已保留。请重试或切回仅本机。") }
                return .loaded(try repository.load())
            }.value
            switch result {
            case .uploaded(let uploaded):
                if pendingUpload == uploaded { pendingUpload = nil; try? localRepository.markPendingSync(false) }
                syncStatus = pendingUpload == nil ? "已保存到 iCloud。" : "本机修改等待上传…"
            case .loaded(var remote):
                remote.preferences.lockEnabled = current.preferences.lockEnabled
                if pendingUpload != nil || current != before {
                    var versions = try await Task.detached { try source.versions() }.value
                    var shared = current; shared.preferences.lockEnabled = false
                    versions.insert(LedgerVersion(id: "device", ledger: shared, deviceName: "这台设备（尚未同步）"), at: 0)
                    presentSyncChoice(SyncChoice(versions: versions, source: source, target: .iCloud, switching: false))
                } else if remote != current {
                    remote = try localRepository.save(remote, reason: "接收同步前")
                    adoptSyncedLedger(remote); syncStatus = "已读取 iCloud 账本。"
                } else { syncStatus = "已读取 iCloud 账本。" }
            case .conflict(var versions):
                if var pending = pendingUpload { pending.preferences.lockEnabled = false; versions.insert(LedgerVersion(id: "device", ledger: pending, deviceName: "这台设备（尚未同步）"), at: 0) }
                presentSyncChoice(SyncChoice(versions: versions, source: source, target: .iCloud, switching: false))
            }
            if pendingUpload != nil, syncChoice == nil { syncRefreshRequested = true }
        } catch LedgerSyncError.changed {
            syncRefreshRequested = true
        } catch {
            syncStatus = error.localizedDescription
            if await CloudLedgerMonitor.availableDirectory() == nil { syncAvailabilityNeedsRefresh = true }
            // Pending edits and their marker remain local across launch/retry.
        }
    }
}
