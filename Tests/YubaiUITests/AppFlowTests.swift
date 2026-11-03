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
    func testSalaryConfirmationChangesHorizonAndUndoRestoresCard() {
        let app = application("salary", keepingUndo: true); app.launch()
        XCTAssertTrue(app.buttons["confirmSalary"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["这是工资吗？"].exists)
        snapshot("salary-candidate", app)
        tap(app.buttons["confirmSalary"], in: app)
        assertGone(app.buttons["confirmSalary"])
        let funds = app.buttons["fundsFormula"]
        let payday = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in funds.exists && funds.label.contains("发工资") }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [payday], timeout: 5), .completed)
        tapUndo(messagePrefix: "工资已加到会回来的账单", exact: true, in: app)
        XCTAssertTrue(app.buttons["confirmSalary"].waitForExistence(timeout: 5))
        XCTAssertFalse(funds.label.contains("发工资"))
    }

    func testConfirmedSalaryAppearsInFixedFlowsLaterGroup() {
        let app = application("salary"); app.launch()
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
            XCTAssertFalse(app.buttons["fixedFlowSchedule"].exists)
            XCTAssertTrue(app.navigationBars["固定收付"].exists)
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
        XCTAssertFalse(app.staticTexts["这个月还没有固定收付"].exists)
        snapshot(day >= 10 ? "salary-fixed-flows-later" : "salary-fixed-flows-income", app)
    }

    func testRejectedSalaryStaysDismissedAfterRelaunch() {
        let app = application("salary"); app.launch()
        tap(app.buttons["rejectSalary"], in: app)
        assertGone(app.buttons["confirmSalary"])
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["openCloudAI"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["confirmSalary"].exists)
        XCTAssertTrue(app.staticTexts["6 笔还没分类"].exists)
    }

    func testPendingImportsPageOpensCloudSettingsWithoutRequests() {
        let app = application("salary")
        app.launchEnvironment["YUBAI_UI_TEST_CONFIGURED_KEY"] = "0"
        app.launch()
        let salary = app.descendants(matching: .any).matching(identifier: "salaryCard").firstMatch
        XCTAssertTrue(salary.waitForExistence(timeout: 10))
        let start = point(salary, x: 0.85, y: 0.35, in: app)
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: -salary.frame.width * 0.65, dy: 0)), withVelocity: .slow, thenHoldForDuration: 0.2)
        XCTAssertTrue(app.buttons["openCloudAI"].waitForExistence(timeout: 5))
        assertSelectedTab("tab_overview", in: app)
        let pending = app.descendants(matching: .any).matching(identifier: "pendingImportsCard").firstMatch
        XCTAssertEqual(pending.value as? String, "requests=0")
        snapshot("pending-imports-cloud-off", app)
        tap(app.buttons["openCloudAI"], in: app)
        XCTAssertTrue(app.navigationBars["智能与隐私"].waitForExistence(timeout: 5))
        tap(app.buttons["closeSheet"], in: app)
        XCTAssertEqual(pending.value as? String, "requests=0")
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "organizingImports").firstMatch.exists)
        tap(app.buttons["classifyImportsManually"], in: app)
        assertSelectedTab("tab_entries", in: app)
        XCTAssertTrue(app.buttons["entriesFilter_没分类"].isSelected)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'ledgerEntry_' ")).firstMatch.exists)
    }

    func testPendingImportsOrganizesOnlyAfterTapWithFakeTransport() {
        let app = application("salary"); app.launch()
        tap(app.buttons["rejectSalary"], in: app)
        tap(app.buttons["openCloudAI"], in: app)
        tap(app.switches["打开云端智能"], in: app)
        tap(app.buttons["closeSheet"], in: app)
        let pending = app.descendants(matching: .any).matching(identifier: "pendingImportsCard").firstMatch
        XCTAssertTrue(app.buttons["organizeImports"].waitForExistence(timeout: 5))
        XCTAssertEqual(pending.value as? String, "requests=0")
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["organizeImports"].waitForExistence(timeout: 10))
        XCTAssertEqual(pending.value as? String, "requests=0")
        tap(app.buttons["organizeImports"], in: app)
        assertGone(pending)
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["fundsFormula"].waitForExistence(timeout: 10))
        XCTAssertFalse(pending.exists)
    }

    func testOrganizationSkipsUncertainGroupsAndFallbackPrecedesUncoveredInflows() {
        let app = application("salary")
        app.launchEnvironment["YUBAI_UI_ORGANIZATION_SCENARIO"] = "by-party"
        app.launch()
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
        app.launch()
        assertLegacyQuestionIsIgnoredDuringOrganization(app)
        assertGone(app.buttons["stopOrganizing"], timeout: 25)
        XCTAssertFalse(app.staticTexts["nowImportQuestion"].exists)
        XCTAssertFalse(app.staticTexts["unsortedQuestionTitle"].exists)
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "pendingImportsCard").firstMatch.exists)
        XCTAssertFalse(app.staticTexts["organizeError"].exists)
        app.terminate(); app.launch()
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
        app.launch()
        assertLegacyQuestionIsIgnoredDuringOrganization(app)
        app.terminate(); app.launch()
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
        app.launch()
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
        XCTAssertTrue(apply.isEnabled); XCTAssertEqual(apply.label, "6 笔记为 餐饮")
        tap(app.buttons["unsortedNature_investBuy"], in: app)
        XCTAssertTrue(apply.isEnabled); XCTAssertEqual(apply.label, "6 笔记为 买基金")
        XCTAssertFalse(app.buttons["unsortedCategory_餐饮"].isSelected)
        tap(app.buttons["unsortedCategory_餐饮"], in: app)
        XCTAssertFalse(app.buttons["unsortedNature_investBuy"].isSelected)
        XCTAssertEqual(apply.label, "6 笔记为 餐饮")
        tap(apply, in: app)
        let reduced = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == '3'"), object: count)
        XCTAssertEqual(XCTWaiter.wait(for: [reduced], timeout: 5), .completed)
        XCTAssertFalse(firstGroup.exists); XCTAssertTrue(secondGroup.exists)
        tap(app.navigationBars.buttons["现在"], in: app)
        XCTAssertTrue(app.staticTexts["unsortedQuestionTitle"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["unsortedQuestionTitle"].label, "3 笔还没分类")
        app.terminate(); app.launch()
        XCTAssertTrue(app.staticTexts["unsortedQuestionTitle"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["unsortedQuestionTitle"].label, "3 笔还没分类")
    }

    func testFallbackGroupAppliesOnlyCheckedEntriesAndLeavesUncheckedEntryInPartyGroup() {
        let app = application("salary")
        app.launchEnvironment["YUBAI_UI_ORGANIZATION_SCENARIO"] = "by-party"
        app.launch()
        tap(app.buttons["organizeImports"], in: app)
        XCTAssertTrue(app.buttons["groupUnsortedByParty"].waitForExistence(timeout: 15))
        tap(app.buttons["groupUnsortedByParty"], in: app)
        let count = app.staticTexts["unsortedEntryCount"]
        XCTAssertTrue(count.waitForExistence(timeout: 5)); XCTAssertEqual(count.label, "9")
        tap(app.buttons["unsortedGroup_out:合成对方甲"], in: app)
        tap(app.buttons["unsortedCategory_餐饮"], in: app)
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
        app.terminate(); app.launch()
        XCTAssertTrue(app.staticTexts["unsortedQuestionTitle"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["unsortedQuestionTitle"].label, "4 笔还没分类")
    }

    func testPendingImportsStopKeepsCompletedChunkAndRemainingCount() {
        let app = application("salary")
        app.launchEnvironment["YUBAI_UI_ORGANIZATION_SCENARIO"] = "stop-second"
        app.launch()
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
        app.terminate(); app.launch()
        XCTAssertTrue(pending.waitForExistence(timeout: 10))
        XCTAssertTrue(pending.staticTexts["55 笔还没分类"].exists)
        assertImportRequestState(pending, requests: 0, entries: 70, classified: 15)
    }

    func testPendingImportsSecondChunkFailureShowsReasonAndRetriesOnlyRemaining() {
        let app = application("salary")
        app.launchEnvironment["YUBAI_UI_ORGANIZATION_SCENARIO"] = "fail-second"
        app.launch()
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
        app.terminate(); app.launch()
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
        app.launch()
        let cloud = app.buttons["welcomeCloudAI"]
        tap(cloud, in: app)
        XCTAssertTrue(app.navigationBars["智能与隐私"].waitForExistence(timeout: 5))
        tap(app.switches["打开云端智能"], in: app)
        tap(app.buttons["closeSheet"], in: app)
        XCTAssertTrue(cloud.label.contains("已开"))
        XCTAssertFalse(app.buttons["tab_overview"].exists)
        app.terminate(); app.launch()
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
        for tab in ["tab_overview", "tab_insights", "tab_entries", "tab_settings"] where app.buttons[tab].exists && app.buttons[tab].isSelected {
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
        if ["tab_overview", "tab_insights", "tab_entries", "tab_settings"].contains(identifier) { assertSelectedTab(identifier, in: app, file: file, line: line) }
    }
    private func scrollToVisible(_ element: XCUIElement, in app: XCUIApplication, scroll: XCUIElement? = nil, file: StaticString = #filePath, line: UInt = #line) {
        // Only the containing vertical scroller may move; alerts, undo and navigation never scroll.
        var container = scroll
        if container == nil && element.waitForExistence(timeout: 5) && !element.isHittable && app.alerts.count == 0 {
            let identifier = element.identifier.isEmpty ? element.label : element.identifier
            if !element.identifier.hasPrefix("tab_") && !["undoLastChange", "addEntry", "closeSheet", "cancelManualSheet"].contains(element.identifier) {
                container = app.scrollViews.allElementsBoundByIndex.last { candidate in
                    candidate.identifier != "rootPager" && candidate.isHittable && candidate.frame.height > 120 && candidate.descendants(matching: element.elementType).matching(identifier: identifier).count > 0
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
        let end = point(element, x: left ? 0.15 : 0.85, in: app, file: file, line: line)
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
    private func assertGone(_ element: XCUIElement, timeout: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line) {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: timeout), .completed, file: file, line: line)
    }
    private func assertRevealState(_ row: XCUIElement, revealed: Bool, action: XCUIElement, closedFrame: CGRect? = nil, file: StaticString = #filePath, line: UInt = #line) {
        var previous = CGRect.null, stableSince = Date()
        let state = revealed ? "revealed" : "closed"
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard row.exists, (row.value as? String)?.components(separatedBy: "; ").last == state else { stableSince = Date(); return false }
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
            guard state.contains("destination=\(destination);") && state.contains("visible=\(destination);") && state.contains("phase=idle;"),
                  anchor.isHittable && viewport.contains(frame),
                  abs(page.frame.minX - viewport.minX) <= 1 && abs(page.frame.maxX - viewport.maxX) <= 1 else { stableSince = Date(); return false }
            if frame != previous { previous = frame; stableSince = Date(); return false }
            return Date().timeIntervalSince(stableSince) >= 0.35
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 10), .completed,
                       "Tab \(identifier): \(String(describing: navigation.value)); page=\(page.frame); anchor=\(anchor.frame)", file: file, line: line)
    }
    private func assertPagingLocked(_ locked: Bool, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let state = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            (app.otherElements["mainNavigation"].value as? String)?.hasSuffix("locked=\(locked ? 1 : 0)") == true
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [state], timeout: 5), .completed, file: file, line: line)
    }
    private func assertCurrentTab(_ identifier: String, content: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        assertSelectedTab(identifier, in: app, file: file, line: line)
        let element = rootPage(identifier, in: app).descendants(matching: .any).matching(identifier: content).firstMatch
        let visible = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in element.exists && element.isHittable }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [visible], timeout: 5), .completed, file: file, line: line)
        XCTAssertGreaterThanOrEqual(element.frame.minX, app.frame.minX, file: file, line: line)
        XCTAssertLessThanOrEqual(element.frame.maxX, app.frame.maxX, file: file, line: line)
        for other in ["tab_overview", "tab_insights", "tab_entries", "tab_settings"] where other != identifier {
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
        for identifier in ["tab_overview", "tab_insights", "addEntry", "tab_entries", "tab_settings"] {
            assertGone(app.buttons[identifier], file: file, line: line)
        }
    }

    private func openFixedBills(_ app: XCUIApplication) {
        tap(app.buttons["tab_settings"], in: app)
        tap(app.buttons["openFixedFlows"], in: app)
        XCTAssertTrue(app.navigationBars["固定收付"].waitForExistence(timeout: 5))
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
        for title in ["这周外卖花了多少？", "11月1日的房租够吗？", "想买一双 899 的鞋，该不该买？"] {
            XCTAssertTrue(app.buttons[title].exists); XCTAssertFalse(app.buttons[title].isEnabled)
        }
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
        tapUndo(messagePrefix: "房租 300.00 已记下", exact: true, in: app)
        assertState(check, value: "已到期", enabled: true)
        tap(check, in: app)
        assertGone(check); XCTAssertTrue(app.images["已付 房租"].exists)
        snapshot("bill-paid", app)
        tap(app.navigationBars.buttons["我"], in: app); tap(app.buttons["tab_overview"], in: app)
        XCTAssertTrue(app.buttons["fundsFormula"].label.contains("¥700.00"))
        XCTAssertTrue(app.buttons["todayEntries"].label.contains("1 笔"))
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
        tap(app.navigationBars.buttons["我"], in: app); tap(app.buttons["tab_overview"], in: app)
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
        let field = app.textFields["fixedFlowSettlementAmount"]
        tap(field, in: app)
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 3) + "100")
        tap(app.buttons["saveManualSheet"], in: app)
        assertGone(check); XCTAssertTrue(app.images["已付 电费"].exists)
        tap(app.navigationBars.buttons["我"], in: app); tap(app.buttons["tab_overview"], in: app)
        XCTAssertTrue(app.buttons["fundsFormula"].label.contains("¥900.00"))
        XCTAssertTrue(app.buttons["todayEntries"].label.contains("1 笔"))
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
        tapAlertButton("fixedFlowStopConfirm", label: "停掉以后的", in: confirmation)
        XCTAssertFalse(check.exists); XCTAssertFalse(row.exists)
        XCTAssertTrue(app.buttons["resumeFixedFlow_" + planID].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS '那期已记'")).firstMatch.exists)
        XCTAssertFalse(app.buttons["结束这个安排"].exists)
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

    func testUpcomingPaymentStopUsesAlertAndSupportsCancelAndUndo() {
        let app = application("bills", keepingUndo: true); app.launch()
        tap(app.buttons["fundsFormula"], in: app)
        let calculation = app.navigationBars["还能花是怎么算的"]
        XCTAssertTrue(calculation.waitForExistence(timeout: 5))
        let end = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'endArrangement_' ")).firstMatch
        XCTAssertTrue(end.waitForExistence(timeout: 5))
        let identifier = end.identifier
        tap(end, in: app)
        let confirmation = app.alerts["停掉「房租」？"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        XCTAssertEqual(app.popovers.count, 0)
        XCTAssertTrue(alertButton("endArrangementConfirm", in: confirmation).isHittable)
        XCTAssertTrue(alertButton("endArrangementCancel", in: confirmation).isHittable)
        snapshot("upcoming-payment-stop-alert", app)
        tapAlertButton("endArrangementCancel", label: "取消", in: confirmation); assertGone(confirmation)
        XCTAssertTrue(app.buttons[identifier].exists)
        tap(app.buttons[identifier], in: app)
        tapAlertButton("endArrangementConfirm", label: "停掉以后的", in: confirmation)
        // Undo belongs to the root overlay. Close the sheet before any secondary waits.
        calculation.buttons["closeSheet"].tap()
        tapUndo(messagePrefix: "结束安排", in: app)
        assertGone(calculation)
        tap(app.buttons["fundsFormula"], in: app)
        XCTAssertTrue(app.buttons[identifier].waitForExistence(timeout: 5))
        // Independently verify that confirming removes the arrangement before restoring it.
        tap(app.buttons[identifier], in: app)
        tapAlertButton("endArrangementConfirm", label: "停掉以后的", in: confirmation)
        assertGone(confirmation); assertGone(app.buttons[identifier])
        calculation.buttons["closeSheet"].tap()
        tapUndo(messagePrefix: "结束安排", in: app)
        tap(app.buttons["fundsFormula"], in: app)
        XCTAssertTrue(app.buttons[identifier].waitForExistence(timeout: 5))
    }

    func testFixedBillEditorUsesInstallmentsAndAccountGatesAutomaticRecording() {
        let app = application("bills"); app.launch(); openFixedBills(app)
        tap(app.buttons["addFixedFlow"], in: app)
        XCTAssertFalse(app.staticTexts["到什么时候"].exists)
        XCTAssertFalse(app.staticTexts["90 天里会先留出"].exists)
        XCTAssertFalse(app.switches["fixedFlowAutoPay"].isEnabled)
        tap(app.textFields["金额"], in: app); app.textFields["金额"].typeText("10")
        tap(app.textFields["名字"], in: app); app.textFields["名字"].typeText("自动测试")
        tap(app.buttons["fixedFlowSchedule"], in: app)
        XCTAssertTrue(app.datePickers.firstMatch.waitForExistence(timeout: 5))
        tap(app.buttons["完成"], in: app)
        tap(app.buttons["fixedFlowInstallments"], in: app); tap(app.buttons["2 期"], in: app)
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

    func testDueCardIncludesPreviousMonthAndLinksOverflowToBills() {
        let app = application("bills-overdue", keepingUndo: true); app.launch()
        assertSelectedTab("tab_overview", in: app)
        let page = rootPage("tab_overview", in: app)
        let more = page.descendants(matching: .any).matching(identifier: "moreDueBills").firstMatch
        XCTAssertTrue(app.buttons["付了 上月账单"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label BEGINSWITH '付了 '")).count, 2)
        scrollToVisible(more, in: app, scroll: page.scrollViews["overviewScroll"].exists ? page.scrollViews["overviewScroll"] : nil)
        XCTAssertEqual(more.value as? String, "1")
        tap(app.buttons["付了 上月账单"], in: app)
        tapUndo(messagePrefix: "上月账单 ", in: app)
        XCTAssertTrue(app.buttons["付了 上月账单"].waitForExistence(timeout: 5))
        tap(app.buttons["付了 上月账单"], in: app)
        assertGone(app.buttons["付了 上月账单"])
        XCTAssertTrue(app.buttons["todayEntries"].label.contains("还没记"))
        tapUndo(messagePrefix: "上月账单 ", in: app)
        tap(more, in: app, scroll: page.scrollViews["overviewScroll"].exists ? page.scrollViews["overviewScroll"] : nil)
        XCTAssertTrue(app.navigationBars["固定收付"].waitForExistence(timeout: 5))
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
        XCTAssertFalse(suggestion.exists)
        tap(app.buttons["keypad_0"], in: app)
        XCTAssertTrue(suggestion.exists); XCTAssertFalse(suggestion.isSelected)
        tap(suggestion, in: app); tap(app.buttons["saveQuickEntry"], in: app)
        openFixedBills(app)
        XCTAssertFalse(app.buttons["付了 房租"].exists); XCTAssertTrue(app.images["已付 房租"].exists)
    }

    func testAutomaticBillsRecordOnceOnLaunchWithoutToast() {
        let app = application("bills-auto"); app.launch()
        let today = app.buttons["todayEntries"]
        XCTAssertTrue(today.waitForExistence(timeout: 5))
        let recorded = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS '1 笔'"), object: today)
        XCTAssertEqual(XCTWaiter.wait(for: [recorded], timeout: 5), .completed)
        XCTAssertFalse(app.buttons["付了 房租"].exists)
        XCTAssertFalse(app.staticTexts["自动记下完成"].exists)
        app.terminate(); app.launch()
        XCTAssertTrue(today.waitForExistence(timeout: 5)); XCTAssertTrue(today.label.contains("1 笔"))
        openFixedBills(app)
        XCTAssertFalse(app.buttons["付了 房租"].exists); XCTAssertTrue(app.images["已付 房租"].exists)
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
            tapUndo(messagePrefix: "话费 ", in: app)
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
        XCTAssertFalse(confirmation.buttons.matching(NSPredicate(format: "label == %@", "停掉以后的")).firstMatch.exists)
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

    func testEraseFromMeThenWelcomeBankImportRestoresTabsAndPagingWithoutRelaunch() {
        let app = application("welcome-import")
        app.launchEnvironment["YUBAI_UI_ERASE_REIMPORT"] = "1"
        let csv = "时间,收支,金额,名称,余额\n2001-01-02 12:00:00,支出,32.00,合成午餐,968.00\n2001-01-03 21:14:00,收入,200.00,合成工资,1168.00\n"
        app.launchEnvironment["YUBAI_UI_STATEMENT"] = Data(csv.utf8).base64EncodedString()
        app.launch()
        for cycle in 1...2 {
            assertSelectedTab("tab_overview", in: app)
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
            assertSelectedTab("tab_overview", in: app)
            assertPagingLocked(false, in: app)
            tap(app.buttons["tab_settings"], in: app)
            assertSelectedTab("tab_settings", in: app)
            XCTAssertTrue(app.buttons["openProfile"].isHittable)
            XCTAssertFalse(app.navigationBars["存储空间"].exists)
            tap(app.buttons["tab_overview"], in: app)
            assertSelectedTab("tab_overview", in: app)
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.2))
            start.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.2)))
            assertSelectedTab("tab_insights", in: app)
            tap(app.buttons["tab_overview"], in: app)
            assertSelectedTab("tab_overview", in: app)
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
        let app = application("entries")
        let arguments = app.launchArguments
        for category in ["UICTContentSizeCategoryL", "UICTContentSizeCategoryAccessibilityXL"] {
            app.launchArguments = arguments + ["-UIPreferredContentSizeCategoryName", category]
            app.launch()
            // Measure the native navigation region on a pushed page, then verify system back.
            // All four roots use the custom header; iOS 26 has no statusBars element.
            openFixedBills(app)
            let navigationBar = app.navigationBars["固定收付"]
            XCTAssertTrue(navigationBar.waitForExistence(timeout: 5))
            let window = app.windows.firstMatch
            XCTAssertTrue(window.exists)
            let safeTop = navigationBar.frame.minY
            XCTAssertGreaterThan(safeTop, window.frame.minY)
            tap(navigationBar.buttons["我"], in: app)
            assertSelectedTab("tab_settings", in: app)
            var titleY: CGFloat?
            for (tab, scrollID, firstContentID) in [("tab_overview", "overviewScroll", "fundsFormula"), ("tab_insights", "insightsScroll", "本周"), ("tab_entries", "entriesScroll", "entriesPreviousMonth"), ("tab_settings", "settingsScroll", "openProfile")] {
                tap(app.buttons[tab], in: app)
                assertSelectedTab(tab, in: app)
                let page = rootPage(tab, in: app), scroll = page.scrollViews[scrollID]
                let scrolls = tab != "tab_overview" || category == "UICTContentSizeCategoryAccessibilityXL"
                if scrolls { XCTAssertTrue(scroll.waitForExistence(timeout: 5)) }
                let headers = [page.staticTexts["rootHeaderTitle"], page.buttons["askYubai"]]
                for header in headers { XCTAssertTrue(header.isHittable) }
                if let titleY { XCTAssertEqual(headers[0].frame.minY, titleY, accuracy: 1) }
                else { titleY = headers[0].frame.minY }
                let headerBottom = max(headers[0].frame.maxY, headers[1].frame.maxY)
                let firstContent = page.buttons[firstContentID]
                if scrolls {
                    for _ in 0..<8 {
                        if firstContent.isHittable && firstContent.frame.minY >= headerBottom { break }
                        scroll.swipeDown()
                    }
                }
                XCTAssertTrue(firstContent.isHittable)
                XCTAssertGreaterThanOrEqual(firstContent.frame.minY, headerBottom)
                let originalFrames = headers.map(\.frame)
                if scrolls { for _ in 0..<4 { scroll.swipeUp() } }
                for (header, originalFrame) in zip(headers, originalFrames) {
                    XCTAssertTrue(header.isHittable)
                    XCTAssertGreaterThanOrEqual(header.frame.minY, safeTop)
                    XCTAssertTrue(window.frame.contains(header.frame))
                    XCTAssertEqual(header.frame.minY, originalFrame.minY, accuracy: 1)
                    XCTAssertEqual(header.frame.height, originalFrame.height, accuracy: 1)
                }
                if scrolls {
                    // Accessibility frames can include the clipped part of a partially visible row.
                    // Fully covered content must not be tappable, while the body remains usable.
                    let content = scroll.descendants(matching: .button).allElementsBoundByIndex
                    XCTAssertTrue(content.contains { $0.isHittable })
                    for element in content where element.frame.maxY <= headerBottom {
                        XCTAssertFalse(element.isHittable)
                    }
                }
                snapshot("\(category)-\(tab)-scrolled-safe-area", app)
            }
            if category == "UICTContentSizeCategoryL" { app.terminate() }
        }
        tap(addEntryTab(app), in: app)
        XCTAssertTrue(app.buttons["importFromEntry"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["askYubai"].isHittable)
        snapshot("scrolled-me-entry-sheet", app)
        tap(app.buttons["cancelManualSheet"], in: app)
        assertSelectedTab("tab_settings", in: app)
    }

    func testEntrySheetWithPurposeSuggestionsKeepsActionsAboveHomeIndicator() {
        let app = application("entries"); app.launch()
        let navigation = app.otherElements["mainNavigation"]
        XCTAssertTrue(navigation.waitForExistence(timeout: 5))
        // The floating bar ends 8pt above the bottom safe-area boundary.
        let safeBottom = navigation.frame.maxY + 8
        tap(addEntryTab(app), in: app)
        let form = app.scrollViews["entryFormScroll"]
        XCTAssertTrue(form.waitForExistence(timeout: 5))
        let recent = form.descendants(matching: .any).matching(identifier: "recentPurpose_合成账目 0").firstMatch
        scrollToVisible(recent, in: app, scroll: form)
        point(recent, x: 0.5, in: app).tap()
        XCTAssertEqual(app.textFields["entryPurpose"].value as? String, "合成账目 0")
        tap(app.buttons["keypad_3"], in: app)
        let save = app.buttons["saveQuickEntry"], again = app.buttons["saveAndAddAnother"]
        XCTAssertTrue(save.isHittable); XCTAssertTrue(again.isHittable)
        XCTAssertLessThanOrEqual(save.frame.maxY, again.frame.minY)
        XCTAssertLessThanOrEqual(again.frame.maxY, safeBottom - 12)
        let originalFrame = again.frame
        form.swipeUp()
        XCTAssertTrue(again.isHittable)
        XCTAssertEqual(again.frame.minY, originalFrame.minY, accuracy: 1)
        XCTAssertLessThanOrEqual(again.frame.maxY, safeBottom - 12)
        snapshot("entry-purpose-chips-safe-bottom", app)
        tap(again, in: app)
        XCTAssertEqual(app.staticTexts["entryKeypadAmount"].label, "0")
        XCTAssertTrue(again.exists); XCTAssertFalse(again.isEnabled)
    }

    func testOverviewAccessibilityXLScalesHeaderAndWrapsTodaySummary() {
        let app = application("overview-xl")
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        app.launch()
        let eye = app.buttons["toggleAmountVisibility"], ask = app.buttons["askYubai"]
        XCTAssertTrue(eye.waitForExistence(timeout: 5)); XCTAssertTrue(ask.exists)
        let normalEye = eye.frame.size, normalAsk = ask.frame.size
        app.terminate()
        app.launchArguments = Array(app.launchArguments.dropLast(2)) + ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"]
        app.launch()
        XCTAssertTrue(app.scrollViews["overviewScroll"].waitForExistence(timeout: 5))
        XCTAssertGreaterThan(eye.frame.width, normalEye.width)
        XCTAssertGreaterThan(ask.frame.width, normalAsk.width)
        XCTAssertEqual(eye.frame.width, ask.frame.width, accuracy: 1)
        XCTAssertEqual(eye.frame.height, ask.frame.height, accuracy: 1)
        XCTAssertLessThanOrEqual(eye.frame.width, 48)
        tap(eye, in: app); XCTAssertEqual(eye.label, "显示金额")
        tap(eye, in: app); XCTAssertEqual(eye.label, "隐藏金额")
        snapshot("overview-xl-header", app)
        let today = app.buttons["todayEntries"], summary = app.staticTexts["todayEntrySummary"]
        for _ in 0..<8 { if summary.isHittable { break }; app.scrollViews["overviewScroll"].swipeUp() }
        XCTAssertTrue(summary.isHittable)
        XCTAssertEqual(summary.label, "1 笔 · 合成测试的午饭和日用品以及下周旅行准备")
        XCTAssertGreaterThan(summary.frame.height, eye.frame.height)
        XCTAssertGreaterThanOrEqual(summary.frame.minX, today.frame.minX)
        XCTAssertLessThanOrEqual(summary.frame.maxX, today.frame.maxX)
        XCTAssertLessThanOrEqual(summary.frame.maxY, today.frame.maxY)
        snapshot("overview-xl-today-wrapped", app)
        tap(today, in: app); assertSelectedTab("tab_entries", in: app)
    }

    func testDonutSelectionChangesSummaryAndCanBeCleared() {
        let app = application("ask"); app.launch()
        tap(app.buttons["tab_insights"], in: app)
        let summary = app.buttons["donutSummary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertTrue(summary.label.contains("支出合计"))
        let slice = app.buttons["donutSlice_0"]
        XCTAssertTrue(slice.waitForExistence(timeout: 5))
        let center = summary.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let segment = center.withOffset(CGVector(dx: 78, dy: 0))
        segment.tap()
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS '餐饮 · 100%' AND label CONTAINS '共'"), object: summary)
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 5), .completed)
        XCTAssertTrue(slice.isSelected)
        snapshot("donut-selected", app)
        segment.tap()
        XCTAssertTrue(summary.label.contains("支出合计"))
        segment.tap()
        tap(summary, in: app)
        XCTAssertTrue(summary.label.contains("支出合计"))
        tap(app.buttons["insightCategory_0"], in: app)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "subcategoryInsights").firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["餐饮 · 本月"].exists)
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

    func testRootSwipeSkipsAddTabAndPushedPageKeepsSystemBack() {
        let app = application("ask"); app.launch()
        XCTAssertTrue(app.buttons["fundsFormula"].waitForExistence(timeout: 5))
        let left = app.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.2))
        let right = app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.2))
        right.press(forDuration: 0.05, thenDragTo: right.withOffset(CGVector(dx: -app.frame.width * 0.15, dy: 0)), withVelocity: .slow, thenHoldForDuration: 0.2)
        assertSelectedTab("tab_overview", in: app)
        XCTAssertFalse(app.buttons["saveQuickEntry"].exists)
        for identifier in ["tab_insights", "tab_entries", "tab_settings"] {
            right.press(forDuration: 0.05, thenDragTo: left)
            assertSelectedTab(identifier, in: app)
            XCTAssertFalse(app.buttons["saveQuickEntry"].exists)
        }
        for identifier in ["tab_entries", "tab_insights", "tab_overview"] {
            left.press(forDuration: 0.05, thenDragTo: right)
            assertSelectedTab(identifier, in: app)
        }
        tap(app.buttons["tab_settings"], in: app)
        assertSelectedTab("tab_settings", in: app)
        tap(app.buttons["openIntelligencePrivacy"], in: app)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "intelligencePrivacyPage").firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["智能与隐私"].waitForExistence(timeout: 5))
        assertGone(app.buttons["tab_settings"]); assertGone(addEntryTab(app))
        let middleLeft = app.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.4))
        let middleRight = app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.4))
        middleRight.press(forDuration: 0.05, thenDragTo: middleLeft)
        XCTAssertTrue(app.navigationBars["智能与隐私"].exists)
        middleLeft.press(forDuration: 0.05, thenDragTo: middleRight)
        XCTAssertTrue(app.navigationBars["智能与隐私"].exists)
        assertGone(app.buttons["tab_entries"])
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.45))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.45)))
        XCTAssertTrue(app.buttons["openIntelligencePrivacy"].waitForExistence(timeout: 5))
        XCTAssertTrue(addEntryTab(app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["tab_settings"].isSelected)
        left.press(forDuration: 0.05, thenDragTo: right)
        assertSelectedTab("tab_entries", in: app)
    }

    func testCancelledInsightBackKeepsTabBarHiddenAndPagingLocked() {
        let app = application("ask"); app.launch()
        tap(app.buttons["tab_insights"], in: app)
        tap(app.buttons["insightCategory_0"], in: app)
        assertPushedPage("餐饮 · 本月", in: app)
        let summary = app.descendants(matching: .any).matching(identifier: "subcategoryInsightsSummary").firstMatch
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertTrue(summary.isHittable)
        for _ in 0..<3 {
            dragBack(app, to: 0.18)
            assertPushedPage("餐饮 · 本月", in: app)
            // V15 adds tappable subcategory rows below this noninteractive summary.
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let summaryY = summary.frame.midY - app.frame.minY
            let left = origin.withOffset(CGVector(dx: app.frame.width * 0.2, dy: summaryY))
            let right = origin.withOffset(CGVector(dx: app.frame.width * 0.8, dy: summaryY))
            right.press(forDuration: 0.05, thenDragTo: left)
            assertPushedPage("餐饮 · 本月", in: app)
            left.press(forDuration: 0.05, thenDragTo: left.withOffset(CGVector(dx: app.frame.width * 0.12, dy: 0)), withVelocity: .slow, thenHoldForDuration: 0.5)
            assertPushedPage("餐饮 · 本月", in: app)
        }
        snapshot("insight-back-cancelled", app)
        let origin = app.coordinate(withNormalizedOffset: .zero), summaryY = summary.frame.midY - app.frame.minY
        origin.withOffset(CGVector(dx: app.frame.width * 0.2, dy: summaryY))
            .press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: app.frame.width * 0.8, dy: summaryY)), withVelocity: .slow, thenHoldForDuration: 0.5)
        assertGone(app.navigationBars["餐饮 · 本月"])
        assertCurrentTab("tab_insights", content: "insightCategory_0", in: app)
        let header = rootPage("tab_insights", in: app).staticTexts["rootHeaderTitle"]
        XCTAssertTrue(header.isHittable)
        let headerY = header.frame.midY - app.frame.minY
        origin.withOffset(CGVector(dx: app.frame.width * 0.8, dy: headerY))
            .press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: app.frame.width * 0.2, dy: headerY)))
        assertCurrentTab("tab_entries", content: "entriesSearchButton", in: app)
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
        tap(app.buttons["tab_overview"], in: app)
        assertCurrentTab("tab_overview", content: "fundsFormula", in: app)
    }

    func testCancelledOverviewBackRestoresTabBarOnlyAfterCompletedPop() {
        let app = application("bills-overdue"); app.launch()
        assertSelectedTab("tab_overview", in: app)
        let page = rootPage("tab_overview", in: app), navigation = app.otherElements["mainNavigation"]
        let more = page.descendants(matching: .any).matching(identifier: "moreDueBills").firstMatch
        scrollToVisible(more, in: app, scroll: page.scrollViews["overviewScroll"].exists ? page.scrollViews["overviewScroll"] : nil)
        XCTAssertLessThanOrEqual(more.frame.maxY, navigation.frame.minY)
        tap(more, in: app)
        assertPushedPage("固定收付", in: app)
        for _ in 0..<2 {
            dragBack(app, to: 0.18)
            assertPushedPage("固定收付", in: app)
        }
        dragBack(app, to: 0.95)
        assertCurrentTab("tab_overview", content: "moreDueBills", in: app)
        tap(app.buttons["tab_insights"], in: app)
        assertCurrentTab("tab_insights", content: "支出", in: app)
        tap(app.buttons["tab_overview"], in: app)
        assertCurrentTab("tab_overview", content: "moreDueBills", in: app)
    }

    func testSheetNavigationDoesNotHideRootTabBarAfterDismissal() {
        let app = application("manual"); app.launch()
        tap(app.buttons["tab_insights"], in: app)
        tap(app.buttons["askYubai"], in: app)
        tap(app.buttons["云端智能没开 ›"], in: app)
        XCTAssertTrue(app.navigationBars["智能与隐私"].waitForExistence(timeout: 5))
        dragBack(app, to: 0.42)
        XCTAssertTrue(app.navigationBars["智能与隐私"].isHittable)
        dragBack(app, to: 0.95)
        tap(app.buttons["closeSheet"], in: app)
        assertCurrentTab("tab_insights", content: "支出", in: app)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.2))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.2)))
        assertCurrentTab("tab_entries", content: "entriesSearchButton", in: app)
    }

    func testTabButtonsScrollToNonadjacentPagesAndPreservePageState() {
        let app = application("ask"); app.launch()
        for (identifier, content) in [("tab_settings", "openProfile"), ("tab_overview", "fundsFormula"), ("tab_entries", "entriesSearchButton"), ("tab_insights", "支出"), ("tab_entries", "entriesSearchButton")] {
            tap(app.buttons[identifier], in: app)
            assertSelectedTab(identifier, in: app)
            XCTAssertTrue(app.buttons[content].waitForExistence(timeout: 5)); XCTAssertTrue(app.buttons[content].isHittable)
            XCTAssertFalse(app.buttons["saveQuickEntry"].exists)
        }
        tap(app.buttons["entriesPreviousMonth"], in: app)
        let month = app.staticTexts["entriesMonth"].label
        tap(app.buttons["tab_overview"], in: app)
        tap(app.buttons["tab_entries"], in: app)
        assertSelectedTab("tab_entries", in: app)
        XCTAssertEqual(app.staticTexts["entriesMonth"].label, month)
        let start = app.staticTexts["本月收入"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: -200, dy: 0)))
        assertSelectedTab("tab_settings", in: app)
    }

    func testTabTapReturnsToLedgerAfterRightSwipe() {
        let app = application("ask"); app.launch(); tap(app.buttons["tab_entries"], in: app)
        assertCurrentTab("tab_entries", content: "entriesSearchButton", in: app)
        for _ in 0..<3 {
            let start = app.staticTexts["本月支出"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: app.frame.width * 0.6, dy: 0)))
            assertCurrentTab("tab_insights", content: "支出", in: app)
            tap(app.buttons["tab_entries"], in: app)
            assertCurrentTab("tab_entries", content: "entriesSearchButton", in: app)
        }
        tap(app.buttons["tab_entries"], in: app)
        assertCurrentTab("tab_entries", content: "entriesSearchButton", in: app)
    }

    func testTabTapReturnsToOverviewAfterLeftSwipe() {
        let app = application("ask"); app.launch()
        assertCurrentTab("tab_overview", content: "fundsFormula", in: app)
        let left = app.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.2))
        let right = app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.2))
        for _ in 0..<3 {
            right.press(forDuration: 0.05, thenDragTo: left)
            assertCurrentTab("tab_insights", content: "支出", in: app)
            tap(app.buttons["tab_overview"], in: app)
            assertCurrentTab("tab_overview", content: "fundsFormula", in: app)
        }
        tap(app.buttons["tab_entries"], in: app)
        assertCurrentTab("tab_entries", content: "entriesSearchButton", in: app)
        tap(app.buttons["tab_overview"], in: app)
        assertCurrentTab("tab_overview", content: "fundsFormula", in: app)
    }

    func testHorizontalFiltersKeepPagingAndVerticalScrollingSeparate() {
        let app = application("entries"); app.launch()
        tap(app.buttons["tab_entries"], in: app)
        let filter = app.buttons["entriesFilter_全部"]
        XCTAssertTrue(filter.waitForExistence(timeout: 5))
        let start = filter.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 180, dy: 0)))
        assertSelectedTab("tab_entries", in: app)
        XCTAssertTrue(filter.isSelected)
        let scroll = app.scrollViews["entriesScroll"]
        scroll.swipeUp()
        assertSelectedTab("tab_entries", in: app)
        XCTAssertFalse(app.textFields["editEntryAmount"].exists)
    }

    func testButlerSwipeDismissesWithoutSwitchingTabs() {
        let app = application("restrain"); app.launch()
        let title = app.staticTexts["butlerTitle_restrain"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        let card = app.descendants(matching: .any).matching(identifier: "butlerCard_restrain").firstMatch
        assertSelectedTab("tab_overview", in: app)
        let closedFrame = card.frame, titleX = title.frame.minX, action = app.buttons["dismissButler_restrain"]
        let middle = point(card, x: 0.5, y: 0.35, in: app)
        middle.press(forDuration: 0.05, thenDragTo: middle.withOffset(CGVector(dx: 80, dy: 0)))
        assertSelectedTab("tab_overview", in: app)
        assertRevealState(card, revealed: false, action: action, closedFrame: closedFrame)
        XCTAssertEqual(title.frame.minX, titleX, accuracy: 1)
        XCTAssertTrue(title.isHittable)
        let start = point(card, x: 0.8, y: 0.35, in: app)
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: -card.frame.width * 0.15, dy: 0)), withVelocity: .slow, thenHoldForDuration: 0.2)
        assertRevealState(card, revealed: false, action: action, closedFrame: closedFrame)
        XCTAssertEqual(title.frame.minX, titleX, accuracy: 1)
        XCTAssertTrue(title.exists)
        assertSelectedTab("tab_overview", in: app)
        let dismiss = point(card, x: 0.65, y: 0.35, in: app)
        dismiss.press(forDuration: 0.05, thenDragTo: dismiss.withOffset(CGVector(dx: -card.frame.width * 0.35, dy: 0)), withVelocity: .slow, thenHoldForDuration: 0.2)
        assertGone(title)
        assertSelectedTab("tab_overview", in: app)
    }

    func testButlerFastShortSwipeDismisses() {
        let app = application("restrain"); app.launch()
        let title = app.staticTexts["butlerTitle_restrain"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        let card = app.descendants(matching: .any).matching(identifier: "butlerCard_restrain").firstMatch
        let start = card.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.35))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: -card.frame.width * 0.2, dy: 0)), withVelocity: XCUIGestureVelocity(1200), thenHoldForDuration: 0)
        assertGone(title)
        assertSelectedTab("tab_overview", in: app)
        XCTAssertTrue(app.buttons["fundsFormula"].isHittable)
    }

    func testButlerFastLongSwipeDismissesWithoutPaging() {
        let app = application("restrain"); app.launch()
        let title = app.staticTexts["butlerTitle_restrain"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        let card = app.descendants(matching: .any).matching(identifier: "butlerCard_restrain").firstMatch
        let start = card.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.35))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: -card.frame.width * 0.7, dy: 0)), withVelocity: XCUIGestureVelocity(1000), thenHoldForDuration: 0)
        assertGone(title)
        assertSelectedTab("tab_overview", in: app)
        XCTAssertTrue(app.buttons["fundsFormula"].isHittable)
        XCTAssertFalse(app.buttons["支出"].exists)
    }

    func testButlerRightSwipeAtFirstPagePreservesCardAndPaging() {
        let app = application("restrain"); app.launch()
        let title = app.staticTexts["butlerTitle_restrain"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        let card = app.descendants(matching: .any).matching(identifier: "butlerCard_restrain").firstMatch
        assertSelectedTab("tab_overview", in: app)
        let closedFrame = card.frame, titleX = title.frame.minX, action = app.buttons["dismissButler_restrain"]
        for velocity in [XCUIGestureVelocity.slow, XCUIGestureVelocity(1000)] {
            let start = point(card, x: 0.15, y: 0.35, in: app)
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: card.frame.width * 0.7, dy: 0)), withVelocity: velocity, thenHoldForDuration: 0)
            assertCurrentTab("tab_overview", content: "fundsFormula", in: app)
            assertRevealState(card, revealed: false, action: action, closedFrame: closedFrame)
            XCTAssertEqual(title.frame.minX, titleX, accuracy: 1)
            XCTAssertTrue(title.isHittable)
        }
        let left = app.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.2))
        let right = app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.2))
        right.press(forDuration: 0.05, thenDragTo: left)
        assertCurrentTab("tab_insights", content: "支出", in: app)
        left.press(forDuration: 0.05, thenDragTo: right)
        assertCurrentTab("tab_overview", content: "fundsFormula", in: app)
        XCTAssertTrue(title.isHittable)
    }

    func testClosedLedgerRowPagesRightAndRevealedRowClosesFirst() {
        let app = application("ask"); app.launch(); tap(app.buttons["tab_entries"], in: app)
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'ledgerEntry_' ")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        let delete = app.buttons[row.identifier.replacingOccurrences(of: "ledgerEntry_", with: "deleteLedgerEntry_")], closedFrame = row.frame
        assertRevealState(row, revealed: false, action: delete, closedFrame: closedFrame)
        swipeRow(row, left: false)
        assertCurrentTab("tab_insights", content: "支出", in: app)
        XCTAssertFalse(app.textFields["editEntryAmount"].exists)
        tap(app.buttons["tab_entries"], in: app)
        assertCurrentTab("tab_entries", content: "entriesSearchButton", in: app)
        assertRevealState(row, revealed: false, action: delete, closedFrame: closedFrame)
        swipeRow(row)
        assertRevealState(row, revealed: true, action: delete)
        swipeRow(row, left: false)
        assertRevealState(row, revealed: false, action: delete, closedFrame: closedFrame)
        assertCurrentTab("tab_entries", content: "entriesSearchButton", in: app)
        swipeRow(row, left: false)
        assertCurrentTab("tab_insights", content: "支出", in: app)
        XCTAssertFalse(app.textFields["editEntryAmount"].exists)
    }

    func testRevealedLedgerRowConsumesSwipesInBothDirections() {
        let app = application("ask"); app.launch(); tap(app.buttons["tab_entries"], in: app)
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'ledgerEntry_' ")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        let delete = app.buttons[row.identifier.replacingOccurrences(of: "ledgerEntry_", with: "deleteLedgerEntry_")], closedFrame = row.frame
        assertRevealState(row, revealed: false, action: delete, closedFrame: closedFrame)
        swipeRow(row)
        assertRevealState(row, revealed: true, action: delete)
        for element in [row, delete] {
            let start = point(element, x: 0.5, in: app)
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: -80, dy: 0)), withVelocity: XCUIGestureVelocity(1000), thenHoldForDuration: 0)
            assertSelectedTab("tab_entries", in: app)
            assertRevealState(row, revealed: true, action: delete)
            assertPagingLocked(true, in: app)
            XCTAssertFalse(app.textFields["editEntryAmount"].exists)
        }
        let start = point(row, x: 0.4, in: app)
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 30, dy: 0)), withVelocity: .slow, thenHoldForDuration: 0.2)
        assertRevealState(row, revealed: false, action: delete, closedFrame: closedFrame)
        assertSelectedTab("tab_entries", in: app)
        assertPagingLocked(false, in: app)
        XCTAssertFalse(app.textFields["editEntryAmount"].exists)
        tap(row, in: app)
        XCTAssertTrue(app.textFields["editEntryAmount"].waitForExistence(timeout: 5))
    }

    func testOnlyOneLedgerRowRevealsDeleteAndOutsideTapClosesIt() {
        let app = application("entries"); app.launch(); tap(app.buttons["tab_entries"], in: app)
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'ledgerEntry_' "))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5))
        let first = app.buttons[rows.element(boundBy: 0).identifier], second = app.buttons[rows.element(boundBy: 1).identifier]
        XCTAssertTrue(first.isHittable); XCTAssertTrue(second.isHittable)
        let firstDelete = app.buttons[first.identifier.replacingOccurrences(of: "ledgerEntry_", with: "deleteLedgerEntry_")]
        let secondDelete = app.buttons[second.identifier.replacingOccurrences(of: "ledgerEntry_", with: "deleteLedgerEntry_")]
        let firstFrame = first.frame, secondFrame = second.frame
        assertRevealState(first, revealed: false, action: firstDelete, closedFrame: firstFrame)
        assertRevealState(second, revealed: false, action: secondDelete, closedFrame: secondFrame)
        swipeRow(first)
        assertRevealState(first, revealed: true, action: firstDelete)
        swipeRow(second)
        assertRevealState(first, revealed: false, action: firstDelete, closedFrame: firstFrame)
        assertRevealState(second, revealed: true, action: secondDelete)
        swipeRow(first)
        assertRevealState(second, revealed: false, action: secondDelete, closedFrame: secondFrame)
        assertRevealState(first, revealed: true, action: firstDelete)
        XCTAssertEqual(rows.matching(NSPredicate(format: "value == 'revealed'")).count, 1)
        assertSelectedTab("tab_entries", in: app)
        app.staticTexts["本月收入"].tap()
        assertRevealState(first, revealed: false, action: firstDelete, closedFrame: firstFrame)
        XCTAssertEqual(rows.matching(NSPredicate(format: "value == 'revealed'")).count, 0)
        assertPagingLocked(false, in: app)
        XCTAssertFalse(app.textFields["editEntryAmount"].exists)
    }

    func testRevealedLedgerRowSlowLeftSwipeKeepsCurrentTab() {
        let app = application("ask"); app.launch(); tap(app.buttons["tab_entries"], in: app)
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'ledgerEntry_' ")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        let delete = app.buttons[row.identifier.replacingOccurrences(of: "ledgerEntry_", with: "deleteLedgerEntry_")], closedFrame = row.frame
        assertRevealState(row, revealed: false, action: delete, closedFrame: closedFrame)
        swipeRow(row)
        assertRevealState(row, revealed: true, action: delete)
        for _ in 0..<3 {
            let start = point(row, x: 0.9, in: app)
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: -200, dy: 0)), withVelocity: XCUIGestureVelocity(200 / 0.6), thenHoldForDuration: 0)
            assertSelectedTab("tab_entries", in: app)
            assertRevealState(row, revealed: true, action: delete)
            assertPagingLocked(true, in: app)
            XCTAssertFalse(app.textFields["editEntryAmount"].exists)
        }
        swipeRow(row, left: false)
        assertRevealState(row, revealed: false, action: delete, closedFrame: closedFrame)
        assertPagingLocked(false, in: app)
        let start = rootPage("tab_entries", in: app).staticTexts["本月收入"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: -200, dy: 0)))
        assertSelectedTab("tab_settings", in: app)
    }

    func testLedgerRevealClosesAfterTabSelectionAndPaging() {
        let app = application("ask"); app.launch(); tap(app.buttons["tab_entries"], in: app)
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'ledgerEntry_' ")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        let delete = app.buttons[row.identifier.replacingOccurrences(of: "ledgerEntry_", with: "deleteLedgerEntry_")], closedFrame = row.frame
        assertRevealState(row, revealed: false, action: delete, closedFrame: closedFrame)
        swipeRow(row)
        assertRevealState(row, revealed: true, action: delete)
        tap(app.buttons["tab_overview"], in: app); tap(app.buttons["tab_entries"], in: app)
        assertSelectedTab("tab_entries", in: app); assertRevealState(row, revealed: false, action: delete, closedFrame: closedFrame)
        swipeRow(row)
        assertRevealState(row, revealed: true, action: delete)
        let start = app.staticTexts["本月收入"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: -200, dy: 0)))
        assertSelectedTab("tab_entries", in: app); assertRevealState(row, revealed: true, action: delete)
        assertPagingLocked(true, in: app)
        rootPage("tab_entries", in: app).staticTexts["本月收入"].tap()
        assertRevealState(row, revealed: false, action: delete, closedFrame: closedFrame)
        assertPagingLocked(false, in: app)
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: -200, dy: 0)))
        assertSelectedTab("tab_settings", in: app)
        tap(app.buttons["tab_entries"], in: app)
        assertSelectedTab("tab_entries", in: app); assertRevealState(row, revealed: false, action: delete, closedFrame: closedFrame)
        XCTAssertFalse(app.textFields["editEntryAmount"].exists)
    }

    func testLedgerRowSwipesDoNotOpenEditorAndTapStillWorks() {
        let app = application("ask"); app.launch()
        tap(app.buttons["tab_entries"], in: app)
        XCTAssertFalse(app.buttons["addFromEntries"].exists)
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'ledgerEntry_' ")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        let start = row.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: -40, dy: 0)), withVelocity: .slow, thenHoldForDuration: 0.2)
        XCTAssertTrue(app.buttons["tab_entries"].isSelected)
        XCTAssertFalse(app.textFields["editEntryAmount"].exists)
        start.press(forDuration: 0.05, thenDragTo: row.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)))
        XCTAssertTrue(app.buttons["tab_entries"].isSelected)
        XCTAssertFalse(app.textFields["editEntryAmount"].exists)
        swipeRow(row, left: false)
        let heading = app.staticTexts["本月收入"]
        let tabSwipe = heading.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        tabSwipe.press(forDuration: 0.05, thenDragTo: tabSwipe.withOffset(CGVector(dx: -180, dy: 0)))
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == true"), object: app.buttons["tab_settings"])
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 5), .completed)
        XCTAssertFalse(app.textFields["editEntryAmount"].exists); XCTAssertFalse(app.buttons["saveQuickEntry"].exists)
        tap(app.buttons["tab_entries"], in: app)
        let backSwipe = app.staticTexts["本月支出"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        backSwipe.press(forDuration: 0.05, thenDragTo: backSwipe.withOffset(CGVector(dx: 220, dy: 0)))
        let previous = XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == true"), object: app.buttons["tab_insights"])
        XCTAssertEqual(XCTWaiter.wait(for: [previous], timeout: 5), .completed)
        XCTAssertFalse(app.textFields["editEntryAmount"].exists)
        tap(app.buttons["tab_entries"], in: app); tap(row, in: app)
        XCTAssertTrue(app.textFields["editEntryAmount"].waitForExistence(timeout: 5))
        tap(app.buttons["cancelManualSheet"], in: app)
        tap(addEntryTab(app), in: app)
        XCTAssertTrue(app.buttons["saveQuickEntry"].waitForExistence(timeout: 5))
    }

    func testLedgerMonthFiltersAndSearchToggle() {
        let app = application("ask"); app.launch(); tap(app.buttons["tab_entries"], in: app)
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'ledgerEntry_' "))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["entriesSearch"].exists)
        tap(app.buttons["entriesFilter_收入"], in: app)
        XCTAssertTrue(app.staticTexts["还没有这类账目"].waitForExistence(timeout: 5)); XCTAssertEqual(rows.count, 0)
        tap(app.buttons["entriesFilter_没分类"], in: app); XCTAssertEqual(rows.count, 0)
        tap(app.buttons["entriesFilter_支出"], in: app); XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5))
        tap(app.buttons["entriesFilter_全部"], in: app)
        tap(app.buttons["entriesPreviousMonth"], in: app)
        XCTAssertTrue(app.staticTexts["这个月还没有账目"].waitForExistence(timeout: 5))
        tap(app.buttons["entriesNextMonth"], in: app); XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5))
        tap(app.buttons["entriesSearchButton"], in: app)
        let search = app.textFields["entriesSearch"]
        tap(search, in: app); search.typeText("32.00")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5))
        search.typeText("999")
        XCTAssertTrue(app.staticTexts["没有找到这笔"].waitForExistence(timeout: 5))
        tap(app.buttons["entriesSearchButton"], in: app)
        XCTAssertFalse(search.exists); XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5))
    }

    func testLedgerSwipeDeleteAndUndoRestoresRow() {
        let app = application("ask", keepingUndo: true); app.launch(); tap(app.buttons["tab_entries"], in: app)
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'ledgerEntry_' ")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        let identifier = row.identifier
        swipeRow(row)
        XCTAssertFalse(app.textFields["editEntryAmount"].exists)
        let delete = app.buttons[identifier.replacingOccurrences(of: "ledgerEntry_", with: "deleteLedgerEntry_")]
        assertRevealState(row, revealed: true, action: delete)
        tap(delete, in: app)
        tapUndo(messagePrefix: "删除这笔", in: app)
        XCTAssertTrue(app.buttons[identifier].waitForExistence(timeout: 5))
        swipeRow(app.buttons[identifier]); assertRevealState(app.buttons[identifier], revealed: true, action: delete)
        tap(delete, in: app)
        assertGone(app.buttons[identifier])
        tapUndo(messagePrefix: "删除这笔", in: app)
        XCTAssertTrue(app.buttons[identifier].waitForExistence(timeout: 5))
        assertSelectedTab("tab_entries", in: app)
    }

    func testDonutSwipeDoesNotSelectSlice() {
        let app = application("ask"); app.launch()
        tap(app.buttons["tab_insights"], in: app)
        let summary = app.buttons["donutSummary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        let start = summary.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).withOffset(CGVector(dx: 78, dy: 0))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: -app.frame.width * 0.5, dy: 0)))
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == true"), object: app.buttons["tab_entries"])
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 5), .completed)
        tap(app.buttons["tab_insights"], in: app)
        XCTAssertTrue(summary.waitForExistence(timeout: 5)); XCTAssertTrue(summary.label.contains("支出合计"))
        XCTAssertFalse(app.buttons["donutSlice_0"].isSelected)
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "subcategoryInsights").firstMatch.exists)
        XCTAssertFalse(app.navigationBars["餐饮 · 本月"].exists)
        // The legend now opens subcategories. A horizontal drag must still page,
        // without activating that NavigationLink on release.
        let category = app.buttons["insightCategory_0"]
        XCTAssertTrue(category.isHittable)
        swipeRow(category)
        assertCurrentTab("tab_entries", content: "entriesSearchButton", in: app)
        tap(app.buttons["tab_insights"], in: app)
        XCTAssertTrue(category.isHittable)
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "subcategoryInsights").firstMatch.exists)
        XCTAssertFalse(app.buttons["donutSlice_0"].isSelected)
    }

    func testLedgerRowsStillScrollVerticallyAndOpenWithTap() {
        let app = application("entries"); app.launch()
        tap(app.buttons["tab_entries"], in: app)
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'ledgerEntry_' "))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5))
        let first = app.buttons[rows.firstMatch.identifier]
        let delete = app.buttons[first.identifier.replacingOccurrences(of: "ledgerEntry_", with: "deleteLedgerEntry_")]
        swipeRow(first)
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        let start = first.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -180)))
        XCTAssertTrue(app.buttons["tab_entries"].isSelected); XCTAssertFalse(app.textFields["editEntryAmount"].exists)
        assertNotHittable(delete)
        XCTAssertFalse(first.isHittable)
        let visible = rows.allElementsBoundByIndex.first { $0.isHittable }
        XCTAssertNotNil(visible)
        if let visible { tap(visible, in: app) }
        XCTAssertTrue(app.textFields["editEntryAmount"].waitForExistence(timeout: 5))
    }

    func testOverviewRowSwipeAtTabBoundaryDoesNotTapRow() {
        let app = application("ask"); app.launch()
        let row = app.buttons["todayEntries"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        let start = row.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: row.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)))
        XCTAssertTrue(app.buttons["tab_overview"].isSelected)
        XCTAssertFalse(app.buttons["saveQuickEntry"].exists)
        tap(row, in: app)
        XCTAssertTrue(app.buttons["entriesSearchButton"].waitForExistence(timeout: 5))
    }

    func testForecastHoldAndDragKeepsTheCurrentTab() {
        let app = application("ask"); app.launch()
        let chart = app.descendants(matching: .any).matching(identifier: "forecastChart").firstMatch
        XCTAssertTrue(chart.waitForExistence(timeout: 5))
        let start = chart.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
        start.press(forDuration: 0.3, thenDragTo: chart.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)))
        XCTAssertTrue(app.buttons["tab_overview"].isSelected)
        XCTAssertTrue(chart.exists)
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
        let identifiers = ["tab_overview", "tab_insights", "addEntry", "tab_entries", "tab_settings"]
        let tabs = app.buttons.matching(NSPredicate(format: "identifier IN %@", identifiers)).allElementsBoundByIndex
        XCTAssertEqual(tabs.count, 5)
        XCTAssertEqual(tabs.map(\.label), ["现在", "洞察", "记一笔", "账目", "我"])
        XCTAssertEqual(app.otherElements["mainNavigation"].label, "主导航")
        XCTAssertTrue(app.buttons["tab_overview"].isSelected)
        XCTAssertFalse(app.buttons["tab_insights"].isSelected)
        XCTAssertFalse(app.buttons["tab_entries"].isSelected)
        XCTAssertFalse(app.buttons["tab_settings"].isSelected)
        XCTAssertFalse(app.buttons["addEntry"].isSelected)
        XCTAssertTrue(app.buttons["tab_overview"].exists); XCTAssertTrue(app.buttons["tab_insights"].exists); XCTAssertTrue(app.buttons["tab_settings"].exists)
        XCTAssertTrue(app.buttons["tab_entries"].exists)
        XCTAssertTrue(addEntryTab(app).exists); XCTAssertTrue(app.buttons["askYubai"].exists)
        snapshot("overview", app)
        tap(app.buttons["tab_insights"], in: app)
        XCTAssertTrue(app.buttons["支出"].waitForExistence(timeout: 5))
        snapshot("insights", app)
        tap(app.buttons["tab_overview"], in: app)
        tap(funds, in: app)
        XCTAssertFalse(addEntryTab(app).isHittable)
        XCTAssertTrue(app.staticTexts["现金"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["日常开销"].exists)
        snapshot("funds-detail", app)
    }

    func testManualAndAskActionsPreserveTheSelectedPage() {
        let app = application("ask"); app.launch()
        tap(app.buttons["tab_insights"], in: app)
        assertSelectedTab("tab_insights", in: app)
        tap(rootPage("tab_insights", in: app).buttons["askYubai"], in: app)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "askInput").firstMatch.waitForExistence(timeout: 5))
        app.navigationBars.firstMatch.swipeLeft()
        tap(app.buttons["closeSheet"], in: app)
        XCTAssertTrue(app.buttons["tab_insights"].waitForExistence(timeout: 5))
        assertSelectedTab("tab_insights", in: app)
        XCTAssertTrue(app.buttons["支出"].exists)
        for identifier in ["tab_overview", "tab_insights", "tab_entries", "tab_settings"] {
            let tab = app.buttons[identifier]
            tap(tab, in: app)
            if identifier == "tab_entries" { XCTAssertTrue(app.buttons["entriesSearchButton"].waitForExistence(timeout: 5)) }
            if identifier == "tab_settings" {
                XCTAssertFalse(app.buttons["openEntries"].exists)
                XCTAssertTrue(app.buttons["openFixedFlows"].exists)
            }
            tap(addEntryTab(app), in: app)
            XCTAssertTrue(app.buttons["saveQuickEntry"].waitForExistence(timeout: 5))
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let headerY = app.buttons["cancelManualSheet"].frame.midY - app.frame.minY
            origin.withOffset(CGVector(dx: app.frame.width * 0.3, dy: headerY))
                .press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: app.frame.width * 0.7, dy: headerY)))
            tap(app.buttons["cancelManualSheet"], in: app)
            assertSelectedTab(identifier, in: app)
        }
    }

    func testFloatingNavigationHidesForKeyboardAndLeavesLastLedgerRowVisible() throws {
        let app = application("entries"); app.launch()
        tap(app.buttons["tab_entries"], in: app)
        tap(app.buttons["entriesSearchButton"], in: app)
        let search = app.textFields["entriesSearch"]
        tap(search, in: app); search.typeText("UI")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        assertNotHittable(addEntryTab(app))
        search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 2))
        let scroll = app.scrollViews["entriesScroll"]
        dismissKeyboard(in: app, scroll: scroll)
        XCTAssertTrue(addEntryTab(app).waitForExistence(timeout: 5))
        let visible = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: addEntryTab(app))
        XCTAssertEqual(XCTWaiter.wait(for: [visible], timeout: 5), .completed)
        assertSelectedTab("tab_entries", in: app)
        for _ in 0..<8 { scrollVertically(scroll, in: app) }
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'ledgerEntry_' ")).allElementsBoundByIndex
        let last = try XCTUnwrap(rows.last)
        XCTAssertTrue(last.isHittable)
        XCTAssertLessThanOrEqual(last.frame.maxY, addEntryTab(app).frame.minY)
        XCTAssertTrue(app.buttons["tab_entries"].isSelected)
        let lastIdentifier = last.identifier
        tap(app.buttons["tab_overview"], in: app); tap(app.buttons["tab_entries"], in: app)
        let restored = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: app.buttons[lastIdentifier])
        XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 5), .completed)
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
        XCTAssertEqual(app.staticTexts["entryKeypadAmount"].label, "15.00")
        XCTAssertEqual(app.buttons["saveQuickEntry"].label, "记下 15.00 元")
    }

    func testTransferWithOneAccountCanAddDestinationWithoutLosingDraft() {
        let app = application("manual"); app.launch() // One active account, no entries.
        tap(addEntryTab(app), in: app)
        tap(app.buttons["keypad_5"], in: app)
        tap(app.buttons["keypad_0"], in: app); tap(app.buttons["keypad_0"], in: app)
        let purpose = app.textFields["entryPurpose"]
        tap(purpose, in: app); purpose.typeText("UI Transfer"); purpose.typeText("\n")
        tap(app.buttons["转账"], in: app)
        let save = app.buttons["saveQuickEntry"], again = app.buttons["saveAndAddAnother"]
        let addAccount = app.buttons["transferAddAccount"]
        XCTAssertTrue(addAccount.waitForExistence(timeout: 5))
        XCTAssertEqual(addAccount.label, "添加账户")
        XCTAssertTrue(app.staticTexts["转出"].exists); XCTAssertTrue(app.staticTexts["转入"].exists)
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
        XCTAssertEqual(app.staticTexts["entryKeypadAmount"].label, "500")
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
        XCTAssertEqual(app.staticTexts["entryKeypadAmount"].label, "500")
        XCTAssertEqual(purpose.value as? String, "UI Transfer")
        XCTAssertTrue(app.buttons["转账"].isSelected); XCTAssertTrue(app.buttons["今天"].exists)
        tap(save, in: app)
        assertGone(save)

        tap(app.buttons["tab_entries"], in: app)
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'ledgerEntry_'"))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(rows.count, 1)
        XCTAssertTrue(rows.firstMatch.label.contains("UI Transfer"))
        tap(rows.firstMatch, in: app)
        XCTAssertTrue(app.textFields["editEntryAmount"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["editEntryAmount"].value as? String, "500")
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

    func testManualKeypadSaveTodayEditAndDelete() {
        let app = application("manual"); app.launch()
        let funds = app.buttons["fundsFormula"]
        XCTAssertTrue(funds.waitForExistence(timeout: 10))
        XCTAssertTrue(funds.label.contains("1,000.00"))
        tap(addEntryTab(app), in: app)
        tap(app.buttons["keypad_3"], in: app); tap(app.buttons["keypad_2"], in: app)
        XCTAssertEqual(app.staticTexts["entryKeypadAmount"].label, "32")
        snapshot("manual-draft", app)
        tap(app.buttons["saveQuickEntry"], in: app)
        let today = app.buttons["todayEntries"]
        let saved = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS '−32.00'"), object: today)
        XCTAssertEqual(XCTWaiter.wait(for: [saved], timeout: 10), .completed)
        XCTAssertTrue(today.label.contains("1 笔"))
        let decreased = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS '968.00'"), object: funds)
        XCTAssertEqual(XCTWaiter.wait(for: [decreased], timeout: 10), .completed)
        snapshot("manual-saved", app)
        tap(today, in: app)
        XCTAssertTrue(app.buttons["tab_entries"].isSelected)
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'ledgerEntry_' ")).firstMatch
        tap(row, in: app)
        XCTAssertTrue(app.textFields["editEntryAmount"].waitForExistence(timeout: 5))
        snapshot("manual-edit", app)
        tap(app.buttons["deleteEntry"], in: app)
        assertGone(row)
        snapshot("manual-deleted", app)
        tap(app.buttons["tab_overview"], in: app)
        XCTAssertTrue(app.buttons["todayEntries"].label.contains("还没记"))
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
        tap(app.buttons["tab_overview"], in: app)
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

    func testRestrainCardCanBeMutedAcrossLaunches() {
        let app = application("restrain"); app.launch()
        let card = app.staticTexts["butlerTitle_restrain"]
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        snapshot("restrain-card", app)
        tap(app.buttons["butlerOptions_restrain"], in: app)
        snapshot("card-options", app)
        tap(app.buttons["以后别提"], in: app)
        assertGone(card)
        snapshot("card-muted", app)
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["fundsFormula"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["butlerTitle_restrain"].exists)
        snapshot("muted-after-relaunch", app)
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
    func testForecastPlaysOncePerVisitAcrossScrollingAndViewLifetimes() {
        var motion = MotionVisitState()
        XCTAssertTrue(motion.claim(0)); XCTAssertFalse(motion.claim(0))
        XCTAssertTrue(motion.claim(1)); XCTAssertFalse(motion.claim(1))
        XCTAssertTrue(motion.claim(2)); XCTAssertFalse(motion.claim(2))
    }
    func testReducedMotionSkipsPlaybackAndDoesNotReplayDuringSameVisit() {
        var motion = MotionVisitState()
        XCTAssertFalse(motion.claim(0, reduceMotion: true)); XCTAssertFalse(motion.claim(0))
        XCTAssertTrue(motion.claim(1)); XCTAssertFalse(motion.claim(1, reduceMotion: true))
        XCTAssertTrue(motion.claim(2))
    }
    func testChartClaimsSurviveViewLifetimesAndStayIndependent() {
        var session = MotionSessionState()
        XCTAssertFalse(session.contains("forecast"))
        XCTAssertTrue(session.claim("forecast"))
        XCTAssertTrue(session.contains("forecast"))
        XCTAssertFalse(session.claim("forecast"))
        XCTAssertTrue(session.claim("donut"))
        var nextLaunch = MotionSessionState()
        XCTAssertTrue(nextLaunch.claim("forecast"))
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
