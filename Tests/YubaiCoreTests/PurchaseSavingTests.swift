import XCTest
@testable import YubaiCore

final class PurchaseSavingTests: XCTestCase {
    let now = Dates.parse("2026-10-15 12:00")!
    func seed(balance: Int64 = 1_000_000) -> Ledger {
        var ledger = Ledger(); ledger.updatedAt = now
        ledger.accounts = [Account(name: "合成账户", balance: balance, at: now)]
        return ledger
    }
    func entry(_ ledger: Ledger, title: String = "咖啡", amount: Int64 = 1000, day: Date? = nil) -> Entry {
        var entry = Entry(date: day ?? now, amount: amount, accountID: ledger.accounts[0].id, title: title, category: "餐饮")
        entry.subcategory = "咖啡饮品"; return entry
    }
    func judge(_ ledger: Ledger, amount: String = "20", title: String = "咖啡") throws -> PurchaseJudgment {
        try JudgePurchaseTool().judge(.object(["title": .string(title), "amount": .string(amount), "category": .string("餐饮"), "subcategory": .string("咖啡饮品")]), ToolContext(ledger: ledger, now: now))
    }
    func call(_ id: String, _ name: String, _ args: JSONValue) throws -> ChatMessage {
        ChatMessage(role: .assistant, toolCalls: [ChatToolCall(id: id, name: name, arguments: try args.jsonText())])
    }
    func testPurchaseBoundsMoneyOverridesPreferenceAndZeroIsAllowed() throws {
        var ledger = seed(balance: 2000)
        ledger.profile.generous = [ProfileArea(title: "咖啡", match: .init(categories: ["餐饮"]))]
        let skip = PurchaseBounds.compute(ledger: ledger, amount: 2001, title: "咖啡", category: "餐饮", now: now)
        XCTAssertEqual(skip.allowedVerdicts, [.skip]); XCTAssertTrue(skip.boundReason.contains(Money.text(-1)))
        XCTAssertEqual(PurchaseBounds.compute(ledger: ledger, amount: 2000, title: "咖啡", category: "餐饮", now: now).allowedVerdicts, Set(PurchaseVerdict.allCases))
    }
    func testPurchaseBoundsCountMonthAndSubcategoryMatching() throws {
        var ledger = seed(); ledger.entries = [entry(ledger)]
        ledger.profile.restrain = [ProfileArea(title: "咖啡", match: .init(subcategories: ["餐饮/咖啡饮品"]), softLimit: .init(perWeekCount: 1, perMonthAmount: 3000))]
        XCTAssertEqual(try judge(ledger).facts["allowed_verdicts"], .strings(["wait", "skip"]))
        ledger.profile.restrain[0].softLimit?.perWeekCount = 3
        XCTAssertEqual(PurchaseBounds.compute(ledger: ledger, amount: 2000, title: "咖啡", category: "餐饮", subcategory: "咖啡饮品", now: now).allowedVerdicts, Set(PurchaseVerdict.allCases))
        let over = PurchaseBounds.compute(ledger: ledger, amount: 2001, title: "咖啡", category: "餐饮", subcategory: "咖啡饮品", now: now)
        XCTAssertEqual(over.allowedVerdicts, [.wait, .skip]); XCTAssertTrue(over.boundReason.contains("本月已花"))
        XCTAssertEqual(PurchaseBounds.compute(ledger: ledger, amount: 2001, title: "午餐", category: "餐饮", subcategory: "午餐", now: now).allowedVerdicts, Set(PurchaseVerdict.allCases))
    }
    func testPurchaseBoundsFloorTargetCapsAtWaitUntilRealCashRunsOut() {
        var ledger = seed(balance: 10_000); ledger.profile.floorAmount = 8000
        func bounds(_ amount: Int64) -> PurchaseBounds { PurchaseBounds.compute(ledger: ledger, amount: amount, title: "咖啡", now: now) }
        let below = bounds(2001)
        XCTAssertEqual(below.allowedVerdicts, [.wait, .skip])
        XCTAssertEqual(below.boundReason, "买了以后离始终留着的 \(Money.text(8000)) 还差 \(Money.text(1))。")
        XCTAssertEqual(bounds(10_000).allowedVerdicts, [.wait, .skip])
        XCTAssertEqual(bounds(10_001).allowedVerdicts, [.skip]); XCTAssertEqual(bounds(10_001).boundReason, "买了以后还能花 \(Money.text(-1))。")
        for amount: Int64 in [1999, 2000] { XCTAssertEqual(bounds(amount).allowedVerdicts, Set(PurchaseVerdict.allCases)) }
        XCTAssertEqual(Finance.assessPurchase(ledger, amount: 2001, now: now).verdict, .wait)
        XCTAssertEqual(Finance.assessPurchase(ledger, amount: 2001, now: now).reason, below.boundReason)
        for floor: Int64? in [nil, 0] {
            ledger.profile.floorAmount = floor
            XCTAssertEqual(bounds(10_000).allowedVerdicts, Set(PurchaseVerdict.allCases))
        }
    }
    func testBoundsPrecedenceIsCashThenFloorThenEquallyStrictRestrainLimits() {
        var ledger = seed(balance: 10_000); ledger.profile.floorAmount = 8000
        ledger.profile.restrain = [ProfileArea(title: "咖啡", match: .init(keywords: ["咖啡"]), softLimit: .init(perWeekCount: 0, perMonthAmount: 1000))]
        func bounds(_ amount: Int64) -> PurchaseBounds { PurchaseBounds.compute(ledger: ledger, amount: amount, title: "咖啡", now: now) }
        // Both floor and restrain allow wait/skip; the earlier floor rule keeps its reason.
        XCTAssertEqual(bounds(2001).allowedVerdicts, [.wait, .skip]); XCTAssertEqual(bounds(2001).boundReason, "买了以后离始终留着的 \(Money.text(8000)) 还差 \(Money.text(1))。")
        XCTAssertEqual(bounds(10_001).allowedVerdicts, [.skip]); XCTAssertFalse(bounds(10_001).boundReason.contains("始终留着"))
        XCTAssertEqual(bounds(2000).allowedVerdicts, [.wait, .skip]); XCTAssertTrue(bounds(2000).boundReason.contains("每周最多 0 次"))
        ledger.profile.restrain[0].softLimit?.perWeekCount = nil
        XCTAssertEqual(bounds(2000).allowedVerdicts, [.wait, .skip]); XCTAssertTrue(bounds(2000).boundReason.contains("本月已花"))
    }
    func testFloorGapReasonCanBeSubmittedButBuyIsRejected() throws {
        var ledger = seed(balance: 10_000); ledger.profile.floorAmount = 8000
        let judgment = try judge(ledger, amount: "20.01"); let ctx = ToolContext(ledger: ledger, now: now)
        XCTAssertEqual(judgment.facts["allowed_verdicts"], .strings(["wait", "skip"]))
        let reason = try XCTUnwrap(judgment.facts["bound_reason"]?.stringValue)
        for verdict in ["wait", "skip"] {
            XCTAssertNoThrow(try SubmitVerdictTool().submit(.object(["verdict": .string(verdict), "need": .string("want"), "reason": .string(reason)]), judgment: judgment, context: ctx))
        }
        XCTAssertThrowsError(try SubmitVerdictTool().submit(.object(["verdict": .string("buy"), "need": .string("want"), "reason": .string(reason)]), judgment: judgment, context: ctx))
    }
    func testRuleVerdictsUseMoneySoftLimitThenOneThird() {
        var ledger = seed(balance: 9000)
        XCTAssertEqual(Finance.assessPurchase(ledger, amount: 9001, now: now).verdict, .skip)
        XCTAssertEqual(Finance.assessPurchase(ledger, amount: 3001, now: now).verdict, .wait)
        XCTAssertEqual(Finance.assessPurchase(ledger, amount: 3000, now: now).verdict, .buy)
        ledger.profile.restrain = [ProfileArea(title: "咖啡", match: .init(keywords: ["咖啡"]), softLimit: .init(perWeekCount: 0))]
        let assessment = Finance.assessPurchase(ledger, amount: 100, title: "咖啡", now: now)
        XCTAssertEqual(assessment.verdict, .wait); XCTAssertTrue(assessment.reason.contains("每周最多 0 次"))
    }
    func testInvalidAIVerdictReturnsToolErrorAndRequiresReselection() async throws {
        let ledger = seed(balance: 1000); let judgment = try judge(ledger, amount: "20")
        let args: JSONValue = .object(["title": .string("咖啡"), "amount": .string("20"), "category": .string("餐饮")])
        let invalid: JSONValue = .object(["verdict": .string("buy"), "need": .string("want"), "reason": .string(judgment.facts["bound_reason"]!.stringValue!)])
        var valid = invalid.objectValue!; valid["verdict"] = .string("skip")
        let transport = ScriptedChatTransport([try call("judge", "judge_purchase", args), try call("bad", "submit_verdict", invalid),
            ChatMessage(role: .assistant, content: "买吧。"), try call("retry", "submit_verdict", .object(valid)), ChatMessage(role: .assistant, content: "先别买，买了以后还能花 -¥10.00。")])
        let reply = try await AskYubai.answer("直接给结论", transport: transport, context: .init(ledger: ledger, now: now))
        XCTAssertEqual(reply.purchaseVerdict?.verdict, .skip)
        XCTAssertEqual(reply.purchaseVerdict?.need, .want)
        let requests = await transport.recorded()
        let result = try XCTUnwrap(requests[2].messages.last(where: { $0.role == .tool })?.content)
        XCTAssertNotNil(try JSONValue.parse(result)["error"])
        XCTAssertTrue(requests[3].messages.last?.content?.contains("submit_verdict") == true)
    }
    func testVerdictReasonMustBeOneGroundedSentenceAndMemoryIDsMustExist() throws {
        var ledger = seed(); let note = MemoryNote(text: "打算长期徒步旅行", kind: .plan, source: .chat, createdAt: now)
        ledger.memories = [note]; let ctx = ToolContext(ledger: ledger, now: now); let judgment = try judge(ledger)
        func submit(_ reason: String, ids: [String] = []) throws -> SubmittedPurchaseVerdict {
            try SubmitVerdictTool().submit(.object(["verdict": .string("buy"), "need": .string("need"), "reason": .string(reason), "memory_ids": .strings(ids)]), judgment: judgment, context: ctx)
        }
        XCTAssertThrowsError(try submit("挺好的，值得买。"))
        XCTAssertThrowsError(try submit(String(repeating: "很", count: 61)))
        XCTAssertThrowsError(try submit("你说过长期徒步。现在买吧。", ids: [note.id.uuidString]))
        XCTAssertThrowsError(try submit("本周已有999次。"))
        XCTAssertThrowsError(try submit("你说过长期徒步旅行。", ids: [UUID().uuidString]))
        let verdict = try submit("你说过打算长期徒步旅行。", ids: [note.id.uuidString])
        XCTAssertEqual(verdict.usedMemoryIDs, [note.id])
        XCTAssertNoThrow(try submit(judgment.facts["bound_reason"]!.stringValue!))
    }
    func testPurchaseQuestionsTerminateTurnAndPreserveRememberedFacts() async throws {
        let ledger = seed()
        let questions: JSONValue = .object(["questions": .array([.object(["text": .string("这双登山鞋，你预计多久穿一次？"), "options": .strings(["每周", "每月", "还没想好"])])])])
        let transport = ScriptedChatTransport([try call("memory", "remember", .object(["text": .string("打算长期徒步"), "kind": .string("plan")])),
            ChatMessage(role: .assistant, toolCalls: [ChatToolCall(id: "ask", name: "ask_purchase_questions", arguments: try questions.jsonText()), ChatToolCall(id: "unused", name: "get_funds")])])
        let reply = try await AskYubaiSession().ask("我打算长期徒步，登山鞋要不要买", ledger: ledger, transport: transport, now: now)
        XCTAssertEqual(reply.purchaseQuestions?.first?.options.count, 3)
        XCTAssertEqual(reply.rememberedNotes.first?.text, "打算长期徒步")
        XCTAssertFalse(reply.toolTrace.contains { $0.name == "get_funds" })
        let recorded = await transport.recorded(); XCTAssertEqual(recorded.count, 2)
    }
    func testQuestionValidationAndDirectVerdictOptOut() async throws {
        let tool = AskPurchaseQuestionsTool()
        for input in [#"{"questions":[]}"#, #"{"questions":[{"text":"用吗？","options":["会"]}]}"#, #"{"questions":[{"text":"用吗？","options":["会","会"]}]}"#, #"{"questions":[{"text":"用吗？","options":["会","不会"],"extra":1}]}"#] {
            XCTAssertThrowsError(try tool.questions(JSONValue.parse(input)))
        }
        let transport = ScriptedChatTransport([try call("ask", "ask_purchase_questions", JSONValue.parse(#"{"questions":[{"text":"用吗？","options":["会","不会"]}]}"#)), ChatMessage(role: .assistant, content: "先核对这件东西的金额。")])
        let reply = try await AskYubai.answer("直接给结论", transport: transport, context: .init(ledger: seed(), now: now))
        XCTAssertNil(reply.purchaseQuestions)
        let requests = await transport.recorded(); XCTAssertTrue(requests[1].messages.last?.content?.contains("跳过提问") == true)
    }
    func testSimilarFollowupsIncludeCategoryAndTitleButExcludeUnanswered() throws {
        var ledger = seed(); var first = WishItem(title: "咖啡杯", amount: 3000); first.followUpAnswer = "值得：天天用"; first.followUpAnsweredAt = Dates.addDays(-3, to: now)
        var second = WishItem(title: "新杯子", amount: 5000); second.category = "餐饮"; second.followUpAnswer = "有点后悔"; second.followUpAnsweredAt = Dates.addDays(-1, to: now)
        var unrelated = WishItem(title: "电视", amount: 50_000); unrelated.followUpAnswer = "一般"
        ledger.wishlist = [first, second, unrelated, WishItem(title: "咖啡", amount: 1000)]
        let rows = try XCTUnwrap(judge(ledger).facts["similar_followups"]?.arrayValue)
        XCTAssertEqual(rows.map { $0["title"]?.stringValue }, ["新杯子", "咖啡杯"])
        XCTAssertEqual(rows.last?["answer"], .string("值得")); XCTAssertNotNil(rows.first?["date"])
    }
    func testRestrainProgressCountsRefundsAndStates() {
        var ledger = seed(); var purchase = entry(ledger, amount: 10_000); purchase.subcategory = "外卖"
        var refund = Entry(date: now, amount: 2000, nature: .refund, accountID: ledger.accounts[0].id, title: "退回"); refund.relatedEntryID = purchase.id
        ledger.entries = [purchase, refund]
        ledger.profile.restrain = [ProfileArea(title: "外卖", match: .init(subcategories: ["餐饮/外卖"]), softLimit: .init(perWeekCount: 2, perMonthAmount: 10_000)), ProfileArea(title: "未设次数")]
        var progress = RestrainProgress.current(ledger: ledger, now: now)
        XCTAssertEqual(progress.count, 1); XCTAssertEqual(progress[0].weekCount, 1); XCTAssertEqual(progress[0].monthAmount, 8000); XCTAssertEqual(progress[0].status, .near)
        ledger.profile.restrain[0].softLimit?.perMonthAmount = 7999
        progress = RestrainProgress.current(ledger: ledger, now: now); XCTAssertEqual(progress[0].status, .over)
        ledger.profile.restrain[0].softLimit?.perMonthAmount = 20_000
        XCTAssertEqual(RestrainProgress.current(ledger: ledger, now: now)[0].status, .normal)
    }
    func testCooldownThresholdsAndDueCardKeepDropAreIdempotent() throws {
        XCTAssertEqual([19_999, 20_000, 100_000, 100_001].map { Wishlist.defaultCooldownDays(amount: $0) }, [0, 3, 3, 7])
        var ledger = seed(); let verdict = SubmittedPurchaseVerdict(verdict: .wait, reason: "先看看使用频率。", need: .unclear, boundReason: "合成依据")
        let wish = try Wishlist.add(fromVerdict: verdict, title: "鞋子", amount: 20_000, in: &ledger, now: now)
        XCTAssertEqual(wish.source, "fromVerdict"); let due = try XCTUnwrap(wish.coolUntil)
        XCTAssertTrue(Wishlist.cooldownDue(ledger, now: due.addingTimeInterval(-1)).isEmpty)
        let card = try XCTUnwrap(ButlerCards.detect(ledger, now: due).first { $0.kind == .cooldownDue })
        XCTAssertEqual(card.title, "鞋子，还想要吗？"); XCTAssertEqual(card.dedupeKey, "cooldown:\(wish.id)")
        _ = ButlerCards.refresh(&ledger, candidates: [card], now: due)
        XCTAssertTrue(ButlerCards.detect(ledger, now: due).filter { $0.kind == .cooldownDue }.isEmpty)
        try Wishlist.answerCooldown(wish.id, choice: .keep, in: &ledger, now: due)
        XCTAssertEqual(ledger.wishlist[0].status, .thinking); XCTAssertNil(ledger.wishlist[0].coolUntil)
        XCTAssertThrowsError(try Wishlist.answerCooldown(wish.id, choice: .drop, in: &ledger, now: due))
        let drop = try Wishlist.add(fromVerdict: verdict, title: "相机", amount: 200_000, in: &ledger, now: now)
        try Wishlist.answerCooldown(drop.id, choice: .drop, in: &ledger, now: drop.coolUntil!)
        XCTAssertEqual(ledger.wishlist.last?.droppedAt, drop.coolUntil)
        XCTAssertEqual(Savings.total(ledger: ledger, now: drop.coolUntil!), 200_000)
    }
    func testSavingsExcludeLegacyDropsThinkingBoughtAndOutsideInterval() {
        var ledger = seed()
        var legacy = WishItem(title: "旧放弃", amount: 1000); legacy.status = .dropped
        var drop = WishItem(title: "真放弃", amount: 2000); drop.status = .dropped; drop.droppedAt = now
        var thinking = WishItem(title: "还在想", amount: 3000); thinking.droppedAt = now
        var bought = thinking; bought.id = UUID(); bought.status = .bought
        var outside = drop; outside.id = UUID(); outside.droppedAt = Dates.addDays(-1, to: now)
        ledger.wishlist = [legacy, drop, thinking, bought, outside]
        let summary = Savings.summary(ledger: ledger, from: now, to: now.addingTimeInterval(1))
        XCTAssertEqual(summary.total, 2000); XCTAssertEqual(summary.lines.map(\.sourceID), [drop.id])
        XCTAssertEqual(Savings.total(ledger: ledger, now: now), 4000)
    }
}
