import XCTest

// Second-pass acceptance walk (test branch only). Fixes the first pass's own test
// mistakes: the bank rows go into a newly added account with a real balance instead
// of the zero-balance 现金 account, the reconcile field is opened before typing, and
// most screens skip the accessibility dump so XCTest snapshots do not add stalls.

private extension AcceptanceWalker {
    func shotsDown(_ name: String, pages: Int) {
        shot(name + "-p1", dump: false)
        guard pages > 1 else { return }
        for page in 2...pages { drag(up: true); settle(1); shot(name + "-p\(page)", dump: false) }
    }

    func clearKeypad(_ times: Int = 14) {
        let key = element("keypad_⌫")
        for _ in 0..<times where key.exists && key.isHittable { key.tap() }
    }

    /// Like a careful person: add the missing bank account with a balance, map the
    /// statement's account to it, and accept the suggested categories.
    func importIntoNewAccount(balance: String) -> Bool {
        shot("first-open", dump: false)
        guard tap("firstImport", timeout: 15) else { shot("first-import-missing"); return false }
        let commit = element("commitImport")
        let begin = Date()
        guard commit.waitForExistence(timeout: 60) else { note("MISS commitImport"); return false }
        note("preview ready \(String(format: "%.1f", Date().timeIntervalSince(begin)))s label=\(commit.label)")
        settle(1.5); shot("preview", dump: true)

        let creates = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'createImportCategory_'"))
        for index in 0..<min(creates.count, 8) {
            tapElement(creates.element(boundBy: index), name: "create category \(index)", timeout: 2, scrolls: 4, settle: 2)
        }
        if tap(label: "添加缺少的账户", timeout: 3, scrolls: 6) {
            shot("add-account-open", dump: true)
            type("银行卡", into: "accountName")
            if tap("accountBalance", timeout: 3, scrolls: 2) {
                keys(balance); shot("add-account-balance", dump: false)
                tap("accountBalanceDone", timeout: 2, scrolls: 0)
            }
            shot("add-account-filled", dump: true)
            tap("saveAccount", timeout: 3, scrolls: 0, settle: 2)
        }
        if tap("importCategoryMapping", timeout: 3, scrolls: 6, settle: 2) {
            let pending = element("importCategory_没分类")
            if tapElement(pending, name: "importCategory_没分类", timeout: 3, scrolls: 12, settle: 1.5) {
                var picked = false
                for label in ["其他支出", "其他", "购物"] where !picked {
                    let option = app.buttons.matching(NSPredicate(format: "label == %@ OR identifier ENDSWITH %@", label, "_" + label)).firstMatch
                    picked = tapElement(option, name: "pick " + label, timeout: 2, scrolls: 3, settle: 2)
                }
            }
            back(); settle(2)
        }
        let mappings = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'mapping_'"))
        for index in 0..<min(mappings.count, 4) {
            guard tapElement(mappings.element(boundBy: index), name: "account mapping \(index)", timeout: 2, scrolls: 4, settle: 1) else { continue }
            shot("account-menu", dump: true)
            let bank = app.buttons.matching(NSPredicate(format: "label == '银行卡'")).firstMatch
            if !tapElement(bank, name: "menu 银行卡", timeout: 2, scrolls: 0, settle: 1) {
                let any = app.descendants(matching: .any).matching(NSPredicate(format: "label == '银行卡'")).element(boundBy: 0)
                tapElement(any, name: "menu 银行卡 (any)", timeout: 2, scrolls: 0, settle: 1)
            }
        }
        settle(3)
        note("commit enabled=\(commit.isEnabled) label=\(commit.label)")
        shot("preview-decided", dump: true)
        let start = Date()
        guard tapElement(commit, name: "commitImport", timeout: 5, scrolls: 8, settle: 0.2) else { return false }
        let result = element("importResultPage")
        while Date().timeIntervalSince(start) < 300, !result.exists, alive("import") { Thread.sleep(forTimeInterval: 0.5) }
        note("TIMING commit→result \(String(format: "%.1f", Date().timeIntervalSince(start)))s exists=\(result.exists)")
        settle(2)
        shot("result", dump: true)
        drag(up: true); settle(1); shot("result-p2", dump: true)
        drag(up: true); settle(1); shot("result-p3", dump: false)
        return result.exists
    }

    func timed(_ label: String, _ id: String, timeout: TimeInterval = 90, action: () -> Void) {
        let start = Date()
        action()
        let ok = element(id).waitForExistence(timeout: timeout)
        note("TIMING \(label) \(String(format: "%.1f", Date().timeIntervalSince(start)))s ok=\(ok)")
    }
}

/// The year walk already proved a 4,339-row import works; XCTest queries on that
/// preview take ~35 s each, so this walk imports the last four and a half months.
private func recentStatement() -> Data {
    let text = String(decoding: AcceptanceYearData.csv, as: UTF8.self)
    let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
    let kept = [lines[0]] + lines.dropFirst().filter { $0 >= "2026-07-01" }
    return Data((kept.joined(separator: "\n") + "\n").utf8)
}

