import XCTest
@testable import YubaiCore

final class Round40Tests: XCTestCase {
    let now = Dates.parse("2026-11-06 12:30:00")!
    func fixture() -> Ledger { var l = Ledger(); l.accounts = [Account(name: "卡")]; return l }
    func row(_ ledger: Ledger, _ date: String, _ title: String = "午饭", _ category: String = "餐饮", _ nature: Nature = .expense) -> Entry {
        Entry(date: Dates.parse(date)!, amount: 3200, nature: nature, accountID: ledger.accounts[0].id, title: title, category: category)
    }
    func testNoHistoryDoesNotGuessWords() {
        XCTAssertNil(EntryHistory.suggestion(purpose: "午饭咖啡地铁", nature: .expense, in: fixture(), at: now))
    }
    func testSamePurposeUsesLastChoiceIncludingSubcategory() {
        var l = fixture(); var latest = row(l, "2026-11-05 21:00:00", "公司午饭", "餐饮"); latest.subcategory = "午餐"
        l.entries = [row(l, "2026-11-04 12:00:00", "公司午饭", "交通"), latest]
        XCTAssertEqual(EntryHistory.suggestion(purpose: " 公司午饭 ", nature: .expense, in: l, at: now), .init(category: "餐饮", subcategory: "午餐"))
    }
    func testTimeWindowCountsCurrentNatureAndIgnoresDeletedAndFuture() {
        var l = fixture(); var deleted = row(l, "2026-11-05 12:30:00", "删除", "购物"); deleted.deletedAt = now
        l.entries = [row(l, "2026-11-03 10:30:00", "早饭"), row(l, "2026-11-04 14:30:00", "晚午饭"), row(l, "2026-11-05 14:31:00", "车", "交通"), row(l, "2026-11-07 12:00:00", "购物", "购物"), deleted, row(l, "2026-11-05 12:00:00", "工资", "工资奖金", .income)]
        XCTAssertEqual(EntryHistory.suggestion(purpose: "", nature: .expense, in: l, at: now)?.category, "餐饮")
        XCTAssertEqual(EntryHistory.suggestion(purpose: "", nature: .income, in: l, at: now)?.category, "工资奖金")
        XCTAssertNil(EntryHistory.suggestion(purpose: "", nature: .transfer, in: l, at: now))
    }
    func testTimeWindowWrapsMidnight() {
        var l = fixture(); l.entries = [row(l, "2026-11-05 23:30:00")]
        XCTAssertEqual(EntryHistory.suggestion(purpose: "", nature: .expense, in: l, at: Dates.parse("2026-11-06 00:20:00")!)?.category, "餐饮")
    }
    func testLatestUnsortedPurposeStaysUnsorted() {
        var l = fixture(); l.entries = [row(l, "2026-11-04 12:30:00"), row(l, "2026-11-05 12:30:00", "午饭", Classification.pendingCategory)]
        XCTAssertNil(EntryHistory.suggestion(purpose: "午饭", nature: .expense, in: l, at: now))
    }
    func testRecallFiltersNatureAndRestoresLatestFields() {
        var l = fixture(); l.accounts.append(Account(name: "另一张卡"))
        var latest = row(l, "2026-11-05 12:00:00"); latest.subcategory = "午餐"; latest.accountID = l.accounts[1].id
        l.entries = [row(l, "2026-11-04 12:00:00"), latest, row(l, "2026-11-06 12:00:00", "工资", "工资奖金", .income)]
        let result = EntryHistory.recentPurposes(in: l, nature: .expense, now: now)
        XCTAssertEqual(result.count, 1); XCTAssertEqual(result[0].count, 2)
        XCTAssertEqual(result[0].entry.accountID, l.accounts[1].id); XCTAssertEqual(result[0].entry.subcategory, "午餐")
    }
    func testRecallFrequencyAndRecencyBothMatter() {
        var l = fixture(); l.entries = [row(l, "2026-11-05 12:00:00"), row(l, "2026-11-04 12:00:00"), row(l, "2026-11-06 12:00:00", "地铁", "交通")]
        XCTAssertEqual(EntryHistory.recentPurposes(in: l, nature: .expense, now: now).first?.purpose, "午饭")
        l.entries[0].date = Dates.parse("2025-01-01 12:00:00")!; l.entries[1].date = Dates.parse("2025-01-02 12:00:00")!
        XCTAssertEqual(EntryHistory.recentPurposes(in: l, nature: .expense, now: now).first?.purpose, "地铁")
    }
    func testSearchSpansMonthsAndTotalsOnlyMatches() {
        var l = fixture(); l.entries = [row(l, "2026-11-05 12:00:00", "房租", "居住"), row(l, "2026-10-01 12:00:00", "房租", "居住"), row(l, "2026-09-01 12:00:00", "午饭"), row(l, "2026-10-02 12:00:00", "房租分摊", "其他收入", .income)]
        let result = EntryTimeline.snapshot(sortedEntries: l.entries.sorted { $0.date > $1.date }, ledger: l, month: now, search: "房租")
        XCTAssertEqual(result.count, 3); XCTAssertEqual(result.months.count, 2)
        XCTAssertEqual(result.spending, 6400); XCTAssertEqual(result.income, 3200)
        XCTAssertEqual(result.months[1].spending, 3200); XCTAssertEqual(result.months[1].income, 3200)
        XCTAssertEqual(EntryTimeline.snapshot(sortedEntries: l.entries.sorted { $0.date > $1.date }, ledger: l, month: now, search: " ").count, 1)
    }
    func testSearchFiltersDeletedAndNatureAndAddsDayIncome() {
        var l = fixture(); var deleted = row(l, "2026-10-01 12:00:00"); deleted.deletedAt = now
        l.entries = [deleted, row(l, "2026-11-05 12:00:00", "工资", "工资奖金", .income)]
        let result = EntryTimeline.snapshot(sortedEntries: l.entries.sorted { $0.date > $1.date }, ledger: l, month: now)
        XCTAssertEqual(result.days.first?.income, 3200)
        XCTAssertEqual(EntryTimeline.snapshot(sortedEntries: l.entries, ledger: l, month: now, search: "午饭", filter: .expense).count, 0)
    }
    func testTrashCutoffIsExactAndRestorePreservesEntry() throws {
        var l = fixture(); var a = row(l, "2026-10-01 12:00:00"); a.deletedAt = RecentlyDeleted.cutoff(now: now).addingTimeInterval(1)
        var b = a; b.id = UUID(); b.deletedAt = RecentlyDeleted.cutoff(now: now)
        l.entries = [a, b]
        XCTAssertEqual(RecentlyDeleted.entries(in: l, now: now).map(\.id), [a.id])
        XCTAssertThrowsError(try RecentlyDeleted.restore(b.id, in: &l, now: now))
        try RecentlyDeleted.restore(a.id, in: &l, now: now)
        var expected = a; expected.deletedAt = nil
        XCTAssertEqual(l.entries[0], expected); XCTAssertEqual(RecentlyDeleted.purge(in: &l, now: now), 1)
        XCTAssertEqual(l.entries, [expected])
    }
    func testTrashOrderingDaysAndClearKeepActiveEntries() {
        var l = fixture(); var a = row(l, "2026-10-01 12:00:00"); a.deletedAt = Dates.addDays(-8, to: now)
        var b = a; b.id = UUID(); b.deletedAt = now
        let active = row(l, "2026-11-06 12:00:00")
        l.entries = [a, active, b]
        XCTAssertEqual(RecentlyDeleted.entries(in: l, now: now).map(\.id), [b.id, a.id])
        XCTAssertEqual(RecentlyDeleted.daysRemaining(a, now: now), 22)
        RecentlyDeleted.clear(in: &l); XCTAssertEqual(l.entries, [active])
    }
    func testManualUnsortedDoesNotAcquireKeywordGuessAtSave() throws {
        var l = fixture()
        let change = try ManualBookkeeping.change(amount: 3200, nature: .expense, accountID: l.accounts[0].id,
                                                  day: now, purpose: "午饭咖啡", category: Classification.pendingCategory, now: now)
        try change.apply(to: &l)
        XCTAssertEqual(l.entries[0].category, Classification.pendingCategory)
        XCTAssertNil(l.entries[0].subcategory)
    }
    func testExplicitPendingEditDoesNotGuessFromPurpose() throws {
        var l = fixture(); var original = row(l, "2026-11-05 12:00:00", "午饭", "餐饮")
        l.entries = [original]
        original.category = Classification.pendingCategory; original.subcategoryUserEdited = true
        try ManualBookkeeping.edit(original, in: &l)
        XCTAssertEqual(l.entries[0].category, Classification.pendingCategory); XCTAssertNil(l.entries[0].subcategory)
    }
    func testBackdatedManualEntryUsesSaveClock() {
        let value = ManualBookkeeping.saveDate(for: Dates.parse("2026-10-01")!, now: now)
        XCTAssertEqual(Dates.calendar.component(.hour, from: value), 12)
        XCTAssertEqual(Dates.calendar.component(.minute, from: value), 30)
        XCTAssertEqual(Dates.calendar.component(.day, from: value), 1)
    }
}


