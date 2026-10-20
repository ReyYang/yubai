import Foundation

public enum SampleData {
    public static func ledger(now: Date = Date()) -> Ledger {
        var l = Ledger(); l.isSample = true; l.preferences.onboardingComplete = true; l.preferences.horizonDays = 90
        l.preferences.emergencyReserve = 500_000; l.preferences.dailyLiving = 4_000
        let bank = Account(name: "工资卡", kind: .bank, balance: 3_680_000, at: now)
        let wechat = Account(name: "微信零钱", kind: .cash, balance: 186_050, at: now)
        let alipay = Account(name: "支付宝余额", kind: .cash, balance: 92_480, at: now)
        let credit = Account(name: "信用卡", kind: .credit, balance: -238_600, at: now)
        let fund = Account(name: "长期基金", kind: .investment, balance: 1_285_030, at: now)
        l.accounts = [bank, wechat, alipay, credit, fund]
        let descriptions: [(String, String, Int64)] = [("工作日午餐", "餐饮", 2800), ("咖啡与阅读", "餐饮", 2200), ("地铁出行", "交通", 600), ("周末采购", "日用购物", 18650), ("订阅工具", "学习工作", 13800), ("电影之夜", "娱乐旅行", 7800), ("药店补给", "医疗健康", 4650), ("与朋友晚餐", "餐饮", 15600)]
        for i in 0..<72 {
            let v = descriptions[i % descriptions.count]
            var e = Entry(date: Dates.addDays(-(i / 2), to: now).addingTimeInterval(-Double(i % 8 + 1) * 3600), amount: v.2, accountID: i % 3 == 0 ? bank.id : wechat.id, title: v.0, category: v.1)
            e.source = "示例"; e.classificationReason = "示例数据，不代表你的消费"; l.entries.append(e)
        }
        l.entries.append(Entry(date: Dates.addDays(-8, to: now), amount: 1_850_000, nature: .income, accountID: bank.id, title: "九月工资", category: "工资奖金"))
        var transfer = Entry(date: Dates.addDays(-5, to: now), amount: 100_000, nature: .transfer, accountID: bank.id, title: "补充微信零钱", category: "内部移动"); transfer.otherAccountID = wechat.id; l.entries.append(transfer)
        var salary = Plan(title: "工资到账", amount: 1_850_000, dueDate: Dates.addDays(20, to: now), frequency: .monthly, inflow: true, category: "工资奖金", nature: .income); salary.accountID = bank.id
        l.plans = [salary, Plan(title: "宽带与通信", amount: 12900, dueDate: Dates.addDays(6, to: now), frequency: .monthly, category: "居住"), Plan(title: "云服务订阅", amount: 6800, dueDate: Dates.addDays(12, to: now), frequency: .monthly, category: "学习工作")]
        var repay = Plan(title: "信用卡还款", amount: 238_600, dueDate: Dates.addDays(15, to: now), nature: .repayment); repay.accountID = credit.id; l.plans.append(repay)
        l.rents = [Rent(monthlyTotal: 480_000, personalShare: 240_000, startDate: Dates.addDays(-30, to: now), nextDueDate: Dates.addDays(42, to: now))]
        l.goals = [Goal(title: "下一次远行", target: 800_000, reserved: 180_000, dueDate: Dates.addDays(150, to: now))]
        return l
    }
}
