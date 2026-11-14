import Foundation

public enum ButlerTextPiece: Codable, Equatable, Sendable {
    case text(String), count, sum
}
public enum ButlerSuggestionAction: Codable, Equatable, Sendable {
    case stopSubscription(UUID), setBudget(category: String, cents: Int64), tryTwoWeeks(String)
    case saveLeftover(String), addWish(title: String, cents: Int64), neverMention
    public var title: String {
        switch self {
        case .stopSubscription: "停掉"
        case .setBudget: "定预算"
        case .tryTwoWeeks: "试两周"
        case .saveLeftover: "存起来"
        case .addWish: "加进心愿单"
        case .neverMention: "不再提"
        }
    }
}
public struct ButlerSuggestion: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public let topic: String
    public let observation: [ButlerTextPiece]
    public let proposal: [ButlerTextPiece]
    public let entryIDs: [UUID]
    public let count: Int
    public let sumCents: Int64
    public let action: ButlerSuggestionAction
    public let memoryIDs: [UUID]
    public let createdAt: Date
    public var answeredAt: Date?
    public func text(_ pieces: [ButlerTextPiece], hidden: Bool = false) -> String {
        pieces.map { piece in
            switch piece {
            case .text(let value): return HomeButler.privacyText(value, hidden: hidden)
            case .count: return String(count)
            case .sum: return hidden ? "••••" : Money.text(sumCents, currency: false)
            }
        }.joined()
    }
    public var taskID: String { "suggestion:" + id.uuidString }
}
public struct ButlerReview: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let suggestion: ButlerSuggestion
    public let dueAt: Date
    public var answeredAt: Date?
    public var taskID: String { "suggestion-review:" + id.uuidString }
}
public struct ButlerAIState: Codable, Equatable, Sendable {
    public var lastRunAt: Date?
    public var weeklyAt: Date?
    public var paydayRuns: [String: Date] = [:]
    public var spikeRuns: [String: Date] = [:]
    public var activeSpikes: Set<String> = []
    public var suggestions: [ButlerSuggestion] = []
    public var reviews: [ButlerReview] = []
    public init() {}
}

public enum ButlerSuggestionVerifier {
    public static let instruction = """
    同时读butler_digest，结合消费观和记忆提出可执行建议。不能从统计猜测生活事实、加班或用户意愿；这些判断必须有引用记忆支持。零条或多条都可以，不设条数目标。
    摘要的星期数字采用：1=周日，2=周一，3=周二，4=周三，5=周四，6=周五，7=周六。
    suggestions每项严格为 {"topic":"稳定的主题键","observation":[{"text":"外卖 "},{"count":true},{"text":" 次，共 "},{"sum":true}],"proposal":[{"text":"试试带饭？"}],"entry_ids":["摘要中的ID"],"claimed_count":1,"claimed_sum_cents":2800,"action":{"kind":"try_two_weeks","review":"带饭怎么样？"},"memory_ids":["用到的记忆ID"]}。
    text片段除「周三」「星期三」这类星期名称外不能有数字，笔数和金额只能用count或sum片段，数值由代码填。claimed_sum_cents必须是所引账目的净支出分整数精确和；不估计。每条必须有原账ID，不能引用摘要之外的ID。
    action只能选一种，且只能带下列指定参数：stop_subscription/plan_id（已有订阅ID）；set_budget/category/amount_cents（已有支出分类和分整数）；try_two_weeks/review（一句两周后问的话）；save_leftover/cycle_start（摘要中可存结余的周期）；add_wish/title/amount_cents；never_mention（无参数）。不建议未知金额，不进行真实付款。
    不再提mutedTopics中的主题。用户的回答是记忆事实，遵守纠正，不重复劝说。返回纯JSON，不要Markdown或额外字段。
    """

