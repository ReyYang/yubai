import XCTest

final class Round46AddEntryFlowTests: YubaiUITestCase {
    private var app = XCUIApplication()
    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws { app.terminate(); try super.tearDownWithError() }
    private func launch(_ script: String = "v46-entry", explicit: Bool = true, large: Bool = false, key: Bool = true) {
        app = XCUIApplication()
        app.launchArguments = ["--test-ledger", UUID().uuidString, "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launchEnvironment["YUBAI_UI_TEST_SCRIPT"] = script
        app.launchEnvironment["YUBAI_UI_TEST_CONFIGURED_KEY"] = key ? "1" : "0"
        app.launchEnvironment["YUBAI_UI_TEST_KEEP_UNDO"] = "1"
        app.launchEnvironment["YUBAI_UI_TEST_ENTRY_EXPLICIT_FINISH"] = explicit ? "1" : "0"
        app.launchEnvironment["DEEPSEEK_API_KEY"] = ""
        launchApp(app)
        XCTAssertTrue(element("mainNavigation").waitForExistence(timeout: 10))
    }
    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
    private func prefix(_ id: String) -> XCUIElement { app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", id)).firstMatch }
    private func tap(_ id: String) {
        let target = element(id)
        XCTAssertTrue(target.exists || target.waitForExistence(timeout: 5), id)
        XCTAssertTrue(target.isHittable, id); target.tap()
    }
    private func keys(_ text: String) { for key in text { tap("keypad_" + String(key)) } }
    private func purpose(_ text: String) {
        let field = app.textFields["entryPurpose"]; tap("entryPurpose"); field.typeText(text + "\n")
    }
    private func record(_ amount: String, category: String = "餐饮") {
        keys(amount); tap("entryCategory_" + category); tap("saveQuickEntry")
        XCTAssertTrue(element("entrySavedReceipt").waitForExistence(timeout: 3))
    }
    private func wait(_ condition: @escaping () -> Bool, timeout: TimeInterval = 5) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed)
    }
    private func assertStays(_ id: String, for duration: TimeInterval = 2.5) {
        let absent = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !self.element(id).exists }, object: nil)
        absent.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [absent], timeout: duration), .completed)
    }

    func testSingleEntryClosesAfterReceiptAndDoesNotShowSavedToast() {
        launch(explicit: false); tap("addEntry"); keys("32"); tap("entryCategory_餐饮"); tap("saveQuickEntry")
        wait { !self.element("entrySessionSummary").exists && self.element("addEntry").isHittable }
        XCTAssertFalse(element("toastMessage").exists)
        XCTAssertTrue(element("availableFunds").label.contains("1,532.00"))
    }
    func testNextDigitCancelsTheTwoSecondClose() {
        launch(explicit: false); tap("addEntry"); keys("32"); tap("saveQuickEntry")
        tap("keypad_8")
        XCTAssertEqual(element("entryKeypadAmount").value as? String, "8.00")
        XCTAssertTrue(element("saveQuickEntry").exists); assertStays("entrySessionSummary")
        tap("saveQuickEntry")
        wait { !self.element("entrySessionSummary").exists && self.element("addEntry").isHittable }
    }
    func testExplicitFinishRetainsCategoryDateAndAccountAcrossEntries() {
        launch(); tap("addEntry"); tap("entryDate_yesterday"); record("32")
        XCTAssertEqual(app.buttons["cancelManualSheet"].label, "完成")
        XCTAssertEqual(element("entryKeypadAmount").value as? String, "0.00")
        assertStays("entrySessionSummary")
        keys("8"); XCTAssertTrue(app.buttons["entryCategory_餐饮"].isSelected)
        XCTAssertTrue(app.buttons["entryDate_yesterday"].isSelected)
        XCTAssertEqual(app.buttons["entryAccountChip"].value as? String, "招行储蓄卡")
        tap("saveQuickEntry"); wait { self.element("entrySessionSummary").label.contains("已记 2 笔") }
        XCTAssertTrue(element("entrySessionSummary").label.contains("40.00")); XCTAssertFalse(element("toastMessage").exists)
        tap("cancelManualSheet"); wait { self.element("addEntry").isHittable }
    }
    func testSessionEditsOneEntryAndRestoresTheUnfinishedDraft() {
        launch(); tap("addEntry"); purpose("咖啡"); record("32")
        keys("8"); tap("entrySessionSummary"); prefix("editSessionEntry_").tap()
        XCTAssertTrue(app.buttons["saveSessionEdit"].waitForExistence(timeout: 5))
        app.buttons["keypad_⌫"].press(forDuration: 1); keys("28"); tap("saveSessionEdit")
        XCTAssertEqual(element("entryKeypadAmount").value as? String, "8.00")
        XCTAssertTrue(element("entrySessionSummary").label.contains("28.00"))
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'editSessionEntry_' ")).count, 1)
    }
    func testSessionSwipeDeleteAndUndoRefreshTheTotal() {
        launch(); tap("addEntry"); record("32"); tap("entrySessionSummary")
        let row = prefix("editSessionEntry_"); XCTAssertTrue(row.waitForExistence(timeout: 5)); row.swipeLeft()
        let remove = prefix("deleteSessionEntry_"); XCTAssertTrue(remove.waitForExistence(timeout: 5)); remove.tap()
        wait { self.element("entrySessionSummary").label.contains("已记 0 笔") }
        tap("undoLastChange"); wait { self.element("entrySessionSummary").label.contains("已记 1 笔") }
        XCTAssertTrue(element("entrySessionSummary").label.contains("32.00"))
    }
    func testAccountDateAndCategoryPickersReplaceContentInTheSameSheet() {
        launch(); tap("addEntry"); keys("32"); tap("entryAccountChip")
        XCTAssertTrue(element("entryInlineAccounts").exists)
        let choices = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'entryAccountChoice_' "))
        choices.element(boundBy: 1).tap(); XCTAssertEqual(app.buttons["entryAccountChip"].value as? String, "微信零钱")
        app.buttons["entryDate_today"].press(forDuration: 0.8)
        XCTAssertTrue(element("entryInlineCalendar").waitForExistence(timeout: 5))
        tap("entryCalendarMonth"); XCTAssertTrue(element("entryCalendarYearWheel").waitForExistence(timeout: 5))
        tap("entryDateDone")
        tap("entryDateDone"); tap("entryCategoryMore")
        XCTAssertTrue(element("entryMoreManage").exists); XCTAssertFalse(element("saveQuickEntry").exists)
        tap("entryMoreCategory_服饰")
        XCTAssertEqual(element("entryKeypadAmount").value as? String, "32.00")
        XCTAssertTrue(element("saveQuickEntry").exists); XCTAssertLessThanOrEqual(app.sheets.count, 1)
    }
    func testPurposeRecallsFillAllThreeValuesAndHintsStayUnselected() {
        launch(); tap("addEntry"); tap("entryAccountChip")
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'entryAccountChoice_' ")).element(boundBy: 1).tap()
        purpose("剪头发")
        wait { self.element("entryCategory_美容").value as? String == "建议" }
        XCTAssertFalse(app.buttons["entryCategory_美容"].isSelected)
        tap("entryCategory_美容"); XCTAssertTrue(app.buttons["entryCategory_美容"].isSelected)
        tap("entryPurpose"); let field = app.textFields["entryPurpose"]
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 3) + "咖")
        tap("recentPurpose_咖啡豆")
        XCTAssertEqual(field.value as? String, "咖啡豆")
        XCTAssertEqual(element("entryKeypadAmount").value as? String, "128.00")
        XCTAssertTrue(app.buttons["entryCategory_购物"].isSelected)
        XCTAssertEqual(app.buttons["entryAccountChip"].value as? String, "微信零钱")
    }
    func testIncomeHasItsOwnCategoriesAndTransferKeepsSpendableUnchanged() {
        launch(); let before = element("availableFunds").label
        tap("addEntry"); tap("entryNature_income")
        XCTAssertTrue(element("entryCategory_报销").exists); XCTAssertFalse(element("entryCategory_餐饮").exists)
        tap("entryNature_transfer"); keys("500")
        XCTAssertTrue(element("entrySavingHint").label.contains("不变"))
        tap("transferDestinationAccount"); XCTAssertTrue(element("entryInlineAccounts").exists)
        prefix("entryAccountChoice_").tap(); tap("saveQuickEntry"); tap("cancelManualSheet")
        wait { self.element("addEntry").isHittable }
        XCTAssertEqual(element("availableFunds").label, before)
    }
    func testBigPurchaseCanGoToWishAndUndoWithoutRecording() {
        launch("v46-entry-big"); let before = element("availableFunds").label
        tap("addEntry"); keys("1200"); purpose("大衣"); tap("entryCategory_购物")
        XCTAssertTrue(element("bigPurchaseDays").waitForExistence(timeout: 5))
        tap("bigFromReserve"); wait { self.element("entrySavingHint").label.contains("3,800.00") }
        tap("keypad_0")
        XCTAssertFalse(app.buttons["saveQuickEntry"].isEnabled)
        XCTAssertTrue(app.buttons["saveEntryWish"].isEnabled)
        tap("bigFromCycle"); tap("saveEntryWish")
        XCTAssertTrue(element("toastMessage").waitForExistence(timeout: 5)); XCTAssertEqual(element("availableFunds").label, before)
        tap("undoLastChange"); XCTAssertEqual(element("availableFunds").label, before)
    }
    func testReceiptEntryIsHiddenWithoutConfiguredAI() {
        launch("v46-entry-receipt", key: false); app.buttons["addEntry"].press(forDuration: 0.8)
        XCTAssertTrue(element("manageQuickRepeats").waitForExistence(timeout: 5)); XCTAssertFalse(element("quickReceipt").exists)
    }
    func testReceiptRecognizesCategoriesAndSelectionChangesExactSaveCount() {
        launch("v46-entry-receipt"); app.buttons["addEntry"].press(forDuration: 0.8); tap("quickReceipt")
        XCTAssertTrue(element("receiptSummary").waitForExistence(timeout: 10))
        XCTAssertTrue(element("receiptSummary").label.contains("186.40"))
        XCTAssertEqual(app.buttons["receiptCategory_0"].value as? String, "买菜")
        tap("receiptSelect_1"); wait { self.app.buttons["saveReceiptEntries"].value as? String == "2 笔" }
        tap("receiptMode_merged"); wait { self.app.buttons["saveReceiptEntries"].value as? String == "1 笔" }
        tap("receiptCategory_-1"); XCTAssertTrue(element("entryMoreManage").waitForExistence(timeout: 5))
        tap("entryMoreCancel"); XCTAssertTrue(element("receiptSummary").exists)
    }
    func testLargestTypeKeepsShortSegmentsHorizontalAndHiddenAmountPrivate() {
        launch("v46-entry-hard", large: true); tap("toggleAmountVisibility"); tap("addEntry"); keys("1234567.89")
        XCTAssertEqual(element("entryKeypadAmount").value as? String, "金额已隐藏")
        XCTAssertFalse(element("entrySavingHint").label.contains("1,234,567.89"))
        let expense = app.buttons["entryNature_expense"], income = app.buttons["entryNature_income"], transfer = app.buttons["entryNature_transfer"]
        XCTAssertEqual(expense.frame.midY, income.frame.midY, accuracy: 1); XCTAssertEqual(expense.frame.midY, transfer.frame.midY, accuracy: 1)
        XCTAssertTrue(app.buttons["saveQuickEntry"].isHittable)
        XCTAssertLessThanOrEqual(element("entryKeypadAmount").frame.maxX, app.frame.maxX)
    }
}
