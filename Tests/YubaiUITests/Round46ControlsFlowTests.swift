import XCTest

final class Round46ControlsFlowTests: XCTestCase {
    private var app = XCUIApplication()
    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws { app.terminate(); try super.tearDownWithError() }
    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
    private func launch(large: Bool = false, toast: Bool = false, hidden: Bool = false) {
        app.launchArguments = ["--test-ledger", UUID().uuidString, "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN",
                               "-UIPreferredContentSizeCategoryName", large ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL"]
        app.launchEnvironment["YUBAI_UI_TEST_SCRIPT"] = "gallery"
        app.launchEnvironment["YUBAI_UI_TEST_CONFIGURED_KEY"] = "1"
        app.launchEnvironment["YUBAI_UI_TEST_KEEP_UNDO"] = "1"
        app.launchEnvironment["YUBAI_GALLERY_TOAST"] = toast ? "1" : "0"
        app.launchEnvironment["YUBAI_GALLERY_HIDE_AMOUNTS"] = hidden ? "1" : "0"
        app.launchEnvironment["DEEPSEEK_API_KEY"] = ""
        app.launch(); XCTAssertTrue(element("mainNavigation").waitForExistence(timeout: 15))
    }
    private func tap(_ id: String) {
        let target = element(id); XCTAssertTrue(target.waitForExistence(timeout: 6), id)
        for _ in 0..<8 { if target.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(target.isHittable, id); target.tap()
    }
    private func settings(_ id: String) { tap("openSettings"); tap(id) }
    private func keys(_ value: String) { for key in value { tap("keypad_" + String(key)) } }

    func testSettingsHasStableLedgerEntriesAndWeeklyReview() {
        launch(); tap("openSettings")
        for id in ["openAccounts", "openFixedFlows", "openSpendingParts", "openCategories", "openSettingsWeekly"] {
            XCTAssertTrue(element(id).exists, id)
        }
        tap("openSettingsWeekly"); XCTAssertTrue(element("weeklyReviewPage").waitForExistence(timeout: 5))
    }
    func testCategoryDuplicateIsInlineAndCannotBeSaved() {
        launch(); settings("openCategories"); tap("addMainCategory")
        let input = element("newCategoryName"); XCTAssertTrue(input.waitForExistence(timeout: 5)); input.typeText("餐饮")
        XCTAssertTrue(element("inlineFieldError").waitForExistence(timeout: 5))
        XCTAssertFalse(element("saveNewCategory").isEnabled)
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }
    func testCategoryDeletionRequiresADestinationAndKeepsUndo() {
        launch(); settings("openCategories"); tap("manageCategory_餐饮"); tap("deleteMainCategory")
        XCTAssertFalse(element("confirmCategoryMerge").isEnabled)
        tap("mergeInto_其他支出"); tap("confirmCategoryMerge")
        XCTAssertTrue(element("categoriesDirection").waitForExistence(timeout: 5))
        XCTAssertFalse(element("manageCategory_餐饮").exists)
        tap("undoLastChange"); XCTAssertTrue(element("manageCategory_餐饮").waitForExistence(timeout: 5))
    }
    func testAccountMoneyUsesOneSharedKeypadAndCompleteGroupedValue() {
        launch(large: true); settings("openAccounts"); tap("addAccount"); tap("accountBalance")
        let hiddenKeyboard = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !self.app.keyboards.firstMatch.exists }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [hiddenKeyboard], timeout: 5), .completed)
        keys("1234567.89")
        XCTAssertTrue(element("accountBalanceAmount").label.contains("1,234,567.89"))
        XCTAssertEqual(app.buttons.matching(identifier: "keypad_1").count, 1)
        tap("accountBalanceDone"); XCTAssertEqual(element("accountBalance").value as? String, "1,234,567.89")
    }
    func testHiddenStoredBalanceIsRevealedOnlyWhileEditing() {
        launch(hidden: true); settings("openAccounts"); tap("addAccount")
        XCTAssertEqual(element("accountBalance").value as? String, "金额已隐藏")
        tap("accountBalance"); keys("12.34")
        XCTAssertTrue(element("accountBalanceAmount").label.contains("12.34"))
        tap("accountBalanceDone"); XCTAssertEqual(element("accountBalance").value as? String, "金额已隐藏")
    }
    func testLongToastKeepsUndoAndCloseBesideItsText() {
        launch(toast: true)
        let message = element("toastMessage"), undo = element("undoLastChange")
        XCTAssertTrue(message.waitForExistence(timeout: 5)); XCTAssertTrue(undo.isHittable)
        XCTAssertGreaterThanOrEqual(undo.frame.width, 44); XCTAssertGreaterThanOrEqual(undo.frame.height, 44)
        XCTAssertLessThanOrEqual(message.frame.maxX, undo.frame.minX)
        tap("undoLastChange"); XCTAssertEqual(element("toastMessage").label, "已撤销")
    }
    func testAIChildPreferenceSurvivesMasterOffAndOn() {
        launch(); settings("openIntelligencePrivacy"); tap("cloudAIToggle")
        let answers = element("aiFeature_answers")
        XCTAssertTrue(answers.isEnabled); tap("aiFeature_answers")
        XCTAssertEqual(answers.value as? String, "0")
        tap("cloudAIToggle"); XCTAssertFalse(answers.isEnabled)
        tap("cloudAIToggle"); XCTAssertTrue(answers.isEnabled); XCTAssertEqual(answers.value as? String, "0")
    }
    func testBackupPasswordValidationGatesEncryptedExport() {
        launch(); settings("openBackup"); tap("backupToFile")
        element("backupPassword").typeText("123")
        XCTAssertTrue(element("inlineFieldError").exists); XCTAssertFalse(element("exportEncryptedBackup").isEnabled)
        element("backupPassword").typeText("45678")
        XCTAssertTrue(element("exportEncryptedBackup").isEnabled)
    }
}
