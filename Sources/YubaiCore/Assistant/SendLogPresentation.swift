import Foundation

public struct SendLogSummaryLine: Equatable, Sendable {
    public let label: String
    public let value: String
    public init(_ label: String, _ value: String) { self.label = label; self.value = value }
}
public struct SendLogTraceStep: Identifiable, Equatable, Sendable {
    public let id: Int
    public let title: String
    public let outgoing: Bool
    public let lines: [SendLogSummaryLine]
}

/// Plain-language projections of the in-memory trace. Raw requests remain available
/// separately; the timeline never dumps tool JSON or repeats conversation history.
public enum SendLogPresentation {
    public static func toolName(_ name: String) -> String {
        switch name {
        case "get_profile": return "账户和消费观"
        case "query_entries": return "查账目"
        case "get_funds": return "算还能花"
        case "forecast": return "看现金会怎么走"
        case "summarize": return "汇总收支"
        case "compare_to_habit": return "和平时的花费比一比"
        case "propose_entry": return "提出记账草稿"
        case "propose_entry_changes": return "提出账目修改"
        case "propose_plan": return "提出收付款安排"
        case "propose_profile_change": return "提出消费观修改"
        case "remember": return "记住一件事"
        case "recall": return "找记住的事"
        default: return "其他查阅"
        }
    }
    public static func purpose(_ value: String) -> String {
        if value.hasPrefix("问余白") { return "问余白" }
        if value.contains("识别列") { return "识别表头" }
        if value.contains("记忆") || value == "每周回看" { return "记住的事" }
        if value.contains("来信") { return "每周来信" }
        return value
    }
    public static func rules(in group: SendLogGroup) -> [String] {
        var rules: [String] = []
        for message in group.items.flatMap(\.messages) where message.role == .system {
            if let text = message.content, !text.isEmpty, !rules.contains(text) { rules.append(text) }
        }
        return rules
    }
    public static func trace(in group: SendLogGroup) -> [SendLogTraceStep] {
        var steps: [SendLogTraceStep] = [], previous: [ChatMessage] = []
        var names: [String: String] = [:]
        func add(_ title: String, outgoing: Bool, lines: [SendLogSummaryLine]) {
            guard !lines.isEmpty else { return }
            steps.append(SendLogTraceStep(id: steps.count + 1, title: title, outgoing: outgoing, lines: lines))
        }
        for (index, item) in group.items.enumerated() {
            for call in item.messages.flatMap({ $0.toolCalls ?? [] }) { names[call.id] = call.function.name }
            var start = 0
            if index == 0 {
                start = item.messages.lastIndex(where: { $0.role == .user }) ?? 0
            } else {
                while start < min(previous.count, item.messages.count), previous[start] == item.messages[start] { start += 1 }
                // A compressed history is a new snapshot. Restrict it to this turn.
                if start < previous.count { start = max(start, item.messages.lastIndex(where: { $0.role == .user }) ?? start) }
            }
            for message in item.messages.dropFirst(start) {
                guard let content = message.content, !content.isEmpty else { continue }
                switch message.role {
                case .user: add("发出 · 你说的", outgoing: true, lines: summary(content))
                case .tool:
                    let name = names[message.toolCallID ?? ""].map(toolName) ?? "查阅结果"
                    add("发出 · 余白给的", outgoing: true, lines: [.init("查阅", name)] + summary(content))
                case .system, .assistant: break
                }
            }
            previous = item.messages
            guard let response = item.response else {
                add("等云端回", outgoing: false, lines: [.init("", "还在等待回复")]); continue
            }
            if !response.toolCalls.isEmpty {
                let proposal = response.toolCalls.allSatisfy { $0.hasPrefix("propose_") }
                add(proposal ? "云端回 · 提出草稿" : "云端回 · 想先看", outgoing: false,
                    lines: response.toolCalls.map { .init("", toolName($0)) })
            }
            if let content = response.content, !content.isEmpty {
                add("云端回 · 回答", outgoing: false, lines: summary(content))
            }
            if let error = response.errorDescription {
                add("没成功", outgoing: false, lines: [.init("原因", error)])
            } else if response.finishReason == "length" {
                add("没成功", outgoing: false, lines: [.init("原因", "云端回复被截断")])
            } else if let status = response.httpStatus, !(200..<300).contains(status) {
                add("没成功", outgoing: false, lines: [.init("原因", "HTTP \(status)")])
            }
        }
        return steps
    }

