import Foundation
#if canImport(CryptoKit)
import CryptoKit
#elseif os(Linux)
import Crypto
import _CryptoExtras
#endif
import CArchive
#if os(Linux)
import Glibc
#else
import Darwin
#endif

extension CodingUserInfoKey {
    static let ledgerMetadataOnly = CodingUserInfoKey(rawValue: "yubai.metadataOnly")!
}
private struct LedgerHeader: Decodable { let schema: Int }

public enum LedgerCodec {
    public static let capacity = 250 * 1024 * 1024
    // Bound bundles by the existing per-file and attachment-count limits, not a total payload quota.
    public static let bundleCapacity = capacity + 5000 * ((capacity + 2) / 3 * 4 + 1024)
    public static let backupCapacity = (bundleCapacity + 2) / 3 * 4 + 4096
    static func checksum(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    public static func encode(_ ledger: Ledger) throws -> Data { try encoded(ledger, metadataOnly: false) }
    public static func encodeMetadata(_ ledger: Ledger) throws -> Data { try encoded(ledger, metadataOnly: true) }
    private static func encoded(_ ledger: Ledger, metadataOnly: Bool) throws -> Data {
        try ledger.validate()
        try validateAttachments(ledger, requirePayloads: !metadataOnly)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        encoder.userInfo[.ledgerMetadataOnly] = true
        let metadata = try encoder.encode(ledger)
        guard metadata.count <= capacity else { throw YubaiError.invalid("账本资料超过 250 MB，本次修改未保存。") }
        if metadataOnly { return metadata }
        encoder.userInfo[.ledgerMetadataOnly] = false
        let data = try encoder.encode(ledger)
        guard data.count <= bundleCapacity else { throw YubaiError.invalid("账本超过安全容量，本次修改未保存。") }
        return data
    }
    static func validateAttachments(_ ledger: Ledger, requirePayloads: Bool) throws {
        for attachment in ledger.attachments {
            guard (0...capacity).contains(attachment.byteCount) else { throw YubaiError.invalid("单个附件超过 250 MB。") }
            if requirePayloads, attachment.checksum != nil || attachment.data.count != attachment.byteCount { throw YubaiError.invalid("附件尚未完整读取，请稍后再试。") }
        }
    }
    public static func decode(_ data: Data) throws -> Ledger {
        guard data.count <= bundleCapacity else { throw YubaiError.invalid("账本超过安全读取大小，请分开处理附件。") }
        do {
            var ledger = try JSONDecoder().decode(Ledger.self, from: data); try ledger.validate()
            try validateAttachments(ledger, requirePayloads: false)
            if try JSONDecoder().decode(LedgerHeader.self, from: data).schema < 4 { ledger.preMigrationData = data }
            return ledger
        }
        catch let error as YubaiError { throw error }
        catch { throw YubaiError.invalid("账本格式损坏或版本不兼容，原文件已保留。请从备份恢复。") }
    }
}
public struct Recovery: Identifiable, Sendable {
    public var id: URL { url }; public var url: URL; public var date: Date; public var name: String
}
public enum LedgerSyncError: Error { case changed }

public struct LedgerRepository: Sendable {
    // Bound the whole local Recovery directory, including shared payloads.
    // The newest recovery/readable version and payloads needed by the live ledger win over the budget.
    static let historyByteLimit: Int64 = 10 * 1024 * 1024
    private final class State: @unchecked Sendable {
        let lock = NSRecursiveLock(); var digest: String?
        let discoveryLock = NSLock(); var discoveredFiles: Set<URL>?
        var payloadChecksums: [URL: String] = [:]
    }
    private let state: State
    private let localState: State
    private let historyLock: NSRecursiveLock
    public let directory: URL
    public let localDirectory: URL
    public let isUbiquitous: Bool
    public var file: URL { directory.appendingPathComponent("ledger.json") }
    private var history: URL { localDirectory.appendingPathComponent("Recovery", isDirectory: true) }
    public init(directory: URL) {
        self.directory = directory; localDirectory = directory; isUbiquitous = false
        let state = State(); self.state = state; localState = state; historyLock = NSRecursiveLock()
    }
    private init(directory: URL, localDirectory: URL, isUbiquitous: Bool, historyLock: NSRecursiveLock, localState: State) {
        self.directory = directory; self.localDirectory = localDirectory; self.isUbiquitous = isUbiquitous
        state = State(); self.localState = localState; self.historyLock = historyLock
    }
    // A relocated repository shares LOCAL history and its lock, never the last-read digest.
    public func relocated(to directory: URL, isUbiquitous: Bool = false) -> Self {
        Self(directory: directory, localDirectory: localDirectory, isUbiquitous: isUbiquitous, historyLock: historyLock, localState: localState)
    }
    private var pendingSyncFile: URL { localDirectory.appendingPathComponent(".icloud-pending") }
    public var hasPendingSync: Bool { FileManager.default.fileExists(atPath: pendingSyncFile.path) }
    public func markPendingSync(_ pending: Bool) throws {
        state.lock.lock(); defer { state.lock.unlock() }
        if pending { try prepare(localDirectory); try writePrivate(Data("pending".utf8), to: pendingSyncFile) }
        else if hasPendingSync { try FileManager.default.removeItem(at: pendingSyncFile) }
    }
    public func updateDiscoveredFiles(_ urls: [URL]) {
        state.discoveryLock.lock(); defer { state.discoveryLock.unlock() }
        state.discoveredFiles = Set(urls.map { $0.standardizedFileURL })
    }
    private func discovered(_ url: URL) -> Bool {
        state.discoveryLock.lock(); defer { state.discoveryLock.unlock() }
        return state.discoveredFiles?.contains(url.standardizedFileURL) == true
    }
    func containsFile(_ url: URL) -> Bool {
        #if os(Linux)
        return FileManager.default.fileExists(atPath: url.path) || discovered(url)
        #else
        FileManager.default.fileExists(atPath: url.path) || discovered(url) || (try? url.resourceValues(forKeys: [.isUbiquitousItemKey]).isUbiquitousItem) == true
        #endif
    }
    private func prepare(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }
    private func writePrivate(_ data: Data, to destination: URL) throws {
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(".writing-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try storageWrite { try data.write(to: temporary, options: .atomic) }; try protect(temporary)
        try install(temporary, at: destination)
    }
    private func install(_ temporary: URL, at destination: URL) throws {
        #if os(Linux)
        let result = Glibc.rename(temporary.path, destination.path)
        #else
        let result = Darwin.rename(temporary.path, destination.path)
        #endif
        guard result == 0 else { throw writeError(POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)) }
    }
    private func storageWrite<T>(_ body: () throws -> T) throws -> T {
        do { return try body() }
        catch { throw writeError(error) }
    }
    private func writeError(_ error: Error) -> Error {
        let value = error as NSError
        let underlying = value.userInfo[NSUnderlyingErrorKey] as? NSError
        if value.code == NSFileWriteOutOfSpaceError && value.domain == NSCocoaErrorDomain ||
           [value, underlying].compactMap({ $0 }).contains(where: { $0.domain == NSPOSIXErrorDomain && $0.code == Int(ENOSPC) }) {
            return YubaiError.invalid("手机空间不足，本次修改未保存。")
        }
        return error
    }
    private func protect(_ url: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
        #endif
    }
    // Call cloud I/O on a worker. Each immutable attachment is coordinated separately.
    func access<T>(writing: Bool, _ body: (URL) throws -> T) throws -> T {
        state.lock.lock(); defer { state.lock.unlock() }
        guard isUbiquitous else { return try body(directory) }
        #if os(Linux)
        throw YubaiError.invalid("Linux 不支持 iCloud 账本，请使用本机目录。")
        #else
        state.discoveryLock.lock(); let ready = state.discoveredFiles != nil; state.discoveryLock.unlock()
        guard ready else { throw YubaiError.invalid("正在从 iCloud 读取文件列表，请稍后重试。") }
        if writing || !FileManager.default.fileExists(atPath: directory.path) { try prepare(directory) }
        let ledgerURL = directory.appendingPathComponent("ledger.json")
        let hasFile = containsFile(ledgerURL)
        if hasFile { try downloaded(ledgerURL) }
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?; var result: Result<T, Error>?
        if writing || !hasFile {
            coordinator.coordinate(writingItemAt: ledgerURL, options: hasFile ? .forReplacing : [], error: &coordinationError) { url in result = Result { try body(url.deletingLastPathComponent()) } }
        } else {
            coordinator.coordinate(readingItemAt: ledgerURL, options: [], error: &coordinationError) { url in result = Result { try body(url.deletingLastPathComponent()) } }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw YubaiError.invalid("无法协调账本文件，请稍后重试。") }
        return try result.get()
        #endif
    }
    private func downloaded(_ url: URL) throws {
        guard isUbiquitous else { return }
        #if os(Linux)
        throw YubaiError.invalid("Linux 不支持 iCloud 账本，请使用本机目录。")
        #else
        let values = try? url.resourceValues(forKeys: [.isUbiquitousItemKey])
        guard values?.isUbiquitousItem == true || discovered(url) else { return }
        try FileManager.default.startDownloadingUbiquitousItem(at: url)
        let deadline = Date().addingTimeInterval(30)
        var freshURL = url
        while true {
            freshURL.removeAllCachedResourceValues()
            if (try? freshURL.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]).ubiquitousItemDownloadingStatus) == .current { return }
            guard Date() < deadline else { throw YubaiError.invalid("iCloud 还未读取完成，请联网后重试。") }
            Thread.sleep(forTimeInterval: 0.1)
        }
        #endif
    }
    private func payloadAccess<T>(_ url: URL, writing: Bool, deleting: Bool = false, _ body: (URL) throws -> T) throws -> T {
        guard isUbiquitous else { return try body(url) }
        #if os(Linux)
        throw YubaiError.invalid("Linux 不支持 iCloud 账本，请使用本机目录。")
        #else
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var error: NSError?; var result: Result<T, Error>?
        if writing { coordinator.coordinate(writingItemAt: url, options: deleting ? .forDeleting : [], error: &error) { coordinated in result = Result { try body(coordinated) } } }
        else { coordinator.coordinate(readingItemAt: url, options: [], error: &error) { coordinated in result = Result { try body(coordinated) } } }
        if let error { throw error }
        guard let result else { throw YubaiError.invalid("无法协调附件文件。") }
        return try result.get()
        #endif
    }
    private func attachments(at root: URL) -> URL { root.appendingPathComponent("Attachments", isDirectory: true) }
    func read(_ url: URL, attachmentDirectory: URL) throws -> Ledger {
        try downloaded(url)
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= LedgerCodec.capacity else { throw YubaiError.invalid("账本文件超过 250 MB，原文件已保留。") }
        return located(try LedgerCodec.decode(Data(contentsOf: url)), at: attachmentDirectory)
    }
    private func located(_ ledger: Ledger, at root: URL) -> Ledger {
        var ledger = ledger
        for i in ledger.attachments.indices where ledger.attachments[i].checksum != nil {
            ledger.attachments[i].unload(at: root.appendingPathComponent(ledger.attachments[i].id.uuidString), repository: self)
        }
        return ledger
    }
    public func attachmentData(_ id: UUID) throws -> Data {
        try access(writing: false) { root in
            let ledger = try read(root.appendingPathComponent("ledger.json"), attachmentDirectory: attachments(at: root))
            guard let item = ledger.attachments.first(where: { $0.id == id }) else { throw YubaiError.invalid("附件不存在。") }
            return try Self.attachmentData(item)
        }
    }
    static func attachmentData(_ item: Attachment) throws -> Data {
        guard let checksum = item.checksum else { return item.data }
        guard let url = item.payloadURL, let repository = item.payloadRepository else { throw YubaiError.invalid("附件尚未完整读取，请稍后再试。") }
        return try repository.withPayload(url, writing: false) { coordinated in
            guard try coordinated.resourceValues(forKeys: [.fileSizeKey]).fileSize == item.byteCount else { throw YubaiError.invalid("附件缺失或大小不符，账本未被覆盖。") }
            let bytes = try Data(contentsOf: coordinated)
            guard LedgerCodec.checksum(bytes) == checksum else { throw YubaiError.invalid("附件校验失败，账本未被覆盖。") }
            return bytes
        }
    }
    private func withPayload<T>(_ url: URL, writing: Bool, _ body: (URL) throws -> T) throws -> T {
        // Immutable payload reads must not take another repository's ledger lock.
        let cloud = isUbiquitous && url.deletingLastPathComponent().standardizedFileURL == attachments(at: directory).standardizedFileURL
        if cloud { try downloaded(url); return try payloadAccess(url, writing: writing, body) }
        if !FileManager.default.fileExists(atPath: url.path), UUID(uuidString: url.lastPathComponent) != nil {
            let retained = recoveryPayloads.appendingPathComponent(url.lastPathComponent)
            if FileManager.default.fileExists(atPath: retained.path) { return try body(retained) }
        }
        return try body(url)
    }
    private func fileChecksum(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        var hash = SHA256()
        while let bytes = try handle.read(upToCount: 1024 * 1024), !bytes.isEmpty { hash.update(data: bytes) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
    private func checkSpace(_ count: Int, at root: URL) throws {
        #if !os(Linux)
        if let available = try? root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage,
           available < Int64(count) { throw YubaiError.invalid("手机空间不足，本次修改未保存。") }
        #endif
    }
    private func writeAttachments(_ ledger: Ledger, at root: URL, known: [UUID: String] = [:], repairing: Bool = false) throws {
        guard !ledger.attachments.isEmpty else { return }
        try prepare(root)
        let cloud = isUbiquitous && root.standardizedFileURL == attachments(at: directory).standardizedFileURL
        let newBytes = ledger.attachments.filter { !(cloud ? containsFile(root.appendingPathComponent($0.id.uuidString)) : FileManager.default.fileExists(atPath: root.appendingPathComponent($0.id.uuidString).path)) }.reduce(0) { $0 + $1.byteCount }
        try checkSpace(newBytes, at: root)
        for item in ledger.attachments {
            let destination = root.appendingPathComponent(item.id.uuidString)
            if cloud, containsFile(destination) { try downloaded(destination) }
            let write: (URL) throws -> Void = { url in
                let checksum = item.payloadChecksum
                if FileManager.default.fileExists(atPath: url.path) {
                    let sameSize = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize == item.byteCount
                    let existing = repairing && sameSize ? try self.fileChecksum(url) : known[item.id] ?? self.state.payloadChecksums[url]
                    if sameSize, try (existing ?? self.fileChecksum(url)) == checksum { self.state.payloadChecksums[url] = checksum; return }
                    guard repairing else { throw YubaiError.invalid("同一附件标识的内容不同，原文件已保留。") }
                }
                if repairing { try self.checkSpace(item.byteCount, at: root) }
                if let source = item.payloadURL, let repository = item.payloadRepository {
                    try repository.withPayload(source, writing: false) { source in
                        guard try source.resourceValues(forKeys: [.fileSizeKey]).fileSize == item.byteCount else { throw YubaiError.invalid("附件缺失或大小不符，账本未被覆盖。") }
                        let temporary = root.appendingPathComponent(".writing-\(UUID().uuidString)")
                        defer { try? FileManager.default.removeItem(at: temporary) }
                        try self.storageWrite { try FileManager.default.copyItem(at: source, to: temporary) }; try self.protect(temporary)
                        if repairing, try self.fileChecksum(temporary) != checksum { throw YubaiError.invalid("附件校验失败，账本未被覆盖。") }
                        try self.install(temporary, at: url)
                    }
                } else {
                    guard item.data.count == item.byteCount else { throw YubaiError.invalid("附件尚未完整读取，请稍后再试。") }
                    try self.writePrivate(item.data, to: url)
                }
                self.state.payloadChecksums[url] = checksum
            }
            if cloud { try payloadAccess(destination, writing: true, write) }
            else { try write(destination) }
        }
    }
    private func recoveryURL(reason: String) throws -> URL {
        try prepare(history)
        #if !os(Linux)
        var excluded = history; var values = URLResourceValues(); values.isExcludedFromBackup = true
        try excluded.setResourceValues(values)
        #endif
        let latest = try recoveries().first.map { Int64(($0.date.timeIntervalSince1970 * 1000).rounded()) } ?? 0
        let stamp = max(Int64(Date().timeIntervalSince1970 * 1000), latest + 1)
        let safeReason = reason.replacingOccurrences(of: "/", with: "-").prefix(40)
        return history.appendingPathComponent("\(stamp)-\(UUID().uuidString.prefix(8))-\(safeReason).json.gz")
    }
    private var recoveryPayloads: URL { history.appendingPathComponent("Payloads", isDirectory: true) }
    private func recoveryAttachments(_ url: URL) -> URL { url.deletingPathExtension().appendingPathExtension("attachments") }
    func recoveryBytes(_ url: URL) throws -> Data {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= LedgerCodec.capacity + LedgerCodec.capacity / 1000 + 1024 else { throw YubaiError.invalid("恢复文件超过安全容量。") }
        let bytes = try Data(contentsOf: url)
        return url.pathExtension == "gz" ? try RecoveryCompression.decode(bytes) : bytes
    }
    private func preserve(bytes: Data, ledger: Ledger?, reason: String) throws {
        historyLock.lock(); defer { historyLock.unlock() }
        let destination = try recoveryURL(reason: reason)
        if let ledger { try writeAttachments(ledger, at: recoveryPayloads) }
        let metadata = try ledger.map { ledger in
            ledger.attachments.contains(where: { $0.checksum == nil }) ? try LedgerCodec.encodeMetadata(ledger) : bytes
        } ?? bytes
        let compressed = try RecoveryCompression.encode(metadata)
        try checkSpace(compressed.count, at: history)
        try writePrivate(compressed, to: destination)
    }
    private func preserveCurrent(at root: URL, reason: String, verify: Bool = true) throws {
        let url = root.appendingPathComponent("ledger.json")
        if verify, try (url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) > LedgerCodec.capacity { throw YubaiError.invalid("账本文件超过 250 MB，原文件已保留。") }
        let bytes = try Data(contentsOf: url)
        let decoded: Ledger?
        if verify { decoded = try LedgerCodec.decode(bytes) }
        else { decoded = try? LedgerCodec.decode(bytes) }
        let ledger = decoded.map { located($0, at: attachments(at: root)) }
        // Embedded legacy payloads are split too; undecodable originals remain verbatim inside gzip.
        let label = decoded?.preMigrationData != nil ? "升级前版本" : reason
        if verify { try preserve(bytes: bytes, ledger: ledger, reason: label) }
        else {
            do { try preserve(bytes: bytes, ledger: ledger, reason: label) }
            catch { try preserve(bytes: bytes, ledger: nil, reason: label) }
        }
    }
    public func preserveRecovery(_ ledger: Ledger, reason: String) throws {
        state.lock.lock(); defer { state.lock.unlock() }
        historyLock.lock(); defer { historyLock.unlock() }
        try preserve(bytes: LedgerCodec.encodeMetadata(ledger), ledger: ledger, reason: reason); pruneHistory()
    }
    private func pruneHistory() {
        historyLock.lock(); defer { historyLock.unlock() }
        guard let versions = try? recoveries() else { return }
        // Decode references once, even when the byte budget evicts several versions.
        var references: [URL: Set<UUID>] = [:]
        for version in versions {
            if let ledger = try? LedgerCodec.decode(recoveryBytes(version.url)) {
                references[version.url] = Set(ledger.attachments.map(\.id))
            }
        }
        let newestReadable = versions.first { references[$0.url] != nil }?.url
        var currentIDs = Set<UUID>(), currentReadable = true
        for current in Set([file, localDirectory.appendingPathComponent("ledger.json")]) where containsFile(current) {
            if let ledger = try? LedgerCodec.decode(Data(contentsOf: current)) { currentIDs.formUnion(ledger.attachments.map(\.id)) }
            else { currentReadable = false }
        }
        let payloads = (try? FileManager.default.contentsOfDirectory(at: recoveryPayloads, includingPropertiesForKeys: nil)) ?? []
        var remaining = versions
        func collectPayloads() {
            // Never collect payloads if any retained or live metadata cannot be read.
            guard currentReadable, remaining.allSatisfy({ references[$0.url] != nil }) else { return }
            let used = remaining.reduce(into: currentIDs) { $0.formUnion(references[$1.url]!) }
            for url in payloads where UUID(uuidString: url.lastPathComponent).map({ !used.contains($0) }) == true {
                try? FileManager.default.removeItem(at: url); state.payloadChecksums.removeValue(forKey: url)
            }
        }
        collectPayloads()
        var byteCount = (try? bytesIn(history)) ?? Int64.max
        // Both limits delete oldest first. There is deliberately no age-based expiry.
        for recovery in versions.dropFirst().reversed() {
            guard remaining.count > 20 || byteCount > Self.historyByteLimit else { break }
            // A damaged newest file must not evict the last readable fallback.
            if recovery.url == newestReadable { continue }
            do { try FileManager.default.removeItem(at: recovery.url) }
            catch { continue }
            try? FileManager.default.removeItem(at: recoveryAttachments(recovery.url))
            remaining.removeAll { $0.url == recovery.url }
            collectPayloads()
            byteCount = (try? bytesIn(history)) ?? Int64.max
        }
    }
    public func exists() throws -> Bool {
        try access(writing: false) { root in
            let url = root.appendingPathComponent("ledger.json")
            return containsFile(url)
        }
    }
    public func load() throws -> Ledger {
        state.lock.lock(); defer { state.lock.unlock() }
        var needsMigration = false
        var ledger = try access(writing: false) { root -> Ledger in
            let url = root.appendingPathComponent("ledger.json")
            guard containsFile(url) else { state.digest = nil; return Ledger() }
            #if !os(Linux)
            guard !isUbiquitous || (NSFileVersion.unresolvedConflictVersionsOfItem(at: url) ?? []).isEmpty else { throw LedgerSyncError.changed }
            #endif
            let ledger = try read(url, attachmentDirectory: attachments(at: root))
            let bytes = try Data(contentsOf: url)
            needsMigration = ledger.preMigrationData != nil || ledger.attachments.contains(where: { $0.checksum == nil })
            state.digest = LedgerCodec.checksum(bytes)
            return ledger
        }
        if needsMigration {
            // Recheck after acquiring write coordination; never rewrite a newly arriving version.
            try access(writing: true) { root in
                try checkUnchanged(at: root)
                try preserveCurrent(at: root, reason: "附件拆分前")
                ledger = try put(ledger, at: root); pruneHistory()
            }
        }
        // Existing installations also receive the budget without needing a new history write.
        if !needsMigration { pruneHistory() }
        return ledger
    }
    private func cleaned(_ ledger: Ledger) -> Ledger {
        var ledger = ledger
        let batchReferences = ledger.imports.flatMap { batch in
            (batch.attachmentID.map { [$0] } ?? []) + (batch.undo?.entries.compactMap(\.attachmentID) ?? [])
        }
        let referenced = Set(ledger.entries.compactMap(\.attachmentID) + batchReferences)
        // Pending changes refer to existing entry IDs; all entries, including deleted ones, are retained above.
        ledger.attachments.removeAll { !referenced.contains($0.id) }
        return ledger
    }
    private func put(_ ledger: Ledger, at root: URL, repairing: Bool = false) throws -> Ledger {
        var shared = cleaned(ledger)
        if isUbiquitous { shared.preferences.lockEnabled = false }
        let previous = (try? LedgerCodec.decode(Data(contentsOf: root.appendingPathComponent("ledger.json"))))?.attachments ?? []
        let known = Dictionary(uniqueKeysWithValues: previous.map { ($0.id, $0.payloadChecksum) })
        let bytes = try LedgerCodec.encodeMetadata(shared)
        try prepare(root); try checkSpace(bytes.count, at: root)
        try writeAttachments(shared, at: attachments(at: root), known: known, repairing: repairing)
        try writePrivate(bytes, to: root.appendingPathComponent("ledger.json")); state.digest = LedgerCodec.checksum(bytes)
        let used = Set(shared.attachments.map(\.id))
        var files = (try? FileManager.default.contentsOfDirectory(at: attachments(at: root), includingPropertiesForKeys: nil)) ?? []
        state.discoveryLock.lock(); files += Array(state.discoveredFiles ?? []); state.discoveryLock.unlock()
        for url in Set(files) where url.deletingLastPathComponent().standardizedFileURL == attachments(at: root).standardizedFileURL && UUID(uuidString: url.lastPathComponent).map({ !used.contains($0) }) == true {
            try? payloadAccess(url, writing: true, deleting: true) { try FileManager.default.removeItem(at: $0) }
            state.payloadChecksums.removeValue(forKey: url)
        }
        for i in shared.attachments.indices { shared.attachments[i].unload(at: attachments(at: root).appendingPathComponent(shared.attachments[i].id.uuidString), repository: self) }
        shared.preMigrationData = nil
        return shared
    }
    func checkUnchanged(at root: URL) throws {
        let url = root.appendingPathComponent("ledger.json")
        let digest = FileManager.default.fileExists(atPath: url.path) ? try LedgerCodec.checksum(Data(contentsOf: url)) : nil
        guard digest == state.digest else { throw LedgerSyncError.changed }
        #if !os(Linux)
        if isUbiquitous, !(NSFileVersion.unresolvedConflictVersionsOfItem(at: url) ?? []).isEmpty { throw LedgerSyncError.changed }
        #endif
    }
    /// Checkpoints may skip history only after the run's pre-change snapshot has been preserved.
    /// They still use the ordinary validation, atomic write and stale-file protection.
    @discardableResult public func save(_ ledger: Ledger, reason: String = "修改", requiringUnchanged: Bool = false, preservingRecovery: Bool = true) throws -> Ledger {
        _ = try LedgerCodec.encodeMetadata(ledger)
        return try access(writing: true) { root in
            if isUbiquitous || requiringUnchanged || !preservingRecovery { try checkUnchanged(at: root) }
            try prepare(root)
            if preservingRecovery, FileManager.default.fileExists(atPath: root.appendingPathComponent("ledger.json").path) { try preserveCurrent(at: root, reason: reason) }
            else if let bytes = ledger.preMigrationData { try preserve(bytes: bytes, ledger: LedgerCodec.decode(bytes), reason: "升级前版本") }
            let saved = try put(ledger, at: root)
            if preservingRecovery { pruneHistory() }
            return saved
        }
    }
    public func recoveries() throws -> [Recovery] {
        historyLock.lock(); defer { historyLock.unlock() }
        guard FileManager.default.fileExists(atPath: history.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: history, includingPropertiesForKeys: [.contentModificationDateKey]).filter { $0.pathExtension == "json" || $0.lastPathComponent.hasSuffix(".json.gz") }.map { url in
            let name = (url.pathExtension == "gz" ? url.deletingPathExtension() : url).deletingPathExtension().lastPathComponent
            let stamp = name.split(separator: "-").first.flatMap { Int64($0) }.flatMap { (0..<10_000_000_000_000).contains($0) ? $0 : nil }
            let date = stamp.map { Date(timeIntervalSince1970: Double($0) / 1000) } ?? (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return Recovery(url: url, date: date, name: name)
        }.sorted { $0.date > $1.date }
    }

    /// App storage is measured from the local mirror. Recovery includes shared payloads
    /// exactly once; file lengths are read without loading attachment contents.
    public func storageUsage() throws -> StorageUsage {
        do {
            return try access(writing: false) { root in
                historyLock.lock(); defer { historyLock.unlock() }
                var usage = StorageUsage()
                let versions = try recoveries()
                usage.recoveryCount = versions.count; usage.oldestRecovery = versions.map(\.date).min()
                usage.attachmentBytes = try bytesIn(attachments(at: root))
                usage.recoveryBytes = try bytesIn(history)
                if FileManager.default.fileExists(atPath: root.path) {
                    for url in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
                    where url.lastPathComponent != "Attachments" && url.lastPathComponent != "Recovery" {
                        usage.ledgerBytes += try bytesIn(url)
                    }
                }
                return usage
            }
        } catch { throw YubaiError.invalid("无法读取存储空间，请稍后重试。") }
    }
    private func bytesIn(_ url: URL) throws -> Int64 {
        guard FileManager.default.fileExists(atPath: url.path) else { return 0 }
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isSymbolicLink != true else { return 0 }
        if values.isDirectory != true { return Int64(values.fileSize ?? 0) }
        return try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil).reduce(0) { try $0 + bytesIn($1) }
    }

    @discardableResult public func deleteOldScreenshots(from ledger: Ledger, months: Int, now: Date = Date(), calendar: Calendar = .current) throws -> Ledger {
        do {
            return try access(writing: true) { root in
                historyLock.lock(); defer { historyLock.unlock() }
                try checkUnchanged(at: root)
                var next = ledger
                let removed = StorageAttachments.removeOldScreenshots(from: &next, months: months, now: now, calendar: calendar)
                guard !removed.isEmpty else { return ledger }
                next.updatedAt = Date()
                let payloads = removed.map { attachments(at: root).appendingPathComponent($0.id.uuidString) }
                return try storageTransaction(paths: [root.appendingPathComponent("ledger.json"), history] + payloads) {
                    // The ordinary save preserves the previous ledger and its shared payloads.
                    let saved = try save(next, reason: "删除旧截图", requiringUnchanged: true)
                    // Ordinary garbage collection is best effort. This user action must report
                    // an unlink failure and roll back rather than claim the screenshots are gone.
                    for url in payloads where containsFile(url) {
                        try payloadAccess(url, writing: true, deleting: true) { try FileManager.default.removeItem(at: $0) }
                    }
                    return saved
                }
            }
        } catch LedgerSyncError.changed { throw YubaiError.invalid("账本已有更新，请重新打开存储空间后再试。") }
        catch let error as YubaiError { throw error }
        catch { throw YubaiError.invalid("删除旧截图失败，原账本已保留。请稍后重试。") }
    }

    public func clearRecoveryHistory() throws {
        state.lock.lock(); defer { state.lock.unlock() }
        historyLock.lock(); defer { historyLock.unlock() }
        do {
            try storageTransaction(paths: [history]) {
                if FileManager.default.fileExists(atPath: history.path) { try FileManager.default.removeItem(at: history) }
            }
            state.payloadChecksums = state.payloadChecksums.filter { !$0.key.path.hasPrefix(history.path + "/") }
        } catch let error as YubaiError { throw error }
        catch { throw YubaiError.invalid("清除恢复历史失败，原数据已保留。请稍后重试。") }
    }

    /// Always targets Application Support, even when invoked on a relocated cloud repository.
    /// The caller switches its location preference to local only after this succeeds.
    public func eraseAllLocalData() throws {
        localState.lock.lock(); defer { localState.lock.unlock() }
        state.lock.lock(); defer { state.lock.unlock() }
        historyLock.lock(); defer { historyLock.unlock() }
        do {
            let manager = FileManager.default
            if manager.fileExists(atPath: localDirectory.path) {
                let paths = try manager.contentsOfDirectory(at: localDirectory, includingPropertiesForKeys: nil)
                try storageTransaction(paths: paths) { for url in paths { try manager.removeItem(at: url) } }
            }
            localState.digest = nil; localState.payloadChecksums.removeAll()
            if directory == localDirectory { state.digest = nil; state.payloadChecksums.removeAll() }
        } catch let error as YubaiError { throw error }
        catch { throw YubaiError.invalid("抹掉失败，本机数据已保留。请稍后重试。") }
    }

    /// Private rollback snapshot uses hard links on the same volume, with copy fallback.
    /// Immutable payloads require no second in-memory or on-disk copy. A failed delete
    /// restores metadata, history and payloads together, including an originally absent path.
    private func storageTransaction<T>(paths: [URL], _ body: () throws -> T) throws -> T {
        guard !paths.isEmpty else { return try body() }
        let manager = FileManager.default
        let staging = localDirectory.deletingLastPathComponent().appendingPathComponent(".yubai-storage-\(UUID().uuidString)", isDirectory: true)
        try prepare(staging)
        var snapshots: [(URL, URL, Bool)] = []
        let digest = state.digest
        var keepSnapshot = false
        defer { if !keepSnapshot { try? manager.removeItem(at: staging) } }
        for (index, original) in paths.enumerated() {
            let snapshot = staging.appendingPathComponent(String(index))
            let exists = containsFile(original)
            if exists { try snapshotStorage(original, to: snapshot) }
            snapshots.append((original, snapshot, exists))
        }
        do { return try body() }
        catch {
            do {
                for (original, snapshot, existed) in snapshots {
                    let restore: (URL) throws -> Void = { destination in
                        if manager.fileExists(atPath: destination.path) { try manager.removeItem(at: destination) }
                        if existed { try manager.moveItem(at: snapshot, to: destination) }
                    }
                    if isCloudPayload(original) { try payloadAccess(original, writing: true, restore) }
                    else { try restore(original) }
                }
                state.digest = digest; state.payloadChecksums.removeAll()
            } catch {
                keepSnapshot = true
                throw YubaiError.invalid("无法完成清理，原数据副本保留在 \(staging.path)。")
            }
            throw error
        }
    }
    private func isCloudPayload(_ url: URL) -> Bool {
        isUbiquitous && url.deletingLastPathComponent().standardizedFileURL == attachments(at: directory).standardizedFileURL
    }
    private func snapshotStorage(_ original: URL, to snapshot: URL) throws {
        if isCloudPayload(original) {
            try downloaded(original)
            try payloadAccess(original, writing: false) { try cloneStorage($0, to: snapshot) }
        } else { try cloneStorage(original, to: snapshot) }
    }
    private func cloneStorage(_ original: URL, to snapshot: URL) throws {
        let manager = FileManager.default
        let values = try original.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        if values.isSymbolicLink == true { try manager.copyItem(at: original, to: snapshot) }
        else if values.isDirectory == true {
            try prepare(snapshot)
            for child in try manager.contentsOfDirectory(at: original, includingPropertiesForKeys: nil) {
                try cloneStorage(child, to: snapshot.appendingPathComponent(child.lastPathComponent))
            }
        } else {
            do { try manager.linkItem(at: original, to: snapshot) }
            catch { try manager.copyItem(at: original, to: snapshot); try protect(snapshot) }
        }
    }
    public func readRecovery(_ recovery: Recovery) throws -> Ledger {
        state.lock.lock(); defer { state.lock.unlock() }
        historyLock.lock(); defer { historyLock.unlock() }
        let recoveryDirectory = recovery.url.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL
        guard recoveryDirectory == history.resolvingSymlinksInPath().standardizedFileURL else { throw YubaiError.invalid("恢复文件不属于当前账本。") }
        var ledger = try LedgerCodec.decode(recoveryBytes(recovery.url))
        if ledger.attachments.contains(where: { $0.checksum == nil }) {
            try writeAttachments(ledger, at: recoveryPayloads)
            for i in ledger.attachments.indices where ledger.attachments[i].checksum == nil {
                ledger.attachments[i].unload(at: recoveryPayloads.appendingPathComponent(ledger.attachments[i].id.uuidString), repository: self)
            }
        }
        for i in ledger.attachments.indices where ledger.attachments[i].checksum != nil {
            let id = ledger.attachments[i].id.uuidString
            let shared = recoveryPayloads.appendingPathComponent(id)
            let legacy = recoveryAttachments(recovery.url).appendingPathComponent(id)
            ledger.attachments[i].unload(at: FileManager.default.fileExists(atPath: shared.path) ? shared : legacy, repository: self)
            // Verify with bounded memory, keeping the returned ledger metadata-only.
            let item = ledger.attachments[i]; let url = item.payloadURL!
            guard try url.resourceValues(forKeys: [.fileSizeKey]).fileSize == item.byteCount,
                  try fileChecksum(url) == item.checksum else { throw YubaiError.invalid("附件校验失败，恢复版本未被采用。") }
        }
        return ledger
    }
    public func recover(_ recovery: Recovery) throws -> Ledger {
        state.lock.lock(); defer { state.lock.unlock() }
        let restored = try readRecovery(recovery)
        return try restoreBackup(restored)
    }
    @discardableResult public func restoreBackup(_ restored: Ledger) throws -> Ledger {
        _ = try LedgerCodec.encodeMetadata(restored)
        return try access(writing: true) { root in
            if isUbiquitous { try checkUnchanged(at: root) }
            try prepare(root)
            if FileManager.default.fileExists(atPath: root.appendingPathComponent("ledger.json").path) { try preserveCurrent(at: root, reason: "恢复前", verify: false) }
            if let bytes = restored.preMigrationData { try preserve(bytes: bytes, ledger: LedgerCodec.decode(bytes), reason: "升级前版本") }
            let saved = try put(restored, at: root, repairing: true); pruneHistory(); return saved
        }
    }
    public func resolve(_ versions: [LedgerVersion], choosing id: String, source: LedgerVersionSource, reason: String = "同步冲突时的另一版本", prepare: (Ledger) -> Ledger = { $0 }) throws -> Ledger {
        guard let chosen = versions.first(where: { $0.id == id }) else { throw YubaiError.invalid("请选择一份账本。") }
        let selected = prepare(chosen.ledger)
        _ = try LedgerCodec.encodeMetadata(selected)
        return try access(writing: true) { root in
            try source.validate()
            for other in versions where other.id != id { try preserveRecovery(other.ledger, reason: reason) }
            let saved = try put(selected, at: root)
            try source.markResolved(); pruneHistory(); return saved
        }
    }
}

public enum Backup {
    private struct Envelope: Codable {
        var format = "yubai-backup"; var version = 1; var createdAt = Date()
        var encrypted: Bool; var salt: Data?; var rounds: Int?; var payload: Data; var checksum: String
    }
    private static func key(password: String, salt: Data, rounds: Int) throws -> SymmetricKey {
        guard (100_000...1_000_000).contains(rounds), salt.count == 16 else { throw YubaiError.invalid("备份加密参数无效。") }
        #if os(Linux)
        // 旧备份允许低于 210,000 轮；沿用上方校验范围，不改变 v1 格式。
        return try KDF.Insecure.PBKDF2.deriveKey(from: Data(password.utf8), salt: salt, using: .sha256,
                                              outputByteCount: 32, unsafeUncheckedRounds: rounds)
        #else
        let passwordData = Array(password.utf8); var output = [UInt8](repeating: 0, count: 32)
        let result = passwordData.withUnsafeBytes { pass in salt.withUnsafeBytes { s in
            yubai_derive_key(pass.bindMemory(to: CChar.self).baseAddress, passwordData.count, s.bindMemory(to: UInt8.self).baseAddress, salt.count, UInt32(rounds), &output)
        } }
        guard result == 0 else { throw YubaiError.invalid("无法创建备份加密密钥。") }
        return SymmetricKey(data: output)
        #endif
    }
    public static func export(_ ledger: Ledger, password: String = "") throws -> Data {
        var complete = ledger
        for i in complete.attachments.indices { complete.attachments[i].data = try LedgerRepository.attachmentData(ledger.attachments[i]) }
        let plain = try LedgerCodec.encode(complete)
        let checksum = SHA256.hash(data: plain).map { String(format: "%02x", $0) }.joined()
        var envelope: Envelope
        if password.isEmpty { envelope = Envelope(encrypted: false, payload: plain, checksum: checksum) }
        else {
            guard password.count >= 8 else { throw YubaiError.invalid("备份密码至少 8 个字符。") }
            let salt = Data((0..<16).map { _ in UInt8.random(in: 0...255) }); let rounds = 210_000
            let sealed = try AES.GCM.seal(plain, using: key(password: password, salt: salt, rounds: rounds), authenticating: Data("yubai-backup-v1".utf8))
            envelope = Envelope(encrypted: true, salt: salt, rounds: rounds, payload: sealed.combined!, checksum: checksum)
        }
        return try JSONEncoder().encode(envelope)
    }
    public static func restore(_ data: Data, password: String = "") throws -> Ledger {
        guard data.count <= LedgerCodec.backupCapacity else { throw YubaiError.invalid("备份文件过大。") }
        let envelope: Envelope
        do { envelope = try JSONDecoder().decode(Envelope.self, from: data) } catch { throw YubaiError.invalid("这不是有效的余白备份。") }
        guard envelope.format == "yubai-backup", envelope.version == 1 else { throw YubaiError.invalid("请用匹配版本的余白恢复此备份。") }
        let plain: Data
        if envelope.encrypted {
            guard !password.isEmpty else { throw YubaiError.invalid("这个备份已加密，请填写创建备份时的密码。") }
            guard let salt = envelope.salt, let rounds = envelope.rounds else { throw YubaiError.invalid("备份缺少加密参数。") }
            do { plain = try AES.GCM.open(AES.GCM.SealedBox(combined: envelope.payload), using: key(password: password, salt: salt, rounds: rounds), authenticating: Data("yubai-backup-v1".utf8)) }
            catch { throw YubaiError.invalid("密码不正确或备份已损坏，当前账本未变动。") }
        } else { plain = envelope.payload }
        guard SHA256.hash(data: plain).map({ String(format: "%02x", $0) }).joined() == envelope.checksum else { throw YubaiError.invalid("备份校验失败，当前账本未变动。") }
        let ledger = try LedgerCodec.decode(plain)
        try LedgerCodec.validateAttachments(ledger, requirePayloads: true)
        _ = try LedgerCodec.encodeMetadata(ledger)
        return ledger
    }
}
