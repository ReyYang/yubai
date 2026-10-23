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
        app.launchEnvironment["YUBAI_UI_TEST_CONFIGURED_KEY"] = "1"
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
        let confirmation = app.alerts["停掉「工资」？"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        XCTAssertTrue(confirmation.buttons["取消"].isHittable)
        tap(confirmation.buttons["停掉以后的"], in: app)
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
        row.swipeLeft()
        tap(app.buttons["停掉"], in: app)
        let confirmation = app.alerts["停掉「工资」？"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        XCTAssertTrue(confirmation.staticTexts["停掉「工资」？"].exists)
        tap(confirmation.buttons["取消"], in: app)
        assertGone(confirmation)
        XCTAssertTrue(check.isEnabled)
        func stop() {
            row.swipeLeft()
            tap(app.buttons["停掉"], in: app)
            XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
            tap(confirmation.buttons["停掉以后的"], in: app)
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

    func testFixedBillGroupedSwipesKeepCardAndContentGeometry() {
        let app = application("bills-overdue"); app.launch(); openFixedBills(app)
        let card = app.descendants(matching: .any).matching(identifier: "fixedFlowExpenseCard").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        let rows = card.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'fixedFlow_' ")).allElementsBoundByIndex
        XCTAssertGreaterThanOrEqual(rows.count, 2)
        for index in [0, rows.count - 1] {
            let row = rows[index]
            for _ in 0..<8 { if row.isHittable { break }; app.swipeUp() }
            XCTAssertTrue(row.isHittable)
            let check = row.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'settleFixedFlow_' ")).firstMatch
            let originalCard = card.frame, originalRow = row.frame, originalCheck = check.frame
            let labels = row.staticTexts.allElementsBoundByIndex.map(\.label)
            row.swipeLeft()
            let action = app.buttons[row.identifier.replacingOccurrences(of: "fixedFlow_", with: "stopFixedFlow_")]
            XCTAssertTrue(action.waitForExistence(timeout: 5)); XCTAssertTrue(action.isHittable)
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
            row.swipeRight()
            let hidden = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == false"), object: action)
            XCTAssertEqual(XCTWaiter.wait(for: [hidden], timeout: 5), .completed)
            XCTAssertEqual(check.frame.minX, originalCheck.minX, accuracy: 1)
        }
    }

    func testUpcomingPaymentStopUsesAlertAndSupportsCancelAndConfirm() {
        let app = application("bills"); app.launch()
        tap(app.buttons["fundsFormula"], in: app)
        let end = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'endArrangement_' ")).firstMatch
        XCTAssertTrue(end.waitForExistence(timeout: 5))
        let identifier = end.identifier
        tap(end, in: app)
        let confirmation = app.alerts.firstMatch
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        XCTAssertTrue(confirmation.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '停掉「' AND label ENDSWITH '」？'")).firstMatch.exists)
        XCTAssertTrue(confirmation.buttons["停掉以后的"].isHittable)
        XCTAssertTrue(confirmation.buttons["取消"].isHittable)
        snapshot("upcoming-payment-stop-alert", app)
        tap(confirmation.buttons["取消"], in: app); assertGone(confirmation)
        XCTAssertTrue(app.buttons[identifier].exists)
        tap(app.buttons[identifier], in: app)
        tap(confirmation.buttons["停掉以后的"], in: app)
        assertGone(confirmation)
        assertGone(app.buttons[identifier])
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
        let storage = app.buttons["openStorage"]
        let navigation = app.otherElements["mainNavigation"]
        for _ in 0..<8 {
            if storage.isHittable && storage.frame.maxY <= navigation.frame.minY { break }
            app.swipeUp()
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
                let scroll = app.scrollViews[scrollID]
                let scrolls = tab != "tab_overview" || category == "UICTContentSizeCategoryAccessibilityXL"
                if scrolls { XCTAssertTrue(scroll.waitForExistence(timeout: 5)) }
                let headers = [app.staticTexts["rootHeaderTitle"], app.buttons["askYubai"]]
                for header in headers { XCTAssertTrue(header.isHittable) }
                if let titleY { XCTAssertEqual(headers[0].frame.minY, titleY, accuracy: 1) }
                else { titleY = headers[0].frame.minY }
                let headerBottom = max(headers[0].frame.maxY, headers[1].frame.maxY)
                let firstContent = app.buttons[firstContentID]
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
        let recent = app.buttons["合成账目 0"]
        for _ in 0..<8 { if recent.isHittable { break }; form.swipeUp() }
        XCTAssertTrue(recent.isHittable)
        tap(recent, in: app)
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
        XCTAssertTrue(app.navigationBars["餐饮"].waitForExistence(timeout: 5))
    }

    func testModelMenuSelectsInlineAndKeepsCustomEditor() {
        let app = application("ask"); app.launch()
        tap(app.buttons["tab_settings"], in: app)
        tap(app.buttons["openIntelligencePrivacy"], in: app)
        tap(app.buttons["editCloudModel"], in: app)
        XCTAssertTrue(app.buttons["cloudModel_deepseek-chat"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["cloudModel_deepseek-reasoner"].exists)
        XCTAssertTrue(app.buttons["customCloudModel"].exists)
        XCTAssertFalse(app.textFields["cloudModelName"].exists)
        snapshot("model-menu", app)
        tap(app.buttons["cloudModel_deepseek-reasoner"], in: app)
        XCTAssertTrue(app.buttons["editCloudModel"].label.contains("deepseek-reasoner"))
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
        let incoming = app.descendants(matching: .any).matching(identifier: "importTotal_流入").firstMatch
        XCTAssertTrue(incoming.waitForExistence(timeout: 5))
        XCTAssertTrue(incoming.label.contains("1 笔")); XCTAssertTrue(incoming.label.contains("40.00"))
        let outgoing = app.descendants(matching: .any).matching(identifier: "importTotal_流出").firstMatch
        XCTAssertTrue(outgoing.label.contains("1 笔")); XCTAssertTrue(outgoing.label.contains("32.00"))
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