/// 一个认真的新用户：把一年账单导进新建的银行卡（填了真实余额），看导入结果、工资、
/// 还能花算式、对余额（真的输入数字）、心愿单判断，并记录关键操作耗时。
final class IARevisitTests: YubaiUITestCase {
    func testCarefulYearImport() {
        let w = AcceptanceWalker(self, tag: "R1-revisit", script: "acceptance",
                                 environment: ["YUBAI_UI_STATEMENT": recentStatement().base64EncodedString()])
        w.launch()
        guard w.importIntoNewAccount(balance: "20000") else { w.finish(); return }

        // Recognized plans (salary + bills) on the result page.
        if w.tap("reviewRecognizedImportPlans", timeout: 3, scrolls: 6) { w.shot("recognized-review", dump: true); w.back() }
        if w.tap("addAllRecognizedImportPlans", timeout: 3, scrolls: 6, settle: 3) { w.shot("recognized-added", dump: true) }
        w.timed("close result→home", "availableFunds") { if !w.tap("closeImportResult", timeout: 5, scrolls: 4) { w.home() } }
        w.settle(3)
        w.shotsDown("home", pages: 3)
        w.note("home hero: \(w.element("availableFunds").exists ? w.element("availableFunds").label : "-")")
        if w.tap("confirmSalary", timeout: 3, scrolls: 4, settle: 3) { w.shot("salary-confirmed", dump: true) }
        if w.tap("setupFirstSalary", timeout: 2, scrolls: 2) { w.shot("payday-sheet-after-import", dump: true); w.back() }
        w.root("ledger"); w.settle(2)
        if w.tap("fundsFormula", timeout: 4, scrolls: 0, settle: 2) { w.shot("formula", dump: true); w.drag(up: true); w.shot("formula-p2", dump: false); w.back() }

        // Accounts and a real reconcile: open the field, clear it, type the bank balance.
        w.root("yubai")
        if w.tap("openAccounts", timeout: 4, scrolls: 8, settle: 2) {
            w.shot("accounts", dump: true)
            if w.tap(label: "对一下余额", timeout: 3, scrolls: 4) || w.tap("reconcileAccounts", timeout: 2, scrolls: 2) {
                w.shot("reconcile-open", dump: true)
                let field = w.app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'reconcileField_'")).firstMatch
                if w.tapElement(field, name: "reconcile field", timeout: 3, scrolls: 2) {
                    w.shot("reconcile-field-open", dump: true)
                    w.keys("18500"); w.shot("reconcile-typed", dump: true)
                    let done = w.app.buttons.matching(NSPredicate(format: "identifier ENDSWITH 'Done'")).firstMatch
                    w.tapElement(done, name: "keypad done", timeout: 2, scrolls: 0)
                    w.shot("reconcile-result", dump: true)
                }
                if w.tap("reconcileApply", timeout: 3, scrolls: 3, settle: 3) { w.shot("reconcile-applied", dump: true) }
            }
            w.back()
        }
        w.root("ledger"); w.settle(2); w.shot("home-after-reconcile", dump: true)
        if w.tap("fundsFormula", timeout: 4, scrolls: 0, settle: 2) { w.shot("formula-after-reconcile", dump: true); w.back() }

        // Wishlist purchase check (local, no AI): a 699 pair of shoes.
        w.root("yubai")
        if w.tap("openWishlist", timeout: 4, scrolls: 8, settle: 2) {
            w.shot("wishlist", dump: true)
            let add = w.app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'addWish' OR label == '加一个' OR label == '想买的'")).firstMatch
            if w.tapElement(add, name: "add wish", timeout: 3, scrolls: 4) {
                w.shot("wish-add", dump: true)
                w.keys("699"); w.shot("wish-typed", dump: true)
            }
            w.back(); w.back()
        }

        // Timing of everyday moves on a year of data, without accessibility dumps.
        w.timed("tab insights", "rootPage_insights") { w.root("insights") }
        w.settle(1); w.shot("insights", dump: false)
        w.timed("tab ledger", "rootPage_ledger") { w.root("ledger") }
        w.timed("open add", "saveQuickEntry") { w.tap("addEntry", timeout: 5, scrolls: 0, settle: 0) }
        w.keys("32"); w.type("晚饭", into: "entryPurpose"); w.submitKeyboard()
        w.timed("save entry→home", "availableFunds") { w.tap("saveQuickEntry", timeout: 3, scrolls: 0, settle: 0) }
        w.settle(2); w.shot("home-after-entry", dump: true)
        w.timed("open search", "entriesSearchCancel") { w.tap("openLedgerSearch", timeout: 3, scrolls: 0, settle: 0) }
        w.finish()
    }
}