    /// Invalid individual suggestions are discarded, while valid siblings survive.
    public static func parse(_ rows: JSONValue, digest: ButlerDigest, ledger: Ledger, now: Date) -> [ButlerSuggestion] {
        guard let rows = rows.arrayValue else { return [] }
        var topics = Set<String>()
        return rows.compactMap { row in
            guard keys(row, ["topic", "observation", "proposal", "entry_ids", "claimed_count", "claimed_sum_cents", "action", "memory_ids"]),
                  let topic = row["topic"]?.stringValue, validText(topic, limit: 120),
                  let observation = pieces(row["observation"]), let proposal = pieces(row["proposal"]),
                  observation.contains(.count), observation.contains(.sum),
                  let ids = ids(row["entry_ids"]), !ids.isEmpty, Set(ids).isSubset(of: digest.candidateIDs),
                  let count = integer(row["claimed_count"]), let sum = integer(row["claimed_sum_cents"]),
                  let memories = Self.ids(row["memory_ids"]), let action = action(row["action"], ledger: ledger, now: now) else { return nil }
            let value = ButlerSuggestion(id: UUID(), topic: topic, observation: observation, proposal: proposal, entryIDs: ids,
                count: Int(count), sumCents: sum, action: action, memoryIDs: memories, createdAt: now)
            guard verify(value, in: ledger, now: now), topics.insert(topic).inserted else { return nil }
            return value
        }
    }
    public static func verify(_ value: ButlerSuggestion, in ledger: Ledger, now: Date) -> Bool {
        guard value.count > 0, value.count == value.entryIDs.count, Set(value.entryIDs).count == value.count,
              !ledger.mutedTopics.contains("ai:" + value.topic),
              Set(value.memoryIDs).count == value.memoryIDs.count,
              Set(value.memoryIDs).isSubset(of: Set(ledger.memories.map(\.id))),
              actionIsCurrent(value.action, ledger: ledger, now: now) else { return false }
        let byID = Dictionary(uniqueKeysWithValues: ledger.activeEntries.map { ($0.id, $0) })
        var sum: Int64 = 0
        for id in value.entryIDs {
            guard let row = byID[id], row.date <= now, row.date <= value.createdAt,
                  row.date >= Dates.addDays(-27, to: Dates.day(value.createdAt)),
                  row.nature == .expense || row.nature == .refund else { return false }
            let result = sum.addingReportingOverflow(Finance.spendingAmount(row, ledger: ledger))
            guard !result.overflow else { return false }; sum = result.partialValue
        }
        return sum == value.sumCents && sum > 0
    }
    static func keys(_ row: JSONValue, _ expected: [String]) -> Bool { Set(row.objectValue?.keys.map { $0 } ?? []) == Set(expected) }
    static func integer(_ value: JSONValue?) -> Int64? {
        guard case .number(let raw) = value, raw.isFinite, raw.rounded() == raw,
              abs(raw) <= 9_007_199_254_740_991 else { return nil }
        return Int64(raw)
    }
    static func validText(_ text: String, limit: Int = 200) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && text.count <= limit && !text.contains(where: { $0.isNewline })
    }
    private static func ids(_ row: JSONValue?) -> [UUID]? {
        guard let rows = row?.arrayValue else { return nil }
        let ids = rows.compactMap { $0.stringValue.flatMap(UUID.init(uuidString:)) }
        return ids.count == rows.count && Set(ids).count == ids.count ? ids : nil
    }
    private static func pieces(_ value: JSONValue?) -> [ButlerTextPiece]? {
        guard let rows = value?.arrayValue, !rows.isEmpty else { return nil }
        var result: [ButlerTextPiece] = []
        for row in rows {
            if keys(row, ["text"]), let text = row["text"]?.stringValue, validText(text), !hasUnverifiedNumber(text) { result.append(.text(text)) }
            else if keys(row, ["count"]), row["count"] == .bool(true) { result.append(.count) }
            else if keys(row, ["sum"]), row["sum"] == .bool(true) { result.append(.sum) }
            else { return nil }
        }
        return result.count <= 40 ? result : nil
    }
    private static func hasUnverifiedNumber(_ text: String) -> Bool {
        // Swift treats 三/四 as numbers too. Weekday names are observations from
        // the digest, while monetary/count claims still require typed slots.
        text.replacingOccurrences(of: #"(?:周|星期)[一二三四五六日天]"#, with: "", options: .regularExpression).contains(where: { $0.isNumber })
    }
    private static func action(_ row: JSONValue?, ledger: Ledger, now: Date) -> ButlerSuggestionAction? {
        guard let row, let kind = row["kind"]?.stringValue else { return nil }
        let value: ButlerSuggestionAction
        switch kind {
        case "stop_subscription":
            guard keys(row, ["kind", "plan_id"]), let id = row["plan_id"]?.stringValue.flatMap(UUID.init(uuidString:)) else { return nil }; value = .stopSubscription(id)
        case "set_budget":
            guard keys(row, ["kind", "category", "amount_cents"]), let category = row["category"]?.stringValue, let cents = integer(row["amount_cents"]) else { return nil }; value = .setBudget(category: category, cents: cents)
        case "try_two_weeks":
            guard keys(row, ["kind", "review"]), let review = row["review"]?.stringValue, validText(review) else { return nil }; value = .tryTwoWeeks(review)
        case "save_leftover":
            guard keys(row, ["kind", "cycle_start"]), let start = row["cycle_start"]?.stringValue else { return nil }; value = .saveLeftover(start)
        case "add_wish":
            guard keys(row, ["kind", "title", "amount_cents"]), let title = row["title"]?.stringValue, validText(title, limit: 100), let cents = integer(row["amount_cents"]) else { return nil }; value = .addWish(title: title, cents: cents)
        case "never_mention": guard keys(row, ["kind"]) else { return nil }; value = .neverMention
        default: return nil
        }
        return actionIsCurrent(value, ledger: ledger, now: now) ? value : nil
    }
    static func actionIsCurrent(_ action: ButlerSuggestionAction, ledger: Ledger, now: Date) -> Bool {
        switch action {
        case .stopSubscription(let id): return ledger.plans.contains { $0.id == id && $0.active && $0.stoppedAt == nil && !$0.inflow && $0.nature == .expense && $0.frequency != .once && ($0.category.contains("订阅") || $0.title.contains("会员") || BrandIcons.match($0.title) != nil) }
        case .setBudget(let category, let cents): return cents > 0 && cents <= Money.limit && ledger.categories.contains { $0.name == category && !$0.income && !$0.system } && ledger.partsMode == .amount
        case .saveLeftover(let start): return Savings.pendingLeftover(in: ledger).map { Dates.text($0.cycleStart) == start } == true
        case .addWish(let title, let cents): return validText(title, limit: 100) && cents > 0 && cents <= Money.limit
        case .tryTwoWeeks(let text): return validText(text)
        case .neverMention: return true
        }
    }
}

