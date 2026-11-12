import XCTest

/// Opt-in pixel inventory. Run scripts/gallery.sh; ordinary UI tests skip this class.
/// All navigation uses the same controls as the owner. Each area gets a fresh ledger.
final class ScreenGalleryTests: XCTestCase {
    private var app = XCUIApplication()
    private var missing: [String] = []
    private var planned: [String] = []
    private var activeStop: String?
    private var issues: [String] = []
    private var writeErrors: [String] = []
    private var prefix = ""
    private var directory: URL!
    private let longName = "为了搬家以后和家人朋友一起长期使用而认真挑选并且反复比较尺寸颜色材质保修与运输安排的生活用品"
    private let latinName = "SupercalifragilisticexpialidociousPneumonoultramicroscopicsilicovolcanoconiosis"

    private struct Miss: Error, CustomStringConvertible { let description: String }

    override func setUpWithError() throws {
        try super.setUpWithError()
        guard let path = ProcessInfo.processInfo.environment["YUBAI_GALLERY_DIR"], !path.isEmpty else {
            throw XCTSkip("Screen gallery is opt-in: scripts/gallery.sh")
        }
        directory = URL(fileURLWithPath: path, isDirectory: true)
        do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        catch { writeErrors.append("Host directory unavailable; use xcresult attachments: " + error.localizedDescription) }
        continueAfterFailure = true
        executionTimeAllowance = 3600
    }

    // A native XCTest interaction can record an issue without throwing. Associate it
    // with this stop, keep walking, and emit one aggregate failure after all shots.
    override func record(_ issue: XCTIssue) {
        if activeStop != nil { issues.append(issue.compactDescription) }
        else { super.record(issue) }
    }

    override func tearDownWithError() throws {
        if directory != nil {
            app.terminate()
            let label = prefix.isEmpty ? "full" : String(prefix.dropLast())
            let report = missing.joined(separator: "\n") + (missing.isEmpty ? "" : "\n")
            try? report.write(to: directory.appendingPathComponent("missing-\(label).txt"), atomically: true, encoding: .utf8)
            try? (planned.joined(separator: "\n") + "\n").write(to: directory.appendingPathComponent("planned-\(label).txt"), atomically: true, encoding: .utf8)
            let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
            let reports = files
                .filter { $0.lastPathComponent.hasPrefix("missing-") && $0.pathExtension == "txt" }
            let all = reports.sorted { $0.lastPathComponent < $1.lastPathComponent }.compactMap { try? String(contentsOf: $0, encoding: .utf8) }.joined()
            try? all.write(to: directory.appendingPathComponent("missing.txt"), atomically: true, encoding: .utf8)
            let attachment = XCTAttachment(string: report)
            attachment.name = "missing-\(label).txt"; attachment.lifetime = .keepAlways; add(attachment)
            let combined = XCTAttachment(string: all.isEmpty ? report : all)
            combined.name = "missing.txt"; combined.lifetime = .keepAlways; add(combined)
            if !writeErrors.isEmpty {
                let errors = XCTAttachment(string: writeErrors.joined(separator: "\n"))
                errors.name = "write-errors-\(label).txt"; errors.lifetime = .keepAlways; add(errors)
            }
            if !missing.isEmpty { XCTFail("Gallery stops not reached:\n" + report) }
        }
        try super.tearDownWithError()
    }

    /// This is the only screenshot writer, including failure screenshots.
    private func shot(_ name: String) {
        Thread.sleep(forTimeInterval: 0.25) // Only a short pixel settle; navigation uses predicate waits.
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        if let path = ProcessInfo.processInfo.environment["YUBAI_GALLERY_DIR"], !path.isEmpty {
            do { try screenshot.pngRepresentation.write(to: URL(fileURLWithPath: path, isDirectory: true).appendingPathComponent(name + ".png"), options: .atomic) }
            catch { writeErrors.append(name + ": " + error.localizedDescription) }
        }
    }

