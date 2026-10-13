import Foundation

public enum YubaiError: LocalizedError, Equatable {
    case invalid(String)
    public var errorDescription: String? { if case let .invalid(message) = self { return message }; return nil }
}

public enum Money {
    public static let limit: Int64 = 99_999_999_999_99
    public static func parse(_ input: String, allowNegative: Bool = false) throws -> Int64 {
        var s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        for symbol in ["¥", "￥", "CNY", "RMB", "元", " "] { s = s.replacingOccurrences(of: symbol, with: "") }
        s = s.replacingOccurrences(of: "，", with: ",")
        if s.contains(",") {
            guard s.range(of: #"^[+-]?\d{1,3}(,\d{3})+(\.\d{1,2})?$"#, options: .regularExpression) != nil else { throw YubaiError.invalid("金额的千位分隔格式不正确。") }
            s = s.replacingOccurrences(of: ",", with: "")
        }
        s = s.replacingOccurrences(of: "−", with: "-").replacingOccurrences(of: "＋", with: "+")
        guard s.range(of: #"^[+-]?\d{1,12}(\.\d{1,2})?$"#, options: .regularExpression) != nil,
              let decimal = Decimal(string: s, locale: Locale(identifier: "en_US_POSIX")) else {
            throw YubaiError.invalid("请输入有效金额，最多保留两位小数。")
        }
        let cents = NSDecimalNumber(decimal: decimal * 100).int64Value
        guard abs(cents) <= limit, allowNegative || cents >= 0 else { throw YubaiError.invalid("金额超出范围或不能为负数。") }
        return cents
    }
    public static func text(_ cents: Int64, currency: Bool = true) -> String {
        let f = NumberFormatter(); f.locale = Locale(identifier: "zh_CN")
        f.numberStyle = currency ? .currency : .decimal; f.currencySymbol = "¥"
        f.minimumFractionDigits = 2; f.maximumFractionDigits = 2
        return f.string(from: NSDecimalNumber(decimal: Decimal(cents) / 100)) ?? "0.00"
    }
    public static func input(_ cents: Int64) -> String { NSDecimalNumber(decimal: Decimal(cents) / 100).stringValue }
}

public enum Dates {
    public static var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = .current; return c }
    public static func day(_ d: Date) -> Date { calendar.startOfDay(for: d) }
    public static func addDays(_ n: Int, to date: Date) -> Date { calendar.date(byAdding: .day, value: n, to: date)! }
    public static func addMonths(_ n: Int, to date: Date) -> Date { calendar.date(byAdding: .month, value: n, to: date)! }
    public static func text(_ d: Date, time: Bool = false) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_CN"); f.dateFormat = time ? "yyyy-MM-dd HH:mm" : "yyyy-MM-dd"; return f.string(from: d)
    }
    public static func parse(_ input: String) -> Date? {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        for format in ["yyyy-MM-dd HH:mm:ss", "yyyy/MM/dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy/MM/dd HH:mm", "yyyy-MM-dd", "yyyy/MM/dd", "yyyy年MM月dd日 HH:mm:ss", "yyyyMMdd"] {
            let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = format; f.isLenient = false
            if let d = f.date(from: value), f.string(from: d) == value { return d }
        }
        return ISO8601DateFormatter().date(from: value)
    }
    public static func excel(_ serial: Double, date1904: Bool = false) -> Date? {
        guard serial.isFinite, serial >= 1, serial <= 100000 else { return nil }
        var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let base = utc.date(from: DateComponents(year: date1904 ? 1904 : 1899, month: date1904 ? 1 : 12, day: date1904 ? 1 : 30))!
        let absolute = base.addingTimeInterval((serial * 86400).rounded())
        let parts = utc.dateComponents([.year, .month, .day, .hour, .minute, .second], from: absolute)
        return calendar.date(from: parts)
    }
}

