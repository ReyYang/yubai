import XCTest

// Independent acceptance walks (test branch only). Each class is its own CI shard so
// the walks run in parallel. They never assert: misses, crashes and timings are logged.

private func yearWalker(_ test: YubaiUITestCase, tag: String, arguments: [String] = []) -> AcceptanceWalker {
    let w = AcceptanceWalker(test, tag: tag, script: "acceptance",
                             environment: ["YUBAI_UI_STATEMENT": AcceptanceYearData.csv.base64EncodedString()],
                             arguments: arguments)
    w.launch()
    w.importYear(capture: false)
    if !w.tap("closeImportResult", timeout: 5, scrolls: 0) { w.home() }
    w.settle(2)
    return w
}

private func ledgerRow(_ w: AcceptanceWalker, _ index: Int = 0) -> XCUIElement {
    w.app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'ledgerEntry_'")).element(boundBy: index)
}

/// 空白新用户第一周：首次打开、设工资、手记几笔、看各页空状态、重启后数据还在。
final class IAFirstUseTests: YubaiUITestCase {
    func testBlankUserFirstWeek() {
        let w = AcceptanceWalker(self, tag: "A1-first", script: "empty")
        w.launch()
        w.shot("first-open")
        // 还能花 → 发薪日与工资
        if w.tap("firstOpenEmptyAmount", timeout: 10) {
            w.shot("payday-setup")
            if w.tap("paydaySetupAmount") { w.shot("payday-amount-keypad"); w.keys("9500"); w.shot("payday-amount-typed"); w.tap("paydaySetupAmountDone") }
            w.shot("payday-setup-filled")
            w.tap("paydaySetupDone")
            w.shot("after-payday-setup")
        }
        w.home(); w.shot("home-after-setup")
        // 第一笔：午饭 25.5
        if w.tap("addEntry") {
            w.shot("add-entry-open")
            w.keys("25.5"); w.type("午饭 黄焖鸡", into: "entryPurpose"); w.shot("add-entry-filled")
            w.tap("saveQuickEntry"); w.shot("add-entry-saved")
            // 第二笔：打车 18（不填用途）
            if w.element("keypad_1").exists { w.keys("18"); w.shot("second-entry-no-purpose"); w.tap("saveQuickEntry"); w.shot("second-entry-saved") }
            w.home()
        }
        // 收入：兼职 1200
        if w.tap("addEntry") {
            w.tap("entryNature_income"); w.shot("income-mode")
            w.keys("1200"); w.type("兼职稿费", into: "entryPurpose"); w.shot("income-filled")
            w.tap("saveQuickEntry"); w.shot("income-saved"); w.home()
        }
        // 退款与转账两种性质看一眼
        if w.tap("addEntry") {
            w.tap("entryNature_refund"); w.shot("refund-mode")
            w.tap("entryNature_transfer"); w.shot("transfer-mode")
            w.home()
        }
        w.shot("home-after-4-entries")
        w.scrollShots("home", max: 4)
        w.root("insights"); w.scrollShots("insights-new-user", max: 4)
        w.root("yubai"); w.scrollShots("yubai-new-user", max: 4)
        w.crawl("yubai-new-user") { w.root("yubai") }
        w.root("ledger")
        if w.tap("fundsFormula") { w.scrollShots("formula-new-user", max: 4); w.home() }
        if w.tap("openSaving") { w.scrollShots("saving-new-user", max: 4); w.home() }
        w.relaunch("persistence check")
        w.shot("after-relaunch")
        w.finish()
    }
}

/// 有一年账单的新用户：首次打开就导入一整年。
final class IAImportTests: YubaiUITestCase {
    func testFirstImportOfOneYear() {
        let w = AcceptanceWalker(self, tag: "B1-import", script: "acceptance",
                                 environment: ["YUBAI_UI_STATEMENT": AcceptanceYearData.csv.base64EncodedString()])
        w.launch()
        let ok = w.importYear(capture: true)
        w.note("import ok=\(ok)")
        w.note("result buttons: " + w.visibleButtons().map { $0.0 + "=" + $0.1 }.joined(separator: " | "))
        for id in ["importResultSummary", "importRecognizedPlans", "activeEntryCount", "importResultUnclassified"] where w.element(id).exists {
            w.note("result \(id): \(w.element(id).label)")
        }
        if w.tap("reviewRecognizedImportPlans", timeout: 3) { w.scrollShots("recognized-plans", max: 5); w.back(); w.settle() }
        if w.tap("importResultUnclassified", timeout: 3) { w.scrollShots("unclassified-from-result", max: 4); w.back(); w.settle() }
        w.shot("result-after-subpages")
        w.tap("closeImportResult", timeout: 3, scrolls: 0)
        w.home()
        w.shot("home-after-import")
        w.scrollShots("home-after-import", max: 10)
        for id in ["pendingImportsCard", "quickSortUnsorted", "classifyImportsManually", "groupUnsortedByParty", "salaryCard", "firstSalaryCard", "balanceMismatchCard"] {
            if w.element(id).exists { w.note("home shows \(id)") }
        }
        if w.tap("quickSortUnsorted", timeout: 3) { w.scrollShots("quick-sort", max: 4); w.home() }
        if w.tap("classifyImportsManually", timeout: 3) { w.scrollShots("classify-manually", max: 4); w.home() }
        if w.tap("firstSalaryCard", timeout: 3) { w.shot("first-salary-card-tap"); w.home() }
        w.crawl("home-after-import") { w.root("ledger") }
        w.finish()
    }
}