    @discardableResult private func stop(_ name: String, _ walk: () throws -> Void) -> Bool {
        let name = prefix + name
        planned.append(name); activeStop = name; issues = []
        defer { activeStop = nil }
        do {
            try walk()
            if !issues.isEmpty { throw Miss(description: issues.joined(separator: "; ")) }
            shot(name)
            if !issues.isEmpty { throw Miss(description: issues.joined(separator: "; ")) }
            return true
        } catch {
            missing.append(name + "-MISSING: " + String(describing: error).replacingOccurrences(of: "\n", with: " "))
            // Attach the current pixels and hierarchy even if a host-path write fails.
            shot(name + "-MISSING")
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = name + "-MISSING-hierarchy"; hierarchy.lifetime = .keepAlways; add(hierarchy)
            return false
        }
    }

    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
    private func buttonPrefix(_ value: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", value)).firstMatch
    }
    private func wait(_ predicate: @escaping () -> Bool, _ reason: String, timeout: TimeInterval = 6) throws {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in predicate() }, object: nil)
        guard XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed else { throw Miss(description: reason) }
    }
    private func require(_ id: String, timeout: TimeInterval = 6) throws {
        guard element(id).waitForExistence(timeout: timeout) else { throw Miss(description: "Missing identifier: " + id) }
    }
    private func launch(_ fixture: String = "gallery", dark: Bool = false, large: Bool = false, organization: String? = nil, statement: String? = nil) throws {
        app.terminate(); app = XCUIApplication()
        app.launchArguments = ["--test-ledger", UUID().uuidString, "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", large ? "UICTContentSizeCategoryAccessibilityL" : "UICTContentSizeCategoryL"]
        app.launchEnvironment["YUBAI_UI_TEST_SCRIPT"] = fixture
        app.launchEnvironment["YUBAI_UI_TEST_CONFIGURED_KEY"] = "1"
        app.launchEnvironment["YUBAI_UI_TEST_KEEP_UNDO"] = "1"
        app.launchEnvironment["YUBAI_GALLERY_APPEARANCE"] = dark ? "dark" : "light"
        app.launchEnvironment["DEEPSEEK_API_KEY"] = ""
        if let organization { app.launchEnvironment["YUBAI_UI_ORGANIZATION_SCENARIO"] = organization }
        if let statement { app.launchEnvironment["YUBAI_UI_STATEMENT"] = Data(statement.utf8).base64EncodedString() }
        app.launch()
        try require(fixture == "empty" ? "welcomeScroll" : fixture == "gallery-locked" ? "lockedPage" : "mainNavigation", timeout: 15)
    }
    private func drag(_ scroll: XCUIElement, up: Bool = true) throws {
        guard scroll.exists && scroll.isHittable else { throw Miss(description: "Scroll container unavailable: " + scroll.identifier) }
        var frame = scroll.frame.intersection(app.frame).insetBy(dx: 12, dy: 12)
        let navigation = element("mainNavigation"), keyboard = app.keyboards.firstMatch
        if navigation.exists && navigation.isHittable { frame.size.height = min(frame.maxY, navigation.frame.minY) - frame.minY }
        if keyboard.exists { frame.size.height = min(frame.maxY, keyboard.frame.minY) - frame.minY }
        guard frame.height > 60 else { throw Miss(description: "No visible scroll viewport") }
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let start = origin.withOffset(CGVector(dx: frame.midX - app.frame.minX, dy: frame.minY + frame.height * (up ? 0.78 : 0.22) - app.frame.minY))
        let end = origin.withOffset(CGVector(dx: frame.midX - app.frame.minX, dy: frame.minY + frame.height * (up ? 0.22 : 0.78) - app.frame.minY))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
    }
    private func reveal(_ target: XCUIElement) throws {
        _ = target.waitForExistence(timeout: 3)
        for _ in 0..<24 {
            if target.exists && target.isHittable { return }
            guard app.alerts.count == 0 else { break }
            let containers = app.scrollViews.allElementsBoundByIndex + app.collectionViews.allElementsBoundByIndex + app.tables.allElementsBoundByIndex
            let scrolls = containers.filter { $0.isHittable && $0.frame.height > 120 && $0.frame.width > app.frame.width * 0.65 }
            let containing = scrolls.last { target.exists && $0.descendants(matching: target.elementType).matching(identifier: target.identifier).count > 0 }
            guard let scroll = containing ?? scrolls.last else { break }
            let above = target.exists && !target.frame.isEmpty && target.frame.maxY < scroll.frame.minY + 20
            try drag(scroll, up: !above)
        }
        try wait({ target.exists && target.isHittable }, "Not reachable: " + (target.exists ? target.identifier : target.description), timeout: 2)
    }
    private func tap(_ target: XCUIElement) throws {
        try reveal(target)
        try wait({ target.exists && target.isEnabled && target.isHittable }, "Control disabled: " + target.identifier)
        target.tap()
    }
    private func tap(_ id: String) throws { try tap(element(id)) }
    private func type(_ value: String, into id: String) throws {
        let field = element(id); try tap(field)
        try wait({ self.app.keyboards.firstMatch.exists }, "Keyboard did not open for " + id)
        field.typeText(value)
    }
    private func keys(_ value: String) throws { for key in value { try tap("keypad_" + String(key)) } }
    private func back() throws {
        let custom = element("ledgerBack")
        if custom.exists && custom.isHittable { try tap(custom) }
        else { try tap(app.navigationBars.buttons.firstMatch) }
    }
    private func root(_ tab: String) throws {
        for _ in 0..<10 {
            if element("mainNavigation").exists && element("mainNavigation").isHittable { break }
            if element("cancelManualSheet").exists && element("cancelManualSheet").isHittable {
                try tap("cancelManualSheet")
                if app.buttons["放弃这笔"].waitForExistence(timeout: 0.3) { try tap(app.buttons["放弃这笔"]) }
            } else { try back() }
        }
        try tap("tab_" + tab)
        try wait({ self.element("tab_" + tab).isSelected }, "Tab did not select: " + tab)
    }
    private func settings(_ destination: String? = nil) throws {
        try root("now"); try tap("openSettings"); try require("settingsScroll")
        if let destination { try tap(destination) }
    }
    private func formula() throws { try root("now"); try tap("fundsFormula"); try require("formulaPage") }
    private func close(_ id: String = "cancelManualSheet") throws { try tap(id) }
    private func bill(_ title: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'formulaBill_' AND label == %@", "看" + title)).firstMatch
    }
    private func longPress(_ target: XCUIElement) throws { try reveal(target); target.press(forDuration: 0.8) }
    private func toast() throws { try require("toastMessage"); try require("undoLastChange") }
    private func search(_ value: String) throws {
        try root("ledger"); try type(value, into: "entriesSearch")
        try require("entriesSearchTotal")
    }
    private func calendarDay(_ date: Date, from displayed: Date = Date(), id: String = "entryCalendar") throws {
        let calendar = Calendar.current
        let from = calendar.dateComponents([.year, .month], from: displayed), to = calendar.dateComponents([.year, .month], from: date)
        let months = (to.year! - from.year!) * 12 + to.month! - from.month!
        if months != 0 { for _ in 0..<abs(months) { try tap(id + (months > 0 ? "Next" : "Previous")) } }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "zh_CN"); formatter.dateFormat = "yyyy-MM-dd"
        try tap(id + "Day_" + formatter.string(from: date))
    }
    private func galleryID(_ number: Int) -> String { String(format: "47000000-0000-0000-0000-%012d", number) }
    private var galleryStatement: String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "zh_CN"); formatter.dateFormat = "yyyy-MM-dd"
        var rows = ["时间,收支,金额,名称,分类,交易单号"]
        for index in 0..<16 {
            let date = Calendar.current.date(byAdding: .day, value: -index, to: Date())!
            let amount = index == 0 ? "0.00" : index == 1 ? "1234567.89" : "0.01"
            let category = index == 2 ? "合成导入分类" + longName : index == 3 ? "" : "餐饮"
            let title = index % 2 == 0 ? longName : latinName
            rows.append("\(formatter.string(from: date)) 12:00:00,支出,\(amount),\(title),\(category),gallery-csv-\(index)")
        }
        return rows.joined(separator: "\n")
    }
    private func detail() throws {
        // Ordinary ledger rows open 改一笔. A bought wish exposes the existing detail route.
        try root("saving"); try tap("openWishlist"); try tap("pastWishes")
        try tap("wishBoughtEntry_" + galleryID(406)); try require("entryDetailTitle")
    }

    func testFullWalk() {
        rootsAndLedger()
        formulaAndAccounts()
        bills()
        saving()
        entrySheets()
        categories()
        yubai()
        settingsPages()
        importsAndReceipt()
        specificStates()
        emptyAndWelcome()
    }

    private func rootsAndLedger() {
        stop("01-now-01-top") { try launch(); try require("fundsFormula") }
        stop("01-now-02-middle") { try drag(element("nowScroll")) }
        stop("01-now-03-bottom") { for _ in 0..<6 { try drag(element("nowScroll")) } }
        stop("01-now-04-hidden-amounts") { try root("now"); try tap("toggleAmountVisibility"); try require("fundsFormula") }
        stop("01-now-05-todo") { try launch(); try tap("openLetterInbox"); try require("letterInbox") }
        stop("01-now-06-weekly-review") { try tap("weeklyReviewRow"); try require("letterBody") }
        stop("01-now-07-weekly-review-bottom") { try drag(app.scrollViews.firstMatch) }
        stop("01-now-08-hidden-ledger") { try launch(); try tap("toggleAmountVisibility"); try root("ledger"); try require("entriesScroll") }
        stop("01-now-09-hidden-saving") { try root("saving"); try require("savingTabScroll") }
        stop("01-now-10-hidden-yubai") { try root("yubai"); try require("openProfile") }
        stop("01-now-11-butler-evidence-sheet") { try launch(); try tap("openLetterInbox"); try tap("butlerEvidence_" + galleryID(652)); try require("butlerEvidencePage") }
        stop("01-now-12-proposal-sheet") { try launch(); try tap("openLetterInbox"); try tap("butlerPrimary_" + galleryID(652)); try require("butlerProposalPage") }
        stop("01-now-13-proposal-applied-toast") { try tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH '改好这'")).firstMatch); try toast() }
        stop("02-saving-01-tab") { try launch(); try root("saving"); try require("savingTabScroll") }
        stop("03-ledger-01-detail-top") { try launch(); try root("ledger"); try require("entriesScroll") }
        stop("03-ledger-02-detail-middle") { for _ in 0..<3 { try drag(element("entriesScroll")) } }
        stop("03-ledger-03-detail-bottom") { for _ in 0..<18 { try drag(element("entriesScroll")) } }
        stop("03-ledger-04-search") { try launch(); try search(longName); try reveal(buttonPrefix("ledgerEntry_")) }
        stop("03-ledger-05-filter-unclassified") { try tap("entriesSearchCancel"); try tap("entriesFilter_没分类"); try require("activeEntryCount") }
        stop("03-ledger-06-filter-income") { try tap("entriesFilter_收入"); try require("activeEntryCount") }
        stop("03-ledger-07-future-entry") { try launch(); try search("合成未来账目"); try reveal(element("ledgerEntry_" + galleryID(201))); try wait({ self.element("ledgerEntry_" + self.galleryID(201)).value as? String == "未来" }, "Future row state") }
        stop("03-ledger-08-entry-detail") { try launch(); try detail() }
        stop("03-ledger-09-entry-edit") { try tap("entryDetailEdit"); try require("editEntryAmount") }
        stop("03-ledger-10-entry-edit-keyboard") { try tap("entryPurpose"); try requireKeyboard() }
        stop("03-ledger-11-split-unitemized") { try launch(); try search("没细记"); try tap("ledgerEntry_" + galleryID(200)); try tap("entryDetailSplit"); try require("splitUnitemizedScroll") }
        stop("03-ledger-12-split-filled") { try keys("100"); try tap("entryCategory_餐饮"); try tap("splitUnitemizedAdd"); try keys("312"); try tap("entryCategory_交通"); try tap("splitUnitemizedAdd"); try require("splitUnitemizedParts") }
        stop("03-ledger-13-split-toast") { try tap("splitUnitemizedDone"); try toast() }
        stop("03-ledger-14-split-undone") { try tap("undoLastChange"); try require("ledgerEntry_" + galleryID(200)) }
        stop("03-ledger-15-where-top") { try launch(); try root("ledger"); try tap("ledgerMode_where"); try require("whereTotal") }
        stop("03-ledger-16-where-middle") { try drag(element("insightsScroll")) }
        stop("03-ledger-17-where-cash-chart") { try reveal(element("cashTimelineChart")); try require("cashTimelineCard") }
        stop("03-ledger-18-where-chart-selected") { try tap("cashTimelineChart"); try require("cashTimelineReadout") }
        stop("03-ledger-19-where-bottom") { for _ in 0..<5 { try drag(element("insightsScroll")) } }
        stop("03-ledger-20-where-category") { try launch(); try root("ledger"); try tap("ledgerMode_where"); try tap("insightCategory_0"); try require("whereCategoryPage") }
        stop("03-ledger-21-where-category-bottom") { try reveal(element("whereCategoryEntries")) }
        stop("03-ledger-22-category-records") { try tap("whereCategoryEntries"); try require("clearLedgerCategory") }
        stop("03-ledger-23-where-custom-range") { try launch(); try root("ledger"); try tap("ledgerMode_where"); try tap("wherePeriod_3"); try wait({ self.app.datePickers.count > 0 }, "Custom range picker") }
        stop("03-ledger-24-month-picker") { try launch(); try root("ledger"); try tap("entriesMonth"); try wait({ self.app.pickerWheels.count > 0 }, "Month wheel") }
        stop("03-ledger-25-search-empty") { try launch(); try search("合成绝对不存在的账目编号999"); try wait({ self.element("activeEntryCount").label.contains("0") }, "Search empty state") }
    }

    private func formulaAndAccounts() {
        stop("04-formula-01-current") { try launch(); try formula() }
        stop("04-formula-02-bottom") { try reveal(element("formulaAddBill")) }
        stop("04-formula-03-cycle-menu") { try tap("formulaCycle"); try require("formulaCyclePast_0") }
        stop("04-formula-04-past-cycle") { try tap("formulaCyclePast_0"); try require("closedFormulaCard") }
        stop("04-formula-05-past-cycle-where") { try tap("closedFormulaWhere"); try require("whereTotal") }
        stop("04-formula-06-edit-reserve") { try launch(); try formula(); try tap("formulaRow_fixedSavings"); try require("amountSheetAmount") }
        stop("04-formula-07-edit-saving") { try launch(); try formula(); try tap("formulaRow_saving"); try require("amountSheetAmount") }
        stop("04-formula-08-budget") { try launch(); try formula(); try tap("openSpendingParts"); try require("spendingPartsPage") }
        stop("04-formula-09-add-budget-alert") { try tap("addBudgetPart"); try wait({ self.app.alerts.firstMatch.exists }, "Add budget alert") }
        stop("04-formula-10-budget-alert-keyboard") { try tap(app.alerts.firstMatch.textFields.firstMatch); app.alerts.firstMatch.textFields.firstMatch.typeText(longName); try requireKeyboard() }
        stop("04-formula-11-budget-amount-sheet") { try launch(); try formula(); try tap("openSpendingParts"); try tap("budgetAmount_合成超支分项" + longName); try require("amountSheetAmount") }
        stop("04-formula-12-budget-category-sheet") { try launch(); try formula(); try tap("openSpendingParts"); try tap("budgetCategory_" + galleryID(350)); try require("categoryPickerCategory_餐饮") }
        stop("05-accounts-01-list-top") { try launch(); try formula(); try tap("formulaRow_hand"); try require("accountsPage") }
        stop("05-accounts-02-list-bottom") { try reveal(element("addAccount")) }
        stop("05-accounts-03-credit") { try tap("accountRow_信用卡"); try require("accountDetailPage") }
        stop("05-accounts-04-credit-editor") { try tap("editAccount"); try require("accountName") }
        stop("05-accounts-05-add-account") { try launch(); try formula(); try tap("formulaRow_hand"); try tap("addAccount"); try require("accountName") }
        stop("05-accounts-06-editor-long-keyboard") { try type(longName + latinName, into: "accountName"); try requireKeyboard() }
        stop("05-accounts-07-archived-account") { try launch(); try formula(); try tap("formulaRow_hand"); try tap("accountRow_已归档的旧银行卡"); try require("accountDetailPage") }
        stop("05-accounts-08-reconcile") { try launch(); try formula(); try tap("formulaRow_hand"); try tap("reconcileAll"); try require("reconcileSheet") }
        stop("05-accounts-09-reconcile-one-account") { try launch(); try tap("openLetterInbox"); let card = element("butlerCard_staleBalance"); try tap(card.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'butlerPrimary_' ")).firstMatch); try require("accountBalance"); try wait({ self.element("accountBalance").isEnabled }, "Single-account reconciliation") }
    }

    private func bills() {
        stop("06-bills-01-list") { try launch(); try formula(); try tap("formulaRow_bills"); try require("fixedFlowsScroll") }
        stop("06-bills-02-list-bottom") { for _ in 0..<12 { try drag(element("fixedFlowsScroll")) } }
        stop("06-bills-03-editor") { try launch(); try formula(); try tap("formulaRow_bills"); try tap(buttonPrefix("editFixedFlow_")); try require("fixedFlowTitle") }
        stop("06-bills-04-editor-schedule") { try tap("fixedFlowSchedule"); try wait({ self.app.datePickers.count > 0 || self.app.pickerWheels.count > 0 }, "Schedule controls") }
        stop("06-bills-05-detail") { try launch(); try formula(); try tap("formulaBill_" + galleryID(300)); try require("billDetailPage") }
        stop("06-bills-06-detail-history") { try reveal(element("billDetailHistory")) }
        stop("06-bills-07-long-press-menu") { try launch("v45-bill"); try formula(); try longPress(bill("话费和宽带")); try require("billMenu_move") }
        stop("06-bills-08-move-occurrence") { try tap("billMenu_move"); try require("billMoveSheet") }
        stop("06-bills-09-move-future") { try calendarDay(Calendar.current.date(byAdding: .day, value: 2, to: Date())!, id: "billMoveCalendar") }
        stop("06-bills-10-move-toast") { try tap("billMoveDone"); try toast() }
        stop("06-bills-11-variable-pay") { try launch("v45-bill"); try formula(); let row = bill("电费"); try reveal(row); let id = String(row.identifier.dropFirst("formulaBill_".count)); try tap("billCheck_" + id); try require("amountSheetAmount") }
        stop("06-bills-12-paid-toast") { try keys("163.40"); try tap("amountSheetDone"); try toast() }
        stop("06-bills-13-link-existing") { try launch("v45-bill"); try formula(); try longPress(bill("话费和宽带")); try tap("billMenu_linked"); try require("billLinkSheet") }
        stop("06-bills-14-match-existing") { try launch("v45-bill-match"); try formula(); let row = bill("话费和宽带"); try reveal(row); let id = String(row.identifier.dropFirst("formulaBill_".count)); try tap("billCheck_" + id); try require("billMatchConfirm") }
        stop("06-bills-15-skip-toast") { try launch("v45-bill"); try formula(); try longPress(bill("话费和宽带")); try tap("billMenu_skip"); try toast() }
        stop("06-bills-16-stop-confirmation") { try launch("v45-bill"); try formula(); try longPress(bill("话费和宽带")); try tap("billMenu_stop"); try require("fixedFlowStopConfirm") }
        stop("06-bills-17-stop-toast") { try tap("fixedFlowStopConfirm"); try toast() }
        stop("06-bills-18-add-bill") { try launch(); try formula(); try tap("formulaAddBill"); try require("billAddName") }
        stop("06-bills-19-add-bill-long-keyboard") { try type(longName + latinName, into: "billAddName"); try requireKeyboard() }
        stop("06-bills-20-add-bill-day") { try tap("billAddDay"); try require("billDay_1") }
        stop("06-bills-21-add-recurring-editor") { try launch(); try formula(); try tap("formulaRow_bills"); try tap("addFixedFlow"); try require("fixedFlowTitle") }
    }

    private func saving() {
        stop("02-saving-02-reserve") { try launch(); try root("saving"); try tap("openReserve"); try require("reservePage") }
        stop("02-saving-03-payback-progress") { try reveal(element("reservePaybackProgress")) }
        stop("02-saving-04-payback-offer") { try reveal(element("reservePaybackOffer")) }
        stop("02-saving-05-payback-accepted") { try tap("reservePaybackAccept"); try require("reservePaybackProgress") }
        stop("02-saving-06-edit-total") { try tap("editReserveTotal"); try require("amountSheetAmount") }
        stop("02-saving-07-reserve-adjustment-toast") { try keys("7200"); try tap("saveReserveTotal"); try toast() }
        stop("02-saving-08-monthly-fixed") { try launch(); try root("saving"); try tap("openSavings"); try require("savingsPage") }
        stop("02-saving-09-monthly-share") { try tap("savingMode_share"); try require("savingsPage") }
        stop("02-saving-10-monthly-amount") { try tap("editSavingTarget"); try require("saveSavingsAmount") }
        stop("02-saving-11-wishlist-top") { try launch(); try root("saving"); try tap("openWishlist"); try require("wishlistPage") }
        stop("02-saving-12-wishlist-cooling") { try reveal(element("wish_" + galleryID(400))) }
        stop("02-saving-13-wish-detail-inline") { try reveal(element("wish_" + galleryID(402))) }
        stop("02-saving-14-wish-purchase-picker") { try tap("wishPurchase_" + galleryID(402)); try require("wishEntryPicker") }
        stop("02-saving-15-wishlist-past") { try launch(); try root("saving"); try tap("openWishlist"); try tap("pastWishes"); try wait({ self.app.navigationBars["过去的心愿"].exists }, "Past wishes page") }
        stop("02-saving-16-wishlist-past-bottom") { for _ in 0..<8 { try drag(app.scrollViews.firstMatch) } }
        stop("02-saving-17-wish-dropped-toast") { try launch(); try root("saving"); try tap("openWishlist"); let wish = element("wish_" + galleryID(400)); try reveal(wish.buttons["不买了"]); try tap(wish.buttons["不买了"]); try toast() }
        stop("02-saving-18-monthly-history") { try launch(); try root("saving"); try tap("openSavings"); try reveal(element("savingHistory")) }
        stop("02-saving-19-payback-declined") { try launch(); try root("saving"); try tap("openReserve"); try tap("reservePaybackDecline"); try require("reservePaybackProgress") }
        stop("02-saving-20-focused-wish-sheet") { try launch(); try tap("openLetterInbox"); let card = element("butlerCard_cooldownDue"); try tap(card.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'butlerPrimary_' ")).firstMatch); try require("wishlistPage"); try require("closeSheet") }
    }

    private func entrySheets() {
        stop("07-entry-01-expense-zero") { try launch(); try tap("addEntry"); try require("entryKeypadAmount") }
        stop("07-entry-02-category-grid") { try keys("0.01"); try require("entryCategoryMore") }
        stop("07-entry-03-more-categories") { try tap("entryCategoryMore"); try require("entryCategoryPicker") }
        stop("07-entry-04-more-categories-bottom") { for _ in 0..<8 { try drag(element("entryCategoryPicker")) } }
        stop("07-entry-05-date-calendar") { try close("entryMoreCancel"); try longPress(element("entryDate_today")); try require("entryCalendar") }
        stop("07-entry-06-future-date") { try calendarDay(Calendar.current.date(byAdding: .day, value: 2, to: Date())!); try tap("entryDateDone"); try require("entryDate_other") }
        stop("07-entry-07-account-menu") { try tap("entryAccountChip"); try wait({ self.app.buttons.matching(NSPredicate(format: "label CONTAINS '余额'")).count > 0 }, "Account menu") }
        stop("07-entry-08-purpose-keyboard") { try launch(); try tap("addEntry"); try type(longName + latinName, into: "entryPurpose"); try requireKeyboard() }
        stop("07-entry-09-income") { try launch(); try tap("addEntry"); try tap("entryNature_income"); try keys("1234567.89"); try require("entryIntoFixedSavings") }
        stop("07-entry-10-transfer") { try launch(); try tap("addEntry"); try tap("entryNature_transfer"); try require("transferDestinationAccount") }
        stop("07-entry-11-big-purchase-hint") { try launch("v45-home"); try tap("addEntry"); try keys("1200"); try require("bigPurchaseDays") }
        stop("07-entry-12-big-from-reserve") { try tap("bigFromReserve"); try require("entrySavingHint") }
        stop("07-entry-13-discard-confirmation") { try close(); try wait({ self.app.buttons["放弃这笔"].exists }, "Discard confirmation") }
        stop("07-entry-14-saved-in-sheet") { try launch(); try tap("addEntry"); try tap("entryDate_yesterday"); try keys("0.01"); try type("合成一分钱\n", into: "entryPurpose"); try tap("entryCategory_餐饮"); try tap("saveQuickEntry"); try require("entryAddedList") }
        stop("07-entry-15-saved-toast") { try launch(); try tap("addEntry"); try keys("0.01"); try type("合成一分钱\n", into: "entryPurpose"); try tap("entryCategory_餐饮"); try tap("saveQuickEntry"); try toast() }
        stop("07-entry-16-quick-repeat-menu") { try launch(); try longPress(element("addEntry")); try require("quickRepeatMenu") }
        stop("07-entry-17-long-repeat-toast") { try tap("quickRepeat_0"); try toast(); try wait({ self.element("toastMessage").label.contains(self.longName) }, "Long receipt text") }
        stop("07-entry-18-undone-receipt") { try tap("undoLastChange"); try require("toastMessage") }
        stop("07-entry-19-delete-toast") { try launch(); try detail(); try tap("deleteEntryDetail"); try toast() }
        stop("07-entry-20-short-repeat-toast") { try launch("v45-repeats"); try longPress(element("addEntry")); try tap("quickRepeat_0"); try toast() }
        stop("07-entry-21-long-saved-toast") { try launch(); try tap("addEntry"); try keys("1234567.89"); try type(longName + "\n", into: "entryPurpose"); try tap("entryCategory_餐饮"); try tap("entryAccountChip"); try tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", latinName + " · 余额")).firstMatch); try tap("saveQuickEntry"); try toast() }
        stop("07-entry-22-income-toast") { try launch(); try tap("addEntry"); try tap("entryNature_income"); try keys("0.01"); try tap("saveQuickEntry"); try toast() }
        stop("07-entry-23-transfer-toast") { try launch(); try tap("addEntry"); try tap("entryNature_transfer"); try keys("0.01"); try tap("saveQuickEntry"); try toast() }
        stop("07-entry-24-calendar-future-selected") { try launch(); try tap("addEntry"); try longPress(element("entryDate_today")); try calendarDay(Calendar.current.date(byAdding: .day, value: 2, to: Date())!); try require("entryCalendar") }
    }

    private func categories() {
        stop("08-categories-01-list") { try launch(); try settings("openCategories"); try require("categoriesDirection") }
        stop("08-categories-02-list-bottom") { for _ in 0..<10 { try drag(app.scrollViews.firstMatch) } }
        stop("08-categories-03-add-sheet") { try tap("addMainCategory"); try require("newCategoryName") }
        stop("08-categories-04-add-keyboard") { try tap("newCategoryName"); try requireKeyboard() }
        stop("08-categories-05-add-long-name") { try type(longName + latinName, into: "newCategoryName"); try requireKeyboard() }
        stop("08-categories-06-new-category-toast") { try tap("saveNewCategory"); try require("categoryName"); try toast() }
        stop("08-categories-07-detail") { try launch(); try settings("openCategories"); try tap("manageCategory_餐饮"); try require("categoryName") }
        stop("08-categories-08-subcategory") { try tap("editSubcategory_咖啡饮品"); try require("subcategoryName") }
        stop("08-categories-09-add-subcategory") { try close(); try tap("addSubcategory"); try require("newCategoryName") }
        stop("08-categories-10-merge-sheet") { try launch(); try settings("openCategories"); try tap("manageCategory_餐饮"); try tap("mergeCategory"); try require("confirmCategoryMerge") }
        stop("08-categories-11-hidden") { try launch(); try settings("openCategories"); try tap("hiddenCategories"); try require("unhideCategory_合成自建分类17") }
        stop("08-categories-12-sort") { try launch(); try settings("openCategories"); try tap("sortCategories"); try require("categoryOrderPreview") }
        stop("08-categories-13-income") { try launch(); try settings("openCategories"); try tap("categoriesDirection_income") }
    }

    private func yubai() {
        stop("09-yubai-01-tab") { try launch(); try root("yubai"); try require("openProfile") }
        stop("09-yubai-02-profile") { try tap("openProfile"); try require("profilePage") }
        stop("09-yubai-03-profile-bottom") { try reveal(element("addPrinciple")) }
        stop("09-yubai-04-add-principle-keyboard") { try tap("addPrinciple"); try require("principleText"); try requireKeyboard() }
        stop("09-yubai-05-add-principle-long") { try type(latinName + longName, into: "principleText") }
        stop("09-yubai-06-principle-toast") { try tap("savePrinciple"); try toast() }
        stop("09-yubai-07-memories") { try launch(); try root("yubai"); try tap("openMemories"); try require("memoriesPage") }
        stop("09-yubai-08-memory-editor") { try tap("memory_" + galleryID(460)); try require("memoryText") }
        stop("09-yubai-09-memory-delete-toast") { try tap("deleteMemory"); try toast() }
        stop("09-yubai-10-ask-conversation") { try launch("v45-ask"); try ask("咖啡共花了多少钱？"); try require("askAnswer", timeout: 15) }
        stop("09-yubai-11-ask-evidence") { try tap("answerEvidence"); try wait({ self.app.navigationBars["依据"].exists || self.buttonPrefix("evidenceEntry_").exists }, "Answer evidence page") }
        stop("09-yubai-12-ask-disabled") { try launch(); try detail(); try tap("entryDetailAsk"); try require("askPage"); try require("enableAskAI") }
        stop("09-yubai-13-recent-question") { try launch("v45-ask"); try ask("咖啡共花了多少钱？"); try require("askAnswer", timeout: 15); try root("yubai"); try require("recentQuestion_0") }
        stop("09-yubai-14-profile-conversation") { try launch("profile-revisit"); try root("yubai"); try tap("openProfile"); try tap("profileChatEntry"); try require("profileInput") }
        stop("09-yubai-15-purchase-questions") { try launch("judge-ask"); try ask("想买双徒步鞋 899，该不该买？"); try require("purchaseQuestions", timeout: 15) }
        stop("09-yubai-16-purchase-verdict") { try tap(app.buttons["直接给结论"]); try require("purchaseVerdict", timeout: 15) }
        stop("09-yubai-17-purchase-details") { try tap("answerEvidence"); try wait({ self.app.navigationBars["明细"].exists }, "Purchase details") }
        stop("09-yubai-18-ask-record-draft") { try launch(); try settings("openIntelligencePrivacy"); try tap("cloudAIToggle"); try ask("记一笔：合成午饭 28 元，合成地铁 8 元"); try require("multiEntryDraftCard", timeout: 15) }
        stop("09-yubai-19-ask-record-edit") { try tap(buttonPrefix("editDraft_")); try require("editEntryAmount") }
        stop("09-yubai-20-ask-record-confirm") { try close(); try tap("confirmDraftAmounts"); try require("saveDraftEntries") }
        stop("09-yubai-21-ask-record-saved") { try tap("saveDraftEntries"); try require("draftEntriesSaved"); try toast() }
        stop("09-yubai-22-profile-area-editor") { try launch(); try root("yubai"); try tap("openProfile"); try tap("profileArea_" + galleryID(451)); try require("profileAreaTitle") }
    }

    private func settingsPages() {
        stop("10-settings-01-settings") { try launch(); try settings() }
        stop("10-settings-02-frequent-entries") { try tap("openQuickCapture"); try require("frequentEntriesPage") }
        stop("10-settings-03-frequent-hidden") { try reveal(buttonPrefix("frequentUnhide_")) }
        stop("10-settings-04-quick-capture") { try tap("openQuickCaptureSettings"); try require("addCaptureShortcut") }
        stop("10-settings-05-card-mappings") { try tap("openCaptureCardRules"); try require("captureRulesPage") }
        stop("10-settings-06-intelligence-privacy-top") { try launch(); try settings("openIntelligencePrivacy"); try require("intelligencePrivacyPage") }
        stop("10-settings-07-intelligence-privacy-bottom") { for _ in 0..<6 { try drag(element("intelligencePrivacyPage")) } }
        stop("10-settings-08-cloud-key") { try launch(); try settings("openIntelligencePrivacy"); try tap("openCloudKey"); try require("cloudKeyPage") }
        stop("10-settings-09-model-menu") { try launch(); try settings("openIntelligencePrivacy"); try tap("editCloudModel"); try require("customCloudModel") }
        stop("10-settings-10-custom-model") { try tap("customCloudModel"); try require("cloudModelName") }
        stop("10-settings-11-send-log") { try launch(); try settings("openIntelligencePrivacy"); try tap("openCloudSendLog"); try require("cloudSendSummary") }
        stop("10-settings-12-backup") { try launch(); try settings("openBackup"); try require("backupPage") }
        stop("10-settings-13-recently-deleted") { try tap("recentlyDeleted"); try require("recentlyDeletedList") }
        stop("10-settings-14-delete-permanently-dialog") { try tap("clearRecentlyDeleted"); try wait({ self.app.buttons.matching(NSPredicate(format: "label == '全部清掉'")).count > 0 }, "Clear recently deleted dialog") }
        stop("10-settings-15-recovery-versions") { try launch(); try settings("openBackup"); try tap("openRecoveryVersions"); try wait({ self.app.navigationBars["恢复版本"].exists }, "Recovery versions") }
        stop("10-settings-16-storage") { try launch(); try settings("openStorage"); try require("storageHeadline") }
        stop("10-settings-17-delete-photos-sheet") { try tap("openStoragePhotos"); try require("storageOriginalsPreserved") }
        stop("10-settings-18-erase-confirmation-sheet") { try launch(); try settings("openStorage"); try tap("openStorageErase"); try require("storageEraseConfirmation") }
        stop("10-settings-19-erase-keyboard") { try type("抹掉", into: "storageEraseConfirmation"); try requireKeyboard() }
        stop("10-settings-20-card-mapping-editor") { try launch(); try settings("openQuickCapture"); try tap("openQuickCaptureSettings"); try tap("openCaptureCardRules"); try tap("addCaptureRule"); try require("captureRuleName") }
        stop("10-settings-21-merchant-mappings") { try launch(); try settings("openQuickCapture"); try tap("openQuickCaptureSettings"); try tap("openCaptureMerchantRules"); try require("captureRulesPage") }
        stop("10-settings-22-merchant-mapping-editor") { try tap("addCaptureRule"); try require("captureRuleName") }
        stop("10-settings-23-backup-password-keyboard") { try launch(); try settings("openBackup"); try tap("backupToFile"); try type("GalleryOnly123", into: "backupPassword"); try requireKeyboard() }
        stop("10-settings-24-backup-restore-picker") { try launch(); try settings("openBackup"); try tap("restoreFromBackup"); try wait({ self.app.buttons["取消"].exists }, "Restore file picker") }
        stop("10-settings-25-recovery-confirmation") { try launch(); try settings("openBackup"); try tap("openRecoveryVersions"); try tap(buttonPrefix("recoveryVersion_")); try wait({ self.app.buttons["恢复所选版本"].exists }, "Restore version dialog") }
        stop("10-settings-26-clear-history-dialog") { try launch(); try settings("openStorage"); try tap("clearStorageHistory"); try wait({ self.app.buttons.matching(NSPredicate(format: "label CONTAINS '份恢复历史'")).count > 0 }, "Clear history dialog") }
    }

    private func importsAndReceipt() {
        stop("11-import-01-picker") { try launch(); try tap("addEntry"); try tap("importFromEntry"); try require("chooseBillFile") }
        stop("11-import-02-system-file-picker") { try tap("chooseBillFile"); try wait({ self.app.buttons["取消"].exists || self.app.navigationBars["浏览"].exists }, "System document picker") }
        stop("11-import-03-history") { try launch(); try settings("openImportHistory"); try require("importHistoryPage") }
        stop("11-import-04-result-unclassified-and-plans") { try tap("openImportBatch_" + galleryID(500)); try require("importResultPage"); try require("importResultUnclassified"); try require("importRecognizedPlans") }
        stop("11-import-05-recognized-plans-detail") { try tap("reviewRecognizedImportPlans"); try wait({ self.app.navigationBars["从流水里认出来的"].exists }, "Recognized plan evidence") }
        stop("11-import-06-triage") { try back(); try tap("importResultUnclassified"); try require("letterTriage") }
        stop("11-import-07-triage-source") { try tap("sortSourceToggle"); try require("letterTriage") }
        stop("11-import-08-history-undo-dialog") { try launch(); try settings("openImportHistory"); try tap("undoImportBatch"); try wait({ self.app.buttons["撤销这一批"].exists }, "Undo batch dialog") }
        stop("11-import-09-batch-undone-toast") { try tap(app.buttons["撤销这一批"]); try require("toastMessage") }
        stop("11-import-10-receipt-separate") { try launch("v45-receipt"); try longPress(element("addEntry")); try tap("quickReceipt"); try require("receiptSummary", timeout: 15) }
        stop("11-import-11-receipt-merged") { try tap("receiptSelect_2"); try tap("receiptMode_merged"); try wait({ self.element("saveReceiptEntries").value as? String == "1 笔" }, "Merged receipt preparation") }
        stop("11-import-12-receipt-category") { try tap("receiptCategory_0"); try require("receiptPickCategory_0Category_餐饮") }
        stop("11-import-13-fallback-groups") { try launch("salary", organization: "by-party"); try tap("openLetterInbox"); try tap("organizeImports"); try require("groupUnsortedByParty", timeout: 20); try tap("groupUnsortedByParty"); try require("unsortedGroupsScroll") }
        stop("11-import-14-fallback-group-detail") { try tap("unsortedGroup_out:合成对方甲"); try require("unsortedGroupScroll") }
        stop("11-import-15-unsorted-undo-bar") { try launch("salary", organization: "by-party"); try tap("openLetterInbox"); try tap("organizeImports"); try require("groupUnsortedByParty", timeout: 20); try tap("groupUnsortedByParty"); try tap("unsortedGroup_out:合成对方甲"); try tap("unsortedCategory_餐饮"); try tap("unsortedMainOnly_餐饮"); try tap("applyUnsortedGroup"); try require("unsortedUndoMessage"); try require("quickSortUndo") }
        stop("11-import-16-preview") { try launch("import", statement: galleryStatement); try tap("addEntry"); try tap("importFromEntry"); try require("commitImport", timeout: 20) }
        stop("11-import-17-preview-category-mapping") { try tap("importCategoryMapping"); try require("createImportCategory_合成导入分类" + longName) }
    }

    private func specificStates() {
        stop("12-states-01-payday-card") { try launch("v45-payday"); try require("paydayArrived") }
        stop("12-states-02-payday-sheet") { try tap("paydayArrived"); try require("amountSheetAmount") }
        stop("12-states-03-payday-extra-to-savings") { try keys("8210"); try require("paydayExtraToSavings"); try tap("paydayExtraToSavings") }
        stop("12-states-04-payday-toast") { try tap("amountSheetDone"); try toast() }
        stop("12-states-05-late-salary") { try launch("v45-late"); try require("paydayArrived") }
        stop("12-states-06-new-cycle-leftover") { try launch("v45-newcycle"); try require("leftoverSave") }
        stop("12-states-07-leftover-saved") { try tap("leftoverSave"); try require("fundsFormula") }
        stop("12-states-08-overspend") { try launch("v45-over"); try require("coverSaveLess") }
        stop("12-states-09-cover-save-less") { try tap("coverSaveLess"); try require("coverLevel") }
        stop("12-states-10-cover-level") { try tap("coverLevel"); try require("amountSheetAmount") }
        stop("12-states-11-cover-toast") { try tap("amountSheetDone"); try toast() }
        stop("12-states-12-cover-reserve-cushion") { try launch("v45-over"); try tap("coverFromReserve"); try tap("coverCushion"); try require("amountSheetAmount") }
        stop("12-states-13-cover-reserve-toast") { try tap("amountSheetDone"); try toast() }
        stop("12-states-14-fast-spending") { try launch("v45-fast"); try require("paceChart") }
        stop("12-states-15-reconcile-gap") { try launch("v45-gap"); try tap("openReconcile"); try require("reconcileSheet") }
        stop("12-states-16-reconcile-keyboard") { try tap("reconcileField_合成银行卡"); try requireKeyboard() }
        stop("12-states-17-payday-setup") { try launch("v45-new"); try tap("setupItem_payday"); try require("paydaySetupSheet") }
        stop("12-states-18-payday-setup-amount") { try tap("paydaySetupAmount"); try require("amountSheetAmount") }
        stop("12-states-19-salary-candidate") { try launch("salary"); try tap("openLetterInbox"); try require("confirmSalary") }
        stop("12-states-20-salary-confirmed-toast") { try tap("confirmSalary"); try toast() }
        stop("12-states-21-locked") { try launch("gallery-locked"); try require("lockedPage") }
        stop("12-states-22-bill-due-card") { try launch("v45-bill"); try require("billDuePaid") }
        stop("12-states-23-new-ledger-setup") { try launch("v45-new"); try require("setupItem_payday") }
        stop("12-states-24-reconcile-difference") {
            try launch("v45-gap"); try tap("openReconcile")
            let field = element("reconcileField_合成银行卡"); try tap(field)
            let old = field.value as? String ?? ""
            guard let amount = Double(old.replacingOccurrences(of: ",", with: "")) else { throw Miss(description: "Reconcile amount is not numeric: " + old) }
            field.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.5)).tap()
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count) + String(format: "%.2f", amount - 412))
            try wait({ self.element("reconcileResult").exists && self.element("reconcileResult").label.contains("412.00") }, "Expected reconciliation difference 412.00")
        }
        stop("12-states-25-reconcile-toast") { try tap("reconcileApply"); try toast() }
    }

    private func emptyAndWelcome() {
        stop("13-empty-01-now") { try launch("gallery-empty"); try require("addFirstAccount") }
        stop("13-empty-02-saving") { try root("saving"); try require("savingTabScroll") }
        stop("13-empty-03-ledger") { try root("ledger"); try require("emptyLedgerAdd") }
        stop("13-empty-04-where") { try tap("ledgerMode_where"); try require("whereTotal") }
        stop("13-empty-05-yubai") { try root("yubai"); try require("openProfile") }
        stop("13-empty-06-wishlist") { try root("saving"); try tap("openWishlist"); try require("wishlistPage") }
        stop("13-empty-07-memories") { try root("yubai"); try tap("openMemories"); try require("emptyMemories") }
        stop("13-empty-08-import-history") { try launch("gallery-empty"); try settings("openImportHistory"); try require("emptyImportHistory") }
        stop("13-empty-09-accounts") { try launch("gallery-empty"); try tap("addFirstAccount"); try require("accountName") }
        stop("13-empty-10-welcome") { try launch("empty"); try require("welcomeBalanceCard") }
        stop("13-empty-11-onboarding-account-keyboard") { try tap("welcomeOtherAccount"); try type(longName, into: "accountName"); try requireKeyboard() }
        stop("13-empty-12-onboarding-privacy") { try launch("empty"); try tap("welcomeCloudAI"); try require("intelligencePrivacyPage") }
        stop("13-empty-13-fixed-bills") { try launch("manual"); try formula(); try tap("formulaRow_bills"); try require("fixedFlowsScroll") }
        stop("13-empty-14-frequent-entries") { try launch("gallery-empty"); try settings("openQuickCapture"); try require("frequentEntriesPage") }
        stop("13-empty-15-budget") { try launch("manual"); try formula(); try tap("openSpendingParts"); try require("budgetTotal") }
    }

    private func requireKeyboard() throws {
        try wait({ self.app.keyboards.firstMatch.exists }, "Expected keyboard is absent")
    }
    private func ask(_ text: String) throws {
        try root("yubai"); try type(text, into: "askYubai"); try tap("sendAskHome"); try require("askInput")
    }

    func testAccessibilityWalk() { prefix = "80-a11y-"; reduced(large: true, dark: false) }
    func testDarkWalk() { prefix = "90-dark-"; reduced(large: false, dark: true) }

    /// YubaiColor.adaptive + the appearance setting support dark mode; neither is forced light.
    private func reduced(large: Bool, dark: Bool) {
        stop("01-now") { try launch(dark: dark, large: large); try require("fundsFormula") }
        stop("02-saving") { try root("saving"); try require("savingTabScroll") }
        stop("03-ledger") { try root("ledger"); try require("entriesScroll") }
        stop("04-where") { try tap("ledgerMode_where"); try require("whereTotal") }
        stop("05-cash-chart") { try reveal(element("cashTimelineChart")) }
        stop("06-yubai") { try root("yubai"); try require("openProfile") }
        stop("07-profile") { try tap("openProfile"); try require("profilePage") }
        stop("08-principle-keyboard") { try tap("addPrinciple"); try requireKeyboard() }
        stop("09-principle-long") { try type(longName + latinName, into: "principleText") }
        stop("10-toast") { try tap("savePrinciple"); try toast() }
        stop("11-formula") { try formula(); try require("formulaPage") }
        stop("12-accounts") { try tap("formulaRow_hand"); try require("accountsPage") }
        stop("13-account-editor") { try tap("accountRow_" + longName); try tap("editAccount"); try require("accountName") }
        stop("14-settings") { try settings(); try require("settingsScroll") }
        stop("15-categories") { try tap("openCategories"); try require("categoriesDirection") }
        stop("16-category-keyboard") { try tap("addMainCategory"); try tap("newCategoryName"); try requireKeyboard() }
        stop("17-category-long") { try type(longName + latinName, into: "newCategoryName") }
        stop("18-entry-expense") { try launch(dark: dark, large: large); try tap("addEntry"); try require("entryKeypadAmount") }
        stop("19-entry-keyboard") { try type(longName + latinName, into: "entryPurpose"); try requireKeyboard() }
        stop("20-entry-income") { try launch(dark: dark, large: large); try tap("addEntry"); try tap("entryNature_income"); try keys("1234567.89"); try require("entryIntoFixedSavings") }
        stop("21-entry-transfer") { try tap("entryNature_transfer"); try require("transferDestinationAccount") }
        stop("22-long-repeat-toast") { try launch(dark: dark, large: large); try longPress(element("addEntry")); try tap("quickRepeat_0"); try toast() }
    }
}
