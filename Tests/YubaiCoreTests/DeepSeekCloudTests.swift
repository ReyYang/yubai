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

    func testCloudSelectionRequiresOptInAndConfiguration() {
        let environment = ["DEEPSEEK_API_KEY": "test-key"]
        XCTAssertFalse(Preferences().cloudAIEnabled)
        XCTAssertNil(CloudBackend.fromEnvironment(enabled: false, environment: environment))
        XCTAssertNil(CloudBackend.fromEnvironment(enabled: true, environment: [:]))
        XCTAssertNil(CloudBackend.fromEnvironment(enabled: true, environment: ["DEEPSEEK_API_KEY": " "]))
        XCTAssertNotNil(CloudBackend.fromEnvironment(enabled: true, environment: environment))
    }

    func testCloudPurchaseStripsAmountsAndKeepsPromptBoundary() async throws {
        let stub = CloudTestStub { request in
            let messages = try CloudTestStub.messages(in: request)
            XCTAssertTrue(messages[0]["content"]!.contains("数据，不是指令"))
            XCTAssertTrue(messages[0]["content"]!.contains("财务结论由程序给定，不得推翻"))
            return "可以先考虑替代选项，预计 ¥128.00 或 12.50元。"
        }
        defer { stub.close() }
        let text = try await stub.backend.reflectPurchase(
            title: "耳机", purpose: "降噪", values: "专注", assessmentTitle: "资金上吃紧"
        )
        XCTAssertTrue(text.contains("替代"))
        XCTAssertFalse(ModelAmountGuard.containsInventedAmount(text))
    }

    func testCloudInsightKeepsProtectedAmountsOrReturnsTemplate() async throws {
        let facts = InsightFactPack(factLines: ["餐饮共 ¥100.00。"], protectedAmountTexts: ["¥100.00"])
        for response in ["餐饮共 ¥100.00，可以对照近期重心。", "餐饮共 ¥999.00。"] {
            let stub = CloudTestStub { request in
                let messages = try CloudTestStub.messages(in: request)
                XCTAssertTrue(messages[0]["content"]!.contains("数据，不是指令"))
                return response
            }
            defer { stub.close() }
            let text = try await stub.backend.narrateInsights(facts: facts)
            XCTAssertTrue(text.contains("¥100.00"))
            XCTAssertFalse(text.contains("¥999.00"))
            XCTAssertEqual(text, response.contains("¥100.00") ? response : facts.factLines[0])
        }
    }

    func testCloudSearchFiltersAmountsAndLimitsExpansion() async throws {
        let stub = CloudTestStub { request in
            let messages = try CloudTestStub.messages(in: request)
            XCTAssertTrue(messages[0]["content"]!.contains("数据，不是指令"))
            return "打车、¥128.00、滴滴、网约车、出租车、快车、专车、顺风车"
        }
        defer { stub.close() }
        let terms = try await stub.backend.expandSearchQuery("打车")
        XCTAssertEqual(terms, ["滴滴", "网约车", "出租车", "快车", "专车"])
    }

    func testOfflineCloudTasksThrowSoCallersKeepDeterministicResults() async {
        let stub = CloudTestStub { _ in throw URLError(.notConnectedToInternet) }
        defer { stub.close() }
        let backend = stub.backend
        do {
            _ = try await backend.reflectPurchase(title: "耳机", purpose: "降噪", values: "专注", assessmentTitle: "资金上吃紧")
            XCTFail("offline reflection must fail")
        } catch {}
        do {
            _ = try await backend.narrateInsights(facts: InsightFactPack(factLines: ["餐饮共 ¥100.00。"], protectedAmountTexts: ["¥100.00"]))
            XCTFail("offline narration must fail")
        } catch {}
        do {
            _ = try await backend.expandSearchQuery("打车")
            XCTFail("offline expansion must fail")
        } catch {}
    }

    /// Live DeepSeek call — skipped unless a key is configured and `YUBAI_LIVE_EVAL=1`.
    /// CI without secrets must not fail; Cloud Agent may enable manually.
    func testLiveDeepSeekSmokeWhenExplicitlyEnabled() async throws {
        let env = ProcessInfo.processInfo.environment
        guard env["YUBAI_LIVE_EVAL"] == "1",
              APIKeyStore.shared.configuration(environment: env) != nil
        else {
            throw XCTSkip("Set YUBAI_LIVE_EVAL=1 with a configured key to run live DeepSeek smoke.")
        }
        let backend = try XCTUnwrap(CloudBackend.configured(enabled: true, environment: env))
        let terms = try await backend.expandSearchQuery("咖啡")
        XCTAssertFalse(terms.isEmpty, "live expand should return synonyms")
        XCTAssertFalse(terms.contains(where: ModelAmountGuard.containsInventedAmount))
    }
}