/// 一年数据下的账本：主页、还能花算式、存钱页、搜索、筛选、跳月、点开一笔。
final class IAYearLedgerTests: YubaiUITestCase {
    func testLedgerWithOneYear() {
        let w = yearWalker(self, tag: "C1-ledger")
        w.root("ledger"); w.scrollShots("ledger-home", max: 12)
        if w.tap("fundsFormula") {
            w.scrollShots("formula", max: 6)
            w.crawl("formula") { w.root("ledger"); w.tap("fundsFormula") }
            w.home()
        }
        if w.tap("openSaving") {
            w.scrollShots("saving", max: 6)
            w.crawl("saving") { w.root("ledger"); w.tap("openSaving") }
            w.home()
        }
        w.root("ledger")
        if w.tap("openLedgerSearch") {
            w.shot("search-open")
            w.type("咖啡", into: "entriesSearch"); w.settle(1.5); w.shot("search-coffee")
            w.back(); w.shot("search-after-dismiss-keyboard")
            w.home()
        }
        w.root("ledger")
        if w.tap("openLedgerSearch") { w.type("基金", into: "entriesSearch"); w.settle(1.5); w.shot("search-fund"); w.home() }
        w.root("ledger")
        if w.tap("openLedgerSearch") { w.type("25", into: "entriesSearch"); w.settle(1.5); w.shot("search-amount-25"); w.home() }
        w.root("ledger")
        if w.tap("openLedgerFilters") { w.scrollShots("filters", max: 4); w.crawl("filters") { w.root("ledger"); w.tap("openLedgerFilters") }; w.home() }
        w.root("ledger")
        if w.tap("entriesMonth", timeout: 3) || w.tap("ledgerJumpYear", timeout: 2) { w.shot("month-jump"); w.home() }
        w.root("ledger")
        w.drag(up: true); w.drag(up: true)
        let row = ledgerRow(w)
        if w.tapElement(row, name: "first ledger row") {
            w.scrollShots("entry-open", max: 4)
            w.crawl("entry-open") { w.root("ledger"); w.drag(up: true); w.drag(up: true); w.tapElement(ledgerRow(w), name: "row") }
            w.home()
        }
        // 左滑一行
        w.root("ledger"); w.drag(up: true); w.drag(up: true)
        let swipeRow = ledgerRow(w, 1)
        if swipeRow.exists { swipeRow.swipeLeft(); w.settle(); w.shot("row-swipe-left"); w.home() }
        // 往下翻到很久以前
        w.root("ledger")
        for _ in 0..<25 { w.app.swipeUp(); if !w.timeLeft { break } }
        w.settle(2); w.shot("ledger-deep-scroll")
        w.crawl("ledger-home") { w.root("ledger") }
        w.finish()
    }
}

/// 一年数据下的洞察。
final class IAYearInsightsTests: YubaiUITestCase {
    func testInsightsWithOneYear() {
        let w = yearWalker(self, tag: "D1-insights")
        w.root("insights"); w.scrollShots("insights", max: 12)
        w.root("insights")
        if w.tap("insightCategory_0") { w.scrollShots("category-0", max: 6); w.crawl("category-0") { w.root("insights"); w.tap("insightCategory_0") }; w.home() }
        w.root("insights")
        if w.tap("insightCategory_1") { w.scrollShots("category-1", max: 4); w.home() }
        w.root("insights")
        if w.tap("cashMonthCard", timeout: 3) { w.scrollShots("cash-month", max: 4); w.home() }
        w.crawl("insights") { w.root("insights") }
        w.crawl("insights-lower") { w.root("insights"); w.drag(up: true); w.drag(up: true) }
        w.finish()
    }
}

/// 一年数据下的「余白」页与设置的每个子页。
final class IAYearYubaiTests: YubaiUITestCase {
    func testYubaiAndSettingsWithOneYear() {
        let w = yearWalker(self, tag: "E1-yubai")
        w.root("yubai"); w.scrollShots("yubai", max: 8)
        w.crawl("yubai") { w.root("yubai") }
        w.crawl("yubai-lower") { w.root("yubai"); w.drag(up: true); w.drag(up: true) }
        // 问余白（没有配置 key）
        w.root("yubai")
        if w.tap("askYubai") { w.app.typeText("这个月咖啡花了多少？\n"); w.settle(3); w.shot("ask-no-key"); w.home() }
        let settings = ["openSpendingParts", "openCategories", "openImportHistory", "openSettingsWeekly", "openNoticeSettings", "openQuickCapture",
                        "openCloudService", "openCloudKey", "openIntelligencePrivacy", "openCloudSendLog", "openBackup", "openRecoveryVersions",
                        "recentlyDeleted", "openStorage", "openLedgerLocation", "openDeviceSettings"]
        w.root("yubai")
        if w.tap("openSettings") { w.scrollShots("settings", max: 8) }
        for id in settings {
            guard w.timeLeft else { break }
            w.root("yubai"); guard w.tap("openSettings") else { break }
            if w.tap(id, scrolls: 10) { w.scrollShots("settings-" + id, max: 4) }
        }
        w.finish()
    }
}

