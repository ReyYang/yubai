import XCTest
@testable import YubaiCore

final class ButlerTests: XCTestCase {
    func testFullCardBatchHasJSONBudgetWithoutThinkingAndAcceptsFences() async throws {
        let candidates = (0..<12).map { index in
            CardCandidate(kind: .restrain, dedupeKey: "batch-\(index)", evidence: [], facts: [], title: "原观察", body: "原正文", action: .openEvidence, priority: 0)
        }
        let title = String(repeating: "字", count: 14), body = String(repeating: "文", count: 60)
        let cards: [JSONValue] = candidates.indices.map { .object(["key": .string("c\($0)"), "title": .string(title), "body": .string(body)]) }
        let json = try JSONValue.object(["cards": .array(cards)]).jsonText()
        let script = ScriptedChatTransport([ChatMessage(role: .assistant, content: "```json\n" + json + "\n```")])
        let result = await ButlerWording.word(candidates, ledger: seed(), transport: script, now: now)
        XCTAssertEqual(result.map(\.body), Array(repeating: body, count: 12))
        let requests = await script.recorded()
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.thinking, false)
        XCTAssertGreaterThanOrEqual(request.maxTokens, 12 * 256)
    }
    private let now = Dates.parse("2026-06-17 12:00")!
    private func seed() -> Ledger {
        var ledger = Ledger()
        ledger.accounts = [Account(name: "合成账户", balance: 1_000_000, at: Dates.addDays(-10, to: now))]
        return ledger
    }
    private func expense(_ ledger: Ledger, amount: Int64 = 2000, title: String = "外卖", date: Date? = nil, category: String = "餐饮") -> Entry {
        Entry(date: date ?? now, amount: amount, accountID: ledger.accounts[0].id, title: title, category: category)
    }
    private func restrained() -> Ledger {
        var ledger = seed()
        ledger.profile.restrain = [ProfileArea(title: "外卖", match: AreaMatch(keywords: ["外卖"]), softLimit: SoftLimit(perWeekCount: 2, perMonthAmount: 5000))]
        ledger.entries = [expense(ledger), expense(ledger, amount: 4000)]
        return ledger
    }
    func testExactlyOneRestrainForBothLimitsAndNoNeutralOrGenerousCard() {
        var ledger = restrained()
        let cards = ButlerCards.detect(ledger, now: now)
        XCTAssertEqual(cards.count, 1); XCTAssertEqual(cards.first?.kind, .restrain)
        XCTAssertEqual(cards.first?.priority, 1)
        XCTAssertEqual(Set(cards.first?.evidence ?? []), Set(ledger.entries.map(\.id)))
        XCTAssertEqual(cards.first?.facts.first { $0.label == "本月消费" }?.cents, 6000)
        ledger.profile.restrain = []
        ledger.entries = [expense(ledger, amount: 500_000, title: "大件", category: "日用购物")]
        XCTAssertTrue(ButlerCards.detect(ledger, now: now).isEmpty)
        ledger.profile.generous = [ProfileArea(title: "购物", match: AreaMatch(categories: ["日用购物"]))]
        XCTAssertTrue(ButlerCards.detect(ledger, now: now).isEmpty)
    }
    func testNearLineOnlyAtEightyPercentAndRefundPersonalShare() {
        var ledger = seed()
        ledger.profile.restrain = [ProfileArea(title: "外卖", match: AreaMatch(keywords: ["外卖"]), softLimit: SoftLimit(perMonthAmount: 10_000))]
        var entry = expense(ledger, amount: 20_000); entry.personalExpense = 7999; ledger.entries = [entry]
        XCTAssertTrue(ButlerCards.detect(ledger, now: now).isEmpty)
        ledger.entries[0].personalExpense = 8000
        XCTAssertEqual(ButlerCards.detect(ledger, now: now).first?.priority, 2)
        var refund = expense(ledger, amount: 2000, title: "退款"); refund.nature = .refund; refund.relatedEntryID = entry.id
        ledger.entries.append(refund)
        XCTAssertTrue(ButlerCards.detect(ledger, now: now).isEmpty)
    }
    func testRentShortfallUsesCashOnlyEvenWhenRemainderIsBelowFloor() {
        var ledger = seed(); ledger.accounts[0].anchorBalance = 100_000
        ledger.profile.floorAmount = 20_000
        ledger.plans = [Plan(title: "房租", amount: 110_000, dueDate: Dates.addDays(5, to: now))]
        ledger.preferences.horizonDays = 7 // Detection still looks 30 days ahead.
        let cards = ButlerCards.detect(ledger, now: now)
        XCTAssertEqual(cards.count, 1); XCTAssertEqual(cards.first?.kind, .shortfall)
        XCTAssertEqual(cards.first?.facts.first { $0.label == "付款前及当天最少还能花" }?.cents, -10_000)
        for amount: Int64 in [70_000, 90_000, 100_000] {
            ledger.plans[0].amount = amount
            XCTAssertTrue(ButlerCards.detect(ledger, now: now).isEmpty, "现金仍不小于零；低于始终留着目标不触发缺口卡")
        }
        ledger.plans[0].dueDate = Dates.addDays(31, to: now); ledger.plans[0].amount = 200_000
        XCTAssertTrue(ButlerCards.detect(ledger, now: now).isEmpty)
    }
    func testShortfallFloorFactIsContextOnlyAndRequiresAnExplicitTarget() throws {
        var ledger = seed(); ledger.accounts[0].anchorBalance = 100_000
        ledger.plans = [Plan(title: "房租", amount: 110_000, dueDate: Dates.addDays(5, to: now))]
        for floor: Int64? in [nil, 0, 20_000] {
            ledger.profile.floorAmount = floor
            let card = try XCTUnwrap(ButlerCards.detect(ledger, now: now).first { $0.kind == .shortfall })
            XCTAssertEqual(card.facts.first { $0.label == "付款前及当天最少还能花" }?.cents, -10_000)
            XCTAssertEqual(card.facts.first { $0.label == "存下的钱" }?.cents, 0)
        }
    }
    func testUpkeepAgingAndActivity() {
        var ledger = seed(); ledger.accounts[0].anchorDate = Dates.addDays(-31, to: now)
        XCTAssertTrue(ButlerCards.detect(ledger, now: now).isEmpty)
        var entry = expense(ledger, date: Dates.addDays(-4, to: now)); entry.nature = .unknownIn
        ledger.entries = [entry]
        XCTAssertEqual(Set(ButlerCards.detect(ledger, now: now).map(\.kind)), Set([.unknownInflow, .staleBalance]))
        ledger.entries[0].date = Dates.addDays(-3, to: now)
        XCTAssertEqual(ButlerCards.detect(ledger, now: now).map(\.kind), [.staleBalance])
    }
    func testUpkeepIncludesSameDayRecordingAfterAnchorButNotEarlierDays() {
        var ledger = seed(); let anchor = Dates.addDays(-31, to: now); ledger.accounts[0].anchorDate = anchor
        var entry = expense(ledger, date: Dates.day(anchor)); entry.recordedAt = anchor.addingTimeInterval(60)
        ledger.entries = [entry]
        let cards = ButlerCards.detect(ledger, now: now)
        XCTAssertEqual(cards.map(\.kind), [.staleBalance]); XCTAssertEqual(cards.first?.evidence, [entry.id])
        ledger.entries[0].recordedAt = anchor
        XCTAssertTrue(ButlerCards.detect(ledger, now: now).isEmpty)
        ledger.entries[0].recordedAt = now; ledger.entries[0].date = Dates.addDays(-1, to: Dates.day(anchor))
        XCTAssertTrue(ButlerCards.detect(ledger, now: now).isEmpty)
    }
    func testMuteStableTopicDedupeDismissalAndNoOpRefresh() throws {
        var ledger = restrained()
        XCTAssertTrue(ButlerCards.refresh(&ledger, now: now))
        let saved = ledger
        XCTAssertFalse(ButlerCards.refresh(&ledger, now: now)); XCTAssertEqual(ledger, saved)
        ledger.cards[0].dismissedAt = now
        XCTAssertTrue(ButlerCards.detect(ledger, now: now).isEmpty)
        ButlerCards.mute(ledger.cards[0].id, in: &ledger, now: now)
        XCTAssertEqual(ledger.mutedTopics, ["restrain:" + ledger.profile.restrain[0].id.uuidString])
        // Move the expenses into next week; weekly dedupe changes, stable mute remains.
        let nextWeek = Dates.addDays(7, to: now)
        for i in ledger.entries.indices { ledger.entries[i].date = nextWeek }
        XCTAssertTrue(ButlerCards.detect(ledger, now: nextWeek).isEmpty)
        let restored = try LedgerCodec.decode(LedgerCodec.encode(ledger))
        XCTAssertEqual(restored.cards, ledger.cards)
    }
    func testAnswerDismissesWithoutMutingAndSurvivesPersistence() throws {
        for value in [CardFeedback.worth, .regret] {
            var ledger = restrained()
            _ = ButlerCards.refresh(&ledger, now: now)
            let card = try XCTUnwrap(ButlerCards.visible(ledger).first)
            let before = ledger
            ButlerCards.feedback(value, cardID: card.id, in: &ledger, now: now)
            let answered = try XCTUnwrap(ledger.cards.first { $0.id == card.id })
            XCTAssertEqual(answered.feedback, value)
            XCTAssertEqual(answered.feedbackAt, now)
            XCTAssertEqual(answered.dismissedAt, now)
            XCTAssertEqual(answered.evidence, card.evidence)
            XCTAssertTrue(ButlerCards.queued(ledger).isEmpty)
            XCTAssertTrue(ledger.mutedTopics.isEmpty)
            let saved = try LedgerCodec.decode(LedgerCodec.encode(ledger))
            XCTAssertEqual(saved.cards, ledger.cards)
            XCTAssertTrue(ButlerCards.detect(saved, now: now).isEmpty)
            var legacy = saved
            legacy.cards[0].dismissedAt = nil // Old versions kept answered cards open.
            XCTAssertTrue(ButlerCards.queued(legacy).isEmpty)
            ButlerCards.feedback(value, cardID: card.id, in: &ledger, now: Dates.addDays(1, to: now))
            XCTAssertEqual(ledger, saved) // Repeated completion cannot replace the first answer.
            XCTAssertEqual(ButlerCards.visible(before).map(\.id), [card.id])
            XCTAssertNil(before.cards.first?.feedback)
        }
    }
    func testFiveVisibleCardsInPriorityOrderAndOverflowRemainsQueued() {
        var ledger = seed()
        let kinds: [CardKind] = [.answerQuestion, .staleBalance, .unknownInflow, .restrain, .shortfall, .restrain, .offCharacter]
        let priorities = [5, 4, 3, 2, 0, 1, 5]
        ledger.cards = kinds.enumerated().map { index, kind in
            var card = ButlerCard(kind: kind, title: "合成卡片", body: "观察", dedupeKey: "test:\(index)")
            if kind == .unknownInflow {
                let entry = Entry(date: now, amount: 100, nature: .unknownIn, accountID: ledger.accounts[0].id, title: "合成进账")
                ledger.entries.append(entry); card.evidence = [entry.id]
            }
            card.priority = priorities[index]; card.createdAt = now; return card
        }
        XCTAssertEqual(ButlerCards.visible(ledger).map(\.priority), [0, 1, 5, 2, 3])
        XCTAssertEqual(ledger.cards.filter { $0.dismissedAt == nil }.count, 7)
        let id = ButlerCards.visible(ledger)[0].id
        ledger.cards[ledger.cards.firstIndex { $0.id == id }!].dismissedAt = now
        XCTAssertEqual(ButlerCards.visible(ledger).count, 5)
        XCTAssertEqual(ButlerCards.visible(ledger).last?.priority, 4)
    }
    func testFallbackAndUnverifiedAIAmountAndOneBatch() async throws {
        let ledger = restrained(); let candidates = ButlerCards.detect(ledger, now: now)
        let local = await ButlerWording.word(candidates, ledger: ledger, transport: nil)
        XCTAssertEqual(local, candidates)
        let bad = ScriptedChatTransport([ChatMessage(role: .assistant, content: try JSONValue.object(["cards": .array([
            .object(["key": .string("c0"), "title": .string("外卖到线了"), "body": .string("本月消费 ¥999.00。")])])]).jsonText())])
        let rejected = await ButlerWording.word(candidates, ledger: ledger, transport: bad)
        XCTAssertEqual(rejected, candidates)
        let requests = await bad.recorded(); XCTAssertEqual(requests.count, 1)
        XCTAssertNotNil(requests[0].groupID); XCTAssertEqual(requests[0].groupTitle, "管家卡片与周回顾")
        let good = ScriptedChatTransport([ChatMessage(role: .assistant, content: try JSONValue.object(["cards": .array([
            .object(["key": .string("c0"), "title": .string("外卖到线了"), "body": .string("本月外卖 ¥60.00，到了你留的线。")])])]).jsonText())])
        let accepted = await ButlerWording.word(candidates, ledger: ledger, transport: good)
        XCTAssertEqual(accepted.first?.body, "本月外卖 ¥60.00，到了你留的线。")
        XCTAssertEqual(accepted.first?.evidence, candidates.first?.evidence)
    }
    func testFeedbackProposalsThresholdsWindowAndNoAutomaticProfileChange() throws {
        var ledger = restrained(); let profile = ledger.profile; let area = profile.restrain[0]
        func card(_ index: Int, kind: CardKind = .offCharacter) -> ButlerCard {
            var card = ButlerCard(kind: kind, title: "观察", body: "一笔记录", evidence: [ledger.entries[0].id], dedupeKey: "off:\(index)")
            card.areaID = area.id; card.createdAt = now; return card
        }
        ledger.cards = [card(0), card(1), card(2)]
        ButlerCards.feedback(.regret, cardID: ledger.cards[0].id, in: &ledger, now: Dates.addDays(-61, to: now))
        ButlerCards.feedback(.regret, cardID: ledger.cards[1].id, in: &ledger, now: now)
        XCTAssertTrue(ledger.pendingChanges.isEmpty)
        ButlerCards.feedback(.regret, cardID: ledger.cards[2].id, in: &ledger, now: now)
        XCTAssertEqual(ledger.pendingChanges.count, 1); XCTAssertEqual(ledger.profile, profile)
        XCTAssertEqual(ledger.pendingChanges.first?.source, "卡片反馈")
        XCTAssertTrue(ledger.pendingChanges.first?.isProfileOnly == true)
        try ledger.pendingChanges[0].validateStructure()
        let before = ledger.pendingChanges
        ButlerCards.feedback(.regret, cardID: ledger.cards[2].id, in: &ledger, now: now)
        XCTAssertEqual(ledger.pendingChanges, before)
        ledger.pendingChanges = []; ledger.cards = [card(3, kind: .restrain), card(4, kind: .restrain), card(5, kind: .restrain)]
        ButlerCards.feedback(.worth, cardID: ledger.cards[0].id, in: &ledger, now: now)
        XCTAssertTrue(ledger.pendingChanges.isEmpty)
        ButlerCards.feedback(.worth, cardID: ledger.cards[1].id, in: &ledger, now: now)
        ButlerCards.feedback(.worth, cardID: ledger.cards[2].id, in: &ledger, now: now)
        XCTAssertEqual(ledger.pendingChanges.count, 1); XCTAssertEqual(ledger.profile, profile)
        let proposal = ledger.pendingChanges[0]
        try proposal.apply(to: &ledger)
        XCTAssertTrue(ledger.profile.generous.isEmpty)
        XCTAssertEqual(ledger.profile.restrain.first?.id, area.id)
        XCTAssertEqual(ledger.profile.restrain.first?.softLimit, SoftLimit(perWeekCount: 3, perMonthAmount: 6250))
    }
    func testOffCharacterSelectionIncludesImportHistoryAndMergesSameCategory() async {
        var ledger = seed()
        ledger.entries = (0..<10).map { _ in expense(ledger, amount: 1000, title: "午餐", date: Dates.addDays(-10, to: now)) }
        let imported = (0..<4).map { _ in expense(ledger, amount: 10_000, title: "聚餐") }
        ledger.entries += imported
        let candidates = OffCharacter.candidates(ledger, entryIDs: imported.map(\.id), now: now)
        XCTAssertEqual(candidates.count, 1)
        XCTAssertTrue(candidates.allSatisfy { $0.facts.contains { $0.label == "近来同类均值" && $0.cents == 3076 } })
        XCTAssertEqual(Set(candidates.first?.evidence ?? []), Set(imported.map(\.id)))
        let local = await ButlerWording.word(candidates, ledger: ledger, transport: nil, select: true)
        XCTAssertEqual(local.count, 1)
        ledger.cards = local.map { $0.card(now: now) }
        XCTAssertTrue(OffCharacter.candidates(ledger, entryIDs: imported.map(\.id), now: now).isEmpty)
    }
    func testOffCharacterBulkImportCountsSameCategoryHistory() {
        var ledger = seed(); let batchID = UUID()
        ledger.entries = (0..<10).map { expense(ledger, date: Dates.addDays(-30 + $0 * 3, to: now), category: "交通") }
        let imported = (0..<20).map { index -> Entry in
            var entry = expense(ledger, title: "午餐", date: Dates.addDays(-60 + index * 3, to: now))
            entry.batchID = batchID; return entry
        }
        ledger.entries += imported
        XCTAssertTrue(OffCharacter.candidates(ledger, entryIDs: imported.map(\.id), now: now).isEmpty)
    }
    func testOffCharacterHistoricalImportUsesItsOwnPriorNinetyDays() {
        var ledger = seed(); let day = Dates.day(Dates.addDays(-120, to: now))
        ledger.entries = [-90, -60, -1].map { expense(ledger, amount: 1000, date: Dates.addDays($0, to: day)) }
        ledger.entries += [expense(ledger, amount: 100_000, date: Dates.addDays(-90, to: day).addingTimeInterval(-1)),
                           expense(ledger, amount: 100_000, date: Dates.addDays(1, to: day)),
                           expense(ledger, amount: 100_000, date: Dates.addDays(-10, to: now))]
        let imported = expense(ledger, amount: 3000, date: Dates.addDays(-120, to: now))
        ledger.entries.append(imported)
        let candidates = OffCharacter.candidates(ledger, entryIDs: [imported.id], now: now)
        XCTAssertEqual(candidates.count, 1); XCTAssertEqual(candidates.first?.evidence, [imported.id])
        XCTAssertEqual(candidates.first?.facts.first { $0.label == "近来同类均值" }?.cents, 1000)
    }
    func testOffCharacterGenuinelyRareCategoryStillProducesCandidate() {
        var ledger = seed()
        ledger.entries = (0..<10).map { _ in expense(ledger, date: Dates.addDays(-10, to: now)) }
        let imported = expense(ledger, title: "电影", category: "娱乐旅行")
        ledger.entries.append(imported)
        let candidates = OffCharacter.candidates(ledger, entryIDs: [imported.id], now: now)
        XCTAssertEqual(candidates.count, 1); XCTAssertEqual(candidates.first?.evidence, [imported.id])
        XCTAssertEqual(candidates.first?.facts.first { $0.label == "近90天同类记录" }?.value, "0 笔")
        ledger.entries.removeFirst()
        XCTAssertTrue(OffCharacter.candidates(ledger, entryIDs: [imported.id], now: now).isEmpty)
    }
    func testPostImportCommentsPersistWithOrganizationAndAreRemovedByBatchUndo() async throws {
        let original = restrained()
        var ledger = original
        var batch = ImportBatch(filename: "合成账单", importedCount: 2, duplicateCount: 0, skippedCount: 0)
        batch.needsOrganization = true; batch.undo = ImportUndo(updatedAt: ledger.updatedAt)
        let imported = [expense(ledger, title: "午餐外卖"), expense(ledger, title: "晚餐外卖")].map { entry -> Entry in
            var entry = entry; entry.batchID = batch.id; return entry
        }
        ledger.entries += imported; ledger.imports = [batch]
        let before = ledger
        let script = ScriptedChatTransport([
            ChatMessage(role: .assistant, content: "{\"rows\":[]}"),
            ChatMessage(role: .assistant, content: "invalid optional wording")])
        let result = try await ImportOrganizer(transport: script).organize(ledger: ledger, entryIDs: imported.map(\.id), now: now)
        XCTAssertEqual(result.comments?.count, 1)
        XCTAssertTrue(result.comments?.allSatisfy { $0.kind == .offCharacter } == true)
        XCTAssertEqual(Set(result.comments?.first?.evidence ?? []), Set(imported.map(\.id)))
        result.finish(batchID: batch.id, before: before, in: &ledger)
        XCTAssertEqual(ledger.cards.count, 1)
        XCTAssertEqual(ledger.imports[0].undo?.cardIDs.count, 1)
        ledger = try LedgerCodec.decode(LedgerCodec.encode(ledger))
        XCTAssertEqual(ledger.imports[0].organization?.comments?.count, 1)
        BillImporter.undo(batchID: batch.id, in: &ledger)
        XCTAssertEqual(try LedgerCodec.encode(ledger), try LedgerCodec.encode(original))
    }
    func testRegretInUnprofiledAreaProposesANewRestrainArea() {
        var ledger = seed()
        ledger.entries = [expense(ledger, title: "游戏", category: "娱乐旅行"), expense(ledger, title: "电影", category: "娱乐旅行")]
        ledger.cards = ledger.entries.map { entry in
            ButlerCard(kind: .offCharacter, title: "和平时不同", body: "一笔观察", evidence: [entry.id], dedupeKey: "off:\(entry.id)")
        }
        for id in ledger.cards.map(\.id) { ButlerCards.feedback(.regret, cardID: id, in: &ledger, now: now) }
        XCTAssertEqual(ledger.pendingChanges.count, 1)
        XCTAssertTrue(ledger.profile.restrain.isEmpty)
        guard case .profile(.upsertArea(let area, let stance)) = ledger.pendingChanges[0].items[0] else { return XCTFail("Expected area proposal") }
        XCTAssertEqual(area.match.categories, ["娱乐旅行"]); XCTAssertEqual(stance, .restrain)
    }
    func testWorthWithoutLineMovesToGenerousAndUsedFeedbackIsNotReused() throws {
        var ledger = restrained(); ledger.profile.restrain[0].softLimit = nil
        let area = ledger.profile.restrain[0]
        ledger.cards = (0..<3).map { index in
            var card = ButlerCard(kind: .offCharacter, title: "观察", body: "", dedupeKey: "test:\(index)")
            card.areaID = area.id; card.createdAt = now; return card
        }
        for id in ledger.cards.prefix(2).map(\.id) { ButlerCards.feedback(.worth, cardID: id, in: &ledger, now: now) }
        let change = try XCTUnwrap(ledger.pendingChanges.first)
        XCTAssertEqual(ledger.cards.prefix(2).compactMap(\.feedbackProposalID), [change.id, change.id])
        try change.apply(to: &ledger); ledger.pendingChanges = []
        XCTAssertEqual(ledger.profile.generous.first?.id, area.id)
        ButlerCards.feedback(.worth, cardID: ledger.cards[2].id, in: &ledger, now: now)
        XCTAssertTrue(ledger.pendingChanges.isEmpty)
    }
    func testBothFeedbacksUseSixtyDayWindowAndLegacyCreatedAtFallback() {
        for value in [CardFeedback.worth, .regret] {
            var ledger = restrained(); let area = ledger.profile.restrain[0]
            ledger.cards = (0..<4).map { index in
                var card = ButlerCard(kind: .restrain, title: "观察", body: "", dedupeKey: "window:\(index)")
                card.areaID = area.id; card.createdAt = Dates.addDays(-61, to: now); return card
            }
            ledger.cards[0].feedback = value
            ButlerCards.feedback(value, cardID: ledger.cards[1].id, in: &ledger, now: now)
            XCTAssertTrue(ledger.pendingChanges.isEmpty)
            ledger.cards[2].createdAt = Dates.addDays(-60, to: now); ledger.cards[2].feedback = value
            ButlerCards.feedback(value, cardID: ledger.cards[3].id, in: &ledger, now: now)
            XCTAssertEqual(ledger.pendingChanges.count, 1)
            XCTAssertNil(ledger.cards[0].feedbackProposalID)
            XCTAssertNotNil(ledger.cards[2].feedbackProposalID)
        }
    }
    func testFeedbackTightensOrRelaxesBothLinesAndRoundsCents() {
        for value in [CardFeedback.worth, .regret] {
            var ledger = restrained(); ledger.profile.restrain[0].softLimit = SoftLimit(perWeekCount: 0, perMonthAmount: 102)
            ledger.cards = (0..<2).map { index in
                var card = ButlerCard(kind: .followUp, title: "观察", body: "", dedupeKey: "line:\(index)")
                card.areaID = ledger.profile.restrain[0].id; card.createdAt = now; return card
            }
            for id in ledger.cards.map(\.id) { ButlerCards.feedback(value, cardID: id, in: &ledger, now: now) }
            guard case .profile(.upsertArea(let area, let stance))? = ledger.pendingChanges.first?.items.first else { return XCTFail("Expected profile proposal") }
            XCTAssertEqual(stance, .restrain)
            XCTAssertEqual(area.softLimit?.perWeekCount, value == .worth ? 1 : 0)
            XCTAssertEqual(area.softLimit?.perMonthAmount, value == .worth ? 128 : 81)
        }
    }
    func testRefreshArchivesOldDismissedPayloadAndKeepsMemoryAndDedupe() throws {
        var ledger = seed()
        var card = ButlerCard(kind: .followUp, title: "保留标题", body: "旧正文", evidence: [UUID()], dedupeKey: "archive:one")
        card.dismissedAt = Dates.addDays(-366, to: now); card.feedback = .worth; card.feedbackAt = Dates.addDays(-367, to: now)
        card.feedbackProposalID = UUID(); card.areaID = UUID(); card.facts = [CardFact("依据", "旧内容")]
        card.importQuestion = ImportQuestion(text: "旧问题", entryIDs: [], options: [])
        card.letter = WeeklyLetter.facts(ledger, weekEnding: now)
        var recent = card; recent.id = UUID(); recent.dedupeKey = "archive:two"; recent.dismissedAt = Dates.addDays(-365, to: now)
        ledger.cards = [card, recent]
        XCTAssertTrue(ButlerCards.refresh(&ledger, candidates: [], now: now))
        let archived = ledger.cards[0]
        XCTAssertEqual(archived.body, ""); XCTAssertNil(archived.facts); XCTAssertTrue(archived.evidence.isEmpty)
        XCTAssertNil(archived.letter); XCTAssertNil(archived.importQuestion)
        var expected = card; expected.body = ""; expected.facts = nil; expected.evidence = []; expected.letter = nil; expected.importQuestion = nil
        XCTAssertEqual(archived, expected); XCTAssertEqual(ledger.cards[1], recent)
        XCTAssertFalse(ButlerCards.refresh(&ledger, candidates: [], now: now))
        XCTAssertEqual(try LedgerCodec.decode(LedgerCodec.encode(ledger)).cards[0], archived)
    }

}
