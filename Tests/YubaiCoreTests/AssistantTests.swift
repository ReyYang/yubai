import XCTest
@testable import YubaiCore

actor ScriptedChatTransport: ChatTransport {
    private var replies: [ChatMessage]
    private var requests: [ChatRequest] = []
    init(_ replies: [ChatMessage]) { self.replies = replies }
    func send(_ request: ChatRequest) async throws -> ChatMessage {
        requests.append(request)
        guard !replies.isEmpty else { throw YubaiError.invalid("脚本响应已用完。") }
        return replies.removeFirst()
    }
    func recorded() -> [ChatRequest] { requests }
}

/// Fixed, entirely synthetic ledger shared with the assistant eval seed.
enum AssistantFixtures {
    static func context() -> ToolContext {
        let now = Dates.parse("2026-06-15 12:00")!
        let anchor = Dates.addDays(-100, to: now)
        let bank = Account(name: "合成银行卡", balance: 100_000, at: anchor)
        let cash = Account(name: "零钱", kind: .cash, at: anchor)
        let credit = Account(name: "合成信用卡", kind: .credit, balance: -5000, at: anchor)
        var ledger = Ledger(); ledger.accounts = [bank, cash, credit]
        ledger.preferences.horizonDays = 10; ledger.preferences.dailyLiving = 100; ledger.preferences.emergencyReserve = 2000
        ledger.preferences.purchaseValues = "为长期有用的事物花钱"
        let coffee = Entry(date: Dates.addDays(-2, to: now), amount: 2000, accountID: bank.id, title: "瑞幸咖啡", category: "餐饮")
        var second = Entry(date: Dates.addDays(-1, to: now), amount: 3000, accountID: bank.id, title: "咖啡", category: "餐饮")
        second.note = "加班外卖"; second.externalID = "external_PRIVATE"; second.sourceIdentity = "source_PRIVATE"; second.fingerprint = "fingerprint_PRIVATE"
        var refund = Entry(date: now, amount: 500, nature: .refund, accountID: bank.id, title: "咖啡退款", category: "其他支出")
        refund.relatedEntryID = coffee.id
        var rent = Entry(date: Dates.addDays(-4, to: now), amount: 10_000, accountID: bank.id, title: "房租", category: "居住")
        rent.personalExpense = 4000
        var transfer = Entry(date: now, amount: 1000, nature: .transfer, accountID: bank.id, title: "微信转账-张三")
        transfer.otherAccountID = cash.id
        ledger.entries = [coffee, second, refund, rent, transfer,
            Entry(date: Dates.addDays(-3, to: now), amount: 10_000, nature: .income, accountID: bank.id, title: "工资", category: "工资奖金"),
            Entry(date: now, amount: 1000, nature: .unknownIn, accountID: bank.id, title: "待明确")]
        ledger.plans = [Plan(title: "电费", amount: 7000, dueDate: Dates.addDays(3, to: now)),
                        Plan(title: "工资", amount: 20_000, dueDate: Dates.addDays(5, to: now), inflow: true)]
        ledger.goals = [Goal(title: "学习", target: 10_000, reserved: 3000)]
        return ToolContext(ledger: ledger, now: now)
    }
}

