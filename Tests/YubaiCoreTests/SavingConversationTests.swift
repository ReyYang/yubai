import XCTest
@testable import YubaiCore

final class SavingConversationTests: XCTestCase {
    func testSavedEnvironmentAndDirectModelNamesStayUnchangedWithoutCatalog() throws {
        let suite = "SavingModelTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)); defer { defaults.removePersistentDomain(forName: suite) }
        for old in ["deepseek-chat", "deepseek-v4-flash", "deepseek-flash", "deepseek-reasoner"] {
            let new = old
            defaults.set(old, forKey: DeepSeekConfiguration.modelPreferenceKey)
            XCTAssertEqual(DeepSeekConfiguration.modelName(environment: [:], defaults: defaults), new)
            XCTAssertEqual(DeepSeekConfiguration.modelName(environment: ["DEEPSEEK_MODEL": " " + old + " "], defaults: defaults), new)
            XCTAssertEqual(DeepSeekConfiguration(apiKey: "fake", model: old).model, new)
        }
        XCTAssertEqual(DeepSeekConfiguration.defaultModel, "deepseek-flash")
        XCTAssertEqual(DeepSeekClient.fallbackModels, ["deepseek-flash", "deepseek-v4-pro"])
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
    func testPurchasePromptIncludesQuestionsVerdictsMemoryAndUserChoice() {
        let prompt = AskYubai.prompt(now: AssistantFixtures.context().now)
        for word in ["ask_purchase_questions", "submit_verdict", "最后由用户决定", "用户坚持要买", "remember", "长期徒步", "similar_followups", "直接给结论"] { XCTAssertTrue(prompt.contains(word), word) }
        XCTAssertFalse(prompt.contains("不打分、不说教、不替用户决定"))
    }
}
