import Foundation

public struct CardFact: Codable, Equatable, Sendable {
    public var label: String
    public var value: String
    public var cents: Int64?
    public init(_ label: String, _ value: String) { self.label = label; self.value = value }
    public init(_ label: String, cents: Int64) { self.label = label; self.value = Money.text(cents); self.cents = cents }
}

public struct CardCandidate: Equatable, Sendable {
    public var kind: CardKind
    public var dedupeKey: String
    public var evidence: [UUID]
    public var facts: [CardFact]
    public var title: String
    public var body: String
    public var action: CardAction
    public var priority: Int
    public var areaID: UUID? = nil
    public var letter: LetterFacts? = nil
    public var meta: String? = nil
    public func card(now: Date) -> ButlerCard {
        var card = ButlerCard(kind: kind, title: kind == .offCharacter ? title : String(title.prefix(14)),
                              body: kind == .offCharacter ? body : String(body.prefix(60)),
                              evidence: kind == .offCharacter ? evidence : Array(evidence.prefix(1000)), action: action, dedupeKey: dedupeKey)
        card.createdAt = now; card.letter = letter; card.facts = facts; card.areaID = areaID; card.priority = priority
        card.meta = meta
        if kind != .offCharacter && evidence.count > 1000 { card.facts?.append(CardFact("明细", "显示 1000 笔")) }
        return card
    }
}

