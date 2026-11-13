import XCTest

final class Round47ButlerFlowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws { app?.terminate(); app = nil; try super.tearDownWithError() }
    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
    private func launch(_ fixture: String = "v47-ai-valid", large: Bool = false, hidden: Bool = false, configured: Bool? = nil) {
        app = XCUIApplication()
        app.launchArguments = ["--test-ledger", UUID().uuidString, "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launchEnvironment["YUBAI_UI_TEST_SCRIPT"] = fixture
        app.launchEnvironment["YUBAI_UI_TEST_CONFIGURED_KEY"] = (configured ?? (fixture != "v47-c-empty")) ? "1" : "0"
        app.launchEnvironment["DEEPSEEK_API_KEY"] = ""
        app.launchEnvironment["YUBAI_GALLERY_HIDE_AMOUNTS"] = hidden ? "1" : "0"
        app.launch(); XCTAssertTrue(element("mainNavigation").waitForExistence(timeout: 15))
    }
    private func tap(_ id: String) {
        let target = element(id); XCTAssertTrue(target.waitForExistence(timeout: 8), id)
        for _ in 0..<10 { if target.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(target.isHittable, id); target.tap()
    }
    private func wait(_ condition: @escaping () -> Bool) {
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)], timeout: 10), .completed)
    }
    private func settings() { tap("openSettings"); tap("openIntelligencePrivacy"); XCTAssertTrue(element("butlerLastRun").waitForExistence(timeout: 5)) }
    private func backToRoot() {
        for _ in 0..<8 {
            if element("mainNavigation").exists && element("mainNavigation").isHittable { return }
            let custom = element("ledgerBack")
            if custom.exists { custom.tap() } else { app.navigationBars.buttons.firstMatch.tap() }
        }
    }
    func testVerifiedCardShowsCodeNumbersAndPushesEvidence() {
        launch(); XCTAssertTrue(element("butlerSuggestionCard").waitForExistence(timeout: 10))
        XCTAssertTrue(element("butlerAIText").label.contains("7 次，共 214.00"))
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "butlerSuggestionCard").count, 1)
        tap("butlerAIEvidence"); XCTAssertTrue(element("butlerAIEvidencePage").waitForExistence(timeout: 5))
        XCTAssertTrue(element("butlerEvidenceTitle").label.contains("214.00")); XCTAssertTrue(element("butlerEvidenceMemories").exists)
        XCTAssertTrue(element("butlerEvidenceMore").label.contains("3 笔"))
        tap("butlerEvidenceMore")
        XCTAssertTrue(element("butlerEvidenceEntry_" + String(format: "47000000-0000-0000-0000-%012d", 472107)).waitForExistence(timeout: 5))
    }
    func testTrialLeavesOneReviewAndWritesFeedbackMemory() {
        launch(); tap("butlerAIAccept"); wait { !self.element("butlerSuggestionCard").exists }
        settings(); XCTAssertTrue((element("butlerLastRun").value as? String ?? "").contains("reviews=1;memories=2"))
    }
    func testNeverAnswerPersistsAcrossRelaunch() {
        launch(); tap("butlerAINever"); app.terminate(); app.launch()
        XCTAssertTrue(element("mainNavigation").waitForExistence(timeout: 10))
        XCTAssertFalse(element("butlerSuggestionCard").exists)
        settings(); XCTAssertTrue((element("butlerLastRun").value as? String ?? "").contains("requests=0"))
    }
    func testCorrectionWithSentenceWritesMemoryAndClosesEvidence() {
        launch(); tap("butlerAIEvidence"); tap("butlerAIIncorrect")
        let field = element("butlerAICorrectionText"); field.tap(); field.typeText("周四是和同事拼单")
        tap("butlerAICorrectionSave"); wait { !self.element("butlerAIEvidencePage").exists }
        tap("tab_yubai"); tap("openMemories")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "周四是和同事拼单")).firstMatch.waitForExistence(timeout: 5))
    }
    func testCorrectionCanBeSubmittedWithoutSentence() {
        launch(); tap("butlerAIEvidence"); tap("butlerAIIncorrect"); tap("butlerAICorrectionSave")
        wait { !self.element("butlerAIEvidencePage").exists }
        settings(); XCTAssertTrue((element("butlerLastRun").value as? String ?? "").contains("memories=2"))
    }
    func testScriptedWrongSumUnknownIDUnknownActionMalformedAndEmptyNeverEnterQueue() {
        for fixture in ["v47-ai-wrong-sum", "v47-ai-unknown-id", "v47-ai-unknown-action", "v47-ai-malformed", "v47-ai-none"] {
            launch(fixture); settings()
            wait { (self.element("butlerLastRun").value as? String ?? "").contains("requests=1;suggestions=0") }
            backToRoot(); XCTAssertFalse(element("butlerSuggestionCard").exists); app.terminate()
        }
    }
    func testSeveralSuggestionsStillShowOneCardAtATime() {
        launch("v47-ai-many"); tap("butlerAIAccept")
        XCTAssertTrue(element("butlerSuggestionCard").waitForExistence(timeout: 5))
        tap("butlerAINever"); wait { !self.element("butlerSuggestionCard").exists }
        settings(); XCTAssertTrue((element("butlerLastRun").value as? String ?? "").contains("suggestions=2;reviews=1;memories=3"))
    }
    func testOrdinaryRelaunchDoesNotRequestAgain() {
        launch(); XCTAssertTrue(element("butlerSuggestionCard").waitForExistence(timeout: 10))
        app.terminate(); app.launch(); XCTAssertTrue(element("mainNavigation").waitForExistence(timeout: 10))
        settings(); XCTAssertTrue((element("butlerLastRun").value as? String ?? "").contains("requests=0;suggestions=1"))
    }
    func testToggleOffPersistsAndHidesSuggestions() {
        launch(); XCTAssertTrue(element("butlerSuggestionCard").waitForExistence(timeout: 10)); settings()
        tap("aiFeature_butlerSuggestions"); backToRoot(); XCTAssertFalse(element("butlerSuggestionCard").exists)
        app.terminate(); app.launch(); XCTAssertTrue(element("mainNavigation").waitForExistence(timeout: 10))
        settings(); XCTAssertEqual(element("aiFeature_butlerSuggestions").value as? String, "0")
    }
    func testDueTwoWeekReviewWorksOfflineWithoutNewRequest() {
        launch("v47-ai-review"); XCTAssertTrue(element("butlerAIReviewCard").waitForExistence(timeout: 10))
        tap("butlerAIReviewDone"); wait { !self.element("butlerAIReviewCard").exists }
        settings(); XCTAssertTrue((element("butlerLastRun").value as? String ?? "").contains("requests=0"))
    }
    func testLargestTextAndHiddenAmountsKeepEvidenceAndActionsReachable() {
        launch("v47-ai-hard", large: true, hidden: true); tap("butlerAIEvidence")
        XCTAssertTrue(element("butlerEvidenceTitle").label.contains("••••"))
        XCTAssertFalse(element("butlerEvidenceTitle").label.contains("1,234,567.89"))
        tap("butlerAIIncorrect"); tap("butlerAICorrectionSave")
    }
    func testEmptyLedgerActionsOpenCaptureAndImport() {
        launch("v47-c-empty"); tap("tab_ledger"); XCTAssertTrue(element("emptyState_ledger").exists)
        tap("emptyLedgerAdd"); XCTAssertTrue(element("entryKeypadAmount").waitForExistence(timeout: 5)); tap("cancelManualSheet")
        tap("emptyLedgerImport"); XCTAssertTrue(element("chooseBillFile").waitForExistence(timeout: 5))
    }
    func testEmptyAssistantExamplesSendImmediatelyAndValuesAndMemoriesHaveSharedState() {
        launch("v47-c-empty", configured: true); tap("tab_yubai"); XCTAssertTrue(element("emptyState_assistant").exists)
        tap("askSuggestion_0"); XCTAssertTrue(element("askAnswer").waitForExistence(timeout: 10)); backToRoot()
        tap("tab_yubai"); tap("openProfile"); XCTAssertTrue(element("emptyState_profile").exists)
        tap("addPrinciple"); XCTAssertTrue(element("principleText").waitForExistence(timeout: 5)); tap("cancelManualSheet")
        backToRoot(); tap("tab_yubai"); tap("openMemories"); XCTAssertTrue(element("emptyState_memories").exists)
    }
    func testEmptySavingWishBillsBudgetAndFrequentActionsAreConnected() {
        launch("v47-c-empty"); tap("openSaving"); XCTAssertTrue(element("emptyState_saving").exists)
        tap("openWishlist"); XCTAssertTrue(element("emptyState_wish").exists); tap("emptyAction_wish")
        XCTAssertTrue(element("wishTitle").waitForExistence(timeout: 5)); tap("cancelManualSheet"); backToRoot()
        tap("openSettings"); tap("openFixedFlows"); XCTAssertTrue(element("emptyState_bills").exists)
        tap("emptyAction_bills"); XCTAssertTrue(element("fixedFlowTitle").waitForExistence(timeout: 5)); tap("cancelManualSheet"); backToRoot()
        tap("openSettings"); tap("openSpendingParts"); XCTAssertTrue(element("emptyState_budget").exists)
        tap("addBudgetPart"); XCTAssertTrue(element("budgetPartName").waitForExistence(timeout: 5)); tap("cancelManualSheet"); backToRoot()
        element("addEntry").press(forDuration: 0.8); tap("manageQuickRepeats"); XCTAssertTrue(element("emptyState_frequent").exists)
        tap("emptyAction_frequent"); XCTAssertTrue(element("frequentEntryPurpose").waitForExistence(timeout: 5))
    }
    func testSearchNoResultsHasTwoDistinctExits() {
        launch(); tap("tab_ledger")
        let field = element("entriesSearch"); field.tap(); field.typeText("星巴克")
        XCTAssertTrue(element("emptyState_search").waitForExistence(timeout: 5))
        tap("emptySecondary_search"); XCTAssertTrue(element("emptyState_search").exists)
        tap("emptyAction_search"); XCTAssertFalse(element("emptyState_search").exists)
    }
    func testNoKeyDefaultsSuggestionToggleOffAndNeverRequests() {
        launch("v47-c-empty"); settings()
        XCTAssertEqual(element("aiFeature_butlerSuggestions").value as? String, "0")
        XCTAssertFalse(element("aiFeature_butlerSuggestions").isEnabled)
        XCTAssertTrue((element("butlerLastRun").value as? String ?? "").contains("requests=0"))
    }
    func testAddingFrequentTemplateSavesWithoutRecordingAnEntry() {
        launch("v47-c-empty"); element("addEntry").press(forDuration: 0.8); tap("manageQuickRepeats"); tap("emptyAction_frequent")
        let field = element("frequentEntryPurpose"); field.tap(); field.typeText("午饭\n")
        tap("keypad_2"); tap("keypad_8"); tap("saveFrequentEntry")
        XCTAssertTrue(element("frequentEntry_0").waitForExistence(timeout: 5)); tap("cancelManualSheet")
        tap("tab_ledger"); XCTAssertTrue(element("emptyState_ledger").exists)
    }
}
