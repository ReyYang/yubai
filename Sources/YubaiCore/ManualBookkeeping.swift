import Foundation

/// Decimal, integer-cent arithmetic shared by the manual keypad and its save action.
public struct EntryKeypad: Equatable, Sendable {
    public private(set) var expression = "0"
    public init() {}
    public var amount: Int64? { try? Self.evaluate(expression) }
    public var canSave: Bool { amount.map { $0 > 0 && $0 <= Money.limit } ?? false }
    public var resultText: String { Money.input(amount ?? 0) }
    public var displayText: String {
        expression.dropFirst().contains(where: { $0 == "+" || $0 == "-" }) ? resultText : expression
    }
    public var pendingOperator: String? {
        guard expression.count > 1, let last = expression.last, last == "+" || last == "-" else { return nil }
        return last == "-" ? "−" : "+"
    }
    public var expressionText: String? {
        guard expression.dropFirst().contains(where: { $0 == "+" || $0 == "-" }) else { return nil }
        let first = expression.prefix(1).replacingOccurrences(of: "-", with: "−")
        let rest = expression.dropFirst().replacingOccurrences(of: "+", with: " + ").replacingOccurrences(of: "-", with: " − ")
        return (first + rest).trimmingCharacters(in: .whitespaces)
    }
    public mutating func reset() { expression = "0" }
    @discardableResult public mutating func resolve() -> Int64? {
        guard let amount else { return nil }
        expression = Money.input(amount); return amount
    }
    public mutating func press(_ key: String) {
        if key == "⌫" { expression = expression.count > 1 ? String(expression.dropLast()) : "0"; return }
        let key = key == "−" ? "-" : key
        if key == "+" || key == "-" {
            var next = expression
            if next.last == "+" || next.last == "-" { next.removeLast() }
            guard (try? Self.evaluate(next)) != nil else { return }
            expression = next + key; return
        }
        guard key == "." || (key.count == 1 && key.first.map { "0123456789".contains($0) } == true) else { return }
        let start = expression.lastIndex(where: { $0 == "+" || $0 == "-" }).map { expression.index(after: $0) } ?? expression.startIndex
        var operand = String(expression[start...])
        if key == "." {
            guard !operand.contains(".") else { return }
            operand = (operand.isEmpty ? "0" : operand) + "."
        } else {
            if let dot = operand.firstIndex(of: "."), operand.distance(from: dot, to: operand.endIndex) > 2 { return }
            operand = operand == "0" ? key : operand + key
        }
        let next = String(expression[..<start]) + operand
        guard (try? Self.evaluate(next)) != nil else { return }
        expression = next
    }
    public static func evaluate(_ expression: String) throws -> Int64 {
        let text = expression.replacingOccurrences(of: "−", with: "-")
        var total: Int64 = 0; var operand = ""; var sign: Int64 = 1
        func value(_ input: String) throws -> Int64 {
            guard !input.isEmpty else { throw YubaiError.invalid("请输入金额。") }
            return try Money.parse(input.hasSuffix(".") ? String(input.dropLast()) : input)
        }
        for (index, char) in text.enumerated() {
            if char == "+" || char == "-" {
                if index == 0 && char == "-" { sign = -1; continue }
                total += try value(operand) * sign
                guard (-Money.limit...Money.limit).contains(total) else { throw YubaiError.invalid("金额超出范围。") }
                operand = ""; sign = char == "+" ? 1 : -1
            } else {
                guard "0123456789.".contains(char) else { throw YubaiError.invalid("请输入有效金额。") }
                operand.append(char)
            }
        }
        if !operand.isEmpty { total += try value(operand) * sign }
        guard !text.isEmpty, (-Money.limit...Money.limit).contains(total) else { throw YubaiError.invalid("金额超出范围。") }
        return total
    }
}

