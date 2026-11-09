import Foundation

public struct LetterPoint: Codable, Equatable, Identifiable, Sendable {
    public var date: Date
    public var available: Int64
    public var id: Date { date }
}
public struct LetterFacts: Codable, Equatable, Sendable {
    public var weeklySavings: Int64? = nil
    public var totalSavings: Int64? = nil
    public var subscriptions: [SubscriptionCandidate]? = nil
    public var learned: [LearnedLine]? = nil
    public var review: ProfileReviewCandidate? = nil
    public var weekEnding: Date
    public var series: [LetterPoint]
    public var spending: Int64
    public var availableChange: Int64
    public var comparison: CardFact
    public var evidence: [UUID]
    public var numbers: [CardFact] {
        [CardFact("本周消费", cents: spending), CardFact("还能花比上周", cents: availableChange), comparison]
            + (weeklySavings.map { [CardFact("本周省下", cents: $0)] } ?? [])
            + (totalSavings.map { [CardFact("累计省下", cents: $0)] } ?? [])
    }
}

public enum WeeklyLetter {
    /// Retrospective estimates, not historical snapshots: use today's profile,
    /// plans, horizon and goals for all days. Rewind any later balance anchor with
    /// recorded postings; remove later entries so payments aren't marked paid early.
    /// Missing historical postings / past settings cannot be reconstructed.
    public static func available(_ ledger: Ledger, at date: Date) -> Int64 {
        Finance.funds(snapshot(ledger, at: date), now: date).available
    }
    static func snapshot(_ ledger: Ledger, at date: Date) -> Ledger {
        var snapshot = ledger
        for i in snapshot.accounts.indices where snapshot.accounts[i].anchorDate > date {
            let account = snapshot.accounts[i]
            var earlier = account; earlier.anchorDate = date
            // Rewind only activity included in the later anchor, not entries recorded after it.
            let later = ledger.activeEntries.filter {
                let posting = $0.postingDate(for: account.id)
                return earlier.includes($0, posting: posting) && !account.includes($0, posting: posting)
            }
            snapshot.accounts[i].anchorBalance -= later.reduce(Int64(0)) { $0 + $1.delta(for: account.id) }
            snapshot.accounts[i].anchorDate = date
        }
        snapshot.entries.removeAll { entry in
            entry.date > date && !(entry.nature.paired && entry.otherAccountID != nil && entry.otherDate.map { $0 <= date } == true)
        }
        // A paired posting on the other account may already exist even when the
        // payment's primary side is in the future. Keep it for balances only.
        for i in snapshot.entries.indices where snapshot.entries[i].date > date {
            snapshot.entries[i].planID = nil; snapshot.entries[i].occurrence = nil
            snapshot.entries[i].rentID = nil; snapshot.entries[i].rentPeriod = nil
        }
        let laterSavings = ledger.savingHistory.filter { $0.cycleEnd >= Dates.day(date) }.reduce(Int64(0)) { $0 + $1.saved }
        snapshot.fixedSavings = max(0, (ledger.fixedSavings ?? 0) - laterSavings)
        return snapshot
    }
    public static func facts(_ ledger: Ledger, weekEnding: Date) -> LetterFacts {
        let lastDay = Dates.day(weekEnding)
        let start = Dates.addDays(-6, to: lastDay)
        let end = Dates.addDays(1, to: lastDay)
        let close = end.addingTimeInterval(-0.001)
        let series = (0..<7).map { offset -> LetterPoint in
            let day = Dates.addDays(offset, to: start)
            let at = Dates.addDays(1, to: day).addingTimeInterval(-0.001)
            return LetterPoint(date: day, available: available(ledger, at: at))
        }
        let review = Finance.review(ledger, from: start, through: end)
        let previousClose = start.addingTimeInterval(-0.001)
        let change = (series.last?.available ?? 0) - available(ledger, at: previousClose)
        let comparison: CardFact
        if ledger.profile.restrain.isEmpty {
            if let largest = review.byCategory.first { comparison = CardFact("最多的分类 · " + largest.category, cents: largest.amount) }
            else { comparison = CardFact("最多的分类", "暂无消费") }
        } else {
            let limited = ledger.profile.restrain.filter { $0.softLimit?.perWeekCount != nil || $0.softLimit?.perMonthAmount != nil }
            let count = limited.filter { area in
                let usage = area.usage(in: ledger, now: close)
                return area.softLimit?.perWeekCount.map { usage.weekCount >= $0 && usage.weekCount > 0 } == true || area.softLimit?.perMonthAmount.map { usage.monthAmount >= $0 && usage.monthAmount > 0 } == true
            }.count
            comparison = limited.isEmpty ? CardFact("想克制的领域", "\(ledger.profile.restrain.count) 个 · 没写次数或金额") : CardFact("达到你写的次数或金额", "\(count) 个 / \(limited.count) 个")
        }
        let evidence = ledger.activeEntries.filter { $0.date >= start && $0.date < end && ($0.nature == .expense || $0.nature == .refund) }.map(\.id)
        var facts = LetterFacts(weekEnding: lastDay, series: series, spending: review.spending, availableChange: change, comparison: comparison, evidence: Array(evidence.prefix(1000)))
        let saved = Savings.summary(ledger: ledger, from: start, to: end, now: close).total
        let total = Savings.total(ledger: ledger, now: close)
        facts.weeklySavings = saved > 0 ? saved : nil; facts.totalSavings = total > 0 ? total : nil
        return facts
    }
    public static func candidate(_ ledger: Ledger, now: Date) -> CardCandidate? {
        let key = "letter:" + ButlerCards.isoWeek(now)
        guard !ledger.accounts.isEmpty, !ButlerCards.isMuted(key, in: ledger), !ledger.cards.contains(where: { $0.dedupeKey == key }) else { return nil }
        let monday = ButlerCards.calendar.dateInterval(of: .weekOfYear, for: now)!.start
        var facts = facts(ledger, weekEnding: Dates.addDays(-1, to: monday))
        facts.review = ProfileReview.candidate(ledger: ledger, now: now)
        let month = String(Dates.text(now).prefix(7))
        if !ledger.cards.contains(where: { $0.kind == .weeklyLetter && String(Dates.text($0.createdAt).prefix(7)) == month }) {
            let subscriptions = SubscriptionCheck.candidates(ledger: ledger, now: now)
            facts.subscriptions = subscriptions.isEmpty ? nil : subscriptions
        }
        let change = facts.availableChange == 0 ? "和上周持平" : (facts.availableChange > 0 ? "比上周增加了" : "比上周减少了")
        let body = "这一周消费 \(Money.text(facts.spending))。还能花\(change)。"
        var candidate = CardCandidate(kind: .weeklyLetter, dedupeKey: key, evidence: facts.evidence,
            facts: facts.numbers + facts.series.map { CardFact(Dates.text($0.date), cents: $0.available) }, title: "每周来信", body: body, action: .openEvidence, priority: 6)
        candidate.letter = facts
        return candidate
    }
    /// Omit exact template duplicates in older saved letters beside their UI cards.
    public static func displayBody(_ body: String, facts: LetterFacts) -> String {
        var result = body.replacingOccurrences(of: "还能花比上周保持原样", with: "还能花和上周持平")
        if let saved = facts.weeklySavings, saved > 0 {
            result = result.replacingOccurrences(of: "本周省下 \(Money.text(saved))。", with: "")
        }
        if let total = facts.totalSavings, total > 0 {
            result = result.replacingOccurrences(of: "累计省下 \(Money.text(total))。", with: "")
        }
        if let subscriptions = facts.subscriptions, !subscriptions.isEmpty {
            result = result.replacingOccurrences(of: "这些还在用吗？" + subscriptions.map(\.title).joined(separator: "、") + "。", with: "")
            result = result.replacingOccurrences(of: "这些还在用吗？", with: "")
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    public static func isFresh(_ card: ButlerCard, now: Date) -> Bool {
        let weekday = ButlerCards.calendar.component(.weekday, from: now)
        return card.kind == .weeklyLetter && card.dismissedAt == nil && (2...4).contains(weekday) && card.dedupeKey == "letter:" + ButlerCards.isoWeek(now)
    }
}
