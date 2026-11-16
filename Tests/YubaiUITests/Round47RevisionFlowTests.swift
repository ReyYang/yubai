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
    private func tap(_ id: String) { tapControl(element(id), in: app, settles: !id.hasPrefix("keypad_"), reveals: !id.hasPrefix("keypad_")) }
    private func keys(_ number: String) { for key in number { tap("keypad_" + String(key)) } }
    private func expect(_ id: String, contains text: String) {
        XCTAssertTrue(UIConditionWait.run(timeout: 8, read: { self.element(id).exists && self.element(id).label.contains(text) }), "\(id): expected \(text), got \(element(id).label)")
    }
    private func gone(_ id: String) { XCTAssertTrue(waitForDisappearance(element(id)), id) }
    private func formula() { tap("fundsFormula"); XCTAssertTrue(element("formulaResult").waitForExistence(timeout: 5)) }
    private func reconcile(_ actual: String) {
        tap("reconcileField_招行储蓄卡"); keys(actual)
        tap("reconcileField_招行储蓄卡Done")
    }
    private func enter(_ purpose: String, amount: String) {
        tap("addEntry")
        XCTAssertTrue(element("entryKeypadAmount").waitForExistence(timeout: 5))
        typeIntoField(purpose + "\n", identifier: "entryPurpose", in: app)
        keys(amount)
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
        launch("v47r-carry"); expect("carryNoticeText", contains: "上期省下 620.00 已存好")
        tap("leftoverKeep"); gone("newCycleCard"); expect("availableFunds", contains: "¥2,484.00")
        formula(); expect("formulaRow_carry", contains: "620.00"); tap("BackButton")
        tap("undoLastChange"); expect("availableFunds", contains: "¥1,864.00"); gone("newCycleCard")
        app.terminate(); launchApp(app); gone("newCycleCard")
    }
    func testCarryDismissKeepsSavingsAcrossRelaunch() {
        launch("v47r-carry-fast", dark: true); let saved = element("openSaving").label
        tap("leftoverDismiss"); gone("newCycleCard"); XCTAssertEqual(element("openSaving").label, saved)
        app.terminate(); launchApp(app); gone("newCycleCard"); XCTAssertEqual(element("openSaving").label, saved)
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
            XCTAssertEqual(message.label, mode.hidden ? "已记调整 −••••" : "已记调整 −2,400.00")
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
    func testSavingSegmentsKeepBothCompleteLabelsAcrossAllGalleryModes() {
        for mode in galleryModes {
            launch("v47r-deficit", large: mode.large, dark: mode.dark, hidden: mode.hidden)
            formula(); tap("formulaRow_saving")
            for id in ["savingMode_fixed", "savingMode_share"] {
                let segment = element(id)
                XCTAssertTrue(segment.waitForExistence(timeout: 5))
                XCTAssertEqual(app.buttons.matching(identifier: id).count, 1)
                XCTAssertGreaterThanOrEqual(segment.frame.height, 43.5)
                tap(id)
                XCTAssertTrue(segment.isSelected)
                XCTAssertNoThrow(try auditAppText(in: app) { issue in
                    if let target = issue.element, ["固定金额", "每笔进账留几成"].contains(target.label) {
                        XCTFail("Saving segment clipped: " + issue.detailedDescription)
                    }
                    return true
                })
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
    func testEntryStripPreviewsRemainingLiveAndStillSavesWhenExceeded() {
        launch("v47r-soft-lines"); enter("外卖", amount: "38")
        expect("entrySavingHint", contains: "282.00")
        tap("keypad_0"); expect("entrySavingHint", contains: "超出")
        XCTAssertTrue(element("saveQuickEntry").isEnabled); tap("saveQuickEntry"); expect("entrySessionSummary", contains: "1 笔")
    }
    func testEntryCountAndUnwatchedStrip() {
        launch("v47r-soft-count"); enter("咖啡", amount: "18"); expect("entrySavingHint", contains: "咖啡还剩"); expect("entrySavingHint", contains: "3 次")
        launch("v47r-soft-lines"); tap("addEntry"); tap("entryCategory_购物"); keys("38"); expect("entrySavingHint", contains: "还能花")
    }
    func testEntryStripExceededBy18() {
        launch("v47r-soft-lines"); enter("外卖", amount: "338"); expect("entrySavingHint", contains: "外卖超出"); expect("entrySavingHint", contains: "18.00")
        XCTAssertTrue(element("saveQuickEntry").isEnabled)
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
        launch("v47r-mismatch"); expect("mismatchText", contains: "账面比卡里多 412.00")
        tap("openReconcile"); reconcile("10174"); XCTAssertFalse(element("reconcileSpendableAfter").exists)
        tap("reconcileApply"); gone("balanceMismatchCard"); tap("tab_yubai"); expect("openAccounts", contains: "上次 11月20日")
        app.terminate(); launchApp(app); gone("balanceMismatchCard")
    }
    func testCoveredReconciliationCreatesAdjustmentWithoutChangingHeadline() {
        launch("v47r-reconcile-covered"); tap("tab_yubai"); tap("openAccounts"); tap("reconcileAll")
        reconcile("11762"); expect("reconcileApply", contains: "记成调整 −412.00")
        XCTAssertFalse(element("reconcileSpendableAfter").exists); tap("reconcileApply"); tap("BackButton"); tap("tab_ledger")
        expect("availableFunds", contains: "¥1,864.00")
    }
    func testFloorPreviewIsConditionalAndReplacesCurrentGap() {
        launch("v47r-reconcile-floor"); tap("tab_yubai"); tap("openAccounts"); tap("reconcileAll")
        reconcile("9774"); expect("reconcileSpendableAfter", contains: "1,464.00"); expect("reconcileApply", contains: "−2,400.00")
        tap("reconcileApply"); tap("BackButton"); tap("tab_ledger"); expect("availableFunds", contains: "¥1,464.00")
        formula(); expect("formulaRow_balanceGap", contains: "400.00")
    }
    func testNextPeriodYearlyAndQuarterlyBillCardsDismissOrOpenBill() {
        for script in ["v47r-next-bill", "v47r-next-quarterly"] {
            launch(script); expect("billHeadsUpText", contains: script == "v47r-next-bill" ? "一年一次" : "一季一次")
            tap("openBillHeadsUp"); XCTAssertTrue(element("billDetailAmount").waitForExistence(timeout: 5))
            tap("BackButton"); gone("billHeadsUpCard")
        }
    }
    func testPaydayTopupUsesBoardButtonsAndRevealsOnlyTheNextCard() {
        launch("v47-topup-queue"); expect("savingsTopupAll", contains: "补回 ¥500.00"); expect("savingsTopupDecline", contains: "不补")
        XCTAssertFalse(element("renewalCard").exists); XCTAssertFalse(element("dismissHomeCard").exists)
        tap("savingsTopupDecline"); gone("savingsTopupCard"); XCTAssertTrue(element("renewalCard").waitForExistence(timeout: 5))
    }
    func testYearlyAndAISuggestionsCanCloseWithoutExecutingAnAction() {
        for (script, close, card) in [("v47r-next-bill", "dismissBillHeadsUp", "billHeadsUpCard"),
                                      ("v47r-suggestion", "dismissHomeCard", "butlerSuggestionCard"),
                                      ("v47r-weekly-ai", "dismissHomeCard", "butlerSuggestionCard")] {
            launch(script); tap(close); gone(card)
            app.terminate(); launchApp(app); gone(card)
        }
    }
    func testLongCardExpandsInPlaceWithLargestText() {
        launch("v47r-weekly-ai", large: true)
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
    func testSoftLineSuggestionWritesExistingProfileAndCorrectionWritesMemory() {
        launch("v47r-suggestion"); expect("butlerAIAccept", contains: "盯住外卖 ¥800.00")
        tap("butlerAIAccept"); gone("butlerSuggestionCard"); formula(); XCTAssertTrue(element("softLineWatches").waitForExistence(timeout: 5))
        launch("v47r-weekly-ai"); tap("butlerAIIncorrect"); typeIntoField("周四是和同事拼单", identifier: "butlerAICorrectionText", in: app); tap("butlerAICorrectionSave")
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
