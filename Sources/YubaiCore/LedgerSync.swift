import Foundation

public enum LedgerLocation: String, Codable, Sendable {
    case local, iCloud
    public var label: String { self == .local ? "仅本机" : "iCloud" }
}

public struct LedgerVersion: Identifiable, Sendable {
    public var id: String
    public var ledger: Ledger
    public var date: Date
    public var deviceName: String?
    public init(id: String, ledger: Ledger, date: Date? = nil, deviceName: String? = nil) {
        self.id = id; self.ledger = ledger; self.date = date ?? ledger.updatedAt; self.deviceName = deviceName
    }
    public func differingEntries(from other: Ledger) -> [Entry] {
        let previous = Dictionary(uniqueKeysWithValues: other.entries.map { ($0.id, $0) })
        return Array(ledger.entries.lazy.filter { previous[$0.id] != $0 }.prefix(3))
    }
}

// Resolution is in LedgerRepository; tests can supply versions without iCloud or entitlements.
public protocol LedgerVersionSource: Sendable {
    func versions() throws -> [LedgerVersion]
    func validate() throws
    func markResolved() throws
}

public final class FileLedgerVersionSource: LedgerVersionSource, @unchecked Sendable {
    private let repository: LedgerRepository
    private var fingerprint: String?
    #if !os(Linux)
    private var conflicts: [NSFileVersion] = []
    #endif
    public init(repository: LedgerRepository) { self.repository = repository }
    #if !os(Linux)
    private func unresolved() -> [NSFileVersion] {
        repository.isUbiquitous ? NSFileVersion.unresolvedConflictVersionsOfItem(at: repository.file) ?? [] : []
    }
    private func sameConflicts(_ latest: [NSFileVersion]) -> Bool {
        latest.count == conflicts.count && conflicts.allSatisfy { old in
            latest.contains { (old.persistentIdentifier as? NSObject)?.isEqual($0.persistentIdentifier) == true }
        }
    }
    #endif
    public func versions() throws -> [LedgerVersion] {
        try repository.access(writing: false) { root in
            let file = root.appendingPathComponent("ledger.json")
            #if !os(Linux)
            conflicts = unresolved()
            #endif
            guard repository.containsFile(file) else {
                fingerprint = nil; return []
            }
            let payloads = root.appendingPathComponent("Attachments", isDirectory: true)
            let current = try repository.read(file, attachmentDirectory: payloads)
            fingerprint = try LedgerCodec.checksum(Data(contentsOf: file))
            #if os(Linux)
            return [LedgerVersion(id: "current", ledger: current)]
            #else
            let native = repository.isUbiquitous ? NSFileVersion.currentVersionOfItem(at: file) : nil
            var result = [LedgerVersion(id: "current", ledger: current, date: native?.modificationDate, deviceName: native?.localizedNameOfSavingComputer)]
            for (index, version) in conflicts.enumerated() {
                let ledger = try repository.read(version.url, attachmentDirectory: payloads)
                result.append(LedgerVersion(id: "conflict-\(index)", ledger: ledger, date: version.modificationDate, deviceName: version.localizedNameOfSavingComputer))
            }
            return result
            #endif
        }
    }
    public func validate() throws {
        // Invoked under the repository's write coordination, immediately before replacement.
        let file = repository.file
        let latest = FileManager.default.fileExists(atPath: file.path) ? try LedgerCodec.checksum(Data(contentsOf: file)) : nil
        guard latest == fingerprint else { throw LedgerSyncError.changed }
        #if !os(Linux)
        guard sameConflicts(unresolved()) else { throw LedgerSyncError.changed }
        #endif
    }
    public func markResolved() throws {
        // Only the versions the user saw are marked resolved. Never delete newly arriving versions.
        #if !os(Linux)
        for version in conflicts { version.isResolved = true }
        #endif
    }
}

public struct LedgerLocationChange: Sendable {
    public var target: LedgerLocation
    public var versions: [LedgerVersion]
    public var source: FileLedgerVersionSource
    public var needsChoice: Bool { target == .iCloud && versions.count > 1 }
}

public struct LedgerLocations: Sendable {
    public let local: LedgerRepository
    public let cloud: LedgerRepository?
    public init(local: LedgerRepository, cloudDirectory: URL?, ubiquitous: Bool = false) {
        self.local = local; cloud = cloudDirectory.map { local.relocated(to: $0, isUbiquitous: ubiquitous) }
    }
    public func repository(for location: LedgerLocation) throws -> LedgerRepository {
        if location == .local { return local }
        guard let cloud else { throw YubaiError.invalid("iCloud 不可用，账本仍保存在本机。") }
        return cloud
    }
    public func previewSwitch(to location: LedgerLocation, current: Ledger) throws -> LedgerLocationChange {
        let destination = try repository(for: location)
        let source = FileLedgerVersionSource(repository: destination)
        var versions = try source.versions()
        if versions.isEmpty || versions.contains(where: { $0.ledger != current }) {
            versions.insert(LedgerVersion(id: "device", ledger: current, deviceName: "这台设备"), at: 0)
        }
        return LedgerLocationChange(target: location, versions: versions, source: source)
    }
    public func completeSwitch(_ change: LedgerLocationChange, choosing id: String) throws -> Ledger {
        try repository(for: change.target).resolve(change.versions, choosing: id, source: change.source, reason: "切换存储时的另一版本")
    }
}
