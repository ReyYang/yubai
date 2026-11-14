import XCTest
@testable import YubaiCore

final class Round47IntegrationTests: XCTestCase {
    private let now = Dates.parse("2026-11-20 20:00")!

    private func seed() throws -> Ledger {
        var ledger = Ledger()
        ledger.updatedAt = now
        ledger.preferences.cloudAIEnabled = true
        ledger.preferences.butlerSuggestionsEnabled = true
        ledger.fixedSavings = 300_000
        ledger.savingRule = .fixed(200_000)
        ledger.cycleAnchor = .payday
        let account = Account(name: "工资卡", balance: 2_000_000, at: Dates.addDays(-60, to: now))
        ledger.accounts = [account]
        var salary = Plan(title: "工资", amount: 801_000, dueDate: Dates.addMonths(-1, to: Dates.day(now)),
                          frequency: .monthly, inflow: true, category: "工资", nature: .income)
        salary.accountID = account.id
        ledger.plans = [salary]
        var income = Entry(date: now, amount: salary.amount, nature: .income, accountID: account.id, title: "工资", category: "工资")
        income.planID = salary.id
        income.occurrence = Dates.day(now)
        ledger.entries = [income]
        for offset in 1...7 {
            ledger.entries.append(Entry(date: Dates.addDays(-offset, to: now), amount: 1000,
                                        accountID: account.id, title: "午饭", category: "餐饮"))
        }
        try Reserve.transfer(.take, amount: 50_000, in: &ledger, now: Dates.addDays(-1, to: now))
        ledger.salarySetupDeferral = SalarySetupDeferral(deferredAt: Dates.addMonths(-1, to: now), postedIncomeIDs: [])
        return ledger
    }

    private func enqueue(in ledger: inout Ledger, action: JSONValue = .object(["kind": .string("try_two_weeks"), "review": .string("带饭怎么样？")])) throws -> ButlerSuggestion {
        let entries = ledger.entries.filter { $0.nature == .expense }
        let row: JSONValue = .object([
            "topic": .string("午饭"),
            "observation": .array([.object(["text": .string("午饭 ")]), .object(["count": .bool(true)]),
                                   .object(["text": .string(" 次，共 ")]), .object(["sum": .bool(true)])]),
            "proposal": .array([.object(["text": .string("。试试带饭？")])]),
            "entry_ids": .array(entries.map { .string($0.id.uuidString) }),
            "claimed_count": .number(Double(entries.count)), "claimed_sum_cents": .number(7000),
            "memory_ids": .array([]), "action": action
        ])
        let values = ButlerSuggestionVerifier.parse(.array([row]), digest: ButlerDigest.build(ledger, now: now), ledger: ledger, now: now)
        let value = try XCTUnwrap(values.first)
        ButlerIntelligence.enqueue(values, in: &ledger, now: now)
        return value
    }

    func testCombinedFieldsRoundTripAndMissingNewFieldsDecodeTogether() throws {
        var ledger = try seed()
        _ = try enqueue(in: &ledger)
        let offer = try XCTUnwrap(Reserve.topupOffer(ledger, now: now))
        try Reserve.answerTopup(offer, amount: 20_000, in: &ledger, now: now)
        ButlerCadence.recordAttempt([.weekly, .payday("salary")], in: &ledger, now: now)
        let data = try JSONEncoder().encode(ledger)
        let restored = try JSONDecoder().decode(Ledger.self, from: data)
        XCTAssertEqual(restored, ledger)
        XCTAssertEqual(restored.savingsTransfers.count, 2)
        XCTAssertEqual(restored.savingsTopupDecisions.count, 1)
        XCTAssertEqual(restored.butlerAI?.suggestions.count, 1)
        XCTAssertNotNil(restored.salarySetupDeferral)
        XCTAssertEqual(HomeButler.queue(restored, now: now), HomeButler.queue(ledger, now: now))

        var old = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        for key in ["butlerAI", "savingsTransfers", "savingsTopupDecisions", "salarySetupDeferral"] { old.removeValue(forKey: key) }
        let legacy = try JSONDecoder().decode(Ledger.self, from: JSONSerialization.data(withJSONObject: old))
        XCTAssertNil(legacy.butlerAI)
        XCTAssertNil(legacy.salarySetupDeferral)
        XCTAssertTrue(legacy.savingsTransfers.isEmpty)
        XCTAssertTrue(legacy.savingsTopupDecisions.isEmpty)
        try legacy.validate()
    }

