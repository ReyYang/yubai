import XCTest

final class Round46Batch3FlowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws { app?.terminate(); app = nil; try super.tearDownWithError() }
    private func launch(_ fixture: String = "v46-b3-book", large: Bool = false) {
        app = XCUIApplication()
        app.launchArguments = ["--test-ledger", UUID().uuidString, "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launchEnvironment["YUBAI_UI_TEST_SCRIPT"] = fixture
        app.launchEnvironment["YUBAI_UI_TEST_CONFIGURED_KEY"] = "1"
        app.launchEnvironment["YUBAI_UI_TEST_KEEP_UNDO"] = "1"
        app.launchEnvironment["DEEPSEEK_API_KEY"] = ""
        app.launch(); XCTAssertTrue(element("mainNavigation").waitForExistence(timeout: 15))
    }
    private func id(_ value: Int) -> String { String(format: "47000000-0000-0000-0000-%012d", value) }
    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
    private func tap(_ id: String) {
        let target = element(id); XCTAssertTrue(target.waitForExistence(timeout: 6), id)
        for _ in 0..<12 { if target.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(target.isHittable, id); target.tap()
    }
    private func question(_ text: String) {
        tap("tab_yubai"); tap("askYubai"); element("askYubai").typeText(text); tap("sendAskHome")
    }
    func testOnlyNowHasGlobalAddAndEveryLedgerDayHasItsOwnAdd() {
        launch()
        let capsule = element("navigationCapsule").frame
        XCTAssertTrue(element("addEntry").exists)
        for tab in ["ledger", "yubai"] {
            tap("tab_" + tab)
            XCTAssertFalse(element("addEntry").exists)
            XCTAssertEqual(element("navigationCapsule").frame, capsule)
        }
        tap("tab_ledger")
        let add = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'addEntryOnDay_' ")).firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 5)); add.tap()
        XCTAssertTrue(element("entryKeypadAmount").waitForExistence(timeout: 5))
        XCTAssertTrue(element("entryDate_today").isSelected)
    }
    func testLedgerTapOpensOriginalSourceThenEditAndDeleteCanBeUndone() {
        launch(); tap("tab_ledger"); tap("ledgerEntry_" + id(460310))
        XCTAssertTrue(element("entryDetailSource").waitForExistence(timeout: 5))
        XCTAssertFalse(element("editEntryAmount").exists)
        tap("entryDetailEdit"); XCTAssertTrue(element("saveEditedEntry").waitForExistence(timeout: 5))
        tap("cancelManualSheet"); tap("deleteEntryDetail")
        XCTAssertTrue(element("toastMessage").waitForExistence(timeout: 5)); tap("undoLastChange")
        XCTAssertTrue(element("ledgerEntry_" + id(460310)).waitForExistence(timeout: 5))
    }
    func testLargestEditorKeepsTheWholeAmountAndACompactCategoryStrip() {
        launch("v46-b3-hard", large: true); tap("tab_ledger"); tap("ledgerEntry_" + id(460310)); tap("entryDetailEdit")
        let amount = element("editEntryAmount")
        XCTAssertTrue(amount.waitForExistence(timeout: 5)); XCTAssertEqual(amount.value as? String, "1,234,567.89")
        XCTAssertGreaterThanOrEqual(amount.frame.minX, app.frame.minX); XCTAssertLessThanOrEqual(amount.frame.maxX, app.frame.maxX)
        XCTAssertTrue(element("entryCategoryStrip").exists); XCTAssertLessThanOrEqual(element("entryCategoryStrip").frame.height, 60)
    }
    func testFirstCycleStillExposesCategoriesWithoutInventingComparison() {
        launch("v46-b3-where-empty"); tap("tab_ledger"); tap("ledgerMode_where")
        XCTAssertTrue(element("whereInsufficientData").waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["比平时多"].exists); XCTAssertFalse(app.staticTexts["比平时少"].exists)
        tap("whereAllCategories"); XCTAssertTrue(element("allCategoriesPage").waitForExistence(timeout: 5))
        tap("insightCategory_0"); XCTAssertTrue(element("whereCategoryEntries").waitForExistence(timeout: 5))
        tap("whereCategoryEntries"); XCTAssertTrue(element("clearLedgerCategory").waitForExistence(timeout: 5))
    }
    func testSaveEmptyStartsAtZeroAndSettingTargetRemovesPrompt() {
        launch("v46-b3-save-empty"); tap("openSaving")
        XCTAssertTrue(element("reserveTotal").label.contains("0.00")); XCTAssertFalse(element("openWishlist").exists)
        tap("setFirstSavingTarget"); tap("keypad_2"); tap("keypad_0"); tap("keypad_0"); tap("saveSavingsAmount")
        XCTAssertTrue(element("openSavings").waitForExistence(timeout: 5)); XCTAssertFalse(element("savingFirstRule").exists)
        tap("openSavings"); XCTAssertTrue(element("editSavingTarget").waitForExistence(timeout: 5))
    }
    func testCoolingWishKeepOpensAnAmountAndTitlePrefilledEntry() {
        launch(); tap("openSaving"); tap("openWishlist"); tap("cooldownKeep")
        XCTAssertTrue(element("entryKeypadAmount").waitForExistence(timeout: 5))
        XCTAssertEqual(element("entryKeypadAmount").value as? String, "1,899.00")
        XCTAssertEqual(element("entryPurpose").value as? String, "降噪耳机")
    }
    func testReserveRecordsStayPlainAcrossLaunch() {
        launch("v46-b3-reserve"); tap("openSaving"); tap("openReserve")
        XCTAssertTrue(element("reserveLine_0").waitForExistence(timeout: 5))
        XCTAssertFalse(element("reserveTotal").exists)
        app.terminate(); app.launch(); tap("openSaving"); tap("openReserve")
        XCTAssertTrue(element("reserveLine_0").waitForExistence(timeout: 5))
        XCTAssertFalse(element("reservePaybackOffer").exists)
    }

    func testSpendingAnswerUsesFactsAndOpensItsWhereDestination() {
        launch(); question("这个月钱去哪了")
        XCTAssertTrue(element("whereAnswerCard").waitForExistence(timeout: 15))
        XCTAssertTrue(element("askCategoryBudget").exists)
        tap("askShowWhere"); XCTAssertTrue(element("whereMonthlyCharges").waitForExistence(timeout: 5))
        XCTAssertTrue(element("tab_ledger").isSelected)
    }
    func testSentenceDraftsWaitForConfirmationAndSaveTogetherWithUndo() {
        launch(); question("帮我记：昨天打车 35，中午和同事吃饭 AA 我出了 62")
        XCTAssertTrue(element("multiEntryDraftCard").waitForExistence(timeout: 15))
        XCTAssertFalse(element("confirmDraftAmounts").exists)
        XCTAssertTrue(element("draftEntryPreview").waitForExistence(timeout: 5))
        tap("saveDraftEntries"); XCTAssertTrue(element("draftEntriesSaved").waitForExistence(timeout: 5))
        XCTAssertTrue(element("undoLastChange").waitForExistence(timeout: 5)); tap("undoLastChange")
    }
    func testPrincipleSuggestionSavesAndBecomesEditableInValues() {
        launch(); tap("tab_yubai"); tap("openProfile"); tap("addPrinciple")
        tap("principleSuggestion_每天用得上的，愿意多花"); tap("savePrinciple")
        XCTAssertTrue(element("profilePrinciple_每天用得上的，愿意多花").waitForExistence(timeout: 5))
    }
}
