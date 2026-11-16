import XCTest

final class Round47HomeFlowTests: YubaiUITestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws { app?.terminate(); app = nil; try super.tearDownWithError() }
    private func launch(_ fixture: String = "v47r-ledger", large: Bool = false, hidden: Bool = false, dark: Bool = false) {
        app = XCUIApplication()
        app.launchArguments = ["--test-ledger", UUID().uuidString, "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launchEnvironment["YUBAI_UI_TEST_SCRIPT"] = fixture
        let instant = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 20))!
        app.launchEnvironment["YUBAI_UI_TEST_NOW"] = String(instant.timeIntervalSince1970)
        app.launchEnvironment["YUBAI_GALLERY_HIDE_AMOUNTS"] = hidden ? "1" : "0"
        app.launchEnvironment["YUBAI_GALLERY_APPEARANCE"] = dark ? "dark" : "light"
        app.launchEnvironment["YUBAI_UI_TEST_ENTRY_EXPLICIT_FINISH"] = "1"
        app.launchEnvironment["DEEPSEEK_API_KEY"] = ""
        launchApp(app); XCTAssertTrue(element("mainNavigation").waitForExistence(timeout: 15))
    }
    private func id(_ number: Int) -> String { String(format: "47000000-0000-0000-0000-%012d", number) }
    private func element(_ id: String) -> XCUIElement { control(id, in: app) }
    private func tap(_ id: String) {
        tapControl(element(id), in: app, settles: !id.hasPrefix("keypad_"), reveals: !id.hasPrefix("keypad_"))
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
        tap("addEntry"); keys(amount); tap("entryCategory_餐饮"); tap("saveQuickEntry"); tap("cancelManualSheet")
        XCTAssertTrue(element("entriesScroll").waitForExistence(timeout: 6))
    }
    func testLedgerIsRootAndOnlyLedgerHasTheEntryPill() {
        launch(); XCTAssertTrue(element("tab_ledger").isSelected)
        let capsule = capsuleFrame(in: app)
        XCTAssertTrue(element("addEntry").exists)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier IN %@", ["tab_ledger", "tab_insights", "tab_yubai"])).count, 3)
        for tab in ["insights", "yubai"] {
            tap("tab_" + tab)
            XCTAssertEqual(capsuleFrame(in: app), capsule)
            XCTAssertFalse(element("addEntry").exists)
        }
        tap("tab_ledger"); XCTAssertTrue(element("addEntry").exists)
    }
    func testSavedPillPushesAndBackReturnsToLedger() {
        launch(); tap("openSaving")
        XCTAssertTrue(app.navigationBars["存钱"].waitForExistence(timeout: 5)); XCTAssertFalse(element("mainNavigation").exists)
        XCTAssertEqual(app.scrollViews.matching(identifier: "savingTabScroll").count, 1)
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "savingTabScroll").count, 1)
        tap("BackButton"); XCTAssertTrue(element("mainNavigation").waitForExistence(timeout: 5)); XCTAssertTrue(element("tab_ledger").isSelected)
        XCTAssertEqual(app.buttons.matching(identifier: "openSaving").count, 1)
        XCTAssertTrue(element("openSaving").label.contains("已存"))
        XCTAssertTrue(element("openSaving").label.contains("¥"))
    }
    func testBambooRendersOffMainAndBodyUpdatesReuseBothCachedAppearances() {
        for dark in [false, true] {
            launch(dark: dark)
            XCTAssertTrue(UIConditionWait.run(timeout: 30, read: {
                guard let bamboo = self.windowMetrics(in: self.app)?.bamboo else { return false }
                return bamboo.ready.contains(where: { $0.hasPrefix("light@") }) &&
                    bamboo.ready.contains(where: { $0.hasPrefix("dark@") }) && bamboo.pending == 0
            }), "Both bamboo appearances must finish on the worker")
            guard let before = windowMetrics(in: app)?.bamboo else { XCTFail("Missing raster diagnostics"); return }
            XCTAssertEqual(before.mainRenders, 0)
            XCTAssertEqual(before.renders, before.ready.count)
            // Each action evaluates the root background/body again; none may
            // render, even when the other tab's task requests the same key.
            tap("toggleAmountVisibility")
            for tab in ["insights", "yubai", "ledger"] { tap("tab_" + tab) }
            tap("toggleAmountVisibility")
            guard let after = windowMetrics(in: app)?.bamboo else { XCTFail("Missing raster diagnostics after layout"); return }
            XCTAssertEqual(after.mainRenders, 0)
            XCTAssertEqual(after.renders, before.renders)
            XCTAssertEqual(after.ready, before.ready)
            XCTAssertEqual(app.state, .runningForeground)
            app.terminate()
        }
    }
    func testHeaderControlsNavigateIndependentlyInBothOrders() {
        for large in [false, true] {
            for order in [["fundsFormula", "openSaving"], ["openSaving", "fundsFormula"]] {
                launch(large: large)
                for id in order {
                    tap(id)
                    let destination = id == "fundsFormula" ? "formulaPage" : "savingTabScroll"
                    let other = id == "fundsFormula" ? "savingTabScroll" : "formulaPage"
                    XCTAssertTrue(element(destination).waitForExistence(timeout: 5))
                    XCTAssertFalse(element(other).exists)
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
    func testSearchExpandsInPlaceAndFindsPreviousMonths() {
        launch(); XCTAssertFalse(element("entriesSearch").exists)
        tap("openLedgerSearch"); tap("entriesSearch"); app.typeText("咖啡")
        XCTAssertTrue(element("entriesSearchTotal").waitForExistence(timeout: 5))
        XCTAssertFalse(element("availableFunds").exists)
        let old = "ledgerEntry_" + id(479203)
        reveal(old); XCTAssertTrue(element(old).isHittable)
        tap("entriesSearchCancel"); XCTAssertFalse(element("entriesSearch").exists)
    }
    func testFilterButtonUsesTheSameInPlaceFilterRow() {
        launch(); tap("openLedgerFilters"); tap("entriesFilter_收入")
        XCTAssertTrue(element("entriesFilter_收入").isSelected)
        XCTAssertFalse(element("ledgerEntry_" + id(479101)).exists)
        tap("tab_ledger")
        XCTAssertTrue(element("availableFunds").waitForExistence(timeout: 5))
        XCTAssertFalse(element("entriesFilter_收入").exists)
    }
    func testTappingSelectedLedgerClearsSearchAndReturnsToHero() {
        launch(); tap("openLedgerSearch"); tap("entriesSearch"); app.typeText("咖啡")
        tap("entriesFilter_支出")
        element("entriesSearch").typeText("\n")
        XCTAssertTrue(waitForDisappearance(app.keyboards.firstMatch))
        tap("tab_ledger")
        XCTAssertTrue(element("availableFunds").waitForExistence(timeout: 5))
        XCTAssertTrue(element("availableFunds").isHittable)
        XCTAssertFalse(element("entriesSearch").exists); XCTAssertFalse(element("entriesFilter_支出").exists)
    }
    func testTappingSelectedLedgerReturnsFromTheOldestEntryToTop() {
        launch(); reveal("ledgerEntry_" + id(479999)); tap("tab_ledger")
        wait { self.element("availableFunds").isHittable }
        XCTAssertTrue(element("ledgerWaterBar").exists)
    }
    func testSelectedYubaiReturnsToTheAskField() {
        launch(large: true); tap("tab_yubai")
        XCTAssertTrue(revealControl(element("openSettings"), in: app, deadline: Date().addingTimeInterval(60)))
        XCTAssertLessThan(element("openSettings").frame.maxY, capsuleFrame(in: app).minY)
        tap("openSettings"); XCTAssertTrue(element("settingsScroll").waitForExistence(timeout: 5))
        tap("BackButton")
        tap("tab_yubai")
        wait { self.element("askYubai").isHittable }
        XCTAssertGreaterThanOrEqual(element("askYubai").frame.height, 44)
    }
    func testMonthSheetYearHasAnIdentifierAndFullTargetAtBothTextSizes() {
        for large in [false, true] {
            launch(large: large); tap("entriesMonth")
            let year = element("ledgerJumpYear")
            XCTAssertTrue(year.waitForExistence(timeout: 5)); XCTAssertTrue(year.isHittable)
            XCTAssertGreaterThanOrEqual(year.frame.height, 43.5)
            XCTAssertGreaterThanOrEqual(year.frame.width, 43.5)
            tap("ledgerJumpYear")
            XCTAssertTrue(element("ledgerJumpYear_2026").waitForExistence(timeout: 5))
            tap("ledgerJumpYear_2026")
            XCTAssertTrue(element("ledgerJumpMonth_11").isHittable)
            app.terminate()
        }
    }
    func testLedgerDateFactsAndHeroClearTheHeader() {
        launch()
        XCTAssertTrue(element("ledgerPeriod").label.contains("12月10日发工资"))
        XCTAssertTrue(app.staticTexts["今天 · 11月20日"].exists)
        XCTAssertGreaterThanOrEqual(element("ledgerHeroLabel").frame.minY, element("rootHeaderRegion").frame.maxY + 16)
        launch("v47r-deficit")
        XCTAssertTrue(element("ledgerGapBill").label.contains("12月5日 房租"))
    }
    func testSelectedInsightsReturnsToItsPeriodControl() {
        launch(large: true); tap("tab_insights")
        XCTAssertTrue(revealControl(element("cashMonthCard"), in: app, deadline: Date().addingTimeInterval(60)))
        tap("tab_insights")
        wait { self.element("insightsPeriod_这一期").isHittable }
        XCTAssertFalse(element("addEntry").exists)
    }
    func testOldestEntryIsHittableAndFullyAbovePillAtBothTextSizes() {
        for large in [false, true] {
            launch("v47r-ledger-end", large: large)
            let key = "ledgerEntry_" + id(479999)
            reveal(key)
            let row = element(key), pill = element("addEntry")
            XCTAssertTrue(row.isHittable)
            XCTAssertLessThan(row.frame.maxY, pill.frame.minY)
            tap(key); XCTAssertTrue(element("editEntryAmount").waitForExistence(timeout: 5))
            XCTAssertEqual(element("editEntryAmount").value as? String, "12.00")
            app.terminate()
        }
    }
    func testOldestEntryKeepsSwipeActionsAbovePill() {
        launch("v47r-ledger-end"); let key = "ledgerEntry_" + id(479999); reveal(key)
        let row = element(key), pill = element("addEntry")
        XCTAssertTrue(waitForStableFrame(row))
        XCTAssertLessThan(row.frame.maxY, pill.frame.minY)
        // A bounded short native pan reveals both actions without completing
        // the full-swipe delete or letting a row tap open the editor.
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: row.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.5)),
                   withVelocity: .slow, thenHoldForDuration: 0.1)
        let delete = element("deleteLedgerEntry_" + id(479999)), sort = element("sortLedgerEntry_" + id(479999))
        XCTAssertTrue(delete.waitForExistence(timeout: 5)); XCTAssertTrue(delete.isHittable)
        XCTAssertTrue(sort.isHittable)
        XCTAssertLessThan(delete.frame.maxY, pill.frame.minY); XCTAssertLessThan(sort.frame.maxY, pill.frame.minY)
        XCTAssertFalse(element("editEntryAmount").exists)
    }
    func testDayPlusPrefillsThatDayAndRowTapEditsOriginal() {
        launch(); let key = "ledgerEntry_" + id(479103); reveal(key); tap(key)
        XCTAssertTrue(element("editEntryAmount").waitForExistence(timeout: 5))
        XCTAssertEqual(element("editEntryAmount").value as? String, "186.40")
        tap("cancelManualSheet")
        let yesterday = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'addEntryOnDay_' AND label CONTAINS '11月19日'")).firstMatch
        tapControl(yesterday, in: app)
        XCTAssertTrue(element("entryDate_yesterday").isSelected)
    }
    func testMonthJumpUsesMonthGrid() {
        launch(); tap("entriesMonth"); tap("ledgerJumpMonth_8")
        XCTAssertTrue(element("entriesScroll").waitForExistence(timeout: 5))
        XCTAssertFalse(element("ledgerJumpMonth_8").exists)
    }
    func testSettingsLivesUnderYubaiAndEveryGroupPushesAnExistingPage() {
        launch(); XCTAssertFalse(element("openSettings").exists)
        tap("tab_insights"); XCTAssertFalse(element("openSettings").exists)
        tap("tab_yubai")
        for (entry, page) in [("openAccounts", "accountsPage"), ("openMemories", "memoryPage"), ("openSettings", "settingsScroll")] {
            tap(entry)
            XCTAssertFalse(element("mainNavigation").exists)
            if entry == "openSettings" { XCTAssertTrue(element(page).waitForExistence(timeout: 5)) }
            else { XCTAssertTrue(element("BackButton").waitForExistence(timeout: 5)) }
            tap("BackButton")
        }
    }
    func testInsightsRangesAndCategoryDrillDown() {
        launch(); tap("tab_insights")
        XCTAssertTrue(element("insightsAmount_收入").waitForExistence(timeout: 5))
        let current = element("insightsAmount_支出").label
        tap("insightsPeriod_上一期"); wait { self.element("insightsAmount_支出").label != current }
        tap("insightsPeriod_今年"); XCTAssertTrue(element("insightsPeriod_今年").isSelected)
        tap("insightsPeriod_这一期"); tap("insightCategory_0")
        XCTAssertTrue(element("whereCategoryEntries").waitForExistence(timeout: 5))
        XCTAssertFalse(element("addEntry").exists)
    }
    func testLargestDarkAndHiddenAmountsKeepLedgerRowsReachable() {
        launch("v47r-ledger-hard", large: true, hidden: true, dark: true)
        XCTAssertEqual(element("availableFunds").label, "金额已隐藏")
        reveal("ledgerEntry_" + id(479999))
        XCTAssertTrue(element("ledgerEntry_" + id(479999)).isHittable)
        XCTAssertFalse(element("entriesScroll").label.contains("1,234,567.89"))
        tap("tab_insights"); XCTAssertEqual(element("insightsAmount_收入").label, "金额已隐藏")
    }
    func testImmediatePillTapOpensOneEntrySheetAtBothTextSizes() {
        for large in [false, true] {
            launch("v47r-soft-lines", large: large)
            tap("addEntry")
            XCTAssertTrue(element("entryPurpose").waitForExistence(timeout: 5))
            XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "entryPurpose").count, 1)
            XCTAssertFalse(element("quickRepeatMenu").exists)
            tap("cancelManualSheet")
            XCTAssertTrue(element("mainNavigation").waitForExistence(timeout: 5))
            app.terminate()
        }
    }
    func testLongPressStillOpensCommonEntriesWithoutAdding() {
        launch(); let amount = element("availableFunds").label
        element("addEntry").press(forDuration: 0.5)
        XCTAssertTrue(element("quickRepeatMenu").waitForExistence(timeout: 5))
        XCTAssertFalse(element("entryKeypadAmount").exists)
        XCTAssertEqual(element("availableFunds").label, amount)
    }
    func testFirstOpenShowsWindowAndThreeTabs() {
        launch("v47-first"); XCTAssertTrue(element("firstOpenScene").exists)
        XCTAssertTrue(element("firstOpenEmptyAmount").exists); XCTAssertEqual(element("addEntry").label, "记第一笔")
        XCTAssertFalse(element("availableFunds").exists); XCTAssertTrue(element("tab_insights").exists)
    }
    func testFirstImportOpensExistingImportFlow() {
        launch("v47-first"); tap("firstImport"); XCTAssertTrue(element("chooseBillFile").waitForExistence(timeout: 5))
    }
    func testFirstEntryUsesMonthlySpendingWithoutBarOrFormula() {
        launch("v47-first"); add("28")
        XCTAssertTrue(element("firstSalaryCard").waitForExistence(timeout: 5)); XCTAssertTrue(app.staticTexts["这个月花了"].exists)
        XCTAssertTrue(element("availableFunds").label.contains("¥28.00"))
        XCTAssertFalse(element("ledgerWaterBar").exists); XCTAssertFalse(element("fundsFormula").exists)
        XCTAssertFalse(element("openSaving").exists)
        XCTAssertEqual(element("setupFirstSalary").label, "填发薪日和工资")
    }
    func testPostponingSalarySurvivesRelaunch() {
        launch("v47-after"); tap("deferFirstSalary"); XCTAssertFalse(element("firstSalaryCard").exists)
        app.terminate(); launchApp(app); XCTAssertTrue(element("mainNavigation").waitForExistence(timeout: 10))
        XCTAssertFalse(element("firstSalaryCard").exists)
    }
    func testSalaryQuestionOpensAndSavesTheExistingSalarySetup() {
        launch("v47-after"); tap("setupFirstSalary")
        XCTAssertTrue(element("paydaySetupSheet").waitForExistence(timeout: 5))
        tap("paydaySetupAmount"); keys("8010"); tap("paydaySetupAmountDone"); tap("paydaySetupDone")
        XCTAssertTrue(waitForDisappearance(element("paydaySetupSheet")))
        XCTAssertFalse(element("firstSalaryCard").exists)
        app.terminate(); launchApp(app)
        XCTAssertTrue(element("mainNavigation").waitForExistence(timeout: 10))
        XCTAssertFalse(element("firstSalaryCard").exists)
    }
    func testSalaryPromptReturnsOnNewIncomeOrDeadline() {
        for fixture in ["v47-after-income", "v47-after-deadline"] {
            launch(fixture); XCTAssertTrue(element("firstSalaryCard").exists); app.terminate()
        }
    }
    func testFirstImportClearsPillAtLargestTextSize() {
        launch("v47-first", large: true)
        XCTAssertTrue(revealControl(element("firstImport"), in: app, deadline: Date().addingTimeInterval(60)))
        XCTAssertTrue(element("firstImport").isHittable)
        XCTAssertLessThan(element("firstImport").frame.maxY, element("addEntry").frame.minY)
    }
}
