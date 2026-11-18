import XCTest

/// Independent acceptance walk (test branch only, never merged).
/// Never asserts: every miss, crash and timing goes into a text attachment, every
/// screen into a screenshot plus a compact accessibility dump.
final class AcceptanceWalker {
    let app = XCUIApplication()
    unowned let testCase: YubaiUITestCase
    let tag: String
    let ledger: String
    private var number = 0
    private(set) var log: [String] = []
    let started = Date()
    var deadline: Date

    init(_ testCase: YubaiUITestCase, tag: String, script: String, minutes: Double = 24,
         environment: [String: String] = [:], arguments: [String] = []) {
        self.testCase = testCase; self.tag = tag
        ledger = UUID().uuidString
        deadline = Date().addingTimeInterval(minutes * 60)
        app.launchArguments = ["--test-ledger", ledger, "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"] + arguments
        app.launchEnvironment["YUBAI_UI_TEST_SCRIPT"] = script
        app.launchEnvironment["YUBAI_UI_TEST_CONFIGURED_KEY"] = "0"
        app.launchEnvironment["DEEPSEEK_API_KEY"] = ""
        for (key, value) in environment { app.launchEnvironment[key] = value }
        testCase.continueAfterFailure = true
    }

    var timeLeft: Bool { Date() < deadline }
    func note(_ text: String) {
        let line = String(format: "[%6.1fs] ", Date().timeIntervalSince(started)) + text
        log.append(line); print("ACCEPT \(tag) " + line)
    }

    func launch() {
        let begin = Date()
        _ = testCase.launchApp(app, timeout: 30)
        note("launch \(String(format: "%.1f", Date().timeIntervalSince(begin)))s state=\(app.state.rawValue)")
        settle(2)
    }
    func relaunch(_ why: String) {
        note("RELAUNCH (\(why))")
        app.terminate(); launch()
    }

    func settle(_ seconds: TimeInterval = 1.2) { Thread.sleep(forTimeInterval: seconds) }

    // MARK: Capture

    func shot(_ name: String, dump: Bool = true) {
        alive("before shot \(name)")
        number += 1
        let label = "\(tag)-\(String(format: "%03d", number))-\(name)"
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = label; attachment.lifetime = .keepAlways
        testCase.add(attachment)
        if dump {
            let text = XCTAttachment(string: axDump())
            text.name = label + "-ax"; text.lifetime = .keepAlways
            testCase.add(text)
        }
    }

    func finish() {
        note("finished in \(Int(Date().timeIntervalSince(started)))s")
        let attachment = XCTAttachment(string: log.joined(separator: "\n"))
        attachment.name = "\(tag)-zz-log"; attachment.lifetime = .keepAlways
        testCase.add(attachment)
        app.terminate()
    }

    private func snapshotRoot() -> XCUIElementSnapshot? { try? app.snapshot() }

    func axDump() -> String {
        guard let root = snapshotRoot() else { return "<no snapshot>" }
        let screen = root.frame
        var lines: [String] = []
        func walk(_ node: XCUIElementSnapshot, depth: Int) {
            let f = node.frame
            let visible = f.intersects(screen) && f.width > 0 && f.height > 0
            let id = node.identifier, label = node.label
            let value = (node.value as? String) ?? ""
            if visible && (!id.isEmpty || !label.isEmpty || !value.isEmpty) && node.elementType != .other || (visible && node.elementType == .other && !id.isEmpty) {
                lines.append("\(typeName(node.elementType)) id=\(id) label=\(label.prefix(160)) value=\(value.prefix(80)) frame=\(Int(f.minX)),\(Int(f.minY)),\(Int(f.width))x\(Int(f.height))\(node.isEnabled ? "" : " DISABLED")\(node.isSelected ? " SELECTED" : "")")
            }
            if lines.count < 900 { for child in node.children { walk(child, depth: depth + 1) } }
        }
        walk(root, depth: 0)
        return lines.joined(separator: "\n")
    }

    private func typeName(_ type: XCUIElement.ElementType) -> String {
        switch type {
        case .button: "button"; case .staticText: "text"; case .textField: "field"; case .textView: "textview"
        case .switch: "switch"; case .image: "image"; case .cell: "cell"; case .scrollView: "scroll"; case .collectionView: "collection"
        case .navigationBar: "navbar"; case .alert: "alert"; case .sheet: "sheet"; case .slider: "slider"; case .picker: "picker"
        case .pickerWheel: "wheel"; case .segmentedControl: "segmented"; case .link: "link"; case .other: "other"; case .keyboard: "keyboard"
        case .searchField: "search"; case .menuItem: "menuitem"
        default: "t\(type.rawValue)"
        }
    }

    // MARK: Liveness

    @discardableResult func alive(_ context: String) -> Bool {
        if app.state == .runningForeground { return true }
        note("APP NOT RUNNING (\(context)) state=\(app.state.rawValue) — possible crash")
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "\(tag)-CRASH-\(number)"; attachment.lifetime = .keepAlways; testCase.add(attachment)
        launch()
        return false
    }

