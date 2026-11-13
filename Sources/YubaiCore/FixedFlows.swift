import Foundation

struct FixedFlowPaymentKey: Hashable { var id: UUID; var day: Date }
struct FixedFlowPayments {
    var plans: [FixedFlowPaymentKey: Int64] = [:]
    var rentPaid: [FixedFlowPaymentKey: Int64] = [:]; var rentReceived: [FixedFlowPaymentKey: Int64] = [:]
    var latest: [UUID: Entry] = [:]
    var actual: [UUID: Entry] = [:]
    var rates: [ManualExchangeRate] = []
    var asOf: Date = .distantFuture
    init(in ledger: Ledger, now: Date = .distantFuture) {
        rates = ledger.preferences.billExchangeRates ?? []; asOf = now
        for entry in ledger.entries where entry.deletedAt == nil && entry.date <= now {
            if let id = entry.planID, let date = entry.occurrence {
                plans[FixedFlowPaymentKey(id: id, day: Dates.day(date)), default: 0] += entry.amount
                if entry.source != "自动扣款", actual[id] == nil || entry.date > actual[id]!.date || (entry.date == actual[id]!.date && (entry.recordedAt ?? entry.date) > (actual[id]!.recordedAt ?? actual[id]!.date)) { actual[id] = entry }
                if latest[id] == nil || entry.date > latest[id]!.date || (entry.date == latest[id]!.date && (entry.recordedAt ?? entry.date) > (latest[id]!.recordedAt ?? latest[id]!.date)) { latest[id] = entry }
            }
            if let id = entry.rentID, let date = entry.rentPeriod {
                if entry.nature == .expense { rentPaid[FixedFlowPaymentKey(id: id, day: Dates.day(date)), default: 0] += entry.amount }
                if entry.nature == .contribution {
                    let month = Dates.calendar.dateInterval(of: .month, for: date)!.start
                    rentReceived[FixedFlowPaymentKey(id: id, day: month), default: 0] += entry.amount
                }
            }
        }
    }
    func amount(for plan: Plan) -> Int64 {
        guard plan.estimated || plan.currency != .cny, let entry = (plan.currency == .cny ? latest[plan.id] : actual[plan.id]),
              plan.estimatedAmountSince.map({ (entry.recordedAt ?? entry.date) > $0 }) ?? true else {
            if plan.currency == .cny { return plan.amount }
            return ManualBillExchangeRates(rates).rate(for: plan.currency, asOf: asOf)?.convert(plan.amount) ?? 0
        }
        return entry.amount
    }
    func remaining(for plan: Plan, on date: Date) -> Int64 {
        guard !plan.isSkipped(on: date) else { return 0 }
        let paid = plans[FixedFlowPaymentKey(id: plan.id, day: Dates.day(date)), default: 0]
        if paid > 0 && plan.settledOccurrences.contains(where: { Dates.day($0) == Dates.day(date) }) { return 0 }
        return (plan.estimated || plan.currency != .cny) && paid > 0 ? 0 : max(0, amount(for: plan) - paid)
    }
}

