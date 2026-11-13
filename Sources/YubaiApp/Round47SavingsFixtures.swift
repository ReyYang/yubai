#if DEBUG && targetEnvironment(simulator)
import Foundation
import YubaiCore

extension UITestSupport {
    static let savings47Scripts: Set<String> = [
        "v47-spend", "v47-spend-over", "v47-spend-zero", "v47-savings", "v47-savings-hard", "v47-savings-no-floor",
        "v47-records", "v47-topup", "v47-topup-queue", "v47-toast-short", "v47-toast-long"
    ]
    static func savings47Ledger(_ script: String, now: Date) throws -> Ledger {
        let today = Dates.day(now), start = Dates.addDays(-10, to: today)
        let month = Dates.calendar.dateInterval(of: .month, for: today)!.start
        var value = Ledger(); value.id = galleryID(471000)
        value.preferences.onboardingComplete = true; value.preferences.profileColdStartDone = true
        value.preferences.cloudAIEnabled = false; value.preferences.appearance = galleryAppearance ?? "light"
        value.lastReflectionWeek = ButlerCards.isoWeek(today); value.lastSubcategoryBatchDay = Dates.text(today)
        value.mutedTopics = ["letter"]; value.cycleAnchor = .payday
        var bank = Account(name: "工资卡", balance: 300_000, at: Dates.addDays(-1, to: start)); bank.id = galleryID(471010)
        value.accounts = [bank]; value.fixedSavings = 300_000; value.savingRule = .fixed(200_000); value.profile.floorAmount = 300_000
        var salary = Plan(title: "工资", amount: 801_000, dueDate: start, frequency: .monthly, inflow: true, category: "工资", nature: .income)
        salary.id = galleryID(471020); salary.accountID = bank.id
        var income = Entry(date: start.addingTimeInterval(9 * 3600), amount: 801_000, nature: .income, accountID: bank.id, title: "工资", category: "工资")
        income.id = galleryID(471030); income.planID = salary.id; income.occurrence = start
        value.plans = [salary]; value.entries = [income]
        for (index, item) in [("房租", Int64(300_000)), ("话费和宽带", 16_000), ("电费", 10_000), ("水费", 2500), ("视频会员", 2500)].enumerated() {
            var bill = Plan(title: item.0, amount: item.1, dueDate: Dates.addDays(index + 2, to: today), category: "居住")
            bill.id = galleryID(471040 + index); bill.accountID = bank.id; value.plans.append(bill)
        }
        var yearly = Plan(title: "年付保险", amount: 360_000, dueDate: Dates.addMonths(11, to: month), frequency: .yearly, category: "居住")
        yearly.id = galleryID(471050); yearly.yearlyReserveSince = month; yearly.accountID = bank.id; value.plans.append(yearly)
        for index in 0..<34 {
            var entry = Entry(date: Dates.addDays(-(index % 9), to: today), amount: index < 33 ? 2400 : 4400,
                              accountID: bank.id, title: "日常\(index + 1)", category: "餐饮")
            entry.id = galleryID(471100 + index); value.entries.append(entry)
        }
        var headphones = WishItem(title: "降噪耳机", amount: 189_900); headphones.id = galleryID(471200); headphones.createdAt = Dates.addDays(-6, to: today)
        var camera = WishItem(title: "相机", amount: 860_000); camera.id = galleryID(471201); camera.createdAt = Dates.addDays(-5, to: today)
        value.wishlist = [headphones, camera]
        if script == "v47-spend-zero" {
            value.plans = [salary]; value.entries = [income]; value.savingRule = nil; value.fixedSavings = 0; value.profile.floorAmount = nil
        }
        if script == "v47-spend-over" {
            var extra = Entry(date: now, amount: 200_000, accountID: bank.id, title: "旅行", category: "旅行"); extra.id = galleryID(471150)
            value.entries.append(extra)
        }
        if script == "v47-savings-hard" {
            value.accounts[0].anchorBalance = 1_234_567_890; value.accounts[0].name = galleryLongTitle + galleryLatinTitle
            value.fixedSavings = 123_456_789; value.profile.floorAmount = 98_765_432
            value.wishlist[0].title = galleryLongTitle + galleryLatinTitle; value.wishlist[1].title = galleryLatinTitle
            value.wishlist[1].amount = 987_654_321
            value.entries[1].title = galleryLongTitle + galleryLatinTitle
        }
        if script == "v47-savings-no-floor" { value.profile.floorAmount = nil }
        if script == "v47-records" {
            try Reserve.transfer(.take, amount: 50_000, in: &value, now: Dates.addDays(-1, to: today))
            var coat = Entry(date: Dates.addDays(-2, to: today), amount: 120_000, accountID: bank.id, title: "大衣", category: "购物", fromReserve: true)
            coat.id = galleryID(471151); value.entries.append(coat)
            var repair = Entry(date: Dates.addDays(-23, to: today), amount: 86_000, accountID: bank.id, title: galleryLongTitle, category: "交通", fromReserve: true)
            repair.id = galleryID(471152); value.entries.append(repair)
            try Reserve.transfer(.putBack, amount: 20_000, in: &value, now: now.addingTimeInterval(-1))
        }
        if script.hasPrefix("v47-topup") {
            value.plans[0].dueDate = today
            value.entries = [income]; value.entries[0].date = today; value.entries[0].occurrence = today
            // This previous-day withdrawal belongs to the first payday shown now.
            try Reserve.transfer(.take, amount: 50_000, in: &value, now: Dates.addDays(-1, to: today))
            value.accounts[0].anchorBalance += 601_000 - Finance.funds(value, now: now).available
            if script == "v47-topup-queue" {
                var renewal = Plan(title: "视频会员", amount: 2500, dueDate: Dates.addDays(1, to: today), frequency: .monthly, category: "订阅")
                renewal.id = galleryID(471051); renewal.accountID = bank.id; value.plans.append(renewal)
            }
        }
        let cycle = Finance.cycle(in: value, now: now)
        let previous = Finance.cycle(in: value, now: cycle.start.addingTimeInterval(-1))
        value.savingHistory = [CycleSaving(cycleStart: previous.start, cycleEnd: previous.end, income: 801_000, target: 200_000,
                                          saved: 200_000, unspent: 0, leftoverChoice: .keep)]
        try value.validate(); return value
    }
}
#endif
