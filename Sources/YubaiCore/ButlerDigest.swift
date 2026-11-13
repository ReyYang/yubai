import Foundation

/// A bounded time window, never a copy of the ledger's raw history. Money is
/// integer cents; the usual is the preceding 12 weeks normalized to four weeks.
public struct ButlerDigest: Codable, Equatable, Sendable {
    public struct Group: Codable, Equatable, Sendable {
        public let key: String
        public let count: Int
        public let sumCents: Int64
        public let usualCount: Double
        public let usualSumCents: Int64
        public let entryIDs: [UUID]
    }
    public struct Charge: Codable, Equatable, Sendable {
        public let id: UUID
        public let title: String
        public let amountCents: Int64
        public let frequency: Frequency
    }
    public struct Wish: Codable, Equatable, Sendable {
        public let id: UUID
        public let title: String
        public let amountCents: Int64
    }
    public struct Saving: Codable, Equatable, Sendable {
        public let savedCents: Int64
        public let targetCents: Int64
        public let leftoverCycle: String?
        public let leftoverCents: Int64
    }
    public let start: Date
    public let end: Date
    public let categories: [Group]
    public let weekdays: [Group]
    public let merchants: [Group]
    /// Category × weekday × merchant permits evidence selection without raw rows.
    public let candidates: [Group]
    public let newMerchants: [String]
    public let recurringCharges: [Charge]
    public let wishes: [Wish]
    public let saving: Saving
    public let profile: SpendingProfile
    public let memories: [MemoryNote]
    public let mutedTopics: [String]
    public var candidateIDs: Set<UUID> { Set(candidates.flatMap(\.entryIDs)) }

    public static func build(_ ledger: Ledger, now: Date) -> Self {
        // Today plus the previous 27 days, through the precise snapshot time.
        let start = Dates.addDays(-27, to: Dates.day(now))
        let baseline = Dates.addDays(-84, to: start)
        let rows = ledger.activeEntries.filter {
            $0.date >= baseline && $0.date <= now && ($0.nature == .expense || $0.nature == .refund)
        }.sorted { $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date < $1.date }
        let current = rows.filter { $0.date >= start }, old = rows.filter { $0.date < start }
        func category(_ e: Entry) -> String { ledger.normalizedCategory(for: e).category }
        func merchant(_ e: Entry) -> String { CategoryMemory.key(e.title) }
        func weekday(_ e: Entry) -> String { String(Dates.calendar.component(.weekday, from: e.date)) }
        func groups(includeIDs: Bool = false, allKeys: [String] = [], _ key: (Entry) -> String) -> [Group] {
            let recent = Dictionary(grouping: current, by: key), usual = Dictionary(grouping: old, by: key)
            return Set(recent.keys).union(usual.keys).union(allKeys).sorted().map { k in
                let entries = recent[k] ?? [], prior = usual[k] ?? []
                return Group(key: k, count: entries.count,
                    sumCents: entries.reduce(0) { $0 + Finance.spendingAmount($1, ledger: ledger) },
                    usualCount: Double(prior.count) / 3,
                    usualSumCents: prior.reduce(Int64(0)) { $0 + Finance.spendingAmount($1, ledger: ledger) } / 3,
                    entryIDs: includeIDs ? entries.map(\.id) : [])
            }
        }
        // A merchant seen before the usual's twelve-week baseline is still
        // known. Consult that history locally without putting its rows on wire.
        let priorMerchants = Set(ledger.activeEntries.filter {
            $0.date < start && ($0.nature == .expense || $0.nature == .refund)
        }.map(merchant))
        let funds = Finance.funds(ledger, now: now), leftover = Savings.pendingLeftover(in: ledger)
        let payments = FixedFlowPayments(in: ledger, now: now)
        return Self(start: start, end: now, categories: groups(category), weekdays: groups(allKeys: (1...7).map(String.init), weekday), merchants: groups(merchant),
            candidates: groups(includeIDs: true) { category($0) + "|" + weekday($0) + "|" + merchant($0) }.filter { !$0.entryIDs.isEmpty },
            newMerchants: Set(current.map(merchant)).subtracting(priorMerchants).filter { !$0.isEmpty }.sorted(),
            recurringCharges: ledger.plans.filter { $0.active && $0.stoppedAt == nil && !$0.inflow && $0.frequency != .once }
                .sorted { $0.id.uuidString < $1.id.uuidString }.map { Charge(id: $0.id, title: $0.title, amountCents: payments.amount(for: $0), frequency: $0.frequency) },
            wishes: ledger.wishlist.filter { $0.status == .thinking }.sorted { $0.id.uuidString < $1.id.uuidString }
                .map { Wish(id: $0.id, title: $0.title, amountCents: $0.amount) },
            saving: Saving(savedCents: ledger.fixedSavingsTotal(now: now), targetCents: funds.savingTarget,
                leftoverCycle: leftover.map { Dates.text($0.cycleStart) }, leftoverCents: leftover?.unspent ?? 0),
            profile: ledger.profile,
            memories: ledger.memories.sorted { $0.id.uuidString < $1.id.uuidString }, mutedTopics: ledger.mutedTopics.sorted())
    }

    public func json() throws -> JSONValue {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        return try JSONValue.parse(String(decoding: encoder.encode(self), as: UTF8.self))
    }
}