public enum FixedFlowState: String, Sendable { case paid, due, upcoming }
public enum FixedFlowStopResolution: Sendable { case settle, skip }
public struct FixedFlowOccurrence: Identifiable, Equatable, Sendable {
    public var id: String; public var title: String; public var date: Date; public var state: FixedFlowState
    public var amount: Int64; public var planID: UUID?; public var rentID: UUID?; public var inflow: Bool; public var autoPay: Bool
    public var installment: (index: Int, total: Int)?; public var estimated: Bool
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.title == rhs.title && lhs.date == rhs.date && lhs.state == rhs.state && lhs.amount == rhs.amount &&
        lhs.planID == rhs.planID && lhs.rentID == rhs.rentID && lhs.inflow == rhs.inflow && lhs.autoPay == rhs.autoPay &&
        lhs.installment?.index == rhs.installment?.index && lhs.installment?.total == rhs.installment?.total && lhs.estimated == rhs.estimated
    }
    public func overdueDays(now: Date = Date(), calendar: Calendar = Dates.calendar) -> Int {
        max(0, calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0)
    }
    public func statusText(now: Date = Date(), calendar: Calendar = Dates.calendar) -> String {
        let dateLabel = "\(calendar.component(.day, from: date))日"
        let days = overdueDays(now: now, calendar: calendar)
        let status: String
        switch state {
        case .paid: status = inflow ? "已收到" : "已付"
        case .due: status = days > 0 ? "过了 \(days) 天" + (inflow ? "还没收到" : "还没记") : (inflow ? "今天该收到" : "今天到期")
        case .upcoming: status = "还没到"
        }
        return dateLabel + " · " + status
    }
}
public struct FixedFlowUpcoming: Identifiable, Sendable {
    public var id: UUID { planID }
    public var planID: UUID; public var title: String; public var amount: Int64; public var inflow: Bool
    public var date: Date; public var frequency: Frequency; public var dueDate: Date; public var monthlyDay: Int?
    public func detail(now: Date = Date()) -> String {
        let calendar = Dates.calendar
        let schedule = FixedFlowArrangement.schedule(frequency, date: dueDate, now: now, monthlyDay: monthlyDay).replacingOccurrences(of: " ", with: "")
        let year = calendar.component(.year, from: date) == calendar.component(.year, from: now) + 1 ? "明年" : ""
        let start = "\(year)\(calendar.component(.month, from: date))月\(calendar.component(.day, from: date))日起"
        return schedule + " · " + start
    }
}
public struct FixedFlowMonth: Sendable {
    public var date: Date; public var occurrences: [FixedFlowOccurrence]
    public var remainingOutflow: Int64; public var remainingInflow: Int64
    public var overdueOutflow: Int64 = 0; public var overdueInflow: Int64 = 0
    public var stopped: [FixedFlowArrangement] = []
    public var later: [FixedFlowUpcoming] = []
}

