import Foundation

public struct ProfileReviewUsage: Codable, Equatable, Sendable {
    public let weekStart: Date
    public let count: Int
    public let amount: Int64
}
public struct ProfileReviewCandidate: Codable, Equatable, Sendable {
    public enum Target: Codable, Equatable, Sendable { case area(UUID), principle(String) }
    public let target: Target
    public let text: String
    public let confirmedAt: Date
    /// Current partial ISO week and the three preceding weeks, oldest first.
    /// Principles have no selectors, so they carry no invented usage.
    public let usage: [ProfileReviewUsage]
}

public enum ProfileReview {
    public static func candidate(ledger: Ledger, now: Date = Date()) -> ProfileReviewCandidate? {
        let cutoff = Dates.addDays(-90, to: now)
        let monday = ButlerCards.calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? Dates.day(now)
        var candidates: [ProfileReviewCandidate] = ledger.profile.restrain.compactMap { area in
            guard let date = area.confirmedAt, date < cutoff else { return nil }
            let weeks = (-3...0).map { offset -> ProfileReviewUsage in
                let start = Dates.addDays(offset * 7, to: monday)
                let end = min(now, Dates.addDays(7, to: start).addingTimeInterval(-0.001))
                let usage = area.usage(in: ledger, from: start, through: end)
                return ProfileReviewUsage(weekStart: start, count: usage.count, amount: usage.amount)
            }
            return ProfileReviewCandidate(target: .area(area.id), text: words(area), confirmedAt: date, usage: weeks)
        }
        for text in ledger.profile.principles {
            guard let date = ledger.profile.principleDates[text], date < cutoff else { continue }
            candidates.append(ProfileReviewCandidate(target: .principle(text), text: text, confirmedAt: date, usage: []))
        }
        return candidates.sorted {
            if $0.confirmedAt != $1.confirmedAt { return $0.confirmedAt < $1.confirmedAt }
            return key($0.target) < key($1.target)
        }.first
    }
    private static func key(_ target: ProfileReviewCandidate.Target) -> String {
        switch target { case .area(let id): return "area:" + id.uuidString; case .principle(let text): return "principle:" + text }
    }
    private static func words(_ area: ProfileArea) -> String {
        area.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? area.title : area.note
    }
    private static func check(_ candidate: ProfileReviewCandidate, in ledger: Ledger) throws {
        switch candidate.target {
        case .area(let id):
            guard let area = ledger.profile.restrain.first(where: { $0.id == id }), area.confirmedAt == candidate.confirmedAt,
                  words(area) == candidate.text else { throw YubaiError.invalid("这条消费观已改变，请刷新来信。") }
        case .principle(let text):
            guard candidate.text == text, ledger.profile.principles.contains(text), ledger.profile.principleDates[text] == candidate.confirmedAt else { throw YubaiError.invalid("这条原则已改变，请刷新来信。") }
        }
    }
    public static func keep(_ candidate: ProfileReviewCandidate, in ledger: inout Ledger, now: Date = Date()) throws {
        try check(candidate, in: ledger)
        var next = ledger
        switch candidate.target {
        case .area(let id):
            if let i = next.profile.restrain.firstIndex(where: { $0.id == id }) { next.profile.restrain[i].confirmedAt = now }
        case .principle(let text): next.profile.principleDates[text] = now
        }
        next.profile.updatedAt = now; next.updatedAt = max(now, ledger.updatedAt)
        try next.validate(); ledger = next
    }
    /// Returns a proposal; the caller presents and confirms it through ChangeSet.
    public static func remove(_ candidate: ProfileReviewCandidate, in ledger: Ledger, now: Date = Date()) throws -> ChangeSet {
        try check(candidate, in: ledger)
        let change: ProfileChange
        switch candidate.target { case .area(let id): change = .removeArea(id); case .principle(let text): change = .removePrinciple(text) }
        var proposal = ChangeSet(source: "画像回顾", reason: String(("回顾这条还算不算数：" + candidate.text).prefix(4000)), items: [.profile(change)])
        proposal.createdAt = now; try proposal.validateStructure(); return proposal
    }
}
