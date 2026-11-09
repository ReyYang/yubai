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
    func testSalaryConfirmationFromLetterAndUndoRestoresCard() {
        let app = application("salary", keepingUndo: true); app.launch()
        openInbox(in: app)
        tap(app.buttons["confirmSalary"], in: app)
        assertGone(app.buttons["confirmSalary"])
        tapUndo(messagePrefix: "工资已加到会回来的账单", exact: true, in: app)
        XCTAssertTrue(app.buttons["confirmSalary"].waitForExistence(timeout: 5))
    }

    func testConfirmedSalaryAppearsInFixedFlowsLaterGroup() {
        let app = application("salary"); app.launch(); openInbox(in: app, required: false)
        tap(app.buttons["confirmSalary"], in: app)
        assertGone(app.buttons["confirmSalary"])
        let day = Calendar(identifier: .gregorian).component(.day, from: Date())
        openFixedBills(app)
        let later = app.descendants(matching: .any).matching(identifier: "fixedFlowLater").firstMatch
        let income = app.descendants(matching: .any).matching(identifier: "fixedFlowIncomeCard").firstMatch
        // Confirmation schedules the next payday strictly after today.
        if day >= 10 {
            XCTAssertTrue(later.waitForExistence(timeout: 5))
            let rows = later.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'fixedFlowLater_' "))
            let row = rows.firstMatch
            scrollToVisible(row, in: app, scroll: app.scrollViews["fixedFlowsScroll"])
            XCTAssertEqual(rows.count, 1)
            XCTAssertTrue(later.staticTexts["以后"].exists)
            XCTAssertTrue(row.staticTexts["工资"].exists)
            XCTAssertTrue(row.staticTexts["+8,000.00"].exists)
            XCTAssertTrue(row.staticTexts.matching(NSPredicate(format: "label CONTAINS '每月10日'")).firstMatch.exists)
            XCTAssertFalse(income.staticTexts["工资"].exists)
            tap(row, in: app)
            XCTAssertTrue(app.buttons["fixedFlowSchedule"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["改账单"].exists)
            XCTAssertEqual(app.textFields["fixedFlowTitle"].value as? String, "工资")
            XCTAssertFalse(app.buttons["saveManualSheet"].isEnabled)
            tap(app.buttons["cancelManualSheet"], in: app)
            assertGone(app.buttons["fixedFlowSchedule"])
            XCTAssertTrue(app.navigationBars["会回来的账单"].exists)
        } else {
            XCTAssertTrue(income.waitForExistence(timeout: 5))
            let rows = income.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'fixedFlow_' "))
            let row = rows.firstMatch
            scrollToVisible(row, in: app, scroll: app.scrollViews["fixedFlowsScroll"])
            XCTAssertEqual(rows.count, 1)
            XCTAssertTrue(app.staticTexts["要收"].exists)
            XCTAssertTrue(row.staticTexts["工资"].exists)
            XCTAssertTrue(row.staticTexts["+8,000.00"].exists)
            XCTAssertTrue(row.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '10日 · '")).firstMatch.exists)
            XCTAssertFalse(later.staticTexts["工资"].exists)
            XCTAssertFalse(later.exists)
        }
        XCTAssertFalse(app.staticTexts["这个月还没有会回来的账单"].exists)
        snapshot(day >= 10 ? "salary-fixed-flows-later" : "salary-fixed-flows-income", app)
    }

    func testRejectedSalaryStaysDismissedAfterRelaunch() {
        let app = application("salary"); app.launch(); openInbox(in: app, required: false)
        tap(app.buttons["rejectSalary"], in: app)
        assertGone(app.buttons["confirmSalary"])
        app.terminate(); app.launch(); openInbox(in: app, required: false)
        XCTAssertTrue(app.buttons["openCloudAI"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["confirmSalary"].exists)
        XCTAssertTrue(app.staticTexts["6 笔还没分类"].exists)
    }

    func testLetterShowsSalaryAndImportsTogetherAndOpensTriage() {
        let app = application("salary"); app.launch(); openInbox(in: app)
        let salary = app.descendants(matching: .any).matching(identifier: "salaryCard").firstMatch
        let pending = app.descendants(matching: .any).matching(identifier: "pendingImportsCard").firstMatch
        XCTAssertTrue(salary.waitForExistence(timeout: 5)); XCTAssertTrue(pending.exists)
        tap(salary.buttons["dismissLetterCard"], in: app)
        assertGone(salary); XCTAssertTrue(pending.exists)
        tap(pending.buttons["classifyImportsManually"], in: app)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "letterTriage").firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["askYubai"].isHittable)
    }

    func testPendingImportsOrganizesOnlyAfterTapWithFakeTransport() {
        let app = application("salary"); app.launch(); openInbox(in: app, required: false)
        tap(app.buttons["rejectSalary"], in: app)
        tap(app.buttons["organizeImports"], in: app)
        tap(app.switches["打开云端智能"], in: app)
        tap(app.buttons["closeSheet"], in: app)
        let pending = app.descendants(matching: .any).matching(identifier: "pendingImportsCard").firstMatch
        XCTAssertTrue(app.buttons["organizeImports"].waitForExistence(timeout: 5))
        XCTAssertEqual(pending.value as? String, "requests=0")
        app.terminate(); app.launch(); openInbox(in: app, required: false)
        XCTAssertTrue(app.buttons["organizeImports"].waitForExistence(timeout: 10))
        XCTAssertEqual(pending.value as? String, "requests=0")
        tap(app.buttons["organizeImports"], in: app)
        assertGone(pending)
        app.terminate(); app.launch(); openInbox(in: app, required: false)
        XCTAssertTrue(app.buttons["fundsFormula"].waitForExistence(timeout: 10))
        XCTAssertFalse(pending.exists)
    }

    func testOrganizationSkipsUncertainGroupsAndFallbackPrecedesUncoveredInflows() {
        let app = application("salary")
        app.launchEnvironment["YUBAI_UI_ORGANIZATION_SCENARIO"] = "by-party"
        app.launch(); openInbox(in: app, required: false)
        tap(app.buttons["organizeImports"], in: app)
        let question = app.staticTexts["nowImportQuestion"]
        let fallback = app.staticTexts["unsortedQuestionTitle"]
        let summary = app.buttons["unknownInflowsSummary"]
        XCTAssertTrue(fallback.waitForExistence(timeout: 15))
        assertGone(app.buttons["stopOrganizing"])
        XCTAssertFalse(question.exists)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'homeImportAnswer_' ")).firstMatch.exists)
        XCTAssertTrue(fallback.waitForExistence(timeout: 5)); XCTAssertEqual(fallback.label, "9 笔还没分类")
        XCTAssertFalse(app.buttons["都是日常收支"].exists)
        XCTAssertFalse(app.buttons["稍后写用途"].exists)
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertTrue(summary.label.contains("6 笔进账没说来源"), "The classified personal incoming record must not get an unknown-inflow reminder")
        XCTAssertLessThan(fallback.frame.minY, summary.frame.minY)
        tap(summary, in: app)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "butlerCard_unknownInflow").firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["nowImportQuestion"].exists)
    }

    func testOrganizationIgnoresLegacyQuestionsThroughCompletionAndRelaunch() {
        let app = application("salary")
        app.launchEnvironment["YUBAI_UI_ORGANIZATION_SCENARIO"] = "questions-complete"
        app.launch(); openInbox(in: app, required: false)
        assertLegacyQuestionIsIgnoredDuringOrganization(app)
        assertGone(app.buttons["stopOrganizing"], timeout: 25)
        XCTAssertFalse(app.staticTexts["nowImportQuestion"].exists)
        XCTAssertFalse(app.staticTexts["unsortedQuestionTitle"].exists)
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "pendingImportsCard").firstMatch.exists)
        XCTAssertFalse(app.staticTexts["organizeError"].exists)
        app.terminate(); app.launch(); openInbox(in: app, required: false)
        XCTAssertTrue(app.buttons["fundsFormula"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["nowImportQuestion"].exists)
    }

    func testOrganizationStopKeepsClassificationsWithoutModelQuestionsAndRestoresIdleTimer() {
        let app = application("salary")
        app.launchEnvironment["YUBAI_UI_ORGANIZATION_SCENARIO"] = "questions-stop"
        app.launch()
        assertLegacyQuestionIsIgnoredDuringOrganization(app)
        tap(app.buttons["stopOrganizing"], in: app)
        assertGone(app.buttons["stopOrganizing"])
        XCTAssertFalse(app.staticTexts["nowImportQuestion"].exists)
        assertStoppedWithoutModelQuestionState(app)
        XCTAssertFalse(app.staticTexts["organizeError"].exists)
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["fundsFormula"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["nowImportQuestion"].exists)
        XCTAssertTrue(app.staticTexts["55 笔还没分类"].exists)
    }

    func testOrganizationFailureKeepsClassificationsWithoutModelQuestionsAndRestoresIdleTimer() {
        let app = application("salary")
        app.launchEnvironment["YUBAI_UI_ORGANIZATION_SCENARIO"] = "questions-fail"
        app.launch()
        assertLegacyQuestionIsIgnoredDuringOrganization(app)
        XCTAssertTrue(app.staticTexts["organizeError"].waitForExistence(timeout: 25))
        XCTAssertFalse(app.staticTexts["nowImportQuestion"].exists)
        assertStoppedWithoutModelQuestionState(app)
    }

    func testOrganizationRelaunchKeepsClassificationsWithoutModelQuestionsOrRestarting() {
        let app = application("salary")
        app.launchEnvironment["YUBAI_UI_ORGANIZATION_SCENARIO"] = "questions-stop"
        app.launch(); openInbox(in: app, required: false)
        assertLegacyQuestionIsIgnoredDuringOrganization(app)
        app.terminate(); app.launch(); openInbox(in: app, required: false)
        XCTAssertTrue(app.buttons["fundsFormula"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["nowImportQuestion"].exists)
        XCTAssertFalse(app.buttons["stopOrganizing"].exists)
        let pending = app.descendants(matching: .any).matching(identifier: "pendingImportsCard").firstMatch
        XCTAssertEqual(pending.value as? String, "requests=0;entries=70;classified=15;resent=0;questions=0;idle=0")
        XCTAssertTrue(pending.staticTexts["55 笔还没分类"].exists)
    }

    private func assertLegacyQuestionIsIgnoredDuringOrganization(_ app: XCUIApplication,
                                                                 file: StaticString = #filePath, line: UInt = #line) {
        tap(app.buttons["organizeImports"], in: app)
        let pending = app.descendants(matching: .any).matching(identifier: "pendingImportsCard").firstMatch
        let state = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@",
            "requests=3;entries=70;classified=15;resent=0;questions=0;idle=1"), object: pending)
        XCTAssertEqual(XCTWaiter.wait(for: [state], timeout: 10), .completed, file: file, line: line)
        let progress = app.descendants(matching: .any).matching(identifier: "organizeProgress").firstMatch
        XCTAssertEqual(progress.value as? String, "15/70", file: file, line: line)
        XCTAssertTrue(app.buttons["stopOrganizing"].exists, file: file, line: line)
        XCTAssertTrue(pending.staticTexts["整理时别离开余白"].exists, file: file, line: line)
        XCTAssertFalse(app.staticTexts["nowImportQuestion"].exists, file: file, line: line)
        XCTAssertFalse(app.staticTexts["unsortedQuestionTitle"].exists, file: file, line: line)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'homeImportAnswer_' ")).firstMatch.exists,
                       file: file, line: line)
    }

    private func assertStoppedWithoutModelQuestionState(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let pending = app.descendants(matching: .any).matching(identifier: "pendingImportsCard").firstMatch
        let state = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@",
            "requests=3;entries=70;classified=15;resent=0;questions=0;idle=0"), object: pending)
        XCTAssertEqual(XCTWaiter.wait(for: [state], timeout: 5), .completed, file: file, line: line)
        XCTAssertTrue(app.buttons["organizeImports"].isEnabled, file: file, line: line)
        XCTAssertTrue(pending.staticTexts["55 笔还没分类"].exists, file: file, line: line)
    }

    func testFallbackGroupsByPartyAppliesCategoryAndUpdatesRemainingCount() {
        let app = application("salary")
        app.launchEnvironment["YUBAI_UI_ORGANIZATION_SCENARIO"] = "by-party"
        app.launch(); openInbox(in: app, required: false)
        tap(app.buttons["organizeImports"], in: app)
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
        XCTAssertFalse(app.buttons["unsortedUse_expense"].exists)
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
        tap(app.navigationBars.buttons["现在"], in: app)
        XCTAssertTrue(app.staticTexts["unsortedQuestionTitle"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["unsortedQuestionTitle"].label, "3 笔还没分类")
        app.terminate(); app.launch(); openInbox(in: app, required: false)
        XCTAssertTrue(app.staticTexts["unsortedQuestionTitle"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["unsortedQuestionTitle"].label, "3 笔还没分类")
    }

    func testTwoStepCategoryPickerExpandsCollapsesAndAppliesSmallItem() {
        let app = application("salary")
        app.launchEnvironment["YUBAI_UI_ORGANIZATION_SCENARIO"] = "by-party"
        app.launch(); openInbox(in: app, required: false); tap(app.buttons["organizeImports"], in: app)
        XCTAssertTrue(app.buttons["quickSortUnsorted"].waitForExistence(timeout: 15))
        tap(app.buttons["quickSortUnsorted"], in: app)
        let progress = app.staticTexts["quickSortProgress"]
        tap(app.buttons["quickSortCategory_美容个护"], in: app)
        let sub = app.buttons["quickSortSubcategory_美容个护/理发"]
        XCTAssertTrue(sub.exists); XCTAssertEqual(progress.label, "0/2")
        tap(app.buttons["quickSortCategory_美容个护"], in: app)
        XCTAssertFalse(sub.exists); XCTAssertEqual(progress.label, "0/2")
        tap(app.buttons["quickSortCategory_美容个护"], in: app); tap(sub, in: app)
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == '1/2'"), object: progress)], timeout: 5), .completed)
        XCTAssertEqual(app.staticTexts["unsortedUndoMessage"].label, "合成对方甲 · 6 笔记为美容个护 · 理发")
        tap(app.buttons["quickSortUndo"], in: app)
        XCTAssertEqual(progress.label, "0/2")
    }

    func testCategoryAdditionDefaultsToExpandedMainAndAppliesGroup() {
        let app = application("salary")
        app.launchEnvironment["YUBAI_UI_ORGANIZATION_SCENARIO"] = "by-party"
        app.launch(); openInbox(in: app, required: false); tap(app.buttons["organizeImports"], in: app)
        XCTAssertTrue(app.buttons["quickSortUnsorted"].waitForExistence(timeout: 15))
        tap(app.buttons["quickSortUnsorted"], in: app)
        tap(app.buttons["quickSortCategory_美容个护"], in: app)
        tap(app.buttons["quickSortAdd"], in: app)
        XCTAssertTrue(app.buttons["美容个护"].isSelected)
        let field = app.textFields["categoryAdditionName"]
        tap(field, in: app); field.typeText("合成护理\n")
        let save = app.buttons["categoryAdditionSave"]
        XCTAssertEqual(save.label, "加上，这 6 笔记为合成护理"); tap(save, in: app)
        XCTAssertTrue(app.staticTexts["quickSortProgress"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["quickSortProgress"].label, "1/2")
        tap(app.buttons["quickSortUndo"], in: app)
        XCTAssertEqual(app.staticTexts["quickSortProgress"].label, "0/2")
        tap(app.buttons["quickSortCategory_美容个护"], in: app)
        XCTAssertTrue(app.buttons["quickSortSubcategory_美容个护/合成护理"].exists)
    }

    func testCategoryManagementAddsSmallItemDeletesItAndMergesWithUndo() {
        let app = application("salary"); app.launch()
        tap(app.buttons["tab_settings"], in: app); tap(app.buttons["openCategories"], in: app)
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

    func testQuickSortCategoryAdvancesAndUndoRestoresOnlyLastGroup() {
        let app = application("salary")
        app.launchEnvironment["YUBAI_UI_ORGANIZATION_SCENARIO"] = "by-party"
        app.launch(); openInbox(in: app, required: false)
        tap(app.buttons["organizeImports"], in: app)
        XCTAssertTrue(app.buttons["quickSortUnsorted"].waitForExistence(timeout: 15))
        tap(app.buttons["quickSortUnsorted"], in: app)
        let party = app.staticTexts["quickSortParty"]
        let progress = app.staticTexts["quickSortProgress"]
        XCTAssertTrue(party.waitForExistence(timeout: 5)); XCTAssertEqual(party.label, "合成对方甲")
        XCTAssertEqual(progress.label, "0/2"); XCTAssertEqual(progress.value as? String, "还没分类 9 笔")
        tap(app.buttons["quickSortCategory_餐饮"], in: app)
        tap(app.buttons["quickSortMainOnly_餐饮"], in: app)
        let advanced = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == '合成对方乙'"), object: party)
        XCTAssertEqual(XCTWaiter.wait(for: [advanced], timeout: 5), .completed)
        XCTAssertEqual(progress.label, "1/2"); XCTAssertEqual(progress.value as? String, "还没分类 3 笔")
        XCTAssertFalse(app.staticTexts["toastMessage"].exists, "Only the dedicated undo bar should show")
        XCTAssertEqual(app.staticTexts["unsortedUndoMessage"].label, "合成对方甲 · 6 笔记为餐饮")
        tap(app.buttons["quickSortUndo"], in: app)
        let restored = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == '合成对方甲'"), object: party)
        XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 5), .completed)
        XCTAssertEqual(progress.label, "0/2"); XCTAssertEqual(progress.value as? String, "还没分类 9 笔")
        tap(app.buttons["quickSortCategory_餐饮"], in: app)
        tap(app.buttons["quickSortMainOnly_餐饮"], in: app)
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == '合成对方乙'"), object: party)], timeout: 5), .completed)
        tap(app.buttons["quickSortCategory_交通"], in: app)
        tap(app.buttons["quickSortMainOnly_交通"], in: app)
        XCTAssertTrue(app.navigationBars["现在"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["unsortedQuestionTitle"].exists)
        tap(app.buttons["quickSortUndo"], in: app)
        XCTAssertTrue(app.staticTexts["unsortedQuestionTitle"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["unsortedQuestionTitle"].label, "3 笔还没分类", "Undo of the final group must keep the earlier group classified")
    }

    func testQuickSortSkipRotatesAndDetailsReturnToCurrentGroup() {
        let app = application("salary")
        app.launchEnvironment["YUBAI_UI_ORGANIZATION_SCENARIO"] = "by-party"
        app.launch(); openInbox(in: app, required: false)
        tap(app.buttons["organizeImports"], in: app)
        XCTAssertTrue(app.buttons["quickSortUnsorted"].waitForExistence(timeout: 15))
        tap(app.buttons["quickSortUnsorted"], in: app)
        let party = app.staticTexts["quickSortParty"]
        XCTAssertTrue(party.waitForExistence(timeout: 5))
        tap(app.buttons["quickSortSkip"], in: app)
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == '合成对方乙'"), object: party)], timeout: 5), .completed)
        tap(app.buttons["quickSortGroupDetails"], in: app)
        XCTAssertTrue(app.buttons["applyUnsortedGroup"].waitForExistence(timeout: 5))
        tap(app.navigationBars.buttons["一个个分"], in: app)
        XCTAssertTrue(party.waitForExistence(timeout: 5)); XCTAssertEqual(party.label, "合成对方乙")
        tap(app.buttons["quickSortSkip"], in: app)
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == '合成对方甲'"), object: party)], timeout: 5), .completed)
        tap(app.navigationBars.buttons["现在"], in: app)
        tap(app.buttons["quickSortUnsorted"], in: app)
        XCTAssertTrue(party.waitForExistence(timeout: 5)); XCTAssertEqual(party.label, "合成对方甲")
        XCTAssertEqual(app.staticTexts["quickSortProgress"].label, "0/2")
    }

    func testUnsortedMultiSelectAppliesAllGroupsWithOneUndo() {
        let app = application("salary", keepingUndo: true)
        app.launchEnvironment["YUBAI_UI_ORGANIZATION_SCENARIO"] = "by-party"
        app.launch(); openInbox(in: app, required: false)
        tap(app.buttons["organizeImports"], in: app)
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
        XCTAssertTrue(app.navigationBars["现在"].waitForExistence(timeout: 5))
        XCTAssertFalse(count.exists); XCTAssertFalse(apply.exists)
        XCTAssertFalse(app.staticTexts["unsortedQuestionTitle"].exists)
        XCTAssertEqual(app.staticTexts["unsortedUndoMessage"].label, "2 组 · 9 笔记为餐饮")
        XCTAssertFalse(app.staticTexts["toastMessage"].exists)
        tap(app.buttons["quickSortUndo"], in: app)
        XCTAssertTrue(app.staticTexts["unsortedQuestionTitle"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["unsortedQuestionTitle"].label, "9 笔还没分类")
        tap(app.buttons["groupUnsortedByParty"], in: app)
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == '9'"), object: count)], timeout: 5), .completed)
        XCTAssertTrue(first.exists); XCTAssertTrue(second.exists)
    }

    func testUnsortedManyGroupsBatchApplyReturnsToVisibleHeaderAndUndoRestores() {
        let app = application("salary", keepingUndo: true)
        app.launchEnvironment["YUBAI_UI_ORGANIZATION_SCENARIO"] = "by-party-many"
        app.launch(); openInbox(in: app, required: false)
        tap(app.buttons["organizeImports"], in: app)
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
        let app = application("salary", keepingUndo: true)
        app.launchEnvironment["YUBAI_UI_ORGANIZATION_SCENARIO"] = "by-party-long"
        app.launch(); openInbox(in: app, required: false)
        tap(app.buttons["organizeImports"], in: app)
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
        XCTAssertTrue(app.navigationBars["现在"].waitForExistence(timeout: 5), "Final detail and list must each dismiss once")
    }

    func testQuickSortScrolledCardApplySkipAndUndoShowNextCardAtTop() {
        let app = application("salary", keepingUndo: true)
        app.launchEnvironment["YUBAI_UI_ORGANIZATION_SCENARIO"] = "by-party-long"
        app.launch(); openInbox(in: app, required: false)
        tap(app.buttons["organizeImports"], in: app)
        XCTAssertTrue(app.buttons["quickSortUnsorted"].waitForExistence(timeout: 15))
        tap(app.buttons["quickSortUnsorted"], in: app)
        let scroll = app.scrollViews["quickSortScroll"]
        let party = app.staticTexts["quickSortParty"]
        XCTAssertTrue(party.waitForExistence(timeout: 5)); XCTAssertEqual(party.label, "合成对方00")
        for _ in 0..<4 { scrollVertically(scroll, in: app) }
        XCTAssertFalse(party.isHittable)
        tap(app.buttons["quickSortSkip"], in: app)
        assertVisibleWithoutScrolling(party, label: "合成对方01", in: app, scroll: scroll)
        for _ in 0..<4 { scrollVertically(scroll, in: app) }
        XCTAssertFalse(party.isHittable)
        tap(app.buttons["quickSortSkip"], in: app)
        assertVisibleWithoutScrolling(party, label: "合成对方00", in: app, scroll: scroll)
        tap(app.buttons["quickSortCategory_合成分类23"], in: app, scroll: scroll)
        assertVisibleWithoutScrolling(party, label: "合成对方01", in: app, scroll: scroll)
        for _ in 0..<4 { scrollVertically(scroll, in: app) }
        XCTAssertFalse(party.isHittable)
        tap(app.buttons["quickSortUndo"], in: app)
        assertVisibleWithoutScrolling(party, label: "合成对方00", in: app, scroll: scroll)
        XCTAssertEqual(app.staticTexts["quickSortProgress"].label, "0/2")
    }

    func testFallbackGroupAppliesOnlyCheckedEntriesAndLeavesUncheckedEntryInPartyGroup() {
        let app = application("salary")
        app.launchEnvironment["YUBAI_UI_ORGANIZATION_SCENARIO"] = "by-party"
        app.launch(); openInbox(in: app, required: false)
        tap(app.buttons["organizeImports"], in: app)
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
        tap(app.navigationBars.buttons["现在"], in: app)
        XCTAssertEqual(app.staticTexts["unsortedQuestionTitle"].label, "4 笔还没分类")
        app.terminate(); app.launch(); openInbox(in: app, required: false)
        XCTAssertTrue(app.staticTexts["unsortedQuestionTitle"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["unsortedQuestionTitle"].label, "4 笔还没分类")
    }

    func testPendingImportsStopKeepsCompletedChunkAndRemainingCount() {
        let app = application("salary")
        app.launchEnvironment["YUBAI_UI_ORGANIZATION_SCENARIO"] = "stop-second"
        app.launch(); openInbox(in: app, required: false)
        let pending = app.descendants(matching: .any).matching(identifier: "pendingImportsCard").firstMatch
        XCTAssertTrue(pending.waitForExistence(timeout: 10))
        XCTAssertTrue(pending.staticTexts["70 笔还没分类"].exists)
        assertImportRequestState(pending, requests: 0, entries: 70, classified: 0)
        let details = pending.staticTexts.matching(NSPredicate(format: "label CONTAINS '合成工资卡'")).firstMatch.label
        tap(app.buttons["organizeImports"], in: app)
        let progress = app.descendants(matching: .any).matching(identifier: "organizeProgress").firstMatch
        let checkpoint = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == '15/70'"), object: progress)
        XCTAssertEqual(XCTWaiter.wait(for: [checkpoint], timeout: 10), .completed)
        XCTAssertTrue(pending.staticTexts["55 笔还没分类"].exists)
        XCTAssertTrue(pending.staticTexts["15 / 70"].exists)
        XCTAssertTrue(pending.staticTexts["整理时别离开余白"].exists)
        XCTAssertTrue(pending.staticTexts[details].exists)
        XCTAssertFalse(app.buttons["classifyImportsManually"].exists)
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "organizingImports").firstMatch.exists)
        assertImportRequestState(pending, requests: 3, entries: 70, classified: 15)
        snapshot("organization-progress", app)
        tap(app.buttons["stopOrganizing"], in: app)
        assertGone(progress)
        XCTAssertTrue(app.buttons["organizeImports"].isEnabled)
        XCTAssertTrue(app.buttons["classifyImportsManually"].exists)
        XCTAssertFalse(app.staticTexts["organizeError"].exists)
        XCTAssertTrue(pending.staticTexts["55 笔还没分类"].exists)
        assertImportRequestState(pending, requests: 3, entries: 70, classified: 15)
        app.terminate(); app.launch(); openInbox(in: app, required: false)
        XCTAssertTrue(pending.waitForExistence(timeout: 10))
        XCTAssertTrue(pending.staticTexts["55 笔还没分类"].exists)
        assertImportRequestState(pending, requests: 0, entries: 70, classified: 15)
    }

    func testPendingImportsSecondChunkFailureShowsReasonAndRetriesOnlyRemaining() {
        let app = application("salary")
        app.launchEnvironment["YUBAI_UI_ORGANIZATION_SCENARIO"] = "fail-second"
        app.launch(); openInbox(in: app, required: false)
        let pending = app.descendants(matching: .any).matching(identifier: "pendingImportsCard").firstMatch
        XCTAssertTrue(pending.waitForExistence(timeout: 10))
        let details = pending.staticTexts.matching(NSPredicate(format: "label CONTAINS '合成工资卡'")).firstMatch.label
        tap(app.buttons["organizeImports"], in: app)
        let error = app.staticTexts["organizeError"]
        XCTAssertTrue(error.waitForExistence(timeout: 10))
        XCTAssertEqual(error.label, "DeepSeek 返回错误（HTTP 503）。")
        XCTAssertTrue(pending.staticTexts["55 笔还没分类"].exists)
        XCTAssertTrue(pending.staticTexts[details].exists)
        XCTAssertTrue(app.buttons["organizeImports"].isEnabled)
        XCTAssertTrue(app.buttons["classifyImportsManually"].isEnabled)
        assertImportRequestState(pending, requests: 3, entries: 70, classified: 15)
        snapshot("organization-second-chunk-error", app)
        tap(app.buttons["organizeImports"], in: app)
        assertGone(error)
        let progress = app.descendants(matching: .any).matching(identifier: "organizeProgress").firstMatch
        let checkpoint = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == '30/55'"), object: progress)
        XCTAssertEqual(XCTWaiter.wait(for: [checkpoint], timeout: 15), .completed)
        XCTAssertTrue(pending.staticTexts["25 笔还没分类"].exists)
        // Retry saves two 15-row chunks; the next two requests contain only remaining IDs.
        assertImportRequestState(pending, requests: 7, entries: 70, classified: 45)
        assertGone(pending)
        app.terminate(); app.launch(); openInbox(in: app, required: false)
        XCTAssertTrue(app.buttons["fundsFormula"].waitForExistence(timeout: 10))
        XCTAssertFalse(pending.exists)
    }

    private func assertImportRequestState(_ card: XCUIElement, requests: Int, entries: Int, classified: Int,
                                          file: StaticString = #filePath, line: UInt = #line) {
        let value = "requests=\(requests);entries=\(entries);classified=\(classified);resent=0"
        let state = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: card)
        XCTAssertEqual(XCTWaiter.wait(for: [state], timeout: 5), .completed, file: file, line: line)
    }

    func testWelcomeCloudSettingsPersistThroughStatementOnboarding() {
        let app = application("welcome-import")
        let csv = "时间,收支,金额,名称,余额\n2001-01-02 12:00:00,支出,32.00,合成午餐,968.00\n"
        app.launchEnvironment["YUBAI_UI_STATEMENT"] = Data(csv.utf8).base64EncodedString()
        app.launch(); openInbox(in: app, required: false)
        let cloud = app.buttons["welcomeCloudAI"]
        tap(cloud, in: app)
        XCTAssertTrue(app.navigationBars["智能与隐私"].waitForExistence(timeout: 5))
        tap(app.switches["打开云端智能"], in: app)
        tap(app.buttons["closeSheet"], in: app)
        XCTAssertTrue(cloud.label.contains("已开"))
        XCTAssertFalse(app.buttons["tab_ledger"].exists)
        app.terminate(); app.launch(); openInbox(in: app, required: false)
        XCTAssertTrue(cloud.waitForExistence(timeout: 10)); XCTAssertTrue(cloud.label.contains("已开"))
        tap(app.buttons["招行储蓄卡"], in: app)
        tap(app.buttons["welcomeImportStatement"], in: app)
        XCTAssertTrue(app.staticTexts["welcomeStatementBalance"].waitForExistence(timeout: 10))
        tap(app.buttons["startLedger"], in: app)
        XCTAssertTrue(app.buttons["organizeImports"].waitForExistence(timeout: 10))
        let pending = app.descendants(matching: .any).matching(identifier: "pendingImportsCard").firstMatch
        XCTAssertEqual(pending.value as? String, "requests=0")
        XCTAssertFalse(app.buttons["openCloudAI"].exists)
    }

    func testSavingsOpensFromCalculationAndMeAndEditsWithKeypad() {
        let app = application("v42"); app.launch()
        tap(app.buttons["fundsFormula"], in: app)
        XCTAssertTrue(app.staticTexts["还能花怎么算"].waitForExistence(timeout: 5))
        tap(app.buttons["openSavings"], in: app)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "savingsPage").firstMatch.waitForExistence(timeout: 5))
        tap(app.buttons["editFixedSavings"], in: app)
        tap(app.buttons["keypad_2"], in: app); tap(app.buttons["keypad_0"], in: app)
        tap(app.buttons["saveSavingsAmount"], in: app)
        tap(app.buttons["ledgerBack"], in: app); tap(app.buttons["closeSheet"], in: app)
        tap(app.buttons["tab_settings"], in: app); tap(app.buttons["openSavings"], in: app)
        XCTAssertTrue(app.staticTexts.matching(identifier: "存着不动").firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["askYubai"].isHittable)
    }

    func testShareSavingsUsesIncomeAndCustomPercentage() {
        let app = application("v42-share"); app.launch()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS '进账留两成'")).firstMatch.waitForExistence(timeout: 5))
        tap(app.buttons["tab_settings"], in: app); tap(app.buttons["openSavings"], in: app)
        tap(app.buttons["三成"], in: app)
        tap(app.buttons["自定"], in: app)
        tap(app.buttons["keypad_2"], in: app); tap(app.buttons["keypad_5"], in: app)
        tap(app.buttons["saveSavingsAmount"], in: app)
        tap(app.buttons["ledgerBack"], in: app); tap(app.buttons["tab_ledger"], in: app)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS '进账留25%'")).firstMatch.waitForExistence(timeout: 5))
    }

    func testLargeEntryCanBecomeWishWithoutAddingLedgerEntryAndCanUndo() {
        let app = application("v42", keepingUndo: true); app.launch()
        let count = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'ledgerEntry_'")).count
        tap(addEntryTab(app), in: app)
        for key in ["1", "5", "0", "0"] { tap(app.buttons["keypad_" + key], in: app) }
        let field = app.textFields["entryPurpose"]
        tap(field, in: app); field.typeText("耳机\n")
        tap(app.buttons["saveEntryWish"], in: app)
        XCTAssertTrue(app.staticTexts["toastMessage"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'ledgerEntry_'")).count, count)
        tapUndo(messagePrefix: "已放进心愿单", exact: false, in: app)
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
        for tab in ["tab_ledger", "tab_insights", "tab_settings"] where app.buttons[tab].exists && app.buttons[tab].isSelected {
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
        if ["tab_ledger", "tab_insights", "tab_settings"].contains(identifier) { assertSelectedTab(identifier, in: app, file: file, line: line) }
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
                scrollVertically(container, in: app, file: file, line: line)
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
        for other in ["tab_ledger", "tab_insights", "tab_settings"] where other != identifier {
            XCTAssertFalse(app.buttons[other].isSelected, file: file, line: line)
        }
    }

    private func addEntryTab(_ app: XCUIApplication) -> XCUIElement {
        app.buttons["addEntry"]
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
        for identifier in ["tab_ledger", "tab_insights", "tab_settings", "addEntry"] {
            assertGone(app.buttons[identifier], file: file, line: line)
        }
    }

    private func openInbox(in app: XCUIApplication, required: Bool = true) {
        let chip = app.buttons["openLetterInbox"]
        if required { XCTAssertTrue(chip.waitForExistence(timeout: 10)) }
        else { _ = chip.waitForExistence(timeout: 2) }
        if chip.exists && chip.isHittable { tap(chip, in: app) }
    }

    private func openFixedBills(_ app: XCUIApplication) {
        while app.buttons["ledgerBack"].exists && app.buttons["ledgerBack"].isHittable { tap(app.buttons["ledgerBack"], in: app) }
        tap(app.buttons["tab_settings"], in: app)
        tap(app.buttons["openFixedFlows"], in: app)
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
        // The Chinese candidate/assistant area begins above the Keyboard AX frame.
        let inputTops = [keyboard, app.otherElements.matching(identifier: "inputView").firstMatch, app.otherElements.matching(identifier: "SystemInputAssistantView").firstMatch]
            .filter { $0.exists && !$0.frame.isEmpty }.map { $0.frame.minY }
        let inputTop = inputTops.min() ?? keyboard.frame.minY
        let startY = min(inputTop, frame.maxY) - 24
        XCTAssertGreaterThan(startY, frame.minY, file: file, line: line)
        let start = origin.withOffset(CGVector(dx: frame.midX - app.frame.minX, dy: startY - app.frame.minY))
        let end = origin.withOffset(CGVector(dx: frame.midX - app.frame.minX, dy: app.windows.firstMatch.frame.maxY - app.frame.minY - 24))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.3)
        assertGone(keyboard, file: file, line: line)
    }

    private func openPurchaseFixture(_ fixture: String, question: String = "想买双徒步鞋 899，该不该买？") -> XCUIApplication {
        let app = application(fixture); app.launch()
        tap(app.buttons["askYubai"], in: app)
        let input = app.descendants(matching: .any).matching(identifier: "askInput").firstMatch
        tap(input, in: app); input.typeText(question)
        tap(app.buttons["sendAsk"], in: app)
        return app
    }

    private func assertPurchaseVerdict(_ label: String, in app: XCUIApplication) {
        let verdict = app.staticTexts["purchaseVerdict"]
        XCTAssertTrue(verdict.waitForExistence(timeout: 10))
        XCTAssertEqual(verdict.label, label)
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
        XCTAssertTrue(app.buttons["放进心愿单 · 3 天后再问我"].exists)
        XCTAssertLessThanOrEqual(app.buttons["放进心愿单 · 3 天后再问我"].frame.height, 56)
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
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS '买了以后还能花' AND label CONTAINS '620'")).firstMatch.exists)
        snapshot("purchase-skip", app)
    }

    func testWishlistCoolScreenshotFixture() {
        let app = application("wishlist-cool"); app.launch()
        tap(app.buttons["tab_settings"], in: app)
        tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "心愿单")).firstMatch, in: app)
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
        tap(app.buttons["tab_settings"], in: app); tap(app.buttons["openWishlist"], in: app)
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
        // The profile tab always keeps the letter reachable, including Thu–Sun.
        tap(app.buttons["tab_settings"], in: app)
        tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "每周来信")).firstMatch, in: app)
        tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "每周来信")).firstMatch, in: app)
        XCTAssertTrue(app.staticTexts["这些还在用吗？"].waitForExistence(timeout: 5))
        for title in ["视频会员", "网盘", "健身 App", "这周省下", "一共省下"] { XCTAssertTrue(app.staticTexts[title].exists) }
        let body = app.staticTexts["letterBody"].label
        XCTAssertTrue(body.contains("还能花"))
        XCTAssertFalse(body.contains("比上周保持原样"))
        for duplicate in ["本周省下", "累计省下", "这些还在用吗"] { XCTAssertFalse(body.contains(duplicate)) }
        for day in [3, 12, 24] { XCTAssertTrue(app.staticTexts["每月 \(day) 日"].exists) }
        snapshot("letter-saving-subscriptions", app)
    }

    func testProfileRevisitScreenshotFixture() {
        let app = application("profile-revisit")
        app.launchEnvironment["YUBAI_UI_PROFILE_REPLY_DELAY"] = "3"
        app.launch()
        XCTAssertTrue(app.buttons["restrainNear"].waitForExistence(timeout: 5))
        tap(app.buttons["tab_settings"], in: app)
        tap(app.buttons["openProfile"], in: app)
        snapshot("profile-progress", app)
        tap(app.buttons["profileChatEntry"], in: app)
        XCTAssertTrue(app.buttons["最近花钱的感觉变了"].waitForExistence(timeout: 10))
        snapshot("profile-revisit-opening", app)
        let input = app.descendants(matching: .any).matching(identifier: "profileInput").firstMatch
        tap(input, in: app); input.typeText("外卖这周到上限了，但加班那几天真没办法")
        XCTAssertLessThanOrEqual(input.frame.height, 100)
        tap(app.buttons["sendProfile"], in: app)
        XCTAssertTrue(app.staticTexts["profileUserMessage_1"].waitForExistence(timeout: 1))
        XCTAssertEqual(app.staticTexts["profileUserMessage_1"].label, "外卖这周到上限了，但加班那几天真没办法")
        XCTAssertFalse((input.value as? String ?? "").contains("外卖这周"))
        XCTAssertFalse(app.staticTexts["profileAssistantMessage_2"].exists)
        snapshot("profile-revisit-just-sent", app)
        XCTAssertTrue(app.staticTexts["外卖这周已经 3 次了，加班的日子想怎么安排？"].waitForExistence(timeout: 10))
        snapshot("profile-revisit-reply", app)
    }

    func testSubcategoryScreenshotFixture() {
        let app = application("subcategory"); app.launch()
        tap(app.buttons["tab_insights"], in: app)
        tap(app.buttons["insightCategory_0"], in: app)
        assertPushedPage("购物 · 本月", in: app)
        XCTAssertTrue(app.staticTexts["其他"].exists)
        snapshot("shopping-subcategories", app)
        tap(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "运动户外")).firstMatch, in: app)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "徒步鞋")).firstMatch.waitForExistence(timeout: 5))
        snapshot("outdoor-records", app)
        tap(app.navigationBars.buttons["购物 · 本月"], in: app)
        tap(app.navigationBars.buttons["洞察"], in: app)
        tap(app.buttons["tab_settings"], in: app)
        tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "心愿单")).firstMatch, in: app)
        tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "买了 1 件")).firstMatch, in: app)
        tap(app.buttons["购买记录"], in: app)
        XCTAssertTrue(app.staticTexts["entryDetailTitle"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["entryDetailTitle"].label, "徒步鞋 · 京东")
        XCTAssertTrue(app.buttons["entrySubcategory"].label.contains("运动户外"))
        snapshot("entry-subcategory", app)
        tap(app.buttons["entrySubcategory"], in: app)
        XCTAssertTrue(app.buttons["运动户外"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["换主项"].exists)
        snapshot("subcategory-picker", app)
    }

    func testAskWithoutKeyDisablesComposerEvenWithScriptedReplies() {
        let app = application("ask")
        app.launchEnvironment["YUBAI_UI_TEST_CONFIGURED_KEY"] = "0"
        app.launch()
        tap(app.buttons["askYubai"], in: app)
        let input = app.descendants(matching: .any).matching(identifier: "askInput").firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 5)); XCTAssertFalse(input.isEnabled)
        for title in ["这周餐饮花了多少？", "想买一双 899 的鞋，该不该买？"] {
            XCTAssertTrue(app.buttons[title].exists); XCTAssertFalse(app.buttons[title].isEnabled)
        }
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label ENDSWITH %@", "够付吗？")).count, 0)
        let configure = app.buttons["configureAskKey"]
        XCTAssertTrue(configure.exists); XCTAssertTrue(configure.isEnabled)
        snapshot("ask-missing-key", app)
        tap(configure, in: app)
        XCTAssertTrue(app.navigationBars["智能与隐私"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.switches["打开云端智能"].value as? String, "1")
    }

    func testBoughtWishShowsStatusAndDateWithoutAskAgain() {
        let app = application("wish-bought"); app.launch()
        tap(app.buttons["tab_settings"], in: app)
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
        tap(app.navigationBars.buttons["我"], in: app); tap(app.buttons["tab_ledger"], in: app)
        XCTAssertTrue(app.buttons["fundsFormula"].label.contains("¥700.00"))
        XCTAssertFalse(app.buttons["todayEntries"].exists)
    }

    func testUndoReceiptDismissesAfterProductionLifetime() {
        let app = application("bills"); app.launch(); openFixedBills(app)
        XCTAssertNil(app.launchEnvironment["YUBAI_UI_TEST_KEEP_UNDO"])
        let check = app.buttons["付了 房租"], undo = app.buttons["undoLastChange"], message = app.staticTexts["toastMessage"]
        XCTAssertTrue(check.isHittable)
        let started = ProcessInfo.processInfo.systemUptime
        check.tap()
        XCTAssertTrue(undo.waitForExistence(timeout: 2)); XCTAssertTrue(undo.isHittable)
        XCTAssertEqual(message.label, "房租 300.00 已记下")
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
        tap(app.navigationBars.buttons["我"], in: app); tap(app.buttons["tab_ledger"], in: app)
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
        tap(app.navigationBars.buttons["我"], in: app); tap(app.buttons["tab_ledger"], in: app)
        XCTAssertTrue(app.buttons["fundsFormula"].label.contains("¥900.00"))
        XCTAssertFalse(app.buttons["todayEntries"].exists)
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

    func testFundsCalculationShowsFiveRowsAndSavingsLink() {
        let app = application("v42"); app.launch(); tap(app.buttons["fundsFormula"], in: app)
        for title in ["流动资金", "这个月到账", "这个月要攒", "已经花了", "还要付", "还能花"] { XCTAssertTrue(app.staticTexts[title].exists) }
        XCTAssertTrue(app.buttons["openSavings"].exists)
        XCTAssertFalse(app.buttons["askYubai"].isHittable)
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
        XCTAssertTrue(app.buttons["entryCategory_工资奖金"].exists); XCTAssertFalse(app.buttons["会员订阅"].exists)
        tap(app.buttons["entryCategory_工资奖金"], in: app)
        tap(app.buttons["要付"], in: app)
        XCTAssertEqual(category.value as? String, "其他支出")
        tap(app.buttons["cancelManualSheet"], in: app)
    }

    func testDueBillInLetterStillSettles() {
        let app = application("bills"); app.launch(); openInbox(in: app)
        let check = app.buttons["付了 房租"]
        XCTAssertTrue(check.waitForExistence(timeout: 5))
        tap(check, in: app); assertGone(check)
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

    func testFixedBillEditorUsesInstallmentsAndAccountGatesAutomaticRecording() {
        let app = application("bills"); app.launch(); openFixedBills(app)
        tap(app.buttons["addFixedFlow"], in: app)
        XCTAssertFalse(app.staticTexts["到什么时候"].exists)
        XCTAssertFalse(app.staticTexts["90 天里会先留出"].exists)
        XCTAssertFalse(app.switches["fixedFlowAutoPay"].isEnabled)
        enterAmount("10", identifier: "fixedFlowAmount", in: app)
        tap(app.textFields["名字"], in: app); app.textFields["名字"].typeText("自动测试")
        tap(app.buttons["fixedFlowSchedule"], in: app)
        XCTAssertTrue(app.datePickers.firstMatch.waitForExistence(timeout: 5))
        tap(app.buttons["完成"], in: app)
        tap(app.buttons["增加期数"], in: app); tap(app.buttons["增加期数"], in: app)
        tap(app.buttons["账户"], in: app)
        tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH '合成银行卡 · 余额'")).firstMatch, in: app)
        XCTAssertTrue(app.switches["fixedFlowAutoPay"].isEnabled)
        tap(app.switches["fixedFlowAutoPay"], in: app); tap(app.switches["fixedFlowEstimated"], in: app)
        tap(app.buttons["saveManualSheet"], in: app)
        XCTAssertTrue(app.buttons["付了 自动测试"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS '1/2 期' AND label CONTAINS '自动' AND label CONTAINS '大约'")).firstMatch.exists)
        XCUIDevice.shared.press(.home); app.activate()
        let paid = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true"), object: app.images["已付 自动测试"])
        XCTAssertEqual(XCTWaiter.wait(for: [paid], timeout: 5), .completed)
        XCTAssertFalse(app.staticTexts["自动记下完成"].exists)
    }

    func testOverdueBillsAppearInLetter() {
        let app = application("bills-overdue"); app.launch(); openInbox(in: app)
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
        XCTAssertFalse(app.buttons["todayEntries"].exists)
        XCTAssertFalse(app.staticTexts["自动记下完成"].exists)
        openFixedBills(app)
        XCTAssertFalse(app.buttons["付了 房租"].exists); XCTAssertTrue(app.images["已付 房租"].exists)
        tap(app.buttons["tab_ledger"], in: app)
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

    func testEraseFromMeThenWelcomeBankImportRestoresThreeTabsWithoutRelaunch() {
        let app = application("welcome-import")
        app.launchEnvironment["YUBAI_UI_ERASE_REIMPORT"] = "1"
        let csv = "时间,收支,金额,名称,余额\n2001-01-02 12:00:00,支出,32.00,合成午餐,968.00\n2001-01-03 21:14:00,收入,200.00,合成工资,1168.00\n"
        app.launchEnvironment["YUBAI_UI_STATEMENT"] = Data(csv.utf8).base64EncodedString()
        app.launch()
        for cycle in 1...2 {
            assertSelectedTab("tab_ledger", in: app)
            tap(app.buttons["tab_settings"], in: app)
            assertSelectedTab("tab_settings", in: app)
            let storage = app.buttons["openStorage"]
            scrollToVisible(storage, in: app, scroll: rootPage("tab_settings", in: app).scrollViews["settingsScroll"])
            tap(storage, in: app)
            XCTAssertTrue(app.navigationBars["存储空间"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.otherElements["mainNavigation"].exists)
            tap(app.buttons["openStorageErase"], in: app)
            let confirmation = app.textFields["storageEraseConfirmation"]
            XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
            tap(confirmation, in: app); confirmation.typeText("抹掉")
            let erase = app.buttons["eraseDeviceData"]
            scrollToVisible(erase, in: app, scroll: app.scrollViews.matching(NSPredicate(format: "hittable == true")).firstMatch)
            tap(erase, in: app)
            XCTAssertTrue(app.buttons["startLedger"].waitForExistence(timeout: 10))
            tap(app.buttons["招行储蓄卡"], in: app)
            tap(app.buttons["welcomeImportStatement"], in: app)
            XCTAssertTrue(app.staticTexts["welcomeStatementBalance"].waitForExistence(timeout: 10))
            XCTAssertTrue(app.buttons["welcomeImportStatement"].label.contains("已导入 2 笔"))
            tap(app.buttons["startLedger"], in: app)
            XCTAssertTrue(app.otherElements["mainNavigation"].waitForExistence(timeout: 10))
            assertSelectedTab("tab_ledger", in: app)
            tap(app.buttons["tab_settings"], in: app)
            assertSelectedTab("tab_settings", in: app)
            XCTAssertTrue(app.buttons["openProfile"].isHittable)
            XCTAssertFalse(app.navigationBars["存储空间"].exists)
            tap(app.buttons["tab_ledger"], in: app)
            assertSelectedTab("tab_ledger", in: app)
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.2))
            start.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.2)))
            assertSelectedTab("tab_ledger", in: app)
            tap(app.buttons["tab_insights"], in: app)
            assertSelectedTab("tab_insights", in: app)
            tap(app.buttons["tab_ledger"], in: app)
            snapshot("erase-import-tabs-cycle-\(cycle)", app)
        }
    }

    func testStorageEntryAndOverviewOpenFromMe() {
        let app = application("ask"); app.launch()
        tap(app.buttons["tab_settings"], in: app)
        let storage = app.buttons["openStorage"]
        let navigation = app.otherElements["mainNavigation"]
        for _ in 0..<8 {
            if storage.isHittable && storage.frame.maxY <= navigation.frame.minY { break }
            scrollVertically(rootPage("tab_settings", in: app).scrollViews["settingsScroll"], in: app)
        }
        XCTAssertTrue(storage.isHittable)
        XCTAssertLessThanOrEqual(storage.frame.maxY, navigation.frame.minY)
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

    func testScrolledRootHeadersStayInsideSafeAreaWhenOpeningEntrySheet() {
        let app = application("entries"); app.launch()
        var headerY: CGFloat?
        for (tab, scrollID) in [("tab_ledger", "entriesScroll"), ("tab_insights", "insightsScroll"), ("tab_settings", "settingsScroll")] {
            tap(app.buttons[tab], in: app)
            let page = rootPage(tab, in: app), header = rootPage(tab, in: app).staticTexts["rootHeaderTitle"]
            XCTAssertTrue(header.waitForExistence(timeout: 5))
            if let headerY { XCTAssertEqual(header.frame.minY, headerY, accuracy: 1) } else { headerY = header.frame.minY }
            let y = header.frame.minY
            let scroll = page.scrollViews[scrollID]
            if scroll.exists { scroll.swipeUp() }
            XCTAssertEqual(header.frame.minY, y, accuracy: 1)
            XCTAssertTrue(page.buttons["askYubai"].isHittable)
        }
        tap(app.buttons["tab_ledger"], in: app); tap(addEntryTab(app), in: app)
        XCTAssertTrue(app.buttons["importFromEntry"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["askYubai"].isHittable)
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
        let app = application("overview-xl")
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"]
        app.launch()
        XCTAssertTrue(app.staticTexts["rootHeaderTitle"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["askYubai"].isHittable)
        XCTAssertTrue(app.buttons["entriesSearchButton"].isHittable)
        XCTAssertTrue(app.buttons["fundsFormula"].exists)
    }

    func testInsightsShowsCycleCashBeforeCategoriesAndCategoryOpensDetails() {
        let app = application("ask"); app.launch(); tap(app.buttons["tab_insights"], in: app)
        let cash = app.descendants(matching: .any).matching(identifier: "cashTimelineCard").firstMatch
        let category = app.buttons["insightCategory_0"]
        XCTAssertTrue(cash.waitForExistence(timeout: 5)); XCTAssertTrue(app.staticTexts["花在哪"].exists)
        XCTAssertLessThan(cash.frame.minY, category.frame.minY)
        tap(category, in: app)
        XCTAssertFalse(app.otherElements["mainNavigation"].isHittable)
        XCTAssertFalse(app.buttons["askYubai"].isHittable)
    }

    func testModelMenuSelectsInlineAndKeepsCustomEditor() {
        let app = application("ask"); app.launch()
        tap(app.buttons["tab_settings"], in: app)
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

    func testRootTabsChangeOnlyByTapAndAddBelongsToLedger() {
        let app = application("entries"); app.launch()
        rootPage("tab_ledger", in: app).swipeLeft()
        assertSelectedTab("tab_ledger", in: app)
        tap(app.buttons["tab_insights"], in: app)
        rootPage("tab_insights", in: app).swipeRight()
        assertSelectedTab("tab_insights", in: app)
        XCTAssertFalse(addEntryTab(app).exists)
        tap(app.buttons["tab_settings"], in: app)
        XCTAssertFalse(addEntryTab(app).exists)
        tap(app.buttons["tab_ledger"], in: app)
        XCTAssertTrue(addEntryTab(app).isHittable)
    }


    func testCancelledNestedBackKeepsTabBarHiddenUntilSettingsRoot() {
        let app = application("ask"); app.launch()
        tap(app.buttons["tab_settings"], in: app)
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
        assertCurrentTab("tab_settings", content: "openIntelligencePrivacy", in: app)
        tap(app.buttons["tab_ledger"], in: app)
        assertCurrentTab("tab_ledger", content: "fundsFormula", in: app)
    }


    func testSheetNavigationDoesNotHideRootTabBarAfterDismissal() {
        let app = application("manual"); app.launch(); tap(app.buttons["tab_insights"], in: app)
        tap(app.buttons["askYubai"], in: app)
        tap(app.buttons["云端智能没开 ›"], in: app)
        XCTAssertTrue(app.navigationBars["智能与隐私"].waitForExistence(timeout: 5))
        dragBack(app, to: 0.95); tap(app.buttons["closeSheet"], in: app)
        assertSelectedTab("tab_insights", in: app)
        tap(app.buttons["tab_ledger"], in: app)
        assertCurrentTab("tab_ledger", content: "entriesSearchButton", in: app)
    }

    func testTabButtonsPreserveInsightWindowWithoutPaging() {
        let app = application("ask"); app.launch()
        tap(app.buttons["tab_insights"], in: app); tap(app.buttons["本周"], in: app)
        for tab in ["tab_settings", "tab_ledger", "tab_insights"] { tap(app.buttons[tab], in: app); assertSelectedTab(tab, in: app) }
        XCTAssertTrue(app.buttons["本周"].isSelected)
        XCTAssertFalse(addEntryTab(app).exists)
    }

    func testLedgerSearchOwnsFiltersAndPreservesRootSelection() {
        let app = application("entries"); app.launch(); tap(app.buttons["entriesSearchButton"], in: app)
        XCTAssertTrue(app.textFields["entriesSearch"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.otherElements["mainNavigation"].isHittable)
        tap(app.buttons["支出"], in: app)
        tap(app.buttons["ledgerBack"], in: app)
        assertSelectedTab("tab_ledger", in: app)
    }

    private func swipeButler(_ card: XCUIElement, right: Bool = false, in app: XCUIApplication) {
        scrollToVisible(card, in: app)
        let start = point(card, x: right ? 0.25 : 0.75, y: 0.35, in: app)
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: card.frame.width * (right ? 0.45 : -0.45), dy: 0)), withVelocity: .slow, thenHoldForDuration: 0.2)
    }

    func testLetterIgnoresHorizontalSwipesAndCloseSupportsUndo() {
        let app = application("restrain", keepingUndo: true); app.launch(); openInbox(in: app)
        let card = app.descendants(matching: .any).matching(identifier: "butlerCard_restrain").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        swipeButler(card, in: app); XCTAssertTrue(card.exists)
        swipeButler(card, right: true, in: app); XCTAssertTrue(card.exists)
        tap(card.buttons["dismissLetterCard"], in: app); assertGone(card)
        tapUndo(messagePrefix: "收起了", exact: true, in: app)
        XCTAssertTrue(card.waitForExistence(timeout: 5))
    }


    func testLetterFeedbackPreservesOtherCardsAndSupportsUndo() {
        let app = application("butler-deck", keepingUndo: true); app.launch(); openInbox(in: app)
        let top = app.staticTexts["butlerTitle_offCharacter"], next = app.staticTexts["butlerTitle_recurring"]
        XCTAssertTrue(top.waitForExistence(timeout: 5)); XCTAssertTrue(next.exists)
        tap(app.buttons["都值得"], in: app); assertGone(top); XCTAssertTrue(next.exists)
        tapUndo(messagePrefix: "记下了：都值得", exact: true, in: app)
        XCTAssertTrue(top.waitForExistence(timeout: 5))
    }


    func testLetterScrollsAndHasNoRootAssistantButton() {
        let app = application("butler-deck"); app.launch(); openInbox(in: app)
        let card = app.descendants(matching: .any).matching(identifier: "butlerCard_offCharacter").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        app.scrollViews.firstMatch.swipeUp()
        XCTAssertTrue(card.exists)
        XCTAssertFalse(app.buttons["askYubai"].isHittable)
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
        tap(app.buttons["tab_insights"], in: app); assertSelectedTab("tab_insights", in: app)
        tap(app.buttons["tab_ledger"], in: app); assertSelectedTab("tab_ledger", in: app)
        XCTAssertFalse(app.buttons["editEntryAmount"].exists)
    }

    func testLedgerRowSwipesDoNotOpenEditorAndTapStillWorks() {
        let app = application("ask"); app.launch()
        tap(app.buttons["tab_ledger"], in: app)
        XCTAssertFalse(app.buttons["addFromEntries"].exists)
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'ledgerEntry_' ")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        let start = row.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: -40, dy: 0)), withVelocity: .slow, thenHoldForDuration: 0.2)
        XCTAssertTrue(app.buttons["tab_ledger"].isSelected)
        XCTAssertFalse(app.buttons["editEntryAmount"].exists)
        start.press(forDuration: 0.05, thenDragTo: row.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)))
        XCTAssertTrue(app.buttons["tab_ledger"].isSelected)
        XCTAssertFalse(app.buttons["editEntryAmount"].exists)
        swipeRow(row, left: false)
        let heading = app.staticTexts["本月收入"]
        let tabSwipe = heading.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        tabSwipe.press(forDuration: 0.05, thenDragTo: tabSwipe.withOffset(CGVector(dx: -180, dy: 0)))
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == true"), object: app.buttons["tab_settings"])
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 5), .completed)
        XCTAssertFalse(app.buttons["editEntryAmount"].exists); XCTAssertFalse(app.buttons["saveQuickEntry"].exists)
        tap(app.buttons["tab_ledger"], in: app)
        let backSwipe = app.staticTexts["本月支出"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        backSwipe.press(forDuration: 0.05, thenDragTo: backSwipe.withOffset(CGVector(dx: 220, dy: 0)))
        let previous = XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == true"), object: app.buttons["tab_insights"])
        XCTAssertEqual(XCTWaiter.wait(for: [previous], timeout: 5), .completed)
        XCTAssertFalse(app.buttons["editEntryAmount"].exists)
        tap(app.buttons["tab_ledger"], in: app); tap(row, in: app)
        XCTAssertTrue(app.buttons["editEntryAmount"].waitForExistence(timeout: 5))
        tap(app.buttons["cancelManualSheet"], in: app)
        tap(addEntryTab(app), in: app)
        XCTAssertTrue(app.buttons["saveQuickEntry"].waitForExistence(timeout: 5))
    }

    func testSearchPageOwnsMonthFiltersAndSearch() {
        let app = application("ask"); app.launch(); tap(app.buttons["entriesSearchButton"], in: app)
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'ledgerEntry_' "))
        XCTAssertTrue(app.textFields["entriesSearch"].waitForExistence(timeout: 5))
        tap(app.buttons["entriesFilter_收入"], in: app); XCTAssertEqual(rows.count, 0)
        tap(app.buttons["entriesFilter_支出"], in: app); XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5))
        tap(app.buttons["entriesFilter_全部"], in: app)
        tap(app.buttons["entriesPreviousMonth"], in: app); XCTAssertEqual(rows.count, 0)
        tap(app.buttons["entriesNextMonth"], in: app)
        let search = app.textFields["entriesSearch"]
        tap(search, in: app); search.typeText("32.00")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5))
        search.typeText("999"); XCTAssertTrue(app.staticTexts["没有找到这笔"].waitForExistence(timeout: 5))
        tap(app.buttons["ledgerBack"], in: app)
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
        let app = application("ask"); app.launch()
        XCTAssertTrue(app.buttons["fundsFormula"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'ledgerEntry_' ")).firstMatch.exists)
        XCTAssertFalse(app.buttons["openTodayLedger"].exists)
    }

    func testCashTimelineHoldAndDragKeepsTheCurrentTab() {
        let app = application("cashflow"); app.launch(); tap(app.buttons["tab_insights"], in: app)
        let chart = app.descendants(matching: .any).matching(identifier: "cashTimelineChart").firstMatch
        XCTAssertTrue(chart.waitForExistence(timeout: 5))
        chart.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)).press(forDuration: 0.4,
            thenDragTo: chart.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)))
        assertSelectedTab("tab_insights", in: app); XCTAssertTrue(chart.exists)
    }

    func testCashTimelineHasOneCycleAndNoPreviousComparisonOrPaging() {
        let app = application("cashflow"); app.launch()
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "cashTimelineCard").firstMatch.exists)
        tap(app.buttons["tab_insights"], in: app)
        XCTAssertTrue(app.staticTexts["现金这个月"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["上个月"].exists)
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "cashTimelinePages").firstMatch.exists)
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "cashTimelineComparison").firstMatch.exists)
    }

    func testCashTimelineRespectsLedgerAmountPrivacy() {
        let app = application("cashflow-low"); app.launch()
        tap(app.buttons["toggleAmountVisibility"], in: app)
        tap(app.buttons["tab_insights"], in: app)
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "cashTimelineChart").firstMatch.exists)
        tap(app.buttons["tab_ledger"], in: app); tap(app.buttons["toggleAmountVisibility"], in: app)
        tap(app.buttons["tab_insights"], in: app)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "cashTimelineChart").firstMatch.waitForExistence(timeout: 5))
    }

    func testWelcomeStatementBalanceReviewAndCommit() {
        let app = application("welcome-import")
        let csv = "时间,收支,金额,名称,余额\n2001-01-02 12:00:00,支出,32.00,合成午餐,968.00\n2001-01-03 21:14:00,收入,200.00,合成工资,1168.00\n"
        app.launchEnvironment["YUBAI_UI_STATEMENT"] = Data(csv.utf8).base64EncodedString()
        app.launch()
        XCTAssertFalse(app.buttons["welcomeImportStatement"].exists)
        tap(app.buttons["支付宝"], in: app)
        XCTAssertFalse(app.buttons["welcomeImportStatement"].exists)
        tap(app.buttons["招行储蓄卡"], in: app)
        let statement = app.buttons["welcomeImportStatement"]
        XCTAssertGreaterThanOrEqual(statement.frame.height, 52 - 0.01)
        tap(statement, in: app)
        XCTAssertTrue(app.staticTexts["welcomeStatementBalance"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["welcomeStatementBalance"].label.contains("1月3日 21:14"))
        XCTAssertEqual(app.textFields["accountBalance"].value as? String, "1168.00")
        XCTAssertTrue(statement.label.contains("已导入 2 笔"))
        XCTAssertFalse(app.buttons["welcomeImportRecent"].exists)
        XCTAssertTrue(app.buttons["startLedger"].isEnabled)
        snapshot("welcome-statement-balance", app)
        tap(app.buttons["微信零钱"], in: app)
        XCTAssertFalse(statement.exists)
        XCTAssertFalse(app.staticTexts["welcomeStatementBalance"].exists)
        XCTAssertFalse(app.buttons["startLedger"].isEnabled)
        tap(app.buttons["招行储蓄卡"], in: app)
        tap(statement, in: app)
        XCTAssertTrue(app.staticTexts["welcomeStatementBalance"].waitForExistence(timeout: 10))
        tap(statement, in: app)
        XCTAssertTrue(app.buttons["selectImportRow_3"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["commitImport"].exists)
        XCTAssertFalse(app.pickers["importDefaultAccount"].exists)
        tap(app.buttons["selectImportRow_3"], in: app)
        tap(app.buttons["closeSheet"], in: app)
        XCTAssertTrue(statement.label.contains("已导入 1 笔"))
        XCTAssertEqual(app.textFields["accountBalance"].value as? String, "1168.00")
        tap(app.buttons["startLedger"], in: app)
        let funds = app.buttons["fundsFormula"]
        XCTAssertTrue(funds.waitForExistence(timeout: 10))
        // These old fixture rows cannot change the 90-day spending estimate.
        XCTAssertTrue(funds.label.contains("1,168.00"))
        tap(app.buttons["tab_settings"], in: app)
        tap(app.buttons["openImportHistory"], in: app)
        XCTAssertTrue(app.staticTexts["合成账单.csv"].waitForExistence(timeout: 5))
    }

    func testWelcomeAnnualStatementDefaultsToRecentThreeMonthsAndCommitsSelectedCount() {
        verifyAnnualWelcomeImport(selectAll: false)
    }

    func testWelcomeAnnualStatementAllRangeCommitsFullCount() {
        verifyAnnualWelcomeImport(selectAll: true)
    }

    private func verifyAnnualWelcomeImport(selectAll: Bool) {
        let app = application("welcome-import")
        let lines = (1...12).map { month in
            String(format: "2001-%02d-15 12:00:00,支出,1.00,合成日常,1000.00", month)
        } + ["2002-01-15 12:00:00,支出,1.00,合成日常,1234.56"]
        let csv = (["时间,收支,金额,名称,余额"] + lines).joined(separator: "\n")
        app.launchEnvironment["YUBAI_UI_STATEMENT"] = Data(csv.utf8).base64EncodedString()
        app.launchEnvironment["YUBAI_UI_TEST_IMPORT_STATE"] = "1"
        app.launch()
        tap(app.buttons["招行储蓄卡"], in: app)
        let statement = app.buttons["welcomeImportStatement"]
        tap(statement, in: app)
        let recent = app.buttons["welcomeImportRecent"], all = app.buttons["welcomeImportAll"]
        XCTAssertTrue(recent.waitForExistence(timeout: 10))
        XCTAssertTrue(recent.isSelected); XCTAssertFalse(all.isSelected)
        XCTAssertTrue(recent.label.contains("4 笔")); XCTAssertTrue(all.label.contains("13 笔"))
        XCTAssertTrue(statement.label.contains("已导入 4 笔"))
        XCTAssertTrue(statement.label.contains("2001年10月15日–2002年1月15日"))
        XCTAssertLessThanOrEqual(recent.frame.maxY, statement.frame.minY)
        XCTAssertEqual(app.textFields["accountBalance"].value as? String, "1234.56")
        tap(all, in: app)
        XCTAssertTrue(all.isSelected); XCTAssertFalse(recent.isSelected)
        XCTAssertTrue(statement.label.contains("已导入 13 笔"))
        XCTAssertTrue(statement.label.contains("2001年1月15日–2002年1月15日"))
        XCTAssertEqual(app.textFields["accountBalance"].value as? String, "1234.56")
        if !selectAll {
            tap(recent, in: app)
            XCTAssertTrue(statement.label.contains("已导入 4 笔"))
            tap(statement, in: app)
            XCTAssertTrue(app.buttons["selectImportRow_14"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["selectImportRow_2"].exists)
            // The welcome page can remain in the accessibility tree beneath the review sheet.
            XCTAssertFalse(app.buttons["welcomeImportRecent"].isHittable)
            tap(app.buttons["selectImportRow_14"], in: app)
            tap(app.buttons["closeSheet"], in: app)
            XCTAssertTrue(statement.label.contains("已导入 3 笔"))
            tap(all, in: app)
            XCTAssertTrue(statement.label.contains("已导入 12 笔"))
            tap(recent, in: app)
            tap(statement, in: app)
            tap(app.buttons["selectImportRow_14"], in: app)
            tap(app.buttons["closeSheet"], in: app)
            XCTAssertTrue(statement.label.contains("已导入 4 笔"))
            XCTAssertEqual(app.textFields["accountBalance"].value as? String, "1234.56")
        }
        snapshot(selectAll ? "welcome-import-all" : "welcome-import-recent", app)
        tap(app.buttons["startLedger"], in: app)
        let pending = app.descendants(matching: .any).matching(identifier: "pendingImportsCard").firstMatch
        XCTAssertTrue(pending.waitForExistence(timeout: 10))
        let count = selectAll ? 13 : 4
        XCTAssertTrue(pending.staticTexts["\(count) 笔还没分类"].exists)
        assertImportRequestState(pending, requests: 0, entries: count, classified: 0)
        XCTAssertTrue(app.buttons["fundsFormula"].label.contains("1,234.56"))
        app.terminate(); app.launch()
        XCTAssertTrue(pending.waitForExistence(timeout: 10))
        assertImportRequestState(pending, requests: 0, entries: count, classified: 0)
    }

    func testWelcomeStatementWithoutBalanceAndAccountSwitch() {
        let app = application("welcome-import")
        let csv = "时间,收支,金额,名称\n2001-01-02 12:00:00,支出,32.00,合成午餐\n"
        app.launchEnvironment["YUBAI_UI_STATEMENT"] = Data(csv.utf8).base64EncodedString()
        app.launch()
        tap(app.buttons["welcomeOtherAccount"], in: app)
        app.textFields["accountName"].typeText("UI Bank")
        tap(app.buttons["welcomeImportStatement"], in: app)
        XCTAssertTrue(app.staticTexts["这份流水没有余额"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["welcomeImportStatement"].label.contains("已导入 1 笔"))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["startLedger"].isEnabled)
        app.textFields["accountBalance"].typeText("1000")
        XCTAssertTrue(app.buttons["startLedger"].isEnabled)
        snapshot("welcome-statement-no-balance", app)
        tap(app.buttons["微信零钱"], in: app)
        XCTAssertFalse(app.buttons["welcomeImportStatement"].exists)
        XCTAssertFalse(app.staticTexts["这份流水没有余额"].exists)
        XCTAssertFalse(app.buttons["startLedger"].isEnabled)
        tap(app.buttons["招行储蓄卡"], in: app)
        XCTAssertFalse(app.staticTexts["welcomeStatementBalance"].exists)
        XCTAssertTrue(app.buttons["welcomeImportStatement"].label.contains("导入这张卡的流水"))
        XCTAssertFalse(app.buttons["startLedger"].isEnabled)
    }

    func testFirstLaunchEmptyLedgerAccountAndAvailableFunds() {
        let app = application("empty"); app.launch()
        snapshot("welcome", app)
        XCTAssertFalse(app.buttons["startLedger"].isEnabled)
        XCTAssertGreaterThan(app.buttons["startLedger"].frame.width, app.frame.width * 0.8)
        XCTAssertGreaterThan(app.buttons["startLedger"].frame.minY, app.frame.midY)
        tap(app.textFields["accountBalance"], in: app); app.textFields["accountBalance"].typeText("1000")
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5))
        let scroll = app.scrollViews["welcomeScroll"]
        let start = app.buttons["startLedger"]
        let chips = ["微信零钱", "支付宝", "招行储蓄卡", "welcomeOtherAccount"].map { app.buttons[$0] }
        let card = app.descendants(matching: .any).matching(identifier: "welcomeBalanceCard").firstMatch
        func assertKeyboardLayout() {
            // No swipe first: focusing the field must reveal the card's chips automatically.
            let visible = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                chips.allSatisfy { $0.isHittable && $0.frame.minY >= scroll.frame.minY && $0.frame.maxY <= start.frame.minY }
                    && card.frame.maxY <= start.frame.minY && start.frame.maxY <= keyboard.frame.minY
            }, object: scroll)
            XCTAssertEqual(XCTWaiter.wait(for: [visible], timeout: 5), .completed)
            XCTAssertTrue(keyboard.exists)
            XCTAssertTrue(start.isHittable)
            XCTAssertLessThanOrEqual(start.frame.maxY, keyboard.frame.minY)
            for chip in chips {
                XCTAssertTrue(chip.isHittable)
                XCTAssertGreaterThanOrEqual(chip.frame.minY, scroll.frame.minY)
                XCTAssertLessThanOrEqual(chip.frame.maxY, start.frame.minY)
            }
            XCTAssertLessThanOrEqual(card.frame.maxY, start.frame.minY)
        }
        assertKeyboardLayout()
        snapshot("welcome-default-account-keyboard", app)
        tap(app.buttons["welcomeOtherAccount"], in: app)
        tap(app.textFields["accountName"], in: app); app.textFields["accountName"].typeText("UI Bank")
        snapshot("welcome-account", app)
        tap(app.textFields["accountBalance"], in: app)
        assertKeyboardLayout()
        snapshot("welcome-keyboard-chips", app)
        tap(app.buttons["startLedger"], in: app)
        let funds = app.buttons["fundsFormula"]
        XCTAssertTrue(funds.waitForExistence(timeout: 10))
        // A newly opened ledger has no known obligations or spending estimate.
        XCTAssertTrue(funds.label.contains("还能花")); XCTAssertTrue(funds.label.contains("1,000.00"))
        let identifiers = ["tab_ledger", "tab_insights", "tab_settings", "addEntry"]
        let tabs = app.buttons.matching(NSPredicate(format: "identifier IN %@", identifiers)).allElementsBoundByIndex
        XCTAssertEqual(tabs.count, 4)
        XCTAssertEqual(Set(tabs.map(\.label)), Set(["账本", "洞察", "我", "记一笔"]))
        XCTAssertEqual(app.otherElements["mainNavigation"].label, "主导航")
        XCTAssertTrue(app.buttons["tab_ledger"].isSelected)
        XCTAssertFalse(app.buttons["tab_insights"].isSelected)
        XCTAssertFalse(app.buttons["tab_settings"].isSelected)
        XCTAssertFalse(app.buttons["addEntry"].isSelected)
        XCTAssertTrue(app.buttons["tab_ledger"].exists); XCTAssertTrue(app.buttons["tab_insights"].exists); XCTAssertTrue(app.buttons["tab_settings"].exists)
        XCTAssertTrue(app.buttons["tab_ledger"].exists)
        XCTAssertTrue(addEntryTab(app).exists); XCTAssertTrue(app.buttons["askYubai"].exists)
        snapshot("overview", app)
        tap(app.buttons["tab_insights"], in: app)
        XCTAssertTrue(app.staticTexts["花在哪"].waitForExistence(timeout: 5))
        snapshot("insights", app)
        tap(app.buttons["tab_ledger"], in: app)
        tap(funds, in: app)
        XCTAssertFalse(addEntryTab(app).isHittable)
        XCTAssertTrue(app.staticTexts["流动资金"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["这个月要攒"].exists)
        snapshot("funds-detail", app)
    }

    func testManualAndAskActionsPreserveTheSelectedPage() {
        let app = application("ask"); app.launch()
        for tab in ["tab_ledger", "tab_insights", "tab_settings"] {
            tap(app.buttons[tab], in: app)
            tap(rootPage(tab, in: app).buttons["askYubai"], in: app)
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "askInput").firstMatch.waitForExistence(timeout: 5))
            tap(app.buttons["closeSheet"], in: app)
            assertSelectedTab(tab, in: app)
            XCTAssertEqual(addEntryTab(app).exists, tab == "tab_ledger")
        }
    }

    func testLedgerSearchKeyboardLeavesNavigationOnThePushedPage() {
        let app = application("entries"); app.launch(); tap(app.buttons["entriesSearchButton"], in: app)
        let field = app.textFields["entriesSearch"]
        XCTAssertTrue(field.waitForExistence(timeout: 5)); tap(field, in: app); field.typeText("合成")
        XCTAssertFalse(app.otherElements["mainNavigation"].isHittable)
        tap(app.buttons["ledgerBack"], in: app)
        assertSelectedTab("tab_ledger", in: app)
        XCTAssertTrue(addEntryTab(app).isHittable)
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
        purpose.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.5)).tap()
        purpose.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 2) + "兼职\n")
        XCTAssertTrue(app.buttons["entryCategory_购物"].isSelected)
        tap(app.buttons["收入"], in: app)
        XCTAssertFalse(app.buttons["entryCategory_工资奖金"].isSelected)
        tap(app.buttons["支出"], in: app)
        XCTAssertFalse(app.buttons["entryCategory_餐饮"].isSelected)
    }

    private func entryScroll(_ app: XCUIApplication) -> XCUIElement {
        let scroll = app.scrollViews["entriesScroll"]
        if scroll.exists { return scroll }
        let collection = app.collectionViews["entriesScroll"]
        return collection.exists ? collection : app.tables["entriesScroll"]
    }

    func testPushedPageHidesTabBarAndRootReselectionScrollsToTop() {
        let app = application("ask"); app.launch(); tap(app.buttons["tab_settings"], in: app)
        tap(app.buttons["openIntelligencePrivacy"], in: app)
        assertPushedPage("智能与隐私", in: app)
        dragBack(app, to: 0.95)
        XCTAssertTrue(app.buttons["openIntelligencePrivacy"].waitForExistence(timeout: 5))
        app.scrollViews["settingsScroll"].swipeUp()
        tap(app.buttons["tab_settings"], in: app)
        XCTAssertTrue(rootPage("tab_settings", in: app).staticTexts["rootHeaderTitle"].isHittable)
    }

    func testAskConversationSurvivesClosingAndCanBeCleared() {
        let app = application("ask"); app.launch(); tap(app.buttons["askYubai"], in: app)
        let input = app.descendants(matching: .any).matching(identifier: "askInput").firstMatch
        tap(input, in: app); input.typeText("这周花了多少？"); tap(app.buttons["sendAsk"], in: app)
        XCTAssertTrue(app.staticTexts["这周花了多少？"].waitForExistence(timeout: 5))
        tap(app.buttons["closeSheet"], in: app); tap(app.buttons["askYubai"], in: app)
        XCTAssertTrue(app.staticTexts["这周花了多少？"].waitForExistence(timeout: 5))
        tap(app.buttons["clearAskConversation"], in: app)
        XCTAssertFalse(app.staticTexts["这周花了多少？"].exists)
        XCTAssertFalse(app.buttons["clearAskConversation"].exists)
    }

    func testEntryDiscardDialogContinuesOrDiscards() {
        let app = application("manual"); app.launch(); tap(addEntryTab(app), in: app)
        tap(app.buttons["keypad_3"], in: app); tap(app.buttons["keypad_2"], in: app)
        tap(app.buttons["cancelManualSheet"], in: app)
        XCTAssertTrue(app.buttons["放弃这笔"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["已经填了 32.00 元"].exists)
        tap(app.buttons["继续记"], in: app)
        XCTAssertEqual(app.buttons["entryKeypadAmount"].value as? String, "32.00")
        tap(app.buttons["cancelManualSheet"], in: app); tap(app.buttons["放弃这笔"], in: app)
        assertGone(app.buttons["saveQuickEntry"])
        tap(addEntryTab(app), in: app); tap(app.buttons["cancelManualSheet"], in: app)
        assertGone(app.buttons["saveQuickEntry"]); XCTAssertFalse(app.buttons["放弃这笔"].exists)
        for choice in ["entryCategory_交通", "收入", "昨天"] {
            tap(addEntryTab(app), in: app); tap(app.buttons[choice], in: app)
            tap(app.buttons["cancelManualSheet"], in: app)
            assertGone(app.buttons["saveQuickEntry"]); XCTAssertFalse(app.buttons["放弃这笔"].exists)
        }
        tap(addEntryTab(app), in: app)
        let purpose = app.textFields["entryPurpose"]
        tap(purpose, in: app); purpose.typeText("合成用途\n")
        tap(app.buttons["cancelManualSheet"], in: app)
        XCTAssertTrue(app.buttons["放弃这笔"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["放弃修改？"].exists); XCTAssertFalse(app.staticTexts["已经填了 0.00 元"].exists)
        tap(app.buttons["放弃这笔"], in: app); assertGone(app.buttons["saveQuickEntry"])
    }

    func testEntrySearchIncludesOtherMonths() {
        let app = application("round40"); app.launch(); tap(app.buttons["tab_ledger"], in: app)
        tap(app.buttons["entriesSearchButton"], in: app)
        let field = app.textFields["entriesSearch"]; tap(field, in: app); field.typeText("合成跨月房租")
        let total = app.descendants(matching: .any).matching(identifier: "entriesSearchTotal").firstMatch
        XCTAssertTrue(total.waitForExistence(timeout: 5)); XCTAssertTrue(total.staticTexts["全部月份 · 3 笔"].exists)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'ledgerEntry_' ")).count, 3)
    }

    func testRecentlyDeletedRestoresOnlyChosenEntry() {
        let app = application("round40"); app.launch(); tap(app.buttons["tab_settings"], in: app)
        tap(app.buttons["openBackup"], in: app)
        tap(app.buttons["recentlyDeleted"], in: app)
        let restore = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'restoreDeleted_' ")).firstMatch
        XCTAssertTrue(restore.waitForExistence(timeout: 5)); tap(restore, in: app)
        XCTAssertFalse(restore.exists)
        dragBack(app, to: 0.95)
        assertPushedPage("备份与恢复", in: app)
        dragBack(app, to: 0.95)
        tap(app.buttons["tab_ledger"], in: app); tap(app.buttons["entriesSearchButton"], in: app)
        let field = app.textFields["entriesSearch"]; tap(field, in: app); field.typeText("合成放回测试")
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'ledgerEntry_' ")).count, 1)
    }

    private func openEntryMore(_ app: XCUIApplication) -> XCUIElement {
        tap(app.buttons["entryCategoryMore"], in: app)
        let scroll = app.scrollViews["entryCategoryPicker"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 5))
        return scroll
    }

    func testEntryMoreShowsBothLevelsKeepsTopFiveAndPersistsSmallItem() {
        let app = application("manual"); app.launch(); tap(addEntryTab(app), in: app)
        tap(app.buttons["keypad_3"], in: app)
        let purpose = app.textFields["entryPurpose"]
        tap(purpose, in: app); purpose.typeText("合成剪头发\n")
        let scroll = openEntryMore(app)
        // Small items are already present beneath each main; no expansion tap.
        XCTAssertTrue(app.buttons["entryMoreSubcategory_餐饮/早餐"].exists)
        XCTAssertFalse(app.buttons["entryMoreCategory_工资奖金"].exists)
        XCTAssertFalse(app.buttons["entryMoreCategory_餐饮"].isSelected)
        XCTAssertFalse(app.buttons["entryMoreCategory_美容个护"].isSelected, "A local suggestion must not become a selection")
        tap(app.buttons["entryMoreSubcategory_美容个护/理发"], in: app, scroll: scroll)
        assertGone(scroll)
        let chosen = app.buttons["entryCategory_美容个护"]
        XCTAssertEqual(chosen.label, "美容个护 · 理发"); XCTAssertTrue(chosen.isSelected)
        XCTAssertTrue(app.windows.firstMatch.frame.contains(chosen.frame), "The full chip must fit without squeezing")
        for main in ["餐饮", "购物", "交通", "居住", "医疗健康"] {
            XCTAssertTrue(app.buttons["entryCategory_" + main].exists, "Choosing outside the prefix keeps all five fixed chips")
        }
        _ = openEntryMore(app); tap(app.buttons["entryMoreCancel"], in: app)
        XCTAssertEqual(chosen.label, "美容个护 · 理发")
        tap(app.buttons["saveQuickEntry"], in: app)
        tap(app.buttons["tab_ledger"], in: app)
        tap(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'ledgerEntry_' ")).firstMatch, in: app)
        XCTAssertEqual(app.buttons["entryCategory_美容个护"].label, "美容个护 · 理发")
    }

    func testEditMoreConfirmsMainOnlyAndSmallItemDespiteLocalGuess() {
        let app = application("manual"); app.launch(); tap(addEntryTab(app), in: app)
        tap(app.buttons["keypad_3"], in: app)
        let purpose = app.textFields["entryPurpose"]
        tap(purpose, in: app); purpose.typeText("合成剪头发\n")
        tap(app.buttons["saveQuickEntry"], in: app)
        tap(app.buttons["tab_ledger"], in: app)
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'ledgerEntry_' ")).firstMatch
        tap(row, in: app)
        XCTAssertEqual(app.buttons["entryCategory_餐饮"].label, "餐饮")
        var scroll = openEntryMore(app)
        tap(app.buttons["entryMoreCategory_美容个护"], in: app, scroll: scroll)
        assertGone(scroll) // A main with small items still confirms main-only in one tap.
        XCTAssertEqual(app.buttons["entryCategory_美容个护"].label, "美容个护")
        tap(app.buttons["saveManualSheet"], in: app); tap(row, in: app)
        XCTAssertEqual(app.buttons["entryCategory_美容个护"].label, "美容个护", "Saving must not reapply the hair-cut guess")
        scroll = openEntryMore(app)
        tap(app.buttons["entryMoreSubcategory_美容个护/理发"], in: app, scroll: scroll)
        tap(app.buttons["saveManualSheet"], in: app); tap(row, in: app)
        XCTAssertEqual(app.buttons["entryCategory_美容个护"].label, "美容个护 · 理发")
        scroll = openEntryMore(app)
        tap(app.buttons["entryMoreCategory_美容个护"], in: app, scroll: scroll)
        tap(app.buttons["saveManualSheet"], in: app)
        app.terminate(); app.launch(); tap(app.buttons["tab_ledger"], in: app); tap(row, in: app)
        XCTAssertEqual(app.buttons["entryCategory_美容个护"].label, "美容个护")
    }

    func testEntryMoreFollowsNatureAndClearsOldSmallItem() {
        let app = application("manual"); app.launch(); tap(addEntryTab(app), in: app)
        _ = openEntryMore(app); tap(app.buttons["entryMoreSubcategory_餐饮/早餐"], in: app)
        XCTAssertEqual(app.buttons["entryCategory_餐饮"].label, "餐饮 · 早餐")
        tap(app.buttons["收入"], in: app)
        _ = openEntryMore(app)
        XCTAssertFalse(app.buttons["entryMoreCategory_餐饮"].exists)
        tap(app.buttons["entryMoreSubcategory_工资奖金/工资"], in: app)
        XCTAssertEqual(app.buttons["entryCategory_工资奖金"].label, "工资奖金 · 工资")
        tap(app.buttons["支出"], in: app)
        XCTAssertEqual(app.buttons["entryCategory_餐饮"].label, "餐饮")
        tap(app.buttons["转账"], in: app)
        XCTAssertFalse(app.buttons["entryCategoryMore"].exists)
        tap(app.buttons["收入"], in: app)
        XCTAssertEqual(app.buttons["entryCategory_工资奖金"].label, "工资奖金")
        _ = openEntryMore(app); tap(app.buttons["entryMoreSubcategory_工资奖金/工资"], in: app)
        tap(app.buttons["keypad_3"], in: app); tap(app.buttons["saveQuickEntry"], in: app)
        tap(app.buttons["tab_ledger"], in: app)
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'ledgerEntry_' ")).firstMatch
        tap(row, in: app)
        XCTAssertEqual(app.buttons["entryCategory_工资奖金"].label, "工资奖金 · 工资")
        tap(app.buttons["转账"], in: app)
        XCTAssertFalse(app.buttons["entryCategoryMore"].exists)
        tap(app.buttons["支出"], in: app)
        _ = openEntryMore(app)
        XCTAssertFalse(app.buttons["entryMoreCategory_工资奖金"].exists)
        tap(app.buttons["entryMoreCancel"], in: app)
        tap(app.buttons["saveManualSheet"], in: app); tap(row, in: app)
        XCTAssertEqual(app.buttons["entryCategory_餐饮"].label, "餐饮")
    }

    func testEntryMoreAddsSmallItemAndRepeatKeepsPlanMainOnly() {
        let app = application("manual"); app.launch(); tap(addEntryTab(app), in: app)
        var scroll = openEntryMore(app)
        tap(app.buttons["entryMoreAdd"], in: app, scroll: scroll)
        tap(app.buttons["categoryAdditionCancel"], in: app)
        XCTAssertTrue(scroll.waitForExistence(timeout: 5))
        tap(app.buttons["entryMoreCancel"], in: app)
        XCTAssertEqual(app.buttons["entryCategory_餐饮"].label, "餐饮")
        scroll = openEntryMore(app)
        tap(app.buttons["entryMoreAdd"], in: app, scroll: scroll)
        tap(app.buttons["categoryAdditionParent_餐饮"], in: app)
        let name = app.textFields["categoryAdditionName"]
        tap(name, in: app); name.typeText("合成小项\n")
        tap(app.buttons["categoryAdditionSave"], in: app)
        assertGone(scroll)
        XCTAssertEqual(app.buttons["entryCategory_餐饮"].label, "餐饮 · 合成小项")
        tap(app.buttons["keypad_3"], in: app); tap(app.buttons["entryRepeat"], in: app)
        tap(app.buttons["saveQuickEntry"], in: app)
        XCTAssertTrue(app.buttons["addEntry"].waitForExistence(timeout: 5))
        tap(app.buttons["tab_ledger"], in: app)
        tap(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'ledgerEntry_' ")).firstMatch, in: app)
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
        tap(app.buttons["转账"], in: app); XCTAssertFalse(app.buttons["entryRepeat"].exists)
        tap(app.buttons["支出"], in: app)
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
        let app = application("manual"); app.launch() // One active account, no entries.
        tap(addEntryTab(app), in: app)
        tap(app.buttons["keypad_5"], in: app)
        tap(app.buttons["keypad_0"], in: app); tap(app.buttons["keypad_0"], in: app)
        let purpose = app.textFields["entryPurpose"]
        tap(purpose, in: app); purpose.typeText("UI Transfer"); purpose.typeText("\n")
        tap(app.buttons["转账"], in: app)
        let save = app.buttons["saveQuickEntry"], again = app.buttons["saveQuickEntry"]
        let addAccount = app.buttons["transferAddAccount"]
        XCTAssertTrue(addAccount.waitForExistence(timeout: 5))
        XCTAssertEqual(addAccount.label, "添加账户")
        XCTAssertTrue(app.staticTexts["转入"].exists)
        XCTAssertFalse(app.buttons["内部移动"].exists)
        XCTAssertFalse(save.isEnabled); XCTAssertFalse(again.isEnabled)

        tap(addAccount, in: app)
        let accountEditor = app.navigationBars["添加账户"]
        XCTAssertTrue(accountEditor.waitForExistence(timeout: 5))
        tap(app.textFields["accountName"], in: app); app.textFields["accountName"].typeText("Cancelled Bank")
        tap(accountEditor.buttons["取消"], in: app)
        assertGone(accountEditor)
        XCTAssertTrue(addAccount.exists)
        XCTAssertFalse(save.isEnabled); XCTAssertFalse(again.isEnabled)
        XCTAssertEqual(app.buttons["entryKeypadAmount"].value as? String, "500.00")
        XCTAssertEqual(purpose.value as? String, "UI Transfer")
        XCTAssertTrue(app.buttons["转账"].isSelected); XCTAssertTrue(app.buttons["今天"].exists)

        tap(addAccount, in: app)
        XCTAssertTrue(accountEditor.waitForExistence(timeout: 5))
        tap(app.textFields["accountName"], in: app); app.textFields["accountName"].typeText("UI Transfer Bank")
        tap(app.textFields["accountBalance"], in: app); app.textFields["accountBalance"].typeText("0")
        tap(app.buttons["saveAccount"], in: app)
        assertGone(accountEditor)
        let destination = app.buttons["transferDestinationAccount"]
        assertState(destination, value: "UI Transfer Bank", enabled: true)
        assertGone(addAccount)
        XCTAssertTrue(save.isEnabled); XCTAssertTrue(again.isEnabled)
        XCTAssertEqual(app.buttons["entryKeypadAmount"].value as? String, "500.00")
        XCTAssertEqual(purpose.value as? String, "UI Transfer")
        XCTAssertTrue(app.buttons["转账"].isSelected); XCTAssertTrue(app.buttons["今天"].exists)
        tap(save, in: app)
        assertGone(save)

        tap(app.buttons["tab_ledger"], in: app)
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'ledgerEntry_'"))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(rows.count, 1)
        XCTAssertTrue(rows.firstMatch.label.contains("UI Transfer"))
        tap(rows.firstMatch, in: app)
        XCTAssertTrue(app.buttons["editEntryAmount"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["editEntryAmount"].value as? String, "500.00")
        XCTAssertTrue(app.buttons["转账"].isSelected)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "value == %@", "合成银行卡")).firstMatch.exists)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "value == %@", "UI Transfer Bank")).firstMatch.exists)
        tap(app.buttons["cancelManualSheet"], in: app)

        // A later transfer uses the existing second account without opening the editor.
        tap(addEntryTab(app), in: app); tap(app.buttons["转账"], in: app)
        assertState(destination, value: "UI Transfer Bank", enabled: true)
        XCTAssertFalse(addAccount.exists)
        tap(app.buttons["keypad_1"], in: app)
        XCTAssertTrue(save.isEnabled)
        tap(app.buttons["cancelManualSheet"], in: app)
    }

    func testManualKeypadSaveUpdatesFundsAndLedgerEditAndDelete() {
        let app = application("manual"); app.launch()
        let funds = app.buttons["fundsFormula"]
        XCTAssertTrue(funds.waitForExistence(timeout: 10))
        XCTAssertTrue(funds.label.contains("1,000.00"))
        tap(addEntryTab(app), in: app)
        tap(app.buttons["keypad_3"], in: app); tap(app.buttons["keypad_2"], in: app)
        XCTAssertEqual(app.buttons["entryKeypadAmount"].value as? String, "32.00")
        snapshot("manual-draft", app)
        tap(app.buttons["saveQuickEntry"], in: app)
        XCTAssertFalse(app.buttons["todayEntries"].exists)
        let decreased = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS '968.00'"), object: funds)
        XCTAssertEqual(XCTWaiter.wait(for: [decreased], timeout: 10), .completed)
        snapshot("manual-saved", app)
        tap(app.buttons["tab_ledger"], in: app)
        XCTAssertTrue(app.buttons["tab_ledger"].isSelected)
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'ledgerEntry_' ")).firstMatch
        tap(row, in: app)
        XCTAssertTrue(app.buttons["editEntryAmount"].waitForExistence(timeout: 5))
        snapshot("manual-edit", app)
        tap(app.buttons["deleteEntry"], in: app)
        assertGone(row)
        snapshot("manual-deleted", app)
        tap(app.buttons["tab_ledger"], in: app)
        XCTAssertFalse(app.buttons["todayEntries"].exists)
        XCTAssertTrue(funds.label.contains("1,000.00"))
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
        let fallback = app.staticTexts["unsortedQuestionTitle"]
        XCTAssertTrue(fallback.waitForExistence(timeout: 10)); XCTAssertEqual(fallback.label, "1 笔还没分类")
        XCTAssertFalse(app.staticTexts["importQuestion"].exists)
        XCTAssertFalse(app.buttons["importAnswer_0"].exists)
        XCTAssertTrue(app.buttons["groupUnsortedByParty"].exists)
        snapshot("import-fallback", app)
        tap(app.buttons["closeSheet"], in: app)
        tap(app.buttons["tab_settings"], in: app)
        tap(app.buttons["openImportHistory"], in: app)
        XCTAssertTrue(app.staticTexts["合成账单.csv"].waitForExistence(timeout: 5))
        snapshot("import-history", app)
        tap(app.buttons["undoImportBatch"], in: app)
        tap(app.buttons["撤销这一批"], in: app)
        XCTAssertTrue(app.staticTexts["emptyImportHistory"].waitForExistence(timeout: 5))
        snapshot("history-undone", app)
        // Reimport is no longer a duplicate. The pre-existing record survives undo.
        tap(app.navigationBars.buttons["我"], in: app)
        tap(app.buttons["tab_ledger"], in: app)
        tap(addEntryTab(app), in: app)
        tap(app.buttons["importFromEntry"], in: app)
        XCTAssertTrue(app.buttons["commitImport"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["commitImport"].isEnabled)
        tap(app.buttons["commitImport"], in: app)
        XCTAssertTrue(app.staticTexts["unsortedQuestionTitle"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["importQuestion"].exists)
        XCTAssertFalse(app.buttons["importAnswer_0"].exists)
        tap(app.buttons["undoImportResult"], in: app)
        XCTAssertTrue(app.staticTexts["activeEntryCount"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["activeEntryCount"].label, "有效记录 1 笔")
        snapshot("reimport-undone", app)
    }

    func testLetterClosePersistsForButlerCards() {
        let app = application("restrain", keepingUndo: true); app.launch(); openInbox(in: app)
        let card = app.descendants(matching: .any).matching(identifier: "butlerCard_restrain").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        tap(card.buttons["dismissLetterCard"], in: app); assertGone(card)
        app.terminate(); app.launch(); openInbox(in: app, required: false)
        XCTAssertFalse(app.staticTexts["butlerTitle_restrain"].exists)
    }

    func testAskNumericAnswerEvidenceAndEntryDetail() {
        let app = application("ask"); app.launch()
        snapshot("overview", app)
        tap(app.buttons["askYubai"], in: app)
        snapshot("ask", app)
        tap(app.descendants(matching: .any).matching(identifier: "askInput").firstMatch, in: app); app.descendants(matching: .any).matching(identifier: "askInput").firstMatch.typeText("咖啡共花了多少钱？")
        tap(app.buttons["sendAsk"], in: app)
        let answer = app.staticTexts["askAnswer"]
        XCTAssertTrue(answer.waitForExistence(timeout: 10)); XCTAssertTrue(answer.label.contains("32.00"))
        snapshot("numeric-answer", app)
        tap(app.buttons["answerEvidence"], in: app)
        snapshot("answer-evidence", app)
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'evidenceEntry_' ")).firstMatch
        tap(row, in: app)
        XCTAssertTrue(app.staticTexts["entryDetailTitle"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["entryDetailTitle"].label, "合成咖啡")
        XCTAssertTrue(app.staticTexts["明细"].exists)
        snapshot("entry-detail", app)
    }

    func testProfilePrinciplePersistsAndBackupOpens() {
        let app = application("profile"); app.launch()
        snapshot("overview", app)
        tap(app.buttons["tab_settings"], in: app)
        tap(app.buttons["openProfile"], in: app)
        snapshot("profile", app)
        tap(app.buttons["editProfile"], in: app)
        tap(app.buttons["addPrinciple"], in: app)
        snapshot("add-principle", app)
        tap(app.descendants(matching: .any).matching(identifier: "principleText").firstMatch, in: app); app.descendants(matching: .any).matching(identifier: "principleText").firstMatch.typeText("为每天用得上的东西花钱")
        tap(app.buttons["savePrinciple"], in: app)
        XCTAssertTrue(app.staticTexts["为每天用得上的东西花钱"].waitForExistence(timeout: 5))
        snapshot("principle-saved", app)
        app.terminate(); app.launch()
        tap(app.buttons["tab_settings"], in: app)
        tap(app.buttons["openProfile"], in: app)
        XCTAssertTrue(app.staticTexts["为每天用得上的东西花钱"].waitForExistence(timeout: 5))
        snapshot("principle-after-relaunch", app)
        tap(app.navigationBars.buttons["我"], in: app)
        tap(app.buttons["openBackup"], in: app)
        XCTAssertTrue(app.navigationBars["备份与恢复"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.secureTextFields["备份密码（至少 8 位）"].exists)
        XCTAssertFalse(app.secureTextFields["备份密码"].exists)
        XCTAssertTrue(app.buttons["选择备份文件"].exists)
        XCTAssertFalse(addEntryTab(app).isHittable)
        XCTAssertFalse(app.buttons["tab_settings"].isHittable)
        snapshot("backup", app)
    }
    func testAskMemoryCanBeOpenedEditedAndDeletedFromMe() {
        let app = application("memory"); app.launch()
        snapshot("overview", app)
        tap(app.buttons["askYubai"], in: app)
        let input = app.descendants(matching: .any).matching(identifier: "askInput").firstMatch
        tap(input, in: app); input.typeText("年底前想换电脑")
        tap(app.buttons["sendAsk"], in: app)
        XCTAssertTrue(app.staticTexts["已记下：年底前想换电脑"].waitForExistence(timeout: 10))
        snapshot("memory-answer", app)
        tap(app.buttons["closeSheet"], in: app)
        tap(app.buttons["tab_settings"], in: app)
        tap(app.buttons["openProfile"], in: app); tap(app.buttons["openMemories"], in: app)
        XCTAssertTrue(app.navigationBars["余白记得的"].waitForExistence(timeout: 5))
        XCTAssertFalse(addEntryTab(app).isHittable)
        snapshot("memories", app)
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'memory_' ")).firstMatch
        tap(row, in: app)
        let field = app.descendants(matching: .any).matching(identifier: "memoryText").firstMatch
        tap(field, in: app); field.typeText("，先留一笔钱")
        guard let edited = field.value as? String else { XCTFail("Memory editor must expose its text"); return }
        XCTAssertTrue(edited.contains("先留一笔钱"))
        snapshot("memory-editor", app)
        tap(app.buttons["saveMemory"], in: app)
        XCTAssertTrue(app.staticTexts[edited].waitForExistence(timeout: 5))
        app.terminate(); app.launch()
        tap(app.buttons["tab_settings"], in: app); tap(app.buttons["openProfile"], in: app); tap(app.buttons["openMemories"], in: app)
        XCTAssertTrue(app.staticTexts[edited].waitForExistence(timeout: 5))
        snapshot("memory-after-relaunch", app)
        tap(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'memory_' ")).firstMatch, in: app)
        tap(app.buttons["deleteMemory"], in: app)
        XCTAssertTrue(app.staticTexts["emptyMemories"].waitForExistence(timeout: 5))
        snapshot("memory-deleted", app)
    }
}

/// The same Foundation-only source is compiled into the app and this test bundle.
final class MotionStateTests: XCTestCase {
    func testChartClaimsSurviveViewLifetimesAndStayIndependent() {
        var session = MotionSessionState()
        XCTAssertFalse(session.contains("cashTimeline"))
        XCTAssertTrue(session.claim("cashTimeline"))
        XCTAssertTrue(session.contains("cashTimeline"))
        XCTAssertFalse(session.claim("cashTimeline"))
        XCTAssertTrue(session.claim("donut"))
        var nextLaunch = MotionSessionState()
        XCTAssertTrue(nextLaunch.claim("cashTimeline"))
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
