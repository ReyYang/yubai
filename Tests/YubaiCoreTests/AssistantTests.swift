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
        ledger.profile.floorAmount = 2000
        ledger.preferences.purchaseValues = "为长期有用的事物花钱"
        let coffee = Entry(date: Dates.addDays(-2, to: now), amount: 2000, accountID: bank.id, title: "瑞幸咖啡", category: "餐饮")
        var second = Entry(date: Dates.addDays(-1, to: now), amount: 3000, accountID: bank.id, title: "咖啡", category: "餐饮")
        second.note = "加班外卖 美团"; second.externalID = "external_PRIVATE"; second.sourceIdentity = "source_PRIVATE"; second.fingerprint = "fingerprint_PRIVATE"
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

final class AskYubaiExamplesTests: XCTestCase {
    private let now = Dates.parse("2026-11-04 12:00")!
    private let purchase = "想买一双 899 的鞋，该不该买？"

    func testUpcomingPaymentUsesFirstNonInflowOccurrence() {
        var ledger = Ledger()
        ledger.plans = [Plan(title: "工资", amount: 500_000, dueDate: Dates.parse("2026-11-05")!, inflow: true),
                        Plan(title: "房租", amount: 200_000, dueDate: Dates.parse("2026-11-06")!),
                        Plan(title: "网费", amount: 10_000, dueDate: Dates.parse("2026-11-08")!)]
        let occurrences = Finance.funds(ledger, now: now).occurrences
        XCTAssertEqual(AskYubai.exampleQuestions(ledger: ledger, occurrences: occurrences, now: now),
                       ["11月6日的房租够付吗？", "这周花了多少？", purchase])
    }

    func testNoUpcomingPaymentSkipsBillQuestion() {
        var ledger = Ledger()
        ledger.plans = [Plan(title: "工资", amount: 500_000, dueDate: Dates.parse("2026-11-05")!, inflow: true)]
        let occurrences = Finance.funds(ledger, now: now).occurrences
        XCTAssertEqual(AskYubai.exampleQuestions(ledger: ledger, occurrences: occurrences, now: now),
                       ["这周花了多少？", purchase])
        XCTAssertEqual(AskYubai.exampleQuestions(ledger: Ledger(), occurrences: [], now: now),
                       ["这周花了多少？", purchase])
    }

    func testWeeklySpendingUsesLargestCategoryTotalAndCurrentName() {
        var ledger = Ledger()
        let account = Account(name: "合成银行卡", at: now)
        ledger.accounts = [account]
        ledger.categoryAliases["外卖"] = "餐饮"
        ledger.entries = [Entry(date: Dates.parse("2026-11-02")!, amount: 6000, accountID: account.id, title: "午饭", category: "外卖"),
                          Entry(date: now, amount: 6000, accountID: account.id, title: "晚饭", category: "餐饮"),
                          Entry(date: now, amount: 10_000, accountID: account.id, title: "打车", category: "交通"),
                          Entry(date: now, amount: 500_000, nature: .income, accountID: account.id, title: "工资", category: "工资奖金")]
        XCTAssertEqual(AskYubai.exampleQuestions(ledger: ledger, occurrences: [], now: now),
                       ["这周餐饮花了多少？", purchase])
    }

    func testNoWeeklySpendingUsesGenericQuestion() {
        var ledger = Ledger()
        let account = Account(name: "合成银行卡", at: now)
        ledger.accounts = [account]
        ledger.entries = [Entry(date: Dates.parse("2026-11-01 23:59")!, amount: 10_000, accountID: account.id, title: "上周晚饭", category: "餐饮"),
                          Entry(date: now, amount: 500_000, nature: .income, accountID: account.id, title: "工资", category: "工资奖金")]
        XCTAssertEqual(AskYubai.exampleQuestions(ledger: ledger, occurrences: [], now: now),
                       ["这周花了多少？", purchase])
    }

    func testPendingCategoryUsesDisplayName() {
        var ledger = Ledger()
        let account = Account(name: "合成银行卡", at: now)
        ledger.accounts = [account]
        ledger.entries = [Entry(date: now, amount: 3000, accountID: account.id, title: "午饭", category: Classification.pendingCategory)]
        XCTAssertEqual(AskYubai.exampleQuestions(ledger: ledger, occurrences: [], now: now),
                       ["这周没分类花了多少？", purchase])
    }

