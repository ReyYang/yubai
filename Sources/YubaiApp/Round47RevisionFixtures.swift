#if DEBUG && targetEnvironment(simulator)
import Foundation
import YubaiCore

extension UITestSupport {
    static let revision47Scripts: Set<String> = Set(["v47r-ledger", "v47r-ledger-hard", "v47r-ledger-end", "v47r-insights", "v47r-yubai", "v47r-restraint-empty"]).union(model47Scripts)
    static func revision47Ledger(_ script: String, now: Date) throws -> Ledger {
        if model47Scripts.contains(script) { return try model47Ledger(script, now: now) }
        var value = try home47Ledger("v47-home", now: now)
        value.id = galleryID(479000)
        value.entries = []; value.cards = []; value.imports = []; value.memories = []
        value.profile = SpendingProfile(); value.savingHistory = []; value.cycleCovers = []
        value.reservePaybacks = nil
        value.preferences.cloudAIEnabled = false
        let today = Dates.day(now)
        value.accounts = [Account(name: "招行储蓄卡", kind: .bank, balance: 500_000, at: Dates.addMonths(-4, to: today))]
        value.accounts[0].id = galleryID(479001)
        let month = Dates.calendar.dateInterval(of: .month, for: today)!.start
        let payday = Dates.addDays(9, to: month)
        var salary = Plan(title: "工资", amount: 801_000, dueDate: Dates.addMonths(1, to: payday), frequency: .monthly, inflow: true, category: "工资", nature: .income)
        salary.id = galleryID(479002); salary.accountID = value.accounts[0].id; salary.autoPay = false
        var rent = Plan(title: "房租", amount: 331_000, dueDate: Dates.addDays(4, to: Dates.addMonths(1, to: month)), frequency: .monthly, category: "居住")
        rent.id = galleryID(479003); rent.accountID = value.accounts[0].id; rent.autoPay = false
        value.plans = [salary, rent]; value.cycleAnchor = .payday
        value.savingRule = .fixed(200_000); value.fixedSavings = 300_000
        func add(_ number: Int, _ title: String, _ category: String, _ amount: Int64, _ day: Date, income: Bool = false) {
            var row = Entry(date: min(day, now.addingTimeInterval(-1)), amount: amount, nature: income ? .income : .expense,
                            accountID: value.accounts[0].id, title: title, category: category)
            row.id = galleryID(number); row.recordedAt = row.date; row.userEdited = true
            value.entries.append(row)
        }
        add(479010, "工资", "工资", 801_000, payday, income: true)
        add(479101, "晚饭", "餐饮", 4500, today)
        add(479102, "地铁", "交通", 950, today)
        add(479103, "山姆会员店", "购物", 18_640, Dates.addDays(-1, to: today))
        add(479104, "午饭", "餐饮", 2800, Dates.addDays(-1, to: today))
        for offset in 2...8 {
            add(479110 + offset, offset.isMultiple(of: 2) ? "咖啡" : "外卖", "餐饮", 1800 + Int64(offset * 100), Dates.addDays(-offset, to: today))
        }
        add(479119, "日用", "日用", 40_610, Dates.addDays(1, to: payday))
        for offset in 1...3 {
            let day = Dates.addDays(-1, to: Dates.addMonths(-offset + 1, to: month))
            add(479200 + offset, "咖啡", "餐饮", 1800, day)
        }
        add(479999, "最早的一笔", "日用", 1200, Dates.addDays(-1, to: Dates.addMonths(-3, to: month)))
        // Income and spending, rather than opening cash, produce the hero.
        if script == "v47r-ledger-hard" {
            value.entries[1].title = galleryLongTitle + galleryLatinTitle
            value.entries[1].amount = 123_456_789
            value.accounts[0].anchorBalance = 987_654_321
        }
        if script == "v47r-restraint-empty" { value.profile.principles = ["钱该怎么花，你说了算"] }
        value.preferences.lastBackupAt = Dates.addDays(-1, to: today)
        for task in HomeButler.queue(value, now: now) { HomeButler.answer(task.id, in: &value, now: now) }
        try value.validate(); return value
    }
}
#endif
