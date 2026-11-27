import Foundation

public enum PurchaseVerdict: String, Codable, CaseIterable, Hashable, Sendable {
    case buy, wait, skip
    public var label: String { switch self { case .buy: "买吧"; case .wait: "等等再说"; case .skip: "先别买" } }
}
public enum PurchaseNeed: String, Codable, Sendable { case need, want, unclear }
public struct PurchaseBounds: Equatable, Sendable {
    public let allowedVerdicts: Set<PurchaseVerdict>
    public let boundReason: String
    public static func compute(ledger: Ledger, amount: Int64, title: String, category: String? = nil, subcategory: String? = nil, now: Date = Dates.now) -> PurchaseBounds {
        let funds = Finance.funds(ledger, now: now)
        let after = funds.spendable.rawR - amount
        var sample = Entry(date: now, amount: amount, accountID: UUID(), title: title, category: category ?? Classification.pendingCategory)
        sample.subcategory = subcategory
        let summary = ledger.spendingParts.isEmpty ? nil : SpendingParts.summary(ledger, now: now)
        let balance = SpendingParts.part(for: sample, in: ledger).flatMap { part in summary?.parts.first { $0.id == part.id } }
        func number(_ amount: Int64) -> String {
            let text = Money.text(amount, currency: false)
            return text.hasSuffix(".00") ? String(text.dropLast(3)) : text
        }
        let partReason = balance.map { value in
            value.part.name + "这月还剩 " + number(value.remaining) + "，这笔 " + number(amount) +
                (amount > value.remaining ? " 会用掉没分的 " + number(amount - value.remaining) : "") + "。"
        } ?? ""

        if after + funds.spendable.plannedSaving < 0 {
            return PurchaseBounds(allowedVerdicts: [.skip], boundReason: partReason + "买了以后，会回来的账单还差 \(Money.text(-after - funds.spendable.plannedSaving))。")
        }
        if after < 0 {
            return PurchaseBounds(allowedVerdicts: [.wait, .skip], boundReason: partReason + "买了以后，这个月少攒 \(Money.text(min(funds.spendable.plannedSaving, -after)))。")
        }
        let areas = Set(ledger.profile.restrain.filter { ButlerCards.matches($0, entry: sample, ledger: ledger) }.map(\.id))
        for line in SoftLines.usage(ledger, now: now) where areas.contains(line.areaID) {
            let used = line.used + (line.mode == .count ? (amount > 0 ? 1 : 0) : amount)
            if used > line.limit {
                let fact = line.mode == .count ? "\(line.used) 次，每期最多 \(line.limit) 次" : Money.text(line.used) + "，每期最多 " + Money.text(line.limit)
                return PurchaseBounds(allowedVerdicts: [.wait, .skip], boundReason: partReason + "\(line.title)这个周期已有 \(fact)。")
            }
        }
        if let balance, amount > balance.remaining {
            return PurchaseBounds(allowedVerdicts: [.wait, .skip], boundReason: partReason)
        }
        return PurchaseBounds(allowedVerdicts: Set(PurchaseVerdict.allCases), boundReason: partReason + "买了以后还能花 \(Money.text(after))。")
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
    public let description = "在judge_purchase给定的allowed_verdicts中提交结论。reason只写一句（不超过60字，不含句号、分号或换行），必须含有以下之一：bound_reason里的金额原文（如「买了以后还能花 ¥1,234.00」）、habit里的次数、用户原话中连续4个字、心愿单回答。引用记忆用memory_ids。"
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
        let submitted = raw.trimmingCharacters(in: .whitespacesAndNewlines)
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
        func sharesPhrase(_ source: String, _ reason: String) -> Bool {
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
            let usage = area.periodUsage(in: context.ledger, now: context.now)
            return [String(usage.count)] + (area.softLimit?.periodCount.map { [String($0)] } ?? [])
        }
        let countPattern = try NSRegularExpression(pattern: #"(\d+)\s*(?:次|笔)"#)
        let followups = judgment.facts["similar_followups"]?.arrayValue ?? []
        func grounded(_ reason: String) -> Bool {
            let countMatches = countPattern.matches(in: reason, range: NSRange(reason.startIndex..., in: reason))
            let nsReason = reason as NSString
            let countsGrounded = countMatches.allSatisfy { match in
                let number = nsReason.substring(with: match.range(at: 1))
                return allowedCountTexts.contains(number) || quotes.contains { $0.contains(nsReason.substring(with: match.range)) }
            }
            let groundedNumber = countsGrounded && reason.range(of: #"[¥￥]\s*-?\d|\d+(?:\.\d+)?\s*(?:元|次|笔)"#, options: .regularExpression) != nil
                && AssistantAmountGuard.unverified(in: reason, results: [judgment.facts]).isEmpty
            // The approved part sentence has bare numbers. Accept that exact local
            // fact without requiring the model to add a currency symbol or prose.
            let groundedPart = judgment.facts["spending_part"] != nil &&
                reason.trimmingCharacters(in: CharacterSet(charactersIn: "。")) == bounds.boundReason.components(separatedBy: "。").first
            let groundedFollowup = followups.contains { row in
                guard let title = row["title"]?.stringValue, let answer = row["answer"]?.stringValue else { return false }
                return reason.contains(title) && reason.contains(answer)
            }
            return groundedNumber || groundedPart || quotes.contains { sharesPhrase($0, reason) } || groundedFollowup
        }
        // A rejected reason costs another full round trip. Keep the model's first
        // grounded sentence; otherwise state the local bound instead of asking again.
        let candidates = [submitted, Self.firstSentence(submitted)] + [Self.firstSentence(bounds.boundReason)]
        guard let reason = candidates.first(where: { Self.isOneSentence($0) && grounded($0) }) else {
            throw YubaiError.invalid("理由需要引用一个具体事实，例如买后还能花、已发生的次数、用户原话或心愿单回答。")
        }
        return SubmittedPurchaseVerdict(verdict: verdict, reason: reason, need: need, boundReason: bounds.boundReason, usedMemoryIDs: ids)
    }
    static func isOneSentence(_ reason: String) -> Bool {
        let sentence = reason.replacingOccurrences(of: #"(?<=\d)\.(?=\d)"#, with: "", options: .regularExpression).trimmingCharacters(in: CharacterSet(charactersIn: "。.!！?？"))
        return !reason.isEmpty && reason.count <= 60 && !sentence.contains(where: { "。.!！?？\n\r；;".contains($0) })
    }
    static func firstSentence(_ text: String) -> String {
        let masked = text.replacingOccurrences(of: #"(?<=\d)\.(?=\d)"#, with: "\u{0}", options: .regularExpression)
        let head = masked.split(whereSeparator: { "。.!！?？\n\r；;".contains($0) }).first.map(String.init) ?? ""
        return head.replacingOccurrences(of: "\u{0}", with: ".").trimmingCharacters(in: .whitespacesAndNewlines)
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
    public static func current(ledger: Ledger, now: Date = Dates.now) -> [RestrainProgress] {
        ledger.profile.restrain.compactMap { area in
            guard let line = area.softLimit, line.periodCount != nil || line.periodAmount != nil else { return nil }
            let usage = area.periodUsage(in: ledger, now: now)
            func ratio(_ value: Double, _ limit: Double) -> Double { limit == 0 ? (value > 0 ? .infinity : 0) : value / limit }
            let ratios = [line.periodCount.map { ratio(Double(usage.count), Double($0)) }, line.periodAmount.map { ratio(Double(usage.amount), Double($0)) }].compactMap { $0 }
            let value = ratios.max() ?? 0
            return RestrainProgress(areaID: area.id, title: area.title, weekCount: usage.count, perWeekCount: line.periodCount,
                monthAmount: usage.amount, perMonthAmount: line.periodAmount, ratio: value, status: value > 1 ? .over : value >= 0.8 ? .near : .normal)
        }
    }
}
