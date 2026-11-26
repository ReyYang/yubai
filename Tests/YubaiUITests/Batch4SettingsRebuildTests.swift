import XCTest

final class Batch4SettingsRebuildTests: YubaiUITestCase {
    private let app = XCUIApplication()

    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws { app.terminate(); try super.tearDownWithError() }

    private func launch(_ fixture: [String], dark: Bool = false) {
        app.launchArguments = fixture + ["-YubaiTheme", dark ? "dark" : "light", "-YubaiLogSettingsRenderCounts",
                                         "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launchEnvironment["YUBAI_GALLERY_HIDE_AMOUNTS"] = "0"
        XCTAssertTrue(launchApp(app))
    }

    private func launchScript(_ script: String) {
        app.launchArguments = ["--test-ledger", UUID().uuidString, "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launchEnvironment["YUBAI_UI_TEST_SCRIPT"] = script
        app.launchEnvironment["DEEPSEEK_API_KEY"] = ""
        XCTAssertTrue(launchApp(app))
    }

    private func element(_ id: String) -> XCUIElement { control(id, in: app) }
    private func tap(_ id: String) {
        tapControl(element(id), in: app, settles: !id.hasPrefix("keypad_"), reveals: !id.hasPrefix("keypad_"))
    }
    private func label(_ id: String, contains text: String) {
        let target = element(id)
        XCTAssertTrue(UIConditionWait.run(timeout: 8, read: { target.exists && target.label.contains(text) }),
                      "\(id) does not contain \(text): \(target.label)")
    }
    private func keys(_ input: String) { for digit in input { tap("keypad_" + String(digit)) } }

    func testSettingsRowsShowLiveValuesAndRoute() {
        launch(["-YubaiSettingsFixture", "main"])
        label("settingsCycle", contains: "每月 10 日")
        label("settingsSaving", contains: "5,000.00")
        label("settingsRecurring", contains: "386.00")
        label("openIntelligencePrivacy", contains: "DeepSeek")
        XCTAssertFalse(element("settingsICloud").exists)
        tap("settingsRecurring")
        XCTAssertTrue(element("recurringScroll").waitForExistence(timeout: 5))
        label("recurringTotal", contains: "386.00")
        tap("BackButton")
        tap("openCategories")
        XCTAssertTrue(element("category_购物").waitForExistence(timeout: 5))
        tap("category_购物")
        XCTAssertTrue(element("addSubcategory").waitForExistence(timeout: 5))
    }

    func testCycleSheetPreviewsAndSavesWeekendShift() {
        launch(["-YubaiSettingsFixture", "cycle"])
        XCTAssertTrue(element("cycleSheet").waitForExistence(timeout: 5))
        label("cyclePreviewRange", contains: "11.10 – 12.09")
        tap("cycleDay_15")
        label("cyclePreviewRange", contains: "11.15 – 12.14")
        tap("cycleDone")
        XCTAssertTrue(waitForDisappearance(element("cycleSheet")))
        label("settingsCycle", contains: "每月 15 日")
    }

    func testCloudSwitchWithoutKeyOpensKeySheet() {
        launch(["-YubaiSettingsFixture", "ai"])
        XCTAssertTrue(element("aiSettingsScroll").waitForExistence(timeout: 5))
        label("openCloudKey", contains: "sk-…3f2a")
        tap("assistantTone_温和")
        XCTAssertTrue(element("assistantTone_温和").isSelected)
        tap("openCloudKey")
        XCTAssertTrue(element("apiKeySheet").waitForExistence(timeout: 5))
        XCTAssertTrue(element("apiKeySave").isEnabled)
    }

    func testAddAccountFromAssetsAndArchiveFromEdit() {
        launch(["-YubaiAssetsFixture"])
        tap("overviewAddAccount")
        XCTAssertTrue(element("accountAddSheet").waitForExistence(timeout: 5))
        tap("accountType_credit")
        keys("1200")
        label("accountBalance", contains: "1,200")
        tap("saveAccount")
        XCTAssertTrue(waitForDisappearance(element("accountAddSheet")))
        XCTAssertTrue(element("overviewAccount_信用卡").waitForExistence(timeout: 5))
        label("overviewAccount_信用卡", contains: "−1,200.00")
        tap("overviewAccount_信用卡")
        tap("editAccount")
        XCTAssertTrue(element("accountEditScroll").waitForExistence(timeout: 5))
        tap("archiveAccount")
        tap("confirmAction")
        XCTAssertTrue(waitForDisappearance(element("accountEditScroll")))
    }

    func testNewLedgerOnboardsInOneSave() {
        launchScript("empty")
        XCTAssertTrue(element("onboardScene").waitForExistence(timeout: 10))
        tap("onboardDay_10"); tap("onboardNext")
        keys("18500")
        tap("settingsChip_370000")
        label("onboardSavingAmount", contains: "3,700")
        tap("onboardNext")
        tap("onboardAccount_储蓄卡"); tap("onboardAccount_储蓄卡")
        XCTAssertTrue(element("accountAddSheet").waitForExistence(timeout: 5))
        keys("32180"); tap("saveAccount")
        XCTAssertTrue(waitForDisappearance(element("accountAddSheet")))
        label("onboardLiquidCash", contains: "32,180.00")
        tap("onboardNext")
        XCTAssertTrue(waitForDisappearance(element("onboardScene")))
        XCTAssertTrue(element("openSettings").waitForExistence(timeout: 5))
        tap("openSettings")
        label("settingsCycle", contains: "每月 10 日")
        label("settingsSaving", contains: "3,700.00")
    }
}