extension Round40Tests {
    func testContinuousLedgerKeepsPreviousDayAtPaydayAndFiltersMonthTotals() {
        var l = fixture()
        let today = Dates.parse("2026-11-10 12:00")!
        l.plans = [Plan(title: "工资", amount: 800_000, dueDate: Dates.parse("2026-10-10")!, frequency: .monthly, inflow: true, nature: .income)]
        var fixed = row(l, "2026-11-10", "补贴", "补贴", .income); fixed.intoFixedSavings = true
        var deleted = row(l, "2026-10-20"); deleted.deletedAt = today
        l.entries = [fixed, row(l, "2026-11-09"), row(l, "2026-10-31"), row(l, "2026-09-30"), deleted]
        let sorted = l.entries.sorted { $0.date > $1.date }
        let all = EntryTimeline.snapshot(sortedEntries: sorted, ledger: l, month: today, allMonths: true)
        XCTAssertEqual(Finance.cycle(in: l, now: today).start, Dates.parse("2026-11-10"))
        XCTAssertEqual(all.count, 4); XCTAssertEqual(all.months.count, 3)
        XCTAssertEqual(all.days.map(\.date), ["2026-11-10", "2026-11-09", "2026-10-31", "2026-09-30"].map { Dates.parse($0)! })
        XCTAssertEqual(all.months[0].spending, 3200); XCTAssertEqual(all.months[0].income, 3200)
        XCTAssertTrue(all.months[0].days[0].entries[0].intoFixedSavings)
        let income = EntryTimeline.snapshot(sortedEntries: sorted, ledger: l, month: today, filter: .income, allMonths: true)
        XCTAssertEqual(income.count, 1); XCTAssertEqual(income.spending, 0); XCTAssertEqual(income.months[0].spending, 0)
        let expenses = EntryTimeline.snapshot(sortedEntries: sorted, ledger: l, month: today, filter: .expense, allMonths: true)
        XCTAssertEqual(expenses.count, 3); XCTAssertEqual(expenses.income, 0); XCTAssertEqual(expenses.months[0].income, 0)
    }

    func testContinuousLedgerHandlesFourThousandRowsInDescendingMonths() {
        var l = fixture()
        let start = Dates.parse("2026-11-10")!
        l.entries = (0..<4000).map { i in
            Entry(date: Dates.addDays(-i, to: start), amount: 100, accountID: l.accounts[0].id, title: "午饭", category: "餐饮")
        }
        let result = EntryTimeline.snapshot(sortedEntries: l.entries, ledger: l, month: start, allMonths: true)
        XCTAssertEqual(result.count, 4000); XCTAssertEqual(result.spending, 400_000)
        XCTAssertEqual(result.months.flatMap(\.days), result.days)
        XCTAssertEqual(result.months.map(\.date), result.months.map(\.date).sorted(by: >))
        XCTAssertEqual(result.days.last?.entries.first?.id, l.entries.last?.id)
    }
}
