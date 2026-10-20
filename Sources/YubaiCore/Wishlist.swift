import Foundation

public enum FollowUpChoice: String, CaseIterable, Sendable { case worth = "值得", neutral = "一般", regret = "有点后悔" }
public enum Wishlist {
    public static func matches(_ wish: WishItem, entry: Entry, now: Date) -> Bool {
        guard wish.status == .thinking, wish.amount > 0, entry.deletedAt == nil, entry.nature == .expense,
              entry.date >= Dates.day(wish.createdAt), entry.date <= Dates.addDays(60, to: wish.createdAt), entry.date <= now,
              abs(entry.amount - wish.amount) <= wish.amount / 10 else { return false }
        func normalize(_ text: String) -> String { text.lowercased().filter { $0.isLetter || $0.isNumber } }
        let a = normalize(wish.title), b = normalize(entry.displayTitle)
        guard a.count >= 2, b.count >= 2 else { return a == b && !a.isEmpty }
        if a.contains(b) || b.contains(a) { return true }
        func pairs(_ value: String) -> Set<String> {
            let chars = Array(value)
            return Set((0..<(chars.count - 1)).map { String(chars[$0...($0 + 1)]) })
        }
        let x = pairs(a), y = pairs(b)
        return Double(x.intersection(y).count) / Double(max(1, x.union(y).count)) >= 0.5
    }
    public static func candidates(for wish: WishItem, in ledger: Ledger, now: Date) -> [Entry] {
        let used = Set(ledger.wishlist.filter { $0.id != wish.id }.compactMap(\.boughtEntryID))
        return ledger.activeEntries.filter { !used.contains($0.id) && matches(wish, entry: $0, now: now) }.sorted { $0.date > $1.date }
    }
    public static func markBought(_ wishID: UUID, entryID: UUID, in ledger: inout Ledger) throws {
        guard let i = ledger.wishlist.firstIndex(where: { $0.id == wishID && $0.status == .thinking }),
              let entry = ledger.activeEntries.first(where: { $0.id == entryID && $0.nature == .expense }),
              !ledger.wishlist.contains(where: { $0.id != wishID && $0.boughtEntryID == entryID }) else { throw YubaiError.invalid("请选择一笔尚未关联心愿的支出记录。") }
        ledger.wishlist[i].status = .bought; ledger.wishlist[i].boughtEntryID = entryID
        ledger.wishlist[i].followUpAt = Dates.addDays(30, to: entry.date)
    }
    /// Only newly imported/added rows are eligible. Ambiguity requires a manual choice.
    public static func autoLink(_ ledger: inout Ledger, addedEntryIDs: Set<UUID>, now: Date) {
        let thinking = ledger.wishlist.filter { $0.status == .thinking }
        var links: [(UUID, UUID)] = []
        for wish in thinking {
            let rows = candidates(for: wish, in: ledger, now: now).filter { addedEntryIDs.contains($0.id) }
            guard rows.count == 1, let entry = rows.first,
                  thinking.filter({ matches($0, entry: entry, now: now) }).count == 1 else { continue }
            links.append((wish.id, entry.id))
        }
        for (wish, entry) in links { try? markBought(wish, entryID: entry, in: &ledger) }
    }
    public static func followUps(_ ledger: Ledger, now: Date) -> [CardCandidate] {
        ledger.wishlist.compactMap { wish in
            guard wish.status == .bought, wish.followUpAnswer == nil, let due = wish.followUpAt, due <= now else { return nil }
            let entry = wish.boughtEntryID.flatMap { id in ledger.activeEntries.first { $0.id == id } }
            let area = entry.flatMap { entry in (ledger.profile.restrain + ledger.profile.generous).first { ButlerCards.matches($0, entry: entry, ledger: ledger) } }
            return CardCandidate(kind: .followUp, dedupeKey: "follow:\(wish.id)", evidence: entry.map { [$0.id] } ?? [],
                facts: [CardFact("心愿", wish.title), CardFact("当时的判断", wish.judgment), CardFact("购买金额", cents: entry?.amount ?? wish.amount)],
                title: "买了一个月，觉得值吗？", body: "「\(String(wish.title.prefix(20)))」用了一阵，想听听你的感受。", action: .openWish(wish.id), priority: 2, areaID: area?.id)
        }
    }
    public static func answerFollowUp(_ wishID: UUID, choice: FollowUpChoice, text: String = "", in ledger: inout Ledger, now: Date) throws {
        guard let i = ledger.wishlist.firstIndex(where: { $0.id == wishID && $0.status == .bought }),
              let due = ledger.wishlist[i].followUpAt, due <= now, ledger.wishlist[i].followUpAnswer == nil, text.count <= 3900 else { throw YubaiError.invalid("这条回访已处理或还没到时间。") }
        _ = ButlerCards.refresh(&ledger, now: now)
        ledger.wishlist[i].followUpAnswer = choice.rawValue + (text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : "：" + text)
        ledger.wishlist[i].followUpAnsweredAt = now
        let explanation = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !explanation.isEmpty {
            let redactor = Redactor(ledger: ledger)
            let title = String(redactor.text(ledger.wishlist[i].title).split(whereSeparator: { $0.isNewline }).joined(separator: " ").prefix(40))
            let words = redactor.text(explanation).split(whereSeparator: { $0.isNewline }).joined(separator: " ")
            let note = "买了「\(title)」，一个月后觉得\(choice.rawValue)：\(words)"
            ledger.memories.append(MemoryNote(text: String(note.prefix(200)), kind: .value, source: .followUp,
                createdAt: now, evidence: ledger.wishlist[i].boughtEntryID.map { [$0] } ?? []))
            ledger.updatedAt = max(now, ledger.updatedAt)
        }
        if let card = ledger.cards.first(where: { $0.dedupeKey == "follow:\(wishID)" }) {
            if choice != .neutral { ButlerCards.feedback(choice == .worth ? .worth : .regret, cardID: card.id, in: &ledger, now: now) }
            if let index = ledger.cards.firstIndex(where: { $0.id == card.id }) { ledger.cards[index].dismissedAt = now }
        }
    }
}
