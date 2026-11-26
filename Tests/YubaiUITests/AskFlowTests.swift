import XCTest

/// 问余白: open from the home bar, verdict card, 审批卡 with undo, 截图批量记账, AI 未连接 → 去设置.
final class AskFlowTests: YubaiUITestCase {
    private let app = XCUIApplication()

    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws { app.terminate(); try super.tearDownWithError() }

    private func launch(_ fixture: String, scripted: Bool = false) {
        app.launchArguments = ["-YubaiAskFixture", fixture, "-YubaiTheme", "light", "-YubaiLogAskRenderCounts",
                               "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        if scripted {
            // Scripted replies only: no network, and the key is a test stand-in.
            app.launchArguments += ["--test-ledger", UUID().uuidString]
            app.launchEnvironment["YUBAI_UI_TEST_SCRIPT"] = "ask"
            app.launchEnvironment["YUBAI_UI_TEST_CONFIGURED_KEY"] = "1"
            app.launchEnvironment["DEEPSEEK_API_KEY"] = ""
        }
        XCTAssertTrue(launchApp(app))
    }

    private func element(_ id: String) -> XCUIElement { control(id, in: app) }
    private func any(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
    private func tap(_ id: String) { tapControl(element(id), in: app) }
    private func label(_ id: String, contains text: String, timeout: TimeInterval = 10) {
        let target = any(id)
        XCTAssertTrue(UIConditionWait.run(timeout: timeout, read: { target.exists && target.label.contains(text) }),
                      "\(id) does not contain \(text): \(target.label)")
    }

    func testOpenFromTheBarSendsAndShowsTheVerdict() {
        launch("live", scripted: true)
        tap("openLedgerSearch")
        let field = app.textFields["entriesSearch"]
        XCTAssertTrue(field.waitForExistence(timeout: 8))
        field.typeText("想买个 1299 的降噪耳机")
        tap("askHomeSearch")
        XCTAssertTrue(any("askSheet").waitForExistence(timeout: 8))
        label("askVerdict", contains: "先别买", timeout: 15)
        label("askVerdictCard", contains: "4,969.40")
    }

    func testApprovalAppliesOnlyOnConfirmAndUndoBringsItBack() {
        launch("approve")
        label("askApprovalCard", contains: "冲抵")
        tap("askPrimary")
        label("askDone", contains: "已冲抵")
        tap("undoLastChange")
        XCTAssertTrue(element("askPrimary").waitForExistence(timeout: 8))
    }

    func testBatchChecksFollowTheCountAndRecord() {
        launch("batch")
        label("askPrimary", contains: "记下 3 笔")
        tap("askBatchRow_1")
        label("askPrimary", contains: "记下 4 笔")
        tap("askBatchRow_0")
        label("askPrimary", contains: "记下 3 笔")
        tap("askPrimary")
        label("askDone", contains: "已记下 3 笔")
    }

    func testOfflineGoSettingsLandsOnTheAIPage() {
        launch("offline")
        XCTAssertTrue(any("askOffline").waitForExistence(timeout: 8))
        tap("askGoSettings")
        XCTAssertTrue(any("aiSettingsScroll").waitForExistence(timeout: 8))
        XCTAssertFalse(any("askSheet").exists)
    }
}
