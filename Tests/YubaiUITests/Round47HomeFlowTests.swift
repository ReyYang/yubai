import XCTest

final class Round47HomeFlowTests: YubaiUITestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws { app?.terminate(); app = nil; try super.tearDownWithError() }
    private func launch(_ fixture: String = "v47-home", large: Bool = false, hidden: Bool = false, dark: Bool = false, reduceMotion: Bool = false, textCategory: String? = nil) {
        app = XCUIApplication()
        app.launchArguments = ["--test-ledger", UUID().uuidString, "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        else if let textCategory { app.launchArguments += ["-UIPreferredContentSizeCategoryName", textCategory] }
        app.launchEnvironment["YUBAI_UI_TEST_REDUCE_MOTION"] = reduceMotion ? "1" : "0"
        app.launchEnvironment["YUBAI_UI_TEST_SCRIPT"] = fixture
        app.launchEnvironment["YUBAI_GALLERY_HIDE_AMOUNTS"] = hidden ? "1" : "0"
        app.launchEnvironment["YUBAI_GALLERY_APPEARANCE"] = dark ? "dark" : "light"
        app.launchEnvironment["YUBAI_UI_TEST_ENTRY_EXPLICIT_FINISH"] = "1"
        app.launchEnvironment["DEEPSEEK_API_KEY"] = ""
        launchApp(app); XCTAssertTrue(element("mainNavigation").waitForExistence(timeout: 15))
    }
    private func id(_ number: Int) -> String { String(format: "47000000-0000-0000-0000-%012d", number) }
    private func element(_ id: String) -> XCUIElement { control(id, in: app) }
    private func reveal(_ target: XCUIElement) {
        XCTAssertTrue(revealControl(target, in: app, deadline: Date().addingTimeInterval(60)), target.description)
    }
    private func tap(_ id: String) {
        let target = element(id)
        if !target.exists || !target.isHittable { reveal(target) }
        tapControl(target, in: app, settles: !id.hasPrefix("keypad_"))
    }
    private func keys(_ amount: String) { for key in amount { tap("keypad_" + String(key)) } }
    private func add(_ amount: String, yesterday: Bool = false) {
        tap("addEntry"); keys(amount)
        if yesterday { tap("entryDate_yesterday") }
        tap("entryCategory_餐饮"); tap("saveQuickEntry"); tap("cancelManualSheet")
        XCTAssertTrue(element("addEntry").exists || element("addEntry").waitForExistence(timeout: 5))
    }
    private func wait(_ predicate: @escaping () -> Bool, timeout: TimeInterval = 5) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in predicate() }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed)
    }
    func testSavingPushesAndEdgeSwipeReturnsToSameHome() {
        launch(); tap("openSaving")
        XCTAssertTrue(app.navigationBars["存钱"].waitForExistence(timeout: 5))
        XCTAssertFalse(element("mainNavigation").exists)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.005, dy: 0.45))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.45)), withVelocity: .slow, thenHoldForDuration: 0.5)
        XCTAssertTrue(element("mainNavigation").waitForExistence(timeout: 5)); XCTAssertTrue(element("tab_now").isSelected)
    }
    func testSavingCardCoversAllFourStatesAndIsOneButton() {
        for (fixture, text) in [("v47-saving-wish", "还差"), ("v47-saving-reached", "够了"),
                                ("v47-saving-monthly", "每月先存"), ("v47-saving-empty", "开始存钱")] {
            launch(fixture)
            XCTAssertEqual(app.buttons.matching(identifier: "openSaving").count, 1)
            XCTAssertTrue(element("openSaving").label.contains(text), fixture)
            app.terminate()
        }
    }
    func testFirstOpenShowsEmptyRuleAndFirstEntryPill() {
        launch("v47-first")
        XCTAssertTrue(element("firstOpenScene").exists); XCTAssertTrue(element("firstOpenEmptyAmount").exists)
        XCTAssertEqual(element("addEntry").label, "记第一笔")
        XCTAssertTrue(element("firstImport").exists); XCTAssertFalse(element("availableFunds").exists)
        XCTAssertFalse(element("dailyPace").exists)
    }
    func testFirstImportOpensExistingImportFlow() {
        launch("v47-first"); tap("firstImport")
        XCTAssertTrue(element("chooseBillFile").waitForExistence(timeout: 5))
    }
    func testFirstEntryShowsMonthlySpendingAndSalarySetup() {
        launch("v47-first"); add("28")
        XCTAssertTrue(element("firstSalaryCard").waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["这个月花了"].exists)
        XCTAssertTrue(element("availableFunds").label.contains("28.00")); XCTAssertFalse(element("dailyPace").exists)
        tap("setupFirstSalary"); XCTAssertTrue(element("paydaySetupSheet").waitForExistence(timeout: 5))
        tap("paydaySetupAmount"); keys("8010"); tap("paydaySetupAmountDone"); tap("paydaySetupDone")
        XCTAssertTrue(element("fundsFormula").waitForExistence(timeout: 5)); XCTAssertFalse(element("firstSalaryCard").exists)
    }
    func testPostponeSurvivesRelaunchAndNextIncomeWakesPrompt() {
        launch("v47-after"); tap("deferFirstSalary")
        XCTAssertFalse(element("firstSalaryCard").exists)
        app.terminate(); launchApp(app); XCTAssertTrue(element("mainNavigation").waitForExistence(timeout: 10))
        XCTAssertFalse(element("firstSalaryCard").exists)
        tap("addEntry"); tap("entryNature_income"); keys("8010"); tap("entryCategory_工资"); tap("saveQuickEntry"); tap("cancelManualSheet")
        XCTAssertTrue(element("firstSalaryCard").waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["这个月花了"].exists)
    }
    func testTenthOfFollowingMonthWakesDeferredPrompt() {
        launch("v47-after-deadline"); XCTAssertTrue(element("firstSalaryCard").exists)
    }
    func testReceiptNeverBorrowsYesterdayAndGhostStartsToday() {
        launch("v47-receipt-empty"); reveal(element("receiptFirstEntry")); tap("receiptFirstEntry")
        XCTAssertTrue(element("entryDate_today").waitForExistence(timeout: 5)); XCTAssertTrue(element("entryDate_today").isSelected)
    }
    func testReceiptAddsWithoutToastHighlightsThenKeepsSwipeUndo() {
        launch("v47-receipt-normal"); add("18")
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'ledgerEntry_' AND value == '已记下'")).firstMatch
        XCTAssertTrue(row.exists || row.waitForExistence(timeout: 2))
        let identifier = row.identifier
        XCTAssertTrue(element("receiptTotal").label.contains("54.00")); XCTAssertFalse(element("toastMessage").exists)
        wait({ self.element(identifier).value as? String != "已记下" }, timeout: 4)
        let saved = element(identifier); reveal(saved); saved.swipeLeft()
        tap("undoReceipt_" + identifier.replacingOccurrences(of: "ledgerEntry_", with: ""))
        wait { self.element("receiptTotal").label.contains("36.00") }
        XCTAssertFalse(element(identifier).exists)
    }
    func testMoreThanSixKeepsLatestSixAndOpensTodayInLedger() {
        launch("v47-receipt-many")
        let receipt = element("todayEntries"); reveal(element("receiptMoreEntries"))
        XCTAssertTrue(element("receiptMoreEntries").label.contains("3"))
        let rows = receipt.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'ledgerEntry_'"))
        XCTAssertEqual(rows.count, 6)
        tap("receiptMoreEntries"); XCTAssertTrue(element("tab_ledger").isSelected)
        XCTAssertTrue(element("entriesScroll").exists)
    }
    func testReceiptTapEditsThatOriginalEntry() {
        launch("v47-receipt-normal"); reveal(element("ledgerEntry_" + id(470101))); tap("ledgerEntry_" + id(470101))
        XCTAssertTrue(element("editEntryAmount").waitForExistence(timeout: 5))
        XCTAssertEqual(element("editEntryAmount").value as? String, "28.00")
    }
    func testBackdatedEntryKeepsExistingToastFeedback() {
        launch("v47-receipt-normal"); add("18", yesterday: true)
        XCTAssertTrue(element("toastMessage").waitForExistence(timeout: 5))
        XCTAssertTrue(element("toastMessage").label.contains("已记下"))
        XCTAssertTrue(element("receiptTotal").label.contains("36.00"))
    }
    func testLargestTextDarkAndHiddenAmountsKeepReceiptReachable() {
        launch("v47-home-hard", large: true, hidden: true, dark: true, reduceMotion: true)
        reveal(element("receiptTotal"))
        XCTAssertEqual(element("receiptTotal").label, "金额已隐藏")
        XCTAssertTrue(element("receiptTotal").isHittable)
        XCTAssertLessThan(element("receiptTotal").frame.maxY, element("addEntry").frame.minY)
        XCTAssertFalse(element("todayEntries").label.contains("1234567.89"))
    }
    func testInactiveRootsExposeNoInputOrDuplicateHeaders() {
        launch("v47-first", large: true)
        XCTAssertFalse(element("askYubai").exists)
        XCTAssertEqual(element("addEntry").label, "记第一笔")
        tap("tab_ledger")
        XCTAssertFalse(element("askYubai").exists)
        XCTAssertFalse(element("firstImport").exists)
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "rootHeaderTitle").count, 1)
        tap("tab_yubai")
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "askYubai").count, 1)
        XCTAssertGreaterThanOrEqual(element("askYubai").frame.height, 44)
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "rootHeaderTitle").count, 1)
    }
    func testFirstImportClearsFloatingActionsAtLargestTextSize() {
        launch("v47-first", large: true)
        reveal(element("firstImport"))
        XCTAssertTrue(element("firstImport").isHittable)
        XCTAssertGreaterThanOrEqual(element("firstImport").frame.height, 44)
        XCTAssertLessThan(element("firstImport").frame.maxY, element("addEntry").frame.minY)
    }
    func testLargestReceiptAndUpcomingHeaderClearTheWholeNavigationArea() {
        launch("v47-home-hard", large: true)
        XCTAssertEqual(app.scrollViews["nowScroll"].frame.width, app.frame.width, accuracy: 0.5)
        for id in ["openFixedFlows", "receiptOpenLedger", "receiptMoreEntries", "receiptTotal"] {
            let target = element(id); reveal(target)
            XCTAssertTrue(target.isHittable, id)
            XCTAssertGreaterThanOrEqual(target.frame.minY, element("rootHeaderRegion").frame.maxY, id)
            XCTAssertLessThan(target.frame.maxY, element("mainNavigation").frame.minY, id)
        }
        XCTAssertTrue(element("receiptTotal").label.contains("1,234,610.04"))
        XCTAssertLessThan(element("receiptTotal").frame.height, 160)
        XCTAssertGreaterThanOrEqual(element("receiptDate").frame.minX, app.frame.minX)
        XCTAssertLessThanOrEqual(element("receiptDate").frame.maxX, app.frame.maxX)
    }
    func testCrossingSavingCardLosesItsActionAndRecoversAfterScrollingBack() {
        launch(); let card = element("openSaving"); reveal(card)
        let viewport = app.scrollViews["nowScroll"].frame, frame = card.frame
        let marker = app.staticTexts["接下来 7 天"]
        XCTAssertTrue(marker.exists)
        let markerY = marker.frame.minY
        let distance = frame.minY - viewport.minY + 12
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let start = origin.withOffset(CGVector(dx: viewport.midX, dy: viewport.maxY - 16))
        let end = origin.withOffset(CGVector(dx: viewport.midX, dy: viewport.maxY - 16 - distance))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
        let crossed = frame.offsetBy(dx: 0, dy: marker.frame.minY - markerY)
        XCTAssertLessThan(crossed.minY, viewport.minY)
        XCTAssertGreaterThan(crossed.maxY, viewport.minY)
        XCTAssertFalse(card.exists && card.isHittable)
        end.press(forDuration: 0.05, thenDragTo: start, withVelocity: .slow, thenHoldForDuration: 0.1)
        reveal(card); tap("openSaving")
        XCTAssertTrue(element("reserveTotal").waitForExistence(timeout: 5))
    }
    func testUpcomingBillNameUsesTwoLinesAndDetailKeepsItsFullName() {
        launch("v47-home-hard", textCategory: "UICTContentSizeCategoryL")
        let name = element("formulaBill_" + id(4630)); reveal(name)
        let fullName = name.label
        XCTAssertGreaterThan(fullName.count, 20)
        XCTAssertLessThanOrEqual(name.frame.height, 44.5)
        tap("formulaBill_" + id(4630))
        XCTAssertTrue(app.scrollViews.staticTexts.matching(NSPredicate(format: "label == %@", fullName)).firstMatch.waitForExistence(timeout: 5))
    }
    func testCapsuleStaysInPlaceAndAssistantInputClearsOnlyTheCapsule() {
        launch()
        let capsule = capsuleFrame(in: app)
        for tab in ["ledger", "yubai"] {
            tap("tab_" + tab)
            XCTAssertEqual(capsuleFrame(in: app), capsule)
            XCTAssertFalse(element("addEntry").exists)
        }
        let field = element("askYubai")
        XCTAssertGreaterThanOrEqual(field.frame.height, 44)
        XCTAssertLessThan(field.frame.maxY, capsule.minY)
        XCTAssertLessThanOrEqual(capsule.minY - field.frame.maxY, 32)
    }
    func testPaydayDayTargetsKeepFortyFourScreenPointsAtBothTextSizes() {
        for (large, category) in [(false, "UICTContentSizeCategoryL"), (false, "UICTContentSizeCategoryXXXL"), (true, "UICTContentSizeCategoryAccessibilityXXXL")] {
            launch("v47-after", large: large, textCategory: category); tap("setupFirstSalary")
            let first = element("paydaySetupDay_1")
            XCTAssertTrue(first.waitForExistence(timeout: 5))
            XCTAssertTrue(waitForStableFrame(first))
            let days = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'paydaySetupDay_'"))
            XCTAssertGreaterThanOrEqual(days.count, 7)
            for day in days.allElementsBoundByIndex {
                XCTAssertGreaterThanOrEqual(day.frame.width, 44, day.identifier)
                XCTAssertGreaterThanOrEqual(day.frame.height, 44, day.identifier)
                XCTAssertGreaterThanOrEqual(day.frame.minX, app.frame.minX, day.identifier)
                XCTAssertLessThanOrEqual(day.frame.maxX, app.frame.maxX, day.identifier)
            }
            let firstRow = days.allElementsBoundByIndex.filter { abs($0.frame.minY - first.frame.minY) < 1 }
            XCTAssertEqual(firstRow.count, large ? 4 : 7, category)
            let lastColumn = large ? 4 : 7
            tap("paydaySetupDay_\(lastColumn)")
            XCTAssertTrue(element("paydaySetupDay_\(lastColumn)").isSelected)
            // The amount is required by the salary plan; selecting a day alone
            // must not enable confirmation for a zero-amount plan.
            XCTAssertFalse(element("paydaySetupDone").isEnabled)
            app.terminate()
        }
    }
    func testLastTodayRowReachedFromReceiptClearsTheCapsuleAtBothTextSizes() {
        for large in [false, true] {
            launch("v47-receipt-many", large: large)
            reveal(element("receiptMoreEntries")); tap("receiptMoreEntries")
            let last = element("ledgerEntry_" + id(470110))
            reveal(last)
            XCTAssertTrue(last.exists && last.isHittable)
            let header = element("rootHeaderRegion").frame, capsule = capsuleFrame(in: app)
            XCTAssertGreaterThanOrEqual(last.frame.minY, header.maxY)
            XCTAssertLessThan(last.frame.maxY, capsule.minY)
            for row in app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'ledgerEntry_'")).allElementsBoundByIndex {
                if row.frame.minY < header.maxY || row.frame.maxY > capsule.minY {
                    XCTAssertFalse(row.isHittable, row.identifier)
                }
            }
            app.terminate()
        }
    }
}