extension FixedFlows {
    public static func unsettled(planID: UUID, in ledger: Ledger, now: Date = Date()) -> [Occurrence] {
        Finance.occurrences(in: ledger, now: now, days: 1).filter { $0.planID == planID && Dates.day($0.date) <= Dates.day(now) }
    }
    public static func stop(planID: UUID, resolution: FixedFlowStopResolution? = nil, in ledger: Ledger, now: Date = Date()) throws -> ChangeSet {
        guard let plan = ledger.plans.first(where: { $0.id == planID && $0.active && $0.endDate == nil }) else { throw YubaiError.invalid("找不到可停掉的安排。") }
        let pending = unsettled(planID: planID, in: ledger, now: now)
        guard pending.isEmpty || resolution != nil else { throw YubaiError.invalid("先处理已到期还没记的账单。") }
        var items: [ChangeItem] = []
        for row in pending {
            if resolution == .settle { items += try settle(planID: planID, occurrence: row.date, in: ledger, now: now).items }
            else { items.append(.skipOccurrence(planID, row.date)) }
        }
        items.append(.endPlan(planID, now))
        var change = ChangeSet(source: "用户操作", reason: "停掉「\(plan.title)」", items: items); change.createdAt = now
        var preview = ledger; try change.apply(to: &preview)
        return change
    }
    public static func resume(id: UUID, in ledger: Ledger, now: Date = Date()) throws -> ChangeSet {
        guard let row = FixedFlowArrangement.stopped(in: ledger, now: now).first(where: { $0.id == id }) else { throw YubaiError.invalid("找不到已停掉的安排。") }
        var change = ChangeSet(source: "用户操作", reason: "恢复「\(row.title)」", items: [.resumePlan(id)])
        change.createdAt = now
        var preview = ledger; try change.apply(to: &preview)
        return change
    }
    public static func resolveStopped(planID: UUID, resolution: FixedFlowStopResolution, in ledger: Ledger, now: Date = Date()) throws -> ChangeSet {
        guard let row = FixedFlowArrangement.stopped(in: ledger, now: now).first(where: { $0.id == planID }), !row.pending.isEmpty else { throw YubaiError.invalid("找不到已停掉安排的未结清期。") }
        var items: [ChangeItem] = []
        for occurrence in row.pending {
            if resolution == .settle { items += try settle(planID: planID, occurrence: occurrence.date, in: ledger, now: now).items }
            else { items.append(.skipOccurrence(planID, occurrence.date)) }
        }
        var change = ChangeSet(source: "用户操作", reason: "「\(row.title)」" + (resolution == .settle ? "已记下" : "不要了"), items: items); change.createdAt = now
        var preview = ledger; try change.apply(to: &preview)
        return change
    }
    public static func settle(planID: UUID, occurrence: Date, amount: Int64? = nil, accountID: UUID? = nil, in ledger: Ledger, now: Date = Date()) throws -> ChangeSet {
        guard let plan = ledger.plans.first(where: { $0.id == planID && $0.active }), plan.occurrenceIndex(on: occurrence) != nil else { throw YubaiError.invalid("找不到这期固定收付。") }
        let payments = FixedFlowPayments(in: ledger, now: now); let remaining = payments.remaining(for: plan, on: occurrence)
        guard remaining > 0 else { throw YubaiError.invalid(plan.inflow ? "这期已经收到了。" : "这期已经付了。") }
        guard let account = accountID ?? plan.accountID ?? ManualBookkeeping.defaultAccount(in: ledger)?.id else { throw YubaiError.invalid("先添加一个收付款账户。") }
        let day = Dates.day(occurrence); let today = Dates.day(now)
        let draft = EntryDraft(date: ManualBookkeeping.entryDate(for: min(day, today), now: now), amount: amount ?? remaining,
                               amountConfirmed: true, nature: plan.nature, accountID: account, title: plan.title, category: plan.category,
                               planID: plan.id, occurrence: day, intoFixedSavings: plan.intoFixedSavings)
        let c = Dates.calendar; let label = "\(c.component(.month, from: day))月\(c.component(.day, from: day))日"
        var change = ChangeSet(source: "用户操作", reason: "「\(plan.title)」\(label)这期" + (plan.inflow ? "收到了" : "付了"), items: [.addEntry(draft)])
        change.createdAt = now
        var preview = ledger; try change.apply(to: &preview)
        return change
    }
    public static func suggestions(amount: Int64, nature: Nature, purpose: String, day: Date, accountID: UUID?, in ledger: Ledger, now: Date = Date()) -> [Occurrence] {
        guard nature != .transfer, amount > 0, amount <= Money.limit else { return [] }
        func normalized(_ text: String) -> String { String(text.filter { !$0.isWhitespace }).lowercased() }
        let name = normalized(purpose); let day = Dates.day(day)
        let days = max(0, Dates.calendar.dateComponents([.day], from: Dates.day(now), to: Dates.addDays(3, to: day)).day ?? 0) + 1
        let plans = Dictionary(uniqueKeysWithValues: ledger.plans.map { ($0.id, $0) })
        let matches = Finance.occurrences(in: ledger, now: now, days: days).compactMap { occurrence -> (occurrence: Occurrence, exact: Bool, overlap: Bool, distance: Int)? in
            guard let id = occurrence.planID, let plan = plans[id], occurrence.inflow == nature.inflow,
                  accountID == nil || plan.accountID == nil || accountID == plan.accountID else { return nil }
            let distance = abs(Dates.calendar.dateComponents([.day], from: day, to: Dates.day(occurrence.date)).day ?? Int.max)
            guard distance <= 3 else { return nil }
            let title = normalized(plan.title); let overlap = !name.isEmpty && !title.isEmpty && (name.contains(title) || title.contains(name))
            let exact = amount == occurrence.amount
            guard exact || (overlap && (plan.estimated || abs(amount - occurrence.amount) <= occurrence.amount / 10)) else { return nil }
            return (occurrence, exact, overlap, distance)
        }
        return Array(matches.sorted {
            if $0.exact != $1.exact { return $0.exact }
            if $0.overlap != $1.overlap { return $0.overlap }
            if $0.distance != $1.distance { return $0.distance < $1.distance }
            return $0.occurrence.id < $1.occurrence.id
        }.prefix(3).map(\.occurrence))
    }
    public static func autoSettle(in ledger: Ledger, now: Date = Date()) -> ChangeSet? {
        let anchor = ledger.paydayConfirmSince != nil ? Finance.anchorPlan(in: ledger, now: now)?.id : nil
        let plans = Dictionary(uniqueKeysWithValues: ledger.plans.filter { $0.autoPay && $0.accountID != nil && $0.id != anchor }.map { ($0.id, $0) })
        let today = Dates.day(now)
        let scheduled = Set(ledger.entries.compactMap { entry -> FixedFlowPaymentKey? in
            guard entry.deletedAt == nil, entry.date > now, let id = entry.planID, let day = entry.occurrence else { return nil }
            return FixedFlowPaymentKey(id: id, day: Dates.day(day))
        })
        let items = Finance.occurrences(in: ledger, now: now, days: 1).compactMap { occurrence -> ChangeItem? in
            guard let id = occurrence.planID, let plan = plans[id], let account = plan.accountID,
                  !scheduled.contains(FixedFlowPaymentKey(id: id, day: Dates.day(occurrence.date))),
                  ledger.accounts.contains(where: { $0.id == account }),
                  Dates.day(occurrence.date) >= Dates.day(plan.autoPaySince ?? plan.dueDate), Dates.day(occurrence.date) <= today else { return nil }
            let draft = EntryDraft(date: ManualBookkeeping.entryDate(for: Dates.day(occurrence.date), now: now), amount: occurrence.amount,
                                   amountConfirmed: true, nature: plan.nature, accountID: account, title: plan.title, category: plan.category,
                                   planID: id, occurrence: Dates.day(occurrence.date), intoFixedSavings: plan.intoFixedSavings)
            return .addEntry(draft)
        }
        guard !items.isEmpty else { return nil }
        var change = ChangeSet(source: "自动扣款", reason: "记录已到期的固定收付", items: items); change.createdAt = now
        return change
    }
    public static func month(containing date: Date, in ledger: Ledger) -> FixedFlowMonth {
        month(containing: date, in: ledger, asOf: date)
    }
    public static func month(containing date: Date, in ledger: Ledger, asOf now: Date) -> FixedFlowMonth {
        let interval = Dates.calendar.dateInterval(of: .month, for: date)!; let end = interval.end.addingTimeInterval(-0.001)
        let today = Dates.day(now); let payments = FixedFlowPayments(in: ledger, now: now)
        let stopped = FixedFlowArrangement.stopped(in: ledger, now: now); let stoppedIDs = Set(stopped.map(\.id))
        let pending = stopped.flatMap(\.pending)
        var rows: [FixedFlowOccurrence] = []
        var outflow = pending.filter { !$0.inflow }.reduce(Int64(0)) { $0 + $1.amount }
        var inflow = pending.filter(\.inflow).reduce(Int64(0)) { $0 + $1.amount }
        var overdueOutflow = pending.filter { !$0.inflow && $0.overdue }.reduce(Int64(0)) { $0 + $1.amount }
        var overdueInflow = pending.filter { $0.inflow && $0.overdue }.reduce(Int64(0)) { $0 + $1.amount }
        func append(id: String, title: String, date: Date, amount: Int64, paid: Int64, remaining: Int64, incoming: Bool, planID: UUID? = nil, rentID: UUID? = nil, autoPay: Bool = false, installment: (index: Int, total: Int)? = nil, estimated: Bool = false) {
            guard date >= interval.start, date < interval.end else { return }
            if planID.map({ stoppedIDs.contains($0) }) == true { return }
            if incoming { inflow += remaining } else { outflow += remaining }
            if Dates.day(date) < today { if incoming { overdueInflow += remaining } else { overdueOutflow += remaining } }
            if rentID.map({ stoppedIDs.contains($0) }) == true { return }
            rows.append(FixedFlowOccurrence(id: id, title: title, date: date, state: paid > 0 && remaining == 0 ? .paid : (Dates.day(date) <= today ? .due : .upcoming),
                                            amount: paid > 0 && remaining == 0 ? paid : (paid > 0 ? remaining : amount), planID: planID, rentID: rentID, inflow: incoming, autoPay: autoPay,
                                            installment: installment, estimated: estimated))
        }
        var later: [FixedFlowUpcoming] = []
        for plan in ledger.plans where plan.active {
            let schedule = plan.schedule(through: end)
            // Paid or skipped periods still count as a period in this month.
            if !stoppedIDs.contains(plan.id), plan.stoppedAt == nil, !schedule.contains(where: { $0.date >= interval.start }) {
                if let date = plan.nextScheduledDate(after: end) {
                    later.append(FixedFlowUpcoming(planID: plan.id, title: plan.title, amount: payments.amount(for: plan), inflow: plan.inflow,
                                                   date: date, frequency: plan.frequency, dueDate: plan.dueDate, monthlyDay: plan.monthlyDay))
                }
            }
            for item in schedule where item.date >= interval.start && !plan.isSkipped(on: item.date) {
                let paid = payments.plans[FixedFlowPaymentKey(id: plan.id, day: Dates.day(item.date)), default: 0]
                append(id: "\(plan.id)-\(item.date.timeIntervalSince1970)", title: plan.title, date: item.date, amount: payments.amount(for: plan), paid: paid,
                       remaining: payments.remaining(for: plan, on: item.date), incoming: plan.inflow, planID: plan.id, autoPay: plan.autoPay,
                       installment: plan.installments.map { (item.index + 1, $0) }, estimated: plan.estimated || plan.currency != .cny)
            }
        }
        for rent in ledger.rents where rent.active {
            for index in 0..<240 {
                let date = Dates.addMonths(index * rent.monthsPerPayment, to: rent.nextDueDate)
                if Dates.day(date) > end || rent.endDate.map({ Dates.day(date) > Dates.day($0) }) == true { break }
                let paid = payments.rentPaid[FixedFlowPaymentKey(id: rent.id, day: Dates.day(date)), default: 0]
                let amount = rent.monthlyTotal * Int64(rent.monthsPerPayment)
                append(id: "rent-\(rent.id)-\(date.timeIntervalSince1970)", title: rent.title, date: date, amount: amount, paid: paid,
                       remaining: max(0, amount - paid), incoming: false, rentID: rent.id)
            }
            let first = Dates.calendar.dateInterval(of: .month, for: rent.startDate)!.start
            for index in 0..<1200 {
                let month = Dates.addMonths(index, to: first); let date = max(Dates.addDays(rent.receiveDay - 1, to: month), rent.startDate)
                if Dates.day(date) > end || rent.endDate.map({ Dates.day(date) > Dates.day($0) }) == true { break }
                let amount = rent.monthlyTotal - rent.personalShare
                guard amount > 0 else { continue }
                let paid = payments.rentReceived[FixedFlowPaymentKey(id: rent.id, day: month), default: 0]
                append(id: "share-\(rent.id)-\(month.timeIntervalSince1970)", title: rent.title + " · 应收分摊", date: date, amount: amount, paid: paid,
                       remaining: max(0, amount - paid), incoming: true, rentID: rent.id)
            }
        }
        rows.sort { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }
        later.sort { $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date < $1.date }
        return FixedFlowMonth(date: interval.start, occurrences: rows, remainingOutflow: outflow, remainingInflow: inflow,
                              overdueOutflow: overdueOutflow, overdueInflow: overdueInflow, stopped: stopped, later: later)
    }
}

