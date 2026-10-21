import Foundation

public struct AssistantToolTrace: Equatable, Sendable {
    public let name: String
    public let args: JSONValue
}

public struct AssistantReply: Equatable, Sendable {
    public var rememberedNotes: [MemoryNote] = []
    public var updatedNotes: [MemoryUpdate] = []
    public var usedMemoryIDs: [UUID] = []
    public var memoryLedgerID: UUID? = nil
    public var memoryLedgerUpdatedAt: Date? = nil
    public var chart: AnswerChart? = nil
    public var purchaseJudgment: PurchaseJudgment? = nil
    public var pastedStatement: PastedStatement? = nil
    public let proposedChangeSets: [ChangeSet]
    public let text: String
    public let evidenceEntryIDs: [UUID]
    public let toolTrace: [AssistantToolTrace]
    public let unverifiedAmounts: [String]
}

public struct AssistantAgent: Sendable {
    public let transport: any ChatTransport
    public let context: ToolContext
    public init(transport: any ChatTransport, context: ToolContext) { self.transport = transport; self.context = context }

    public func run(system: String, messages: [ChatMessage], tools: [any AssistantTool], characterBudget: Int = AssistantContextBudget.defaultLimit, purpose: String = "财务管家") async throws -> AssistantReply {
        let redactor = context.redactor
        let groupID = UUID()
        // SendLog truncates after hiding the transport's key, which may straddle
        // the title boundary and is not known to this agent.
        let groupTitle = redactor.text(messages.last(where: { $0.role == .user })?.content ?? purpose)
        var conversation = [ChatMessage(role: .system, content: redactor.text(system)),
            ChatMessage(role: .system, content: Memory.prompt(ledger: context.ledger, now: context.now, characterBudget: context.memoryCharacterBudget))] + messages.map { clean($0) }
        let definitions = tools.map { ChatToolDefinition(name: $0.name, description: redactor.text($0.description), parameters: redactor.value($0.parameters)) }
        var results: [JSONValue] = []; var trace: [AssistantToolTrace] = []; var evidence: [UUID] = []
        var proposed: [ChangeSet] = []
        var chart: AnswerChart?
        var judgment: PurchaseJudgment?
        var memoryLedger = context.ledger
        var current = context
        var usedMemoryIDs = Set<UUID>()
        var rememberedResults: [String: JSONValue] = [:]
        var previousResults: [String: JSONValue] = [:]
        let ledgerIDs = Set(context.ledger.activeEntries.map(\.id))
        while true {
            try Task.checkCancellation()
            AssistantContextBudget.compactTools(&conversation, limit: characterBudget)
            let reply = try await transport.send(ChatRequest(messages: conversation, tools: definitions, purpose: purpose, groupID: groupID, groupTitle: groupTitle))
            try Task.checkCancellation()
            guard reply.role == .assistant else { throw YubaiError.invalid("云端未返回助手消息。") }
            let calls = reply.toolCalls ?? []
            if calls.isEmpty {
                var text = reply.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !text.isEmpty else { throw YubaiError.invalid("云端返回空内容。") }
                var unverified = AssistantAmountGuard.unverified(in: text, results: results)
                if !unverified.isEmpty {
                    conversation.append(clean(reply))
                    conversation.append(ChatMessage(role: .system, content: "上一条回复含未经工具核实的金额。请重写最终答复，只引用工具结果中的金额原文；没有依据就说明无法确认，不要计算或猜测金额。"))
                    AssistantContextBudget.compactTools(&conversation, limit: characterBudget)
                    let retry = try await transport.send(ChatRequest(messages: conversation, purpose: "\(purpose)·金额核对", groupID: groupID, groupTitle: groupTitle))
                    try Task.checkCancellation()
                    guard retry.role == .assistant, retry.toolCalls?.isEmpty ?? true,
                          let revised = retry.content?.trimmingCharacters(in: .whitespacesAndNewlines), !revised.isEmpty else {
                        throw YubaiError.invalid("云端金额核对未返回有效文字。")
                    }
                    text = revised; unverified = AssistantAmountGuard.unverified(in: text, results: results)
                }
                if let judgment, !judgment.hasProfile, !text.contains("还不知道你在乎什么") {
                    text += "\n还不知道你在乎什么，可以在『我的消费观』里补上"
                }
                var answer = AssistantReply(proposedChangeSets: proposed, text: text, evidenceEntryIDs: evidence, toolTrace: trace, unverifiedAmounts: unverified)
                answer.chart = chart; answer.purchaseJudgment = judgment
                answer.memoryLedgerID = context.ledger.id; answer.memoryLedgerUpdatedAt = context.ledger.updatedAt
                let originals = Dictionary(uniqueKeysWithValues: context.ledger.memories.map { ($0.id, $0) })
                for note in memoryLedger.memories {
                    if let old = originals[note.id] {
                        if !Memory.sameContent(old, note) {
                            var updated = note; updated.previousText = old.text
                            answer.updatedNotes.append(MemoryUpdate(previous: old, note: updated))
                        }
                    } else {
                        var added = note; added.previousText = nil; answer.rememberedNotes.append(added)
                    }
                }
                answer.usedMemoryIDs = usedMemoryIDs.sorted { $0.uuidString < $1.uuidString }
                return answer
            }
            guard Set(calls.map(\.id)).count == calls.count,
                  calls.allSatisfy({ !$0.id.isEmpty && $0.type == "function" }) else { throw YubaiError.invalid("云端工具调用格式无效。") }
            conversation.append(clean(reply))
            var currentResults: [String: JSONValue] = [:]; var repeated = false
            for call in calls {
                try Task.checkCancellation()
                let args = try? JSONValue.parse(call.function.arguments)
                let normalized = args.flatMap { try? $0.jsonText() } ?? call.function.arguments.trimmingCharacters(in: .whitespacesAndNewlines)
                let key = call.function.name + "\n" + normalized
                trace.append(AssistantToolTrace(name: call.function.name, args: args.map { redactor.value($0) } ?? .null))
                let result: JSONValue
                if let cached = rememberedResults[key] ?? previousResults[key] { result = cached; repeated = true }
                else {
                    do {
                        guard let tool = tools.first(where: { $0.name == call.function.name }) else { throw YubaiError.invalid("没有这个工具，请使用已声明的工具。") }
                        guard let args, args.objectValue != nil else { throw YubaiError.invalid("参数不是有效JSON对象，请按工具结构重试。") }
                        if let chartTool = tool as? ShowChartTool {
                            guard chart == nil else { throw YubaiError.invalid("每个答复只能展示一张图。") }
                            let built = try chartTool.build(args, context); chart = built.chart; result = built.result
                        } else if let purchaseTool = tool as? JudgePurchaseTool {
                            let purchase = try purchaseTool.judge(args, current); judgment = purchase; result = purchase.facts
                            usedMemoryIDs.formUnion(purchase.usedMemoryIDs)
                        } else if let memoryTool = tool as? MemoryTool {
                            if memoryTool == .remember {
                                let note = try memoryTool.note(args, current)
                                if let i = memoryLedger.memories.firstIndex(where: { $0.id == note.id }) { memoryLedger.memories[i] = note }
                                else { memoryLedger.memories.append(note) }
                                previousResults.removeAll(); currentResults.removeAll()
                                current = ToolContext(ledger: memoryLedger, now: context.now, confirmedEntryAmount: context.confirmedEntryAmount,
                                    parsedEntryAmounts: context.parsedEntryAmounts, parsedEntries: context.parsedEntries, entryAccountHint: context.entryAccountHint, memoryCharacterBudget: context.memoryCharacterBudget)
                                result = redactor.value(.object(["remembered": Memory.row(note, now: context.now)]))
                                rememberedResults[key] = result
                            } else {
                                let notes = try memoryTool.matches(args, current)
                                usedMemoryIDs.formUnion(notes.map(\.id))
                                result = redactor.value(.object(["memories": .array(notes.map { Memory.row($0, now: context.now) })]))
                            }
                        } else if let proposalTool = tool as? ProposalTool {
                            let change = try proposalTool.propose(args, context)
                            result = proposalTool.result(change, context); proposed.append(change)
                        } else { result = redactor.value(try tool.run(args, current)) }
                    } catch {
                        // Only local validation messages may be echoed; arbitrary errors may contain data.
                        let message = (error as? YubaiError)?.localizedDescription ?? "工具未能完成，请检查参数后重试。"
                        result = .object(["error": .object(["message": .string(redactor.text(message)), "retryable": .bool(true)])])
                    }
                }
                currentResults[key] = result
                results.append(result)
                for id in Self.evidence(in: result) where ledgerIDs.contains(id) && !evidence.contains(id) { evidence.append(id) }
                conversation.append(ChatMessage(role: .tool, content: try result.jsonText(), toolCallID: call.id))
            }
            previousResults = currentResults
            if repeated { conversation.append(ChatMessage(role: .system, content: "这个调用刚执行过，结果相同；请换个查询或直接回答")) }
        }
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

public enum AssistantContextBudget {
    public static let defaultLimit = 120_000
    static let historyNote = "更早的对话已省略"
    static let summaryPrefix = "前情摘要："
    static func count(_ messages: [ChatMessage]) -> Int {
        messages.reduce(0) { total, message in
            let calls = (message.toolCalls ?? []).reduce(0) { $0 + $1.id.count + $1.function.name.count + $1.function.arguments.count }
            return total + (message.content?.count ?? 0) + (message.toolCallID?.count ?? 0) + calls
        }
    }
    private static func toolNote(_ message: ChatMessage, call: ChatToolCall?) -> String {
        func scalar(_ value: JSONValue) -> String? {
            switch value {
            case .string(let text): return String(text.prefix(48))
            case .number, .bool: return try? value.jsonText()
            default: return nil
            }
        }
        func facts(_ value: JSONValue, prefix: String = "") -> [String] {
            guard let fields = value.objectValue else { return [] }
            let preferred = ["count", "total", "sum", "amount", "from", "to", "start", "end", "range"]
            let keys = preferred.filter { fields[$0] != nil } + fields.keys.filter { !preferred.contains($0) }.sorted()
            return keys.flatMap { key -> [String] in
                let item = fields[key]!
                if let text = scalar(item) { return [prefix + key + "=" + text] }
                if let rows = item.arrayValue { return [prefix + key + "条数=" + String(rows.count)] }
                if prefix.isEmpty { return facts(item, prefix: key + ".") }
                return []
            }
        }
        let arguments = call.map { String($0.function.arguments.prefix(60)) } ?? "{}"
        let result = message.content.flatMap { try? JSONValue.parse($0) }.map { facts($0).joined(separator: "，") } ?? ""
        let text = (call?.function.name ?? "工具") + " 参数=" + arguments + "；" + result
        return String(text.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ").prefix(184)) + "；需要细节请重新查询"
    }
    static func compactTools(_ messages: inout [ChatMessage], limit: Int) {
        var size = count(messages)
        guard size > limit else { return }
        let target = max(0, limit * 3 / 5)
        let recent = messages.lastIndex { $0.role == .assistant && !($0.toolCalls?.isEmpty ?? true) } ?? messages.endIndex
        var calls: [String: ChatToolCall] = [:]
        for i in messages.indices where i < recent {
            for call in messages[i].toolCalls ?? [] { calls[call.id] = call }
            guard size > target else { break }
            guard messages[i].role == .tool, let content = messages[i].content,
                  !content.hasSuffix("；需要细节请重新查询") else { continue }
            let note = toolNote(messages[i], call: messages[i].toolCallID.flatMap { calls[$0] })
            guard note.count < content.count else { continue }
            size -= content.count - note.count; messages[i].content = note
        }
    }
    static func historySlice(_ messages: [ChatMessage], limit: Int, reserving: Int) -> (remaining: [ChatMessage], removed: [ChatMessage], summaryBudget: Int)? {
        guard count(messages) + reserving > limit else { return nil }
        let first = messages.first?.role == .system ? 1 : 0
        let target = max(0, (limit - reserving) * 3 / 5)
        let summaryBudget = min(1600, max(32, target / 10))
        var size = count(messages) - count(Array(messages.prefix(first)))
        var end = first
        while size + summaryBudget > target {
            guard end + 1 < messages.count, messages[end].role == .user, messages[end + 1].role == .assistant else { break }
            size -= count(Array(messages[end...(end + 1)])); end += 2
        }
        guard end > first else { return nil }
        return (Array(messages.dropFirst(end)), Array(messages.prefix(end)), summaryBudget)
    }
}

/// A conservative text heuristic, not a semantic proof. Dates, times, UUIDs, percentages and
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
        for pattern in [
            #"(?<!\d)\d{4}[-/]\d{1,2}[-/]\d{1,2}(?!\d)"#,
            #"(?<!\d)(?:\d{4}年)?\d{1,2}月\d{1,2}日(?!\d)"#,
            #"(?<!\d)\d{1,2}[:：]\d{2}(?:[:：]\d{2})?(?!\d)"#,
            #"(?<![0-9a-fA-F])[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}(?![0-9a-fA-F])"#
        ] {
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
