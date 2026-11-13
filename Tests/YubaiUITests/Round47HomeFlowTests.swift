import XCTest

final class Round47HomeFlowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws { app?.terminate(); app = nil; try super.tearDownWithError() }
    private func launch(_ fixture: String = "v47-home", large: Bool = false, hidden: Bool = false, dark: Bool = false, reduceMotion: Bool = false) {
        app = XCUIApplication()
        app.launchArguments = ["--test-ledger", UUID().uuidString, "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launchEnvironment["YUBAI_UI_TEST_REDUCE_MOTION"] = reduceMotion ? "1" : "0"
        app.launchEnvironment["YUBAI_UI_TEST_SCRIPT"] = fixture
        app.launchEnvironment["YUBAI_GALLERY_HIDE_AMOUNTS"] = hidden ? "1" : "0"
        app.launchEnvironment["YUBAI_GALLERY_APPEARANCE"] = dark ? "dark" : "light"
        app.launchEnvironment["YUBAI_UI_TEST_ENTRY_EXPLICIT_FINISH"] = "1"
        app.launchEnvironment["DEEPSEEK_API_KEY"] = ""
        app.launch(); XCTAssertTrue(element("mainNavigation").waitForExistence(timeout: 15))
    }
    private func id(_ number: Int) -> String { String(format: "47000000-0000-0000-0000-%012d", number) }
    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
    private func reveal(_ target: XCUIElement) {
        XCTAssertTrue((target.exists || target.waitForExistence(timeout: 5)))
        for _ in 0..<8 {
            if target.isHittable && target.frame.maxY < element("mainNavigation").frame.minY { break }
            let scroll = app.scrollViews.matching(identifier: "nowScroll").firstMatch
            let first = app.scrollViews.matching(identifier: "firstOpenScroll").firstMatch
            if scroll.exists { scroll.swipeUp() } else if first.exists { first.swipeUp() } else { app.swipeUp() }
        }
    }
    private func tap(_ id: String) {
        let target = element(id); XCTAssertTrue((target.exists || target.waitForExistence(timeout: 5)), id)
        if !target.isHittable { reveal(target) }
        XCTAssertTrue(target.isHittable, id); target.tap()
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
        app.terminate(); app.launch(); XCTAssertTrue(element("mainNavigation").waitForExistence(timeout: 10))
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
        for id in ["openFixedFlows", "receiptOpenLedger", "receiptMoreEntries", "receiptTotal"] {
            let target = element(id); reveal(target)
            XCTAssertTrue(target.isHittable, id)
            XCTAssertLessThan(target.frame.maxY, element("mainNavigation").frame.minY, id)
        }
    }
    func testCapsuleStaysInPlaceAndAssistantInputClearsOnlyTheCapsule() {
        launch()
        let capsule = element("navigationCapsule").frame
        for tab in ["ledger", "yubai"] {
            tap("tab_" + tab)
            XCTAssertEqual(element("navigationCapsule").frame, capsule)
            XCTAssertFalse(element("addEntry").exists)
        }
        let field = element("askYubai")
        XCTAssertGreaterThanOrEqual(field.frame.height, 44)
        XCTAssertLessThan(field.frame.maxY, capsule.minY)
        XCTAssertLessThanOrEqual(capsule.minY - field.frame.maxY, 32)
    }
    func testLastTodayRowReachedFromReceiptClearsTheCapsuleAtBothTextSizes() {
        for large in [false, true] {
            launch("v47-receipt-many", large: large)
            reveal(element("receiptMoreEntries")); tap("receiptMoreEntries")
            let last = element("ledgerEntry_" + id(470110))
            for _ in 0..<12 {
                if last.exists && last.isHittable { break }
                app.swipeUp()
            }
            XCTAssertTrue(last.exists && last.isHittable)
            let header = element("rootHeaderRegion").frame, capsule = element("navigationCapsule").frame
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
