import Foundation

/// The home and deck share this queue. Only facts with a monetary consequence
/// and an available action belong here; weekly reports stay in their own page.
public enum HomeTask: Identifiable, Equatable, Sendable {
    case payday(Payday.Due), bill(Occurrence), leftover(CycleSaving), gap(Reconciliation.Gap)
    case salary(SalaryCandidate), imports(PendingImportOrganization), butler(ButlerCard)
    case renewal(HomeRenewal), overspend(Overspend.Options), cooldown(WishItem), restraint(HomeRestraint)
    case funding(HomeFunding)

    public var id: String {
        switch self {
        case .payday(let v): "payday:" + v.planID.uuidString + ":" + Dates.text(v.occurrence)
        case .bill(let v): "due:" + v.id
        case .leftover(let v): "leftover:" + Dates.text(v.cycleStart)
        case .gap(let v): "gap:" + Dates.text(v.lastRecorded)
        case .salary(let v): "salary:" + v.key
        case .imports(let v): "imports:" + v.batchIDs.map(\.uuidString).sorted().joined(separator: ":")
        case .butler(let v): "confirmation:" + v.id.uuidString
        case .renewal(let v): v.id
        case .overspend: "overspend"
        case .cooldown(let v): "cooldown:" + v.id.uuidString
        case .restraint(let v): v.id
        case .funding(let v): v.id
        }
    }
    public var priority: Int {
        switch self {
        case .overspend: 0
        case .payday, .butler, .funding: 1
        case .gap, .salary, .imports: 2
        case .renewal, .leftover: 3
        case .cooldown: 4
        case .bill: 5
        case .restraint: 6
        }
    }
}

public struct HomeRenewal: Equatable, Identifiable, Sendable {
    public var plan: Plan
    public var date: Date
    public var amount: Int64
    /// A ledger cannot establish app usage. This flag requires an explicit memory.
    public var explicitlyUnused: Bool
    public var unusedFact: String?
    public var lastMonthUnused: Bool { unusedFact != nil }
    public var id: String { "renewal:" + plan.id.uuidString }
}

public struct HomeFunding: Equatable, Identifiable, Sendable {
    public var bill: Occurrence
    public var target: Account
    public var source: Account
    public var amount: Int64
    public var id: String { "funding:" + bill.id }
}

public struct HomeRestraint: Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var amount: Int64
    public var usual: Int64
    public var entryIDs: [UUID]
    public var interval: DateInterval
}

public enum HomeButler {
    public static func queue(_ ledger: Ledger, now: Date, organizingBatchIDs: Set<UUID> = []) -> [HomeTask] {
        let today = Dates.day(now), funds = Finance.funds(ledger, now: now)
        var items: [HomeTask] = []
        if let over = Overspend.options(ledger, now: now) { items.append(.overspend(over)) }
        let payday = Payday.due(in: ledger, now: now)
        if let payday { items.append(.payday(payday)) }
        items += funding(ledger, now: now).map(HomeTask.funding)
        for bill in funds.occurrences where (bill.planID != nil || bill.rentID != nil) && Dates.day(bill.date) <= today {
            if bill.inflow && bill.planID == payday?.planID { continue }
            items.append(.bill(bill))
        }
        if let gap = Reconciliation.gap(in: ledger, now: now) { items.append(.gap(gap)) }
        if let salary = SalaryDetection.candidate(in: ledger) { items.append(.salary(salary)) }
        if let leftover = Savings.pendingLeftover(in: ledger) { items.append(.leftover(leftover)) }
        items += renewals(ledger, now: now).map(HomeTask.renewal)
        items += ledger.wishlist.filter { $0.status == .thinking && $0.amount > 0 && $0.coolUntil.map { $0 <= now } == true }.map(HomeTask.cooldown)
        let pending = PendingImportOrganization(in: ledger)
        // A completed batch can still contain unsorted rows. Fallback questions
        // below retain their real group routes instead of synthesizing a new batch.
        let pendingIDs = Set(pending.entryIDs)
        if ledger.activeEntries.contains(where: { pendingIDs.contains($0.id) && Classification.isPending($0) }) { items.append(.imports(pending)) }
        for card in ButlerCards.queued(ledger, organizingBatchIDs: organizingBatchIDs) {
            guard card.kind == .answerQuestion || card.kind == .unknownInflow || card.action.map({
                if case .confirmChangeSet = $0 { return true }; return false
            }) == true else { continue }
            if let question = card.importQuestion, question.isFallback,
               Set(question.entryIDs).isSubset(of: pendingIDs) { continue }
            guard confirmationAmount(card, in: ledger) > 0 else { continue }
            items.append(.butler(card))
        }
        items += restraints(ledger, now: now).map(HomeTask.restraint)
        return items.filter { task in
            guard !isAnswered(task.id, in: ledger, now: now) else { return false }
            if (ledger.preferences.butlerNotices ?? ButlerNoticePreferences()).home { return true }
            switch task { case .cooldown, .restraint, .leftover: return false; default: return true }
        }.sorted {
            $0.priority == $1.priority ? $0.id < $1.id : $0.priority < $1.priority
        }
    }