    // MARK: Elements

    func element(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
    func button(label: String) -> XCUIElement { app.buttons.matching(NSPredicate(format: "label == %@", label)).firstMatch }

    func onScreen(_ e: XCUIElement) -> Bool {
        guard e.exists else { return false }
        let f = e.frame, w = app.frame
        return f.width > 1 && f.height > 1 && f.minY >= w.minY - 1 && f.maxY <= w.maxY + 1 && f.minX < w.maxX && f.maxX > w.minX
    }

    @discardableResult func waitFor(_ id: String, _ timeout: TimeInterval = 5) -> Bool {
        element(id).waitForExistence(timeout: timeout)
    }

    /// Tap by identifier; scroll down to find it if needed. Records a miss and returns false.
    @discardableResult func tap(_ id: String, timeout: TimeInterval = 4, scrolls: Int = 6, settle seconds: TimeInterval = 1.2) -> Bool {
        let e = element(id)
        return tapElement(e, name: id, timeout: timeout, scrolls: scrolls, settle: seconds)
    }
    @discardableResult func tap(label: String, timeout: TimeInterval = 3, scrolls: Int = 0, settle seconds: TimeInterval = 1.2) -> Bool {
        tapElement(button(label: label), name: "label:" + label, timeout: timeout, scrolls: scrolls, settle: seconds)
    }
    @discardableResult func tapElement(_ e: XCUIElement, name: String, timeout: TimeInterval = 4, scrolls: Int = 6, settle seconds: TimeInterval = 1.2) -> Bool {
        alive("before tap \(name)")
        guard e.waitForExistence(timeout: timeout) else { note("MISS \(name) (not found)"); return false }
        var attempts = 0
        while !(onScreen(e) && e.isHittable) && attempts < scrolls {
            if e.frame.minY > app.frame.midY || e.frame.minY >= app.frame.maxY { drag(up: true) } else { drag(up: false) }
            attempts += 1
        }
        if e.isHittable { e.tap() }
        else if onScreen(e) {
            note("WARN \(name) not hittable, tapping its centre")
            e.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        } else { note("MISS \(name) (off screen after \(attempts) scrolls) frame=\(e.frame)"); return false }
        settle(seconds)
        return true
    }

    func type(_ text: String, into id: String) {
        let field = element(id)
        guard tapElement(field, name: id, settle: 0.8) else { return }
        field.typeText(text)
        settle(0.5)
    }

    func keys(_ text: String) {
        for character in text {
            let key = element("keypad_" + String(character))
            if key.exists && key.isHittable { key.tap() } else { note("MISS keypad_\(character)") }
        }
        settle(0.6)
    }

    // MARK: Scrolling

    func drag(up: Bool, fraction: CGFloat = 0.42) {
        let top: CGFloat = 0.30, bottom = top + fraction
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? bottom : top))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? top : bottom))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.15)
        settle(0.8)
    }

    /// Screenshot, scroll, screenshot ... until the visible tree stops changing.
    func scrollShots(_ name: String, max pages: Int = 8) {
        shot(name + "-p1")
        var previous = axDump()
        for page in 2...max(2, pages) {
            guard timeLeft else { return }
            drag(up: true)
            let now = axDump()
            if now == previous { break }
            shot(name + "-p\(page)", dump: false)
            let text = XCTAttachment(string: now); text.name = "\(tag)-\(String(format: "%03d", number))-\(name)-p\(page)-ax"; text.lifetime = .keepAlways
            testCase.add(text)
            previous = now
        }
        for _ in 0..<pages { drag(up: false, fraction: 0.5); if !timeLeft { break } }
    }

    // MARK: Navigation

    private let dismissIDs = ["closeImportResult", "closeSheet", "cancelManualSheet", "amountSheetCancel", "entriesSearchCancel", "BackButton"]
    var atRoot: Bool {
        let nav = app.otherElements["mainNavigation"]
        return nav.exists && nav.isHittable
    }

    /// One step back: alert, keyboard, known close ids, nav back, sheet swipe.
    func back() {
        alive("back")
        if app.alerts.firstMatch.exists {
            let alert = app.alerts.firstMatch
            let cancel = alert.buttons.matching(NSPredicate(format: "label IN %@", ["取消", "Cancel", "好", "OK", "知道了"])).firstMatch
            (cancel.exists ? cancel : alert.buttons.firstMatch).tap(); settle(); return
        }
        let sheetCancel = app.sheets.firstMatch
        if sheetCancel.exists {
            let cancel = sheetCancel.buttons.matching(NSPredicate(format: "label IN %@", ["取消", "Cancel"])).firstMatch
            if cancel.exists { cancel.tap(); settle(); return }
        }
        if app.keyboards.firstMatch.exists {
            let done = app.toolbars.buttons.matching(NSPredicate(format: "label IN %@", ["完成", "Done"])).firstMatch
            if done.exists && done.isHittable { done.tap(); settle(0.6) }
        }
        for id in dismissIDs {
            let e = element(id)
            if e.exists && e.isHittable { e.tap(); settle(); return }
        }
        let bar = app.navigationBars.buttons.firstMatch
        if bar.exists && bar.isHittable { bar.tap(); settle(); return }
        for label in ["取消", "关闭", "完成", "返回"] {
            let e = button(label: label)
            if e.exists && e.isHittable { e.tap(); settle(); return }
        }
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12))
        start.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)), withVelocity: .fast, thenHoldForDuration: 0.05)
        settle()
    }

    func home() {
        for _ in 0..<6 { if atRoot { return }; back() }
        if !atRoot { relaunch("could not return to the root") }
    }

    func root(_ tab: String) {
        home()
        tap("tab_" + tab, scrolls: 0)
    }

    // MARK: Crawling

    private let skipWords = ["删除", "删掉", "撤销", "清空", "恢复", "还原", "退出", "停止", "重置", "移除", "合并", "隐藏", "导出", "备份", "分享",
                             "delete", "Delete", "undo", "Undo", "clear", "Clear", "restore", "Restore", "stop", "Stop", "merge", "Merge",
                             "hide", "Hide", "export", "Export", "backup", "Backup", "choose", "Choose", "Photo", "Receipt", "File", "tab_", "keypad_",
                             "BackButton", "closeSheet", "cancelManualSheet", "closeImportResult", "返回", "取消", "关闭", "Cancel", "toggleAmountVisibility",
                             "commitImport", "skipImport", "reconcileApply", "confirm", "Confirm"]

    /// Buttons visible on this screen, as (key, description).
    func visibleButtons() -> [(String, String)] {
        guard let root = snapshotRoot() else { return [] }
        let screen = root.frame
        var found: [(String, String)] = [], seen = Set<String>()
        func walk(_ node: XCUIElementSnapshot) {
            if node.elementType == .button || node.elementType == .cell {
                let f = node.frame
                if f.minY >= screen.minY && f.maxY <= screen.maxY && f.width > 4 && f.height > 4 && node.isEnabled {
                    let key = node.identifier.isEmpty ? "label:" + node.label : node.identifier
                    let all = node.identifier + " " + node.label
                    if !node.label.isEmpty || !node.identifier.isEmpty, !skipWords.contains(where: { all.contains($0) }), seen.insert(key).inserted {
                        found.append((key, node.label))
                    }
                }
            }
            for child in node.children { walk(child) }
        }
        walk(root)
        return found
    }

    /// Depth-1 crawl: for each visible button of the screen that `reach` opens,
    /// tap it, capture, return. `reach` must bring back the same screen.
    func crawl(_ name: String, limit: Int = 30, reach: () -> Void) {
        reach()
        let buttons = Array(visibleButtons().prefix(limit))
        note("CRAWL \(name): \(buttons.count) buttons: " + buttons.map { $0.0 }.joined(separator: ", "))
        for (index, item) in buttons.enumerated() {
            let (key, label) = item
            guard timeLeft else { note("CRAWL \(name) stopped at deadline"); return }
            if index > 0 { reach() }
            let target = key.hasPrefix("label:") ? button(label: String(key.dropFirst(6))) : element(key)
            guard tapElement(target, name: key, timeout: 3, scrolls: 0, settle: 1.5) else { continue }
            let safe = (key.hasPrefix("label:") ? "L-" + label : key).replacingOccurrences(of: "/", with: "-").prefix(40)
            shot("\(name)-tap-\(safe)")
            home()
        }
    }

    // MARK: Year import

    /// Brand-new user: first open → 已经有账单，导进来 → preview → commit → result.
    @discardableResult func importYear(capture: Bool) -> Bool {
        if capture { shot("first-open") }
        guard tap("firstImport", timeout: 15) else { shot("first-import-missing"); return false }
        let commit = element("commitImport")
        let previewStart = Date()
        guard commit.waitForExistence(timeout: 60) else { note("MISS commitImport after 60s"); shot("import-preview-missing"); return false }
        note("import preview ready in \(String(format: "%.1f", Date().timeIntervalSince(previewStart)))s")
        if capture { settle(1.5); scrollShots("import-preview", max: 6) }
        let begin = Date()
        guard tapElement(commit, name: "commitImport", timeout: 5, scrolls: 8, settle: 0.5) else { shot("commit-missing"); return false }
        let result = element("importResultPage")
        var reported = false
        while Date().timeIntervalSince(begin) < 240 {
            if result.exists { break }
            if !alive("during import") { return false }
            if !reported && Date().timeIntervalSince(begin) > 8 && capture { shot("import-in-progress"); reported = true }
            Thread.sleep(forTimeInterval: 1)
        }
        note("import result after \(String(format: "%.1f", Date().timeIntervalSince(begin)))s exists=\(result.exists)")
        settle(2)
        if capture { scrollShots("import-result", max: 6) }
        return true
    }
}
