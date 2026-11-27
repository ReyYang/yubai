import Foundation
import XCTest
@testable import YubaiCore

/// 编辑分类 · 图标: an optional icon name on a category, old ledgers read as before.
final class CategoryIconTests: XCTestCase {
    func testOldCategoriesDecodeWithoutAnIconAndNilIsNeverWritten() throws {
        let old = #"{"name":"通讯","symbol":"square.grid.2x2","income":false,"subcategories":["话费"]}"#
        let category = try JSONDecoder().decode(Category.self, from: Data(old.utf8))
        XCTAssertNil(category.icon)
        let encoded = String(decoding: try JSONEncoder().encode(category), as: UTF8.self)
        XCTAssertFalse(encoded.contains("\"icon\""))
    }

    func testAMalformedIconIsIgnoredInsteadOfFailingTheLedger() throws {
        let odd = #"{"name":"通讯","symbol":"square.grid.2x2","income":false,"icon":42}"#
        XCTAssertNil(try JSONDecoder().decode(Category.self, from: Data(odd.utf8)).icon)
    }

    func testSetIconRoundTripsAndClears() throws {
        var ledger = Ledger()
        ledger.categories = [Category("通讯"), Category("通讯", income: true)]
        try CategoryModel.setIcon("cat-digital", category: "通讯", income: false, in: &ledger)
        XCTAssertEqual(ledger.categories[0].icon, "cat-digital")
        XCTAssertNil(ledger.categories[1].icon, "only the one direction")
        let decoded = try JSONDecoder().decode(Category.self, from: JSONEncoder().encode(ledger.categories[0]))
        XCTAssertEqual(decoded.icon, "cat-digital")
        try CategoryModel.setIcon("  ", category: "通讯", income: false, in: &ledger)
        XCTAssertNil(ledger.categories[0].icon)
    }
}