    public static func confirmationAmount(_ card: ButlerCard, in ledger: Ledger) -> Int64 {
        if let value = card.facts?.compactMap(\.cents).first(where: { $0 != 0 }) { return abs(value) }
        if case .confirmChangeSet(let id) = card.action, let change = ledger.pendingChanges.first(where: { $0.id == id }) {
            let amounts = change.items.compactMap { item -> Int64? in
                switch item { case .addPlan(let plan), .updatePlan(let plan): return plan.amount
                case .addEntry(let entry): return entry.amount; default: return nil }
            }
            if let amount = amounts.max(), amount > 0 { return amount }
        }
        let ids = Set(card.importQuestion?.entryIDs ?? card.evidence)
        return ledger.activeEntries.filter { ids.contains($0.id) }.reduce(0) { $0 + $1.amount }
    }

    public static func upcoming(_ ledger: Ledger, now: Date, excluding: String? = nil) -> [Occurrence] {
        let today = Dates.day(now), end = Dates.addDays(7, to: today)
        return Finance.occurrences(in: ledger, now: now, days: 8).filter {
            Dates.day($0.date) >= today && Dates.day($0.date) <= end && $0.id != excluding
        }
    }


    public static func isAnswered(_ key: String, in ledger: Ledger, now: Date) -> Bool {
        guard let date = ledger.butlerAnswers[key] else { return false }
        // "还没" only puts today's question away. "留着" is a permanent answer.
        return key.hasPrefix("due:") || key.hasPrefix("payday:") ? Dates.day(date) == Dates.day(now) : true
    }
    public static func answer(_ key: String, in ledger: inout Ledger, now: Date) {
        ledger.butlerAnswers[key] = now
    }

    /// Monetary runs in imported titles are masked without disabling actions.
    public static func privacyText(_ text: String, hidden: Bool) -> String {
        guard hidden else { return text }
        let pattern = #"(?:[¥￥$€£]\s*)?[0-9]+(?:[,，][0-9]{3})*\.[0-9]{2}|[¥￥$€£]\s*[0-9]+|[0-9]+(?:[,，][0-9]{3})*\s*元"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        return regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "••••")
    }

