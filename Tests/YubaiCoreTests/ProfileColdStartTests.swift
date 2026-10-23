import XCTest
@testable import YubaiCore

final class ProfileColdStartTests: XCTestCase {
    private let wholeProfile = #"{"reason":"根据这次聊天整理，等你确认","items":[{"operation":"upsert_area","stance":"generous","title":"学习","categories":["学习"],"keywords":["书"]},{"operation":"upsert_area","stance":"restrain","title":"外卖","keywords":["外卖"],"per_week_count":3,"per_month_amount":"500"},{"operation":"add_principle","text":"大件先等两天"},{"operation":"set_floor","amount":"5000"}]}"#
    func testThreeQuestionsThenOneProposalAndOnlyConfirmationChangesProfile() async throws {
        let ctx = AssistantFixtures.context()
        let script = ScriptedChatTransport([
            ChatMessage(role: .assistant, content: "什么事情让你觉得多花一点也值得？"),
            ChatMessage(role: .assistant, content: "哪些花费，你想克制一点？"),
            ChatMessage(role: .assistant, content: "你希望始终留着多少钱？"),
            ChatMessage(role: .assistant, toolCalls: [ChatToolCall(id: "read", name: "get_profile")]),
            ChatMessage(role: .assistant, toolCalls: [ChatToolCall(id: "whole", name: "propose_profile_change", arguments: wholeProfile)]),
            ChatMessage(role: .assistant, content: "整理好了一份消费观，确认后才会生效。")])
        let coldStart = ProfileColdStart(transport: script)
        var messages: [ChatMessage] = []
        let original = try LedgerCodec.encode(ctx.ledger)
        for answer in ["学习、读书值得多花。", "外卖每周最多三次，每月五百。大件先等两天。", "五千元。"] {
            let reply = try await coldStart.next(ledger: ctx.ledger, messages: messages, mode: .coldStart, now: ctx.now)
            XCTAssertTrue(reply.proposedChangeSets.isEmpty)
            XCTAssertLessThanOrEqual(reply.text.filter { $0 == "？" || $0 == "?" }.count, 1)
            messages.append(ChatMessage(role: .assistant, content: reply.text))
            messages.append(ChatMessage(role: .user, content: answer))
        }
        let final = try await coldStart.next(ledger: ctx.ledger, messages: messages, mode: .coldStart, now: ctx.now)
        XCTAssertEqual(final.proposedChangeSets.count, 1)
        let change = try XCTUnwrap(final.proposedChangeSets.first)
        XCTAssertTrue(change.isProfileOnly); XCTAssertEqual(change.items.count, 4)
        XCTAssertEqual(try LedgerCodec.encode(ctx.ledger), original)
        var confirmed = ctx.ledger; try change.apply(to: &confirmed)
        XCTAssertEqual(confirmed.profile.generous.map(\.title), ["学习"])
        XCTAssertEqual(confirmed.profile.restrain.map(\.title), ["外卖"])
        XCTAssertEqual(confirmed.profile.restrain[0].softLimit, SoftLimit(perWeekCount: 3, perMonthAmount: 50_000))
        XCTAssertEqual(confirmed.profile.principles, ["大件先等两天"])
        XCTAssertEqual(confirmed.profile.floorAmount, 500_000)
        XCTAssertEqual(confirmed.entries, ctx.ledger.entries)
        XCTAssertEqual(confirmed.accounts, ctx.ledger.accounts)
        XCTAssertEqual(confirmed.plans, ctx.ledger.plans); XCTAssertEqual(confirmed.goals, ctx.ledger.goals)
        XCTAssertEqual(try LedgerCodec.decode(LedgerCodec.encode(confirmed)).profile, confirmed.profile)
        let requests = await script.recorded()
        XCTAssertEqual(requests.count, 6)
        for request in requests.prefix(3) { XCTAssertEqual(request.tools.map(\.function.name), ["get_profile", "recall"]) }
        XCTAssertEqual(requests.last?.tools.map(\.function.name), ["get_profile", "propose_profile_change", "recall"])
        XCTAssertEqual(final.toolTrace.filter { $0.name == "propose_profile_change" }.count, 1)
    }
    func testRevisionStillProducesOneProposalWithoutMoreQuestions() async throws {
        let ctx = AssistantFixtures.context()
        let script = ScriptedChatTransport([
            ChatMessage(role: .assistant, toolCalls: [ChatToolCall(id: "revision", name: "propose_profile_change", arguments: wholeProfile)]),
            ChatMessage(role: .assistant, content: "已重新整理，等你确认。")])
        let messages = ["愿意多花的？", "想克制的？", "底线多少？"].flatMap { question in
            [ChatMessage(role: .assistant, content: question), ChatMessage(role: .user, content: "暂时没想好")]
        } + [ChatMessage(role: .user, content: "学习可以多花，外卖每周三次每月五百，底线五千，大件先等两天。")]
        let reply = try await ProfileColdStart(transport: script).next(ledger: ctx.ledger, messages: messages, mode: .coldStart, now: ctx.now)
        XCTAssertEqual(reply.proposedChangeSets.count, 1)
        let requests = await script.recorded()
        XCTAssertTrue(requests[0].messages[0].content?.contains("不再提问") == true)
    }
    func testMultipleProposalsAreRejectedRatherThanPartiallyReturned() async throws {
        let script = ScriptedChatTransport([
            ChatMessage(role: .assistant, toolCalls: [
                ChatToolCall(id: "one", name: "propose_profile_change", arguments: wholeProfile),
                ChatToolCall(id: "two", name: "propose_profile_change", arguments: wholeProfile)]),
            ChatMessage(role: .assistant, content: "请确认。")])
        let messages = (0..<3).flatMap { _ in [ChatMessage(role: .assistant, content: "一个问题？"), ChatMessage(role: .user, content: "好")] }
        do {
            _ = try await ProfileColdStart(transport: script).next(ledger: AssistantFixtures.context().ledger, messages: messages, mode: .coldStart)
            XCTFail("must return exactly one proposal")
        } catch { XCTAssertTrue(error is YubaiError) }
    }
    func testBatchValidationIsAtomicAndSingleOperationRemainsSupported() throws {
        let ctx = AssistantFixtures.context()
        let change = try ProposalTool.profile.propose(JSONValue.parse(wholeProfile), ctx)
        XCTAssertTrue(change.isProfileOnly)
        let single = try ProposalTool.profile.propose(JSONValue.parse(#"{"reason":"反馈","operation":"add_principle","text":"值得的再买"}"#), ctx)
        XCTAssertEqual(single.items, [.profile(.addPrinciple("值得的再买"))])
        let invalid = wholeProfile.replacingOccurrences(of: #""amount":"5000""#, with: #""amount":"-1""#)
        XCTAssertThrowsError(try ProposalTool.profile.propose(JSONValue.parse(invalid), ctx))
        XCTAssertThrowsError(try ProposalTool.profile.propose(JSONValue.parse(#"{"reason":"反馈","items":[]}"#), ctx))
        XCTAssertThrowsError(try ProposalTool.profile.propose(JSONValue.parse(#"{"reason":"反馈","operation":"clear_floor","items":[{"operation":"clear_floor"}]}"#), ctx))
        XCTAssertThrowsError(try ProposalTool.profile.propose(JSONValue.parse(#"{"reason":"反馈","items":[{"operation":"set_floor","amount":"100","entries":[]}] }"#), ctx))
    }
}
