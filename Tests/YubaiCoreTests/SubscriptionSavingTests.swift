import XCTest
@testable import YubaiCore

final class SubscriptionSavingTests: XCTestCase {
    let now = Dates.parse("2026-06-15 12:00")!
    func seed() -> Ledger {
        var ledger = Ledger(); ledger.updatedAt = now
        ledger.accounts = [Account(name: "合成账户", balance: 100_000, at: Dates.addDays(-100, to: now))]
        return ledger
    }
    func plan(_ ledger: Ledger, frequency: Frequency = .monthly, amount: Int64 = 1000, due: Date? = nil, title: String = "合成会员") -> Plan {
        var plan = Plan(title: title, amount: amount, dueDate: due ?? Dates.parse("2026-06-01")!, frequency: frequency, category: "娱乐旅行")
        plan.accountID = ledger.accounts[0].id; return plan
    }
    func end(_ plan: Plan, in ledger: inout Ledger, at date: Date) throws {
        var change = ChangeSet(source: "用户操作", reason: "停掉", items: [.endPlan(plan.id, date)]); change.createdAt = date
        try change.apply(to: &ledger)
    }
    func testCandidatesFilterAmountFrequencyNatureAndStoppedItems() {
        var ledger = seed()
        let valid = [Frequency.weekly, .monthly, .quarterly, .yearly].enumerated().map { i, frequency in plan(ledger, frequency: frequency, amount: 20_000, title: "合成\(i)") }
        var income = plan(ledger); income.inflow = true; income.nature = .income
        var repayment = plan(ledger); repayment.nature = .repayment
        var stopped = plan(ledger); stopped.stoppedAt = now; stopped.endDate = now
        var finished = plan(ledger); finished.installments = 1
        ledger.plans = valid + [income, repayment, stopped, finished, plan(ledger, frequency: .once), plan(ledger, amount: 20_001)]
        XCTAssertEqual(Set(SubscriptionCheck.candidates(ledger: ledger, now: now).compactMap(\.planID)), Set(valid.map(\.id)))
    }
    func testStillUsingIsRememberedForMonthAndReappearsNextMonth() throws {
        var ledger = seed(); ledger.plans = [plan(ledger)]
        let candidate = try XCTUnwrap(SubscriptionCheck.candidates(ledger: ledger, now: now).first)
        try SubscriptionCheck.answer(candidate, choice: .stillUsing, in: &ledger, now: now)
        XCTAssertTrue(SubscriptionCheck.candidates(ledger: ledger, now: Dates.addDays(1, to: now)).isEmpty)
        XCTAssertEqual(SubscriptionCheck.candidates(ledger: ledger, now: Dates.addMonths(1, to: now)).count, 1)
        XCTAssertTrue(ledger.plans[0].active); XCTAssertEqual(Savings.total(ledger: ledger, now: now), 0)
        XCTAssertThrowsError(try SubscriptionCheck.answer(candidate, choice: .stop, in: &ledger, now: now))
    }
    func testStopAccruesEachElapsedOccurrenceAndExcludesChargesThatOccurred() throws {
        var ledger = seed(); let member = plan(ledger); ledger.plans = [member]
        let candidate = try XCTUnwrap(SubscriptionCheck.candidates(ledger: ledger, now: now).first)
        try SubscriptionCheck.answer(candidate, choice: .stop, in: &ledger, now: now)
        XCTAssertEqual(ledger.plans[0].stoppedAt, now); XCTAssertEqual(ledger.stoppedSubscriptions.count, 1)
        XCTAssertEqual(Savings.total(ledger: ledger, now: Dates.parse("2026-06-30")!), 0)
        XCTAssertEqual(Savings.total(ledger: ledger, now: Dates.parse("2026-07-01")!), 1000)
        let september = Dates.parse("2026-09-01")!
        XCTAssertEqual(Savings.total(ledger: ledger, now: september), 3000)
        var charge = Entry(date: Dates.parse("2026-08-01")!, amount: 1000, accountID: ledger.accounts[0].id, title: "合成会员")
        charge.planID = member.id; charge.occurrence = charge.date; ledger.entries.append(charge)
        XCTAssertEqual(Savings.total(ledger: ledger, now: september), 2000)
        ledger.entries[0].planID = nil; ledger.entries[0].occurrence = nil
        XCTAssertEqual(Savings.total(ledger: ledger, now: september), 2000)
        ledger.entries[0].deletedAt = september
        XCTAssertEqual(Savings.total(ledger: ledger, now: september), 3000)
        let august = Savings.summary(ledger: ledger, from: Dates.parse("2026-08-01")!, to: september)
        XCTAssertEqual(august.total, 1000); XCTAssertEqual(august.lines[0].date, Dates.parse("2026-08-01"))
    }
    func testResumeAndRepeatedStopPreserveNonoverlappingSavings() throws {
        var ledger = seed(); let member = plan(ledger); ledger.plans = [member]
        try end(member, in: &ledger, at: now)
        let resumeAt = Dates.parse("2026-08-01")!
        var resume = try FixedFlows.resume(id: member.id, in: ledger, now: resumeAt); resume.createdAt = resumeAt; try resume.apply(to: &ledger)
        XCTAssertEqual(ledger.stoppedSubscriptions[0].resumedAt, resumeAt)
        XCTAssertEqual(Savings.total(ledger: ledger, now: Dates.parse("2026-10-01")!), 1000)
        try end(ledger.plans[0], in: &ledger, at: Dates.parse("2026-09-15")!)
        XCTAssertEqual(Savings.total(ledger: ledger, now: Dates.parse("2026-10-01")!), 2000)
        XCTAssertEqual(ledger.stoppedSubscriptions.count, 2)
    }
    func testStoppedSubscriptionRetainsOriginalEndAndInstallmentLimit() throws {
        var ledger = seed(); var member = plan(ledger); member.installments = 3; member.endDate = nil; ledger.plans = [member]
        try end(member, in: &ledger, at: now)
        XCTAssertEqual(Savings.total(ledger: ledger, now: Dates.parse("2026-12-01")!), 2000)
        var second = plan(ledger, title: "会到期的会员"); second.endDate = Dates.parse("2026-08-01")!
        ledger.stoppedSubscriptions.append(.init(plan: second, stoppedAt: now))
        XCTAssertEqual(Savings.total(ledger: ledger, now: Dates.parse("2026-12-01")!), 4000)
    }
    func testWeeklyQuarterlyYearlySavingsArePerDueDate() throws {
        for frequency in [Frequency.weekly, .quarterly, .yearly] {
            var ledger = seed(); let member = plan(ledger, frequency: frequency, due: now.addingTimeInterval(1)); ledger.plans = [member]
            try end(member, in: &ledger, at: now)
            let second = frequency.advance(member.dueDate, by: 1)
            XCTAssertEqual(Savings.total(ledger: ledger, now: member.dueDate), 1000)
            XCTAssertEqual(Savings.total(ledger: ledger, now: second.addingTimeInterval(-1)), 1000)
            XCTAssertEqual(Savings.total(ledger: ledger, now: second), 2000)
        }
    }
    func testRecurringMerchantUsesSharedDetectionAndStopCreatesLinkedPlan() throws {
        var ledger = seed()
        ledger.entries = (0..<3).map { _ in Entry(date: Dates.parse("2026-04-01")!, amount: 1500, accountID: ledger.accounts[0].id, title: "合成影音会员", category: "娱乐旅行") }
        for i in ledger.entries.indices { ledger.entries[i].date = Dates.addMonths(i, to: Dates.parse("2026-04-01")!) }
        XCTAssertTrue(RecurringDetection.matches(ledger.entries, frequency: .monthly))
        let candidate = try XCTUnwrap(SubscriptionCheck.candidates(ledger: ledger, now: now).first)
        XCTAssertNil(candidate.planID); XCTAssertEqual(candidate.entryIDs.count, 3)
        try SubscriptionCheck.answer(candidate, choice: .stop, in: &ledger, now: now)
        XCTAssertEqual(ledger.plans.count, 1); XCTAssertEqual(ledger.entries.compactMap(\.planID).count, 3)
        XCTAssertEqual(Savings.total(ledger: ledger, now: Dates.parse("2026-08-01")!), 3000)
        XCTAssertTrue(SubscriptionCheck.candidates(ledger: ledger, now: now).isEmpty)
    }
    func testInferredCandidateRejectsIrregularLargeAndAlreadyPlannedMerchants() {
        var ledger = seed()
        ledger.entries = [0, 2, 30].map { offset in Entry(date: Dates.addDays(-offset, to: now), amount: 1500, accountID: ledger.accounts[0].id, title: "合成商户") }
        XCTAssertTrue(SubscriptionCheck.candidates(ledger: ledger, now: now).isEmpty)
        for i in ledger.entries.indices { ledger.entries[i].date = Dates.addMonths(-i, to: now) }
        XCTAssertEqual(SubscriptionCheck.candidates(ledger: ledger, now: now).count, 1)
        ledger.plans = [plan(ledger, amount: 30_000, title: "合成商户")]
        XCTAssertTrue(SubscriptionCheck.candidates(ledger: ledger, now: now).isEmpty)
    }
    func testOnlyFirstLetterInMonthIncludesSubscriptionCheckAndSavingsOmitZero() throws {
        var ledger = seed(); ledger.plans = [plan(ledger)]
        let first = try XCTUnwrap(WeeklyLetter.candidate(ledger, now: now))
        XCTAssertEqual(first.letter?.subscriptions?.count, 1)
        XCTAssertNil(first.letter?.weeklySavings); XCTAssertNil(first.letter?.totalSavings)
        XCTAssertFalse(first.facts.contains { $0.label.contains("省下") })
        ledger.cards.append(first.card(now: now))
        XCTAssertNil(WeeklyLetter.candidate(ledger, now: now))
        XCTAssertNil(WeeklyLetter.candidate(ledger, now: Dates.addDays(7, to: now))?.letter?.subscriptions)
        XCTAssertEqual(WeeklyLetter.candidate(ledger, now: Dates.parse("2026-07-06")!)?.letter?.subscriptions?.count, 1)
        var drop = WishItem(title: "放弃的鞋", amount: 20_000); drop.status = .dropped; drop.droppedAt = Dates.parse("2026-06-13")!; ledger.wishlist = [drop]
        let facts = WeeklyLetter.facts(ledger, weekEnding: Dates.parse("2026-06-14")!)
        XCTAssertEqual(facts.weeklySavings, 20_000); XCTAssertEqual(facts.totalSavings, 20_000)
        XCTAssertEqual(facts.numbers.filter { $0.label.contains("省下") }.count, 2)
    }
    func testLetterWordingReceivesSubscriptionAndSavingsFactsThroughFakeTransport() async throws {
        var ledger = seed(); ledger.plans = [plan(ledger)]
        var wish = WishItem(title: "鞋子", amount: 30_000); wish.status = .dropped; wish.droppedAt = Dates.parse("2026-06-13")!; ledger.wishlist = [wish]
        let candidate = try XCTUnwrap(WeeklyLetter.candidate(ledger, now: now))
        let transport = ScriptedChatTransport([ChatMessage(role: .assistant, content: #"{"cards":[{"key":"c0","title":"每周来信","body":"这些还在用吗？"}]}"#)])
        let worded = await ButlerWording.word([candidate], ledger: ledger, transport: transport, now: now)
        XCTAssertEqual(worded.first?.letter?.weeklySavings, 30_000)
        let requests = await transport.recorded()
        let payload = try JSONValue.parse(try XCTUnwrap(requests.first?.messages.last?.content))
        XCTAssertEqual(payload.arrayValue?.first?["letter"]?["total_savings"], .money(30_000))
        XCTAssertEqual(payload.arrayValue?.first?["letter"]?["subscriptions"]?.arrayValue?.first?["title"], .string("合成会员"))
    }
    func testFutureSavingsAreExcludedAndScheduledEndCanBeShortened() throws {
        var ledger = seed(); var member = plan(ledger); member.endDate = Dates.parse("2026-12-01")!; ledger.plans = [member]
        let candidate = try XCTUnwrap(SubscriptionCheck.candidates(ledger: ledger, now: now).first)
        try SubscriptionCheck.answer(candidate, choice: .stop, in: &ledger, now: now)
        XCTAssertEqual(ledger.plans[0].stoppedAt, now)
        XCTAssertEqual(ledger.stoppedSubscriptions[0].plan.endDate, member.endDate)
        XCTAssertEqual(Savings.summary(ledger: ledger, from: now, to: Dates.parse("2027-01-01")!, now: now).total, 0)
        XCTAssertEqual(Savings.total(ledger: ledger, now: Dates.parse("2027-01-01")!), 6000)
    }
    func testStopSnapshotAndMonthlyAnswersSurviveRoundTrip() throws {
        var ledger = seed(); ledger.plans = [plan(ledger)]
        let candidate = try XCTUnwrap(SubscriptionCheck.candidates(ledger: ledger, now: now).first)
        try SubscriptionCheck.answer(candidate, choice: .stop, in: &ledger, now: now)
        XCTAssertEqual(try LedgerCodec.decode(LedgerCodec.encode(ledger)), ledger)
    }
}
