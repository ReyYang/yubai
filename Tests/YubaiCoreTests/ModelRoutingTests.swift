import XCTest
@testable import YubaiCore

/// A scripted model: records what it was sent, answers or fails on cue.
private final class FakeProvider: LanguageModelProvider, @unchecked Sendable {
    let id: String
    let capabilities: ModelCapabilities
    var state: ModelAvailability
    var failure: Error?
    private(set) var received: [ChatRequest] = []
    init(_ id: String, capabilities: ModelCapabilities = DeepSeekProvider.defaultCapabilities,
         state: ModelAvailability = .available, failure: Error? = nil) {
        self.id = id; self.capabilities = capabilities; self.state = state; self.failure = failure
    }
    func availability() async -> ModelAvailability { state }
    func send(_ request: ChatRequest) async throws -> ChatMessage {
        received.append(request)
        if let failure { throw failure }
        return ChatMessage(role: .assistant, content: id)
    }
}

private let onDevice = ModelCapabilities(contextTokens: 4_096, toolCalling: false, structuredOutput: true, imageInput: false, leavesDevice: false)

final class ModelRoutingTests: XCTestCase {
    private func ask(_ text: String = "这周吃饭花了多少", tools: [ChatToolDefinition] = [], maxTokens: Int = 400) -> ChatRequest {
        ChatRequest(messages: [ChatMessage(role: .user, content: text)], tools: tools, maxTokens: maxTokens)
    }
    private let tool = ChatToolDefinition(name: "query_entries", description: "查账", parameters: .object([:]))

    func testPicksFirstAvailableProviderThatMeetsTheRequest() async throws {
        let local = FakeProvider("local", capabilities: onDevice), cloud = FakeProvider("cloud")
        let router = ModelRouter(providers: [local, cloud])
        let short = try await router.send(ask())
        XCTAssertEqual(short.content, "local")
        let withTools = try await router.send(ask(tools: [tool]))
        XCTAssertEqual(withTools.content, "cloud", "tool calls need a provider that declares them")
        let long = try await router.send(ask(String(repeating: "账", count: 20_000)))
        XCTAssertEqual(long.content, "cloud", "context larger than the small model goes to the cloud")
    }

    func testFallsThroughToNextProviderOnFailure() async throws {
        let local = FakeProvider("local", capabilities: onDevice, failure: YubaiError.invalid("拒答"))
        let cloud = FakeProvider("cloud")
        let reply = try await ModelRouter(providers: [local, cloud]).send(ask())
        XCTAssertEqual(reply.content, "cloud")
        XCTAssertEqual(local.received.count, 1)
    }

    func testRethrowsLastErrorWhenEveryProviderFails() async {
        let cloud = FakeProvider("cloud", failure: YubaiError.invalid("超时"))
        do { _ = try await ModelRouter(providers: [cloud]).send(ask()); XCTFail("expected failure") }
        catch { XCTAssertEqual(error as? YubaiError, .invalid("超时")) }
    }

    func testNoAvailableModelReportsReasonsInProviderOrder() async {
        let local = FakeProvider("local", capabilities: onDevice, state: .unavailable(.unsupportedSystem))
        let cloud = FakeProvider("cloud", state: .unavailable(.cloudOff))
        let router = ModelRouter(providers: [local, cloud])
        do { _ = try await router.send(ask()); XCTFail("expected no model") }
        catch { XCTAssertEqual(error as? ModelRouterError, .noModel([.unsupportedSystem, .cloudOff])) }
        let state = await router.availability()
        XCTAssertEqual(state, .unavailable(.unsupportedSystem))
        XCTAssertTrue(local.received.isEmpty && cloud.received.isEmpty)
    }

