import XCTest

final class Batch2HomeRebuildTests: YubaiUITestCase {
    private let app = XCUIApplication()

    override func setUpWithError() throws { continueAfterFailure = false }

    override func tearDownWithError() throws {
        app.terminate()
        try super.tearDownWithError()
    }

    private func launch(_ flag: String, _ fixture: String, menu: Bool = false) {
        app.launchArguments = [flag, fixture, "-YubaiTheme", "light", "-YubaiLogHomeRenderCounts",
                               "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        if menu { app.launchArguments.append("-YubaiBillMenu") }
        launchApp(app)
    }

    private func wait(_ id: String, type: XCUIElement.ElementType = .any) -> XCUIElement {
        let element = app.descendants(matching: type).matching(identifier: id).firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: 8), id)
        return element
    }

    /// Spec-Gestures 下拉收起 from on top of a key: the sheet takes the drag and the key never types.
    func testSheetDragFromAKeyClosesWithoutTyping() {
        launch("-YubaiHomeFixture", "normal")
        tapControl(control("addEntry", in: app), in: app)
        let key = wait("keypad_5", type: .button)
        XCTAssertTrue(waitForStableFrame(key))
        let start = key.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 420)))
        XCTAssertTrue(UIConditionWait.run(timeout: 5, read: { !self.app.buttons["keypad_5"].exists }), "sheet did not close")
        tapControl(control("addEntry", in: app), in: app)
        let amount = wait("entryKeypadAmount")
        XCTAssertFalse(amount.value.map { "\($0)".contains("5") } ?? false, "the key under the drag typed: \(String(describing: amount.value))")
    }

    func testHomeHeroPushAndSearchAcrossLedger() {
        launch("-YubaiHomeFixture", "normal")
        wait("fundsFormula", type: .button).tap()
        XCTAssertTrue(wait("formulaResult").label.contains("6,268.40"))
        wait("BackButton", type: .button).tap()
        wait("openLedgerSearch", type: .button).tap()
        let field = wait("entriesSearch", type: .textField)
        field.tap()
        field.typeText("打车")
        XCTAssertTrue(wait("entriesSearchTotal").label.contains("1 笔"))
        XCTAssertTrue(wait("askHomeSearch", type: .button).label.contains("打车"))
        wait("entriesSearchCancel", type: .button).tap()
        XCTAssertTrue(waitForDisappearance(field))
    }

    func testBudgetEditKeypadAndHomeOrder() {
        launch("-YubaiBudgetFixture", "view")
        XCTAssertTrue(wait("formulaResult").label.contains("6,268.40"))
        wait("toggleBudgetEditing", type: .button).tap()
        let shopping = wait("editBudget_购物", type: .button)
        let food = wait("editBudget_吃饭", type: .button)
        XCTAssertLessThan(food.frame.minY, shopping.frame.minY)
        wait("dragBudget_购物").press(forDuration: 1, thenDragTo: wait("dragBudget_吃饭"))
        XCTAssertTrue(UIConditionWait.run(timeout: 6, read: { shopping.frame.minY < food.frame.minY }))
        shopping.tap()
        let keypadAmount = wait("budgetKeypadAmount")
        let cancel = wait("cancelBudgetKeypad", type: .button)
        let delete = wait("deleteBudgetKeypad", type: .button)
        for button in [cancel, delete] {
            XCTAssertTrue(waitForStableFrame(button))
            XCTAssertTrue(button.isHittable)
            XCTAssertGreaterThanOrEqual(button.frame.width, 44)
            XCTAssertGreaterThanOrEqual(button.frame.height, 44)
        }
        cancel.tap()
        XCTAssertTrue(waitForDisappearance(keypadAmount))
        shopping.tap()
        XCTAssertTrue(keypadAmount.waitForExistence(timeout: 5))
        wait("keypad_2", type: .button).tap()
        wait("keypad_00", type: .button).tap()
        wait("saveQuickEntry", type: .button).tap()
        XCTAssertTrue(waitForDisappearance(app.descendants(matching: .any)["budgetKeypadAmount"]))
        XCTAssertEqual(shopping.value as? String, "200.00")
    }

    func testAAReceivesOnePersonAndOpensPrefilledEdit() {
        launch("-YubaiBillFixture", "none")
        XCTAssertTrue(app.staticTexts["待收回 · 2 人"].waitForExistence(timeout: 8))
        app.buttons["周 收到"].tap()
        XCTAssertTrue(app.staticTexts["还差 1 人"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["11月23日 收到 · 招行储蓄"].exists)
        wait("billMore", type: .button).tap()
        wait("entryDetailEdit", type: .button).tap()
        XCTAssertTrue(wait("saveQuickEntry", type: .button).exists)
        XCTAssertTrue(waitForDisappearance(app.descendants(matching: .any)["billFloatingCard"]))
    }

    func testReimbursementRecordsAndUndoRestoresPending() {
        launch("-YubaiBillFixture", "reimburse", menu: true)
        XCTAssertTrue(app.buttons["entryDetailEdit"].waitForExistence(timeout: 8))
        wait("billMore", type: .button).tap()
        XCTAssertTrue(app.buttons["报销到账了"].waitForExistence(timeout: 5))
        app.buttons["报销到账了"].tap()
        XCTAssertTrue(app.staticTexts["报销到账了"].waitForExistence(timeout: 5))
        wait("closeBill", type: .button).tap()
        XCTAssertTrue(waitForDisappearance(app.descendants(matching: .any)["billFloatingCard"]))
        wait("undoLastChange", type: .button).tap()
        let original = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "ledgerEntry_", "便利店")).firstMatch
        XCTAssertTrue(original.waitForExistence(timeout: 5))
        original.tap()
        XCTAssertTrue(app.buttons["报销到账了"].waitForExistence(timeout: 5))
    }
}
