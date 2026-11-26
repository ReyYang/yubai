import XCTest

final class Round47ButlerFlowTests: YubaiUITestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws { app?.terminate(); app = nil; try super.tearDownWithError() }
    private func element(_ id: String) -> XCUIElement { control(id, in: app) }
    private func launch(_ fixture: String = "v47-ai-valid", large: Bool = false, hidden: Bool = false, configured: Bool? = nil, dark: Bool = false) {
        app = XCUIApplication()
        app.launchArguments = ["--test-ledger", UUID().uuidString, "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launchEnvironment["YUBAI_UI_TEST_SCRIPT"] = fixture
        app.launchEnvironment["YUBAI_UI_TEST_CONFIGURED_KEY"] = (configured ?? (fixture != "v47-c-empty")) ? "1" : "0"
        app.launchEnvironment["DEEPSEEK_API_KEY"] = ""
        app.launchEnvironment["YUBAI_GALLERY_HIDE_AMOUNTS"] = hidden ? "1" : "0"
        app.launchEnvironment["YUBAI_GALLERY_APPEARANCE"] = dark ? "dark" : "light"
        if fixture.hasPrefix("v47r-") {
            let instant = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 20))!
            app.launchEnvironment["YUBAI_UI_TEST_NOW"] = String(instant.timeIntervalSince1970)
        }
        launchApp(app); XCTAssertTrue(element("mainNavigation").waitForExistence(timeout: 15))
    }
    private func tap(_ id: String) {
        if id == "tab_yubai" {
            openAssistantHub()
            return
        }
        if !element(id).exists, element("mainNavigation").exists,
           id.hasPrefix("butlerAI") || id.hasPrefix("savingsTopup") {
            openInbox()
        }
        let target = element(id)
        tapControl(target, in: app, settles: !id.hasPrefix("keypad_"), reveals: !id.hasPrefix("keypad_"))
    }

    private func openAssistantHub() {
        backToRoot()
        if !element("openSettings").exists { tap("tab_ledger") }
        tap("openSettings"); tap("openAssistantHub")
    }

    private func openInbox() {
        openAssistantHub()
        XCTAssertTrue(element("yubaiScroll").waitForExistence(timeout: 5))
        // The scripted suggestion is enqueued by the asynchronous cadence run.
        XCTAssertTrue(element("openButlerInbox").waitForExistence(timeout: 15),
                      "待办入口未出现（\(app.launchEnvironment["YUBAI_UI_TEST_SCRIPT"] ?? "")）")
        tap("openButlerInbox")
    }

    private func wait(file: StaticString = #filePath, line: UInt = #line, _ condition: () -> Bool) {
        XCTAssertTrue(UIConditionWait.run(timeout: 10, read: condition), file: file, line: line)
    }

    private func waitForRun(_ expected: String, file: StaticString = #filePath, line: UInt = #line) {
        let target = element("butlerLastRun")
        var latest = ""
        let matched = UIConditionWait.run(timeout: 10) {
            latest = target.value as? String ?? ""
            return latest.contains(expected)
        }
        XCTAssertTrue(matched, "\(app.launchEnvironment["YUBAI_UI_TEST_SCRIPT"] ?? ""): 期望 \(expected)，实际 \(latest)",
                      file: file, line: line)
    }
    private func openFrequentEntries() {
        openAssistantHub(); tap("openFrequentEntries")
        XCTAssertFalse(element("entryKeypadAmount").exists)
    }
    private func settings() { backToRoot(); tap("openSettings"); tap("openIntelligencePrivacy"); XCTAssertTrue(element("butlerLastRun").waitForExistence(timeout: 5)) }
    private func backToRoot() {
        let deadline = Date().addingTimeInterval(30)
        for _ in 0..<8 {
            XCTAssertTrue(waitForNativeTransition(in: app, deadline: deadline), transitionWaitReport)
            if element("mainNavigation").exists && element("mainNavigation").isHittable { return }
            let custom = element("BackButton")
            if custom.exists { custom.tap() } else { app.navigationBars.buttons.firstMatch.tap() }
        }
        XCTFail("Root navigation did not return")
    }
    func testVerifiedCardShowsCodeNumbersAndPushesEvidence() {
        launch(); openInbox(); XCTAssertTrue(element("butlerSuggestionCard").waitForExistence(timeout: 10))
        XCTAssertTrue(element("butlerAIText").label.contains("7 次，共 214.00"))
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "butlerSuggestionCard").count, 1)
        tap("butlerAIEvidence"); XCTAssertTrue(element("butlerAIEvidencePage").waitForExistence(timeout: 5))
        XCTAssertFalse(element("mainNavigation").exists)
        XCTAssertFalse(element("addEntry").exists)
        XCTAssertTrue(element("butlerEvidenceTitle").label.contains("214.00")); XCTAssertTrue(element("butlerEvidenceMemories").exists)
        XCTAssertTrue(element("butlerEvidenceMore").label.contains("3 笔"))
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "butlerEvidenceMore").count, 1)
        tap("butlerEvidenceEntry_" + String(format: "47000000-0000-0000-0000-%012d", 472101))
        tap("billMore")
        XCTAssertTrue(element("entryDetailEdit").waitForExistence(timeout: 5))
        XCTAssertFalse(element("mainNavigation").exists)
        tap("billMore"); tap("closeBill")
        tap("butlerEvidenceMore")
        XCTAssertFalse(element("mainNavigation").exists)
        XCTAssertTrue(element("butlerEvidenceEntry_" + String(format: "47000000-0000-0000-0000-%012d", 472107)).waitForExistence(timeout: 5))
    }
    func testTrialLeavesOneReviewAndWritesFeedbackMemory() {
        launch(); tap("butlerAIAccept"); wait { !self.element("butlerSuggestionCard").exists }
        settings(); XCTAssertTrue((element("butlerLastRun").value as? String ?? "").contains("reviews=1;memories=2"))
    }
    func testNeverAnswerPersistsAcrossRelaunch() {
        launch(); tap("butlerAIEvidence"); tap("butlerAINever"); app.terminate(); launchApp(app)
        XCTAssertTrue(element("mainNavigation").waitForExistence(timeout: 10))
        XCTAssertFalse(element("butlerSuggestionCard").exists)
        settings(); XCTAssertTrue((element("butlerLastRun").value as? String ?? "").contains("requests=0"))
    }
    func testCorrectionWithSentenceWritesMemoryAndClosesEvidence() {
        launch(); tap("butlerAIEvidence"); tap("butlerAIIncorrect")
        typeIntoField("周四是和同事拼单", identifier: "butlerAICorrectionText", in: app)
        tap("butlerAICorrectionSave")
        XCTAssertTrue(waitForDisappearance(element("butlerAICorrectionText")))
        XCTAssertTrue(waitForDisappearance(element("butlerAIEvidencePage")))
        tap("tab_yubai"); tap("openMemories")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "周四是和同事拼单")).firstMatch.waitForExistence(timeout: 5))
    }
    func testCorrectionCanBeSubmittedWithoutSentence() {
        launch(); tap("butlerAIEvidence"); tap("butlerAIIncorrect"); tap("butlerAICorrectionSave")
        wait { !self.element("butlerAIEvidencePage").exists }
        settings(); XCTAssertTrue((element("butlerLastRun").value as? String ?? "").contains("memories=2"))
    }
    func testCorrectionTypingKeepsAppResponsiveAtDefaultAndLargestText() {
        for large in [false, true] {
            launch(large: large); tap("butlerAIEvidence"); tap("butlerAIIncorrect")
            typeIntoField("周四是和同事拼单", identifier: "butlerAICorrectionText", in: app)
            XCTAssertTrue(element("butlerAICorrectionSave").exists)
            let deadline = ProcessInfo.processInfo.systemUptime + 5
            dismissNativeSheet(in: app, closing: element("butlerAICorrectionText"))
            XCTAssertTrue(UIConditionWait.run(timeout: 3, deadline: deadline, read: {
                !self.element("butlerAICorrectionText").exists && self.element("butlerAIEvidencePage").exists
            }), "Correction must respond to a second control within five seconds (large=\(large))")
            XCTAssertLessThan(ProcessInfo.processInfo.systemUptime, deadline)
            app.terminate()
        }
    }
    func testDirectCorrectionAutofocusSurvivesTypingCaptureCancellationReopeningAndSave() throws {
        try correctionAutofocusLifecycle(nested: false)
    }
    func testNestedCorrectionAutofocusSurvivesTypingCaptureCancellationReopeningAndSave() throws {
        try correctionAutofocusLifecycle(nested: true)
    }
    private func correctionAutofocusLifecycle(nested: Bool) throws {
        for large in [false, true] {
            for dark in [false, true] {
                launch(nested ? "v47-ai-valid" : "v47r-weekly-ai", large: large, dark: dark)
                if nested { tap("butlerAIEvidence") }
                tap("butlerAIIncorrect")
                XCTAssertTrue(waitForNativeTransition(in: app, deadline: Date().addingTimeInterval(12)))
                XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
                XCTAssertTrue(dismissKeyboardIntroduction(in: app))
                XCTAssertTrue(waitForKeyboardEditing("butlerAICorrectionText", in: app))
                assertFocusedAppearance("butlerAICorrectionText")
                let field = element("butlerAICorrectionText")
                field.typeText("周四是和同事拼单")
                XCTAssertEqual(field.value as? String, "周四是和同事拼单")
                // Gallery and flow controls share the app-only inventory.
                let tree = try app.snapshot()
                let scope = UIAppContentAuditScope(tree)
                for (button, snapshot) in scope.controls(in: tree, app: app) {
                    XCTAssertFalse(scope.isSystemKeyboard(snapshot))
                    _ = button.isHittable
                }
                XCTAssertNoThrow(try auditAppText(in: app) { issue in
                    XCTFail("Correction text clipped: " + issue.detailedDescription)
                    return true
                })
                assertBambooReadyForCapture(in: app)
                XCTAssertFalse(XCUIScreen.main.screenshot().pngRepresentation.isEmpty)
                XCTAssertEqual(app.state, .runningForeground)
                dismissNativeSheet(in: app)
                XCTAssertTrue(waitForDisappearance(element("butlerAICorrectionText")))
                XCTAssertTrue(waitForNativeTransition(in: app, deadline: Date().addingTimeInterval(12)))
                XCTAssertTrue(element(nested ? "butlerAIEvidencePage" : "butlerSuggestionCard").exists)
                XCTAssertTrue(element("butlerAIIncorrect").isHittable)
                tap("butlerAIIncorrect")
                XCTAssertTrue(waitForNativeTransition(in: app, deadline: Date().addingTimeInterval(12)))
                XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
                XCTAssertTrue(waitForKeyboardEditing("butlerAICorrectionText", in: app))
                assertFocusedAppearance("butlerAICorrectionText")
                XCTAssertEqual(element("butlerAICorrectionText").value as? String, "")
                element("butlerAICorrectionText").typeText("周五也是")
                XCTAssertEqual(element("butlerAICorrectionText").value as? String, "周五也是")
                tap("butlerAICorrectionSave")
                XCTAssertTrue(waitForDisappearance(element("butlerAICorrectionText")))
                if nested { XCTAssertTrue(waitForDisappearance(element("butlerAIEvidencePage"))) }
                XCTAssertEqual(app.state, .runningForeground)
                tap("tab_yubai"); tap("openMemories")
                XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "周五也是")).firstMatch.waitForExistence(timeout: 5))
                XCTAssertEqual(app.state, .runningForeground)
                app.terminate()
            }
        }
    }
    private func assertFocusedAppearance(_ identifier: String) {
        // Repeated reads must not turn a retained completed coordinator back
        // into an active transition or lose the modal's diagnostic probe.
        for _ in 0..<3 {
            let metrics = windowMetrics(in: app)
            XCTAssertNotNil(metrics)
            XCTAssertEqual(metrics?.transitioning, false)
            XCTAssertEqual(metrics?.focused, identifier)
            XCTAssertEqual(metrics?.focusedAfterAppearance, true, "Native focus began before its host appeared: \(identifier)")
        }
    }
    private func auditFocusedSheet(_ identifier: String) throws {
        XCTAssertTrue(waitForNativeTransition(in: app, deadline: Date().addingTimeInterval(12)))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(dismissKeyboardIntroduction(in: app))
        XCTAssertTrue(waitForKeyboardEditing(identifier, in: app), keyboardWaitReport)
        assertFocusedAppearance(identifier)
        let editingHost = try XCTUnwrap(windowMetrics(in: app)?.focusedHost, "Focused native host must be observable")
        XCTAssertEqual(app.state, .runningForeground)
        // This is the same native audit that crashed the correction stop.
        // Its Dynamic Type pass changes content size while the editor stays up.
        try auditAppText(in: app, dynamicType: true) { issue in
            XCTFail("Focused sheet accessibility audit: " + issue.detailedDescription)
            return true
        }
        XCTAssertEqual(app.state, .runningForeground)
        XCTAssertTrue(waitForKeyboardEditing(identifier, in: app), keyboardWaitReport)
        assertFocusedAppearance(identifier)
        XCTAssertEqual(windowMetrics(in: app)?.focusedHost, editingHost, "Dynamic Type must retain the active native editing host")
        XCTAssertEqual(app.textViews.matching(identifier: identifier).count, 1)
        assertBambooReadyForCapture(in: app)
        XCTAssertFalse(XCUIScreen.main.screenshot().pngRepresentation.isEmpty)
    }
    func testCorrectionKeyboardSurvivesDynamicTypeAndClippingAudit() throws {
        try correctionAudit(nested: false)
    }
    func testNestedCorrectionKeyboardSurvivesDynamicTypeAndClippingAudit() throws {
        try correctionAudit(nested: true)
    }
    private func correctionAudit(nested: Bool) throws {
        for mode in [(false, false, false), (false, true, false), (true, false, false), (true, true, true)] {
            launch(nested ? "v47-ai-valid" : "v47r-weekly-ai", large: mode.0, hidden: mode.2, dark: mode.1)
            if nested { tap("butlerAIEvidence") }
            tap("butlerAIIncorrect")
            try auditFocusedSheet("butlerAICorrectionText")
            element("butlerAICorrectionText").typeText("周四是和同事拼单")
            try auditFocusedSheet("butlerAICorrectionText")
            XCTAssertEqual(element("butlerAICorrectionText").value as? String, "周四是和同事拼单")
            tap("butlerAICorrectionSave")
            XCTAssertTrue(waitForDisappearance(element("butlerAICorrectionText")))
            if nested { XCTAssertTrue(waitForDisappearance(element("butlerAIEvidencePage"))) }
            XCTAssertEqual(app.state, .runningForeground)
            app.terminate()
        }
    }
    func testMemoryAutofocusSheetKeyboardSurvivesDynamicTypeAndClippingAudit() throws {
        let noteID = String(format: "47000000-0000-0000-0000-%012d", 472090)
        for mode in [(false, false), (false, true), (true, false), (true, true)] {
            launch(large: mode.0, dark: mode.1)
            tap("tab_yubai"); tap("openMemories")
            let row = app.buttons["memory_" + noteID]
            XCTAssertTrue(revealControl(row, in: app, deadline: Date().addingTimeInterval(60)))
            XCTAssertTrue(waitForStableFrame(row))
            let cell = app.cells.containing(.button, identifier: "memory_" + noteID).firstMatch
            XCTAssertTrue(cell.exists)
            // Run 13 also activated the NavigationLink via cell coordinates.
            // Use the settled row's screen-space pan, then require the real
            // swipe action and sheet header before running either native audit.
            XCTAssertTrue(swipeToRevealTrailingActions(row, in: app, deadline: Date().addingTimeInterval(5)), revealFailure)
            let edit = app.buttons["swipeEditMemory_" + noteID]
            XCTAssertTrue(edit.waitForExistence(timeout: 5))
            XCTAssertTrue(edit.isHittable)
            XCTAssertFalse(element("memoryText").exists, "A swipe must not activate the pushed editor")
            tapControl(edit, in: app, reveals: false)
            XCTAssertTrue(element("nativeSheetHeader").waitForExistence(timeout: 5))
            try auditFocusedSheet("memoryText")
            element("memoryText").typeText("周四和同事拼单")
            try auditFocusedSheet("memoryText")
            XCTAssertTrue((element("memoryText").value as? String ?? "").contains("周四和同事拼单"))
            tap("saveMemory")
            XCTAssertTrue(waitForDisappearance(element("memoryText")))
            XCTAssertEqual(app.state, .runningForeground)
            app.terminate()
        }
    }
    func testScriptedWrongSumUnknownIDUnknownActionMalformedAndEmptyNeverEnterQueue() {
        for fixture in ["v47-ai-wrong-sum", "v47-ai-unknown-id", "v47-ai-unknown-action", "v47-ai-malformed", "v47-ai-none"] {
            launch(fixture); settings()
            waitForRun("requests=1;suggestions=0")
            backToRoot(); XCTAssertFalse(element("butlerSuggestionCard").exists); app.terminate()
        }
    }
    func testSeveralSuggestionsStillShowOneCardAtATime() {
        launch("v47-ai-many"); openInbox(); tap("butlerAIAccept")
        XCTAssertTrue(element("butlerSuggestionCard").waitForExistence(timeout: 5))
        tap("butlerAIEvidence"); tap("butlerAINever"); wait { !self.element("butlerSuggestionCard").exists }
        settings(); XCTAssertTrue((element("butlerLastRun").value as? String ?? "").contains("suggestions=2;reviews=1;memories=3"))
    }
    func testNextSuggestionAtLargestTextKeepsBothAnswersLegibleAboveThePillInEveryAppearance() {
        for mode in [(false, false), (true, false), (false, true), (true, true)] {
            launch("v47-ai-many", large: true, hidden: mode.1, dark: mode.0)
            tap("butlerAIAccept")
            let headline = element("butlerAIText")
            XCTAssertTrue(headline.waitForExistence(timeout: 5))
            XCTAssertEqual(headline.value as? String, "已展开")
            XCTAssertFalse(element("expandButlerHeadline").exists)
            let accept = element("butlerAIAccept"), incorrect = element("butlerAIIncorrect")
            XCTAssertTrue(revealControlsTogether([accept, incorrect], in: app, deadline: Date().addingTimeInterval(60),
                searching: element("butlerInboxScroll"), bottomClearance: 40))
            for target in [accept, incorrect] {
                XCTAssertTrue(target.isHittable)
                XCTAssertLessThanOrEqual(target.frame.maxY, element("butlerInboxScroll").frame.maxY - 40 + 0.5)
                XCTAssertFalse(element("mainNavigation").exists)
            }
            XCTAssertNoThrow(try auditAppText(in: app) { issue in
                if let target = issue.element, ["butlerAIAccept", "butlerAIIncorrect", "butlerAIText"].contains(target.identifier) ||
                    ["试两周", "说得不对"].contains(target.label) {
                    XCTFail("Next suggestion text clipped: " + issue.detailedDescription)
                }
                return true
            })
            tap("butlerAIIncorrect")
            XCTAssertTrue(waitForKeyboardEditing("butlerAICorrectionText", in: app))
            dismissNativeSheet(in: app)
            XCTAssertTrue(waitForDisappearance(element("butlerAICorrectionText")))
            tap("butlerAIAccept")
            wait { !self.element("butlerSuggestionCard").exists }
            XCTAssertEqual(app.state, .runningForeground)
            app.terminate()
        }
    }
    func testOrdinaryRelaunchDoesNotRequestAgain() {
        launch(); openInbox(); XCTAssertTrue(element("butlerSuggestionCard").waitForExistence(timeout: 10))
        app.terminate(); launchApp(app); XCTAssertTrue(element("mainNavigation").waitForExistence(timeout: 10))
        settings(); XCTAssertTrue((element("butlerLastRun").value as? String ?? "").contains("requests=0;suggestions=1"))
    }
    func testToggleOffPersistsAndHidesSuggestions() {
        launch(); openInbox(); XCTAssertTrue(element("butlerSuggestionCard").waitForExistence(timeout: 10)); settings()
        tap("aiFeature_butlerSuggestions"); XCTAssertEqual(element("aiFeature_butlerSuggestions").value as? String, "0")
        backToRoot(); XCTAssertFalse(element("butlerSuggestionCard").exists)
        app.terminate(); launchApp(app); XCTAssertTrue(element("mainNavigation").waitForExistence(timeout: 10))
        settings(); XCTAssertEqual(element("aiFeature_butlerSuggestions").value as? String, "0")
    }
    func testDueTwoWeekReviewWorksOfflineWithoutNewRequest() {
        launch("v47-ai-review"); openInbox(); XCTAssertTrue(element("butlerAIReviewCard").waitForExistence(timeout: 10))
        tap("butlerAIReviewDone"); wait { !self.element("butlerAIReviewCard").exists }
        settings(); XCTAssertEqual(element("cloudAIToggle").value as? String, "0")
        XCTAssertTrue((element("butlerLastRun").value as? String ?? "").contains("requests=0"))
    }
    func testLargestTextAndHiddenAmountsKeepEvidenceAndActionsReachable() {
        launch("v47-ai-hard", large: true, hidden: true); tap("butlerAIEvidence")
        XCTAssertTrue(element("butlerEvidenceTitle").label.contains("••••"))
        XCTAssertFalse(element("butlerEvidenceTitle").label.contains("1,234,567.89"))
        tap("butlerAIIncorrect"); tap("butlerAICorrectionSave")
    }
    func testAssistantSuggestionsAndValuesAndMemoriesUseRevisionRoutes() {
        launch("v47-c-empty", configured: true); tap("tab_yubai")
        XCTAssertTrue(element("askYubai").exists)
        XCTAssertFalse(element("emptyState_assistant").exists)
        for index in 0..<2 {
            XCTAssertGreaterThanOrEqual(element("askSuggestion_\(index)").frame.height, 44)
        }
        XCTAssertFalse(element("askSuggestion_2").exists)
        tap("askSuggestion_0")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForKeyboardEditing("askYubai", in: app))
        XCTAssertTrue((element("askYubai").value as? String ?? "").contains("这个能买吗"))
        tap("sendAskHome"); XCTAssertTrue(element("askAnswer").waitForExistence(timeout: 10)); openAssistantHub()
        tap("askSuggestion_1"); XCTAssertTrue(element("askAnswer").waitForExistence(timeout: 10)); openAssistantHub()
        tap("openProfile"); XCTAssertTrue(element("emptyState_profile").exists)
        tap("addPrinciple"); XCTAssertTrue(element("principleText").waitForExistence(timeout: 5))
        dismissNativeSheet(in: app, closing: element("principleText"))
        openAssistantHub(); tap("openMemories"); XCTAssertTrue(element("emptyState_memories").exists)
        XCTAssertTrue(element("emptyMemories").exists)
    }
    func testEmptySavingWishBillsBudgetAndFrequentActionsAreConnected() {
        launch("v47-c-empty"); XCTAssertFalse(element("openSaving").exists)
        openAssistantHub(); tap("openSaving")
        XCTAssertTrue(element("emptyState_saving").waitForExistence(timeout: 5))
        XCTAssertFalse(element("reserveTotal").exists)
        XCTAssertFalse(element("takeSavings").exists)
        XCTAssertTrue(element("savingFirstRule").exists)
        XCTAssertFalse(element("openWishlist").exists)
        tap("setFirstSavingTarget"); tap("keypad_2"); tap("keypad_0"); tap("keypad_0"); tap("saveSavingsAmount")
        XCTAssertFalse(element("emptyState_saving").exists)
        tap("openWishlist"); XCTAssertTrue(element("emptyState_wish").exists)
        XCTAssertFalse(element("wishlistSavings").exists)
        tap("emptyAction_wish")
        XCTAssertTrue(element("wishTitle").waitForExistence(timeout: 5))
        dismissNativeSheet(in: app, closing: element("wishTitle"))
        XCTAssertTrue(element("emptyState_wish").waitForExistence(timeout: 5))
        backToRoot()
        openAssistantHub(); tap("openFixedFlows"); XCTAssertTrue(element("emptyState_bills").waitForExistence(timeout: 5))
        tap("emptyAction_bills"); XCTAssertTrue(element("fixedFlowTitle").waitForExistence(timeout: 5))
        dismissNativeSheet(in: app, closing: element("fixedFlowTitle"))
        XCTAssertTrue(element("emptyState_bills").waitForExistence(timeout: 5))
        backToRoot()
        tap("openSettings"); tap("openSpendingParts")
        XCTAssertTrue(element("spendingPartsPage").exists)
        let category = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'newBudget_'")).firstMatch
        tapControl(category, in: app)
        XCTAssertTrue(element("budgetKeypad").waitForExistence(timeout: 5))
        tap("cancelBudgetKeypad")
        XCTAssertTrue(waitForDisappearance(element("budgetKeypad")))
        backToRoot()
        openFrequentEntries(); XCTAssertTrue(element("emptyState_frequent").exists)
        tap("emptyAction_frequent"); XCTAssertTrue(element("frequentEntryPurpose").waitForExistence(timeout: 5))
        dismissNativeSheet(in: app, closing: element("frequentEntryPurpose"))
        XCTAssertTrue(element("emptyState_frequent").waitForExistence(timeout: 5))
    }
    func testSearchNoResultsOffersCancelAndAsk() {
        launch(); tap("tab_ledger"); tap("openLedgerSearch")
        let field = element("entriesSearch")
        field.typeText("未见的搜索词")
        let summary = element("entriesSearchTotal")
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertTrue(summary.label.contains("0 笔"))
        tap("askHomeSearch")
        XCTAssertTrue(element("askPage").waitForExistence(timeout: 5))
        tap("BackButton")
        tap("entriesSearchCancel")
        XCTAssertTrue(waitForDisappearance(field))
    }
    func testNoKeyDefaultsSuggestionToggleOffAndNeverRequests() {
        launch("v47-c-empty"); settings()
        XCTAssertEqual(element("aiFeature_butlerSuggestions").value as? String, "0")
        XCTAssertFalse(element("aiFeature_butlerSuggestions").isEnabled)
        XCTAssertTrue((element("butlerLastRun").value as? String ?? "").contains("requests=0"))
    }
    func testEntryTapAndHoldRemainDistinctThroughLargestTextAndFrequentAdd() {
        for mode in [(false, false, false), (false, true, false), (true, false, false), (true, true, true)] {
            launch("v47-c-empty", large: mode.0, hidden: mode.2, dark: mode.1)
            XCTAssertEqual(app.buttons.matching(identifier: "addEntry").count, 1)
            tap("addEntry")
            XCTAssertTrue(element("entryKeypadAmount").waitForExistence(timeout: 5))
            XCTAssertFalse(element("quickRepeatMenu").exists)
            dismissEntrySheet(in: app)
            XCTAssertTrue(waitForDisappearance(element("entryKeypadAmount")))
            openFrequentEntries()
            XCTAssertTrue(element("emptyState_frequent").waitForExistence(timeout: 5))
            tap("emptyAction_frequent")
            XCTAssertTrue(element("saveFrequentEntry").waitForExistence(timeout: 5))
            typeIntoField("午饭\n", identifier: "frequentEntryPurpose", in: app)
            tap("keypad_2"); tap("keypad_8"); tap("saveFrequentEntry")
            XCTAssertTrue(element("frequentEntry_0").waitForExistence(timeout: 5))
            app.terminate()
        }
    }
    func testNestedFrequentFieldPaddingTakesFocusAfterReopening() {
        for large in [false, true] {
            launch("v47-c-empty", large: large)
            openFrequentEntries()
            for _ in 0..<2 {
                tap("emptyAction_frequent")
                let field = element("frequentEntryPurpose")
                XCTAssertTrue(field.waitForExistence(timeout: 5))
                XCTAssertTrue(waitForStableFrame(field))
                XCTAssertGreaterThanOrEqual(field.frame.height, 44)
                field.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.95)).tap()
                XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
                XCTAssertTrue(dismissKeyboardIntroduction(in: app))
                XCTAssertTrue(waitForKeyboardEditing("frequentEntryPurpose", in: app))
                // KeypadSheet keeps its footer mounted while the text editor owns
                // focus. The numeric key must stop being a visible tap target.
                wait {
                    let key = self.element("keypad_1")
                    return !key.exists || !key.isHittable
                }
                XCTAssertTrue(waitForStableFrame(field))
                XCTAssertEqual(windowMetrics(in: app)?.focused, "frequentEntryPurpose")
                field.typeText("午")
                XCTAssertTrue(waitForStableFrame(field))
                XCTAssertTrue(app.keyboards.firstMatch.exists)
                XCTAssertEqual(windowMetrics(in: app)?.focused, "frequentEntryPurpose")
                field.typeText("饭\n")
                XCTAssertTrue((field.value as? String ?? "").contains("午饭"))
                XCTAssertTrue(waitForKeyboardDismissal(in: app))
                XCTAssertTrue(element("keypad_1").isHittable)
                dismissNativeSheet(in: app)
            }
            XCTAssertTrue(element("emptyState_frequent").exists)
            app.terminate()
        }
    }
    func testPaydayTopupAndAISuggestionBothSurviveAnswersAndRelaunch() {
        launch("v47-ai-topup"); openInbox()
        XCTAssertTrue(element("savingsTopupCard").waitForExistence(timeout: 10))
        settings()
        waitForRun("requests=1;suggestions=1")
        backToRoot(); tap("tab_ledger")
        tap("savingsTopupAll")
        tap("butlerAIAccept")
        wait { !self.element("butlerSuggestionCard").exists && !self.element("savingsTopupCard").exists }
        app.terminate(); launchApp(app)
        XCTAssertTrue(element("mainNavigation").waitForExistence(timeout: 10))
        XCTAssertFalse(element("savingsTopupCard").exists)
        XCTAssertFalse(element("butlerSuggestionCard").exists)
        settings()
        XCTAssertTrue((element("butlerLastRun").value as? String ?? "").contains("requests=0;suggestions=1;reviews=1;memories=2"))
        backToRoot(); app.open(URL(string: "yubai://saving")!)
        XCTAssertTrue(element("reserveTotal").waitForExistence(timeout: 5))
        XCTAssertTrue(element("reserveTotal").label.contains("5,000.00"))
    }
    func testCombinedQueueKeepsBothTasksReachableWithLargestTextAndHiddenAmounts() {
        launch("v47-ai-topup-hard", large: true, hidden: true); openInbox()
        XCTAssertTrue(element("savingsTopupCard").waitForExistence(timeout: 10))
        settings()
        wait { (self.element("butlerLastRun").value as? String ?? "").contains("suggestions=1") }
        backToRoot(); tap("tab_ledger")
        XCTAssertFalse(element("butlerSuggestionCard").exists)
        tap("savingsTopupDecline"); tap("butlerAIEvidence")
        XCTAssertTrue(element("butlerEvidenceTitle").waitForExistence(timeout: 5))
        XCTAssertTrue(element("butlerEvidenceTitle").label.contains("••••"))
        tap("butlerAIIncorrect"); tap("butlerAICorrectionSave")
        // Save closes the correction, then its onDismiss pops the evidence.
        // Waiting for both postconditions avoids tapping the outgoing page's
        // BackButton between those two native transitions (run 12, t=50.3s).
        XCTAssertTrue(waitForDisappearance(element("butlerAICorrectionText")))
        XCTAssertTrue(waitForDisappearance(element("butlerAIEvidencePage")))
        backToRoot()
        XCTAssertFalse(element("savingsTopupCard").exists)
        XCTAssertFalse(element("butlerSuggestionCard").exists)
    }
    func testEvidenceLastRowClearsViewportAndFixedActionsAndCorrectionPaddingWorkAtLargestText() {
        launch(large: true); tap("butlerAIEvidence")
        XCTAssertTrue(element("butlerAIEvidencePage").waitForExistence(timeout: 5))
        let scroll = app.scrollViews["butlerAIEvidencePage"]
        XCTAssertTrue(waitForNativeTransition(in: app, deadline: Date().addingTimeInterval(30)))
        XCTAssertTrue(waitForStableFrame(scroll))
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'butlerEvidenceEntry_' OR identifier == 'butlerEvidenceMore'"))
        XCTAssertGreaterThan(rows.count, 0)
        XCTAssertTrue(rows.firstMatch.isHittable)
        for id in ["butlerAIAccept", "butlerAINever", "butlerAIIncorrect"] {
            assertViewport(scroll, clears: element(id))
        }
        let last = element("butlerEvidenceEntry_47000000-0000-0000-0000-000000472104"), more = element("butlerEvidenceMore")
        XCTAssertTrue(revealControl(more, in: app, deadline: Date().addingTimeInterval(60)))
        scroll.swipeUp()
        XCTAssertTrue(waitForStableFrame(last))
        for row in [last, more] {
            XCTAssertTrue(scroll.frame.insetBy(dx: -0.5, dy: -0.5).contains(row.frame), row.identifier)
            XCTAssertLessThanOrEqual(row.frame.maxY, element("butlerAIAccept").frame.minY, row.identifier)
            XCTAssertTrue(row.isHittable)
        }
        let crossing = element("butlerEvidenceEntry_47000000-0000-0000-0000-000000472103")
        XCTAssertTrue(placeControl(crossing, across: element("butlerAIAccept"), in: scroll, atTop: false))
        tap("butlerAIIncorrect")
        XCTAssertFalse(element("entryDetailEdit").exists)
        let field = element("butlerAICorrectionText")
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForStableFrame(field))
        XCTAssertGreaterThanOrEqual(field.frame.height, 44)
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.95)).tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(dismissKeyboardIntroduction(in: app))
        field.typeText("周四是和同事拼单")
        XCTAssertTrue((field.value as? String ?? "").contains("周四是和同事拼单"))
        tap("butlerAICorrectionSave")
        wait { !self.element("butlerAICorrectionText").exists && !self.element("butlerAIEvidencePage").exists }
    }
}