public enum ManualBookkeeping {
    public static func defaults(for nature: Nature) -> [String] {
        if nature == .transfer { return ["内部移动"] }
        let names = nature.inflow ? ["工资奖金", "兼职劳务", "礼金赠与", "投资收益", "其他收入"] : ["餐饮", "交通", "购物", "娱乐旅行", "居住"]
        return names.filter { name in Category.defaults.contains { $0.name == name && $0.income == nature.inflow } }
    }
    public static func categories(in ledger: Ledger, nature: Nature, frequentOnly: Bool = false) -> [String] {
        var counts: [String: Int] = [:]; var latest: [String: Date] = [:]
        for entry in ledger.entries where entry.deletedAt == nil && entry.nature == nature && !entry.category.isEmpty && entry.category != "待整理" {
            let category = CategoryMigration.canonical(ledger.resolveCategory(entry.category)).category
            counts[category, default: 0] += 1
            latest[category] = max(latest[category] ?? .distantPast, entry.date)
        }
        let ranked = counts.keys.sorted {
            if counts[$0] != counts[$1] { return counts[$0, default: 0] > counts[$1, default: 0] }
            if latest[$0] != latest[$1] { return latest[$0, default: .distantPast] > latest[$1, default: .distantPast] }
            return $0 < $1
        }
        var seen = Set<String>(); var result: [String] = []
        let all = ranked + defaults(for: nature) + (frequentOnly ? [] : ledger.categories.filter { $0.income == nature.inflow }.map(\.name))
        for name in all where seen.insert(name).inserted { result.append(name) }
        return frequentOnly ? Array(result.prefix(5)) : result
    }
    public static func guessCategory(_ purpose: String, nature: Nature, in ledger: Ledger) -> String? {
        guard nature != .transfer else { return "内部移动" }
        let key = CategoryMemory.key(purpose)
        guard !key.isEmpty else { return nil }
        if let remembered = ledger.categoryMemory[key] { return ledger.resolveCategory(remembered) }
        let rules: [(String, [String])] = nature.inflow ? [
            ("工资奖金", ["工资", "薪水", "薪资"]), ("工资奖金", ["奖金", "年终奖"]), ("兼职劳务", ["兼职", "稿费"])
        ] : [
            ("餐饮", ["早饭", "早餐", "午饭", "午餐", "晚饭", "晚餐", "吃饭", "外卖", "咖啡", "奶茶", "餐厅"]),
            ("交通", ["打车", "出租车", "滴滴", "地铁", "公交", "车票", "加油"]),
            ("购物", ["日用", "纸巾", "洗衣", "洗发", "超市", "罗森"]),
            ("购物", ["买衣", "衣服", "买鞋", "购物", "淘宝", "京东"]),
            ("娱乐旅行", ["电影", "游戏", "演唱会", "娱乐"])
        ]
        return rules.first { $0.1.contains(where: purpose.contains) }?.0
    }
    public static func defaultAccount(in ledger: Ledger) -> Account? {
        let accounts = ledger.accounts.filter { !$0.archived }
        let ids = Set(accounts.map(\.id))
        if let recent = ledger.entries.lazy.filter({ $0.deletedAt == nil && $0.recordedAt != nil && ids.contains($0.accountID) }).max(by: { $0.recordedAt! < $1.recordedAt! }) {
            return accounts.first { $0.id == recent.accountID }
        }
        return accounts.first { $0.kind == .cash || $0.kind == .bank } ?? accounts.first
    }
    public static func entryDate(for day: Date, now: Date) -> Date {
        Dates.calendar.isDate(day, inSameDayAs: now) ? now : Dates.calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day)!
    }
    public static func change(amount: Int64, nature: Nature, accountID: UUID, otherAccountID: UUID? = nil,
                              day: Date, purpose: String, category: String, link: (planID: UUID, occurrence: Date)? = nil, now: Date = Date()) throws -> ChangeSet {
        guard amount > 0, amount <= Money.limit, Dates.day(day) <= Dates.day(now) else { throw YubaiError.invalid("请核对金额和日期。") }
        if nature == .transfer { guard let otherAccountID, otherAccountID != accountID else { throw YubaiError.invalid("转账的两个账户必须不同。") } }
        let purpose = purpose.trimmingCharacters(in: .whitespacesAndNewlines)
        var draft = EntryDraft(date: entryDate(for: day, now: now), amount: amount, amountConfirmed: true,
                               nature: nature, accountID: accountID, title: purpose.isEmpty ? category : purpose,
                               category: category, purpose: purpose.isEmpty ? nil : purpose)
        draft.otherAccountID = nature == .transfer ? otherAccountID : nil
        draft.planID = link?.planID; draft.occurrence = link?.occurrence
        var change = ChangeSet(source: "手动", reason: "记一笔", items: [.addEntry(draft)])
        change.createdAt = now; return change
    }
    public static func available(after change: ChangeSet, in ledger: Ledger, now: Date = Date()) throws -> Int64 {
        var preview = ledger; try change.apply(to: &preview)
        return Finance.funds(preview, now: now).available
    }
    public static func edit(_ edited: Entry, in ledger: inout Ledger) throws {
        guard let index = ledger.entries.firstIndex(where: { $0.id == edited.id && $0.deletedAt == nil }) else { throw YubaiError.invalid("记录已移除。") }
        let original = ledger.entries[index]
        var next = ledger; var entry = edited
        entry.id = original.id; entry.source = original.source; entry.recordedAt = original.recordedAt
        entry.userEdited = true
        if entry.amount != original.amount { entry.personalExpense = nil; LedgerOperations.recordPersonalShare(&entry, ledger: next) }
        if entry.subcategory != original.subcategory || entry.category != original.category {
            if entry.category != original.category && entry.subcategory == original.subcategory {
                entry.subcategory = nil; entry.subcategoryUserEdited = false
                SubcategoryClassifier.classify(&entry, ledger: next)
            } else { entry.subcategoryUserEdited = true }
            if let sub = entry.subcategory, !SubcategoryClassifier.valid(.init(category: entry.category, subcategory: sub), in: next, nature: entry.nature) { throw YubaiError.invalid("这个小项不属于该主项。") }
            if entry.subcategory == nil { for key in SubcategoryClassifier.keys(entry) { next.subcategoryMemory.removeValue(forKey: key) } }
            else { SubcategoryClassifier.remember(entry, in: &next) }
        }
        next.entries[index] = entry
        LedgerOperations.syncLinkedRefundCategories(in: &next)
        CategoryMemory.remember(entry, in: &next)
        try next.validate(); ledger = next
    }
    public static func dayLabel(_ day: Date, now: Date = Date(), includeTodayDate: Bool = false) -> String {
        let c = Dates.calendar
        let date = "\(c.component(.month, from: day))月\(c.component(.day, from: day))日"
        if c.isDate(day, inSameDayAs: now) { return includeTodayDate ? "今天 · " + date : "今天" }
        if c.isDate(day, inSameDayAs: Dates.addDays(-1, to: now)) { return includeTodayDate ? "昨天 · " + date : "昨天" }
        return date
    }
}

