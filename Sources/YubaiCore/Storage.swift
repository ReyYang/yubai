import Foundation
import CryptoKit
import CArchive
import Darwin

private struct LedgerHeader: Decodable { let schema: Int }

public enum LedgerCodec {
    public static func encode(_ ledger: Ledger) throws -> Data {
        try ledger.validate(); let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; let data = try encoder.encode(ledger)
        guard data.count <= 250 * 1024 * 1024 else { throw YubaiError.invalid("附件使账本超过安全容量，本次修改未保存。请减少这次导入的文件大小。") }; return data
    }
    public static func decode(_ data: Data) throws -> Ledger {
        guard data.count <= 250 * 1024 * 1024 else { throw YubaiError.invalid("账本超过安全读取大小，请分开处理附件。") }
        do {
            var ledger = try JSONDecoder().decode(Ledger.self, from: data); try ledger.validate()
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
public struct LedgerRepository: Sendable {
    private final class State: @unchecked Sendable {
        let lock = NSRecursiveLock(); var digest: SHA256.Digest?
    }
    private let state = State() // Copies serialize repository operations and share the last verified bytes.
    public let directory: URL
    public var file: URL { directory.appendingPathComponent("ledger.json") }
    public init(directory: URL) { self.directory = directory }
    private func prepare(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }
    private func writePrivate(_ data: Data, to destination: URL) throws {
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(".writing-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try data.write(to: temporary, options: .atomic)
        try protect(temporary)
        guard Darwin.rename(temporary.path, destination.path) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }
    private func protect(_ url: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
        #endif
    }
    private func preserveCurrent(reason: String, verify: Bool) throws {
        let manager = FileManager.default; let history = directory.appendingPathComponent("Recovery", isDirectory: true)
        try prepare(history)
        let latest = try recoveries().first.map { Int64(($0.date.timeIntervalSince1970 * 1000).rounded()) } ?? 0
        let stamp = max(Int64(Date().timeIntervalSince1970 * 1000), latest + 1)
        let suffix = UUID().uuidString.prefix(8)
        let safeReason = reason.replacingOccurrences(of: "/", with: "-").prefix(40)
        var destination = history.appendingPathComponent("\(stamp)-\(suffix)-\(safeReason).json")
        var complete = false
        defer { if !complete { try? manager.removeItem(at: destination) } }
        // Atomic replacement leaves the linked prior inode intact; copying handles filesystems without links.
        if Darwin.link(file.path, destination.path) != 0 { try manager.copyItem(at: file, to: destination) }
        try protect(destination)
        let bytes = try Data(contentsOf: destination)
        if verify, state.digest != SHA256.hash(data: bytes) {
            _ = try LedgerCodec.decode(bytes) // Unrecognized bytes must still pass full corruption checks.
        }
        if (try? JSONDecoder().decode(LedgerHeader.self, from: bytes).schema) == 1 {
            let upgraded = history.appendingPathComponent("\(stamp)-\(suffix)-升级前版本.json")
            if upgraded != destination { try manager.moveItem(at: destination, to: upgraded); destination = upgraded }
        }
        complete = true
    }
    private func preserveMigrationSource(_ ledger: Ledger) throws {
        guard let bytes = ledger.preMigrationData else { return }
        let history = directory.appendingPathComponent("Recovery", isDirectory: true)
        try prepare(history)
        let latest = try recoveries().first.map { Int64(($0.date.timeIntervalSince1970 * 1000).rounded()) } ?? 0
        let stamp = max(Int64(Date().timeIntervalSince1970 * 1000), latest + 1)
        try writePrivate(bytes, to: history.appendingPathComponent("\(stamp)-\(UUID().uuidString.prefix(8))-升级前版本.json"))
    }
    private func pruneHistory() {
        if let history = try? recoveries() { for recovery in history.dropFirst(20) { try? FileManager.default.removeItem(at: recovery.url) } }
    }
    public func load() throws -> Ledger {
        state.lock.lock(); defer { state.lock.unlock() }
        guard FileManager.default.fileExists(atPath: file.path) else { state.digest = nil; return Ledger() }
        let bytes = try Data(contentsOf: file); let ledger = try LedgerCodec.decode(bytes)
        state.digest = SHA256.hash(data: bytes); return ledger
    }
    public func save(_ ledger: Ledger, reason: String = "修改") throws {
        state.lock.lock(); defer { state.lock.unlock() }
        let encoded = try LedgerCodec.encode(ledger)
        let manager = FileManager.default
        try prepare(directory)
        if manager.fileExists(atPath: file.path) {
            try preserveCurrent(reason: reason, verify: true)
        } else { try preserveMigrationSource(ledger) }
        try writePrivate(encoded, to: file)
        state.digest = SHA256.hash(data: encoded)
        // History belongs solely to this ledger. Retain the latest 20 complete prior revisions.
        pruneHistory()
    }
    public func recoveries() throws -> [Recovery] {
        state.lock.lock(); defer { state.lock.unlock() }
        let path = directory.appendingPathComponent("Recovery")
        guard FileManager.default.fileExists(atPath: path.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: path, includingPropertiesForKeys: [.contentModificationDateKey]).filter { $0.pathExtension == "json" }.map { url in
            let name = url.deletingPathExtension().lastPathComponent
            let stamp = name.split(separator: "-").first.flatMap { Int64($0) }.flatMap { (0..<10_000_000_000_000).contains($0) ? $0 : nil }
            let date = stamp.map { Date(timeIntervalSince1970: Double($0) / 1000) } ?? (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return Recovery(url: url, date: date, name: name)
        }.sorted { $0.date > $1.date }
    }
    public func recover(_ recovery: Recovery) throws -> Ledger {
        state.lock.lock(); defer { state.lock.unlock() }
        guard recovery.url.deletingLastPathComponent().standardizedFileURL == directory.appendingPathComponent("Recovery").standardizedFileURL else { throw YubaiError.invalid("恢复文件不属于当前账本。") }
        let restored = try LedgerCodec.decode(Data(contentsOf: recovery.url))
        // Use the same visible recovery history as an imported backup, so the user
        // can undo a restore from the app without locating hidden files.
        try restoreBackup(restored)
        return restored
    }
    public func restoreBackup(_ restored: Ledger) throws {
        state.lock.lock(); defer { state.lock.unlock() }
        let bytes = try LedgerCodec.encode(restored)
        try prepare(directory)
        if FileManager.default.fileExists(atPath: file.path) {
            try preserveCurrent(reason: "恢复前", verify: false)
        }
        try preserveMigrationSource(restored)
        try writePrivate(bytes, to: file)
        state.digest = SHA256.hash(data: bytes)
        pruneHistory()
    }
}

public enum Backup {
    private struct Envelope: Codable {
        var format = "yubai-backup"; var version = 1; var createdAt = Date()
        var encrypted: Bool; var salt: Data?; var rounds: Int?; var payload: Data; var checksum: String
    }
    private static func key(password: String, salt: Data, rounds: Int) throws -> SymmetricKey {
        guard (100_000...1_000_000).contains(rounds), salt.count == 16 else { throw YubaiError.invalid("备份加密参数无效。") }
        let passwordData = Array(password.utf8); var output = [UInt8](repeating: 0, count: 32)
        let result = passwordData.withUnsafeBytes { pass in salt.withUnsafeBytes { s in
            yubai_derive_key(pass.bindMemory(to: CChar.self).baseAddress, passwordData.count, s.bindMemory(to: UInt8.self).baseAddress, salt.count, UInt32(rounds), &output)
        } }
        guard result == 0 else { throw YubaiError.invalid("无法创建备份加密密钥。") }
        return SymmetricKey(data: output)
    }
    public static func export(_ ledger: Ledger, password: String = "") throws -> Data {
        let plain = try LedgerCodec.encode(ledger)
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
        guard data.count <= 350 * 1024 * 1024 else { throw YubaiError.invalid("备份文件过大。") }
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
        return try LedgerCodec.decode(plain)
    }
}
