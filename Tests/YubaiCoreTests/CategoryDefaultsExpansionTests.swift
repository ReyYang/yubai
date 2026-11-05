import XCTest
@testable import YubaiCore

final class CategoryDefaultsExpansionTests: XCTestCase {
    private let newMains = ["美容个护", "保险税费", "报销", "二手转卖"]
    private let newSubs = ["交通": ["养车"], "餐饮": ["买菜做饭"], "购物": ["烟酒", "快递"],
                           "人情家庭": ["孝敬长辈", "捐赠"], "居住": ["家政保洁"], "工资奖金": ["公积金"]]
    private let oldDailyWords = ["日用", "纸巾", "洗衣", "洗衣液", "超市", "罗森", "便利店", "商店", "百货", "菜市场", "生鲜"]

    private func oldLedger() -> Ledger {
        var ledger = Ledger()
        ledger.defaultCategoriesVersion = nil
        ledger.categories.removeAll { newMains.contains($0.name) }
        for i in ledger.categories.indices {
            let removed = newSubs[ledger.categories[i].name] ?? []
            ledger.categories[i].subcategories.removeAll { removed.contains($0) }
            for sub in removed { ledger.categories[i].subcategoryKeywords.removeValue(forKey: sub) }
            if ledger.categories[i].name == "购物" { ledger.categories[i].subcategoryKeywords["日用百货"] = oldDailyWords }
        }
        ledger.preferences.categoryOrder.removeAll { newMains.contains($0) }
        return ledger
    }
    private func load(_ ledger: Ledger) throws -> Ledger { try LedgerCodec.decode(LedgerCodec.encode(ledger)) }

    func testExpandedDefaultsAndSymbolsPreserveGoodsAndFeeDomains() throws {
        let ledger = Ledger()
        for main in newMains {
            let category = try XCTUnwrap(ledger.categories.first { $0.name == main })
            XCTAssertFalse(category.symbol.isEmpty)
        }
        for (main, subs) in newSubs {
            XCTAssertTrue(Set(subs).isSubset(of: Set(try XCTUnwrap(ledger.categories.first { $0.name == main }).subcategories)))
        }
        XCTAssertEqual(ledger.categories.first { $0.name == "美容个护" }?.subcategories, ["理发", "美容美甲", "洗浴按摩"])
        XCTAssertEqual(ledger.categories.first { $0.name == "保险税费" }?.subcategories, ["保险", "税费"])
        XCTAssertTrue(try XCTUnwrap(ledger.categories.first { $0.name == "购物" }).subcategories.contains("美妆个护"))
        XCTAssertEqual(ledger.categories.first { $0.name == "利息手续费" }, Category("利息手续费", "percent", subcategories: ["手续费", "利息"], subcategoryKeywords: ["手续费": ["手续费"], "利息": ["利息"]]))
        XCTAssertEqual(ledger.preferences.categoryOrder, Category.defaults.filter { !$0.system }.map(\.name))
        try ledger.validate()
    }

