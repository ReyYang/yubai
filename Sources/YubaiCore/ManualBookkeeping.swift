import Foundation

/// Decimal, integer-cent arithmetic shared by the manual keypad and its save action.
public struct EntryKeypad: Equatable, Sendable {
    public private(set) var expression = "0"
    public init() {}
    public init(amount: Int64) { expression = Money.input(amount) }
    public var amount: Int64? { try? Self.evaluate(expression) }
    public var canSave: Bool { amount.map { $0 > 0 && $0 <= Money.limit } ?? false }
    public var resultText: String {
        let cents = amount ?? 0
        let magnitude = cents.magnitude
        let fraction = magnitude % 100
        return "\(cents < 0 ? "-" : "")\(magnitude / 100).\(fraction < 10 ? "0" : "")\(fraction)"
    }
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
            guard expression != "0" else { return }
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
        guard nature != .transfer else { return [] }
        return Category.defaults.filter { !$0.system && !$0.hidden && $0.income == (nature != .refund && nature.inflow) }.map(\.name)
    }
    public static func categories(in ledger: Ledger, nature: Nature, frequentOnly: Bool = false) -> [String] {
        guard nature != .transfer else { return [] }
        let ordered = ledger.orderedCategories(income: nature.categoryIncome).map(\.name)
        return frequentOnly ? Array(ordered.prefix(5)) : ordered
    }
    public static func guessCategory(_ purpose: String, nature: Nature, in ledger: Ledger) -> String? {
        CategoryGuesser.guess(purpose, nature: nature, in: ledger)?.category
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
    public static func saveDate(for day: Date, now: Date) -> Date {
        Dates.calendar.date(bySettingHour: Dates.calendar.component(.hour, from: now), minute: Dates.calendar.component(.minute, from: now), second: Dates.calendar.component(.second, from: now), of: day)!
    }
    public static func change(amount: Int64, nature: Nature, accountID: UUID, otherAccountID: UUID? = nil,
                              day: Date, purpose: String, category: String, link: (planID: UUID, occurrence: Date)? = nil, now: Date = Date()) throws -> ChangeSet {
        guard amount > 0, amount <= Money.limit, Dates.day(day) <= Dates.day(now) else { throw YubaiError.invalid("请核对金额和日期。") }
        if nature == .transfer { guard let otherAccountID, otherAccountID != accountID else { throw YubaiError.invalid("转账的两个账户必须不同。") } }
        let purpose = purpose.trimmingCharacters(in: .whitespacesAndNewlines)
        var draft = EntryDraft(date: saveDate(for: day, now: now), amount: amount, amountConfirmed: true,
                               nature: nature, accountID: accountID, title: purpose.isEmpty ? category : purpose,
                               category: category, purpose: purpose.isEmpty ? nil : purpose)
        draft.categoryUserEdited = nature != .transfer
        draft.otherAccountID = nature == .transfer ? otherAccountID : nil
        draft.planID = link?.planID; draft.occurrence = link?.occurrence
        var change = ChangeSet(source: "手动", reason: "记一笔", items: [.addEntry(draft)])
        change.createdAt = now; return change
    }
    public static func available(after change: ChangeSet, in ledger: Ledger, now: Date = Date()) throws -> Int64 {
        guard change.items.count == 1, case .addEntry(let draft) = change.items[0],
              !ledger.entries.contains(where: { $0.id == draft.id }) else {
            var preview = ledger; try change.apply(to: &preview)
            return Finance.funds(preview, now: now).available
        }
        try change.validateStructure(); try ledger.validate()
        let entry = try change.addedEntry(draft, in: ledger)
        // Validate the added row and its category memory against the same
        // accounts/plans. Existing rows already passed validation above.
        var isolated = ledger; isolated.entries = [entry]
        if ledger.entries.count >= 200_000 { var full = ledger; full.entries.append(entry); try full.validate() }
        if change.source == "手动" || draft.categoryUserEdited == true { CategoryMemory.remember(entry, in: &isolated) }
        try isolated.validate()
        return available(removing: nil, adding: entry, in: ledger, now: now)
    }
    /// Editing callers can share the keypad calculation without changing a form's
    /// ledger. Validation/refund propagation stays identical to the save action.
    public static func available(after edited: Entry, in ledger: Ledger, now: Date = Date()) throws -> Int64 {
        try ledger.validate()
        guard let original = ledger.entries.first(where: { $0.id == edited.id && $0.deletedAt == nil }) else { throw YubaiError.invalid("记录已移除。") }
        var isolated = ledger
        var entry = try prepareEdit(edited, original: original, in: &isolated)
        // Only this row, its refund target and refunds depending on either
        // can introduce a validation failure. Other rows are unchanged.
        let targets = Set([entry.id, entry.relatedEntryID].compactMap { $0 })
        isolated.entries = ledger.entries.filter { row in
            row.id != original.id && (row.id == entry.relatedEntryID || (row.deletedAt == nil && row.nature == .refund && row.relatedEntryID.map { targets.contains($0) } == true))
        } + [entry]
        LedgerOperations.syncLinkedRefundCategories(in: &isolated)
        entry = isolated.entries.first { $0.id == edited.id }!
        CategoryMemory.remember(entry, in: &isolated)
        try isolated.validate()
        return available(removing: original, adding: entry, in: ledger, now: now)
    }
    private static func available(removing original: Entry?, adding entry: Entry, in ledger: Ledger, now: Date) -> Int64 {
        let base = Finance.funds(ledger, now: now)
        let changes: [(Entry, Int64)] = (original.map { [($0, Int64(-1))] } ?? []) + [(entry, Int64(1))]
        var deltas: [UUID: Int64] = [:], difference: Int64 = 0
        for (row, sign) in changes where row.deletedAt == nil {
            for account in ledger.accounts where account.id == row.accountID || (row.nature.paired && account.id == row.otherAccountID) {
                let posting = row.postingDate(for: account.id)
                if posting <= now, account.includes(row, posting: posting) { deltas[account.id, default: 0] += sign * row.delta(for: account.id) }
            }
            if row.nature == .unknownIn, row.date <= now,
               ledger.accounts.contains(where: { $0.id == row.accountID && ($0.kind == .cash || $0.kind == .bank) && $0.includes(row, posting: row.date) }) {
                difference -= sign * row.amount
            }
        }
        for account in ledger.accounts {
            let delta = deltas[account.id, default: 0]
            if account.kind == .cash || account.kind == .bank { difference += delta }
            else if account.kind == .credit, delta != 0 {
                let old = Finance.balance(account, in: ledger, at: now)
                difference -= max(0, -(old + delta)) - max(0, -old)
            }
        }
        // Historical spending/refunds and linked payments can change reserves.
        // Ordinary entries today use just the affected account deltas above.
        let changesLiving = changes.contains { row, _ in row.date < Dates.day(now) && (row.nature == .expense || row.nature == .refund) }
        let changesPayments = changes.contains { $0.0.planID != nil || $0.0.rentID != nil }
        if changesLiving || changesPayments {
            var preview = ledger
            if let original, let index = preview.entries.firstIndex(where: { $0.id == original.id }) { preview.entries[index] = entry }
            else { preview.entries.append(entry) }
            if changesLiving {
                let oldDaily = base.horizonDays > 0 ? base.living / Int64(base.horizonDays) : 0
                difference -= (Finance.estimatedDailyLiving(preview, now: now) - oldDaily) * Int64(base.horizonDays)
            }
            if changesPayments {
                let repayments = Set(ledger.plans.filter { $0.nature == .repayment }.map(\.id))
                let occurrences = Finance.occurrences(in: preview, now: now, days: base.payday == nil ? Finance.observationDays : base.horizonDays + 1)
                let committed = occurrences.filter { !$0.inflow && Dates.day($0.date) <= base.horizonEnd && !($0.planID.map { repayments.contains($0) } ?? false) }.reduce(Int64(0)) { $0 + $1.amount }
                difference -= committed - base.committed
            }
        }
        return base.available + difference
    }
    public static func edit(_ edited: Entry, in ledger: inout Ledger) throws {
        guard let index = ledger.entries.firstIndex(where: { $0.id == edited.id && $0.deletedAt == nil }) else { throw YubaiError.invalid("记录已移除。") }
        let original = ledger.entries[index]
        var next = ledger
        let entry = try prepareEdit(edited, original: original, in: &next)
        next.entries[index] = entry
        LedgerOperations.syncLinkedRefundCategories(in: &next)
        CategoryMemory.remember(entry, in: &next)
        try next.validate(); ledger = next
    }
    private static func prepareEdit(_ edited: Entry, original: Entry, in next: inout Ledger) throws -> Entry {
        var entry = edited
        entry.id = original.id; entry.source = original.source; entry.recordedAt = original.recordedAt
        entry.userEdited = true
        // ImportOrganizer also sets userEdited. Persist a distinct manual marker
        // for category corrections; conservatively protect any reviewed catch-all
        // even when its category stayed the same. Legacy pending stays pending.
        if entry.category != original.category || (!Classification.isPending(entry) && entry.category == (entry.nature.categoryIncome ? "其他收入" : "其他支出")) {
            entry.classificationReason = "手动选择"
        }
        if entry.amount != original.amount { entry.personalExpense = nil; LedgerOperations.recordPersonalShare(&entry, ledger: next) }
        if entry.subcategory != original.subcategory || entry.category != original.category || entry.nature.categoryIncome != original.nature.categoryIncome {
            if (entry.category != original.category || entry.nature.categoryIncome != original.nature.categoryIncome) && entry.subcategory == original.subcategory && (!entry.subcategoryUserEdited || entry.subcategory != nil) {
                entry.subcategory = nil; entry.subcategoryUserEdited = false
                SubcategoryClassifier.classify(&entry, ledger: next)
            } else { entry.subcategoryUserEdited = true }
            if let sub = entry.subcategory, !SubcategoryClassifier.valid(.init(category: entry.category, subcategory: sub), in: next, nature: entry.nature) { throw YubaiError.invalid("这个小项不属于该主项。") }
            CategoryMemory.remember(entry, in: &next)
        }
        return entry
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
    public var income: Int64 = 0
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
    /// Only display values cross into a lazy row; import metadata and the ledger stay out of its view value.
    public struct Row: Identifiable, Equatable, Sendable {
        public let id: UUID
        public let amount: Int64
        public let inflow: Bool
        public let uncategorized: Bool
        public let categoryName: String
        public let note: String
        public let symbol: String
    }
    public struct Day: Identifiable, Equatable, Sendable {
        public var id: Date { date }
        public let date: Date
        public let spending: Int64
        public let income: Int64
        public let entries: [Row]
    }
    public struct Month: Identifiable, Equatable, Sendable {
        public var id: Date { date }
        public let date: Date
        public let spending: Int64
        public let income: Int64
        public let days: [Day]
    }
    public struct Snapshot: Equatable, Sendable {
        public let spending: Int64
        public let income: Int64
        public let days: [Day]
        public var months: [Month] = []
        public var count: Int { days.reduce(0) { $0 + $1.entries.count } }
    }
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
        Classification.isPending(entry)
    }
    /// Deterministic for the supplied ledger, query, month and calendar; cache at the ledger revision boundary.
    public static func snapshot(sortedEntries: [Entry], ledger: Ledger, month: Date, search: String = "", filter: Filter = .all,
                                calendar: Calendar = Dates.calendar) -> Snapshot {
        guard let interval = calendar.dateInterval(of: .month, for: month) else { return Snapshot(spending: 0, income: 0, days: []) }
        let searching = !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let entries = sortedEntries.filter { $0.deletedAt == nil && (searching || ($0.date >= interval.start && $0.date < interval.end)) }
        let rents = Dictionary(uniqueKeysWithValues: ledger.rents.map { ($0.id, $0) })
        var spending: Int64 = 0; var income: Int64 = 0
        for entry in entries {
            spending += Finance.spendingAmount(entry, rent: entry.rentID.flatMap { rents[$0] })
            if entry.nature == .income { income += entry.amount }
        }
        let symbols = Dictionary(uniqueKeysWithValues: ledger.categories.map { ($0.id, $0.symbol) })
        let grouped = months(sortedEntries: entries, ledger: ledger, search: search, filter: filter, calendar: calendar)
        let days = grouped.flatMap(\.days).map { day in
            Day(date: day.date, spending: day.spending, income: day.income, entries: day.entries.map { entry in
                let category = ledger.resolveCategory(entry.category, income: entry.nature.categoryIncome)
                let uncategorized = isUncategorized(entry)
                let name = uncategorized ? "没分类" : Classification.displayCategory(category)
                let note = entry.note.isEmpty ? (entry.displayTitle == name ? "" : entry.displayTitle) : entry.note
                let symbol: String
                if let known = symbols[CategoryNamespace.key(category, income: entry.nature.categoryIncome)] { symbol = known }
                else {
                    switch category {
                    case "日用", "购物": symbol = "bag"
                    case "娱乐": symbol = "sparkles"
                    case "工资", "奖金": symbol = "banknote"
                    case "兼职": symbol = "hammer"
                    case "理财收益": symbol = "chart.line.uptrend.xyaxis"
                    default: symbol = entry.nature.symbol
                    }
                }
                return Row(id: entry.id, amount: entry.amount, inflow: entry.nature.inflow, uncategorized: uncategorized,
                           categoryName: name, note: note, symbol: symbol)
            })
        }
        let displayMonths = grouped.map { group in
            Month(date: group.date, spending: group.spending, income: group.income,
                  days: days.filter { calendar.isDate($0.date, equalTo: group.date, toGranularity: .month) })
        }
        return Snapshot(spending: searching ? grouped.reduce(0) { $0 + $1.spending } : spending,
                        income: searching ? grouped.reduce(0) { $0 + $1.income } : income, days: days, months: displayMonths)
    }
    public static func months(sortedEntries: [Entry], ledger: Ledger, search: String = "", filter: Filter = .all,
                              calendar: Calendar = Dates.calendar) -> [EntryMonth] {
        let accounts = Dictionary(uniqueKeysWithValues: ledger.accounts.map { ($0.id, $0.name) })
        let rents = Dictionary(uniqueKeysWithValues: ledger.rents.map { ($0.id, $0) })
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let formatter = NumberFormatter(); formatter.locale = Locale(identifier: "zh_CN"); formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2; formatter.maximumFractionDigits = 2
        var dayInterval: DateInterval?; var monthInterval: DateInterval?
        var result: [EntryMonth] = []
        for entry in sortedEntries where entry.deletedAt == nil && filter.includes(entry) {
            if !query.isEmpty {
                let amount = formatter.string(from: NSDecimalNumber(decimal: Decimal(entry.amount) / 100)) ?? ""
                let signed = (entry.nature.inflow ? "+" : "−") + amount
                let category = ledger.resolveCategory(entry.category, income: entry.nature.categoryIncome)
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
            if entry.nature == .income { result[m].income += entry.amount; result[m].days[d].income += entry.amount }
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
                        amount: payments.amount(for: plan), inflow: plan.inflow, canEnd: false,
                        paidCount: paidCount(plan, payments: payments), total: plan.installments, stoppedAt: date, pending: pending)
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
                 paidCount: paidCount(plan, payments: payments),
                 total: plan.installments)
        }
        rows += ledger.rents.filter { $0.active && ($0.endDate == nil || $0.endDate! > now) }.map { rent in
            Self(id: rent.id, title: rent.title, detail: "每 \(rent.monthsPerPayment) 月 \(Dates.calendar.component(.day, from: rent.nextDueDate)) 日" + (rent.accountID.map { " · " + ledger.accountName($0) } ?? ""),
                 amount: next[rent.id]?.amount ?? rent.monthlyTotal * Int64(rent.monthsPerPayment), inflow: false, canEnd: rent.endDate == nil)
        }
        return rows
    }
    private static func paidCount(_ plan: Plan, payments: FixedFlowPayments) -> Int {
        guard plan.installments != nil else { return 0 }
        return payments.plans.keys.filter { $0.id == plan.id && plan.occurrenceIndex(on: $0.day) != nil && !plan.isSkipped(on: $0.day) && payments.remaining(for: plan, on: $0.day) == 0 }.count
    }
    public static func schedule(_ frequency: Frequency, date: Date, now: Date = Date(), monthlyDay: Int? = nil) -> String {
        let c = Dates.calendar
        switch frequency {
        case .once: return ManualBookkeeping.dayLabel(date, now: now)
        case .weekly:
            let names = ["日", "一", "二", "三", "四", "五", "六"]
            return "每周" + names[c.component(.weekday, from: date) - 1]
        case .monthly: return "每月 \(monthlyDay ?? c.component(.day, from: date)) 日"
        case .quarterly: return "每季 \(c.component(.day, from: date)) 日"
        case .yearly: return "每年 \(c.component(.month, from: date)) 月 \(c.component(.day, from: date)) 日"
        }
    }
}