/// 一年数据下的日常操作：记一笔、改一笔、删一笔、对余额，看还能花怎么变。
final class IAYearDailyTests: YubaiUITestCase {
    func testDailyTasksOnTopOfOneYear() {
        let w = yearWalker(self, tag: "F1-daily")
        w.root("ledger"); w.shot("before")
        let funds = w.element("availableFunds")
        w.note("availableFunds before: \(funds.exists ? funds.label : "-")")
        if w.tap("addEntry") {
            w.shot("add-open-with-history")
            w.keys("38"); w.type("咖啡", into: "entryPurpose"); w.settle(1); w.shot("add-coffee-suggestion")
            w.tap("saveQuickEntry"); w.shot("add-coffee-saved"); w.home()
        }
        w.note("availableFunds after +38 expense: \(funds.exists ? funds.label : "-")")
        w.shot("after-expense")
        // 大额：笔记本 6999
        if w.tap("addEntry") {
            w.keys("6999"); w.type("笔记本电脑", into: "entryPurpose"); w.shot("big-purchase-filled")
            w.tap("saveQuickEntry"); w.settle(2); w.shot("big-purchase-saved"); w.home()
        }
        w.note("availableFunds after +6999 expense: \(funds.exists ? funds.label : "-")")
        w.shot("after-big-purchase")
        w.scrollShots("home-after-big", max: 4)
        // 改刚记的那笔
        w.root("ledger")
        let row = ledgerRow(w)
        if w.tapElement(row, name: "latest row") {
            w.shot("edit-latest")
            if w.tap("editEntryAmount", timeout: 3) { w.shot("edit-amount") ; w.back() }
            w.home()
        }
        // 删除刚记的那笔（可撤销）
        w.root("ledger")
        if w.tapElement(ledgerRow(w), name: "latest row for delete") {
            if w.tap("deleteEntry", timeout: 3, scrolls: 6) { w.shot("after-delete-toast"); w.settle(1) }
            w.home()
        }
        w.note("availableFunds after delete: \(funds.exists ? funds.label : "-")")
        w.shot("after-delete")
        // 对一下余额
        for id in ["openReconcile", "reconcileByHand", "balanceMismatchCard"] where w.element(id).exists { w.note("reconcile entry: \(id)") }
        if w.tap(label: "对一下余额", timeout: 2, scrolls: 0) || w.tap("reconcileByHand", timeout: 2) {
            w.shot("reconcile-open"); w.home()
        }
        // 长按 ＋
        w.root("ledger")
        let add = w.element("addEntry")
        if add.exists { add.press(forDuration: 1.2); w.settle(); w.shot("long-press-add"); w.home() }
        // 隐藏金额
        if w.tap("toggleAmountVisibility") { w.shot("amounts-hidden"); w.root("insights"); w.shot("insights-hidden"); w.root("ledger"); w.tap("toggleAmountVisibility") }
        w.finish()
    }
}

/// 一年数据 + 大字号；再切深色看三页。
final class IAYearDisplayTests: YubaiUITestCase {
    func testLargeTextAndDarkMode() {
        let w = yearWalker(self, tag: "G1-display",
                           arguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"])
        w.root("ledger"); w.scrollShots("large-ledger", max: 5)
        if w.tap("fundsFormula") { w.scrollShots("large-formula", max: 4); w.home() }
        if w.tap("addEntry") { w.shot("large-add-entry"); w.keys("25"); w.shot("large-add-entry-typed"); w.home() }
        w.root("insights"); w.scrollShots("large-insights", max: 5)
        w.root("yubai"); w.scrollShots("large-yubai", max: 4)
        // 切深色（设置 → 外观）
        w.root("yubai")
        if w.tap("openSettings") {
            if w.tap(label: "外观", timeout: 2, scrolls: 0) || w.tapElement(w.app.buttons.matching(NSPredicate(format: "label BEGINSWITH '外观'")).firstMatch, name: "外观 picker") {
                w.shot("appearance-menu")
                if !w.tap(label: "深色", timeout: 3) { w.tapElement(w.app.descendants(matching: .any).matching(NSPredicate(format: "label == '深色'")).firstMatch, name: "深色") }
                w.settle(2)
            }
        }
        w.home()
        w.root("ledger"); w.scrollShots("dark-large-ledger", max: 3)
        w.root("insights"); w.scrollShots("dark-large-insights", max: 3)
        w.root("yubai"); w.scrollShots("dark-large-yubai", max: 3)
        w.finish()
    }
}
