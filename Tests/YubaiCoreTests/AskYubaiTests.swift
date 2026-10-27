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
        let expected = Finance.funds(ctx.ledger, now: ctx.now, days: 6).points.filter { $0.date <= Dates.addDays(5, to: Dates.day(ctx.now)) }
        XCTAssertEqual(built.chart.kind, .line)
        XCTAssertEqual(built.chart.points.map(\.cents), expected.map(\.conservative))
    }
    func testProtectedEditsRefuseBeforeAnyToolOrProposal() async throws {
        let ctx = AssistantFixtures.context()
        for question in ["把那笔 42 改成 24", "把那笔金额改为24", "把账户改成微信", "修改交易日期", "那笔 42.50 其实是 24"] {
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
    func testQualifiedDateEditsRefuseLocallyWithoutBlockingCategoryOrPurposeEdits() async throws {
        let ctx = AssistantFixtures.context()
        for question in ["修改原始日期", "更正交易日期", "调整发生日期", "修改记录的交易日期", "修改 交易日期", "把交易日期改为昨天", "把原始日期从昨天改成今天"] {
            let script = ScriptedChatTransport([])
            let reply = try await AskYubai.answer(question, transport: script, context: ctx)
            XCTAssertTrue(reply.text.contains("账单与账户"), question)
            XCTAssertTrue(reply.proposedChangeSets.isEmpty, question)
            XCTAssertTrue(reply.toolTrace.isEmpty, question)
            let calls = await script.recorded(); XCTAssertTrue(calls.isEmpty, question)
        }
        for question in ["把微信账户的美团都改成餐饮", "把交易日期为昨天的美团都改成餐饮", "把发生日期为昨天的转账用途改成房租分摊"] {
            XCTAssertFalse(AskYubai.isProtectedEdit(question), question)
        }
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
        ledger.profile.restrain[0].confirmedAt = Dates.addDays(-200, to: ctx.now)
        ledger.profile.principleDates[ledger.profile.principles[0]] = ctx.now
        let profiled = try JudgePurchaseTool().judge(args, ToolContext(ledger: ledger, now: ctx.now))
        XCTAssertTrue(profiled.hasProfile)
        XCTAssertEqual(profiled.facts["values"]?["restrain"]?.arrayValue?.first?["quote"], .string("下午少点外卖咖啡"))
        XCTAssertEqual(profiled.facts["values"]?["restrain"]?.arrayValue?.first?["confirmed_at"], .string(Dates.text(Dates.addDays(-200, to: ctx.now))))
        XCTAssertEqual(profiled.facts["values"]?["principles"]?.arrayValue?.first?["confirmed_at"], .string(Dates.text(ctx.now)))
        XCTAssertEqual(profiled.facts["affordability"]?["floor_target"], .money(5000))
        XCTAssertEqual(profiled.facts["affordability"]?["floor_room"], .money(funds.available - 5000))
        XCTAssertNil(profiled.facts["affordability"]?["floor_already_reserved"])
        XCTAssertEqual(profiled.facts["affordability"]?["available_after_purchase"], .money(Finance.funds(ledger, now: ctx.now).available - 3200))
    }
    func testFloorTargetAndRoomFactsAreNullableAndSharedWithFundsTool() throws {
        let now = AssistantFixtures.context().now
        var ledger = Ledger(); ledger.accounts = [Account(name: "合成账户", balance: 10_000, at: now)]
        for floor: Int64? in [nil, 0, 8000, 12_000] {
            ledger.profile.floorAmount = floor
            let ctx = ToolContext(ledger: ledger, now: now)
            let judgment = try JudgePurchaseTool().judge(.object(["title": .string("咖啡"), "amount": .string("20")]), ctx)
            let affordability = try XCTUnwrap(judgment.facts["affordability"])
            let funds = try ReadOnlyTool.getFunds.run(.object([:]), ctx)
            let target: JSONValue = floor.map { .money($0) } ?? .null
            let room: JSONValue = floor.map { .money(10_000 - $0) } ?? .null
            XCTAssertEqual(affordability["floor_target"], target); XCTAssertEqual(affordability["floor_room"], room)
            XCTAssertEqual(funds["floor_target"], target); XCTAssertEqual(funds["floor_room"], room)
            XCTAssertEqual(affordability["available"], .money(10_000)); XCTAssertEqual(affordability["available_after_purchase"], .money(8000))
            XCTAssertNil(affordability["floor_already_reserved"]); XCTAssertNil(funds["emergency"])
            XCTAssertEqual(try ReadOnlyTool.getProfile.run(.object([:]), ctx)["floor_amount"], target)
        }
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
    func testExplicitLongTermPreferenceProposesAfterReadingProfileAndDeduplicates() async throws {
        let ctx = AssistantFixtures.context(); let before = ctx.ledger
        let args = #"{"reason":"愿意为学习多花","items":[{"operation":"upsert_area","stance":"generous","title":"学习","keywords":["书"],"note":"长期愿意为学习多花"}]}"#
        let script = ScriptedChatTransport([
            ChatMessage(role: .assistant, toolCalls: [ChatToolCall(id: "profile", name: "get_profile")]),
            ChatMessage(role: .assistant, toolCalls: [ChatToolCall(id: "proposal", name: "propose_profile_change", arguments: args)]),
            ChatMessage(role: .assistant, toolCalls: [ChatToolCall(id: "repeat", name: "propose_profile_change", arguments: args)]),
            ChatMessage(role: .assistant, content: "整理成了一份提案，等你确认。")])
        let reply = try await AskYubai.answer("我长期愿意为学习多花一点", transport: script, context: ctx)
        XCTAssertEqual(reply.toolTrace.map(\.name), ["get_profile", "propose_profile_change", "propose_profile_change"])
        XCTAssertEqual(reply.proposedChangeSets.count, 1); XCTAssertTrue(reply.proposedChangeSets[0].isProfileOnly)
        XCTAssertEqual(ctx.ledger, before)
        let requests = await script.recorded()
        let results = requests.last!.messages.filter { $0.role == .tool }
        XCTAssertEqual(results[1].content, results[2].content)
        let prompt = AskYubai.prompt(now: ctx.now)
        XCTAssertTrue(prompt.contains("先get_profile")); XCTAssertTrue(prompt.contains("临时决定不要提案"))
        XCTAssertTrue(prompt.contains("超过180天"))
    }
    func testSessionCompactsOldPairsAndKeepsRecentConversation() async throws {
        let ctx = AssistantFixtures.context()
        let session = AskYubaiSession(characterBudget: AskYubai.prompt(now: ctx.now).count + Memory.prompt(ledger: ctx.ledger, now: ctx.now).count + 100)
        let script = ScriptedChatTransport([
            ChatMessage(role: .assistant, content: String(repeating: "旧回答", count: 100)),
            ChatMessage(role: .assistant, content: "用户问过旧问题，已给出旧回答。"),
            ChatMessage(role: .assistant, content: "可以继续看看。"),
            ChatMessage(role: .assistant, content: "记得刚才的问题。")])
        _ = try await session.ask(String(repeating: "旧问题", count: 100), ledger: ctx.ledger, transport: script, now: ctx.now)
        _ = try await session.ask("最近的问题", ledger: ctx.ledger, transport: script, now: ctx.now)
        let reply = try await session.ask("继续回答", ledger: ctx.ledger, transport: script, now: ctx.now)
        XCTAssertEqual(reply.text, "记得刚才的问题。")
        let requests = await script.recorded(); let messages = requests[3].messages
        XCTAssertEqual(requests.filter { $0.purpose == "对话摘要" }.count, 1)
        XCTAssertTrue(messages[2].content?.hasPrefix("前情摘要：") == true)
        XCTAssertEqual(messages.filter { $0.role == .user }.map(\.content), ["最近的问题", "继续回答"])
        XCTAssertTrue(messages.contains { $0.content == "可以继续看看。" })
        XCTAssertFalse(messages.contains { $0.role != .system && $0.content?.contains("旧问题") == true })
        let fresh = ScriptedChatTransport([ChatMessage(role: .assistant, content: "新的对话。")])
        _ = try await AskYubaiSession().ask("重新开始", ledger: ctx.ledger, transport: fresh, now: ctx.now)
        let reset = await fresh.recorded(); XCTAssertEqual(reset[0].messages.filter { $0.role == .user }.count, 1)
    }

}

private actor SummaryTestTransport: ChatTransport {
    enum Mode { case success, failure, empty, cancelled }
    let mode: Mode
    private var requests: [ChatRequest] = []
    init(_ mode: Mode) { self.mode = mode }
    func send(_ request: ChatRequest) async throws -> ChatMessage {
        requests.append(request)
        if request.purpose == "对话摘要" {
            switch mode {
            case .failure: throw URLError(.notConnectedToInternet)
            case .empty: return ChatMessage(role: .assistant, content: " \n")
            case .cancelled: throw CancellationError()
            case .success: return ChatMessage(role: .assistant, content: "用户讨论合租，仍在核对。卡号6222021234567890123")
            }
        }
        return ChatMessage(role: .assistant, content: String(repeating: "继续核对。", count: 400))
    }
    func recorded() -> [ChatRequest] { requests }
}

extension AskYubaiTests {
    func testSummaryUsesOneRequestRedactsAndStabilizesHistoryPrefix() async throws {
        let ctx = AssistantFixtures.context()
        let base = AskYubai.prompt(now: ctx.now).count + Memory.prompt(ledger: ctx.ledger, now: ctx.now).count
        let session = AskYubaiSession(characterBudget: base + 12_000)
        let transport = SummaryTestTransport(.success)
        let question = String(repeating: "核对", count: 500)
        for _ in 0..<6 { _ = try await session.ask(question, ledger: ctx.ledger, transport: transport, now: ctx.now) }
        let requests = await transport.recorded()
        let summaries = requests.filter { $0.purpose == "对话摘要" }
        XCTAssertEqual(summaries.count, 1)
        let summary = try XCTUnwrap(summaries.first)
        XCTAssertEqual(summary.temperature, 0); XCTAssertEqual(summary.maxTokens, 800); XCTAssertTrue(summary.tools.isEmpty)
        XCTAssertTrue(summary.messages[0].content?.contains("不编造金额") == true)
        let answers = requests.filter { $0.purpose == "问余白" }
        let compressed = answers[4].messages
        XCTAssertEqual(compressed[2].role, .system); XCTAssertTrue(compressed[2].content?.hasPrefix("前情摘要：") == true)
        XCTAssertFalse(compressed[2].content?.contains("6222021234567890123") == true)
        XCTAssertEqual(compressed[2], answers[5].messages[2])
        XCTAssertLessThanOrEqual(AssistantContextBudget.count(Array(compressed.dropFirst(2).dropLast())), 11_000 * 3 / 5)
        XCTAssertGreaterThan(compressed.filter { $0.role == .user }.count, 1)
    }
    func testSummaryFailureOrEmptyFallsBackWithoutLosingAnswer() async throws {
        for mode in [SummaryTestTransport.Mode.failure, .empty] {
            let ctx = AssistantFixtures.context()
            let base = AskYubai.prompt(now: ctx.now).count + Memory.prompt(ledger: ctx.ledger, now: ctx.now).count
            let session = AskYubaiSession(characterBudget: base + 100)
            let transport = SummaryTestTransport(mode)
            _ = try await session.ask("先核对", ledger: ctx.ledger, transport: transport, now: ctx.now)
            let reply = try await session.ask("继续", ledger: ctx.ledger, transport: transport, now: ctx.now)
            XCTAssertFalse(reply.text.isEmpty)
            let requests = await transport.recorded()
            XCTAssertEqual(requests.filter { $0.purpose == "对话摘要" }.count, 1)
            XCTAssertEqual(requests.last?.messages[2].content, AssistantContextBudget.historyNote)
        }
    }
    func testSummaryCancellationPropagatesAndRetainsHistoryForRetry() async throws {
        let ctx = AssistantFixtures.context()
        let base = AskYubai.prompt(now: ctx.now).count + Memory.prompt(ledger: ctx.ledger, now: ctx.now).count
        let session = AskYubaiSession(characterBudget: base + 100)
        let cancelled = SummaryTestTransport(.cancelled)
        _ = try await session.ask("旧问题", ledger: ctx.ledger, transport: cancelled, now: ctx.now)
        do { _ = try await session.ask("新问题", ledger: ctx.ledger, transport: cancelled, now: ctx.now); XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        let retry = SummaryTestTransport(.success)
        _ = try await session.ask("重试", ledger: ctx.ledger, transport: retry, now: ctx.now)
        let requests = await retry.recorded()
        XCTAssertEqual(requests.first?.purpose, "对话摘要")
        XCTAssertTrue(requests.first?.messages.last?.content?.contains("旧问题") == true)
    }
    func testHistorySliceMergesOldSummaryRemovesWholePairsAndTargetsSixtyPercent() throws {
        let previous = ChatMessage(role: .system, content: "前情摘要：之前讨论过合租")
        let turns = (0..<10).flatMap { _ in [ChatMessage(role: .user, content: String(repeating: "问", count: 80)), ChatMessage(role: .assistant, content: String(repeating: "答", count: 80))] }
        let slice = try XCTUnwrap(AssistantContextBudget.historySlice([previous] + turns, limit: 1000, reserving: 0))
        XCTAssertEqual(slice.removed.first, previous)
        XCTAssertEqual(slice.remaining.first?.role, .user); XCTAssertEqual(slice.remaining.last?.role, .assistant)
        XCTAssertEqual(slice.remaining.count % 2, 0)
        XCTAssertLessThanOrEqual(AssistantContextBudget.count(slice.remaining) + slice.summaryBudget, 600)
        XCTAssertGreaterThan(AssistantContextBudget.count(slice.remaining), 400)
        XCTAssertEqual(AssistantContextBudget.defaultLimit, 120_000)
        let tinyPairs = (0..<1000).flatMap { _ in [ChatMessage(role: .user, content: "问"), ChatMessage(role: .assistant, content: "答")] }
        XCTAssertNil(AssistantContextBudget.historySlice(tinyPairs, limit: AssistantContextBudget.defaultLimit, reserving: 0))
    }
}
