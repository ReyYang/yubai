import XCTest
@testable import YubaiCore

final class WishlistTests: XCTestCase {
    func testAutoLinkUsesTitleAmountWindowAndSchedulesFromPurchaseDate() throws {
        let ctx = AssistantFixtures.context(); var ledger = ctx.ledger
        var wish = WishItem(title: "降噪耳机", amount: 10000, judgment: "通勤时会用到。")
        wish.createdAt = Dates.addDays(-40, to: ctx.now); ledger.wishlist = [wish]
        let entry = Entry(date: Dates.addDays(-35, to: ctx.now), amount: 10999, accountID: ledger.accounts[0].id, title: "无线降噪耳机")
        ledger.entries.append(entry)
        Wishlist.autoLink(&ledger, addedEntryIDs: [entry.id], now: ctx.now)
        XCTAssertEqual(ledger.wishlist[0].status, .bought)
        XCTAssertEqual(ledger.wishlist[0].boughtEntryID, entry.id)
        XCTAssertEqual(ledger.wishlist[0].followUpAt, Dates.addDays(30, to: entry.date))
        XCTAssertNil(ledger.wishlist[0].followUpAnswer)
        XCTAssertTrue(ButlerCards.refresh(&ledger, now: ctx.now))
        let cards = ledger.cards.filter { $0.dedupeKey == "follow:\(wish.id)" }
        XCTAssertEqual(cards.count, 1); XCTAssertEqual(cards.first?.kind, .followUp)
        XCTAssertEqual(cards.first?.title, "买了一个月，觉得值吗？")
        XCTAssertEqual(cards.first?.evidence, [entry.id])
        _ = ButlerCards.refresh(&ledger, now: ctx.now)
        XCTAssertEqual(ledger.cards.filter { $0.dedupeKey == "follow:\(wish.id)" }.count, 1)
        try ledger.validate()
        XCTAssertEqual(try LedgerCodec.decode(LedgerCodec.encode(ledger)).wishlist, ledger.wishlist)
    }
    func testNoAutoLinkForOldFutureDifferentOrAmbiguousEntries() {
        let ctx = AssistantFixtures.context(); var ledger = ctx.ledger
        var wish = WishItem(title: "耳机", amount: 10000); wish.createdAt = Dates.addDays(-10, to: ctx.now)
        let first = Entry(date: ctx.now, amount: 10000, accountID: ledger.accounts[0].id, title: "无线耳机")
        var outsideAmount = first; outsideAmount.amount = 11001
        var outsideDate = first; outsideDate.date = Dates.addDays(61, to: wish.createdAt)
        var old = first; old.date = Dates.addDays(-11, to: ctx.now)
        var unrelated = first; unrelated.title = "咖啡"
        XCTAssertFalse(Wishlist.matches(wish, entry: outsideAmount, now: ctx.now))
        XCTAssertFalse(Wishlist.matches(wish, entry: outsideDate, now: Dates.addDays(70, to: ctx.now)))
        XCTAssertFalse(Wishlist.matches(wish, entry: old, now: ctx.now))
        XCTAssertFalse(Wishlist.matches(wish, entry: unrelated, now: ctx.now))
        ledger.wishlist = [wish]; ledger.entries.append(first)
        Wishlist.autoLink(&ledger, addedEntryIDs: [], now: ctx.now)
        XCTAssertEqual(ledger.wishlist[0].status, .thinking)
        var second = first; second.id = UUID(); ledger.entries.append(second)
        Wishlist.autoLink(&ledger, addedEntryIDs: [first.id, second.id], now: ctx.now)
        XCTAssertEqual(ledger.wishlist[0].status, .thinking)
        ledger.entries.removeLast()
        var otherWish = wish; otherWish.id = UUID(); ledger.wishlist.append(otherWish)
        Wishlist.autoLink(&ledger, addedEntryIDs: [first.id], now: ctx.now)
        XCTAssertTrue(ledger.wishlist.allSatisfy { $0.status == .thinking })
    }
    func testFollowUpRegretFeedsExistingProfileProposalPath() throws {
        let ctx = AssistantFixtures.context(); var ledger = ctx.ledger
        let area = ProfileArea(title: "餐饮", match: AreaMatch(categories: ["餐饮"]), softLimit: SoftLimit(perWeekCount: 4))
        ledger.profile.restrain = [area]
        for index in 0..<2 {
            var wish = WishItem(title: "外卖\(index)", amount: 3200); wish.createdAt = Dates.addDays(-40, to: ctx.now)
            let entry = Entry(date: Dates.addDays(-35, to: ctx.now), amount: 3200, accountID: ledger.accounts[0].id, title: wish.title, category: "餐饮")
            ledger.entries.append(entry); ledger.wishlist.append(wish)
            try Wishlist.markBought(wish.id, entryID: entry.id, in: &ledger)
            try Wishlist.answerFollowUp(wish.id, choice: .regret, text: "没有想象中常用", in: &ledger, now: ctx.now)
        }
        XCTAssertEqual(ledger.wishlist[0].followUpAnswer, "有点后悔：没有想象中常用")
        let proposal = try XCTUnwrap(ledger.pendingChanges.first { $0.source == "卡片反馈" })
        XCTAssertEqual(ledger.profile.restrain[0].softLimit?.perWeekCount, 4) // proposal, no silent preference edit
        guard case .profile(.upsertArea(let proposed, .restrain)) = proposal.items[0] else { return XCTFail("missing feedback proposal") }
        XCTAssertEqual(proposed.softLimit?.perWeekCount, 3)
        XCTAssertEqual(ledger.cards.filter { $0.kind == .followUp && $0.feedback == .regret && $0.dismissedAt != nil }.count, 2)
        XCTAssertThrowsError(try Wishlist.answerFollowUp(ledger.wishlist[0].id, choice: .worth, in: &ledger, now: ctx.now))
        try ledger.validate()
    }
    func testNeutralFollowUpDoesNotProposeProfileAndEarlyReplyCannotSave() throws {
        let ctx = AssistantFixtures.context(); var ledger = ctx.ledger
        var wish = WishItem(title: "咖啡杯", amount: 3200); wish.createdAt = Dates.addDays(-40, to: ctx.now)
        let entry = Entry(date: Dates.addDays(-35, to: ctx.now), amount: 3200, accountID: ledger.accounts[0].id, title: "咖啡杯")
        ledger.entries.append(entry); ledger.wishlist.append(wish)
        try Wishlist.markBought(wish.id, entryID: entry.id, in: &ledger)
        XCTAssertThrowsError(try Wishlist.answerFollowUp(wish.id, choice: .worth, in: &ledger, now: entry.date))
        try Wishlist.answerFollowUp(wish.id, choice: .neutral, in: &ledger, now: ctx.now)
        XCTAssertEqual(ledger.wishlist[0].followUpAnswer, "一般"); XCTAssertTrue(ledger.pendingChanges.isEmpty)
        XCTAssertEqual(ledger.cards.first { $0.dedupeKey == "follow:\(wish.id)" }?.dismissedAt, ctx.now)
    }
}
