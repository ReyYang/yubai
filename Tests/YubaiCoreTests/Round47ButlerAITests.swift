import XCTest
@testable import YubaiCore

final class Round47ButlerAITests: XCTestCase {
    let now = Dates.parse("2026-11-20 20:00")!
    func seed() -> Ledger {
        var ledger = Ledger(); ledger.updatedAt = now; ledger.profile.updatedAt = now
        ledger.preferences.cloudAIEnabled = true; ledger.preferences.butlerSuggestionsEnabled = true
        let account = Account(name: "合成账户", balance: 2_000_000, at: Dates.addDays(-200, to: now))
        ledger.accounts = [account]
        for i in 0..<7 {
            var row = Entry(date: Dates.addDays(-i - 1, to: now), amount: [3600, 3200, 2800, 3000, 2600, 3100, 3100][i], accountID: account.id, title: "合成外卖", category: "餐饮")
            row.id = UUID(uuidString: String(format: "47000000-0000-0000-0000-%012d", i + 1))!
            ledger.entries.append(row)
        }
        for i in 0..<12 {
            ledger.entries.append(Entry(date: Dates.addDays(-35 - i * 6, to: now), amount: 2000, accountID: account.id, title: "合成午饭", category: "餐饮"))
        }
        ledger.memories = [MemoryNote(id: UUID(uuidString: "47000000-0000-0000-0000-000000000099")!, text: "吃上不省，但不想为了累多花钱。", kind: .value, source: .chat, createdAt: Dates.addDays(-23, to: now))]
        return ledger
    }
    func row(_ ledger: Ledger, topic: String = "外卖", action: JSONValue = .object(["kind": .string("try_two_weeks"), "review": .string("带饭怎么样？")])) -> JSONValue {
        .object(["topic": .string(topic), "observation": .array([.object(["text": .string("外卖 ")]), .object(["count": .bool(true)]),
            .object(["text": .string(" 次，共 ")]), .object(["sum": .bool(true)])]),
            "proposal": .array([.object(["text": .string("。试试带饭？")])]),
            "entry_ids": .array(ledger.entries.prefix(7).map { .string($0.id.uuidString) }),
            "claimed_count": .number(7), "claimed_sum_cents": .number(21400), "action": action,
            "memory_ids": .array(ledger.memories.map { .string($0.id.uuidString) })])
    }
    func changed(_ row: JSONValue, _ key: String, _ value: JSONValue) -> JSONValue {
        var fields = row.objectValue!; fields[key] = value; return .object(fields)
    }
    func parsed(_ rows: [JSONValue], ledger: Ledger) -> [ButlerSuggestion] {
        ButlerSuggestionVerifier.parse(.array(rows), digest: ButlerDigest.build(ledger, now: now), ledger: ledger, now: now)
    }
    func queued(_ row: JSONValue? = nil) throws -> Ledger {
        var ledger = seed()
        ButlerIntelligence.enqueue(parsed([row ?? self.row(ledger)], ledger: ledger), in: &ledger, now: now)
        XCTAssertEqual(ledger.butlerAI?.suggestions.count, 1); return ledger
    }
    func testDigestIsDeterministicAndHasNoRawHistory() throws {
        let ledger = seed(), digest = ButlerDigest.build(ledger, now: now)
        var shuffled = ledger; shuffled.entries.reverse()
        XCTAssertEqual(digest, ButlerDigest.build(shuffled, now: now))
        let json = try digest.json().jsonText()
        XCTAssertFalse(json.contains("accountID")); XCTAssertFalse(json.contains("合成账户")); XCTAssertFalse(json.contains("recordedAt"))
        XCTAssertEqual(digest.candidateIDs, Set(ledger.entries.prefix(7).map(\.id)))
        XCTAssertFalse(digest.candidateIDs.contains(ledger.entries.last!.id))
        XCTAssertEqual(digest.categories.first?.count, 7); XCTAssertEqual(digest.categories.first?.sumCents, 21400)
        XCTAssertEqual(digest.categories.first?.usualCount, 4); XCTAssertEqual(digest.categories.first?.usualSumCents, 8000)
        XCTAssertEqual(digest.newMerchants, ["合成外卖"])
    }
    func testDigestExcludesFutureDeletedTransfersAndStartsExactlyFourWeeksAgo() {
        var ledger = seed(); let account = ledger.accounts[0].id
        var future = Entry(date: now.addingTimeInterval(1), amount: 1000, accountID: account, title: "未来")
        var deleted = future; deleted.id = UUID(); deleted.date = now; deleted.deletedAt = now
        future.nature = .expense
        let transfer = Entry(date: now, amount: 1000, nature: .transfer, accountID: account, title: "移动")
        let edge = Entry(date: Dates.addDays(-27, to: Dates.day(now)), amount: 1000, accountID: account, title: "边界")
        ledger.entries += [future, deleted, transfer, edge]
        let digest = ButlerDigest.build(ledger, now: now)
        XCTAssertTrue(digest.candidateIDs.contains(edge.id))
        for value in [future, deleted, transfer] { XCTAssertFalse(digest.candidateIDs.contains(value.id)) }
    }
    func testDigestContainsRecurringWishesSavingsValuesAndDatedMemories() {
        var ledger = seed(); ledger.fixedSavings = 50_000; ledger.savingRule = .fixed(2000)
        ledger.wishlist = [WishItem(title: "相机", amount: 860_000)]
        ledger.profile.principles = ["吃上不省"]
        ledger.plans = [Plan(title: "视频会员", amount: 2500, dueDate: now, frequency: .monthly, category: "订阅")]
        let digest = ButlerDigest.build(ledger, now: now)
        XCTAssertEqual(digest.recurringCharges.first?.id, ledger.plans.first?.id)
        XCTAssertEqual(digest.wishes.first?.amountCents, 860_000)
        XCTAssertEqual(digest.saving.savedCents, 50_000); XCTAssertEqual(digest.profile.principles, ["吃上不省"])
        XCTAssertEqual(digest.memories, ledger.memories)
    }
    func testOldMerchantOutsideBaselineIsNotCalledNewOrSentAsRawHistory() throws {
        var ledger = seed()
        let old = Entry(date: Dates.addDays(-180, to: now), amount: 9900, accountID: ledger.accounts[0].id, title: "合成外卖", category: "餐饮")
        ledger.entries.append(old)
        let digest = ButlerDigest.build(ledger, now: now)
        XCTAssertFalse(digest.newMerchants.contains("合成外卖"))
        XCTAssertFalse(try digest.json().jsonText().contains(old.id.uuidString))
    }
    func testValidReplyVerifiedAndNumbersRenderedByCode() throws {
        let ledger = try queued(), value = ledger.butlerAI!.suggestions[0]
        XCTAssertEqual(value.count, 7); XCTAssertEqual(value.sumCents, 21400)
        XCTAssertEqual(value.text(value.observation), "外卖 7 次，共 214.00")
        XCTAssertEqual(value.text(value.observation, hidden: true), "外卖 7 次，共 ••••")
        XCTAssertTrue(HomeButler.queue(ledger, now: now).contains(.suggestion(value)))
    }
    func testWrongSumDropsOnlyThatSuggestion() {
        let ledger = seed(), valid = row(ledger, topic: "有效")
        XCTAssertEqual(parsed([changed(row(ledger), "claimed_sum_cents", .number(21401)), valid], ledger: ledger).map(\.topic), ["有效"])
    }
    func testWrongCountUnknownIDRepeatedIDAndOutOfWindowIDAreDropped() {
        let ledger = seed(), valid = row(ledger)
        for bad in [changed(valid, "claimed_count", .number(6)),
                    changed(valid, "entry_ids", .array([.string(UUID().uuidString)])),
                    changed(valid, "entry_ids", .array(Array(repeating: .string(ledger.entries[0].id.uuidString), count: 7))),
                    changed(valid, "entry_ids", .array(ledger.entries.suffix(7).map { .string($0.id.uuidString) }))] {
            XCTAssertTrue(parsed([bad], ledger: ledger).isEmpty)
        }
    }
    func testUnknownActionExtraParameterAndUnknownMemoryAreDropped() {
        let ledger = seed()
        for bad in [row(ledger, action: .object(["kind": .string("send_money")])),
                    row(ledger, action: .object(["kind": .string("never_mention"), "url": .string("arbitrary")])),
                    changed(row(ledger), "memory_ids", .array([.string(UUID().uuidString)]))] {
            XCTAssertTrue(parsed([bad], ledger: ledger).isEmpty)
        }
    }
    func testRawNumeralsAndFractionalOrHugeClaimsAreDropped() {
        let ledger = seed(), valid = row(ledger)
        XCTAssertTrue(parsed([changed(valid, "proposal", .array([.object(["text": .string("能省 999 元")])]))], ledger: ledger).isEmpty)
        for number in [21400.5, Double.infinity, 9_007_199_254_740_992] {
            XCTAssertTrue(parsed([changed(valid, "claimed_sum_cents", .number(number))], ledger: ledger).isEmpty)
        }
    }
    func testBoardWeekdayProposalSurvivesNumericGuardButChineseMoneyDoesNot() {
        let ledger = seed(), value = row(ledger)
        let board = changed(value, "proposal", .array([.object(["text": .string("。周三周四试试带饭？")])]))
        XCTAssertEqual(parsed([board], ledger: ledger).count, 1)
        let invented = changed(value, "proposal", .array([.object(["text": .string("每次省三十元")])]))
        XCTAssertTrue(parsed([invented], ledger: ledger).isEmpty)
    }
    func testNoSuggestionCountCapAndEmptyReplyIsValid() async throws {
        let ledger = seed()
        XCTAssertEqual(parsed((0..<25).map { row(ledger, topic: "主题\($0)") }, ledger: ledger).count, 25)
        let script = ScriptedChatTransport([ChatMessage(role: .assistant, content: #"{"suggestions":[]}"#)])
        let values = try await ButlerIntelligence.run(ledger: ledger, transport: script, now: now)
        XCTAssertTrue(values.isEmpty)
        let requests = await script.recorded(); XCTAssertEqual(requests.count, 1); XCTAssertEqual(requests.first?.thinking, false)
    }
    func testMalformedAndFencedJSONRejectedWithoutMutation() async throws {
        let ledger = seed()
        for content in ["not json", #"{"suggestions":{}}"#, "```json\n{\"suggestions\":[]}\n```", #"{"suggestions":[],"extra":true}"#] {
            let script = ScriptedChatTransport([ChatMessage(role: .assistant, content: content)])
            do { _ = try await ButlerIntelligence.run(ledger: ledger, transport: script, now: now); XCTFail(content) } catch { }
            XCTAssertNil(ledger.butlerAI)
        }
    }
    func testWeeklyReflectionAndSuggestionsUseOneRequestAndPersistTogether() async throws {
        var ledger = seed()
        let output: JSONValue = .object(["add": .array([]), "update": .array([]), "remove": .array([]), "learned": .array([]), "suggestions": .array([row(ledger)])])
        let script = ScriptedChatTransport([ChatMessage(role: .assistant, content: try output.jsonText())])
        let result = try await MemoryReflection.run(ledger: ledger, transport: script, now: now, includeButler: true)
        try result.apply(to: &ledger, now: now)
        XCTAssertEqual(ledger.butlerAI?.suggestions.count, 1); XCTAssertEqual(ledger.lastReflectionWeek, ButlerCards.isoWeek(now))
        let requests = await script.recorded(); XCTAssertEqual(requests.count, 1)
        let input = try JSONValue.parse(requests[0].messages.last!.content!)
        XCTAssertNotNil(input["butler_digest"]); XCTAssertNil(input["last_week"])
    }
    func testWrongWeeklySuggestionDoesNotBlockMemoryDistillation() async throws {
        var ledger = seed()
        let output: JSONValue = .object(["add": .array([.object(["text": .string("准备搬家"), "kind": .string("plan")])]), "update": .array([]), "remove": .array([]), "learned": .array([]), "suggestions": .array([changed(row(ledger), "claimed_sum_cents", .number(1))])])
        let result = try await MemoryReflection.run(ledger: ledger, transport: ScriptedChatTransport([ChatMessage(role: .assistant, content: try output.jsonText())]), now: now, includeButler: true)
        try result.apply(to: &ledger, now: now)
        XCTAssertEqual(ledger.memories.last?.text, "准备搬家"); XCTAssertTrue(ledger.butlerAI!.suggestions.isEmpty)
    }
    func testWeeklyCadencePersistsAttemptAndNoOrdinaryOpenRequests() throws {
        var ledger = seed(); ledger.entries = []
        XCTAssertEqual(ButlerCadence.due(ledger, now: now, suggestions: true), [.weekly])
        ButlerCadence.recordAttempt([.weekly], in: &ledger, now: now)
        let decoded = try JSONDecoder().decode(Ledger.self, from: JSONEncoder().encode(ledger))
        XCTAssertEqual(decoded.butlerAI?.lastRunAt, now)
        for hours in [0, 1, 24, 48, 72, 144] {
            XCTAssertTrue(ButlerCadence.due(decoded, now: now.addingTimeInterval(Double(hours * 3600)), suggestions: true).isEmpty)
        }
        XCTAssertEqual(ButlerCadence.due(decoded, now: Dates.addDays(7, to: now), suggestions: true), [.weekly])
    }
    func testSpikeIsAtLeastDoubleUsualAndRunsOncePerEpisode() {
        var ledger = seed(); ledger.lastReflectionWeek = ButlerCards.isoWeek(now)
        let triggers = ButlerCadence.due(ledger, now: now, suggestions: true)
        XCTAssertEqual(triggers, [.spike("餐饮")])
        ButlerCadence.recordAttempt(triggers, in: &ledger, now: now)
        XCTAssertTrue(ButlerCadence.due(ledger, now: now.addingTimeInterval(30), suggestions: true).isEmpty)
        ledger.butlerAI = nil; ledger.entries[0].amount = 1; ledger.entries[1].amount = 1
        XCTAssertTrue(ButlerCadence.due(ledger, now: now, suggestions: true).isEmpty)
    }
    func testSustainedSpikeAcrossWeekBoundaryDoesNotTriggerAgainUntilItFalls() {
        var ledger = seed(); ledger.lastReflectionWeek = ButlerCards.isoWeek(now)
        ButlerCadence.recordAttempt([.weekly, .spike("餐饮")], in: &ledger, now: now)
        XCTAssertTrue(ButlerCadence.due(ledger, now: Dates.addDays(3, to: now), suggestions: true).isEmpty)
        ledger.entries[0].amount = 1; ledger.entries[1].amount = 1
        let ended = ButlerCadence.endedSpikes(ledger, now: now)
        XCTAssertEqual(ended, ["餐饮"]); ButlerCadence.endSpikes(ended, in: &ledger)
        ledger.entries[0].amount = 3600; ledger.entries[1].amount = 3200
        XCTAssertEqual(ButlerCadence.due(ledger, now: now, suggestions: true), [.spike("餐饮")])
    }
    func testPaydayCloseRunsOnlyAfterActualIncomeOnce() {
        var ledger = seed(); ledger.entries = []; ledger.lastReflectionWeek = ButlerCards.isoWeek(now)
        var salary = Plan(title: "工资", amount: 800_000, dueDate: Dates.day(now), frequency: .monthly, inflow: true, category: "工资", nature: .income)
        salary.accountID = ledger.accounts[0].id; ledger.plans = [salary]
        XCTAssertTrue(ButlerCadence.due(ledger, now: now, suggestions: true).isEmpty)
        var income = Entry(date: now, amount: 800_000, nature: .income, accountID: ledger.accounts[0].id, title: "工资", category: "工资")
        income.planID = salary.id; income.occurrence = Dates.day(now); ledger.entries = [income]
        let triggers = ButlerCadence.due(ledger, now: now, suggestions: true)
        XCTAssertEqual(triggers.count, 1)
        if case .payday = triggers.first! {} else { XCTFail() }
        ButlerCadence.recordAttempt(triggers, in: &ledger, now: now)
        XCTAssertTrue(ButlerCadence.due(ledger, now: now, suggestions: true).isEmpty)
    }
    func testTrialSchedulesExactlyFourteenDaysAndAnswerBecomesMemory() throws {
        var ledger = try queued(); let id = ledger.butlerAI!.suggestions[0].id
        try ButlerSuggestions.answer(id, .accept, in: &ledger, now: now)
        let review = try XCTUnwrap(ledger.butlerAI?.reviews.first)
        XCTAssertEqual(review.dueAt, Dates.addDays(14, to: now)); XCTAssertTrue(ledger.memories.last!.text.contains("试两周"))
        XCTAssertTrue(ledger.memories.last!.text.contains("试试带饭"))
        XCTAssertFalse(HomeButler.queue(ledger, now: review.dueAt.addingTimeInterval(-1)).contains(.suggestionReview(review)))
        XCTAssertTrue(HomeButler.queue(ledger, now: review.dueAt).contains(.suggestionReview(review)))
        XCTAssertThrowsError(try ButlerSuggestions.answer(id, .accept, in: &ledger, now: now))
    }
    func testNeverMeansPersistentTopicMuteAndNextDigestIncludesAnswer() throws {
        var ledger = try queued(); let id = ledger.butlerAI!.suggestions[0].id
        try ButlerSuggestions.answer(id, .never, in: &ledger, now: now)
        XCTAssertTrue(ledger.mutedTopics.contains("ai:外卖"))
        XCTAssertTrue(parsed([row(ledger)], ledger: ledger).isEmpty)
        XCTAssertTrue(ButlerDigest.build(ledger, now: now).memories.contains { $0.text.contains("以后不再提") })
        let decoded = try JSONDecoder().decode(Ledger.self, from: JSONEncoder().encode(ledger))
        XCTAssertTrue(decoded.mutedTopics.contains("ai:外卖"))
    }
    func testCorrectionWithOptionalSentenceBecomesMemoryAndDoesNotMute() throws {
        for sentence in ["", "周四是和同事拼单"] {
            var ledger = try queued(); let id = ledger.butlerAI!.suggestions[0].id
            try ButlerSuggestions.answer(id, .incorrect(sentence), in: &ledger, now: now)
            XCTAssertTrue(ledger.memories.contains { $0.text.contains("说得不对") })
            if !sentence.isEmpty { XCTAssertTrue(ledger.memories.last!.text.contains(sentence)) }
            XCTAssertTrue(ledger.mutedTopics.isEmpty)
        }
    }
    func testCorrectionKeepsTheEntireMaximumLengthSentence() throws {
        var ledger = try queued()
        let sentence = String(repeating: "这", count: 200)
        try ButlerSuggestions.answer(ledger.butlerAI!.suggestions[0].id, .incorrect(sentence), in: &ledger, now: now)
        XCTAssertEqual(ledger.memories.last?.text, sentence)
        XCTAssertTrue(ButlerDigest.build(ledger, now: now).memories.contains { $0.text == sentence })
    }
    func testStaleEditedDeletedOrChangedMemoryEvidenceCannotActOrEnterQueue() throws {
        for change in 0..<3 {
            var ledger = try queued(); let value = ledger.butlerAI!.suggestions[0]
            if change == 0 { ledger.entries[0].amount += 1 }
            if change == 1 { ledger.entries[0].deletedAt = now }
            if change == 2 { ledger.memories.removeAll() }
            XCTAssertTrue(ButlerSuggestions.queued(ledger, now: now).isEmpty)
            let before = ledger
            XCTAssertThrowsError(try ButlerSuggestions.answer(value.id, .accept, in: &ledger, now: now))
            XCTAssertEqual(ledger, before)
        }
    }
    func testBudgetActionExecutesInCore() throws {
        let source = seed()
        var ledger = try queued(row(source, action: .object(["kind": .string("set_budget"), "category": .string("餐饮"), "amount_cents": .number(50000)])))
        try ButlerSuggestions.answer(ledger.butlerAI!.suggestions[0].id, .accept, in: &ledger, now: now)
        XCTAssertEqual(ledger.spendingParts.first?.amount, 50000); XCTAssertEqual(ledger.spendingParts.first?.categories, ["餐饮"])
    }
    func testCategoryBudgetDoesNotOverwriteAnExistingCombinedBudget() throws {
        var ledger = seed(); ledger.spendingParts = [SpendingPart(name: "日常", amount: 90000, categories: ["餐饮", "交通"])]
        let value = parsed([row(ledger, action: .object(["kind": .string("set_budget"), "category": .string("餐饮"), "amount_cents": .number(50000)]))], ledger: ledger)[0]
        ButlerIntelligence.enqueue([value], in: &ledger, now: now)
        try ButlerSuggestions.answer(value.id, .accept, in: &ledger, now: now)
        XCTAssertEqual(ledger.spendingParts.first?.categories, ["交通"]); XCTAssertEqual(ledger.spendingParts.first?.amount, 90000)
        XCTAssertEqual(ledger.spendingParts.last?.categories, ["餐饮"]); XCTAssertEqual(ledger.spendingParts.last?.amount, 50000)
    }
    func testAddWishAndNeverMentionActionsExecuteInCore() throws {
        for action: JSONValue in [.object(["kind": .string("add_wish"), "title": .string("饭盒"), "amount_cents": .number(12000)]), .object(["kind": .string("never_mention")])] {
            var ledger = seed(); let values = parsed([row(ledger, action: action)], ledger: ledger)
            ButlerIntelligence.enqueue(values, in: &ledger, now: now)
            try ButlerSuggestions.answer(values[0].id, .accept, in: &ledger, now: now)
            if action["kind"] == .string("add_wish") { XCTAssertEqual(ledger.wishlist.first?.amount, 12000) }
            else { XCTAssertTrue(ledger.mutedTopics.contains("ai:外卖")) }
        }
    }
    func testStopSubscriptionExecutesCodeAndPreservesHistory() throws {
        var ledger = seed()
        let plan = Plan(title: "视频会员", amount: 2500, dueDate: Dates.addDays(1, to: now), frequency: .monthly, category: "订阅")
        ledger.plans = [plan]; let entries = ledger.entries
        let value = parsed([row(ledger, action: .object(["kind": .string("stop_subscription"), "plan_id": .string(plan.id.uuidString)]))], ledger: ledger)[0]
        ButlerIntelligence.enqueue([value], in: &ledger, now: now)
        try ButlerSuggestions.answer(value.id, .accept, in: &ledger, now: now)
        XCTAssertEqual(ledger.plans.first?.stoppedAt, now); XCTAssertEqual(ledger.entries, entries)
    }
    func testSaveLeftoverUsesExactClosedCycleAndCannotRunTwice() throws {
        var ledger = seed()
        ledger.savingHistory = [CycleSaving(cycleStart: Dates.addDays(-40, to: now), cycleEnd: Dates.addDays(-10, to: now), income: 800_000, target: 200_000, saved: 200_000, unspent: 12345)]
        let start = Dates.text(ledger.savingHistory[0].cycleStart)
        let value = parsed([row(ledger, action: .object(["kind": .string("save_leftover"), "cycle_start": .string(start)]))], ledger: ledger)[0]
        ButlerIntelligence.enqueue([value], in: &ledger, now: now)
        try ButlerSuggestions.answer(value.id, .accept, in: &ledger, now: now)
        XCTAssertEqual(ledger.fixedSavings, 12345)
        XCTAssertThrowsError(try ButlerSuggestions.answer(value.id, .accept, in: &ledger, now: now))
    }
    func testRefundAndPersonalShareUseFinanceMathExactly() {
        var ledger = seed(); ledger.entries[0].personalExpense = 1800; ledger.entries[1].nature = .refund
        let sum = ledger.entries.prefix(7).reduce(Int64(0)) { $0 + Finance.spendingAmount($1, ledger: ledger) }
        XCTAssertEqual(parsed([changed(row(ledger), "claimed_sum_cents", .number(Double(sum)))], ledger: ledger).first?.sumCents, sum)
    }
    func testCodeFactsAndMathRemainAvailableWithAIOff() throws {
        var ledger = try queued(); ledger.preferences.cloudAIEnabled = false
        let funds = Finance.funds(ledger, now: now)
        XCTAssertTrue(ButlerSuggestions.queued(ledger, now: now).isEmpty)
        var offline = ledger; offline.butlerAI = nil
        XCTAssertEqual(Finance.funds(offline, now: now), funds)
        XCTAssertEqual(HomeButler.queue(offline, now: now), HomeButler.queue(ledger, now: now))
    }
    func testOldLedgerDecodesWithSuggestionsOffAndNoRunDates() throws {
        let data = try JSONEncoder().encode(seed())
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "butlerAI")
        var preferences = object["preferences"] as! [String: Any]; preferences.removeValue(forKey: "butlerSuggestionsEnabled"); object["preferences"] = preferences
        let old = try JSONDecoder().decode(Ledger.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(old.butlerAI); XCTAssertFalse(old.preferences.isAIEnabled(for: .butlerSuggestions))
    }
    func testExplicitFrequentTemplateCreatesNoTransactionAndPersistsBeyondWindow() throws {
        var ledger = Ledger()
        try EntryHistory.addRepeat(purpose: "午饭", amount: 2800, in: &ledger, now: now)
        XCTAssertTrue(ledger.entries.isEmpty)
        XCTAssertEqual(EntryHistory.repeats(in: ledger, now: Dates.addDays(60, to: now)).first?.amount, 2800)
        XCTAssertThrowsError(try EntryHistory.addRepeat(purpose: "", amount: 2800, in: &ledger, now: now))
    }
}
