import XCTest

/// Every launch uses a fresh UUID directory and simulator-only scripted transport.
/// No Keychain configuration or network connection is needed.
final class AppFlowTests: XCTestCase {
    private var currentApp: XCUIApplication?
    private var snapshotNumber = 0

    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws {
        if let app = currentApp, (testRun?.totalFailureCount ?? 0) > 0 { snapshot("failure", app) }
        currentApp = nil
        try super.tearDownWithError()
    }

    private func application(_ fixture: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--test-ledger", UUID().uuidString, "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launchEnvironment["YUBAI_UI_TEST_SCRIPT"] = fixture
        app.launchEnvironment["DEEPSEEK_API_KEY"] = ""
        currentApp = app; snapshotNumber = 0
        return app
    }
    private func snapshot(_ name: String, _ app: XCUIApplication) {
        snapshotNumber += 1
        let test = app.launchEnvironment["YUBAI_UI_TEST_SCRIPT"] ?? "app-flow"
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "\(test)-\(String(format: "%02d", snapshotNumber))-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
    private func tap(_ element: XCUIElement, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 10), file: file, line: line)
        for _ in 0..<8 { if element.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(element.isHittable, file: file, line: line)
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 10), .completed, file: file, line: line)
        element.tap()
    }
    private func assertGone(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 10), .completed, file: file, line: line)
    }

    private func addEntryTab(_ app: XCUIApplication) -> XCUIElement {
        let identified = app.tabBars.buttons["addEntry"]
        return identified.exists ? identified : app.tabBars.buttons["记一笔"]
    }

    func testStorageEntryAndOverviewOpenFromMe() {
        let app = application("ask"); app.launch()
        tap(app.tabBars.buttons["我"], in: app)
        tap(app.buttons["openStorage"], in: app)
        XCTAssertTrue(app.navigationBars["存储空间"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "storageHeadline").firstMatch.exists)
        XCTAssertTrue(app.buttons["openStoragePhotos"].exists)
        XCTAssertTrue(app.buttons["openStorageHistory"].exists)
        XCTAssertTrue(app.buttons["openStorageErase"].exists)
        XCTAssertFalse(addEntryTab(app).isHittable)
        snapshot("storage-overview", app)
        tap(app.buttons["openStoragePhotos"], in: app)
        XCTAssertTrue(app.staticTexts["账单原件不删，导入记录里仍可撤销。"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["半年前"].isSelected)
        snapshot("storage-photos", app)
    }

    func testFirstLaunchEmptyLedgerAccountAndAvailableFunds() {
        let app = application("empty"); app.launch()
        snapshot("welcome", app)
        tap(app.buttons["startLedger"], in: app)
        XCTAssertTrue(app.staticTexts["从真实余额开始"].waitForExistence(timeout: 5))
        snapshot("empty-ledger", app)
        tap(app.buttons["addFirstAccount"], in: app)
        snapshot("add-account", app)
        tap(app.textFields["accountName"], in: app); app.textFields["accountName"].typeText("UI Bank")
        tap(app.textFields["accountBalance"], in: app); app.textFields["accountBalance"].typeText("1000")
        tap(app.buttons["saveAccount"], in: app)
        let funds = app.buttons["fundsFormula"]
        XCTAssertTrue(funds.waitForExistence(timeout: 10))
        // A newly opened ledger has no known obligations or spending estimate.
        XCTAssertTrue(funds.label.contains("还能自在支配")); XCTAssertTrue(funds.label.contains("1,000"))
        XCTAssertEqual(app.tabBars.buttons.count, 4)
        XCTAssertTrue(app.tabBars.buttons["现在"].exists); XCTAssertTrue(app.tabBars.buttons["洞察"].exists); XCTAssertTrue(app.tabBars.buttons["我"].exists)
        XCTAssertTrue(addEntryTab(app).exists); XCTAssertTrue(app.buttons["askYubai"].exists)
        snapshot("overview", app)
        tap(app.tabBars.buttons["洞察"], in: app)
        XCTAssertTrue(app.buttons["支出 · 按类型"].waitForExistence(timeout: 5))
        snapshot("insights", app)
        tap(app.tabBars.buttons["现在"], in: app)
        tap(funds, in: app)
        XCTAssertFalse(addEntryTab(app).isHittable)
        XCTAssertTrue(app.staticTexts["可支配现金"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["减：日常生活预留"].exists)
        snapshot("funds-detail", app)
    }

    func testManualAndAskActionsPreserveTheSelectedPage() {
        let app = application("ask"); app.launch()
        tap(app.tabBars.buttons["洞察"], in: app)
        XCTAssertTrue(app.tabBars.buttons["洞察"].isSelected)
        tap(app.buttons["askYubai"], in: app)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "askInput").firstMatch.waitForExistence(timeout: 5))
        tap(app.buttons["closeSheet"], in: app)
        XCTAssertTrue(app.tabBars.buttons["洞察"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["洞察"].isSelected)
        XCTAssertTrue(app.buttons["支出 · 按类型"].exists)
        tap(addEntryTab(app), in: app)
        XCTAssertTrue(app.buttons["saveQuickEntry"].waitForExistence(timeout: 5))
        tap(app.buttons["cancelManualSheet"], in: app)
        XCTAssertTrue(app.tabBars.buttons["洞察"].isSelected)
    }

    func testManualKeypadSaveTodayEditAndDelete() {
        let app = application("manual"); app.launch()
        let funds = app.buttons["fundsFormula"]
        XCTAssertTrue(funds.waitForExistence(timeout: 10))
        XCTAssertTrue(funds.label.contains("1,000"))
        tap(addEntryTab(app), in: app)
        tap(app.buttons["keypad_3"], in: app); tap(app.buttons["keypad_2"], in: app)
        XCTAssertEqual(app.staticTexts["entryKeypadAmount"].label, "32")
        snapshot("manual-draft", app)
        tap(app.buttons["saveQuickEntry"], in: app)
        let today = app.buttons["todayEntries"]
        let saved = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS '−32.00'"), object: today)
        XCTAssertEqual(XCTWaiter.wait(for: [saved], timeout: 10), .completed)
        XCTAssertTrue(today.label.contains("1 笔"))
        let decreased = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS '968'"), object: funds)
        XCTAssertEqual(XCTWaiter.wait(for: [decreased], timeout: 10), .completed)
        snapshot("manual-saved", app)
        tap(today, in: app)
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'ledgerEntry_' ")).firstMatch
        tap(row, in: app)
        XCTAssertTrue(app.textFields["editEntryAmount"].waitForExistence(timeout: 5))
        snapshot("manual-edit", app)
        tap(app.buttons["deleteEntry"], in: app)
        tap(app.buttons["confirmDeleteEntry"], in: app)
        assertGone(row)
        snapshot("manual-deleted", app)
        tap(app.navigationBars.buttons["现在"], in: app)
        XCTAssertTrue(app.buttons["todayEntries"].label.contains("还没记"))
        XCTAssertTrue(funds.label.contains("1,000"))
    }

    func testImportOrganizeAnswerAndUndoEntireBatch() {
        let app = application("import")
        let csv = "时间,收支,金额,名称,交易类型,交易单号\n2001-01-02 12:00:00,支出,32.00,合成午餐,商户消费,ui-lunch\n2001-01-02 13:00:00,收入,40.00,合成来款,转账,ui-incoming\n"
        app.launchEnvironment["YUBAI_UI_STATEMENT"] = Data(csv.utf8).base64EncodedString()
        app.launch()
        snapshot("overview", app)
        tap(addEntryTab(app), in: app)
        tap(app.buttons["importFromEntry"], in: app)
        snapshot("import-preview", app)
        tap(app.buttons["commitImport"], in: app)
        let question = app.staticTexts["importQuestion"]
        XCTAssertTrue(question.waitForExistence(timeout: 10)); XCTAssertEqual(question.label, "这笔来款是什么用途？")
        snapshot("import-question", app)
        tap(app.buttons["importAnswer_0"], in: app)
        assertGone(question)
        tap(app.buttons["closeSheet"], in: app)
        tap(app.tabBars.buttons["我"], in: app)
        tap(app.buttons["openImportHistory"], in: app)
        XCTAssertTrue(app.staticTexts["合成账单.csv"].waitForExistence(timeout: 5))
        snapshot("import-history", app)
        tap(app.buttons["undoImportBatch"], in: app)
        tap(app.buttons["撤销这一批"], in: app)
        XCTAssertTrue(app.staticTexts["emptyImportHistory"].waitForExistence(timeout: 5))
        snapshot("history-undone", app)
        // Reimport is no longer a duplicate. The pre-existing record survives undo.
        tap(app.navigationBars.buttons["我"], in: app)
        tap(app.tabBars.buttons["现在"], in: app)
        tap(addEntryTab(app), in: app)
        tap(app.buttons["importFromEntry"], in: app)
        XCTAssertTrue(app.buttons["commitImport"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["commitImport"].isEnabled)
        tap(app.buttons["commitImport"], in: app)
        XCTAssertTrue(app.staticTexts["importQuestion"].waitForExistence(timeout: 10))
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
        XCTAssertTrue(app.staticTexts["来源与依据"].exists)
        snapshot("entry-detail", app)
    }

    func testProfilePrinciplePersistsAndBackupOpens() {
        let app = application("profile"); app.launch()
        snapshot("overview", app)
        tap(app.tabBars.buttons["我"], in: app)
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
        tap(app.tabBars.buttons["我"], in: app)
        tap(app.buttons["openProfile"], in: app)
        XCTAssertTrue(app.staticTexts["为每天用得上的东西花钱"].waitForExistence(timeout: 5))
        snapshot("principle-after-relaunch", app)
        tap(app.navigationBars.buttons["我"], in: app)
        tap(app.buttons["openBackup"], in: app)
        XCTAssertTrue(app.navigationBars["备份与恢复"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.secureTextFields["备份密码（至少 8 位）"].exists)
        XCTAssertFalse(addEntryTab(app).isHittable)
        XCTAssertFalse(app.tabBars.buttons["我"].isHittable)
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
        tap(app.tabBars.buttons["我"], in: app)
        tap(app.buttons["openMemories"], in: app)
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
        tap(app.tabBars.buttons["我"], in: app); tap(app.buttons["openMemories"], in: app)
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
