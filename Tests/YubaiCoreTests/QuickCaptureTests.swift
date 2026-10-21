import XCTest
@testable import YubaiCore

final class QuickCaptureTests: XCTestCase {
    private let now = Dates.parse("2026-10-21 12:31:00")!
    private func fixture() -> Ledger {
        var ledger = Ledger()
        ledger.accounts = [Account(name: "微信零钱", kind: .cash, balance: 150_000, at: now.addingTimeInterval(-3600)), Account(name: "招行信用卡", kind: .credit, balance: 0, at: now.addingTimeInterval(-3600))]
        return ledger
    }
    private func drafts(_ text: String, ledger: Ledger? = nil) throws -> [EntryDraft] {
        guard case .drafts(let result) = try QuickCapture.parse(text, in: ledger ?? fixture(), now: now) else { XCTFail("应识别金额"); return [] }
        return result
    }
    func testLocalParserSharesAmountsAndMultipleDrafts() throws {
        for text in ["午饭 32", "咖啡 18 和面包 12", "打车24", "两杯咖啡各18"] {
            let entries = try drafts(text)
            XCTAssertEqual(entries.map(\.amount), EntryAmountParser.candidates(in: text))
            XCTAssertTrue(entries.allSatisfy { $0.amountConfirmed && $0.nature == .expense })
        }
        let result = try drafts("咖啡 18 和面包 12")
        XCTAssertEqual(result.map(\.title), ["咖啡", "面包"]); XCTAssertEqual(result.first?.category, "餐饮")
        XCTAssertEqual(try drafts("打车24").first?.category, "交通")
        XCTAssertEqual(try drafts("32").first?.title, "其他支出")
    }
    func testFollowUpAndMissingAccountAreDistinct() throws {
        for text in ["", "午饭", "2026-10-21 12:31", "买了3件", "1234567890123"] {
            XCTAssertEqual(try QuickCapture.parse(text, in: fixture(), now: now), .needsFollowUp)
        }
        XCTAssertThrowsError(try QuickCapture.parse("午饭32", in: Ledger(), now: now))
    }
    func testDefaultAccountCategoryMemoryAndSavePreviewUseExistingAlgorithms() throws {
        var ledger = fixture(); ledger.categoryMemory[CategoryMemory.key("面包")] = "餐饮"
        let parsed = try drafts("面包12", ledger: ledger)
        XCTAssertEqual(parsed[0].accountID, ManualBookkeeping.defaultAccount(in: ledger)?.id)
        XCTAssertEqual(parsed[0].category, "餐饮")
        var change = ChangeSet(source: "快捷指令", reason: "记一笔", items: parsed.map(ChangeItem.addEntry)); change.createdAt = now
        let preview = try ManualBookkeeping.available(after: change, in: ledger, now: now)
        let ids = try QuickCapture.record(parsed, in: &ledger, now: now)
        XCTAssertEqual(QuickCapture.available(in: ledger, now: now), preview)
        XCTAssertEqual(ids, parsed.map(\.id)); XCTAssertEqual(ledger.entries[0].recordedAt, now)
        XCTAssertEqual(ledger.entries[0].quickCapture?.withoutOpeningApp, true)
    }
    func testApplePayCurrencyAndInvalidAmounts() throws {
        for text in ["¥18.00", "CN¥18.00", "18.00", " ￥18 "] { XCTAssertEqual(try QuickCapture.applePayAmount(text), 1800) }
        XCTAssertEqual(try QuickCapture.applePayAmount("CN¥1,234.56"), 123456)
        for text in ["", "USD18", "-18", "0", "18.001", "18 32", "9999999999999999999999"] { XCTAssertThrowsError(try QuickCapture.applePayAmount(text)) }
    }
    func testApplePayRulesAndUnclassifiedFallback() throws {
        var ledger = fixture(); ledger.preferences.quickCapture.cardAccounts["招行"] = ledger.accounts[1].id
        try QuickCapture.remember(merchant: "瑞幸", category: "餐饮", in: &ledger)
        let first = try QuickCapture.applePay(merchant: "瑞幸", amount: "¥18", card: "招行", date: now, in: &ledger, now: now)
        XCTAssertEqual(first.entry.accountID, ledger.accounts[1].id); XCTAssertEqual(first.entry.category, "餐饮")
        XCTAssertEqual(first.entry.source, "Apple Pay"); XCTAssertFalse(first.entry.externalID.isEmpty)
        XCTAssertEqual(first.entry.quickCapture?.card, "招行"); XCTAssertFalse(first.entry.hasNoCaptureCategory)
        let unknown = try QuickCapture.applePay(merchant: "某某商户", amount: "58", card: "未映射", date: now, in: &ledger, now: now)
        XCTAssertEqual(unknown.entry.category, "其他支出"); XCTAssertTrue(unknown.entry.hasNoCaptureCategory)
        XCTAssertEqual(unknown.entry.accountID, ledger.accounts[1].id)
    }
    func testDedupAcrossBoundaryAndAfterUndo() throws {
        var ledger = fixture()
        let first = try QuickCapture.applePay(merchant: "咖啡", amount: "18", card: "A", date: now, in: &ledger, now: now)
        for offset in [-120.0, -1, 1, 119, 120] {
            let repeated = try QuickCapture.applePay(merchant: "咖啡", amount: "CN¥18.00", card: "A", date: now.addingTimeInterval(offset), in: &ledger, now: now)
            XCTAssertFalse(repeated.inserted); XCTAssertEqual(repeated.entry.id, first.entry.id)
        }
        QuickCapture.undo(entryID: first.entry.id, in: &ledger, now: now)
        let replay = try QuickCapture.applePay(merchant: "咖啡", amount: "18", card: "A", date: now, in: &ledger, now: now)
        XCTAssertFalse(replay.inserted); XCTAssertEqual(ledger.activeEntries.count, 0)
        QuickCapture.undo(entryID: UUID(), in: &ledger, now: now)
        for (merchant, amount, card, offset) in [("咖啡", "18", "A", 121.0), ("咖啡", "18", "B", 0), ("午饭", "18", "A", 0), ("咖啡", "19", "A", 0)] {
            XCTAssertTrue(try QuickCapture.applePay(merchant: merchant, amount: amount, card: card, date: now.addingTimeInterval(offset), in: &ledger, now: now).inserted)
        }
    }
    func testEditedDateDoesNotErasePaymentDedupEvidence() throws {
        var ledger = fixture()
        let first = try QuickCapture.applePay(merchant: "咖啡", amount: "18", card: "卡", date: now, in: &ledger, now: now)
        var edited = first.entry; edited.date = Dates.addDays(-1, to: now); edited.amount = 2000
        try ManualBookkeeping.edit(edited, in: &ledger)
        let repeated = try QuickCapture.applePay(merchant: "咖啡", amount: "18", card: "卡", date: now, in: &ledger, now: now)
        XCTAssertFalse(repeated.inserted); XCTAssertEqual(repeated.entry.id, first.entry.id); XCTAssertEqual(ledger.entries.count, 1)
    }
    func testArchivedCardMappingFallsBackAndRuleReplacement() throws {
        var ledger = fixture(); ledger.accounts[1].archived = true
        ledger.preferences.quickCapture.cardAccounts["卡"] = ledger.accounts[1].id
        try QuickCapture.remember(merchant: "SHOP", category: "购物", in: &ledger)
        try QuickCapture.remember(merchant: " shop ", category: "日用", in: &ledger)
        XCTAssertEqual(ledger.preferences.quickCapture.merchantCategories.count, 1)
        let entry = try QuickCapture.applePay(merchant: "Shop", amount: "1", card: "卡", date: now, in: &ledger, now: now).entry
        XCTAssertEqual(entry.category, "日用"); XCTAssertEqual(entry.accountID, ledger.accounts[0].id)
        XCTAssertThrowsError(try QuickCapture.remember(merchant: "", category: "餐饮", in: &ledger))
    }
    func testPreferencesAndEntryOldJSONCompatibilityAndRoundTrip() throws {
        var ledger = fixture()
        _ = try QuickCapture.applePay(merchant: "咖啡", amount: "18", card: "卡", date: now, in: &ledger, now: now)
        ledger.preferences.quickCapture.cardAccounts["卡"] = ledger.accounts[0].id
        let data = try LedgerCodec.encode(ledger)
        XCTAssertEqual(try LedgerCodec.decode(data), ledger)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var preferences = try XCTUnwrap(json["preferences"] as? [String: Any]); preferences.removeValue(forKey: "quickCapture"); json["preferences"] = preferences
        var entries = try XCTUnwrap(json["entries"] as? [[String: Any]]); entries[0].removeValue(forKey: "quickCapture"); json["entries"] = entries
        let old = try LedgerCodec.decode(JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(old.preferences.quickCapture, QuickCapturePreferences()); XCTAssertNil(old.entries[0].quickCapture)
    }
    func testScreenshotPaymentAndAmountOnSeparateLine() {
        let result = ReceiptTextParser.drafts(lines: ["支付成功", "¥32.00", "老王面馆", "2026-10-21 12:30:00", "订单号 2026102112345678", "账户余额 100.00"], now: now)
        XCTAssertEqual(result.count, 1); XCTAssertEqual(result.first?.amount, 3200); XCTAssertEqual(result.first?.title, "老王面馆")
        XCTAssertEqual(result.first?.nature, .expense); XCTAssertEqual(result.first?.directionNeedsReview, false)
    }
    func testScreenshotListPreservesEqualAmountsAndIncome() throws {
        let lines = ["2026-10-20 12:00:00", "午饭 -32.00", "滴滴出行 -24.00", "咖啡 -24.00", "工资 收入 +1000.00", "合计 1080.00", "余额 9999.00"]
        let result = ReceiptTextParser.drafts(lines: lines, now: now)
        XCTAssertEqual(result.map(\.amount), [3200, 2400, 2400, 100000]); XCTAssertEqual(result.map(\.title), ["午饭", "滴滴出行", "咖啡", "工资"])
        XCTAssertEqual(result.last?.nature, .income); XCTAssertEqual(result.first?.dateNeedsReview, false)
        let table = String(data: try ReceiptTextParser.table(lines: lines, now: now), encoding: .utf8)!
        XCTAssertEqual(table.components(separatedBy: "\n").count, 5)
        XCTAssertEqual(result[1].entryDraft(in: fixture(), accountID: fixture().accounts[0].id).category, "交通")
    }
    func testScreenshotInlineDatesAndTimesNeverBecomeMoney() {
        let result = ReceiptTextParser.drafts(lines: ["2026-10-20 12:30 午饭 -32.00", "2026-10-21 09:31 咖啡 -18.00"], now: now)
        XCTAssertEqual(result.map(\.amount), [3200, 1800]); XCTAssertEqual(result.map(\.title), ["午饭", "咖啡"])
        XCTAssertEqual(Dates.text(result[0].date), "2026-10-20"); XCTAssertEqual(Dates.text(result[1].date), "2026-10-21")
    }
    func testScreenshotIgnoresDatesCountsAndEmptyRecognition() {
        XCTAssertTrue(ReceiptTextParser.drafts(lines: ["12:31", "2026-10-21", "订单号 123456789", "共3笔"], now: now).isEmpty)
        XCTAssertThrowsError(try ReceiptTextParser.table(lines: [], now: now))
    }
    func testSnapshotTodayFrequentAndUndo() throws {
        var ledger = fixture()
        for (text, offset) in [("午饭32", -86400.0), ("咖啡18", -120), ("午饭32", 0), ("打车24", -60)] {
            let items = try drafts(text, ledger: ledger)
            var dated = items; dated[0].date = now.addingTimeInterval(offset)
            try QuickCapture.record(dated, in: &ledger, now: now)
        }
        let snapshot = QuickCaptureSnapshot(ledger: ledger, now: now)
        XCTAssertEqual(snapshot.todayCount, 3); XCTAssertEqual(snapshot.todayTotal, 7400)
        XCTAssertEqual(snapshot.frequent.count, 3); XCTAssertEqual(snapshot.frequent.first?.purpose, "午饭")
        XCTAssertEqual(snapshot.available, Finance.funds(ledger, now: now).available)
        XCTAssertEqual(try JSONDecoder().decode(QuickCaptureSnapshot.self, from: JSONEncoder().encode(snapshot)), snapshot)
        QuickCapture.undo(entryID: ledger.entries.last!.id, in: &ledger, now: now)
        XCTAssertEqual(QuickCaptureSnapshot(ledger: ledger, now: now).todayCount, 2)
    }
}
