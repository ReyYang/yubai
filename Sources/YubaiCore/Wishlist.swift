import Foundation

public enum FollowUpChoice: String, CaseIterable, Sendable { case worth = "值得", neutral = "一般", regret = "有点后悔" }
public enum CooldownChoice: String, Sendable { case keep, drop }
public enum Wishlist {
    public static func defaultCooldownDays(amount: Int64) -> Int { amount < 20_000 ? 0 : amount <= 100_000 ? 3 : 7 }
    @discardableResult public static func add(fromVerdict verdict: SubmittedPurchaseVerdict, title: String, amount: Int64,
        category: String? = nil, subcategory: String? = nil, purpose: String = "", in ledger: inout Ledger, now: Date = Date()) throws -> WishItem {
        guard amount > 0, amount <= Money.limit, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw YubaiError.invalid("请核对心愿单的名称和金额。") }
        var wish = WishItem(title: title, amount: amount, purpose: purpose, judgment: verdict.verdict.label + "：" + verdict.reason)
        wish.createdAt = now; wish.source = "fromVerdict"; wish.category = category; wish.subcategory = subcategory
        let days = defaultCooldownDays(amount: amount)
        wish.coolUntil = days == 0 ? nil : Dates.addDays(days, to: now)
        var next = ledger; next.wishlist.append(wish); next.updatedAt = max(now, next.updatedAt)
        try next.validate(); ledger = next; return wish
    }
    public static func cooldownDue(_ ledger: Ledger, now: Date) -> [CardCandidate] {
        ledger.wishlist.compactMap { wish in
            guard wish.status == .thinking, let due = wish.coolUntil, due <= now else { return nil }
            return CardCandidate(kind: .cooldownDue, dedupeKey: "cooldown:\(wish.id)", evidence: [],
                facts: [CardFact("心愿单", wish.title), CardFact("金额", cents: wish.amount), CardFact("日期", Dates.text(due))],
                title: "\(wish.title)，还想要吗？", body: "还想要，或是不要了？", action: .openWish(wish.id), priority: 2)
        }
    }
    public static func answerCooldown(_ wishID: UUID, choice: CooldownChoice, in ledger: inout Ledger, now: Date) throws {
        guard let i = ledger.wishlist.firstIndex(where: { $0.id == wishID && $0.status == .thinking }),
              let due = ledger.wishlist[i].coolUntil, due <= now else { throw YubaiError.invalid("这件心愿还没到日期，或已经回答过了。") }
        ledger.wishlist[i].coolUntil = nil
        if choice == .drop { ledger.wishlist[i].status = .dropped; ledger.wishlist[i].droppedAt = now }
        for j in ledger.cards.indices where ledger.cards[j].dedupeKey == "cooldown:\(wishID)" { ledger.cards[j].dismissedAt = now }
        ledger.updatedAt = max(now, ledger.updatedAt)
    }

    public static func matches(_ wish: WishItem, entry: Entry, now: Date) -> Bool {
        guard wish.status == .thinking, wish.amount > 0, entry.deletedAt == nil, entry.nature == .expense,
              entry.date >= Dates.day(wish.createdAt), entry.date <= Dates.addDays(60, to: wish.createdAt), entry.date <= now,
              abs(entry.amount - wish.amount) <= wish.amount / 10 else { return false }
        return similarTitles(wish.title, entry.displayTitle)
    }
    static func similarTitles(_ first: String, _ second: String) -> Bool {
        func normalize(_ text: String) -> String { text.lowercased().filter { $0.isLetter || $0.isNumber } }
        let a = normalize(first), b = normalize(second)
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
        ledger.wishlist[i].coolUntil = nil; ledger.wishlist[i].status = .bought; ledger.wishlist[i].boughtEntryID = entryID
        ledger.wishlist[i].followUpAt = Dates.addDays(30, to: entry.date)
        for j in ledger.cards.indices where ledger.cards[j].dedupeKey == "cooldown:\(wishID)" { ledger.cards[j].dismissedAt = entry.date }
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
                title: "买了一个月 · 用得怎么样？", body: "\(String(wish.title.prefix(20)))，用得怎么样？", action: .openWish(wish.id), priority: 2, areaID: area?.id)
        }
    }
    public static func answerFollowUp(_ wishID: UUID, choice: FollowUpChoice, text: String = "", in ledger: inout Ledger, now: Date) throws {
        guard let i = ledger.wishlist.firstIndex(where: { $0.id == wishID && $0.status == .bought }),
              let due = ledger.wishlist[i].followUpAt, due <= now, ledger.wishlist[i].followUpAnswer == nil, text.count <= 3900 else { throw YubaiError.invalid("已经回答过或还没满一个月。") }
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