    public static func summary(_ text: String) -> [SendLogSummaryLine] {
        guard let value = try? JSONValue.parse(text) else { return [.init("", clipped(text, limit: 600))] }
        guard let fields = value.objectValue else { return [.init("内容", short(value))] }
        let keys: [(String, String)] = [
            ("error", "需要核对"), ("accounts", "账户"), ("entry_account_hint", "本次账户"),
            ("parsed_entries", "本机读出的"), ("restrain", "想克制"), ("generous", "愿意多花"),
            ("principles", "消费原则"), ("entries", "账目"), ("rows", "记录"), ("count", "笔数"),
            ("total", "合计"), ("income", "收入"), ("expense", "支出"), ("available", "可支配"),
            ("preview", "草稿"), ("skipped", "未采用"), ("memories", "记住的事"), ("notes", "记住的事"),
            ("summary", "摘要"), ("answer", "回答"), ("headers", "表头"), ("samples", "脱敏样例"),
            ("changes", "整理结果"), ("questions", "需要你选"), ("text", "内容"),
            ("date", "日期列"), ("amount", "金额列"), ("direction", "收支列")]
        let lines = keys.compactMap { key, label -> SendLogSummaryLine? in
            guard let v = fields[key], v != .null, v != .array([]) else { return nil }
            if key == "entry_account_hint" { return .init(label, "已提供账户标识") }
            return .init(label, short(v))
        }
        return lines.isEmpty ? [.init("内容", "\(fields.count) 项资料")] : Array(lines.prefix(6))
    }
    private static func short(_ value: JSONValue) -> String {
        switch value {
        case .null: return "未提供"
        case .bool(let b): return b ? "是" : "否"
        case .number(let n): return String(format: "%g", n)
        case .string(let s): return UUID(uuidString: s) == nil ? clipped(s, limit: 160) : "已提供标识"
        case .array(let rows):
            let parts = rows.prefix(3).map { row -> String in
                if let title = row["title"]?.stringValue ?? row["text"]?.stringValue {
                    let amount = row["amount"].map(short).map { " " + $0 } ?? ""
                    return clipped(title, limit: 50) + amount
                }
                return short(row)
            }
            return "\(rows.count) 项" + (parts.isEmpty ? "" : "：" + parts.joined(separator: " · ")) + (rows.count > 3 ? "…" : "")
        case .object(let fields):
            if let text = fields["text"]?.stringValue { return clipped(text, limit: 160) }
            if let title = fields["title"]?.stringValue { return clipped(title, limit: 160) }
            return "\(fields.count) 项资料"
        }
    }
    private static func clipped(_ text: String, limit: Int) -> String {
        String(text.prefix(limit)) + (text.count > limit ? "…" : "")
    }
}

public struct SendLogRawField: Identifiable, Equatable, Sendable {
    public var id: String { name }
    public let name: String
    public let value: JSONValue
}

public struct SendLogRawGroup: Equatable, Sendable {
    public let party: String
    public let detail: String
    public let fields: [SendLogRawField]
}

public struct SendLogRawSection: Equatable, Sendable {
    public enum Body: Equatable, Sendable {
        case fields([SendLogRawField])
        case groups([SendLogRawGroup])
        case array(name: String, values: [JSONValue])
        case text(String)
    }
    public let title: String?
    public let body: Body
}

/// Lossless text fallbacks and unabridged JSON projections for the raw sheet.
/// Unlike the timeline, these do not translate field names or clip values.
public enum SendLogRawPresentation {
    public struct Rules: Equatable, Sendable {
        public let text: String
        public var paragraphs: [String] { text.components(separatedBy: "\n") }
        public var preview: String { paragraphs.first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? "" }
        public var count: Int { text.count }
    }

    public static func rules(in item: SendLogItem) -> Rules {
        Rules(text: SendLogPresentation.rules(in: SendLogGroup(items: [item])).joined(separator: "\n\n"))
    }

    public static func fields(in object: [String: JSONValue]) -> [SendLogRawField] {
        object.keys.sorted().map { SendLogRawField(name: $0, value: object[$0]!) }
    }

    public static func isScalar(_ value: JSONValue) -> Bool {
        switch value { case .array, .object: false; default: true }
    }

    public static func scalarText(_ value: JSONValue) -> String {
        switch value {
        case .string(let text): text
        case .null: "null"
        default: (try? value.jsonText()) ?? ""
        }
    }

    public static func initiallyCollapsed(count: Int) -> Bool { count > 8 }
    public static func initiallyCollapsed(_ values: [JSONValue]) -> Bool { initiallyCollapsed(count: values.count) }

    public static func arrayTitle(_ name: String, count: Int) -> String {
        let unit = name == "groups" ? "组" : name == "questions" ? "个" : "项"
        return "\(name) · \(count) \(unit)"
    }

    public static func requestSections(in item: SendLogItem) -> [SendLogRawSection] {
        // Older/unparsed log items still expose their original request.
        guard !item.messages.isEmpty else { return requestSections(item.requestText) }
        return item.messages.filter { $0.role != .system }.flatMap { message in
            var sections = message.content.flatMap { $0.isEmpty ? nil : requestSections($0) } ?? []
            for call in message.toolCalls ?? [] {
                let arguments = (try? JSONValue.parse(call.function.arguments)).flatMap { $0.objectValue == nil ? nil : $0 }
                    ?? .string(call.function.arguments)
                sections.append(SendLogRawSection(title: nil, body: .fields(fields(in: [
                    "id": .string(call.id), "type": .string(call.type),
                    "function": .object(["name": .string(call.function.name), "arguments": arguments])
                ]))))
            }
            return sections
        }
    }

