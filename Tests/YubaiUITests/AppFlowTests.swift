import XCTest

/// Every launch uses a fresh UUID directory and simulator-only scripted transport.
/// No Keychain configuration or network connection is needed.
final class AppFlowTests: XCTestCase {
    private var currentApp: XCUIApplication?
    private var snapshotNumber = 0

    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws {
        if let app = currentApp, (testRun?.totalFailureCount ?? 0) > 0 {
            snapshot("failure", app)
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "failure-hierarchy"; hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        currentApp = nil
        try super.tearDownWithError()
    }

    private func application(_ fixture: String, keepingUndo: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--test-ledger", UUID().uuidString, "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launchEnvironment["YUBAI_UI_TEST_SCRIPT"] = fixture
        app.launchEnvironment["YUBAI_UI_TEST_CONFIGURED_KEY"] = "1"
        if keepingUndo { app.launchEnvironment["YUBAI_UI_TEST_KEEP_UNDO"] = "1" }
        app.launchEnvironment["DEEPSEEK_API_KEY"] = ""
        currentApp = app; snapshotNumber = 0
        return app
    }

    func testRound46RenewalReceiptChangesFundsAndUndoRestoresTheCard() {
        let app = application("v46-home", keepingUndo: true); app.launch()
        let before = displayedAmount(anyElement("availableFunds", in: app))
        tap(app.buttons["stopRenewal"], in: app)
        XCTAssertTrue(anyElement("butlerReceipt", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS '以后每月省下 25.00'")).firstMatch.exists)
        XCTAssertEqual(displayedAmount(anyElement("availableFunds", in: app)), before + 2500)
        tap(app.buttons["undoButlerReceipt"], in: app)
        XCTAssertTrue(app.buttons["stopRenewal"].waitForExistence(timeout: 5))
        XCTAssertEqual(displayedAmount(anyElement("availableFunds", in: app)), before)
    }

    func testRound46KeepRenewalPersistsAcrossLaunches() {
        let app = application("v46-home"); app.launch()
        tap(app.buttons["keepRenewal"], in: app)
        assertGone(anyElement("renewalCard", in: app))
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["fundsFormula"].waitForExistence(timeout: 5))
        XCTAssertFalse(anyElement("renewalCard", in: app).exists)
        if app.buttons["openLetterInbox"].exists {
            openInbox(in: app)
            for _ in 0..<4 {
                XCTAssertFalse(anyElement("renewalCard", in: app).exists)
                tap(app.buttons["butlerDeckNext"], in: app)
            }
        }
    }

    func testRound46HiddenRenewalStaysActionableAndReceiptStaysHidden() {
        let app = application("v46-home", keepingUndo: true); app.launch()
        tap(app.buttons["toggleAmountVisibility"], in: app)
        let card = anyElement("renewalCard", in: app)
        XCTAssertFalse(card.staticTexts.allElementsBoundByIndex.contains { $0.label.contains("25.00") })
        XCTAssertTrue(app.buttons["stopRenewal"].isEnabled)
        tap(app.buttons["stopRenewal"], in: app)
        let receipt = anyElement("butlerReceipt", in: app)
        XCTAssertTrue(receipt.waitForExistence(timeout: 5))
        XCTAssertFalse(receipt.staticTexts.allElementsBoundByIndex.contains { $0.label.contains("25.00") })
        XCTAssertTrue(app.buttons["undoButlerReceipt"].isEnabled)
    }

    func testRound46QuietHomeHasNoCardOrPlaceholder() {
        let app = application("v46-quiet"); app.launch()
        XCTAssertTrue(anyElement("todayEntries", in: app).waitForExistence(timeout: 5))
        for id in ["renewalCard", "firstUseCard", "pendingImportsCard", "openLetterInbox", "importBusyRow"] {
            XCTAssertFalse(anyElement(id, in: app).exists)
        }
        XCTAssertEqual(displayedAmount(anyElement("availableFunds", in: app)), 156400)
    }

    func testRound46DeckCyclesAndAnswerRemovesOnlyTheTopDecision() {
        let app = application("v46-deck"); app.launch(); openInbox(in: app)
        XCTAssertTrue(anyElement("pendingImportsCard", in: app).waitForExistence(timeout: 5))
        tap(app.buttons["butlerDeckNext"], in: app)
        XCTAssertTrue(app.buttons["billDueNotYet"].waitForExistence(timeout: 5))
        XCTAssertFalse(anyElement("pendingImportsCard", in: app).exists)
        tap(app.buttons["billDueNotYet"], in: app)
        XCTAssertTrue(app.navigationBars["还有 2 件"].waitForExistence(timeout: 5))
        XCTAssertTrue(anyElement("butlerDeckPosition", in: app).exists)
        app.swipeLeft()
        XCTAssertTrue(app.buttons["butlerDeckNext"].exists)
    }

    func testRound46FirstLaunchRecordsIncomeAndExpenseWithoutSetup() {
        let app = application("empty"); app.launch()
        XCTAssertTrue(app.buttons["firstEntry"].waitForExistence(timeout: 5))
        tap(app.buttons["firstEntry"], in: app)
        tap(app.buttons["entryNature_income"], in: app); pressAmount("100", in: app)
        tap(app.buttons["saveQuickEntry"], in: app)
        XCTAssertEqual(displayedAmount(anyElement("availableFunds", in: app)), 10000)
        tap(app.buttons["addEntry"], in: app); pressAmount("25", in: app)
        tap(app.buttons["entryCategory_餐饮"], in: app); tap(app.buttons["saveQuickEntry"], in: app)
        XCTAssertEqual(displayedAmount(anyElement("availableFunds", in: app)), 7500)
        app.terminate(); app.launch()
        XCTAssertEqual(displayedAmount(anyElement("availableFunds", in: app)), 7500)
        XCTAssertFalse(anyElement("firstUseCard", in: app).exists)
    }

    func testRound46SavingsTallyUsesElapsedPeriodsAndPersists() {
        let app = application("v46-saved"); app.launch()
        for _ in 0..<2 {
            tap(app.buttons["tab_saving"], in: app); tap(app.buttons["openButlerSaved"], in: app)
            XCTAssertEqual(displayedAmount(anyElement("butlerSavedTotal", in: app)), 197400)
            XCTAssertTrue(app.staticTexts["降噪耳机"].exists)
            app.terminate(); app.launch()
        }
    }

    func testRound46QuickMenuOffersReceiptAndManagement() {
        let app = application("v46-home"); app.launch()
        let add = app.buttons["addEntry"]; XCTAssertTrue(add.waitForExistence(timeout: 5)); add.press(forDuration: 0.8)
        for id in ["quickRepeat_0", "quickReceipt", "manageQuickRepeats"] { XCTAssertTrue(app.buttons[id].waitForExistence(timeout: 5)) }
        tap(app.buttons["manageQuickRepeats"], in: app)
        XCTAssertTrue(anyElement("frequentEntriesPage", in: app).waitForExistence(timeout: 5))
    }

    func testRound46SpendDerivesTheTotalAndSalaryOpensItsRecordedEntry() {
        let app = application("v46-spend"); app.launch(); tap(app.buttons["fundsFormula"], in: app)
        XCTAssertEqual(displayedAmount(anyElement("formulaRow_income", in: app)), 801000)
        XCTAssertEqual(displayedAmount(anyElement("formulaRow_saving", in: app)), -200000)
        XCTAssertEqual(displayedAmount(anyElement("formulaRow_bills", in: app)), -361000)
        XCTAssertEqual(displayedAmount(anyElement("formulaRow_spent", in: app)), -83600)
        XCTAssertEqual(displayedAmount(anyElement("formulaResult", in: app)), 156400)
        XCTAssertFalse(anyElement("formulaRow_hand", in: app).exists)
        tap(app.buttons["formulaRow_income"], in: app)
        XCTAssertTrue(anyElement("editEntryAmount", in: app).waitForExistence(timeout: 5))
    }

    func testRound46LargestTextKeepsMoneyAndActionsInsideThePage() {
        let app = application("v46-hard")
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        for id in ["availableFunds", "stopRenewal", "keepRenewal"] {
            let target = anyElement(id, in: app); scrollToVisible(target, in: app)
            XCTAssertGreaterThanOrEqual(target.frame.minX, app.frame.minX)
            XCTAssertLessThanOrEqual(target.frame.maxX, app.frame.maxX)
            XCTAssertFalse(target.label.contains("…"))
        }
        tap(app.buttons["fundsFormula"], in: app)
        XCTAssertTrue(app.buttons["ledgerBack"].waitForExistence(timeout: 5) || app.navigationBars.buttons.firstMatch.exists)
        dragBack(app, to: 0.95)
        XCTAssertTrue(app.buttons["addEntry"].waitForExistence(timeout: 5))
    }
    func testSalaryConfirmationFromLetterAndUndoRestoresCard() {
        let app = application("salary", keepingUndo: true); app.launch()
        openInbox(in: app)
        showDeckAction("confirmSalary", in: app)
        tap(app.buttons["confirmSalary"], in: app)
        assertGone(app.buttons["confirmSalary"])
        tapUndo(messagePrefix: "工资已加到会回来的账单", exact: true, in: app)
        showDeckAction("confirmSalary", in: app)
        XCTAssertTrue(app.buttons["confirmSalary"].waitForExistence(timeout: 5))
    }

    func testConfirmedSalaryAppearsInFixedFlowsLaterGroup() {
        let app = application("salary"); app.launch(); openInbox(in: app)
        showDeckAction("confirmSalary", in: app)
        tap(app.buttons["confirmSalary"], in: app); assertGone(app.buttons["confirmSalary"])
        openFixedBills(app)
        let edit = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'editFixedFlow_' AND label == '改工资' ")).firstMatch
        scrollToVisible(edit, in: app, scroll: app.scrollViews["fixedFlowsScroll"])
        XCTAssertTrue(app.staticTexts["工资"].firstMatch.exists)
        tap(edit, in: app)
        XCTAssertTrue(app.buttons["fixedFlowSchedule"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["fixedFlowTitle"].value as? String, "工资")
        XCTAssertEqual(app.buttons["fixedFlowAmount"].value as? String, "8000")
        XCTAssertFalse(app.buttons["saveManualSheet"].isEnabled)
        tap(app.buttons["cancelManualSheet"], in: app)
        assertGone(app.buttons["fixedFlowSchedule"])
        XCTAssertTrue(app.navigationBars["会回来的账单"].exists)
        snapshot("salary-fixed-flows", app)
    }


    func testDeckShowsOneCardAndCyclesToSalaryAndImports() {
        let app = application("salary"); app.launch(); openInbox(in: app)
        XCTAssertTrue(anyElement("letterInbox", in: app).waitForExistence(timeout: 5))
        for _ in 0..<8 {
            if app.buttons["confirmSalary"].exists { break }
            tap(app.buttons["butlerDeckNext"], in: app)
        }
        XCTAssertTrue(app.buttons["confirmSalary"].exists)
        XCTAssertFalse(anyElement("pendingImportsCard", in: app).exists)
        for _ in 0..<8 {
            tap(app.buttons["butlerDeckNext"], in: app)
            if app.buttons["classifyImportsManually"].exists { break }
        }
        tap(app.buttons["classifyImportsManually"], in: app)
        XCTAssertTrue(anyElement("letterTriage", in: app).waitForExistence(timeout: 5))
    }

    func testFallbackGroupsByPartyAppliesCategoryAndUpdatesRemainingCount() {
        let app = application("v46-sort")
        app.launchEnvironment["YUBAI_UI_ORGANIZATION_SCENARIO"] = "by-party"
        app.launch(); openInbox(in: app, required: false)

        XCTAssertTrue(app.buttons["groupUnsortedByParty"].waitForExistence(timeout: 15))
        tap(app.buttons["groupUnsortedByParty"], in: app)
        let count = app.staticTexts["unsortedEntryCount"]
        XCTAssertTrue(count.waitForExistence(timeout: 5)); XCTAssertEqual(count.label, "9")
        let firstGroup = app.buttons["unsortedGroup_out:合成对方甲"]
        let secondGroup = app.buttons["unsortedGroup_out:合成对方乙"]
        XCTAssertTrue(firstGroup.waitForExistence(timeout: 5)); XCTAssertTrue(secondGroup.exists)
        tap(firstGroup, in: app)
        let apply = app.buttons["applyUnsortedGroup"]
        XCTAssertTrue(apply.waitForExistence(timeout: 5)); XCTAssertFalse(apply.isEnabled)
        XCTAssertEqual(apply.label, "选一个分类")
        XCTAssertTrue(app.buttons["unsortedCategory_其他支出"].exists)
        tap(app.buttons["unsortedCategory_餐饮"], in: app)
        tap(app.buttons["unsortedMainOnly_餐饮"], in: app)
        XCTAssertTrue(apply.isEnabled); XCTAssertEqual(apply.label, "6 笔记为 餐饮")
        tap(app.buttons["unsortedNature_investBuy"], in: app)
        XCTAssertTrue(apply.isEnabled); XCTAssertEqual(apply.label, "6 笔记为 买基金")
        XCTAssertFalse(app.buttons["unsortedCategory_餐饮"].isSelected)
        tap(app.buttons["unsortedCategory_餐饮"], in: app)
        tap(app.buttons["unsortedMainOnly_餐饮"], in: app)
        XCTAssertFalse(app.buttons["unsortedNature_investBuy"].isSelected)
        XCTAssertEqual(apply.label, "6 笔记为 餐饮")
        tap(apply, in: app)
        let reduced = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == '3'"), object: count)
        XCTAssertEqual(XCTWaiter.wait(for: [reduced], timeout: 5), .completed)
        XCTAssertFalse(firstGroup.exists); XCTAssertTrue(secondGroup.exists)
        tap(app.navigationBars.buttons.firstMatch, in: app)
        XCTAssertTrue(app.staticTexts["unsortedQuestionTitle"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["unsortedQuestionTitle"].label.hasPrefix("3 笔还没分类"))
        app.terminate(); app.launch(); openInbox(in: app, required: false)
        XCTAssertTrue(app.staticTexts["unsortedQuestionTitle"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["unsortedQuestionTitle"].label.hasPrefix("3 笔还没分类"))
    }

    func testTwoStepCategoryPickerExpandsCollapsesAndAppliesSmallItem() {
        let app = application("v46-sort", keepingUndo: true)
        app.launchEnvironment["YUBAI_UI_ORGANIZATION_SCENARIO"] = "by-party"
        app.launch(); openInbox(in: app, required: false)
        tap(app.buttons["groupUnsortedByParty"], in: app); tap(app.buttons["unsortedGroup_out:合成对方甲"], in: app)
        let category = app.buttons["unsortedCategory_美容个护"], sub = app.buttons["unsortedSubcategory_美容个护/理发"]
        tap(category, in: app); XCTAssertTrue(sub.waitForExistence(timeout: 5))
        tap(category, in: app); assertGone(sub)
        tap(category, in: app); tap(sub, in: app)
        XCTAssertEqual(app.buttons["applyUnsortedGroup"].label, "6 笔记为 美容个护 · 理发")
        tap(app.buttons["applyUnsortedGroup"], in: app)
        XCTAssertTrue(app.staticTexts["unsortedEntryCount"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["unsortedEntryCount"].label, "3")
        tap(app.buttons["quickSortUndo"], in: app)
        XCTAssertEqual(app.staticTexts["unsortedEntryCount"].label, "9")
    }

    func testCategoryAdditionDefaultsToExpandedMainAndAppliesGroup() {
        let app = application("v46-sort", keepingUndo: true)
        app.launchEnvironment["YUBAI_UI_ORGANIZATION_SCENARIO"] = "by-party"
        app.launch(); openInbox(in: app, required: false)
        tap(app.buttons["groupUnsortedByParty"], in: app); tap(app.buttons["unsortedGroup_out:合成对方甲"], in: app)
        tap(app.buttons["unsortedCategory_美容个护"], in: app); tap(app.buttons["unsortedAdd"], in: app)
        XCTAssertTrue(app.buttons["categoryAdditionParent_美容个护"].isSelected)
        let field = app.textFields["categoryAdditionName"]
        tap(field, in: app); field.typeText("合成护理\n")
        let save = app.buttons["categoryAdditionSave"]
        XCTAssertEqual(save.label, "加上"); tap(save, in: app)
        XCTAssertTrue(app.staticTexts["unsortedEntryCount"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["unsortedEntryCount"].label, "3")
        tap(app.buttons["quickSortUndo"], in: app)
        XCTAssertEqual(app.staticTexts["unsortedEntryCount"].label, "9")
    }

    func testUnsortedMultiSelectAppliesAllGroupsWithOneUndo() {
        let app = application("v46-sort", keepingUndo: true)
        app.launchEnvironment["YUBAI_UI_ORGANIZATION_SCENARIO"] = "by-party"
        app.launch(); openInbox(in: app, required: false)

        XCTAssertTrue(app.buttons["groupUnsortedByParty"].waitForExistence(timeout: 15))
        tap(app.buttons["groupUnsortedByParty"], in: app)
        let count = app.staticTexts["unsortedEntryCount"]
        XCTAssertTrue(count.waitForExistence(timeout: 5)); XCTAssertEqual(count.label, "9")
        tap(app.buttons["unsortedSelect"], in: app)
        let apply = app.buttons["unsortedApplySelected"]
        XCTAssertTrue(apply.exists); XCTAssertFalse(apply.isEnabled)
        let first = app.buttons["unsortedGroup_out:合成对方甲"]
        let second = app.buttons["unsortedGroup_out:合成对方乙"]
        tap(first, in: app); tap(second, in: app)
        XCTAssertTrue(first.isSelected); XCTAssertTrue(second.isSelected)
        XCTAssertEqual(app.staticTexts["unsortedSelectionCount"].label, "2 组 · 9 笔")
        tap(apply, in: app)
        XCTAssertTrue(app.staticTexts["9 笔记为"].waitForExistence(timeout: 5))
        tap(app.buttons["unsortedSelectedCategory_餐饮"], in: app)
        tap(app.buttons["unsortedSelectedMainOnly_餐饮"], in: app)
        XCTAssertTrue(app.buttons["fundsFormula"].waitForExistence(timeout: 5))
        XCTAssertFalse(count.exists); XCTAssertFalse(apply.exists)
        XCTAssertFalse(app.staticTexts["unsortedQuestionTitle"].exists)
        XCTAssertEqual(app.staticTexts["unsortedUndoMessage"].label, "2 组 · 9 笔记为餐饮")
        XCTAssertFalse(app.staticTexts["toastMessage"].exists)
        tap(app.buttons["quickSortUndo"], in: app)
        XCTAssertTrue(app.staticTexts["unsortedQuestionTitle"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["unsortedQuestionTitle"].label.hasPrefix("9 笔还没分类"))
        tap(app.buttons["groupUnsortedByParty"], in: app)
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == '9'"), object: count)], timeout: 5), .completed)
        XCTAssertTrue(first.exists); XCTAssertTrue(second.exists)
    }

    func testUnsortedManyGroupsBatchApplyReturnsToVisibleHeaderAndUndoRestores() {
        let app = application("v46-sort", keepingUndo: true)
        app.launchEnvironment["YUBAI_UI_ORGANIZATION_SCENARIO"] = "by-party-many"
        app.launch(); openInbox(in: app, required: false)

        XCTAssertTrue(app.buttons["groupUnsortedByParty"].waitForExistence(timeout: 15))
        tap(app.buttons["groupUnsortedByParty"], in: app)
        let scroll = app.scrollViews["unsortedGroupsScroll"]
        let count = app.staticTexts["unsortedEntryCount"]
        XCTAssertTrue(count.waitForExistence(timeout: 5)); XCTAssertEqual(count.label, "75")
        tap(app.buttons["unsortedSelect"], in: app)
        for index in 0..<61 {
            let group = app.buttons[String(format: "unsortedGroup_out:合成对方%02d", index)]
            tap(group, in: app, scroll: scroll)
            XCTAssertTrue(group.isSelected)
        }
        XCTAssertFalse(count.isHittable, "The batch must start with the viewport far below the header")
        XCTAssertEqual(app.staticTexts["unsortedSelectionCount"].label, "61 组 · 72 笔")
        tap(app.buttons["unsortedApplySelected"], in: app)
        tap(app.buttons["unsortedSelectedCategory_其他支出"], in: app)

        // Do not scroll to these assertions: an offscreen AX node would miss the bug.
        assertVisibleWithoutScrolling(count, label: "3", in: app, scroll: scroll)
        assertVisibleWithoutScrolling(app.textFields["unsortedPartySearch"], in: app, scroll: scroll)
        XCTAssertEqual(app.buttons["unsortedSelect"].label, "选择")
        XCTAssertEqual(app.staticTexts["unsortedUndoMessage"].label, "61 组 · 72 笔记为其他支出")
        tap(app.buttons["quickSortUndo"], in: app)
        assertVisibleWithoutScrolling(count, label: "75", in: app, scroll: scroll)
        assertVisibleWithoutScrolling(app.textFields["unsortedPartySearch"], in: app, scroll: scroll)
        XCTAssertTrue(app.buttons["unsortedGroup_out:合成对方00"].exists)
        XCTAssertFalse(app.buttons["unsortedApplySelected"].exists)
    }

    func testUnsortedLongGroupPartialApplyAndUndoReturnToTop() {
        let app = application("v46-sort", keepingUndo: true)
        app.launchEnvironment["YUBAI_UI_ORGANIZATION_SCENARIO"] = "by-party-long"
        app.launch(); openInbox(in: app, required: false)

        XCTAssertTrue(app.buttons["groupUnsortedByParty"].waitForExistence(timeout: 15))
        tap(app.buttons["groupUnsortedByParty"], in: app)
        tap(app.buttons["unsortedGroup_out:合成对方00"], in: app)
        let scroll = app.scrollViews["unsortedGroupScroll"]
        let category = app.buttons["unsortedCategory_其他支出"]
        tap(category, in: app, scroll: scroll)
        let toggles = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'unsortedEntryToggle_'"))
        let firstToggle = toggles.firstMatch
        tap(firstToggle, in: app, scroll: scroll)
        let remainingID = firstToggle.identifier
        // Traverse the real lazy list to its bottom before removing 63 of 64 rows.
        for _ in 0..<18 { scrollVertically(scroll, in: app) }
        XCTAssertFalse(category.isHittable)
        let apply = app.buttons["applyUnsortedGroup"]
        XCTAssertEqual(apply.label, "63 笔记为 其他支出")
        tap(apply, in: app)
        assertVisibleWithoutScrolling(category, in: app, scroll: scroll)
        XCTAssertEqual(apply.label, "1 笔记为 其他支出")
        let remaining = app.buttons[remainingID]
        tapUndo(messagePrefix: "已改好 · 整理", in: app)
        assertVisibleWithoutScrolling(category, in: app, scroll: scroll)
        XCTAssertEqual(apply.label, "64 笔记为 其他支出")
        scrollToVisible(remaining, in: app, scroll: scroll)
        XCTAssertEqual(remaining.value as? String, "已选择")
        // Applying the whole group still returns once to the live list.
        tap(apply, in: app)
        let list = app.scrollViews["unsortedGroupsScroll"]
        assertVisibleWithoutScrolling(app.staticTexts["unsortedEntryCount"], label: "1", in: app, scroll: list)
        tap(app.buttons["unsortedGroup_out:合成对方01"], in: app)
        tap(app.buttons["unsortedCategory_其他支出"], in: app, scroll: scroll)
        tap(apply, in: app)
        XCTAssertTrue(app.buttons["fundsFormula"].waitForExistence(timeout: 5), "Final detail and list must each dismiss once")
    }

    func testFallbackGroupAppliesOnlyCheckedEntriesAndLeavesUncheckedEntryInPartyGroup() {
        let app = application("v46-sort")
        app.launchEnvironment["YUBAI_UI_ORGANIZATION_SCENARIO"] = "by-party"
        app.launch(); openInbox(in: app, required: false)

        XCTAssertTrue(app.buttons["groupUnsortedByParty"].waitForExistence(timeout: 15))
        tap(app.buttons["groupUnsortedByParty"], in: app)
        let count = app.staticTexts["unsortedEntryCount"]
        XCTAssertTrue(count.waitForExistence(timeout: 5)); XCTAssertEqual(count.label, "9")
        tap(app.buttons["unsortedGroup_out:合成对方甲"], in: app)
        tap(app.buttons["unsortedCategory_餐饮"], in: app)
        tap(app.buttons["unsortedMainOnly_餐饮"], in: app)
        let purpose = app.textFields["unsortedPurpose"]
        tap(purpose, in: app); purpose.typeText("合成用途\n")
        let scroll = app.scrollViews["unsortedGroupScroll"]
        let toggle = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'unsortedEntryToggle_' ")).firstMatch
        tap(toggle, in: app, scroll: scroll)
        let toggleID = toggle.identifier
        let entryID = String(toggleID.dropFirst("unsortedEntryToggle_".count))
        XCTAssertEqual(toggle.value as? String, "未选择")
        let entry = app.buttons["unsortedEntry_" + entryID]
        tap(entry, in: app)
        let original = app.otherElements["unsortedEntrySource_" + entryID]
        XCTAssertTrue(original.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.value as? String, "未选择", "Expanding the body must not toggle selection")
        tap(entry, in: app); XCTAssertFalse(original.exists)
        let apply = app.buttons["applyUnsortedGroup"]
        XCTAssertTrue(apply.isEnabled); XCTAssertEqual(apply.label, "5 笔记为 餐饮")
        tap(apply, in: app)
        let remaining = app.buttons[toggleID]
        scrollToVisible(remaining, in: app, scroll: scroll)
        XCTAssertTrue(remaining.waitForExistence(timeout: 5), "Partial application keeps this group open")
        XCTAssertEqual(remaining.value as? String, "已选择", "Remaining rows are selected again")
        XCTAssertEqual(apply.label, "1 笔记为 餐饮")
        tap(remaining, in: app)
        XCTAssertFalse(apply.isEnabled); XCTAssertEqual(apply.label, "选一个分类")
        tap(remaining, in: app)
        tap(app.navigationBars.buttons["按对方分"], in: app)
        XCTAssertTrue(count.waitForExistence(timeout: 5)); XCTAssertEqual(count.label, "4")
        let group = app.buttons["unsortedGroup_out:合成对方甲"]
        XCTAssertTrue(group.exists); XCTAssertTrue(app.buttons["unsortedGroup_out:合成对方乙"].exists)
        tap(group, in: app)
        scrollToVisible(app.buttons[toggleID], in: app, scroll: scroll)
        XCTAssertTrue(app.buttons[toggleID].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons[toggleID].value as? String, "已选择")
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'unsortedEntryToggle_' ")).count, 1)
        tap(app.navigationBars.buttons["按对方分"], in: app)
        tap(app.navigationBars.buttons.firstMatch, in: app)
        XCTAssertTrue(app.staticTexts["unsortedQuestionTitle"].label.hasPrefix("4 笔还没分类"))
        app.terminate(); app.launch(); openInbox(in: app, required: false)
        XCTAssertTrue(app.staticTexts["unsortedQuestionTitle"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["unsortedQuestionTitle"].label.hasPrefix("4 笔还没分类"))
    }

    func testCategoryManagementAddsSmallItemDeletesItAndMergesWithUndo() {
        let app = application("salary"); app.launch()
        openSettings(app); tap(app.buttons["openCategories"], in: app)
        XCTAssertFalse(app.buttons["hiddenCategories"].exists)
        tap(app.buttons["addMainCategory"], in: app)
        let field = app.textFields["newCategoryName"]
        tap(field, in: app); field.typeText("合成大类\n"); tap(app.buttons["saveNewCategory"], in: app)
        XCTAssertTrue(app.textFields["categoryName"].waitForExistence(timeout: 5))
        tap(app.buttons["addSubcategory"], in: app)
        tap(field, in: app); field.typeText("合成小项\n"); tap(app.buttons["saveNewCategory"], in: app)
        let sub = app.buttons["editSubcategory_合成小项"]
        XCTAssertTrue(sub.waitForExistence(timeout: 5)); tap(sub, in: app)
        tap(app.buttons["deleteSubcategory"], in: app); XCTAssertFalse(sub.exists)
        tap(app.buttons["mergeCategory"], in: app)
        tap(app.buttons["mergeInto_餐饮"], in: app)
        XCTAssertEqual(app.buttons["confirmCategoryMerge"].label, "0 笔改成餐饮")
        tap(app.buttons["confirmCategoryMerge"], in: app)
        XCTAssertTrue(app.buttons["undoLastChange"].waitForExistence(timeout: 5))
        tap(app.buttons["undoLastChange"], in: app)
        XCTAssertTrue(app.buttons["manageCategory_合成大类"].exists)
    }


    private func assertImportRequestState(_ card: XCUIElement, requests: Int, entries: Int, classified: Int,
                                          file: StaticString = #filePath, line: UInt = #line) {
        let value = "requests=\(requests);entries=\(entries);classified=\(classified);resent=0"
        let state = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: card)
        XCTAssertEqual(XCTWaiter.wait(for: [state], timeout: 5), .completed, file: file, line: line)
    }


    func testSavingsEditsFromFormulaAndSavingTabWithKeypad() {
        let app = application("v45-home"); app.launch()
        tap(app.buttons["fundsFormula"], in: app)
        tap(anyElement("formulaRow_fixedSavings", in: app), in: app)
        XCTAssertTrue(anyElement("amountSheetAmount", in: app).waitForExistence(timeout: 5))
        pressAmount("5020", in: app)
        XCTAssertTrue(anyElement("formulaEditResult", in: app).exists)
        tap(app.buttons["saveSavingsAmount"], in: app)
        assertGone(app.buttons["saveSavingsAmount"])
        XCTAssertTrue(anyElement("formulaRow_fixedSavings", in: app).label.contains("5,020.00"))
        backToRoot(app)
        tap(app.buttons["tab_saving"], in: app); tap(app.buttons["openSavings"], in: app)
        XCTAssertTrue(anyElement("savingsPage", in: app).waitForExistence(timeout: 5))
        tap(app.buttons["editSavingTarget"], in: app)
        pressAmount("1800", in: app); tap(app.buttons["saveSavingsAmount"], in: app)
        assertGone(app.buttons["saveSavingsAmount"])
        backToRoot(app); tap(app.buttons["tab_now"], in: app); tap(app.buttons["fundsFormula"], in: app)
        XCTAssertTrue(anyElement("formulaRow_saving", in: app).label.contains("1,800.00"))
        snapshot("savings-formula-and-tab", app)
    }

    func testShareSavingsUsesIncomeAndCustomPercentage() {
        let app = application("v45-share"); app.launch()
        tap(app.buttons["tab_saving"], in: app); tap(app.buttons["openSavings"], in: app)
        XCTAssertTrue(app.buttons["savingMode_share"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["savingMode_share"].isSelected)
        tap(app.buttons["三成"], in: app); tap(app.buttons["自定"], in: app)
        pressAmount("25", in: app); tap(app.buttons["saveSavingsAmount"], in: app)
        assertGone(app.buttons["saveSavingsAmount"])
        XCTAssertTrue(app.buttons["自定"].isSelected)
        backToRoot(app); tap(app.buttons["tab_now"], in: app); tap(app.buttons["fundsFormula"], in: app)
        XCTAssertTrue(anyElement("formulaRow_saving", in: app).label.contains("2,100.00"))
        tap(anyElement("formulaRow_saving", in: app), in: app)
        XCTAssertEqual(anyElement("amountSheetAmount", in: app).value as? String, "25%")
    }

    func testLargeEntryCanBecomeWishWithoutAddingLedgerEntryAndCanUndo() {
        let app = application("v45-home", keepingUndo: true); app.launch()
        let before = app.buttons["fundsFormula"].label
        tap(app.buttons["tab_ledger"], in: app)
        let rows = ledgerRows(app)
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5)); let count = rows.count
        tap(addEntryTab(app), in: app); pressAmount("1500", in: app)
        let field = app.textFields["entryPurpose"]
        tap(field, in: app); field.typeText("合成耳机\n")
        tap(app.buttons["saveEntryWish"], in: app)
        assertGone(app.buttons["saveQuickEntry"]); XCTAssertEqual(rows.count, count)
        tap(app.buttons["tab_now"], in: app); XCTAssertEqual(app.buttons["fundsFormula"].label, before)
        tap(app.buttons["tab_saving"], in: app); tap(app.buttons["openWishlist"], in: app)
        XCTAssertTrue(app.staticTexts["合成耳机"].waitForExistence(timeout: 5))
        tapUndo(messagePrefix: "已放进心愿单", in: app)
        assertGone(app.staticTexts["合成耳机"])
        snapshot("big-entry-wish-undone", app)
    }

    private func snapshot(_ name: String, _ app: XCUIApplication) {
        snapshotNumber += 1
        let test = app.launchEnvironment["YUBAI_UI_TEST_SCRIPT"] ?? "app-flow"
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "\(test)-\(String(format: "%02d", snapshotNumber))-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
    private func rootPage(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier.replacingOccurrences(of: "tab_", with: "rootPage_")).firstMatch
    }
    private func visibleFrame(_ element: XCUIElement, in app: XCUIApplication) -> CGRect {
        var frame = element.frame.intersection(app.windows.firstMatch.frame).intersection(app.frame)
        for tab in ["tab_now", "tab_saving", "tab_ledger", "tab_yubai"] where app.buttons[tab].exists && app.buttons[tab].isSelected {
            let page = rootPage(tab, in: app)
            if page.exists { frame = frame.intersection(page.frame) }
        }
        return frame
    }
    private func point(_ element: XCUIElement, x: CGFloat, y: CGFloat = 0.5, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) -> XCUICoordinate {
        let frame = visibleFrame(element, in: app).insetBy(dx: 8, dy: 2)
        XCTAssertFalse(frame.isNull || frame.isEmpty, file: file, line: line)
        return app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: frame.minX + frame.width * x - app.frame.minX, dy: frame.minY + frame.height * y - app.frame.minY))
    }
    private func scrollVertically(_ scroll: XCUIElement, up: Bool = true, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(scroll.exists && scroll.isHittable, file: file, line: line)
        var frame = visibleFrame(scroll, in: app)
        let navigation = app.otherElements["mainNavigation"], keyboard = app.keyboards.firstMatch
        if navigation.exists && navigation.isHittable { frame.size.height = min(frame.maxY, navigation.frame.minY) - frame.minY }
        if keyboard.exists { frame.size.height = min(frame.maxY, keyboard.frame.minY) - frame.minY }
        XCTAssertGreaterThan(frame.height, 40, file: file, line: line)
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let start = origin.withOffset(CGVector(dx: frame.midX - app.frame.minX, dy: frame.minY + frame.height * (up ? 0.8 : 0.2) - app.frame.minY))
        let end = origin.withOffset(CGVector(dx: frame.midX - app.frame.minX, dy: frame.minY + frame.height * (up ? 0.2 : 0.8) - app.frame.minY))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
    }
    private func tap(_ element: XCUIElement, in app: XCUIApplication, scroll: XCUIElement? = nil, file: StaticString = #filePath, line: UInt = #line) {
        scrollToVisible(element, in: app, scroll: scroll, file: file, line: line)
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in element.exists && element.isEnabled && element.isHittable }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed, file: file, line: line)
        let identifier = element.identifier
        element.tap()
        if ["tab_now", "tab_saving", "tab_ledger", "tab_yubai"].contains(identifier) { assertSelectedTab(identifier, in: app, file: file, line: line) }
    }
    private func scrollToVisible(_ element: XCUIElement, in app: XCUIApplication, scroll: XCUIElement? = nil, file: StaticString = #filePath, line: UInt = #line) {
        // Only the containing vertical scroller may move; alerts, undo and navigation never scroll.
        var container = scroll
        if container == nil && element.waitForExistence(timeout: 5) && !element.isHittable && app.alerts.count == 0 {
            let identifier = element.identifier.isEmpty ? element.label : element.identifier
            if !element.identifier.hasPrefix("tab_") && !["undoLastChange", "addEntry", "closeSheet", "cancelManualSheet"].contains(element.identifier) {
                container = app.scrollViews.allElementsBoundByIndex.last { candidate in
                    candidate.isHittable && candidate.frame.height > 120 && candidate.descendants(matching: element.elementType).matching(identifier: identifier).count > 0
                }
            }
        }
        if let container {
            for _ in 0..<8 {
                var viewport = visibleFrame(container, in: app)
                let navigation = app.otherElements["mainNavigation"], keyboard = app.keyboards.firstMatch
                if navigation.exists && navigation.isHittable { viewport.size.height = min(viewport.maxY, navigation.frame.minY) - viewport.minY }
                if keyboard.exists { viewport.size.height = min(viewport.maxY, keyboard.frame.minY) - viewport.minY }
                // A visible but inaccessible control is an AX failure, not a reason to scroll past it.
                if element.exists && viewport.contains(element.frame) { break }
                let above = element.exists && !element.frame.isEmpty && element.frame.maxY <= viewport.minY
                scrollVertically(container, up: !above, in: app, file: file, line: line)
            }
        }
        let visible = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in element.exists && element.isHittable }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [visible], timeout: 5), .completed, file: file, line: line)
    }
    private func swipeRow(_ element: XCUIElement, left: Bool = true, file: StaticString = #filePath, line: UInt = #line) {
        guard let app = currentApp else { XCTFail("No launched app", file: file, line: line); return }
        XCTAssertTrue(element.isHittable, file: file, line: line)
        let start = point(element, x: left ? 0.85 : 0.15, in: app, file: file, line: line)
        let native = element.identifier.hasPrefix("ledgerEntry_") || element.identifier.hasPrefix("fixedFlow_")
        let end = point(element, x: native ? 0.5 : left ? 0.15 : 0.85, in: app, file: file, line: line)
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
    }
    private func assertState(_ element: XCUIElement, value: String, enabled: Bool, file: StaticString = #filePath, line: UInt = #line) {
        let state = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@ AND enabled == %@", value, NSNumber(value: enabled)), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [state], timeout: 5), .completed, file: file, line: line)
    }
    private func assertNotHittable(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let hidden = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !element.exists || !element.isHittable }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [hidden], timeout: 5), .completed, file: file, line: line)
    }
    private func assertVisibleWithoutScrolling(_ element: XCUIElement, label: String? = nil, in app: XCUIApplication, scroll: XCUIElement,
                                               file: StaticString = #filePath, line: UInt = #line) {
        let visible = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            element.exists && element.isHittable && self.visibleFrame(scroll, in: app).contains(element.frame) &&
                (label == nil || element.label == label)
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [visible], timeout: 5), .completed, "Content must be visible without a recovery swipe", file: file, line: line)
    }
    private func assertGone(_ element: XCUIElement, timeout: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line) {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: timeout), .completed, file: file, line: line)
    }
    private func assertRevealState(_ row: XCUIElement, revealed: Bool, action: XCUIElement, closedFrame: CGRect? = nil, file: StaticString = #filePath, line: UInt = #line) {
        var previous = CGRect.null, stableSince = Date()
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard row.exists, revealed ? (action.exists && action.isHittable) : !action.exists else { stableSince = Date(); return false }
            let frame = row.frame
            if frame != previous { previous = frame; stableSince = Date(); return false }
            return Date().timeIntervalSince(stableSince) >= 0.35
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 5), .completed, file: file, line: line)
        if revealed {
            XCTAssertTrue(action.waitForExistence(timeout: 5) && action.isHittable, file: file, line: line)
            if let app = currentApp { XCTAssertTrue(app.windows.firstMatch.frame.contains(action.frame), file: file, line: line) }
        } else {
            if let closedFrame {
                XCTAssertEqual(row.frame.minX, closedFrame.minX, accuracy: 1, file: file, line: line)
                XCTAssertEqual(row.frame.minY, closedFrame.minY, accuracy: 1, file: file, line: line)
                XCTAssertEqual(row.frame.width, closedFrame.width, accuracy: 1, file: file, line: line)
                XCTAssertEqual(row.frame.height, closedFrame.height, accuracy: 1, file: file, line: line)
            }
            // A covered action is still a VoiceOver defect if it remains in AX at all.
            assertGone(action, file: file, line: line)
        }
    }
    private func assertSelectedTab(_ identifier: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let page = rootPage(identifier, in: app), anchor = page.staticTexts["rootHeaderTitle"]
        let navigation = app.otherElements["mainNavigation"]
        let destination = identifier.replacingOccurrences(of: "tab_", with: "")
        var previous = CGRect.null, stableSince = Date()
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard app.buttons[identifier].exists && app.buttons[identifier].isSelected && page.exists && anchor.exists else { stableSince = Date(); return false }
            let state = navigation.value as? String ?? ""
            let viewport = app.windows.firstMatch.frame.intersection(app.frame), frame = anchor.frame
            guard state == "destination=\(destination)",
                  anchor.isHittable && viewport.contains(frame),
                  abs(page.frame.minX - viewport.minX) <= 1 && abs(page.frame.maxX - viewport.maxX) <= 1 else { stableSince = Date(); return false }
            if frame != previous { previous = frame; stableSince = Date(); return false }
            return Date().timeIntervalSince(stableSince) >= 0.35
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 10), .completed,
                       "Tab \(identifier): \(String(describing: navigation.value)); page=\(page.frame); anchor=\(anchor.frame)", file: file, line: line)
    }
    private func assertCurrentTab(_ identifier: String, content: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        assertSelectedTab(identifier, in: app, file: file, line: line)
        let element = rootPage(identifier, in: app).descendants(matching: .any).matching(identifier: content).firstMatch
        let visible = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in element.exists && element.isHittable }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [visible], timeout: 5), .completed, file: file, line: line)
        XCTAssertGreaterThanOrEqual(element.frame.minX, app.frame.minX, file: file, line: line)
        XCTAssertLessThanOrEqual(element.frame.maxX, app.frame.maxX, file: file, line: line)
        for other in ["tab_now", "tab_saving", "tab_ledger", "tab_yubai"] where other != identifier {
            XCTAssertFalse(app.buttons[other].isSelected, file: file, line: line)
        }
    }

    /// The ledger home's 收入/支出 filters stay in the tree under a sheet; match the sheet's direction control.
    private func natureButton(_ title: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == %@ AND NOT (identifier BEGINSWITH %@)", title, "entriesFilter_")).firstMatch
    }
    private func addEntryTab(_ app: XCUIApplication) -> XCUIElement {
        app.buttons["addEntry"]
    }
    /// v45: 设置不再是标签页，从任一根页右上角的 `openSettings` 进入（推入页，底栏隐藏）。
    private func openSettings(_ app: XCUIApplication) {
        tap(app.buttons["openSettings"], in: app)
    }
    /// v45: 洞察并进账本页的「去向」。
    private func openWhere(_ app: XCUIApplication) {
        tap(app.buttons["tab_ledger"], in: app)
        tap(app.buttons["ledgerMode_where"], in: app)
    }
    private func anyElement(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
    private func ledgerRows(_ app: XCUIApplication) -> XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'ledgerEntry_' "))
    }
    private func pressAmount(_ text: String, in app: XCUIApplication) {
        for character in text { tap(app.buttons["keypad_" + String(character)], in: app) }
    }
    private func replaceText(_ text: String, in field: XCUIElement, app: XCUIApplication, submit: Bool = false) {
        scrollToVisible(field, in: app)
        let old = field.value as? String ?? ""
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.5)).tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count) + text + (submit ? "\n" : ""))
    }
    private func displayedAmount(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) -> Int64 {
        XCTAssertTrue(element.waitForExistence(timeout: 5), file: file, line: line)
        let text = element.label.replacingOccurrences(of: "−", with: "-")
        let pattern = #"-?[0-9]+(?:,[0-9]{3})*\.[0-9]{2}"#
        guard let range = text.range(of: pattern, options: .regularExpression),
              let value = Double(text[range].replacingOccurrences(of: ",", with: "")) else {
            XCTFail("Missing amount: \(text)", file: file, line: line); return 0
        }
        return Int64((value * 100).rounded())
    }
    private func assertSearchCount(_ count: Int, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let summary = app.staticTexts["activeEntryCount"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "\(count) 笔"), object: summary)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed, file: file, line: line)
    }
    private func backToRoot(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        for _ in 0..<8 {
            if app.otherElements["mainNavigation"].exists && app.otherElements["mainNavigation"].isHittable { break }
            let custom = app.buttons["ledgerBack"]
            if custom.exists && custom.isHittable { tap(custom, in: app, file: file, line: line) }
            else { tap(app.navigationBars.buttons.firstMatch, in: app, file: file, line: line) }
        }
        XCTAssertTrue(app.otherElements["mainNavigation"].waitForExistence(timeout: 5), file: file, line: line)
    }
    /// v45 的问答从余白页输入后推入；测试回复由 UITestTransport 提供。
    private func ask(_ question: String, in app: XCUIApplication) {
        tap(app.buttons["tab_yubai"], in: app)
        let field = app.textFields["askYubai"]
        tap(field, in: app); field.typeText(question)
        tap(app.buttons["sendAskHome"], in: app)
        XCTAssertTrue(anyElement("askInput", in: app).waitForExistence(timeout: 5))
    }
    /// v45: 欢迎页的金额是自带键盘上的一个显示，不再是文本框。
    private func balanceValue(_ app: XCUIApplication) -> String? {
        anyElement("accountBalance", in: app).value as? String
    }
    private func enterBalance(_ text: String, in app: XCUIApplication) {
        for character in text { tap(app.buttons["keypad_\(character)"], in: app) }
    }

    private func dragBack(_ app: XCUIApplication, to progress: CGFloat) {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.005, dy: 0.45))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: progress, dy: 0.45)), withVelocity: .slow, thenHoldForDuration: 0.5)
    }

    private func assertPushedPage(_ title: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let bar = app.navigationBars[title]
        XCTAssertTrue(bar.waitForExistence(timeout: 5), file: file, line: line)
        XCTAssertTrue(bar.isHittable, file: file, line: line)
        XCTAssertEqual(bar.frame.minX, app.frame.minX, accuracy: 1, file: file, line: line)
        assertGone(app.otherElements["mainNavigation"], file: file, line: line)
        for identifier in ["tab_now", "tab_saving", "tab_ledger", "tab_yubai", "addEntry"] {
            assertGone(app.buttons[identifier], file: file, line: line)
        }
    }

    private func openInbox(in app: XCUIApplication, required: Bool = true) {
        let chip = app.buttons["openLetterInbox"]
        if required { XCTAssertTrue(chip.waitForExistence(timeout: 10)) }
        else { _ = chip.waitForExistence(timeout: 2) }
        if chip.exists && chip.isHittable { tap(chip, in: app) }
    }

    private func showDeckAction(_ id: String, in app: XCUIApplication) {
        for _ in 0..<12 {
            if app.buttons[id].exists { return }
            guard app.buttons["butlerDeckNext"].exists else { break }
            tap(app.buttons["butlerDeckNext"], in: app)
        }
        XCTAssertTrue(app.buttons[id].waitForExistence(timeout: 5))
    }
    private func homeBillCheck(_ title: String, in app: XCUIApplication) -> XCUIElement {
        let check = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'billCheck_' AND label == %@", "付了 " + title)).firstMatch
        if !check.exists && app.buttons["billDueNotYet"].exists { tap(app.buttons["billDueNotYet"], in: app) }
        XCTAssertTrue(check.waitForExistence(timeout: 5)); return check
    }
    private func openFixedBills(_ app: XCUIApplication) {
        backToRoot(app)
        tap(app.buttons["tab_now"], in: app)
        tap(app.buttons["fundsFormula"], in: app)
        tap(anyElement("formulaRow_bills", in: app), in: app)
        XCTAssertTrue(app.navigationBars["会回来的账单"].waitForExistence(timeout: 5))
    }

    private func openFixedBillStop(_ row: XCUIElement, title: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        scrollToVisible(row, in: app, scroll: app.scrollViews["fixedFlowsScroll"], file: file, line: line)
        let identifier = row.identifier
        XCTAssertTrue(identifier.hasPrefix("fixedFlow_"), file: file, line: line)
        let action = app.buttons["stopFixedFlow_" + identifier.dropFirst("fixedFlow_".count)]
        swipeRow(row, file: file, line: line)
        assertRevealState(row, revealed: true, action: action, file: file, line: line)
        point(action, x: 0.5, in: app, file: file, line: line).tap()
        XCTAssertTrue(app.alerts["停掉「\(title)」？"].waitForExistence(timeout: 5), file: file, line: line)
    }
    private func alertButton(_ identifier: String, in alert: XCUIElement) -> XCUIElement {
        // iOS 26 exports nested copies with the same identifier, label and frame.
        alert.buttons.matching(identifier: identifier).firstMatch
    }
    private func tapAlertButton(_ identifier: String, label: String, in alert: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(alert.waitForExistence(timeout: 5), file: file, line: line)
        let button = alertButton(identifier, in: alert)
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in button.exists && button.isEnabled && button.isHittable }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed, file: file, line: line)
        XCTAssertEqual(button.label, label, file: file, line: line)
        XCTAssertTrue(alert.frame.contains(button.frame), file: file, line: line)
        button.tap()
    }
    private func tapUndo(messagePrefix: String, exact: Bool = false, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let undo = app.buttons["undoLastChange"], message = app.staticTexts["toastMessage"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            undo.exists && undo.isEnabled && undo.isHittable && message.exists && (exact ? message.label == messagePrefix : message.label.hasPrefix(messagePrefix))
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 3), .completed, file: file, line: line)
        undo.tap()
    }
    private func dismissKeyboard(in app: XCUIApplication, scroll: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5), file: file, line: line)
        let origin = app.coordinate(withNormalizedOffset: .zero), frame = scroll.frame.intersection(app.windows.firstMatch.frame)
        let startY = min(keyboard.frame.minY, frame.maxY) - 48
        XCTAssertGreaterThan(startY, frame.minY, file: file, line: line)
        let start = origin.withOffset(CGVector(dx: frame.midX - app.frame.minX, dy: startY - app.frame.minY))
        let end = origin.withOffset(CGVector(dx: frame.midX - app.frame.minX, dy: app.windows.firstMatch.frame.maxY - app.frame.minY - 24))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.3)
        assertGone(keyboard, file: file, line: line)
    }

    private func openPurchaseFixture(_ fixture: String, question: String = "想买双徒步鞋 899，该不该买？") -> XCUIApplication {
        let app = application(fixture); app.launch()
        ask(question, in: app)
        return app
    }

    private func assertPurchaseVerdict(_ label: String, in app: XCUIApplication) {
        let verdict = app.staticTexts["purchaseVerdict"]
        XCTAssertTrue(verdict.waitForExistence(timeout: 10))
        XCTAssertTrue(verdict.label.hasPrefix(label + "，"))
    }

    func testJudgeAskScreenshotFixture() {
        let app = openPurchaseFixture("judge-ask")
        XCTAssertTrue(app.staticTexts["最近三个月徒步过几次？"].waitForExistence(timeout: 10))
        XCTAssertGreaterThanOrEqual(app.staticTexts["最近三个月徒步过几次？"].frame.minY, app.navigationBars.firstMatch.frame.maxY)
        XCTAssertTrue(app.buttons["有双跑鞋"].exists)
        XCTAssertTrue(app.buttons["会，旧鞋磨脚"].exists)
        snapshot("purchase-questions", app)
        tap(app.buttons["还没怎么去"], in: app)
        tap(app.buttons["有双跑鞋"], in: app)
        tap(app.buttons["说不好"], in: app)
        tap(app.buttons["就这样回答"], in: app)
        assertPurchaseVerdict("等等再说", in: app)
    }

    func testJudgeWaitScreenshotFixture() {
        let app = openPurchaseFixture("judge-wait")
        assertPurchaseVerdict("等等再说", in: app)
        XCTAssertTrue(app.buttons["放进心愿单"].exists)
        XCTAssertLessThanOrEqual(app.buttons["放进心愿单"].frame.height, 56)
        snapshot("purchase-wait", app)
    }

    func testJudgeBuyScreenshotFixture() {
        let app = openPurchaseFixture("judge-buy")
        assertPurchaseVerdict("买吧", in: app)
        XCTAssertTrue(app.buttons["买了，记一笔"].exists)
        snapshot("purchase-buy", app)
    }

    func testJudgeSkipScreenshotFixture() {
        let app = openPurchaseFixture("judge-skip", question: "想买个 1,899 的降噪耳机，该不该买？")
        assertPurchaseVerdict("先别买", in: app)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '还能花' AND label CONTAINS '620'")).firstMatch.exists)
        snapshot("purchase-skip", app)
    }

    func testWishlistCoolScreenshotFixture() {
        let app = application("wishlist-cool"); app.launch()
        tap(app.buttons["tab_saving"], in: app)
        tap(app.buttons["openWishlist"], in: app)
        XCTAssertTrue(app.staticTexts["没买，省下的"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["冷静了 7 天"].exists)
        XCTAssertTrue(app.buttons["还想要"].exists)
        XCTAssertTrue(app.staticTexts["冷静中 · 还有 2 天"].exists)
        XCTAssertTrue(app.staticTexts["wishFollowUpAge"].exists)
        XCTAssertEqual(app.staticTexts["wishFollowUpAge"].label, "买了一个月")
        XCTAssertFalse(app.staticTexts["冷静中 · 还有 0 天"].exists)
        snapshot("wishlist-cooldown", app)
        scrollToVisible(app.staticTexts["放了 12 天"], in: app)
        XCTAssertTrue(app.staticTexts["放了 12 天"].exists)
    }

    func testWishlistFollowUpCloseAndAnswersAreUndoable() {
        let app = application("wishlist-cool", keepingUndo: true); app.launch()
        tap(app.buttons["tab_saving"], in: app); tap(app.buttons["openWishlist"], in: app)
        let card = app.descendants(matching: .any).matching(identifier: "butlerCard_followUp").firstMatch
        let age = app.staticTexts["wishFollowUpAge"]
        XCTAssertTrue(age.waitForExistence(timeout: 5))
        tap(card.buttons["dismissLetterCard"], in: app); assertGone(age)
        tapUndo(messagePrefix: "收起了", exact: true, in: app)
        for answer in ["值得", "一般", "有点后悔"] {
            tap(card.buttons[answer], in: app); assertGone(age)
            tapUndo(messagePrefix: "记下了：" + answer, exact: true, in: app)
            XCTAssertTrue(age.waitForExistence(timeout: 5))
        }
    }

    func testLetterSavingScreenshotFixture() {
        let app = application("letter-saving"); app.launch()
        openWhere(app); tap(app.buttons["openWeekly"], in: app)
        XCTAssertTrue(app.staticTexts["letterBody"].waitForExistence(timeout: 5))
        scrollToVisible(anyElement("letterSubscriptions", in: app), in: app)
        for title in ["视频会员", "网盘", "健身 App"] { XCTAssertTrue(app.staticTexts[title].exists) }
        XCTAssertTrue(anyElement("letterSavings", in: app).exists)
        let body = app.staticTexts["letterBody"].label
        XCTAssertTrue(body.contains("还能花")); XCTAssertFalse(body.contains("比上周保持原样"))
        for day in [3, 12, 24] { XCTAssertTrue(app.staticTexts["每月 \(day) 日"].exists) }
        snapshot("weekly-saving-subscriptions", app)
    }

    func testProfileRevisitScreenshotFixture() {
        let app = application("profile-revisit"); app.launch()
        tap(app.buttons["tab_yubai"], in: app); tap(app.buttons["openProfile"], in: app)
        snapshot("profile-progress", app)
        tap(app.buttons["profileChatEntry"], in: app)
        XCTAssertTrue(app.buttons["最近花钱的感觉变了"].waitForExistence(timeout: 10))
        let input = anyElement("profileInput", in: app)
        tap(input, in: app); input.typeText("外卖这周到上限了，但加班那几天真没办法")
        XCTAssertLessThanOrEqual(input.frame.height, 100)
        tap(app.buttons["sendProfile"], in: app)
        let sent = app.staticTexts["profileUserMessage_1"]
        XCTAssertTrue(sent.waitForExistence(timeout: 5))
        XCTAssertEqual(sent.label, "外卖这周到上限了，但加班那几天真没办法")
        XCTAssertTrue(app.staticTexts["外卖这周已经 3 次了，加班的日子想怎么安排？"].waitForExistence(timeout: 10))
        snapshot("profile-revisit-reply", app)
    }

    func testSubcategoryScreenshotFixture() {
        let app = application("subcategory"); app.launch()
        openWhere(app); tap(app.buttons["insightCategory_0"], in: app)
        assertPushedPage("购物 · 本月", in: app)
        XCTAssertTrue(app.staticTexts["其他"].exists)
        snapshot("shopping-subcategories", app)
        tap(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "运动户外")).firstMatch, in: app)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "徒步鞋")).firstMatch.waitForExistence(timeout: 5))
        snapshot("outdoor-records", app)
        backToRoot(app); tap(app.buttons["tab_saving"], in: app); tap(app.buttons["openWishlist"], in: app)
        tap(app.buttons["pastWishes"], in: app); tap(app.buttons["购买记录"], in: app)
        XCTAssertTrue(app.staticTexts["entryDetailTitle"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["entryDetailTitle"].label, "徒步鞋 · 京东")
        XCTAssertTrue(app.buttons["entrySubcategory"].label.contains("运动户外"))
        tap(app.buttons["entrySubcategory"], in: app)
        XCTAssertTrue(app.buttons["运动户外"].waitForExistence(timeout: 5)); XCTAssertTrue(app.buttons["换主项"].exists)
        snapshot("subcategory-picker", app)
    }

    func testAskWithoutKeyDisablesComposerEvenWithScriptedReplies() {
        let app = application("ask")
        app.launchEnvironment["YUBAI_UI_TEST_CONFIGURED_KEY"] = "0"
        app.launch(); ask("咖啡共花了多少钱？", in: app)
        let input = anyElement("askInput", in: app)
        XCTAssertFalse(input.isEnabled)
        for title in ["这周餐饮花了多少？", "想买一双 899 的鞋，该不该买？"] {
            XCTAssertTrue(app.buttons[title].exists); XCTAssertFalse(app.buttons[title].isEnabled)
        }
        XCTAssertFalse(app.staticTexts["askAnswer"].exists)
        tap(app.buttons["configureAskKey"], in: app)
        XCTAssertTrue(app.navigationBars["智能与隐私"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.switches["cloudAIToggle"].value as? String, "1")
    }

    func testBoughtWishShowsStatusAndDateWithoutAskAgain() {
        let app = application("wish-bought"); app.launch()
        tap(app.buttons["tab_saving"], in: app)
        tap(app.buttons["openWishlist"], in: app)
        XCTAssertTrue(app.staticTexts["心愿单还是空的"].exists)
        XCTAssertTrue(app.buttons["该不该买"].exists)
        tap(app.buttons["pastWishes"], in: app)
        XCTAssertTrue(app.navigationBars["过去的心愿"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["已买"].exists)
        let date = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'wishFollowUpDate_' ")).firstMatch
        XCTAssertTrue(date.exists); XCTAssertTrue(date.label.contains("问你用得怎么样"))
        XCTAssertFalse(app.buttons["再问一次"].exists)
        snapshot("wish-bought", app)
    }

    func testFixedBillCheckMarksPaidAndUndoRestoresIt() {
        let app = application("bills", keepingUndo: true); app.launch()
        XCTAssertTrue(app.buttons["fundsFormula"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["fundsFormula"].label.contains("¥700.00"))
        openFixedBills(app)
        let check = app.buttons["付了 房租"]
        tap(check, in: app)
        tapUndo(messagePrefix: "已记下 · 房租 300.00", exact: true, in: app)
        assertState(check, value: "已到期", enabled: true)
        tap(check, in: app)
        assertGone(check); XCTAssertTrue(app.images["已付 房租"].exists)
        snapshot("bill-paid", app)
        backToRoot(app); tap(app.buttons["tab_now"], in: app)
        XCTAssertTrue(app.buttons["fundsFormula"].label.contains("¥700.00"))
        XCTAssertTrue(anyElement("todayEntries", in: app).exists)
    }

    func testUndoReceiptDismissesAfterProductionLifetime() {
        let app = application("bills"); app.launch(); openFixedBills(app)
        XCTAssertNil(app.launchEnvironment["YUBAI_UI_TEST_KEEP_UNDO"])
        let check = app.buttons["付了 房租"], undo = app.buttons["undoLastChange"], message = app.staticTexts["toastMessage"]
        XCTAssertTrue(check.isHittable)
        let started = ProcessInfo.processInfo.systemUptime
        check.tap()
        XCTAssertTrue(undo.waitForExistence(timeout: 2)); XCTAssertTrue(undo.isHittable)
        XCTAssertEqual(message.label, "已记下 · 房租 300.00")
        let early = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !undo.exists }, object: nil)
        early.isInverted = true
        let earlyWindow = max(0.01, 2 - (ProcessInfo.processInfo.systemUptime - started))
        XCTAssertEqual(XCTWaiter.wait(for: [early], timeout: earlyWindow), .completed)
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !undo.exists && !message.exists }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 4), .completed)
        let elapsed = ProcessInfo.processInfo.systemUptime - started
        XCTAssertGreaterThanOrEqual(elapsed, 3.5); XCTAssertLessThan(elapsed, 7)
        XCTAssertTrue(app.images["已付 房租"].exists); XCTAssertFalse(check.exists)
    }

    func testFixedIncomeCheckIncreasesAvailableAndPersists() {
        let app = application("bills"); app.launch()
        XCTAssertTrue(app.buttons["fundsFormula"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["fundsFormula"].label.contains("¥700.00"))
        openFixedBills(app)
        let check = app.buttons["收到了 工资"]
        tap(check, in: app)
        assertGone(check); XCTAssertTrue(app.images["已收到 工资"].exists)
        backToRoot(app); tap(app.buttons["tab_now"], in: app)
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS '¥1,200.00'"), object: app.buttons["fundsFormula"])
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed)
        snapshot("income-received", app)
        app.terminate(); app.launch(); openFixedBills(app)
        XCTAssertFalse(app.buttons["收到了 工资"].exists); XCTAssertTrue(app.images["已收到 工资"].exists)
    }

    func testFixedBillLongPressChangesAmountBeforeRecording() {
        let app = application("bills-estimated"); app.launch(); openFixedBills(app)
        let check = app.buttons["付了 电费"]
        XCTAssertTrue(check.waitForExistence(timeout: 5)); check.press(forDuration: 0.8)
        tap(app.buttons["改金额再记"], in: app)
        enterAmount("100", identifier: "fixedFlowSettlementAmount", in: app)
        tap(app.buttons["saveManualSheet"], in: app)
        assertGone(check); XCTAssertTrue(app.images["已付 电费"].exists)
        backToRoot(app); tap(app.buttons["tab_now"], in: app)
        XCTAssertTrue(app.buttons["fundsFormula"].label.contains("¥900.00"))
        XCTAssertTrue(anyElement("todayEntries", in: app).exists)
    }

    func testFixedBillSwipeStopsFutureOccurrencesAndKeepsPaidRow() {
        let app = application("bills"); app.launch(); openFixedBills(app)
        let check = app.buttons["收到了 工资"]
        XCTAssertTrue(check.waitForExistence(timeout: 5))
        let planID = String(check.identifier.split(separator: "_")[1])
        tap(check, in: app)
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'fixedFlow_' AND value BEGINSWITH '已收到; '")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5)); openFixedBillStop(row, title: "工资", in: app)
        let confirmation = app.alerts["停掉「工资」？"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        XCTAssertTrue(alertButton("fixedFlowStopCancel", in: confirmation).isHittable)
        XCTAssertTrue(alertButton("fixedFlowStopConfirm", in: confirmation).isHittable)
        XCTAssertFalse(confirmation.staticTexts["只停以后的，付过的记录保留。"].exists)
        XCTAssertFalse(alertButton("fixedFlowStopSkip", in: confirmation).exists)
        tapAlertButton("fixedFlowStopCancel", label: "取消", in: confirmation)
        assertGone(confirmation)
        XCTAssertTrue(row.exists); XCTAssertFalse(app.buttons["resumeFixedFlow_" + planID].exists)
        openFixedBillStop(row, title: "工资", in: app)
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        tapAlertButton("fixedFlowStopConfirm", label: "停掉", in: confirmation)
        XCTAssertFalse(check.exists); XCTAssertFalse(row.exists)
        XCTAssertTrue(app.buttons["resumeFixedFlow_" + planID].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS '那期已记'")).firstMatch.exists)
        XCTAssertFalse(app.buttons["停掉"].exists)
        snapshot("bill-stopped-paid-kept", app)
        app.terminate(); app.launch(); openFixedBills(app)
        XCTAssertFalse(app.buttons["收到了 工资"].exists)
        XCTAssertTrue(app.buttons["resumeFixedFlow_" + planID].exists)
    }

    func testFixedBillStopAndResumeBothSupportUndo() {
        let app = application("bills", keepingUndo: true); app.launch(); openFixedBills(app)
        let check = app.buttons["收到了 工资"]
        XCTAssertTrue(check.waitForExistence(timeout: 5))
        let planID = String(check.identifier.split(separator: "_")[1])
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "fixedFlow_" + planID)).firstMatch
        let restore = app.buttons["resumeFixedFlow_" + planID]
        openFixedBillStop(row, title: "工资", in: app)
        let confirmation = app.alerts["停掉「工资」？"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        XCTAssertTrue(confirmation.staticTexts["停掉「工资」？"].exists)
        tapAlertButton("fixedFlowStopCancel", label: "取消", in: confirmation)
        assertGone(confirmation)
        XCTAssertTrue(check.isEnabled)
        func stop() {
            openFixedBillStop(row, title: "工资", in: app)
            XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
            tapAlertButton("fixedFlowStopConfirm", label: "收到了，记一笔再停", in: confirmation)
        }
        stop()
        tapUndo(messagePrefix: "已停掉", in: app); assertGone(restore)
        XCTAssertTrue(check.isEnabled)
        stop()
        XCTAssertTrue(restore.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(identifier: "已停掉").firstMatch.exists)
        tap(restore, in: app)
        tapUndo(messagePrefix: "已恢复", in: app)
        XCTAssertTrue(restore.waitForExistence(timeout: 5))
        tap(restore, in: app); assertGone(restore)
        XCTAssertFalse(check.exists); XCTAssertTrue(app.images["已收到 工资"].exists)
        tapUndo(messagePrefix: "已恢复", in: app)
        XCTAssertTrue(restore.waitForExistence(timeout: 5))
        snapshot("bill-stopped-restorable", app)
    }

    func testFixedBillGroupedSwipesKeepCardAndContentGeometry() {
        let app = application("bills-overdue"); app.launch(); openFixedBills(app)
        let card = app.descendants(matching: .any).matching(identifier: "fixedFlowExpenseCard").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        let rows = card.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'fixedFlow_' ")).allElementsBoundByIndex
        XCTAssertGreaterThanOrEqual(rows.count, 2)
        for index in [0, rows.count - 1] {
            let row = rows[index]
            scrollToVisible(row, in: app, scroll: app.scrollViews["fixedFlowsScroll"])
            let check = row.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'settleFixedFlow_' ")).firstMatch
            let originalCard = card.frame, originalRow = row.frame, originalCheck = check.frame
            let labels = row.staticTexts.allElementsBoundByIndex.map(\.label)
            swipeRow(row)
            let action = app.buttons[row.identifier.replacingOccurrences(of: "fixedFlow_", with: "stopFixedFlow_")]
            assertRevealState(row, revealed: true, action: action)
            XCTAssertEqual(card.frame.minX, originalCard.minX, accuracy: 1)
            XCTAssertEqual(card.frame.minY, originalCard.minY, accuracy: 1)
            XCTAssertEqual(card.frame.width, originalCard.width, accuracy: 1)
            XCTAssertEqual(card.frame.height, originalCard.height, accuracy: 1)
            XCTAssertEqual(row.frame.width, originalRow.width, accuracy: 1)
            XCTAssertEqual(row.frame.height, originalRow.height, accuracy: 1)
            XCTAssertEqual(check.frame.width, originalCheck.width, accuracy: 1)
            XCTAssertEqual(check.frame.minX, originalCheck.minX - 96, accuracy: 1)
            XCTAssertEqual(action.frame.width, 78, accuracy: 1)
            XCTAssertEqual(action.frame.minX - check.frame.maxX, 12, accuracy: 1)
            XCTAssertTrue(originalCard.contains(action.frame))
            XCTAssertEqual(row.staticTexts.allElementsBoundByIndex.map(\.label).filter { $0 != "停掉" }, labels)
            snapshot("fixed-bill-group-row-\(index)-revealed", app)
            swipeRow(row, left: false)
            assertRevealState(row, revealed: false, action: action, closedFrame: originalRow)
            XCTAssertEqual(check.frame.minX, originalCheck.minX, accuracy: 1)
        }
    }

    func testFundsCalculationShowsFormulaRowsAndEditSheet() {
        let app = application("v45-home"); app.launch()
        let before = displayedAmount(anyElement("availableFunds", in: app))
        tap(app.buttons["fundsFormula"], in: app)
        for identifier in ["formulaRow_income", "formulaRow_hand", "formulaRow_fixedSavings", "formulaRow_saving", "formulaRow_bills", "formulaResult"] {
            scrollToVisible(anyElement(identifier, in: app), in: app)
        }
        XCTAssertTrue(anyElement("formulaRow_hand", in: app).label.contains("手上的钱"))
        tap(anyElement("formulaRow_saving", in: app), in: app)
        XCTAssertTrue(anyElement("amountSheetAmount", in: app).waitForExistence(timeout: 5))
        XCTAssertEqual(anyElement("amountSheetAmount", in: app).value as? String, "2000.00")
        pressAmount("1800", in: app)
        let result = anyElement("formulaEditResult", in: app)
        XCTAssertTrue(result.waitForExistence(timeout: 5)); XCTAssertEqual(displayedAmount(result), before + 20_000)
        tap(app.buttons["saveSavingsAmount"], in: app)
        assertGone(app.buttons["saveSavingsAmount"])
        scrollToVisible(anyElement("formulaResult", in: app), in: app)
        XCTAssertEqual(displayedAmount(anyElement("formulaResult", in: app)), before + 20_000)
        snapshot("formula-edit-saving", app)
    }

    func testFixedBillRowOpensPrefilledEditorRenamesAndSupportsUndo() {
        let app = application("bills", keepingUndo: true); app.launch(); openFixedBills(app)
        let check = app.buttons["付了 房租"]
        XCTAssertTrue(check.waitForExistence(timeout: 5))
        let planID = String(check.identifier.split(separator: "_")[1])
        tap(app.buttons["editFixedFlow_" + planID], in: app)
        let editor = app.scrollViews["fixedFlowEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5)); XCTAssertTrue(app.staticTexts["改账单"].exists)
        XCTAssertFalse(editor.buttons["要付"].exists); XCTAssertFalse(editor.buttons["要收"].exists)
        let name = app.textFields["fixedFlowTitle"], amount = app.buttons["fixedFlowAmount"]
        XCTAssertEqual(name.value as? String, "房租"); XCTAssertEqual(amount.value as? String, "300")
        XCTAssertTrue(app.buttons["fixedFlowCategory"].exists); XCTAssertFalse(app.buttons["saveManualSheet"].isEnabled)
        replaceFixedFlowName("租金已改", in: app)
        tap(app.buttons["saveManualSheet"], in: app)
        assertGone(editor)
        XCTAssertTrue(app.buttons["付了 租金已改"].waitForExistence(timeout: 5)); XCTAssertFalse(check.exists)
        tapUndo(messagePrefix: "已改好 · 修改安排", in: app)
        XCTAssertTrue(check.waitForExistence(timeout: 5)); XCTAssertFalse(app.buttons["付了 租金已改"].exists)
    }

    func testFixedBillEditorStopSkipsPendingAndStoppedRowStillEditsWithoutResuming() {
        let app = application("bills"); app.launch(); openFixedBills(app)
        let check = app.buttons["付了 房租"]
        XCTAssertTrue(check.waitForExistence(timeout: 5))
        let planID = String(check.identifier.split(separator: "_")[1])
        tap(app.buttons["editFixedFlow_" + planID], in: app)
        let editor = app.scrollViews["fixedFlowEditor"], stop = app.buttons["fixedFlowEditStop"]
        tap(stop, in: app, scroll: editor)
        let confirmation = app.alerts["停掉「房租」？"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        XCTAssertEqual(alertButton("fixedFlowStopConfirm", in: confirmation).label, "付了，记一笔再停")
        XCTAssertEqual(alertButton("fixedFlowStopSkip", in: confirmation).label, "没付，这期也不要了")
        tapAlertButton("fixedFlowStopCancel", label: "取消", in: confirmation)
        XCTAssertTrue(editor.exists)
        tap(stop, in: app, scroll: editor)
        tapAlertButton("fixedFlowStopSkip", label: "没付，这期也不要了", in: confirmation)
        assertGone(editor); XCTAssertFalse(check.exists)
        let restore = app.buttons["resumeFixedFlow_" + planID]
        XCTAssertTrue(restore.waitForExistence(timeout: 5))
        tap(app.buttons["editFixedFlow_" + planID], in: app)
        XCTAssertTrue(editor.waitForExistence(timeout: 5)); XCTAssertFalse(stop.exists)
        XCTAssertFalse(app.buttons["saveManualSheet"].isEnabled)
        replaceFixedFlowName("已停租金", in: app)
        tap(app.buttons["saveManualSheet"], in: app)
        assertGone(editor); XCTAssertTrue(restore.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["已停租金"].exists); XCTAssertFalse(app.buttons["付了 已停租金"].exists)
    }

    func testFixedBillEditorStopSettlesAllPendingPeriodsAndSupportsUndo() {
        let app = application("bills-multiple", keepingUndo: true); app.launch(); openFixedBills(app)
        let check = app.buttons.matching(identifier: "付了 每周订阅").firstMatch
        XCTAssertTrue(check.waitForExistence(timeout: 5))
        let planID = String(check.identifier.split(separator: "_")[1])
        tap(app.buttons.matching(identifier: "editFixedFlow_" + planID).firstMatch, in: app)
        let editor = app.scrollViews["fixedFlowEditor"]
        tap(app.buttons["fixedFlowEditStop"], in: app, scroll: editor)
        let confirmation = app.alerts["停掉「每周订阅」？"]
        XCTAssertTrue(confirmation.staticTexts["还有 6 期没记。"].exists)
        tapAlertButton("fixedFlowStopConfirm", label: "付了，记一笔再停", in: confirmation)
        assertGone(editor); XCTAssertTrue(app.buttons["resumeFixedFlow_" + planID].waitForExistence(timeout: 5))
        XCTAssertFalse(check.exists)
        tapUndo(messagePrefix: "已停掉", in: app)
        XCTAssertTrue(check.waitForExistence(timeout: 5))
    }

    func testFixedBillEditorStopWithoutPendingUsesSameSimpleConfirmation() {
        let app = application("bills"); app.launch(); openFixedBills(app)
        let check = app.buttons["收到了 工资"]
        XCTAssertTrue(check.waitForExistence(timeout: 5))
        let planID = String(check.identifier.split(separator: "_")[1])
        tap(check, in: app)
        XCTAssertFalse(app.buttons["fixedFlowSchedule"].exists)
        tap(app.buttons["editFixedFlow_" + planID], in: app)
        let editor = app.scrollViews["fixedFlowEditor"]
        tap(app.buttons["fixedFlowEditStop"], in: app, scroll: editor)
        let confirmation = app.alerts["停掉「工资」？"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5)); XCTAssertFalse(alertButton("fixedFlowStopSkip", in: confirmation).exists)
        tapAlertButton("fixedFlowStopConfirm", label: "停掉", in: confirmation)
        assertGone(editor); XCTAssertTrue(app.buttons["resumeFixedFlow_" + planID].waitForExistence(timeout: 5))
    }

    func testFixedBillRevealedRowTapClosesBeforeEditing() {
        let app = application("bills"); app.launch(); openFixedBills(app)
        let check = app.buttons["付了 房租"]
        XCTAssertTrue(check.waitForExistence(timeout: 5))
        let planID = String(check.identifier.split(separator: "_")[1])
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "fixedFlow_" + planID)).firstMatch
        scrollToVisible(row, in: app, scroll: app.scrollViews["fixedFlowsScroll"])
        let action = app.buttons[row.identifier.replacingOccurrences(of: "fixedFlow_", with: "stopFixedFlow_")]
        swipeRow(row); assertRevealState(row, revealed: true, action: action)
        point(row, x: 0.2, in: app).tap()
        assertRevealState(row, revealed: false, action: action)
        XCTAssertFalse(app.buttons["fixedFlowSchedule"].exists); XCTAssertTrue(check.exists)
        tap(app.buttons["editFixedFlow_" + planID], in: app)
        XCTAssertTrue(app.buttons["fixedFlowSchedule"].waitForExistence(timeout: 5))
    }

    func testFixedBillAddNameAcceptsTypingWithoutOpeningSchedule() {
        let app = application("bills"); app.launch(); openFixedBills(app)
        tap(app.buttons["addFixedFlow"], in: app)
        XCTAssertTrue(app.staticTexts["添加账单"].waitForExistence(timeout: 5))
        let name = app.textFields["fixedFlowTitle"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertEqual(name.label, "名字"); XCTAssertEqual(name.placeholderValue, "名字")
        tap(name, in: app)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        name.typeText("房租")
        XCTAssertEqual(name.value as? String, "房租")
        XCTAssertFalse(app.datePickers.firstMatch.exists); XCTAssertFalse(app.popovers.firstMatch.exists)
    }

    func testFixedBillAddCategoryTracksDirectionAndKeepsExistingDefaults() {
        let app = application("bills"); app.launch(); openFixedBills(app)
        tap(app.buttons["addFixedFlow"], in: app)
        let category = app.buttons["fixedFlowCategory"]
        XCTAssertTrue(category.waitForExistence(timeout: 5)); XCTAssertEqual(category.value as? String, "其他支出")
        tap(category, in: app); tap(app.buttons["会员订阅"], in: app)
        XCTAssertEqual(category.value as? String, "会员订阅")
        tap(app.buttons["要收"], in: app)
        XCTAssertEqual(category.value as? String, "其他收入")
        tap(category, in: app)
        // Fixed-flow categories are Menu items exposed by their titles.
        let salary = app.buttons["工资奖金"]
        XCTAssertTrue(salary.waitForExistence(timeout: 5)); XCTAssertFalse(app.buttons["会员订阅"].exists)
        tap(salary, in: app)
        XCTAssertEqual(category.value as? String, "工资奖金")
        tap(app.buttons["要付"], in: app)
        XCTAssertEqual(category.value as? String, "其他支出")
        tap(app.buttons["cancelManualSheet"], in: app)
    }

    func testDueBillInLetterStillSettles() {
        let app = application("bills"); app.launch(); openInbox(in: app, required: false)
        let card = app.descendants(matching: .any).matching(identifier: "dueBills")
            .containing(NSPredicate(format: "label BEGINSWITH '房租' ")).firstMatch
        let check = card.buttons["billDuePaid"]
        XCTAssertTrue(check.waitForExistence(timeout: 5))
        tap(check, in: app)
        XCTAssertTrue(app.buttons["undoLastChange"].waitForExistence(timeout: 5))
        backToRoot(app); tap(app.buttons["tab_ledger"], in: app)
        XCTAssertTrue(ledgerRows(app).firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(ledgerRows(app).count, 1)
    }

    private func enterAmount(_ text: String, identifier: String, in app: XCUIApplication) {
        tap(app.buttons[identifier], in: app)
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        for key in text { tap(app.buttons["keypad_" + String(key)], in: app) }
        tap(app.buttons["amountKeypadDone"], in: app)
        assertGone(app.buttons["amountKeypadDone"])
    }

    private func replaceFixedFlowName(_ text: String, in app: XCUIApplication) {
        let field = app.textFields["fixedFlowTitle"]
        scrollToVisible(field, in: app)
        let count = (field.value as? String ?? "").count
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.5)).tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: count) + text)
    }

    private func toggleSwitch(_ element: XCUIElement, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let value = (element.value as? String) == "1" ? "0" : "1"
        tap(element, in: app, file: file, line: line)
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: element)
        if XCTWaiter.wait(for: [changed], timeout: 2) != .completed {
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
            let retried = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: element)
            XCTAssertEqual(XCTWaiter.wait(for: [retried], timeout: 2), .completed, file: file, line: line)
        }
        XCTAssertEqual(element.value as? String, value, file: file, line: line)
    }

    func testFixedBillEditorUsesInstallmentsAndAccountGatesAutomaticRecording() {
        let app = application("bills"); app.launch(); openFixedBills(app)
        tap(app.buttons["addFixedFlow"], in: app)
        XCTAssertFalse(app.staticTexts["到什么时候"].exists)
        XCTAssertFalse(app.staticTexts["90 天里会先留出"].exists)
        XCTAssertFalse(app.switches["fixedFlowAutoPay"].isEnabled)
        enterAmount("10", identifier: "fixedFlowAmount", in: app)
        tap(app.textFields["名字"], in: app); app.textFields["名字"].typeText("自动测试")
        tap(app.buttons["fixedFlowSchedule"], in: app)
        let schedule = app.popovers.firstMatch
        XCTAssertTrue(schedule.datePickers.firstMatch.waitForExistence(timeout: 5))
        // The name keyboard can also expose a button labeled 完成.
        tap(schedule.buttons["完成"], in: app)
        assertGone(schedule)
        tap(app.buttons["增加期数"], in: app); tap(app.buttons["增加期数"], in: app)
        tap(app.buttons["账户"], in: app)
        tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH '合成银行卡 · 余额'")).firstMatch, in: app)
        XCTAssertTrue(app.switches["fixedFlowAutoPay"].isEnabled)
        let editor = app.scrollViews["fixedFlowEditor"]
        for _ in 0..<4 {
            let frame = visibleFrame(editor, in: app)
            let trayTop = min(frame.maxY, app.textFields["fixedFlowTitle"].frame.minY)
            if ["fixedFlowAutoPay", "fixedFlowEstimated"].allSatisfy({ app.switches[$0].frame.maxY < trayTop }) { break }
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let start = origin.withOffset(CGVector(dx: frame.midX - app.frame.minX, dy: frame.minY + (trayTop - frame.minY) * 0.85 - app.frame.minY))
            let end = origin.withOffset(CGVector(dx: frame.midX - app.frame.minX, dy: frame.minY + (trayTop - frame.minY) * 0.15 - app.frame.minY))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
        }
        let trayTop = min(visibleFrame(editor, in: app).maxY, app.textFields["fixedFlowTitle"].frame.minY)
        for identifier in ["fixedFlowAutoPay", "fixedFlowEstimated"] {
            XCTAssertLessThan(app.switches[identifier].frame.maxY, trayTop)
        }
        toggleSwitch(app.switches["fixedFlowAutoPay"], in: app); toggleSwitch(app.switches["fixedFlowEstimated"], in: app)
        XCTAssertEqual(app.switches["fixedFlowAutoPay"].value as? String, "1")
        XCTAssertEqual(app.switches["fixedFlowEstimated"].value as? String, "1")
        tap(app.buttons["saveManualSheet"], in: app)
        XCTAssertTrue(app.buttons["付了 自动测试"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS '1/2 期' AND label CONTAINS '自动' AND label CONTAINS '大约'")).firstMatch.exists)
        XCUIDevice.shared.press(.home); app.activate()
        let paid = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true"), object: app.images["已付 自动测试"])
        XCTAssertEqual(XCTWaiter.wait(for: [paid], timeout: 5), .completed)
        XCTAssertFalse(app.staticTexts["自动记下完成"].exists)
    }

    func testOverdueBillsAppearInLetter() {
        let app = application("bills-overdue"); app.launch(); openInbox(in: app, required: false)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "dueBills").firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["askYubai"].isHittable)
    }

    func testManualBillSuggestionRequiresSelectionAndCanBeCancelled() {
        let app = application("bills"); app.launch()
        tap(addEntryTab(app), in: app)
        for digit in ["3", "0", "0"] { tap(app.buttons["keypad_" + digit], in: app) }
        let suggestion = app.buttons["fixedFlowSuggestion"]
        XCTAssertTrue(suggestion.waitForExistence(timeout: 5)); XCTAssertFalse(suggestion.isSelected)
        tap(suggestion, in: app); XCTAssertTrue(suggestion.isSelected)
        tap(suggestion, in: app); XCTAssertFalse(suggestion.isSelected)
        tap(suggestion, in: app)
        tap(app.buttons["keypad_⌫"], in: app)
        assertGone(suggestion)
        tap(app.buttons["keypad_0"], in: app)
        XCTAssertTrue(suggestion.waitForExistence(timeout: 5)); XCTAssertFalse(suggestion.isSelected)
        tap(suggestion, in: app); tap(app.buttons["saveQuickEntry"], in: app)
        openFixedBills(app)
        XCTAssertFalse(app.buttons["付了 房租"].exists); XCTAssertTrue(app.images["已付 房租"].exists)
    }

    func testAutomaticBillsRecordOnceOnLaunchWithoutToast() {
        let app = application("bills-auto"); app.launch()
        XCTAssertTrue(app.buttons["fundsFormula"].waitForExistence(timeout: 5))
        XCTAssertTrue(anyElement("todayEntries", in: app).waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["自动记下完成"].exists)
        openFixedBills(app)
        XCTAssertFalse(app.buttons["付了 房租"].exists); XCTAssertTrue(app.images["已付 房租"].exists)
        backToRoot(app); tap(app.buttons["tab_ledger"], in: app)
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'ledgerEntry_' "))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5)); XCTAssertEqual(rows.count, 1)
        app.terminate(); app.launch()
        tap(app.buttons["tab_ledger"], in: app)
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5)); XCTAssertEqual(rows.count, 1)
        openFixedBills(app)
        XCTAssertEqual(app.images.matching(identifier: "已付 房租").count, 1)
        XCTAssertFalse(app.buttons["付了 房租"].exists)
    }

    func testFixedBillsStateTextAndUpcomingHasOnlyContextAction() {
        let app = application("bills-clarity", keepingUndo: true); app.launch(); openFixedBills(app)
        XCTAssertTrue(app.staticTexts["要付"].exists); XCTAssertTrue(app.staticTexts["要收"].exists)
        let day = Calendar.current.component(.day, from: Date())
        let status = day > 1 ? "1日 · 过了 \(day - 1) 天还没记" : "1日 · 今天到期"
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", status)).firstMatch.exists)
        let overdue = app.descendants(matching: .any).matching(identifier: "fixedFlowOverdue").firstMatch
        XCTAssertEqual(overdue.exists, day > 1)
        if day > 1 {
            XCTAssertTrue(overdue.label.contains("其中")); XCTAssertTrue(overdue.label.contains("已过期"))
            XCTAssertTrue(overdue.label.contains("过期没收到")); XCTAssertTrue(overdue.label.contains("·"))
            tap(app.buttons["付了 房租"], in: app)
            let incomeOnly = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS '过期没收到' AND NOT (label CONTAINS '其中')"), object: overdue)
            XCTAssertEqual(XCTWaiter.wait(for: [incomeOnly], timeout: 5), .completed)
            tap(app.buttons["收到了 工资"], in: app); assertGone(overdue)
        }
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS '已付 · 自动'")).firstMatch.exists)
        XCTAssertFalse(app.buttons["付了 视频会员"].exists)
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'fixedFlow_' AND value BEGINSWITH '还没到; '")).firstMatch
        let month = Calendar.current.dateInterval(of: .month, for: Date())!
        if !Calendar.current.isDate(Date(), inSameDayAs: month.end.addingTimeInterval(-1)) {
            XCTAssertFalse(app.buttons["付了 话费"].exists); XCTAssertTrue(row.exists)
            scrollToVisible(row, in: app, scroll: app.scrollViews["fixedFlowsScroll"])
            row.press(forDuration: 0.8)
            let early = app.buttons["提前标记付了"]
            XCTAssertTrue(early.waitForExistence(timeout: 5)); early.tap()
            // Native menu synchronization must not consume the undo business test's receipt.
            tapUndo(messagePrefix: "已记下 · 话费 ", in: app)
            assertGone(app.images["已付 话费"])
            XCTAssertTrue(row.exists)
            XCTAssertFalse(app.buttons["付了 话费"].exists)
        }
        snapshot("bill-states", app)
    }

    func testFixedIncomeStopSkipCancelPersistenceAndUndo() {
        let app = application("bills", keepingUndo: true); app.launch(); openFixedBills(app)
        let check = app.buttons["收到了 工资"]
        XCTAssertTrue(check.waitForExistence(timeout: 5))
        let planID = String(check.identifier.split(separator: "_")[1])
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "fixedFlow_" + planID)).firstMatch
        let restore = app.buttons["resumeFixedFlow_" + planID]
        openFixedBillStop(row, title: "工资", in: app)
        let confirmation = app.alerts["停掉「工资」？"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5)); XCTAssertEqual(app.popovers.count, 0)
        XCTAssertTrue(confirmation.staticTexts["停掉「工资」？"].exists)
        XCTAssertFalse(confirmation.buttons.matching(NSPredicate(format: "label == %@", "停掉")).firstMatch.exists)
        let confirm = alertButton("fixedFlowStopConfirm", in: confirmation), skip = alertButton("fixedFlowStopSkip", in: confirmation), cancel = alertButton("fixedFlowStopCancel", in: confirmation)
        XCTAssertEqual(confirm.label, "收到了，记一笔再停"); XCTAssertEqual(skip.label, "没收到，这期也不要了")
        for button in [confirm, skip, cancel] {
            XCTAssertTrue(button.isHittable)
            XCTAssertTrue(button.isEnabled)
            XCTAssertTrue(confirmation.frame.contains(button.frame))
        }
        tapAlertButton("fixedFlowStopCancel", label: "取消", in: confirmation)
        assertGone(confirmation); XCTAssertTrue(check.exists); XCTAssertFalse(restore.exists)
        openFixedBillStop(row, title: "工资", in: app)
        tapAlertButton("fixedFlowStopSkip", label: "没收到，这期也不要了", in: confirmation)
        tapUndo(messagePrefix: "已停掉", in: app)
        assertGone(restore); XCTAssertTrue(check.exists)
        openFixedBillStop(row, title: "工资", in: app)
        tapAlertButton("fixedFlowStopSkip", label: "没收到，这期也不要了", in: confirmation)
        XCTAssertTrue(restore.waitForExistence(timeout: 5)); assertGone(row)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS '那期没要'")).firstMatch.exists)
        app.terminate(); app.launch(); openFixedBills(app)
        XCTAssertTrue(restore.waitForExistence(timeout: 5)); XCTAssertFalse(row.exists)
        tap(restore, in: app); XCTAssertFalse(check.exists)
        snapshot("income-skipped-and-resumed", app)
    }

    func testFixedBillStopHandlesEveryUnsettledPeriod() {
        let app = application("bills-multiple", keepingUndo: true); app.launch(); openFixedBills(app)
        let check = app.buttons.matching(identifier: "付了 每周订阅").firstMatch
        XCTAssertTrue(check.waitForExistence(timeout: 5))
        let planID = String(check.identifier.split(separator: "_")[1])
        let rows = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "fixedFlow_" + planID))
        let originalCount = rows.count
        XCTAssertGreaterThan(originalCount, 0)
        openFixedBillStop(rows.firstMatch, title: "每周订阅", in: app)
        let confirmation = app.alerts["停掉「每周订阅」？"]
        XCTAssertTrue(confirmation.staticTexts["还有 6 期没记。"].exists)
        XCTAssertEqual(alertButton("fixedFlowStopSkip", in: confirmation).label, "没付，这期也不要了")
        tapAlertButton("fixedFlowStopConfirm", label: "付了，记一笔再停", in: confirmation)
        tapUndo(messagePrefix: "已停掉", in: app)
        XCTAssertTrue(check.waitForExistence(timeout: 5)); XCTAssertEqual(rows.count, originalCount)
        openFixedBillStop(rows.firstMatch, title: "每周订阅", in: app)
        XCTAssertTrue(confirmation.staticTexts["还有 6 期没记。"].exists)
        tapAlertButton("fixedFlowStopConfirm", label: "付了，记一笔再停", in: confirmation)
        XCTAssertTrue(app.buttons["resumeFixedFlow_" + planID].waitForExistence(timeout: 5))
        XCTAssertEqual(rows.count, 0); XCTAssertFalse(check.exists)
        tapUndo(messagePrefix: "已停掉", in: app)
        XCTAssertTrue(check.waitForExistence(timeout: 5)); XCTAssertEqual(rows.count, originalCount)
        snapshot("multiple-period-stop-undone", app)
    }


    func testStorageEntryAndOverviewOpenFromMe() {
        let app = application("ask"); app.launch()
        openSettings(app)
        let storage = app.buttons["openStorage"]
        for _ in 0..<8 {
            if storage.isHittable { break }
            scrollVertically(app.scrollViews["settingsScroll"], in: app)
        }
        XCTAssertTrue(storage.isHittable)
        XCTAssertFalse(app.otherElements["mainNavigation"].exists)
        tap(app.buttons["openStorage"], in: app)
        XCTAssertTrue(app.navigationBars["存储空间"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "storageHeadline").firstMatch.exists)
        XCTAssertTrue(app.buttons["openStoragePhotos"].exists)
        XCTAssertTrue(app.buttons["openStorageHistory"].exists)
        XCTAssertTrue(app.buttons["openStorageErase"].exists)
        XCTAssertFalse(addEntryTab(app).isHittable)
        snapshot("storage-overview", app)
        tap(app.buttons["openStoragePhotos"], in: app)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "storageOriginalsPreserved").firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["账单原件"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["不删"].exists)
        XCTAssertTrue(app.buttons["半年前"].isSelected)
        snapshot("storage-photos", app)
    }

    func testRootHeadersStayFixedAndAddOnlyBelongsToNow() {
        let app = application("v46-quiet"); app.launch()
        let capsule = anyElement("navigationCapsule", in: app)
        let original = capsule.frame
        for tab in ["tab_now", "tab_saving", "tab_ledger", "tab_yubai"] {
            tap(app.buttons[tab], in: app)
            XCTAssertTrue(rootPage(tab, in: app).staticTexts["rootHeaderTitle"].waitForExistence(timeout: 5))
            XCTAssertEqual(capsule.frame.minX, original.minX, accuracy: 1)
            XCTAssertEqual(capsule.frame.width, original.width, accuracy: 1)
            if tab == "tab_now" { XCTAssertTrue(addEntryTab(app).isHittable) }
            else { XCTAssertFalse(addEntryTab(app).exists) }
        }
    }

    func testEntrySheetWithPurposeSuggestionsKeepsActionsAboveHomeIndicator() {
        let app = application("entries"); app.launch()
        let safeBottom = app.otherElements["mainNavigation"].frame.maxY + 8
        tap(addEntryTab(app), in: app)
        let field = app.textFields["entryPurpose"], save = app.buttons["saveQuickEntry"]
        XCTAssertTrue(field.waitForExistence(timeout: 5)); XCTAssertTrue(save.isHittable)
        XCTAssertLessThan(field.frame.maxY, save.frame.minY)
        XCTAssertLessThanOrEqual(save.frame.maxY, safeBottom)
        let original = save.frame
        app.scrollViews["entryFormScroll"].swipeUp()
        XCTAssertEqual(save.frame.minY, original.minY, accuracy: 1)
        tap(field, in: app); field.typeText("午饭")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(save.exists); XCTAssertTrue(field.isHittable)
        field.typeText("\n"); XCTAssertTrue(save.waitForExistence(timeout: 5))
    }

    func testLedgerAccessibilityXLKeepsRootControlsReachable() {
        let app = application("v45-home")
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"]
        app.launch()
        for identifier in ["fundsFormula", "dailyPace", "openSettings", "addEntry"] {
            scrollToVisible(anyElement(identifier, in: app), in: app)
        }
        tap(app.buttons["tab_ledger"], in: app)
        scrollToVisible(app.textFields["entriesSearch"], in: app)
        tap(app.buttons["tab_yubai"], in: app)
        scrollToVisible(app.textFields["askYubai"], in: app)
        snapshot("roots-accessibility-xl", app)
    }

    func testWhereCategoryOpensItsDetails() {
        let app = application("ask"); app.launch(); openWhere(app)
        let category = app.buttons["insightCategory_0"]
        XCTAssertTrue(category.waitForExistence(timeout: 5))
        scrollVertically(app.scrollViews["insightsScroll"], up: false, in: app)
        tap(category, in: app)
        assertPushedPage("餐饮 · 本月", in: app)
    }

    func testModelMenuSelectsInlineAndKeepsCustomEditor() {
        let app = application("ask"); app.launch()
        openSettings(app)
        tap(app.buttons["openIntelligencePrivacy"], in: app)
        tap(app.buttons["editCloudModel"], in: app)
        XCTAssertTrue(app.buttons["cloudModel_deepseek-flash"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["cloudModel_deepseek-v4-pro"].exists)
        XCTAssertTrue(app.buttons["customCloudModel"].exists)
        XCTAssertFalse(app.textFields["cloudModelName"].exists)
        snapshot("model-menu", app)
        tap(app.buttons["cloudModel_deepseek-v4-pro"], in: app)
        XCTAssertTrue(app.buttons["editCloudModel"].label.contains("deepseek-v4-pro"))
        tap(app.buttons["editCloudModel"], in: app)
        tap(app.buttons["customCloudModel"], in: app)
        XCTAssertTrue(app.textFields["cloudModelName"].waitForExistence(timeout: 5))
    }

    func testRootTabsChangeOnlyByTapAndAddBelongsToNow() {
        let app = application("entries"); app.launch()
        assertSelectedTab("tab_now", in: app)
        rootPage("tab_now", in: app).swipeLeft()
        assertSelectedTab("tab_now", in: app)
        for tab in ["tab_saving", "tab_ledger", "tab_yubai", "tab_now"] {
            tap(app.buttons[tab], in: app)
            rootPage(tab, in: app).swipeRight()
            assertSelectedTab(tab, in: app)
            if tab == "tab_now" { XCTAssertTrue(addEntryTab(app).isHittable) }
            else { XCTAssertFalse(addEntryTab(app).exists) }
            XCTAssertTrue(app.buttons["openSettings"].isHittable)
            XCTAssertTrue(app.buttons["toggleAmountVisibility"].isHittable)
        }
    }

    func testTabBarHasFourTabsAndSeparateAddOnTheRight() {
        let app = application("manual"); app.launch()
        let identifiers = ["tab_now", "tab_saving", "tab_ledger", "tab_yubai", "addEntry"]
        let buttons = app.buttons.matching(NSPredicate(format: "identifier IN %@", identifiers)).allElementsBoundByIndex
        XCTAssertEqual(buttons.count, 5)
        XCTAssertEqual(Set(buttons.map(\.label)), Set(["现在", "存钱", "账本", "余白", "记一笔"]))
        XCTAssertEqual(app.otherElements["mainNavigation"].label, "主导航")
        XCTAssertTrue(app.buttons["tab_now"].isSelected)
        for tab in ["tab_saving", "tab_ledger", "tab_yubai"] { XCTAssertFalse(app.buttons[tab].isSelected) }
        XCTAssertFalse(addEntryTab(app).isSelected)
        XCTAssertLessThan(app.buttons["tab_saving"].frame.midX, addEntryTab(app).frame.midX)
        XCTAssertLessThan(app.buttons["tab_ledger"].frame.midX, app.buttons["tab_yubai"].frame.midX)
        XCTAssertLessThan(app.buttons["tab_yubai"].frame.maxX, addEntryTab(app).frame.minX)
    }

    func testAddEntryOpensFromNowAndSettingsPushesFromEveryRoot() {
        let app = application("manual"); app.launch()
        tap(addEntryTab(app), in: app)
        XCTAssertTrue(app.buttons["saveQuickEntry"].waitForExistence(timeout: 5))
        tap(app.buttons["cancelManualSheet"], in: app)
        for tab in ["tab_now", "tab_saving", "tab_ledger", "tab_yubai"] {
            tap(app.buttons[tab], in: app)
            openSettings(app)
            XCTAssertFalse(app.otherElements["mainNavigation"].exists)
            dragBack(app, to: 0.95)
            assertSelectedTab(tab, in: app)
        }
    }

    func testCancelledNestedBackKeepsTabBarHiddenUntilSettingsRoot() {
        let app = application("ask"); app.launch()
        openSettings(app)
        tap(app.buttons["openIntelligencePrivacy"], in: app)
        tap(app.buttons["editCloudModel"], in: app)
        tap(app.buttons["customCloudModel"], in: app)
        assertPushedPage("模型", in: app)
        dragBack(app, to: 0.18)
        assertPushedPage("模型", in: app)
        XCTAssertTrue(app.textFields["cloudModelName"].isHittable)
        dragBack(app, to: 0.95)
        assertPushedPage("智能与隐私", in: app)
        for _ in 0..<2 {
            dragBack(app, to: 0.18)
            assertPushedPage("智能与隐私", in: app)
        }
        dragBack(app, to: 0.95)
        XCTAssertTrue(app.buttons["openIntelligencePrivacy"].waitForExistence(timeout: 5))
        dragBack(app, to: 0.95)
        assertCurrentTab("tab_now", content: "fundsFormula", in: app)
    }


    func testSheetNavigationDoesNotHideRootTabBarAfterDismissal() {
        let app = application("manual"); app.launch(); tap(app.buttons["tab_yubai"], in: app)
        ask("这个月钱去哪了", in: app)
        tap(app.buttons["云端智能没开 ›"], in: app)
        assertPushedPage("智能与隐私", in: app)
        backToRoot(app); assertSelectedTab("tab_yubai", in: app)
        tap(addEntryTab(app), in: app); tap(app.buttons["importFromEntry"], in: app)
        XCTAssertTrue(app.buttons["chooseBillFile"].waitForExistence(timeout: 5))
        tap(app.buttons["cancelManualSheet"], in: app)
        assertSelectedTab("tab_yubai", in: app)
        tap(app.buttons["tab_ledger"], in: app)
        assertCurrentTab("tab_ledger", content: "entriesSearch", in: app)
    }

    func testTabButtonsPreserveWherePeriodWithoutPaging() {
        let app = application("ask"); app.launch(); openWhere(app)
        tap(app.buttons["wherePeriod_1"], in: app)
        for tab in ["tab_saving", "tab_yubai", "tab_now", "tab_ledger"] {
            tap(app.buttons[tab], in: app); assertSelectedTab(tab, in: app)
        }
        XCTAssertTrue(app.buttons["ledgerMode_where"].isSelected)
        XCTAssertTrue(app.buttons["wherePeriod_1"].isSelected)
        XCTAssertTrue(addEntryTab(app).isHittable)
    }

    func testLedgerSearchStaysOnHomeAndCancelRestoresHeader() {
        let app = application("entries"); app.launch(); tap(app.buttons["tab_ledger"], in: app)
        tap(app.buttons["entriesFilter_支出"], in: app)
        let field = app.textFields["entriesSearch"]
        tap(field, in: app)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["ledgerMode_detail"].exists)
        XCTAssertTrue(rootPage("tab_ledger", in: app).staticTexts["rootHeaderTitle"].exists)
        tap(app.buttons["entriesSearchCancel"], in: app)
        assertGone(app.keyboards.firstMatch)
        XCTAssertTrue(field.isHittable); XCTAssertTrue(app.buttons["ledgerMode_detail"].isSelected)
        XCTAssertTrue(app.buttons["entriesFilter_支出"].isSelected)
        assertSelectedTab("tab_ledger", in: app)
    }


    func testNativeLedgerShortSwipeRevealsAndFullSwipeDeletesWithUndo() {
        let app = application("entries", keepingUndo: true); app.launch(); tap(app.buttons["tab_ledger"], in: app)
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'ledgerEntry_' ")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5)); let identifier = row.identifier
        let action = app.buttons[identifier.replacingOccurrences(of: "ledgerEntry_", with: "deleteLedgerEntry_")]
        swipeRow(row); assertRevealState(row, revealed: true, action: action)
        tap(action, in: app); assertGone(app.buttons[identifier])
        tapUndo(messagePrefix: "已删掉 ·", in: app)
        let restored = app.buttons[identifier]; XCTAssertTrue(restored.waitForExistence(timeout: 5))
        let start = restored.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: restored.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.5)), withVelocity: .fast, thenHoldForDuration: 0)
        assertGone(app.buttons[identifier]); tapUndo(messagePrefix: "已删掉 ·", in: app)
        XCTAssertTrue(app.buttons[identifier].waitForExistence(timeout: 5))
    }

    func testNativeLedgerMenuOffersEditDuplicateAndDelete() {
        let app = application("entries"); app.launch(); tap(app.buttons["tab_ledger"], in: app)
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'ledgerEntry_' ")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5)); row.press(forDuration: 0.8)
        XCTAssertTrue(app.buttons["改一笔"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["再记一笔一样的"].exists); XCTAssertTrue(app.buttons["删掉"].exists)
        tap(app.buttons["再记一笔一样的"], in: app)
        XCTAssertEqual(app.buttons["entryKeypadAmount"].value as? String, "32.00")
        XCTAssertTrue(app.buttons["saveQuickEntry"].isEnabled)
    }

    func testNativeLedgerOnlyOneActionIsOpenAndTabsStillSwitchByTap() {
        let app = application("entries"); app.launch(); tap(app.buttons["tab_ledger"], in: app)
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'ledgerEntry_' "))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5))
        swipeRow(rows.element(boundBy: 0)); swipeRow(rows.element(boundBy: 1))
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'deleteLedgerEntry_' ")).count, 1)
        openWhere(app); assertSelectedTab("tab_ledger", in: app)
        tap(app.buttons["tab_ledger"], in: app); assertSelectedTab("tab_ledger", in: app)
        XCTAssertFalse(app.buttons["editEntryAmount"].exists)
    }

    func testLedgerRowSwipesDoNotOpenEditorAndTapStillWorks() {
        let app = application("ask", keepingUndo: true); app.launch(); tap(app.buttons["tab_ledger"], in: app)
        let row = ledgerRows(app).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        let delete = app.buttons[row.identifier.replacingOccurrences(of: "ledgerEntry_", with: "deleteLedgerEntry_")]
        swipeRow(row); assertRevealState(row, revealed: true, action: delete)
        XCTAssertFalse(app.buttons["editEntryAmount"].exists)
        swipeRow(row, left: false); assertRevealState(row, revealed: false, action: delete)
        assertSelectedTab("tab_ledger", in: app)
        tap(row, in: app)
        XCTAssertTrue(app.buttons["editEntryAmount"].waitForExistence(timeout: 5))
        tap(app.buttons["cancelManualSheet"], in: app)
        tap(addEntryTab(app), in: app)
        XCTAssertTrue(app.buttons["saveQuickEntry"].waitForExistence(timeout: 5))
    }

    func testHomeSearchFiltersAllMonthsAndCancelClearsQuery() {
        let app = application("round40"); app.launch(); tap(app.buttons["tab_ledger"], in: app)
        tap(app.buttons["entriesFilter_收入"], in: app)
        XCTAssertTrue(app.staticTexts["还没有这类账目"].waitForExistence(timeout: 5))
        tap(app.buttons["entriesFilter_支出"], in: app)
        let field = app.textFields["entriesSearch"]
        tap(field, in: app); field.typeText("3500.00")
        assertSearchCount(3, in: app)
        field.typeText("999")
        XCTAssertTrue(app.staticTexts["没有找到这笔"].waitForExistence(timeout: 5))
        tap(app.buttons["entriesSearchCancel"], in: app)
        XCTAssertEqual(field.value as? String, field.placeholderValue)
        XCTAssertTrue(app.buttons["entriesFilter_支出"].isSelected)
        assertSelectedTab("tab_ledger", in: app)
    }

    func testLedgerSwipeDeleteAndUndoRestoresRow() {
        let app = application("ask", keepingUndo: true); app.launch(); tap(app.buttons["tab_ledger"], in: app)
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'ledgerEntry_' ")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        let identifier = row.identifier
        swipeRow(row)
        XCTAssertFalse(app.buttons["editEntryAmount"].exists)
        let delete = app.buttons[identifier.replacingOccurrences(of: "ledgerEntry_", with: "deleteLedgerEntry_")]
        assertRevealState(row, revealed: true, action: delete)
        tap(delete, in: app)
        tapUndo(messagePrefix: "已删掉 ·", in: app)
        XCTAssertTrue(app.buttons[identifier].waitForExistence(timeout: 5))
        swipeRow(app.buttons[identifier]); assertRevealState(app.buttons[identifier], revealed: true, action: delete)
        tap(delete, in: app)
        assertGone(app.buttons[identifier])
        tapUndo(messagePrefix: "已删掉 ·", in: app)
        XCTAssertTrue(app.buttons[identifier].waitForExistence(timeout: 5))
        assertSelectedTab("tab_ledger", in: app)
    }


    func testLedgerRowsStillScrollVerticallyAndOpenWithTap() {
        let app = application("entries"); app.launch()
        tap(app.buttons["tab_ledger"], in: app)
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'ledgerEntry_' "))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5))
        let first = app.buttons[rows.firstMatch.identifier]
        let delete = app.buttons[first.identifier.replacingOccurrences(of: "ledgerEntry_", with: "deleteLedgerEntry_")]
        swipeRow(first)
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        let start = first.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -180)))
        XCTAssertTrue(app.buttons["tab_ledger"].isSelected); XCTAssertFalse(app.buttons["editEntryAmount"].exists)
        assertNotHittable(delete)
        XCTAssertFalse(first.isHittable)
        let visible = rows.allElementsBoundByIndex.first { $0.isHittable }
        XCTAssertNotNil(visible)
        if let visible { tap(visible, in: app) }
        XCTAssertTrue(app.buttons["editEntryAmount"].waitForExistence(timeout: 5))
    }

    func testLedgerHomeContainsTheCurrentCycleEntries() {
        let app = application("v45-home"); app.launch()
        XCTAssertTrue(app.buttons["fundsFormula"].waitForExistence(timeout: 5))
        let today = anyElement("todayEntries", in: app)
        scrollToVisible(today, in: app)
        XCTAssertEqual(today.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'ledgerEntry_' ")).count, 2)
        tap(app.buttons["tab_ledger"], in: app)
        let field = app.textFields["entriesSearch"]
        tap(field, in: app); field.typeText("日常")
        assertSearchCount(8, in: app)
    }


    func testManualEntryAndAskReturnToTheirOwnRoot() {
        let app = application("ask"); app.launch()
        tap(addEntryTab(app), in: app)
        XCTAssertTrue(app.buttons["saveQuickEntry"].waitForExistence(timeout: 5))
        tap(app.buttons["cancelManualSheet"], in: app); assertSelectedTab("tab_now", in: app)
        ask("咖啡共花了多少钱？", in: app)
        XCTAssertTrue(app.staticTexts["askAnswer"].waitForExistence(timeout: 10))
        backToRoot(app); assertSelectedTab("tab_yubai", in: app)
    }

    func testLedgerSearchFocusesImmediatelyAndCancelDismissesKeyboard() {
        let app = application("entries"); app.launch(); tap(app.buttons["tab_ledger"], in: app)
        let field = app.textFields["entriesSearch"]
        tap(field, in: app)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        field.typeText("合成")
        XCTAssertTrue(app.buttons["entriesSearchCancel"].isHittable)
        tap(app.buttons["entriesSearchCancel"], in: app)
        assertGone(app.keyboards.firstMatch)
        assertSelectedTab("tab_ledger", in: app)
        XCTAssertTrue(addEntryTab(app).isHittable); XCTAssertTrue(field.isHittable)
    }

    func testManualKeypadOperatorsAndPurposeKeyboard() {
        let app = application("manual"); app.launch()
        tap(addEntryTab(app), in: app)
        tap(app.buttons["keypad_1"], in: app); tap(app.buttons["keypad_2"], in: app); tap(app.buttons["keypad_+"], in: app)
        XCTAssertTrue(app.buttons["keypad_+"].isSelected)
        XCTAssertEqual(app.staticTexts["entryKeypadExpression"].label, "12 +")
        let purpose = app.textFields["entryPurpose"]
        tap(purpose, in: app); purpose.typeText("Lunch")
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5))
        assertGone(app.buttons["keypad_+"]); assertGone(app.buttons["saveQuickEntry"]); assertGone(app.buttons["saveAndAddAnother"])
        XCTAssertTrue(purpose.isHittable); XCTAssertLessThanOrEqual(purpose.frame.maxY, keyboard.frame.minY)
        purpose.typeText("\n")
        assertGone(keyboard)
        XCTAssertTrue(app.buttons["keypad_+"].waitForExistence(timeout: 5)); XCTAssertTrue(app.buttons["keypad_+"].isSelected)
        tap(app.buttons["keypad_3"], in: app)
        XCTAssertFalse(app.buttons["keypad_+"].isSelected)
        XCTAssertEqual(app.staticTexts["entryKeypadExpression"].label, "12 + 3")
        XCTAssertEqual(app.buttons["entryKeypadAmount"].value as? String, "15.00")
        XCTAssertEqual(app.buttons["saveQuickEntry"].label, "记下 15.00 元")
    }

    func testEntryPurposeKeepsExplicitCategoryAndNatureDoesNotPreselect() {
        let app = application("manual"); app.launch(); tap(addEntryTab(app), in: app)
        let purpose = app.textFields["entryPurpose"]
        XCTAssertFalse(app.buttons["entryCategory_餐饮"].isSelected)
        tap(purpose, in: app); purpose.typeText("地铁\n")
        XCTAssertFalse(app.buttons["entryCategory_餐饮"].isSelected); XCTAssertFalse(app.buttons["entryCategory_交通"].isSelected)
        tap(app.buttons["entryCategory_购物"], in: app)
        replaceText("兼职", in: purpose, app: app, submit: true)
        XCTAssertTrue(app.buttons["entryCategory_购物"].isSelected)
        tap(natureButton("收入", in: app), in: app)
        XCTAssertFalse(app.buttons["entryCategory_工资奖金"].isSelected)
        tap(natureButton("支出", in: app), in: app)
        XCTAssertFalse(app.buttons["entryCategory_餐饮"].isSelected)
    }

    private func entryScroll(_ app: XCUIApplication) -> XCUIElement {
        let scroll = app.scrollViews["entriesScroll"]
        if scroll.exists { return scroll }
        let collection = app.collectionViews["entriesScroll"]
        return collection.exists ? collection : app.tables["entriesScroll"]
    }

    func testPushedPageHidesTabBarAndRootReselectionScrollsToTop() {
        let app = application("entries"); app.launch(); tap(app.buttons["tab_ledger"], in: app)
        openSettings(app); tap(app.buttons["openIntelligencePrivacy"], in: app)
        assertPushedPage("智能与隐私", in: app)
        backToRoot(app); assertSelectedTab("tab_ledger", in: app)
        let scroll = entryScroll(app), field = app.textFields["entriesSearch"]
        scrollVertically(scroll, in: app)
        assertNotHittable(field)
        tap(app.buttons["tab_ledger"], in: app)
        assertVisibleWithoutScrolling(field, in: app, scroll: scroll)
        XCTAssertTrue(rootPage("tab_ledger", in: app).staticTexts["rootHeaderTitle"].isHittable)
    }

    func testAskConversationSurvivesClosingAndCanBeCleared() {
        let app = application("ask"); app.launch(); ask("咖啡共花了多少钱？", in: app)
        XCTAssertTrue(app.staticTexts["askAnswer"].waitForExistence(timeout: 10))
        backToRoot(app)
        tap(app.buttons["recentQuestion_0"], in: app)
        let answers = app.staticTexts.matching(identifier: "askAnswer")
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in answers.count == 2 }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed)
        tap(app.buttons["clearAskConversation"], in: app)
        assertGone(answers.firstMatch); assertGone(app.buttons["clearAskConversation"])
    }

    func testEntryDiscardDialogContinuesOrDiscards() {
        let app = application("manual"); app.launch(); tap(addEntryTab(app), in: app)
        pressAmount("32", in: app); tap(app.buttons["cancelManualSheet"], in: app)
        XCTAssertTrue(app.buttons["放弃这笔"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["已经填了 32.00 元"].exists)
        tap(app.buttons["继续记"], in: app)
        XCTAssertEqual(app.buttons["entryKeypadAmount"].value as? String, "32.00")
        tap(app.buttons["cancelManualSheet"], in: app); tap(app.buttons["放弃这笔"], in: app)
        assertGone(app.buttons["saveQuickEntry"])
        tap(addEntryTab(app), in: app); tap(app.buttons["cancelManualSheet"], in: app)
        assertGone(app.buttons["saveQuickEntry"])
        for choice in ["entryCategory_交通", "entryNature_income", "entryDate_yesterday"] {
            tap(addEntryTab(app), in: app); tap(app.buttons[choice], in: app)
            tap(app.buttons["cancelManualSheet"], in: app); assertGone(app.buttons["saveQuickEntry"])
        }
        tap(addEntryTab(app), in: app)
        let purpose = app.textFields["entryPurpose"]
        tap(purpose, in: app); purpose.typeText("合成用途\n")
        tap(app.buttons["cancelManualSheet"], in: app)
        XCTAssertTrue(app.buttons["放弃这笔"].waitForExistence(timeout: 5)); XCTAssertTrue(app.staticTexts["放弃修改？"].exists)
        tap(app.buttons["放弃这笔"], in: app); assertGone(app.buttons["saveQuickEntry"])
    }

    func testEntrySearchIncludesOtherMonths() {
        let app = application("round40"); app.launch(); tap(app.buttons["tab_ledger"], in: app)
        let field = app.textFields["entriesSearch"]
        tap(field, in: app); field.typeText("合成跨月房租")
        assertSearchCount(3, in: app)
        XCTAssertTrue(anyElement("entriesSearchTotal", in: app).label.contains("10,500.00"))
        XCTAssertEqual(ledgerRows(app).count, 3)
    }

    func testRecentlyDeletedRestoresOnlyChosenEntry() {
        let app = application("round40"); app.launch(); openSettings(app)
        tap(app.buttons["openBackup"], in: app); tap(app.buttons["recentlyDeleted"], in: app)
        let restore = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'restoreDeleted_' ")).firstMatch
        XCTAssertTrue(restore.waitForExistence(timeout: 5)); tap(restore, in: app)
        assertGone(restore)
        backToRoot(app); tap(app.buttons["tab_ledger"], in: app)
        let field = app.textFields["entriesSearch"]
        tap(field, in: app); field.typeText("合成放回测试")
        assertSearchCount(1, in: app); XCTAssertEqual(ledgerRows(app).count, 1)
    }

    private func openEntryMore(_ app: XCUIApplication) -> XCUIElement {
        tap(app.buttons["entryCategoryMore"], in: app)
        let scroll = app.scrollViews["entryCategoryPicker"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 5))
        return scroll
    }

    func testEntryMoreShowsBothLevelsKeepsGridAndPersistsSmallItem() {
        let app = application("manual"); app.launch(); tap(addEntryTab(app), in: app)
        pressAmount("3", in: app)
        let purpose = app.textFields["entryPurpose"]
        tap(purpose, in: app); purpose.typeText("合成剪头发\n")
        _ = openEntryMore(app)
        XCTAssertFalse(app.buttons["entryMoreCategory_工资奖金"].exists)
        XCTAssertFalse(app.buttons["entryMoreCategory_美容个护"].isSelected)
        tap(app.buttons["entryMoreCategory_美容个护"], in: app)
        let scroll = openEntryMore(app)
        tap(app.buttons["entryMoreSubcategory_美容个护/理发"], in: app, scroll: scroll)
        assertGone(scroll)
        XCTAssertTrue(app.buttons["entryCategory_美容个护"].isSelected)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'entryCategory_' ")).count, 9)
        XCTAssertTrue(app.buttons["entryCategoryMore"].exists)
        tap(app.buttons["saveQuickEntry"], in: app); tap(app.buttons["tab_ledger"], in: app)
        tap(ledgerRows(app).firstMatch, in: app)
        XCTAssertEqual(app.buttons["entryCategory_美容个护"].label, "美容个护 · 理发")
        snapshot("category-small-item-saved", app)
    }

    func testEditMoreConfirmsMainOnlyAndSmallItemDespiteLocalGuess() {
        let app = application("manual"); app.launch(); tap(addEntryTab(app), in: app)
        pressAmount("3", in: app)
        let purpose = app.textFields["entryPurpose"]
        tap(purpose, in: app); purpose.typeText("合成剪头发\n")
        tap(app.buttons["saveQuickEntry"], in: app); tap(app.buttons["tab_ledger"], in: app)
        let row = ledgerRows(app).firstMatch
        tap(row, in: app)
        var scroll = openEntryMore(app)
        tap(app.buttons["entryMoreCategory_美容个护"], in: app, scroll: scroll); assertGone(scroll)
        XCTAssertEqual(app.buttons["entryCategory_美容个护"].label, "美容个护")
        tap(app.buttons["saveManualSheet"], in: app); assertGone(app.buttons["editEntryAmount"]); tap(row, in: app)
        XCTAssertEqual(app.buttons["entryCategory_美容个护"].label, "美容个护")
        scroll = openEntryMore(app)
        tap(app.buttons["entryMoreSubcategory_美容个护/理发"], in: app, scroll: scroll)
        tap(app.buttons["saveManualSheet"], in: app); assertGone(app.buttons["editEntryAmount"]); tap(row, in: app)
        XCTAssertEqual(app.buttons["entryCategory_美容个护"].label, "美容个护 · 理发")
        scroll = openEntryMore(app); tap(app.buttons["entryMoreCategory_美容个护"], in: app, scroll: scroll)
        tap(app.buttons["saveManualSheet"], in: app); assertGone(app.buttons["editEntryAmount"])
        app.terminate(); app.launch(); tap(app.buttons["tab_ledger"], in: app); tap(row, in: app)
        XCTAssertEqual(app.buttons["entryCategory_美容个护"].label, "美容个护")
    }

    func testEntryMoreFollowsNatureAndClearsOldSmallItem() {
        let app = application("manual"); app.launch(); tap(addEntryTab(app), in: app)
        _ = openEntryMore(app); tap(app.buttons["entryMoreCategory_餐饮"], in: app)
        _ = openEntryMore(app); tap(app.buttons["entryMoreSubcategory_餐饮/早餐"], in: app)
        tap(natureButton("收入", in: app), in: app)
        _ = openEntryMore(app); XCTAssertFalse(app.buttons["entryMoreCategory_餐饮"].exists)
        tap(app.buttons["entryMoreCategory_工资奖金"], in: app)
        _ = openEntryMore(app); tap(app.buttons["entryMoreSubcategory_工资奖金/工资"], in: app)
        XCTAssertEqual(app.buttons["entryCategory_工资奖金"].label, "工资奖金 · 工资")
        tap(natureButton("支出", in: app), in: app)
        _ = openEntryMore(app); tap(app.buttons["entryMoreCategory_餐饮"], in: app)
        _ = openEntryMore(app)
        XCTAssertFalse(app.buttons["entryMoreSubcategory_餐饮/早餐"].isSelected)
        XCTAssertFalse(app.buttons["entryMoreCategory_工资奖金"].exists)
        tap(app.buttons["entryMoreCancel"], in: app)
        tap(natureButton("转账", in: app), in: app)
        XCTAssertFalse(app.buttons["entryCategoryMore"].exists)
    }

    func testEntryMoreAddsSmallItemAndRepeatKeepsPlanMainOnly() {
        let app = application("manual"); app.launch(); tap(addEntryTab(app), in: app)
        var scroll = openEntryMore(app)
        tap(app.buttons["entryMoreAdd"], in: app, scroll: scroll)
        tap(app.buttons["cancelManualSheet"], in: app)
        XCTAssertTrue(scroll.waitForExistence(timeout: 5)); tap(app.buttons["entryMoreCancel"], in: app)
        scroll = openEntryMore(app); tap(app.buttons["entryMoreAdd"], in: app, scroll: scroll)
        tap(app.buttons["categoryAdditionParent_餐饮"], in: app)
        let name = app.textFields["categoryAdditionName"]
        tap(name, in: app); name.typeText("合成小项\n"); tap(app.buttons["categoryAdditionSave"], in: app)
        assertGone(scroll)
        XCTAssertTrue(app.buttons["entryCategory_餐饮"].isSelected)
        pressAmount("3", in: app); tap(app.buttons["entryRepeat"], in: app); tap(app.buttons["saveQuickEntry"], in: app)
        assertGone(app.buttons["saveQuickEntry"]); tap(app.buttons["tab_ledger"], in: app); tap(ledgerRows(app).firstMatch, in: app)
        XCTAssertEqual(app.buttons["entryCategory_餐饮"].label, "餐饮 · 合成小项")
        tap(app.buttons["entryRepeat"], in: app)
        XCTAssertEqual(app.buttons["fixedFlowCategory"].value as? String, "餐饮")
    }

    func testEditAmountTrayReplacesSelectionResolvesAndRepeatsDeletion() {
        let app = application("manual"); app.launch()
        tap(addEntryTab(app), in: app)
        tap(app.buttons["keypad_3"], in: app); tap(app.buttons["keypad_2"], in: app)
        tap(app.buttons["saveQuickEntry"], in: app)
        tap(app.buttons["tab_ledger"], in: app)
        tap(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'ledgerEntry_' ")).firstMatch, in: app)
        XCTAssertFalse(app.textFields["备注"].exists); XCTAssertFalse(app.staticTexts["备注"].exists)
        let amount = app.buttons["editEntryAmount"]
        enterAmount("5.5+2", identifier: "editEntryAmount", in: app)
        XCTAssertEqual(amount.value as? String, "7.50")
        tap(amount, in: app); tap(app.buttons["keypad_⌫"], in: app)
        XCTAssertEqual(amount.value as? String, "7.00")
        app.buttons["keypad_⌫"].press(forDuration: 1.2)
        XCTAssertEqual(amount.value as? String, "0.00")
        XCTAssertFalse(app.buttons["amountKeypadDone"].isEnabled)
        tap(app.buttons["cancelManualSheet"], in: app)
        XCTAssertTrue(app.buttons["继续记"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["放弃修改？"].exists); XCTAssertFalse(app.staticTexts["已经填了 0.00 元"].exists)
        tap(app.buttons["继续记"], in: app)
        tap(app.buttons["keypad_8"], in: app)
        XCTAssertEqual(amount.value as? String, "8.00")
        tap(app.buttons["amountKeypadDone"], in: app)
        tap(app.buttons["saveManualSheet"], in: app)
        XCTAssertFalse(amount.exists)
    }

    func testQuickEntryRepeatSavesFirstPeriodAndNextSheetResetsRepeat() {
        let app = application("manual"); app.launch(); tap(addEntryTab(app), in: app)
        tap(app.buttons["keypad_2"], in: app); tap(app.buttons["entryRepeat"], in: app)
        XCTAssertTrue(app.buttons["entryRepeat"].isSelected)
        tap(app.buttons["saveQuickEntry"], in: app)
        XCTAssertTrue(app.buttons["addEntry"].waitForExistence(timeout: 5))
        tap(addEntryTab(app), in: app)
        XCTAssertFalse(app.buttons["entryRepeat"].isSelected)
        tap(app.buttons["cancelManualSheet"], in: app)
        openFixedBills(app)
        XCTAssertTrue(app.images.matching(NSPredicate(format: "label BEGINSWITH '已付 ' ")).firstMatch.waitForExistence(timeout: 5))
    }

    func testEditRepeatCreatesPlanAndLinkedChipOpensItsEditor() {
        let app = application("manual"); app.launch(); tap(addEntryTab(app), in: app)
        tap(app.buttons["keypad_3"], in: app); tap(app.buttons["saveQuickEntry"], in: app)
        tap(app.buttons["tab_ledger"], in: app)
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'ledgerEntry_' ")).firstMatch
        tap(row, in: app); tap(app.buttons["entryRepeat"], in: app)
        XCTAssertTrue(app.buttons["entryRepeat"].isSelected)
        tap(app.buttons["saveManualSheet"], in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 5)); tap(row, in: app)
        let repeatChip = app.buttons["entryRepeat"]
        XCTAssertTrue(repeatChip.isSelected)
        tap(repeatChip, in: app)
        XCTAssertTrue(app.buttons["fixedFlowSchedule"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["改账单"].exists)
    }

    func testEntryRepeatIsHiddenForTransferAndSelectedBillMatch() {
        let app = application("bills"); app.launch(); tap(addEntryTab(app), in: app)
        XCTAssertTrue(app.buttons["entryRepeat"].exists)
        tap(natureButton("转账", in: app), in: app); XCTAssertFalse(app.buttons["entryRepeat"].exists)
        tap(natureButton("支出", in: app), in: app)
        for key in "300" { tap(app.buttons["keypad_" + String(key)], in: app) }
        let match = app.buttons["fixedFlowSuggestion"]
        XCTAssertTrue(match.waitForExistence(timeout: 5)); tap(match, in: app)
        XCTAssertFalse(app.buttons["entryRepeat"].exists)
        tap(match, in: app); XCTAssertTrue(app.buttons["entryRepeat"].exists)
    }

    func testFixedFlowAmountUsesSameTrayAndNameFocusClosesIt() {
        let app = application("bills"); app.launch(); openFixedBills(app)
        let check = app.buttons["付了 房租"]
        XCTAssertTrue(check.waitForExistence(timeout: 5))
        let planID = String(check.identifier.split(separator: "_")[1])
        tap(app.buttons["editFixedFlow_" + planID], in: app)
        enterAmount("12+3", identifier: "fixedFlowAmount", in: app)
        XCTAssertEqual(app.buttons["fixedFlowAmount"].value as? String, "15")
        tap(app.buttons["fixedFlowAmount"], in: app)
        tap(app.textFields["fixedFlowTitle"], in: app)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5)); assertGone(app.buttons["amountKeypadDone"])
    }

    func testTransferWithOneAccountCanAddDestinationWithoutLosingDraft() {
        let app = application("manual"); app.launch(); tap(addEntryTab(app), in: app)
        tap(natureButton("转账", in: app), in: app); pressAmount("500", in: app)
        let purpose = app.textFields["entryPurpose"]
        tap(purpose, in: app); purpose.typeText("UI Transfer\n")
        let save = app.buttons["saveQuickEntry"], addAccount = app.buttons["transferAddAccount"]
        XCTAssertFalse(save.isEnabled); tap(addAccount, in: app)
        let name = app.textFields["accountName"]
        tap(name, in: app); name.typeText("UI Transfer Bank\n")
        tap(app.buttons["saveManualSheet"], in: app)
        assertGone(name)
        XCTAssertTrue(save.isEnabled)
        XCTAssertEqual(app.buttons["entryKeypadAmount"].value as? String, "500.00")
        XCTAssertEqual(purpose.value as? String, "UI Transfer")
        XCTAssertTrue(app.buttons["transferDestinationAccount"].value as? String == "UI Transfer Bank 0.00")
        tap(save, in: app); assertGone(save)
        tap(app.buttons["tab_ledger"], in: app); XCTAssertTrue(ledgerRows(app).firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(ledgerRows(app).count, 1)
        tap(ledgerRows(app).firstMatch, in: app)
        XCTAssertEqual(app.buttons["editEntryAmount"].value as? String, "500.00")
        XCTAssertTrue(natureButton("转账", in: app).isSelected)
        tap(app.buttons["cancelManualSheet"], in: app)
        tap(addEntryTab(app), in: app); tap(natureButton("转账", in: app), in: app)
        XCTAssertTrue((app.buttons["transferDestinationAccount"].value as? String ?? "").contains("UI Transfer Bank"))
        XCTAssertFalse(addAccount.exists)
    }

    func testManualKeypadSaveUpdatesFundsAndLedgerEditAndDelete() {
        let app = application("manual"); app.launch()
        let funds = app.buttons["fundsFormula"]
        XCTAssertTrue(funds.waitForExistence(timeout: 10)); XCTAssertTrue(funds.label.contains("1,000.00"))
        tap(addEntryTab(app), in: app); pressAmount("32", in: app)
        XCTAssertEqual(app.buttons["entryKeypadAmount"].value as? String, "32.00")
        tap(app.buttons["saveQuickEntry"], in: app); assertGone(app.buttons["saveQuickEntry"])
        let decreased = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS '968.00'"), object: funds)
        XCTAssertEqual(XCTWaiter.wait(for: [decreased], timeout: 5), .completed)
        XCTAssertTrue(anyElement("todayEntries", in: app).waitForExistence(timeout: 5))
        tap(app.buttons["tab_ledger"], in: app)
        let row = ledgerRows(app).firstMatch
        tap(row, in: app); XCTAssertTrue(app.buttons["editEntryAmount"].waitForExistence(timeout: 5))
        tap(app.buttons["deleteEntry"], in: app); assertGone(row)
        tap(app.buttons["tab_now"], in: app)
        XCTAssertTrue(funds.label.contains("1,000.00")); XCTAssertFalse(anyElement("todayEntries", in: app).exists)
        snapshot("manual-deleted", app)
    }

    func testImportOrganizationIgnoresLegacyQuestionKeepsFallbackAndUndoesEntireBatch() {
        let app = application("import")
        let csv = "时间,收支,金额,名称,交易类型,交易单号\n2001-01-02 12:00:00,支出,32.00,合成午餐,商户消费,ui-lunch\n2001-01-02 13:00:00,收入,40.00,合成来款,转账,ui-incoming\n"
        app.launchEnvironment["YUBAI_UI_STATEMENT"] = Data(csv.utf8).base64EncodedString()
        app.launch()
        snapshot("overview", app)
        tap(addEntryTab(app), in: app)
        tap(app.buttons["importFromEntry"], in: app)
        snapshot("import-preview", app)
        let incoming = app.descendants(matching: .any).matching(identifier: "importTotal_流入").firstMatch
        XCTAssertTrue(incoming.waitForExistence(timeout: 5))
        XCTAssertTrue(incoming.label.contains("1 笔")); XCTAssertTrue(incoming.label.contains("40.00"))
        let outgoing = app.descendants(matching: .any).matching(identifier: "importTotal_流出").firstMatch
        XCTAssertTrue(outgoing.label.contains("1 笔")); XCTAssertTrue(outgoing.label.contains("32.00"))
        tap(app.buttons["commitImport"], in: app)
        let fallback = app.buttons["importResultUnclassified"]
        let classified = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            fallback.exists && fallback.label.contains("还没分类") && fallback.label.contains("1")
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [classified], timeout: 10), .completed)
        XCTAssertFalse(app.staticTexts["importQuestion"].exists)
        XCTAssertFalse(app.buttons["importAnswer_0"].exists)
        XCTAssertTrue(fallback.isEnabled)
        snapshot("import-fallback", app)
        tap(app.buttons["closeSheet"], in: app)
        openSettings(app)
        tap(app.buttons["openImportHistory"], in: app)
        XCTAssertTrue(app.staticTexts["合成账单.csv"].waitForExistence(timeout: 5))
        snapshot("import-history", app)
        tap(app.buttons["undoImportBatch"], in: app)
        tap(app.buttons["撤销这一批"], in: app)
        XCTAssertTrue(app.staticTexts["emptyImportHistory"].waitForExistence(timeout: 5))
        snapshot("history-undone", app)
        // Reimport is no longer a duplicate. The pre-existing record survives undo.
        backToRoot(app)
        tap(app.buttons["tab_ledger"], in: app)
        tap(addEntryTab(app), in: app)
        tap(app.buttons["importFromEntry"], in: app)
        XCTAssertTrue(app.buttons["commitImport"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["commitImport"].isEnabled)
        tap(app.buttons["commitImport"], in: app)
        XCTAssertTrue(app.buttons["importResultUnclassified"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["importQuestion"].exists)
        XCTAssertFalse(app.buttons["importAnswer_0"].exists)
        tap(app.buttons["undoImportResult"], in: app)
        XCTAssertTrue(app.staticTexts["activeEntryCount"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["activeEntryCount"].label, "有效记录 1 笔")
        snapshot("reimport-undone", app)
    }


    func testAskNumericAnswerEvidenceAndEntryDetail() {
        let app = application("ask"); app.launch(); ask("咖啡共花了多少钱？", in: app)
        let answer = app.staticTexts["askAnswer"]
        XCTAssertTrue(answer.waitForExistence(timeout: 10)); XCTAssertTrue(answer.label.contains("32.00"))
        snapshot("numeric-answer", app)
        tap(app.buttons["answerEvidence"], in: app)
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'evidenceEntry_' ")).firstMatch
        tap(row, in: app)
        XCTAssertTrue(app.staticTexts["entryDetailTitle"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["entryDetailTitle"].label, "合成咖啡")
        snapshot("entry-detail", app)
    }

    func testProfilePrinciplePersistsAndBackupOpens() {
        let app = application("profile"); app.launch()
        tap(app.buttons["tab_yubai"], in: app); tap(app.buttons["openProfile"], in: app)
        tap(app.buttons["editProfile"], in: app); tap(app.buttons["addPrinciple"], in: app)
        let field = anyElement("principleText", in: app)
        tap(field, in: app); field.typeText("为每天用得上的东西花钱")
        tap(app.buttons["savePrinciple"], in: app)
        XCTAssertTrue(app.staticTexts["为每天用得上的东西花钱"].waitForExistence(timeout: 5))
        app.terminate(); app.launch(); tap(app.buttons["tab_yubai"], in: app); tap(app.buttons["openProfile"], in: app)
        XCTAssertTrue(app.staticTexts["为每天用得上的东西花钱"].waitForExistence(timeout: 5))
        backToRoot(app); openSettings(app); tap(app.buttons["openBackup"], in: app)
        XCTAssertTrue(app.navigationBars["备份与恢复"].waitForExistence(timeout: 5))
        XCTAssertTrue(anyElement("lastBackup", in: app).exists); XCTAssertTrue(app.buttons["restoreFromBackup"].exists)
        tap(app.buttons["backupToFile"], in: app)
        XCTAssertTrue(app.secureTextFields["备份密码（至少 8 位）"].waitForExistence(timeout: 5))
        XCTAssertFalse(addEntryTab(app).isHittable)
        snapshot("backup", app)
    }
    func testAskMemoryCanBeOpenedEditedAndDeletedFromMe() {
        let app = application("memory"); app.launch(); ask("年底前想换电脑", in: app)
        XCTAssertTrue(app.staticTexts["已记下：年底前想换电脑"].waitForExistence(timeout: 10))
        backToRoot(app); tap(app.buttons["openMemories"], in: app)
        XCTAssertTrue(app.navigationBars["余白记得的"].waitForExistence(timeout: 5))
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'memory_' ")).firstMatch
        tap(row, in: app)
        let field = anyElement("memoryText", in: app)
        replaceText("年底前想换电脑，先留一笔钱", in: field, app: app)
        tap(app.buttons["saveMemory"], in: app)
        XCTAssertTrue(app.staticTexts["年底前想换电脑，先留一笔钱"].waitForExistence(timeout: 5))
        app.terminate(); app.launch(); tap(app.buttons["tab_yubai"], in: app); tap(app.buttons["openMemories"], in: app)
        XCTAssertTrue(app.staticTexts["年底前想换电脑，先留一笔钱"].waitForExistence(timeout: 5))
        tap(row, in: app); tap(app.buttons["deleteMemory"], in: app)
        XCTAssertTrue(anyElement("emptyMemories", in: app).waitForExistence(timeout: 5))
        snapshot("memory-deleted", app)
    }

    func testLedgerMonthWheelRemainsOnHome() {
        let app = application("round40"); app.launch(); tap(app.buttons["tab_ledger"], in: app)
        tap(app.buttons.matching(identifier: "entriesMonth").firstMatch, in: app)
        XCTAssertTrue(app.pickerWheels.firstMatch.waitForExistence(timeout: 5))
        let year = app.pickerWheels.element(boundBy: 0), month = app.pickerWheels.element(boundBy: 1)
        let current = Int((month.value as? String ?? "").components(separatedBy: " ")[0])!
        if current == 1 {
            let currentYear = Int((year.value as? String ?? "").components(separatedBy: " ")[0])!
            year.adjust(toPickerWheelValue: "\(currentYear - 1) 年")
        }
        month.adjust(toPickerWheelValue: "\(current == 1 ? 12 : current - 1) 月")
        tap(app.buttons["saveManualSheet"], in: app); assertGone(app.pickerWheels.firstMatch)
        assertSelectedTab("tab_ledger", in: app)
        let row = ledgerRows(app).matching(NSPredicate(format: "label CONTAINS '合成跨月房租' AND hittable == true")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        tap(app.buttons["tab_ledger"], in: app)
        assertVisibleWithoutScrolling(app.textFields["entriesSearch"], in: app, scroll: entryScroll(app))
    }

    func testIncomeFixedSavingsChipResetsWhenDirectionChanges() {
        let app = application("manual"); app.launch(); tap(addEntryTab(app), in: app)
        tap(natureButton("收入", in: app), in: app)
        let chip = app.buttons["entryIntoFixedSavings"]
        XCTAssertTrue(chip.waitForExistence(timeout: 5)); tap(chip, in: app)
        XCTAssertTrue(chip.isSelected)
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "identifier == 'entrySavingHint' AND label CONTAINS '→'")).firstMatch.exists)
        tap(natureButton("支出", in: app), in: app); assertGone(chip)
        tap(natureButton("收入", in: app), in: app); XCTAssertFalse(chip.isSelected)
        tap(app.buttons["cancelManualSheet"], in: app)
    }


    // MARK: v45 interactions

    func testV45ImportRecognizesSalaryAndBillsAddsAllAndBatchUndoRemovesPlans() {
        let app = application("v45-import-plans"); app.launch(); openSettings(app)
        tap(app.buttons["openImportHistory"], in: app)
        let batch = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'openImportBatch_' ")).firstMatch
        tap(batch, in: app)
        let page = anyElement("importResultPage", in: app)
        let plans = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'recognizedImportPlan_' "))
        XCTAssertTrue(app.buttons["addAllRecognizedImportPlans"].waitForExistence(timeout: 10))
        XCTAssertEqual(plans.count, 2)
        XCTAssertTrue((page.value as? String ?? "").contains("plans=0"))
        tap(app.buttons["addAllRecognizedImportPlans"], in: app)
        let added = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            (page.value as? String ?? "").contains("plans=2")
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [added], timeout: 5), .completed)
        XCTAssertFalse(app.buttons["addAllRecognizedImportPlans"].exists)
        tap(app.buttons["undoImportResult"], in: app)
        XCTAssertTrue(app.staticTexts["activeEntryCount"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["activeEntryCount"].label, "有效记录 0 笔")
        XCTAssertTrue((page.value as? String ?? "").contains("plans=0"))
    }

    func testV45ImportMergesManualIDAndBatchUndoRestoresOriginalSource() {
        let app = application("v45-import-merge")
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "zh_CN"); formatter.dateFormat = "yyyy-MM-dd"
        let csv = "时间,收支,金额,名称,交易类型,交易单号\n" + formatter.string(from: Date()) + " 00:00:00,支出,18.00,合成银行咖啡,商户消费,v45-merged-coffee\n"
        app.launchEnvironment["YUBAI_UI_STATEMENT"] = Data(csv.utf8).base64EncodedString()
        app.launch(); tap(addEntryTab(app), in: app); tap(app.buttons["importFromEntry"], in: app)
        XCTAssertTrue(app.buttons["commitImport"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["commitImport"].isEnabled)
        tap(app.buttons["commitImport"], in: app)
        let page = anyElement("importResultPage", in: app)
        XCTAssertTrue(page.waitForExistence(timeout: 5))
        let state = page.value as? String ?? ""
        XCTAssertTrue(state.contains("entries=1")); XCTAssertTrue(state.contains("manualTitle=合成手记咖啡"))
        XCTAssertTrue(state.contains("manualCategory=餐饮")); XCTAssertFalse(state.contains("manualSource=手动"))
        tap(app.buttons["undoImportResult"], in: app)
        XCTAssertTrue(app.staticTexts["activeEntryCount"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["activeEntryCount"].label, "有效记录 1 笔")
        XCTAssertTrue((page.value as? String ?? "").contains("manualSource=手动"))
        tap(app.buttons["closeSheet"], in: app); tap(app.buttons["tab_ledger"], in: app)
        let search = app.textFields["entriesSearch"]
        tap(search, in: app); search.typeText("合成手记咖啡"); assertSearchCount(1, in: app)
        XCTAssertEqual(ledgerRows(app).firstMatch.identifier, "ledgerEntry_45000000-0000-0000-0000-000000000005")
    }

    func testV45ReceiptSelectionSwitchesBetweenSeparateAndOneMergedEntry() {
        let app = application("v45-receipt"); app.launch(); addEntryTab(app).press(forDuration: 0.8)
        tap(app.buttons["quickReceipt"], in: app)
        XCTAssertTrue(app.staticTexts["receiptSummary"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["receiptSummary"].label.contains("186.40"))
        tap(app.buttons["receiptSelect_2"], in: app)
        let save = app.buttons["saveReceiptEntries"]
        let separate = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "2 笔"), object: save)
        XCTAssertEqual(XCTWaiter.wait(for: [separate], timeout: 5), .completed)
        tap(app.buttons["receiptMode_merged"], in: app)
        let merged = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@ AND enabled == true", "1 笔"), object: save)
        XCTAssertEqual(XCTWaiter.wait(for: [merged], timeout: 5), .completed)
        XCTAssertTrue(anyElement("receiptAvailableAfter", in: app).label.contains("9,843.60"))
        tap(save, in: app)
        tap(app.buttons["tab_ledger"], in: app)
        let search = app.textFields["entriesSearch"]
        tap(search, in: app); search.typeText("合成超市"); assertSearchCount(1, in: app)
        XCTAssertTrue(ledgerRows(app).firstMatch.label.contains("156.40"))
        XCTAssertTrue(ledgerRows(app).firstMatch.label.contains("没分类"))
    }

    func testV45PrincipleEditorSets48HourWishInsteadOfDefaultSevenDays() {
        let app = application("v45-principles"); app.launch(); tap(app.buttons["tab_yubai"], in: app)
        tap(app.buttons["openProfile"], in: app); tap(app.buttons["addPrinciple"], in: app)
        tap(app.buttons["principleSuggestion_超过 2,000 等 48 小时"], in: app)
        tap(app.buttons["savePrinciple"], in: app)
        XCTAssertTrue(app.buttons["profilePrinciple_超过 2,000 等 48 小时"].waitForExistence(timeout: 5))
        backToRoot(app); ask("徒步鞋 2480，该不该买？", in: app)
        XCTAssertTrue(app.buttons["purchaseSaveWish"].waitForExistence(timeout: 10))
        tap(app.buttons["purchaseSaveWish"], in: app)
        backToRoot(app); tap(app.buttons["tab_saving"], in: app); tap(app.buttons["openWishlist"], in: app)
        let wait = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'wishWait_' ")).firstMatch
        XCTAssertTrue(wait.waitForExistence(timeout: 5)); XCTAssertEqual(wait.value as? String, "等待 48 小时")
        XCTAssertTrue(wait.label.contains("2 天"))
        app.terminate(); app.launch(); tap(app.buttons["tab_saving"], in: app); tap(app.buttons["openWishlist"], in: app)
        XCTAssertTrue(wait.waitForExistence(timeout: 5)); XCTAssertEqual(wait.value as? String, "等待 48 小时")
    }

    func testV45WeeklyBackupWritesOnceAndActivationDoesNotRepeatIt() {
        let app = application("v45-backup"); app.launch(); openSettings(app); tap(app.buttons["openBackup"], in: app)
        let backup = anyElement("lastBackup", in: app)
        let saved = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            backup.label.contains("今天") && (backup.value as? String ?? "").contains("files=1")
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [saved], timeout: 10), .completed)
        let enabled = app.switches["weeklyAutoBackup"]
        XCTAssertEqual(enabled.value as? String, "1")
        XCTAssertTrue(app.buttons["exportEntriesCSV"].exists)
        app.terminate(); app.launch(); openSettings(app); tap(app.buttons["openBackup"], in: app)
        XCTAssertTrue(backup.waitForExistence(timeout: 5)); XCTAssertTrue((backup.value as? String ?? "").contains("files=1"))
        tap(enabled, in: app); XCTAssertEqual(enabled.value as? String, "0")
    }

    func testV45CSVExportCancelDoesNotChangeSuccessfulBackupDate() {
        let app = application("v45-backup"); app.launch(); openSettings(app); tap(app.buttons["openBackup"], in: app)
        let backup = anyElement("lastBackup", in: app)
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            (backup.value as? String ?? "").contains("files=1")
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed)
        let date = backup.label
        tap(app.buttons["exportEntriesCSV"], in: app)
        let cancel = app.buttons["取消"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 5)); tap(cancel, in: app)
        XCTAssertTrue(backup.waitForExistence(timeout: 5)); XCTAssertEqual(backup.label, date)
        XCTAssertTrue((backup.value as? String ?? "").contains("csv=1"))
        XCTAssertTrue((backup.value as? String ?? "").contains("files=1"))
    }

    func testV45FourAIFeaturesPersistUnderMasterAndPreventQuestionsAndReceiptEntry() {
        let app = application("v45-ai"); app.launch(); openSettings(app); tap(app.buttons["openIntelligencePrivacy"], in: app)
        for feature in ["importClassification", "answers", "weeklyReview", "receiptRecognition"] {
            let toggle = app.switches["aiFeature_" + feature]
            scrollToVisible(toggle, in: app); XCTAssertEqual(toggle.value as? String, "1"); tap(toggle, in: app)
        }
        let master = app.switches["cloudAIToggle"]
        scrollToVisible(master, in: app); tap(master, in: app); tap(master, in: app)
        for feature in ["importClassification", "answers", "weeklyReview", "receiptRecognition"] {
            XCTAssertEqual(app.switches["aiFeature_" + feature].value as? String, "0")
        }
        backToRoot(app); ask("现在还能花多少？", in: app)
        XCTAssertTrue(app.buttons["enableAskAI"].waitForExistence(timeout: 5)); XCTAssertFalse(app.buttons["sendAsk"].isEnabled)
        XCTAssertTrue((anyElement("askPage", in: app).value as? String ?? "").contains("requests=0"))
        backToRoot(app); addEntryTab(app).press(forDuration: 0.8)
        XCTAssertTrue(app.buttons["quickRepeat_0"].waitForExistence(timeout: 5)); XCTAssertFalse(app.buttons["quickReceipt"].exists)
        app.terminate(); app.launch(); openSettings(app); tap(app.buttons["openIntelligencePrivacy"], in: app)
        XCTAssertEqual(app.switches["aiFeature_answers"].value as? String, "0")
    }

    func testV45FrequentEntriesPinReorderHideAndLongPressRespectSavedOrder() {
        let app = application("v45-repeats"); app.launch(); openSettings(app); tap(app.buttons["openQuickCapture"], in: app)
        XCTAssertTrue(anyElement("frequentEntriesPage", in: app).waitForExistence(timeout: 5))
        tap(app.buttons["frequentPin_2"], in: app)
        let first = anyElement("frequentEntry_0", in: app)
        XCTAssertTrue(first.staticTexts["咖啡"].waitForExistence(timeout: 5))
        tap(app.buttons["frequentMoveDown_0"], in: app)
        XCTAssertTrue(first.staticTexts["地铁"].waitForExistence(timeout: 5))
        tap(app.buttons["frequentHide_0"], in: app)
        XCTAssertTrue(first.staticTexts["咖啡"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'frequentUnhide_' ")).firstMatch.exists)
        app.terminate(); app.launch(); addEntryTab(app).press(forDuration: 0.8)
        XCTAssertTrue(app.buttons["quickRepeat_0"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["quickRepeat_0"].label.contains("咖啡"))
        XCTAssertTrue(app.buttons["quickRepeat_1"].label.contains("午饭")); XCTAssertFalse(app.buttons["quickRepeat_2"].exists)
    }

    func testV45SettingsShowsPaydayDayAsFact() {
        let app = application("v45-home"); app.launch(); openSettings(app)
        let detail = app.staticTexts["settingsPaydayDetail"]
        XCTAssertTrue(detail.waitForExistence(timeout: 5))
        XCTAssertNotNil(detail.label.range(of: #"^发工资那天 · [0-9]{1,2} 号$"#, options: .regularExpression))
    }

    func testBillDueMatchesExistingEntryWithoutAddingDuplicate() {
        let app = application("v45-bill-match", keepingUndo: true); app.launch()
        tap(app.buttons["tab_ledger"], in: app)
        let search = app.textFields["entriesSearch"]
        tap(search, in: app); search.typeText("话费和宽带"); assertSearchCount(1, in: app)
        let entryID = ledgerRows(app).firstMatch.identifier
        tap(app.buttons["entriesSearchCancel"], in: app); tap(app.buttons["tab_now"], in: app)
        tap(app.buttons["billDuePaid"], in: app)
        XCTAssertTrue(app.buttons["billMatchConfirm"].waitForExistence(timeout: 5))
        tap(app.buttons["billMatchConfirm"], in: app); assertGone(app.buttons["billMatchConfirm"])
        XCTAssertFalse(app.buttons["billDuePaid"].exists)
        tap(app.buttons["tab_ledger"], in: app)
        tap(search, in: app); search.typeText("话费和宽带"); assertSearchCount(1, in: app)
        XCTAssertEqual(ledgerRows(app).firstMatch.identifier, entryID)
        app.terminate(); app.launch(); XCTAssertFalse(app.buttons["billDuePaid"].exists)
    }

    func testV45BillLongPressOffersSixActionsAndSkipsThisOccurrence() {
        let app = application("v45-bill"); app.launch()
        let before = displayedAmount(anyElement("availableFunds", in: app))

        let bill = homeBillCheck("话费和宽带", in: app)
        scrollToVisible(bill, in: app)
        let identifier = bill.identifier
        bill.press(forDuration: 0.8)
        for identifier in ["billMenu_pay", "billMenu_linked", "billMenu_amount", "billMenu_skip", "billMenu_move", "billMenu_stop"] {
            XCTAssertTrue(app.buttons[identifier].waitForExistence(timeout: 5))
        }
        tap(app.buttons["billMenu_skip"], in: app)
        assertGone(app.buttons[identifier])
        backToRoot(app)
        XCTAssertEqual(displayedAmount(anyElement("availableFunds", in: app)), before + 16_000)
        app.terminate(); app.launch()
        XCTAssertFalse(app.buttons[identifier].exists)
        snapshot("bill-skipped-this-month", app)
    }

    func testV45EstimatedBillCheckEditsAmountBeforeRecording() {
        let app = application("v45-bill"); app.launch()
        let before = displayedAmount(anyElement("availableFunds", in: app))

        let bill = homeBillCheck("电费", in: app)
        scrollToVisible(bill, in: app)
        let planID = String(bill.identifier.dropFirst("billCheck_".count))
        tap(app.buttons["billCheck_" + planID], in: app)
        XCTAssertTrue(anyElement("amountSheetAmount", in: app).waitForExistence(timeout: 5))
        XCTAssertEqual(anyElement("amountSheetAmount", in: app).value as? String, "180.00")
        pressAmount("163.40", in: app)
        tap(app.buttons["amountSheetDone"], in: app); assertGone(app.buttons["amountSheetDone"])
        XCTAssertFalse(anyElement("billCheck_" + planID, in: app).exists)
        backToRoot(app)
        XCTAssertEqual(displayedAmount(anyElement("availableFunds", in: app)), before + 1660)
        tap(app.buttons["tab_ledger"], in: app)
        let search = app.textFields["entriesSearch"]
        tap(search, in: app); search.typeText("电费"); assertSearchCount(2, in: app)
        XCTAssertTrue(ledgerRows(app).matching(NSPredicate(format: "label CONTAINS '163.40' ")).firstMatch.exists)
        snapshot("variable-bill-actual-amount", app)
    }

    func testV45OverspendLevelOnlyBreaksEven() {
        let app = application("v45-over"); app.launch()
        let over = displayedAmount(anyElement("availableFunds", in: app))
        tap(app.buttons["coverSaveLess"], in: app)
        tap(app.buttons["coverLevel"], in: app)
        XCTAssertTrue(app.buttons["coverLevel"].label.contains("只补平"))
        XCTAssertEqual(anyElement("amountSheetAmount", in: app).value as? String, String(format: "%.2f", Double(over) / 100))
        XCTAssertTrue(app.buttons["coverCushion"].label.contains("再留够"))
        tap(app.buttons["amountSheetDone"], in: app)
        assertGone(app.buttons["amountSheetDone"])
        XCTAssertEqual(displayedAmount(anyElement("availableFunds", in: app)), 0)
        XCTAssertFalse(app.buttons["coverSaveLess"].exists)
        tap(app.buttons["fundsFormula"], in: app)
        XCTAssertEqual(displayedAmount(anyElement("formulaRow_saving", in: app)), 200_000 - over)
        snapshot("overspend-level", app)
    }

    func testV45OverspendCushionUsesReserveAndRestoresDailyPace() {
        let app = application("v45-over"); app.launch()
        let over = displayedAmount(anyElement("availableFunds", in: app))
        tap(app.buttons["coverFromReserve"], in: app)
        tap(app.buttons["coverCushion"], in: app)
        XCTAssertTrue(app.buttons["coverCushion"].label.contains("再留够 5 天"))
        let amount = anyElement("amountSheetAmount", in: app)
        guard let text = amount.value as? String, let value = Double(text.replacingOccurrences(of: ",", with: "")) else {
            XCTFail("Cover sheet must expose its amount"); return
        }
        let covered = Int64((value * 100).rounded())
        XCTAssertGreaterThan(covered, over)
        tap(app.buttons["amountSheetDone"], in: app); assertGone(app.buttons["amountSheetDone"])
        XCTAssertEqual(displayedAmount(anyElement("availableFunds", in: app)), covered - over)
        XCTAssertTrue(anyElement("dailyPace", in: app).exists)
        XCTAssertFalse(app.buttons["coverFromReserve"].exists)
        tap(app.buttons["fundsFormula"], in: app)
        XCTAssertEqual(displayedAmount(anyElement("formulaRow_fixedSavings", in: app)), 500_000 - covered)
        XCTAssertEqual(displayedAmount(anyElement("formulaRow_saving", in: app)), 200_000)
        snapshot("overspend-reserve-cushion", app)
    }

    func testV45PaydayAmountConfirmationStartsNewCycle() {
        let app = application("v45-payday"); app.launch()
        let oldCycle = app.buttons["fundsFormula"].label
         tap(app.buttons["paydayArrived"], in: app)
        XCTAssertTrue(anyElement("amountSheetAmount", in: app).waitForExistence(timeout: 5))
        XCTAssertEqual(anyElement("amountSheetAmount", in: app).value as? String, "8010.00")
        pressAmount("8210", in: app)
        XCTAssertTrue(app.buttons["paydayExtraToSavings"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["paydayExtraToSavings"].isSelected)
        tap(app.buttons["amountSheetDone"], in: app); assertGone(app.buttons["amountSheetDone"])
        assertGone(app.buttons["paydayArrived"])
        XCTAssertTrue(anyElement("dailyPace", in: app).waitForExistence(timeout: 5))
        XCTAssertNotEqual(app.buttons["fundsFormula"].label, oldCycle)
        backToRoot(app); tap(app.buttons["tab_ledger"], in: app)
        let search = app.textFields["entriesSearch"]
        tap(search, in: app); search.typeText("工资"); assertSearchCount(1, in: app)
        XCTAssertTrue(ledgerRows(app).firstMatch.label.contains("8,210.00"))
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["fundsFormula"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["paydayArrived"].exists)
        snapshot("payday-started-new-cycle", app)
    }

    func testV45LeftoverKeepAndSaveResolveOnce() {
        for save in [false, true] {
            let app = application("v45-newcycle"); app.launch()
            let before = displayedAmount(anyElement("availableFunds", in: app))
            tap(app.buttons[save ? "leftoverSave" : "leftoverKeep"], in: app)
            assertGone(app.buttons["leftoverSave"]); assertGone(app.buttons["leftoverKeep"])
            XCTAssertEqual(displayedAmount(anyElement("availableFunds", in: app)), before - (save ? 21_200 : 0))
            tap(app.buttons["fundsFormula"], in: app)
            XCTAssertEqual(displayedAmount(anyElement("formulaRow_fixedSavings", in: app)), 500_000 + (save ? 21_200 : 0))
            app.terminate(); app.launch()
            XCTAssertTrue(app.buttons["fundsFormula"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["leftoverSave"].exists); XCTAssertFalse(app.buttons["leftoverKeep"].exists)
            XCTAssertEqual(displayedAmount(anyElement("availableFunds", in: app)), before - (save ? 21_200 : 0))
            app.terminate()
        }
    }

    func testV45GapReconcileAddsOneUnitemizedExpense() {
        let app = application("v45-gap"); app.launch()
        let before = displayedAmount(anyElement("availableFunds", in: app))
        tap(app.buttons["openReconcile"], in: app)
        let bank = app.textFields["reconcileField_合成银行卡"], wallet = app.textFields["reconcileField_微信零钱"]
        XCTAssertTrue(bank.waitForExistence(timeout: 5))
        let walletBalance = wallet.value as? String
        guard let value = bank.value as? String, let balance = Double(value.replacingOccurrences(of: ",", with: "")) else {
            XCTFail("Reconciliation must expose the book balance"); return
        }
        replaceText(String(format: "%.2f", balance - 412), in: bank, app: app)
        XCTAssertEqual(wallet.value as? String, walletBalance)
        let result = anyElement("reconcileResult", in: app)
        XCTAssertTrue(result.waitForExistence(timeout: 5)); XCTAssertTrue(result.label.contains("412.00"))
        tap(app.buttons["reconcileApply"], in: app); assertGone(anyElement("reconcileSheet", in: app))
        XCTAssertEqual(displayedAmount(anyElement("availableFunds", in: app)), before - 41_200)
        XCTAssertFalse(app.buttons["openReconcile"].exists)
        tap(app.buttons["tab_ledger"], in: app)
        let search = app.textFields["entriesSearch"]
        tap(search, in: app); search.typeText("没细记"); assertSearchCount(1, in: app)
        XCTAssertEqual(ledgerRows(app).count, 1)
        XCTAssertTrue(ledgerRows(app).firstMatch.label.contains("412.00"))
        snapshot("reconcile-one-unitemized-entry", app)
    }

    func testV45CategoryGridOutlinesHistoryHintUntilSelected() {
        let app = application("v45-entry-history"); app.launch(); tap(addEntryTab(app), in: app)
        let cells = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'entryCategory_' "))
        XCTAssertTrue(app.buttons["entryCategoryMore"].waitForExistence(timeout: 5))
        XCTAssertEqual(cells.count, 9)
        XCTAssertEqual(app.buttons["entryCategoryMore"].label, "全部")
        let field = app.textFields["entryPurpose"]
        tap(field, in: app); field.typeText("合成咖啡\n")
        let hint = app.buttons["entryCategory_餐饮"]
        let outlined = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == '建议' AND selected == false"), object: hint)
        XCTAssertEqual(XCTWaiter.wait(for: [outlined], timeout: 5), .completed)
        tap(hint, in: app)
        XCTAssertTrue(hint.isSelected)
        XCTAssertNotEqual(hint.value as? String, "建议")
        snapshot("category-hint-selected-by-person", app)
    }

    func testV45BigPurchaseFromReserveKeepsCycleAvailable() {
        let app = application("v45-home"); app.launch()
        let before = displayedAmount(anyElement("availableFunds", in: app))
        tap(addEntryTab(app), in: app); pressAmount("1200", in: app)
        XCTAssertTrue(anyElement("bigPurchaseDays", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["bigFromCycle"].isSelected)
        tap(app.buttons["bigFromReserve"], in: app)
        XCTAssertTrue(app.buttons["bigFromReserve"].isSelected)
        let field = app.textFields["entryPurpose"]
        tap(field, in: app); field.typeText("合成大衣\n")
        tap(app.buttons["entryCategory_购物"], in: app); tap(app.buttons["saveQuickEntry"], in: app)
        assertGone(app.buttons["saveQuickEntry"])
        XCTAssertEqual(displayedAmount(anyElement("availableFunds", in: app)), before)
        tap(app.buttons["fundsFormula"], in: app)
        XCTAssertEqual(displayedAmount(anyElement("formulaRow_fixedSavings", in: app)), 380_000)
        backToRoot(app); tap(app.buttons["tab_ledger"], in: app)
        let search = app.textFields["entriesSearch"]
        tap(search, in: app); search.typeText("合成大衣"); assertSearchCount(1, in: app)
        XCTAssertTrue(ledgerRows(app).firstMatch.label.contains("1,200.00"))
        snapshot("big-purchase-from-reserve", app)
    }

    func testV45LongPressAddRepeatsRecentExpenseAndCanUndo() {
        let app = application("v45-entry-history", keepingUndo: true); app.launch()
        tap(app.buttons["tab_ledger"], in: app)
        let search = app.textFields["entriesSearch"]
        tap(search, in: app); search.typeText("合成咖啡"); assertSearchCount(3, in: app)
        tap(app.buttons["entriesSearchCancel"], in: app)
        addEntryTab(app).press(forDuration: 0.8)
        XCTAssertTrue(anyElement("quickRepeatMenu", in: app).waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["quickReceipt"].exists)
        XCTAssertTrue(app.buttons["quickRepeat_0"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["quickRepeat_0"].label.contains("合成咖啡"))
        tap(app.buttons["quickRepeat_0"], in: app)
        assertGone(anyElement("quickRepeatMenu", in: app)); XCTAssertFalse(app.buttons["saveQuickEntry"].exists)
        tap(search, in: app); search.typeText("合成咖啡"); assertSearchCount(4, in: app)
        tap(app.buttons["entriesSearchCancel"], in: app)
        tapUndo(messagePrefix: "已记下 · 合成咖啡", in: app)
        tap(search, in: app); search.typeText("合成咖啡"); assertSearchCount(3, in: app)
        snapshot("quick-repeat-undone", app)
    }

    func testV45SavingTabOpensReserveHistoryAndEditsTotal() {
        let app = application("v45-home"); app.launch(); tap(app.buttons["tab_saving"], in: app)
        tap(app.buttons["openReserve"], in: app)
        XCTAssertTrue(anyElement("reservePage", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(anyElement("reserveLine_0", in: app).exists)
        tap(app.buttons["editReserveTotal"], in: app)
        XCTAssertTrue(anyElement("amountSheetAmount", in: app).waitForExistence(timeout: 5))
        pressAmount("7200", in: app); tap(app.buttons["saveReserveTotal"], in: app)
        assertGone(app.buttons["saveReserveTotal"])
        XCTAssertEqual(displayedAmount(anyElement("reserveTotal", in: app)), 720_000)
        XCTAssertTrue(anyElement("reserveLine_0", in: app).label.contains("调整"))
        backToRoot(app); assertSelectedTab("tab_saving", in: app)
        XCTAssertEqual(displayedAmount(anyElement("reserveTotal", in: app)), 720_000)
        snapshot("reserve-edited-history", app)
    }

    func testV45LedgerSwitchesModesAndSearchesAllMonths() {
        let app = application("round40"); app.launch(); tap(app.buttons["tab_ledger"], in: app)
        XCTAssertTrue(app.buttons["ledgerMode_detail"].isSelected)
        tap(app.buttons["ledgerMode_where"], in: app)
        XCTAssertTrue(anyElement("whereTotal", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["ledgerMode_where"].isSelected)
        tap(app.buttons["ledgerMode_detail"], in: app)
        let search = app.textFields["entriesSearch"]
        tap(search, in: app); search.typeText("合成跨月房租"); assertSearchCount(3, in: app)
        XCTAssertEqual(ledgerRows(app).count, 3)
        XCTAssertTrue(anyElement("entriesSearchTotal", in: app).label.contains("10,500.00"))
        tap(app.buttons["entriesSearchCancel"], in: app)
        XCTAssertTrue(app.buttons["ledgerMode_detail"].isSelected)
        snapshot("ledger-search-all-months", app)
    }

    func testV45YubaiAskRemembersRecentQuestion() {
        let app = application("v45-ask"); app.launch()
        ask("咖啡共花了多少钱？", in: app)
        XCTAssertTrue(app.staticTexts["askAnswer"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["askAnswer"].label.contains("32.00"))
        backToRoot(app); assertSelectedTab("tab_yubai", in: app)
        let recent = app.buttons["recentQuestion_0"]
        XCTAssertTrue(recent.waitForExistence(timeout: 5)); XCTAssertTrue(recent.label.contains("咖啡共花了多少钱？"))
        app.terminate(); app.launch(); tap(app.buttons["tab_yubai"], in: app)
        tap(recent, in: app)
        XCTAssertTrue(app.staticTexts["askAnswer"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["askAnswer"].label.contains("32.00"))
        snapshot("recent-question-reopened", app)
    }

    func testV45BudgetAddsFirstPartFromFormula() {
        let app = application("manual"); app.launch(); tap(app.buttons["fundsFormula"], in: app)
        backToRoot(app); openSettings(app); tap(app.buttons["openSpendingParts"], in: app)
        XCTAssertTrue(anyElement("spendingPartsPage", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(anyElement("budgetTotal", in: app).exists)
        tap(app.buttons["addBudgetPart"], in: app)
        let alert = app.alerts["加一项"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        tap(alert.textFields.firstMatch, in: app); alert.textFields.firstMatch.typeText("合成餐饮预算")
        tap(alert.buttons.matching(NSPredicate(format: "label == '好' ")).firstMatch, in: app)
        XCTAssertTrue(anyElement("budgetPart_合成餐饮预算", in: app).waitForExistence(timeout: 5))
        snapshot("first-budget-part", app)
    }


    // MARK: v45 second batch · formula, category, payback, split and dates


    func testV45CategoryDetailComparesAndFiltersExactEntriesIncludingRefund() {
        let app = application("v45-category"); app.launch(); openWhere(app)
        tap(app.buttons["insightCategory_0"], in: app)
        XCTAssertTrue(anyElement("whereCategoryPage", in: app).waitForExistence(timeout: 5))
        XCTAssertEqual(displayedAmount(anyElement("whereCategorySummary", in: app)), 5500)
        XCTAssertTrue(anyElement("whereCategoryCycles", in: app).exists)
        XCTAssertTrue(anyElement("whereCategoryPlaces", in: app).exists)
        XCTAssertTrue(app.buttons["whereCategoryEntries"].label.contains("3 笔"))
        tap(app.buttons["whereCategoryEntries"], in: app)
        assertSearchCount(3, in: app)
        XCTAssertEqual(ledgerRows(app).count, 3)
        XCTAssertTrue(app.buttons["clearLedgerCategory"].exists)
        XCTAssertFalse(ledgerRows(app).matching(NSPredicate(format: "label CONTAINS '合成餐饮备注' ")).firstMatch.exists)
        snapshot("category-exact-records", app)
    }

    func testV45ReservePaybackRaisesMonthlySavingAndRemembersTheAnswer() {
        let app = application("v45-payback"); app.launch()
        tap(app.buttons["tab_saving"], in: app); tap(app.buttons["openReserve"], in: app)
        let accept = app.buttons["reservePaybackAccept"]
        scrollToVisible(accept, in: app); XCTAssertTrue(accept.label.contains("400.00"))
        tap(accept, in: app)
        assertGone(anyElement("reservePaybackOffer", in: app))
        XCTAssertTrue(anyElement("reservePaybackProgress", in: app).exists)
        backToRoot(app); tap(app.buttons["openSavings"], in: app)
        XCTAssertEqual(displayedAmount(anyElement("monthlyPaybackAmount", in: app)), 40_000)
        XCTAssertEqual(displayedAmount(anyElement("monthlySavingTotal", in: app)), 240_000)
        backToRoot(app); tap(app.buttons["tab_now"], in: app); tap(app.buttons["fundsFormula"], in: app)
        XCTAssertEqual(displayedAmount(anyElement("formulaRow_saving", in: app)), 240_000)
        app.terminate(); app.launch()
        tap(app.buttons["tab_saving"], in: app); tap(app.buttons["openReserve"], in: app)
        XCTAssertTrue(anyElement("reservePaybackProgress", in: app).waitForExistence(timeout: 5))
        XCTAssertFalse(anyElement("reservePaybackOffer", in: app).exists)
        snapshot("reserve-payback-persisted", app)
    }

    func testV45ReserveCoverCanDeclinePaybackOnce() {
        let app = application("v45-over"); app.launch()
        tap(app.buttons["coverFromReserve"], in: app); tap(app.buttons["coverLevel"], in: app)
        tap(app.buttons["amountSheetDone"], in: app); assertGone(app.buttons["amountSheetDone"])
        tap(app.buttons["tab_saving"], in: app); tap(app.buttons["openReserve"], in: app)
        let decline = app.buttons["reservePaybackDecline"]
        scrollToVisible(decline, in: app); tap(decline, in: app)
        assertGone(anyElement("reservePaybackOffer", in: app))
        XCTAssertFalse(anyElement("reservePaybackProgress", in: app).exists)
        app.terminate(); app.launch()
        tap(app.buttons["tab_saving"], in: app); tap(app.buttons["openReserve"], in: app)
        XCTAssertTrue(anyElement("reservePage", in: app).waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["reservePaybackDecline"].exists)
        snapshot("reserve-cover-payback-declined", app)
    }

    func testV45UnitemizedSplitsIntoTwoEntriesAndUndoRestoresOriginal() {
        let app = application("v45-split", keepingUndo: true); app.launch()
        let before = displayedAmount(anyElement("availableFunds", in: app))
        tap(app.buttons["tab_ledger"], in: app)
        let search = app.textFields["entriesSearch"]
        tap(search, in: app); search.typeText("没细记"); assertSearchCount(1, in: app)
        let originalID = ledgerRows(app).firstMatch.identifier
        tap(ledgerRows(app).firstMatch, in: app); tap(app.buttons["entryDetailSplit"], in: app)
        pressAmount("100", in: app); tap(app.buttons["entryCategory_餐饮"], in: app)
        tap(app.buttons["splitUnitemizedAdd"], in: app)
        pressAmount("312", in: app); tap(app.buttons["entryCategory_交通"], in: app)
        tap(app.buttons["splitUnitemizedAdd"], in: app)
        XCTAssertEqual(displayedAmount(anyElement("splitUnitemizedRemaining", in: app)), 0)
        tap(app.buttons["splitUnitemizedDone"], in: app)
        assertGone(anyElement("splitUnitemizedScroll", in: app))
        tapUndo(messagePrefix: "已记下 · 2 笔", exact: true, in: app)
        assertSearchCount(1, in: app)
        XCTAssertEqual(ledgerRows(app).firstMatch.identifier, originalID)
        XCTAssertTrue(ledgerRows(app).firstMatch.label.contains("412.00"))
        tap(app.buttons["entriesSearchCancel"], in: app); tap(app.buttons["tab_now"], in: app)
        XCTAssertEqual(displayedAmount(anyElement("availableFunds", in: app)), before)
        snapshot("unitemized-split-undone", app)
    }

    func testV45FutureEntryWaitsForItsDayAndCanBeEditedToToday() {
        let app = application("v45-home"); app.launch()
        let before = displayedAmount(anyElement("availableFunds", in: app))
        let today = Date(), tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        tap(addEntryTab(app), in: app)
        app.buttons["entryDate_today"].press(forDuration: 0.7)
        selectV45CalendarDay(tomorrow, displayed: today, identifier: "entryCalendar", in: app)
        tap(app.buttons["entryDateDone"], in: app)
        pressAmount("32", in: app)
        let purpose = app.textFields["entryPurpose"]
        tap(purpose, in: app); purpose.typeText("合成未来餐")
        tap(app.buttons["entryCategory_餐饮"], in: app); tap(app.buttons["saveQuickEntry"], in: app)
        assertGone(app.buttons["saveQuickEntry"])
        XCTAssertEqual(displayedAmount(anyElement("availableFunds", in: app)), before)
        tap(app.buttons["tab_ledger"], in: app)
        let search = app.textFields["entriesSearch"]
        tap(search, in: app); search.typeText("合成未来餐"); assertSearchCount(1, in: app)
        let row = ledgerRows(app).firstMatch, entryID = row.identifier
        XCTAssertEqual(row.value as? String, "未来"); tap(row, in: app)
        tap(app.buttons["editEntryDate"], in: app)
        selectV45CalendarDay(today, displayed: tomorrow, identifier: "entryCalendar", in: app)
        tap(app.buttons["entryDateDone"], in: app); tap(app.buttons["saveEditedEntry"], in: app)
        assertGone(app.buttons["saveEditedEntry"])
        XCTAssertEqual(ledgerRows(app).firstMatch.identifier, entryID)
        XCTAssertEqual(ledgerRows(app).firstMatch.value as? String ?? "", "")
        tap(app.buttons["entriesSearchCancel"], in: app); tap(app.buttons["tab_now"], in: app)
        XCTAssertEqual(displayedAmount(anyElement("availableFunds", in: app)), before - 3200)
        snapshot("future-entry-posting-date", app)
    }

    func testV45BillMoveChangesOneOccurrenceAndCanReturnToUsualDay() {
        let app = application("v45-bill"); app.launch()
        let bill = homeBillCheck("话费和宽带", in: app)
        scrollToVisible(bill, in: app)
        let original = bill.value as? String
        bill.press(forDuration: 0.8); tap(app.buttons["billMenu_move"], in: app)
        XCTAssertTrue(anyElement("billMoveSheet", in: app).waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["fixedFlowTitle"].exists)
        let today = Date(), target = Calendar.current.date(byAdding: .day, value: 2, to: Date())!
        selectV45CalendarDay(target, displayed: today, identifier: "billMoveCalendar", in: app)
        tap(app.buttons["billMoveDone"], in: app); assertGone(anyElement("billMoveSheet", in: app))
        XCTAssertNotEqual(bill.value as? String, original)
        backToRoot(app); scrollToVisible(bill, in: app)
        bill.press(forDuration: 0.8); tap(app.buttons["billMenu_move"], in: app)
        tap(app.buttons["billMoveClear"], in: app); assertGone(anyElement("billMoveSheet", in: app))
        XCTAssertEqual(bill.value as? String, original)
        snapshot("bill-one-occurrence-restored", app)
    }


    private func selectV45CalendarDay(_ target: Date, displayed: Date, identifier: String, in app: XCUIApplication) {
        let calendar = Calendar.current
        let from = calendar.dateComponents([.year, .month], from: displayed)
        let to = calendar.dateComponents([.year, .month], from: target)
        let months = (to.year! - from.year!) * 12 + to.month! - from.month!
        if months != 0 {
            for _ in 0..<abs(months) { tap(app.buttons[identifier + (months > 0 ? "Next" : "Previous")], in: app) }
        }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "zh_CN"); formatter.dateFormat = "yyyy-MM-dd"
        tap(app.buttons[identifier + "Day_" + formatter.string(from: target)], in: app)
    }

    // MARK: v45 smoke tests: one per fixture script. Open the page, assert the key identifiers exist and are reachable.

    private func assertV45(_ identifiers: [String], absent: [String] = [], in app: XCUIApplication,
                           file: StaticString = #filePath, line: UInt = #line) {
        assertSelectedTab("tab_now", in: app, file: file, line: line)
        for identifier in identifiers {
            let element = anyElement(identifier, in: app)
            XCTAssertTrue(element.waitForExistence(timeout: 10), identifier, file: file, line: line)
        }
        for identifier in absent { XCTAssertFalse(anyElement(identifier, in: app).exists, identifier, file: file, line: line) }
        XCTAssertTrue(addEntryTab(app).isHittable, file: file, line: line)
        XCTAssertTrue(app.buttons["openSettings"].isHittable, file: file, line: line)
    }

    func testHomeShowsAvailableDailyAndRecentEntries() {
        let app = application("v45-home"); app.launch()
        assertV45(["fundsFormula", "availableFunds", "dailyPace", "todayEntries"], in: app)
        XCTAssertTrue(app.buttons["fundsFormula"].label.contains("1,564.00"))
        snapshot("v45-home", app)
    }


    func testV45OverOffersBothCoverRows() {
        let app = application("v45-over"); app.launch()
        assertV45(["fundsFormula", "coverSaveLess", "coverFromReserve"], absent: ["dailyPace"], in: app)
        snapshot("v45-over", app)
    }

    func testV45BillDueCardOffersPaidAndNotYet() {
        let app = application("v45-bill"); app.launch()
        assertV45(["fundsFormula", "billDuePaid", "billDueNotYet"], in: app)
        snapshot("v45-bill", app)
    }

    func testV45PaydayCardOffersArrivedAndNotYet() {
        let app = application("v45-payday"); app.launch()
        assertV45(["fundsFormula", "paydayArrived", "paydayNotYet"], in: app)
        snapshot("v45-payday", app)
    }

    func testV45LatePaydayKeepsTheAskAndHidesPace() {
        let app = application("v45-late"); app.launch()
        assertV45(["fundsFormula", "paydayArrived", "paydayNotYet"], absent: ["dailyPace"], in: app)
        snapshot("v45-late", app)
    }

    func testV45NewCycleAsksWhatToDoWithTheLeftover() {
        let app = application("v45-newcycle"); app.launch()
        assertV45(["fundsFormula", "leftoverSave", "leftoverKeep"], in: app)
        snapshot("v45-newcycle", app)
    }

    func testV45GapOffersReconcile() {
        let app = application("v45-gap"); app.launch()
        assertV45(["fundsFormula", "openReconcile"], in: app)
        snapshot("v45-gap", app)
    }

    func testNewLedgerShowsFirstEntryCardWithoutDaily() {
        let app = application("v45-new"); app.launch()
        assertV45(["fundsFormula", "firstUseCard"], absent: ["dailyPace"], in: app)
        snapshot("v45-new", app)
    }
}

/// The same Foundation-only source is compiled into the app and this test bundle.
final class MotionStateTests: XCTestCase {
    func testMotionClaimsSurviveViewLifetimesAndStayIndependent() {
        var session = MotionSessionState()
        XCTAssertFalse(session.contains("receipt"))
        XCTAssertTrue(session.claim("receipt"))
        XCTAssertTrue(session.contains("receipt"))
        XCTAssertFalse(session.claim("receipt"))
        XCTAssertTrue(session.claim("donut"))
        var nextLaunch = MotionSessionState()
        XCTAssertTrue(nextLaunch.claim("receipt"))
    }
    func testTabDirectionAndReselection() {
        XCTAssertEqual(MotionSessionState.direction(from: 0, to: 2), 1)
        XCTAssertEqual(MotionSessionState.direction(from: 2, to: 1), -1)
        XCTAssertEqual(MotionSessionState.direction(from: 1, to: 1), 0)
    }
    func testOnlyNewActiveEntriesTriggerSaveAndMissingActiveEntriesTriggerDeletion() {
        let old = UUID(), added = UUID(), alreadyDeleted = UUID()
        let change = MotionEntryChange(previous: [old, alreadyDeleted], previousActive: [old], currentActive: [added, alreadyDeleted])
        XCTAssertEqual(change.saved, [added])
        XCTAssertEqual(change.deleted, [old])
        let edit = MotionEntryChange(previous: [old], previousActive: [old], currentActive: [old])
        XCTAssertTrue(edit.saved.isEmpty); XCTAssertTrue(edit.deleted.isEmpty)
    }
}
