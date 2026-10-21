import XCTest
@testable import YubaiCore

final class MultiEntryTests: XCTestCase {
    private func rows(_ amounts: [String], _ ctx: ToolContext) -> [JSONValue] {
        amounts.enumerated().map { index, amount in .object([
            "title": .string("补记\(index)"), "amount": .string(amount), "date": .string(Dates.text(ctx.now)),
            "account": .string(ctx.ledger.accounts[0].id.uuidString), "category": .string("餐饮"),
            "nature": .string("expense"), "purpose": .string("本地原文补记")]) }
    }
    private func args(_ rows: [JSONValue]) -> JSONValue { .object(["reason": .string("用户补记多笔"), "entries": .array(rows)]) }
    func testLocalFragmentsMultiplicityAndExcludedNumbers() {
        let entries = EntryAmountParser.entries(in: "午饭 32、打车 15、咖啡 28")
        XCTAssertEqual(entries.map(\.text), ["午饭", "打车", "咖啡"])
        XCTAssertEqual(entries.map(\.amount), [3200, 1500, 2800])
        for text in ["两杯咖啡各 18", "2杯咖啡每杯18", "两份午餐各18元"] {
            XCTAssertEqual(EntryAmountParser.candidates(in: text), [1800, 1800], text)
        }
        XCTAssertEqual(EntryAmountParser.candidates(in: "咖啡18 咖啡18"), [1800, 1800])
        XCTAssertEqual(EntryAmountParser.candidates(in: "三杯咖啡18"), [1800])
        XCTAssertEqual(EntryAmountParser.candidates(in: "两杯咖啡和三杯茶各18"), [1800])
        XCTAssertEqual(EntryAmountParser.candidates(in: "买2杯咖啡共18元"), [1800])
        XCTAssertEqual(EntryAmountParser.candidates(in: "早餐 12 午餐 32 晚餐 45 都用微信"), [1200, 3200, 4500])
        XCTAssertEqual(EntryAmountParser.entries(in: "2026-06-15 12:30 午饭 ￥32.50 2个人 订单123456789012").map(\.amount), [3250])
    }
    func testMultisetRejectsOveruseAndSupportsLegacySingleEntry() throws {
        let base = AssistantFixtures.context()
        let once = ToolContext(ledger: base.ledger, now: base.now, parsedEntryAmounts: [1800])
        let twice = ToolContext(ledger: base.ledger, now: base.now, parsedEntryAmounts: [1800, 1800])
        let input = args(rows(["18", "18"], base))
        XCTAssertThrowsError(try ProposalTool.entry.propose(input, once))
        let proposal = try ProposalTool.entry.propose(input, twice)
        XCTAssertEqual(proposal.items.count, 2)
        let lines = proposal.preview(in: base.ledger)
        XCTAssertEqual(lines.count, 3); XCTAssertTrue(lines[2].contains("合计 2 笔，¥36.00"))
        var legacy = try XCTUnwrap(rows(["18"], base)[0].objectValue); legacy["reason"] = .string("单笔兼容")
        XCTAssertEqual(try ProposalTool.entry.propose(.object(legacy), once).items.count, 1)
        var mixed = input.objectValue!; mixed["title"] = .string("混用")
        XCTAssertThrowsError(try ProposalTool.entry.propose(.object(mixed), twice))
        XCTAssertThrowsError(try ProposalTool.entry.propose(args([]), twice))
        let confirmed = ToolContext(ledger: base.ledger, now: base.now, confirmedEntryAmount: 1800)
        XCTAssertThrowsError(try ProposalTool.entry.propose(input, confirmed))
    }
    func testSessionExposesParsedEntriesAndProposesOneChangeSet() async throws {
        let ctx = AssistantFixtures.context()
        let input = args(rows(["32", "15", "28"], ctx))
        let transport = ScriptedChatTransport([
            ChatMessage(role: .assistant, toolCalls: [ChatToolCall(id: "profile", name: "get_profile")]),
            ChatMessage(role: .assistant, toolCalls: [ChatToolCall(id: "proposal", name: "propose_entry", arguments: try input.jsonText())]),
            ChatMessage(role: .assistant, content: "三笔待核对金额。")])
        let reply = try await AskYubaiSession().ask("午饭32、打车15、咖啡28", ledger: ctx.ledger, transport: transport, now: ctx.now)
        XCTAssertEqual(reply.proposedChangeSets.count, 1)
        let proposal = try XCTUnwrap(reply.proposedChangeSets.first)
        XCTAssertEqual(proposal.items.count, 3)
        for (index, amount) in [Int64(3200), 1500, 2800].enumerated() {
            guard case .addEntry(let draft) = proposal.items[index] else { return XCTFail("Expected an entry") }
            XCTAssertEqual(draft.amount, amount); XCTAssertFalse(draft.amountConfirmed)
        }
        let requests = await transport.recorded()
        let profile = try JSONValue.parse(XCTUnwrap(requests[1].messages.first { $0.role == .tool }?.content))
        XCTAssertEqual(profile["parsed_entries"]?.arrayValue?.map { $0["text"] }, [.string("午饭"), .string("打车"), .string("咖啡")])
        XCTAssertEqual(profile["parsed_entry_amounts"], .array([.money(3200), .money(1500), .money(2800)]))
        XCTAssertTrue(AskYubai.prompt(now: ctx.now).contains("一次propose_entry用entries一次提出全部"))
        XCTAssertFalse(AskYubai.prompt(now: ctx.now).contains("多笔或不明确时先问清是哪一笔"))
    }
    func testSessionKeepsRepeatedCandidatesWhileClarifyingAccount() async throws {
        let ctx = AssistantFixtures.context(); let session = AskYubaiSession()
        let input = args(rows(["18", "18"], ctx))
        let transport = ScriptedChatTransport([
            ChatMessage(role: .assistant, content: "这两杯用哪个账户？"),
            ChatMessage(role: .assistant, toolCalls: [ChatToolCall(id: "profile", name: "get_profile")]),
            ChatMessage(role: .assistant, toolCalls: [ChatToolCall(id: "proposal", name: "propose_entry", arguments: try input.jsonText())]),
            ChatMessage(role: .assistant, content: "两笔待确认。")])
        _ = try await session.ask("两杯咖啡各18", ledger: ctx.ledger, transport: transport, now: ctx.now)
        let reply = try await session.ask("微信", ledger: ctx.ledger, transport: transport, now: ctx.now)
        XCTAssertEqual(reply.proposedChangeSets.first?.items.count, 2)
        let requests = await transport.recorded()
        let profile = try JSONValue.parse(XCTUnwrap(requests[2].messages.last { $0.role == .tool }?.content))
        XCTAssertEqual(profile["parsed_entry_amounts"], .array([.money(1800), .money(1800)]))
        XCTAssertEqual(profile["parsed_entries"]?.arrayValue?.count, 2)
    }
    func testNoEntryCountCeiling() throws {
        let ctx = AssistantFixtures.context()
        let amounts = Array(repeating: Int64(100), count: 201)
        let context = ToolContext(ledger: ctx.ledger, now: ctx.now, parsedEntryAmounts: amounts)
        XCTAssertEqual(try ProposalTool.entry.propose(args(rows(Array(repeating: "1", count: amounts.count), ctx)), context).items.count, 201)
    }
}
