import XCTest
import UIKit

final class AppFlowTests: XCTestCase {
    func application(demo: Bool = false, ledgerID: String = UUID().uuidString) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--test-ledger", ledgerID, "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"] + (demo ? ["--demo"] : [])
        return app
    }
    func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testEmptyLedgerCreateAccountRecordAndRestart() throws {
        continueAfterFailure = false
        let app = application(); app.launch()
        XCTAssertTrue(app.buttons["startLedger"].waitForExistence(timeout: 10))
        attach(app, "iPhone-01-welcome")
        app.buttons["startLedger"].tap()
        XCTAssertTrue(app.textFields["accountName"].waitForExistence(timeout: 5))
        app.textFields["accountName"].tap(); app.textFields["accountName"].typeText("UI Bank")
        app.textFields["accountBalance"].tap(); app.textFields["accountBalance"].typeText("1000")
        app.buttons["saveAccount"].tap()
        XCTAssertTrue(app.buttons["addEntry"].waitForExistence(timeout: 5))
        app.buttons["addEntry"].tap()
        XCTAssertTrue(app.textFields["entryAmount"].waitForExistence(timeout: 5))
        app.textFields["entryAmount"].tap(); app.textFields["entryAmount"].typeText("25.50")
        app.textFields["entryTitle"].tap(); app.textFields["entryTitle"].typeText("Lunch")
        app.buttons["saveEntry"].tap()
        app.tabBars.buttons["账本"].tap()
        XCTAssertTrue(app.staticTexts["Lunch"].waitForExistence(timeout: 5))
        attach(app, "iPhone-02-persisted-entry")
        app.terminate(); app.launch()
        XCTAssertTrue(app.tabBars.buttons["账本"].waitForExistence(timeout: 10)); app.tabBars.buttons["账本"].tap()
        XCTAssertTrue(app.staticTexts["Lunch"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["startLedger"].exists)
    }
    func testDemoNavigationAndPurchaseAssessment() throws {
        continueAfterFailure = false
        let app = application(demo: true); app.launch()
        XCTAssertTrue(app.staticTexts["给生活，留一点余白"].waitForExistence(timeout: 10))
        app.buttons["fundsFormula"].tap()
        XCTAssertTrue(app.staticTexts["减：已知付款"].waitForExistence(timeout: 5))
        app.buttons["fundsFormula"].tap()
        attach(app, "iPhone-03-overview")
        app.tabBars.buttons["账本"].tap(); attach(app, "iPhone-04-ledger")
        app.tabBars.buttons["安排"].tap(); attach(app, "iPhone-05-plans")
        app.buttons["房租分摊"].tap(); attach(app, "iPhone-06-rent")
        app.tabBars.buttons["洞察"].tap(); attach(app, "iPhone-07-insights")
        app.buttons["购买前咨询"].tap()
        XCTAssertTrue(app.textFields["想买什么"].waitForExistence(timeout: 5))
        app.textFields["想买什么"].tap(); app.textFields["想买什么"].typeText("Camera")
        app.textFields["金额"].tap(); app.textFields["金额"].typeText("999999")
        app.buttons["看看对资金的影响"].tap()
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["这笔购买会挤占已安排的资金"].waitForExistence(timeout: 5))
        attach(app, "iPhone-08-purchase")
    }
    func testInvalidAmountDoesNotSaveAndDemoDoesNotBecomeRealLedger() throws {
        continueAfterFailure = false
        let id = UUID().uuidString
        let app = application(demo: true, ledgerID: id); app.launch()
        XCTAssertTrue(app.buttons["addEntry"].waitForExistence(timeout: 10)); app.buttons["addEntry"].tap()
        app.textFields["entryAmount"].tap(); app.textFields["entryAmount"].typeText("0")
        app.textFields["entryTitle"].tap(); app.textFields["entryTitle"].typeText("Invalid")
        app.buttons["saveEntry"].tap()
        XCTAssertTrue(app.alerts["需要留意"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["金额需要大于零。"].exists)
        app.alerts.buttons["知道了"].tap(); app.buttons["取消"].tap()
        app.buttons["退出示例"].tap()
        XCTAssertTrue(app.buttons["startLedger"].waitForExistence(timeout: 5))
        app.terminate()
        let real = application(ledgerID: id); real.launch()
        XCTAssertTrue(real.buttons["startLedger"].waitForExistence(timeout: 10))
    }
    func testBillFileImport() throws {
        continueAfterFailure = false
        let app = application(demo: true)
        let statement = "微信支付账单明细\n交易时间,交易类型,交易对方,商品,收/支,金额(元),支付方式,当前状态,交易单号\n2026-09-20 12:30:00,商户消费,验证午餐店,工作日午餐,支出,28.00,零钱,支付成功,uitest001\n2026-09-20 13:00:00,商户消费,验证书店,一本书,支出,66.00,银行卡,支付成功,uitest002\n2026-09-20 14:00:00,转账,验证账户,转账,收入,1200.00,零钱,已收钱,uitest003\n"
        app.launchEnvironment["YUBAI_UI_STATEMENT"] = Data(statement.utf8).base64EncodedString(); app.launch()
        XCTAssertTrue(app.buttons["导入"].waitForExistence(timeout: 10)); app.buttons["导入"].tap()
        XCTAssertTrue(app.buttons["chooseBillFile"].waitForExistence(timeout: 5)); app.buttons["chooseBillFile"].tap()
        let browse = app.buttons.matching(NSPredicate(format: "label == '浏览' OR label == 'Browse'")).firstMatch
        XCTAssertTrue(browse.waitForExistence(timeout: 10)); browse.tap()
        let local = app.cells.matching(NSPredicate(format: "label == '我的iPhone'")).firstMatch
        if local.waitForExistence(timeout: 3) { local.tap() }
        let folder = app.cells.matching(NSPredicate(format: "label BEGINSWITH '余白,' OR label == '余白'")).firstMatch
        if folder.waitForExistence(timeout: 3) { folder.tap() }
        let file = app.cells.matching(NSPredicate(format: "label CONTAINS '余白验证账单'")).firstMatch
        if !file.waitForExistence(timeout: 10) { print("FILE_PICKER_STATE\n" + app.debugDescription); XCTFail("Synthetic statement was not visible in Files"); return }; file.tap()
        app.buttons["打开"].tap()
        XCTAssertTrue(app.buttons["mapping_银行卡"].waitForExistence(timeout: 10)); app.buttons["mapping_银行卡"].tap()
        app.buttons["工资卡"].tap()
        XCTAssertTrue(app.buttons["mapping_零钱"].waitForExistence(timeout: 10)); app.buttons["mapping_零钱"].tap()
        app.buttons["微信零钱"].tap()
        XCTAssertTrue(app.buttons["commitImport"].waitForExistence(timeout: 10))
        attach(app, "iPhone-09-import-preview")
        XCTAssertTrue(app.buttons["commitImport"].isEnabled); app.buttons["commitImport"].tap()
        XCTAssertTrue(app.staticTexts["这一份，整理好了"].waitForExistence(timeout: 8))
        attach(app, "iPhone-10-import-result")
        app.buttons["查看导入明细"].tap()
        XCTAssertTrue(app.buttons["commitImport"].waitForExistence(timeout: 10)); XCTAssertFalse(app.buttons["commitImport"].isEnabled)
        attach(app, "iPhone-11-import-repeat")
    }
    func testReceiptImageOCRAndConfirmedSave() throws {
        continueAfterFailure = false
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 900, height: 1200))
        let image = renderer.image { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 900, height: 1200))
            let lines = [("验证咖啡店", 80.0, 58.0), ("支付成功", 220.0, 44.0), ("¥ 28.50", 370.0, 86.0), ("2026-09-20 12:30:00", 570.0, 36.0), ("合成测试图片，不是真实账单", 990.0, 28.0)]
            for (text, y, size) in lines { (text as NSString).draw(at: CGPoint(x: 80, y: y), withAttributes: [.font: UIFont.systemFont(ofSize: size), .foregroundColor: UIColor.black]) }
        }
        let app = application(demo: true); app.launchEnvironment["YUBAI_UI_RECEIPT"] = try XCTUnwrap(image.pngData()).base64EncodedString(); app.launch()
        XCTAssertTrue(app.buttons["导入"].waitForExistence(timeout: 10)); app.buttons["导入"].tap()
        XCTAssertTrue(app.buttons["chooseBillFile"].waitForExistence(timeout: 5)); app.buttons["chooseBillFile"].tap()
        let browse = app.buttons.matching(NSPredicate(format: "label == '浏览' OR label == 'Browse'")).firstMatch
        XCTAssertTrue(browse.waitForExistence(timeout: 10)); browse.tap()
        let local = app.cells["DOC.sidebar.item.我的iPhone"]; if local.waitForExistence(timeout: 3) { local.tap() }
        let folder = app.cells.matching(NSPredicate(format: "label BEGINSWITH '余白,' OR label == '余白'")).firstMatch; if folder.waitForExistence(timeout: 3) { folder.tap() }
        let file = app.cells.matching(NSPredicate(format: "label CONTAINS '余白验证截图'")).firstMatch
        XCTAssertTrue(file.waitForExistence(timeout: 10)); file.tap(); app.buttons["打开"].tap()
        XCTAssertTrue(app.textFields["确认金额"].waitForExistence(timeout: 30))
        XCTAssertEqual(app.textFields["确认金额"].value as? String, "28.5")
        attach(app, "iPhone-12-OCR-confirmation")
        app.buttons["确认并保存"].tap()
        XCTAssertTrue(app.staticTexts["这一份，整理好了"].waitForExistence(timeout: 10))
        attach(app, "iPhone-13-OCR-result")
    }
    func testEncryptedBackupExportAndRestoreIntoEmptyLedger() throws {
        continueAfterFailure = false
        let app = application(); app.launch()
        XCTAssertTrue(app.buttons["startLedger"].waitForExistence(timeout: 10)); app.buttons["startLedger"].tap()
        app.textFields["accountName"].tap(); app.textFields["accountName"].typeText("Backup Bank")
        app.textFields["accountBalance"].tap(); app.textFields["accountBalance"].typeText("1234.56")
        app.buttons["saveAccount"].tap()
        app.tabBars.buttons["我的"].tap(); app.swipeUp()
        app.buttons["备份、恢复与导出"].tap()
        let exportPassword = app.secureTextFields["备份密码（推荐，至少 8 位）"]
        XCTAssertTrue(exportPassword.waitForExistence(timeout: 5)); exportPassword.tap(); exportPassword.typeText("test-backup-123")
        app.buttons["导出完整备份"].tap()
        let save = app.buttons.matching(NSPredicate(format: "label == '存储' OR label == '保存'")).firstMatch
        if !save.waitForExistence(timeout: 10) { print("EXPORT_PICKER_STATE\n" + app.debugDescription); XCTFail("Save action is unavailable"); return }
        let local = app.cells["DOC.sidebar.item.我的iPhone"]; if local.waitForExistence(timeout: 3) { local.tap() }
        let folder = app.cells.matching(NSPredicate(format: "label BEGINSWITH '余白,' OR label == '余白'")).firstMatch; if folder.waitForExistence(timeout: 3) { folder.tap() }
        save.tap()
        if app.buttons["替换"].waitForExistence(timeout: 2) { app.buttons["替换"].tap() }
        XCTAssertTrue(app.staticTexts["文件已保存到你选择的位置。"].waitForExistence(timeout: 10))
        app.terminate()
        let fresh = application(); fresh.launch()
        XCTAssertTrue(fresh.buttons["恢复备份"].waitForExistence(timeout: 10)); fresh.buttons["恢复备份"].tap()
        let restorePassword = fresh.secureTextFields["如果备份已加密，填写密码"]
        XCTAssertTrue(restorePassword.waitForExistence(timeout: 5)); restorePassword.tap(); restorePassword.typeText("test-backup-123")
        fresh.buttons["选择备份文件"].tap()
        let browse = fresh.buttons.matching(NSPredicate(format: "label == '浏览' OR label == 'Browse'")).firstMatch
        if browse.waitForExistence(timeout: 5) { browse.tap() }
        let localFile = fresh.cells["DOC.sidebar.item.我的iPhone"]; if localFile.waitForExistence(timeout: 3) { localFile.tap() }
        let appFolder = fresh.cells.matching(NSPredicate(format: "label BEGINSWITH '余白,' OR label == '余白'")).firstMatch; if appFolder.waitForExistence(timeout: 3) { appFolder.tap() }
        let file = fresh.cells.matching(NSPredicate(format: "label CONTAINS '余白备份'")).firstMatch
        if !file.waitForExistence(timeout: 10) { print("RESTORE_PICKER_STATE\n" + fresh.debugDescription); XCTFail("Exported backup is unavailable"); return }; file.tap()
        if fresh.buttons["打开"].exists { fresh.buttons["打开"].tap() }
        XCTAssertTrue(fresh.buttons["确认恢复这份账本"].waitForExistence(timeout: 10))
        attach(fresh, "iPhone-14-verified-backup")
        fresh.buttons["确认恢复这份账本"].tap(); fresh.buttons["closeSheet"].tap()
        XCTAssertTrue(fresh.tabBars.buttons["我的"].waitForExistence(timeout: 10)); fresh.tabBars.buttons["我的"].tap()
        fresh.buttons["账户与余额核对"].tap()
        XCTAssertTrue(fresh.staticTexts["Backup Bank"].waitForExistence(timeout: 5))
        attach(fresh, "iPhone-15-restored-account")
    }
    func testDarkAppearanceAndAccessibilityText() throws {
        continueAfterFailure = false
        let app = application(demo: true)
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["我的"].waitForExistence(timeout: 10)); app.tabBars.buttons["我的"].tap()
        let appearance = app.buttons.matching(NSPredicate(format: "label BEGINSWITH '外观,'")).firstMatch
        for _ in 0..<16 { if appearance.exists && appearance.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(appearance.isHittable); appearance.tap(); app.buttons["深色"].tap()
        if app.buttons["关闭提示"].exists { app.buttons["关闭提示"].tap() }
        app.tabBars.buttons["现在"].tap()
        XCTAssertTrue(app.buttons["addEntry"].waitForExistence(timeout: 10)); attach(app, "iPhone-16-dark-large-overview")
        app.swipeUp(); attach(app, "iPhone-17-dark-large-scroll")
        app.tabBars.buttons["账本"].tap(); attach(app, "iPhone-18-dark-large-ledger")
        app.tabBars.buttons["我的"].tap(); attach(app, "iPhone-19-dark-large-settings")
    }
}