public enum AccountKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case cash, bank, credit, investment, receivable
    public var id: String { rawValue }
    public var label: String { switch self { case .cash: "零钱与现金"; case .bank: "银行卡"; case .credit: "信用与借款"; case .investment: "投资"; case .receivable: "借出待收" } }
    public var symbol: String { switch self { case .cash: "wallet.bifold"; case .bank: "building.columns"; case .credit: "creditcard"; case .investment: "chart.line.uptrend.xyaxis"; case .receivable: "arrow.down.left.circle" } }
}
public struct Account: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID(); public var name: String; public var kind: AccountKind
    public var anchorBalance: Int64; public var anchorDate: Date
    public var reconciled: Bool; public var archived = false
    public var note = ""; public var creditLimit: Int64 = 0
    public init(name: String, kind: AccountKind = .bank, balance: Int64 = 0, at: Date = Date(), reconciled: Bool = true) {
        self.name = name; self.kind = kind; self.anchorBalance = balance; self.anchorDate = at; self.reconciled = reconciled
    }
}

public enum Nature: String, Codable, CaseIterable, Identifiable, Sendable {
    case expense, income, transfer, repayment, borrow, lend, loanReturn, loanRecovery, refund, contribution, investBuy, investSell, adjustmentIn, adjustmentOut, unknownIn, unknownOut
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .expense: "支出"; case .income: "收入"; case .transfer: "自有账户转账"; case .repayment: "信用还款"
        case .borrow: "借入本金"; case .lend: "借出本金"; case .loanReturn: "归还借款"; case .loanRecovery: "收回借款"
        case .refund: "消费退款"; case .contribution: "收到分摊"; case .investBuy: "投资申购"; case .investSell: "投资赎回"
        case .adjustmentIn: "调增余额"; case .adjustmentOut: "调减余额"; case .unknownIn: "待明确流入"; case .unknownOut: "待明确流出"
        }
    }
    public var inflow: Bool { [.income, .borrow, .loanRecovery, .refund, .contribution, .investSell, .adjustmentIn, .unknownIn].contains(self) }
    public var paired: Bool { [.transfer, .repayment, .investBuy, .investSell, .borrow, .lend, .loanReturn, .loanRecovery].contains(self) }
    public var uncertain: Bool { self == .unknownIn || self == .unknownOut }
    public var symbol: String {
        switch self { case .income: "arrow.down.left"; case .expense: "arrow.up.right"; case .refund: "arrow.uturn.backward"; case .contribution: "person.2"; default: paired ? "arrow.left.arrow.right" : "circle.dotted" }
    }
}

public struct Entry: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID(); public var date: Date; public var amount: Int64
    public var nature: Nature; public var accountID: UUID; public var otherAccountID: UUID?
    public var title: String; public var category: String; public var note: String = ""
    public var source: String = "手动"; public var externalID: String = ""; public var batchID: UUID?
    public var sourceIdentity: String = ""
    public var sourceRow: Int?; public var fingerprint: String = ""
    public var userEdited = false; public var deletedAt: Date?
    public var relatedEntryID: UUID?; public var planID: UUID?; public var occurrence: Date?
    public var rentID: UUID?; public var rentPeriod: Date?
    public var attachmentID: UUID?; public var classificationReason: String = "手动选择"
    public var otherDate: Date?; public var mergedIntoID: UUID?; public var personalExpense: Int64?
    public init(date: Date = Date(), amount: Int64, nature: Nature = .expense, accountID: UUID, title: String, category: String = "其他支出") {
        self.date = date; self.amount = amount; self.nature = nature; self.accountID = accountID; self.title = title; self.category = category
    }
    public func delta(for account: UUID) -> Int64 {
        if accountID == account { return nature.inflow ? amount : -amount }
        if nature.paired && otherAccountID == account { return nature.inflow ? -amount : amount }
        return 0
    }
    public func postingDate(for account: UUID) -> Date { otherAccountID == account ? (otherDate ?? date) : date }
}