    public static func renewals(_ ledger: Ledger, now: Date) -> [HomeRenewal] {
        let today = Dates.day(now), payments = FixedFlowPayments(in: ledger, now: now)
        return ledger.plans.compactMap { plan in
            guard plan.active, plan.stoppedAt == nil, !plan.inflow, plan.nature == .expense,
                  [.monthly, .quarterly, .yearly].contains(plan.frequency),
                  plan.category == "订阅" || plan.title.contains("会员") || plan.title.contains("订阅") || plan.title.contains("年付") else { return nil }
            let limit = Dates.addDays(plan.frequency == .yearly ? 7 : 1, to: today)
            guard let due = plan.schedule(through: limit).first(where: {
                $0.date > today && !plan.isSkipped(on: $0.date) && payments.remaining(for: plan, on: $0.date) > 0
            }), due.date <= limit else { return nil }
            let unused = ledger.memories.contains { memory in
                memory.text.contains(plan.title) && ["不用了", "不看了", "没用了"].contains(where: memory.text.contains)
            }
            let usage = ledger.memories.filter { memory in
                memory.text.contains(plan.title) && Dates.calendar.isDate(memory.createdAt, equalTo: now, toGranularity: .month)
            }.sorted { $0.createdAt > $1.createdAt }.compactMap { memory in
                ["上个月没打开过", "上个月没用过"].first(where: memory.text.contains)
            }.first
            return HomeRenewal(plan: plan, date: due.date, amount: payments.amount(for: plan), explicitlyUnused: unused || usage != nil, unusedFact: usage)
        }.filter { $0.amount > 0 && !isAnswered($0.id, in: ledger, now: now) }.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }
    }

    public static func funding(_ ledger: Ledger, now: Date) -> [HomeFunding] {
        let accounts = ledger.accounts.filter { !$0.archived && ($0.kind == .cash || $0.kind == .bank) }
        let bills = upcoming(ledger, now: now).filter { !$0.inflow && $0.planID != nil }
        let planAccounts = Dictionary(uniqueKeysWithValues: ledger.plans.compactMap { plan in plan.accountID.map { (plan.id, $0) } })
        var obligations: [UUID: Int64] = [:]
        for bill in bills { if let id = bill.planID.flatMap({ planAccounts[$0] }) { obligations[id, default: 0] += bill.amount } }
        var outflow: [UUID: Int64] = [:]
        return bills.compactMap { bill in
            guard let plan = ledger.plans.first(where: { $0.id == bill.planID }), let target = accounts.first(where: { $0.id == plan.accountID }) else { return nil }
            outflow[target.id, default: 0] += bill.amount
            let shortfall = outflow[target.id, default: 0] - Finance.balance(target, in: ledger, at: now)
            guard shortfall > 0 else { return nil }
            let sources = accounts.filter { $0.id != target.id && Finance.balance($0, in: ledger, at: now) - obligations[$0.id, default: 0] >= shortfall }
            guard let source = sources.first(where: { $0.name.contains("微信") }) ?? sources.first else { return nil }
            return HomeFunding(bill: bill, target: target, source: source, amount: shortfall)
        }
    }
    public static func confirmRent(_ bill: Occurrence, in ledger: inout Ledger, now: Date) throws {
        guard let rentID = bill.rentID, let rent = ledger.rents.first(where: { $0.id == rentID }),
              Finance.occurrences(in: ledger, now: now, days: 1).contains(bill),
              let account = rent.accountID ?? ManualBookkeeping.defaultAccount(in: ledger)?.id else { throw YubaiError.invalid("这期账单或账户已经变了。") }
        var next = ledger
        var entry = Entry(date: now, amount: bill.amount, nature: bill.inflow ? .contribution : .expense,
                          accountID: account, title: bill.title, category: bill.inflow ? "其他收入" : "居住")
        entry.rentID = rentID; entry.rentPeriod = bill.rentMonth ?? Dates.day(bill.date); entry.recordedAt = now; entry.source = "手动"
        next.entries.append(entry)
        try next.validate(); ledger = next
    }
    public static func transferFunding(_ value: HomeFunding, in ledger: inout Ledger, now: Date) throws {
        guard funding(ledger, now: now).contains(value), !isAnswered(value.id, in: ledger, now: now) else { throw YubaiError.invalid("账户或账单金额已经变了。") }
        var next = ledger
        let change = try ManualBookkeeping.change(amount: value.amount, nature: .transfer, accountID: value.source.id, otherAccountID: value.target.id,
                                                   day: now, purpose: value.bill.title, category: "内部移动", now: now)
        try change.apply(to: &next)
        answer(value.id, in: &next, now: now)
        try next.validate(); ledger = next
    }

    public static func stop(_ renewal: HomeRenewal, in ledger: inout Ledger, now: Date) throws {
        guard renewals(ledger, now: now).contains(renewal) else { throw YubaiError.invalid("这项固定账单已经变了。") }
        var next = ledger
        var change = ChangeSet(source: "用户操作", reason: "停掉", items: [.endPlan(renewal.plan.id, now)])
        change.createdAt = now
        try change.apply(to: &next)
        answer(renewal.id, in: &next, now: now)
        ButlerSavings.synchronize(&next, now: now)
        try next.validate(); ledger = next
    }

    public static func prepareMerchantSort(_ pending: PendingImportOrganization, in ledger: inout Ledger) -> UUID? {
        let ids = Set(pending.entryIDs)
        for batch in ledger.imports where batch.undoneAt == nil {
            if let question = batch.organization?.questions.first(where: { $0.isFallback && !Set($0.entryIDs).isDisjoint(with: ids) }) { return question.id }
        }
        guard let index = ledger.imports.firstIndex(where: { pending.batchIDs.contains($0.id) && $0.undoneAt == nil }) else { return nil }
        let entries = ledger.activeEntries.filter { $0.batchID == ledger.imports[index].id && ids.contains($0.id) && Classification.isPending($0) }
        guard !entries.isEmpty else { return nil }
        let question = ImportQuestion(text: "\(entries.count) 笔还没分类", entryIDs: entries.map(\.id), options: [], groupsByParty: true)
        if ledger.imports[index].organization == nil {
            ledger.imports[index].organization = ImportOrganization(changeSet: ChangeSet(source: "本机整理", reason: "整理分类", items: []), questions: [], skipped: [])
        }
        ledger.imports[index].organization?.questions.append(question)
        return question.id
    }

    public static func restraints(_ ledger: Ledger, now: Date) -> [HomeRestraint] {
        guard let previous = Finance.completedCycles(ledger, now: now, limit: 1).first else { return [] }
        let funds = Finance.funds(ledger, now: now)
        let elapsed = max(0, Dates.calendar.dateComponents([.day], from: funds.cycleStart, to: Dates.day(now)).day ?? 0) + 1
        let previousEnd = min(previous.end, Dates.addDays(elapsed, to: previous.start))
        let interval = DateInterval(start: funds.cycleStart, end: now.addingTimeInterval(0.001))
        func rows(_ area: ProfileArea, from: Date, to: Date) -> [Entry] {
            ledger.activeEntries.filter { entry in
                guard entry.date >= from, entry.date < to, entry.nature == .expense || entry.nature == .refund else { return false }
                let source = entry.relatedEntryID.flatMap { id in ledger.entries.first { $0.id == id } } ?? entry
                return ButlerCards.matches(area, entry: source, ledger: ledger)
            }
        }
        return ledger.profile.restrain.compactMap { area in
            let current = rows(area, from: interval.start, to: interval.end)
            let old = rows(area, from: previous.start, to: previousEnd)
            let amount = current.reduce(Int64(0)) { $0 + Finance.spendingAmount($1, ledger: ledger) }
            let usual = old.reduce(Int64(0)) { $0 + Finance.spendingAmount($1, ledger: ledger) }
            guard !old.isEmpty, usual > 0, amount > usual else { return nil }
            return HomeRestraint(id: "restraint:" + area.id.uuidString + ":" + Dates.text(funds.cycleStart), title: area.title,
                                 amount: amount, usual: usual, entryIDs: current.map(\.id), interval: interval)
        }
    }
}

