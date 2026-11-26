import XCTest

/// 常用: long-press 记一笔, one tap records with undo, 编辑常用 opens the list.
final class OftenMenuTests: YubaiUITestCase {
    private let app = XCUIApplication()

    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws { app.terminate(); try super.tearDownWithError() }

    private func launch() {
        app.launchArguments = ["--test-ledger", UUID().uuidString, "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launchEnvironment["YUBAI_UI_TEST_SCRIPT"] = "ask"
        app.launchEnvironment["DEEPSEEK_API_KEY"] = ""
        XCTAssertTrue(launchApp(app))
    }

    private func any(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    private func openMenu() {
        let entry = any("addEntry")
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        entry.press(forDuration: 0.8)
        XCTAssertTrue(any("quickRepeatMenu").waitForExistence(timeout: 5))
    }

    func testLongPressRecordsAndUndoes() {
        launch()
        openMenu()
        XCTAssertTrue(any("quickRepeat_0").label.contains("午饭"))
        any("quickRepeat_0").tap()
        XCTAssertTrue(waitForDisappearance(any("quickRepeatMenu")))
        XCTAssertTrue(any("undoLastChange").waitForExistence(timeout: 5))
        XCTAssertFalse(any("entrySheet").exists, "a long press is not a tap on 记一笔")
    }

    func testEditOftenOpensTheList() {
        launch()
        openMenu()
        any("manageQuickRepeats").tap()
        XCTAssertTrue(any("frequentEntriesPage").waitForExistence(timeout: 5))
    }
}
