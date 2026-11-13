import Foundation

public enum ButlerNoticeTier: String, CaseIterable, Identifiable, Sendable {
    case immediate, ordinary, home
    public var id: Self { self }
    public var title: String { switch self { case .immediate: "马上通知"; case .ordinary: "普通通知"; case .home: "只在主页" } }
}
public struct ButlerNoticePreferences: Codable, Equatable, Sendable {
    public var immediate = false
    public var ordinary = false
    public var home = true
    public init() {}
    private enum CodingKeys: String, CodingKey { case immediate, ordinary, home }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        immediate = try c.decodeIfPresent(Bool.self, forKey: .immediate) ?? false
        ordinary = try c.decodeIfPresent(Bool.self, forKey: .ordinary) ?? false
        home = try c.decodeIfPresent(Bool.self, forKey: .home) ?? true
    }
    public subscript(_ tier: ButlerNoticeTier) -> Bool {
        get { switch tier { case .immediate: immediate; case .ordinary: ordinary; case .home: home } }
        set { switch tier { case .immediate: immediate = newValue; case .ordinary: ordinary = newValue; case .home: home = newValue } }
    }
}

public struct HomeTaskCopy: Equatable, Sendable {
    public var kicker: String
    public var title: String
    public static func monthDay(_ date: Date) -> String {
        let c = Dates.calendar
        return "\(c.component(.month, from: date))月\(c.component(.day, from: date))日"
    }
    public static func make(_ task: HomeTask, now: Date, hidden: Bool) -> Self? {
        func money(_ amount: Int64) -> String { hidden ? "••••" : Money.text(amount, currency: false) }
        switch task {
        case .payday(let due):
            return Self(kicker: "固定进账 · " + monthDay(due.occurrence), title: due.title + " " + money(due.usual) + " 到了吗？")
        case .bill(let bill):
            let late = max(0, Dates.calendar.dateComponents([.day], from: Dates.day(bill.date), to: Dates.day(now)).day ?? 0)
            return Self(kicker: (bill.inflow ? "固定进账 · " : "固定账单 · ") + (late > 0 ? "晚了 \(late) 天" : "今天到期"),
                        title: bill.title + " " + money(bill.amount) + (bill.inflow ? " 到了吗？" : " 付了吗？"))
        case .renewal(let renewal):
            let days = Dates.calendar.dateComponents([.day], from: Dates.day(now), to: Dates.day(renewal.date)).day ?? 1
            return Self(kicker: (days == 1 ? "明天续费" : "\(days) 天后续费") + " · " + renewal.plan.title,
                        title: (renewal.unusedFact.map { $0 + "，" } ?? "") + (renewal.plan.frequency == .yearly ? "一年 " : renewal.plan.frequency.label + " ") +
                            (renewal.plan.currency == .cny ? money(renewal.amount) : renewal.plan.currency.amountText(renewal.plan.amount, hidden: hidden) + "，约 " + money(renewal.amount)))
        case .funding(let funding):
            return Self(kicker: monthDay(funding.bill.date) + " · " + funding.bill.title,
                        title: funding.target.name + "里还差 " + money(funding.amount))
        default: return nil
        }
    }
}

public struct ButlerNotice: Equatable, Identifiable, Sendable {
    public var id: String
    public var taskID: String
    public var tier: ButlerNoticeTier
    public var fireDate: Date
    public var copy: HomeTaskCopy
}
public enum ButlerNotices {
    /// A day-only due date never establishes an imminent charge. Time-sensitive
    /// delivery requires a recorded time and a verified debit-account shortfall.
    public static func planned(_ ledger: Ledger, now: Date) -> [ButlerNotice] {
        let settings = ledger.preferences.butlerNotices ?? ButlerNoticePreferences()
        guard settings.immediate || settings.ordinary else { return [] }
        let hidden = ledger.preferences.hideAmounts || ledger.preferences.lockEnabled
        var result: [ButlerNotice] = []
        func add(_ task: HomeTask, at date: Date, tier: ButlerNoticeTier, asOf: Date) {
            guard settings[tier], !HomeButler.isAnswered(task.id, in: ledger, now: date),
                  let copy = HomeTaskCopy.make(task, now: asOf, hidden: hidden) else { return }
            let suffix: String
            if case .renewal(let renewal) = task { suffix = ":" + Dates.text(renewal.date) } else { suffix = "" }
            result.append(ButlerNotice(id: task.id + suffix, taskID: task.id, tier: tier, fireDate: max(now, date), copy: copy))
        }
        for task in HomeButler.queue(ledger, now: now) {
            switch task {
            case .payday, .bill, .renewal: add(task, at: now, tier: .ordinary, asOf: now)
            case .funding(let value):
                let hasTime = value.bill.date != Dates.day(value.bill.date)
                let immediate = hasTime && value.bill.date >= now && value.bill.date <= now.addingTimeInterval(3600)
                if immediate { add(task, at: now, tier: .immediate, asOf: now) }
                else if Dates.day(value.bill.date) <= Dates.day(now) { add(task, at: now, tier: .ordinary, asOf: now) }
                else if hasTime { add(task, at: value.bill.date.addingTimeInterval(-3600), tier: .immediate, asOf: now) }
            default: break
            }
        }
        let salary = Finance.anchorPlan(in: ledger, now: now)?.id
        let payments = FixedFlowPayments(in: ledger, now: now)
        for plan in ledger.plans where plan.active && plan.stoppedAt == nil {
            guard let due = plan.nextScheduledDate(after: now), payments.remaining(for: plan, on: due) > 0 else { continue }
            let isRenewal = !plan.inflow && plan.nature == .expense && [.monthly, .quarterly, .yearly].contains(plan.frequency) &&
                (plan.category == "订阅" || plan.title.contains("会员") || plan.title.contains("订阅") || plan.title.contains("年付"))
            let lead = isRenewal ? (plan.frequency == .yearly ? 7 : 1) : 0
            let day = Dates.addDays(-lead, to: Dates.day(due))
            guard day > Dates.day(now), let fire = Dates.calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day) else { continue }
            if isRenewal, let renewal = HomeButler.renewals(ledger, now: fire).first(where: { $0.plan.id == plan.id }) {
                add(.renewal(renewal), at: fire, tier: .ordinary, asOf: fire)
            } else if plan.id == salary {
                add(.payday(Payday.Due(planID: plan.id, occurrence: Dates.day(due), title: plan.title, usual: payments.amount(for: plan), lateDays: 0)), at: fire, tier: .ordinary, asOf: fire)
            } else if !plan.inflow {
                let occurrence = Occurrence(id: "\(plan.id)-\(due.timeIntervalSince1970)", title: plan.title, date: due,
                                            amount: payments.remaining(for: plan, on: due), inflow: false, planID: plan.id, overdue: false)
                add(.bill(occurrence), at: fire, tier: .ordinary, asOf: fire)
            }
        }
        var seen: Set<String> = []
        return Array(result.sorted { $0.fireDate == $1.fireDate ? $0.id < $1.id : $0.fireDate < $1.fireDate }.filter { seen.insert($0.id).inserted }.prefix(60))
    }
}
