import XCTest
@testable import YubaiCore

final class CategoryModelTests: XCTestCase {
    let now = Dates.parse("2026-10-20 12:30")!
    func seed() -> Ledger {
        var ledger = Ledger(); ledger.updatedAt = now
        ledger.accounts = [Account(name: "测试卡", balance: 100_000, at: now)]
        return ledger
    }
    func row(_ ledger: Ledger, _ category: String = Classification.pendingCategory, _ sub: String? = nil, title: String = "商户订单123") -> Entry {
        var entry = Entry(date: now, amount: 1000, accountID: ledger.accounts[0].id, title: title, category: category)
        entry.subcategory = sub; return entry
    }
    func oldJSON(_ ledger: Ledger, schema: Int = 3) throws -> [String: Any] {
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(ledger)) as? [String: Any])
        json["schema"] = schema; return json
    }
    func decode(_ json: [String: Any]) throws -> Ledger { try LedgerCodec.decode(JSONSerialization.data(withJSONObject: json)) }
    func testDefaultsHaveExactOrderNoAutomaticOtherAndSystemIsNeverSelectable() throws {
        let ledger = seed()
        let expense = ["餐饮", "购物", "交通", "居住", "医疗健康", "娱乐", "旅行", "会员订阅", "学习成长", "人情家庭", "利息手续费", "其他支出"]
        XCTAssertEqual(ManualBookkeeping.defaults(for: .expense), expense)
        XCTAssertEqual(ManualBookkeeping.categories(in: ledger, nature: .expense), expense)
        XCTAssertEqual(ManualBookkeeping.defaults(for: .income), ["工资奖金", "兼职劳务", "礼金赠与", "投资收益", "其他收入"])
        XCTAssertTrue(ManualBookkeeping.categories(in: ledger, nature: .transfer).isEmpty)
        XCTAssertEqual(ledger.categories.filter(\.system).map(\.name), ["内部移动"])
        XCTAssertEqual(Category("自定").subcategories, [])
        XCTAssertFalse(ledger.categories.contains { $0.subcategories.contains("其他") })
        XCTAssertTrue(ledger.categories.first { $0.name == "其他支出" }!.subcategories.isEmpty)
        try ledger.validate()
    }
    func testAllPreviousRuleWordsRemainInTheTable() {
        let words = Set(Category.defaults.flatMap { $0.keywords + $0.subcategoryKeywords.values.flatMap { $0 } })
        let previous = ["工资", "薪水", "薪资", "奖金", "年终奖", "兼职", "稿费", "早饭", "早餐", "午饭", "午餐", "晚饭", "晚餐", "吃饭", "外卖", "咖啡", "奶茶", "餐厅", "打车", "出租车", "滴滴", "地铁", "公交", "车票", "加油", "日用", "纸巾", "洗衣", "洗发", "超市", "罗森", "买衣", "衣服", "买鞋", "购物", "淘宝", "京东", "电影", "游戏", "演唱会", "娱乐", "饿了么", "美团外卖", "饮品", "零食", "水果", "聚餐", "停车", "火车", "机票", "高铁", "共享单车", "洗衣液", "鞋包", "登山杖", "登山鞋", "帐篷", "房租", "水费", "电费", "燃气", "会员", "订阅"]
        XCTAssertTrue(Set(previous).isSubset(of: words), "丢失：\(Set(previous).subtracting(words))")
    }
    func testKeywordUpgradeOnSchema4LoadIsAdditiveAndIdempotent() throws {
        var ledger = seed()
        ledger.categories = [Category("餐饮", subcategories: ["咖啡饮品", "自定小项"], keywords: ["自定主词", "餐厅"],
            subcategoryKeywords: ["咖啡饮品": ["自定饮品", "咖啡"], "自定小项": ["自定小词"]]),
            Category("购物", subcategories: ["服饰鞋包"], keywords: ["自定购物"]),
            Category("自定义", keywords: ["私人词"]), Category("交通", keywords: ["系统词"], system: true)]
        let upgraded = try LedgerCodec.decode(LedgerCodec.encode(ledger))
        XCTAssertEqual(upgraded.schema, 4); XCTAssertEqual(upgraded.categories.map(\.name), ledger.categories.map(\.name))
        let dining = upgraded.categories[0], defaults = Category.defaults.first { $0.name == "餐饮" }!
        XCTAssertEqual(dining.keywords, ["自定主词", "餐厅"] + defaults.keywords.filter { !["自定主词", "餐厅"].contains($0) })
        XCTAssertEqual(dining.subcategoryKeywords["咖啡饮品"], ["自定饮品", "咖啡"] + defaults.subcategoryKeywords["咖啡饮品"]!.filter { !["自定饮品", "咖啡"].contains($0) })
        XCTAssertEqual(dining.subcategories, ["咖啡饮品", "自定小项"]); XCTAssertEqual(dining.subcategoryKeywords["自定小项"], ["自定小词"])
        XCTAssertNil(upgraded.categories[1].subcategoryKeywords["日用百货"])
        XCTAssertEqual(Array(upgraded.categories.suffix(2)), Array(ledger.categories.suffix(2)))
        var again = upgraded; CategoryMigration.upgradeKeywords(to: &again); XCTAssertEqual(again, upgraded)
        XCTAssertEqual(try LedgerCodec.decode(LedgerCodec.encode(upgraded)), upgraded)
        XCTAssertEqual(CategoryGuesser.guess("COFFEE", nature: .expense, in: upgraded), .init(category: "餐饮", subcategory: "咖啡饮品"))
    }
    func testGenericVocabularyAndLongestEvidence() {
        let ledger = seed()
        for word in ["烧烤", "小吃", "面馆", "麻辣烫", "饭店", "餐饮", "烧麦", "火锅", "快餐"] {
            XCTAssertEqual(CategoryGuesser.guess(word, nature: .expense, in: ledger)?.category, "餐饮", word)
        }
        for (words, category, sub) in [(["coffee", "CAFE", "茶饮"], "餐饮", "咖啡饮品"),
            (["便利店", "超市", "商店", "百货", "菜市场", "生鲜"], "购物", "日用百货"),
            (["高速", "加油站", "停车场", "etc"], "交通", "加油停车"),
            (["地铁", "公交"], "交通", "公共交通"), (["药房"], "医疗健康", "药品"), (["诊所"], "医疗健康", "看病")] {
            for word in words { XCTAssertEqual(CategoryGuesser.guess(word, nature: .expense, in: ledger), .init(category: category, subcategory: sub), word) }
        }
        XCTAssertNil(CategoryGuesser.guess("蚂蚁（杭州）基金销售有限公司", nature: .expense, in: ledger))
        XCTAssertEqual(CategoryGuesser.guess("便利店 COFFEE", nature: .expense, in: ledger), .init(category: "餐饮", subcategory: "咖啡饮品"))
        XCTAssertEqual(CategoryGuesser.guess("电影会员", nature: .expense, in: ledger), .init(category: "会员订阅", subcategory: "影音会员"))
    }
    func testSchema3MigrationEverySplitAndOtherAndIdempotence() throws {
        var ledger = seed()
        let cases: [(String, String?, String, String?)] = [
            ("娱乐旅行", "旅行住宿", "旅行", "住宿"), ("娱乐旅行", "会员订阅", "会员订阅", nil),
            ("娱乐旅行", "电影演出", "娱乐", "电影演出"), ("娱乐旅行", "游戏", "娱乐", "游戏"),
            ("娱乐旅行", "运动健身", "娱乐", "运动健身"), ("娱乐旅行", nil, "娱乐", nil),
            ("学习工作", "课程", "学习成长", "课程"), ("学习工作", "书籍", "购物", "书和文具"),
            ("学习工作", "办公用品", "购物", "书和文具"), ("学习工作", "软件工具", "会员订阅", "软件云服务"),
            ("学习工作", nil, "学习成长", nil), ("餐饮", "其他", "餐饮", nil)
        ]
        ledger.categories += [Category("娱乐旅行", subcategories: ["旅行住宿", "会员订阅", "电影演出", "游戏", "运动健身", "其他"]), Category("学习工作", subcategories: ["课程", "书籍", "办公用品", "软件工具", "其他"])]
        ledger.entries = cases.map { row(ledger, $0.0, $0.1) }
        let migrated = try decode(oldJSON(ledger))
        XCTAssertEqual(migrated.schema, 4)
        XCTAssertEqual(migrated.entries.map(\.category), cases.map { $0.2 })
        XCTAssertEqual(migrated.entries.map(\.subcategory), cases.map { $0.3 })
        XCTAssertFalse(migrated.categories.contains { ["娱乐旅行", "学习工作"].contains($0.name) || $0.subcategories.contains("其他") })
        var again = migrated; CategoryMigration.apply(to: &again); XCTAssertEqual(again, migrated)
        XCTAssertEqual(try LedgerCodec.decode(LedgerCodec.encode(migrated)), migrated)
        XCTAssertEqual(migrated.categoryAssignment(category: "学习工作", subcategory: "软件工具"), .init(category: "会员订阅", subcategory: "软件云服务"))
    }
    func testMigrationRewritesEveryReferenceIncludingDelayedChangesAndUndo() throws {
        var ledger = seed(); ledger.categories += [Category("学习工作"), Category("娱乐旅行")]
        ledger.entries = [row(ledger, "学习工作", "书籍")]
        ledger.plans = [Plan(title: "课程", amount: 200, dueDate: now, category: "学习工作")]
        var wish = WishItem(title: "工具", amount: 200); wish.category = "学习工作"; wish.subcategory = "软件工具"; ledger.wishlist = [wish]
        ledger.profile.generous = [ProfileArea(title: "成长", match: .init(categories: ["学习工作"], subcategories: ["学习工作/书籍", "娱乐旅行/旅行住宿"]))]
        ledger.profile.restrain = [ProfileArea(title: "订阅", match: .init(subcategories: ["娱乐旅行/会员订阅"]))]
        ledger.classificationMemory = ["商店": "学习工作/办公用品", "旅店": "娱乐旅行/旅行住宿"]
        ledger.categoryAliases = ["旧办公": "学习工作", "酒店旧名": "娱乐旅行/旅行住宿"]
        let area = ledger.profile.generous[0]
        ledger.pendingChanges = [ChangeSet(source: "问余白", reason: "待确认", items: [.setCategory(entry: ledger.entries[0].id, category: "学习工作"), .addPlan(ledger.plans[0]), .addEntry(EntryDraft(date: now, amount: 100, accountID: ledger.accounts[0].id, title: "草稿", category: "娱乐旅行")), .profile(.upsertArea(area, stance: .generous))])]
        var batch = ImportBatch(filename: "账单", importedCount: 1, duplicateCount: 0, skippedCount: 0)
        var undo = ImportUndo(updatedAt: now); undo.entries = ledger.entries; batch.undo = undo; ledger.imports = [batch]
        var card = ButlerCard(kind: .answerQuestion, title: "用途", body: "", dedupeKey: "问题")
        card.importQuestion = ImportQuestion(text: "用途", entryIDs: [ledger.entries[0].id], options: [ImportAnswer(title: "分类", items: ledger.pendingChanges[0].items)])
        ledger.cards = [card]
        let result = try decode(oldJSON(ledger))
        XCTAssertEqual(result.plans[0].category, "学习成长")
        XCTAssertEqual(result.wishlist[0].category, "会员订阅"); XCTAssertEqual(result.wishlist[0].subcategory, "软件云服务")
        XCTAssertEqual(result.profile.generous[0].match.subcategories, ["购物/书和文具", "旅行/住宿"])
        XCTAssertEqual(result.profile.restrain[0].match.categories, ["会员订阅"])
        XCTAssertEqual(result.classificationMemory["商店"], "购物/书和文具")
        XCTAssertEqual(result.categoryAliases["旧办公"], "学习成长")
        XCTAssertEqual(result.imports[0].undo?.entries[0].subcategory, "书和文具")
        if case .setCategory(_, let name) = result.pendingChanges[0].items[0] { XCTAssertEqual(name, "学习成长") } else { XCTFail() }
        XCTAssertEqual(result.cards[0].importQuestion?.options[0].items, result.pendingChanges[0].items)
    }
    func testCustomMainMappingContainsAliasAndUnmappedIsRetained() throws {
        var ledger = seed(); ledger.categories += [Category("餐饮美食"), Category("交通出行"), Category("私人收藏", subcategories: ["藏品", "其他"])]
        ledger.categoryAliases["吃喝旧名"] = "餐饮美食"
        ledger.entries = [row(ledger, "餐饮美食"), row(ledger, "交通出行"), row(ledger, "私人收藏", "藏品"), row(ledger, "吃喝旧名")]
        let result = try decode(oldJSON(ledger))
        XCTAssertEqual(result.entries.map(\.category), ["餐饮", "交通", "私人收藏", "餐饮"])
        XCTAssertEqual(result.resolveCategory("餐饮美食"), "餐饮")
        XCTAssertEqual(result.resolveCategory("吃喝旧名"), "餐饮")
        XCTAssertEqual(result.categories.filter { $0.name == "私人收藏" }.first?.subcategories, ["藏品"])
    }
    func testSchema1FixtureStillMigratesAllTheWayToFour() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "ledger-schema-1", withExtension: "json", subdirectory: "Fixtures"))
        let ledger = try LedgerCodec.decode(Data(contentsOf: url)); XCTAssertEqual(ledger.schema, 4)
        XCTAssertEqual(ledger.categories.filter { !$0.system && !$0.income }.count, 12)
        XCTAssertEqual(try LedgerCodec.decode(LedgerCodec.encode(ledger)), ledger)
    }
    func testLegacyThreeMemoriesNormalizeAndHaveDeterministicPrecedence() throws {
        let ledger = seed(); var json = try oldJSON(ledger)
        json["categoryMemory"] = ["SHOP-123": "餐饮", " old 2! ": "工资"]
        json["subcategoryMemory"] = ["shop456": "学习工作/办公用品"]
        var prefs = json["preferences"] as! [String: Any]
        prefs["quickCapture"] = ["merchantCategories": [" SHOP789! ": "交通", "merchant123": "日用购物"], "cardAccounts": [:]]
        json["preferences"] = prefs; json["classificationMemory"] = ["fresh123": "娱乐旅行/旅行住宿"]
        let result = try decode(json)
        XCTAssertEqual(result.classificationMemory["shop"], "购物/书和文具")
        XCTAssertEqual(result.classificationMemory["old"], "工资奖金/工资")
        XCTAssertEqual(result.classificationMemory["merchant"], "购物/日用百货")
        XCTAssertEqual(result.classificationMemory["fresh"], "旅行/住宿")
        let encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: LedgerCodec.encode(result)) as? [String: Any])
        XCTAssertNil(encoded["categoryMemory"]); XCTAssertNil(encoded["subcategoryMemory"])
        XCTAssertNil(((encoded["preferences"] as? [String: Any])?["quickCapture"] as? [String: Any])?["merchantCategories"])
        XCTAssertEqual(try LedgerCodec.decode(LedgerCodec.encode(result)), result)
    }
    func testSinglePendingMeaningMigratesLegacyFlagAndEmptyButKeepsExplicitOther() throws {
        var ledger = seed(); ledger.categories.append(Category("没分类"))
        ledger.entries = [row(ledger, ""), row(ledger, " \n"), row(ledger, "没分类"), row(ledger), row(ledger, "其他支出"), row(ledger, "其他收入"), row(ledger, "其他支出")]
        ledger.entries[4].classificationReason = "没分类"; ledger.entries[5].nature = .income
        let result = try decode(oldJSON(ledger))
        for entry in result.entries.prefix(5) {
            XCTAssertEqual(entry.category, Classification.pendingCategory)
            XCTAssertTrue(EntryTimeline.isUncategorized(entry)); XCTAssertTrue(SubcategoryClassifier.isUnclassified(entry.category))
            XCTAssertEqual(Classification.displayCategory(entry.category), "没分类")
        }
        XCTAssertFalse(EntryTimeline.isUncategorized(result.entries[5])); XCTAssertFalse(EntryTimeline.isUncategorized(result.entries[6]))
        XCTAssertFalse(SubcategoryClassifier.isUnclassified("其他支出")); XCTAssertFalse(SubcategoryClassifier.isUnclassified("其他收入"))
        XCTAssertFalse(result.categories.contains { Classification.isPending($0.name) })
    }
    func testKeywordGuessingHasBothLevelsAndGoodsServicesAndTicketsAreDistinct() {
        let ledger = seed()
        for (text, main, sub) in [("滴滴", "交通", "打车"), ("京东纸巾", "购物", "日用百货"), ("登山鞋", "购物", "运动户外"), ("买书", "购物", "书和文具"), ("健身房", "娱乐", "运动健身"), ("旅行机票", "交通", "火车飞机"), ("电影会员", "会员订阅", "影音会员"), ("软件订阅", "会员订阅", "软件云服务")] {
            XCTAssertEqual(CategoryGuesser.guess(text, nature: .expense, in: ledger), .init(category: main, subcategory: sub), text)
        }
        XCTAssertEqual(CategoryGuesser.guess("京东淘宝", nature: .expense, in: ledger), .init(category: "购物"))
        XCTAssertEqual(CategoryGuesser.guess("未知商店", nature: .expense, in: ledger), .init(category: "购物", subcategory: "日用百货"))
        XCTAssertNil(CategoryGuesser.guess("未知商户", nature: .expense, in: ledger))
        XCTAssertEqual(CategoryGuesser.guess("工资", nature: .income, in: ledger)?.subcategory, "工资")
    }
    func testMemoryWinsOverKeywordsAndPurposeMerchantTitleUseOneKey() throws {
        var ledger = seed()
        try QuickCapture.remember(merchant: " 滴滴-订单123! ", category: "购物", in: &ledger)
        XCTAssertEqual(QuickCapture.key("滴滴-订单456!"), CategoryMemory.key("滴滴-订单123!"))
        XCTAssertEqual(ManualBookkeeping.guessCategory("滴滴-订单456!", nature: .expense, in: ledger), "购物")
        var entry = row(ledger, title: "咖啡"); entry.quickCapture = .init(merchant: "滴滴-订单789", withoutOpeningApp: true)
        XCTAssertEqual(CategoryGuesser.guess(entry, in: ledger)?.category, "购物")
        entry.purpose = "专门用途"; ledger.classificationMemory["专门用途"] = "餐饮/聚餐"
        XCTAssertEqual(CategoryGuesser.guess(entry, in: ledger), .init(category: "餐饮", subcategory: "聚餐"))
        let pay = try QuickCapture.applePay(merchant: "滴滴-订单456!", amount: "10", card: "卡", date: now, in: &ledger)
        XCTAssertEqual(pay.entry.category, "购物")
    }
    func testUserEditsAcrossManualBulkSubcategoryAndChangeSetTeachAllEntrances() throws {
        var ledger = seed(); ledger.entries = [row(ledger, title: "固定商店123")]
        var edited = ledger.entries[0]; edited.category = "购物"; edited.subcategory = "美妆个护"
        try ManualBookkeeping.edit(edited, in: &ledger)
        XCTAssertEqual(CategoryGuesser.guess("固定商店456", nature: .expense, in: ledger), .init(category: "购物", subcategory: "美妆个护"))
        try SubcategoryClassifier.set("日用百货", entryID: edited.id, in: &ledger)
        guard case .drafts(let drafts) = try QuickCapture.parse("固定商店 10", in: ledger, now: now) else { return XCTFail() }
        try QuickCapture.record(drafts, in: &ledger, now: now)
        XCTAssertEqual(ledger.entries.last?.subcategory, "日用百货")
        try LedgerOperations.bulkEdit([edited.id], category: "餐饮", nature: nil, in: &ledger)
        XCTAssertEqual(ManualBookkeeping.guessCategory("固定商店789", nature: .expense, in: ledger), "餐饮")
        try ChangeSet(source: "问余白", reason: "手选", items: [.setCategory(entry: edited.id, category: "其他支出")]).apply(to: &ledger)
        XCTAssertEqual(CategoryGuesser.guess("固定商店789", nature: .expense, in: ledger), .init(category: "其他支出"))
    }
    func testMealTimeRequiresExistingDiningAndMealTextAndUsesEntryDate() {
        let ledger = seed()
        for (hour, meal) in [(8, "早餐"), (12, "午餐"), (19, "晚餐")] {
            var entry = row(ledger, "餐饮", title: "食堂吃饭"); entry.date = Dates.calendar.date(bySettingHour: hour, minute: 0, second: 0, of: now)!
            XCTAssertEqual(CategoryGuesser.guess(entry, in: ledger)?.subcategory, meal)
        }
        XCTAssertNil(CategoryGuesser.guess(row(ledger, title: "吃饭"), in: ledger)?.subcategory)
        XCTAssertNil(CategoryGuesser.guess(row(ledger, "餐饮", title: "不明商户"), in: ledger)?.subcategory)
        XCTAssertNil(CategoryGuesser.guess(row(ledger, "交通", title: "吃饭"), in: ledger))
        XCTAssertEqual(CategoryGuesser.guess(row(ledger, "餐饮", title: "晚饭"), in: ledger)?.subcategory, "晚餐")
    }
    func testUnknownApplePayAndShortcutStayPendingAndExplicitOtherIsPreserved() throws {
        var ledger = seed()
        let pay = try QuickCapture.applePay(merchant: "不明用途", amount: "10", card: "卡", date: now, in: &ledger)
        XCTAssertEqual(pay.entry.category, Classification.pendingCategory)
        guard case .drafts(let drafts) = try QuickCapture.parse("不明用途 20", in: ledger, now: now) else { return XCTFail() }
        try QuickCapture.record(drafts, in: &ledger, now: now)
        XCTAssertEqual(ledger.entries.last?.category, Classification.pendingCategory)
        for category in ["其他支出", "其他收入"] {
            var entry = row(ledger, category, title: "滴滴工资"); entry.nature = category == "其他收入" ? .income : .expense
            SubcategoryClassifier.classify(&entry, ledger: ledger); XCTAssertEqual(entry.category, category); XCTAssertNil(entry.subcategory)
        }
        let explicit = EntryDraft(date: now, amount: 100, amountConfirmed: true, accountID: ledger.accounts[0].id, title: "滴滴", category: "其他支出")
        try QuickCapture.record([explicit], in: &ledger, now: now)
        XCTAssertEqual(ledger.entries.last?.category, "其他支出"); XCTAssertFalse(ledger.entries.last!.hasNoCaptureCategory)
    }
    func testImportMapsLabelsRecordsAliasesAndNeverCreatesAMain() throws {
        var ledger = seed(); let before = ledger.categories
        let bytes = Data("日期,金额,收支,用途,分类\n2026-10-20,10,支出,不明甲,餐饮美食\n2026-10-20,10,支出,不明乙,交通出行\n2026-10-20,10,支出,不明丙,私人名目\n2026-10-20,10,支出,不明丁,书和文具\n".utf8)
        let preview = try BillImporter.preview(data: bytes, filename: "分类.csv", accountID: ledger.accounts[0].id, ledger: ledger)
        XCTAssertEqual(preview.selectedEntries.map(\.category), ["餐饮", "交通", Classification.pendingCategory, "购物"])
        XCTAssertEqual(preview.selectedEntries.last?.subcategory, "书和文具")
        _ = try BillImporter.commit(preview, data: bytes, to: &ledger)
        XCTAssertEqual(ledger.categories, before)
        XCTAssertEqual(ledger.categoryAliases["餐饮美食"], "餐饮"); XCTAssertEqual(ledger.categoryAliases["交通出行"], "交通")
        XCTAssertNil(ledger.categoryAliases["私人名目"])
    }
    func testImportCreatesOnlyConfirmedMainsAndUsesSourceDirections() throws {
        var ledger = seed(); let before = ledger.categories
        ledger.classificationMemory["滴滴"] = "交通/打车"
        let bytes = Data("日期,金额,收支,性质,用途,分类\n2026-10-20,10,支出,,滴滴,私人名目\n2026-10-20,20,支出,,不明甲,私人名目\n2026-10-20,30,收入,,不明乙,个人进账\n2026-10-20,40,收入,退款,退回,退款名目\n2026-10-20,50,支出,,不明丙,未确认名目\n".utf8)
        let names: Set<String> = ["私人名目", "个人进账", "退款名目"]
        let preview = try BillImporter.preview(data: bytes, filename: "分类.csv", accountID: ledger.accounts[0].id,
            ledger: ledger, categoryMappings: Dictionary(uniqueKeysWithValues: names.map { ($0, $0) }))
        XCTAssertEqual(preview.selectedEntries.first?.category, "交通")
        XCTAssertEqual(preview.selectedEntries.first?.subcategory, "打车")
        let batch = try BillImporter.commit(preview, data: bytes, confirmedNewCategories: names, to: &ledger)
        XCTAssertEqual(batch.importedCount, 5)
        XCTAssertEqual(ledger.categories.count, before.count + 3)
        XCTAssertEqual(ledger.categories.prefix(before.count), before[...])
        XCTAssertEqual(ledger.entries.map(\.category), ["私人名目", "私人名目", "个人进账", "退款名目", Classification.pendingCategory])
        XCTAssertEqual(ledger.categories.first { $0.name == "私人名目" }?.income, false)
        XCTAssertEqual(ledger.categories.first { $0.name == "个人进账" }?.income, true)
        XCTAssertEqual(ledger.categories.first { $0.name == "退款名目" }?.income, false)
        XCTAssertTrue(ledger.entries.prefix(4).allSatisfy { $0.userEdited && $0.subcategory == nil })
        XCTAssertEqual(ledger.classificationMemory["滴滴"], "私人名目")
        XCTAssertFalse(ledger.categories.contains { $0.name == "未确认名目" })
        XCTAssertEqual(ledger.entries.map(\.fingerprint), preview.selectedEntries.map(\.fingerprint))
        XCTAssertEqual(ledger.entries.map(\.amount), preview.selectedEntries.map(\.amount))
        XCTAssertEqual(ledger.entries.map(\.nature), preview.selectedEntries.map(\.nature))
        try ledger.validate()
    }
    func testImportMappingAloneNeverCreatesMain() throws {
        let bytes = Data("日期,金额,收支,用途,分类\n2026-10-20,10,支出,不明用途,私人名目\n".utf8)
        for target in ["私人名目", "其他支出"] {
            var ledger = seed(); let before = ledger.categories
            let preview = try BillImporter.preview(data: bytes, filename: "分类.csv", accountID: ledger.accounts[0].id,
                ledger: ledger, categoryMappings: ["私人名目": target])
            XCTAssertEqual(preview.selectedEntries.first?.userEdited, true)
            _ = try BillImporter.commit(preview, data: bytes, to: &ledger)
            XCTAssertEqual(ledger.categories, before)
            XCTAssertEqual(ledger.entries.first?.category, target == "私人名目" ? Classification.pendingCategory : target)
        }
    }
    func testImportNewMainsUseSelectedRowsAndIgnoreUnselectedOrUnrelatedNames() throws {
        var ledger = seed(); let before = ledger.categories
        let bytes = Data("日期,金额,收支,用途,分类\n2026-10-20,10,支出,不明甲,个人进账\n2026-10-20,20,收入,不明乙,个人进账\n2026-10-20,30,支出,不明丙,不导入名目\n".utf8)
        var preview = try BillImporter.preview(data: bytes, filename: "分类.csv", accountID: ledger.accounts[0].id, ledger: ledger)
        preview.rows[0].included = false; preview.rows[2].included = false
        _ = try BillImporter.commit(preview, data: bytes, confirmedNewCategories: ["个人进账", "不导入名目", "无对应记录"], to: &ledger)
        XCTAssertEqual(ledger.categories.count, before.count + 1)
        XCTAssertEqual(ledger.categories.last?.name, "个人进账")
        XCTAssertEqual(ledger.categories.last?.income, true)
        XCTAssertEqual(ledger.entries.map(\.category), ["个人进账"])
        XCTAssertEqual(ledger.entries.first?.nature, .income)
        XCTAssertEqual(ledger.entries.first?.userEdited, true)
    }
    func testImportNewMainsRejectDuplicateOrInvalidNamesAtomically() throws {
        for name in ["餐饮", "旧名", "其他", "分/类", String(repeating: "长", count: 201), "没分类", " "] {
            var ledger = seed(); ledger.categoryAliases["旧名"] = "交通"
            let before = ledger
            let preview = ImportPreview(filename: "分类.csv", source: "文件", rows: [
                ImportRow(line: 2, entry: row(ledger), status: .ready, message: "", included: true, sourceCategory: "A先建"),
                ImportRow(line: 3, entry: row(ledger), status: .ready, message: "", included: true, sourceCategory: name)
            ], warnings: [])
            XCTAssertThrowsError(try BillImporter.commit(preview, data: Data(), confirmedNewCategories: ["A先建", name], to: &ledger)) { error in
                XCTAssertEqual(error.localizedDescription, ["餐饮", "旧名"].contains(name) ? "分类名称已存在。" : "分类名称无效。")
            }
            XCTAssertEqual(ledger, before, name)
        }
    }
    func testImportNewMainsRollBackWhenEntriesCannotBeCommitted() throws {
        var ledger = seed()
        let bytes = Data("日期,金额,收支,用途,分类\n2026-10-20,10,支出,不明用途,私人名目\n".utf8)
        let preview = try BillImporter.preview(data: bytes, filename: "分类.csv", accountID: ledger.accounts[0].id, ledger: ledger)
        _ = try BillImporter.commit(preview, data: bytes, to: &ledger)
        let before = ledger
        XCTAssertThrowsError(try BillImporter.commit(preview, data: bytes, confirmedNewCategories: ["私人名目"], to: &ledger))
        XCTAssertEqual(ledger, before)
    }
    func testImportNewMainsAreNotCreatedWithoutSelectedEntries() throws {
        var ledger = seed(); let before = ledger
        let bytes = Data("日期,金额,收支,用途,分类\n2026-10-20,10,支出,不明用途,私人名目\n".utf8)
        var preview = try BillImporter.preview(data: bytes, filename: "分类.csv", accountID: ledger.accounts[0].id, ledger: ledger)
        preview.rows[0].included = false
        XCTAssertThrowsError(try BillImporter.commit(preview, data: bytes, confirmedNewCategories: ["私人名目"], to: &ledger))
        XCTAssertEqual(ledger, before)
    }
    func testImportUsesUnifiedMemoryBeforeBillClues() throws {
        var ledger = seed(); ledger.classificationMemory["常去商户"] = "购物/美妆个护"
        let bytes = Data("日期,金额,收支,用途,分类\n2026-10-20,10,支出,常去商户123,餐饮美食\n".utf8)
        let preview = try BillImporter.preview(data: bytes, filename: "分类.csv", accountID: ledger.accounts[0].id, ledger: ledger)
        XCTAssertEqual(preview.selectedEntries.first?.category, "购物"); XCTAssertEqual(preview.selectedEntries.first?.subcategory, "美妆个护")
    }
    func testFixedOrderIgnoresCountsAndSupportsHiddenUnhiddenAndCustom() throws {
        var ledger = seed(); ledger.entries = (0..<10).map { _ in row(ledger, "交通") }
        XCTAssertEqual(ManualBookkeeping.categories(in: ledger, nature: .expense, frequentOnly: true), ["餐饮", "购物", "交通", "居住", "医疗健康"])
        try CategoryModel.add(Category("收藏"), in: &ledger)
        try CategoryModel.setOrder(["收藏", "交通", "餐饮"], in: &ledger)
        try CategoryModel.setHidden(true, category: "交通", in: &ledger)
        XCTAssertEqual(ManualBookkeeping.categories(in: ledger, nature: .expense).prefix(2), ["收藏", "餐饮"])
        try CategoryModel.setHidden(false, category: "交通", in: &ledger)
        XCTAssertEqual(ManualBookkeeping.categories(in: ledger, nature: .expense).prefix(3), ["收藏", "交通", "餐饮"])
        XCTAssertEqual(try LedgerCodec.decode(LedgerCodec.encode(ledger)).preferences.categoryOrder, ["收藏", "交通", "餐饮"])
    }
    func testRenameThenMergeRewriteAllReferencesAndRefunds() throws {
        var ledger = seed(); try CategoryModel.add(Category("收藏", subcategories: ["藏品"], keywords: ["藏品消费"]), in: &ledger)
        var expense = row(ledger, "收藏", "藏品"); expense.purpose = "常用用途"
        var refund = row(ledger, "其他支出"); refund.nature = .refund; refund.relatedEntryID = expense.id; refund.amount = 100
        ledger.entries = [expense, refund]; CategoryMemory.remember(expense, in: &ledger)
        ledger.plans = [Plan(title: "收藏计划", amount: 100, dueDate: now, category: "收藏")]
        var wish = WishItem(title: "藏品", amount: 100); wish.category = "收藏"; wish.subcategory = "藏品"; ledger.wishlist = [wish]
        let area = ProfileArea(title: "收藏", match: .init(categories: ["收藏"], subcategories: ["收藏/藏品"]))
        ledger.profile.generous = [area]; var restraint = area; restraint.id = UUID(); ledger.profile.restrain = [restraint]
        ledger.categoryAliases = ["旧收藏": "收藏"]
        ledger.pendingChanges = [ChangeSet(source: "测试", reason: "待确认", items: [.setCategory(entry: expense.id, category: "收藏"), .addPlan(ledger.plans[0]), .profile(.upsertArea(area, stance: .restrain))])]
        try CategoryModel.setOrder(["收藏", "餐饮"], in: &ledger)
        try CategoryModel.rename("收藏", to: "珍藏", in: &ledger)
        XCTAssertEqual(ledger.entries.map(\.category), ["珍藏", "珍藏"])
        XCTAssertEqual(ledger.resolveCategory("旧收藏"), "珍藏"); XCTAssertEqual(ledger.resolveCategory("收藏"), "珍藏")
        XCTAssertEqual(ledger.plans[0].category, "珍藏"); XCTAssertEqual(ledger.wishlist[0].category, "珍藏")
        XCTAssertEqual(ledger.profile.generous[0].match.subcategories, ["珍藏/藏品"])
        XCTAssertEqual(ledger.classificationMemory["常用用途"], "珍藏/藏品")
        try CategoryModel.merge("珍藏", into: "购物", in: &ledger)
        XCTAssertEqual(ledger.entries.map(\.category), ["购物", "购物"]); XCTAssertEqual(ledger.entries[1].subcategory, "藏品")
        XCTAssertEqual(ledger.plans[0].category, "购物"); XCTAssertEqual(ledger.wishlist[0].category, "购物")
        XCTAssertEqual(ledger.profile.restrain[0].match.categories, ["购物"])
        XCTAssertEqual(ledger.classificationMemory["常用用途"], "购物/藏品")
        XCTAssertEqual(ledger.resolveCategory("旧收藏"), "购物"); XCTAssertEqual(ledger.resolveCategory("收藏"), "购物")
        XCTAssertTrue(ledger.categories.first { $0.name == "购物" }!.subcategories.contains("藏品"))
        if case .setCategory(_, let name) = ledger.pendingChanges[0].items[0] { XCTAssertEqual(name, "购物") } else { XCTFail() }
        XCTAssertEqual(ledger.preferences.categoryOrder, ["购物", "餐饮"])
        XCTAssertEqual(try LedgerCodec.decode(LedgerCodec.encode(ledger)), ledger)
    }
    func testAddRenameDeleteSmallItemsRewritePathsAndMemory() throws {
        var ledger = seed(); try CategoryModel.add(Category("收藏"), in: &ledger)
        try CategoryModel.addSubcategory("书画", to: "收藏", keywords: ["画作"], in: &ledger)
        ledger.entries = [row(ledger, "收藏", "书画")]; ledger.classificationMemory["商店"] = "收藏/书画"
        ledger.profile.generous = [ProfileArea(title: "书画", match: .init(subcategories: ["收藏/书画"]))]
        var wish = WishItem(title: "画", amount: 100); wish.category = "收藏"; wish.subcategory = "书画"; ledger.wishlist = [wish]
        try CategoryModel.renameSubcategory("书画", in: "收藏", to: "艺术", ledger: &ledger)
        XCTAssertEqual(ledger.entries[0].subcategory, "艺术"); XCTAssertEqual(ledger.wishlist[0].subcategory, "艺术")
        XCTAssertEqual(ledger.classificationMemory["商店"], "收藏/艺术")
        XCTAssertEqual(ledger.categoryAssignment(category: "收藏", subcategory: "书画").subcategory, "艺术")
        XCTAssertEqual(CategoryGuesser.guess("画作", nature: .expense, in: ledger)?.subcategory, "艺术")
        try CategoryModel.removeSubcategory("艺术", from: "收藏", in: &ledger)
        XCTAssertNil(ledger.entries[0].subcategory); XCTAssertNil(ledger.wishlist[0].subcategory)
        XCTAssertEqual(ledger.classificationMemory["商店"], "收藏")
        XCTAssertEqual(ledger.profile.generous[0].match.categories, ["收藏"])
        XCTAssertTrue(ledger.profile.generous[0].match.subcategories.isEmpty)
        XCTAssertNil(ledger.categoryAssignment(category: "收藏", subcategory: "书画").subcategory)
    }
    func testInvalidOperationsAreAtomicAndProtectSystemAndOther() throws {
        var ledger = seed()
        for name in ["内部移动", "其他支出", "其他收入"] {
            let before = ledger
            XCTAssertThrowsError(try CategoryModel.rename(name, to: "新名", in: &ledger))
            XCTAssertThrowsError(try CategoryModel.merge(name, into: "购物", in: &ledger))
            XCTAssertEqual(ledger, before)
        }
        let before = ledger
        XCTAssertThrowsError(try CategoryModel.merge("餐饮", into: "工资奖金", in: &ledger))
        XCTAssertThrowsError(try CategoryModel.setHidden(true, category: "内部移动", in: &ledger))
        XCTAssertThrowsError(try CategoryModel.add(Category("购物"), in: &ledger))
        XCTAssertThrowsError(try CategoryModel.addSubcategory("A/B", to: "购物", in: &ledger))
        XCTAssertThrowsError(try CategoryModel.setOrder(["购物", "购物"], in: &ledger))
        XCTAssertEqual(ledger, before)
    }
    func testStatsToolsHabitsAndProfileResolveAliasesAndRefundOriginalConsistently() throws {
        var ledger = seed(); ledger.categoryAliases = ["旧餐饮": "餐饮", "旧工资": "工资奖金"]
        var expense = row(ledger, "旧餐饮", "午餐", title: "食堂"); expense.amount = 1000
        var refund = row(ledger, "交通", "打车"); refund.nature = .refund; refund.relatedEntryID = expense.id; refund.amount = 200
        var income = row(ledger, "旧工资", "工资"); income.nature = .income
        var income2 = income; income2.id = UUID(); income2.category = "工资奖金"
        ledger.entries = [expense, refund, income, income2]
        let interval = DateInterval(start: Dates.day(now), end: Dates.addDays(1, to: now))
        XCTAssertEqual(Finance.review(ledger, from: interval.start, through: interval.end).byCategory.map(\.category), ["餐饮"])
        let flow = Finance.cashFlow(ledger, during: interval)
        XCTAssertEqual(flow.spendingByCategory.first?.amount, 800); XCTAssertEqual(flow.incomeByCategory.count, 1)
        XCTAssertEqual(flow.incomeByCategory.first?.category, "工资奖金")
        XCTAssertEqual(Finance.subcategoryBreakdown(ledger, category: "旧餐饮", during: interval).first?.amount, 800)
        let area = ProfileArea(title: "午餐", match: .init(subcategories: ["餐饮/午餐"]))
        XCTAssertTrue(ButlerCards.matches(area, entry: refund, ledger: ledger))
        XCTAssertEqual(ProfileHabits.summary(ledger, now: now).first { $0.kind == .category }?.title, "餐饮")
        let context = ToolContext(ledger: ledger, now: now)
        let result = try ReadOnlyTool.queryEntries.run(.object(["category": .string("餐饮"), "subcategory": .string("午餐")]), context)
        XCTAssertEqual(result["entries"]?.arrayValue?.count, 2)
        XCTAssertTrue(result["entries"]!.arrayValue!.allSatisfy { $0["category"] == .string("餐饮") && $0["subcategory"] == .string("午餐") })
    }
    func testDailyAIOnlyChangesPendingMainAndCanLeaveSmallItemEmpty() async throws {
        var ledger = seed(); ledger.entries = [row(ledger), row(ledger, "其他支出", title: "滴滴"), row(ledger, "其他收入", title: "工资")]
        ledger.entries[2].nature = .income
        XCTAssertEqual(SubcategoryBatch.pending(ledger).map(\.id), [ledger.entries[0].id])
        let reply = "{\"items\":[{\"id\":\"\(ledger.entries[0].id)\",\"category\":\"其他支出\",\"subcategory\":null}]}"
        let transport = ScriptedChatTransport([ChatMessage(role: .assistant, content: reply)])
        let result = try await SubcategoryBatch.run(transport: transport, ledger: ledger, now: now)
        try result.apply(to: &ledger, now: now)
        XCTAssertEqual(ledger.entries.map(\.category), ["其他支出", "其他支出", "其他收入"])
        XCTAssertTrue(ledger.entries.allSatisfy { $0.subcategory == nil })
    }
    func testAIRejectsChangingKnownMainAndHidesSystemAndHiddenInPayload() async throws {
        var ledger = seed(); ledger.entries = [row(ledger, "餐饮")]
        try CategoryModel.setHidden(true, category: "购物", in: &ledger)
        let reply = "{\"items\":[{\"id\":\"\(ledger.entries[0].id)\",\"category\":\"交通\",\"subcategory\":\"打车\"}]}"
        let transport = ScriptedChatTransport([ChatMessage(role: .assistant, content: reply)])
        do { _ = try await SubcategoryBatch.run(transport: transport, ledger: ledger, now: now); XCTFail() } catch { }
        let requests = await transport.recorded()
        let table = try JSONValue.parse(requests[0].messages.last!.content!)["categories"]!.arrayValue!
        XCTAssertFalse(table.contains { $0["category"] == .string("内部移动") || $0["category"] == .string("购物") })
    }
    func testImportOrganizerCannotChangeExplicitOtherEvenWithHostileModel() async throws {
        var ledger = seed(); ledger.entries = [row(ledger, "其他支出", title: "滴滴")]
        let id = ledger.entries[0].id
        let reply = "{\"rows\":[{\"entry\":\"\(id)\",\"category\":\"交通\",\"nature\":\"expense\",\"confident\":true}],\"items\":[{\"kind\":\"set_category\",\"entry\":\"\(id)\",\"category\":\"餐饮\"}]}"
        let transport = ScriptedChatTransport([ChatMessage(role: .assistant, content: reply), ChatMessage(role: .assistant, content: "{}")])
        let result = try await ImportOrganizer(transport: transport).organize(ledger: ledger, entryIDs: [id], now: now)
        XCTAssertFalse(result.changeSet.items.contains { if case .setCategory = $0 { return true }; return false })
        XCTAssertEqual(ledger.entries[0].category, "其他支出")
    }
    func testReviewedDraftTeachesMemoryButAutomaticDraftDoesNotAndOldDraftDecodes() throws {
        var ledger = seed()
        guard case .drafts(let automatic) = try QuickCapture.parse("滴滴 10", in: ledger, now: now) else { return XCTFail() }
        XCTAssertEqual(automatic[0].subcategory, "打车")
        try QuickCapture.record(automatic, in: &ledger, now: now)
        XCTAssertTrue(ledger.classificationMemory.isEmpty)
        var reviewed = EntryDraft(date: now, amount: 100, amountConfirmed: true, accountID: ledger.accounts[0].id, title: "常用商店", category: "购物", subcategory: "美妆个护")
        reviewed.categoryUserEdited = true
        try ChangeSet(source: "问余白", reason: "用户核对", items: [.addEntry(reviewed)]).apply(to: &ledger)
        XCTAssertEqual(ledger.classificationMemory["常用商店"], "购物/美妆个护")
        let pay = try QuickCapture.applePay(merchant: "常用商店", amount: "10", card: "卡", date: now, in: &ledger)
        XCTAssertEqual(pay.entry.subcategory, "美妆个护")
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(reviewed)) as? [String: Any])
        json.removeValue(forKey: "subcategory"); json.removeValue(forKey: "categoryUserEdited")
        let old = try JSONDecoder().decode(EntryDraft.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(old.subcategory); XCTAssertNil(old.categoryUserEdited)
    }
    func testCompatibilityMemoryProjectionKeepsOtherSmallItemsAndSelectionFiltersCurrentSystem() throws {
        var ledger = seed(); ledger.classificationMemory = ["商店": "购物/日用百货"]
        ledger.categoryMemory["餐厅"] = "餐饮"
        XCTAssertEqual(ledger.classificationMemory["商店"], "购物/日用百货")
        XCTAssertEqual(ledger.resolveCategory("购物/日用百货"), "购物")
        XCTAssertFalse(ledger.categoryNames(including: "内部移动").contains("内部移动"))
        try CategoryModel.setHidden(true, category: "购物", in: &ledger)
        XCTAssertFalse(ledger.categoryNames(including: "购物").contains("购物"))
        XCTAssertNil(CategoryGuesser.guess("商店", nature: .expense, in: ledger))
    }

    func testDailyBatchAppliesUnifiedUserMemoryBeforeAskingAI() async throws {
        var ledger = seed(); ledger.entries = [row(ledger, title: "滴滴")]
        ledger.classificationMemory["滴滴"] = "购物/日用百货"
        let transport = ScriptedChatTransport([])
        let result = try await SubcategoryBatch.run(transport: transport, ledger: ledger, now: now)
        XCTAssertEqual(result.choices[ledger.entries[0].id], .init(category: "购物", subcategory: "日用百货"))
        let requests = await transport.recorded(); XCTAssertTrue(requests.isEmpty)
        try result.apply(to: &ledger, now: now)
        XCTAssertEqual(ledger.entries[0].category, "购物"); XCTAssertEqual(ledger.entries[0].subcategory, "日用百货")
    }

}
