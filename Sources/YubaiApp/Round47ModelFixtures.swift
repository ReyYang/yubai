#if DEBUG && targetEnvironment(simulator)
import Foundation
import YubaiCore

extension UITestSupport {
    static let model47Scripts: Set<String> = [
        "v47r-fast", "v47r-no-income", "v47r-carry-fast", "v47r-soft-lines", "v47r-soft-exceeded", "v47r-soft-count",
        "v47r-next-bill", "v47r-next-quarterly", "v47r-mismatch", "v47r-reconcile-covered", "v47r-reconcile-floor",
        "v47r-overdue", "v47r-suggestion", "v47r-weekly-ai", "v47r-weekly-letter"
    ]
    static func model47Ledger(_ script: String, now: Date) throws -> Ledger {
        var value = try savings47Ledger("v47-spend", now: now)
        value.id = galleryID(478000)
        value.cards = []; value.memories = []; value.butlerAnswers = [:]
        value.lastReconciledAt = Dates.addDays(-2, to: now)
        value.accounts[0].name = "招行储蓄卡"
        let account = value.accounts[0].id, today = Dates.day(now)
        func expense(_ number: Int, _ title: String, _ amount: Int64, _ category: String, _ subcategory: String? = nil) -> Entry {
            var row = Entry(date: today, amount: amount, accountID: account, title: title, category: category)
            row.id = galleryID(number); row.subcategory = subcategory
            return row
        }
        if script == "v47r-fast" || script == "v47r-carry-fast" {
            value.entries.removeAll { $0.nature == .expense }
            value.entries.append(expense(478101, "晚饭", 162_000, "餐饮"))
        }
        if script == "v47r-no-income" { value.entries.removeAll { $0.nature == .income } }
        if script == "v47r-carry-fast" {
            value.savingHistory[0].autoSaved = true; value.savingHistory[0].leftover = 62_000
            value.savingHistory[0].unspent = 62_000; value.savingHistory[0].leftoverChoice = .save
        }
        if script.hasPrefix("v47r-soft") {
            value.entries.removeAll { $0.nature == .expense }
            value.entries += [expense(478101, "外卖", 48_000, "餐饮", "外卖"),
                              expense(478102, "咖啡", 1800, "餐饮", "咖啡饮品"),
                              expense(478103, "咖啡", 1800, "餐饮", "咖啡饮品"),
                              expense(478104, "打车", 28_000, "交通", "打车"), expense(478105, "日用", 4000, "日用")]
            var takeaway = ProfileArea(title: "外卖", match: .init(subcategories: ["餐饮/外卖"]), softLimit: .init(perPeriodAmount: 80_000))
            takeaway.id = galleryID(478201)
            var coffee = ProfileArea(title: "咖啡", match: .init(subcategories: ["餐饮/咖啡饮品"]), softLimit: .init(perPeriodCount: 6))
            coffee.id = galleryID(478202)
            var taxi = ProfileArea(title: "打车", match: .init(subcategories: ["交通/打车"]), softLimit: .init(perPeriodAmount: 20_000))
            taxi.id = galleryID(478203)
            value.profile.restrain = [takeaway, coffee, taxi]
            if script == "v47r-soft-exceeded" { value.entries[1].amount = 81_800 }
            if script == "v47r-soft-count" { value.profile.restrain = [coffee] }
        }
        if script == "v47r-next-bill" || script == "v47r-next-quarterly" {
            let end = Finance.cycle(in: value, now: now).end
            var bill = Plan(title: script == "v47r-next-bill" ? "车险" : "季付房租", amount: 420_000,
                            dueDate: Dates.addDays(9, to: end), frequency: script == "v47r-next-bill" ? .yearly : .quarterly, category: "居住")
            bill.id = galleryID(478301); bill.accountID = account; bill.autoPay = false
            value.plans.append(bill)
        }
        if script == "v47r-mismatch" {
            value.lastReconciledAt = Dates.addDays(-23, to: now)
            // Physical cash is exactly 412.00 short of the canonical need.
            value.accounts[0].anchorBalance = 258_800
        }
        if script == "v47r-reconcile-covered" || script == "v47r-reconcile-floor" {
            value.accounts[0].anchorBalance = 500_000
            value.lastReconciledAt = Dates.addDays(-23, to: now)
        }
        if script == "v47r-overdue" {
            var bill = Plan(title: "上期未付房租", amount: 505_000, dueDate: Dates.addDays(-40, to: today), frequency: .once, category: "居住")
            bill.id = galleryID(478302); bill.accountID = account
            value.plans.append(bill)
        }
        if script == "v47r-suggestion" || script == "v47r-weekly-ai" {
            value.preferences.cloudAIEnabled = true; value.preferences.butlerSuggestionsEnabled = true
            value.lastReflectionWeek = ButlerCards.isoWeek(now)
            value.entries.removeAll { $0.nature == .expense }
            let count = script == "v47r-suggestion" ? 31 : 7
            let total: Int64 = script == "v47r-suggestion" ? 124_000 : 21_400
            for index in 0..<count {
                var row = expense(478400 + index, "加班后的外卖", index == count - 1 ? total - Int64(count - 1) * (total / Int64(count)) : total / Int64(count), "餐饮", "外卖")
                row.date = Dates.addDays(-(index % 9), to: today); value.entries.append(row)
            }
            let ids = value.entries.filter { $0.nature == .expense }.map(\.id)
            if script == "v47r-suggestion" {
                for index in 0..<3 {
                    var old = expense(478450 + index, "外卖", 62_000, "餐饮", "外卖")
                    old.date = Dates.addDays(-35 - index * 28, to: today); value.entries.append(old)
                }
            }
            let action: JSONValue = script == "v47r-suggestion" ? .object(["kind": .string("set_budget"), "category": .string("外卖"), "amount_cents": .number(80_000)]) : .object(["kind": .string("try_two_weeks"), "review": .string("带饭怎么样？")])
            let row: JSONValue = .object(["topic": .string("外卖"),
                "observation": .array([.object(["text": .string(script == "v47r-suggestion" ? "外卖 " : "加班后的外卖 ")]), .object(["count": .bool(true)]), .object(["text": .string(" 次，共 ")]), .object(["sum": .bool(true)])]),
                "proposal": .array([.object(["text": .string(script == "v47r-suggestion" ? "盯住外卖" : "。周三周四试试带饭？")])]),
                "entry_ids": .array(ids.map { .string($0.uuidString) }), "claimed_count": .number(Double(count)), "claimed_sum_cents": .number(Double(total)), "action": action, "memory_ids": .array([])])
            let suggestions = ButlerSuggestionVerifier.parse(.array([row]), digest: ButlerDigest.build(value, now: now), ledger: value, now: now)
            ButlerIntelligence.enqueue(suggestions, in: &value, now: now)
            ButlerCadence.recordAttempt(ButlerCadence.due(value, now: now, suggestions: true), in: &value, now: now)
        }
        if script == "v47r-weekly-letter" {
            value.mutedTopics.removeAll { $0 == "letter" }
            var card = ButlerCard(kind: .weeklyLetter, title: "每周来信", body: "", action: .openEvidence, dedupeKey: "letter:" + ButlerCards.isoWeek(now))
            card.createdAt = now; card.id = galleryID(478500); value.cards = [card]
        }
        // Isolate the specified card while preserving the production queue.
        for task in HomeButler.queue(value, now: now) {
            let keep: Bool
            switch task {
            case .leftover: keep = script == "v47r-carry-fast"
            case .balanceMismatch: keep = script == "v47r-mismatch"
            case .billHeadsUp: keep = script == "v47r-next-bill" || script == "v47r-next-quarterly"
            case .suggestion: keep = script == "v47r-suggestion" || script == "v47r-weekly-ai"
            case .butler(let card): keep = script == "v47r-weekly-letter" && card.kind == .weeklyLetter
            case .overspend: keep = script == "v47r-overdue"
            default: keep = false
            }
            if !keep { HomeButler.answer(task.id, in: &value, now: now) }
        }
        try value.validate(); return value
    }
}
#endif
