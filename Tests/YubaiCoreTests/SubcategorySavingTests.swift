import XCTest
@testable import YubaiCore

final class SubcategorySavingTests: XCTestCase {
    let now = Dates.parse("2026-06-15 12:00")!
    func seed() -> Ledger {
        var ledger = Ledger(); ledger.updatedAt = now
        ledger.accounts = [Account(name: "不要发出的账户名字", balance: 100_000, at: now)]
        return ledger
    }
    func entry(_ ledger: Ledger, title: String, category: String = "餐饮", amount: Int64 = 3200) -> Entry {
        Entry(date: now, amount: amount, accountID: ledger.accounts[0].id, title: title, category: category)
    }
    func response(_ entries: [Entry], category: String? = nil, sub: String = "午餐") throws -> ChatMessage {
        let items: [JSONValue] = entries.map { entry in
            var fields: [String: JSONValue] = ["id": .string(entry.id.uuidString), "subcategory": .string(sub)]
            if let category { fields["category"] = .string(category) }
            return .object(fields)
        }
        return ChatMessage(role: .assistant, content: try JSONValue.object(["items": .array(items)]).jsonText())
    }
    func testUnifiedCategoryTableHasTwoLevelsWithoutAutomaticOther() {
        let categories = Category.defaults
        XCTAssertEqual(categories.filter { !$0.income && !$0.system }.map(\.name), ["餐饮", "购物", "交通", "居住", "医疗健康", "娱乐", "旅行", "会员订阅", "学习成长", "人情家庭", "利息手续费", "其他支出"])
        XCTAssertEqual(categories.filter(\.income).map(\.name), ["工资奖金", "兼职劳务", "礼金赠与", "投资收益", "其他收入"])
        XCTAssertTrue(categories.allSatisfy { !$0.subcategories.contains("其他") && !$0.subcategories.contains(where: { $0.contains("/") }) })
        XCTAssertEqual(ManualBookkeeping.defaults(for: .expense).count, 12)
        XCTAssertTrue(ManualBookkeeping.defaults(for: .expense).allSatisfy { name in categories.contains { $0.name == name } })
    }
    func testEditingUnlinkedRefundSubcategoryUsesExpenseCategoriesAndRemembersChoice() throws {
        var ledger = seed()
        var refund = entry(ledger, title: "退回鞋款", category: "购物")
        refund.nature = .refund
        ledger.entries = [refund]
        try SubcategoryClassifier.set("运动户外", entryID: refund.id, in: &ledger)
        XCTAssertEqual(ledger.entries[0].subcategory, "运动户外")
        XCTAssertTrue(ledger.entries[0].subcategoryUserEdited)
        XCTAssertEqual(ledger.subcategoryMemory[CategoryMemory.key(refund.title)], "购物/运动户外")
        XCTAssertFalse(SubcategoryClassifier.valid(.init(category: "工资奖金", subcategory: "工资"), in: ledger, nature: .refund))
        try ledger.validate()
    }
    func testLegacyCategoriesMigrateEntriesMemoriesAliasesProfileAndKeepCustom() throws {
        var old = seed(); let names = ["日用购物", "日用", "购物", "娱乐", "工资", "奖金", "兼职", "理财收益", "自定义主项"]
        old.categories = names.map { Category($0, income: ["工资", "奖金", "兼职", "理财收益"].contains($0)) }
        old.entries = names.map { name in var e = entry(old, title: name, category: name); if ["工资", "奖金", "兼职", "理财收益"].contains(name) { e.nature = .income }; return e }
        old.categoryMemory = ["用途": "日用", "发薪": "工资"]; old.categoryAliases = ["旧购物": "日用购物"]
        old.profile.restrain = [ProfileArea(title: "购物", match: .init(categories: ["日用购物", "日用"]))]
        old.profile.generous = [ProfileArea(title: "自定义", match: .init(categories: ["自定义主项"]))]
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as? [String: Any]); json["schema"] = 2
        json["categories"] = (json["categories"] as! [[String: Any]]).map { row -> [String: Any] in var row = row; row.removeValue(forKey: "subcategories"); return row }
        json["entries"] = (json["entries"] as! [[String: Any]]).map { row -> [String: Any] in var row = row; row.removeValue(forKey: "subcategory"); row.removeValue(forKey: "subcategoryUserEdited"); return row }
        let ledger = try JSONDecoder().decode(Ledger.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(ledger.schema, 4)
        XCTAssertEqual(ledger.entries.map(\.category), ["购物", "购物", "购物", "娱乐", "工资奖金", "工资奖金", "兼职劳务", "投资收益", "自定义主项"])
        XCTAssertEqual(ledger.entries[0].subcategory, "日用百货"); XCTAssertEqual(ledger.entries[4].subcategory, "工资"); XCTAssertEqual(ledger.entries[5].subcategory, "奖金")
        XCTAssertEqual(ledger.categoryMemory["用途"], "购物"); XCTAssertEqual(ledger.subcategoryMemory["用途"], "购物/日用百货")
        XCTAssertEqual(ledger.resolveCategory("旧购物"), "购物"); XCTAssertEqual(ledger.profile.restrain[0].match.categories, ["购物"])
        XCTAssertTrue(ledger.categories.contains { $0.name == "自定义主项" }); XCTAssertFalse(ledger.categories.contains { $0.name == "日用" })
        XCTAssertEqual(try LedgerCodec.decode(LedgerCodec.encode(ledger)), ledger)
    }
    func testOldLedgerMissingEveryNewFieldAndOldWishAndLetterDecode() throws {
        var ledger = seed(); ledger.entries = [entry(ledger, title: "午餐")]
        ledger.wishlist = [WishItem(title: "旧心愿", amount: 1000)]
        ledger.cards = [WeeklyLetter.candidate(ledger, now: now)!.card(now: now)]
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(ledger)) as? [String: Any]); json["schema"] = 2
        for key in ["subcategoryMemory", "lastSubcategoryBatchDay", "subscriptionChecks", "stoppedSubscriptions"] { json.removeValue(forKey: key) }
        json["entries"] = (json["entries"] as! [[String: Any]]).map { row -> [String: Any] in var row = row; row.removeValue(forKey: "subcategoryUserEdited"); return row }
        let decoded = try JSONDecoder().decode(Ledger.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertFalse(decoded.entries[0].subcategoryUserEdited)
        XCTAssertNil(decoded.wishlist[0].coolUntil); XCTAssertNil(decoded.wishlist[0].droppedAt); XCTAssertNil(decoded.wishlist[0].source)
        XCTAssertNil(decoded.cards[0].letter?.weeklySavings); XCTAssertNil(decoded.lastSubcategoryBatchDay)
        XCTAssertTrue(decoded.subscriptionChecks.isEmpty); XCTAssertTrue(decoded.stoppedSubscriptions.isEmpty)
        XCTAssertEqual(try LedgerCodec.decode(LedgerCodec.encode(decoded)), decoded)
    }
    func testLocalKeywordsCanGuessMainWithoutSmallItemAndRespectMainCategory() {
        let ledger = seed()
        XCTAssertEqual(SubcategoryClassifier.local(entry(ledger, title: "美团外卖"), ledger), .init(category: "餐饮", subcategory: "外卖"))
        XCTAssertEqual(SubcategoryClassifier.local(entry(ledger, title: "滴滴", category: Classification.pendingCategory), ledger), .init(category: "交通", subcategory: "打车"))
        XCTAssertEqual(SubcategoryClassifier.local(entry(ledger, title: "京东淘宝", category: "购物"), ledger), .init(category: "购物"))
        XCTAssertNil(SubcategoryClassifier.local(entry(ledger, title: "外卖", category: "交通"), ledger))
        XCTAssertEqual(SubcategoryClassifier.local(entry(ledger, title: "京东纸巾", category: "购物"), ledger)?.subcategory, "日用百货")
    }
    func testUserSubcategoryMemoryWinsAndClearingPreventsReclassification() throws {
        var ledger = seed(); var e = entry(ledger, title: "商户订单123", category: "购物"); e.purpose = "常买的用品"; ledger.entries = [e]
        try SubcategoryClassifier.set("美妆个护", entryID: e.id, in: &ledger)
        XCTAssertTrue(ledger.entries[0].subcategoryUserEdited)
        var next = e; next.title = "商户订单456"; next.purpose = nil
        XCTAssertEqual(SubcategoryClassifier.local(next, ledger)?.subcategory, "美妆个护")
        XCTAssertEqual(ledger.subcategoryMemory["常买的用品"], "购物/美妆个护")
        XCTAssertThrowsError(try SubcategoryClassifier.set("打车", entryID: e.id, in: &ledger))
        try SubcategoryClassifier.set(nil, entryID: e.id, in: &ledger)
        SubcategoryClassifier.classify(&ledger.entries[0], ledger: seed())
        XCTAssertNil(ledger.entries[0].subcategory); XCTAssertTrue(SubcategoryBatch.pending(ledger).isEmpty)
    }
    func testManualEditRemembersSubcategoryAndMainChangeClearsStaleSmallItem() throws {
        var ledger = seed(); ledger.entries = [entry(ledger, title: "咖啡")]
        var edited = ledger.entries[0]; edited.subcategory = "咖啡饮品"
        try ManualBookkeeping.edit(edited, in: &ledger)
        XCTAssertTrue(ledger.entries[0].subcategoryUserEdited); XCTAssertEqual(ledger.subcategoryMemory["咖啡"], "餐饮/咖啡饮品")
        edited = ledger.entries[0]; edited.category = "购物"
        try ManualBookkeeping.edit(edited, in: &ledger)
        XCTAssertNil(ledger.entries[0].subcategory); XCTAssertFalse(ledger.entries[0].subcategoryUserEdited)
    }
    func testManualQuickCaptureAndImportRunLocalClassification() throws {
        var ledger = seed()
        let change = try ManualBookkeeping.change(amount: 3200, nature: .expense, accountID: ledger.accounts[0].id, day: now, purpose: "午餐", category: "餐饮", now: now)
        try change.apply(to: &ledger); XCTAssertEqual(ledger.entries.last?.subcategory, "午餐")
        let pay = try QuickCapture.applePay(merchant: "滴滴", amount: "32", card: "合成卡", date: now, in: &ledger, now: now)
        XCTAssertEqual(pay.entry.subcategory, "打车")
        let csv = "日期,金额,收支,交易对方,分类\n2026-06-14,20,支出,外卖,餐饮\n"
        let preview = try BillImporter.preview(data: Data(csv.utf8), filename: "合成.csv", accountID: ledger.accounts[0].id, ledger: ledger)
        _ = try BillImporter.commit(preview, data: Data(csv.utf8), to: &ledger)
        XCTAssertEqual(ledger.entries.last?.subcategory, "外卖")
    }
    func testBatchChunksAllRowsAndLogsRedactedAllowlistedPayloadOncePerDay() async throws {
        var ledger = seed(); ledger.entries = (0..<161).map { _ in entry(ledger, title: "转账给张三 6222021234567890", category: Classification.pendingCategory) }
        let replies = try stride(from: 0, to: 161, by: 40).map { offset in
            var reply = try response(Array(ledger.entries.dropFirst(offset).prefix(40)), category: "餐饮")
            reply.content = "```json\n" + reply.content! + "\n```"
            return reply
        }
        let transport = ScriptedChatTransport(replies)
        let result = try await SubcategoryBatch.run(transport: transport, ledger: ledger, now: now)
        XCTAssertEqual(result.choices.count, 161); let requests = await transport.recorded(); XCTAssertEqual(requests.count, 5)
        for request in requests {
            XCTAssertEqual(request.purpose, "小项归类")
            XCTAssertEqual(request.thinking, false)
            let body = request.messages.compactMap(\.content).joined(separator: "\n")
            XCTAssertFalse(body.contains("不要发出的账户名字")); XCTAssertFalse(body.contains(ledger.accounts[0].id.uuidString)); XCTAssertFalse(body.contains("张三")); XCTAssertFalse(body.contains("6222021234567890"))
            let payload = try JSONValue.parse(request.messages.last!.content!)
            let count = payload["entries"]!.arrayValue!.count
            XCTAssertLessThanOrEqual(count, 40)
            XCTAssertGreaterThanOrEqual(request.maxTokens, 512 + count * 128)
            XCTAssertLessThanOrEqual(request.maxTokens, 6000)
            XCTAssertNil(payload["entries"]?.arrayValue?.first?["amount"]); XCTAssertNotNil(payload["entries"]?.arrayValue?.first?["amount_band"])
        }
        try result.apply(to: &ledger, now: now)
        XCTAssertFalse(SubcategoryBatch.isDue(ledger, now)); XCTAssertTrue(SubcategoryBatch.pending(ledger).isEmpty)
        XCTAssertTrue(SubcategoryBatch.isDue(ledger, Dates.addDays(1, to: now))); XCTAssertFalse(ledger.subcategoryMemory.isEmpty)
        do { _ = try await SubcategoryBatch.run(transport: transport, ledger: ledger, now: now); XCTFail("second round") } catch { }
        let count = await transport.recorded().count; XCTAssertEqual(count, 5)
    }
    func testBatchStrictJSONRejectsUnknownDuplicateCrossCategoryAndWrongIncome() async throws {
        let base = seed(); var ledger = base; let row = entry(base, title: "用途"); ledger.entries = [row]
        let id = row.id.uuidString
        let invalid = [
            #"{"items":[{"id":"ID","subcategory":"不存在"}]}"#,
            #"{"items":[{"id":"ID","category":"交通","subcategory":"打车"}]}"#,
            #"{"items":[{"id":"ID","subcategory":"午餐","extra":1}]}"#,
            #"{"items":[{"id":"ID","subcategory":"午餐"},{"id":"ID","subcategory":"午餐"}]}"#,
            #"{"items":[],"extra":true}"#, #"{"items":[{"id":"missing","subcategory":"午餐"}]}"#,
            #"{"items":[{"id":"ID","subcategory":"午餐","category":1}]}"#, "not json"
        ]
        for text in invalid {
            let transport = ScriptedChatTransport([ChatMessage(role: .assistant, content: text.replacingOccurrences(of: "ID", with: id))])
            do { _ = try await SubcategoryBatch.run(transport: transport, ledger: ledger, now: now); XCTFail(text) } catch { }
            XCTAssertEqual(ledger, baseWithEntry(base, row)); XCTAssertNil(ledger.lastSubcategoryBatchDay)
        }
        ledger.entries[0].category = Classification.pendingCategory
        let transport = ScriptedChatTransport([try response(ledger.entries, category: "工资奖金", sub: "工资")])
        do { _ = try await SubcategoryBatch.run(transport: transport, ledger: ledger, now: now); XCTFail("wrong income") } catch { }
    }
    func baseWithEntry(_ base: Ledger, _ row: Entry) -> Ledger { var next = base; next.entries = [row]; return next }
    func testBatchFailureInLaterChunkAndStaleApplyAreAtomic() async throws {
        var ledger = seed(); ledger.entries = (0..<41).map { _ in entry(ledger, title: "用途") }
        let before = ledger
        let bad = ScriptedChatTransport([try response(Array(ledger.entries.prefix(40))), ChatMessage(role: .assistant, content: "bad")])
        do { _ = try await SubcategoryBatch.run(transport: bad, ledger: ledger, now: now); XCTFail("later chunk") } catch { }
        XCTAssertEqual(ledger, before)
        let good = ScriptedChatTransport([try response(Array(ledger.entries.prefix(40))), try response(Array(ledger.entries.suffix(1)))])
        let result = try await SubcategoryBatch.run(transport: good, ledger: ledger, now: now)
        ledger.updatedAt = now.addingTimeInterval(1); let changed = ledger
        XCTAssertThrowsError(try result.apply(to: &ledger, now: now)); XCTAssertEqual(ledger, changed)
    }
    func testBatchSkipsUserEditedSmallItemsAndKeepsCustomMainAndSmallItems() async throws {
        var ledger = seed(); ledger.categories.append(Category("自定义", subcategories: ["常用"])); ledger.entries = [entry(ledger, title: "用途", category: "自定义")]
        var edited = entry(ledger, title: "不自动改"); edited.subcategoryUserEdited = true; ledger.entries.append(edited)
        let transport = ScriptedChatTransport([try response([ledger.entries[0]], category: "自定义", sub: "常用")])
        let result = try await SubcategoryBatch.run(transport: transport, ledger: ledger, now: now); try result.apply(to: &ledger, now: now)
        XCTAssertEqual(ledger.entries[0].subcategory, "常用"); XCTAssertNil(ledger.entries[1].subcategory)
    }
    func testBatchCancellationDoesNotSendAndIncomeBreakdownUsesIncomeSmallItems() async throws {
        var ledger = seed(); var wage = entry(ledger, title: "工资", category: "工资奖金", amount: 500_000); wage.nature = .income; wage.subcategory = "工资"; ledger.entries = [wage]
        let breakdown = Finance.subcategoryBreakdown(ledger, category: "工资奖金", during: .init(start: Dates.day(now), end: Dates.addDays(1, to: now)))
        XCTAssertEqual(breakdown.first?.amount, 500_000); XCTAssertEqual(breakdown.first?.category, "工资")
        ledger.entries[0].subcategory = nil
        let transport = ScriptedChatTransport([])
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await SubcategoryBatch.run(transport: transport, ledger: ledger, now: now)
        }
        do { _ = try await task.value; XCTFail("cancelled") } catch { XCTAssertTrue(error is CancellationError) }
        let requests = await transport.recorded(); XCTAssertTrue(requests.isEmpty); XCTAssertNil(ledger.lastSubcategoryBatchDay)
    }
    func testSubcategoryStatsAndHabitToolsFollowRefundAndPreferSmallItem() throws {
        var ledger = seed(); var lunch = entry(ledger, title: "饭", amount: 3000); lunch.subcategory = "午餐"
        var coffee = entry(ledger, title: "咖啡", amount: 2000); coffee.subcategory = "咖啡饮品"
        var refund = entry(ledger, title: "退回", category: "其他支出", amount: 500); refund.nature = .refund; refund.relatedEntryID = lunch.id
        ledger.entries = [lunch, coffee, refund]
        let ctx = ToolContext(ledger: ledger, now: now)
        let breakdown = Finance.subcategoryBreakdown(ledger, category: "餐饮", during: .init(start: Dates.day(now), end: Dates.addDays(1, to: now)))
        XCTAssertEqual(breakdown.map(\.amount), [2500, 2000])
        let habit = try ReadOnlyTool.compareToHabit.run(.object(["category": .string("餐饮"), "subcategory": .string("午餐"), "keyword": .string("不会匹配")]), ctx)
        XCTAssertEqual(habit["count"], .number(1)); XCTAssertEqual(habit["average"], .money(3000))
        let query = try ReadOnlyTool.queryEntries.run(.object(["category": .string("餐饮"), "subcategory": .string("午餐")]), ctx)
        XCTAssertEqual(query["entries"]?.arrayValue?.count, 2)
        XCTAssertTrue(query["entries"]!.arrayValue!.allSatisfy { $0["subcategory"] == .string("午餐") })
        let summary = try ReadOnlyTool.summarize.run(.object(["category": .string("餐饮"), "group_by": .string("subcategory")]), ctx)
        XCTAssertEqual(summary["groups"]?.arrayValue?.count, 2)
    }
}