    func testLongestMatchSeparatesServicesGoodsHotelAndGroceries() {
        let cases = ["美容个护/理发": ["理发店", "造型", "美发", "剪发", "烫发", "染发"],
                     "美容个护/美容美甲": ["美甲", "美容", "美睫"], "美容个护/洗浴按摩": ["洗浴", "按摩", "足疗", "spa", "汗蒸"],
                     "旅行/住宿": ["酒店", "酒店住宿"], "购物/烟酒": ["烟", "香烟", "白酒", "啤酒"],
                     "餐饮/买菜做饭": ["菜市场", "生鲜", "买菜", "叮咚买菜"], "购物/美妆个护": ["洗发", "护肤"],
                     "购物/快递": ["快递", "顺丰", "邮费", "运费", "寄件"], "交通/养车": ["保养", "洗车", "违章", "交通罚款", "年检", "4s"],
                     "保险税费/保险": ["保险", "保费", "人寿", "车险", "医疗险"], "保险税费/税费": ["个税", "缴税", "纳税", "印花税", "契税"],
                     "人情家庭/孝敬长辈": ["孝敬长辈"], "人情家庭/捐赠": ["捐款", "捐赠", "公益"],
                     "居住/家政保洁": ["家政", "保洁", "钟点工", "清洁"]]
        for (path, words) in cases {
            for word in words { XCTAssertEqual(CategoryGuesser.guess(word, nature: .expense, in: Ledger())?.path, path, word) }
        }
        XCTAssertNil(CategoryGuesser.guess("罚款", nature: .expense, in: Ledger()))
        XCTAssertNil(CategoryGuesser.guess("盒马", nature: .expense, in: Ledger()))
        // A longer goods phrase must outrank the shorter service word “造型”.
        var custom = Ledger()
        custom.categories[custom.categories.firstIndex { $0.name == "购物" }!].subcategoryKeywords["美妆个护", default: []].append("造型喷雾")
        XCTAssertEqual(CategoryGuesser.guess("造型喷雾", nature: .expense, in: custom)?.path, "购物/美妆个护")
    }

    func testIncomeEvidenceIsConstrainedByDirection() {
        for (text, path) in [("差旅报销", "报销"), ("报销", "报销"), ("闲鱼", "二手转卖"), ("转转", "二手转卖"),
                             ("二手", "二手转卖"), ("回收", "二手转卖"), ("公积金提取", "工资奖金/公积金"), ("住房公积金", "工资奖金/公积金")] {
            XCTAssertEqual(CategoryGuesser.guess(text, nature: .income, in: Ledger())?.path, path)
            XCTAssertNil(CategoryGuesser.guess(text, nature: .expense, in: Ledger()))
        }
    }