    public static func requestSections(_ text: String) -> [SendLogRawSection] {
        guard let object = (try? JSONValue.parse(text))?.objectValue else {
            return [SendLogRawSection(title: nil, body: .text(text))]
        }
        var remaining = object
        var groups: [SendLogRawGroup]?
        if let values = object["groups"]?.arrayValue, !values.isEmpty,
           values.allSatisfy({ $0["party"]?.stringValue != nil }) {
            groups = values.map { value in
                var fields = value.objectValue!
                let party = fields.removeValue(forKey: "party")!.stringValue!
                let inflow = fields.removeValue(forKey: "inflow") == .bool(true)
                let count = fields.removeValue(forKey: "count").map(scalarText)
                let direction = inflow ? "收入" : "支出"
                return SendLogRawGroup(party: party, detail: count.map { "\(direction) · \($0) 笔" } ?? direction,
                    fields: Self.fields(in: fields))
            }
            remaining.removeValue(forKey: "groups")
        }
        var sections: [SendLogRawSection] = []
        if !remaining.isEmpty { sections.append(SendLogRawSection(title: nil, body: .fields(fields(in: remaining)))) }
        if let groups {
            sections.append(SendLogRawSection(title: arrayTitle("groups", count: groups.count), body: .groups(groups)))
        }
        // Keep an explicitly empty object visible as raw JSON.
        return sections.isEmpty ? [SendLogRawSection(title: nil, body: .text(text))] : sections
    }

    public static func responseSections(in item: SendLogItem) -> [SendLogRawSection] {
        guard let response = item.response else {
            return [SendLogRawSection(title: nil, body: .text("还在等待回复"))]
        }
        var sections: [SendLogRawSection] = []
        if let content = response.content, !content.isEmpty {
            if let value = try? JSONValue.parseModelResponse(content) {
                if let object = value.objectValue, !object.isEmpty {
                    let ordinary = object.filter { $0.value.arrayValue == nil }
                    if !ordinary.isEmpty { sections.append(SendLogRawSection(title: nil, body: .fields(fields(in: ordinary)))) }
                    for field in fields(in: object) {
                        if let values = field.value.arrayValue {
                            sections.append(SendLogRawSection(title: arrayTitle(field.name, count: values.count),
                                body: .array(name: field.name, values: values)))
                        }
                    }
                } else if let values = value.arrayValue {
                    sections.append(SendLogRawSection(title: nil, body: .array(name: "", values: values)))
                } else { sections.append(SendLogRawSection(title: nil, body: .text(scalarText(value)))) }
            } else { sections.append(SendLogRawSection(title: nil, body: .text(content))) }
        }
        if !response.toolCalls.isEmpty {
            sections.append(SendLogRawSection(title: nil, body: .fields([
                SendLogRawField(name: "tool_calls", value: .array(response.toolCalls.map { .string($0) }))
            ])))
        }
        if let reason = failureReason(response) { sections.append(SendLogRawSection(title: nil, body: .text(reason))) }
        return sections
    }

    private static func failureReason(_ response: SendLogResponse) -> String? {
        response.errorDescription ?? (response.finishReason == "length" ? "云端回复被截断" : nil)
            ?? response.httpStatus.flatMap { (200..<300).contains($0) ? nil : "HTTP \($0)" }
    }

    /// JSONSerialization preserves numeric values without a Double round trip.
    /// Deliberately omit sortedKeys: copying should only format the raw payload.
    public static func prettyPrinted(_ text: String) -> String {
        guard let value = try? JSONSerialization.jsonObject(with: Data(text.utf8), options: [.fragmentsAllowed]),
              let data = try? JSONSerialization.data(withJSONObject: value,
                options: [.prettyPrinted, .withoutEscapingSlashes, .fragmentsAllowed]) else { return text }
        return String(decoding: data, as: UTF8.self)
    }

    public static func copyText(in group: SendLogGroup) -> String {
        group.items.enumerated().map { index, item in
            var reply: [String] = []
            // Keep fences/commentary and the original content in the clipboard.
            if let content = item.response?.content, !content.isEmpty { reply.append(prettyPrinted(content)) }
            if let calls = item.response?.toolCalls, !calls.isEmpty,
               let data = try? JSONSerialization.data(withJSONObject: ["tool_calls": calls], options: [.prettyPrinted, .withoutEscapingSlashes]) {
                reply.append(String(decoding: data, as: UTF8.self))
            }
            if let response = item.response, let reason = failureReason(response) { reply.append(reason) }
            if item.response == nil { reply.append("还在等待回复") }
            return "第 \(index + 1) 次发出\n" + prettyPrinted(item.requestText)
                + "\n\n第 \(index + 1) 次云端回\n" + reply.joined(separator: "\n\n")
        }.joined(separator: "\n\n")
    }
}
