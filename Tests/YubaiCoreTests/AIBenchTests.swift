import XCTest
@testable import YubaiCore

final class AIBenchTests: XCTestCase {
    private func smallFixture() throws -> AIBenchFixture {
        var fixture = try AIBenchRunner.loadBundledFixture(bundle: .module)
        fixture.categorize = Array(fixture.categorize.prefix(1))
        fixture.purchase = Array(fixture.purchase.prefix(1))
        fixture.insight = Array(fixture.insight.prefix(1))
        fixture.search = Array(fixture.search.prefix(1))
        return fixture
    }

    func testBundledCloudFixtureCoversAllTasks() throws {
        let fixture = try AIBenchRunner.loadBundledFixture(bundle: .module)
        XCTAssertEqual(fixture.categorize.count, 16)
        XCTAssertEqual(fixture.purchase.count, 12)
        XCTAssertEqual(fixture.insight.count, 12)
        XCTAssertEqual(fixture.search.count, 12)
        for sample in fixture.insight {
            XCTAssertFalse(sample.protectedAmountTexts.isEmpty)
            XCTAssertNotNil(InsightNarrationGuard.accept(sample.factLines.joined(separator: " "), protecting: sample.protectedAmountTexts))
        }
    }

    func testRunnerScoresCloudResponsesAcrossAllTasks() async throws {
        let fixture = try smallFixture()
        let stub = CloudTestStub { request in
            let messages = try CloudTestStub.messages(in: request)
            let system = messages[0]["content"]!
            if system.contains("选择分类") { return #"[{"index":0,"category":"餐饮"}]"# }
            if system.contains("消费思考助手") { return "可以先考虑替代方案，资金结论以程序判断为准。" }
            if system.contains("资金线索") { return "餐饮共 ¥1,280.50，可以对照近期重心。" }
            return "星巴克、瑞幸"
        }
        defer { stub.close() }
        let score = await AIBenchRunner.run(fixture: fixture, backend: stub.backend)
        XCTAssertEqual(score.categorizePass, 1)
        XCTAssertEqual(score.purchasePass, 1)
        XCTAssertEqual(score.insightPass, 1)
        XCTAssertEqual(score.searchPass, 1)
        XCTAssertEqual(score.totalCases, 4)
        XCTAssertEqual(score.passRate, 1)
        XCTAssertFalse(score.summary.contains("test-key"))
    }

    func testRunnerCountsRequestFailuresForEveryTask() async throws {
        let stub = CloudTestStub { _ in throw URLError(.notConnectedToInternet) }
        defer { stub.close() }
        let score = await AIBenchRunner.run(fixture: try smallFixture(), backend: stub.backend)
        XCTAssertEqual(score.totalCases, 4)
        XCTAssertEqual(score.totalPass, 0)
        XCTAssertEqual(score.passRate, 0)
    }

    func testRunnerRejectsWrongAnswersAndScoresGuardedInsightFallback() async throws {
        let stub = CloudTestStub { request in
            let messages = try CloudTestStub.messages(in: request)
            if messages[0]["content"]!.contains("选择分类") { return #"[{"index":0,"category":"交通"}]"# }
            return "不相关的答复"
        }
        defer { stub.close() }
        let score = await AIBenchRunner.run(fixture: try smallFixture(), backend: stub.backend)
        XCTAssertEqual(score.categorizePass, 0)
        XCTAssertEqual(score.purchasePass, 0)
        XCTAssertEqual(score.searchPass, 0)
        // This is the guarded backend result: missing amounts restore the local template.
        XCTAssertEqual(score.insightPass, 1)
        XCTAssertEqual(score.totalPass, 1)
    }

    func testInsightGuardRejectsMissingProtectedAmount() {
        XCTAssertNil(InsightNarrationGuard.accept("餐饮很多", protecting: ["¥1,280.50"]))
        XCTAssertNotNil(InsightNarrationGuard.accept("餐饮共 ¥1,280.50，可对照重心。", protecting: ["¥1,280.50"]))
    }

    func testSearchExpansionMatchesSynonymsWithoutChangingEntries() async throws {
        let stub = CloudTestStub { _ in "滴滴、网约车" }
        defer { stub.close() }
        let expanded = try await stub.backend.expandSearchQuery("打车")
        let corpus: [(id: UUID, title: String, note: String, category: String)] = [
            (UUID(), "滴滴出行到公司", "", "交通"),
            (UUID(), "午饭", "", "餐饮")
        ]
        let ids = SemanticSearchSupport.matchEntries(query: "打车", expandedTerms: expanded, entries: corpus)
        XCTAssertEqual(ids, [corpus[0].id])
    }

    /// Full cloud evaluation is opt-in and uses only the bundled synthetic fixture.
    func testLiveCloudFixtureWhenExplicitlyEnabled() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["YUBAI_LIVE_EVAL"] == "1",
              let backend = CloudBackend.configured(enabled: true, environment: environment)
        else { throw XCTSkip("Set YUBAI_LIVE_EVAL=1 and a configured key to run the cloud fixture.") }
        let fixture = try AIBenchRunner.loadBundledFixture(bundle: .module)
        let score = await AIBenchRunner.run(fixture: fixture, backend: backend)
        print(score.summary)
        XCTAssertEqual(score.totalCases, 52)
        XCTAssertGreaterThan(score.totalPass, 0, score.summary)
    }
}
