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
            if try JSONDecoder().decode(LedgerHeader.self, from: data).schema == 1 { ledger.preMigrationData = data }
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
    private final class State: @unchecked Sendable {
        let lock = NSRecursiveLock(); var digest: String?
        let discoveryLock = NSLock(); var discoveredFiles: Set<URL>?
        var payloadChecksums: [URL: String] = [:]
    }
    private let state: State
    private let historyLock: NSRecursiveLock
    public let directory: URL
    public let localDirectory: URL
    public let isUbiquitous: Bool
    public var file: URL { directory.appendingPathComponent("ledger.json") }
    private var history: URL { localDirectory.appendingPathComponent("Recovery", isDirectory: true) }
    public init(directory: URL) {
        self.directory = directory; localDirectory = directory; isUbiquitous = false; state = State(); historyLock = NSRecursiveLock()
    }
    private init(directory: URL, localDirectory: URL, isUbiquitous: Bool, historyLock: NSRecursiveLock) {
        self.directory = directory; self.localDirectory = localDirectory; self.isUbiquitous = isUbiquitous; state = State(); self.historyLock = historyLock
    }
    // A relocated repository shares LOCAL history and its lock, never the last-read digest.
    public func relocated(to directory: URL, isUbiquitous: Bool = false) -> Self {
        Self(directory: directory, localDirectory: localDirectory, isUbiquitous: isUbiquitous, historyLock: historyLock)
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
        for recovery in versions.dropFirst(20) {
            do {
                try FileManager.default.removeItem(at: recovery.url)
                try? FileManager.default.removeItem(at: recoveryAttachments(recovery.url))
            } catch { continue }
        }
        guard let remaining = try? recoveries() else { return }
        var used = Set<UUID>()
        // Never collect payloads if any retained metadata cannot be read.
        for version in remaining {
            guard let ledger = try? LedgerCodec.decode(recoveryBytes(version.url)) else { return }
            used.formUnion(ledger.attachments.map(\.id))
        }
        for current in Set([file, localDirectory.appendingPathComponent("ledger.json")]) where containsFile(current) {
            guard let ledger = try? LedgerCodec.decode(Data(contentsOf: current)) else { return }
            used.formUnion(ledger.attachments.map(\.id))
        }
        guard let payloads = try? FileManager.default.contentsOfDirectory(at: recoveryPayloads, includingPropertiesForKeys: nil) else { return }
        for url in payloads where UUID(uuidString: url.lastPathComponent).map({ !used.contains($0) }) == true {
            try? FileManager.default.removeItem(at: url); state.payloadChecksums.removeValue(forKey: url)
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
    @discardableResult public func save(_ ledger: Ledger, reason: String = "修改", requiringUnchanged: Bool = false) throws -> Ledger {
        _ = try LedgerCodec.encodeMetadata(ledger)
        return try access(writing: true) { root in
            if isUbiquitous || requiringUnchanged { try checkUnchanged(at: root) }
            try prepare(root)
            if FileManager.default.fileExists(atPath: root.appendingPathComponent("ledger.json").path) { try preserveCurrent(at: root, reason: reason) }
            else if let bytes = ledger.preMigrationData { try preserve(bytes: bytes, ledger: LedgerCodec.decode(bytes), reason: "升级前版本") }
            let saved = try put(ledger, at: root); pruneHistory(); return saved
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
