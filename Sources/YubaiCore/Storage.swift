import Foundation
import CryptoKit
import CArchive
import Darwin

public enum LedgerCodec {
    public static func encode(_ ledger: Ledger) throws -> Data {
        try ledger.validate(); let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; let data = try encoder.encode(ledger)
        guard data.count <= 250 * 1024 * 1024 else { throw YubaiError.invalid("附件使账本超过安全容量，本次修改未保存。请减少这次导入的文件大小。") }; return data
    }
    public static func decode(_ data: Data) throws -> Ledger {
        guard data.count <= 250 * 1024 * 1024 else { throw YubaiError.invalid("账本超过安全读取大小，请分开处理附件。") }
        do { let ledger = try JSONDecoder().decode(Ledger.self, from: data); try ledger.validate(); return ledger }
        catch let error as YubaiError { throw error }
        catch { throw YubaiError.invalid("账本格式损坏或版本不兼容，原文件已保留。请从备份恢复。") }
    }
}
public struct Recovery: Identifiable, Sendable {
    public var id: URL { url }; public var url: URL; public var date: Date; public var name: String
}
public struct LedgerRepository: Sendable {
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
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: temporary.path)
        #endif
        guard Darwin.rename(temporary.path, destination.path) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }
    private func pruneHistory() {
        if let history = try? recoveries() { for recovery in history.dropFirst(20) { try? FileManager.default.removeItem(at: recovery.url) } }
    }
    public func load() throws -> Ledger {
        guard FileManager.default.fileExists(atPath: file.path) else { return Ledger() }
        return try LedgerCodec.decode(Data(contentsOf: file))
    }
    public func save(_ ledger: Ledger, reason: String = "修改") throws {
        let encoded = try LedgerCodec.encode(ledger)
        let manager = FileManager.default
        try prepare(directory)
        if manager.fileExists(atPath: file.path) {
            let old = try Data(contentsOf: file)
            _ = try LedgerCodec.decode(old) // A corrupt current file is never silently overwritten.
            let history = directory.appendingPathComponent("Recovery", isDirectory: true)
            try prepare(history)
            let safeReason = reason.replacingOccurrences(of: "/", with: "-").prefix(40)
            let name = "\(Int(Date().timeIntervalSince1970 * 1000))-\(UUID().uuidString.prefix(8))-\(safeReason).json"
            try writePrivate(old, to: history.appendingPathComponent(name))
        }
        try writePrivate(encoded, to: file)
        // History belongs solely to this ledger. Retain the latest 20 complete prior revisions.
        pruneHistory()
    }
    public func recoveries() throws -> [Recovery] {
        let path = directory.appendingPathComponent("Recovery")
        guard FileManager.default.fileExists(atPath: path.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: path, includingPropertiesForKeys: [.contentModificationDateKey]).filter { $0.pathExtension == "json" }.map { url in
            Recovery(url: url, date: (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast, name: url.deletingPathExtension().lastPathComponent)
        }.sorted { $0.date > $1.date }
    }
    public func recover(_ recovery: Recovery) throws -> Ledger {
        guard recovery.url.deletingLastPathComponent().standardizedFileURL == directory.appendingPathComponent("Recovery").standardizedFileURL else { throw YubaiError.invalid("恢复文件不属于当前账本。") }
        let restored = try LedgerCodec.decode(Data(contentsOf: recovery.url))
        // Use the same visible recovery history as an imported backup, so the user
        // can undo a restore from the app without locating hidden files.
        try restoreBackup(restored)
        return restored
    }
    public func restoreBackup(_ restored: Ledger) throws {
        let bytes = try LedgerCodec.encode(restored)
        try prepare(directory)
        if FileManager.default.fileExists(atPath: file.path) {
            let history = directory.appendingPathComponent("Recovery", isDirectory: true)
            try prepare(history)
            try writePrivate(Data(contentsOf: file), to: history.appendingPathComponent("\(Int(Date().timeIntervalSince1970 * 1000))-恢复前-\(UUID().uuidString.prefix(8)).json"))
        }
        try writePrivate(bytes, to: file)
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
