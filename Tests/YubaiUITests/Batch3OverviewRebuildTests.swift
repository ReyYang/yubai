import XCTest

final class Batch3OverviewRebuildTests: YubaiUITestCase {
    private let app = XCUIApplication()

    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws { app.terminate(); try super.tearDownWithError() }

    private func launch(_ fixture: [String], dark: Bool = false, hidden: Bool = false, xl: Bool = false) {
        app.launchArguments = fixture + ["-YubaiTheme", dark ? "dark" : "light", "-YubaiLogOverviewRenderCounts",
                                         "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        if xl { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryXL"] }
        app.launchEnvironment["YUBAI_GALLERY_HIDE_AMOUNTS"] = hidden ? "1" : "0"
        app.launchEnvironment["YUBAI_UI_TEST_KEEP_UNDO"] = "1"
        XCTAssertTrue(launchApp(app))
    }

    private func element(_ id: String) -> XCUIElement { control(id, in: app) }
    private func tap(_ id: String) {
        tapControl(element(id), in: app, settles: !id.hasPrefix("keypad_"), reveals: !id.hasPrefix("keypad_"))
    }

    private func label(_ id: String, contains text: String) {
        let target = element(id)
        XCTAssertTrue(UIConditionWait.run(timeout: 8, read: { target.exists && target.label.contains(text) }),
                      "\(id) does not contain \(text)")
    }

    private func keys(_ input: String) { for digit in input { tap("keypad_" + String(digit)) } }

    private func openFirstBill() {
        let first = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "overviewBill_")).firstMatch
        tapControl(first, in: app)
        XCTAssertTrue(element("billFloatingCard").waitForExistence(timeout: 5))
        tap("closeBill")
    }

    func testReviewPeriodsCustomCalendarAndQuickRanges() {
        launch(["-YubaiReviewFixture", "review"])
        label("overviewSpent", contains: "6,845.60")
        label("overviewSaved", contains: "5,000.00")
        label("overviewPeriod", contains: "11.10")
        tap("overviewPeriod"); tap("overviewPeriod_previous")
        label("overviewPeriod", contains: "上期")
        tap("overviewPeriod"); tap("overviewPeriod_custom")
        tap("overviewQuick_lastThreeCycles"); label("overviewDate_start", contains: "2026.09.10")
        tap("overviewQuick_samePeriodLastYear"); label("overviewDate_start", contains: "2025.11.10")
        tap("overviewQuick_thisYear"); label("overviewDate_start", contains: "2026.01.01")
        tap("overviewDate_end")
        XCTAssertTrue(element("overviewCalendar").waitForExistence(timeout: 5))
        tap("entryQuick_昨天")
        label("overviewDate_end", contains: "2026.11.22")
        tap("overviewPeriodApply"); label("overviewPeriod", contains: "自定义")
        tap("overviewPeriod"); tap("overviewPeriod_current")
        label("overviewPeriod", contains: "本期")
    }

    func testAnomalyDrillBillFilteringAndConditionalBudget() {
        launch(["-YubaiReviewDrillFixture"])
        label("overviewDrillAmount", contains: "1,318.00")
        label("overviewSubcategory_衣服", contains: "+181%")
        openFirstBill()
        tap("overviewBudget"); XCTAssertTrue(element("formulaPage").waitForExistence(timeout: 5))
        XCTAssertFalse(element("budgetKeypad").exists)
        tap("BackButton")
        tap("overviewSeeAll"); label("entriesSearchTotal", contains: "9 笔")
        XCTAssertTrue(element("entriesSearchCancel").exists)
        XCTAssertFalse(element("fundsFormula").exists)
        tap("entriesSearchCancel"); XCTAssertTrue(element("fundsFormula").waitForExistence(timeout: 5))

        tap("tab_insights")
        XCTAssertTrue(element("reviewDrillPage").waitForExistence(timeout: 5))
        tap("BackButton")
        XCTAssertTrue(waitForDisappearance(element("reviewDrillPage")))
        XCTAssertTrue(element("overviewDonut").waitForExistence(timeout: 5))
        tap("overviewCategory_其他 4 类")
        XCTAssertTrue(element("overviewSubcategory_交通").waitForExistence(timeout: 5))
        XCTAssertFalse(element("overviewBudget").exists)
        tap("overviewSeeAll"); label("entriesSearchTotal", contains: "4 笔")
    }

    func testAssetsMemoryFloorReserveCreditAndAddAccount() {
        launch(["-YubaiAssetsFixture"])
        label("overviewLiquidCash", contains: "58,420.00")
        label("overviewAccount_招行信用卡", contains: "−3,216.80")
        tap("tab_ledger"); tap("tab_insights")
        XCTAssertTrue(element("overviewSegment_资产").isSelected)
        tap("overviewFloor")
        XCTAssertTrue(element("savingsFloorSheet").waitForExistence(timeout: 5))
        dismissNativeSheet(in: app)
        XCTAssertTrue(waitForDisappearance(element("savingsFloorSheet")))
        tap("overviewReserve"); XCTAssertTrue(element("reservePage").waitForExistence(timeout: 5))
        tap("BackButton")
        tap("overviewAddAccount"); XCTAssertTrue(element("accountName").waitForExistence(timeout: 5))
    }

    func testAccountDetailTransferAndDigitsOnlyReconciliation() {
        launch(["-YubaiAccountFixture", "view"])
        label("overviewAccountBalance", contains: "32,180.00")
        label("overviewAccountReconciled", contains: "11.20")
        label("accountBalanceChart", contains: "近 30 天余额走势")
        openFirstBill()
        tap("overviewTransfer")
        XCTAssertTrue(element("entryNature_transfer").waitForExistence(timeout: 5))
        XCTAssertTrue(element("entryNature_transfer").isSelected)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label == %@", "转出，招行储蓄")).firstMatch.exists)
        dismissEntrySheet(in: app)

        tap("reconcileAccount"); label("overviewValuationAmount", contains: "32,180.00")
        XCTAssertFalse(element("reconcileApply").isEnabled)
        XCTAssertFalse(element("keypad_+").exists)
        XCTAssertFalse(element("saveQuickEntry").exists)
        keys("32056.40")
        label("overviewValuationAmount", contains: "32,056.40")
        label("overviewValuationDifference", contains: "−123.60")
        tap("reconcileApply")
        label("overviewAccountBalance", contains: "32,056.40")
        label("overviewAccountReconciled", contains: "11.23")
        label("toastMessage", contains: "已记调整 −123.60")
    }

    func testInvestmentValuationLeavesSpendableUnchanged() {
        launch(["-YubaiAssetsFixture"])
        tap("tab_ledger")
        let headline = element("fundsFormula")
        XCTAssertTrue(headline.waitForExistence(timeout: 5))
        let before = headline.value as? String
        XCTAssertEqual(before, "¥18,500.00")
        tap("tab_insights"); tap("overviewInvest_基金")
        label("overviewValuationAmount", contains: "41,236.00")
        keys("42018.50")
        label("overviewValuationDifference", contains: "+782.50")
        tap("overviewInvestApply")
        label("overviewInvestmentValue_基金", contains: "42,018.50")
        label("overviewInvestmentDate_基金", contains: "11.23")
        tap("tab_ledger"); XCTAssertEqual(headline.value as? String, before)
    }

    func testCreditValuationTypesAmountOwedAndAcceptsZero() {
        launch(["-YubaiAssetsFixture"])
        tap("overviewAccount_招行信用卡")
        label("overviewAccountBalance", contains: "−3,216.80")

        tap("reconcileAccount")
        XCTAssertFalse(element("overviewValuationSign").exists)
        label("overviewBookAmount", contains: "3,216.80")
        keys("3300")
        label("overviewValuationAmount", contains: "3,300")
        label("overviewValuationDifference", contains: "−83.20")
        tap("reconcileApply")
        label("overviewAccountBalance", contains: "−3,300.00")

        tap("reconcileAccount"); keys("0")
        XCTAssertEqual(element("overviewValuationAmount").label, "0")
        label("overviewValuationDifference", contains: "+3,300.00")
        tap("reconcileApply")
        XCTAssertTrue(waitForDisappearance(element("reconcileSheet")))
        XCTAssertEqual(element("overviewAccountBalance").label, "0.00")
    }

    func testDarkHiddenXLKeepsReviewAndNavigationUsable() {
        launch(["-YubaiReviewFixture", "review"], dark: true, hidden: true, xl: true)
        label("overviewSpent", contains: "金额已隐藏")
        XCTAssertTrue(element("addEntry").isHittable)
        XCTAssertTrue(element("tab_ledger").isHittable)
        tap("overviewAnomaly")
        label("overviewDrillAmount", contains: "金额已隐藏")
        XCTAssertTrue(element("BackButton").isHittable)
        tap("BackButton")
        tap("overviewSegment_资产")
        label("overviewLiquidCash", contains: "金额已隐藏")
    }
}