    func testOldLedgerAddsNewDefaultsOnceWithoutSchemaBump() throws {
        let original = oldLedger()
        let migrated = try load(original)
        for main in newMains { XCTAssertTrue(migrated.categories.contains { $0.name == main }, main) }
        for (main, subs) in newSubs {
            let category = try XCTUnwrap(migrated.categories.first { $0.name == main })
            XCTAssertTrue(Set(subs).isSubset(of: Set(category.subcategories)))
        }
        XCTAssertEqual(migrated.defaultCategoriesVersion, CategoryMigration.currentDefaultsVersion)
        XCTAssertEqual(migrated.schema, 4)
        XCTAssertEqual(try load(migrated), migrated)
        let encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: LedgerCodec.encode(migrated)) as? [String: Any])
        XCTAssertEqual(encoded["defaultCategoriesVersion"] as? Int, 2)
        XCTAssertEqual(migrated.id, original.id); XCTAssertEqual(migrated.entries, original.entries)
    }

    func testHiddenAndAliasSourceTargetPathsAreNeverOffered() throws {
        var old = oldLedger()
        old.categories.append(Category("美容个护", hidden: true))
        old.categoryAliases = ["保险税费": "其他支出", "旧报销": "报销", "二手转卖/旧小项": "其他收入",
                               "交通/养车": "交通/加油停车", "购物/旧寄送": "购物/快递", "人情家庭/捐赠": "人情家庭"]
        let migrated = try load(old)
        XCTAssertEqual(migrated.categories.first { $0.name == "美容个护" }, Category("美容个护", hidden: true))
        for main in ["保险税费", "报销", "二手转卖"] { XCTAssertFalse(migrated.categories.contains { $0.name == main }) }
        XCTAssertFalse(try XCTUnwrap(migrated.categories.first { $0.name == "交通" }).subcategories.contains("养车"))
        XCTAssertFalse(try XCTUnwrap(migrated.categories.first { $0.name == "购物" }).subcategories.contains("快递"))
        XCTAssertFalse(try XCTUnwrap(migrated.categories.first { $0.name == "人情家庭" }).subcategories.contains("捐赠"))
        XCTAssertEqual(migrated.categoryAliases, old.categoryAliases)
        XCTAssertEqual(try load(migrated), migrated)
    }

    func testSchema3UpgradeAlsoProtectsExpansionAliasesAndMovesUntouchedWords() throws {
        var old = oldLedger()
        old.categories.append(Category("个人护理"))
        old.categoryAliases = ["美容个护": "个人护理", "保险税费": "其他支出", "交通/养车": "交通/加油停车"]
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: LedgerCodec.encode(old)) as? [String: Any])
        json["schema"] = 3
        let migrated = try LedgerCodec.decode(JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(migrated.schema, 4); XCTAssertEqual(migrated.defaultCategoriesVersion, 2)
        XCTAssertFalse(migrated.categories.contains { $0.name == "美容个护" || $0.name == "保险税费" })
        XCTAssertTrue(migrated.categories.contains { $0.name == "报销" }); XCTAssertTrue(migrated.categories.contains { $0.name == "二手转卖" })
        XCTAssertFalse(try XCTUnwrap(migrated.categories.first { $0.name == "交通" }).subcategories.contains("养车"))
        let words = try XCTUnwrap(migrated.categories.first { $0.name == "购物" }?.subcategoryKeywords["日用百货"])
        XCTAssertFalse(words.contains("菜市场")); XCTAssertFalse(words.contains("生鲜"))
        XCTAssertEqual(ManualBookkeeping.categories(in: migrated, nature: .expense).last, "其他支出")
        XCTAssertEqual(try load(migrated), migrated)
    }

    func testRenamedMergedDeletedDefaultsStayGoneEvenWhenVersionIsMissing() throws {
        var ledger = Ledger()
        try CategoryModel.rename("美容个护", to: "护理服务", in: &ledger)
        try CategoryModel.merge("保险税费", into: "其他支出", in: &ledger)
        try CategoryModel.merge("二手转卖", into: "其他收入", in: &ledger)
        try CategoryModel.renameSubcategory("养车", in: "交通", to: "车辆维护", ledger: &ledger)
        try CategoryModel.removeSubcategory("快递", from: "购物", in: &ledger)
        ledger.defaultCategoriesVersion = nil
        let migrated = try load(ledger)
        for main in ["美容个护", "保险税费", "二手转卖"] { XCTAssertFalse(migrated.categories.contains { $0.name == main }) }
        XCTAssertTrue(migrated.categories.contains { $0.name == "护理服务" })
        XCTAssertFalse(try XCTUnwrap(migrated.categories.first { $0.name == "交通" }).subcategories.contains("养车"))
        XCTAssertFalse(try XCTUnwrap(migrated.categories.first { $0.name == "购物" }).subcategories.contains("快递"))
    }

    func testSeenVersionPreventsLaterDeletionWithoutAliasesFromReturning() throws {
        var ledger = try load(oldLedger())
        ledger.categories.removeAll { $0.name == "美容个护" }
        let i = try XCTUnwrap(ledger.categories.firstIndex { $0.name == "交通" })
        ledger.categories[i].subcategories.removeAll { $0 == "养车" }
        ledger.categories[i].subcategoryKeywords.removeValue(forKey: "养车")
        let loaded = try load(ledger)
        XCTAssertFalse(loaded.categories.contains { $0.name == "美容个护" })
        XCTAssertFalse(try XCTUnwrap(loaded.categories.first { $0.name == "交通" }).subcategories.contains("养车"))
        XCTAssertEqual(loaded, ledger)
    }

    func testMissingBaselineDefaultsAreNotResurrectedAndHiddenParentsStayUntouched() throws {
        var ledger = oldLedger()
        ledger.categories.removeAll { $0.name == "娱乐" }
        let i = try XCTUnwrap(ledger.categories.firstIndex { $0.name == "交通" })
        ledger.categories[i].hidden = true
        let result = try load(ledger)
        XCTAssertFalse(result.categories.contains { $0.name == "娱乐" })
        XCTAssertFalse(try XCTUnwrap(result.categories.first { $0.name == "交通" }).subcategories.contains("养车"))
    }

    func testCustomOrderRemainsRelativeAndNewMainsFollowDefaultNeighbours() throws {
        var ledger = oldLedger()
        ledger.categories += [Category("收藏"), Category("副业", income: true)]
        ledger.preferences.categoryOrder = ["收藏", "旅行", "医疗健康", "餐饮", "购物", "交通", "居住", "娱乐", "会员订阅", "学习成长", "利息手续费", "人情家庭", "工资奖金", "副业", "兼职劳务", "礼金赠与", "投资收益", "其他支出", "其他收入"]
        let result = try load(ledger)
        let order = result.preferences.categoryOrder
        XCTAssertEqual(order.filter { !newMains.contains($0) }, ["收藏", "旅行", "医疗健康", "餐饮", "购物", "交通", "居住", "娱乐", "会员订阅", "学习成长", "利息手续费", "人情家庭", "其他支出", "工资奖金", "副业", "兼职劳务", "礼金赠与", "投资收益", "其他收入"])
        XCTAssertEqual(order[try XCTUnwrap(order.firstIndex(of: "医疗健康")) + 1], "美容个护")
        XCTAssertEqual(order[try XCTUnwrap(order.firstIndex(of: "人情家庭")) + 1], "保险税费")
        XCTAssertEqual(Array(order.suffix(3)), ["报销", "二手转卖", "其他收入"])
        XCTAssertEqual(ManualBookkeeping.categories(in: result, nature: .expense).last, "其他支出")
        XCTAssertEqual(ManualBookkeeping.categories(in: result, nature: .income).last, "其他收入")
    }

    func testOrderFallsBackToFollowingNeighbourWithoutPrependingCustomItems() throws {
        var ledger = oldLedger()
        ledger.categories.append(Category("收藏"))
        ledger.preferences.categoryOrder = ["收藏", "娱乐", "其他支出", "其他收入"]
        let order = try load(ledger).preferences.categoryOrder
        XCTAssertEqual(Array(order.prefix(3)), ["收藏", "美容个护", "娱乐"])
    }

    func testKeywordMoveOnlyRemovesFromUntouchedDefaultList() throws {
        for custom in [false, true] {
            var ledger = oldLedger()
            let i = try XCTUnwrap(ledger.categories.firstIndex { $0.name == "购物" })
            if custom { ledger.categories[i].subcategoryKeywords["日用百货"]!.append("用户指定词") }
            let result = try load(ledger)
            let words = try XCTUnwrap(result.categories.first { $0.name == "购物" }?.subcategoryKeywords["日用百货"])
            XCTAssertEqual(words.contains("菜市场"), custom); XCTAssertEqual(words.contains("生鲜"), custom)
            XCTAssertEqual(words.contains("用户指定词"), custom)
            XCTAssertEqual(CategoryGuesser.guess("菜市场", nature: .expense, in: result)?.path, "餐饮/买菜做饭")
        }
    }

    func testBothPromptsUseExpandedRealCategoriesAndFollowRenames() throws {
        var ledger = Ledger()
        for party in [true, false] {
            let prompt = ImportOrganizer.prompt(for: ledger, byParty: party)
            for path in ["美容个护/理发", "保险税费/保险", "保险税费/税费", "餐饮/买菜做饭", "报销", "二手转卖"] { XCTAssertTrue(prompt.contains("→" + path), path) }
            XCTAssertFalse(prompt.contains("保险公司→其他支出"))
        }
        try CategoryModel.rename("美容个护", to: "个人护理", in: &ledger)
        try CategoryModel.setHidden(true, category: "保险税费", in: &ledger)
        try CategoryModel.merge("二手转卖", into: "其他收入", in: &ledger)
        for party in [true, false] {
            let prompt = ImportOrganizer.prompt(for: ledger, byParty: party)
            XCTAssertTrue(prompt.contains("→个人护理/理发"))
            XCTAssertFalse(prompt.contains("→美容个护")); XCTAssertFalse(prompt.contains("→保险税费")); XCTAssertFalse(prompt.contains("→二手转卖"))
        }
    }
}