    func testTopupAndSuggestionShareQueueAndAnswersPreserveEachOther() throws {
        var ledger = try seed()
        let suggestion = try enqueue(in: &ledger)
        let offer = try XCTUnwrap(Reserve.topupOffer(ledger, now: now))
        let queue = HomeButler.queue(ledger, now: now)
        let topupIndex = try XCTUnwrap(queue.firstIndex(of: .savingsTopup(offer)))
        let suggestionIndex = try XCTUnwrap(queue.firstIndex(of: .suggestion(suggestion)))
        XCTAssertLessThan(topupIndex, suggestionIndex)
        XCTAssertEqual(Set(queue.map(\.id)).count, queue.count)
        let cash = Finance.funds(ledger, now: now).cash
        try Reserve.answerTopup(offer, amount: 20_000, in: &ledger, now: now)
        XCTAssertTrue(HomeButler.queue(ledger, now: now).contains(.suggestion(suggestion)))
        XCTAssertNil(Reserve.topupOffer(ledger, now: now))
        try ButlerSuggestions.answer(suggestion.id, .accept, in: &ledger, now: now)
        XCTAssertEqual(ledger.savingsTopupDecisions.count, 1)
        XCTAssertEqual(ledger.savingsTransfers.count, 2)
        XCTAssertEqual(Finance.funds(ledger, now: now).cash, cash)
        let due = Dates.addDays(14, to: now)
        let review = try XCTUnwrap(ledger.butlerAI?.reviews.first)
        XCTAssertEqual(review.dueAt, due)
        XCTAssertTrue(HomeButler.queue(ledger, now: due).contains(.suggestionReview(review)))
        XCTAssertNil(Reserve.topupOffer(ledger, now: due))
    }

    func testDigestUsesSameSavingsPotAsHomeAfterTakeFromPendingAndPutBack() throws {
        var ledger = try seed()
        try Reserve.transfer(.take, amount: 400_000, in: &ledger, now: now)
        XCTAssertEqual(ledger.savingsTransfers.last?.fromSetAside, 150_000)
        for putBack in [false, true] {
            if putBack { try Reserve.transfer(.putBack, amount: 10_000, in: &ledger, now: now) }
            let digest = ButlerDigest.build(ledger, now: now)
            XCTAssertEqual(digest.saving.savedCents, putBack ? 60_000 : 50_000)
            XCTAssertEqual(digest.saving.savedCents, HomeSavingCard.make(ledger, now: now).total)
            XCTAssertEqual(digest.saving.savedCents, Reserve.overview(ledger, now: now).total)
            XCTAssertEqual(digest.saving.targetCents, Finance.funds(ledger, now: now).savingTarget)
            XCTAssertEqual(Finance.spendingDerivation(ledger, now: now).exerciseResult, Finance.funds(ledger, now: now).available)
        }
    }

    func testChangedEvidenceRemovesOnlySuggestionAndKeepsTopup() throws {
        var ledger = try seed()
        let suggestion = try enqueue(in: &ledger)
        let offer = try XCTUnwrap(Reserve.topupOffer(ledger, now: now))
        ledger.entries[1].amount += 1
        let queue = HomeButler.queue(ledger, now: now)
        XCTAssertTrue(queue.contains(.savingsTopup(offer)))
        XCTAssertFalse(queue.contains(.suggestion(suggestion)))
        let before = ledger
        XCTAssertThrowsError(try ButlerSuggestions.answer(suggestion.id, .accept, in: &ledger, now: now))
        XCTAssertEqual(ledger, before)
    }

    func testAIBudgetActionPreservesTransferDecisionFloorAndDeferral() throws {
        var ledger = try seed()
        let suggestion = try enqueue(in: &ledger, action: .object(["kind": .string("set_budget"), "category": .string("餐饮"), "amount_cents": .number(50_000)]))
        let offer = try XCTUnwrap(Reserve.topupOffer(ledger, now: now))
        try Reserve.answerTopup(offer, amount: 0, in: &ledger, now: now)
        try Reserve.setFloor(100_000, in: &ledger, now: now)
        let before = ledger
        try ButlerSuggestions.answer(suggestion.id, .accept, in: &ledger, now: now)
        XCTAssertEqual(ledger.savingsTransfers, before.savingsTransfers)
        XCTAssertEqual(ledger.savingsTopupDecisions, before.savingsTopupDecisions)
        XCTAssertEqual(ledger.salarySetupDeferral, before.salarySetupDeferral)
        XCTAssertEqual(ledger.profile.floorAmount, before.profile.floorAmount)
        XCTAssertEqual(ledger.spendingParts.first { $0.categories == ["餐饮"] }?.amount, 50_000)
        XCTAssertNil(Reserve.topupOffer(ledger, now: now))
        XCTAssertEqual(try JSONDecoder().decode(Ledger.self, from: JSONEncoder().encode(ledger)), ledger)
    }
}
