import XCTest

final class Round47SavingsFlowTests: YubaiUITestCase {
    private var app = XCUIApplication()
    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws { app.terminate(); try super.tearDownWithError() }
    private func element(_ id: String) -> XCUIElement { control(id, in: app) }
    private func launch(_ fixture: String = "v47-savings", large: Bool = false, hidden: Bool = false, keepUndo: Bool = true, dark: Bool = false) {
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
        app.launchEnvironment["YUBAI_GALLERY_APPEARANCE"] = dark ? "dark" : "light"
        app.launchEnvironment["DEEPSEEK_API_KEY"] = ""
        launchApp(app); XCTAssertTrue(element("mainNavigation").waitForExistence(timeout: 15))
    }
    private func tap(_ id: String) {
        if id == "savingsTopupPartial" { element("savingsTopupCard").press(forDuration: 0.8) }
        let target = element(id)
        tapControl(target, in: app, settles: !id.hasPrefix("keypad_"), reveals: !id.hasPrefix("keypad_"))
    }

    private func backToHome() {
        for _ in 0..<8 {
            if element("tab_ledger").isHittable { return }
            back()
        }
        XCTFail("未回到首页")
    }

    private func openInbox() {
        backToHome()
        tap("openSettings"); tap("openAssistantHub"); tap("openButlerInbox")
    }

