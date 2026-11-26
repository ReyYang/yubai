import XCTest

/// 设置 · 心愿与回顾 routes to its three pages; 导入记录 → 导入账单 opens import.
final class SettingsHubTests: YubaiUITestCase {
    private let app = XCUIApplication()

    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws { app.terminate(); try super.tearDownWithError() }

    private func launch(_ fixture: String) {
        app.launchArguments = ["-YubaiSettingsFixture", fixture, "-YubaiTheme", "light",
                               "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launchEnvironment["YUBAI_GALLERY_HIDE_AMOUNTS"] = "0"
        XCTAssertTrue(launchApp(app))
    }

    private func any(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
    private func tap(_ id: String) { tapControl(control(id, in: app), in: app) }

    func testHubRowsOpenTheirPages() {
        launch("main")
        XCTAssertTrue(any("openWishesHub").waitForExistence(timeout: 8))
        XCTAssertTrue(any("openWishesHub").label.contains("2 件心愿"))
        tap("openWishesHub")
        XCTAssertTrue(any("wishesHubPage").waitForExistence(timeout: 5))
        for (row, page) in [("openWishlist", "wishlistPage"), ("openWeekly", "weeklyReviewPage"), ("openProfile", "profilePage")] {
            tap(row)
            XCTAssertTrue(any(page).waitForExistence(timeout: 5), page)
            tap("BackButton")
            XCTAssertTrue(any("wishesHubPage").waitForExistence(timeout: 5))
        }
    }

    func testImportHistoryOpensImport() {
        launch("main")
        tap("openImportHistory")
        tap("importBills")
        XCTAssertTrue(any("importPage").waitForExistence(timeout: 5))
    }
}
