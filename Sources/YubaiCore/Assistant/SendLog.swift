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
    public var groupID: UUID? = nil
    public var groupTitle: String? = nil
    /// Tool results are messages with role .tool and their original toolCallID.
    public var messages: [ChatMessage] = []
    public var tools: [String] = []
    public var temperature: Double?
    public var maxTokens: Int?
    public var response: SendLogResponse?
    /// Occurrences in the outgoing message content/arguments, after redaction.
    public var redactionSummary: [String: Int] = [:]
}

/// A snapshot of retained requests, in chronological order. Evicted requests are
/// not included in totals. Legacy requests without a group ID each form one group.
public struct SendLogGroup: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let title: String
    public let purpose: String
    public let startedAt: Date
    public let requestCount: Int
    public let totalBytes: Int
    /// Sum of request durations, rather than elapsed time between requests.
    public let totalDurationMilliseconds: Int
    public let hasFailure: Bool
    public let failureReasons: [String]
    public let redactionSummary: [String: Int]
    public let items: [SendLogItem]

    init(items: [SendLogItem]) {
        let items = items.sorted { $0.time < $1.time }
        let first = items[0]
        self.items = items; id = first.groupID ?? first.id
        title = first.groupTitle ?? first.purpose; purpose = first.purpose
        startedAt = first.time; requestCount = items.count
        totalBytes = items.reduce(0) { $0 + $1.byteSize }
        totalDurationMilliseconds = items.reduce(0) { $0 + ($1.response?.durationMilliseconds ?? 0) }
        var reasons: [String] = [], summary: [String: Int] = [:]
        for item in items {
            if let response = item.response {
                let reason = response.errorDescription ?? response.httpStatus.flatMap {
                    (200..<300).contains($0) ? nil : "HTTP \($0)"
                }
                if let reason, !reasons.contains(reason) { reasons.append(reason) }
            }
            for (kind, count) in item.redactionSummary { summary[kind, default: 0] += count }
        }
        failureReasons = reasons; hasFailure = !reasons.isEmpty; redactionSummary = summary
    }
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
    /// Newest group first. Each group's items and totals share one locked snapshot.
    public var groups: [SendLogGroup] {
        let snapshot = items.reversed()
        var grouped: [UUID: [SendLogItem]] = [:], order: [UUID] = []
        for item in snapshot {
            let key = item.groupID ?? item.id
            if grouped[key] == nil { order.append(key) }
            grouped[key, default: []].append(item)
        }
        return order.reversed().compactMap { grouped[$0].map { SendLogGroup(items: $0) } }
            .sorted { $0.startedAt > $1.startedAt }
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

    @discardableResult func record(time: Date = Date(), purpose: String, model: String, body: Data, apiKey: String,
                                   groupID: UUID? = nil, groupTitle: String? = nil) -> UUID {
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
        item.groupID = groupID
        // Redact the complete title before truncating, so a cut identifier cannot leak.
        item.groupTitle = groupTitle.map { String(Redactor.shared.text(Self.hideKey($0, apiKey)).prefix(30)) }
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
