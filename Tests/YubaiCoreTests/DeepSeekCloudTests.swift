import XCTest
@testable import YubaiCore

final class DeepSeekCloudTests: XCTestCase {
    func testImportErrorsKeepTheExistingSpecificReason() async throws {
        let cases: [(Int, String, String)] = [
            (401, "", "云端密钥无效或无权访问，请检查密钥设置。"),
            (403, "", "云端密钥无效或无权访问，请检查密钥设置。"),
            (503, "", "云端服务返回错误（HTTP 503）。本机计算结果已保留。"),
            (404, #"{"error":{"code":"model_not_found"}}"#, DeepSeekError.modelUnavailable(DeepSeekConfiguration.defaultModel).localizedDescription),
            (200, "malformed", "整理返回格式无效。")
        ]
        for (status, body, expected) in cases {
            let stub = CloudTestStub(rawResponse: true, statusCode: status) { _ in body }
            defer { stub.close() }
            do { _ = try await stub.send(ChatRequest(messages: [])); XCTFail() }
            catch { XCTAssertEqual(ImportOrganizer.failureMessage(error), expected) }
        }
        for code in [URLError.timedOut, .notConnectedToInternet] {
            let stub = CloudTestStub { _ in throw URLError(code) }
            defer { stub.close() }
            do { _ = try await stub.send(ChatRequest(messages: [])); XCTFail() }
            catch { XCTAssertEqual(ImportOrganizer.failureMessage(error), "整理请求网络中断或超时。") }
        }
    }
    func testImportTimeoutOverrideDoesNotChangeOtherRequestsOrHTTPPayload() async throws {
        for timeout in [nil, 180.0] as [Double?] {
            let stub = CloudTestStub { request in
                XCTAssertEqual(request.timeoutInterval, timeout ?? 60)
                let payload = try CloudTestStub.payload(in: request)
                XCTAssertNil(payload["timeout"])
                return #"{"rows":[]}"#
            }
            defer { stub.close() }
            _ = try await stub.send(ChatRequest(messages: [], timeout: timeout))
        }
    }
    func testShortCloudTasksDisableThinking() async throws {
        let log = SendLog()
        let stub = CloudTestStub(sendLog: log) { request in
            let payload = try CloudTestStub.payload(in: request)
            XCTAssertEqual(payload["thinking"] as? [String: String], ["type": "disabled"])
            return "先看看替代选项"
        }
        defer { stub.close() }
        _ = try await stub.backend.reflectPurchase(title: "耳机", purpose: "降噪", assessmentTitle: "资金上吃紧", verdict: .skip)
        _ = try await stub.backend.narrateInsights(facts: InsightFactPack(factLines: ["近期支出稳定。"], protectedAmountTexts: []))
        _ = try await stub.backend.expandSearchQuery("耳机")
        XCTAssertEqual(log.totalCount, 3)
    }

    func testModelsUsesAuthenticatedGETAndKeepsUnknownIDsWithoutChatRequest() async throws {
        let log = SendLog()
        let before = log.totalCount
        let stub = CloudTestStub(rawResponse: true, sendLog: log) { request in
            XCTAssertEqual(request.url?.path, "/models")
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
            XCTAssertNil(request.httpBody)
            return #"{"data":[{"id":"deepseek-chat"},{"id":"deepseek-reasoner"},{"id":" future-model "},{"id":"deepseek-chat"},{"id":" "}]}"#
        }
        defer { stub.close() }
        let models = try await stub.listModels()
        XCTAssertEqual(models, ["deepseek-chat", "deepseek-reasoner", "future-model"])
        XCTAssertEqual(log.totalCount, before)
    }

    func testModelsRejectsHTTPMalformedAndEmptyResponsesWithoutExposingBody() async {
        for (status, body) in [(401, "test-key"), (503, "test-key"), (200, "not json"), (200, #"{"data":[]}"#), (200, #"{"data":[{"id":" "}]}"#), (200, #"{"data":[{}]}"#)] {
            let stub = CloudTestStub(rawResponse: true, statusCode: status) { _ in body }
            defer { stub.close() }
            do { _ = try await stub.listModels(); XCTFail("invalid model list must fail") }
            catch { XCTAssertFalse(error.localizedDescription.contains("test-key")) }
        }
        XCTAssertEqual(DeepSeekClient.fallbackModels, ["deepseek-flash", "deepseek-v4-pro"])
    }

    func testModelsPreservesVersionedBaseAndNormalizesCompletionURL() async throws {
        for basePath in ["/v1", "/v1/", "/v1/chat/completions", "/v1/chat/completions/"] {
            let stub = CloudTestStub(rawResponse: true, basePath: basePath) { request in
                XCTAssertEqual(request.url?.path, "/v1/models")
                return #"{"data":[{"id":"future-model","extra":"ignored"}]}"#
            }
            defer { stub.close() }
            let models = try await stub.listModels()
            XCTAssertEqual(models, ["future-model"])
        }
    }

    func testModelsOfflineAndCancellationDoNotReturnASuccessfulCatalog() async {
        let stub = CloudTestStub { _ in throw URLError(.notConnectedToInternet) }
        defer { stub.close() }
        do { _ = try await stub.listModels(); XCTFail("offline model list must fail") } catch {}
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await stub.listModels()
        }
        do { _ = try await task.value; XCTFail("cancelled model list must fail") }
        catch { XCTAssertTrue(error is CancellationError) }
    }
    func testModelPreferenceIsUsedWithBothKeySourcesAndEnvironmentStillWins() throws {
        let suite = "YubaiModelTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let storage = MemoryAPIKeyStorage(); let keys = APIKeyStore(storage: storage)
        XCTAssertEqual(DeepSeekConfiguration.modelName(environment: [:], defaults: defaults), DeepSeekConfiguration.defaultModel)
        defaults.set("  replacement-model  ", forKey: DeepSeekConfiguration.modelPreferenceKey)
        let env = ["DEEPSEEK_API_KEY": "env-key"]
        XCTAssertEqual(keys.configuration(environment: env, defaults: defaults)?.model, "replacement-model")
        try keys.save("keychain-key")
        XCTAssertTrue(keys.hasKeychainKey)
        XCTAssertEqual(keys.configuration(environment: env, defaults: defaults)?.apiKey, "keychain-key")
        XCTAssertEqual(keys.configuration(environment: env, defaults: defaults)?.model, "replacement-model")
        XCTAssertEqual(keys.configuration(environment: ["DEEPSEEK_MODEL": "override-model"], defaults: defaults)?.model, "override-model")
        defaults.set(" ", forKey: DeepSeekConfiguration.modelPreferenceKey)
        XCTAssertEqual(DeepSeekConfiguration.modelName(environment: ["DEEPSEEK_MODEL": " "], defaults: defaults), DeepSeekConfiguration.defaultModel)
        try keys.delete(); XCTAssertFalse(keys.hasKeychainKey)
    }
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
            title: "耳机", purpose: "降噪", values: "专注", assessmentTitle: "资金上吃紧", verdict: .skip
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

    func testPurchaseJudgmentUsesCurrentStructuredProfileAfterEditAndDeletion() async throws {
        var ledger = AssistantFixtures.context().ledger
        ledger.profile.principles = ["先看看家里有没有替代"]
        ledger.preferences.purchaseValues = "旧偏好不再引用"
        let stub = CloudTestStub { request in
            let messages = try CloudTestStub.messages(in: request)
            let user = try XCTUnwrap(messages.last?["content"])
            XCTAssertFalse(user.contains("旧偏好不再引用"))
            XCTAssertTrue(user.contains("\"generous\"")); XCTAssertTrue(user.contains("\"habits\""))
            return user.contains("先看看家里有没有替代") ? "按你的原则，先看看家里有没有替代。" : "想想它会在什么场景里用到。"
        }
        defer { stub.close() }
        let firstProfile = try ReadOnlyTool.getProfile.run(.object([:]), ToolContext(ledger: ledger))
        let first = try await stub.backend.reflectPurchase(title: "耳机", purpose: "通勤", profile: firstProfile, assessmentTitle: "已知安排内，可以承受", verdict: .buy)
        try ChangeSet(source: "用户", reason: "删除原则", items: [.profile(.removePrinciple("先看看家里有没有替代"))]).apply(to: &ledger)
        let nextProfile = try ReadOnlyTool.getProfile.run(.object([:]), ToolContext(ledger: ledger))
        let next = try await stub.backend.reflectPurchase(title: "耳机", purpose: "通勤", profile: nextProfile, assessmentTitle: "已知安排内，可以承受", verdict: .buy)
        XCTAssertNotEqual(first, next)
        XCTAssertFalse(next.contains("先看看家里有没有替代"))
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
            _ = try await backend.reflectPurchase(title: "耳机", purpose: "降噪", values: "专注", assessmentTitle: "资金上吃紧", verdict: .skip)
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

extension DeepSeekCloudTests {
    func testOrganizationUsesSelectedModelWithoutCatalogAndThinkingStaysDisabled() async throws {
        let log = SendLog()
        let stub = CloudTestStub(sendLog: log, model: "deepseek-v4-pro") { request in
            let payload = try CloudTestStub.payload(in: request)
            XCTAssertEqual(payload["thinking"] as? [String: String], ["type": "disabled"])
            XCTAssertNil(payload["purpose"])
            return #"{"rows":[]}"#
        }
        defer { stub.close() }
        _ = try await stub.send(ChatRequest(messages: [], thinking: false, purpose: "导入整理", model: "deepseek-flash"))
        _ = try await stub.send(ChatRequest(messages: [], thinking: false))
        XCTAssertEqual(stub.backend.client.configuration.model, "deepseek-v4-pro")
        XCTAssertEqual(log.items.map(\.model), ["deepseek-v4-pro", "deepseek-v4-pro"])
        for item in log.items {
            let payload = try JSONSerialization.jsonObject(with: Data(item.requestText.utf8)) as! [String: Any]
            XCTAssertEqual(payload["model"] as? String, item.model)
            XCTAssertEqual(payload["thinking"] as? [String: String], ["type": "disabled"])
        }
    }
    func testOrganizationHTTPFailuresRetainStatusIncludingAuthAndUnavailableModel() async throws {
        for status in [400, 401, 403, 404, 429, 503] {
            let stub = CloudTestStub(rawResponse: true, statusCode: status) { _ in #"{"error":{"code":"model_not_found","secret":"test-key"}}"# }
            defer { stub.close() }
            do {
                _ = try await stub.send(ChatRequest(messages: [], purpose: "导入整理", model: "deepseek-flash"))
                XCTFail("must reject HTTP error")
            } catch {
                XCTAssertEqual(error as? DeepSeekError, .http(status))
                XCTAssertEqual(ImportOrganizer.failureMessage(error), "DeepSeek 返回错误（HTTP \(status)）。")
                XCTAssertFalse(error.localizedDescription.contains("test-key"))
            }
        }
    }
}

private actor RetryWaits {
    var values: [TimeInterval] = []
    func append(_ value: TimeInterval) { values.append(value) }
}

private final class RetryCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func next() -> Int { lock.lock(); defer { lock.unlock() }; value += 1; return value }
    var count: Int { lock.lock(); defer { lock.unlock() }; return value }
}

extension DeepSeekCloudTests {
    func testOrganizationRetryStatusPartitionAndNetworkPartition() {
        for status in 100...599 {
            XCTAssertEqual(DeepSeekRetryPolicy.retries(status: status), [429, 500, 502, 503, 504].contains(status))
        }
        for code in [URLError.timedOut, .networkConnectionLost, .cannotConnectToHost, .notConnectedToInternet] {
            XCTAssertTrue(DeepSeekRetryPolicy.retries(network: URLError(code)))
        }
        for code in [URLError.cancelled, .badURL, .serverCertificateUntrusted, .userAuthenticationRequired] {
            XCTAssertFalse(DeepSeekRetryPolicy.retries(network: URLError(code)))
        }
    }
    func testRetryAfterSecondsDateInvalidValuesAndJitterBounds() {
        let now = Date(timeIntervalSince1970: 784111777) // Sun, 06 Nov 1994 08:49:37 GMT
        XCTAssertEqual(DeepSeekRetryPolicy.retryAfter(" 12 "), 12)
        XCTAssertEqual(DeepSeekRetryPolicy.retryAfter("0"), 0)
        XCTAssertEqual(DeepSeekRetryPolicy.retryAfter("300"), 30)
        XCTAssertEqual(DeepSeekRetryPolicy.retryAfter("Sun, 06 Nov 1994 08:49:57 GMT", now: now), 20)
        XCTAssertEqual(DeepSeekRetryPolicy.retryAfter("Sun, 06 Nov 1994 08:59:37 GMT", now: now), 30)
        XCTAssertEqual(DeepSeekRetryPolicy.retryAfter("Sun, 06 Nov 1994 08:49:00 GMT", now: now), 0)
        for invalid in [nil, "", "bad", "-1", "nan", "inf"] as [String?] {
            XCTAssertNil(DeepSeekRetryPolicy.retryAfter(invalid))
        }
        for retry in 1...4 {
            let base = DeepSeekRetryPolicy.delays[retry - 1]
            XCTAssertEqual(DeepSeekRetryPolicy.delay(retry: retry, jitter: 0), base * 0.8, accuracy: 0.00001)
            XCTAssertEqual(DeepSeekRetryPolicy.delay(retry: retry, jitter: 1), base * 1.2, accuracy: 0.00001)
            XCTAssertEqual(DeepSeekRetryPolicy.delay(retry: retry, header: "300", jitter: 1), 30)
        }
    }
    func testEachRetryableHTTPStatusExhaustsBoundedRetriesInTheSameLogItem() async throws {
        for status in [429, 500, 502, 503, 504] {
            let counter = RetryCounter(), log = SendLog(), waits = RetryWaits()
            // A fixed HTTP status suffices: test the complete five-attempt failure path.
            let stub = CloudTestStub(rawResponse: true, statusCode: status, sendLog: log,
                retrySleep: { await waits.append($0) }) { _ in _ = counter.next(); return "test-key" }
            defer { stub.close() }
            do { _ = try await stub.send(ChatRequest(messages: [], purpose: "导入整理·按对方")); XCTFail() }
            catch { XCTAssertEqual(error as? DeepSeekError, .http(status)) }
            XCTAssertEqual(counter.count, 5)
            let delays = await waits.values
            XCTAssertEqual(delays, [1, 3, 8, 20])
            let item = try XCTUnwrap(log.items.first)
            XCTAssertEqual(log.items.count, 1)
            XCTAssertEqual(item.attempts?.map(\.number), [1, 2, 3, 4, 5])
            XCTAssertEqual(item.attempts?.compactMap { $0.response?.httpStatus }, Array(repeating: status, count: 5))
            XCTAssertNil(item.attempts?.last?.retryDelay)
            XCTAssertFalse(String(decoding: try JSONEncoder().encode(item), as: UTF8.self).contains("test-key"))
            let steps = SendLogPresentation.trace(in: SendLogGroup(items: [item]))
            XCTAssertEqual(steps.filter { $0.title.hasPrefix("没成功") }.count, 5)
            XCTAssertTrue(steps.contains { $0.title == "没成功 · 第 5 次" })
        }
    }
    func testRequestAndAccountErrorsNeverRetry() async throws {
        for status in [400, 401, 402, 403, 404, 422] {
            let counter = RetryCounter(), log = SendLog()
            let stub = CloudTestStub(rawResponse: true, statusCode: status, sendLog: log,
                retrySleep: { _ in XCTFail("must not sleep") }) { _ in _ = counter.next(); return "" }
            defer { stub.close() }
            do { _ = try await stub.send(ChatRequest(messages: [], purpose: "导入整理")); XCTFail() }
            catch { XCTAssertEqual(error as? DeepSeekError, .http(status)) }
            XCTAssertEqual(counter.count, 1)
            XCTAssertEqual(log.items.first?.attempts?.count, 1)
            XCTAssertEqual(ImportOrganizer.abortsRun(DeepSeekError.http(status)), [401, 402].contains(status))
        }
    }
    func testNetworkInterruptionRetriesThenSucceedsAndRetainsBothAttempts() async throws {
        for code in [URLError.timedOut, .networkConnectionLost] {
            let counter = RetryCounter(), log = SendLog()
            let stub = CloudTestStub(sendLog: log) { _ in
                if counter.next() == 1 { throw URLError(code) }
                return "恢复了"
            }
            defer { stub.close() }
            let reply = try await stub.send(ChatRequest(messages: [], purpose: "导入整理"))
            XCTAssertEqual(reply.content, "恢复了")
            XCTAssertEqual(counter.count, 2)
            let attempts = try XCTUnwrap(log.items.first?.attempts)
            XCTAssertEqual(attempts.count, 2)
            XCTAssertNotNil(attempts[0].response?.errorDescription)
            XCTAssertEqual(attempts[1].response?.httpStatus, 200)
            XCTAssertNil(attempts[1].response?.errorDescription)
            XCTAssertFalse(log.groups[0].hasFailure, "Recovered attempts are history, not a final failure")
        }
    }
    func testRetryAfterReachesWaitAndCancellationInterruptsBackoffImmediately() async throws {
        let waiting = expectation(description: "entered backoff"), log = SendLog(), counter = RetryCounter()
        let stub = CloudTestStub(rawResponse: true, statusCode: 503, sendLog: log, headers: ["Retry-After": "900"],
            retrySleep: { delay in
                XCTAssertEqual(delay, 30)
                waiting.fulfill()
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }) { _ in _ = counter.next(); return "" }
        defer { stub.close() }
        let run = Task { try await stub.send(ChatRequest(messages: [], purpose: "导入整理")) }
        await fulfillment(of: [waiting], timeout: 2)
        XCTAssertNil(log.items.first?.response)
        XCTAssertTrue(SendLogPresentation.trace(in: log.groups[0]).contains { $0.title == "重试等待中" })
        let start = Date(); run.cancel()
        do { _ = try await run.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.5)
        XCTAssertEqual(counter.count, 1)
        XCTAssertEqual(log.items.first?.response?.errorDescription, "请求已取消。")
        let group = try XCTUnwrap(log.groups.first)
        let step = try XCTUnwrap(SendLogPresentation.trace(in: group).last)
        let source = try XCTUnwrap(SendLogRawPresentation.sources(in: group).first { $0.target == step.target })
        XCTAssertEqual(SendLogRawPresentation.prepare(source).sections.last?.body, .text("请求已取消。"))
    }
    func testAdaptiveConcurrencyReducesBothPhasesAndRecoversAfterThreeSuccessesPerStep() async throws {
        let controller = ImportRequestController()
        var party = await controller.limit(ceiling: 4), individual = await controller.limit(ceiling: 2)
        XCTAssertEqual(party, 4); XCTAssertEqual(individual, 2)
        for status in [429, 503] {
            await controller.congested(status: status)
            party = await controller.limit(ceiling: 4); individual = await controller.limit(ceiling: 2)
            XCTAssertEqual(party, 1); XCTAssertEqual(individual, 1)
            for capacity in 2...4 {
                await controller.succeeded(); await controller.succeeded()
                party = await controller.limit(ceiling: 4)
                XCTAssertEqual(party, capacity - 1)
                await controller.succeeded()
                party = await controller.limit(ceiling: 4); individual = await controller.limit(ceiling: 2)
                XCTAssertEqual(party, capacity); XCTAssertEqual(individual, min(2, capacity))
            }
        }
        await controller.congested(status: 500)
        party = await controller.limit(ceiling: 4); XCTAssertEqual(party, 4)
    }
    func testAdaptiveGateDoesNotAdmitNewAttemptsUntilInFlightWorkDrainsAndCancelsWaiters() async throws {
        let controller = ImportRequestController()
        for _ in 0..<4 { try await controller.acquire(ceiling: 4) }
        await controller.congested(status: 503)
        let admitted = RetryCounter()
        let waiting = Task { try await controller.acquire(ceiling: 4); _ = admitted.next(); await controller.release() }
        for _ in 0..<3 { await controller.release() }
        try await Task.sleep(nanoseconds: 10_000_000)
        XCTAssertEqual(admitted.count, 0)
        let start = Date(); waiting.cancel()
        do { try await waiting.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.5)
        await controller.release()
        try await controller.acquire(ceiling: 2); await controller.release()
        XCTAssertEqual(admitted.count, 0)
    }
}

extension DeepSeekCloudTests {
    func testHTTP503RetrySuccessUsesReducedGateAndDoesNotHoldItDuringBackoff() async throws {
        let controller = ImportRequestController(), counter = RetryCounter(), log = SendLog()
        let stub = CloudTestStub(sendLog: log, responseStatus: { counter.count == 1 ? 503 : 200 }, retrySleep: { _ in
            let limit = await controller.limit(ceiling: 4)
            XCTAssertEqual(limit, 1, "first 503 reduces capacity before backoff")
            try await controller.acquire(ceiling: 2)
            await controller.release()
        }) { _ in _ = counter.next(); return "恢复了" }
        defer { stub.close() }
        let response = try await ImportRequestScope.$current.withValue(.init(controller: controller, ceiling: 4)) {
            try await stub.send(ChatRequest(messages: [], purpose: "导入整理"))
        }
        XCTAssertEqual(response.content, "恢复了")
        XCTAssertEqual(log.items.count, 1)
        XCTAssertEqual(log.totalCount, 2)
        XCTAssertEqual(log.groups.first?.requestCount, 2)
        XCTAssertEqual(log.totalSentByteSize, (log.items.first?.byteSize ?? 0) * 2)
        XCTAssertEqual(log.items.first?.attempts?.compactMap { $0.response?.httpStatus }, [503, 200])
        XCTAssertFalse(log.groups[0].hasFailure)
    }
}

extension DeepSeekCloudTests {
    private func catalogJSON(_ names: [String]) -> String {
        String(decoding: try! JSONSerialization.data(withJSONObject: ["data": names.map { ["id": $0] }]), as: UTF8.self)
    }
    func testOrganizationPrefersExactFlashNameFromCatalogAndCachesAcrossRequests() async throws {
        let catalogs = RetryCounter(), log = SendLog()
        let catalog = catalogJSON(["deepseek-chat", "vendor/deepseek-v4-FLASH", "deepseek-flash"])
        let stub = CloudTestStub(sendLog: log, model: "deepseek-chat", catalogReply: { _ in _ = catalogs.next(); return catalog }) { request in
            XCTAssertEqual(try CloudTestStub.payload(in: request)["model"] as? String, "vendor/deepseek-v4-FLASH")
            return "ok"
        }
        defer { stub.close() }
        for _ in 0..<3 { _ = try await stub.send(ChatRequest(messages: [], purpose: "导入整理")) }
        XCTAssertEqual(catalogs.count, 1)
        XCTAssertEqual(log.items.map(\.model), Array(repeating: "vendor/deepseek-v4-FLASH", count: 3))
        XCTAssertEqual(stub.backend.client.configuration.model, "deepseek-chat")
    }
    func testOrganizationWithoutFlashUsesSelectedNameEvenIfItIsALegacyNameInCatalog() async throws {
        let catalog = catalogJSON(["deepseek-reasoner", "other"])
        let stub = CloudTestStub(model: "deepseek-reasoner", catalogReply: { _ in catalog }) { request in
            XCTAssertEqual(try CloudTestStub.payload(in: request)["model"] as? String, "deepseek-reasoner")
            return "ok"
        }
        defer { stub.close() }
        _ = try await stub.send(ChatRequest(messages: [], purpose: "导入整理·按对方"))
    }
    func testOrganizationCatalogFailureUsesSelectedRawNameAndCachesFailure() async throws {
        for offline in [false, true] {
            let catalogs = RetryCounter()
            let stub = CloudTestStub(model: "deepseek-chat", catalogReply: { _ in
                _ = catalogs.next()
                if offline { throw URLError(.notConnectedToInternet) }
                return "{}"
            }, catalogStatus: 503) { request in
                XCTAssertEqual(try CloudTestStub.payload(in: request)["model"] as? String, "deepseek-chat")
                return "ok"
            }
            defer { stub.close() }
            for _ in 0..<2 { _ = try await stub.send(ChatRequest(messages: [], purpose: "导入整理")) }
            XCTAssertEqual(catalogs.count, 1)
        }
    }
    func testCanonicalModelOnlyMapsMissingSavedNamesToVerifiedCatalogEntries() {
        let names = ["deepseek-chat", "deepseek-v4-flash", "deepseek-flash", "deepseek-reasoner", "deepseek-v4-pro", "private-model"]
        for name in names {
            XCTAssertEqual(DeepSeekConfiguration.canonicalModel(name), name)
            XCTAssertEqual(DeepSeekConfiguration.canonicalModel(name, availableModels: names), name)
        }
        XCTAssertEqual(DeepSeekConfiguration.canonicalModel("deepseek-chat", availableModels: ["deepseek-v4-flash"]), "deepseek-v4-flash")
        XCTAssertEqual(DeepSeekConfiguration.canonicalModel("deepseek-flash", availableModels: ["deepseek-chat"]), "deepseek-chat")
        XCTAssertEqual(DeepSeekConfiguration.canonicalModel("deepseek-reasoner", availableModels: ["deepseek-v4-pro"]), "deepseek-v4-pro")
        XCTAssertEqual(DeepSeekConfiguration.canonicalModel("deepseek-chat", availableModels: ["unrelated"]), "deepseek-chat")
    }
    func testFirst503ImmediatelyFallsBackToSelectedModelAndSticksForBothPhasesAndLaterClients() async throws {
        let posts = RetryCounter(), catalogs = RetryCounter(), log = SendLog(), controller = ImportRequestController()
        let catalog = catalogJSON(["deepseek-chat", "deepseek-v4-flash"])
        let stub = CloudTestStub(sendLog: log, model: "deepseek-chat", responseStatus: { posts.count == 1 ? 503 : 200 },
            catalogReply: { _ in _ = catalogs.next(); return catalog }, retrySleep: { _ in XCTFail("fallback must be immediate") }) { request in
            let number = posts.next(), model = try CloudTestStub.payload(in: request)["model"] as? String
            XCTAssertEqual(model, number == 1 ? "deepseek-v4-flash" : "deepseek-chat")
            return "ok"
        }
        defer { stub.close() }
        for purpose in ["导入整理·按对方", "导入整理"] {
            _ = try await ImportRequestScope.$current.withValue(.init(controller: controller, ceiling: 4)) {
                try await stub.send(ChatRequest(messages: [], purpose: purpose))
            }
        }
        XCTAssertEqual(posts.count, 3); XCTAssertEqual(catalogs.count, 1)
        let item = try XCTUnwrap(log.items.last)
        XCTAssertEqual(item.attempts?.compactMap(\.model), ["deepseek-v4-flash", "deepseek-chat"])
        XCTAssertEqual(item.attempts?.compactMap { $0.response?.httpStatus }, [503, 200])
        let retryBody = try XCTUnwrap(item.attempts?.last?.requestText)
        XCTAssertEqual(try JSONValue.parse(retryBody)["model"], .string("deepseek-chat"))
        XCTAssertTrue(SendLogRawPresentation.copyText(in: log.groups.last!).contains("deepseek-chat"))
        XCTAssertFalse(log.groups.last!.hasFailure)
    }
    func testLaterModelRelated400404503FallsBackOnceAndRetainsSelectedModel() async throws {
        for status in [400, 404, 503] {
            let posts = RetryCounter(), controller = ImportRequestController()
            let catalog = catalogJSON(["selected", "real-flash"])
            let stub = CloudTestStub(rawResponse: true, model: "selected", responseStatus: { posts.count == 2 ? status : 200 },
                catalogReply: { _ in catalog }, retrySleep: { _ in XCTFail("model fallback must not back off") }) { request in
                let number = posts.next()
                XCTAssertEqual(try CloudTestStub.payload(in: request)["model"] as? String, number <= 2 ? "real-flash" : "selected")
                return number == 2 ? #"{"error":{"code":"model_not_found"}}"# : #"{"choices":[{"message":{"content":"ok"}}]}"#
            }
            defer { stub.close() }
            for _ in 0..<3 {
                _ = try await ImportRequestScope.$current.withValue(.init(controller: controller, ceiling: 4)) {
                    try await stub.send(ChatRequest(messages: [], purpose: "导入整理"))
                }
            }
            XCTAssertEqual(posts.count, 4)
        }
    }
    func testFallbackIsBoundedAndOrdinaryRetryBudgetRemainsFour() async throws {
        let posts = RetryCounter(), waits = RetryWaits(), log = SendLog()
        let catalog = catalogJSON(["selected", "real-flash"])
        let stub = CloudTestStub(rawResponse: true, statusCode: 503, sendLog: log, model: "selected",
            catalogReply: { _ in catalog }, retrySleep: { await waits.append($0) }) { _ in _ = posts.next(); return "" }
        defer { stub.close() }
        do { _ = try await stub.send(ChatRequest(messages: [], purpose: "导入整理")); XCTFail() }
        catch { XCTAssertEqual(error as? DeepSeekError, .http(503)) }
        XCTAssertEqual(posts.count, 6)
        XCTAssertEqual(log.items.first?.attempts?.compactMap(\.model), ["real-flash"] + Array(repeating: "selected", count: 5))
        let delays = await waits.values; XCTAssertEqual(delays, [1, 3, 8, 20])
    }
    func testCatalogCoalescesLookupsAndSeparatesCredentialsAndEndpoints() async throws {
        let catalog = DeepSeekModelCatalog(), counter = RetryCounter()
        let config = DeepSeekConfiguration(apiKey: "fake-one", baseURL: URL(string: "https://catalog.yubai.test")!)
        try await withThrowingTaskGroup(of: [String]?.self) { group in
            for _ in 0..<4 { group.addTask {
                try await catalog.models(for: config) {
                    _ = counter.next(); try await Task.sleep(nanoseconds: 10_000_000); return ["real-flash"]
                }
            } }
            for try await names in group { XCTAssertEqual(names, ["real-flash"]) }
        }
        XCTAssertEqual(counter.count, 1)
        for variant in [DeepSeekConfiguration(apiKey: "fake-two", baseURL: config.baseURL),
                        DeepSeekConfiguration(apiKey: config.apiKey, baseURL: URL(string: "https://other.yubai.test")!)] {
            _ = try await catalog.models(for: variant) { _ = counter.next(); return ["other"] }
        }
        XCTAssertEqual(counter.count, 3)
    }
}

extension DeepSeekCloudTests {
    func testModelCatalogLookupCanBeCancelledWithoutWaitingForItsTimeout() async throws {
        let catalog = DeepSeekModelCatalog(), started = expectation(description: "catalog lookup started")
        let configuration = DeepSeekConfiguration(apiKey: "fake", baseURL: URL(string: "https://cancel-catalog.yubai.test")!)
        let run = Task {
            try await catalog.models(for: configuration) {
                started.fulfill()
                try await Task.sleep(nanoseconds: 30_000_000_000)
                return ["real-flash"]
            }
        }
        await fulfillment(of: [started], timeout: 2)
        let start = Date(); run.cancel()
        do { _ = try await run.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.5)
    }
    func testFlashSelectionDoesNotFallBackOnAccountErrors() async throws {
        let catalog = catalogJSON(["selected", "real-flash"])
        for status in [401, 402, 422] {
            let posts = RetryCounter()
            let stub = CloudTestStub(rawResponse: true, statusCode: status, model: "selected", catalogReply: { _ in catalog },
                retrySleep: { _ in XCTFail("account/request errors must not sleep") }) { request in
                _ = posts.next()
                XCTAssertEqual(try CloudTestStub.payload(in: request)["model"] as? String, "real-flash")
                return ""
            }
            defer { stub.close() }
            do { _ = try await stub.send(ChatRequest(messages: [], purpose: "导入整理")); XCTFail() }
            catch { XCTAssertEqual(error as? DeepSeekError, .http(status)) }
            XCTAssertEqual(posts.count, 1)
        }
    }
}
