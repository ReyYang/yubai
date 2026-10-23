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
    private func assertSelectedTab(_ identifier: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == true"), object: app.buttons[identifier])
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 5), .completed, file: file, line: line)
    }
    private func assertCurrentTab(_ identifier: String, content: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        assertSelectedTab(identifier, in: app, file: file, line: line)
        let element = app.buttons[content]
        let visible = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: element)
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

    private func openFixedBills(_ app: XCUIApplication) {
        tap(app.buttons["tab_settings"], in: app)
        tap(app.buttons["openFixedFlows"], in: app)
        XCTAssertTrue(app.navigationBars["固定收付"].waitForExistence(timeout: 5))
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
        XCTAssertTrue(app.staticTexts["放了 12 天"].exists)
        XCTAssertTrue(app.staticTexts["买了一个月 · 用得怎么样？"].exists)
        snapshot("wishlist-cooldown", app)
    }

    func testLetterSavingScreenshotFixture() {
        let app = application("letter-saving"); app.launch()
        // The profile tab always keeps the letter reachable, including Thu–Sun.
        tap(app.buttons["tab_settings"], in: app)
        tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "每周来信")).firstMatch, in: app)
        tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "每周来信")).firstMatch, in: app)
        XCTAssertTrue(app.staticTexts["这些还在用吗？"].waitForExistence(timeout: 5))
        for title in ["视频会员", "网盘", "健身 App", "这周省下", "一共省下"] { XCTAssertTrue(app.staticTexts[title].exists) }
        snapshot("letter-saving-subscriptions", app)
    }

    func testProfileRevisitScreenshotFixture() {
        let app = application("profile-revisit"); app.launch()
        XCTAssertTrue(app.buttons["restrainNear"].waitForExistence(timeout: 5))
        tap(app.buttons["tab_settings"], in: app)
        tap(app.buttons["openProfile"], in: app)
        snapshot("profile-progress", app)
        tap(app.buttons["profileChatEntry"], in: app)
        XCTAssertTrue(app.buttons["最近花钱的感觉变了"].waitForExistence(timeout: 10))
        snapshot("profile-revisit-opening", app)
        let input = app.descendants(matching: .any).matching(identifier: "profileInput").firstMatch
        tap(input, in: app); input.typeText("外卖这周到上限了，但加班那几天真没办法")
        tap(app.buttons["sendProfile"], in: app)
        XCTAssertTrue(app.staticTexts["外卖这周已经 3 次了，加班的日子想怎么安排？"].waitForExistence(timeout: 10))
        snapshot("profile-revisit-reply", app)
    }

    func testSubcategoryScreenshotFixture() {
        let app = application("subcategory"); app.launch()
        tap(app.buttons["tab_insights"], in: app)
        tap(app.buttons["insightCategory_0"], in: app)
        XCTAssertTrue(app.navigationBars["购物 · 本月"].waitForExistence(timeout: 5))
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

    func testFixedBillCheckMarksPaidAndUndoRestoresIt() {
        let app = application("bills"); app.launch()
        XCTAssertTrue(app.buttons["fundsFormula"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["fundsFormula"].label.contains("¥700"))
        openFixedBills(app)
        let check = app.buttons["付了 房租"]
        tap(check, in: app)
        XCTAssertEqual(check.value as? String, "已付"); XCTAssertFalse(check.isEnabled)
        XCTAssertTrue(app.staticTexts["房租 300 已记下"].exists)
        tap(app.buttons["撤销"], in: app)
        XCTAssertTrue(check.isEnabled); XCTAssertEqual(check.value as? String, "已到期")
        tap(check, in: app)
        XCTAssertFalse(check.isEnabled)
        snapshot("bill-paid", app)
        tap(app.navigationBars.buttons["我"], in: app); tap(app.buttons["tab_overview"], in: app)
        XCTAssertTrue(app.buttons["fundsFormula"].label.contains("¥700"))
        XCTAssertTrue(app.buttons["todayEntries"].label.contains("1 笔"))
    }

    func testFixedIncomeCheckIncreasesAvailableAndPersists() {
        let app = application("bills"); app.launch()
        XCTAssertTrue(app.buttons["fundsFormula"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["fundsFormula"].label.contains("¥700"))
        openFixedBills(app)
        let check = app.buttons["收到了 工资"]
        tap(check, in: app)
        XCTAssertFalse(check.isEnabled); XCTAssertEqual(check.value as? String, "已收到")
        tap(app.navigationBars.buttons["我"], in: app); tap(app.buttons["tab_overview"], in: app)
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS '¥1,200'"), object: app.buttons["fundsFormula"])
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed)
        snapshot("income-received", app)
        app.terminate(); app.launch(); openFixedBills(app)
        XCTAssertFalse(app.buttons["收到了 工资"].isEnabled)
    }

    func testFixedBillLongPressChangesAmountBeforeRecording() {
        let app = application("bills-estimated"); app.launch(); openFixedBills(app)
        let check = app.buttons["付了 电费"]
        XCTAssertTrue(check.waitForExistence(timeout: 5)); check.press(forDuration: 0.8)
        let field = app.textFields["fixedFlowSettlementAmount"]
        tap(field, in: app)
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 3) + "100")
        tap(app.buttons["saveManualSheet"], in: app)
        XCTAssertEqual(check.value as? String, "已付")
        tap(app.navigationBars.buttons["我"], in: app); tap(app.buttons["tab_overview"], in: app)
        XCTAssertTrue(app.buttons["fundsFormula"].label.contains("¥900"))
        XCTAssertTrue(app.buttons["todayEntries"].label.contains("1 笔"))
    }

    func testFixedBillSwipeStopsFutureOccurrencesAndKeepsPaidRow() {
        let app = application("bills"); app.launch(); openFixedBills(app)
        let check = app.buttons["收到了 工资"]
        tap(check, in: app)
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'fixedFlow_' AND value == '已收到'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5)); row.swipeLeft()
        tap(app.buttons["停掉"], in: app)
        tap(app.buttons["停掉以后的"], in: app)
        XCTAssertTrue(check.exists); XCTAssertFalse(check.isEnabled)
        XCTAssertFalse(app.buttons["结束这个安排"].exists)
        snapshot("bill-stopped-paid-kept", app)
        app.terminate(); app.launch(); openFixedBills(app)
        XCTAssertFalse(app.buttons["收到了 工资"].isEnabled)
    }

    func testFixedBillStopAndResumeBothSupportUndo() {
        let app = application("bills"); app.launch(); openFixedBills(app)
        let check = app.buttons["收到了 工资"]
        XCTAssertTrue(check.waitForExistence(timeout: 5))
        let planID = String(check.identifier.split(separator: "_")[1])
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "fixedFlow_" + planID)).firstMatch
        let restore = app.buttons["resumeFixedFlow_" + planID]
        func stop() {
            row.swipeLeft()
            tap(app.buttons["停掉"], in: app); tap(app.buttons["停掉以后的"], in: app)
            XCTAssertTrue(restore.waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts.matching(identifier: "已停掉").firstMatch.exists)
        }
        stop()
        tap(app.buttons["撤销"], in: app); assertGone(restore)
        stop()
        tap(restore, in: app); assertGone(restore)
        XCTAssertTrue(check.isEnabled)
        tap(app.buttons["撤销"], in: app)
        XCTAssertTrue(restore.waitForExistence(timeout: 5))
        snapshot("bill-stopped-restorable", app)
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
        let paid = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == false AND value == '已付'"), object: app.buttons["付了 自动测试"])
        XCTAssertEqual(XCTWaiter.wait(for: [paid], timeout: 5), .completed)
        XCTAssertFalse(app.staticTexts["自动记下完成"].exists)
    }

    func testDueCardIncludesPreviousMonthAndLinksOverflowToBills() {
        let app = application("bills-overdue"); app.launch()
        XCTAssertTrue(app.buttons["付了 上月账单"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label BEGINSWITH '付了 '")).count, 2)
        XCTAssertEqual(app.buttons["moreDueBills"].label, "还有 1 笔 ›")
        tap(app.buttons["付了 上月账单"], in: app)
        XCTAssertFalse(app.buttons["付了 上月账单"].exists)
        XCTAssertTrue(app.buttons["todayEntries"].label.contains("还没记"))
        tap(app.buttons["撤销"], in: app)
        tap(app.buttons["moreDueBills"], in: app)
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
        XCTAssertFalse(app.buttons["付了 房租"].isEnabled)
        XCTAssertEqual(app.buttons["付了 房租"].value as? String, "已付")
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
        XCTAssertFalse(app.buttons["付了 房租"].isEnabled)
    }

    func testStorageEntryAndOverviewOpenFromMe() {
        let app = application("ask"); app.launch()
        tap(app.buttons["tab_settings"], in: app)
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
        XCTAssertTrue(app.navigationBars["餐饮"].waitForExistence(timeout: 5))
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
        let middle = card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
        middle.press(forDuration: 0.05, thenDragTo: middle.withOffset(CGVector(dx: 80, dy: 0)))
        XCTAssertTrue(title.exists)
        assertSelectedTab("tab_overview", in: app)
        let start = card.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.35))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: -card.frame.width * 0.15, dy: 0)), withVelocity: .slow, thenHoldForDuration: 0.2)
        assertGone(app.buttons["知道了"])
        XCTAssertTrue(title.exists)
        assertSelectedTab("tab_overview", in: app)
        let dismiss = card.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.35))
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
        for velocity in [XCUIGestureVelocity.slow, XCUIGestureVelocity(1000)] {
            let start = card.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.35))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: card.frame.width * 0.7, dy: 0)), withVelocity: velocity, thenHoldForDuration: 0)
            assertCurrentTab("tab_overview", content: "fundsFormula", in: app)
            XCTAssertTrue(title.isHittable); assertGone(app.buttons["知道了"])
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
        let delete = app.buttons[row.identifier.replacingOccurrences(of: "ledgerEntry_", with: "deleteLedgerEntry_")]
        row.swipeRight()
        assertCurrentTab("tab_insights", content: "支出", in: app)
        XCTAssertFalse(app.textFields["editEntryAmount"].exists)
        tap(app.buttons["tab_entries"], in: app)
        assertCurrentTab("tab_entries", content: "entriesSearchButton", in: app)
        assertGone(delete)
        row.swipeLeft()
        XCTAssertTrue(delete.waitForExistence(timeout: 5)); XCTAssertTrue(delete.isHittable)
        row.swipeRight()
        assertGone(delete)
        assertCurrentTab("tab_entries", content: "entriesSearchButton", in: app)
        row.swipeRight()
        assertCurrentTab("tab_insights", content: "支出", in: app)
        XCTAssertFalse(app.textFields["editEntryAmount"].exists)
    }

    func testRevealedLedgerRowConsumesSwipesInBothDirections() {
        let app = application("ask"); app.launch(); tap(app.buttons["tab_entries"], in: app)
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'ledgerEntry_' ")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        let delete = app.buttons[row.identifier.replacingOccurrences(of: "ledgerEntry_", with: "deleteLedgerEntry_")]
        row.swipeLeft()
        XCTAssertTrue(delete.waitForExistence(timeout: 5)); XCTAssertTrue(delete.isHittable)
        for element in [row, delete] {
            let start = element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: -80, dy: 0)), withVelocity: XCUIGestureVelocity(1000), thenHoldForDuration: 0)
            assertSelectedTab("tab_entries", in: app)
            XCTAssertTrue(delete.isHittable); XCTAssertFalse(app.textFields["editEntryAmount"].exists)
        }
        let start = row.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 30, dy: 0)), withVelocity: .slow, thenHoldForDuration: 0.2)
        assertGone(delete)
        assertSelectedTab("tab_entries", in: app)
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
        first.swipeLeft()
        XCTAssertTrue(firstDelete.waitForExistence(timeout: 5))
        second.swipeLeft()
        assertGone(firstDelete)
        XCTAssertTrue(secondDelete.waitForExistence(timeout: 5)); XCTAssertTrue(secondDelete.isHittable)
        first.swipeLeft()
        assertGone(secondDelete)
        XCTAssertTrue(firstDelete.waitForExistence(timeout: 5)); XCTAssertTrue(firstDelete.isHittable)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'deleteLedgerEntry_' ")).count, 1)
        assertSelectedTab("tab_entries", in: app)
        app.staticTexts["本月收入"].tap()
        assertGone(firstDelete)
        XCTAssertFalse(app.textFields["editEntryAmount"].exists)
    }

    func testRevealedLedgerRowSlowLeftSwipeKeepsCurrentTab() {
        let app = application("ask"); app.launch(); tap(app.buttons["tab_entries"], in: app)
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'ledgerEntry_' ")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        let delete = app.buttons[row.identifier.replacingOccurrences(of: "ledgerEntry_", with: "deleteLedgerEntry_")]
        row.swipeLeft()
        XCTAssertTrue(delete.waitForExistence(timeout: 5)); XCTAssertTrue(delete.isHittable)
        for _ in 0..<3 {
            let start = row.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: -200, dy: 0)), withVelocity: XCUIGestureVelocity(200 / 0.6), thenHoldForDuration: 0)
            assertSelectedTab("tab_entries", in: app)
            XCTAssertTrue(delete.isHittable); XCTAssertFalse(app.textFields["editEntryAmount"].exists)
        }
        row.swipeRight()
        assertGone(delete)
        let start = app.staticTexts["本月收入"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: -200, dy: 0)))
        assertSelectedTab("tab_settings", in: app)
    }

    func testLedgerRevealClosesAfterTabSelectionAndPaging() {
        let app = application("ask"); app.launch(); tap(app.buttons["tab_entries"], in: app)
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'ledgerEntry_' ")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        let delete = app.buttons[row.identifier.replacingOccurrences(of: "ledgerEntry_", with: "deleteLedgerEntry_")]
        row.swipeLeft()
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        tap(app.buttons["tab_overview"], in: app); tap(app.buttons["tab_entries"], in: app)
        assertSelectedTab("tab_entries", in: app); assertGone(delete)
        row.swipeLeft()
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        let start = app.staticTexts["本月收入"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: -200, dy: 0)))
        assertSelectedTab("tab_entries", in: app); XCTAssertTrue(delete.isHittable)
        app.staticTexts["本月收入"].tap()
        assertGone(delete)
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: -200, dy: 0)))
        assertSelectedTab("tab_settings", in: app)
        tap(app.buttons["tab_entries"], in: app)
        assertSelectedTab("tab_entries", in: app); assertGone(delete)
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
        row.swipeRight()
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
        let app = application("ask"); app.launch(); tap(app.buttons["tab_entries"], in: app)
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'ledgerEntry_' ")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        let identifier = row.identifier
        row.swipeLeft()
        XCTAssertFalse(app.textFields["editEntryAmount"].exists)
        tap(app.buttons[identifier.replacingOccurrences(of: "ledgerEntry_", with: "deleteLedgerEntry_")], in: app)
        assertGone(app.buttons[identifier])
        tap(app.buttons["撤销"], in: app)
        XCTAssertTrue(app.buttons[identifier].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["tab_entries"].isSelected)
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
    }

    func testLedgerRowsStillScrollVerticallyAndOpenWithTap() {
        let app = application("entries"); app.launch()
        tap(app.buttons["tab_entries"], in: app)
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'ledgerEntry_' "))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5))
        let first = app.buttons[rows.firstMatch.identifier]
        let delete = app.buttons[first.identifier.replacingOccurrences(of: "ledgerEntry_", with: "deleteLedgerEntry_")]
        first.swipeLeft()
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        let start = first.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -180)))
        XCTAssertTrue(app.buttons["tab_entries"].isSelected); XCTAssertFalse(app.textFields["editEntryAmount"].exists)
        assertGone(delete)
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

    func testFirstLaunchEmptyLedgerAccountAndAvailableFunds() {
        let app = application("empty"); app.launch()
        snapshot("welcome", app)
        XCTAssertFalse(app.buttons["startLedger"].isEnabled)
        tap(app.buttons["welcomeOtherAccount"], in: app)
        snapshot("welcome-account", app)
        tap(app.textFields["accountName"], in: app); app.textFields["accountName"].typeText("UI Bank")
        tap(app.textFields["accountBalance"], in: app); app.textFields["accountBalance"].typeText("1000")
        tap(app.buttons["startLedger"], in: app)
        let funds = app.buttons["fundsFormula"]
        XCTAssertTrue(funds.waitForExistence(timeout: 10))
        // A newly opened ledger has no known obligations or spending estimate.
        XCTAssertTrue(funds.label.contains("还能花")); XCTAssertTrue(funds.label.contains("1,000"))
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
        XCTAssertTrue(app.buttons["tab_insights"].isSelected)
        tap(app.buttons["askYubai"], in: app)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "askInput").firstMatch.waitForExistence(timeout: 5))
        app.navigationBars.firstMatch.swipeLeft()
        tap(app.buttons["closeSheet"], in: app)
        XCTAssertTrue(app.buttons["tab_insights"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["tab_insights"].isSelected)
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
            app.navigationBars.firstMatch.swipeRight()
            tap(app.buttons["cancelManualSheet"], in: app)
            XCTAssertTrue(tab.isSelected)
        }
    }

    func testFloatingNavigationHidesForKeyboardAndLeavesLastLedgerRowVisible() throws {
        let app = application("entries"); app.launch()
        tap(app.buttons["tab_entries"], in: app)
        tap(app.buttons["entriesSearchButton"], in: app)
        let search = app.textFields["entriesSearch"]
        tap(search, in: app); search.typeText("UI")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        let hidden = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == false"), object: addEntryTab(app))
        XCTAssertEqual(XCTWaiter.wait(for: [hidden], timeout: 5), .completed)
        search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 2))
        let scroll = app.scrollViews["entriesScroll"]
        scroll.swipeUp()
        XCTAssertTrue(addEntryTab(app).waitForExistence(timeout: 5))
        let visible = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: addEntryTab(app))
        XCTAssertEqual(XCTWaiter.wait(for: [visible], timeout: 5), .completed)
        for _ in 0..<8 { scroll.swipeUp() }
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
