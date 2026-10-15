import XCTest
@testable import YubaiCore

final class AIBenchTests: XCTestCase {
    func testRoutingDefaultsToRulesWithoutWeightsAndCloudOff() {
        var prefs = Preferences()
        prefs.localAIEnabled = true
        prefs.downloadedModelEnabled = true
        prefs.cloudAIEnabled = false
        prefs.appleSystemModelEnabled = false
        let route = IntelligenceRouting.resolve(preferences: prefs, localWeightReady: false, appleFMAvailable: true)
        XCTAssertEqual(route.kind, .rulesOnly)
    }

    func testRoutingPrefersLocalWeightThenCloudThenAppleFM() {
        var prefs = Preferences()
        prefs.localAIEnabled = true
        prefs.downloadedModelEnabled = true
        prefs.cloudAIEnabled = true
        prefs.appleSystemModelEnabled = true
        XCTAssertEqual(
            IntelligenceRouting.resolve(preferences: prefs, localWeightReady: true, appleFMAvailable: true).kind,
            .localDownloaded
        )
        prefs.downloadedModelEnabled = false
        XCTAssertEqual(
            IntelligenceRouting.resolve(preferences: prefs, localWeightReady: false, appleFMAvailable: true).kind,
            .cloudOptional
        )
        prefs.cloudAIEnabled = false
        XCTAssertEqual(
            IntelligenceRouting.resolve(preferences: prefs, localWeightReady: false, appleFMAvailable: true).kind,
            .appleFMOptional
        )
    }

    func testWeightStoreBlocksPlaceholderDownload() async {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = ModelWeightStore(directory: dir, blockPlaceholderDownloads: true)
        let spec = ModelWeightCatalog.defaults[0]
        do {
            try await store.download(spec: spec)
            XCTFail("placeholder download should be blocked")
        } catch ModelWeightError.placeholderBlocked {
            // expected
        } catch {
            XCTFail("unexpected \(error)")
        }
        try? FileManager.default.removeItem(at: dir)
    }

    func testWeightInstallFixtureAndReadyFlag() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ModelWeightStore(directory: dir)
        let spec = ModelWeightCatalog.defaults[0]
        XCTAssertFalse(store.hasReadyWeight)
        try store.installFixture(spec: spec, data: Data("gguf-fixture".utf8))
        XCTAssertTrue(store.hasReadyWeight)
        try store.delete(spec: spec)
        XCTAssertFalse(store.hasReadyWeight)
    }

    func testInsightGuardRejectsMissingProtectedAmount() {
        XCTAssertNil(InsightNarrationGuard.accept("餐饮很多", protecting: ["¥1,280.50"]))
        XCTAssertNotNil(InsightNarrationGuard.accept("餐饮共 ¥1,280.50，可对照重心。", protecting: ["¥1,280.50"]))
    }

    func testBenchRulesMockLocalAndMockCloud() async throws {
        let fixture = try AIBenchRunner.loadBundledFixture(bundle: .module)

        let rules = await AIBenchRunner.run(fixture: fixture, backend: RulesOnlyBackend())
        let mockLocal = await AIBenchRunner.run(fixture: fixture, backend: MockLocalBackend())
        let mockCloud = await AIBenchRunner.run(fixture: fixture, backend: MockCloudBackend())

        print(rules.summary)
        print(mockLocal.summary)
        print(mockCloud.summary)

        // Rules should do well on categorize + insight; purchase intentionally weak.
        XCTAssertGreaterThanOrEqual(rules.categorizePass, 10, rules.summary)
        XCTAssertEqual(rules.insightPass, rules.insightTotal, rules.summary)

        // Mock local should clear a high bar across all four tasks.
        XCTAssertGreaterThanOrEqual(mockLocal.passRate, 0.75, mockLocal.summary)
        XCTAssertGreaterThanOrEqual(mockLocal.categorizePass, 12, mockLocal.summary)
        XCTAssertGreaterThanOrEqual(mockLocal.purchasePass, 10, mockLocal.summary)
        XCTAssertEqual(mockLocal.insightPass, mockLocal.insightTotal, mockLocal.summary)
        XCTAssertGreaterThanOrEqual(mockLocal.searchPass, 10, mockLocal.summary)

        XCTAssertGreaterThanOrEqual(mockCloud.passRate, 0.75, mockCloud.summary)
    }

    func testSemanticSearchExpansionHelpsSynonyms() async throws {
        let expanded = try await MockLocalBackend().expandSearchQuery("打车")
        XCTAssertTrue(expanded.contains(where: { $0.localizedCaseInsensitiveContains("滴滴") }))
        let corpus: [(id: UUID, title: String, note: String, category: String)] = [
            (UUID(), "滴滴出行到公司", "", "交通"),
            (UUID(), "午饭", "", "餐饮")
        ]
        let ids = SemanticSearchSupport.matchEntries(query: "打车", expandedTerms: expanded, entries: corpus)
        XCTAssertEqual(ids.count, 1)
        XCTAssertEqual(ids[0], corpus[0].id)
    }

    func testPreferenceMigrationKeepsAppleFMWhenLegacyOnlyHadLocalAI() throws {
        var ledger = Ledger()
        ledger.preferences.localAIEnabled = true
        var json = try JSONSerialization.jsonObject(with: LedgerCodec.encode(ledger)) as! [String: Any]
        var preferences = json["preferences"] as! [String: Any]
        preferences.removeValue(forKey: "appleSystemModelEnabled")
        preferences.removeValue(forKey: "cloudAIEnabled")
        preferences.removeValue(forKey: "downloadedModelEnabled")
        preferences.removeValue(forKey: "experimentalMockLocalAI")
        json["preferences"] = preferences
        let restored = try LedgerCodec.decode(JSONSerialization.data(withJSONObject: json))
        XCTAssertTrue(restored.preferences.appleSystemModelEnabled)
        XCTAssertFalse(restored.preferences.cloudAIEnabled)
        XCTAssertTrue(restored.preferences.downloadedModelEnabled)
        XCTAssertFalse(restored.preferences.experimentalMockLocalAI)
    }
}
