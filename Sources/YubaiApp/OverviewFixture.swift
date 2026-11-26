import Foundation
import YubaiCore

enum OverviewFixture {
    case review, period, drill, assets, account, reconcile, invest

    static let current: Self? = {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "-YubaiReviewFixture") {
            return args.dropFirst(index + 1).first == "period" ? .period : .review
        }
        if args.contains("-YubaiReviewDrillFixture") { return .drill }
        if args.contains("-YubaiAssetsFixture") { return .assets }
        if let index = args.firstIndex(of: "-YubaiAccountFixture") {
            switch args.dropFirst(index + 1).first {
            case "reconcile": return .reconcile
            case "invest": return .invest
            default: return .account
            }
        }
        #endif
        return nil
    }()

    static let chartClearingSource = "overview-fixture-clearing"

    var now: Date { Self.date("2026-11-23 12:00:00") }

    private static func date(_ value: String) -> Date { Dates.parse(value)! }

    #if DEBUG
    struct Seed {
        var ledger: Ledger
        var segment = OverviewSegment.review
        var route: TabRoute?
        var periodSheet: OverviewPeriodSelection?
        var valuation: AccountValuationTarget?
        var valuationAmount: Int64?
    }

    func makeSeed() -> Seed {
        switch self {
        case .review, .period, .drill: reviewSeed()
        case .assets, .account, .reconcile, .invest: accountSeed()
        }
    }

    private func baseLedger() -> Ledger {
        var ledger = Ledger()
        ledger.preferences.onboardingComplete = true
        ledger.preferences.hideAmounts = ProcessInfo.processInfo.environment["YUBAI_GALLERY_HIDE_AMOUNTS"] == "1"
        ledger.updatedAt = now
        return ledger
    }

    private func reviewSeed() -> Seed {
        var ledger = baseLedger()
        let bank = Account(name: "招行储蓄", balance: 3_218_000, at: Self.date("2026-09-09"))
        ledger.accounts = [bank]
        ledger.cycleAnchor = .payday
        ledger.savingRule = .fixed(500_000)
        ledger.savingHistory = [
            CycleSaving(cycleStart: Self.date("2026-10-10"), cycleEnd: Self.date("2026-11-09"),
                        income: 1_850_000, target: 438_000, saved: 438_000)
        ]
        ledger.plans = [
            Plan(title: "工资", amount: 1_850_000, dueDate: Self.date("2026-10-10"),
                 frequency: .monthly, inflow: true, category: "工资奖金", nature: .income)
        ]
        ledger.spendingParts = [SpendingPart(name: "购物", amount: 150_000, categories: ["购物"])]
        if let index = ledger.categories.firstIndex(where: { $0.name == "购物" }) {
            for name in ["衣服", "数码配件", "日用杂货"] where !ledger.categories[index].subcategories.contains(name) {
                ledger.categories[index].subcategories.append(name)
            }
        }

        func spending(_ day: String, _ title: String, _ amount: Int64, category: String, subcategory: String? = nil) -> Entry {
            var entry = Entry(date: Self.date(day), amount: amount, accountID: bank.id, title: title, category: category)
            entry.subcategory = subcategory
            return entry
        }

        let main: [(String, Int64, Int64)] = [
            ("居住", 200_010, 200_000), ("吃饭", 126_400, 130_200), ("买菜", 98_000, 91_200),
            ("娱乐", 57_800, 64_000), ("交通", 31_200, 31_000), ("学习", 20_650, 20_000),
            ("医疗健康", 12_000, 12_000), ("运动", 6_700, 6_000),
        ]
        for (name, current, previous) in main {
            ledger.entries.append(spending("2026-11-12", name, current, category: name))
            ledger.entries.append(spending("2026-10-12", name, previous, category: name))
        }

        let shopping: [(String, String, String, Int64)] = [
            ("21", "优衣库", "衣服", 29_900), ("18", "充电器", "数码配件", 19_900),
            ("14", "羽绒服", "衣服", 60_000), ("12", "数据线", "数码配件", 6_500),
            ("11", "收纳盒", "日用杂货", 6_800), ("10", "转接头", "数码配件", 3_500),
            ("10", "清洁布", "日用杂货", 2_000), ("10", "挂钩", "日用杂货", 1_800),
            ("10", "纸巾", "日用杂货", 1_400),
        ]
        for (day, name, sub, amount) in shopping {
            ledger.entries.append(spending("2026-11-" + day, name, amount, category: "购物", subcategory: sub))
        }
        for (name, amount) in [("衣服", 32_000), ("数码配件", 18_000), ("日用杂货", 28_450)] {
            ledger.entries.append(spending("2026-10-12", name, Int64(amount), category: "购物", subcategory: name))
        }

        for day in ["2026-10-10", "2026-11-10"] {
            ledger.entries.append(Entry(date: Self.date(day), amount: 1_850_000, nature: .income,
                                        accountID: bank.id, title: "工资", category: "工资奖金"))
        }

        var seed = Seed(ledger: ledger)
        if self == .drill { seed.route = .whereCategory(title: "购物", categories: ["购物"], isOther: false, selection: .current) }
        if self == .period { seed.periodSheet = .custom(start: Self.date("2026-10-01"), end: Self.date("2026-11-23")) }
        return seed
    }

    private func accountSeed() -> Seed {
        var ledger = baseLedger()
        var bank = Account(name: "招行储蓄", balance: 3_218_000, at: Self.date("2026-11-20"))
        let alipay = Account(name: "支付宝", kind: .cash, balance: 2_499_960, at: Self.date("2026-11-20"))
        let wechat = Account(name: "微信零钱", kind: .cash, balance: 124_040, at: Self.date("2026-11-20"))
        let credit = Account(name: "招行信用卡", kind: .credit, balance: -321_680, at: Self.date("2026-11-20"))
        let fund = Account(name: "基金", kind: .investment, balance: 4_123_600, at: Self.date("2026-11-01"))
        ledger.accounts = [bank, alipay, wechat, credit, fund]
        ledger.profile.floorAmount = 5_000_000
        ledger.fixedSavings = 5_842_000
        ledger.lastReconciledAt = bank.anchorDate

        if self != .assets {
            ledger.accounts.append(contentsOf: chartEntries(bank: &bank, alipay: alipay, fund: fund, entries: &ledger.entries))
            ledger.accounts[0] = bank
        } else {
            ledger.entries = [Entry(date: Self.date("2026-11-10"), amount: 1_850_000, nature: .income,
                                    accountID: bank.id, title: "工资", category: "工资奖金")]
        }
        var seed = Seed(ledger: ledger, segment: .assets)
        if self != .assets { seed.route = .accountDetail(bank.id) }
        if self == .reconcile { seed.valuation = .reconcile(bank.id); seed.valuationAmount = 3_205_640 }
        if self == .invest { seed.valuation = .invest(fund.id); seed.valuationAmount = 4_201_850 }
        return seed
    }

    private func chartEntries(bank: inout Account, alipay: Account, fund: Account, entries: inout [Entry]) -> [Account] {
        let start = Self.date("2026-10-24")
        let points: [Int64] = [
            30_200, 29_800, 29_650, 29_100, 28_900, 28_400, 27_800, 27_650, 27_200, 26_900,
            26_500, 26_200, 25_900, 25_600, 25_450, 25_100, 24_800, 43_300, 38_300, 37_900,
            37_400, 36_800, 36_500, 35_200, 34_800, 34_100, 33_600, 33_200, 32_900, 32_600, 32_180,
        ]
        let anchorDay = Dates.calendar.dateComponents([.day], from: start, to: Dates.day(bank.anchorDate)).day!
        bank.anchorBalance = points[anchorDay] * 100
        let statementDate = Dates.addDays(-1, to: start)
        var statementAccount = Account(name: "历史清算", at: statementDate, reconciled: false)
        statementAccount.archived = true

        var pay = Entry(date: Self.date("2026-11-10"), amount: 1_850_000, nature: .income,
                        accountID: bank.id, title: "工资", category: "工资奖金")
        pay.recordedAt = pay.date
        var transfer = Entry(date: Self.date("2026-11-18"), amount: 200_000, nature: .transfer, accountID: bank.id, title: "转到支付宝")
        transfer.otherAccountID = alipay.id
        var buy = Entry(date: Self.date("2026-11-22"), amount: 100_000, nature: .investBuy, accountID: bank.id, title: "基金定投")
        buy.otherAccountID = fund.id
        buy.otherDate = fund.anchorDate
        var savings = Entry(date: Self.date("2026-11-11"), amount: 500_000, nature: .transfer, accountID: bank.id, title: "先攒")
        savings.otherAccountID = statementAccount.id
        entries = [
            Entry(date: Dates.day(now), amount: 4_200, accountID: bank.id, title: "午饭", category: "吃饭"),
            buy, transfer, savings, pay
        ]

        // The five recent bills and the full chart describe different aggregates.
        // Earlier statement transfers clear on their own posting dates to supply the remaining daily movement.
        for index in points.indices.dropFirst() {
            let day = Dates.addDays(index, to: start)
            let visible = entries.filter { Dates.day($0.date) == day }.reduce(Int64(0)) { $0 + $1.delta(for: bank.id) }
            let difference = (points[index] - points[index - 1]) * 100 - visible
            if difference != 0 {
                var posting = Entry(date: difference > 0 ? statementDate : day, amount: abs(difference),
                                    nature: .transfer, accountID: difference > 0 ? statementAccount.id : bank.id,
                                    title: "清算")
                posting.source = Self.chartClearingSource
                posting.otherAccountID = difference > 0 ? bank.id : statementAccount.id
                posting.otherDate = difference > 0 ? day : nil
                entries.append(posting)
            }
        }
        return [statementAccount]
    }
    #endif
}
