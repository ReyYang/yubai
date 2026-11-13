import XCTest

final class Round47SavingsFlowTests: XCTestCase {
    private var app = XCUIApplication()
    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws { app.terminate(); try super.tearDownWithError() }
    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
    private func launch(_ fixture: String = "v47-savings", large: Bool = false, hidden: Bool = false, keepUndo: Bool = true) {
        app.terminate()
        app.launchArguments = ["--test-ledger", UUID().uuidString, "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launchEnvironment["YUBAI_UI_TEST_SCRIPT"] = fixture
        app.launchEnvironment["YUBAI_UI_TEST_CONFIGURED_KEY"] = "1"
        app.launchEnvironment["YUBAI_UI_TEST_KEEP_UNDO"] = keepUndo ? "1" : "0"
        app.launchEnvironment["YUBAI_GALLERY_HIDE_AMOUNTS"] = hidden ? "1" : "0"
        app.launchEnvironment["DEEPSEEK_API_KEY"] = ""
        app.launch(); XCTAssertTrue(element("mainNavigation").waitForExistence(timeout: 15))
    }
    private func tap(_ id: String) {
        let target = element(id); XCTAssertTrue(target.waitForExistence(timeout: 5), id)
        for _ in 0..<10 { if target.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(target.isHittable, id); target.tap()
    }
    private func keys(_ value: String) { for key in value { tap("keypad_" + String(key)) } }
    private func amount(_ id: String) -> Int64 {
        let target = element(id); XCTAssertTrue(target.waitForExistence(timeout: 5), id)
        let text = target.label.replacingOccurrences(of: "−", with: "-")
        guard let range = text.range(of: #"-?[0-9]+(?:,[0-9]{3})*\.[0-9]{2}"#, options: .regularExpression),
              let value = Double(text[range].replacingOccurrences(of: ",", with: "")) else { XCTFail(text); return 0 }
        return Int64((value * 100).rounded())
    }
    private func back() { tap("ledgerBack") }
    private func saved() { tap("openSaving"); XCTAssertTrue(element("reserveTotal").waitForExistence(timeout: 5)) }
    private func gone(_ id: String) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !self.element(id).exists }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed)
    }
    func testWorkedExerciseIsOneCardAndEqualsHomeIncludingYearlyReserves() {
        launch("v47-spend"); let home = amount("availableFunds"); tap("fundsFormula")
        XCTAssertEqual(amount("formulaRow_income"), 801_000)
        XCTAssertEqual(amount("formulaRow_saving"), -200_000)
        XCTAssertEqual(amount("formulaRow_bills"), -331_000)
        XCTAssertEqual(amount("formulaRow_yearlySetAside"), -30_000)
        XCTAssertEqual(amount("formulaRow_spent"), -83_600)
        XCTAssertEqual(amount("formulaResult"), home)
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "formulaCard").count, 1)
        XCTAssertTrue(element("formulaRow_daily").label.contains("÷"))
    }
    func testZeroRowsAreOmittedButSalaryAndSpentStay() {
        launch("v47-spend-zero"); tap("fundsFormula")
        XCTAssertTrue(element("formulaRow_income").waitForExistence(timeout: 5))
        XCTAssertEqual(amount("formulaRow_spent"), 0)
        for id in ["formulaRow_saving", "formulaRow_bills", "formulaRow_yearlySetAside"] { XCTAssertFalse(element(id).exists) }
    }
    func testOverspentExerciseKeepsTheNegativeAnswer() {
        launch("v47-spend-over"); tap("fundsFormula"); XCTAssertEqual(amount("formulaResult"), -43_600)
    }
    func testEveryExerciseSourceReachesItsRealDestination() {
        for (source, destination) in [("income", "editEntryAmount"), ("saving", "saveSavingsAmount"), ("bills", "cycleBillsPage"),
                                      ("yearlySetAside", "yearlyBillsPage"), ("spent", "entriesScroll")] {
            launch("v47-spend"); tap("fundsFormula"); tap("formulaRow_" + source)
            XCTAssertTrue(element(destination).waitForExistence(timeout: 5), destination)
        }
    }
    func testSavingsHasEqualActionsAndEditableFloorBelowHero() {
        launch(); saved()
        XCTAssertEqual(element("takeSavings").frame.width, element("putBackSavings").frame.width, accuracy: 1)
        XCTAssertTrue(element("editSavingsFloor").exists)
        XCTAssertFalse(element("mainNavigation").exists)
        XCTAssertEqual(amount("reserveTotal"), 500_000)
    }
    func testTakePreviewUpdatesBothTotalsAndSharedUndoRestoresThem() {
        launch(); let home = amount("availableFunds"); saved(); tap("takeSavings"); keys("500")
        XCTAssertTrue(element("transferSavedPreview").label.contains("4,500.00"))
        XCTAssertTrue(element("transferAvailablePreview").label.contains("2,064.00"))
        tap("confirmSavingsTransfer"); gone("savingsTransferSheet"); XCTAssertEqual(amount("reserveTotal"), 450_000)
        tap("undoLastChange"); XCTAssertEqual(amount("reserveTotal"), 500_000)
        back(); XCTAssertEqual(amount("availableFunds"), home)
    }
    func testPutBackAndUndoUpdateTheHomeSavingCard() {
        launch(); let home = amount("availableFunds"); saved(); tap("putBackSavings"); keys("500"); tap("confirmSavingsTransfer")
        gone("savingsTransferSheet"); XCTAssertEqual(amount("reserveTotal"), 550_000)
        back(); XCTAssertEqual(amount("availableFunds"), home - 50_000)
        XCTAssertTrue(element("openSaving").label.contains("5,500.00"))
        tap("undoLastChange"); XCTAssertEqual(amount("availableFunds"), home)
        XCTAssertTrue(element("openSaving").label.contains("5,000.00"))
    }
    func testTakeCannotExceedSavedAndPutBackCannotExceedSpendable() {
        for (button, value) in [("takeSavings", "5000.01"), ("putBackSavings", "1564.01")] {
            launch(); saved(); tap(button); keys(value)
            XCTAssertFalse(element("confirmSavingsTransfer").isEnabled)
            XCTAssertFalse(app.alerts.firstMatch.exists)
            tap("amountSheetCancel"); XCTAssertEqual(amount("reserveTotal"), 500_000)
        }
    }
    func testFloorCanBeChangedClearedAndRestoredWithoutChangingMoney() {
        launch(); saved(); tap("editSavingsFloor"); keys("2500"); tap("saveSavingsFloor"); gone("savingsFloorSheet")
        XCTAssertTrue(element("editSavingsFloor").label.contains("2,500.00")); XCTAssertEqual(amount("reserveTotal"), 500_000)
        tap("editSavingsFloor"); tap("clearSavingsFloor"); gone("savingsFloorSheet")
        XCTAssertFalse(element("editSavingsFloor").label.contains("2,500.00"))
        tap("editSavingsFloor"); keys("1000"); tap("saveSavingsFloor"); gone("savingsFloorSheet")
        XCTAssertTrue(element("editSavingsFloor").label.contains("1,000.00"))
    }
    func testRecordsAreOnlyRowsAndIncludeBothDirections() {
        launch("v47-records"); saved(); tap("openReserve")
        XCTAssertTrue(element("reserveLine_0").waitForExistence(timeout: 5))
        XCTAssertTrue(element("reserveLine_0").label.contains("放回去"))
        XCTAssertTrue(element("reserveLine_1").label.contains("拿出来用"))
        XCTAssertFalse(element("reserveTotal").exists)
        XCTAssertFalse(element("reservePaybackOffer").exists); XCTAssertFalse(element("reservePaybackProgress").exists)
    }
    func testPaydayAllClosesTheQuestionAndPersistsTheNewTotals() {
        launch("v47-topup"); let before = amount("availableFunds"); tap("savingsTopupAll"); gone("savingsTopupCard")
        XCTAssertEqual(amount("availableFunds"), before - 50_000)
        app.terminate(); app.launch(); XCTAssertTrue(element("mainNavigation").waitForExistence(timeout: 15))
        XCTAssertFalse(element("savingsTopupCard").exists); XCTAssertEqual(amount("availableFunds"), before - 50_000)
    }
    func testPaydayPartialClosesWholeQuestionAndUsesTheSameSheet() {
        launch("v47-topup"); let before = amount("availableFunds"); tap("savingsTopupPartial")
        keys("200"); tap("confirmSavingsTransfer"); gone("savingsTransferSheet"); gone("savingsTopupCard")
        XCTAssertEqual(amount("availableFunds"), before - 20_000)
        tap("undoLastChange"); XCTAssertTrue(element("savingsTopupCard").waitForExistence(timeout: 5))
    }
    func testPaydayDeclineIsPermanentAndTheNextQueueItemAppears() {
        launch("v47-topup-queue"); let before = amount("availableFunds")
        XCTAssertTrue(element("savingsTopupCard").waitForExistence(timeout: 5)); XCTAssertFalse(element("renewalCard").exists)
        tap("savingsTopupDecline"); gone("savingsTopupCard")
        XCTAssertEqual(amount("availableFunds"), before); XCTAssertTrue(element("renewalCard").waitForExistence(timeout: 5))
        app.terminate(); app.launch(); XCTAssertTrue(element("mainNavigation").waitForExistence(timeout: 15))
        XCTAssertFalse(element("savingsTopupCard").exists)
    }
    func testLargeHiddenSavingsKeepsControlsAndAmountsInsideScreen() {
        launch("v47-savings-hard", large: true, hidden: true); saved()
        XCTAssertEqual(element("reserveTotal").label, "金额已隐藏")
        tap("takeSavings"); keys("1234567.89")
        XCTAssertTrue(element("transferSavedPreview").label.contains("••••"))
        XCTAssertLessThanOrEqual(element("amountSheetAmount").frame.maxX, app.frame.maxX)
        XCTAssertGreaterThanOrEqual(element("confirmSavingsTransfer").frame.minX, app.frame.minX)
    }
    func testShortToastHasNoChevronAndLongToastReadsFullTextWhileCollapsed() {
        launch("v47-toast-short"); XCTAssertTrue(element("toastMessage").waitForExistence(timeout: 5)); XCTAssertFalse(element("expandToast").exists)
        launch("v47-toast-long"); XCTAssertTrue(element("expandToast").waitForExistence(timeout: 5))
        XCTAssertTrue(element("toastMessage").label.hasSuffix("生活用品 2 笔"))
    }
    func testExpandedToastPausesTimeoutThenSecondTapDismisses() {
        launch("v47-toast-long", keepUndo: false)
        XCTAssertTrue(element("expandToast").waitForExistence(timeout: 5))
        let collapsedHeight = element("toastMessage").frame.height
        tap("expandToast"); XCTAssertEqual(element("expandToast").value as? String, "已展开")
        XCTAssertGreaterThan(element("toastMessage").frame.height, collapsedHeight)
        let remains = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !self.element("toastMessage").exists }, object: nil)
        remains.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [remains], timeout: 7), .completed)
        tap("expandToast"); gone("toastMessage")
    }
    func testExpandedToastSupportsUndoAndSwipeDismiss() {
        launch("v47-toast-long"); tap("expandToast"); tap("undoLastChange")
        XCTAssertEqual(element("toastMessage").label, "已撤销")
        launch("v47-toast-long"); tap("expandToast"); element("expandToast").swipeDown(); gone("toastMessage")
    }
}
