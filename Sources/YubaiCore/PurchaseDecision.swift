import Foundation

public enum PurchaseVerdict: String, Codable, CaseIterable, Hashable, Sendable {
    case buy, wait, skip
    public var label: String { switch self { case .buy: "买吧"; case .wait: "等等再说"; case .skip: "先别买" } }
}
public enum PurchaseNeed: String, Codable, Sendable { case need, want, unclear }
public struct PurchaseBounds: Equatable, Sendable {
    public let allowedVerdicts: Set<PurchaseVerdict>
    public let boundReason: String
    public static func compute(ledger: Ledger, amount: Int64, title: String, category: String? = nil, subcategory: String? = nil, now: Date = Date()) -> PurchaseBounds {
        let funds = Finance.funds(ledger, now: now)
        let after = funds.available - amount
        if funds.liquidNow - funds.dueRest - amount < 0 {
            return PurchaseBounds(allowedVerdicts: [.skip], boundReason: "买了以后，会回来的账单还差 \(Money.text(amount + funds.dueRest - funds.liquidNow))。")
        }
        if after < 0 {
            return PurchaseBounds(allowedVerdicts: [.wait, .skip], boundReason: "买了以后，这个月少攒 \(Money.text(min(funds.savingTarget, -after)))。")
        }
        var sample = Entry(date: now, amount: amount, accountID: UUID(), title: title, category: category ?? Classification.pendingCategory); sample.subcategory = subcategory
        for area in ledger.profile.restrain where ButlerCards.matches(area, entry: sample, ledger: ledger) {
            let usage = area.usage(in: ledger, now: now)
            if let count = area.softLimit?.perWeekCount, usage.weekCount >= count {
                return PurchaseBounds(allowedVerdicts: [.wait, .skip], boundReason: "\(area.title)本周已有 \(usage.weekCount) 次，你写的每周最多 \(count) 次。")
            }
            if let limit = area.softLimit?.perMonthAmount, usage.monthAmount + amount > limit {
                return PurchaseBounds(allowedVerdicts: [.wait, .skip], boundReason: "\(area.title)本月已花 \(Money.text(usage.monthAmount))，加这笔会超过你写的 \(Money.text(limit))。")
            }
        }
        return PurchaseBounds(allowedVerdicts: Set(PurchaseVerdict.allCases), boundReason: "买了以后还能花 \(Money.text(after))。")
    }
}
public struct SubmittedPurchaseVerdict: Equatable, Sendable {
    public let verdict: PurchaseVerdict
    public let reason: String
    public let need: PurchaseNeed
    public let boundReason: String
    public let usedMemoryIDs: [UUID]
    public init(verdict: PurchaseVerdict, reason: String, need: PurchaseNeed, boundReason: String, usedMemoryIDs: [UUID] = []) {
        self.verdict = verdict; self.reason = reason; self.need = need; self.boundReason = boundReason; self.usedMemoryIDs = usedMemoryIDs
    }
}
public struct PurchaseQuestion: Equatable, Sendable {
    public let text: String
    public let options: [String]
    public init(text: String, options: [String]) { self.text = text; self.options = options }
}
public struct SubmitVerdictTool: AssistantTool {
    public init() {}
    public let name = "submit_verdict"
    public let description = "在judge_purchase给定的allowed_verdicts中提交结论。reason为一句不超过60字的话，指向钱、习惯、用户原话或心愿单回答中的具体事实。引用记忆用memory_ids。"
    public var parameters: JSONValue { .object(["type": .string("object"), "properties": .object([
        "verdict": .object(["type": .string("string"), "enum": .strings(PurchaseVerdict.allCases.map(\.rawValue))]),
        "reason": .object(["type": .string("string"), "maxLength": .number(60)]),
        "need": .object(["type": .string("string"), "enum": .strings(["need", "want", "unclear"])]),
        "memory_ids": .object(["type": .string("array"), "items": .object(["type": .string("string")])])]),
        "required": .strings(["verdict", "reason", "need"]), "additionalProperties": .bool(false)]) }
    public func run(_ args: JSONValue, _ ctx: ToolContext) throws -> JSONValue { throw YubaiError.invalid("请先调用judge_purchase，再提交本次结论。") }
    public func submit(_ args: JSONValue, judgment: PurchaseJudgment, context: ToolContext, userFacts: [String] = []) throws -> SubmittedPurchaseVerdict {
        guard let fields = args.objectValue, Set(fields.keys).isSubset(of: ["verdict", "reason", "need", "memory_ids"]),
              let verdict = args["verdict"]?.stringValue.flatMap(PurchaseVerdict.init(rawValue:)),
              let need = args["need"]?.stringValue.flatMap(PurchaseNeed.init(rawValue:)),
              let raw = args["reason"]?.stringValue else { throw YubaiError.invalid("请提供verdict、reason和need。") }
        let bounds = PurchaseBounds.compute(ledger: context.ledger, amount: judgment.amount, title: judgment.title, category: judgment.category, subcategory: judgment.subcategory, now: context.now)
        guard bounds.allowedVerdicts.contains(verdict) else { throw YubaiError.invalid("这个结论不在allowed_verdicts中，请重选：\(PurchaseVerdict.allCases.filter { bounds.allowedVerdicts.contains($0) }.map(\.rawValue).joined(separator: "、"))。\(bounds.boundReason)") }
        let reason = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let sentence = reason.replacingOccurrences(of: #"(?<=\d)\.(?=\d)"#, with: "", options: .regularExpression).trimmingCharacters(in: CharacterSet(charactersIn: "。.!！?？"))
        guard !reason.isEmpty, reason.count <= 60, !sentence.contains(where: { "。.!！?？\n\r；;".contains($0) }) else { throw YubaiError.invalid("理由请用一句不超过60字的话。") }
        var ids: [UUID] = []
        if let value = fields["memory_ids"] {
            guard let rows = value.arrayValue else { throw YubaiError.invalid("memory_ids需要是列表。") }
            for row in rows {
                guard let id = row.stringValue.flatMap(UUID.init(uuidString:)), context.ledger.memories.contains(where: { $0.id == id }), !ids.contains(id) else { throw YubaiError.invalid("引用的记忆不存在或重复。") }
                ids.append(id)
            }
        }
        let notes = context.ledger.memories.filter { ids.contains($0.id) }
        let quotes = context.ledger.profile.principles + (context.ledger.profile.generous + context.ledger.profile.restrain).map(\.note) + notes.map(\.text) + userFacts
        func sharesPhrase(_ source: String) -> Bool {
            let chars = Array(source)
            guard chars.count >= 4 else { return false }
            return (0...(chars.count - 4)).contains { offset in
                let phrase = String(chars[offset..<(offset + 4)])
                return phrase.allSatisfy { $0.isLetter || $0.isNumber } && reason.contains(phrase)
            }
        }
        // A structural grounding check: numbers must come from tool facts, or the
        // sentence must quote a concrete phrase from an attributed source.
        let allowedCountTexts = [judgment.facts["habit"]?["count"], judgment.facts["habit"]?["last_year"]?["count"]].compactMap { $0 }.compactMap { value -> String? in
            if case .number(let count) = value, let count = Int(exactly: count) { return String(count) }
            return nil
        } + context.ledger.profile.restrain.flatMap { area -> [String] in
            let usage = area.usage(in: context.ledger, now: context.now)
            return [String(usage.weekCount)] + (area.softLimit?.perWeekCount.map { [String($0)] } ?? [])
        }
        let countPattern = try NSRegularExpression(pattern: #"(\d+)\s*(?:次|笔)"#)
        let countMatches = countPattern.matches(in: reason, range: NSRange(reason.startIndex..., in: reason))
        let nsReason = reason as NSString
        let countsGrounded = countMatches.allSatisfy { match in
            let number = nsReason.substring(with: match.range(at: 1))
            return allowedCountTexts.contains(number) || quotes.contains { $0.contains(nsReason.substring(with: match.range)) }
        }
        let groundedNumber = countsGrounded && reason.range(of: #"[¥￥]\s*-?\d|\d+(?:\.\d+)?\s*(?:元|次|笔)"#, options: .regularExpression) != nil
            && AssistantAmountGuard.unverified(in: reason, results: [judgment.facts]).isEmpty
        let followups = judgment.facts["similar_followups"]?.arrayValue ?? []
        let groundedFollowup = followups.contains { row in
            guard let title = row["title"]?.stringValue, let answer = row["answer"]?.stringValue else { return false }
            return reason.contains(title) && reason.contains(answer)
        }
        guard groundedNumber || quotes.contains(where: sharesPhrase) || groundedFollowup else { throw YubaiError.invalid("理由需要引用一个具体事实，例如买后还能花、已发生的次数、用户原话或心愿单回答。") }
        return SubmittedPurchaseVerdict(verdict: verdict, reason: reason, need: need, boundReason: bounds.boundReason, usedMemoryIDs: ids)
    }
}
public struct AskPurchaseQuestionsTool: AssistantTool {
    public init() {}
    public let name = "ask_purchase_questions"
    public let description = "需求不清楚时问1至3题，每题2至3个短选项。围绕使用频率、现有替代、先试先借或反复出现的问题。调用后本轮结束，等待用户回答；直接给结论或记忆足够时跳过。"
    public var parameters: JSONValue { .object(["type": .string("object"), "properties": .object([
        "questions": .object(["type": .string("array"), "minItems": .number(1), "maxItems": .number(3), "items": .object([
            "type": .string("object"), "properties": .object(["text": .object(["type": .string("string"), "maxLength": .number(80)]),
                "options": .object(["type": .string("array"), "minItems": .number(2), "maxItems": .number(3), "items": .object(["type": .string("string"), "maxLength": .number(20)])])]),
            "required": .strings(["text", "options"]), "additionalProperties": .bool(false)])])]), "required": .strings(["questions"]), "additionalProperties": .bool(false)]) }
    public func questions(_ args: JSONValue) throws -> [PurchaseQuestion] {
        guard let root = args.objectValue, Set(root.keys) == ["questions"], let values = args["questions"]?.arrayValue, (1...3).contains(values.count) else { throw YubaiError.invalid("请提供1至3道购买问题。") }
        return try values.map { row in
            guard let fields = row.objectValue, Set(fields.keys) == ["text", "options"], let text = row["text"]?.stringValue,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.count <= 80, !text.contains("\n"),
                  let values = row["options"]?.arrayValue, (2...3).contains(values.count) else { throw YubaiError.invalid("每题需要简短题目和2至3个选项。") }
            let options = values.compactMap(\.stringValue)
            guard options.count == values.count, Set(options).count == options.count, options.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= 20 && !$0.contains("\n") }) else { throw YubaiError.invalid("选项需要2至3个不重复的短句。") }
            return PurchaseQuestion(text: text, options: options)
        }
    }
    public func run(_ args: JSONValue, _ ctx: ToolContext) throws -> JSONValue {
        .object(["questions": .array(try questions(args).map { .object(["text": .string($0.text), "options": .strings($0.options)]) }), "awaiting_answer": .bool(true)])
    }
}
public struct RestrainProgress: Equatable, Identifiable, Sendable {
    public enum Status: String, Sendable { case normal, near, over }
    public let areaID: UUID
    public var id: UUID { areaID }
    public let title: String
    public let weekCount: Int
    public let perWeekCount: Int?
    public let monthAmount: Int64
    public let perMonthAmount: Int64?
    public let ratio: Double
    public let status: Status
    public static func current(ledger: Ledger, now: Date = Date()) -> [RestrainProgress] {
        ledger.profile.restrain.compactMap { area in
            guard let line = area.softLimit, line.perWeekCount != nil || line.perMonthAmount != nil else { return nil }
            let usage = area.usage(in: ledger, now: now)
            func ratio(_ value: Double, _ limit: Double) -> Double { limit == 0 ? (value > 0 ? .infinity : 0) : value / limit }
            let ratios = [line.perWeekCount.map { ratio(Double(usage.weekCount), Double($0)) }, line.perMonthAmount.map { ratio(Double(usage.monthAmount), Double($0)) }].compactMap { $0 }
            let value = ratios.max() ?? 0
            return RestrainProgress(areaID: area.id, title: area.title, weekCount: usage.weekCount, perWeekCount: line.perWeekCount,
                monthAmount: usage.monthAmount, perMonthAmount: line.perMonthAmount, ratio: value, status: value > 1 ? .over : value >= 0.8 ? .near : .normal)
        }
    }
}
