import XCTest
import YubaiCore
@testable import YubaiApp

/// Category icons: one per expense category, explicit picks kept, stable when the list is reordered.
@MainActor
final class CategoryIconTests: XCTestCase {
    private func icons(_ categories: [YubaiCore.Category]) -> [String: DS.Icon] {
        Dictionary(uniqueKeysWithValues: DS.Icon.categoryIcons(categories).filter { !$0.key.income }.map { ($0.key.name, $0.value) })
    }

    func testDefaultCategoriesAllHaveTheirOwnIcon() {
        let table = icons(YubaiCore.Category.defaults)
        let spending = YubaiCore.Category.defaults.filter { !$0.income && !$0.system }.map(\.name)
        let shown = spending.map { table[$0]! }
        XCTAssertEqual(Set(shown).count, shown.count, "no two default expense categories look alike")
        XCTAssertEqual(shown.filter { $0 == .catOther }.count, 1, "only 其他支出 shows the three dots")
        XCTAssertEqual(table["医疗健康"], .catHealth)
        XCTAssertEqual(table["人情家庭"], .catFamily)
    }

    func testTelecomAndDigitalDiffer() {
        let table = icons([YubaiCore.Category("数码"), YubaiCore.Category("通讯")])
        XCTAssertEqual(table["数码"], .catDigital)
        XCTAssertEqual(table["通讯"], .chat)
    }

    func testCollisionsResolveInTheOrderCategoriesWereAddedAndKeepPicks() {
        var picked = YubaiCore.Category("下午茶"); picked.icon = DS.Icon.catFood.rawValue
        let categories = [YubaiCore.Category("吃饭"), YubaiCore.Category("餐饮"), picked,
                          YubaiCore.Category("宠物"), YubaiCore.Category("园艺")]
        let table = icons(categories)
        XCTAssertEqual(table["下午茶"], .catFood, "a hand-picked icon stays even if another category shows it")
        XCTAssertEqual(table["吃饭"], .catFood, "an earlier category may share only with a hand pick")
        let fallbacks = ["餐饮", "宠物", "园艺"].map { table[$0]! }
        XCTAssertEqual(Set(fallbacks).count, 3)
        XCTAssertFalse(fallbacks.contains(.catOther))
        XCTAssertFalse(fallbacks.contains(.catFood))
        // Deterministic: the same ledger gives the same icons; reordering by display order does not reshuffle.
        XCTAssertEqual(icons(categories), table)
    }

    func testRunningOutFallsBackToTheCatchAll() {
        let many = (0..<40).map { YubaiCore.Category("自定义\($0)") }
        let table = icons(many)
        let real = many.compactMap { table[$0.name] }.filter { $0 != .catOther }
        XCTAssertEqual(Set(real).count, real.count, "no repeats while picks last")
        XCTAssertEqual(table["自定义39"], .catOther)
    }

    func testNewCategoryStoresOnlyWhatReadingWouldNotGive() {
        var ledger = Ledger()
        ledger.categories = YubaiCore.Category.defaults
        XCTAssertNil(DS.Icon.newCategoryIcon(name: "咖啡", income: false, in: ledger), "咖啡 means a cup no one shows")
        let stored = DS.Icon.newCategoryIcon(name: "宠物", income: false, in: ledger)
        XCTAssertNotNil(stored)
        XCTAssertNotEqual(stored, DS.Icon.catOther.rawValue)
        XCTAssertNil(DS.Icon.newCategoryIcon(name: "红包", income: true, in: ledger))
    }

    func testCategoriesAddedOneAfterAnotherNeverShareAnIcon() {
        var ledger = Ledger()
        ledger.categories = YubaiCore.Category.defaults
        for name in ["宠物", "咖啡", "园艺", "数码", "通讯"] {
            var added = YubaiCore.Category(name)
            added.icon = DS.Icon.newCategoryIcon(name: name, income: false, in: ledger)
            ledger.categories.append(added)
        }
        let shown = DS.Icon.categoryIcons(ledger.categories).filter { !$0.key.income && $0.key.name != "其他支出" && $0.key.name != "内部移动" }.map(\.value)
        XCTAssertEqual(Set(shown).count, shown.count, "宠物 taking the cup first does not leave 咖啡 with it too")
    }

    func testHomeRowsUseTheLedgerCategoryIcon() {
        let categories = YubaiCore.Category.defaults
        CategoryIcons.configure(categories)
        defer { CategoryIcons.configure([]) }
        let account = Account(name: "卡", at: Dates.now)
        let entry = Entry(date: Dates.now, amount: 100, accountID: account.id, title: "挂号", category: "医疗健康")
        XCTAssertEqual(HomeDisplay.icon(entry, category: categories.first { $0.name == "医疗健康" }, name: "医疗健康"), .catHealth)
    }
}
