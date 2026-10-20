import Foundation

public struct AssistantToolTrace: Equatable, Sendable {
    public let name: String
    public let args: JSONValue
}

public struct AssistantReply: Equatable, Sendable {
    public let text: String
    public let evidenceEntryIDs: [UUID]
    public let toolTrace: [AssistantToolTrace]
    public let unverifiedAmounts: [String]
}

public enum AssistantAgentError: LocalizedError {
    case stepLimit
    public var errorDescription: String? { "本次查询步骤已达上限，请缩小问题后再试。" }
}

public struct AssistantAgent: Sendable {
    public let transport: any ChatTransport
    public let context: ToolContext
    public init(transport: any ChatTransport, context: ToolContext) { self.transport = transport; self.context = context }

    /// maxSteps bounds normal chat turns. Amount verification may make one extra, tool-free request.
    public func run(system: String, messages: [ChatMessage], tools: [any AssistantTool], maxSteps: Int = 8) async throws -> AssistantReply {
        guard maxSteps > 0 else { throw AssistantAgentError.stepLimit }
        let redactor = context.redactor
        var conversation = [ChatMessage(role: .system, content: redactor.text(system))] + messages.map { clean($0) }
        let definitions = tools.map { ChatToolDefinition(name: $0.name, description: redactor.text($0.description), parameters: redactor.value($0.parameters)) }
        var results: [JSONValue] = []; var trace: [AssistantToolTrace] = []; var evidence: [UUID] = []
        let ledgerIDs = Set(context.ledger.activeEntries.map(\.id))
        for _ in 0..<maxSteps {
            try Task.checkCancellation()
            let reply = try await transport.send(ChatRequest(messages: conversation, tools: definitions))
            guard reply.role == .assistant else { throw YubaiError.invalid("云端未返回助手消息。") }
            let calls = reply.toolCalls ?? []
            if calls.isEmpty {
                var text = reply.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !text.isEmpty else { throw YubaiError.invalid("云端返回空内容。") }
                var unverified = AssistantAmountGuard.unverified(in: text, results: results)
                if !unverified.isEmpty {
                    conversation.append(clean(reply))
                    conversation.append(ChatMessage(role: .system, content: "上一条回复含未经工具核实的金额。请重写最终答复，只引用工具结果中的金额原文；没有依据就说明无法确认，不要计算或猜测金额。"))
                    let retry = try await transport.send(ChatRequest(messages: conversation, purpose: "财务管家·金额核对"))
                    guard retry.role == .assistant, retry.toolCalls?.isEmpty ?? true,
                          let revised = retry.content?.trimmingCharacters(in: .whitespacesAndNewlines), !revised.isEmpty else {
                        throw YubaiError.invalid("云端金额核对未返回有效文字。")
                    }
                    text = revised; unverified = AssistantAmountGuard.unverified(in: text, results: results)
                }
                return AssistantReply(text: text, evidenceEntryIDs: evidence, toolTrace: trace, unverifiedAmounts: unverified)
            }
            guard calls.count <= 16, Set(calls.map(\.id)).count == calls.count,
                  calls.allSatisfy({ !$0.id.isEmpty && $0.type == "function" }) else { throw YubaiError.invalid("云端工具调用格式无效。") }
            conversation.append(clean(reply))
            for call in calls {
                try Task.checkCancellation()
                let args = try? JSONValue.parse(call.function.arguments)
                trace.append(AssistantToolTrace(name: call.function.name, args: args.map { redactor.value($0) } ?? .null))
                let result: JSONValue
                do {
                    guard let tool = tools.first(where: { $0.name == call.function.name }) else { throw YubaiError.invalid("没有这个工具，请使用已声明的工具。") }
                    guard let args, args.objectValue != nil else { throw YubaiError.invalid("参数不是有效JSON对象，请按工具结构重试。") }
                    result = redactor.value(try tool.run(args, context))
                } catch {
                    // Only local validation messages may be echoed; arbitrary errors may contain data.
                    let message = (error as? YubaiError)?.localizedDescription ?? "工具未能完成，请检查参数后重试。"
                    result = .object(["error": .object(["message": .string(redactor.text(message)), "retryable": .bool(true)])])
                }
                results.append(result)
                for id in Self.evidence(in: result) where ledgerIDs.contains(id) && !evidence.contains(id) { evidence.append(id) }
                conversation.append(ChatMessage(role: .tool, content: try result.jsonText(), toolCallID: call.id))
            }
        }
        throw AssistantAgentError.stepLimit
    }

