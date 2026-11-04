import XCTest
@testable import YubaiCore

final class OffCharacterTests: XCTestCase {
    private let now = Dates.parse("2026-10-21 12:00")!
    private func seed() -> Ledger {
        var ledger = Ledger()
        ledger.accounts = [Account(name: "合成账户", balance: 1_000_000, at: Dates.parse("2026-07-01")!)]
        return ledger
    }
    private func expense(_ ledger: Ledger, amount: Int64 = 3200, title: String = "午餐", category: String = "餐饮", date: String = "2026-10-14") -> Entry {
        Entry(date: Dates.parse(date)!, amount: amount, accountID: ledger.accounts[0].id, title: title, category: category)
    }
    private func highLedger() -> Ledger {
        var ledger = seed()
        ledger.entries = (0..<41).map { _ in expense(ledger) }
        return ledger
    }
    private func mergedHighLedger() -> (Ledger, [Entry]) {
        var ledger = highLedger()
        let entries = [expense(ledger, amount: 11_200, title: "聚餐", date: "2026-10-18"),
            expense(ledger, amount: 16_000, title: "聚餐", date: "2026-10-19"),
            expense(ledger, amount: 19_200, title: "聚餐", date: "2026-10-20")]
        ledger.entries += entries
        return (ledger, entries)
    }
    func testSingleHighCopyUsesPurposeAmountRoundedMultipleAndEntryDate() throws {
        var ledger = highLedger()
        var entry = expense(ledger, amount: 26_800, title: "合成餐厅", date: "2026-10-19")
        entry.purpose = "生日聚餐"; ledger.entries.append(entry)
        let candidate = try XCTUnwrap(OffCharacter.candidates(ledger, entryIDs: [entry.id], now: now).first)
        XCTAssertEqual(candidate.meta, "比平时贵 · 餐饮 · 10月19日")
        XCTAssertEqual(candidate.title, "生日聚餐 ¥268.00，约是平时的 8 倍")
        XCTAssertEqual(candidate.body, "近 90 天餐饮 41 笔，平均 ¥32.00 · 看这笔 ›")
        XCTAssertEqual(candidate.action, .openEvidence); XCTAssertEqual(candidate.evidence, [entry.id])
        let card = candidate.card(now: now)
        XCTAssertEqual(card.title, candidate.title); XCTAssertEqual(card.body, candidate.body); XCTAssertEqual(card.meta, candidate.meta)
        XCTAssertEqual(card.createdAt, now)
        ledger.cards = [card]
        XCTAssertEqual(try LedgerCodec.decode(LedgerCodec.encode(ledger)).cards, ledger.cards)
    }
    func testHighThresholdAndRoundingUsePersonalSpending() throws {
        var ledger = highLedger()
        var entry = expense(ledger, amount: 26_800, date: "2026-10-19")
        entry.personalExpense = 9599; ledger.entries.append(entry)
        XCTAssertTrue(OffCharacter.candidates(ledger, entryIDs: [entry.id], now: now).isEmpty)
        ledger.entries[41].personalExpense = 9600
        var candidate = try XCTUnwrap(OffCharacter.candidates(ledger, entryIDs: [entry.id], now: now).first)
        XCTAssertEqual(candidate.title, "午餐 ¥96.00，约是平时的 3 倍")
        ledger.entries[41].personalExpense = 11_200
        candidate = try XCTUnwrap(OffCharacter.candidates(ledger, entryIDs: [entry.id], now: now).first)
        XCTAssertEqual(candidate.title, "午餐 ¥112.00，约是平时的 4 倍")
    }
    func testPurposeTruncationAndEmptyTitleCategoryFallback() throws {
        var ledger = highLedger()
        var entry = expense(ledger, amount: 26_800, date: "2026-10-19")
        entry.purpose = "和朋友一起庆祝生日的聚餐"; ledger.entries.append(entry)
        var candidate = try XCTUnwrap(OffCharacter.candidates(ledger, entryIDs: [entry.id], now: now).first)
        XCTAssertEqual(candidate.title, "和朋友一起庆祝生日的… ¥268.00，约是平时的 8 倍")
        ledger.entries[41].purpose = nil; ledger.entries[41].title = ""
        candidate = try XCTUnwrap(OffCharacter.candidates(ledger, entryIDs: [entry.id], now: now).first)
        XCTAssertEqual(candidate.title, "餐饮 ¥268.00，约是平时的 8 倍")
    }
    func testRareCopyFirstAndSecondUseAndOtherSpendingCount() throws {
        var ledger = seed()
        ledger.entries = (0..<86).map { _ in expense(ledger) }
        let entry = expense(ledger, amount: 32_000, title: "猫粮", category: "宠物", date: "2026-10-17")
        ledger.entries.append(entry)
        var candidate = try XCTUnwrap(OffCharacter.candidates(ledger, entryIDs: [entry.id], now: now).first)
        XCTAssertEqual(candidate.meta, "少见 · 宠物 · 10月17日")
        XCTAssertEqual(candidate.title, "猫粮 ¥320.00，近 90 天第一次花在宠物上")
        XCTAssertEqual(candidate.body, "同期其他开销 86 笔 · 看这笔 ›")
        ledger.entries.append(expense(ledger, amount: 32_000, title: "猫砂", category: "宠物", date: "2026-10-15"))
        candidate = try XCTUnwrap(OffCharacter.candidates(ledger, entryIDs: [entry.id], now: now).first)
        XCTAssertEqual(candidate.title, "猫粮 ¥320.00，近 90 天第 2 次花在宠物上")
        XCTAssertEqual(candidate.body, "同期其他开销 86 笔 · 看这笔 ›")
    }
    func testRestrainCopyWithAndWithoutNote() throws {
        var ledger = seed()
        let area = ProfileArea(title: "外卖", match: AreaMatch(keywords: ["外卖"]), note: "一周最多三次")
        ledger.profile.restrain = [area]
        let entry = expense(ledger, amount: 4500, title: "夜宵外卖", date: "2026-10-20")
        ledger.entries = [entry]
        var candidate = try XCTUnwrap(OffCharacter.candidates(ledger, entryIDs: [entry.id], now: now).first)
        XCTAssertEqual(candidate.meta, "想克制的 · 外卖 · 10月20日")
        XCTAssertEqual(candidate.title, "夜宵外卖 ¥45.00，在你想克制的「外卖」里")
        XCTAssertEqual(candidate.body, "你说过：「一周最多三次」 · 看这笔 ›")
        XCTAssertEqual(candidate.areaID, area.id)
        ledger.profile.restrain[0].note = "  \n "
        candidate = try XCTUnwrap(OffCharacter.candidates(ledger, entryIDs: [entry.id], now: now).first)
        XCTAssertEqual(candidate.body, "看这笔 ›")
    }
    func testThreeHighEntriesMergeWithStableKeyAllEvidenceAndMinimumFlooredMultiple() throws {
        var (ledger, entries) = mergedHighLedger()
        let candidates = OffCharacter.candidates(ledger, entryIDs: entries.map(\.id), now: now)
        XCTAssertEqual(candidates.count, 1)
        let candidate = try XCTUnwrap(candidates.first)
        XCTAssertEqual(candidate.title, "3 笔餐饮，每笔都是平时的 3 倍以上")
        XCTAssertEqual(candidate.meta, "比平时贵 · 餐饮 · 10月18日–20日")
        XCTAssertEqual(candidate.body, "共 ¥464.00 · 平时一笔约 ¥32.00 · 看看这 3 笔 ›")
        XCTAssertEqual(Set(candidate.evidence), Set(entries.map(\.id)))
        XCTAssertEqual(candidate.dedupeKey, "off:" + entries.map(\.id.uuidString).sorted().joined(separator: ":"))
        ledger.entries.reverse()
        XCTAssertEqual(OffCharacter.candidates(ledger, entryIDs: entries.reversed().map(\.id), now: now), candidates)
        ledger.cards = [candidate.card(now: now)]
        XCTAssertTrue(OffCharacter.candidates(ledger, entryIDs: entries.map(\.id), now: now).isEmpty)
        ledger.cards[0].evidence = []; ledger.cards[0].dismissedAt = now
        XCTAssertTrue(OffCharacter.candidates(ledger, entryIDs: entries.map(\.id), now: now).isEmpty)
    }
    func testExistingEvidenceAndLegacyKeyAreSkippedBeforeMerging() throws {
        var (ledger, entries) = mergedHighLedger()
        ledger.cards = [ButlerCard(kind: .offCharacter, title: "旧观察", body: "", evidence: [entries[0].id], dedupeKey: "legacy:one"),
            ButlerCard(kind: .offCharacter, title: "旧观察", body: "", dedupeKey: "off:\(entries[1].id)")]
        let candidate = try XCTUnwrap(OffCharacter.candidates(ledger, entryIDs: entries.map(\.id), now: now).first)
        XCTAssertEqual(candidate.evidence, [entries[2].id])
        XCTAssertEqual(candidate.meta, "比平时贵 · 餐饮 · 10月20日")
    }
    func testMergingSeparatesReasonsCategoriesAndRestrainAreas() throws {
        var ledger = highLedger()
        let areas = [ProfileArea(title: "外卖", match: AreaMatch(keywords: ["外卖"])),
            ProfileArea(title: "咖啡", match: AreaMatch(keywords: ["咖啡"]))]
        ledger.profile.restrain = areas
        let entries = [expense(ledger, amount: 26_800, title: "聚餐", date: "2026-10-19"),
            expense(ledger, amount: 26_800, title: "外卖", date: "2026-10-19"),
            expense(ledger, title: "咖啡", date: "2026-10-19"),
            expense(ledger, title: "猫粮", category: "宠物", date: "2026-10-19"),
            expense(ledger, title: "电影", category: "娱乐旅行", date: "2026-10-19")]
        ledger.entries += entries
        let candidates = OffCharacter.candidates(ledger, entryIDs: entries.map(\.id), now: now)
        XCTAssertEqual(candidates.count, 5)
        XCTAssertTrue(candidates.allSatisfy { $0.evidence.count == 1 })
        XCTAssertEqual(Set(candidates.compactMap(\.areaID)), Set(areas.map(\.id)))
    }
    func testRareAndRestrainMergeAndDateRangesAcrossMonthsOrOnSameDay() throws {
        var ledger = seed()
        ledger.entries = (0..<10).map { _ in expense(ledger, date: "2026-09-01") }
        var entries = [expense(ledger, title: "猫粮", category: "宠物", date: "2026-09-30"),
            expense(ledger, title: "猫砂", category: "宠物", date: "2026-10-01")]
        ledger.entries += entries
        var candidates = OffCharacter.candidates(ledger, entryIDs: entries.map(\.id), now: now)
        XCTAssertEqual(candidates.count, 1)
        var candidate = try XCTUnwrap(candidates.first)
        XCTAssertEqual(candidate.meta, "少见 · 宠物 · 9月30日–10月1日")
        XCTAssertEqual(candidate.title, "2 笔宠物，共 ¥64.00，近 90 天少见")
        XCTAssertEqual(candidate.body, "同期其他开销 10 笔 · 看看这 2 笔 ›")
        ledger = seed()
        ledger.profile.restrain = [ProfileArea(title: "外卖", match: AreaMatch(keywords: ["外卖"]))]
        entries = [expense(ledger, title: "午餐外卖", date: "2026-10-20"),
            expense(ledger, title: "水果外卖", category: "日用购物", date: "2026-10-20")]
        ledger.entries = entries
        candidates = OffCharacter.candidates(ledger, entryIDs: entries.map(\.id), now: now)
        XCTAssertEqual(candidates.count, 1)
        candidate = try XCTUnwrap(candidates.first)
        XCTAssertEqual(candidate.meta, "想克制的 · 外卖 · 10月20日")
        XCTAssertEqual(candidate.title, "2 笔消费，共 ¥64.00，在你想克制的「外卖」里")
        XCTAssertEqual(candidate.body, "看看这 2 笔 ›")
        XCTAssertEqual(Set(candidate.evidence), Set(entries.map(\.id)))
    }
    func testOffCharacterAISelectsKeysWithoutRewritingAndRetainsFallback() async throws {
        var ledger = seed()
        ledger.profile.restrain = (0..<4).map { ProfileArea(title: "合成领域\($0)", match: AreaMatch(keywords: ["合成用途\($0)"])) }
        ledger.entries = (0..<4).map { expense(ledger, title: "合成用途\($0)") }
        let candidates = OffCharacter.candidates(ledger, entryIDs: ledger.entries.map(\.id), now: now)
        XCTAssertEqual(candidates.count, 4)
        let transport = ScriptedChatTransport([ChatMessage(role: .assistant, content:
            "{\"cards\":[{\"key\":\"c3\",\"title\":\"改写标题\",\"body\":\"改写正文\"},{\"key\":\"c1\"}]}")])
        let selected = await ButlerWording.word(candidates, ledger: ledger, transport: transport, select: true)
        XCTAssertEqual(selected, [candidates[3], candidates[1]])
        let requests = await transport.recorded(); XCTAssertEqual(requests.count, 1)
        let allKeys = ScriptedChatTransport([ChatMessage(role: .assistant, content:
            "{\"cards\":[{\"key\":\"c3\"},{\"key\":\"c2\"},{\"key\":\"c1\"},{\"key\":\"c0\"}]}")])
        let capped = await ButlerWording.word(candidates, ledger: ledger, transport: allKeys, select: true)
        XCTAssertEqual(capped, [candidates[3], candidates[2], candidates[1]])
        let offline = await ButlerWording.word(candidates, ledger: ledger, transport: nil, select: true)
        XCTAssertEqual(offline, Array(candidates.prefix(3)))
        let broken = ScriptedChatTransport([ChatMessage(role: .assistant, content: "invalid")])
        let fallback = await ButlerWording.word(candidates, ledger: ledger, transport: broken, select: true)
        XCTAssertEqual(fallback, offline)
        let unused = ScriptedChatTransport([])
        let unchanged = await ButlerWording.word(candidates, ledger: ledger, transport: unused)
        XCTAssertEqual(unchanged, candidates)
        let unusedRequests = await unused.recorded(); XCTAssertTrue(unusedRequests.isEmpty)
    }
    func testMixedAIWordingLeavesOffCharacterUntouchedAndStillRewritesOtherKinds() async throws {
        let (ledger, entries) = mergedHighLedger()
        let off = try XCTUnwrap(OffCharacter.candidates(ledger, entryIDs: entries.map(\.id), now: now).first)
        let other = CardCandidate(kind: .staleBalance, dedupeKey: "stale:test", evidence: [], facts: [],
            title: "余额该核对一下了", body: "旧正文", action: .openEvidence, priority: 4)
        let script = ScriptedChatTransport([ChatMessage(role: .assistant, content:
            "{\"cards\":[{\"key\":\"c0\",\"title\":\"改写标题\",\"body\":\"改写正文\"},{\"key\":\"c1\",\"title\":\"核对一下余额\",\"body\":\"可以看看账户余额。\"}]}")])
        let worded = await ButlerWording.word([off, other], ledger: ledger, transport: script)
        XCTAssertEqual(worded[0], off); XCTAssertEqual(worded[1].title, "核对一下余额")
        XCTAssertEqual(worded[1].body, "可以看看账户余额。")
    }
    func testMergedFeedbackCountsOnceAndUsesRemainingEvidenceOrKey() throws {
        for value in [CardFeedback.worth, .regret] {
            var (ledger, entries) = mergedHighLedger()
            let area = ProfileArea(title: "餐饮", match: AreaMatch(categories: ["餐饮"]))
            ledger.profile.restrain = [area]
            let candidate = try XCTUnwrap(OffCharacter.candidates(ledger, entryIDs: entries.map(\.id), now: now).first)
            ledger.cards = [candidate.card(now: now)]
            let id = ledger.cards[0].id
            ButlerCards.feedback(value, cardID: id, in: &ledger, now: now)
            XCTAssertEqual(ledger.cards[0].feedback, value); XCTAssertEqual(ledger.cards[0].feedbackAt, now)
            XCTAssertEqual(ledger.cards[0].dismissedAt, now)
            XCTAssertTrue(ButlerCards.visible(ledger).isEmpty)
            XCTAssertTrue(ledger.pendingChanges.isEmpty)
            ButlerCards.feedback(value, cardID: id, in: &ledger, now: now)
            XCTAssertTrue(ledger.pendingChanges.isEmpty)
            var second = ButlerCard(kind: .offCharacter, title: "合成观察", body: "", evidence: [entries[2].id], dedupeKey: "off:\(entries[2].id)")
            second.areaID = area.id; ledger.cards.append(second)
            ButlerCards.feedback(value, cardID: second.id, in: &ledger, now: now)
            XCTAssertEqual(ledger.pendingChanges.count, 1)
        }
        var (ledger, entries) = mergedHighLedger()
        let candidate = try XCTUnwrap(OffCharacter.candidates(ledger, entryIDs: entries.map(\.id), now: now).first)
        ledger.cards = [candidate.card(now: now)]
        ledger.entries.removeAll { $0.id == candidate.evidence.first }
        ledger.cards[0].evidence = []
        ButlerCards.feedback(.regret, cardID: ledger.cards[0].id, in: &ledger, now: now)
        var second = candidate.card(now: now); second.dedupeKey = "legacy:second"
        ledger.cards.append(second)
        ButlerCards.feedback(.regret, cardID: second.id, in: &ledger, now: now)
        XCTAssertEqual(ledger.pendingChanges.count, 1)
    }
    func testMergedMuteWorksWithKeysEvidenceLegacyTopicsAndCodecRoundTrip() throws {
        var (ledger, entries) = mergedHighLedger()
        let candidate = try XCTUnwrap(OffCharacter.candidates(ledger, entryIDs: entries.map(\.id), now: now).first)
        ledger.cards = [candidate.card(now: now)]
        let single = ButlerCard(kind: .offCharacter, title: "旧观察", body: "", evidence: [entries[1].id], dedupeKey: "legacy:one")
        ledger.cards.append(single)
        ButlerCards.mute(ledger.cards[0].id, in: &ledger, now: now)
        XCTAssertTrue(ButlerCards.visible(ledger).isEmpty)
        XCTAssertEqual(ledger.cards[1].dismissedAt, now)
        for entry in entries { XCTAssertTrue(ButlerCards.isMuted("off:\(entry.id)", in: ledger)) }
        ledger = try LedgerCodec.decode(LedgerCodec.encode(ledger))
        ledger.cards = []
        XCTAssertTrue(OffCharacter.candidates(ledger, entryIDs: entries.map(\.id), now: now).isEmpty)
        XCTAssertFalse(ButlerCards.refresh(&ledger, candidates: [candidate], now: now))
        ledger.mutedTopics = ["off:\(entries[1].id)"]
        XCTAssertTrue(ButlerCards.isMuted(candidate.dedupeKey, in: ledger))
        XCTAssertTrue(ButlerCards.isMuted(single.dedupeKey, evidence: single.evidence, in: ledger))
        let remaining = OffCharacter.candidates(ledger, entryIDs: entries.map(\.id), now: now)
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(Set(remaining[0].evidence), Set([entries[0].id, entries[2].id]))
    }
    func testOldStoredCardWithoutMetaDecodes() throws {
        var ledger = seed()
        var card = ButlerCard(kind: .offCharacter, title: "餐饮记录少见", body: "原来的正文", evidence: [UUID()], dedupeKey: "off:legacy")
        card.createdAt = now; ledger.cards = [card]
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: LedgerCodec.encode(ledger)) as? [String: Any])
        var cards = try XCTUnwrap(json["cards"] as? [[String: Any]])
        cards[0].removeValue(forKey: "meta"); json["cards"] = cards
        let restored = try LedgerCodec.decode(JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(restored.cards[0].meta)
        XCTAssertEqual(restored.cards[0], card)
    }
    func testLargeMergedCardKeepsAllEvidenceAndPersistsItsMute() throws {
        var ledger = seed()
        let ids = (0..<1001).map { _ in UUID() }.sorted { $0.uuidString < $1.uuidString }
        let candidate = CardCandidate(kind: .offCharacter, dedupeKey: "off:" + ids.map(\.uuidString).joined(separator: ":"),
            evidence: ids, facts: [], title: "合成合并观察", body: "看看这 1001 笔 ›", action: .openEvidence, priority: 5,
            meta: "想克制的 · 外卖 · 10月20日")
        ledger.cards = [candidate.card(now: now)]
        XCTAssertEqual(ledger.cards[0].evidence, ids)
        ButlerCards.mute(ledger.cards[0].id, in: &ledger, now: now)
        let restored = try LedgerCodec.decode(LedgerCodec.encode(ledger))
        XCTAssertEqual(restored.cards, ledger.cards)
        XCTAssertTrue(ButlerCards.isMuted("off:\(ids.last!)", in: restored))
    }
}
