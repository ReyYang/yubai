import Foundation

public struct SendLogItem: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let time: Date
    public let purpose: String
    public let model: String
    public let byteSize: Int
    public let requestText: String
}

/// Memory only; never stores headers or credentials. All access is guarded by the lock.
public final class SendLog: @unchecked Sendable {
    public static let shared = SendLog()
    public static let didRecord = Notification.Name("Yubai.SendLog.didRecord")
    private let lock = NSLock()
    private var buffer: [SendLogItem] = []
    private var count = 0
    public init() {}
    public var items: [SendLogItem] {
        lock.lock(); defer { lock.unlock() }; return Array(buffer.reversed())
    }
    public var totalCount: Int { lock.lock(); defer { lock.unlock() }; return count }
    func record(time: Date = Date(), purpose: String, model: String, body: Data, apiKey: String) {
        // Defence in depth if user text happens to contain the configured key.
        let clean = String(decoding: body, as: UTF8.self).replacingOccurrences(of: apiKey, with: "[密钥已隐藏]")
        let truncated = String(decoding: Array(clean.utf8.prefix(4096)), as: UTF8.self)
        let item = SendLogItem(id: UUID(), time: time,
            purpose: purpose.replacingOccurrences(of: apiKey, with: "[密钥已隐藏]"),
            model: model.replacingOccurrences(of: apiKey, with: "[密钥已隐藏]"), byteSize: body.count, requestText: truncated)
        lock.lock()
        count += 1
        buffer.append(item)
        if buffer.count > 50 { buffer.removeFirst(buffer.count - 50) }
        lock.unlock()
        NotificationCenter.default.post(name: Self.didRecord, object: nil)
    }
}
