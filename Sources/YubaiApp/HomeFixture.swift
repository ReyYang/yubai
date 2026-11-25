import Foundation
import YubaiCore

enum HomeFixture: Equatable {
    case home(Home)
    case budget(Budget)
    case bill(Bill, menu: Bool)

    enum Home: String { case normal, tight, over, nopay, empty, search, running, worst }
    enum Budget: String { case view, edit }
    enum Bill: String { case none, partial, expense, reimburse, income, transfer, deposit, large }

    static let current: Self? = {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        func value(_ flag: String) -> String? {
            guard let index = args.firstIndex(of: flag), args.indices.contains(index + 1) else { return nil }
            return args[index + 1]
        }
        if let mode = value("-YubaiHomeFixture").flatMap(Home.init(rawValue:)) { return .home(mode) }
        if let mode = value("-YubaiBudgetFixture").flatMap(Budget.init(rawValue:)) { return .budget(mode) }
        if let mode = value("-YubaiBillFixture").flatMap(Bill.init(rawValue:)) {
            return .bill(mode, menu: args.contains("-YubaiBillMenu"))
        }
        #endif
        return nil
    }()

    var isTight: Bool { self == .home(.tight) }
    var isSearch: Bool { self == .home(.search) }
    var isRunning: Bool { self == .home(.running) }
    var showBillMenu: Bool { if case .bill(_, let menu) = self { menu } else { false } }
    var initialRoute: TabRoute? { if case .budget = self { .formula } else { nil } }
    var editsBudget: Bool { self == .budget(.edit) }
    var now: Date {
        switch self {
        case .home(.empty), .home(.nopay): Self.day(10, time: "22:00")
        case .home(.worst): Dates.parse("2025-12-08 22:00")!
        case .bill(.income, _): Dates.parse("2025-12-09 22:00")!
        default: Self.day(23, time: "22:00")
        }
    }

    func shows(_ entry: Entry) -> Bool {
        guard case .home = self else { return true }
        return ![Self.dailySource, Self.formulaSource].contains(entry.source)
    }

    private static let dailySource = "日线样例"
    private static let formulaSource = "算式样例"

    private static func day(_ day: Int, time: String = "00:00") -> Date {
        Dates.parse(String(format: "2025-11-%02d %@", day, time))!
    }

