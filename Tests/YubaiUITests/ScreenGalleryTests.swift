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
    private var relaunch: (() throws -> Void)?

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
            let label = prefix.isEmpty ? String(name.filter { $0.isLetter || $0.isNumber }.suffix(40)) : String(prefix.dropLast())
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
            print("GALLERY-STOP ok " + name)
            return true
        } catch {
            print("GALLERY-STOP MISSING " + name + ": " + String(describing: error).replacingOccurrences(of: "\n", with: " "))
            missing.append(name + "-MISSING: " + String(describing: error).replacingOccurrences(of: "\n", with: " "))
            // Attach the current pixels and hierarchy even if a host-path write fails.
            shot(name + "-MISSING")
            let tree = app.debugDescription
            if let directory { try? tree.write(to: directory.appendingPathComponent(name + "-MISSING-hierarchy.txt"), atomically: true, encoding: .utf8) }
            let hierarchy = XCTAttachment(string: tree)
            hierarchy.name = name + "-MISSING-hierarchy"; hierarchy.lifetime = .keepAlways; add(hierarchy)
            // Start the next stop from a known screen instead of whatever the failed one left open.
            if let relaunch { try? relaunch() }
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
        relaunch = { [unowned self] in try self.launch(fixture, dark: dark, large: large, organization: organization, statement: statement) }
        app.terminate(); app = XCUIApplication()
        app.launchArguments = ["--test-ledger", UUID().uuidString, "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", large ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL"]
        app.launchEnvironment["YUBAI_UI_TEST_SCRIPT"] = fixture
        app.launchEnvironment["YUBAI_UI_TEST_CONFIGURED_KEY"] = "1"
        app.launchEnvironment["YUBAI_UI_TEST_KEEP_UNDO"] = "1"
        app.launchEnvironment["YUBAI_GALLERY_APPEARANCE"] = dark ? "dark" : "light"
        app.launchEnvironment["DEEPSEEK_API_KEY"] = ""
        if let organization { app.launchEnvironment["YUBAI_UI_ORGANIZATION_SCENARIO"] = organization }
        if let statement { app.launchEnvironment["YUBAI_UI_STATEMENT"] = Data(statement.utf8).base64EncodedString() }
        app.launch()
        try require(fixture == "gallery-locked" ? "lockedPage" : "mainNavigation", timeout: 15)
    }
    private func drag(_ scroll: XCUIElement, up: Bool = true) throws {
        // XCUITest reports some SwiftUI scroll containers as not hittable although a finger can drag them;
        // drag by screen coordinates inside the container's frame, or the window when it has none.
        let bounds = scroll.exists && !scroll.frame.isEmpty ? scroll.frame.intersection(app.frame) : app.frame.insetBy(dx: 0, dy: 110)
        var frame = bounds.insetBy(dx: 12, dy: 12)
        let navigation = element("mainNavigation"), keyboard = app.keyboards.firstMatch
        if navigation.exists && navigation.isHittable { frame.size.height = min(frame.maxY, navigation.frame.minY) - frame.minY }
        if keyboard.exists { frame.size.height = min(frame.maxY, keyboard.frame.minY) - frame.minY }
        guard frame.height > 60 else { throw Miss(description: "No visible scroll viewport") }
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let start = origin.withOffset(CGVector(dx: frame.midX - app.frame.minX, dy: frame.minY + frame.height * (up ? 0.78 : 0.22) - app.frame.minY))
        let end = origin.withOffset(CGVector(dx: frame.midX - app.frame.minX, dy: frame.minY + frame.height * (up ? 0.22 : 0.78) - app.frame.minY))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
    }
    /// On screen where a finger could press it: inside the window, not under the tab bar, and either
    /// in the fixed page header or below it.
    private func onScreen(_ target: XCUIElement) -> Bool {
        guard target.exists, !target.frame.isEmpty else { return false }
        let center = CGPoint(x: target.frame.midX, y: target.frame.midY)
        guard app.frame.insetBy(dx: 4, dy: 4).contains(center) else { return false }
        let navigation = element("mainNavigation")
        if navigation.exists, !navigation.frame.isEmpty, center.y > navigation.frame.minY - 4, !navigation.frame.contains(center) { return false }
        return true
    }
    private func pressable(_ target: XCUIElement) -> Bool { target.exists && (target.isHittable || onScreen(target)) }
    private func press(_ target: XCUIElement) {
        if target.isHittable { target.tap(); return }
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: target.frame.midX - app.frame.minX, dy: target.frame.midY - app.frame.minY)).tap()
    }
    private func reveal(_ target: XCUIElement) throws {
        _ = target.waitForExistence(timeout: 3)
        // A stop that cannot be reached must fail fast: an unbounded search costs minutes per stop on CI.
        let deadline = Date().addingTimeInterval(20)
        for _ in 0..<8 {
            if pressable(target) { return }
            if Date() > deadline { break }
            guard app.alerts.count == 0 else { break }
            let containers = app.scrollViews.allElementsBoundByIndex + app.collectionViews.allElementsBoundByIndex + app.tables.allElementsBoundByIndex
            let scrolls = containers.filter { $0.exists && $0.frame.height > 120 && $0.frame.width > app.frame.width * 0.65 }
            let containing = scrolls.last { target.exists && $0.descendants(matching: target.elementType).matching(identifier: target.identifier).count > 0 }
            let scroll = containing ?? scrolls.last ?? app
            let above = target.exists && !target.frame.isEmpty && target.frame.maxY < scroll.frame.minY + 20
            try drag(scroll, up: !above)
        }
        try wait({ self.pressable(target) }, "Not reachable: " + (target.exists ? target.identifier : target.description), timeout: 2)
    }
    private func tap(_ target: XCUIElement) throws {
        try reveal(target)
        try wait({ target.exists && target.isEnabled && self.pressable(target) }, "Control disabled: " + target.identifier)
        press(target)
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
        let check = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'billCheck_' AND label == %@", "付了 " + title)).firstMatch
        if !check.exists && element("billDueNotYet").exists { press(element("billDueNotYet")) }
        return check
    }
    private func deckAction(_ id: String) throws {
        for _ in 0..<16 {
            if element(id).exists { return }
            guard element("butlerDeckNext").exists else { break }
            try tap("butlerDeckNext")
        }
        try require(id)
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

    // One method per area: each starts from a fresh launch, so one area cannot stall the others.
    func testWalk01RootsAndLedger() { rootsAndLedger() }
    func testWalk02FormulaAndAccounts() { try? launch(); formulaAndAccounts() }
    func testWalk03Bills() { try? launch(); bills() }
    func testWalk04Saving() { try? launch(); saving() }
    func testWalk05EntrySheets() { try? launch(); entrySheets() }
    func testWalk06Categories() { try? launch(); categories() }
    func testWalk07Yubai() { try? launch(); yubai() }
    func testWalk08Settings() { try? launch(); settingsPages() }
    func testWalk09Imports() { try? launch(); importsAndReceipt() }
    func testWalk10States() { try? launch(); specificStates() }
    func testWalk11Empty() { try? launch(); emptyStates() }

    func testWalk46Batch1() { round46Batch1(dark: false, large: false) }
    func testWalk46Batch1Dark() { prefix = "46-dark-"; round46Batch1(dark: true, large: false) }
    func testWalk46Batch1Large() { prefix = "46-a11y-"; round46Batch1(dark: false, large: true) }

    private func round46Batch1(dark: Bool, large: Bool) {
        func load(_ fixture: String) throws { try launch(fixture, dark: dark, large: large) }
        stop("DS-Nav") { try load("v46-hard"); try tap("fundsFormula"); try require("formulaPage"); try audit46() }
        stop("Quick") { try load("v46-home"); try longPress(element("addEntry")); try require("quickRepeatMenu"); try require("manageQuickRepeats"); try audit46() }
        stop("Home-C") { try load("v46-home"); try require("renewalCard"); try require("openLetterInbox"); try audit46() }
        stop("Home-A") { try tap("stopRenewal"); try require("butlerReceipt"); try require("undoButlerReceipt"); try audit46() }
        stop("Home-B") { try load("v46-quiet"); try require("todayEntries"); try audit46() }
        stop("Deck") { try load("v46-deck"); try tap("openLetterInbox"); try require("butlerDeckNext"); try require("pendingImportsCard"); try audit46() }
        stop("Home-Payday") { try load("v46-leftover"); try require("leftoverSave"); try audit46() }
        stop("Payday-Amount") { try load("v46-payday"); try tap("paydayArrived"); try keys("8510"); try require("paydayExtraToSavings"); try audit46() }
        stop("First") { try load("v46-empty"); try require("firstUseCard"); try require("firstEntry"); try audit46() }
        stop("Home-Bill") { try load("v46-bill"); try require("billDuePaid"); try audit46() }
        stop("Home-Gap") { try load("v46-gap"); try require("openReconcile"); try audit46() }
        stop("Recon") {
            try tap("openReconcile"); try require("reconcileSheet")
            let field = element("reconcileField_招行储蓄卡")
            let old = field.value as? String ?? ""
            guard let amount = Double(old.replacingOccurrences(of: ",", with: "")) else { throw Miss(description: "Non-numeric reconcile input") }
            try tap(field)
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count) + String(format: "%.2f", amount - 412))
            if app.keyboards.firstMatch.exists { app.toolbars.buttons["完成"].firstMatch.tap() }
            try require("reconcileResult"); try audit46()
        }
        stop("Recon-Done") { try tap("reconcileApply"); try require("toastMessage"); try require("todayEntries"); try audit46() }
        stop("Home-Over") { try load("v46-over"); try require("coverSaveLess"); try require("coverFromReserve"); try audit46() }
        stop("Over-Cover") { try tap("coverSaveLess"); try tap("coverCushion"); try require("amountSheetAmount"); try audit46() }
        stop("Over-Done") { try tap("amountSheetDone"); try require("dailyPace"); try require("toastMessage"); try audit46() }
        stop("Home-Busy") { try load("v46-busy"); try require("importBusyRow"); try require("organizeProgress"); try audit46() }
        stop("Home-Hidden") { try load("v46-home"); try tap("toggleAmountVisibility"); try require("stopRenewal"); try audit46() }
        stop("Home-Hard") { try load("v46-hard"); try require("renewalCard"); try audit46() }
        stop("Big-Home") { try launch("v46-big", dark: dark, large: true); try require("todayEntries"); try audit46() }
        stop("Spend") { try load("v46-spend"); try tap("fundsFormula"); try require("formulaRow_income"); try require("formulaRow_spent"); try audit46() }
        stop("Saved") { try load("v46-saved"); try root("saving"); try tap("openButlerSaved"); try require("butlerSavedTotal"); try audit46() }
        // These three boards specify behavior, rather than another phone page.
        stop("Goal") { try load("v46-home"); try require("stopRenewal"); try audit46() }
        stop("Butler-Kinds") { try load("v46-deck"); try tap("openLetterInbox"); try require("butlerDeckNext"); try tap("butlerDeckNext"); try audit46() }
        stop("Words") { try load("v46-home"); try settings(); try reveal(element("butlerNoticeSettings")); try require("butlerNotice_ordinary"); try audit46() }
    }

    /// Check visible controls only: scroll content below the viewport is expected.
    /// Native keyboard keys and menus are owned by the system, not by the page.
    private func audit46() throws {
        let controls = ["addEntry", "stopRenewal", "keepRenewal", "openLetterInbox", "butlerDeckNext", "undoButlerReceipt", "firstEntry", "firstImport", "billDuePaid", "billDueNotYet", "coverSaveLess", "coverFromReserve", "reconcileApply", "amountSheetDone", "paydayArrived"]
        var visible: [(String, CGRect)] = []
        for id in controls {
            let target = element(id)
            guard target.exists, target.isHittable else { continue }
            let frame = target.frame
            guard frame.width >= 44, frame.height >= 44 else { throw Miss(description: id + " has a small hit target") }
            guard frame.minX >= app.frame.minX - 1, frame.maxX <= app.frame.maxX + 1,
                  frame.minY >= app.frame.minY, frame.maxY <= app.frame.maxY else { throw Miss(description: id + " is outside the screen") }
            for (other, bounds) in visible where bounds.intersects(frame) {
                let overlap = bounds.intersection(frame)
                if overlap.width > 2 && overlap.height > 2 { throw Miss(description: id + " overlaps " + other) }
            }
            visible.append((id, frame))
        }
        for id in ["availableFunds", "dailyPace", "butlerSavedTotal"] {
            let target = element(id)
            if target.exists, onScreen(target), target.label.contains("…") { throw Miss(description: id + " truncates money") }
        }
    }

    private func rootsAndLedger() {
        stop("01-now-01-top") { try launch(); try require("fundsFormula") }
        stop("01-now-02-middle") { try drag(element("nowScroll")) }
        stop("01-now-03-bottom") { for _ in 0..<6 { try drag(element("nowScroll")) } }
        stop("01-now-04-hidden-amounts") { try root("now"); try tap("toggleAmountVisibility"); try require("fundsFormula") }
        stop("01-now-05-todo") { try launch(); try tap("openLetterInbox"); try require("letterInbox") }
        stop("01-now-06-weekly-review") { try root("ledger"); try tap("ledgerMode_where"); try tap("openWeekly"); try require("letterBody") }
        stop("01-now-07-weekly-review-bottom") { try drag(app.scrollViews.firstMatch) }
        stop("01-now-08-hidden-ledger") { try launch(); try tap("toggleAmountVisibility"); try root("ledger"); try require("entriesScroll") }
        stop("01-now-09-hidden-saving") { try root("saving"); try require("savingTabScroll") }
        stop("01-now-10-hidden-yubai") { try root("yubai"); try require("openProfile") }
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
        stop("04-formula-02-bottom") { try reveal(element("formulaRow_daily")) }
        stop("04-formula-06-edit-reserve") { try launch(); try formula(); try tap("formulaRow_fixedSavings"); try require("amountSheetAmount") }
        stop("04-formula-07-edit-saving") { try launch(); try formula(); try tap("formulaRow_saving"); try require("amountSheetAmount") }
        stop("04-formula-08-budget") { try launch(); try settings("openSpendingParts"); try require("spendingPartsPage") }
        stop("04-formula-09-add-budget-alert") { try tap("addBudgetPart"); try wait({ self.app.alerts.firstMatch.exists }, "Add budget alert") }
        stop("04-formula-10-budget-alert-keyboard") { try tap(app.alerts.firstMatch.textFields.firstMatch); app.alerts.firstMatch.textFields.firstMatch.typeText(longName); try requireKeyboard() }
        stop("04-formula-11-budget-amount-sheet") { try launch(); try settings("openSpendingParts"); try tap("budgetAmount_合成超支分项" + longName); try require("amountSheetAmount") }
        stop("04-formula-12-budget-category-sheet") { try launch(); try settings("openSpendingParts"); try tap("budgetCategory_" + galleryID(350)); try require("categoryPickerCategory_餐饮") }
        stop("05-accounts-01-list-top") { try launch(); try formula(); try tap("formulaRow_hand"); try require("accountsPage") }
        stop("05-accounts-02-list-bottom") { try reveal(element("addAccount")) }
        stop("05-accounts-03-credit") { try tap("accountRow_信用卡"); try require("accountDetailPage") }
        stop("05-accounts-04-credit-editor") { try tap("editAccount"); try require("accountName") }
        stop("05-accounts-05-add-account") { try launch(); try formula(); try tap("formulaRow_hand"); try tap("addAccount"); try require("accountName") }
        stop("05-accounts-06-editor-long-keyboard") { try type(longName + latinName, into: "accountName"); try requireKeyboard() }
        stop("05-accounts-07-archived-account") { try launch(); try formula(); try tap("formulaRow_hand"); try tap("accountRow_已归档的旧银行卡"); try require("accountDetailPage") }
        stop("05-accounts-08-reconcile") { try launch(); try formula(); try tap("formulaRow_hand"); try tap("reconcileAll"); try require("reconcileSheet") }
        stop("05-accounts-09-reconcile-one-account") { try launch("v46-gap"); try tap("openReconcile"); try require("reconcileField_招行储蓄卡") }
    }

    private func bills() {
        stop("06-bills-01-list") { try launch(); try formula(); try tap("formulaRow_bills"); try require("fixedFlowsScroll") }
        stop("06-bills-02-list-bottom") { for _ in 0..<12 { try drag(element("fixedFlowsScroll")) } }
        stop("06-bills-03-editor") { try launch(); try formula(); try tap("formulaRow_bills"); try tap("addFixedFlow"); try require("fixedFlowTitle") }
        stop("06-bills-04-editor-schedule") { try tap("fixedFlowDate"); try require("fixedFlowCalendar") }
        stop("06-bills-05-detail") { try launch("v46-bill"); try tap("billDueNotYet"); try tap(buttonPrefix("formulaBill_")); try require("billDetailPage") }
        stop("06-bills-06-detail-history") { try reveal(element("billDetailHistory")) }
        stop("06-bills-07-long-press-menu") { try launch("v45-bill"); try longPress(bill("话费和宽带")); try require("billMenu_move") }
        stop("06-bills-08-move-occurrence") { try tap("billMenu_move"); try require("billMoveSheet") }
        stop("06-bills-09-move-future") { try calendarDay(Calendar.current.date(byAdding: .day, value: 2, to: Date())!, id: "billMoveCalendar") }
        stop("06-bills-10-move-toast") { try tap("billMoveDone"); try toast() }
        stop("06-bills-11-variable-pay") { try launch("v45-bill"); let row = bill("电费"); try reveal(row); try tap(row); try require("amountSheetAmount") }
        stop("06-bills-12-paid-toast") { try keys("163.40"); try tap("amountSheetDone"); try toast() }
        stop("06-bills-13-link-existing") { try launch("v45-bill"); try longPress(bill("话费和宽带")); try tap("billMenu_linked"); try require("billLinkSheet") }
        stop("06-bills-14-match-existing") { try launch("v45-bill-match"); let row = bill("话费和宽带"); try reveal(row); try tap(row); try require("billMatchConfirm") }
        stop("06-bills-15-skip-toast") { try launch("v45-bill"); try longPress(bill("话费和宽带")); try tap("billMenu_skip"); try toast() }
        stop("06-bills-16-stop-confirmation") { try launch("v45-bill"); try longPress(bill("话费和宽带")); try tap("billMenu_stop"); try require("fixedFlowStopConfirm") }
        stop("06-bills-17-stop-toast") { try tap("fixedFlowStopConfirm"); try toast() }
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
        stop("11-import-13-fallback-groups") { try launch("v46-sort", organization: "by-party"); try require("groupUnsortedByParty", timeout: 20); try tap("groupUnsortedByParty"); try require("unsortedGroupsScroll") }
        stop("11-import-14-fallback-group-detail") { try tap("unsortedGroup_out:合成对方甲"); try require("unsortedGroupScroll") }
        stop("11-import-15-unsorted-undo-bar") { try launch("v46-sort", organization: "by-party"); try require("groupUnsortedByParty", timeout: 20); try tap("groupUnsortedByParty"); try tap("unsortedGroup_out:合成对方甲"); try tap("unsortedCategory_餐饮"); try tap("unsortedMainOnly_餐饮"); try tap("applyUnsortedGroup"); try require("unsortedUndoMessage"); try require("quickSortUndo") }
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
        stop("12-states-15-reconcile-gap") { try launch("v45-gap"); try tap("openReconcile"); try require("reconcileSheet") }
        stop("12-states-16-reconcile-keyboard") { try tap("reconcileField_合成银行卡"); try requireKeyboard() }
        stop("12-states-19-salary-candidate") { try launch("salary"); try tap("openLetterInbox"); try deckAction("confirmSalary") }
        stop("12-states-20-salary-confirmed-toast") { try tap("confirmSalary"); try toast() }
        stop("12-states-21-locked") { try launch("gallery-locked"); try require("lockedPage") }
        stop("12-states-22-bill-due-card") { try launch("v45-bill"); try require("billDuePaid") }
        stop("12-states-23-first-entry") { try launch("v46-empty"); try tap("firstEntry"); try require("entryKeypadAmount") }
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

    private func emptyStates() {
        stop("13-empty-01-now") { try launch("gallery-empty"); try require("firstUseCard") }
        stop("13-empty-02-saving") { try root("saving"); try require("savingTabScroll") }
        stop("13-empty-03-ledger") { try root("ledger"); try require("emptyLedgerAdd") }
        stop("13-empty-04-where") { try tap("ledgerMode_where"); try require("whereTotal") }
        stop("13-empty-05-yubai") { try root("yubai"); try require("openProfile") }
        stop("13-empty-06-wishlist") { try root("saving"); try tap("openWishlist"); try require("wishlistPage") }
        stop("13-empty-07-memories") { try root("yubai"); try tap("openMemories"); try require("emptyMemories") }
        stop("13-empty-08-import-history") { try launch("gallery-empty"); try settings("openImportHistory"); try require("emptyImportHistory") }
        stop("13-empty-09-accounts") { try launch("gallery-empty"); try settings("openAccounts"); try tap("addAccount"); try require("accountName") }
        stop("13-empty-10-first-use") { try launch("empty"); try require("firstUseCard") }
        stop("13-empty-11-first-entry-keyboard") { try tap("firstEntry"); try type(longName, into: "entryPurpose"); try requireKeyboard() }
        stop("13-empty-12-privacy") { try launch("empty"); try settings("openIntelligencePrivacy"); try require("intelligencePrivacyPage") }
        stop("13-empty-13-fixed-bills") { try launch("manual"); try formula(); try tap("formulaRow_bills"); try require("fixedFlowsScroll") }
        stop("13-empty-14-frequent-entries") { try launch("gallery-empty"); try settings("openQuickCapture"); try require("frequentEntriesPage") }
        stop("13-empty-15-budget") { try launch("manual"); try settings("openSpendingParts"); try require("budgetTotal") }
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
    func testWalk46Batch4() { round46Batch4(dark: false, large: false) }
    func testWalk46Batch4Dark() { prefix = "46-dark-"; round46Batch4(dark: true, large: false) }
    func testWalk46Batch4Large() { prefix = "46-a11y-"; round46Batch4(dark: false, large: true) }

    private func round46Batch4(dark: Bool, large: Bool) {
        func load(_ fixture: String = "v46-bills") throws { try launch(fixture, dark: dark, large: large) }
        func calendar() throws { try formula(); try tap("formulaRow_bills"); try require("billsCalendar") }
        func select(_ number: Int) throws {
            let c = Calendar.current, month = c.dateInterval(of: .month, for: Date())!.start
            let last = c.range(of: .day, in: .month, for: Date())!.count
            let day = c.date(byAdding: .day, value: min(number, last) - 1, to: month)!
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "zh_CN")
            try tap("billsDay_" + f.string(from: day))
        }
        stop("Bills-Cal") { try load(); try calendar(); try require("fixedFlowRemaining"); try audit46() }
        stop("Bills-Day") { try select(28); try require("billsSelectedDay"); try reveal(element("billsRate_USD")); try audit46() }
        stop("Bill-Add-FX") {
            try load(); try calendar(); try tap("addFixedFlow")
            try type("Claude Pro", into: "fixedFlowTitle"); try type("20.00", into: "fixedFlowAmount")
            try tap("billCurrency_USD")
            if app.toolbars.buttons["完成"].firstMatch.exists { app.toolbars.buttons["完成"].firstMatch.tap() }
            try require("billEditRate"); try audit46()
        }
        stop("Home-Yearly") { try load("v46-bills-yearly"); try require("renewalCard"); try require("keepRenewal"); try audit46() }
        stop("Bill-Pay") {
            try load("v46-bills-pay"); try tap("billDuePaid"); try require("amountSheetAmount"); try keys("163.40"); try audit46()
        }
        stop("Bill-Detail") {
            try load(); try calendar(); try select(27); try tap("editFixedFlow_" + galleryID(46425)); try require("billDetailHistory"); try audit46()
        }
        stop("Bill-Menu") { try load("v46-bills-match"); try longPress(bill("话费和宽带")); try require("billMenu_move"); try audit46() }
        stop("Bill-Match") { try load("v46-bills-match"); try tap(bill("话费和宽带")); try require("billMatchConfirm"); try audit46() }
        stop("Accounts") { try load(); try settings("openAccounts"); try require("accountsTotal"); try audit46() }
        stop("46-b4-rate") { try load(); try calendar(); try select(28); try tap("billsRate_USD"); try require("billRateValue"); try audit46() }
        stop("46-b4-yearly-switch") { try load(); try calendar(); try tap("yearlyBillsStrip"); try require("yearlyBillsSetAside"); try audit46() }
        stop("46-b4-spend") { try load(); try formula(); try reveal(element("formulaRow_yearlySetAside")); try audit46() }
        stop("46-b4-hidden") { try load("v46-bills-hidden"); try calendar(); try select(28); try require("billsSelectedDay"); try audit46() }
        stop("46-b4-hard") { try load("v46-bills-hard"); try calendar(); try select(21); try require("billsSelectedDay"); try audit46() }
    }

    private func reduced(large: Bool, dark: Bool) {
        stop("01-now") { try launch(dark: dark, large: large); try require("fundsFormula") }
        stop("02-saving") { try root("saving"); try require("savingTabScroll") }
        stop("03-ledger") { try root("ledger"); try require("entriesScroll") }
        stop("04-where") { try tap("ledgerMode_where"); try require("whereTotal") }
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
