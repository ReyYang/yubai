import XCTest
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import YubaiCore

final class StoragePolicyTests: XCTestCase {
    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("yubai-policy-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }
    private func ledger(_ name: String) -> Ledger {
        var ledger = Ledger(); ledger.accounts = [Account(name: name)]; return ledger
    }
    private func write(_ ledger: Ledger, at root: URL, seconds: Int, reason: String, padding: Int = 0) throws -> URL {
        let history = root.appendingPathComponent("Recovery")
        try FileManager.default.createDirectory(at: history, withIntermediateDirectories: true)
        let file = history.appendingPathComponent("\(seconds * 1000)-legacy-\(reason).json")
        try (LedgerCodec.encodeMetadata(ledger) + Data(repeating: 32, count: padding)).write(to: file)
        return file
    }
    func testAutomaticWindowsKeepFirstAndDoNotSlideWithRetriesOrRelaunch() throws {
        let root = try directory(), initial = ledger("初始")
        // Reopening between operations also proves the policy is persisted in filenames.
        for (seconds, reason) in [(1000, "导入整理"), (1003, "整理重试"), (1599, "重试整理"), (1600, "导入整理"), (1601, "导入整理")] {
            let repository = LedgerRepository(directory: root, recoveryDate: { Date(timeIntervalSince1970: Double(seconds)) })
            try repository.preserveRecovery(initial, reason: reason)
        }
        let repository = LedgerRepository(directory: root)
        XCTAssertEqual(try repository.recoveries().map { Int($0.date.timeIntervalSince1970) }, [1600, 1000])
        XCTAssertEqual(try repository.readRecovery(XCTUnwrap(repository.recoveries().last)), initial)
    }
    func testAutomaticCategoriesMergeIndependentlyAndManualOperationsAlwaysPreserve() throws {
        let root = try directory()
        let repository = LedgerRepository(directory: root, recoveryDate: { Date(timeIntervalSince1970: 1000) })
        let initial = ledger("初始")
        for reason in ["导入整理", "回答整理问题", "整理", "批量记账"] {
            for _ in 0..<3 { try repository.preserveRecovery(initial, reason: reason) }
        }
        XCTAssertEqual(try repository.recoveries().count, 4)
        try repository.clearRecoveryHistory()
        for reason in ["导入账单", "抹掉前", "恢复前", "整批撤销"] {
            for _ in 0..<2 { try repository.preserveRecovery(initial, reason: reason) }
        }
        XCTAssertEqual(try repository.recoveries().count, 8)
    }
    func testStartupCoalescesLegacyWindowsButProtectsNewestAndReadableFallback() throws {
        let root = try directory(), repository = LedgerRepository(directory: root)
        try repository.save(ledger("当前"))
        for second in [1000, 1003, 1100, 1600, 1602] {
            _ = try write(ledger("\(second)"), at: root, seconds: second, reason: "导入整理")
        }
        _ = try write(ledger("手动"), at: root, seconds: 1603, reason: "导入账单")
        let newest = try XCTUnwrap(repository.recoveries().first)
        try Data("corrupt".utf8).write(to: newest.url)
        _ = try repository.load()
        XCTAssertEqual(try repository.recoveries().map { Int($0.date.timeIntervalSince1970) }, [1603, 1602, 1600, 1000])
        // 1602 is the most recent readable fallback when the newest file is damaged.
        _ = try repository.load()
        XCTAssertTrue(try repository.recoveries().contains { $0.date.timeIntervalSince1970 == 1602 })
    }
    func testStartupResamplesEightByTimeInsteadOfKeepingTheLatestEight() throws {
        let root = try directory(), repository = LedgerRepository(directory: root)
        try repository.save(ledger("当前"))
        // Exact targets are 1000, 2000, ... 8000; many candidates cluster at the end.
        for second in Array(stride(from: 1000, through: 8000, by: 1000)) + Array(7900..<7920) {
            _ = try write(ledger("\(second)"), at: root, seconds: second, reason: "导入账单")
        }
        let reopened = LedgerRepository(directory: root)
        _ = try reopened.load()
        XCTAssertEqual(try reopened.recoveries().map { Int($0.date.timeIntervalSince1970) }, Array(stride(from: 8000, through: 1000, by: -1000)))
        XCTAssertLessThanOrEqual(try reopened.storageUsage().recoveryBytes, 4 * 1024 * 1024)
        let urls = try reopened.recoveries().map(\.url)
        _ = try reopened.load(); XCTAssertEqual(try reopened.recoveries().map(\.url), urls)
    }
    func testByteBudgetUsesDistributedVersionsAndCanYieldOldestToKeepLatest() throws {
        let root = try directory(), repository = LedgerRepository(directory: root)
        try repository.save(ledger("当前"))
        for second in 1...9 {
            _ = try write(ledger("\(second)"), at: root, seconds: second * 1000, reason: "导入账单", padding: 900_000)
        }
        _ = try repository.load()
        let times = try repository.recoveries().map { Int($0.date.timeIntervalSince1970) }
        XCTAssertEqual(times.count, 4); XCTAssertEqual(times.first, 9000); XCTAssertEqual(times.last, 1000)
        XCTAssertTrue(times.contains { (3000...7000).contains($0) })
        XCTAssertLessThanOrEqual(try repository.storageUsage().recoveryBytes, 4 * 1024 * 1024)
        _ = try write(ledger("大最新"), at: root, seconds: 10000, reason: "导入账单", padding: 4 * 1024 * 1024)
        _ = try repository.load()
        XCTAssertEqual(try repository.recoveries().count, 1)
        XCTAssertEqual(try repository.readRecovery(XCTUnwrap(repository.recoveries().first)).accounts[0].name, "大最新")
    }
    func testDamagedWindowAnchorDoesNotSuppressANewRecovery() throws {
        let root = try directory()
        let file = try write(ledger("旧"), at: root, seconds: 1000, reason: "导入整理")
        try Data("corrupt".utf8).write(to: file)
        let repository = LedgerRepository(directory: root, recoveryDate: { Date(timeIntervalSince1970: 1001) })
        try repository.preserveRecovery(ledger("新"), reason: "导入整理")
        XCTAssertEqual(try repository.readRecovery(XCTUnwrap(repository.recoveries().first)).accounts[0].name, "新")
    }
    func testMissingPayloadDoesNotEvictTheLastCompleteRecovery() throws {
        let root = try directory(), repository = LedgerRepository(directory: root)
        try repository.save(ledger("当前"))
        let complete = try write(ledger("完整"), at: root, seconds: 1000, reason: "导入账单")
        for second in 1001...1010 {
            var broken = ledger("缺失附件")
            let attachment = Attachment(name: "缺失原件.csv", data: Data([1, 2, 3]))
            var entry = Entry(amount: 100, accountID: broken.accounts[0].id, title: "合成")
            entry.attachmentID = attachment.id; broken.entries = [entry]; broken.attachments = [attachment]
            _ = try write(broken, at: root, seconds: second, reason: "导入账单")
        }
        _ = try repository.load()
        XCTAssertTrue(try repository.recoveries().contains { $0.url == complete })
        XCTAssertEqual(try repository.readRecovery(XCTUnwrap(repository.recoveries().last)).accounts[0].name, "完整")
        XCTAssertThrowsError(try repository.readRecovery(XCTUnwrap(repository.recoveries().first)))
        XCTAssertLessThanOrEqual(try repository.recoveries().count, 8)
    }
    func testCloudConfigurationDisablesCacheAndPreservesTimeoutsProxyAndProtocols() {
        let base = URLSessionConfiguration.default
        base.timeoutIntervalForRequest = 37; base.timeoutIntervalForResource = 93
        base.connectionProxyDictionary = ["HTTPSProxy": "127.0.0.1", "HTTPSPort": 4321]
        let configured = CloudNetworking.configuration(basedOn: base)
        XCTAssertNil(configured.urlCache)
        XCTAssertEqual(configured.requestCachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertEqual(configured.timeoutIntervalForRequest, 37); XCTAssertEqual(configured.timeoutIntervalForResource, 93)
        XCTAssertEqual(configured.connectionProxyDictionary as NSDictionary?, base.connectionProxyDictionary as NSDictionary?)
        XCTAssertEqual(configured.protocolClasses?.map { String(describing: $0) }, base.protocolClasses?.map { String(describing: $0) })
        XCTAssertEqual(base.requestCachePolicy, .useProtocolCachePolicy)
        XCTAssertNil(CloudNetworking.session.configuration.urlCache)
    }
    func testBothChatAndCatalogRequestsIgnoreCacheEvenWithInjectedSession() async throws {
        let stub = CloudTestStub(rawResponse: true) { request in
            XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
            if request.url?.lastPathComponent == "models" { return #"{"data":[{"id":"synthetic-model"}]}"# }
            return #"{"choices":[{"message":{"content":"ok"}}]}"#
        }
        defer { stub.close() }
        _ = try await stub.send(ChatRequest(messages: []))
        let models = try await stub.listModels()
        XCTAssertEqual(models, ["synthetic-model"])
    }
    func testStartupCacheCleanupRemovesDBSidecarsAndPayloadsButKeepsOtherCaches() throws {
        let root = try directory()
        for namespace in ["", "app.yubai.personal", "test.yubai", "another.app", "YubaiUITests/test"] {
            let folder = root.appendingPathComponent(namespace)
            try FileManager.default.createDirectory(at: folder.appendingPathComponent("fsCachedData"), withIntermediateDirectories: true)
            for name in ["Cache.db", "Cache.db-wal", "Cache.db-shm", "keep.txt", "fsCachedData/body"] {
                try Data([1, 2, 3]).write(to: folder.appendingPathComponent(name))
            }
        }
        XCTAssertTrue(CloudNetworking.clearLegacyCache(in: root, bundleIdentifier: "test.yubai").isEmpty)
        for namespace in ["", "app.yubai.personal", "test.yubai"] {
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent(namespace).path).filter { $0 == "keep.txt" || $0.hasPrefix("Cache.db") || $0 == "fsCachedData" }, ["keep.txt"])
        }
        for namespace in ["another.app", "YubaiUITests/test"] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(namespace + "/Cache.db-wal").path))
        }
        XCTAssertTrue(CloudNetworking.clearLegacyCache(in: root, bundleIdentifier: "test.yubai").isEmpty)
    }
}
