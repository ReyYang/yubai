import XCTest
@testable import YubaiCore

final class ProposalToolTests: XCTestCase {
    func testEveryToolBuildsValidatedProposalWithoutWritingLedger() throws {
        let ctx = AssistantFixtures.context(); let before = try LedgerCodec.encode(ctx.ledger)
        let entry = ctx.ledger.entries[1].id.uuidString
        let cases: [(ProposalTool, JSONValue)] = [
            (.entryChanges, .object(["reason": .string("外卖午餐"), "items": .array([.object([
                "kind": .string("set_purpose"), "entry": .string(entry), "text": .string("工作午餐")])])])),
            (.plan, .object(["reason": .string("周期付款"), "operation": .string("add_plan"), "title": .string("网费"), "amount": .string("68"), "date": .string("2026-07-01"), "frequency": .string("monthly")])),
            (.plan, .object(["reason": .string("不再订阅"), "operation": .string("end_plan"), "id": .string(ctx.ledger.plans[0].id.uuidString), "date": .string("2026-07-01")])),
            (.plan, .object(["reason": .string("房租分摊"), "operation": .string("add_rent"), "title": .string("房租"), "amount": .string("3000"), "personal_share": .string("1500"), "start_date": .string("2026-06-01"), "date": .string("2026-07-01")])),
            (.profile, .object(["reason": .string("用户想克制外卖"), "operation": .string("upsert_area"), "stance": .string("restrain"), "title": .string("外卖"), "keywords": .strings(["美团"]), "per_week_count": .number(3), "per_month_amount": .string("500")])),
            (.profile, .object(["reason": .string("用户的底线"), "operation": .string("set_floor"), "amount": .string("1000")]))
        ]
        for (tool, args) in cases {
            let change = try tool.propose(args, ctx)
            var dryRun = ctx.ledger; XCTAssertNoThrow(try change.apply(to: &dryRun))
            XCTAssertEqual(change.source, "问余白"); XCTAssertEqual(change.createdAt, ctx.now)
            let result = tool.result(change, ctx)
            XCTAssertEqual(result["id"], .string(change.id.uuidString))
            XCTAssertEqual(result["preview"]?.arrayValue?.count, change.items.count)
            XCTAssertEqual(try LedgerCodec.encode(ctx.ledger), before)
            XCTAssertTrue(ctx.ledger.pendingChanges.isEmpty)
        }
        let amount: Int64 = 4250
        let confirmed = ToolContext(ledger: ctx.ledger, now: ctx.now, confirmedEntryAmount: amount)
        let args = JSONValue.object(["reason": .string("语音补记"), "title": .string("午餐"), "amount": .string("42.50"), "date": .string("2026-06-15"), "account": .string(ctx.ledger.accounts[0].id.uuidString)])
        XCTAssertThrowsError(try ProposalTool.entry.propose(args, ctx))
        let proposal = try ProposalTool.entry.propose(args, confirmed)
        guard case .addEntry(let draft)? = proposal.items.first else { return XCTFail("missing draft") }
        XCTAssertTrue(draft.amountConfirmed); XCTAssertEqual(draft.amount, amount)
        XCTAssertEqual(try LedgerCodec.encode(confirmed.ledger), before)
        var mismatched = args.objectValue!; mismatched["amount"] = .string("43")
        XCTAssertThrowsError(try ProposalTool.entry.propose(.object(mismatched), confirmed))
        var forged = args.objectValue!; forged["amount_confirmed"] = .bool(true)
        XCTAssertThrowsError(try ProposalTool.entry.propose(.object(forged), confirmed))
    }
    func testInvalidProposalRejectedAndAmountEditsNotInToolContract() throws {
        let ctx = AssistantFixtures.context()
        for forbidden in ["amount", "account", "date"] {
            let item: JSONValue = .object(["kind": .string("set_category"), "entry": .string(ctx.ledger.entries[0].id.uuidString), "category": .string("餐饮"), forbidden: .string("123")])
            let args: JSONValue = .object(["reason": .string("尝试修改"), "items": .array([item])])
            XCTAssertThrowsError(try ProposalTool.entryChanges.propose(args, ctx))
        }
        let invalid: JSONValue = .object(["reason": .string("设置底线"), "operation": .string("set_floor"), "amount": .string("-1")])
        XCTAssertThrowsError(try ProposalTool.profile.propose(invalid, ctx))
    }
    func testAgentReturnsProposalAndRedactedPreviewUntilUserApplies() async throws {
        let ctx = AssistantFixtures.context(); let original = try LedgerCodec.encode(ctx.ledger)
        let id = ctx.ledger.entries[1].id.uuidString
        let args: JSONValue = .object(["reason": .string("按午餐用途整理"), "items": .array([.object(["kind": .string("set_purpose"), "entry": .string(id), "text": .string("工作午餐")])])])
        let transport = ScriptedChatTransport([
            ChatMessage(role: .assistant, toolCalls: [ChatToolCall(id: "proposal", name: ProposalTool.entryChanges.name, arguments: try args.jsonText())]),
            ChatMessage(role: .assistant, content: "有一份午餐用途建议，请确认。")])
        let reply = try await AssistantAgent(transport: transport, context: ctx).run(system: "只提案，用户决定。", messages: [], tools: ReadOnlyTool.all + ProposalTool.all)
        let change = try XCTUnwrap(reply.proposedChangeSets.first)
        XCTAssertEqual(reply.proposedChangeSets.count, 1); XCTAssertEqual(reply.evidenceEntryIDs, [ctx.ledger.entries[1].id])
        XCTAssertEqual(try LedgerCodec.encode(ctx.ledger), original)
        let requests = await transport.recorded()
        let toolMessage = try XCTUnwrap(requests.last?.messages.last { $0.role == .tool }?.content)
        let result = try JSONValue.parse(toolMessage)
        XCTAssertEqual(result["id"], .string(change.id.uuidString)); XCTAssertNotNil(result["preview"])
        var confirmed = ctx.ledger; try change.apply(to: &confirmed)
        XCTAssertEqual(confirmed.entries[1].displayTitle, "工作午餐")
    }
    func testAgentRejectsFailedDryRunInsteadOfReturningProposal() async throws {
        let ctx = AssistantFixtures.context()
        let transport = ScriptedChatTransport([
            ChatMessage(role: .assistant, toolCalls: [ChatToolCall(id: "bad", name: ProposalTool.profile.name, arguments: #"{"reason":"底线","operation":"set_floor","amount":"-1"}"#)]),
            ChatMessage(role: .assistant, content: "底线金额无效，请核对。")])
        let reply = try await AssistantAgent(transport: transport, context: ctx).run(system: "", messages: [], tools: ProposalTool.all)
        XCTAssertTrue(reply.proposedChangeSets.isEmpty)
        let requests = await transport.recorded()
        let message = try XCTUnwrap(requests.last?.messages.last { $0.role == .tool }?.content)
        XCTAssertNotNil(try JSONValue.parse(message)["error"])
    }
    func testUUIDsWithNumericRunsSurviveRedactionForProposalLinks() throws {
        let id = "12345678-0000-4000-8000-123456789012"
        let value: JSONValue = .object(["entry": .string(id), "plan": .string(id), "account": .string(id)])
        XCTAssertEqual(Redactor().value(value), value)
        XCTAssertEqual(Redactor().value(.string("订单12345678")), .string("订单****5678"))
    }
}
