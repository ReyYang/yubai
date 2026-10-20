import XCTest

/// Every launch uses a fresh UUID directory and simulator-only scripted transport.
/// No Keychain configuration or network connection is needed.
final class AppFlowTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func application(_ fixture: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--test-ledger", UUID().uuidString, "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launchEnvironment["YUBAI_UI_TEST_SCRIPT"] = fixture
        app.launchEnvironment["DEEPSEEK_API_KEY"] = ""
        return app
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

    func testFirstLaunchEmptyLedgerAccountAndAvailableFunds() {
        let app = application("empty"); app.launch()
        tap(app.buttons["startLedger"], in: app)
        XCTAssertTrue(app.staticTexts["从真实余额开始"].waitForExistence(timeout: 5))
        tap(app.buttons["addFirstAccount"], in: app)
        tap(app.textFields["accountName"], in: app); app.textFields["accountName"].typeText("UI Bank")
        tap(app.textFields["accountBalance"], in: app); app.textFields["accountBalance"].typeText("1000")
        tap(app.buttons["saveAccount"], in: app)
        let funds = app.buttons["fundsFormula"]
        XCTAssertTrue(funds.waitForExistence(timeout: 10))
        // A newly opened ledger has no known obligations or spending estimate.
        XCTAssertTrue(funds.label.contains("保守可动用")); XCTAssertTrue(funds.label.contains("1,000"))
        XCTAssertEqual(app.tabBars.buttons.count, 2)
        XCTAssertTrue(app.tabBars.buttons["现在"].exists); XCTAssertTrue(app.tabBars.buttons["我"].exists)
        XCTAssertTrue(app.buttons["askYubai"].exists)
        tap(funds, in: app)
        XCTAssertTrue(app.staticTexts["可支配现金"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["减：日常生活预留"].exists)
    }

    func testImportOrganizeAnswerAndUndoEntireBatch() {
        let app = application("import")
        let csv = "时间,收支,金额,名称,交易类型,交易单号\n2001-01-02 12:00:00,支出,32.00,合成午餐,商户消费,ui-lunch\n2001-01-02 13:00:00,收入,40.00,合成来款,转账,ui-incoming\n"
        app.launchEnvironment["YUBAI_UI_STATEMENT"] = Data(csv.utf8).base64EncodedString()
        app.launch()
        tap(app.buttons["importBills"], in: app)
        tap(app.buttons["commitImport"], in: app)
        let question = app.staticTexts["importQuestion"]
        XCTAssertTrue(question.waitForExistence(timeout: 10)); XCTAssertEqual(question.label, "这笔来款是什么用途？")
        tap(app.buttons["importAnswer_0"], in: app)
        assertGone(question)
        tap(app.buttons["closeSheet"], in: app)
        tap(app.tabBars.buttons["我"], in: app)
        tap(app.buttons["openImportHistory"], in: app)
        XCTAssertTrue(app.staticTexts["合成账单.csv"].waitForExistence(timeout: 5))
        tap(app.buttons["undoImportBatch"], in: app)
        tap(app.buttons["撤销这一批"], in: app)
        XCTAssertTrue(app.staticTexts["emptyImportHistory"].waitForExistence(timeout: 5))
        // Reimport is no longer a duplicate. The pre-existing record survives undo.
        tap(app.tabBars.buttons["现在"], in: app)
        tap(app.buttons["importBills"], in: app)
        XCTAssertTrue(app.buttons["commitImport"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["commitImport"].isEnabled)
        tap(app.buttons["commitImport"], in: app)
        XCTAssertTrue(app.staticTexts["importQuestion"].waitForExistence(timeout: 10))
        tap(app.buttons["undoImportResult"], in: app)
        XCTAssertTrue(app.staticTexts["activeEntryCount"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["activeEntryCount"].label, "有效记录 1 笔")
    }

    func testRestrainCardCanBeMutedAcrossLaunches() {
        let app = application("restrain"); app.launch()
        let card = app.staticTexts["butlerTitle_restrain"]
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        tap(app.buttons["butlerOptions_restrain"], in: app)
        tap(app.buttons["以后别提"], in: app)
        assertGone(card)
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["fundsFormula"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["butlerTitle_restrain"].exists)
    }

    func testAskNumericAnswerEvidenceAndEntryDetail() {
        let app = application("ask"); app.launch()
        tap(app.buttons["askYubai"], in: app)
        tap(app.descendants(matching: .any).matching(identifier: "askInput").firstMatch, in: app); app.descendants(matching: .any).matching(identifier: "askInput").firstMatch.typeText("咖啡共花了多少钱？")
        tap(app.buttons["sendAsk"], in: app)
        let answer = app.staticTexts["askAnswer"]
        XCTAssertTrue(answer.waitForExistence(timeout: 10)); XCTAssertTrue(answer.label.contains("32.00"))
        tap(app.buttons["answerEvidence"], in: app)
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'evidenceEntry_' ")).firstMatch
        tap(row, in: app)
        XCTAssertTrue(app.staticTexts["entryDetailTitle"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["entryDetailTitle"].label, "合成咖啡")
        XCTAssertTrue(app.staticTexts["来源与依据"].exists)
    }

    func testProfilePrinciplePersistsAndBackupOpens() {
        let app = application("profile"); app.launch()
        tap(app.tabBars.buttons["我"], in: app)
        tap(app.buttons["openProfile"], in: app)
        tap(app.buttons["addPrinciple"], in: app)
        tap(app.descendants(matching: .any).matching(identifier: "principleText").firstMatch, in: app); app.descendants(matching: .any).matching(identifier: "principleText").firstMatch.typeText("为每天用得上的东西花钱")
        tap(app.buttons["savePrinciple"], in: app)
        XCTAssertTrue(app.staticTexts["为每天用得上的东西花钱"].waitForExistence(timeout: 5))
        app.terminate(); app.launch()
        tap(app.tabBars.buttons["我"], in: app)
        tap(app.buttons["openProfile"], in: app)
        XCTAssertTrue(app.staticTexts["为每天用得上的东西花钱"].waitForExistence(timeout: 5))
        tap(app.navigationBars.buttons["我"], in: app)
        tap(app.buttons["openBackup"], in: app)
        XCTAssertTrue(app.navigationBars["备份与同步"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.secureTextFields["备份密码（至少 8 位）"].exists)
        XCTAssertTrue(app.buttons["askYubai"].exists)
    }
}
