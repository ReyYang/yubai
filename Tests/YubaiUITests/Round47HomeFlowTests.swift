import XCTest

final class Round47HomeFlowTests: YubaiUITestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws { app?.terminate(); app = nil; try super.tearDownWithError() }
    private func launch(_ fixture: String = "v47r-ledger", large: Bool = false, hidden: Bool = false, dark: Bool = false, reduceMotion: Bool = false, keepUndo: Bool = false) {
        app = XCUIApplication()
        app.launchArguments = ["--test-ledger", UUID().uuidString, "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launchEnvironment["YUBAI_UI_TEST_SCRIPT"] = fixture
        let instant = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 20))!
        app.launchEnvironment["YUBAI_UI_TEST_NOW"] = String(instant.timeIntervalSince1970)
        app.launchEnvironment["YUBAI_GALLERY_HIDE_AMOUNTS"] = hidden ? "1" : "0"
        app.launchEnvironment["YUBAI_GALLERY_APPEARANCE"] = dark ? "dark" : "light"
        app.launchEnvironment["YUBAI_UI_TEST_REDUCE_MOTION"] = reduceMotion ? "1" : "0"
        app.launchEnvironment["YUBAI_UI_TEST_KEEP_UNDO"] = keepUndo ? "1" : "0"
        app.launchEnvironment["YUBAI_UI_TEST_ENTRY_EXPLICIT_FINISH"] = "1"
        app.launchEnvironment["DEEPSEEK_API_KEY"] = ""
        launchApp(app)
        XCTAssertTrue(element("mainNavigation").waitForExistence(timeout: 15),
                      "Root navigation missing; bamboo={\(windowMetrics(in: app)?.bamboo?.description ?? "diagnostics unreadable")}")
    }
    private func id(_ number: Int) -> String { String(format: "47000000-0000-0000-0000-%012d", number) }
    private func element(_ id: String) -> XCUIElement { control(id, in: app) }
    private func tap(_ id: String) {
        tapControl(element(id), in: app, settles: !id.hasPrefix("keypad_"), reveals: !id.hasPrefix("keypad_"))
    }
    private func openAssistantHub() {
        if !element("openSettings").exists { tap("tab_ledger") }
        tap("openSettings"); tap("openAssistantHub")
    }
    private func reveal(_ id: String) {
        XCTAssertTrue(revealControl(element(id), in: app, deadline: Date().addingTimeInterval(60), searching: element("entriesScroll")), id)
    }
    private func keys(_ amount: String) { for key in amount { tap("keypad_" + String(key)) } }
    private func wait(_ predicate: @escaping () -> Bool) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in predicate() }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 6), .completed)
    }
    private func add(_ amount: String) {
        tap("addEntry"); keys(amount); tap("entryCategory_餐饮"); tap("saveQuickEntry")
        XCTAssertTrue(waitForDisappearance(element("saveQuickEntry")))
        XCTAssertTrue(element("entriesScroll").waitForExistence(timeout: 6))
    }

    func testLedgerIsRootAndBothTabsCanRecordAnEntry() {
        launch()
        XCTAssertTrue(element("tab_ledger").isSelected)
        let bar = element("mainNavigation").frame
        XCTAssertTrue(element("addEntry").isHittable)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier IN %@", ["tab_ledger", "tab_insights"])).count, 2)
        XCTAssertFalse(element("tab_yubai").exists)
        tap("tab_insights")
        XCTAssertTrue(element("tab_insights").isSelected)
        XCTAssertTrue(element("addEntry").isHittable)
        XCTAssertEqual(element("mainNavigation").frame, bar)
        tap("tab_ledger")
        XCTAssertTrue(element("addEntry").isHittable)
    }

    func testSavingFromSettingsHubAndBackReturnsToLedger() {
        launch(); openAssistantHub(); tap("openSaving")
        XCTAssertTrue(element("savingTabScroll").waitForExistence(timeout: 5))
        XCTAssertFalse(element("mainNavigation").exists)
        tap("BackButton"); tap("BackButton"); tap("BackButton")
        XCTAssertTrue(element("mainNavigation").waitForExistence(timeout: 5))
        XCTAssertTrue(element("tab_ledger").isSelected)
    }
    func testBambooRendersOffMainAndBodyUpdatesReuseBothCachedAppearances() {
        for (dark, reduceMotion) in [(false, false), (true, false), (false, true), (true, true)] {
            launch(dark: dark, reduceMotion: reduceMotion)
            let preparation = waitForBambooRasters(in: app)
            let context = "dark=\(dark) reduceMotion=\(reduceMotion)"
            let initialDiagnostics = "\(context) \(preparation)"
            XCTAssertTrue(preparation.ready, "Both bamboo appearances must finish on the worker: \(initialDiagnostics)")
            guard let before = preparation.observed else { XCTFail("Missing raster diagnostics: \(initialDiagnostics)"); return }
            XCTAssertEqual(before.mainRenders, 0, initialDiagnostics)
            XCTAssertEqual(before.activeRenders, 0, initialDiagnostics)
            XCTAssertEqual(before.maxConcurrentRenders, 1, initialDiagnostics)
            XCTAssertEqual(before.renders, before.ready.count, initialDiagnostics)
            XCTAssertTrue(before.failed.isEmpty, initialDiagnostics)
            XCTAssertNil(before.lastFailure, initialDiagnostics)
            // Each action evaluates the root background/body again; none may
            // render, even when the other tab's task requests the same key.
            tap("tab_insights"); tap("toggleAmountVisibility"); tap("toggleAmountVisibility"); tap("tab_ledger")
            guard let after = windowMetrics(in: app)?.bamboo else {
                XCTFail("Raster diagnostics unreadable after layout; \(initialDiagnostics)"); return
            }
            let diagnostics = "\(context) before={\(before)} after={\(after)}"
            XCTAssertTrue(after.isReady, diagnostics)
            XCTAssertEqual(after.mainRenders, 0, diagnostics)
            XCTAssertEqual(after.activeRenders, 0, diagnostics)
            XCTAssertEqual(after.maxConcurrentRenders, 1, diagnostics)
            XCTAssertEqual(after.renders, before.renders, diagnostics)
            XCTAssertEqual(after.ready, before.ready, diagnostics)
            XCTAssertEqual(app.state, .runningForeground, diagnostics)
            app.terminate()
        }
    }
    func testRepeatedColdBambooWarmupsDrainBothAppearancesAndKeepTheProcessAlive() {
        // Each launch has a fresh cache and performs two real renders. Repeated
        // warm(cache-hit) calls would never exercise the crashing pool teardown.
        for iteration in 0..<12 {
            launch(dark: iteration.isMultiple(of: 2), reduceMotion: iteration.isMultiple(of: 3))
            let preparation = waitForBambooRasters(in: app)
            let diagnostics = "cold launch=\(iteration) \(preparation)"
            XCTAssertTrue(preparation.ready, diagnostics)
            guard let observed = preparation.observed else { XCTFail(diagnostics); return }
            XCTAssertEqual(observed.ready.count, 2, diagnostics)
            XCTAssertEqual(observed.renders, 2, diagnostics)
            XCTAssertEqual(observed.mainRenders, 0, diagnostics)
            XCTAssertEqual(observed.activeRenders, 0, diagnostics)
            XCTAssertEqual(observed.maxConcurrentRenders, 1, diagnostics)
            XCTAssertTrue(observed.failed.isEmpty, diagnostics)
            XCTAssertNil(observed.lastFailure, diagnostics)
            tap("tab_insights"); tap("toggleAmountVisibility"); tap("tab_ledger")
            XCTAssertTrue(element("openSettings").isHittable, diagnostics)
            XCTAssertEqual(app.state, .runningForeground, diagnostics)
            app.terminate()
        }
    }

    func testHeaderControlsNavigateIndependentlyInBothOrders() {
        for large in [false, true] {
            for order in [["fundsFormula", "openSettings"], ["openSettings", "fundsFormula"]] {
                launch(large: large)
                for id in order {
                    tap(id)
                    let destination = id == "fundsFormula" ? "formulaPage" : "settingsScroll"
                    XCTAssertTrue(element(destination).waitForExistence(timeout: 5))
                    XCTAssertFalse(element("mainNavigation").exists)
                    tap("BackButton")
                    XCTAssertTrue(element("mainNavigation").waitForExistence(timeout: 5))
                    XCTAssertTrue(element("tab_ledger").isSelected)
                    XCTAssertFalse(element(destination).exists)
                }
                app.terminate()
            }
        }
    }
    private func checkTopBarImmediatelyAndAfterScrolling(large: Bool = false, hidden: Bool = false, dark: Bool = false) {
        launch(large: large, hidden: hidden, dark: dark)
        let scroll = element("entriesScroll")
        for scrolled in [false, true] {
            if scrolled { scroll.swipeUp() }
            XCTAssertTrue(element("openSettings").isHittable)
            tap("openSettings")
            XCTAssertTrue(element("settingsScroll").waitForExistence(timeout: 5))
            tap("BackButton")
            tap("openLedgerSearch")
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
            let field = element("entriesSearch")
            field.typeText("咖啡")
            XCTAssertTrue(element("entriesSearchTotal").waitForExistence(timeout: 5))
            tap("entriesSearchCancel")
            XCTAssertTrue(waitForDisappearance(field))
            XCTAssertTrue(waitForKeyboardDismissal(in: app))
        }
    }
    func testEveryTopBarControlWorksImmediatelyAndAfterScrollingInLight() {
        checkTopBarImmediatelyAndAfterScrolling()
    }
    func testEveryTopBarControlWorksImmediatelyAndAfterScrollingInDark() {
        checkTopBarImmediatelyAndAfterScrolling(dark: true)
    }
    func testEveryTopBarControlWorksImmediatelyAndAfterScrollingWithHiddenAmounts() {
        checkTopBarImmediatelyAndAfterScrolling(hidden: true)
    }
    func testEveryTopBarControlWorksImmediatelyAndAfterScrollingAtLargestText() {
        checkTopBarImmediatelyAndAfterScrolling(large: true)
    }
    func testEveryTopBarControlWorksImmediatelyAndAfterScrollingAtLargestDarkHiddenText() {
        checkTopBarImmediatelyAndAfterScrolling(large: true, hidden: true, dark: true)
    }

    func testFlatTabBarKeepsBothTabsAndTheEntryActionAtEveryTextSize() {
        for (large, dark, hidden) in [(false, false, false), (true, false, false), (true, true, true)] {
            launch(large: large, hidden: hidden, dark: dark)
            let bar = element("mainNavigation"), add = element("addEntry")
            XCTAssertTrue(waitForStableFrame(add))
            XCTAssertGreaterThanOrEqual(add.frame.height, 48)
            XCTAssertGreaterThanOrEqual(add.frame.width, 124)
            XCTAssertLessThan(element("tab_ledger").frame.midX, add.frame.midX)
            XCTAssertGreaterThan(element("tab_insights").frame.midX, add.frame.midX)
            XCTAssertTrue(bar.frame.contains(add.frame))
            app.terminate()
        }
    }
    func testSearchExpandsInPlaceAndFindsPreviousMonths() {
        launch(); XCTAssertFalse(element("entriesSearch").exists)
        tap("openLedgerSearch"); tap("entriesSearch"); app.typeText("咖啡")
        XCTAssertTrue(element("entriesSearchTotal").waitForExistence(timeout: 5))
        XCTAssertFalse(element("availableFunds").exists)
        let old = "ledgerEntry_" + id(479203)
        reveal(old); XCTAssertTrue(element(old).isHittable)
        tap("entriesSearchCancel"); XCTAssertFalse(element("entriesSearch").exists)
    }

    func testSearchAutofocusAndSummaryRemainQueryableAcrossAllGalleryModes() {
        for large in [false, true] {
            for dark in [false, true] {
                for hidden in [false, true] {
                    launch("v47r-ledger-hard", large: large, hidden: hidden, dark: dark)
                    tap("openLedgerSearch")
                    XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
                    XCTAssertTrue(dismissKeyboardIntroduction(in: app))
                    let field = element("entriesSearch")
                    field.typeText("咖啡")
                    XCTAssertEqual(field.value as? String, "咖啡")
                    let summary = element("entriesSearchTotal")
                    XCTAssertTrue(summary.waitForExistence(timeout: 5))
                    XCTAssertTrue(summary.label.contains("笔"))
                    XCTAssertTrue(element("askHomeSearch").exists)
                    tap("entriesSearchCancel")
                    XCTAssertTrue(waitForDisappearance(field))
                    XCTAssertTrue(element("fundsFormula").exists)
                    app.terminate()
                }
            }
        }
    }

    func testSearchAutofocusReopensAfterCancelAndStaysDismissedAfterReturn() {
        for large in [false, true] {
            launch("v47r-ledger-hard", large: large)
            tap("openLedgerSearch")
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
            XCTAssertTrue(dismissKeyboardIntroduction(in: app))
            let field = element("entriesSearch")
            field.typeText("咖啡\n")
            XCTAssertTrue(waitForKeyboardDismissal(in: app))
            XCTAssertEqual(field.value as? String, "咖啡")
            XCTAssertTrue(element("entriesSearchTotal").exists)
            tap("entriesSearchCancel")
            XCTAssertTrue(waitForDisappearance(field))
            tap("openLedgerSearch")
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
            XCTAssertNotEqual(field.value as? String, "咖啡")
            tap("entriesSearchCancel")
            XCTAssertTrue(waitForDisappearance(field))
            XCTAssertTrue(waitForKeyboardDismissal(in: app))
            app.terminate()
        }
    }

    func testInPlaceSearchOnlyShowsMatchingBills() {
        launch()
        tap("openLedgerSearch")
        element("entriesSearch").typeText("咖啡")
        XCTAssertTrue(element("ledgerEntry_" + id(479203)).waitForExistence(timeout: 5))
        XCTAssertFalse(element("ledgerEntry_" + id(479101)).exists)
        tap("entriesSearchCancel")
        XCTAssertTrue(element("fundsFormula").exists)
    }
    func testTappingSelectedLedgerClearsSearchAndReturnsToHero() {
        launch(); tap("openLedgerSearch"); tap("entriesSearch"); app.typeText("咖啡")
        element("entriesSearch").typeText("\n")
        XCTAssertTrue(waitForDisappearance(app.keyboards.firstMatch))
        tap("tab_ledger")
        XCTAssertTrue(element("fundsFormula").waitForExistence(timeout: 5))
        XCTAssertTrue(element("fundsFormula").isHittable)
        XCTAssertFalse(element("entriesSearch").exists)
    }
    func testTappingSelectedLedgerReturnsFromTheOldestEntryToTop() {
        launch(); reveal("ledgerEntry_" + id(479999)); tap("tab_ledger")
        wait { self.element("fundsFormula").isHittable }
        XCTAssertTrue(element("openLedgerSearch").exists)
    }
    func testAskRemainsAccessibleAfterReturningFromSettings() {
        launch(large: true); tap("openSettings")
        XCTAssertTrue(element("settingsScroll").waitForExistence(timeout: 5))
        tap("BackButton")
        tap("openLedgerSearch")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        element("entriesSearch").typeText("咖啡")
        tap("askHomeSearch")
        XCTAssertTrue(element("askPage").waitForExistence(timeout: 5))
    }
    func testCalendarMonthArrowsHaveFullTargetsAtBothTextSizes() {
        for large in [false, true] {
            launch(large: large); tap("addEntry"); tap("entryTimePill")
            let previous = app.buttons["上个月"]
            XCTAssertTrue(previous.waitForExistence(timeout: 5))
            XCTAssertGreaterThanOrEqual(previous.frame.width, 43.5)
            previous.tap()
            XCTAssertTrue(app.staticTexts["2026年10月"].exists)
            XCTAssertTrue(app.buttons["下个月"].isHittable)
            app.terminate()
        }
    }
    func testLedgerDateFactsAndHeroClearTheHeader() {
        launch()
        XCTAssertTrue(app.staticTexts["今天"].exists)
        XCTAssertGreaterThanOrEqual(element("fundsFormula").frame.minY, element("rootHeaderRegion").frame.maxY)
        tap("fundsFormula")
        XCTAssertTrue(element("formulaPage").waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "11.10", "12.09")).firstMatch.exists)
    }
    func testSelectedInsightsReturnsToItsPeriodControl() {
        launch("v47r-soft-lines", large: true); tap("tab_insights")
        let period = element("overviewPeriod")
        XCTAssertTrue(period.waitForExistence(timeout: 5))
        let top = period.frame
        element("overviewScroll").swipeUp()
        tap("tab_insights")
        wait { period.isHittable && abs(period.frame.minY - top.minY) < 2 }
        XCTAssertTrue(element("addEntry").exists)
    }
    func testOldestEntryIsHittableAndFullyAbovePillAtBothTextSizes() {
        for large in [false, true] {
            launch("v47r-ledger-end", large: large)
            let key = "ledgerEntry_" + id(479999)
            reveal(key)
            let row = element(key), pill = element("addEntry")
            XCTAssertTrue(row.isHittable)
            XCTAssertLessThan(row.frame.maxY, pill.frame.minY)
            tap(key); tap("billMore"); tap("entryDetailEdit")
            XCTAssertTrue(element("entryKeypadAmount").waitForExistence(timeout: 5))
            XCTAssertEqual(element("entryKeypadAmount").value as? String, "12.00")
            app.terminate()
        }
    }
    func testOldestEntryMenuKeepsActionsReachableAboveTabBar() {
        for large in [false, true] {
            launch(large: large)
            let id = "ledgerEntry_" + self.id(479999)
            reveal(id)
            XCTAssertLessThanOrEqual(element(id).frame.maxY, element("mainNavigation").frame.minY)
            tap(id); tap("billMore")
            XCTAssertTrue(element("deleteEntryDetail").isHittable)
            XCTAssertTrue(element("entryDetailRecategorize").exists)
            XCTAssertFalse(element("entryKeypadAmount").exists)
            tap("billMore"); tap("closeBill")
            XCTAssertTrue(element(id).waitForExistence(timeout: 5))
            app.terminate()
        }
    }
    func testLedgerBillMenuDeleteAndUndoRestoresRow() {
        launch(keepUndo: true)
        let key = "ledgerEntry_" + id(479103)
        reveal(key)
        let row = element(key), originalLabel = row.label
        tap(key); tap("billMore"); tap("deleteEntryDetail")
        XCTAssertTrue(waitForDisappearance(row))
        tap("undoLastChange")
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertEqual(row.label, originalLabel)
    }

    func testLedgerRowEditSavesAmountWithTwoDecimals() {
        launch()
        let key = "ledgerEntry_" + id(479103)
        reveal(key); tap(key); tap("billMore"); tap("entryDetailEdit")
        let amount = element("entryKeypadAmount")
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        XCTAssertEqual(amount.value as? String, "186.40")
        keys("23.7"); tap("saveQuickEntry")
        XCTAssertTrue(waitForDisappearance(amount))
        reveal(key)
        XCTAssertTrue(element(key).label.contains("−23.70"))
        XCTAssertFalse(element(key).label.contains("186.40"))
    }

    func testBillEditPreservesTheOriginalDateInStageA() {
        launch()
        let key = "ledgerEntry_" + id(479103)
        reveal(key); tap(key); tap("billMore"); tap("entryDetailEdit")
        XCTAssertTrue(element("entryKeypadAmount").waitForExistence(timeout: 5))
        XCTAssertEqual(element("entryKeypadAmount").value as? String, "186.40")
        let pill = element("entryTimePill")
        XCTAssertTrue(waitForStableFrame(pill))
        let pillFrame = pill.frame
        let window = app.windows.firstMatch
        let windowFrame = window.frame
        let pillCenter = window.coordinate(withNormalizedOffset: .zero).withOffset(
            CGVector(dx: pillFrame.midX - windowFrame.minX, dy: pillFrame.midY - windowFrame.minY))
        tap("entryTimePill")
        let yesterday = element("entryQuick_昨天")
        XCTAssertTrue(yesterday.waitForExistence(timeout: 5))
        // The calendar scrim temporarily takes the pill out of the AX tree.
        pillCenter.tap()
        XCTAssertTrue(waitForDisappearance(yesterday))
        dismissEntrySheet(in: app)
        XCTAssertTrue(element(key).waitForExistence(timeout: 5))
    }
    func testStageACalendarSelectsAPreviousMonthDate() {
        launch(); tap("addEntry"); tap("entryTimePill")
        app.buttons["上个月"].tap()
        let day = app.buttons["2026年10月20日"]
        XCTAssertTrue(day.waitForExistence(timeout: 5))
        day.tap()
        XCTAssertTrue(element("entryTimePill").label.contains("10月20日"))
    }
    func testSettingsLivesOnHomeAndTheHubStillReachesExistingPages() {
        launch()
        XCTAssertTrue(element("openSettings").exists)
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "rootHeaderRegion").count, 1)
        tap("tab_insights")
        XCTAssertTrue(element("tab_insights").isSelected)
        XCTAssertTrue(waitForDisappearance(element("openSettings")))
        tap("tab_ledger"); tap("openSettings")
        XCTAssertTrue(element("settingsScroll").waitForExistence(timeout: 5))
        tap("openAssistantHub")
        for entry in ["openAccounts", "openMemories"] {
            tap(entry)
            XCTAssertFalse(element("mainNavigation").exists)
            XCTAssertTrue(element("BackButton").waitForExistence(timeout: 5))
            tap("BackButton")
        }
    }
    func testInsightsRangesAndCategoryDrillDown() {
        launch("v47r-soft-lines"); tap("tab_insights")
        let spent = element("overviewSpent")
        XCTAssertTrue(spent.waitForExistence(timeout: 5))
        let current = spent.label
        tap("overviewPeriod"); tap("overviewPeriod_previous")
        wait { spent.label != current }
        tap("overviewPeriod"); tap("overviewPeriod_custom"); tap("overviewQuick_thisYear"); tap("overviewPeriodApply")
        wait { self.element("overviewPeriod").label.contains("自定义") }
        tap("overviewPeriod"); tap("overviewPeriod_current")
        let category = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "overviewCategory_")).firstMatch
        tapControl(category, in: app)
        XCTAssertTrue(element("whereCategoryEntries").waitForExistence(timeout: 5))
        XCTAssertFalse(element("addEntry").exists)
    }
    func testLargestDarkAndHiddenAmountsKeepLedgerRowsReachable() {
        launch("v47r-ledger-hard", large: true, hidden: true, dark: true)
        XCTAssertEqual(element("fundsFormula").value as? String, "金额已隐藏")
        reveal("ledgerEntry_" + id(479999))
        XCTAssertTrue(element("ledgerEntry_" + id(479999)).isHittable)
        XCTAssertFalse(element("entriesScroll").label.contains("1,234,567.89"))
        tap("tab_insights"); XCTAssertEqual(element("overviewSpent").label, "金额已隐藏")
    }
    func testImmediatePillTapOpensOneEntrySheetAtBothTextSizes() {
        for large in [false, true] {
            launch("v47r-soft-lines", large: large)
            tap("addEntry")
            XCTAssertTrue(element("entryPurpose").waitForExistence(timeout: 5))
            XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "entryPurpose").count, 1)
            XCTAssertFalse(element("quickRepeatMenu").exists)
            dismissEntrySheet(in: app)
            XCTAssertTrue(element("mainNavigation").waitForExistence(timeout: 5))
            app.terminate()
        }
    }

    func testSettingsHubOpensCommonEntriesWithoutAdding() {
        launch()
        let amount = element("fundsFormula").value as? String
        openAssistantHub(); tap("openFrequentEntries")
        XCTAssertTrue(element("BackButton").waitForExistence(timeout: 5))
        XCTAssertFalse(element("entryKeypadAmount").exists)
        tap("BackButton"); tap("BackButton"); tap("BackButton")
        XCTAssertEqual(element("fundsFormula").value as? String, amount)
    }
    func testFirstOpenShowsWindowAndTwoTabs() {
        launch("v47-first"); XCTAssertTrue(element("firstOpenScene").exists)
        XCTAssertTrue(element("firstOpenEmptyAmount").exists); XCTAssertEqual(element("addEntry").label, "记一笔")
        XCTAssertFalse(element("availableFunds").exists); XCTAssertTrue(element("tab_insights").exists)
    }
    func testSharedPaydaySheetTitlesGrowAndPassNativeAuditsAcrossGalleryModes() {
        for large in [false, true] {
            for (dark, hidden) in [(false, false), (true, false), (false, true), (true, true)] {
                launch("v47-after", large: large, hidden: hidden, dark: dark)
                openAssistantHub(); tap("openPaydaySetup")
                XCTAssertTrue(element("paydaySetupSheet").waitForExistence(timeout: 5))
                for (title, cancelID) in [("哪天发工资", "paydaySetupCancel"), ("工资", "amountSheetCancel")] {
                    if cancelID == "amountSheetCancel" { tap("paydaySetupAmount") }
                    let text = app.staticTexts[title], cancel = element(cancelID)
                    XCTAssertTrue(waitForStableFrame(text))
                    XCTAssertEqual(text.label, title)
                    XCTAssertGreaterThan(text.frame.width, 0)
                    XCTAssertGreaterThanOrEqual(text.frame.minX, app.windows.firstMatch.frame.minX)
                    XCTAssertLessThanOrEqual(text.frame.maxX, app.windows.firstMatch.frame.maxX)
                    if large {
                        XCTAssertGreaterThan(text.frame.height, 22)
                        XCTAssertLessThanOrEqual(text.frame.maxY, cancel.frame.minY)
                    } else { XCTAssertEqual(text.frame.midY, cancel.frame.midY, accuracy: 0.5) }
                    XCTAssertNoThrow(try auditAppText(in: app, dynamicType: true) { issue in
                        XCTFail("Shared sheet titles must grow without clipping: " + issue.detailedDescription)
                        return true
                    })
                    XCTAssertEqual(app.state, .runningForeground)
                    XCTAssertTrue(waitForNativeTransition(in: app, deadline: Date().addingTimeInterval(12)))
                    XCTAssertTrue(waitForStableFrame(text))
                    XCTAssertEqual(text.label, title)
                    XCTAssertTrue(cancel.isHittable)
                }
                tap("amountSheetCancel"); tap("paydaySetupCancel")
                XCTAssertTrue(waitForDisappearance(element("paydaySetupSheet")))
                app.terminate()
            }
        }
    }
    func testFirstImportOpensExistingImportFlow() {
        launch("v47-first"); tap("firstImport"); XCTAssertTrue(element("chooseBillFile").waitForExistence(timeout: 5))
    }

    func testFirstEntryLeavesSalaryPendingAndOffersIncomeCapture() {
        launch("v47-first")
        XCTAssertTrue(element("firstOpenScene").exists)
        add("28")
        XCTAssertFalse(element("firstOpenScene").exists)
        XCTAssertTrue(app.staticTexts["工资未到账"].waitForExistence(timeout: 5))
        XCTAssertTrue(element("recordSalary").isHittable)
        tap("recordSalary")
        XCTAssertTrue(element("entryKeypadAmount").waitForExistence(timeout: 5))
        XCTAssertTrue(element("entryNature_income").isSelected)
        XCTAssertFalse(app.staticTexts["工资未到账"].isHittable)
    }
    func testCancellingSalaryCaptureLeavesSalaryPendingAfterRelaunch() {
        launch("v47-after"); tap("recordSalary"); dismissEntrySheet(in: app)
        app.terminate(); launchApp(app)
        XCTAssertTrue(element("mainNavigation").waitForExistence(timeout: 10))
        XCTAssertTrue(element("recordSalary").exists)
    }
    func testSalaryQuestionOpensAndSavesTheExistingSalarySetup() {
        launch("v47-after"); openAssistantHub(); tap("openPaydaySetup")
        XCTAssertTrue(element("paydaySetupSheet").waitForExistence(timeout: 5))
        tap("paydaySetupAmount"); keys("8010"); tap("paydaySetupAmountDone"); tap("paydaySetupDone")
        XCTAssertTrue(waitForDisappearance(element("paydaySetupSheet")))
        XCTAssertFalse(element("paydaySetupSheet").exists)
        app.terminate(); launchApp(app)
        XCTAssertTrue(element("mainNavigation").waitForExistence(timeout: 10))
        XCTAssertFalse(element("paydaySetupSheet").exists)
    }
    func testSalaryCaptureIsAvailableWhileTheCycleHasNoIncome() {
        launch("v47-after-deadline")
        XCTAssertTrue(element("recordSalary").exists)
        app.terminate()
        launch("v47-after-income")
        XCTAssertFalse(element("recordSalary").exists)
    }
    func testFirstImportClearsPillAtLargestTextSize() {
        launch("v47-first", large: true)
        XCTAssertTrue(revealControl(element("firstImport"), in: app, deadline: Date().addingTimeInterval(60)))
        XCTAssertTrue(element("firstImport").isHittable)
        XCTAssertLessThan(element("firstImport").frame.maxY, element("addEntry").frame.minY)
    }
}