public enum Frequency: String, Codable, CaseIterable, Identifiable, Sendable {
    case once, weekly, monthly, quarterly, yearly
    public var id: String { rawValue }
    public var label: String { switch self { case .once: "一次"; case .weekly: "每周"; case .monthly: "每月"; case .quarterly: "每季"; case .yearly: "每年" } }
    public func advance(_ original: Date, by count: Int) -> Date {
        switch self { case .once: return original; case .weekly: return Dates.addDays(7 * count, to: original); case .monthly: return Dates.addMonths(count, to: original); case .quarterly: return Dates.addMonths(3 * count, to: original); case .yearly: return Dates.addMonths(12 * count, to: original) }
    }
}
public struct Plan: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID(); public var title: String; public var amount: Int64; public var dueDate: Date
    public var frequency: Frequency; public var inflow: Bool; public var accountID: UUID?
    public var category: String; public var nature: Nature; public var active = true
    public var endDate: Date?; public var note = ""
    public init(title: String, amount: Int64, dueDate: Date, frequency: Frequency = .once, inflow: Bool = false, category: String = "其他支出", nature: Nature = .expense) {
        self.title = title; self.amount = amount; self.dueDate = dueDate; self.frequency = frequency; self.inflow = inflow; self.category = category; self.nature = nature
    }
}
public struct Goal: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID(); public var title: String; public var target: Int64; public var reserved: Int64
    public var dueDate: Date?; public var note = ""
    public init(title: String, target: Int64, reserved: Int64 = 0, dueDate: Date? = nil) { self.title = title; self.target = target; self.reserved = reserved; self.dueDate = dueDate }
}
public struct Rent: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID(); public var title: String; public var monthlyTotal: Int64; public var personalShare: Int64
    public var startDate: Date; public var nextDueDate: Date; public var monthsPerPayment: Int
    public var receiveDay: Int; public var accountID: UUID?; public var active = true; public var note = ""
    public var endDate: Date?
    public init(title: String = "合租房租", monthlyTotal: Int64, personalShare: Int64, startDate: Date, nextDueDate: Date, monthsPerPayment: Int = 3, receiveDay: Int = 1) {
        self.title = title; self.monthlyTotal = monthlyTotal; self.personalShare = personalShare; self.startDate = startDate; self.nextDueDate = nextDueDate; self.monthsPerPayment = monthsPerPayment; self.receiveDay = receiveDay
    }
}
public struct Category: Codable, Identifiable, Equatable, Sendable {
    public var name: String; public var symbol: String; public var income: Bool
    public var id: String { name }
    public init(_ name: String, _ symbol: String = "square.grid.2x2", income: Bool = false) { self.name = name; self.symbol = symbol; self.income = income }
    public static let defaults: [Category] = [
        .init("餐饮", "fork.knife"), .init("居住", "house"), .init("交通", "tram"), .init("日用购物", "bag"),
        .init("医疗健康", "cross.case"), .init("学习工作", "book"), .init("娱乐旅行", "sparkles"), .init("人情家庭", "gift"),
        .init("利息手续费", "percent"), .init("其他支出", "ellipsis"), .init("工资奖金", "briefcase", income: true),
        .init("兼职劳务", "hammer", income: true), .init("礼金赠与", "gift", income: true), .init("投资收益", "chart.line.uptrend.xyaxis", income: true), .init("其他收入", "ellipsis", income: true)
    ]
}
public struct Rule: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID(); public var keyword: String; public var category: String; public var nature: Nature?; public var enabled = true
    public init(keyword: String, category: String, nature: Nature? = nil) { self.keyword = keyword; self.category = category; self.nature = nature }
}
public struct Attachment: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID(); public var name: String; public var data: Data; public var createdAt = Date()
    public init(name: String, data: Data) { self.name = name; self.data = data }
}
public struct ImportBatch: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID(); public var filename: String; public var importedAt = Date()
    public var importedCount: Int; public var duplicateCount: Int; public var skippedCount: Int
    public var attachmentID: UUID?; public var undoneAt: Date?
    public init(filename: String, importedCount: Int, duplicateCount: Int, skippedCount: Int) { self.filename = filename; self.importedCount = importedCount; self.duplicateCount = duplicateCount; self.skippedCount = skippedCount }
}
public struct Preferences: Codable, Equatable, Sendable {
    public var horizonDays = 90; public var emergencyReserve: Int64 = 0
    public var dailyLiving: Int64 = 0; public var hideAmounts = false; public var lockEnabled = false
    public var appearance = "system"; public var purchaseValues = "为长期有用和真正喜欢的事物花钱"
    public var localAIEnabled = true; public var onboardingComplete = false
    public init() {}
}
public struct AdviceRecord: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID(); public var createdAt = Date(); public var title: String; public var amount: Int64
    public var result: String; public var note: String
    public init(title: String, amount: Int64, result: String, note: String) { self.title = title; self.amount = amount; self.result = result; self.note = note }
}
public struct Ledger: Codable, Equatable, Sendable {
    public var schema = 1; public var id = UUID(); public var updatedAt = Date()
    public var isSample = false
    public var accounts: [Account] = []; public var entries: [Entry] = []; public var plans: [Plan] = []
    public var goals: [Goal] = []; public var rents: [Rent] = []; public var rules: [Rule] = []
    public var categories = Category.defaults; public var imports: [ImportBatch] = []; public var attachments: [Attachment] = []
    public var categoryAliases: [String: String] = [:]
    public var advice: [AdviceRecord] = []; public var preferences = Preferences()
    public init() {}
    public var activeEntries: [Entry] { entries.filter { $0.deletedAt == nil } }
    public func accountName(_ id: UUID?) -> String { accounts.first { $0.id == id }?.name ?? "未指定账户" }
    public func resolveCategory(_ category: String) -> String { categoryAliases[category] ?? category }
    public func validate() throws {
        guard schema == 1 else { throw YubaiError.invalid("这个账本来自更新版本，请先更新余白。") }
        guard accounts.count <= 1000, entries.count <= 200_000, plans.count <= 1000, rents.count <= 100,
              goals.count <= 1000, attachments.count <= 5000 else { throw YubaiError.invalid("账本超出安全容量，请分卷备份。") }
        guard Set(accounts.map(\.id)).count == accounts.count, Set(entries.map(\.id)).count == entries.count,
              Set(plans.map(\.id)).count == plans.count, Set(rents.map(\.id)).count == rents.count,
              Set(goals.map(\.id)).count == goals.count, Set(rules.map(\.id)).count == rules.count,
              Set(imports.map(\.id)).count == imports.count, Set(advice.map(\.id)).count == advice.count,
              Set(attachments.map(\.id)).count == attachments.count else { throw YubaiError.invalid("账本包含重复标识，无法安全读取。") }
        let ids = Set(accounts.map(\.id)); let categoryNames = categories.map(\.name)
        func dateValid(_ value: Date) -> Bool { (-2_208_988_800...7_258_118_400).contains(value.timeIntervalSince1970) }
        guard Set(categoryNames).count == categoryNames.count else { throw YubaiError.invalid("分类名称不能重复。") }
        for a in accounts { guard !a.name.trimmingCharacters(in: .whitespaces).isEmpty, a.anchorBalance >= -Money.limit, a.anchorBalance <= Money.limit, (0...Money.limit).contains(a.creditLimit), dateValid(a.anchorDate) else { throw YubaiError.invalid("账户信息无效。") } }
        for e in entries {
            guard ids.contains(e.accountID), e.amount > 0, e.amount <= Money.limit, !e.title.isEmpty,
                  dateValid(e.date), e.otherDate.map(dateValid) ?? true else { throw YubaiError.invalid("交易金额、日期或账户无效。") }
            if let other = e.otherAccountID { guard ids.contains(other), other != e.accountID, e.nature.paired else { throw YubaiError.invalid("转账的两个账户必须不同且存在。") } }
            if e.nature.paired, let other = e.otherAccountID, let kind = accounts.first(where: { $0.id == other })?.kind, e.nature != .transfer {
                let required: AccountKind = [.borrow, .loanReturn, .repayment].contains(e.nature) ? .credit : ([.lend, .loanRecovery].contains(e.nature) ? .receivable : .investment)
                guard kind == required, accounts.contains(where: { $0.id == e.accountID && ($0.kind == .cash || $0.kind == .bank) }) else { throw YubaiError.invalid("\(e.nature.label)需要把收付款账户关联到“\(required.label)”账户，请核对两边账户类型。") }
            }
            if e.mergedIntoID != nil && e.deletedAt == nil { throw YubaiError.invalid("已合并的转账证据不能单独恢复，否则会重复记账。请撤销合并或恢复合并前版本。") }
            if let personal = e.personalExpense { guard personal >= 0, personal <= e.amount else { throw YubaiError.invalid("个人承担金额不能超过本笔付款。") } }
            if e.deletedAt == nil, let pID = e.planID {
                guard let p = plans.first(where: { $0.id == pID }), e.occurrence != nil, e.nature == p.nature else { throw YubaiError.invalid("这笔记录已关联资金安排，性质需要与安排一致；请先解除关联再修改。") }
            }
            if e.deletedAt == nil, let rID = e.rentID {
                guard rents.contains(where: { $0.id == rID }), e.rentPeriod != nil, e.nature == .expense || e.nature == .contribution else { throw YubaiError.invalid("房租记录需要保留支出或收到分摊的性质；请先解除关联再修改。") }
            }
        }
        let entriesByID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
        let refunds = Dictionary(grouping: activeEntries.filter { $0.nature == .refund && $0.relatedEntryID != nil }, by: { $0.relatedEntryID! })
        for (id, rows) in refunds {
            guard let original = entriesByID[id], original.deletedAt == nil, original.nature == .expense,
                  rows.reduce(Int64(0), { $0 + $1.amount }) <= original.amount else { throw YubaiError.invalid("关联退款超过原支出，或原支出已被移除。请先核对退款关联。") }
        }
        for p in plans { guard p.amount > 0, p.amount <= Money.limit, !p.title.isEmpty, dateValid(p.dueDate), p.endDate.map({ dateValid($0) && $0 >= p.dueDate }) ?? true else { throw YubaiError.invalid("资金安排信息无效。") } }
        guard plans.reduce(Int64(0), { $0 + $1.amount }) <= Money.limit else { throw YubaiError.invalid("所有安排总额超出安全计算范围。") }
        for g in goals { guard g.target > 0, g.target <= Money.limit, g.reserved >= 0, g.reserved <= g.target, !g.title.isEmpty else { throw YubaiError.invalid("目标金额或预留金额无效。") } }
        for r in rents { guard r.monthlyTotal > 0, r.monthlyTotal <= Money.limit / 12, r.personalShare >= 0, r.personalShare <= r.monthlyTotal, (1...12).contains(r.monthsPerPayment), (1...28).contains(r.receiveDay), dateValid(r.startDate), dateValid(r.nextDueDate), r.endDate.map({ dateValid($0) && $0 >= r.startDate }) ?? true else { throw YubaiError.invalid("房租金额、分摊或周期无效。") } }
        guard (7...366).contains(preferences.horizonDays), preferences.emergencyReserve >= 0, preferences.emergencyReserve <= Money.limit,
              preferences.dailyLiving >= 0, preferences.dailyLiving <= Money.limit / 366 else { throw YubaiError.invalid("资金偏好数值无效。") }
    }
}
