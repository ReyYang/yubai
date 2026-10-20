import XCTest
@testable import YubaiCore

final class MemoryTests: XCTestCase {
    private let now = Dates.parse("2026-10-20 12:00")!
    private func seed() -> Ledger {
        var ledger = Ledger(); ledger.updatedAt = now; ledger.profile.updatedAt = now
        ledger.accounts = [Account(name: "合成账户", balance: 1_000_000, at: Dates.addDays(-100, to: now))]
        return ledger
    }
    private func note(_ text: String = "和室友合租", kind: MemoryKind = .life, age: Int = 10) -> MemoryNote {
        MemoryNote(text: text, kind: kind, source: .user, createdAt: Dates.addDays(-age, to: now))
    }
    private func rows(_ block: JSONValue) -> [JSONValue] { MemoryKind.allCases.flatMap { block[$0.rawValue]?.arrayValue ?? [] } }
    private func call(_ id: String, _ tool: String, _ args: JSONValue) throws -> ChatMessage {
        ChatMessage(role: .assistant, toolCalls: [ChatToolCall(id: id, name: tool, arguments: try args.jsonText())])
    }
    func testRememberWritesOnlyWhenAppliedAndUndoDeletes() async throws {
        var ledger = seed(); let before = ledger
        let args: JSONValue = .object(["text": .string("明年想搬去离公司近的地方"), "kind": .string("plan")])
        let script = ScriptedChatTransport([try call("save", "remember", args),
            try call("read", "recall", .object(["kind": .string("plan")])),
            // A nonconsecutive identical write must not create another note.
            try call("again", "remember", args), ChatMessage(role: .assistant, content: "记下了，可以随时修改。")])
        let reply = try await AskYubai.answer("我打算搬家", transport: script, context: ToolContext(ledger: ledger, now: now))
        XCTAssertEqual(ledger, before); XCTAssertTrue(reply.proposedChangeSets.isEmpty)
        XCTAssertEqual(reply.rememberedNotes.count, 1); XCTAssertTrue(reply.updatedNotes.isEmpty)
        let saved = try XCTUnwrap(reply.rememberedNotes.first)
        XCTAssertEqual(saved.source, .chat); XCTAssertEqual(saved.kind, .plan); XCTAssertEqual(reply.usedMemoryIDs, [saved.id])
        let requests = await script.recorded()
        let toolRows = requests.last!.messages.filter { $0.role == .tool }.compactMap { $0.content.flatMap { try? JSONValue.parse($0) } }
        XCTAssertEqual(toolRows[0]["remembered"]?["id"], .string(saved.id.uuidString))
        XCTAssertEqual(toolRows[1]["memories"]?.arrayValue?.count, 1)
        try Memory.apply(reply, to: &ledger, now: now)
        XCTAssertEqual(ledger.memories.first?.lastUsedAt, now)
        Memory.undo(noteID: saved.id, in: &ledger, now: now)
        XCTAssertTrue(ledger.memories.isEmpty)
    }
    func testReplacesKeepsOriginalWordsAcrossMultipleUpdatesAndUndoRestores() async throws {
        var ledger = seed(); let old = note(); ledger.memories = [old]
        let first: JSONValue = .object(["text": .string("准备独自住"), "kind": .string("plan"), "replaces": .string(old.id.uuidString)])
        let last: JSONValue = .object(["text": .string("下个月开始独自住"), "kind": .string("life"), "replaces": .string(old.id.uuidString)])
        let script = ScriptedChatTransport([try call("a", "remember", first), try call("b", "remember", last), ChatMessage(role: .assistant, content: "已更新这条记忆。")])
        let reply = try await AskYubai.answer("居住情况变了", transport: script, context: ToolContext(ledger: ledger, now: now))
        XCTAssertTrue(reply.rememberedNotes.isEmpty); XCTAssertEqual(reply.updatedNotes.count, 1)
        XCTAssertEqual(reply.updatedNotes.first?.previous, old); XCTAssertEqual(reply.updatedNotes.first?.note.previousText, old.text)
        try Memory.apply(reply, to: &ledger, now: now)
        XCTAssertEqual(ledger.memories[0].id, old.id); XCTAssertEqual(ledger.memories[0].createdAt, old.createdAt)
        XCTAssertEqual(ledger.memories[0].text, "下个月开始独自住"); XCTAssertEqual(ledger.memories[0].previousText, old.text)
        Memory.undo(noteID: old.id, in: &ledger, now: now)
        XCTAssertEqual(ledger.memories[0].text, old.text); XCTAssertNil(ledger.memories[0].previousText)
        XCTAssertEqual(ledger.profile, seed().profile)
    }
    func testBadRememberArgumentsAreRejectedWithoutWrites() throws {
        let ledger = seed(); let ctx = ToolContext(ledger: ledger, now: now)
        for args in [JSONValue.object(["text": .string(" "), "kind": .string("life")]),
                     .object(["text": .string(String(repeating: "字", count: 201)), "kind": .string("life")]),
                     .object(["text": .string("长期计划"), "kind": .string("secret")]),
                     .object(["text": .string("长期计划"), "kind": .string("plan"), "replaces": .string(UUID().uuidString)]),
                     .object(["text": .string("长期计划"), "kind": .string("plan"), "entry_ids": .strings([UUID().uuidString])]),
                     .object(["text": .string("长期\n计划"), "kind": .string("plan")])] {
            XCTAssertThrowsError(try MemoryTool.remember.run(args, ctx))
        }
        XCTAssertTrue(ledger.memories.isEmpty)
    }
    func testFailedConversationDiscardsStagedWrites() async throws {
        let ledger = seed(); let before = ledger
        let script = ScriptedChatTransport([try call("save", "remember", .object(["text": .string("长期搬家计划"), "kind": .string("plan")]))])
        do {
            _ = try await AskYubai.answer("记下这个计划", transport: script, context: ToolContext(ledger: ledger, now: now))
            XCTFail("Transport failure must not return a partial reply")
        } catch { XCTAssertEqual(ledger, before) }
    }
    func testManyRememberCallsHaveNoFixedLimitAndEvidenceIsChecked() async throws {
        var ledger = seed()
        let entry = Entry(date: now, amount: 1000, accountID: ledger.accounts[0].id, title: "合成支出")
        ledger.entries = [entry]
        let calls = try (0..<24).map { index in
            try call("m\(index)", "remember", .object(["text": .string("长期计划事项\(index)"), "kind": .string("plan"), "entry_ids": .strings([entry.id.uuidString])]))
        }
        let script = ScriptedChatTransport(calls + [ChatMessage(role: .assistant, content: "已经记下这些计划。")])
        let reply = try await AskYubai.answer("记下计划", transport: script, context: ToolContext(ledger: ledger, now: now))
        XCTAssertEqual(reply.rememberedNotes.count, 24)
        XCTAssertTrue(reply.rememberedNotes.allSatisfy { $0.evidence == [entry.id] })
        try Memory.apply(reply, to: &ledger, now: now); XCTAssertEqual(ledger.memories.count, 24)
    }
    func testContextBudgetPrioritizesRecentlyUsedAndRecallSearchesOmittedNotes() throws {
        var ledger = seed()
        let recent = note(String(repeating: "新", count: 180), kind: .plan, age: 1)
        var used = note(String(repeating: "用", count: 180), kind: .value, age: 100); used.lastUsedAt = now
        let old = note("旧的合租情况" + String(repeating: "旧", count: 170), age: 200)
        ledger.memories = [old, recent, used]
        let budget = 600
        let block = Memory.context(ledger: ledger, now: now, characterBudget: budget)
        XCTAssertLessThanOrEqual(try block.jsonText().count, budget)
        XCTAssertEqual(rows(block).count, 1); XCTAssertEqual(rows(block).first?["id"], .string(used.id.uuidString))
        XCTAssertEqual(block["omitted_count"], .number(2)); XCTAssertNotNil(block["recall_hint"])
        ledger.memories[2].lastUsedAt = nil
        let byUpdate = Memory.context(ledger: ledger, now: now, characterBudget: budget)
        XCTAssertEqual(rows(byUpdate).first?["id"], .string(recent.id.uuidString))
        let recall = try MemoryTool.recall.run(.object(["keyword": .string("合租"), "kind": .string("life")]), ToolContext(ledger: ledger, now: now, memoryCharacterBudget: budget))
        XCTAssertEqual(recall["memories"]?.arrayValue?.first?["id"], .string(old.id.uuidString))
        XCTAssertEqual(rows(Memory.context(ledger: ledger, now: now, characterBudget: Int.max)).count, 3)
        XCTAssertEqual(Memory.context(ledger: ledger, now: now, characterBudget: 0)["omitted_count"], .number(3))
        ledger.memories = (0..<30).map { note("合成背景\($0)") }
        XCTAssertEqual(rows(Memory.context(ledger: ledger, now: now)).count, 30)
    }
    func testRecallAndPurchaseReferencesMarkOnlyUsedMemories() async throws {
        var ledger = seed(); let home = note(); let plan = note("每年想去旅行", kind: .plan)
        ledger.memories = [home, plan]
        let script = ScriptedChatTransport([try call("recall", "recall", .object(["keyword": .string("合租")])),
            try call("judge", "judge_purchase", .object(["title": .string("旅行箱"), "amount": .string("100"), "memory_ids": .strings([plan.id.uuidString])])),
            ChatMessage(role: .assistant, content: "可以结合你的旅行计划考虑。")])
        let reply = try await AskYubai.answer("买个旅行箱怎么样", transport: script, context: ToolContext(ledger: ledger, now: now))
        XCTAssertEqual(Set(reply.usedMemoryIDs), Set([home.id, plan.id])); XCTAssertTrue(reply.updatedNotes.isEmpty)
        try Memory.apply(reply, to: &ledger, now: now)
        XCTAssertTrue(ledger.memories.allSatisfy { $0.lastUsedAt == now })
        XCTAssertTrue(ledger.memories.allSatisfy { $0.updatedAt == home.updatedAt })
        let unreferenced = try JudgePurchaseTool().judge(.object(["title": .string("旅行箱"), "amount": .string("100")]), ToolContext(ledger: ledger, now: now))
        XCTAssertTrue(unreferenced.usedMemoryIDs.isEmpty)
        XCTAssertNotNil(unreferenced.facts["memories"])
        XCTAssertThrowsError(try JudgePurchaseTool().judge(.object(["title": .string("旅行箱"), "amount": .string("100"), "memory_ids": .strings([UUID().uuidString])]), ToolContext(ledger: ledger, now: now)))
    }
    func testSnapshotAndConcurrentEditRejectionAreAtomic() async throws {
        var ledger = seed(); let old = note(); ledger.memories = [old]
        let script = ScriptedChatTransport([try call("save", "remember", .object(["text": .string("独自住"), "kind": .string("life"), "replaces": .string(old.id.uuidString)])), ChatMessage(role: .assistant, content: "已更新。")])
        let reply = try await AskYubai.answer("我搬家了", transport: script, context: ToolContext(ledger: ledger, now: now))
        ledger.memories[0].text = "用户刚刚改过的原话"
        let before = ledger
        XCTAssertThrowsError(try Memory.apply(reply, to: &ledger, now: now)); XCTAssertEqual(ledger, before)
        ledger = seed()
        XCTAssertThrowsError(try Memory.apply(reply, to: &ledger, now: now))
    }
    func testBackgroundIsRedactedInEveryAssistantPathAndUUIDsSurvive() async throws {
        var ledger = seed()
        let id = UUID(uuidString: "12345678-1234-4abc-8def-123456789012")!
        ledger.memories = [MemoryNote(id: id, text: "和张三吃饭，卡号6222021234567890", kind: .life, source: .user, createdAt: now)]
        let answer = ScriptedChatTransport([ChatMessage(role: .assistant, content: "我记得你的生活背景。")])
        _ = try await AskYubai.answer("了解我吗", transport: answer, context: ToolContext(ledger: ledger, now: now))
        let cold = ScriptedChatTransport([ChatMessage(role: .assistant, content: "你愿意为哪些事情多花一点？")])
        _ = try await ProfileColdStart(transport: cold).next(ledger: ledger, messages: [], now: now)
        let wording = ScriptedChatTransport([ChatMessage(role: .assistant, content: "bad optional wording")])
        let candidate = try XCTUnwrap(WeeklyLetter.candidate(ledger, now: now))
        _ = await ButlerWording.word([candidate], ledger: ledger, transport: wording, now: now)
        for requests in [await answer.recorded(), await cold.recorded(), await wording.recorded()] {
            let message = try XCTUnwrap(requests[0].messages.first { $0.role == .system && $0.content?.contains("memories") == true }?.content)
            XCTAssertFalse(message.contains("张三")); XCTAssertFalse(message.contains("6222021234567890"))
            let block = try JSONValue.parse(Redactor(ledger: ledger).content(message))["memories"]!
            XCTAssertEqual(rows(block).first?["id"], .string(id.uuidString))
            XCTAssertEqual(rows(block).first?["updated"], .string("2026-10-20"))
            XCTAssertEqual(rows(block).first?["days_since_updated"], .number(0))
        }
        let profile = try ReadOnlyTool.getProfile.run(.object([:]), ToolContext(ledger: ledger, now: now))
        XCTAssertEqual(rows(profile["memories"]!).first?["id"], .string(id.uuidString))
    }
    func testFollowUpSavesOnlyFreeTextPreservingChoiceAndLength() throws {
        for choice in FollowUpChoice.allCases {
            var ledger = seed()
            var wish = WishItem(title: "合成椅子", amount: 1000)
            wish.status = .bought; wish.createdAt = Dates.addDays(-40, to: now); wish.followUpAt = Dates.addDays(-1, to: now)
            ledger.wishlist = [wish]
            try Wishlist.answerFollowUp(wish.id, choice: choice, text: "坐着不合适" + String(repeating: "字", count: 220), in: &ledger, now: now)
            XCTAssertEqual(ledger.memories.count, 1); XCTAssertEqual(ledger.memories[0].source, .followUp)
            XCTAssertEqual(ledger.memories[0].kind, .value); XCTAssertEqual(ledger.memories[0].text.count, 200)
            XCTAssertTrue(ledger.memories[0].text.contains("觉得" + choice.rawValue))
            XCTAssertThrowsError(try Wishlist.answerFollowUp(wish.id, choice: choice, text: "重复回答", in: &ledger, now: now))
            try ledger.validate()
            ledger = seed(); ledger.wishlist = [wish]
            try Wishlist.answerFollowUp(wish.id, choice: choice, text: " \n ", in: &ledger, now: now)
            XCTAssertTrue(ledger.memories.isEmpty)
        }
    }
    func testLedgerRoundTripLegacyDecodeEqualityAndValidation() throws {
        var ledger = seed(); ledger.memories = [note()]; ledger.lastReflectionWeek = ButlerCards.isoWeek(now)
        XCTAssertEqual(try LedgerCodec.decode(LedgerCodec.encode(ledger)), ledger)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: LedgerCodec.encode(ledger)) as? [String: Any])
        json.removeValue(forKey: "memories"); json.removeValue(forKey: "lastReflectionWeek")
        let old = try LedgerCodec.decode(JSONSerialization.data(withJSONObject: json))
        XCTAssertTrue(old.memories.isEmpty); XCTAssertNil(old.lastReflectionWeek); XCTAssertNotEqual(old, ledger)
        json["schema"] = 1
        let legacy = try LedgerCodec.decode(JSONSerialization.data(withJSONObject: json))
        XCTAssertTrue(legacy.memories.isEmpty); XCTAssertNil(legacy.lastReflectionWeek)
        for invalid in ["", "  ", String(repeating: "字", count: 201)] {
            ledger.memories = [note(invalid)]; XCTAssertThrowsError(try ledger.validate())
        }
        ledger.memories = [note()]; ledger.memories.append(ledger.memories[0]); XCTAssertThrowsError(try ledger.validate())
        ledger.memories = [note()]; ledger.memories[0].updatedAt = Date(timeIntervalSince1970: 8_000_000_000)
        XCTAssertThrowsError(try ledger.validate())
        ledger.memories = [note()]; ledger.memories[0].lastUsedAt = Date(timeIntervalSince1970: .nan)
        XCTAssertThrowsError(try ledger.validate())
        ledger.memories = [note()]; ledger.memories[0].createdAt = Dates.addDays(1, to: now)
        XCTAssertThrowsError(try ledger.validate())
        ledger.memories = [note()]; ledger.memories[0].previousText = " "
        XCTAssertThrowsError(try ledger.validate())
        ledger.memories = []; ledger.lastReflectionWeek = "2026-W99"; XCTAssertThrowsError(try ledger.validate())
    }
    func testMemoryMergeUsesNewerEditsAndDoesNotResurrectChosenDeletion() {
        var chosen = seed(); let shared = note("旧原话"); chosen.memories = [shared]
        var deleted = note("已删除的事"); deleted.updatedAt = now; var other = chosen
        other.memories[0].text = "较新的原话"; other.memories[0].updatedAt = now
        other.memories[0].previousText = shared.text; other.memories.append(deleted)
        var future = note("选定版本之后的新事"); future.updatedAt = Dates.addDays(1, to: now); other.memories.append(future)
        chosen.memories[0].lastUsedAt = now
        let merged = LedgerMemoryMerge.merge(chosen: chosen, others: [other])
        XCTAssertEqual(merged.memories.first?.text, "较新的原话"); XCTAssertEqual(merged.memories.first?.lastUsedAt, now)
        XCTAssertFalse(merged.memories.contains { $0.id == deleted.id }); XCTAssertTrue(merged.memories.contains { $0.id == future.id })
        var tie = other; tie.memories[0].text = "同时间另一个版本"
        XCTAssertEqual(LedgerMemoryMerge.merge(chosen: merged, others: [tie]).memories.first?.text, "较新的原话")
        other.id = UUID(); XCTAssertEqual(LedgerMemoryMerge.merge(chosen: chosen, others: [other]), chosen)
    }
}
