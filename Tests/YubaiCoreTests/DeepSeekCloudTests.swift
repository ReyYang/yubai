import XCTest
@testable import YubaiCore

final class DeepSeekCloudTests: XCTestCase {
    func testConfigurationMissingKeyReturnsNil() {
        XCTAssertNil(DeepSeekConfiguration.fromEnvironment(environment: [:]))
        XCTAssertNil(DeepSeekConfiguration.fromEnvironment(environment: ["DEEPSEEK_API_KEY": "  "]))
    }

    func testConfigurationReadsKeyAndOptionalBaseURL() {
        let config = DeepSeekConfiguration.fromEnvironment(environment: [
            "DEEPSEEK_API_KEY": "test-key-not-real",
            "DEEPSEEK_BASE_URL": "https://example.test/v1",
            "DEEPSEEK_MODEL": "deepseek-flash"
        ])
        XCTAssertEqual(config?.apiKey, "test-key-not-real")
        XCTAssertEqual(config?.baseURL.absoluteString, "https://example.test/v1")
        XCTAssertEqual(config?.model, "deepseek-flash")
        XCTAssertFalse(config?.diagnosticsLabel.contains("test-key") ?? true)
        XCTAssertEqual(
            DeepSeekClient.chatCompletionsURL(baseURL: URL(string: "https://api.deepseek.com")!).absoluteString,
            "https://api.deepseek.com/chat/completions"
        )
    }

    func testAmountGuardStripsInventedCurrency() {
        XCTAssertTrue(ModelAmountGuard.containsInventedAmount("大约要花 ¥128.00"))
        XCTAssertTrue(ModelAmountGuard.containsInventedAmount("大约 12.50元"))
        let cleaned = ModelAmountGuard.stripInventedAmounts("可以先找替代，不必花 ¥128.00，看看 12.50元 的选项。")
        XCTAssertNotNil(cleaned)
        XCTAssertFalse(ModelAmountGuard.containsInventedAmount(cleaned!))
        XCTAssertFalse(cleaned!.contains("¥"))
    }

    func testCloudOptionalDisabledThrows() async {
        let backend = CloudOptionalBackend(enabled: false, client: nil)
        do {
            _ = try await backend.expandSearchQuery("咖啡")
            XCTFail("expected disabled error")
        } catch let error as YubaiError {
            XCTAssertEqual(error, .invalid("云端增强未开启。"))
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testCloudOptionalWithoutKeyDegradesCategorizeAndSearch() async throws {
        let backend = CloudOptionalBackend(enabled: true, client: nil, fallBackToRules: true)
        let allowed = Category.defaults.map(\.name)
        let suggestions = try await backend.categorize(
            batch: [CategorizeItem(index: 0, purpose: "瑞幸咖啡", direction: "支出")],
            allowedCategories: allowed
        )
        XCTAssertEqual(suggestions.count, 1)
        XCTAssertTrue(allowed.contains(suggestions[0].category))

        let terms = try await backend.expandSearchQuery("打车")
        XCTAssertTrue(terms.contains(where: { $0.localizedCaseInsensitiveContains("滴滴") }))

        let narration = try await backend.narrateInsights(
            facts: InsightFactPack(factLines: ["餐饮共 ¥100.00"], protectedAmountTexts: ["¥100.00"])
        )
        XCTAssertTrue(narration.contains("¥100.00"))
    }

    func testParseCategorySuggestionsWhitelistAndGapFill() {
        let batch = [
            CategorizeItem(index: 0, purpose: "瑞幸咖啡", direction: "支出"),
            CategorizeItem(index: 1, purpose: "未知奇怪用途XYZ", direction: "支出")
        ]
        let allowed = Set(Category.defaults.map(\.name))
        let text = #"[{"index":0,"category":"餐饮"},{"index":1,"category":"不是白名单"}]"#
        let suggestions = CloudOptionalBackend.parseCategorySuggestions(from: text, allowed: allowed, batch: batch)
        XCTAssertEqual(suggestions.first(where: { $0.index == 0 })?.category, "餐饮")
        XCTAssertNotNil(suggestions.first(where: { $0.index == 1 }))
        XCTAssertTrue(allowed.contains(suggestions.first(where: { $0.index == 1 })!.category))
    }

    func testDelegateStillPreferredOverClient() async throws {
        let backend = CloudOptionalBackend(
            enabled: true,
            client: DeepSeekClient(configuration: DeepSeekConfiguration(apiKey: "unused")),
            delegate: MockCloudBackend()
        )
        let text = try await backend.reflectPurchase(
            title: "耳机",
            purpose: "降噪",
            values: "专注",
            assessmentTitle: "资金上吃紧"
        )
        XCTAssertTrue(text.contains("云端 mock"))
    }

    /// Live DeepSeek call — skipped unless `DEEPSEEK_API_KEY` is set and `YUBAI_RUN_DEEPSEEK_LIVE=1`.
    /// CI without secrets must not fail; Cloud Agent may enable manually.
    func testLiveDeepSeekSmokeWhenExplicitlyEnabled() async throws {
        let env = ProcessInfo.processInfo.environment
        guard env["YUBAI_RUN_DEEPSEEK_LIVE"] == "1",
              DeepSeekConfiguration.fromEnvironment(environment: env) != nil
        else {
            throw XCTSkip("Set YUBAI_RUN_DEEPSEEK_LIVE=1 with DEEPSEEK_API_KEY to run live DeepSeek smoke.")
        }
        let backend = CloudOptionalBackend.fromEnvironment(enabled: true, environment: env, fallBackToRules: false)
        let terms = try await backend.expandSearchQuery("咖啡")
        XCTAssertFalse(terms.isEmpty, "live expand should return synonyms")
        XCTAssertFalse(terms.contains(where: ModelAmountGuard.containsInventedAmount))
    }
}
