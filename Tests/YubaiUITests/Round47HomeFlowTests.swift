import XCTest

final class Round47HomeFlowTests: YubaiUITestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws { app?.terminate(); app = nil; try super.tearDownWithError() }
    private func launch(_ fixture: String = "v47r-ledger", large: Bool = false, hidden: Bool = false, dark: Bool = false, reduceMotion: Bool = false) {
        app = XCUIApplication()
        app.launchArguments = ["--test-ledger", UUID().uuidString, "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launchEnvironment["YUBAI_UI_TEST_SCRIPT"] = fixture
        let instant = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 20))!
        app.launchEnvironment["YUBAI_UI_TEST_NOW"] = String(instant.timeIntervalSince1970)
        app.launchEnvironment["YUBAI_GALLERY_HIDE_AMOUNTS"] = hidden ? "1" : "0"
        app.launchEnvironment["YUBAI_GALLERY_APPEARANCE"] = dark ? "dark" : "light"
        app.launchEnvironment["YUBAI_UI_TEST_REDUCE_MOTION"] = reduceMotion ? "1" : "0"
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
            tap("toggleAmountVisibility")
            for tab in ["insights", "yubai", "ledger"] { tap("tab_" + tab) }
            tap("toggleAmountVisibility")
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
            tap("toggleAmountVisibility")
            XCTAssertTrue(element("entriesMonth").isHittable, diagnostics)
            XCTAssertEqual(app.state, .runningForeground, diagnostics)
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
    private func checkTopBarImmediatelyAndAfterScrolling(large: Bool = false, hidden: Bool = false, dark: Bool = false) {
        launch(large: large, hidden: hidden, dark: dark)
        let scroll = element("entriesScroll")
        for scrolled in [false, true] {
            for id in ["toggleAmountVisibility", "entriesMonth", "openLedgerSearch", "openLedgerFilters"] {
                if scrolled {
                    scroll.swipeUp()
                    XCTAssertTrue(UIConditionWait.run(timeout: 6, read: {
                        (self.windowMetrics(in: self.app)?.scroll(matching: scroll.frame)?.remainingUp ?? 0) > 0.5
                    }), "The control must be tested after actual list motion: " + id)
                }
                let target = element(id), header = element("rootHeaderRegion")
                XCTAssertTrue(target.waitForExistence(timeout: 5))
                XCTAssertTrue(header.frame.insetBy(dx: -0.5, dy: -0.5).contains(target.frame))
                XCTAssertTrue(target.isHittable, "Visible top-bar control must accept native hits: " + id)
                switch id {
                case "toggleAmountVisibility":
                    let before = target.label
                    tap(id)
                    wait { target.label != before }
                    tap(id); wait { target.label == before }
                case "entriesMonth":
                    tap(id)
                    XCTAssertTrue(element("ledgerJumpMonth_1").waitForExistence(timeout: 5))
                    tap("cancelManualSheet")
                    XCTAssertTrue(waitForDisappearance(element("ledgerJumpMonth_1")))
                case "openLedgerSearch":
                    tap(id)
                    XCTAssertTrue(waitForKeyboardEditing("entriesSearch", in: app))
                    let field = element("entriesSearch")
                    tapControl(field, in: app)
                    field.typeText("咖啡")
                    XCTAssertTrue(element("entriesSearchTotal").waitForExistence(timeout: 5))
                    XCTAssertTrue(element("entriesSearchCancel").isHittable)
                    tap("entriesSearchCancel")
                    XCTAssertTrue(waitForDisappearance(field))
                    XCTAssertTrue(waitForKeyboardDismissal(in: app))
                default:
                    tap(id)
                    XCTAssertTrue(element("entriesFilter_收入").waitForExistence(timeout: 5))
                    tap(id)
                    XCTAssertTrue(waitForDisappearance(element("entriesFilter_收入")))
                }
                XCTAssertTrue(waitForNativeTransition(in: app, deadline: Date().addingTimeInterval(12)))
            }
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
    func testFloatingPillAndCapsuleKeepTheSameCompactGeometryAcrossTextSizesAndModes() {
        var baselinePill: CGSize?, baselineCapsule: CGSize?
        for mode in [(false, false, false), (true, false, false), (true, true, false), (true, false, true), (true, true, true)] {
            launch(large: mode.0, hidden: mode.2, dark: mode.1)
            let pill = element("addEntry"), scroll = element("entriesScroll")
            XCTAssertTrue(waitForStableFrame(pill))
            let capsule = capsuleFrame(in: app)
            XCTAssertGreaterThanOrEqual(pill.frame.height, 44)
            XCTAssertGreaterThanOrEqual(pill.frame.width, 44)
            XCTAssertEqual(pill.frame.height, 52, accuracy: 0.5)
            if let baselinePill, let baselineCapsule {
                XCTAssertEqual(pill.frame.width, baselinePill.width, accuracy: 0.5)
                XCTAssertEqual(pill.frame.height, baselinePill.height, accuracy: 0.5)
                XCTAssertEqual(capsule.width, baselineCapsule.width, accuracy: 0.5)
                XCTAssertEqual(capsule.height, baselineCapsule.height, accuracy: 0.5)
            } else { baselinePill = pill.frame.size; baselineCapsule = capsule.size }
            // Reservation follows the actual measured navigation, including its
            // real pill, inter-control gap and capsule, after the font cap.
            XCTAssertEqual(scroll.frame.maxY, element("mainNavigation").frame.minY, accuracy: 0.5)
            XCTAssertEqual(capsule.minY - pill.frame.maxY, 12, accuracy: 0.5)
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
                    let deadline = Date().addingTimeInterval(90)
                    launch("v47r-ledger-hard", large: large, hidden: hidden, dark: dark)
                    tap("openLedgerSearch")
                    // Use the same in-place autofocus route as the gallery;
                    // do not tap the field again to rescue a lost request.
                    XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
                    XCTAssertTrue(dismissKeyboardIntroduction(in: app))
                    XCTAssertTrue(waitForKeyboardEditing("entriesSearch", in: app, deadline: deadline), keyboardWaitReport)
                    let metrics = windowMetrics(in: app)
                    let context = "large=\(large) dark=\(dark) hidden=\(hidden) focusEvents=\(metrics?.inputFocusEvents ?? [])"
                    XCTAssertEqual(metrics?.focused, "entriesSearch", context)
                    XCTAssertEqual(metrics?.focusedAfterAppearance, true, context)
                    XCTAssertEqual(metrics?.transitioning, false)
                    XCTAssertNotNil(metrics?.focusedHost, context)
                    element("entriesSearch").typeText("咖啡")
                    XCTAssertEqual(element("entriesSearch").value as? String, "咖啡", context)
                    XCTAssertTrue(waitForKeyboardEditing("entriesSearch", in: app, deadline: deadline), keyboardWaitReport)
                    let afterTyping = windowMetrics(in: app)
                    XCTAssertEqual(afterTyping?.focusedAfterAppearance, true, context)
                    XCTAssertEqual(afterTyping?.focusedHost, metrics?.focusedHost, context)
                    let end = ProcessInfo.processInfo.systemUptime + max(0, deadline.timeIntervalSinceNow)
                    XCTAssertTrue(UIConditionWait.run(deadline: end, read: { self.element("entriesSearchTotal").exists }))
                    XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "entriesSearchTotal").count, 1)
                    XCTAssertTrue(element("entriesFilter_没分类").exists)
                    XCTAssertTrue(element("entriesSearchTotal").label.contains(hidden ? "金额已隐藏" : "共"))
                    XCTAssertTrue(waitForNativeTransition(in: app, deadline: deadline))
                    XCTAssertLessThan(Date(), deadline)
                    tap("entriesSearchCancel")
                    XCTAssertTrue(waitForDisappearance(element("entriesSearch")))
                    XCTAssertTrue(waitForNativeTransition(in: app, deadline: deadline))
                    XCTAssertTrue(element("availableFunds").exists)
                    XCTAssertEqual(app.state, .runningForeground)
                    app.terminate()
                }
            }
        }
    }
    func testSearchAutofocusReopensAfterCancelAndStaysDismissedAfterReturn() {
        for large in [false, true] {
            launch("v47r-ledger-hard", large: large)
            let deadline = Date().addingTimeInterval(90)
            tap("openLedgerSearch")
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
            XCTAssertTrue(dismissKeyboardIntroduction(in: app))
            XCTAssertTrue(waitForKeyboardEditing("entriesSearch", in: app, deadline: deadline), keyboardWaitReport)
            XCTAssertEqual(windowMetrics(in: app)?.focusedAfterAppearance, true)
            element("entriesSearch").typeText("咖啡\n")
            XCTAssertTrue(waitForKeyboardDismissal(in: app, deadline: deadline))
            XCTAssertEqual(element("entriesSearch").value as? String, "咖啡")
            XCTAssertTrue(element("entriesSearchTotal").exists)
            // A completed initial request must not revive focus on the next
            // native sampling turns after Return ends the editing session.
            for _ in 0..<3 { XCTAssertEqual(windowMetrics(in: app)?.focused, "") }
            XCTAssertFalse(app.keyboards.firstMatch.exists)
            tap("entriesSearchCancel")
            XCTAssertTrue(waitForDisappearance(element("entriesSearch")))
            tap("openLedgerSearch")
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
            XCTAssertTrue(waitForKeyboardEditing("entriesSearch", in: app, deadline: deadline), keyboardWaitReport)
            XCTAssertEqual(windowMetrics(in: app)?.focusedAfterAppearance, true)
            XCTAssertEqual(element("entriesSearch").value as? String, "")
            tap("entriesSearchCancel")
            XCTAssertTrue(waitForDisappearance(element("entriesSearch")))
            XCTAssertTrue(waitForKeyboardDismissal(in: app, deadline: deadline))
            XCTAssertEqual(app.state, .runningForeground)
            app.terminate()
        }
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
        // savings47Ledger places the earliest unpaid bill two days after the
        // scripted Nov 20 clock. Dec 5 belongs to the other ledger fixture.
        XCTAssertEqual(element("ledgerGapBill").label, "11月22日 房租")
        XCTAssertEqual(element("ledgerHeroLabel").label, "缺口")
        XCTAssertGreaterThanOrEqual(element("ledgerHeroLabel").frame.minY, element("rootHeaderRegion").frame.maxY + 16)
        XCTAssertGreaterThanOrEqual(element("ledgerGapBill").frame.minY, element("rootHeaderRegion").frame.maxY + 16)
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
        for large in [false, true] {
            launch("v47r-ledger-end", large: large); let key = "ledgerEntry_" + id(479999); reveal(key)
            let row = element(key), pill = element("addEntry")
            XCTAssertTrue(waitForStableFrame(row))
            XCTAssertLessThan(row.frame.maxY, pill.frame.minY)
            XCTAssertTrue(swipeToRevealTrailingActions(row, in: app, deadline: Date().addingTimeInterval(5)), revealFailure)
            let delete = element("deleteLedgerEntry_" + id(479999)), sort = element("sortLedgerEntry_" + id(479999))
            XCTAssertTrue(delete.waitForExistence(timeout: 5)); XCTAssertTrue(delete.isHittable)
            XCTAssertTrue(sort.isHittable)
            XCTAssertLessThan(delete.frame.maxY, pill.frame.minY); XCTAssertLessThan(sort.frame.maxY, pill.frame.minY)
            XCTAssertFalse(element("editEntryAmount").exists)
            app.terminate()
        }
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
    func testSharedPaydaySheetTitlesGrowAndPassNativeAuditsAcrossGalleryModes() {
        for large in [false, true] {
            for (dark, hidden) in [(false, false), (true, false), (false, true), (true, true)] {
                launch("v47-after", large: large, hidden: hidden, dark: dark)
                tap("setupFirstSalary")
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