    private func keys(_ value: String) { for key in value { tap("keypad_" + String(key)) } }
    private func amount(_ id: String) -> Int64 {
        let target = element(id); XCTAssertTrue((target.exists || target.waitForExistence(timeout: 5)), id)
        let valueText = (target.value as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let text = (valueText.isEmpty ? target.label : valueText).replacingOccurrences(of: "−", with: "-")
        guard let range = text.range(of: #"-?[0-9]+(?:,[0-9]{3})*\.[0-9]{2}"#, options: .regularExpression),
              let value = Double(text[range].replacingOccurrences(of: ",", with: "")) else {
            XCTFail("\(id): 无法读取金额 ‘\(text)’")
            return 0
        }
        return Int64((value * 100).rounded())
    }
    private func back() { tap("BackButton") }
    private func saved() {
        backToHome()
        tap("openSettings"); tap("openAssistantHub"); tap("openSaving")
        XCTAssertTrue(element("savingTabScroll").waitForExistence(timeout: 10))
        let total = element("reserveTotal")
        XCTAssertTrue(total.waitForExistence(timeout: 5), "reserveTotal 缺失，储蓄空状态存在：\(element("emptyState_saving").exists)")
    }
    private func gone(_ id: String) {
        XCTAssertTrue(waitForDisappearance(element(id)), id)
    }
    func testWorkedExerciseIsOneCardAndEqualsHomeWithoutYearlyReserves() {
        launch("v47-spend"); let home = amount("fundsFormula"); tap("fundsFormula")
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
        for (source, destination) in [("income", "entryKeypadAmount"), ("saving", "savingsPage"), ("bills", "cycleBillsPage"),
                                      ("spent", "entriesScroll")] {
            launch("v47-spend"); tap("fundsFormula"); tap("formulaRow_" + source)
            XCTAssertTrue(element(destination).waitForExistence(timeout: 5), destination)
        }
    }
    func testExerciseSheetsReopenAfterDismissalAndReturningFromDeeperPage() {
        launch("v47-spend"); tap("fundsFormula"); tap("formulaRow_bills")
        XCTAssertTrue(element("cycleBillsPage").waitForExistence(timeout: 5)); back()
        for _ in 0..<2 {
            tap("formulaRow_income"); XCTAssertTrue(element("entryKeypadAmount").waitForExistence(timeout: 5))
            XCTAssertEqual(element("entryKeypadAmount").value as? String, "8,010.00")
            dismissEntrySheet(in: app)
            tap("formulaRow_saving"); XCTAssertTrue(element("savingsPage").waitForExistence(timeout: 5))
            back(); gone("savingsPage")
            XCTAssertTrue(waitForStableFrame(element("formulaRow_income")))
            XCTAssertTrue(element("formulaRow_income").isHittable)
        }
    }
    func testPushedBillAndEntryPagesReachTheGlobalSheetPresenter() {
        launch("v47-spend"); tap("fundsFormula"); tap("formulaRow_bills")
        tap("editFixedFlow_47000000-0000-0000-0000-000000471040"); tap("billDetailAmount")
        XCTAssertTrue(element("fixedFlowTitle").waitForExistence(timeout: 5))
        tap("cancelManualSheet"); gone("fixedFlowTitle"); back(); back()
        tap("formulaRow_spent"); tap("ledgerEntry_47000000-0000-0000-0000-000000471100"); tap("billMore"); tap("entryDetailEdit")
        XCTAssertTrue(element("entryKeypadAmount").waitForExistence(timeout: 5))
        XCTAssertEqual(element("entryKeypadAmount").value as? String, "24.00")
        dismissEntrySheet(in: app)
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
    func testFormulaEvidencePresetsSurviveRepeatedRootReplacement() {
        for large in [false, true] {
            launch("v47-spend-no-salary", large: large)
            for _ in 0..<2 {
                tap("fundsFormula"); tap("formulaRow_income")
                XCTAssertTrue(element("entriesScroll").waitForExistence(timeout: 5))
                for suffix in ["471030", "471031"] {
                    XCTAssertTrue(element("ledgerEntry_47000000-0000-0000-0000-000000" + suffix).waitForExistence(timeout: 5))
                }
                XCTAssertTrue(element("entriesSearchTotal").label.contains("2 笔"))
                XCTAssertEqual(amount("entriesSearchTotal"), 801_000)
                XCTAssertFalse(element("ledgerEntry_47000000-0000-0000-0000-000000471100").exists)
                XCTAssertFalse(element("fundsFormula").exists)
                tap("tab_ledger")
                XCTAssertTrue(element("fundsFormula").waitForExistence(timeout: 5))
                tap("fundsFormula"); tap("formulaRow_spent")
                XCTAssertTrue(element("ledgerEntry_47000000-0000-0000-0000-000000471100").waitForExistence(timeout: 5))
                XCTAssertEqual(amount("entriesSearchTotal"), 83_600)
                XCTAssertFalse(element("ledgerEntry_47000000-0000-0000-0000-000000471030").exists)
                tap("tab_ledger")
                XCTAssertTrue(element("fundsFormula").waitForExistence(timeout: 5))
            }
        }
    }
    func testFormulaBackWorksWhileIncomeCrossesNavigationAndIncomeStillEditsAtLargestText() {
        launch("v47-spend", large: true); tap("fundsFormula")
        let scroll = app.scrollViews["formulaPage"], income = element("formulaRow_income")
        XCTAssertTrue(income.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForNativeTransition(in: app, deadline: Date().addingTimeInterval(30)))
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "formulaPage").count, 1)
        tapControl(income, in: app, reveals: false)
        XCTAssertTrue(element("entryKeypadAmount").waitForExistence(timeout: 5))
        dismissEntrySheet(in: app)
        XCTAssertTrue(placeControl(income, across: element("BackButton"), in: scroll, atTop: true))
        tap("BackButton")
        XCTAssertTrue(element("fundsFormula").waitForExistence(timeout: 5))
        XCTAssertFalse(element("entryKeypadAmount").exists)
        tap("fundsFormula")
        XCTAssertTrue(revealControl(income, in: app, deadline: Date().addingTimeInterval(60)))
        XCTAssertTrue(scroll.frame.insetBy(dx: -0.5, dy: -0.5).contains(income.frame))
        tapControl(income, in: app, reveals: false)
        XCTAssertTrue(element("entryKeypadAmount").waitForExistence(timeout: 5))
        XCTAssertEqual(element("entryKeypadAmount").value as? String, "8,010.00")
    }
    func testSavingsHasEqualActionsAndEditableFloorBelowHero() {
        launch(); saved()
        XCTAssertEqual(element("takeSavings").frame.width, element("putBackSavings").frame.width, accuracy: 1)
        XCTAssertTrue(element("editSavingsFloor").exists)
        XCTAssertFalse(element("mainNavigation").exists)
        XCTAssertEqual(amount("reserveTotal"), 500_000)
    }
    func testTakePreviewUpdatesBothTotalsAndSharedUndoRestoresThem() {
        launch(); let home = amount("fundsFormula"); saved(); tap("takeSavings"); keys("500")
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
        backToHome(); XCTAssertEqual(amount("fundsFormula"), home)
    }
    func testPutBackAndUndoUpdateTheHomeSavingCard() {
        launch(); let home = amount("fundsFormula"); saved(); tap("putBackSavings"); keys("500"); tap("confirmSavingsTransfer")
        gone("savingsTransferSheet"); XCTAssertEqual(amount("reserveTotal"), 550_000)
        backToHome(); XCTAssertEqual(amount("fundsFormula"), home - 50_000)
        saved(); XCTAssertEqual(amount("reserveTotal"), 550_000); backToHome()
        tap("undoLastChange"); XCTAssertEqual(amount("fundsFormula"), home)
        saved(); XCTAssertEqual(amount("reserveTotal"), 500_000); backToHome()
    }
    func testTakeCannotExceedSavedAndPutBackCannotExceedSpendable() {
        for (button, value) in [("takeSavings", "5000.01"), ("putBackSavings", "1864.01")] {
            launch(); saved(); tap(button); keys(value)
            XCTAssertFalse(element("confirmSavingsTransfer").isEnabled)
            XCTAssertFalse(app.alerts.firstMatch.exists)
            tap("amountSheetCancel"); XCTAssertEqual(amount("reserveTotal"), 500_000)
        }
    }
    func testDarkPutBackLimitPresentsSettledPreviewAtDefaultAndLargestText() {
        for large in [false, true] {
            launch(large: large, dark: true); saved(); tap("putBackSavings")
            let deadline = Date().addingTimeInterval(90)
            let preview = element("savingsTransferPreview")
            XCTAssertTrue(preview.waitForExistence(timeout: 5))
            XCTAssertTrue(waitForNativeTransition(in: app, deadline: deadline))
            XCTAssertTrue(waitForStableFrame(preview, deadline: deadline))
            for key in "1864.01" {
                let target = element("keypad_" + String(key))
                // Exercise the same fixed-footer reveal used by the gallery.
                XCTAssertTrue(revealControl(target, in: app, deadline: deadline))
                target.tap()
            }
            XCTAssertEqual(element("amountSheetAmount").value as? String, "1864.01")
            XCTAssertFalse(element("confirmSavingsTransfer").isEnabled)
            XCTAssertTrue(element("transferSavedPreview").label.contains("5,000.00，变为 5,000.00"))
            XCTAssertTrue(element("transferAvailablePreview").label.contains("1,864.00，变为 1,864.00"))
            XCTAssertTrue(waitForNativeTransition(in: app, deadline: deadline))
            XCTAssertTrue(waitForStableFrame(preview, deadline: deadline))
            XCTAssertEqual(app.state, .runningForeground)
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
        launch("v47-topup"); let before = amount("fundsFormula"); openInbox(); tap("savingsTopupAll"); gone("savingsTopupCard"); backToHome()
        XCTAssertEqual(amount("fundsFormula"), before - 50_000)
        app.terminate(); launchApp(app); XCTAssertTrue(element("mainNavigation").waitForExistence(timeout: 15))
        XCTAssertFalse(element("savingsTopupCard").exists); XCTAssertEqual(amount("fundsFormula"), before - 50_000)
    }
    func testPaydayPartialClosesWholeQuestionAndUsesTheSameSheet() {
        launch("v47-topup"); let before = amount("fundsFormula"); openInbox(); tap("savingsTopupPartial")
        keys("200"); tap("confirmSavingsTransfer"); gone("savingsTransferSheet"); gone("savingsTopupCard"); backToHome()
        XCTAssertEqual(amount("fundsFormula"), before - 20_000)
        tap("undoLastChange"); openInbox(); XCTAssertTrue(element("savingsTopupCard").waitForExistence(timeout: 5))
    }
    func testPaydayDeclineIsPermanentAndTheNextQueueItemAppears() {
        launch("v47-topup-queue"); let before = amount("fundsFormula"); openInbox()
        XCTAssertTrue(element("savingsTopupCard").waitForExistence(timeout: 5)); XCTAssertFalse(element("renewalCard").exists)
        tap("savingsTopupDecline"); gone("savingsTopupCard")
        XCTAssertTrue(element("renewalCard").waitForExistence(timeout: 5)); backToHome()
        XCTAssertEqual(amount("fundsFormula"), before)
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
        XCTAssertGreaterThanOrEqual(element("toastMessage").frame.height, 44)
        XCTAssertGreaterThanOrEqual(element("toastMessage").frame.width, 44)
        launch("v47-toast-long"); XCTAssertTrue(element("expandToast").waitForExistence(timeout: 5))
        XCTAssertTrue(element("toastMessage").label.hasSuffix("生活用品 2 笔"))
    }
    func testToastMessagesExposeAndRespondAcrossTheirWholeAreaAtEverySize() {
        for large in [false, true] {
            for dark in [false, true] {
                for fixture in ["v47-toast-short", "v47-toast-long", "v47r-deficit"] {
                    launch(fixture, large: large, dark: dark)
                    if fixture == "v47r-deficit" { tap("coverFromReserve") }
                    let message = element("toastMessage"), viewport = element("toastBody"), undo = element("undoLastChange")
                    XCTAssertTrue(message.waitForExistence(timeout: 5))
                    XCTAssertTrue(waitForStableFrame(message))
                    let context = "\(fixture) large=\(large) dark=\(dark) frame=\(message.frame)"
                    XCTAssertEqual(message.elementType, .button, context)
                    XCTAssertGreaterThanOrEqual(message.frame.width, 44, context)
                    XCTAssertGreaterThanOrEqual(message.frame.height, 44, context)
                    XCTAssertTrue(viewport.frame.insetBy(dx: -0.5, dy: -0.5).contains(message.frame), context)
                    XCTAssertEqual(message.frame.minX, viewport.frame.minX, accuracy: 0.5, context)
                    XCTAssertTrue(message.isHittable, context)
                    XCTAssertTrue(undo.isHittable, context)
                    if large { XCTAssertGreaterThanOrEqual(undo.frame.minY, message.frame.maxY, context) }
                    else { XCTAssertGreaterThanOrEqual(undo.frame.minX, message.frame.maxX, context) }
                    if fixture != "v47-toast-long" || large {
                        XCTAssertEqual(message.frame.maxX, viewport.frame.maxX, accuracy: 0.5, context)
                        XCTAssertFalse(element("expandToast").exists, context)
                    } else {
                        XCTAssertLessThanOrEqual(message.frame.maxX, element("expandToast").frame.minX, context)
                    }
                    // For a short receipt this point is blank row space, well
                    // beyond the glyphs that used to be the whole AX target.
                    if fixture == "v47r-deficit" { XCTAssertEqual(message.label, "已拿出", context) }
                    message.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)).tap()
                    if fixture == "v47-toast-long" && !large {
                        XCTAssertTrue(UIConditionWait.run(timeout: 5, read: { self.element("expandToast").value as? String == "已展开" }))
                        XCTAssertTrue(waitForStableFrame(message))
                        XCTAssertGreaterThanOrEqual(message.frame.height, 44, context)
                        message.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)).tap()
                    }
                    gone("toastMessage")
                    XCTAssertEqual(app.state, .runningForeground, context)
                }
            }
        }
    }
    func testExpandedToastPausesTimeoutThenSecondTapDismisses() {
        launch("v47-toast-long", keepUndo: false)
        saved(); backToHome()
        XCTAssertTrue(element("expandToast").exists || element("expandToast").waitForExistence(timeout: 5))
        XCTAssertTrue(waitForStableFrame(element("toastMessage")))
        let bodyLineHeight: CGFloat = 22 // YubaiFont.body.lineHeight in DesignSystem.swift (default Dynamic Type).
        let minimumExpandedHeight = 2 * bodyLineHeight
        element("expandToast").tap(); XCTAssertEqual(element("expandToast").value as? String, "已展开")
        // Two body lines fit in YubaiSize.tapMin (44 pt), so expansion need not grow the button.
        XCTAssertTrue(UIConditionWait.run(timeout: 5, read: { self.element("toastMessage").frame.height >= minimumExpandedHeight }))
        XCTAssertGreaterThanOrEqual(element("toastMessage").frame.height, minimumExpandedHeight)
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
    func testTopupPartialPresentationSurvivesDynamicTypeAndClippingAudit() throws {
        for large in [false, true] {
            launch("v47-topup", large: large); openInbox()
            tap("savingsTopupPartial")
            XCTAssertTrue(waitForNativeTransition(in: app, deadline: Date().addingTimeInterval(12)))
            try auditAppText(in: app, dynamicType: true) { issue in
                XCTFail("Topup sheet accessibility audit: " + issue.detailedDescription)
                return true
            }
            XCTAssertEqual(app.state, .runningForeground)
            XCTAssertTrue(element("savingsTransferPreview").exists)
            keys("200")
            XCTAssertTrue(element("confirmSavingsTransfer").isEnabled)
            tap("amountSheetCancel"); gone("savingsTransferSheet")
            XCTAssertTrue(element("savingsTopupCard").exists)
        }
    }
    func testLargestToastWrapsInsideItsVisibleViewportAndKeepsUndoAndDismiss() {
        for dark in [false, true] {
            launch("v47-toast-long", large: true, dark: dark)
            let message = element("toastMessage"), undo = element("undoLastChange"), viewport = element("toastBody")
            XCTAssertTrue(message.waitForExistence(timeout: 5))
            XCTAssertTrue(waitForStableFrame(message))
            XCTAssertEqual(message.label, "已删除 · 为了搬家以后和家人朋友一起长期使用而认真挑选的生活用品 2 笔")
            XCTAssertFalse(element("expandToast").exists)
            XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "toastMessage").count, 1)
            XCTAssertTrue(viewport.frame.insetBy(dx: -0.5, dy: -0.5).contains(message.frame))
            XCTAssertTrue(app.frame.contains(message.frame))
            XCTAssertGreaterThan(message.frame.height, 44)
            XCTAssertGreaterThanOrEqual(undo.frame.minY, message.frame.maxY)
            XCTAssertTrue(message.isHittable); XCTAssertTrue(undo.isHittable)
            XCTAssertLessThanOrEqual(element("fundsFormula").frame.maxY, message.frame.minY - 12 + 0.5)
            XCTAssertNoThrow(try auditAppText(in: app) { issue in
                if let target = issue.element, target.label.contains("已删除") { XCTFail(issue.detailedDescription) }
                return true
            })
            let last = element("ledgerEntry_47000000-0000-0000-0000-000000471030")
            XCTAssertTrue(revealControl(last, in: app, deadline: Date().addingTimeInterval(60), searching: element("entriesScroll")), revealFailure)
            XCTAssertTrue(last.isHittable)
            XCTAssertLessThanOrEqual(last.frame.maxY, message.frame.minY - 12 + 0.5)
            tap("undoLastChange"); XCTAssertEqual(message.label, "已撤销")

            launch("v47-toast-long", large: true, dark: dark)
            XCTAssertTrue(waitForStableFrame(element("toastMessage")))
            element("toastMessage").swipeDown(); gone("toastMessage")
            XCTAssertTrue(element("openSettings").exists)
        }
    }

    func testLargestHeadlineAmountsStayOnOneLineOnHomeSavingsAndFormula() {
        for hidden in [false, true] {
            for fixture in ["v47-savings", "v47r-less", "v47r-deficit", "v47-spend-no-salary", "v47-savings-hard"] {
                launch(fixture, large: true, hidden: hidden)
                let home = element("availableFunds")
                assertHeadlineFits(home)
                if element("fundsFormula").exists {
                    let expected = home.label
                    tap("fundsFormula")
                    let result = element("formulaResult")
                    XCTAssertTrue(revealControl(result, in: app, deadline: Date().addingTimeInterval(60), searching: element("formulaPage")))
                    XCTAssertEqual(result.label, expected)
                    assertHeadlineFits(result)
                    back()
                }
                saved(); assertHeadlineFits(element("reserveTotal"))
            }
        }
    }
    private func assertHeadlineFits(_ target: XCUIElement) {
        XCTAssertTrue(target.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForStableFrame(target))
        XCTAssertTrue(app.frame.insetBy(dx: -0.5, dy: -0.5).contains(target.frame))
        // The largest scaled hero token's one-line box is below 120pt;
        // the supplied wrapped amount measured 206pt. Never accept two lines.
        XCTAssertLessThan(target.frame.height, 120)
        XCTAssertTrue(target.label == "金额已隐藏" || target.label.range(of: #"¥[0-9,]+\.[0-9]{2}$"#, options: .regularExpression) != nil)
        XCTAssertNoThrow(try auditAppText(in: app) { issue in
            if let element = issue.element, element.identifier == target.identifier || element.label.contains(target.label) {
                XCTFail("Headline amount clipped: " + issue.detailedDescription)
            }
            return true
        })
        assertBambooReadyForCapture(in: app)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "largest-single-line-" + target.identifier
        attachment.lifetime = .keepAlways; add(attachment)
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
        XCTAssertFalse(element("entryKeypadAmount").exists)

        launch("v47-toast-short")
        let toast = element("toastMessage")
        let last = element("ledgerEntry_47000000-0000-0000-0000-000000471030")
        XCTAssertTrue(waitForStableFrame(element("toastBody")))
        XCTAssertTrue(revealControl(last, in: app, deadline: Date().addingTimeInterval(180), searching: element("entriesScroll")))
        XCTAssertTrue(toast.exists); XCTAssertTrue(last.isHittable)
        XCTAssertLessThanOrEqual(last.frame.maxY, toast.frame.minY - 12 + 0.5)
        XCTAssertLessThan(last.frame.maxY, element("addEntry").frame.minY)
        tapControl(last, in: app, reveals: false)
        XCTAssertTrue(element("entryKeypadAmount").waitForExistence(timeout: 5))
        dismissEntrySheet(in: app)
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
        XCTAssertEqual(amount("fundsFormula"), 35_000)
        tap("coverFromReserve")
        XCTAssertEqual(amount("fundsFormula"), 0)
        tap("undoLastChange")
        XCTAssertEqual(amount("fundsFormula"), 35_000)
    }
    func testRevisionCarryRevertAddsItsOwnRowAndUndoRestoresSavings() {
        launch("v47r-carry"); openInbox(); tap("leftoverKeep"); backToHome()
        XCTAssertEqual(amount("fundsFormula"), 248_400)
        tap("fundsFormula")
        XCTAssertEqual(amount("formulaRow_carry"), 62_000)
        back(); tap("undoLastChange")
        XCTAssertEqual(amount("fundsFormula"), 186_400)
        XCTAssertFalse(element("newCycleCard").exists)
    }
    func testRevisionFloorAppearsInFormula() {
        launch("v47r-floor"); tap("fundsFormula")
        XCTAssertEqual(amount("formulaRow_balanceGap"), -40_000)
        XCTAssertEqual(amount("formulaResult"), 146_400)
    }

}
