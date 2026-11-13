#if DEBUG && targetEnvironment(simulator)
import Foundation
import YubaiCore

extension UITestSupport {
    static let butler47Scripts: Set<String> = ["v47-c-empty", "v47-ai-valid", "v47-ai-many", "v47-ai-wrong-sum", "v47-ai-unknown-id", "v47-ai-unknown-action", "v47-ai-malformed", "v47-ai-none", "v47-ai-review", "v47-ai-hard"]
    static func butler47Ledger(_ script: String, now: Date) throws -> Ledger {
        if script == "v47-c-empty" {
            var empty = try galleryLedger("gallery-empty", now: now)
            empty.preferences.cloudAIEnabled = true
            empty.preferences.aiWeeklyReviewDisabled = true; empty.preferences.aiImportClassificationDisabled = true
            empty.preferences.aiReceiptRecognitionDisabled = true; empty.preferences.butlerSuggestionsEnabled = false
            return empty
        }
        var ledger = try home47Ledger("v47-home", now: now)
        ledger.id = galleryID(472000); ledger.entries = []; ledger.cards = []; ledger.imports = []
        ledger.preferences.cloudAIEnabled = true; ledger.preferences.butlerSuggestionsEnabled = true
        ledger.preferences.aiImportClassificationDisabled = true
        ledger.lastSubcategoryBatchDay = Dates.text(now)
        ledger.lastReflectionWeek = nil; ledger.butlerAI = nil
        ledger.profile.generous = []; ledger.profile.restrain = []
        ledger.memories = [MemoryNote(id: galleryID(472090), text: "吃上不省，但不想为了累多花钱。", kind: .value, source: .chat, createdAt: Dates.addDays(-23, to: now))]
        let titles = ["麻辣香锅外卖", "轻食外卖", "烤肉饭外卖", "麻辣烫外卖", "加班外卖", "加班外卖", "加班外卖"]
        for i in 0..<7 {
            let amount: Int64 = script == "v47-ai-hard" ? 123_456_789 : [3600, 3200, 2800, 3000, 2600, 3100, 3100][i]
            var entry = Entry(date: Dates.addDays(-[1, 2, 8, 9, 15, 16, 22][i], to: now), amount: amount, accountID: ledger.accounts[0].id,
                              title: script == "v47-ai-hard" ? galleryLongTitle : titles[i], category: "餐饮")
            entry.id = galleryID(472101 + i); ledger.entries.append(entry)
        }
        if script == "v47-ai-review" {
            ledger.entries = ledger.entries.map { entry in var value = entry; value.date = Dates.addDays(-14, to: entry.date); return value }
        }
        // Existing code reminders still participate, but this gallery focuses the suggestion.
        for task in HomeButler.queue(ledger, now: now) { HomeButler.answer(task.id, in: &ledger, now: now) }
        if script == "v47-ai-review" {
            let trialStart = Dates.addDays(-14, to: now)
            let reply = try JSONValue.parse(butler47Content(script, ids: ledger.entries.map(\.id), memoryID: ledger.memories[0].id, sum: 21400))
            let values = ButlerSuggestionVerifier.parse(reply["suggestions"]!, digest: ButlerDigest.build(ledger, now: trialStart), ledger: ledger, now: trialStart)
            ButlerIntelligence.enqueue(values, in: &ledger, now: trialStart)
            if let value = values.first {
                try ButlerSuggestions.answer(value.id, .accept, in: &ledger, now: trialStart)
            }
            ledger.lastReflectionWeek = ButlerCards.isoWeek(now)
        }
        try ledger.validate(); return ledger
    }
    static func butler47Content(_ script: String, ids: [UUID], memoryID: UUID, sum: Int64) throws -> String {
        if script == "v47-ai-malformed" { return "{broken" }
        var action: JSONValue = .object(["kind": .string("try_two_weeks"), "review": .string("带饭怎么样？")])
        if script == "v47-ai-unknown-action" { action = .object(["kind": .string("send_money")]) }
        let entryIDs = script == "v47-ai-unknown-id" ? [UUID()] : ids
        let row: JSONValue = .object(["topic": .string("加班外卖"),
            "observation": .array([.object(["text": .string("加班后的外卖 ")]), .object(["count": .bool(true)]), .object(["text": .string(" 次，共 ")]), .object(["sum": .bool(true)])]),
            "proposal": .array([.object(["text": .string("。周三周四试试带饭？")])]),
            "entry_ids": .array(entryIDs.map { .string($0.uuidString) }), "claimed_count": .number(Double(ids.count)),
            "claimed_sum_cents": .number(Double(script == "v47-ai-wrong-sum" ? sum + 1 : sum)),
            "action": action, "memory_ids": .array([.string(memoryID.uuidString)])])
        var rows = script == "v47-ai-none" ? [] : [row]
        if script == "v47-ai-many", var second = row.objectValue {
            second["topic"] = .string("晚饭的安排"); rows.append(.object(second))
        }
        return try JSONValue.object(["add": .array([]), "update": .array([]), "remove": .array([]), "learned": .array([]), "suggestions": .array(rows)]).jsonText()
    }
    static func butler47Reply(_ request: ChatRequest, script: String) throws -> ChatMessage? {
        guard butler47Scripts.contains(script) else { return nil }
        if script == "v47-c-empty" { return ChatMessage(role: .assistant, content: "还没有支出。") }
        if request.purpose == "每周回看" || request.purpose == "管家的建议" {
            let input = try JSONValue.parse(request.messages.last?.content ?? "{}")
            let digest = input["butler_digest"] ?? input
            let ids = (digest["candidates"]?.arrayValue ?? []).flatMap { $0["entryIDs"]?.arrayValue ?? [] }.compactMap { $0.stringValue.flatMap(UUID.init(uuidString:)) }
            let memories = digest["memories"]?.arrayValue ?? []
            let memory = memories.first?["id"]?.stringValue.flatMap(UUID.init(uuidString:)) ?? galleryID(472090)
            let sum = (digest["categories"]?.arrayValue ?? []).reduce(Int64(0)) { result, row in
                if case .number(let value) = row["sumCents"] { return result + Int64(value) }; return result
            }
            var content = try butler47Content(script, ids: ids, memoryID: memory, sum: sum)
            if request.purpose == "管家的建议", let rows = try? JSONValue.parse(content)["suggestions"] { content = try JSONValue.object(["suggestions": rows]).jsonText() }
            return ChatMessage(role: .assistant, content: content)
        }
        return ChatMessage(role: .assistant, content: "已记下。")
    }
}
#endif
