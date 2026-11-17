#if DEBUG && targetEnvironment(simulator)
import Foundation
import YubaiCore

extension UITestSupport {
    static let billGalleryScripts: Set<String> = ["v46-bills", "v46-bills-yearly", "v46-bills-pay", "v46-bills-match", "v46-bills-hidden", "v46-bills-hard"]
    static func billGalleryLedger(_ script: String, now: Date) throws -> Ledger {
        let today = Dates.day(now), c = Dates.calendar, month = c.dateInterval(of: .month, for: now)!.start
        let dayNumber = c.component(.day, from: today), last = c.range(of: .day, in: .month, for: now)!.count
        func date(_ day: Int) -> Date { Dates.addDays(min(day, last) - 1, to: month) }
        var ledger = Ledger(); ledger.id = galleryID(46400)
        ledger.preferences.onboardingComplete = true; ledger.preferences.profileColdStartDone = true
        ledger.preferences.cloudAIEnabled = false; ledger.preferences.lastBillCurrency = .usd
        ledger.preferences.hideAmounts = script == "v46-bills-hidden"
        ledger.preferences.billExchangeRates = [ManualExchangeRate(currency: .usd, cnyPerUnit: Decimal(string: "7.12")!, updatedAt: min(now, today.addingTimeInterval(9 * 3600)))]
        ledger.cycleAnchor = .calendarMonth; ledger.fixedSavings = 0; ledger.savingRule = .fixed(200_000)
        let names = ["招行储蓄卡", "微信零钱", "支付宝", "招行信用卡", "公积金"]
        let kinds: [AccountKind] = [.bank, .cash, .cash, .credit, .investment]
        let amounts: [Int64] = [921_400, 186_000, 110_000, -64_000, 4_820_000]
        for index in names.indices {
            var account = Account(name: names[index], kind: kinds[index], balance: amounts[index], at: now)
            account.id = galleryID(46410 + index); account.note = index == 0 ? "工资卡" : ""
            account.creditPaymentDay = index == 3 ? 5 : nil
            ledger.accounts.append(account)
        }
        let bank = ledger.accounts[0].id
        func bill(_ id: Int, _ name: String, _ amount: Int64, _ due: Date, frequency: Frequency = .monthly, currency: BillCurrency = .cny, paid: Bool = false, estimated: Bool = false) {
            var plan = Plan(title: name, amount: amount, dueDate: due, frequency: frequency, category: name == "房租" ? "居住" : "订阅")
            plan.id = galleryID(id); plan.accountID = bank; plan.currency = currency; plan.estimated = estimated
            plan.yearlyReserveSince = Dates.addMonths(-11, to: due)
            if paid {
                var entry = Entry(date: due, amount: amount, accountID: bank, title: name, category: plan.category)
                entry.id = galleryID(id + 100); entry.planID = plan.id; entry.occurrence = due
                plan.settledOccurrences = [due]; ledger.entries.append(entry)
            }
            ledger.plans.append(plan)
        }
        bill(46420, "房租", 300_000, date(min(5, dayNumber)), paid: true)
        bill(46421, "iCloud", 4_220, date(min(8, dayNumber)), paid: true)
        bill(46422, "ChatGPT Plus", 14_000, date(min(11, dayNumber)), paid: true)
        bill(46423, "腾讯视频", 2_500, date(21))
        let phoneDue = script == "v46-bills-match" ? Dates.addDays(1, to: today) : date(25)
        bill(46424, "话费和宽带", 16_000, phoneDue)
        bill(46425, "电费", 18_000, script == "v46-bills-pay" ? today : date(27), estimated: true)
        bill(46426, "Claude Pro", 2_000, date(28), currency: .usd)
        bill(46427, "1Password", 3_588, script == "v46-bills-yearly" ? Dates.addDays(7, to: today) : date(28), frequency: .yearly, currency: .usd)
        bill(46428, "Setapp", 50_000, Dates.addMonths(4, to: date(28)), frequency: .yearly)
        bill(46429, "Nintendo Switch Online", 47_585, Dates.addMonths(8, to: date(28)), frequency: .yearly)
        var salary = Plan(title: "工资", amount: 801_000, dueDate: date(10), frequency: .monthly, inflow: true, category: "工资奖金", nature: .income)
        salary.id = galleryID(46430); salary.accountID = bank
        if date(10) <= today {
            var entry = Entry(date: date(10), amount: salary.amount, nature: .income, accountID: bank, title: "工资", category: "工资奖金")
            entry.id = galleryID(46530); entry.planID = salary.id; entry.occurrence = salary.dueDate
            salary.settledOccurrences = [salary.dueDate]; ledger.entries.append(entry)
        }
        ledger.plans.append(salary)
        for (index, amount) in [16_820, 21_460, 19_840, 10_600].enumerated() {
            let due = Dates.addMonths(-index - 1, to: date(27))
            var entry = Entry(date: due, amount: Int64(amount), accountID: ledger.accounts[2].id, title: index == 1 ? "夏天空调" : "电费", category: "居住")
            entry.id = galleryID(46540 + index); entry.planID = galleryID(46425); entry.occurrence = due
            ledger.entries.append(entry)
        }
        // The displayed estimate was explicitly refreshed after these older payments.
        if let index = ledger.plans.firstIndex(where: { $0.id == galleryID(46425) }) { ledger.plans[index].estimatedAmountSince = now; ledger.plans[index].dueDate = Dates.addMonths(-4, to: date(27)) }
        ledger.entries.append(Entry(date: now.addingTimeInterval(-1), amount: 2_800, accountID: bank, title: "午饭", category: "餐饮"))
        ledger.entries.append(Entry(date: now.addingTimeInterval(-1), amount: 800, accountID: bank, title: "地铁", category: "交通"))
        if script == "v46-bills-match" {
            var entry = Entry(date: today, amount: 15_800, accountID: bank, title: "话费和宽带 · 中国移动", category: "居住")
            entry.id = galleryID(46560); entry.source = "导入"; ledger.entries.append(entry)
        }
        if script == "v46-bills-hard" {
            ledger.plans[3].title = galleryLongTitle + galleryLatinTitle; ledger.plans[3].amount = 9_999_999_999
            ledger.accounts[0].name = galleryLongTitle; ledger.accounts[0].anchorBalance = 999_999_999_999
        }
        if script == "v46-bills-yearly" {
            for index in ledger.plans.indices where !ledger.plans[index].inflow {
                ledger.plans[index].accountID = ledger.accounts[3].id
                if ledger.plans[index].id != galleryID(46427) { ledger.butlerAnswers["renewal:" + ledger.plans[index].id.uuidString] = now }
            }
            if let index = ledger.plans.firstIndex(where: { $0.id == galleryID(46425) }) { ledger.plans[index].skippedOccurrences = [date(27)] }
            let target: Int64 = 156_400
            ledger.accounts[0].anchorBalance += target - Finance.funds(ledger, now: now).available
        }
        ledger.updatedAt = now
        try ledger.validate(); return ledger
    }
}
#endif