public struct EntryDay: Identifiable, Sendable {
    public var id: Date { date }; public var date: Date; public var entries: [Entry]; public var net: Int64
    public var spending: Int64 = 0
}
public struct EntryMonth: Identifiable, Sendable {
    public var id: Date { date }; public var date: Date; public var days: [EntryDay]; public var spending: Int64; public var income: Int64
}
public struct TodayEntries: Equatable, Sendable {
    public var count = 0; public var net: Int64 = 0; public var latest: Entry?
    public init(in ledger: Ledger, now: Date = Date()) {
        let start = Dates.day(now); let end = Dates.addDays(1, to: start)
        for entry in ledger.entries where entry.deletedAt == nil && entry.date >= start && entry.date < end {
            count += 1; net += entry.nature.inflow ? entry.amount : -entry.amount
            if latest == nil || (entry.recordedAt ?? entry.date) > (latest!.recordedAt ?? latest!.date) { latest = entry }
        }
    }
}
/// One pass over the store's cached descending entries. No ledger scans per day or row.
public enum EntryTimeline {
    public enum Filter: String, CaseIterable, Sendable {
        case all = "全部", expense = "支出", income = "收入", uncategorized = "没分类"
        public func includes(_ entry: Entry) -> Bool {
            switch self {
            case .all: true
            case .expense: entry.nature == .expense
            case .income: entry.nature == .income
            case .uncategorized: EntryTimeline.isUncategorized(entry)
            }
        }
    }
    public static func isUncategorized(_ entry: Entry) -> Bool {
        entry.hasNoCaptureCategory || entry.category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || entry.category == Classification.pendingCategory
    }
    public static func months(sortedEntries: [Entry], ledger: Ledger, search: String = "", filter: Filter = .all) -> [EntryMonth] {
        let accounts = Dictionary(uniqueKeysWithValues: ledger.accounts.map { ($0.id, $0.name) })
        let rents = Dictionary(uniqueKeysWithValues: ledger.rents.map { ($0.id, $0) })
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let formatter = NumberFormatter(); formatter.locale = Locale(identifier: "zh_CN"); formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2; formatter.maximumFractionDigits = 2
        let calendar = Dates.calendar
        var dayInterval: DateInterval?; var monthInterval: DateInterval?
        var result: [EntryMonth] = []
        for entry in sortedEntries where entry.deletedAt == nil && filter.includes(entry) {
            if !query.isEmpty {
                let amount = formatter.string(from: NSDecimalNumber(decimal: Decimal(entry.amount) / 100)) ?? ""
                let signed = (entry.nature.inflow ? "+" : "−") + amount
                let category = ledger.resolveCategory(entry.category)
                let displayCategory = isUncategorized(entry) ? "没分类" : Classification.displayCategory(category)
                let fields = [entry.title, entry.purpose ?? "", entry.note, entry.category, category, displayCategory, accounts[entry.accountID] ?? "", entry.otherAccountID.flatMap { accounts[$0] } ?? "", Money.input(entry.amount), amount, signed, signed.replacingOccurrences(of: "−", with: "-"), "¥" + amount]
                guard fields.contains(where: { $0.localizedCaseInsensitiveContains(query) }) else { continue }
            }
            if dayInterval.map({ entry.date >= $0.start && entry.date < $0.end }) != true {
                dayInterval = calendar.dateInterval(of: .day, for: entry.date)
            }
            if monthInterval.map({ entry.date >= $0.start && entry.date < $0.end }) != true {
                monthInterval = calendar.dateInterval(of: .month, for: entry.date)
            }
            guard let day = dayInterval?.start, let month = monthInterval?.start else { continue }
            if result.last?.date != month { result.append(EntryMonth(date: month, days: [], spending: 0, income: 0)) }
            let m = result.count - 1
            if result[m].days.last?.date != day { result[m].days.append(EntryDay(date: day, entries: [], net: 0)) }
            let d = result[m].days.count - 1
            result[m].days[d].entries.append(entry)
            result[m].days[d].net += entry.nature.inflow ? entry.amount : -entry.amount
            let spending = Finance.spendingAmount(entry, rent: entry.rentID.flatMap { rents[$0] })
            result[m].days[d].spending += spending
            result[m].spending += spending
            if entry.nature == .income { result[m].income += entry.amount }
        }
        return result
    }
    public static func metadata(_ entry: Entry, accountNames: [UUID: String]) -> String {
        let account = accountNames[entry.accountID] ?? "已移除账户"
        if [.transfer, .repayment].contains(entry.nature), let other = entry.otherAccountID {
            return account + " → " + (accountNames[other] ?? "已移除账户") + " · 不算支出"
        }
        let parts = Dates.calendar.dateComponents([.hour, .minute], from: entry.date)
        let time = (parts.hour == 0 && parts.minute == 0) ? "" : String(format: "%02d:%02d · ", parts.hour ?? 0, parts.minute ?? 0)
        return time + entry.category + " · " + account
    }
}