public enum ButlerCards {
    public static var calendar: Calendar {
        var c = Dates.calendar; c.firstWeekday = 2; c.minimumDaysInFirstWeek = 4; return c
    }
    public static func isoWeek(_ date: Date) -> String {
        let c = calendar
        return String(format: "%04d-W%02d", c.component(.yearForWeekOfYear, from: date), c.component(.weekOfYear, from: date))
    }
    public static func topic(_ key: String) -> String {
        if key.hasPrefix("off:") { return key }
        let parts = key.split(separator: ":")
        return parts.prefix(parts.first == "letter" ? 1 : 2).joined(separator: ":")
    }
    static func offCharacterEntryIDs(_ key: String) -> Set<UUID> {
        guard key.hasPrefix("off:") else { return [] }
        return Set(key.dropFirst(4).split(whereSeparator: { $0 == ":" || $0 == "," }).compactMap { UUID(uuidString: String($0)) })
    }
    static func offCharacterEntryIDs(_ card: ButlerCard) -> Set<UUID> {
        guard card.kind == .offCharacter else { return [] }
        return Set(card.evidence).union(offCharacterEntryIDs(card.dedupeKey))
    }
    public static func isMuted(_ key: String, evidence: [UUID] = [], in ledger: Ledger) -> Bool {
        let ids = offCharacterEntryIDs(key).union(evidence)
        return ledger.mutedTopics.contains {
            key == $0 || key.hasPrefix($0 + ":") || !ids.isDisjoint(with: offCharacterEntryIDs($0))
        }
    }
    public static func matches(_ area: ProfileArea, entry: Entry, ledger: Ledger) -> Bool {
        let choice = ledger.normalizedCategory(for: entry)
        let category = choice.category
        let text = entry.title + " " + (entry.purpose ?? "") + " " + entry.note
        return area.match.subcategories.contains { ledger.categoryAssignment(category: CategoryAssignment(path: $0).category, subcategory: CategoryAssignment(path: $0).subcategory).path == choice.path } || area.match.categories.contains { ledger.resolveCategory($0) == category } || area.match.keywords.contains {
            let word = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            return !word.isEmpty && text.localizedCaseInsensitiveContains(word)
        }
    }
    public static func detect(_ ledger: Ledger, now: Date) -> [CardCandidate] {
        var result: [CardCandidate] = []
        let week = calendar.dateInterval(of: .weekOfYear, for: now)!.start
        let month = calendar.dateInterval(of: .month, for: now)!.start
        for area in ledger.profile.restrain {
            let usage = area.usage(in: ledger, now: now)
            let countLimit = area.softLimit?.perWeekCount
            let amountLimit = area.softLimit?.perMonthAmount
            let over = countLimit.map { usage.weekCount >= $0 && usage.weekCount > 0 } == true || amountLimit.map { usage.monthAmount >= $0 && usage.monthAmount > 0 } == true
            let near = countLimit.map { Double(usage.weekCount) >= Double($0) * 0.8 && usage.weekCount > 0 } == true || amountLimit.map { Double(usage.monthAmount) >= Double($0) * 0.8 && usage.monthAmount > 0 } == true
            let noLine = countLimit == nil && amountLimit == nil
            guard over || near || (noLine && usage.weekCount > 0) else { continue }
            let entries = ledger.activeEntries.filter { e in
                guard e.date >= min(week, month), e.date <= now, e.nature == .expense || e.nature == .refund else { return false }
                let source = e.relatedEntryID.flatMap { id in ledger.entries.first { $0.id == id } } ?? e
                return matches(area, entry: source, ledger: ledger)
            }.sorted { $0.date > $1.date }
            var facts = [CardFact("领域", area.title), CardFact("你的原话", area.note), CardFact("本周", "\(usage.weekCount) 次"), CardFact("本月消费", cents: usage.monthAmount)]
            if let countLimit { facts.append(CardFact("每周最多", "\(countLimit) 次")) }
            if let amountLimit { facts.append(CardFact("每月最多", cents: amountLimit)) }
            let detail: String
            if let countLimit, usage.weekCount >= countLimit || (!over && Double(usage.weekCount) >= Double(countLimit) * 0.8) {
                detail = "本周第 \(usage.weekCount) 次 · 你写的最多 \(countLimit) 次"
            } else if let amountLimit {
                detail = "本月 \(Money.text(usage.monthAmount)) · 你写的最多 \(Money.text(amountLimit))"
            } else { detail = "本周有 \(usage.weekCount) 次，落在你想克制的领域。" }
            result.append(CardCandidate(kind: .restrain, dedupeKey: "restrain:\(area.id):\(isoWeek(now))", evidence: entries.map(\.id), facts: facts,
                title: String(area.title.prefix(8)) + "这周的记录", body: detail,
                action: .openEvidence, priority: over ? 1 : 2, areaID: area.id))
        }
        // Forecast points exclude the floor target; below zero means a real cash shortfall.
        // Include the payment day, after that day's outflows.
        let funds = Finance.funds(ledger, now: now)
        let repayments = Set(ledger.plans.filter { $0.nature == .repayment }.map(\.id))
        let daily = Finance.estimatedDailyLiving(ledger, now: now)
        let end = Dates.addDays(30, to: Dates.day(now))
        for item in funds.occurrences where !item.inflow && Dates.day(item.date) >= Dates.day(now) && Dates.day(item.date) <= end {
            let path = funds.points.filter { $0.date <= Dates.day(item.date) }
            guard let low = path.min(by: { $0.conservative < $1.conservative }), low.conservative < 0 else { continue }
            let out = funds.occurrences.filter { !$0.inflow && Dates.day($0.date) <= low.date && !($0.planID.map { repayments.contains($0) } ?? false) }.reduce(Int64(0)) { $0 + $1.amount }
            let days = Dates.calendar.dateComponents([.day], from: Dates.day(now), to: low.date).day ?? 0
            var facts = [CardFact("付款", item.title), CardFact("付款日", Dates.text(item.date)), CardFact("待付", cents: item.amount),
                         CardFact("付款前及当天最少还能花", cents: low.conservative),
                         CardFact("现金", cents: funds.cash), CardFact("信用卡要还", cents: funds.debt), CardFact("在存钱", cents: funds.goals),
                         CardFact("没写用途的进账", cents: funds.uncertainInflow), CardFact("最低点日期", Dates.text(low.date)),
                         CardFact("此前及当天要付", cents: out), CardFact("此前日常开销", cents: daily * Int64(days))]
            if let floor = ledger.profile.floorAmount { facts.append(CardFact("始终留着", cents: floor)) }
            result.append(CardCandidate(kind: .shortfall, dedupeKey: "shortfall:" + item.id, evidence: [], facts: facts,
                title: String(item.title.prefix(9)) + "的缺口", body: "到这笔付款时，最少还能花 \(Money.text(low.conservative))。", action: .openEvidence, priority: 0))
        }
        let asked = questionEntryIDs(in: ledger)
        for entry in ledger.activeEntries where entry.nature == .unknownIn && entry.date < Dates.addDays(-3, to: now) && !asked.contains(entry.id) {
            result.append(CardCandidate(kind: .unknownInflow, dedupeKey: "unknownIn:\(entry.id)", evidence: [entry.id],
                facts: [CardFact("没写用途的进账", cents: entry.amount), CardFact("入账日", Dates.text(entry.date))], title: "这笔是什么？",
                body: "\(Money.text(entry.amount)) 的用途还没记下，可以看看原始记录。", action: .openEvidence, priority: 3))
        }
        for account in ledger.accounts where account.anchorDate < Dates.addDays(-30, to: now) {
            let activity = ledger.activeEntries.filter { $0.delta(for: account.id) != 0 && account.includes($0, posting: $0.postingDate(for: account.id)) && $0.postingDate(for: account.id) <= now }
            guard !activity.isEmpty else { continue }
            let monthKey = String(Dates.text(now).prefix(7))
            result.append(CardCandidate(kind: .staleBalance, dedupeKey: "stale:\(account.id):\(monthKey)", evidence: activity.map(\.id),
                facts: [CardFact("账户", account.name), CardFact("上次对账", Dates.text(account.anchorDate)), CardFact("账本余额", cents: Finance.balance(account, in: ledger, at: now))],
                title: "对一下余额", body: "「\(String(account.name.prefix(12)))」上次对账已超过一个月，之后有新的账目。", action: .reconcileAccount(account.id), priority: 4))
        }
        result += Wishlist.followUps(ledger, now: now)
        result += Wishlist.cooldownDue(ledger, now: now)
        let existing = Set(ledger.cards.map(\.dedupeKey))
        return result.filter { !existing.contains($0.dedupeKey) && !isMuted($0.dedupeKey, in: ledger) }.sorted { a, b in
            a.priority == b.priority ? a.dedupeKey < b.dedupeKey : a.priority < b.priority
        }
    }
    private static func questionEntryIDs(in ledger: Ledger) -> Set<UUID> {
        Set(ledger.imports.filter { $0.undoneAt == nil }.flatMap { $0.organization?.questions ?? [] }.flatMap(\.entryIDs))
            .union(ledger.cards.filter { $0.dismissedAt == nil }.flatMap { $0.importQuestion?.entryIDs ?? [] })
    }
    /// The entire eligible queue, before the five-card window. Aggregation must
    /// use this queue so reminders beyond the window are still reachable.
    public static func queued(_ ledger: Ledger, organizingBatchIDs: Set<UUID> = [],
                              fallbackEntryCount: ((ImportQuestion) -> Int)? = nil) -> [ButlerCard] {
        // Visibility is run-local, never persisted: stopped or relaunched apps
        // immediately expose the questions saved by completed checkpoints.
        let deferredQuestions = Set(ledger.imports.filter { organizingBatchIDs.contains($0.id) }
            .flatMap { $0.organization?.questions.map(\.id) ?? [] })
        let asked = questionEntryIDs(in: ledger)
        let active = Dictionary(uniqueKeysWithValues: ledger.activeEntries.map { ($0.id, $0) })
        return ledger.cards.filter { card in
            guard card.kind != .weeklyLetter, card.dismissedAt == nil, card.feedback == nil,
                  !isMuted(card.dedupeKey, evidence: Array(offCharacterEntryIDs(card)), in: ledger) else { return false }
            if let question = card.importQuestion, deferredQuestions.contains(question.id) { return false }
            if let question = card.importQuestion, question.isFallback {
                return (fallbackEntryCount?(question) ?? UnsortedGroups.entries(for: question, in: ledger).count) > 0
            }
            if card.kind == .unknownInflow {
                return card.evidence.contains { !asked.contains($0) && active[$0]?.nature == .unknownIn }
            }
            return true
        }.sorted {
            let a = rank($0), b = rank($1)
            if a != b { return a < b }
            if $0.kind == .answerQuestion, $1.kind == .answerQuestion {
                let aFallback = $0.importQuestion?.isFallback == true, bFallback = $1.importQuestion?.isFallback == true
                if aFallback != bFallback { return !aFallback }
            }
            if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
            return $0.dedupeKey < $1.dedupeKey
        }
    }
    /// Overflow stays queued; dismissing a card reveals the next one.
    public static func visible(_ ledger: Ledger, organizingBatchIDs: Set<UUID> = [],
                               fallbackEntryCount: ((ImportQuestion) -> Int)? = nil) -> [ButlerCard] {
        Array(queued(ledger, organizingBatchIDs: organizingBatchIDs, fallbackEntryCount: fallbackEntryCount).prefix(5))
    }
    private static func rank(_ card: ButlerCard) -> Int {
        if card.kind == .answerQuestion { return 2 }
        if let priority = card.priority { return priority }
        switch card.kind { case .shortfall: return 0; case .restrain: return 1; case .unknownInflow: return 3; case .staleBalance: return 4; default: return 5 }
    }
    /// The app checks this result before store.update("更新管家卡片"). No-op refreshes
    /// neither change timestamps nor create repository versions.
    @discardableResult public static func refresh(_ ledger: inout Ledger, candidates: [CardCandidate], now: Date) -> Bool {
        var keys = Set(ledger.cards.map(\.dedupeKey)); var changed = false
        for i in ledger.cards.indices {
            guard let dismissed = ledger.cards[i].dismissedAt, dismissed < Dates.addDays(-365, to: now) else { continue }
            let old = ledger.cards[i]
            ledger.cards[i].body = ""; ledger.cards[i].facts = nil; ledger.cards[i].evidence = []
            ledger.cards[i].letter = nil; ledger.cards[i].importQuestion = nil
            if ledger.cards[i] != old { changed = true }
        }
        for candidate in candidates where ledger.cards.count < 5000 && !isMuted(candidate.dedupeKey, evidence: candidate.kind == .offCharacter ? candidate.evidence : [], in: ledger) {
            if keys.insert(candidate.dedupeKey).inserted { ledger.cards.append(candidate.card(now: now)); changed = true }
        }
        return changed
    }
    @discardableResult public static func refresh(_ ledger: inout Ledger, now: Date) -> Bool {
        let candidates = detect(ledger, now: now)
        return refresh(&ledger, candidates: candidates, now: now)
    }
    public static func mute(_ id: UUID, in ledger: inout Ledger, now: Date) {
        guard let i = ledger.cards.firstIndex(where: { $0.id == id }) else { return }
        let ids = offCharacterEntryIDs(ledger.cards[i])
        let key = ids.isEmpty ? topic(ledger.cards[i].dedupeKey) : "off:" + ids.map(\.uuidString).sorted().joined(separator: ":")
        if !ledger.mutedTopics.contains(key) { ledger.mutedTopics.append(key) }
        for i in ledger.cards.indices where topic(ledger.cards[i].dedupeKey) == key || !ids.isDisjoint(with: offCharacterEntryIDs(ledger.cards[i])) { ledger.cards[i].dismissedAt = now }
    }
    public static func feedback(_ value: CardFeedback, cardID: UUID, in ledger: inout Ledger, now: Date) {
        guard let i = ledger.cards.firstIndex(where: { $0.id == cardID }), [.restrain, .offCharacter, .followUp].contains(ledger.cards[i].kind), ledger.cards[i].feedback == nil else { return }
        ledger.cards[i].feedback = value; ledger.cards[i].feedbackAt = now; ledger.cards[i].dismissedAt = now
        let card = ledger.cards[i]
        let ids = Set(card.evidence).union(offCharacterEntryIDs(card))
        let entries = ledger.entries
        let entry = card.evidence.lazy.compactMap { id in entries.first { $0.id == id } }.first ?? entries.first { ids.contains($0.id) }
        let category = entry.map { ledger.resolveCategory($0.category) }
        let existing = (ledger.profile.restrain + ledger.profile.generous).first { $0.id == card.areaID }
        guard let title = existing?.title ?? category else { return }
        var area = existing ?? ProfileArea(title: title, match: AreaMatch(categories: [title]))
        let relevant = ledger.cards.filter { other in
            guard other.feedbackProposalID == nil, [.restrain, .offCharacter, .followUp].contains(other.kind) else { return false }
            let date = other.feedbackAt ?? other.createdAt
            guard date >= Dates.addDays(-60, to: now), date <= now else { return false }
            if let existing { return other.areaID == existing.id }
            let otherIDs = Set(other.evidence).union(offCharacterEntryIDs(other))
            return other.areaID == nil && ledger.entries.contains { otherIDs.contains($0.id) && ledger.resolveCategory($0.category) == category }
        }
        let regrets = relevant.filter { $0.feedback == .regret }
        let worth = relevant.filter { $0.feedback == .worth }
        let relax = value == .worth && worth.count >= 2 && ledger.profile.restrain.contains { $0.id == area.id }
        guard (value == .regret && regrets.count >= 2) || relax, ledger.pendingChanges.count < 100 else { return }
        guard !ledger.pendingChanges.contains(where: { change in
            change.items.contains {
                if case .profile(.upsertArea(let proposed, _)) = $0 { return proposed.id == area.id || proposed.title == area.title }
                if case .profile(.removeArea(let id)) = $0 { return id == area.id }
                return false
            }
        }) else { return }
        let hasLine = area.softLimit?.perWeekCount != nil || area.softLimit?.perMonthAmount != nil
        let move = relax && !hasLine
        if relax {
            if hasLine {
                area.softLimit = SoftLimit(perWeekCount: area.softLimit?.perWeekCount.map { min(10_000, $0 + 1) },
                    perMonthAmount: area.softLimit?.perMonthAmount.map { min(Money.limit, ($0 * 5 + 2) / 4) })
            } else { area.softLimit = nil }
        } else {
            let old = area.softLimit
            let count = old?.perWeekCount.map { max(0, $0 - 1) }
            let amount = old?.perMonthAmount.map { $0 * 4 / 5 }
            area.softLimit = SoftLimit(perWeekCount: count ?? (amount == nil ? max(1, area.usage(in: ledger, now: now).weekCount - 1) : nil), perMonthAmount: amount)
        }
        let reason = move ? "最近两次觉得「\(title)」值得，要记为愿意多花吗？" : (relax ? "最近两次觉得「\(title)」值得，要调高每周次数或每月金额吗？" : "最近两次对「\(title)」有点后悔，要调低每周次数或每月金额吗？")
        var proposal = ChangeSet(source: "卡片反馈", reason: reason,
                                 items: [.profile(.upsertArea(area, stance: move ? .generous : .restrain))])
        proposal.createdAt = now; ledger.pendingChanges.append(proposal)
        let used = Set((relax ? worth : regrets).map(\.id))
        for i in ledger.cards.indices where used.contains(ledger.cards[i].id) { ledger.cards[i].feedbackProposalID = proposal.id }
    }
}
