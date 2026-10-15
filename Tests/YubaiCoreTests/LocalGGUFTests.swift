import XCTest
@testable import YubaiCore
import YubaiLocalLLM

/// Offline unit coverage for local GGUF wiring. Live Metal inference is opt-in (needs downloaded weights).
final class LocalGGUFTests: XCTestCase {
    override func tearDown() {
        LocalInferenceSafety.reset()
        LocalLlamaRegistry.unload()
        super.tearDown()
    }

    func testLocalInferenceSafetyCircuitBreaker() {
        XCTAssertTrue(LocalInferenceSafety.isHealthy)
        LocalInferenceSafety.markUnhealthy("unit-test")
        XCTAssertFalse(LocalInferenceSafety.isHealthy)
        LocalInferenceSafety.reset()
        XCTAssertTrue(LocalInferenceSafety.isHealthy)
    }

    func testAmountGuardStillBlocksLocalReflectPath() async throws {
        struct AmountyInference: LocalGGUFInference {
            func complete(system: String, user: String, temperature: Float, maxTokens: Int) async throws -> String {
                "大概要花 ¥99.00，不如看看替代。"
            }
        }
        let backend = LocalDownloadedBackend(ready: true, inference: AmountyInference(), fallBackToRules: false)
        let text = try await backend.reflectPurchase(
            title: "耳机",
            purpose: "通勤用",
            values: "少而精",
            assessmentTitle: "资金上勉强可以"
        )
        XCTAssertFalse(ModelAmountGuard.containsInventedAmount(text), text)
        XCTAssertFalse(text.contains("99"))
    }

    func testInsightKeepsProtectedAmountsOrFallsBack() async throws {
        struct DropAmountInference: LocalGGUFInference {
            func complete(system: String, user: String, temperature: Float, maxTokens: Int) async throws -> String {
                "餐饮花得不少，可以对照重心。"
            }
        }
        let facts = InsightFactPack(factLines: ["餐饮共 ¥1,280.50"], protectedAmountTexts: ["¥1,280.50"])
        let backend = LocalDownloadedBackend(ready: true, inference: DropAmountInference(), fallBackToRules: false)
        let text = try await backend.narrateInsights(facts: facts)
        // Guard rejects polish → template facts.
        XCTAssertEqual(text, "餐饮共 ¥1,280.50")
    }

    func testLiveLocalGGUFSmokeWhenExplicitlyEnabled() async throws {
        let enabled = ProcessInfo.processInfo.environment["YUBAI_RUN_LOCAL_GGUF_LIVE"] == "1"
        try XCTSkipIf(!enabled, "set YUBAI_RUN_LOCAL_GGUF_LIVE=1 and install a verified Qwen GGUF to run live smoke")

        let store = ModelWeightStore()
        guard let spec = store.anyReadyWeight() else {
            throw XCTSkip("no verified GGUF in \(store.directory.path); download via Settings first")
        }
        let path = store.fileURL(for: spec).path
        let inference = try LocalLlamaRegistry.inference(at: path)
        let backend = LocalDownloadedBackend(ready: true, inference: inference, fallBackToRules: false)

        let suggestions = try await backend.categorize(
            batch: [CategorizeItem(index: 0, purpose: "瑞幸咖啡", direction: "支出")],
            allowedCategories: ["餐饮", "交通", "其他支出"]
        )
        XCTAssertFalse(suggestions.isEmpty, "live categorize returned empty")

        let advice = try await backend.reflectPurchase(
            title: "二手相机",
            purpose: "周末拍照",
            values: "少而精",
            assessmentTitle: "资金上可以承受"
        )
        XCTAssertFalse(ModelAmountGuard.containsInventedAmount(advice), advice)

        let facts = InsightFactPack(
            factLines: ["餐饮共 ¥128.00", "环比略增"],
            protectedAmountTexts: ["¥128.00"]
        )
        let narration = try await backend.narrateInsights(facts: facts)
        XCTAssertNotNil(InsightNarrationGuard.accept(narration, protecting: facts.protectedAmountTexts) ?? narration)

        let terms = try await backend.expandSearchQuery("咖啡")
        XCTAssertFalse(terms.contains(where: ModelAmountGuard.containsInventedAmount))
    }
}
