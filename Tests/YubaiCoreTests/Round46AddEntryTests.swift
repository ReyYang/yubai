import XCTest
@testable import YubaiCore

final class Round46AddEntryTests: XCTestCase {
    private let now = Dates.parse("2026-11-20 12:00")!
    private func ledger() -> Ledger {
        var ledger = Ledger()
        ledger.accounts = [Account(name: "银行卡", balance: 1_000_000, at: Dates.parse("2026-11-01")!),
                           Account(name: "微信", balance: 100_000, at: Dates.parse("2026-11-01")!)]
        ledger.fixedSavings = 500_000; ledger.cycleAnchor = .calendarMonth
        return ledger
    }
    private func entry(_ ledger: Ledger, title: String = "咖啡", amount: Int64 = 3200, category: String = "餐饮", days: Int = -1) -> Entry {
        var entry = Entry(date: Dates.addDays(days, to: now), amount: amount, accountID: ledger.accounts[0].id, title: title, category: category)
        entry.recordedAt = entry.date
        return entry
    }
    func testReceiptWaitsExactlyTwoSeconds() {
        var session = ContinuousEntrySession()
        session.saved([UUID()], at: now, explicitFinish: false)
        XCTAssertTrue(session.receiptVisible)
        XCTAssertFalse(session.shouldDismiss(at: now.addingTimeInterval(1.999)))
        XCTAssertTrue(session.shouldDismiss(at: now.addingTimeInterval(2)))
        XCTAssertEqual(ContinuousEntrySession.receiptFraction(deadline: session.deadline, at: now.addingTimeInterval(0.5)), 0.75)
    }
    func testAnyInteractionCancelsReceiptWithoutLosingEntries() {
        var session = ContinuousEntrySession(); let id = UUID()
        session.saved([id], at: now, explicitFinish: false); session.interact()
        XCTAssertFalse(session.receiptVisible); XCTAssertNil(session.deadline)
        XCTAssertEqual(session.entryIDs, [id]); XCTAssertFalse(session.shouldDismiss(at: now.addingTimeInterval(100)))
    }
    func testEachSaveStartsANewReceiptAndDeduplicatesIDs() {
        var session = ContinuousEntrySession(); let a = UUID(), b = UUID()
        session.saved([a], at: now, explicitFinish: false); session.interact()
        session.saved([a, b], at: now.addingTimeInterval(10), explicitFinish: false)
        XCTAssertEqual(session.entryIDs, [a, b]); XCTAssertTrue(session.receiptVisible)
        XCTAssertEqual(session.deadline, now.addingTimeInterval(12))
    }
    func testAccessibilityWaitsForExplicitFinish() {
        var session = ContinuousEntrySession()
        session.saved([UUID()], at: now, explicitFinish: true)
        XCTAssertTrue(session.receiptVisible); XCTAssertNil(session.deadline)
        XCTAssertFalse(session.shouldDismiss(at: .distantFuture))
        XCTAssertEqual(ContinuousEntrySession.receiptFraction(deadline: nil, at: .distantFuture), 1)
    }
    func testEnablingAccessibilityDuringReceiptCancelsDeadline() {
        var session = ContinuousEntrySession()
        session.saved([UUID()], at: now, explicitFinish: false); session.requireExplicitFinish()
        XCTAssertTrue(session.receiptVisible); XCTAssertNil(session.deadline)
        XCTAssertFalse(session.shouldDismiss(at: .distantFuture))
    }
    func testEmptySaveDoesNotStartAReceipt() {
        var session = ContinuousEntrySession(); session.saved([], at: now, explicitFinish: false)
        XCTAssertTrue(session.entryIDs.isEmpty); XCTAssertFalse(session.receiptVisible); XCTAssertNil(session.deadline)
    }
    func testReceiptProgressClampsAtBothEnds() {
        XCTAssertEqual(ContinuousEntrySession.receiptFraction(deadline: now, at: now.addingTimeInterval(-5)), 1)
        XCTAssertEqual(ContinuousEntrySession.receiptFraction(deadline: now, at: now.addingTimeInterval(5)), 0)
    }
    func testSummaryReflectsEditsDeletionAndUndoInRecordedOrder() throws {
        var ledger = ledger(); let a = entry(ledger), b = entry(ledger, title: "地铁", amount: 800, category: "交通")
        ledger.entries = [b, a]; var session = ContinuousEntrySession()
        session.saved([a.id, b.id], at: now, explicitFinish: true)
        XCTAssertEqual(session.entries(in: ledger).map(\.id), [a.id, b.id]); XCTAssertEqual(session.total(in: ledger), 4000)
        ledger.entries[0].amount = 900; XCTAssertEqual(session.total(in: ledger), 4100)
        ledger.entries[1].deletedAt = now
        XCTAssertEqual(session.entries(in: ledger).map(\.id), [b.id]); XCTAssertEqual(session.total(in: ledger), 900)
        try RecentlyDeleted.restore(a.id, in: &ledger, now: now)
        XCTAssertEqual(session.total(in: ledger), 4100)
    }
    func testSessionIgnoresUnrelatedAndMissingRows() {
        var ledger = ledger(); let a = entry(ledger); ledger.entries = [a]
        var session = ContinuousEntrySession(); session.saved([UUID()], at: now, explicitFinish: true)
        XCTAssertTrue(session.entries(in: ledger).isEmpty); XCTAssertEqual(session.total(in: ledger), 0)
    }
    func testSessionTotalIncludesExpenseIncomeAndTransferOnceEach() {
        var ledger = ledger(); var a = entry(ledger), b = entry(ledger, amount: 20_000), c = entry(ledger, amount: 50_000)
        a.amount = Money.limit; b.nature = .income; c.nature = .transfer; c.otherAccountID = ledger.accounts[1].id
        ledger.entries = [a, b, c]; var session = ContinuousEntrySession()
        session.saved([a.id, b.id, c.id], at: now, explicitFinish: true)
        XCTAssertEqual(session.total(in: ledger), Money.limit + 70_000)
    }
    func testPastTodayAndFutureEntriesShareTheSameLingerRule() {
        let ledger = ledger()
        for days in [-10, 0, 10] {
            var session = ContinuousEntrySession()
            session.saved([entry(ledger, days: days).id], at: now, explicitFinish: false)
            XCTAssertEqual(session.deadline, now.addingTimeInterval(2))
        }
    }
    func testPasteCurrencyGroupingAndArithmeticInExactCents() throws {
        var keypad = EntryKeypad()
        try keypad.paste(" ¥1,234,567.89 "); XCTAssertEqual(keypad.amount, 123_456_789)
        XCTAssertEqual(keypad.groupedResultText, "1,234,567.89")
        try keypad.paste("￥1，200.00＋5−0.01"); XCTAssertEqual(keypad.amount, 120_499)
        XCTAssertEqual(keypad.groupedResultText, "1,204.99")
        try keypad.paste("32+5"); XCTAssertEqual(keypad.amount, 3700)
    }
    func testPasteRejectsMalformedOverflowAndNegativeWithoutChangingDraft() {
        var keypad = EntryKeypad(amount: 3200)
        for text in ["12,34.00", "1.234", "-1.00", "你好", "1e3", "9999999999999", "", "1,000+9999999999999"] {
            XCTAssertThrowsError(try keypad.paste(text), text); XCTAssertEqual(keypad.amount, 3200)
        }
    }
    func testGroupedAmountsAlwaysRetainTwoDecimals() {
        for (amount, text) in [(Int64(0), "0.00"), (1, "0.01"), (100_000, "1,000.00"), (Money.limit, "99,999,999,999.99")] {
            XCTAssertEqual(EntryKeypad(amount: amount).groupedResultText, text)
        }
    }
    func testHintNeedsTwoOfLatestThreeAndNeverUsesSingleKeyword() {
        var ledger = ledger()
        XCTAssertNil(EntryHistory.categoryHint(purpose: "咖啡", nature: .expense, in: ledger, now: now))
        let a = entry(ledger, days: -3), b = entry(ledger, days: -2), c = entry(ledger, category: "购物", days: -1)
        ledger.entries = [a]; XCTAssertNil(EntryHistory.categoryHint(purpose: "咖啡", nature: .expense, in: ledger, now: now))
        ledger.entries = [a, b, c]
        XCTAssertEqual(EntryHistory.categoryHint(purpose: "咖啡", nature: .expense, in: ledger, now: now)?.category, "餐饮")
        ledger.entries.append(entry(ledger, category: "交通", days: 0))
        XCTAssertNil(EntryHistory.categoryHint(purpose: "咖啡", nature: .expense, in: ledger, now: now))
    }
    func testHintExcludesDeletedFutureAndOtherDirection() {
        var ledger = ledger(); let a = entry(ledger, days: -3); var b = entry(ledger, days: -2)
        b.deletedAt = now; var c = entry(ledger, days: -1); c.nature = .income
        ledger.entries = [a, b, c, entry(ledger, days: 1)]
        XCTAssertNil(EntryHistory.categoryHint(purpose: "咖啡", nature: .expense, in: ledger, now: now))
    }
    func testHintMainCategoryCanAgreeAcrossDifferentSmallItems() {
        var ledger = ledger(); var a = entry(ledger, days: -3), b = entry(ledger, days: -2)
        a.subcategory = "早餐"; b.subcategory = "午餐"
        ledger.entries = [a, b, entry(ledger, category: "购物")]
        let hint = EntryHistory.categoryHint(purpose: "咖啡", nature: .expense, in: ledger, now: now)
        XCTAssertEqual(hint?.category, "餐饮"); XCTAssertNil(hint?.subcategory)
    }
    func testPurposeSuggestionsPreferCurrentCategoryAndTimeAndLimitToThree() {
        var ledger = ledger()
        var distant = entry(ledger, title: "夜宵"); distant.date = distant.date.addingTimeInterval(10 * 3600)
        ledger.entries = [distant, entry(ledger, title: "咖啡"), entry(ledger, title: "午饭"), entry(ledger, title: "茶"),
                          entry(ledger, title: "咖啡豆", category: "购物")]
        let rows = EntryHistory.purposeSuggestions(nature: .expense, category: "餐饮", in: ledger, now: now)
        XCTAssertEqual(rows.count, 3); XCTAssertFalse(rows.contains { $0.purpose == "夜宵" || $0.purpose == "咖啡豆" })
        XCTAssertTrue(EntryHistory.purposeSuggestions(nature: .expense, category: nil, in: ledger, now: now, limit: 0).isEmpty)
    }
    func testPurposeRecallRetainsLatestAmountAndCategoryAsOneChoice() {
        var ledger = ledger()
        ledger.entries = [entry(ledger, amount: 2800, days: -2), entry(ledger, amount: 3200, days: -1),
                          entry(ledger, title: "咖啡豆", amount: 12_800, category: "购物")]
        let rows = EntryHistory.recalls(matching: "咖", nature: .expense, in: ledger, now: now)
        XCTAssertEqual(Set(rows.map(\.purpose)), ["咖啡", "咖啡豆"])
        XCTAssertEqual(rows.first { $0.purpose == "咖啡" }?.entry.amount, 3200)
        XCTAssertEqual(rows.first { $0.purpose == "咖啡豆" }?.entry.category, "购物")
    }
    func testRecordedEntryEditDoesNotCreateAnotherEntry() throws {
        var ledger = ledger(); let a = entry(ledger); ledger.entries = [a]
        var edited = a; edited.amount = 2800; edited.purpose = "午饭"
        try ManualBookkeeping.edit(edited, in: &ledger, now: now)
        XCTAssertEqual(ledger.entries.count, 1); XCTAssertEqual(ledger.entries[0].id, a.id)
        XCTAssertEqual(ledger.entries[0].amount, 2800)
    }
}
