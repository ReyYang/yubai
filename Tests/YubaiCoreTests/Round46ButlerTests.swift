import XCTest
@testable import YubaiCore

final class Round46ButlerTests: XCTestCase {
    private let now = Dates.parse("2026-11-20 12:00")!
    private func date(_ value: String) -> Date { Dates.parse(value)! }
    private func ledger() -> Ledger {
        var value = Round45Fixture.ledger()
        value.preferences.onboardingComplete = true
        value.preferences.profileColdStartDone = true
        return value
    }
    private func withRenewal(yearly: Bool = false, days: Int = 1) -> Ledger {
        var value = ledger()
        var plan = Plan(title: "视频会员", amount: 2500, dueDate: Dates.addDays(days, to: Dates.day(now)), frequency: yearly ? .yearly : .monthly, category: "订阅")
        plan.accountID = value.accounts[0].id; value.plans.append(plan)
        return value
    }
    func testRenewalHasExactMoneyAndNeverInventsUsage() throws {
        let value = withRenewal(), renewal = try XCTUnwrap(HomeButler.renewals(value, now: now).first)
        XCTAssertEqual(renewal.amount, 2500)
        XCTAssertFalse(renewal.explicitlyUnused)
        XCTAssertEqual(renewal.date, date("2026-11-21"))
    }
    func testExplicitMemoryIsRequiredForUnusedClaim() throws {
        var value = withRenewal()
        value.memories = [MemoryNote(text: "视频会员不看了", kind: .life, source: .user, createdAt: now)]
        XCTAssertTrue(try XCTUnwrap(HomeButler.renewals(value, now: now).first).explicitlyUnused)
    }
    func testRenewalWindowsAreOneDayForMonthlyAndSevenForYearly() {
        XCTAssertTrue(HomeButler.renewals(withRenewal(days: 2), now: now).isEmpty)
        XCTAssertEqual(HomeButler.renewals(withRenewal(yearly: true, days: 7), now: now).count, 1)
        XCTAssertTrue(HomeButler.renewals(withRenewal(yearly: true, days: 8), now: now).isEmpty)
    }
    func testOrdinaryBillsAreNotAssumedToBeUnusedSubscriptions() {
        var value = withRenewal()
        value.plans[value.plans.count - 1].title = "水费"; value.plans[value.plans.count - 1].category = "居住"
        XCTAssertTrue(HomeButler.renewals(value, now: now).isEmpty)
    }
    func testKeepIsPersistedAndDoesNotAskAgainNextMonth() throws {
        var value = withRenewal()
        let renewal = try XCTUnwrap(HomeButler.renewals(value, now: now).first)
        HomeButler.answer(renewal.id, in: &value, now: now)
        value = try LedgerCodec.decode(LedgerCodec.encode(value))
        XCTAssertTrue(HomeButler.renewals(value, now: now).isEmpty)
        XCTAssertTrue(HomeButler.renewals(value, now: Dates.addMonths(1, to: now)).isEmpty)
    }
    func testNotYetReturnsTomorrowWithoutChangingTheBill() throws {
        var value = ledger()
        let key = "due:bill"
        HomeButler.answer(key, in: &value, now: now)
        value = try LedgerCodec.decode(LedgerCodec.encode(value))
        XCTAssertTrue(HomeButler.isAnswered(key, in: value, now: now))
        XCTAssertFalse(HomeButler.isAnswered(key, in: value, now: Dates.addDays(1, to: now)))
    }
    func testStopRemovesFutureReservationAndCapturesAuditRecordAtomically() throws {
        var value = withRenewal()
        let before = value, funds = Finance.funds(value, now: now)
        let renewal = try XCTUnwrap(HomeButler.renewals(value, now: now).first)
        try HomeButler.stop(renewal, in: &value, now: now)
        XCTAssertEqual(Finance.funds(value, now: now).available, funds.available + renewal.amount)
        XCTAssertTrue(HomeButler.renewals(value, now: now).isEmpty)
        let record = try XCTUnwrap(value.butlerSavings.first)
        XCTAssertEqual(record.item, "视频会员"); XCTAssertEqual(record.amount, 2500)
        XCTAssertEqual(record.cadence, .monthly); XCTAssertTrue(record.undoable)
        XCTAssertEqual(ButlerSavings.total(value, now: now), 0)
        // App undo restores the entire previous transaction, including the tally.
        value = before
        XCTAssertTrue(value.butlerSavings.isEmpty)
        XCTAssertEqual(Finance.funds(value, now: now), funds)
    }
    func testStaleRenewalActionCannotStopAChangedPlan() throws {
        var value = withRenewal()
        let renewal = try XCTUnwrap(HomeButler.renewals(value, now: now).first)
        value.plans[value.plans.count - 1].amount += 100
        let before = value
        XCTAssertThrowsError(try HomeButler.stop(renewal, in: &value, now: now))
        XCTAssertEqual(value, before)
    }
    func testRecurringTallyAccruesOnlyElapsedUnchargedOccurrences() throws {
        var value = withRenewal()
        let renewal = try XCTUnwrap(HomeButler.renewals(value, now: now).first)
        try HomeButler.stop(renewal, in: &value, now: now)
        XCTAssertEqual(ButlerSavings.total(value, now: date("2026-11-21 12:00")), 2500)
        XCTAssertEqual(ButlerSavings.total(value, now: date("2026-12-21 12:00")), 5000)
        var charge = Entry(date: date("2026-12-21 09:00"), amount: 2500, accountID: value.accounts[0].id, title: "视频会员", category: "订阅")
        charge.planID = renewal.plan.id; charge.occurrence = date("2026-12-21")
        value.entries.append(charge)
        XCTAssertEqual(ButlerSavings.total(value, now: date("2026-12-21 12:00")), 2500)
    }
    func testYearlyTallyDoesNotAnnualizeMonthlySavings() throws {
        var value = withRenewal(yearly: true, days: 7)
        let renewal = try XCTUnwrap(HomeButler.renewals(value, now: now).first)
        try HomeButler.stop(renewal, in: &value, now: now)
        XCTAssertEqual(value.butlerSavings.first?.cadence, .yearly)
        XCTAssertEqual(ButlerSavings.total(value, now: date("2027-06-01")), 2500)
        XCTAssertEqual(ButlerSavings.results(value, now: date("2027-06-01"), year: 2027).reduce(0) { $0 + $1.amount }, 0)
    }
    func testResumingStopsAccrualAndSynchronizationIsIdempotent() throws {
        var value = withRenewal()
        let renewal = try XCTUnwrap(HomeButler.renewals(value, now: now).first)
        try HomeButler.stop(renewal, in: &value, now: now)
        var change = ChangeSet(source: "用户操作", reason: "恢复", items: [.resumePlan(renewal.plan.id)])
        change.createdAt = date("2026-12-01")
        try change.apply(to: &value)
        ButlerSavings.synchronize(&value, now: date("2026-12-01"))
        let count = value.butlerSavings.count
        ButlerSavings.synchronize(&value, now: date("2027-01-01"))
        XCTAssertEqual(value.butlerSavings.count, count)
        XCTAssertEqual(ButlerSavings.total(value, now: date("2027-01-01")), 2500)
    }
    func testDroppedWishIsCountedOnceWithItsDecisionAndDate() throws {
        var value = ledger()
        var wish = WishItem(title: "耳机", amount: 189_900)
        wish.createdAt = now.addingTimeInterval(-48 * 3600); wish.coolUntil = now
        value.wishlist = [wish]
        try Wishlist.answerCooldown(wish.id, choice: .drop, in: &value, now: now)
        ButlerSavings.synchronize(&value, now: now); ButlerSavings.synchronize(&value, now: now)
        XCTAssertEqual(value.butlerSavings.count, 1)
        XCTAssertEqual(value.butlerSavings.first?.waitedHours, 48)
        XCTAssertEqual(ButlerSavings.total(value, now: now), 189_900)
        XCTAssertEqual(try LedgerCodec.decode(LedgerCodec.encode(value)).butlerSavings, value.butlerSavings)
    }
    func testOldShapeDecodesNewCollectionsWithDefaults() throws {
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: LedgerCodec.encode(ledger())) as? [String: Any])
        json.removeValue(forKey: "butlerSavings"); json.removeValue(forKey: "butlerAnswers")
        let decoded = try LedgerCodec.decode(JSONSerialization.data(withJSONObject: json))
        XCTAssertTrue(decoded.butlerSavings.isEmpty); XCTAssertTrue(decoded.butlerAnswers.isEmpty)
    }
    func testInvalidAuditRecordAndDuplicateIdentifiersAreRejected() {
        var value = ledger()
        value.butlerSavings = [ButlerSaving(id: "test", item: "会员", amount: 0, cadence: .monthly, date: now, undoable: true)]
        XCTAssertThrowsError(try value.validate())
        value.butlerSavings[0].amount = 2500; value.butlerSavings.append(value.butlerSavings[0])
        XCTAssertThrowsError(try value.validate())
        value.butlerSavings.removeLast()
        var plan = Plan(title: "会员", amount: 2500, dueDate: now, frequency: .monthly)
        plan.dueDate = .distantPast; value.butlerSavings[0].plan = plan
        XCTAssertThrowsError(try value.validate())
        plan.dueDate = now; value.butlerSavings[0].plan = plan
        value.butlerSavings[0].endedAt = now.addingTimeInterval(-1)
        XCTAssertThrowsError(try value.validate())
    }
    func testMustAnswerConfirmationRanksBeforeRenewalAndReminder() throws {
        var value = withRenewal()
        var bill = Plan(title: "话费", amount: 16000, dueDate: Dates.day(now)); bill.accountID = value.accounts[0].id; value.plans.append(bill)
        var confirmation = ButlerCard(kind: .answerQuestion, title: "这笔是什么？", body: "", action: .answerQuestion, dedupeKey: "question:46")
        confirmation.facts = [CardFact("金额", cents: 70300)]; value.cards = [confirmation]
        let queue = HomeButler.queue(value, now: now)
        let required = try XCTUnwrap(queue.firstIndex { if case .butler = $0 { return true }; return false })
        let saving = try XCTUnwrap(queue.firstIndex { if case .renewal = $0 { return true }; return false })
        let reminder = try XCTUnwrap(queue.firstIndex { if case .bill = $0 { return true }; return false })
        XCTAssertLessThan(required, saving); XCTAssertLessThan(saving, reminder)
    }
    func testNonActionableAndAmountlessObservationsStayOffHome() {
        var value = ledger()
        value.cards = [ButlerCard(kind: .weeklyLetter, title: "来信", body: "", dedupeKey: "letter:46"),
                       ButlerCard(kind: .answerQuestion, title: "没有钱数", body: "", action: .answerQuestion, dedupeKey: "question:46")]
        XCTAssertFalse(HomeButler.queue(value, now: now).contains { if case .butler = $0 { return true }; return false })
    }
    func testPendingProposalCanSupplyItsConcreteAmount() {
        var value = ledger()
        let change = ChangeSet(source: "测试", reason: "账单", items: [.addPlan(Plan(title: "房租", amount: 200000, dueDate: now))])
        value.pendingChanges = [change]
        let card = ButlerCard(kind: .recurring, title: "房租", body: "", action: .confirmChangeSet(change.id), dedupeKey: "proposal:46")
        XCTAssertEqual(HomeButler.confirmationAmount(card, in: value), 200000)
    }
    func testHomeRentPaymentAndContributionKeepTheirPeriodAndRejectDoubleConfirmation() throws {
        var value = ledger(); value.plans = []; value.entries = []
        var rent = Rent(monthlyTotal: 20000, personalShare: 10000, startDate: Dates.day(now), nextDueDate: Dates.day(now), monthsPerPayment: 1, receiveDay: 20)
        rent.accountID = value.accounts[0].id; value.rents = [rent]
        let occurrences = Finance.occurrences(in: value, now: now, days: 1).filter { $0.rentID == rent.id }
        XCTAssertEqual(occurrences.count, 2)
        for bill in occurrences {
            try HomeButler.confirmRent(bill, in: &value, now: now)
            let entry = try XCTUnwrap(value.entries.last)
            XCTAssertEqual(entry.rentID, rent.id)
            XCTAssertEqual(entry.rentPeriod, bill.rentMonth ?? Dates.day(bill.date))
            XCTAssertEqual(entry.nature, bill.inflow ? .contribution : .expense)
            let snapshot = value
            XCTAssertThrowsError(try HomeButler.confirmRent(bill, in: &value, now: now))
            XCTAssertEqual(value, snapshot)
        }
        XCTAssertTrue(Finance.occurrences(in: value, now: now, days: 1).isEmpty)
        try value.validate()
    }
    func testDeckCyclesAndReconcilesWithoutLosingQueuedWork() {
        var deck = ButlerDeck(); deck.reconcile(["one", "two", "three"])
        deck.cycle(); XCTAssertEqual(deck.ids, ["two", "three", "one"]); XCTAssertEqual(deck.position, 1)
        deck.cycle(backwards: true); XCTAssertEqual(deck.ids.first, "one")
        deck.reconcile(["two", "three", "four"])
        XCTAssertEqual(deck.ids, ["two", "three", "four"])
        deck.reconcile([]); XCTAssertTrue(deck.ids.isEmpty); XCTAssertEqual(deck.position, 0)
    }
    func testFirstUseCreatesNoSetupUntilAnEntryIsStarted() throws {
        var value = Ledger()
        XCTAssertTrue(HomeButler.queue(value, now: now).isEmpty)
        FirstUse.prepareForEntry(&value, now: now)
        XCTAssertEqual(value.accounts.count, 1); XCTAssertNil(value.savingRule); XCTAssertTrue(value.plans.isEmpty)
        FirstUse.prepareForEntry(&value, now: now); XCTAssertEqual(value.accounts.count, 1)
        let account = value.accounts[0].id
        value.entries = [Entry(date: Dates.addDays(-7, to: now), amount: 10000, nature: .income, accountID: account, title: "收入"),
                         Entry(date: Dates.addDays(-3, to: now), amount: 2800, accountID: account, title: "午饭")]
        XCTAssertEqual(Finance.funds(value, now: now).available, 7200)
        try value.validate()
    }
    func testDerivationIsAnIdentityWithAllFinancialDeductionsAndRefunds() {
        var value = ledger()
        value.goals = [Goal(title: "相机", target: 100000, reserved: 5000)]
        value.accounts.append(Account(name: "信用卡", kind: .credit, balance: -8800, at: now))
        value.entries.append(Entry(date: now, amount: 4000, nature: .unknownIn, accountID: value.accounts[0].id, title: "来款"))
        for saving in [Int64(0), 200000, 900000] {
            value.savingRule = .fixed(saving)
            let formula = Finance.spendingDerivation(value, now: now)
            XCTAssertEqual(formula.otherFunds + formula.income - formula.fixedSavings - formula.creditDebt - formula.goals - formula.uncertainInflow - formula.saving - formula.bills, formula.budget)
            XCTAssertEqual(formula.budget - formula.spent, formula.available)
            XCTAssertEqual(formula.available, Finance.funds(value, now: now).available)
        }
    }
    func testUpcomingIncludesNextPaydayWithoutBookingItsIncomeEarly() {
        let value = ledger(), at = date("2026-12-05 12:00")
        let before = Finance.funds(value, now: at).available
        XCTAssertTrue(HomeButler.upcoming(value, now: at).contains { $0.inflow && $0.title == "工资" })
        XCTAssertEqual(Finance.funds(value, now: at).available, before)
    }
    func testFundingUsesAnAssignedDebitAccountAndRecordsOneRealTransfer() throws {
        var value = Ledger()
        value.accounts = [Account(name: "招行卡", balance: 70000, at: now.addingTimeInterval(-1)),
                          Account(name: "微信", kind: .cash, balance: 60000, at: now.addingTimeInterval(-1))]
        var bill = Plan(title: "房租", amount: 100000, dueDate: Dates.addDays(1, to: Dates.day(now)))
        bill.accountID = value.accounts[0].id; value.plans = [bill]
        let task = try XCTUnwrap(HomeButler.funding(value, now: now).first)
        XCTAssertEqual(task.amount, 30000)
        let before = Finance.funds(value, now: now).available
        try HomeButler.transferFunding(task, in: &value, now: now)
        XCTAssertEqual(Finance.balance(value.accounts[0], in: value, at: now), 100000)
        XCTAssertEqual(Finance.balance(value.accounts[1], in: value, at: now), 30000)
        XCTAssertEqual(Finance.funds(value, now: now).available, before)
        XCTAssertEqual(value.entries.count, 1)
        XCTAssertThrowsError(try HomeButler.transferFunding(task, in: &value, now: now))
    }
    func testFundingDoesNotSpendTheSourceAccountsOwnUpcomingBills() {
        var value = Ledger()
        value.accounts = [Account(name: "卡", balance: 0, at: now), Account(name: "微信", balance: 50000, at: now)]
        var first = Plan(title: "话费", amount: 40000, dueDate: Dates.addDays(1, to: now)); first.accountID = value.accounts[0].id
        var second = Plan(title: "房租", amount: 30000, dueDate: Dates.addDays(2, to: now)); second.accountID = value.accounts[1].id
        value.plans = [first, second]
        XCTAssertTrue(HomeButler.funding(value, now: now).isEmpty)
    }
    func testPrivacyMasksMoneyWithoutDisablingResultNamedChoices() {
        XCTAssertEqual(HomeButler.privacyText("11月20日 · 4 笔，共 12,345.67", hidden: true), "11月20日 · 4 笔，共 ••••")
        XCTAssertEqual(HomeButler.privacyText("存起来 320元", hidden: true), "存起来 ••••")
        XCTAssertEqual(HomeButler.privacyText("留着", hidden: true), "留着")
        XCTAssertEqual(HomeButler.privacyText("25.00", hidden: false), "25.00")
    }
    func testRestraintComparesTheSameElapsedDaysAndAsksOncePerCycle() throws {
        var value = Ledger(); value.cycleAnchor = .calendarMonth
        value.accounts = [Account(name: "卡", balance: 1000000, at: now)]
        value.profile.restrain = [ProfileArea(title: "打车", match: AreaMatch(categories: ["交通"]))]
        value.entries = [Entry(date: date("2026-11-19"), amount: 13200, accountID: value.accounts[0].id, title: "打车", category: "交通"),
                         Entry(date: date("2026-10-19"), amount: 9200, accountID: value.accounts[0].id, title: "打车", category: "交通"),
                         Entry(date: date("2026-10-25"), amount: 50000, accountID: value.accounts[0].id, title: "打车", category: "交通")]
        let item = try XCTUnwrap(HomeButler.restraints(value, now: now).first)
        XCTAssertEqual(item.amount, 13200); XCTAssertEqual(item.usual, 9200)
        HomeButler.answer(item.id, in: &value, now: now)
        XCTAssertFalse(HomeButler.queue(value, now: now).contains { if case .restraint = $0 { return true }; return false })
    }
}