extension FixedFlows {
    public static func expectedAmount(planID: UUID, in ledger: Ledger) -> Int64? {
        ledger.plans.first { $0.id == planID }.map { FixedFlowPayments(in: ledger).amount(for: $0) }
    }
    public static func expectedAmount(planID: UUID, in ledger: Ledger, now: Date) -> Int64? {
        ledger.plans.first { $0.id == planID }.map { FixedFlowPayments(in: ledger, now: now).amount(for: $0) }
    }
    private static func overlap(_ entry: Entry, _ plan: Plan) -> Bool {
        func clean(_ text: String) -> String { String(text.filter { !$0.isWhitespace }).lowercased() }
        let name = clean(entry.displayTitle), title = clean(plan.title)
        return !name.isEmpty && !title.isEmpty && (name.contains(title) || title.contains(name))
    }
    private static func matches(_ entry: Entry, plan: Plan, occurrence: Date, amount: Int64, allowEstimateWithoutName: Bool = false) -> Bool {
        let distance = abs(Dates.calendar.dateComponents([.day], from: Dates.day(entry.date), to: Dates.day(occurrence)).day ?? Int.max)
        return distance <= 3 && entry.nature == plan.nature &&
            (entry.amount == amount || (overlap(entry, plan) && (plan.estimated || abs(entry.amount - amount) <= amount / 10)) || (allowEstimateWithoutName && plan.estimated))
    }
    public static func matchingEntries(planID: UUID, occurrence: Date, in ledger: Ledger, now: Date) -> [Entry] {
        guard let plan = ledger.plans.first(where: { $0.id == planID }), plan.occurrenceIndex(on: occurrence) != nil,
              FixedFlowPayments(in: ledger, now: now).remaining(for: plan, on: occurrence) > 0 else { return [] }
        let amount = FixedFlowPayments(in: ledger, now: now).amount(for: plan)
        return Array(ledger.entries.filter { $0.deletedAt == nil && $0.date <= now && $0.planID == nil && $0.rentID == nil && !$0.fromReserve &&
            matches($0, plan: plan, occurrence: occurrence, amount: amount, allowEstimateWithoutName: true) }.sorted {
                let aExact = $0.amount == amount, bExact = $1.amount == amount
                if aExact != bExact { return aExact }
                let aOverlap = overlap($0, plan), bOverlap = overlap($1, plan)
                if aOverlap != bOverlap { return aOverlap }
                let a = abs(Dates.calendar.dateComponents([.day], from: Dates.day($0.date), to: Dates.day(occurrence)).day ?? Int.max)
                let b = abs(Dates.calendar.dateComponents([.day], from: Dates.day($1.date), to: Dates.day(occurrence)).day ?? Int.max)
                if a != b { return a < b }
                return $0.id.uuidString < $1.id.uuidString
            }.prefix(3))
    }
    public static func linkCandidates(planID: UUID, in ledger: Ledger, now: Date) -> [Entry] {
        guard let plan = ledger.plans.first(where: { $0.id == planID }) else { return [] }
        let from = Dates.addDays(-45, to: now)
        return ledger.entries.filter { $0.deletedAt == nil && $0.date >= from && $0.date <= now && $0.planID == nil && $0.rentID == nil && $0.nature == plan.nature && !$0.fromReserve }
            .sorted { $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date > $1.date }
    }
    public static func markPaid(planID: UUID, occurrence: Date, with entryID: UUID, in ledger: inout Ledger) throws {
        guard let p = ledger.plans.firstIndex(where: { $0.id == planID }), let e = ledger.entries.firstIndex(where: { $0.id == entryID && $0.deletedAt == nil }),
              ledger.plans[p].occurrenceIndex(on: occurrence) != nil, !ledger.plans[p].isSkipped(on: occurrence),
              ledger.entries[e].planID == nil, ledger.entries[e].rentID == nil, !ledger.entries[e].fromReserve,
              ledger.entries[e].nature == ledger.plans[p].nature,
              FixedFlowPayments(in: ledger).remaining(for: ledger.plans[p], on: occurrence) > 0 else {
            throw YubaiError.invalid("找不到这期固定收付。")
        }
        var next = ledger
        next.entries[e].planID = planID; next.entries[e].occurrence = Dates.day(occurrence)
        if next.plans[p].intoFixedSavings { next.entries[e].intoFixedSavings = true }
        if !next.plans[p].settledOccurrences.contains(where: { Dates.day($0) == Dates.day(occurrence) }) { next.plans[p].settledOccurrences.append(Dates.day(occurrence)) }
        try next.validate(); ledger = next
    }
    public static func unlink(entryID: UUID, in ledger: inout Ledger) throws {
        guard let e = ledger.entries.firstIndex(where: { $0.id == entryID && $0.deletedAt == nil }), let id = ledger.entries[e].planID,
              let day = ledger.entries[e].occurrence else { throw YubaiError.invalid("找不到原记录。") }
        var next = ledger
        next.entries[e].planID = nil; next.entries[e].occurrence = nil
        if let p = next.plans.firstIndex(where: { $0.id == id }) { next.plans[p].settledOccurrences.removeAll { Dates.day($0) == Dates.day(day) } }
        try next.validate(); ledger = next
    }
    @discardableResult public static func autoLink(_ ledger: inout Ledger, addedEntryIDs: Set<UUID>, now: Date) -> [(planID: UUID, occurrence: Date)] {
        let addedEntryIDs = BillImporter.mergeAddedManualEntries(addedEntryIDs, in: &ledger, now: now)
        let payments = FixedFlowPayments(in: ledger, now: now)
        let entries = ledger.entries.filter { addedEntryIDs.contains($0.id) && $0.deletedAt == nil && $0.date <= now && $0.planID == nil && $0.rentID == nil && !$0.fromReserve }
        var candidates: [UUID: [FixedFlowPaymentKey]] = [:], owners: [FixedFlowPaymentKey: Set<UUID>] = [:]
        let end = Dates.addDays(4, to: Dates.day(now)).addingTimeInterval(-0.001)
        for plan in ledger.plans where plan.active {
            let amount = payments.amount(for: plan)
            for item in plan.schedule(through: end) where !plan.isSkipped(on: item.date) {
                let key = FixedFlowPaymentKey(id: plan.id, day: Dates.day(item.date))
                guard payments.plans[key, default: 0] == 0 else { continue }
                for entry in entries where matches(entry, plan: plan, occurrence: item.date, amount: amount) {
                    candidates[entry.id, default: []].append(key); owners[key, default: []].insert(entry.id)
                }
            }
        }
        var linked: [(planID: UUID, occurrence: Date)] = []
        for entry in entries.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            guard let keys = candidates[entry.id], keys.count == 1, let key = keys.first, owners[key]?.count == 1 else { continue }
            do { try markPaid(planID: key.id, occurrence: key.day, with: entry.id, in: &ledger); linked.append((key.id, key.day)) }
            catch { continue }
        }
        return linked
    }
    public struct History: Equatable, Sendable { public var entries: [Entry]; public var average: Int64 }
    public static func history(planID: UUID, in ledger: Ledger) -> History {
        history(planID: planID, in: ledger, now: .distantFuture)
    }
    public static func history(planID: UUID, in ledger: Ledger, now: Date) -> History {
        let rows = Array(ledger.entries.filter { $0.deletedAt == nil && $0.planID == planID && $0.date <= now }.sorted {
            $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date > $1.date
        }.prefix(12))
        return History(entries: rows, average: rows.isEmpty ? 0 : rows.reduce(0) { $0 + $1.amount } / Int64(rows.count))
    }
}