final class AssistantTests: XCTestCase {
    func testJSONRoundTrip() throws {
        let value = JSONValue.object(["null": .null, "bool": .bool(true), "number": .number(2.5), "array": .array([.string("余白")])])
        XCTAssertEqual(try JSONValue.parse(value.jsonText()), value)
    }
    func testAgentToolLoopAndEvidence() async throws {
        let ctx = AssistantFixtures.context()
        let script = ScriptedChatTransport([
            ChatMessage(role: .assistant, toolCalls: [ChatToolCall(id: "call-1", name: "query_entries", arguments: #"{"keyword":"瑞幸"}"#)]),
            ChatMessage(role: .assistant, content: "瑞幸咖啡支出 ¥20.00。")])
        let reply = try await AssistantAgent(transport: script, context: ctx).run(system: "只引用工具金额", messages: [ChatMessage(role: .user, content: "咖啡花了多少")], tools: ReadOnlyTool.all)
        XCTAssertEqual(reply.toolTrace.map(\.name), ["query_entries"])
        XCTAssertEqual(reply.evidenceEntryIDs, [ctx.ledger.entries[0].id])
        XCTAssertTrue(reply.unverifiedAmounts.isEmpty)
        let requests = await script.recorded()
        XCTAssertEqual(requests.count, 2)
        let tool = try XCTUnwrap(requests.last?.messages.last)
        XCTAssertEqual(tool.role, .tool); XCTAssertEqual(tool.toolCallID, "call-1")
        XCTAssertTrue(tool.content?.contains(Money.text(2000)) ?? false)
    }
    func testMaxStepsStops() async throws {
        let response = ChatMessage(role: .assistant, toolCalls: [ChatToolCall(id: "repeat", name: "get_funds")])
        let script = ScriptedChatTransport([response, response])
        do {
            _ = try await AssistantAgent(transport: script, context: AssistantFixtures.context()).run(system: "", messages: [], tools: ReadOnlyTool.all, maxSteps: 2)
            XCTFail("must stop")
        } catch { XCTAssertTrue(error is AssistantAgentError) }
        let requests = await script.recorded(); XCTAssertEqual(requests.count, 2)
    }
    func testMalformedAndInvalidArgsBecomeToolErrors() async throws {
        let script = ScriptedChatTransport([
            ChatMessage(role: .assistant, toolCalls: [
                ChatToolCall(id: "bad-json", name: "forecast", arguments: "{"),
                ChatToolCall(id: "bad-days", name: "forecast", arguments: #"{"days":"tomorrow"}"#),
                ChatToolCall(id: "unknown", name: "not_a_tool")]),
            ChatMessage(role: .assistant, content: "请补充有效的日期。")])
        _ = try await AssistantAgent(transport: script, context: AssistantFixtures.context()).run(system: "", messages: [], tools: ReadOnlyTool.all)
        let requests = await script.recorded()
        let errors = requests[1].messages.filter { $0.role == .tool }
        XCTAssertEqual(errors.count, 3)
        for message in errors { XCTAssertNotNil(try JSONValue.parse(message.content!)["error"]) }
    }
    func testAmountGuardNormalizesAndExcludesCounts() {
        let results: [JSONValue] = [.object(["available": .money(123450), "zero": .money(0), "negative": .money(-2050)])]
        XCTAssertEqual(AssistantAmountGuard.unverified(in: "¥1,234.50、1234.5元、￥1234.50、-20.5元。2026-06-15共2笔，90天，100%。", results: results), [])
        XCTAssertTrue(AssistantAmountGuard.unverified(in: Money.text(-2050), results: results).isEmpty)
        XCTAssertTrue(AssistantAmountGuard.unverified(in: "书籍预算200元", results: [.object(["purchaseValues": .string("书籍预算200元")])]).isEmpty)
        XCTAssertEqual(AssistantAmountGuard.unverified(in: "可用999元，另有 ¥800.00。", results: results), ["999元", "¥800.00"])
        XCTAssertFalse(AssistantAmountGuard.unverified(in: "1万元", results: [.money(100)]).isEmpty)
        XCTAssertFalse(AssistantAmountGuard.unverified(in: "10元", results: [.object(["count": .number(10)])]).isEmpty)
    }
    func testAmountGuardRetriesOnceAndReportsRemainingAmounts() async throws {
        let script = ScriptedChatTransport([
            ChatMessage(role: .assistant, toolCalls: [ChatToolCall(id: "funds", name: "get_funds")]),
            ChatMessage(role: .assistant, content: "可动用 ¥999.00。"),
            ChatMessage(role: .assistant, content: "可动用 ¥888.00。")])
        let reply = try await AssistantAgent(transport: script, context: AssistantFixtures.context()).run(system: "", messages: [], tools: ReadOnlyTool.all)
        XCTAssertEqual(reply.unverifiedAmounts, ["¥888.00"])
        let requests = await script.recorded(); XCTAssertEqual(requests.count, 3)
        XCTAssertTrue(requests[2].tools.isEmpty)
        XCTAssertTrue(requests[2].messages.last?.content?.contains("只引用工具结果") ?? false)
    }
    func testAmountRetryCanRecover() async throws {
        let script = ScriptedChatTransport([
            ChatMessage(role: .assistant, toolCalls: [ChatToolCall(id: "funds", name: "get_funds")]),
            ChatMessage(role: .assistant, content: "可动用999元。"),
            ChatMessage(role: .assistant, content: "可动用 ¥775.00。")])
        let reply = try await AssistantAgent(transport: script, context: AssistantFixtures.context()).run(system: "", messages: [], tools: ReadOnlyTool.all)
        XCTAssertTrue(reply.unverifiedAmounts.isEmpty)
    }
}