/// The deck stores IDs, so resolving a card cannot leave a stale copy actionable.
public struct ButlerDeck: Equatable, Sendable {
    public private(set) var ids: [String] = []
    public private(set) var position = 0
    public init() {}
    public mutating func reconcile(_ eligible: [String]) {
        let valid = Set(eligible)
        ids.removeAll { !valid.contains($0) }
        let known = Set(ids)
        ids += eligible.filter { !known.contains($0) }
        position = ids.isEmpty ? 0 : position % ids.count
    }
    public mutating func cycle(backwards: Bool = false) {
        guard ids.count > 1 else { return }
        if backwards { ids.insert(ids.removeLast(), at: 0); position = (position + ids.count - 1) % ids.count }
        else { ids.append(ids.removeFirst()); position = (position + 1) % ids.count }
    }
    public mutating func focus(_ id: String) {
        guard let index = ids.firstIndex(of: id) else { return }
        ids = Array(ids[index...]) + Array(ids[..<index]); position = index
    }
}

public enum FirstUse {
    /// Create the default account only when the person starts recording. Before
    /// a balance is supplied its zero anchor makes the number income minus spend.
    public static func prepareForEntry(_ ledger: inout Ledger, now: Date) {
        ledger.preferences.onboardingComplete = true
        guard ledger.accounts.isEmpty else { return }
        // No user-supplied balance exists yet. Include backdated first entries
        // from the entire supported ledger range in this zero opening balance.
        ledger.accounts.append(Account(name: "现金", kind: .cash, balance: 0, at: Date(timeIntervalSince1970: -2_208_988_800)))
    }
}
