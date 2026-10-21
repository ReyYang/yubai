import XCTest
@testable import YubaiCore

final class MemoryReflectionTests: XCTestCase {
    private let now = Dates.parse("2026-10-20 12:00")!
    private func seed() -> Ledger {
        var ledger = Ledger(); ledger.updatedAt = now; ledger.profile.updatedAt = now
        ledger.accounts = [Account(name: "合成账户", balance: 1_000_000, at: Dates.addDays(-100, to: now))]
        ledger.memories = [MemoryNote(text: "和室友合租", kind: .life, source: .chat, createdAt: Dates.addDays(-20, to: now)),
            MemoryNote(text: "现在是合租", kind: .life, source: .chat, createdAt: Dates.addDays(-10, to: now))]
        ledger.entries = [Entry(date: Dates.parse("2026-10-18 12:00")!, amount: 60_000,
            accountID: ledger.accounts[0].id, title: "合成大件", category: "日用购物"),
            Entry(date: now, amount: 2000, accountID: ledger.accounts[0].id, title: "本周消费", category: "餐饮")]
        return ledger
    }
    private func output(add: [JSONValue] = [], update: [JSONValue] = [], remove: [JSONValue] = [], learned: [JSONValue] = []) -> JSONValue {
        .object(["add": .array(add), "update": .array(update), "remove": .array(remove), "learned": .array(learned)])
    }
    private func transport(_ value: JSONValue) throws -> ScriptedChatTransport {
        ScriptedChatTransport([ChatMessage(role: .assistant, content: try value.jsonText())])
    }
    func testAddUpdateRemoveApplyAtomicallyLearnedInLetterAndUndo() async throws {
        var ledger = seed(); let before = ledger; let original = ledger.memories[0]; let duplicate = ledger.memories[1]
        let json = output(add: [.object(["text": .string("正在为搬家作准备"), "kind": .string("plan")])],
            update: [.object(["id": .string(original.id.uuidString), "text": .string("和室友合租，准备下个月搬家")])],
            remove: [.object(["id": .string(duplicate.id.uuidString), "reason": .string("与另一条合并")])],
            learned: [.string("你正在准备搬家"), .string("你的合租情况有了变化")])
        let result = try await MemoryReflection.run(ledger: ledger, transport: transport(json), now: now)
        XCTAssertEqual(ledger, before); XCTAssertTrue(MemoryReflection.isDue(ledger: ledger, now: now))
        XCTAssertEqual(result.addedNotes.count, 1); XCTAssertEqual(result.updatedNotes.count, 1)
        XCTAssertEqual(result.removedNotes.first?.note, duplicate); XCTAssertEqual(result.removedNotes.first?.reason, "与另一条合并")
        XCTAssertEqual(result.updatedNotes.first?.note.previousText, original.text)
        try result.apply(to: &ledger, now: now)
        XCTAssertEqual(ledger.memories.count, 2); XCTAssertTrue(ledger.memories.allSatisfy { $0.source == .reflection })
        XCTAssertEqual(ledger.profile, before.profile); XCTAssertFalse(MemoryReflection.isDue(ledger: ledger, now: now))
        XCTAssertTrue(MemoryReflection.isDue(ledger: ledger, now: Dates.addDays(7, to: now)))
        let letter = try XCTUnwrap(ledger.cards.first { $0.kind == .weeklyLetter }?.letter)
        XCTAssertEqual(letter.learned, result.learned)
        XCTAssertEqual(letter.learned?.map(\.memoryID), [result.addedNotes[0].id, original.id])
        XCTAssertEqual(try LedgerCodec.decode(LedgerCodec.encode(ledger)), ledger)
        Memory.undo(noteID: original.id, in: &ledger, now: now)
        XCTAssertEqual(ledger.memories.first { $0.id == original.id }?.text, original.text)
        XCTAssertFalse(ledger.cards.contains { $0.letter?.learned?.contains { $0.memoryID == original.id } == true })
        try result.restoreRemoved(in: &ledger, now: now)
        XCTAssertEqual(ledger.memories.first { $0.id == duplicate.id }?.text, duplicate.text)
        let restored = ledger
        XCTAssertThrowsError(try result.restoreRemoved(in: &ledger, now: now)); XCTAssertEqual(ledger, restored)
        Memory.undo(noteID: result.addedNotes[0].id, in: &ledger, now: now)
        XCTAssertEqual(Set(ledger.memories.map(\.id)), Set(before.memories.map(\.id)))
    }
    func testRejectLearnedLineDeletesMemoryAndCleansLetter() async throws {
        var ledger = seed()
        let result = try await MemoryReflection.run(ledger: ledger, transport: transport(output(
            update: [.object(["id": .string(ledger.memories[0].id.uuidString), "text": .string("搬家后更喜欢安静的住处")])], learned: [.string("你更在乎住得安静")])), now: now)
        try result.apply(to: &ledger, now: now)
        let line = try XCTUnwrap(result.learned.first)
        XCTAssertNotNil(ledger.memories.first { $0.id == line.memoryID }?.previousText)
        Memory.reject(lineMemoryID: line.memoryID, in: &ledger, now: now)
        XCTAssertFalse(ledger.memories.contains { $0.id == line.memoryID })
        XCTAssertEqual(ledger.cards.first { $0.kind == .weeklyLetter }?.letter?.learned, [])
        let after = ledger; Memory.reject(lineMemoryID: line.memoryID, in: &ledger, now: now)
        XCTAssertEqual(ledger, after)
    }
    func testExistingLetterIsEnrichedWithoutChangingNumbersOrDuplicatingCards() async throws {
        var ledger = seed()
        let candidate = try XCTUnwrap(WeeklyLetter.candidate(ledger, now: now))
        ledger.cards = [candidate.card(now: now)]
        let id = ledger.cards[0].id; let facts = ledger.cards[0].letter
        let result = try await MemoryReflection.run(ledger: ledger, transport: transport(output(
            add: [.object(["text": .string("准备搬家"), "kind": .string("plan")])], learned: [.string("你在准备搬家")])), now: now)
        try result.apply(to: &ledger, now: now)
        XCTAssertEqual(ledger.cards.count, 1); XCTAssertEqual(ledger.cards[0].id, id)
        XCTAssertEqual(ledger.cards[0].letter?.series, facts?.series)
        XCTAssertEqual(ledger.cards[0].letter?.spending, facts?.spending)
        XCTAssertEqual(ledger.cards[0].letter?.learned, result.learned)
    }
    func testInvalidOutputIsRejectedAsAWholeWithoutWeekStamp() async throws {
        let ledger = seed(); let before = ledger; let id = ledger.memories[0].id.uuidString
        let validAdd: JSONValue = .object(["text": .string("准备搬家"), "kind": .string("plan")])
        let cases: [JSONValue] = [
            output(add: [validAdd, .object(["text": .string(""), "kind": .string("life")])]),
            output(add: [.object(["text": .string("准备搬家"), "kind": .string("unknown")])]),
            output(add: [.object(["text": .string(String(repeating: "字", count: 201)), "kind": .string("life")])]),
            output(update: [.object(["id": .string(UUID().uuidString), "text": .string("不存在的记忆")])]),
            output(remove: [.object(["id": .string(UUID().uuidString), "reason": .string("不存在")])]),
            output(update: [.object(["id": .string(id), "text": .string("新的情况")])], remove: [.object(["id": .string(id), "reason": .string("重复修改")])]),
            output(add: [validAdd], learned: [.string(String(repeating: "字", count: 41))]),
            output(learned: [.string("没有关联记忆")]),
            .object(["add": .array([])]),
            output(add: [validAdd], learned: [.number(1)])
        ]
        for json in cases {
            do { _ = try await MemoryReflection.run(ledger: ledger, transport: transport(json), now: now); XCTFail("Invalid reflection accepted") }
            catch { XCTAssertNil(ledger.lastReflectionWeek); XCTAssertEqual(ledger, before) }
        }
        let broken = ScriptedChatTransport([ChatMessage(role: .assistant, content: "not JSON")])
        do { _ = try await MemoryReflection.run(ledger: ledger, transport: broken, now: now); XCTFail("Malformed JSON accepted") } catch {}
        let offline = ScriptedChatTransport([])
        do { _ = try await MemoryReflection.run(ledger: ledger, transport: offline, now: now); XCTFail("Transport failure accepted") } catch {}
        XCTAssertTrue(MemoryReflection.isDue(ledger: ledger, now: now))
    }
    func testStaleResultDoesNotOverwriteUserEditsOrStampWeek() async throws {
        var ledger = seed()
        let result = try await MemoryReflection.run(ledger: ledger, transport: transport(output()), now: now)
        ledger.updatedAt = now.addingTimeInterval(1)
        let before = ledger
        XCTAssertThrowsError(try result.apply(to: &ledger, now: now)); XCTAssertEqual(ledger, before)
        XCTAssertThrowsError(try result.apply(to: &ledger, now: Dates.addDays(7, to: now)))
    }
    func testInputUsesPreviousISOWeekAllMemoriesAndThisWeeksFeedbackOnly() async throws {
        var ledger = seed()
        ledger.memories += (0..<150).map { MemoryNote(text: "合成背景\($0)", kind: .life, source: .user, createdAt: now) }
        var card = ButlerCard(kind: .offCharacter, title: "合成观察", body: "可以回顾的事", dedupeKey: "feedback:this")
        card.feedback = .worth; card.feedbackAt = now; ledger.cards = [card]
        var previous = card; previous.id = UUID(); previous.dedupeKey = "feedback:previous"; previous.feedbackAt = Dates.addDays(-8, to: now)
        ledger.cards.append(previous)
        var future = card; future.id = UUID(); future.dedupeKey = "feedback:future"; future.feedbackAt = Dates.addDays(1, to: now)
        ledger.cards.append(future)
        var wish = WishItem(title: "已买的合成心愿", amount: 1000); wish.status = .bought
        wish.followUpAnswer = "值得：更适合现在的住处"; wish.followUpAnsweredAt = now; ledger.wishlist = [wish]
        let script = try transport(output())
        _ = try await MemoryReflection.run(ledger: ledger, transport: script, now: now)
        let requests = await script.recorded()
        XCTAssertNotNil(requests[0].groupID); XCTAssertEqual(requests[0].groupTitle, "每周回看与记忆提炼")
        let input = try JSONValue.parse(try XCTUnwrap(requests[0].messages.last?.content))
        XCTAssertEqual(input["last_week"]?["start"], .string("2026-10-12")); XCTAssertEqual(input["last_week"]?["end"], .string("2026-10-18"))
        XCTAssertEqual(input["last_week"]?["summary"]?["matched_count"], .number(1))
        XCTAssertEqual(input["last_week"]?["notable"]?.arrayValue?.count, 1)
        XCTAssertEqual(input["memories"]?["life"]?.arrayValue?.count, 152)
        XCTAssertEqual(input["memories"]?["omitted_count"], .number(0))
        XCTAssertEqual(input["this_week_feedback"]?.arrayValue?.count, 1)
        XCTAssertEqual(input["this_week_followups"]?.arrayValue?.count, 1)
        XCTAssertNil(input["profile"]?["memories"])
    }
    func testDueUsesISOWeekYearBoundaryAndSuccessfulEmptyResultStampsWeek() async throws {
        var ledger = seed(); let date = Dates.parse("2027-01-01 12:00")!
        XCTAssertEqual(ButlerCards.isoWeek(date), "2026-W53")
        let result = try await MemoryReflection.run(ledger: ledger, transport: transport(output()), now: date)
        try result.apply(to: &ledger, now: date)
        XCTAssertFalse(MemoryReflection.isDue(ledger: ledger, now: Dates.parse("2027-01-03")!))
        XCTAssertTrue(MemoryReflection.isDue(ledger: ledger, now: Dates.parse("2027-01-04")!))
        XCTAssertEqual(try LedgerCodec.decode(LedgerCodec.encode(ledger)).lastReflectionWeek, "2026-W53")
        let noCalls = ScriptedChatTransport([])
        do { _ = try await MemoryReflection.run(ledger: ledger, transport: noCalls, now: date); XCTFail("Repeated weekly reflection accepted") } catch {}
        let requests = await noCalls.recorded(); XCTAssertTrue(requests.isEmpty)
    }
}
