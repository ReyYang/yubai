import XCTest
@testable import YubaiCore

final class SavingConversationTests: XCTestCase {
    func testLegacyModelMappingForSavedEnvironmentAndDirectConfiguration() throws {
        let suite = "SavingModelTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)); defer { defaults.removePersistentDomain(forName: suite) }
        for (old, new) in [("deepseek-chat", "deepseek-v4-flash"), ("deepseek-flash", "deepseek-v4-flash"), ("deepseek-reasoner", "deepseek-v4-pro")] {
            defaults.set(old, forKey: DeepSeekConfiguration.modelPreferenceKey)
            XCTAssertEqual(DeepSeekConfiguration.modelName(environment: [:], defaults: defaults), new)
            XCTAssertEqual(DeepSeekConfiguration.modelName(environment: ["DEEPSEEK_MODEL": " " + old + " "], defaults: defaults), new)
            XCTAssertEqual(DeepSeekConfiguration(apiKey: "fake", model: old).model, new)
        }
        XCTAssertEqual(DeepSeekConfiguration.defaultModel, "deepseek-v4-flash")
        XCTAssertEqual(DeepSeekClient.fallbackModels, ["deepseek-v4-flash", "deepseek-v4-pro"])
        XCTAssertEqual(DeepSeekConfiguration.canonicalModel("private-future-model"), "private-future-model")
    }
    func testPurchaseReflectionReceivesCodeVerdictThroughFakeTransport() async throws {
        let transport = ScriptedChatTransport([ChatMessage(role: .assistant, content: "可以先借来用几次，看看是否常用。")])
        let result = try await CloudBackend.reflectPurchase(title: "相机", purpose: "试着拍照", assessmentTitle: "合成财务结论", verdict: .skip, transport: transport)
        XCTAssertTrue(result.contains("借"))
        let requests = await transport.recorded()
        XCTAssertTrue(requests[0].messages[0].content?.contains("财务结论由程序给定，不得推翻") == true)
        XCTAssertTrue(requests[0].messages[1].content?.contains("skip「先别买」") == true)
    }
    func testRevisitAutomaticallyUsesCurrentProfileAndMemories() async throws {
        let ctx = AssistantFixtures.context(); var ledger = ctx.ledger
        ledger.profile.principles = ["日常用得上才买"]
        ledger.memories = [MemoryNote(text: "打算长期徒步", kind: .plan, source: .chat, createdAt: ctx.now)]
        let transport = ScriptedChatTransport([ChatMessage(role: .assistant, toolCalls: [ChatToolCall(id: "profile", name: "get_profile")]), ChatMessage(role: .assistant, content: "你现在最想调整哪件事？")])
        let reply = try await ProfileColdStart(transport: transport).next(ledger: ledger, messages: [], now: ctx.now)
        XCTAssertTrue(reply.proposedChangeSets.isEmpty)
        let requests = await transport.recorded()
        XCTAssertTrue(requests[0].messages[0].content?.contains("这是再聊") == true)
        XCTAssertTrue(requests[0].messages[1].content?.contains("长期徒步") == true)
        XCTAssertTrue(requests[1].messages.last?.content?.contains("日常用得上才买") == true)
        XCTAssertTrue(requests[0].tools.contains { $0.function.name == "remember" })
        XCTAssertFalse(requests[0].tools.contains { $0.function.name == "propose_profile_change" })
    }
    func testRevisitOpeningContextsAreIncludedAndRedacted() async throws {
        let ctx = AssistantFixtures.context()
        for (context, expected) in [(ProfileColdStart.OpeningContext.weeklyLetter("这周更常自己做饭"), "这周更常自己做饭"), (.wishRegret("登山鞋"), "登山鞋"), (.restrainExceeded("咖啡本周多了一次"), "咖啡本周多了一次")] {
            let transport = ScriptedChatTransport([ChatMessage(role: .assistant, content: "想从这件事聊起吗？")])
            _ = try await ProfileColdStart(transport: transport).next(ledger: ctx.ledger, messages: [], mode: .revisit, openingContext: context, now: ctx.now)
            let requests = await transport.recorded(); XCTAssertTrue(requests[0].messages[0].content?.contains(expected) == true)
        }
    }
    func testRevisitCanContinuePastThreeTurnsAndProposeOnlyAfterUserSpeaks() async throws {
        let ctx = AssistantFixtures.context(); var ledger = ctx.ledger; ledger.profile.principles = ["先借再买"]
        let messages = (0..<4).flatMap { _ in [ChatMessage(role: .assistant, content: "想改哪里？"), ChatMessage(role: .user, content: "咖啡每周最多一次")] }
        let transport = ScriptedChatTransport([ChatMessage(role: .assistant, toolCalls: [ChatToolCall(id: "change", name: "propose_profile_change", arguments: #"{"reason":"用户调整","operation":"upsert_area","stance":"restrain","title":"咖啡","subcategories":["餐饮/咖啡饮品"],"per_week_count":1}"#)]), ChatMessage(role: .assistant, content: "整理好了，请确认。")])
        let reply = try await ProfileColdStart(transport: transport).next(ledger: ledger, messages: messages, now: ctx.now)
        XCTAssertEqual(reply.proposedChangeSets.count, 1); XCTAssertTrue(reply.proposedChangeSets[0].isProfileOnly)
        XCTAssertEqual(ledger.profile.principles, ["先借再买"])
        guard case .profile(.upsertArea(let area, _)) = reply.proposedChangeSets[0].items[0] else { return XCTFail("area") }
        XCTAssertEqual(area.match.subcategories, ["餐饮/咖啡饮品"])
    }
    func testPurchasePromptIncludesQuestionsVerdictsMemoryAndUserChoice() {
        let prompt = AskYubai.prompt(now: AssistantFixtures.context().now)
        for word in ["ask_purchase_questions", "submit_verdict", "最后由用户决定", "用户坚持要买", "remember", "长期徒步", "similar_followups", "直接给结论"] { XCTAssertTrue(prompt.contains(word), word) }
        XCTAssertFalse(prompt.contains("不打分、不说教、不替用户决定"))
    }
}
