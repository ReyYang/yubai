import Foundation

public struct SendLogResponse: Codable, Sendable, Equatable {
    public var content: String?
    public var toolCalls: [String]
    public var finishReason: String?
    public var durationMilliseconds: Int
    public var httpStatus: Int?
    public var errorDescription: String?
    public init(content: String? = nil, toolCalls: [String] = [], finishReason: String? = nil,
                durationMilliseconds: Int, httpStatus: Int? = nil, errorDescription: String? = nil) {
        self.content = content; self.toolCalls = toolCalls; self.finishReason = finishReason
        self.durationMilliseconds = durationMilliseconds; self.httpStatus = httpStatus; self.errorDescription = errorDescription
    }
}

public struct SendLogItem: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public let time: Date
    public let purpose: String
    public let model: String
    public let byteSize: Int
    public let requestText: String
    /// Tool results are messages with role .tool and their original toolCallID.
    public var messages: [ChatMessage] = []
    public var tools: [String] = []
    public var temperature: Double?
    public var maxTokens: Int?
    public var response: SendLogResponse?
    /// Occurrences in the outgoing message content/arguments, after redaction.
    public var redactionSummary: [String: Int] = [:]
}

/// Memory only; never stores headers or credentials. All access is guarded by the lock.
/// The byte budget includes both raw text and structured copies, including replies.
public final class SendLog: @unchecked Sendable {
    public static let shared = SendLog()
    public static let didRecord = Notification.Name("Yubai.SendLog.didRecord")
    private let lock = NSLock()
    private var buffer: [SendLogItem] = []
    private var sizes: [UUID: Int] = [:]
    private var bytes = 0
    private var count = 0
    public let byteBudget: Int
    public init(byteBudget: Int = 2 * 1024 * 1024) { self.byteBudget = max(0, byteBudget) }
    public var items: [SendLogItem] {
        lock.lock(); defer { lock.unlock() }; return Array(buffer.reversed())
    }
    public var totalCount: Int { lock.lock(); defer { lock.unlock() }; return count }
    public var retainedByteSize: Int { lock.lock(); defer { lock.unlock() }; return bytes }

    private static func hideKey(_ text: String, _ key: String) -> String {
        key.isEmpty ? text : text.replacingOccurrences(of: key, with: "[密钥已隐藏]")
    }
    private static func sanitized(_ value: JSONValue, key: String) -> JSONValue {
        switch value {
        case .string(let s): return .string(hideKey(s, key))
        case .array(let a): return .array(a.map { sanitized($0, key: key) })
        case .object(let fields):
            var clean: [String: JSONValue] = [:]
            for (name, value) in fields { clean[hideKey(name, key)] = sanitized(value, key: key) }
            return .object(clean)
        default: return value
        }
    }

    @discardableResult func record(time: Date = Date(), purpose: String, model: String, body: Data, apiKey: String) -> UUID {
        // Parse before replacing: a key can contain JSON-escaped characters.
        let original = String(decoding: body, as: UTF8.self)
        let text = (try? JSONValue.parse(original)).flatMap { try? Self.sanitized($0, key: apiKey).jsonText() }
            ?? Self.hideKey(original, apiKey)
        struct Request: Decodable {
            var messages: [ChatMessage]?
            struct Tool: Decodable { struct Function: Decodable { var name: String }; var function: Function }
            var tools: [Tool]?
            var temperature: Double?
            var max_tokens: Int?
        }
        let parsed = try? JSONDecoder().decode(Request.self, from: Data(text.utf8))
        var item = SendLogItem(id: UUID(), time: time, purpose: Self.hideKey(purpose, apiKey),
            model: Self.hideKey(model, apiKey), byteSize: body.count, requestText: text)
        item.messages = parsed?.messages ?? []; item.tools = parsed?.tools?.map { $0.function.name } ?? []
        item.temperature = parsed?.temperature; item.maxTokens = parsed?.max_tokens
        let contents = item.messages.flatMap { message in
            [message.content ?? ""] + (message.toolCalls ?? []).map { $0.function.arguments }
        }
        item.redactionSummary = Redactor.placeholderSummary(in: contents)
        lock.lock()
        count += 1; buffer.append(item); accountFor(item); evict()
        lock.unlock()
        NotificationCenter.default.post(name: Self.didRecord, object: nil)
        return item.id
    }

    /// A late completion for an already evicted request is deliberately ignored.
    func complete(id: UUID, response: SendLogResponse, apiKey: String) {
        var clean = response
        clean.content = clean.content.map { Self.hideKey($0, apiKey) }
        clean.toolCalls = clean.toolCalls.map { Self.hideKey($0, apiKey) }
        clean.finishReason = clean.finishReason.map { Self.hideKey($0, apiKey) }
        clean.errorDescription = clean.errorDescription.map { Self.hideKey($0, apiKey) }
        lock.lock()
        guard let i = buffer.firstIndex(where: { $0.id == id }) else { lock.unlock(); return }
        buffer[i].response = clean; accountFor(buffer[i]); evict()
        lock.unlock()
        NotificationCenter.default.post(name: Self.didRecord, object: nil)
    }
    private func accountFor(_ item: SendLogItem) {
        let size = (try? JSONEncoder().encode(item).count) ?? byteBudget + 1
        bytes += size - (sizes[item.id] ?? 0); sizes[item.id] = size
    }
    private func evict() {
        while bytes > byteBudget, !buffer.isEmpty {
            let old = buffer.removeFirst(); bytes -= sizes.removeValue(forKey: old.id) ?? 0
        }
    }
}