    func makeLedger() -> (ledger: Ledger, billID: UUID?) {
        let start = Self.day(10)
        let bank = Account(name: "招行储蓄", balance: 2_000_000, at: Dates.addDays(-90, to: start))
        let credit = Account(name: "招行信用卡", kind: .credit, at: bank.anchorDate)
        let wallet = Account(name: "支付宝", kind: .cash, at: bank.anchorDate)
        let wechat = Account(name: "微信", kind: .cash, at: bank.anchorDate)
        let fund = Account(name: "基金账户", kind: .investment, at: bank.anchorDate)
        var ledger = Ledger()
        ledger.accounts = [bank, credit, wallet, wechat, fund]
        ledger.preferences.onboardingComplete = true
        ledger.cycleAnchor = .payday
        ledger.updatedAt = now
        ledger.categories = ["吃饭", "购物", "交通", "买菜", "娱乐", "咖啡", "居住", "日用", "其他",
                             "孩子兴趣班与家教", "数码与电子产品", "宠物", "订阅"].map { Category($0) }
        if let index = ledger.categories.firstIndex(where: { $0.name == "娱乐" }) { ledger.categories[index].subcategories = ["电影"] }
        if let index = ledger.categories.firstIndex(where: { $0.name == "购物" }) { ledger.categories[index].subcategories = ["数码配件"] }
        ledger.categories.append(Category("工资", income: true))
        var salary = Plan(title: "工资", amount: 1_850_000, dueDate: start, frequency: .monthly, inflow: true, category: "工资", nature: .income)
        salary.accountID = bank.id
        ledger.plans = [salary, Plan(title: "固定订阅", amount: 38_600, dueDate: Dates.parse("2025-12-09")!, category: "订阅")]
        ledger.fixedSavings = 842_000
        ledger.savingRule = .fixed(500_000)

        func add(_ title: String, _ amount: Int64, _ category: String, _ date: Date, account: Account? = nil,
                 nature: Nature = .expense, destination: Account? = nil, source: String = "手动",
                 change: (inout Entry) -> Void = { _ in }) -> Entry {
            var entry = Entry(date: date, amount: amount, nature: nature, accountID: (account ?? bank).id, title: title, category: category)
            entry.otherAccountID = destination?.id
            entry.source = source
            change(&entry)
            ledger.entries.append(entry)
            return entry
        }

        func addSalary(_ amount: Int64, source: String = Self.formulaSource) {
            _ = add("工资", amount, "工资", start, nature: .income, source: source) {
                $0.planID = salary.id
                $0.occurrence = start
            }
        }

        func movie(_ amount: Int64, personal: Int64, date: Date, named: Bool) -> Entry {
            add("电影票", amount, "娱乐", date, account: credit) {
                $0.pendingRecovery = .split
                $0.personalExpense = personal
                $0.subcategory = "电影"
                if named {
                    $0.note = "IMAX 三人"
                    $0.recoveryParticipants = [RecoveryParticipant(name: "周", amount: 2_600), RecoveryParticipant(name: "林", amount: 2_600)]
                }
            }
        }

        func spend(_ name: String, _ amount: Int64, _ category: String, _ date: Date,
                   on account: Account? = nil, reimbursable: Bool = false) {
            _ = add(name, amount, category, date, account: account) {
                if reimbursable { $0.pendingRecovery = .reimbursement }
            }
        }

        func budgets(_ amounts: [(name: String, amount: Int64, spent: Int64)], fill: Bool = false) {
            ledger.spendingParts = amounts.map { SpendingPart(name: $0.name, amount: $0.amount, categories: [$0.name]) }
            guard fill else { return }
            for row in amounts {
                let recorded = ledger.entries.filter { $0.category == row.name && $0.nature == .expense && !$0.fromReserve }
                    .reduce(Int64(0)) { $0 + Finance.spendingAmount($1, ledger: ledger) }
                if row.spent > recorded {
                    _ = add(row.name, row.spent - recorded, row.name, start, source: Self.dailySource)
                }
            }
        }

        let usualBudgets: [(String, Int64, Int64)] = [
            ("吃饭", 250_000, 126_400), ("购物", 150_000, 131_800), ("交通", 60_000, 18_750),
            ("买菜", 150_000, 98_000), ("娱乐", 65_000, 57_800), ("咖啡", 30_000, 18_600),
        ]

        switch self {
        case .budget:
            addSalary(1_850_000)
            budgets(usualBudgets, fill: true)
            _ = add("其他", 684_560 - ledger.entries.filter { $0.nature == .expense }.reduce(0) { $0 + $1.amount },
                    "其他", Self.day(23), source: Self.formulaSource)
            ledger.savingHistory = [.init(cycleStart: Dates.addMonths(-1, to: start), cycleEnd: Dates.addDays(-1, to: start),
                                          income: 1_850_000, target: 500_000, saved: 500_000, leftover: 120_430)]
            return (ledger, nil)
        case .bill(let mode, _):
            addSalary(1_850_000)
            budgets(usualBudgets)
            let entry: Entry
            switch mode {
            case .none, .partial:
                entry = movie(7_800, personal: 2_600, date: Self.day(22, time: "19:40"), named: true)
                if mode == .partial, let person = entry.recoveryParticipants?.last {
                    _ = try? EntryRecovery.receive(originalID: entry.id, participantID: person.id, into: bank.id,
                                                   in: &ledger, now: Self.day(23, time: "10:00"))
                }
            case .expense:
                entry = add("午饭", 4_200, "吃饭", Self.day(23, time: "12:30"))
                _ = add("吃饭", 126_400, "吃饭", Self.day(22), source: Self.dailySource)
            case .reimburse:
                entry = add("便利店", 15_580, "吃饭", Self.day(21, time: "21:10"), account: credit) {
                    $0.originalCurrency = .jpy
                    $0.originalAmount = 328_000
                    $0.pendingRecovery = .reimbursement
                    $0.note = "东京出差"
                }
            case .income:
                entry = add("工资", 1_850_000, "工资", Dates.day(now), nature: .income) {
                    $0.countsFromCycleStart = Dates.addDays(1, to: Dates.day(now))
                }
            case .transfer:
                entry = add("还信用卡", 321_680, "内部移动", Self.day(23, time: "09:12"),
                            nature: .repayment, destination: credit)
            case .deposit:
                var plan = Plan(title: "基金定投", amount: 100_000, dueDate: Self.day(15), frequency: .monthly, category: "内部移动", nature: .investBuy)
                plan.accountID = bank.id
                plan.otherAccountID = fund.id
                ledger.plans.append(plan)
                entry = add("基金定投", 100_000, "内部移动", Self.day(15), nature: .investBuy, destination: fund) {
                    $0.planID = plan.id
                    $0.occurrence = Self.day(15)
                }
            case .large:
                entry = add("换手机", 699_900, "购物", Self.day(23, time: "15:40"), account: credit) {
                    $0.fromReserve = true
                    $0.subcategory = "数码配件"
                }
            }
            return (ledger, entry.id)
        case .home(let mode):
            let usual = [42_000, 51_800, 48_010, 86_500, 47_600, 29_800, 54_000, 61_200, 45_500, 102_460, 38_800, 46_300, 24_310, 6_280]
            var daily = usual
            switch mode {
            case .tight: daily = [62_000, 71_800, 68_000, 106_500, 67_600, 49_800, 74_000, 81_200, 65_500, 122_460, 58_800, 66_300, 44_310, 26_280]
            case .over: daily = [72_000, 81_800, 78_000, 116_500, 77_600, 59_800, 84_000, 91_200, 75_500, 128_460, 68_800, 76_300, 54_310, 36_280]
            case .nopay: daily = [12_860]
            case .empty: daily = [0]
            case .worst: daily = usual + [0, 0, 1_299_900, 3_000, 4_000, 2_000, 0, 0, 0, 0, 0, 0, 0, 38_820, 1_550]
            default: break
            }

            switch mode {
            case .nopay:
                spend("盒马", 12_860, "买菜", Self.day(10, time: "12:00"), on: wallet)
            case .empty:
                addSalary(1_850_000, source: "手动")
                _ = add("先攒", 500_000, "内部移动", Self.day(10), nature: .investBuy, destination: fund)
            case .worst:
                spend("星巴克臻选上海烘焙工坊（南京西路店）", 6_800, "咖啡", now, reimbursable: true)
                spend("iPhone", 1_299_900, "数码与电子产品", now.addingTimeInterval(-1), on: credit)
                _ = add("成田机场免税店", 750_500, "购物", now.addingTimeInterval(-2), account: credit) {
                    $0.originalCurrency = .jpy
                    $0.originalAmount = 15_800_000
                    $0.pendingRecovery = .split
                    $0.personalExpense = 375_250
                }
                spend("打", 1, "交通", now.addingTimeInterval(-3))
                _ = add("年终奖", 100_000_000, "工资", Dates.parse("2025-09-30")!, nature: .income)
            default:
                if mode != .search {
                    spend("午饭", 4_200, "吃饭", Self.day(23, time: "12:30"))
                    spend("瑞幸", 1_680, "咖啡", Self.day(23, time: "10:00"), on: wechat)
                    spend("地铁", 400, "交通", Self.day(23, time: "08:00"), on: wallet)
                    spend("盒马", 12_860, "买菜", Self.day(22, time: "20:00"), on: wallet)
                    _ = movie(7_800, personal: 2_600, date: Self.day(22, time: "19:40"), named: true)
                    _ = add("基金定投", 100_000, "内部移动", Self.day(22, time: "08:00"), nature: .investBuy, destination: fund) {
                        $0.intoFixedSavings = false
                    }
                    _ = add("便利店", 2_755, "吃饭", Self.day(21, time: "21:00"), account: credit) {
                        $0.originalCurrency = .jpy
                        $0.originalAmount = 58_000
                    }
                    spend("Apple One", 6_800, "订阅", Self.day(21, time: "20:00"), on: credit)
                    spend("晚饭", 9_600, "吃饭", Self.day(21, time: "19:00"), on: wechat)
                }
                spend("打车", 3_650, "交通", Self.day(22, time: "18:00"), on: credit, reimbursable: true)
                if mode == .search {
                    spend("打车", 4_200, "交通", Self.day(15, time: "17:00"), on: wallet)
                    spend("打车", 3_400, "交通", Self.day(12, time: "17:00"), on: wallet)
                }
            }

            let homeBudgets: [(String, Int64, Int64)]
            switch mode {
            case .tight: homeBudgets = [("吃饭", 250_000, 226_400), ("购物", 150_000, 154_200), ("交通", 60_000, 48_750)]
            case .over: homeBudgets = [("吃饭", 250_000, 262_600), ("购物", 150_000, 184_200), ("交通", 60_000, 54_750)]
            case .nopay, .empty: homeBudgets = usualBudgets.prefix(3).map { ($0.0, $0.1, 0) }
            case .worst: homeBudgets = [("孩子兴趣班与家教", 1_300_000, 52_000), ("数码与电子产品", 150_000, 1_299_900), ("宠物", 60_000, 60_000)]
            default: homeBudgets = Array(usualBudgets.prefix(3))
            }
            budgets(homeBudgets)
            // Distribute the unseen expenses across earlier days so the canvas's
            // daily series and budget amounts are derived from the same ledger.
            var remaining = homeBudgets.map { row in
                max(0, row.2 - ledger.entries.filter { $0.category == row.0 && $0.nature == .expense }.reduce(0) { $0 + $1.amount })
            }
            for (index, desired) in daily.enumerated() {
                let date = Dates.addDays(index, to: start)
                if date > now { break }
                let posted = ledger.entries.filter { Dates.day($0.date) == date && $0.nature == .expense }.reduce(0) { $0 + $1.amount }
                var balance = max(0, Int64(desired) - posted)
                for category in remaining.indices where balance > 0 && remaining[category] > 0 {
                    let value = min(balance, remaining[category])
                    _ = add(homeBudgets[category].0, value, homeBudgets[category].0, date, source: Self.dailySource)
                    remaining[category] -= value
                    balance -= value
                }
                if balance > 0 { _ = add("其他", balance, "其他", date, source: Self.dailySource) }
            }
            if mode != .nopay && mode != .empty {
                let result: Int64 = mode == .tight ? 126_840 : mode == .over ? -32_650 : mode == .worst ? 12_840_650 : 626_840
                let expenses = ledger.entries.filter { $0.nature == .expense && $0.date >= start }.reduce(Int64(0)) { $0 + $1.amount }
                addSalary(expenses + result + 500_000 + 38_600)
            }
            return (ledger, nil)
        }
    }
}