public enum ButlerSuggestionAnswer: Equatable, Sendable { case accept, never, incorrect(String) }
public enum ButlerSuggestions {
    public static func queued(_ ledger: Ledger, now: Date) -> [ButlerSuggestion] {
        guard ledger.preferences.butlerSuggestionsEnabled == true, ledger.preferences.cloudAIEnabled else { return [] }
        return (ledger.butlerAI?.suggestions ?? []).filter { $0.answeredAt == nil && ButlerSuggestionVerifier.verify($0, in: ledger, now: now) }
    }
    /// Revalidates at the moment of tapping; never executes model-supplied code.
    public static func answer(_ id: UUID, _ answer: ButlerSuggestionAnswer, in ledger: inout Ledger, now: Date) throws {
        guard let index = ledger.butlerAI?.suggestions.firstIndex(where: { $0.id == id && $0.answeredAt == nil }),
              let value = ledger.butlerAI?.suggestions[index], ButlerSuggestionVerifier.verify(value, in: ledger, now: now) else { throw YubaiError.invalid("这条建议的依据已经变了。") }
        var next = ledger
        var response: String
        var correction: String?
        switch answer {
        case .accept:
            response = value.action.title
            switch value.action {
            case .stopSubscription(let id):
                var change = ChangeSet(source: "用户操作", reason: "停掉", items: [.endPlan(id, now)]); change.createdAt = now
                try change.apply(to: &next); ButlerSavings.synchronize(&next, now: now)
            case .setBudget(let category, let cents):
                if let i = next.spendingParts.firstIndex(where: { $0.categories == [category] }) { next.spendingParts[i].amount = cents }
                else {
                    let part = SpendingPart(name: category, amount: cents, categories: [category])
                    next.spendingParts.append(part)
                    SpendingParts.assign(category: category, to: part.id, in: &next)
                }
            case .tryTwoWeeks:
                next.butlerAI?.reviews.append(ButlerReview(id: UUID(), suggestion: value, dueAt: Dates.addDays(14, to: now)))
            case .saveLeftover(let start):
                guard let cycle = next.savingHistory.first(where: { Dates.text($0.cycleStart) == start }) else { throw YubaiError.invalid("这个周期已经变了。") }
                try Savings.resolveLeftover(cycleStart: cycle.cycleStart, choice: .save, in: &next)
            case .addWish(let title, let cents):
                var wish = WishItem(title: title, amount: cents); wish.createdAt = now
                wish.coolUntil = Wishlist.cooldownUntil(amount: cents, fromPrinciples: next.profile.principles, now: now)
                next.wishlist.append(wish)
            case .neverMention: mute(value.topic, in: &next)
            }
        case .never: response = "不用，以后不再提"; mute(value.topic, in: &next)
        case .incorrect(let sentence):
            let clean = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            guard clean.isEmpty || Memory.validText(clean) else { throw YubaiError.invalid("请用一行、不超过 200 字。") }
            response = "说得不对"
            correction = clean.isEmpty ? nil : clean
        }
        next.butlerAI?.suggestions[index].answeredAt = now
        let context = String(("关于「" + value.topic + "」的建议：" + value.text(value.proposal)).prefix(170))
        next.memories.append(MemoryNote(text: context + "；" + response, kind: .value, source: .feedback, createdAt: now, evidence: value.entryIDs))
        // Keep the entire optional sentence. It must not be clipped to make room
        // for the topic or generated prose in the context note above.
        if let correction { next.memories.append(MemoryNote(text: correction, kind: .life, source: .feedback, createdAt: now, evidence: value.entryIDs)) }
        next.updatedAt = max(next.updatedAt, now); try next.validate(); ledger = next
    }
    public static func answerReview(_ id: UUID, never: Bool, in ledger: inout Ledger, now: Date) throws {
        guard let i = ledger.butlerAI?.reviews.firstIndex(where: { $0.id == id && $0.answeredAt == nil && $0.dueAt <= now }), let value = ledger.butlerAI?.reviews[i] else { throw YubaiError.invalid("这次回看已经答过了。") }
        var next = ledger
        next.butlerAI?.reviews[i].answeredAt = now
        if never { mute(value.suggestion.topic, in: &next) }
        next.memories.append(MemoryNote(text: "关于「" + value.suggestion.topic + "」的两周回看：" + (never ? "不用，以后不再提" : "试过了"), kind: .value, source: .feedback, createdAt: now))
        next.updatedAt = max(next.updatedAt, now)
        try next.validate(); ledger = next
    }
    private static func mute(_ topic: String, in ledger: inout Ledger) {
        if !ledger.mutedTopics.contains("ai:" + topic) { ledger.mutedTopics.append("ai:" + topic) }
    }
}
