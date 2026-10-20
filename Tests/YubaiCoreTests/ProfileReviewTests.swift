import XCTest
@testable import YubaiCore

final class ProfileReviewTests: XCTestCase {
    private let now = Dates.parse("2026-10-20 12:00")!
    private func seed() -> Ledger {
        var ledger = Ledger(); ledger.updatedAt = now; ledger.profile.updatedAt = now
        ledger.accounts = [Account(name: "合成账户", balance: 1_000_000, at: Dates.addDays(-150, to: now))]
        ledger.profile.restrain = [ProfileArea(title: "外卖", match: AreaMatch(categories: ["餐饮"]), note: "外卖想少一点", confirmedAt: Dates.addDays(-100, to: now))]
        return ledger
    }
    func testOldestCandidateOnlyRestrainedAreasOrPrinciplesAndNinetyDayBoundary() throws {
        var ledger = seed(); let area = ledger.profile.restrain[0]
        ledger.profile.generous = [ProfileArea(title: "旅行", confirmedAt: Dates.addDays(-300, to: now))]
        ledger.profile.principles = ["东西用久一点"]
        ledger.profile.principleDates = ["东西用久一点": Dates.addDays(-200, to: now)]
        let principle = try XCTUnwrap(ProfileReview.candidate(ledger: ledger, now: now))
        XCTAssertEqual(principle.target, .principle("东西用久一点")); XCTAssertTrue(principle.usage.isEmpty)
        try ProfileReview.keep(principle, in: &ledger, now: now)
        let candidate = try XCTUnwrap(ProfileReview.candidate(ledger: ledger, now: now))
        XCTAssertEqual(candidate.target, .area(area.id))
        ledger.profile.restrain[0].confirmedAt = Dates.addDays(-90, to: now)
        XCTAssertNil(ProfileReview.candidate(ledger: ledger, now: now))
        ledger.profile.restrain[0].confirmedAt = nil; ledger.profile.principleDates = [:]
        XCTAssertNil(ProfileReview.candidate(ledger: ledger, now: now), "Unknown dates must not invent an age")
    }
    func testFourWeeksReuseUsageForPersonalShareRefundsAndIgnoreFutureRows() throws {
        var ledger = seed(); let account = ledger.accounts[0].id
        var meal = Entry(date: Dates.parse("2026-10-05 12:00")!, amount: 10_000, accountID: account, title: "合成用餐", category: "餐饮")
        meal.personalExpense = 6000
        var refund = Entry(date: Dates.parse("2026-10-06 12:00")!, amount: 1000, nature: .refund, accountID: account, title: "合成退款")
        refund.relatedEntryID = meal.id
        ledger.entries = [meal, refund,
            Entry(date: now, amount: 2000, accountID: account, title: "当前周用餐", category: "餐饮"),
            Entry(date: Dates.addDays(1, to: now), amount: 3000, accountID: account, title: "未来用餐", category: "餐饮"),
            Entry(date: Dates.addDays(-40, to: now), amount: 3000, accountID: account, title: "较早用餐", category: "餐饮")]
        let candidate = try XCTUnwrap(ProfileReview.candidate(ledger: ledger, now: now))
        XCTAssertEqual(candidate.usage.map { Dates.text($0.weekStart) }, ["2026-09-28", "2026-10-05", "2026-10-12", "2026-10-19"])
        XCTAssertEqual(candidate.usage.map(\.count), [0, 1, 0, 1]); XCTAssertEqual(candidate.usage.map(\.amount), [0, 5000, 0, 2000])
        let area = ledger.profile.restrain[0]
        for week in candidate.usage {
            let end = min(now, Dates.addDays(7, to: week.weekStart).addingTimeInterval(-0.001))
            XCTAssertEqual(week.count, area.usage(in: ledger, from: week.weekStart, through: end).count)
        }
    }
    func testKeepRefreshesConfirmationAndRemoveWaitsForChangeSetConfirmation() throws {
        var ledger = seed(); let candidate = try XCTUnwrap(ProfileReview.candidate(ledger: ledger, now: now))
        let before = ledger
        let proposal = try ProfileReview.remove(candidate, in: ledger, now: now)
        XCTAssertEqual(ledger, before); XCTAssertTrue(ledger.pendingChanges.isEmpty)
        XCTAssertTrue(proposal.isProfileOnly); XCTAssertEqual(proposal.source, "画像回顾"); XCTAssertEqual(proposal.createdAt, now)
        try proposal.apply(to: &ledger)
        XCTAssertTrue(ledger.profile.restrain.isEmpty)
        ledger = before; try ProfileReview.keep(candidate, in: &ledger, now: now)
        XCTAssertEqual(ledger.profile.restrain[0].confirmedAt, now); XCTAssertEqual(ledger.profile.updatedAt, now)
        XCTAssertEqual(ledger.profile.restrain[0].note, before.profile.restrain[0].note)
        XCTAssertNil(ProfileReview.candidate(ledger: ledger, now: now))
        XCTAssertThrowsError(try ProfileReview.keep(candidate, in: &ledger, now: now))
        XCTAssertThrowsError(try ProfileReview.remove(candidate, in: ledger, now: now))
    }
    func testPrincipleRemoveAndKeepUsePrincipleDates() throws {
        var ledger = seed(); ledger.profile.restrain = []
        ledger.profile.principles = ["只买能长期用的"]
        ledger.profile.principleDates = ["只买能长期用的": Dates.addDays(-91, to: now)]
        let candidate = try XCTUnwrap(ProfileReview.candidate(ledger: ledger, now: now))
        let proposal = try ProfileReview.remove(candidate, in: ledger, now: now)
        let before = ledger
        try proposal.apply(to: &ledger)
        XCTAssertTrue(ledger.profile.principles.isEmpty); XCTAssertTrue(ledger.profile.principleDates.isEmpty)
        ledger = before; try ProfileReview.keep(candidate, in: &ledger, now: now)
        XCTAssertEqual(ledger.profile.principleDates["只买能长期用的"], now)
    }
    func testReviewTravelsInLetterAndOldLetterJSONStillDecodes() throws {
        let ledger = seed(); let candidate = try XCTUnwrap(WeeklyLetter.candidate(ledger, now: now))
        XCTAssertEqual(candidate.letter?.review?.target, .area(ledger.profile.restrain[0].id))
        let facts = try XCTUnwrap(candidate.letter)
        XCTAssertEqual(try JSONDecoder().decode(LetterFacts.self, from: JSONEncoder().encode(facts)), facts)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(facts)) as? [String: Any])
        json.removeValue(forKey: "review"); json.removeValue(forKey: "learned")
        let old = try JSONDecoder().decode(LetterFacts.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(old.review); XCTAssertNil(old.learned)
    }
}