    private func clean(_ message: ChatMessage) -> ChatMessage {
        var copy = message
        if let content = copy.content { copy.content = context.redactor.content(content) }
        if var calls = copy.toolCalls {
            for i in calls.indices { calls[i].function.arguments = context.redactor.content(calls[i].function.arguments) }
            copy.toolCalls = calls
        }
        return copy
    }
    private static func evidence(in value: JSONValue) -> [UUID] {
        switch value {
        case .object(let fields):
            let own = fields["entry_ids"]?.arrayValue?.compactMap { $0.stringValue.flatMap(UUID.init(uuidString:)) } ?? []
            return own + fields.filter { $0.key != "entry_ids" }.flatMap { evidence(in: $0.value) }
        case .array(let values): return values.flatMap { evidence(in: $0) }
        default: return []
        }
    }
}

/// A conservative text heuristic, not a semantic proof. Dates, UUIDs, percentages and
/// explicit counts are excluded; bare numbers otherwise count as possible money.
public enum AssistantAmountGuard {
    public static func unverified(in text: String, results: [JSONValue]) -> [String] {
        var allowed = Set<Int64>()
        func collect(_ value: JSONValue) {
            switch value {
            case .string(let text):
                for token in tokens(in: text) { if let cents = token.cents { allowed.insert(cents) } }
            case .object(let fields): for item in fields.values { collect(item) }
            case .array(let values): for item in values { collect(item) }
            default: break // Counts and raw integer cents do not authorize yuan amounts.
            }
        }
        for result in results { collect(result) }
        var found: [String] = []
        for token in tokens(in: text) {
            if let cents = token.cents, allowed.contains(cents) { continue }
            if !found.contains(token.text) { found.append(token.text) }
        }
        return found
    }

    private static func tokens(in text: String) -> [(text: String, cents: Int64?)] {
        var scan = text
        for pattern in [#"\b\d{4}-\d{2}-\d{2}\b"#, #"\b[0-9a-fA-F]{8}-[0-9a-fA-F-]{27,}\b"#] {
            scan = scan.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }
        let pattern = #"(?i)(?:[-−+]\s*)?(?:[¥￥]|CNY|RMB)?\s*(?:[-−+]\s*)?\d+(?:[,，]\d{3})*(?:\.\d+)?\s*(?:万元|千元|百元|元|块钱|块|万|千)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = scan as NSString
        var found: [(text: String, cents: Int64?)] = []
        for match in regex.matches(in: scan, range: NSRange(location: 0, length: ns.length)) {
            let raw = ns.substring(with: match.range).trimmingCharacters(in: .whitespacesAndNewlines)
            let suffix = ns.substring(from: NSMaxRange(match.range)).trimmingCharacters(in: .whitespaces)
            let marked = raw.range(of: #"[¥￥元块万千]|(?i:CNY|RMB)"#, options: .regularExpression) != nil
            if !marked, let first = suffix.first, "%％条笔天次周月年个项步:：".contains(first) { continue }
            var normalized = raw.replacingOccurrences(of: "−", with: "-")
            let multiplier: Int64 = normalized.contains("万") ? 10_000 : (normalized.contains("千") ? 1000 : (normalized.contains("百元") ? 100 : 1))
            for token in ["万元", "千元", "百元", "块钱", "块", "万", "千"] { normalized = normalized.replacingOccurrences(of: token, with: "") }
            normalized = normalized.replacingOccurrences(of: "cny", with: "CNY", options: .caseInsensitive)
                .replacingOccurrences(of: "rmb", with: "RMB", options: .caseInsensitive)
            let parsed = try? Money.parse(normalized, allowNegative: true)
            let product = parsed?.multipliedReportingOverflow(by: multiplier)
            found.append((raw, product.flatMap { $0.overflow ? nil : $0.partialValue }))
        }
        return found
    }
}
