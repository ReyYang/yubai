import Foundation

struct FixedFlowPaymentKey: Hashable { var id: UUID; var day: Date }
struct FixedFlowPayments {
    var plans: [FixedFlowPaymentKey: Int64] = [:]
    var rentPaid: [FixedFlowPaymentKey: Int64] = [:]; var rentReceived: [FixedFlowPaymentKey: Int64] = [:]
    var latest: [UUID: Entry] = [:]
    init(in ledger: Ledger) {
        for entry in ledger.entries where entry.deletedAt == nil {
            if let id = entry.planID, let date = entry.occurrence {
                plans[FixedFlowPaymentKey(id: id, day: Dates.day(date)), default: 0] += entry.amount
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
    func amount(for plan: Plan) -> Int64 { plan.estimated ? latest[plan.id]?.amount ?? plan.amount : plan.amount }
    func remaining(for plan: Plan, on date: Date) -> Int64 {
        let paid = plans[FixedFlowPaymentKey(id: plan.id, day: Dates.day(date)), default: 0]
        return plan.estimated && paid > 0 ? 0 : max(0, amount(for: plan) - paid)
    }
}

public enum FixedFlowState: String, Sendable { case paid, due, upcoming }
public struct FixedFlowOccurrence: Identifiable, Sendable {
    public var id: String; public var title: String; public var date: Date; public var state: FixedFlowState
    public var amount: Int64; public var planID: UUID?; public var rentID: UUID?; public var inflow: Bool; public var autoPay: Bool
    public var installment: (index: Int, total: Int)?; public var estimated: Bool
}
public struct FixedFlowMonth: Sendable {
    public var date: Date; public var occurrences: [FixedFlowOccurrence]
    public var remainingOutflow: Int64; public var remainingInflow: Int64
}

extension FixedFlows {
    public static func resume(id: UUID, in ledger: Ledger, now: Date = Date()) throws -> ChangeSet {
        guard let row = FixedFlowArrangement.stopped(in: ledger, now: now).first(where: { $0.id == id }) else { throw YubaiError.invalid("找不到已停掉的安排。") }
        var change = ChangeSet(source: "用户操作", reason: "恢复「\(row.title)」", items: [.resumePlan(id)])
        change.createdAt = now
        var preview = ledger; try change.apply(to: &preview)
        return change
    }
    public static func settle(planID: UUID, occurrence: Date, amount: Int64? = nil, accountID: UUID? = nil, in ledger: Ledger, now: Date = Date()) throws -> ChangeSet {
        guard let plan = ledger.plans.first(where: { $0.id == planID && $0.active }), plan.occurrenceIndex(on: occurrence) != nil else { throw YubaiError.invalid("找不到这期固定收付。") }
        let payments = FixedFlowPayments(in: ledger); let remaining = payments.remaining(for: plan, on: occurrence)
        guard remaining > 0 else { throw YubaiError.invalid(plan.inflow ? "这期已经收到了。" : "这期已经付了。") }
        guard let account = accountID ?? plan.accountID ?? ManualBookkeeping.defaultAccount(in: ledger)?.id else { throw YubaiError.invalid("先添加一个收付款账户。") }
        let day = Dates.day(occurrence); let today = Dates.day(now)
        let draft = EntryDraft(date: ManualBookkeeping.entryDate(for: min(day, today), now: now), amount: amount ?? remaining,
                               amountConfirmed: true, nature: plan.nature, accountID: account, title: plan.title, category: plan.category,
                               planID: plan.id, occurrence: day)
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
        let plans = Dictionary(uniqueKeysWithValues: ledger.plans.filter { $0.autoPay && $0.accountID != nil }.map { ($0.id, $0) })
        let today = Dates.day(now)
        let items = Finance.occurrences(in: ledger, now: now, days: 1).compactMap { occurrence -> ChangeItem? in
            guard let id = occurrence.planID, let plan = plans[id], let account = plan.accountID,
                  ledger.accounts.contains(where: { $0.id == account }),
                  Dates.day(occurrence.date) >= Dates.day(plan.autoPaySince ?? plan.dueDate), Dates.day(occurrence.date) <= today else { return nil }
            let draft = EntryDraft(date: ManualBookkeeping.entryDate(for: Dates.day(occurrence.date), now: now), amount: occurrence.amount,
                                   amountConfirmed: true, nature: plan.nature, accountID: account, title: plan.title, category: plan.category,
                                   planID: id, occurrence: Dates.day(occurrence.date))
            return .addEntry(draft)
        }
        guard !items.isEmpty else { return nil }
        var change = ChangeSet(source: "自动扣款", reason: "记录已到期的固定收付", items: items); change.createdAt = now
        return change
    }
    public static func month(containing now: Date, in ledger: Ledger) -> FixedFlowMonth {
        let interval = Dates.calendar.dateInterval(of: .month, for: now)!; let end = interval.end.addingTimeInterval(-0.001)
        let today = Dates.day(now); let payments = FixedFlowPayments(in: ledger)
        var rows: [FixedFlowOccurrence] = []; var outflow: Int64 = 0; var inflow: Int64 = 0
        func append(id: String, title: String, date: Date, amount: Int64, paid: Int64, remaining: Int64, incoming: Bool, planID: UUID? = nil, rentID: UUID? = nil, autoPay: Bool = false, installment: (index: Int, total: Int)? = nil, estimated: Bool = false) {
            guard date >= interval.start, date < interval.end else { return }
            rows.append(FixedFlowOccurrence(id: id, title: title, date: date, state: paid > 0 && remaining == 0 ? .paid : (Dates.day(date) <= today ? .due : .upcoming),
                                            amount: paid > 0 && remaining == 0 ? paid : (paid > 0 ? remaining : amount), planID: planID, rentID: rentID, inflow: incoming, autoPay: autoPay,
                                            installment: installment, estimated: estimated))
            if incoming { inflow += remaining } else { outflow += remaining }
        }
        for plan in ledger.plans where plan.active {
            for item in plan.schedule(through: end) where item.date >= interval.start {
                let paid = payments.plans[FixedFlowPaymentKey(id: plan.id, day: Dates.day(item.date)), default: 0]
                append(id: "\(plan.id)-\(item.date.timeIntervalSince1970)", title: plan.title, date: item.date, amount: payments.amount(for: plan), paid: paid,
                       remaining: payments.remaining(for: plan, on: item.date), incoming: plan.inflow, planID: plan.id, autoPay: plan.autoPay,
                       installment: plan.installments.map { (item.index + 1, $0) }, estimated: plan.estimated)
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
        return FixedFlowMonth(date: interval.start, occurrences: rows, remainingOutflow: outflow, remainingInflow: inflow)
    }
}