    func testCancellationDoesNotFallThrough() async {
        let first = FakeProvider("first", failure: CancellationError()), second = FakeProvider("second")
        do { _ = try await ModelRouter(providers: [first, second]).send(ask()); XCTFail("expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertTrue(second.received.isEmpty)
    }

    func testDeepSeekProviderFollowsCloudSwitchAndKey() async {
        var preferences = Preferences()
        let off = DeepSeekProvider.configured(preferences: preferences, feature: .answers, environment: [:])
        let offState = await off.availability()
        XCTAssertEqual(offState, .unavailable(.cloudOff))
        preferences.cloudAIEnabled = true
        let noKey = DeepSeekProvider.configured(preferences: preferences, feature: .answers, keyStore: APIKeyStore(storage: MemoryAPIKeyStorage()), environment: [:])
        let noKeyState = await noKey.availability()
        XCTAssertEqual(noKeyState, .unavailable(.missingKey))
        do { _ = try await noKey.send(ask()); XCTFail("expected no model") }
        catch { XCTAssertEqual(error as? ModelRouterError, .noModel([.missingKey])) }
    }

    func testRouterAppliesSharePolicyOnlyToProvidersThatLeaveThePhone() async throws {
        var ledger = LedgerFixture.ledger()
        ledger.accounts[0].name = "招行储蓄"
        let policy = CloudSharePolicy(settings: CloudShareSettings(amount: false, category: true, note: false, account: false), ledger: ledger)
        let local = FakeProvider("local", capabilities: onDevice), cloud = FakeProvider("cloud")
        _ = try await ModelRouter(providers: [local, cloud], sharePolicy: policy).send(ask("招行储蓄 ¥1,299.00"))
        XCTAssertEqual(local.received.first?.messages.first?.content, "招行储蓄 ¥1,299.00")
        _ = try await ModelRouter(providers: [cloud], sharePolicy: policy).send(ask("招行储蓄 ¥1,299.00"))
        XCTAssertEqual(cloud.received.first?.messages.first?.content, "账户1 大额")
    }

    func testEstimateCountsToolsAndReplyBudget() {
        let plain = ModelRequirements.estimate(for: ask("一二三四", maxTokens: 100))
        XCTAssertEqual(plain, ModelRequirements(contextTokens: 102))
        XCTAssertTrue(ModelRequirements.estimate(for: ask(tools: [tool])).toolCalling)
        var structured = ask(); structured.responseFormat = .object(["type": .string("json_object")])
        XCTAssertTrue(ModelRequirements.estimate(for: structured).structuredOutput)
    }
}

final class CloudSharePolicyTests: XCTestCase {
    private func policy(_ settings: CloudShareSettings, ledger: Ledger? = nil) -> CloudSharePolicy { CloudSharePolicy(settings: settings, ledger: ledger) }

    func testDefaultsShareAmountAndCategoryButNotNoteOrAccount() throws {
        XCTAssertEqual(CloudShareSettings.defaults, CloudShareSettings(amount: true, category: true, note: false, account: false))
        var preferences = Preferences()
        XCTAssertEqual(preferences.cloudShareSettings, .defaults)
        XCTAssertNil(preferences.cloudShare, "defaults are not written to the ledger")
        preferences.cloudShareSettings.note = true
        let decoded = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(preferences))
        XCTAssertTrue(decoded.cloudShareSettings.note)
        preferences.cloudShareSettings = .defaults
        XCTAssertNil(preferences.cloudShare)
    }

    func testSettingsDecodeIgnoresUnknownAndFillsMissingKeys() throws {
        let decoded = try JSONDecoder().decode(CloudShareSettings.self, from: Data(#"{"note":true,"location":false}"#.utf8))
        XCTAssertEqual(decoded, CloudShareSettings(amount: true, category: true, note: true, account: false))
    }

    func testOlderPreferencesWithoutShareKeyKeepDefaults() throws {
        var old = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Preferences())) as! [String: Any]
        old.removeValue(forKey: "cloudShare")
        let decoded = try JSONDecoder().decode(Preferences.self, from: JSONSerialization.data(withJSONObject: old))
        XCTAssertEqual(decoded.cloudShareSettings, .defaults)
    }

    func testJSONToolResultsDropOrMaskSwitchedOffFields() throws {
        let p = policy(CloudShareSettings(amount: false, category: false, note: false, account: false))
        let id = UUID().uuidString
        let input = JSONValue.object([
            "id": .string(id), "title": .string("午饭"), "note": .string("和同事"),
            "category": .string("吃饭"), "subcategories": .array([.string("午餐")]),
            "amount": .money(3_250), "account_name": .string("没有这个账户")
        ])
        let out = p.value(input)
        XCTAssertNil(out["note"])
        XCTAssertEqual(out["id"], .string(id))
        XCTAssertEqual(out["amount"], .object(["band": .string("小额")]))
        XCTAssertEqual(out["account_name"], .string("账户"))
        XCTAssertFalse(try out.jsonText().contains("吃饭"))
        XCTAssertFalse(try out.jsonText().contains("午餐"))
    }

    func testEverythingSharedLeavesRequestUntouched() {
        let request = ChatRequest(messages: [ChatMessage(role: .user, content: #"{"note":"x","amount":{"text":"1.00","cents":100}}"#)])
        let all = policy(CloudShareSettings(amount: true, category: true, note: true, account: true))
        XCTAssertEqual(all.apply(to: request).messages, request.messages)
    }

    func testFreeTextAmountsBecomeBandsButDatesAndCountsStay() {
        let p = policy(CloudShareSettings(amount: false, category: true, note: true, account: true))
        XCTAssertEqual(p.text("1299 元的耳机，11月22日打车 36.50，买了 3 次"), "大额的耳机，11月22日打车 小额，买了 3 次")
        XCTAssertEqual(p.text("2026-11-26 还剩 ¥6,268.40"), "2026-11-26 还剩 大额")
        XCTAssertEqual(CloudSharePolicy.band(cents: -150_000), "大额")
    }

    func testAccountNamesAndNotesAreReplacedInFreeText() {
        var ledger = LedgerFixture.ledger()
        ledger.accounts[0].name = "招行储蓄"
        var entry = Entry(amount: 100, accountID: ledger.accounts[0].id, title: "午饭")
        entry.note = "给小王带的"
        ledger.entries = [entry]
        let p = policy(.defaults, ledger: ledger)
        XCTAssertEqual(p.text("招行储蓄 付了午饭，备注 给小王带的"), "账户1 付了午饭，备注 [备注]")
    }

    func testToolCallArgumentsAreNotRewritten() {
        let call = ChatToolCall(id: "1", name: "propose_entry", arguments: #"{"amount":"36.50","note":"x"}"#)
        let request = ChatRequest(messages: [ChatMessage(role: .assistant, toolCalls: [call])])
        let out = policy(CloudShareSettings(amount: false, category: false, note: false, account: false)).apply(to: request)
        XCTAssertEqual(out.messages.first?.toolCalls, [call])
    }
}

final class AIResultEnvelopeTests: XCTestCase {
    private struct Card: Codable, Equatable, Sendable { var title: String; var count: Int? }

    func testMissingVersionReadsAsOneAndUnknownFieldsAreIgnored() throws {
        let data = Data(#"{"payload":{"title":"冲抵","count":2,"future":"x"}}"#.utf8)
        let envelope = try XCTUnwrap(AIResultEnvelope<Card>.decodeIfSupported(data, upTo: 1))
        XCTAssertEqual(envelope.schemaVersion, 1)
        XCTAssertEqual(envelope.payload, Card(title: "冲抵", count: 2))
    }

    func testNewerSchemaIsSkippedNotFatal() throws {
        let newer = try JSONEncoder().encode(AIResultEnvelope(schemaVersion: 3, payload: Card(title: "批量", count: nil)))
        XCTAssertNil(AIResultEnvelope<Card>.decodeIfSupported(newer, upTo: 2))
        XCTAssertNil(AIResultEnvelope<Card>.decodeIfSupported(Data("not json".utf8), upTo: 2))
        XCTAssertEqual(AIResultEnvelope<Card>.decodeIfSupported(newer, upTo: 3)?.payload.title, "批量")
    }
}
