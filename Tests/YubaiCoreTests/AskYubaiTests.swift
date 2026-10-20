import XCTest
@testable import YubaiCore

final class AskYubaiTests: XCTestCase {
    func testNumericAnswerAndCodeChartMatchSummaryWithEvidence() async throws {
        let ctx = AssistantFixtures.context()
        let args: JSONValue = .object(["nature": .string("spending"), "group_by": .string("category")])
        let expected = try ReadOnlyTool.summarize.run(args, ctx)
        let script = ScriptedChatTransport([
            ChatMessage(role: .assistant, toolCalls: [ChatToolCall(id: "summary", name: "summarize", arguments: try args.jsonText()),
                ChatToolCall(id: "chart", name: "show_chart", arguments: try JSONValue.object(["kind": .string("summarize"), "args": args]).jsonText())]),
            ChatMessage(role: .assistant, content: "消费合计 ¥85.00，其中餐饮 ¥45.00。")])
        let reply = try await AskYubai.answer("消费按分类看看", transport: script, context: ctx)
        XCTAssertEqual(reply.unverifiedAmounts, [])
        XCTAssertFalse(reply.evidenceEntryIDs.isEmpty)
        let chart = try XCTUnwrap(reply.chart)
        XCTAssertEqual(chart.kind, .bar)
        for group in try XCTUnwrap(expected["groups"]?.arrayValue) {
            let point = try XCTUnwrap(chart.points.first { $0.label == group["group"]?.stringValue })
            XCTAssertEqual(JSONValue.money(point.cents), group["spending"])
        }
        XCTAssertEqual(chart.points.reduce(0) { $0 + $1.cents }, 8500)
    }
    func testChartKeepsExactCentsBeyondDoubleIntegerPrecision() throws {
        let ctx = AssistantFixtures.context(); var ledger = ctx.ledger
        ledger.entries = (0..<902).map { index in
            Entry(date: ctx.now, amount: Money.limit - Int64(index), accountID: ledger.accounts[0].id, title: "合成大额记录", category: "其他支出")
        }
        let expected = ledger.entries.reduce(Int64(0)) { $0 + $1.amount }
        XCTAssertGreaterThan(expected, 9_007_199_254_740_992)
        let built = try ShowChartTool().build(.object(["kind": .string("summarize"), "args": .object(["nature": .string("spending")])]), ToolContext(ledger: ledger, now: ctx.now))
        XCTAssertEqual(built.chart.points.first?.cents, expected)
    }
    func testOnlyOneChartAndModelCannotSupplyPoints() async throws {
        let ctx = AssistantFixtures.context()
        let args = #"{"kind":"summarize","args":{"nature":"spending"}}"#
        let script = ScriptedChatTransport([
            ChatMessage(role: .assistant, toolCalls: [ChatToolCall(id: "first", name: "show_chart", arguments: args), ChatToolCall(id: "second", name: "show_chart", arguments: args)]),
            ChatMessage(role: .assistant, content: "按账本汇总展示。")])
        let reply = try await AskYubai.answer("看分类图", transport: script, context: ctx)
        XCTAssertNotNil(reply.chart)
        let requests = await script.recorded()
        let results = requests[1].messages.filter { $0.role == .tool }
        XCTAssertNotNil(try JSONValue.parse(try XCTUnwrap(results.last?.content))["error"])
        XCTAssertThrowsError(try ShowChartTool().run(.object(["kind": .string("summarize"), "args": .object([:]), "points": .array([])]), ctx))
    }
    func testForecastChartEqualsEnginePath() throws {
        let ctx = AssistantFixtures.context()
        let built = try ShowChartTool().build(.object(["kind": .string("forecast"), "args": .object(["days": .number(5)])]), ctx)
        var ledger = ctx.ledger; ledger.preferences.horizonDays = 6
        let expected = Finance.funds(ledger, now: ctx.now).points.filter { $0.date <= Dates.addDays(5, to: Dates.day(ctx.now)) }
        XCTAssertEqual(built.chart.kind, .line)
        XCTAssertEqual(built.chart.points.map(\.cents), expected.map(\.conservative))
    }
    func testProtectedEditsRefuseBeforeAnyToolOrProposal() async throws {
        let ctx = AssistantFixtures.context()
        for question in ["把那笔 42 改成 24", "把那笔金额改为24", "把账户改成微信", "修改交易日期"] {
            let script = ScriptedChatTransport([])
            let reply = try await AskYubai.answer(question, transport: script, context: ctx)
            XCTAssertTrue(reply.proposedChangeSets.isEmpty); XCTAssertTrue(reply.toolTrace.isEmpty)
            XCTAssertTrue(reply.text.contains("账单与账户"))
            let calls = await script.recorded(); XCTAssertTrue(calls.isEmpty)
        }
        XCTAssertFalse(AskYubai.isProtectedEdit("把上周的美团都改成餐饮"))
        XCTAssertFalse(AskYubai.isProtectedEdit("把微信账户的美团都改成餐饮"))
    }
    func testCategoryEditOnlyProposesSetCategoryAndDoesNotWrite() async throws {
        let ctx = AssistantFixtures.context(); let before = ctx.ledger
        let id = ctx.ledger.entries[1].id
        let args: JSONValue = .object(["reason": .string("按用户要求分类"), "items": .array([.object([
            "kind": .string("set_category"), "entry": .string(id.uuidString), "category": .string("餐饮")])])])
        let script = ScriptedChatTransport([
            ChatMessage(role: .assistant, toolCalls: [ChatToolCall(id: "query", name: "query_entries", arguments: #"{"keyword":"美团","start_date":"2026-06-08","end_date":"2026-06-14"}"#)]),
            ChatMessage(role: .assistant, toolCalls: [ChatToolCall(id: "edit", name: "propose_entry_changes", arguments: try args.jsonText())]),
            ChatMessage(role: .assistant, content: "已列出这些记录，确认后归为餐饮。")])
        let reply = try await AskYubai.answer("把上周的美团都改成餐饮", transport: script, context: ctx)
        XCTAssertEqual(reply.proposedChangeSets.flatMap(\.items), [.setCategory(entry: id, category: "餐饮")])
        XCTAssertEqual(ctx.ledger, before)
    }
    func testPurchaseFactsEqualFinanceAndOmitEmptyValuesDimension() throws {
        let ctx = AssistantFixtures.context()
        let args: JSONValue = .object(["title": .string("咖啡"), "amount": .string("32"), "category": .string("餐饮")])
        let purchase = try JudgePurchaseTool().judge(args, ctx)
        let funds = Finance.funds(ctx.ledger, now: ctx.now)
        XCTAssertFalse(purchase.hasProfile); XCTAssertNil(purchase.facts["values"])
        XCTAssertEqual(purchase.facts["missing"], .string("还不知道你在乎什么，可以在『我的消费观』里补上"))
        XCTAssertEqual(purchase.facts["affordability"]?["available_after_purchase"], .money(funds.available - 3200))
        XCTAssertEqual(purchase.facts["affordability"]?["forecast"], try ReadOnlyTool.forecast.run(.object(["days": .number(0), "amount": .string("32")]), ctx))
        XCTAssertEqual(purchase.facts["habit"], try ReadOnlyTool.compareToHabit.run(.object(["category": .string("餐饮"), "amount": .string("32")]), ctx))
        var ledger = ctx.ledger
        ledger.profile.floorAmount = 5000
        ledger.profile.restrain = [ProfileArea(title: "咖啡", match: AreaMatch(categories: ["餐饮"]), note: "下午少点外卖咖啡")]
        ledger.profile.principles = ["为每天用得上的东西花钱"]
        let profiled = try JudgePurchaseTool().judge(args, ToolContext(ledger: ledger, now: ctx.now))
        XCTAssertTrue(profiled.hasProfile)
        XCTAssertEqual(profiled.facts["values"]?["restrain"]?.arrayValue?.first?["quote"], .string("下午少点外卖咖啡"))
        XCTAssertEqual(profiled.facts["affordability"]?["floor_already_reserved"], .money(5000))
        XCTAssertEqual(profiled.facts["affordability"]?["available_after_purchase"], .money(Finance.funds(ledger, now: ctx.now).available - 3200))
    }
    func testSentenceDraftAmountIsLocalAndMustBeConfirmed() async throws {
        let base = AssistantFixtures.context()
        XCTAssertEqual(EntryAmountParser.candidates(in: "午饭 32 微信"), [3200])
        XCTAssertEqual(EntryAmountParser.candidates(in: "2026-06-15 12:30 午饭 ￥32.50 2个人 订单123456789012"), [3250])
        XCTAssertEqual(EntryAmountParser.candidates(in: "订单****5678"), [])
        let args: JSONValue = .object(["reason": .string("用户午饭补记"), "title": .string("午饭"), "amount": .string("32"), "date": .string("2026-06-15"), "account": .string(base.ledger.accounts[0].id.uuidString), "category": .string("餐饮")])
        XCTAssertThrowsError(try ProposalTool.entry.propose(args, base))
        let script = ScriptedChatTransport([
            ChatMessage(role: .assistant, toolCalls: [ChatToolCall(id: "entry", name: "propose_entry", arguments: try args.jsonText())]),
            ChatMessage(role: .assistant, content: "午饭 ¥32.00，核对金额后就可以记下。")])
        let reply = try await AskYubaiSession().ask("午饭 32 微信", ledger: base.ledger, transport: script, now: base.now)
        var proposal = try XCTUnwrap(reply.proposedChangeSets.first)
        guard case .addEntry(var draft) = proposal.items[0] else { return XCTFail("missing draft") }
        XCTAssertEqual(draft.amount, 3200); XCTAssertFalse(draft.amountConfirmed)
        var ledger = base.ledger
        XCTAssertThrowsError(try proposal.apply(to: &ledger)); XCTAssertEqual(ledger, base.ledger)
        draft.amountConfirmed = true; proposal.items = [.addEntry(draft)]
        try proposal.apply(to: &ledger); XCTAssertEqual(ledger.entries.last?.amount, 3200)
        var invented = args.objectValue!; invented["amount"] = .string("99")
        XCTAssertThrowsError(try ProposalTool.entry.propose(.object(invented), ToolContext(ledger: base.ledger, now: base.now, parsedEntryAmounts: [3200])))
    }
    func testSessionRetainsConversationButRefreshesLedgerFacts() async throws {
        let ctx = AssistantFixtures.context(); let session = AskYubaiSession()
        let script = ScriptedChatTransport([ChatMessage(role: .assistant, content: "可以一起看看。"), ChatMessage(role: .assistant, content: "也可以再看看用途。")])
        _ = try await session.ask("想聊聊花费", ledger: ctx.ledger, transport: script, now: ctx.now)
        _ = try await session.ask("继续说", ledger: ctx.ledger, transport: script, now: ctx.now)
        let calls = await script.recorded()
        XCTAssertEqual(calls[1].messages.filter { $0.role == .user }.map(\.content), ["想聊聊花费", "继续说"])
    }
}