    func testISOWeekIncludesMondayAndSundayAcrossYearButExcludesAdjacentWeeks() {
        let now = Dates.parse("2027-01-03 12:00")!
        var ledger = Ledger()
        let account = Account(name: "合成银行卡", at: now)
        ledger.accounts = [account]
        ledger.entries = [Entry(date: Dates.parse("2026-12-28")!, amount: 6000, accountID: account.id, title: "周一午饭", category: "餐饮"),
                          Entry(date: Dates.parse("2027-01-03")!, amount: 6000, accountID: account.id, title: "周日午饭", category: "餐饮"),
                          Entry(date: Dates.parse("2027-01-01")!, amount: 10_000, accountID: account.id, title: "打车", category: "交通"),
                          Entry(date: Dates.parse("2026-12-27 23:59")!, amount: 100_000, accountID: account.id, title: "上周购买", category: "购物"),
                          Entry(date: Dates.parse("2027-01-04")!, amount: 100_000, accountID: account.id, title: "下周购买", category: "购物")]
        XCTAssertEqual(AskYubai.exampleQuestions(ledger: ledger, occurrences: [], now: now),
                       ["这周餐饮花了多少？", purchase])
    }

    func testRefundsOffsetOriginalCategoryAndNonpositiveTotalsUseFallback() {
        var ledger = Ledger()
        let account = Account(name: "合成银行卡", at: now)
        ledger.accounts = [account]
        let purchaseEntry = Entry(date: now, amount: 10_000, accountID: account.id, title: "鞋", category: "购物")
        var refund = Entry(date: now, amount: 10_000, nature: .refund, accountID: account.id, title: "退鞋", category: "其他支出")
        refund.relatedEntryID = purchaseEntry.id
        let meal = Entry(date: now, amount: 3000, accountID: account.id, title: "午饭", category: "餐饮")
        ledger.entries = [purchaseEntry, refund, meal]
        XCTAssertEqual(AskYubai.exampleQuestions(ledger: ledger, occurrences: [], now: now),
                       ["这周餐饮花了多少？", purchase])
        ledger.entries.removeLast()
        XCTAssertEqual(AskYubai.exampleQuestions(ledger: ledger, occurrences: [], now: now),
                       ["这周花了多少？", purchase])
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
    func testConsecutiveNormalizedCallsReuseResultsWithoutStopping() async throws {
        let tool = CountingAssistantTool()
        let calls = (0..<12).map { index in ChatMessage(role: .assistant, toolCalls: [
            ChatToolCall(id: "repeat-\(index)", name: tool.name, arguments: index % 2 == 0 ? #"{"a":1,"b":2}"# : #"{ "b":2.0, "a":1 }"#)]) }
        let script = ScriptedChatTransport(calls + [ChatMessage(role: .assistant, content: "已查到，可以回答。")])
        let reply = try await AssistantAgent(transport: script, context: AssistantFixtures.context()).run(system: "", messages: [], tools: [tool])
        XCTAssertEqual(tool.executions, 1); XCTAssertEqual(reply.toolTrace.count, 12)
        let requests = await script.recorded(); XCTAssertEqual(requests.count, 13)
        let results = requests.last!.messages.filter { $0.role == .tool }
        XCTAssertEqual(Set(results.compactMap(\.content)).count, 1)
        XCTAssertEqual(results.map(\.toolCallID), (0..<12).map { "repeat-\($0)" })
        XCTAssertTrue(requests.last!.messages.contains { $0.role == .system && $0.content == "这个调用刚执行过，结果相同；请换个查询或直接回答" })
    }
    func testChangedAndNonconsecutiveCallsExecuteAgainAndLargeBatchIsAllowed() async throws {
        let tool = CountingAssistantTool()
        let calls = (0..<20).map { ChatToolCall(id: "batch-\($0)", name: tool.name, arguments: "{\"key\":\($0)}") }
        let script = ScriptedChatTransport([
            ChatMessage(role: .assistant, toolCalls: calls),
            ChatMessage(role: .assistant, toolCalls: [ChatToolCall(id: "new", name: tool.name, arguments: #"{"key":99}"#)]),
            ChatMessage(role: .assistant, toolCalls: [ChatToolCall(id: "again", name: tool.name, arguments: #"{"key":0}"#)]),
            ChatMessage(role: .assistant, content: "查询完成。")])
        _ = try await AssistantAgent(transport: script, context: AssistantFixtures.context()).run(system: "", messages: [], tools: [tool])
        XCTAssertEqual(tool.executions, 22)
    }
    func testOldToolResultsCompactAndRecentFactsAndTextSurvive() async throws {
        let tool = CountingAssistantTool(payload: String(repeating: "早期依据", count: 1000))
        let calls = (0..<3).map { index in ChatMessage(role: .assistant, content: "继续核对", toolCalls: [
            ChatToolCall(id: "large-\(index)", name: tool.name, arguments: "{\"key\":\(index)}")]) }
        let script = ScriptedChatTransport(calls + [ChatMessage(role: .assistant, content: "最新查询仍可回答。")])
        let reply = try await AssistantAgent(transport: script, context: AssistantFixtures.context()).run(system: "保留系统要求", messages: [ChatMessage(role: .user, content: "保留用户原文")], tools: [tool], characterBudget: 6000)
        XCTAssertEqual(reply.text, "最新查询仍可回答。")
        let requests = await script.recorded(); let messages = requests.last!.messages
        let results = messages.filter { $0.role == .tool }
        XCTAssertEqual(results.map(\.toolCallID), ["large-0", "large-1", "large-2"])
        for result in results.prefix(2) {
            XCTAssertTrue(result.content?.contains(tool.name) == true)
            XCTAssertTrue(result.content?.contains("需要细节请重新查询") == true)
            XCTAssertLessThanOrEqual(result.content?.count ?? 0, 200)
        }
        XCTAssertTrue(results[2].content?.contains("早期依据") == true)
        XCTAssertEqual(messages.first?.content, "保留系统要求")
        XCTAssertTrue(messages.contains { $0.content == "保留用户原文" })
        XCTAssertEqual(messages.filter { $0.content == "继续核对" }.count, 3)
        XCTAssertLessThanOrEqual(AssistantContextBudget.count(messages), 6000)
    }
    func testCancellationStopsEvenWhenTransportReturnsFinalText() async throws {
        let script = CancellationChatTransport()
        let task = Task { try await AssistantAgent(transport: script, context: AssistantFixtures.context()).run(system: "", messages: [], tools: []) }
        await script.waitUntilStarted(); task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
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
    func testAmountGuardExcludesDatesTimesAndUUIDsTouchingChineseText() {
        for value in ["2026-06-15", "2026-6-5", "2026/06/15", "2026/6/5", "2026年6月15日", "6月15日",
                      "14:30", "14:30:45", "14：30", "2026-06-15 14:30",
                      "12345678-1234-4abc-8def-123456789012", "ABCDEF12-ABCD-4ABC-8DEF-ABCDEF123456"] {
            XCTAssertEqual(AssistantAmountGuard.unverified(in: "截至\(value)共2笔", results: []), [], value)
            XCTAssertEqual(AssistantAmountGuard.unverified(in: "截至\(value)共2笔，消费999元", results: []), ["999元"], value)
        }
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
            ChatMessage(role: .assistant, content: "可动用 ¥805.00。")])
        let reply = try await AssistantAgent(transport: script, context: AssistantFixtures.context()).run(system: "", messages: [], tools: ReadOnlyTool.all)
        XCTAssertTrue(reply.unverifiedAmounts.isEmpty)
    }
}

private final class CountingAssistantTool: AssistantTool, @unchecked Sendable {
    let name = "counting_tool"
    let description = "合成测试工具"
    let parameters = JSONValue.object(["type": .string("object")])
    private let lock = NSLock()
    private var count = 0
    private let payload: String
    init(payload: String = "相同结果") { self.payload = payload }
    var executions: Int { lock.lock(); defer { lock.unlock() }; return count }
    func run(_ args: JSONValue, _ ctx: ToolContext) throws -> JSONValue {
        lock.lock(); defer { lock.unlock() }; count += 1
        return .object(["payload": .string(payload)])
    }
}

private actor CancellationChatTransport: ChatTransport {
    private var started = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func send(_ request: ChatRequest) async throws -> ChatMessage {
        started = true; for waiter in waiters { waiter.resume() }; waiters = []
        while !Task.isCancelled { await Task.yield() }
        return ChatMessage(role: .assistant, content: "已取消的回答不应返回。")
    }
}

extension AssistantTests {
    func testToolCompactionKeepsLocalFactsAndCompactsPastThresholdToSixtyPercent() throws {
        var messages = [ChatMessage(role: .system, content: "系统要求")]
        for index in 0..<8 {
            messages.append(ChatMessage(role: .assistant, toolCalls: [ChatToolCall(id: "facts-\(index)", name: "summarize", arguments: #"{"from":"2026-01-01","to":"2026-10-01"}"#)]))
            let content = try JSONValue.object(["count": .number(12), "total": .string("123.45元"), "rows": .array([.null, .null]), "detail": .string(String(repeating: "依据", count: 220))]).jsonText()
            messages.append(ChatMessage(role: .tool, content: content, toolCallID: "facts-\(index)"))
        }
        XCTAssertGreaterThan(AssistantContextBudget.count(messages), 4000)
        AssistantContextBudget.compactTools(&messages, limit: 4000)
        XCTAssertLessThanOrEqual(AssistantContextBudget.count(messages), 2400)
        let note = try XCTUnwrap(messages.first { $0.role == .tool }?.content)
        XCTAssertTrue(note.contains("summarize")); XCTAssertTrue(note.contains("2026-01-01"))
        XCTAssertTrue(note.contains("count=12")); XCTAssertTrue(note.contains("123.45元")); XCTAssertTrue(note.contains("rows条数=2"))
        XCTAssertTrue(note.hasSuffix("需要细节请重新查询")); XCTAssertLessThanOrEqual(note.count, 200)
        let once = messages; AssistantContextBudget.compactTools(&messages, limit: 4000); XCTAssertEqual(messages, once)
        XCTAssertTrue(messages.last?.content?.contains("依据依据") == true)
    }
}
