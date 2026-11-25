import XCTest

final class Round47RevisionFlowTests: YubaiUITestCase {
    private var app = XCUIApplication()
    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws { app.terminate(); try super.tearDownWithError() }
    private func element(_ id: String) -> XCUIElement { control(id, in: app) }
    private func watch(_ number: Int, _ mode: String = "amount") -> String {
        String(format: "47000000-0000-0000-0000-%012d", number) + ":" + mode
    }
    private func launch(_ script: String = "v47-spend", large: Bool = false, dark: Bool = false, hidden: Bool = false) {
        app.terminate()
        app.launchArguments = ["--test-ledger", UUID().uuidString, "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launchEnvironment["YUBAI_UI_TEST_SCRIPT"] = script
        app.launchEnvironment["YUBAI_UI_TEST_CONFIGURED_KEY"] = "1"
        app.launchEnvironment["YUBAI_UI_TEST_KEEP_UNDO"] = "1"
        app.launchEnvironment["YUBAI_UI_TEST_ENTRY_EXPLICIT_FINISH"] = "1"
        app.launchEnvironment["YUBAI_GALLERY_APPEARANCE"] = dark ? "dark" : "light"
        app.launchEnvironment["YUBAI_GALLERY_HIDE_AMOUNTS"] = hidden ? "1" : "0"
        app.launchEnvironment["YUBAI_UI_TEST_NOW"] = String(Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 20))!.timeIntervalSince1970)
        app.launchEnvironment["DEEPSEEK_API_KEY"] = ""
        launchApp(app); XCTAssertTrue(element("mainNavigation").waitForExistence(timeout: 15))
    }
    private func tap(_ id: String) {
        if id == "tab_yubai" {
            openAssistantHub()
            return
        }
        tapControl(element(id), in: app, settles: !id.hasPrefix("keypad_"), reveals: !id.hasPrefix("keypad_"))
    }

    private func backToHome() {
        for _ in 0..<8 {
            if element("tab_ledger").isHittable {
                if !element("tab_ledger").isSelected { tap("tab_ledger") }
                return
            }
            tap("BackButton")
        }
        XCTFail("未回到首页")
    }

    private func openAssistantHub() {
        backToHome()
        tap("openSettings"); tap("openAssistantHub")
    }

    private func openInbox() {
        openAssistantHub(); tap("openButlerInbox")
    }

    private func savingsTotal() -> String {
        backToHome()
        app.open(URL(string: "yubai://saving")!)
        XCTAssertTrue(element("reserveTotal").waitForExistence(timeout: 5))
        let total = element("reserveTotal").label
        tap("BackButton")
        return total
    }
    private func keys(_ number: String) { for key in number { tap("keypad_" + String(key)) } }
    private func expect(_ id: String, contains text: String) {
        XCTAssertTrue(UIConditionWait.run(timeout: 8, read: { self.element(id).exists && self.element(id).label.contains(text) }), "\(id): expected \(text), got \(element(id).label)")
    }
    private func gone(_ id: String) { XCTAssertTrue(waitForDisappearance(element(id)), id) }

    func testHiddenHardSettingsRowScrollsClearOfTheCapsuleAndOpensSettings() {
        launch("v47-ai-topup-hard", hidden: true)
        tap("tab_yubai")
        let scroll = element("yubaiScroll"), settings = element("openSettings")
        let deadline = Date().addingTimeInterval(90)
        XCTAssertTrue(waitForNativeTransition(in: app, deadline: deadline))
        XCTAssertTrue(waitForStableFrame(scroll, deadline: deadline))
        let before = settings.frame
        let needsScroll = before.maxY > scroll.frame.maxY + 0.5
        if needsScroll {
            let travel = windowMetrics(in: app)?.scroll(matching: scroll.frame)
            XCTAssertNotNil(travel)
            XCTAssertGreaterThanOrEqual(travel?.remainingDown ?? 0, before.maxY - scroll.frame.maxY - 0.5)
        }
        XCTAssertTrue(revealControl(settings, in: app, deadline: deadline, searching: scroll))
        XCTAssertTrue(scroll.frame.insetBy(dx: -0.5, dy: -0.5).contains(settings.frame))
        XCTAssertLessThanOrEqual(settings.frame.maxY, element("mainNavigation").frame.minY + 0.5)
        XCTAssertTrue(settings.isHittable)
        if needsScroll { XCTAssertLessThan(settings.frame.minY, before.minY - 0.5) }
        tapControl(settings, in: app, reveals: false)
        XCTAssertTrue(element("settingsScroll").waitForExistence(timeout: 5))
        tap("openIntelligencePrivacy")
        XCTAssertTrue(element("butlerLastRun").waitForExistence(timeout: 5))
        XCTAssertEqual(app.state, .runningForeground)
    }
    private func formula() { tap("fundsFormula"); XCTAssertTrue(element("formulaResult").waitForExistence(timeout: 5)) }
    private func reconcile(_ actual: String) {
        tap("reconcileField_招行储蓄卡"); keys(actual)
        tap("reconcileField_招行储蓄卡Done")
    }
    func testNormalHeroAndFormulaShareExactAmount() {
        launch(); expect("availableFunds", contains: "¥1,864.00"); formula(); expect("formulaResult", contains: "¥1,864.00")
        XCTAssertFalse(element("formulaRow_carry").exists); XCTAssertFalse(element("formulaRow_withdrawal").exists); XCTAssertFalse(element("formulaRow_balanceGap").exists)
    }
    func testFastHeroUsesAmberWaterState() {
        launch("v47r-fast"); expect("availableFunds", contains: "¥1,080.00")
        XCTAssertEqual(element("ledgerWaterBar").value as? String, "花得比日子快")
    }
    func testSavingLessStopsAtZeroWithoutRescueCard() {
        launch("v47r-less"); expect("availableFunds", contains: "¥0.00"); expect("ledgerStatus", contains: "这个月少攒 ¥200.00")
        XCTAssertFalse(element("deficitRescueCard").exists)
        formula(); expect("formulaRow_saving", contains: "原来 2,000.00 · 少攒 200.00"); expect("formulaResult", contains: "¥0.00")
    }
    func testDeficitNamesBillAndRescueIsUndoable() {
        launch("v47r-deficit"); expect("availableFunds", contains: "¥350.00")
        XCTAssertTrue(app.staticTexts["缺口"].exists); XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS '房租'")).firstMatch.exists)
        expect("coverFromReserve", contains: "拿出来用 ¥350.00"); XCTAssertFalse(element("dismissHomeCard").exists)
        tap("coverFromReserve"); expect("availableFunds", contains: "¥0.00"); gone("deficitRescueCard")
        tap("undoLastChange"); expect("availableFunds", contains: "¥350.00"); XCTAssertTrue(element("deficitRescueCard").exists)
    }
    func testDeficitRescueScrollsAboveCompactChromeBeforeTapInAllAppearances() {
        for mode in [(false, false, false), (true, false, false), (true, true, false), (true, false, true), (true, true, true)] {
            launch("v47r-deficit", large: mode.0, dark: mode.1, hidden: mode.2)
            let scroll = element("entriesScroll"), rescue = element("coverFromReserve"), keep = element("deficitKeep")
            XCTAssertTrue(waitForStableFrame(rescue))
            let before = rescue.frame
            let initial = windowMetrics(in: app)?.scroll(matching: scroll.frame)
            let needsScroll = before.maxY > scroll.frame.maxY + 0.5
            if needsScroll {
                XCTAssertGreaterThan(initial?.remainingDown ?? 0, before.maxY - scroll.frame.maxY,
                                     "A rescue below the viewport must have enough native scroll travel")
                XCTAssertTrue(initial?.panOrigins?.contains(where: {
                    $0.x < 20 && $0.y > scroll.frame.minY + 12 && $0.y < scroll.frame.maxY - 12
                }) == true, "The native List gutter must accept a pan above the floating chrome")
            }
            // First reveal the same single action the Rescued gallery stop
            // taps, then keep the stricter simultaneous-answer/fade proof.
            XCTAssertTrue(revealControl(rescue, in: app, deadline: Date().addingTimeInterval(60), searching: scroll))
            XCTAssertTrue(rescue.isHittable)
            XCTAssertLessThanOrEqual(rescue.frame.maxY, element("mainNavigation").frame.minY + 0.5)
            XCTAssertTrue(revealControlsTogether([rescue, keep], in: app, deadline: Date().addingTimeInterval(60),
                                                searching: scroll, bottomClearance: 40))
            for button in [rescue, keep] {
                XCTAssertTrue(button.isHittable)
                XCTAssertLessThanOrEqual(button.frame.maxY, scroll.frame.maxY - 40 + 0.5)
                XCTAssertLessThan(button.frame.maxY, element("addEntry").frame.minY)
                XCTAssertLessThan(button.frame.maxY, capsuleFrame(in: app).minY)
            }
            if needsScroll { XCTAssertLessThan(rescue.frame.minY, before.minY - 0.5) }
            tap("coverFromReserve")
            gone("deficitRescueCard"); expect("availableFunds", contains: mode.2 ? "¥••••" : "¥0.00")
            tap("undoLastChange")
            XCTAssertTrue(element("deficitRescueCard").waitForExistence(timeout: 5))
            XCTAssertEqual(app.state, .runningForeground)
        }
    }
    func testDeficitKeepLeavesHeadlineAndConsumesCardAcrossRelaunch() {
        launch("v47r-deficit"); tap("deficitKeep"); gone("deficitRescueCard"); expect("availableFunds", contains: "¥350.00")
        app.terminate(); launchApp(app); gone("deficitRescueCard"); expect("availableFunds", contains: "¥350.00")
    }
    func testDeficitFormulaShowsZeroSavingAndPositiveDeficit() {
        launch("v47r-deficit"); formula(); expect("formulaRow_saving", contains: "这个月攒不了"); expect("formulaResult", contains: "¥350.00")
        XCTAssertFalse(element("formulaResult").label.contains("−"))
        tap("formulaRow_saving"); expect("formulaEditResult", contains: "改完缺口"); expect("formulaEditResult", contains: "350.00")
        tap("amountSheetCancel")
    }
    func testKnownSalaryWithoutPostedIncomeUsesSpentFallback() {
        launch("v47r-no-income"); XCTAssertTrue(app.staticTexts["这个月花了"].exists)
        expect("availableFunds", contains: "¥836.00"); XCTAssertFalse(element("ledgerWaterBar").exists); XCTAssertFalse(element("fundsFormula").exists)
    }
    func testCarryReleaseAddsSeparateRowAndUndoDoesNotRepeatNotice() {
        launch("v47r-carry"); openInbox(); expect("carryNoticeText", contains: "上期省下 620.00 已存好")
        tap("leftoverKeep"); gone("newCycleCard"); backToHome(); expect("availableFunds", contains: "¥2,484.00")
        formula(); expect("formulaRow_carry", contains: "620.00"); tap("BackButton")
        tap("undoLastChange"); expect("availableFunds", contains: "¥1,864.00"); gone("newCycleCard")
        app.terminate(); launchApp(app); gone("newCycleCard")
    }
    func testCarryDismissKeepsSavingsAcrossRelaunch() {
        launch("v47r-carry-fast", dark: true); let saved = savingsTotal()
        openInbox(); tap("leftoverDismiss"); gone("newCycleCard"); XCTAssertEqual(savingsTotal(), saved)
        app.terminate(); launchApp(app); openAssistantHub()
        XCTAssertFalse(element("openButlerInbox").exists)
        XCTAssertEqual(savingsTotal(), saved)
    }
    func testTakenAndFloorRowsOpenTheirActualSources() {
        launch("v47r-taken"); formula(); expect("formulaRow_withdrawal", contains: "350.00"); tap("formulaRow_withdrawal")
        XCTAssertTrue(element("reserveLine_0").waitForExistence(timeout: 5))
        launch("v47r-floor"); formula(); expect("formulaRow_balanceGap", contains: "400.00"); tap("formulaRow_balanceGap")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'ledgerEntry_'")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(element("reconcileSheet").exists)
    }
    func testSoftLinesShowRemainingCountExceededAndSharedEditor() {
        launch("v47r-soft-lines"); formula()
        expect("softLine_" + watch(478201), contains: "320.00")
        expect("softLine_" + watch(478202, "count"), contains: "4 次")
        expect("softLine_" + watch(478203), contains: "超出 80.00")
        tap("softLine_" + watch(478201)); keys("900"); tap("saveSoftLine")
        expect("softLine_" + watch(478201), contains: "420.00")
        tap("BackButton"); tap("tab_yubai"); tap("openProfile")
        expect("profileArea_" + String(format: "47000000-0000-0000-0000-%012d", 478201), contains: "900.00")
    }
    func testLargestSoftLineEditorsRevealTheirVirtualizedRowsInTheOwningPage() {
        launch("v47r-soft-lines", large: true); formula()
        let watchRow = element("softLine_" + watch(478201))
        XCTAssertTrue(revealControl(watchRow, in: app, deadline: Date().addingTimeInterval(60), searching: element("formulaPage")))
        tapControl(watchRow, in: app); keys("900"); tap("saveSoftLine")
        expect("softLine_" + watch(478201), contains: "420.00")
        tap("BackButton"); tap("tab_insights"); tap("insightCategory_0")
        let countMode = element("modeSoftLine_" + watch(478201))
        XCTAssertTrue(revealControl(countMode, in: app, deadline: Date().addingTimeInterval(60), searching: element("whereCategoryPage")))
        tapControl(countMode, in: app); keys("5"); tap("saveSoftLine")
        let countRow = element("softLine_" + watch(478201, "count"))
        XCTAssertTrue(revealControl(countRow, in: app, deadline: Date().addingTimeInterval(60), searching: element("whereCategoryPage")))
        expect("softLine_" + watch(478201, "count"), contains: "还剩 4 次")
    }
    func testReconcileReceiptShowsFullAdjustmentAndUndoAcrossAllGalleryModes() {
        for mode in galleryModes {
            launch("v47r-reconcile-floor", large: mode.large, dark: mode.dark, hidden: mode.hidden)
            tap("tab_yubai"); tap("openAccounts"); tap("reconcileAll")
            reconcile("9774"); tap("reconcileApply")
            let message = element("toastMessage"), undo = element("undoLastChange")
            XCTAssertTrue(message.waitForExistence(timeout: 5))
            XCTAssertTrue(waitForStableFrame(message))
            XCTAssertEqual(message.label, mode.hidden ? "已记调整 ••••" : "已记调整 −2,400.00")
            if mode.large { XCTAssertGreaterThanOrEqual(undo.frame.minY, message.frame.maxY) }
            else {
                XCTAssertGreaterThanOrEqual(undo.frame.minX, message.frame.maxX)
                XCTAssertFalse(element("expandToast").exists, "A short receipt must fit beside undo")
            }
            XCTAssertTrue(undo.isHittable)
            XCTAssertNoThrow(try auditAppText(in: app) { issue in
                if let target = issue.element, target.label.contains("已记调整") {
                    XCTFail("Adjustment receipt must wrap without clipping: " + issue.detailedDescription)
                }
                return true
            })
            tap("undoLastChange"); expect("toastMessage", contains: "已撤销")
        }
    }
    private var galleryModes: [(large: Bool, dark: Bool, hidden: Bool)] {
        [(false, false, false), (false, true, false), (false, false, true), (true, false, false)]
    }
    func testReconcilePresentationAndCaptureStaySettledAcrossGalleryModes() throws {
        for mode in galleryModes {
            // Match Entry-Recon's route and original stop bound. No focused
            // field or raster is required on this fully presented paper sheet.
            let deadline = Date().addingTimeInterval(90)
            launch("v47r-reconcile", large: mode.large, dark: mode.dark, hidden: mode.hidden)
            let open = element("openReconcile")
            XCTAssertTrue(revealControl(open, in: app, deadline: deadline))
            XCTAssertTrue(waitForStableFrame(open, deadline: deadline))
            rememberTap(open, in: app); open.tap()
            let apply = element("reconcileApply")
            XCTAssertTrue(waitForNativeTransition(in: app, deadline: deadline), transitionWaitReport)
            XCTAssertTrue(waitForStableFrame(apply, deadline: deadline))
            let capture = waitForBambooCapture(in: app, deadline: deadline)
            XCTAssertTrue(capture.ready, capture.description)
            XCTAssertEqual(capture.surface?.required, false, capture.description)
            for _ in 0..<3 {
                XCTAssertLessThan(Date(), deadline)
                let metrics = windowMetrics(in: app)
                XCTAssertNotNil(metrics, "The modal probe must stay readable")
                XCTAssertEqual(metrics?.transitioning, false, transitionWaitReport)
                XCTAssertEqual(metrics?.activeTransitions, [])
            }
            XCTAssertFalse(app.keyboards.firstMatch.exists)
            try auditAppText(in: app, dynamicType: true) { issue in
                XCTFail("Reconcile sheet text must grow without clipping: " + issue.detailedDescription)
                return true
            }
            XCTAssertTrue(waitForNativeTransition(in: app, deadline: Date().addingTimeInterval(12)), transitionWaitReport)
            XCTAssertEqual(app.state, .runningForeground)
            XCTAssertFalse(XCUIScreen.main.screenshot().pngRepresentation.isEmpty)
            tap("reconcileApply"); gone("reconcileByHand")
            XCTAssertEqual(app.state, .runningForeground)
        }
    }
    func testSavingSegmentsKeepBothCompleteLabelsAcrossAllGalleryModes() {
        savingSegments("v47r-deficit")
    }
    func testNormalSavingSegmentsKeepBothCompleteLabelsAcrossAllGalleryModes() {
        savingSegments("v47-spend")
    }
    private func savingSegments(_ fixture: String) {
        // Native Dynamic Type audits also change size while this sheet is up.
        // Cover both appearances with and without hidden amounts at each end.
        for mode in [false, true].flatMap({ large in
            [false, true].flatMap { dark in
                [false, true].map { hidden in (large: large, dark: dark, hidden: hidden) }
            }
        }) {
            launch(fixture, large: mode.large, dark: mode.dark, hidden: mode.hidden)
            formula(); tap("formulaRow_saving")
            let galleryMode = mode.large ? "a11y" : mode.hidden ? "hidden" : mode.dark ? "dark" : "light"
            let stop = "V47-\(galleryMode)-Spend-Edit-" + (fixture == "v47r-deficit" ? "Deficit" : "Saving")
            let fixed = element("savingMode_fixed"), share = element("savingMode_share")
            XCTAssertTrue(waitForStableFrame(fixed))
            XCTAssertTrue(waitForStableFrame(share))
            if mode.large {
                XCTAssertGreaterThanOrEqual(share.frame.minY, fixed.frame.maxY)
                XCTAssertGreaterThan(fixed.frame.height, 44.5)
                XCTAssertGreaterThan(share.frame.height, 44.5)
            } else {
                XCTAssertEqual(fixed.frame.midY, share.frame.midY, accuracy: 0.5)
                XCTAssertEqual(fixed.frame.width, share.frame.width, accuracy: 0.5)
                XCTAssertEqual(fixed.frame.height, 44, accuracy: 0.5)
                XCTAssertEqual(share.frame.height, 44, accuracy: 0.5)
            }
            for (id, title) in [("savingMode_fixed", "固定金额"), ("savingMode_share", "每笔进账留几成")] {
                let segment = element(id)
                XCTAssertTrue(segment.waitForExistence(timeout: 5))
                XCTAssertEqual(app.buttons.matching(identifier: id).count, 1)
                XCTAssertEqual(segment.label, title)
                XCTAssertGreaterThanOrEqual(segment.frame.width, 43.5)
                XCTAssertGreaterThanOrEqual(segment.frame.height, 43.5)
                tap(id)
                XCTAssertTrue(segment.isSelected)
                XCTAssertNoThrow(try auditAppText(in: app, dynamicType: true) { issue in
                    if let warning = GalleryTextReview.warning(stop: stop, issue: issue) {
                        print("GALLERY-WARNING " + warning)
                        return true
                    }
                    XCTFail("Saving sheet text must grow without clipping: " + issue.detailedDescription)
                    return true
                })
                XCTAssertEqual(app.state, .runningForeground)
                XCTAssertTrue(waitForNativeTransition(in: app, deadline: Date().addingTimeInterval(12)))
                XCTAssertTrue(waitForStableFrame(segment))
                XCTAssertEqual(segment.label, title)
                XCTAssertTrue(segment.isSelected)
                XCTAssertEqual(app.buttons.matching(identifier: id).count, 1)
            }
            tap("amountSheetCancel")
        }
    }
    func testLargestDeficitRescueRevealsAboveTheEntryPillAndRemainsUndoable() {
        launch("v47r-deficit", large: true)
        let rescue = element("coverFromReserve")
        XCTAssertTrue(revealControl(rescue, in: app, deadline: Date().addingTimeInterval(60), searching: element("entriesScroll")))
        XCTAssertLessThanOrEqual(rescue.frame.maxY, element("addEntry").frame.minY)
        XCTAssertTrue(rescue.isHittable)
        tapControl(rescue, in: app); expect("availableFunds", contains: "¥0.00"); gone("deficitRescueCard")
        tap("undoLastChange"); expect("availableFunds", contains: "¥350.00")
    }
    func testSoftLineKeypadClearsTheSubmittedSystemKeyboardAcrossAllGalleryModes() {
        for mode in galleryModes {
            launch("v47r-soft-lines", large: mode.large, dark: mode.dark, hidden: mode.hidden)
            tap("addEntry"); typeIntoField("外卖\n", identifier: "entryPurpose", in: app)
            XCTAssertFalse(app.keyboards.firstMatch.exists)
            for key in ["3", "8"] {
                let target = element("keypad_" + key)
                XCTAssertTrue(revealControl(target, in: app, deadline: Date().addingTimeInterval(20)))
                XCTAssertTrue(target.isHittable)
                XCTAssertTrue(app.frame.contains(target.frame))
                tapControl(target, in: app, settles: false)
            }
            expect("entrySavingHint", contains: mode.hidden ? "••••" : "282.00")
            tap("saveQuickEntry"); expect("entrySessionSummary", contains: "1 笔")
        }
    }
    func testLargestSoftLineKeypadHandoffsSettleAndCategoryRowScrollsClear() {
        for dark in [false, true] {
            for (fixture, purpose, amount, expected) in [
                ("v47r-soft-lines", "外卖", "38", "282.00"),
                ("v47r-soft-lines", "外卖", "338", "18.00"),
                ("v47r-soft-count", "咖啡", "18", "3 次")
            ] {
                // Compare the real shared chip at default and largest size.
                launch(fixture, dark: dark); tap("addEntry"); tap("entryNature_income")
                let ordinaryChip = element("entryCategory_工资")
                XCTAssertTrue(ordinaryChip.waitForExistence(timeout: 5))
                XCTAssertTrue(waitForStableFrame(ordinaryChip))
                let ordinaryHeight = ordinaryChip.frame.height
                launch(fixture, large: true, dark: dark); tap("addEntry")
                typeIntoField(purpose + "\n", identifier: "entryPurpose", in: app)
                XCTAssertEqual(element("entryPurpose").value as? String, purpose)
                XCTAssertFalse(app.keyboards.firstMatch.exists)
                // A second keyboard cycle must also be observed and completed.
                typeIntoField("\n", identifier: "entryPurpose", in: app)
                XCTAssertEqual(element("entryPurpose").value as? String, purpose)
                XCTAssertFalse(app.keyboards.firstMatch.exists)
                keys(amount); expect("entrySavingHint", contains: expected)
                let deadline = Date().addingTimeInterval(20)
                XCTAssertTrue(waitForNativeTransition(in: app, deadline: deadline))
                let metrics = windowMetrics(in: app)
                XCTAssertEqual(metrics?.transitioning, false)
                XCTAssertEqual(metrics?.focused, "")
                XCTAssertEqual(metrics?.activeTransitions, [])
                let scroll = element("entryFormScroll"), row = element("entryCategoryGrid")
                let chip = element("entryCategory_餐饮"), tray = element("fixedBottomBar")
                XCTAssertTrue(revealControl(chip, in: app, deadline: Date().addingTimeInterval(60), searching: scroll))
                XCTAssertGreaterThan(chip.frame.height, ordinaryHeight + 8)
                XCTAssertTrue(row.frame.insetBy(dx: -0.5, dy: -0.5).contains(chip.frame))
                XCTAssertTrue(scroll.frame.insetBy(dx: -0.5, dy: -0.5).contains(chip.frame))
                XCTAssertLessThanOrEqual(chip.frame.maxY, tray.frame.minY - 8)
                XCTAssertTrue(chip.isHittable)
                tap("entryCategory_餐饮"); XCTAssertTrue(chip.isSelected)
                let more = element("entryCategoryMore")
                XCTAssertTrue(revealControl(more, in: app, deadline: Date().addingTimeInterval(60), searching: row))
                XCTAssertLessThanOrEqual(more.frame.maxY, tray.frame.minY - 8)
                tap("entryCategoryMore"); XCTAssertTrue(element("entryCategoryPicker").waitForExistence(timeout: 5))
                tap("entryMoreCancel"); tap("saveQuickEntry")
                expect("entrySessionSummary", contains: "1 笔")
                XCTAssertEqual(app.state, .runningForeground)
            }
        }
    }
    func testCategoryPlaceFactsWrapWithoutClippingAcrossAllGalleryModes() {
        for mode in galleryModes {
            launch("v47r-soft-lines", large: mode.large, dark: mode.dark, hidden: mode.hidden)
            tap("tab_insights"); tap("insightCategory_0")
            let places = element("whereCategoryPlaces")
            XCTAssertTrue(revealControl(places, in: app, deadline: Date().addingTimeInterval(60), searching: element("whereCategoryPage")))
            XCTAssertNoThrow(try auditAppText(in: app) { issue in
                if let target = issue.element, target.label.contains("外卖") && target.label.contains("次") {
                    XCTFail("Place and count must wrap or stack: " + issue.detailedDescription)
                }
                return true
            })
        }
    }
    func testUnwatchedFormulaHasOnlyTheAddWatchRow() {
        launch(); formula(); XCTAssertFalse(element("softLineWatches").exists)
        tap("addSoftLine"); tap("entryMoreCategory_购物"); keys("800"); tap("saveSoftLine")
        XCTAssertTrue(element("softLineWatches").waitForExistence(timeout: 5)); XCTAssertFalse(app.alerts.firstMatch.exists)
    }
    func testInsightsCategoryStatusAndCountEditingUseSameWatches() {
        launch("v47r-soft-lines"); tap("tab_insights"); expect("insightSoftLine_" + watch(478201), contains: "外卖还剩 320.00")
        expect("insightSoftLine_" + watch(478203), contains: "打车超出 80.00")
        tap("insightCategory_0"); tap("modeSoftLine_" + watch(478201)); keys("5"); tap("saveSoftLine")
        expect("softLine_" + watch(478201, "count"), contains: "还剩 4 次")
        tap("removeSoftLine_" + watch(478201, "count")); gone("softLine_" + watch(478201, "count"))
        tap("undoLastChange"); XCTAssertTrue(element("softLine_" + watch(478201, "count")).exists)
    }
    func testCategoryCanWatchWholeCategoryInOneAmountSheet() {
        launch(); tap("tab_insights"); tap("insightCategory_0"); tap("addSoftLine"); keys("1200"); tap("saveSoftLine")
        XCTAssertTrue(element("softLineWatches").waitForExistence(timeout: 5))
    }
    func testMismatchReconciliationRemovesCardAndUpdatesRealDate() {
        launch("v47r-mismatch"); openInbox(); expect("mismatchText", contains: "账面比卡里多 412.00")
        tap("openReconcile"); reconcile("10174"); XCTAssertFalse(element("reconcileSpendableAfter").exists)
        tap("reconcileApply"); gone("balanceMismatchCard"); tap("tab_yubai"); expect("openAccounts", contains: "上次 11月20日")
        app.terminate(); launchApp(app); gone("balanceMismatchCard")
    }
    func testCoveredReconciliationCreatesAdjustmentWithoutChangingHeadline() {
        launch("v47r-reconcile-covered"); tap("tab_yubai"); tap("openAccounts"); tap("reconcileAll")
        reconcile("11762"); expect("reconcileApply", contains: "记成调整 −412.00")
        XCTAssertFalse(element("reconcileSpendableAfter").exists); tap("reconcileApply"); backToHome()
        expect("availableFunds", contains: "¥1,864.00")
    }
    func testFloorPreviewIsConditionalAndReplacesCurrentGap() {
        launch("v47r-reconcile-floor"); tap("tab_yubai"); tap("openAccounts"); tap("reconcileAll")
        reconcile("9774"); expect("reconcileSpendableAfter", contains: "1,464.00"); expect("reconcileApply", contains: "−2,400.00")
        tap("reconcileApply"); backToHome(); expect("availableFunds", contains: "¥1,464.00")
        formula(); expect("formulaRow_balanceGap", contains: "400.00")
    }
    func testNextPeriodYearlyAndQuarterlyBillCardsDismissOrOpenBill() {
        for script in ["v47r-next-bill", "v47r-next-quarterly"] {
            launch(script); openInbox(); expect("billHeadsUpText", contains: script == "v47r-next-bill" ? "一年一次" : "一季一次")
            tap("openBillHeadsUp"); XCTAssertTrue(element("billDetailAmount").waitForExistence(timeout: 5))
            tap("BackButton"); gone("billHeadsUpCard")
        }
    }
    func testPaydayTopupUsesBoardButtonsAndRevealsOnlyTheNextCard() {
        launch("v47-topup-queue"); openInbox(); expect("savingsTopupAll", contains: "补回 ¥500.00"); expect("savingsTopupDecline", contains: "不补")
        XCTAssertFalse(element("renewalCard").exists); XCTAssertFalse(element("dismissHomeCard").exists)
        tap("savingsTopupDecline"); gone("savingsTopupCard"); XCTAssertTrue(element("renewalCard").waitForExistence(timeout: 5))
    }
    func testYearlyAndAISuggestionsCanCloseWithoutExecutingAnAction() {
        for (script, close, card) in [("v47r-next-bill", "dismissBillHeadsUp", "billHeadsUpCard"),
                                      ("v47r-suggestion", "dismissHomeCard", "butlerSuggestionCard"),
                                      ("v47r-weekly-ai", "dismissHomeCard", "butlerSuggestionCard")] {
            launch(script); openInbox(); tap(close); gone(card)
            app.terminate(); launchApp(app); gone(card)
        }
    }
    func testLongCardExpandsInPlaceAtDefaultText() {
        launch("v47r-weekly-ai-long"); openInbox()
        XCTAssertTrue(element("expandButlerHeadline").waitForExistence(timeout: 5))
        let headline = element("butlerAIText")
        XCTAssertTrue(headline.waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts.matching(identifier: "butlerAIText").count, 1)
        let fullLabel = headline.label
        XCTAssertTrue(fullLabel.contains("周三周四试试带饭？"))
        XCTAssertEqual(headline.value as? String, "已收起")
        XCTAssertTrue(waitForStableFrame(headline))
        let before = headline.frame.height
        XCTAssertGreaterThan(before, 0)
        tap("expandButlerHeadline")
        XCTAssertEqual(element("expandButlerHeadline").value as? String, "已展开")
        XCTAssertTrue(UIConditionWait.run(timeout: 5, read: { headline.frame.height > before }))
        XCTAssertGreaterThan(headline.frame.height, before)
        XCTAssertEqual(headline.label, fullLabel)
        XCTAssertEqual(headline.value as? String, "已展开")
        XCTAssertNoThrow(try auditAppText(in: app) { issue in
            if let target = issue.element, ["butlerAIText", "butlerAIAccept"].contains(target.identifier) {
                XCTFail("Expanded text/action must be fully legible: " + target.identifier + " " + issue.detailedDescription)
            }
            return true
        })
        XCTAssertTrue(element("butlerAIAccept").exists)
    }
    private func checkLargestButlerCards(dark: Bool = false, hidden: Bool = false) {
        let fixtures: [(String, String, String, [String])] = [
            ("v47r-weekly-ai", "butlerSuggestionCard", "butlerAIText", ["butlerAIAccept", "butlerAIIncorrect"]),
            ("v47r-weekly-ai-long", "butlerSuggestionCard", "butlerAIText", ["butlerAIAccept", "butlerAIIncorrect"]),
            ("v47r-suggestion", "butlerSuggestionCard", "butlerAIText", ["butlerAIAccept", "butlerAIIncorrect"]),
            ("v47r-carry", "newCycleCard", "carryNoticeText", ["leftoverKeep"]),
            ("v47r-mismatch", "balanceMismatchCard", "mismatchText", ["openReconcile"]),
            ("v47r-next-bill", "billHeadsUpCard", "billHeadsUpText", ["openBillHeadsUp"]),
            ("v47r-deficit", "deficitRescueCard", "deficitRescueText", ["coverFromReserve", "deficitKeep"]),
            ("v47-topup", "savingsTopupCard", "", ["savingsTopupAll", "savingsTopupDecline"]),
            ("v47-ai-review", "butlerAIReviewCard", "", ["butlerAIReviewDone", "butlerAIReviewNever"])
        ]
        for (fixture, card, title, answers) in fixtures {
            launch(fixture, large: true, dark: dark, hidden: hidden); openInbox()
            let headline = title.isEmpty ? element(card).staticTexts.matching(NSPredicate(format: "value == %@", "已展开")).firstMatch : element(title)
            XCTAssertTrue(headline.waitForExistence(timeout: 8), fixture)
            XCTAssertEqual(headline.value as? String, "已展开", fixture)
            XCTAssertFalse(element("expandButlerHeadline").exists, "Accessibility text must never collapse: " + fixture)
            let targets = answers.map(element)
            XCTAssertTrue(revealControlsTogether(targets, in: app, deadline: Date().addingTimeInterval(60),
                searching: element("butlerInboxScroll"), bottomClearance: 40), fixture)
            let scroll = element("butlerInboxScroll")
            XCTAssertFalse(element("mainNavigation").exists, fixture)
            for target in targets {
                XCTAssertTrue(target.isHittable, fixture)
                XCTAssertGreaterThanOrEqual(target.frame.height, 44, fixture)
                XCTAssertGreaterThanOrEqual(target.frame.minY, scroll.frame.minY - 0.5, fixture)
                XCTAssertLessThanOrEqual(target.frame.maxY, scroll.frame.maxY - 40 + 0.5, fixture)
            }
            let labels = Set(targets.map(\.label) + [headline.label])
            XCTAssertNoThrow(try auditAppText(in: app) { issue in
                if let target = issue.element, answers.contains(target.identifier) || (!title.isEmpty && target.identifier == title) || labels.contains(target.label) {
                    XCTFail("Full headline and answer text must not clip: " + fixture + " " + issue.detailedDescription)
                }
                return true
            })
            app.terminate()
        }
    }
    func testLargestButlerHeadlinesAndAnswersClearFloatingChromeInLight() {
        checkLargestButlerCards()
    }
    func testLargestButlerHeadlinesAndAnswersClearFloatingChromeInDark() {
        checkLargestButlerCards(dark: true)
    }
    func testLargestButlerHeadlinesAndAnswersClearFloatingChromeWithHiddenAmounts() {
        checkLargestButlerCards(hidden: true)
    }
    func testLargestButlerHeadlinesAndAnswersClearFloatingChromeInDarkWithHiddenAmounts() {
        checkLargestButlerCards(dark: true, hidden: true)
    }
    func testSoftLineSuggestionWritesExistingProfileAndCorrectionWritesMemory() {
        launch("v47r-suggestion"); openInbox(); expect("butlerAIAccept", contains: "盯住外卖 ¥800.00")
        tap("butlerAIAccept"); gone("butlerSuggestionCard"); formula(); XCTAssertTrue(element("softLineWatches").waitForExistence(timeout: 5))
        launch("v47r-weekly-ai"); openInbox(); tap("butlerAIIncorrect"); typeIntoField("周四是和同事拼单", identifier: "butlerAICorrectionText", in: app); tap("butlerAICorrectionSave")
        gone("butlerSuggestionCard"); tap("tab_yubai"); tap("openMemories")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS '周四是和同事拼单'")).firstMatch.waitForExistence(timeout: 5))
    }
    func testOverdueBillIsNamedInDeficitAndFormulaBillSources() {
        launch("v47r-overdue"); expect("ledgerGapBill", contains: "上期未付房租")
        formula(); tap("formulaRow_bills"); XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS '上期未付房租'")).firstMatch.waitForExistence(timeout: 5))
    }
    func testHiddenLargestDarkKeepHeroCardFormulaAndSoftLineActions() {
        launch("v47r-carry-fast", large: true, dark: true, hidden: true)
        XCTAssertEqual(element("availableFunds").label, "金额已隐藏"); XCTAssertTrue(element("ledgerWaterBar").exists)
        expect("carryNoticeText", contains: "••••"); tap("leftoverKeep"); formula(); XCTAssertEqual(element("formulaResult").label, "金额已隐藏")
        launch("v47r-soft-lines", large: true, dark: true, hidden: true); formula(); tap("softLine_" + watch(478201)); XCTAssertTrue(element("saveSoftLine").isHittable)
        launch("v47r-less", hidden: true); expect("ledgerStatus", contains: "这个月少攒 ¥••••")
        launch("v47r-suggestion", hidden: true); expect("butlerAIAccept", contains: "盯住外卖 ¥••••")
    }
}
