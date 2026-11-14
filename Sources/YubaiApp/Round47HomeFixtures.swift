#if DEBUG && targetEnvironment(simulator)
import Foundation
import YubaiCore

extension UITestSupport {
    static let home47Scripts: Set<String> = [
        "v47-home", "v47-home-hard", "v47-saving-wish", "v47-saving-reached", "v47-saving-monthly", "v47-saving-empty",
        "v47-receipt-empty", "v47-receipt-normal", "v47-receipt-added", "v47-receipt-many",
        "v47-first", "v47-after", "v47-after-deferred", "v47-after-income", "v47-after-deadline"
    ]
    static func home47Ledger(_ script: String, now: Date) throws -> Ledger {
        if script == "v47-first" {
            var empty = Ledger(); empty.id = galleryID(470001); empty.preferences.cloudAIEnabled = false
            empty.preferences.appearance = galleryAppearance ?? "light"
            return empty
        }
        let today = Dates.day(now)
        var value = try v46Ledger(script == "v47-home-hard" ? "v46-hard" : "v46-home", now: now)
        value.id = galleryID(470000); value.preferences.cloudAIEnabled = false
        if script != "v47-home-hard" {
            value.fixedSavings = 300_000
            value.accounts[0].anchorBalance -= 200_000
        }
        value.entries.removeAll { Dates.day($0.date) == today }
        func add(_ id: Int, _ title: String, _ amount: Int64, _ minute: Int, nature: Nature = .expense) {
            let elapsed = max(0, now.timeIntervalSince(today) - 1)
            let stamp = today.addingTimeInterval(min(elapsed, Double(minute * 60)))
            var row = Entry(date: stamp, amount: amount, nature: nature, accountID: value.accounts[0].id, title: title,
                            category: nature == .income ? "工资" : title == "地铁" ? "交通" : "餐饮")
            row.id = galleryID(id); row.recordedAt = stamp; row.userEdited = true; value.entries.append(row)
        }
        add(470101, "午饭", 2800, 751); add(470102, "地铁", 800, 1122)
        var wish = WishItem(title: "相机", amount: 860_000); wish.id = galleryID(470201); wish.createdAt = Dates.addDays(-5, to: today)
        value.wishlist = [wish]
        if script == "v47-saving-reached" { value.wishlist[0].title = "降噪耳机"; value.wishlist[0].amount = 189_900 }
        if script == "v47-saving-monthly" || script == "v47-saving-empty" { value.wishlist = [] }
        if script == "v47-saving-empty" { value.fixedSavings = 0; value.savingRule = nil; value.savingHistory = []; value.reservePaybacks = nil }
        if script == "v47-receipt-empty" { value.entries.removeAll { Dates.day($0.date) == today } }
        if script == "v47-receipt-added" { add(470103, "咖啡", 1800, 1145) }
        if script == "v47-receipt-many" || script == "v47-home-hard" {
            for index in 0..<7 { add(470110 + index, index == 6 ? galleryLongTitle + galleryLatinTitle : "日常\(index + 1)", index == 6 ? 123_456_789 : Int64(100 + index), 600 + index) }
        }
        // The crossing regression needs a page taller than the ordinary-size
        // viewport. Its original nine rows fit at the top, so dragging down
        // only bounced and could never place the oldest row across the tabs.
        if script == "v47-receipt-many", ProcessInfo.processInfo.environment["YUBAI_UI_TEST_RECEIPT_CROSSING"] == "1" {
            for index in 0..<20 { add(470300 + index, "日常\(index + 8)", 100, 620 + index) }
        }
        if script == "v47-home-hard" {
            value.wishlist[0].title = galleryLongTitle + galleryLatinTitle; value.wishlist[0].amount = 987_654_321
        }
        if script.hasPrefix("v47-after") {
            value.entries = []; value.plans = []; value.wishlist = []; value.fixedSavings = 0; value.savingRule = nil
            value.savingHistory = []; value.cycleCovers = []; value.reservePaybacks = nil
            value.cards = []; value.memories = []; value.accounts[0].anchorBalance = 0
            value.cycleAnchor = nil; value.paydayConfirmSince = nil
            add(470101, "午饭", 2800, 751)
            if script != "v47-after" {
                FirstUse.deferSalarySetup(&value, now: script == "v47-after-deadline" ? Dates.addMonths(-2, to: now) : now)
            }
            if script == "v47-after-income" { add(470104, "工资", 801_000, 752, nature: .income) }
        }
        try value.validate(); return value
    }
    /// Legacy budget and form walks start with an established ledger. Their
    /// dormant salary plan leaves cash unchanged and never posts income itself.
    static func seedKnownHomeBudget(_ value: inout Ledger, now: Date) {
        if value.entries.isEmpty {
            var previous = Entry(date: Dates.addMonths(-2, to: now), amount: 1, accountID: value.accounts[0].id, title: "合成旧记录", category: "餐饮")
            previous.deletedAt = now; value.entries = [previous]
        }
        if !value.plans.contains(where: { $0.inflow && $0.nature == .income && $0.frequency == .monthly }) {
            var plan = Plan(title: "工资", amount: 801_000, dueDate: Dates.addDays(20, to: Dates.day(now)), frequency: .monthly,
                            inflow: true, category: "工资", nature: .income)
            plan.accountID = value.accounts[0].id; plan.autoPay = false; value.plans.append(plan)
        }
    }
}
#endif
