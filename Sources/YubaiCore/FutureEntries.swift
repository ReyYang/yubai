import Foundation

extension Finance {
    /// Pending recorded entries, ordered by date. Kept separate from plan
    /// obligations so recording one never reserves its amount ahead of time.
    public static func upcomingEntries(in ledger: Ledger, now: Date, days: Int = 7) -> [Entry] {
        guard days > 0 else { return [] }
        let end = Dates.addDays(min(3660, days), to: Dates.day(now))
        return ledger.entries.filter { $0.deletedAt == nil && $0.date > now && $0.date < end }.sorted {
            $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date < $1.date
        }
    }
}
