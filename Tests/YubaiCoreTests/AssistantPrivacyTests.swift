import XCTest
@testable import YubaiCore

final class MemoryAPIKeyStorage: APIKeyStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var value: String?
    func read() throws -> String? { lock.lock(); defer { lock.unlock() }; return value }
    func write(_ key: String) throws { lock.lock(); defer { lock.unlock() }; value = key }
    func delete() throws { lock.lock(); defer { lock.unlock() }; value = nil }
}

final class AssistantPrivacyTests: XCTestCase {
    #if os(Linux)
    func testLinuxAPIKeyStorageSharesProcessMemoryAndSupportsReplacementAndDeletion() throws {
        let first = APIKeyStore(); let second = APIKeyStore()
        try first.delete(); defer { try? first.delete() }
        XCTAssertNil(second.configuration(environment: [:]))
        XCTAssertThrowsError(try first.save(" \n"))
        try first.save("  process-only-key \n")
        XCTAssertEqual(second.configuration(environment: [:])?.apiKey, "process-only-key")
        try second.save("replacement")
        XCTAssertEqual(first.configuration(environment: ["DEEPSEEK_API_KEY": "env-key"])?.apiKey, "replacement")
        try first.delete(); try second.delete()
        XCTAssertFalse(second.hasKeychainKey)
        XCTAssertEqual(first.configuration(environment: ["DEEPSEEK_API_KEY": "env-key"])?.apiKey, "env-key")
    }
    #endif
    func testChineseTransferNamesAndMerchants() {
        let ledger = AssistantFixtures.context().ledger
        let redactor = Redactor(ledger: ledger)
        let cases = ["微信转账-张三", "转账给李四", "红包-王五", "支付宝转账 赵六"]
        var aliases = Set<String>()
        for source in cases {
            let result = redactor.text(source)
            XCTAssertTrue(result.contains("联系人")); XCTAssertNotEqual(result, source)
            XCTAssertEqual(redactor.text(source), result)
            XCTAssertEqual(Redactor(ledger: ledger).text(source), result)
            aliases.insert(result.components(separatedBy: "联系人").last!)
        }
        XCTAssertEqual(aliases.count, 4)
        for merchant in ["瑞幸咖啡", "美团外卖", "微信转账-瑞幸咖啡", "支付宝转账 美团外卖", "转账给王记咖啡"] {
            XCTAssertEqual(redactor.text(merchant), merchant)
        }
        XCTAssertEqual(redactor.text("卡号6222021234567890123 订单12345678"), "卡号****0123 订单****5678")
    }
    func testRedactorDropsSensitiveFieldsAndPreservesEvidenceAndMoney() throws {
        let ctx = AssistantFixtures.context(); let id = ctx.ledger.entries[0].id.uuidString
        let output = ctx.redactor.value(.object(["externalID": .string("never"), "source_identity": .string("never"),
            "fingerprint": .string("never"), "attachments": .array([.string("raw")]), "raw_file": .string("raw"),
            "entry_ids": .strings([id]), "id": .string(id), "amount": .money(123456789),
            "title": .string("订单12345678"), "note": .string("source_PRIVATE external_PRIVATE fingerprint_PRIVATE")]))
        let text = try output.jsonText()
        for forbidden in ["externalID", "source_identity", "fingerprint", "attachments", "raw_file", "PRIVATE"] { XCTAssertFalse(text.contains(forbidden)) }
        XCTAssertEqual(output["entry_ids"], .strings([id])); XCTAssertEqual(output["id"], .string(id))
        XCTAssertEqual(output["amount"], .money(123456789)); XCTAssertEqual(output["title"], .string("订单****5678"))
    }
    func testAgentRedactsUserAndToolTextEvenWithInjectedTransport() async throws {
        let ctx = AssistantFixtures.context()
        let script = ScriptedChatTransport([
            ChatMessage(role: .assistant, toolCalls: [ChatToolCall(id: "q", name: "query_entries")]),
            ChatMessage(role: .assistant, content: "已查看。")])
        _ = try await AssistantAgent(transport: script, context: ctx).run(system: "本地数据", messages: [ChatMessage(role: .user, content: "微信转账-张三 12345678 external_PRIVATE")], tools: ReadOnlyTool.all)
        let requests = await script.recorded()
        for request in requests {
            let text = request.messages.compactMap(\.content).joined()
            XCTAssertFalse(text.contains("张三")); XCTAssertFalse(text.contains("12345678")); XCTAssertFalse(text.contains("external_PRIVATE"))
        }
    }
    func testAPIKeyConfigurationPrecedenceReplacementAndDeletion() throws {
        let memory = MemoryAPIKeyStorage(); let store = APIKeyStore(storage: memory)
        XCTAssertNil(store.configuration(environment: [:]))
        XCTAssertEqual(store.configuration(environment: ["DEEPSEEK_API_KEY": "dev-key"])?.apiKey, "dev-key")
        XCTAssertThrowsError(try store.save("  "))
        try store.save("  private-key \n")
        XCTAssertTrue(store.isConfigured)
        let config = store.configuration(environment: ["DEEPSEEK_API_KEY": "ignored", "DEEPSEEK_MODEL": "custom-model"])
        XCTAssertEqual(config?.apiKey, "private-key"); XCTAssertEqual(config?.model, "custom-model")
        try store.save("replacement"); XCTAssertEqual(try memory.read(), "replacement")
        XCTAssertNotNil(CloudBackend.configured(enabled: true, keyStore: store, environment: [:]))
        XCTAssertNil(CloudBackend.configured(enabled: false, keyStore: store, environment: [:]))
        try store.delete(); XCTAssertNil(try memory.read()); XCTAssertNil(store.configuration(environment: [:]))
    }
    func testSendLogRingBufferAndKeyHygiene() {
        let log = SendLog()
        for index in 0..<55 {
            log.record(purpose: "测试\(index)", model: "test-model", body: Data(("secret-key" + String(repeating: "余", count: 2000)).utf8), apiKey: "secret-key")
        }
        XCTAssertEqual(log.items.count, 50); XCTAssertEqual(log.items.first?.purpose, "测试54"); XCTAssertEqual(log.items.last?.purpose, "测试5")
        XCTAssertEqual(log.totalCount, 55)
        for item in log.items {
            XCTAssertLessThanOrEqual(item.requestText.utf8.count, 4099)
            XCTAssertGreaterThan(item.byteSize, 4096); XCTAssertFalse(item.requestText.contains("secret-key"))
        }
    }
    func testSocialNamesShareTransferAliasesAndMerchantsRemainIntact() {
        let redactor = Redactor()
        let name = redactor.text("转账给张三").replacingOccurrences(of: "转账给", with: "")
        for phrase in ["和张三合租，房租我出六成", "和张三吃饭", "跟张三聚餐", "给张三买书", "请张三一起", "与张三的约定", "陪张三，散步", "和张三。", "跟张三 今天", "给张三"] {
            XCTAssertTrue(redactor.text(phrase).contains(name), phrase)
            XCTAssertFalse(redactor.text(phrase).contains("张三"), phrase)
        }
        XCTAssertFalse(redactor.text("和王小明吃饭").contains("王小明"))
        for phrase in ["给王者荣耀充值", "给王者荣耀买皮肤", "和王记咖啡", "和周末一起", "给李宁公司买东西", "请张家餐厅聚餐", "和陌生人吃饭"] {
            XCTAssertEqual(redactor.text(phrase), phrase)
        }
    }

}
