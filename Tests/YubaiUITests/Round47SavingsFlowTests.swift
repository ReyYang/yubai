import XCTest

final class Round47SavingsFlowTests: YubaiUITestCase {
    private var app = XCUIApplication()
    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws { app.terminate(); try super.tearDownWithError() }
    private func element(_ id: String) -> XCUIElement { control(id, in: app) }
    private func launch(_ fixture: String = "v47-savings", large: Bool = false, hidden: Bool = false, keepUndo: Bool = true) {
        app.terminate()
        app.launchArguments = ["--test-ledger", UUID().uuidString, "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launchEnvironment["YUBAI_UI_TEST_SCRIPT"] = fixture
        app.launchEnvironment["YUBAI_UI_TEST_CONFIGURED_KEY"] = "1"
        app.launchEnvironment["YUBAI_UI_TEST_KEEP_UNDO"] = keepUndo ? "1" : "0"
        // Start a timed fixture after a real page return, once launch/AX startup
        // is complete. The production six-second timeout is unchanged.
        app.launchEnvironment["YUBAI_UI_TEST_TOAST_ON_RETURN"] = keepUndo ? "0" : "1"
        app.launchEnvironment["YUBAI_GALLERY_HIDE_AMOUNTS"] = hidden ? "1" : "0"
        app.launchEnvironment["DEEPSEEK_API_KEY"] = ""
        launchApp(app); XCTAssertTrue(element("mainNavigation").waitForExistence(timeout: 15))
    }
    private func tap(_ id: String) {
        if id == "savingsTopupPartial" { element("savingsTopupCard").press(forDuration: 0.8) }
        let target = element(id)
        tapControl(target, in: app, settles: !id.hasPrefix("keypad_"), reveals: !id.hasPrefix("keypad_"))
    }

    private func keys(_ value: String) { for key in value { tap("keypad_" + String(key)) } }
    private func amount(_ id: String) -> Int64 {
        let target = element(id); XCTAssertTrue((target.exists || target.waitForExistence(timeout: 5)), id)
        let text = target.label.replacingOccurrences(of: "−", with: "-")
        guard let range = text.range(of: #"-?[0-9]+(?:,[0-9]{3})*\.[0-9]{2}"#, options: .regularExpression),
              let value = Double(text[range].replacingOccurrences(of: ",", with: "")) else { XCTFail(text); return 0 }
        return Int64((value * 100).rounded())
    }
    private func back() { tap("BackButton") }
    private func saved() { tap("openSaving"); XCTAssertTrue(element("reserveTotal").waitForExistence(timeout: 5)) }
    private func gone(_ id: String) {
        XCTAssertTrue(waitForDisappearance(element(id)), id)
    }
    func testWorkedExerciseIsOneCardAndEqualsHomeWithoutYearlyReserves() {
        launch("v47-spend"); let home = amount("availableFunds"); tap("fundsFormula")
        XCTAssertEqual(amount("formulaRow_income"), 801_000)
        XCTAssertEqual(amount("formulaRow_saving"), -200_000)
        XCTAssertEqual(amount("formulaRow_bills"), -331_000)
        XCTAssertFalse(element("formulaRow_yearlySetAside").exists)
        XCTAssertEqual(amount("formulaRow_spent"), -83_600)
        XCTAssertEqual(amount("formulaResult"), home)
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "formulaCard").count, 1)
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "formulaPage").count, 1)
        XCTAssertTrue(app.scrollViews["formulaPage"].frame.contains(element("formulaRow_income").frame))
        XCTAssertFalse(element("formulaRow_daily").exists)
        XCTAssertEqual(home, 186_400)
    }
    func testZeroRowsAreOmittedButSalaryAndSpentStay() {
        launch("v47-spend-zero"); tap("fundsFormula")
        XCTAssertTrue(element("formulaRow_income").waitForExistence(timeout: 5))
        XCTAssertEqual(amount("formulaRow_spent"), 0)
        for id in ["formulaRow_saving", "formulaRow_bills", "formulaRow_yearlySetAside"] { XCTAssertFalse(element(id).exists) }
    }
    func testOverspentExerciseUsesSavingBufferAndZeroAnswer() {
        launch("v47-spend-over"); tap("fundsFormula"); XCTAssertEqual(amount("formulaResult"), 0)
        XCTAssertTrue(element("formulaRow_saving").label.contains("1,864.00"))
    }
    func testEveryExerciseSourceReachesItsRealDestination() {
        for (source, destination) in [("income", "editEntryAmount"), ("saving", "saveSavingsAmount"), ("bills", "cycleBillsPage"),
                                      ("spent", "entriesScroll")] {
            launch("v47-spend"); tap("fundsFormula"); tap("formulaRow_" + source)
            XCTAssertTrue(element(destination).waitForExistence(timeout: 5), destination)
        }
    }
    func testExerciseSheetsReopenAfterDismissalAndReturningFromDeeperPage() {
        launch("v47-spend"); tap("fundsFormula"); tap("formulaRow_bills")
        XCTAssertTrue(element("cycleBillsPage").waitForExistence(timeout: 5)); back()
        for _ in 0..<2 {
            tap("formulaRow_income"); XCTAssertTrue(element("editEntryAmount").waitForExistence(timeout: 5))
            XCTAssertEqual(element("editEntryAmount").value as? String, "8,010.00")
            tap("cancelManualSheet"); gone("editEntryAmount")
            tap("formulaRow_saving"); XCTAssertTrue(element("saveSavingsAmount").waitForExistence(timeout: 5))
            tap("amountSheetCancel"); gone("saveSavingsAmount")
            XCTAssertTrue(waitForStableFrame(element("formulaRow_income")))
            XCTAssertTrue(element("formulaRow_income").isHittable)
        }
    }
    func testPushedBillAndEntryPagesReachTheGlobalSheetPresenter() {
        launch("v47-spend"); tap("fundsFormula"); tap("formulaRow_bills")
        tap("editFixedFlow_47000000-0000-0000-0000-000000471040"); tap("billDetailAmount")
        XCTAssertTrue(element("fixedFlowTitle").waitForExistence(timeout: 5))
        tap("cancelManualSheet"); gone("fixedFlowTitle"); back(); back()
        tap("formulaRow_spent"); tap("ledgerEntry_47000000-0000-0000-0000-000000471100")
        XCTAssertTrue(element("editEntryAmount").waitForExistence(timeout: 5))
        XCTAssertEqual(element("editEntryAmount").value as? String, "24.00")
        tap("cancelManualSheet"); gone("editEntryAmount")
        XCTAssertTrue(waitForStableFrame(element("ledgerEntry_47000000-0000-0000-0000-000000471100")))
        XCTAssertTrue(element("ledgerEntry_47000000-0000-0000-0000-000000471100").isHittable)
    }
    func testIncomeSourceWithoutSalaryOpensTheActualLedgerInterval() {
        launch("v47-spend-no-salary"); tap("fundsFormula"); tap("formulaRow_income")
        XCTAssertTrue(element("entriesScroll").waitForExistence(timeout: 5))
        XCTAssertTrue(element("ledgerEntry_47000000-0000-0000-0000-000000471030").waitForExistence(timeout: 5))
        XCTAssertFalse(element("ledgerEntry_47000000-0000-0000-0000-000000471100").exists)
        XCTAssertFalse(element("formulaRow_income").exists)
    }
    func testFormulaBackWorksWhileIncomeCrossesNavigationAndIncomeStillEditsAtLargestText() {
        launch("v47-spend", large: true); tap("fundsFormula")
        let scroll = app.scrollViews["formulaPage"], income = element("formulaRow_income")
        XCTAssertTrue(income.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForNativeTransition(in: app, deadline: Date().addingTimeInterval(30)))
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "formulaPage").count, 1)
        tapControl(income, in: app, reveals: false)
        XCTAssertTrue(element("editEntryAmount").waitForExistence(timeout: 5))
        tap("cancelManualSheet"); gone("editEntryAmount")
        XCTAssertTrue(placeControl(income, across: element("BackButton"), in: scroll, atTop: true))
        tap("BackButton")
        XCTAssertTrue(element("fundsFormula").waitForExistence(timeout: 5))
        XCTAssertFalse(element("editEntryAmount").exists)
        tap("fundsFormula")
        XCTAssertTrue(revealControl(income, in: app, deadline: Date().addingTimeInterval(60)))
        XCTAssertTrue(scroll.frame.insetBy(dx: -0.5, dy: -0.5).contains(income.frame))
        tapControl(income, in: app, reveals: false)
        XCTAssertTrue(element("editEntryAmount").waitForExistence(timeout: 5))
        XCTAssertEqual(element("editEntryAmount").value as? String, "8,010.00")
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
        let confirm = element("confirmSavingsTransfer")
        XCTAssertTrue(waitForStableFrame(element("amountSheetCancel")))
        XCTAssertGreaterThanOrEqual(element("amountSheetCancel").frame.height, 44)
        XCTAssertLessThan(element("amountSheetCancel").frame.maxY, element("amountSheetAmount").frame.minY)
        XCTAssertLessThan(element("amountSheetAmount").frame.maxY, element("transferSavedPreview").frame.minY)
        XCTAssertLessThanOrEqual(element("transferAvailablePreview").frame.maxY, confirm.frame.minY)
        XCTAssertLessThan(confirm.frame.maxY, element("keypad_1").frame.minY)
        XCTAssertTrue(element("transferSavedPreview").label.contains("4,500.00"))
        XCTAssertTrue(element("transferAvailablePreview").label.contains("2,364.00"))
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
        for (button, value) in [("takeSavings", "5000.01"), ("putBackSavings", "1864.01")] {
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
    }
    func testPaydayAllClosesTheQuestionAndPersistsTheNewTotals() {
        launch("v47-topup"); let before = amount("availableFunds"); tap("savingsTopupAll"); gone("savingsTopupCard")
        XCTAssertEqual(amount("availableFunds"), before - 50_000)
        app.terminate(); launchApp(app); XCTAssertTrue(element("mainNavigation").waitForExistence(timeout: 15))
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
        app.terminate(); launchApp(app); XCTAssertTrue(element("mainNavigation").waitForExistence(timeout: 15))
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
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "toastMessage").count, 1)
        XCTAssertGreaterThan(element("toastMessage").frame.height, 0)
        launch("v47-toast-long"); XCTAssertTrue(element("expandToast").waitForExistence(timeout: 5))
        XCTAssertTrue(element("toastMessage").label.hasSuffix("生活用品 2 笔"))
    }
    func testExpandedToastPausesTimeoutThenSecondTapDismisses() {
        launch("v47-toast-long", keepUndo: false)
        saved(); back()
        XCTAssertTrue(element("expandToast").exists || element("expandToast").waitForExistence(timeout: 5))
        XCTAssertTrue(waitForStableFrame(element("toastMessage")))
        let collapsedHeight = element("toastMessage").frame.height
        XCTAssertGreaterThan(collapsedHeight, 0)
        element("expandToast").tap(); XCTAssertEqual(element("expandToast").value as? String, "已展开")
        XCTAssertTrue(UIConditionWait.run(timeout: 5, read: { self.element("toastMessage").frame.height > collapsedHeight }))
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
    func testToastUndoWinsOverReceiptLedgerAndScrollingRevealsTheLedgerAction() {
        launch("v47-toast-short")
        let undo = element("undoLastChange"), scroll = element("entriesScroll")
        let row = element("ledgerEntry_47000000-0000-0000-0000-000000471030")
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        XCTAssertTrue(revealControl(row, in: app, deadline: Date().addingTimeInterval(60), searching: scroll))
        XCTAssertTrue(placeControl(row, across: undo, in: scroll, atTop: false))
        XCTAssertTrue(UIViewportGeometry.overlaps(row.frame, undo.frame))
        XCTAssertTrue(undo.isHittable)
        tap("undoLastChange")
        XCTAssertEqual(element("toastMessage").label, "已撤销")
        XCTAssertTrue(element("tab_ledger").isSelected)
        XCTAssertFalse(element("editEntryAmount").exists)

        launch("v47-toast-short")
        let toast = element("toastMessage")
        let last = element("ledgerEntry_47000000-0000-0000-0000-000000471030")
        XCTAssertTrue(revealControl(last, in: app, deadline: Date().addingTimeInterval(180), searching: element("entriesScroll")))
        XCTAssertTrue(toast.exists); XCTAssertTrue(last.isHittable)
        XCTAssertLessThanOrEqual(last.frame.maxY, toast.frame.minY - 12 + 0.5)
        XCTAssertLessThan(last.frame.maxY, element("addEntry").frame.minY)
        tapControl(last, in: app, reveals: false)
        XCTAssertTrue(element("editEntryAmount").waitForExistence(timeout: 5))
        tap("cancelManualSheet")
        tap("tab_ledger"); saved()
        let records = element("openReserve")
        XCTAssertTrue(revealControl(records, in: app, deadline: Date().addingTimeInterval(180)))
        XCTAssertTrue(toast.exists); XCTAssertTrue(records.isHittable)
        XCTAssertLessThanOrEqual(records.frame.maxY, toast.frame.minY - 12 + 0.5)
        tapControl(records, in: app, reveals: false)
        XCTAssertTrue(element("reserveLine_0").waitForExistence(timeout: 5))
    }
    func testRevisionDeficitRescueAndUndoUseTheSameFormula() {
        launch("v47r-deficit")
        XCTAssertEqual(amount("availableFunds"), 35_000)
        tap("coverFromReserve")
        XCTAssertEqual(amount("availableFunds"), 0)
        tap("undoLastChange")
        XCTAssertEqual(amount("availableFunds"), 35_000)
    }
    func testRevisionCarryRevertAddsItsOwnRowAndUndoRestoresSavings() {
        launch("v47r-carry"); tap("leftoverKeep")
        XCTAssertEqual(amount("availableFunds"), 248_400)
        tap("fundsFormula")
        XCTAssertEqual(amount("formulaRow_carry"), 62_000)
        back(); tap("undoLastChange")
        XCTAssertEqual(amount("availableFunds"), 186_400)
        XCTAssertFalse(element("newCycleCard").exists)
    }
    func testRevisionFloorAppearsInFormula() {
        launch("v47r-floor"); tap("fundsFormula")
        XCTAssertEqual(amount("formulaRow_balanceGap"), -40_000)
        XCTAssertEqual(amount("formulaResult"), 146_400)
    }

}