public enum FixedFlows {
    public static func occurrences(in ledger: Ledger, adding plan: Plan? = nil, now: Date = Date()) -> [Occurrence] {
        var preview = ledger
        if let plan { preview.plans.append(plan) }
        let repayments = Set(preview.plans.filter { $0.nature == .repayment }.map(\.id))
        return Finance.occurrences(in: preview, now: now, days: 90).filter { !($0.planID.map { repayments.contains($0) } ?? false) }
    }
}

public struct FixedFlowArrangement: Identifiable, Sendable {
    public let id: UUID; public let title: String; public let detail: String; public let amount: Int64; public let inflow: Bool; public let canEnd: Bool
    public var paidCount: Int = 0; public var total: Int? = nil
    public var stoppedAt: Date? = nil
    public var pending: [Occurrence] = []
    public var pendingAmount: Int64 { pending.reduce(0) { $0 + $1.amount } }
    public static func stopped(in ledger: Ledger, now: Date = Date()) -> [Self] {
        let payments = FixedFlowPayments(in: ledger)
        let pendingByPlan = Dictionary(grouping: Finance.occurrences(in: ledger, now: now, days: 1).filter { $0.planID != nil && Dates.day($0.date) <= Dates.day(now) }, by: { $0.planID! })
        var rows = ledger.plans.compactMap { plan -> Self? in
            let date = plan.stoppedAt ?? plan.endDate
            guard date.map({ $0 <= now }) ?? !plan.active else { return nil }
            var detail = date.map { "\(Dates.calendar.component(.month, from: $0))月\(Dates.calendar.component(.day, from: $0))日停掉" } ?? "已停掉"
            let pending = pendingByPlan[plan.id] ?? []
            if pending.count > 1 { detail += " · 还有 \(pending.count) 期没记" }
            else if let row = pending.first {
                detail += " · \(Dates.calendar.component(.day, from: row.date))日那期" + (plan.inflow ? "还没收到" : "还没记")
            } else if let date {
                var original = plan; original.endDate = nil
                let end = Dates.addDays(1, to: Dates.day(date)).addingTimeInterval(-0.001)
                if let last = original.schedule(through: end).last {
                    let day = Dates.day(last.date)
                    let status = plan.isSkipped(on: day) ? "没要" : payments.remaining(for: plan, on: day) == 0 ? "已记" : "还没记"
                    detail += " · \(Dates.calendar.component(.day, from: day))日那期" + status
                }
            }
            return Self(id: plan.id, title: plan.title, detail: detail,
                        amount: payments.amount(for: plan), inflow: plan.inflow, canEnd: false, total: plan.installments, stoppedAt: date, pending: pending)
        }
        rows += ledger.rents.compactMap { rent -> Self? in
            let date = rent.stoppedAt ?? rent.endDate
            guard date.map({ $0 <= now }) ?? !rent.active else { return nil }
            return Self(id: rent.id, title: rent.title, detail: date.map { "\(Dates.calendar.component(.month, from: $0))月\(Dates.calendar.component(.day, from: $0))日停掉" } ?? "已停掉", amount: rent.monthlyTotal * Int64(rent.monthsPerPayment),
                        inflow: false, canEnd: false, stoppedAt: date)
        }
        return rows.sorted { $0.stoppedAt == $1.stoppedAt ? $0.id.uuidString < $1.id.uuidString : ($0.stoppedAt ?? .distantPast) > ($1.stoppedAt ?? .distantPast) }
    }
    public static func rows(in ledger: Ledger, now: Date = Date()) -> [Self] {
        let occurrences = Finance.occurrences(in: ledger, now: now, days: 90)
        var next: [UUID: Occurrence] = [:]
        for occurrence in occurrences {
            if let id = occurrence.planID, next[id] == nil { next[id] = occurrence }
            else if !occurrence.inflow, let id = occurrence.rentID, next[id] == nil { next[id] = occurrence }
        }
        let horizon = Dates.addDays(90, to: Dates.day(now))
        let payments = FixedFlowPayments(in: ledger)
        var rows = ledger.plans.filter {
            $0.active && ($0.endDate == nil || $0.endDate! > now)
                && !($0.frequency == .once && $0.dueDate <= horizon && next[$0.id] == nil)
        }.map { plan in
            Self(id: plan.id, title: plan.title, detail: schedule(plan.frequency, date: plan.dueDate, now: now) + (plan.accountID.map { " · " + ledger.accountName($0) } ?? ""),
                 amount: next[plan.id]?.amount ?? payments.amount(for: plan), inflow: plan.inflow, canEnd: plan.endDate == nil,
                 paidCount: plan.installments == nil ? 0 : payments.plans.keys.filter { $0.id == plan.id && plan.occurrenceIndex(on: $0.day) != nil && !plan.isSkipped(on: $0.day) && payments.remaining(for: plan, on: $0.day) == 0 }.count,
                 total: plan.installments)
        }
        rows += ledger.rents.filter { $0.active && ($0.endDate == nil || $0.endDate! > now) }.map { rent in
            Self(id: rent.id, title: rent.title, detail: "每 \(rent.monthsPerPayment) 月 \(Dates.calendar.component(.day, from: rent.nextDueDate)) 日" + (rent.accountID.map { " · " + ledger.accountName($0) } ?? ""),
                 amount: next[rent.id]?.amount ?? rent.monthlyTotal * Int64(rent.monthsPerPayment), inflow: false, canEnd: rent.endDate == nil)
        }
        return rows
    }
    public static func schedule(_ frequency: Frequency, date: Date, now: Date = Date()) -> String {
        let c = Dates.calendar
        switch frequency {
        case .once: return ManualBookkeeping.dayLabel(date, now: now)
        case .weekly:
            let names = ["日", "一", "二", "三", "四", "五", "六"]
            return "每周" + names[c.component(.weekday, from: date) - 1]
        case .monthly: return "每月 \(c.component(.day, from: date)) 日"
        case .quarterly: return "每季 \(c.component(.day, from: date)) 日"
        case .yearly: return "每年 \(c.component(.month, from: date)) 月 \(c.component(.day, from: date)) 日"
        }
    }
}

