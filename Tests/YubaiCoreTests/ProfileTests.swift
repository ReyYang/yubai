import XCTest
@testable import YubaiCore

final class ProfileTests: XCTestCase {
    private let now = Dates.parse("2026-06-17 12:00")!
    private func seed() -> Ledger {
        var ledger = Ledger()
        ledger.accounts = [Account(name: "合成账户", balance: 100_000, at: Dates.addDays(-200, to: now))]
        return ledger
    }
    private func entry(_ ledger: Ledger, _ date: Date, _ amount: Int64, _ title: String, _ category: String = "餐饮") -> Entry {
        Entry(date: date, amount: amount, accountID: ledger.accounts[0].id, title: title, category: category)
    }
    private func profile(_ ledger: Ledger) throws -> JSONValue {
        try ReadOnlyTool.getProfile.run(.object([:]), ToolContext(ledger: ledger, now: now))
    }
    func testStructuredProfileReflectsEditsAndDeletedPrinciple() throws {
        var ledger = seed()
        ledger.profile.generous = [ProfileArea(title: "学习", match: AreaMatch(categories: ["学习"], keywords: ["书"]))]
        ledger.profile.restrain = [ProfileArea(title: "外卖", match: AreaMatch(keywords: ["外卖"]),
            softLimit: SoftLimit(perWeekCount: 3, perMonthAmount: 50_000))]
        ledger.profile.principles = ["超过 2,000 等 48 小时"]
        ledger.profile.floorAmount = 500_000
        ledger.preferences.purchaseValues = "旧的偏好，不应再引用"
        ledger.goals = [Goal(title: "旅行", target: 800_000, reserved: 120_000, dueDate: now)]
        ledger.entries = [entry(ledger, now, 2000, "午餐")]
        let first = try profile(ledger)
        XCTAssertEqual(first["generous"]?.arrayValue?.first?["match"]?["categories"], .strings(["学习"]))
        let limit = first["restrain"]?.arrayValue?.first?["soft_limit"]
        XCTAssertEqual(limit?["per_week_count"], .number(3))
        XCTAssertEqual(limit?["per_month_amount"], .money(50_000))
        XCTAssertEqual(limit?["text"], .string("每周 ≤ 3 次 · 每月 ≤ " + Money.text(50_000)))
        XCTAssertEqual(first["floor_amount"], .money(500_000))
        let goal = first["goals"]?.arrayValue?.first
        XCTAssertEqual(goal?["title"], .string("旅行")); XCTAssertEqual(goal?["target"], .money(800_000))
        XCTAssertEqual(goal?["saved"], .money(120_000)); XCTAssertEqual(goal?["date"], .string(Dates.text(now)))
        XCTAssertEqual(first["habits"]?["window_days"], .number(90))
        XCTAssertEqual(first["habits"]?["lines"]?.arrayValue?.first?["total"], .money(2000))
        XCTAssertFalse(try first.jsonText().contains("旧的偏好"))
        let change = ChangeSet(source: "反馈", reason: "用户更正", items: [
            .profile(.removePrinciple("超过 2,000 等 48 小时")), .profile(.setFloorAmount(600_000)),
            .profile(.removeArea(ledger.profile.restrain[0].id))])
        try change.apply(to: &ledger)
        let next = try profile(ledger)
        XCTAssertEqual(next["principles"], .strings([])); XCTAssertEqual(next["floor_amount"], .money(600_000))
        XCTAssertEqual(next["restrain"], .array([]))
        XCTAssertFalse(try next.jsonText().contains("超过 2,000 等 48 小时"))
        XCTAssertFalse(try next.jsonText().contains("外卖"))
    }
    func testUsageCategoryOrKeywordAndCalendarBoundaries() throws {
        var ledger = seed(); ledger.categoryAliases["旧餐饮"] = "餐饮"
        var purpose = entry(ledger, Dates.addDays(-1, to: now), 2000, "订单", "其他支出"); purpose.purpose = "工作外卖"
        var note = entry(ledger, now, 3000, "午饭", "其他支出"); note.note = "外卖"
        let first = entry(ledger, Dates.parse("2026-06-15 00:00")!, 1000, "外卖午餐")
        var refund = entry(ledger, now, 500, "退回", "其他支出"); refund.nature = .refund; refund.relatedEntryID = first.id
        var removed = entry(ledger, now, 10_000, "外卖"); removed.deletedAt = now
        var unknown = entry(ledger, now, 10_000, "外卖"); unknown.nature = .unknownOut
        ledger.entries = [first, purpose, note, refund, removed, unknown,
            entry(ledger, Dates.parse("2026-06-01 00:00")!, 4000, "聚餐"),
            entry(ledger, Dates.parse("2026-05-31 23:59")!, 5000, "聚餐"),
            entry(ledger, Dates.parse("2026-06-14 23:59")!, 6000, "外卖", "其他支出"),
            entry(ledger, Dates.addDays(1, to: now), 7000, "外卖"),
            entry(ledger, now.addingTimeInterval(1), 8000, "外卖")]
        try ledger.validate()
        let both = ProfileArea(title: "吃饭", match: AreaMatch(categories: ["旧餐饮"], keywords: ["外卖"]))
        let value = both.usage(in: ledger, now: now)
        XCTAssertEqual(value.weekCount, 3); XCTAssertEqual(value.monthAmount, 15_500)
        let category = ProfileArea(title: "餐饮", match: AreaMatch(categories: ["旧餐饮"]))
        XCTAssertEqual(category.usage(in: ledger, now: now).weekCount, 1)
        XCTAssertEqual(category.usage(in: ledger, now: now).monthAmount, 4500)
        let keyword = ProfileArea(title: "外卖", match: AreaMatch(keywords: ["外卖"]))
        XCTAssertEqual(keyword.usage(in: ledger, now: now).weekCount, 3)
        XCTAssertEqual(keyword.usage(in: ledger, now: now).monthAmount, 11_500)
        XCTAssertEqual(ProfileArea(title: "空").usage(in: ledger, now: now).monthAmount, 0)
        let blank = ProfileArea(title: "空", match: AreaMatch(keywords: ["  "]))
        XCTAssertEqual(blank.usage(in: ledger, now: now).weekCount, 0)
        XCTAssertEqual(SoftLimit(perWeekCount: 0).text, "每周 ≤ 0 次")
    }
    func testUsageRefundMatchesOriginalKeywordOutsideMonthAndUsesPersonalShare() {
        var ledger = seed()
        let original = entry(ledger, Dates.parse("2026-05-31")!, 2000, "外卖")
        var refund = entry(ledger, now, 500, "退回"); refund.nature = .refund; refund.relatedEntryID = original.id
        var expense = entry(ledger, now, 4000, "外卖"); expense.personalExpense = 1000
        ledger.entries = [original, refund, expense]
        let area = ProfileArea(title: "外卖", match: AreaMatch(keywords: ["外卖"]))
        XCTAssertEqual(area.usage(in: ledger, now: now).weekCount, 1)
        XCTAssertEqual(area.usage(in: ledger, now: now).monthAmount, 500)
        ledger.entries.removeLast()
        XCTAssertEqual(area.usage(in: ledger, now: now).monthAmount, 0)
    }
    func testHabitsNumbersWindowRankingAndTopFive() throws {
        var ledger = seed()
        let first = entry(ledger, Dates.addDays(-89, to: Dates.day(now)), 1000, "青禾咖啡")
        var refund = entry(ledger, now, 500, "退款", "其他支出"); refund.nature = .refund; refund.relatedEntryID = first.id
        var personal = entry(ledger, now, 10_000, "青禾咖啡"); personal.personalExpense = 3000
        var removed = entry(ledger, now, 90_000, "已删除"); removed.deletedAt = now
        var income = entry(ledger, now, 90_000, "工资"); income.nature = .income
        ledger.entries = [first, personal, refund, removed, income,
            entry(ledger, Dates.addDays(-90, to: Dates.day(now)), 90_000, "过期"),
            entry(ledger, now.addingTimeInterval(1), 90_000, "将来"),
            entry(ledger, now, 3500, "书店", "学习"), entry(ledger, now, 100, "地铁", "交通")]
        let lines = ProfileHabits.summary(ledger, now: now)
        XCTAssertEqual(lines.count, 5)
        let food = try XCTUnwrap(lines.first { $0.kind == .category && $0.title == "餐饮" })
        XCTAssertEqual(food.total, 3500); XCTAssertEqual(food.count, 2); XCTAssertEqual(food.average, 1750)
        XCTAssertEqual(food.countPerWeek, 14.0 / 90, accuracy: 0.000001)
        XCTAssertEqual(lines[0], food) // Same spend ranks the more frequent area first.
        let merchant = try XCTUnwrap(lines.first { $0.kind == .merchant && $0.title == "青禾咖啡" })
        XCTAssertEqual(merchant.total, food.total); XCTAssertEqual(merchant.count, food.count)
        XCTAssertEqual(lines[1], merchant)
        XCTAssertFalse(lines.contains { ["过期", "将来", "已删除", "工资"].contains($0.title) })
        XCTAssertEqual(ProfileHabits.summary(seed(), now: now), [])
        let output = try profile(ledger)["habits"]?["lines"]?.arrayValue ?? []
        XCTAssertEqual(output.map { $0["total"] }, lines.map { .money($0.total) })
    }
    func testNextAgentJudgmentReadsFreshProfileAndDoesNotQuoteDeletedPrinciple() async throws {
        var ledger = seed(); ledger.profile.principles = ["大件先等两天"]
        let script = ScriptedChatTransport([
            ChatMessage(role: .assistant, toolCalls: [ChatToolCall(id: "profile-1", name: "get_profile")]),
            ChatMessage(role: .assistant, content: "按你的原则，大件先等两天。"),
            ChatMessage(role: .assistant, toolCalls: [ChatToolCall(id: "profile-2", name: "get_profile")]),
            ChatMessage(role: .assistant, content: "先想想它能否解决眼前的问题。")])
        let first = try await AssistantAgent(transport: script, context: ToolContext(ledger: ledger, now: now)).run(system: "先读消费观。", messages: [], tools: ReadOnlyTool.all)
        try ChangeSet(source: "用户", reason: "删除原则", items: [.profile(.removePrinciple("大件先等两天"))]).apply(to: &ledger)
        let next = try await AssistantAgent(transport: script, context: ToolContext(ledger: ledger, now: now)).run(system: "先读消费观。", messages: [], tools: ReadOnlyTool.all)
        XCTAssertNotEqual(first.text, next.text)
        let requests = await script.recorded()
        let last = try XCTUnwrap(requests.last)
        XCTAssertFalse(last.messages.contains { $0.content?.contains("大件先等两天") == true })
    }
}
