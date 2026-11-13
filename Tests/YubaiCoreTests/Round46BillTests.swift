import XCTest
@testable import YubaiCore

final class Round46BillTests: XCTestCase {
    func day(_ year: Int = 2026, _ month: Int = 11, _ day: Int = 20) -> Date {
        Dates.calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }
    func ledger() -> Ledger {
        var ledger = Ledger()
        ledger.accounts = [Account(name: "银行卡", balance: 1_000_000, at: day(2026, 1, 1))]
        ledger.cycleAnchor = .calendarMonth; ledger.fixedSavings = 0
        ledger.preferences.billExchangeRates = [ManualExchangeRate(currency: .usd, cnyPerUnit: Decimal(string: "7.12")!, updatedAt: day())]
        return ledger
    }
    func annual(amount: Int64 = 120_000, due: Date? = nil, since: Date? = nil) -> Plan {
        var plan = Plan(title: "年付", amount: amount, dueDate: due ?? day(2027, 10, 28), frequency: .yearly, category: "订阅")
        plan.yearlyReserveSince = since ?? day()
        return plan
    }
    func foreign(_ ledger: Ledger, due: Date? = nil, yearly: Bool = false) -> Plan {
        var plan = Plan(title: "Claude Pro", amount: 2_000, dueDate: due ?? day(2026, 11, 28), frequency: yearly ? .yearly : .monthly, category: "订阅")
        plan.currency = .usd; plan.accountID = ledger.accounts[0].id; plan.yearlyReserveSince = day()
        return plan
    }
    func testCatalogContainsAllIconsAndLicenseStrings() {
        XCTAssertEqual(BrandIcons.catalog.count, 301)
        XCTAssertEqual(Set(BrandIcons.catalog.map(\.slug)).count, 301)
        XCTAssertEqual(BrandIcons.licenses.count, 8)
        XCTAssertTrue(BrandIcons.licenses.contains("MIT (Yubai Brand Icon Library)"))
    }
    func testMatcherUsesCatalogKeywordsCaseWidthAndSpecificity() {
        XCTAssertEqual(BrandIcons.match("Claude Pro 每月")?.slug, "claude")
        XCTAssertEqual(BrandIcons.match("ＣＨＡＴＧＰＴ Plus")?.slug, "chatgpt")
        XCTAssertEqual(BrandIcons.match("1Password 年付")?.slug, "1password")
        XCTAssertEqual(BrandIcons.match("腾讯视频会员")?.slug, "tencent-video")
        XCTAssertEqual(BrandIcons.match("Apple Music")?.slug, "apple-music")
    }
    func testMatcherDoesNotUseAnInitialOrMatchLatinFragments() {
        XCTAssertNil(BrandIcons.match("")); XCTAssertNil(BrandIcons.match("房租"))
        XCTAssertNil(BrandIcons.match("capital letters"))
    }
    func testHalfYearlyAndFortnightlyAdvanceFromOriginalDate() {
        XCTAssertEqual(Frequency.halfYearly.advance(day(2026, 8, 31), by: 1), day(2027, 2, 28))
        XCTAssertEqual(Frequency.halfYearly.advance(day(2026, 8, 31), by: 2), day(2027, 8, 31))
        XCTAssertEqual(Frequency.fortnightly.advance(day(2026, 12, 25), by: 1), day(2027, 1, 8))
    }
    func testNewCyclesSupportFiniteSchedulesSkipsAndMoves() throws {
        for frequency in [Frequency.halfYearly, .fortnightly] {
            var ledger = ledger()
            var plan = Plan(title: frequency.label, amount: 100, dueDate: day(), frequency: frequency)
            plan.installments = 3; plan.skippedOccurrences = [frequency.advance(day(), by: 1)]; ledger.plans = [plan]
            let last = frequency.advance(day(), by: 2)
            XCTAssertEqual(plan.occurrenceIndex(on: last), 2)
            XCTAssertNil(plan.occurrenceIndex(on: frequency.advance(day(), by: 3)))
            try FixedFlows.moveOccurrence(planID: plan.id, occurrence: last, to: Dates.addDays(1, to: last), in: &ledger, now: day())
            XCTAssertNil(ledger.plans[0].occurrenceIndex(on: last))
            XCTAssertEqual(ledger.plans[0].occurrenceIndex(on: Dates.addDays(1, to: last)), 2)
            let rows = Finance.occurrences(in: ledger, now: day(), days: 400)
            XCTAssertEqual(rows.count, 2)
        }
    }
    func testOldPlanAndPreferencesDecodeWithDefaults() throws {
        let plan = Plan(title: "旧房租", amount: 300_000, dueDate: day(), frequency: .monthly)
        let encoder = JSONEncoder(), decoder = JSONDecoder()
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(plan)) as? [String: Any])
        json.removeValue(forKey: "currency"); json.removeValue(forKey: "yearlyReserveSince")
        let old = try decoder.decode(Plan.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(old.currency, .cny); XCTAssertEqual(old.frequency, .monthly)
        XCTAssertNil(old.yearlyReserveSince)
        let preferences = try decoder.decode(Preferences.self, from: encoder.encode(Preferences()))
        XCTAssertNil(preferences.billExchangeRates); XCTAssertNotEqual(preferences.yearlyBillsSetAside, false)
        json.removeValue(forKey: "frequency")
        XCTAssertEqual(try decoder.decode(Plan.self, from: JSONSerialization.data(withJSONObject: json)).frequency, .once)
    }
    func testOldLedgerRoundTripAndNewCurrencyFieldsRoundTrip() throws {
        let encoder = JSONEncoder(), decoder = JSONDecoder()
        var ledger = ledger(); ledger.plans = [foreign(ledger, yearly: true)]
        ledger.preferences.lastBillCurrency = .usd; ledger.preferences.yearlyBillsSetAside = false
        let restored = try decoder.decode(Ledger.self, from: encoder.encode(ledger))
        XCTAssertEqual(restored, ledger); try restored.validate()
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(ledger)) as? [String: Any])
        var preferences = try XCTUnwrap(json["preferences"] as? [String: Any])
        for key in ["billExchangeRates", "lastBillCurrency", "yearlyBillsSetAside"] { preferences.removeValue(forKey: key) }
        json["preferences"] = preferences
        var plans = try XCTUnwrap(json["plans"] as? [[String: Any]])
        plans[0].removeValue(forKey: "currency"); plans[0].removeValue(forKey: "yearlyReserveSince"); json["plans"] = plans
        let old = try decoder.decode(Ledger.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(old.plans[0].currency, .cny); XCTAssertNotNil(old.plans[0].yearlyReserveSince)
        try old.validate()
    }
    func testManualRatesRoundToFenAndDoNotOverflow() {
        let rate = ManualExchangeRate(currency: .usd, cnyPerUnit: Decimal(string: "7.12")!, updatedAt: day())
        XCTAssertEqual(rate.convert(3_588), 25_547); XCTAssertEqual(rate.convert(2_000), 14_240)
        XCTAssertNil(rate.convert(Money.limit)); XCTAssertNil(rate.convert(-1))
        XCTAssertNil(ManualExchangeRate(currency: .usd, cnyPerUnit: -1, updatedAt: day()).convert(100))
    }
    func testManualSourceDoesNotInventRatesOrUseFutureQuotes() {
        let source = ManualBillExchangeRates(ledger().preferences.billExchangeRates!)
        XCTAssertNil(source.rate(for: .eur, asOf: day())); XCTAssertNil(source.rate(for: .usd, asOf: day(2026, 11, 19)))
        XCTAssertEqual(source.rate(for: .usd, asOf: day())?.valueText, "7.12")
    }
    func testRateEditUpdatesOnlyThatCurrencyAndInvalidatesFundsCache() throws {
        var ledger = ledger(); ledger.plans = [foreign(ledger)]
        let before = Finance.funds(ledger, now: day()).available
        try FixedFlows.setRate(ManualExchangeRate(currency: .eur, cnyPerUnit: 8, updatedAt: day()), in: &ledger)
        try FixedFlows.setRate(ManualExchangeRate(currency: .usd, cnyPerUnit: 8, updatedAt: day()), in: &ledger)
        XCTAssertEqual(ledger.preferences.billExchangeRates?.count, 2)
        XCTAssertEqual(Finance.funds(ledger, now: day()).available, before - 1_760)
    }
    func testForeignBillTotalsAndFormulaAlwaysUseCNY() {
        var ledger = ledger(); ledger.plans = [foreign(ledger)]
        let month = BillCalendarMonth(containing: day(), in: ledger, now: day())
        XCTAssertEqual(month.remaining, 14_240); XCTAssertEqual(month.unpaidCount, 1)
        XCTAssertEqual(Finance.funds(ledger, now: day()).committed, 14_240)
        XCTAssertEqual(Finance.formula(ledger, now: day()).billsRest, 14_240)
        XCTAssertEqual(ledger.plans[0].amount, 2_000)
        XCTAssertEqual(BillCurrency.usd.amountText(2000), "US$20.00")
        XCTAssertEqual(BillCurrency.usd.amountText(2000, hidden: true), "••••")
    }
    func testMissingOrOverflowingForeignRateRejectsLedger() {
        var ledger = ledger(); ledger.plans = [foreign(ledger)]
        ledger.preferences.billExchangeRates = nil; XCTAssertThrowsError(try ledger.validate())
        ledger.preferences.billExchangeRates = [ManualExchangeRate(currency: .usd, cnyPerUnit: 100_000, updatedAt: day())]
        ledger.plans[0].amount = Money.limit; XCTAssertThrowsError(try ledger.validate())
    }
    func testForeignActualWinsOverManualRateAndUnlinkRestoresRate() throws {
        var ledger = ledger(); let due = day(2026, 11, 28); ledger.plans = [foreign(ledger)]
        let id = ledger.plans[0].id
        let entry = Entry(date: due, amount: 14_550, accountID: ledger.accounts[0].id, title: "Claude Pro", category: "订阅")
        ledger.entries = [entry]
        try FixedFlows.markPaid(planID: id, occurrence: due, with: entry.id, in: &ledger)
        XCTAssertEqual(ledger.entries.count, 1)
        try FixedFlows.setRate(ManualExchangeRate(currency: .usd, cnyPerUnit: 10, updatedAt: due), in: &ledger)
        XCTAssertEqual(FixedFlows.expectedAmount(planID: id, in: ledger, now: day(2026, 12, 1)), 14_550)
        XCTAssertEqual(FixedFlows.lastActual(planID: id, in: ledger, now: day(2026, 12, 1)), 14_550)
        try FixedFlows.unlink(entryID: entry.id, in: &ledger)
        XCTAssertEqual(FixedFlows.expectedAmount(planID: id, in: ledger, now: day(2026, 12, 1)), 20_000)
    }
    func testAutomaticEstimatedChargeDoesNotBecomeAnActualFXQuote() {
        var ledger = ledger(); ledger.plans = [foreign(ledger)]
        var entry = Entry(date: day(2026, 11, 28), amount: 12_345, accountID: ledger.accounts[0].id, title: "Claude Pro")
        entry.planID = ledger.plans[0].id; entry.occurrence = day(2026, 11, 28); entry.source = "自动扣款"
        ledger.entries = [entry]
        XCTAssertEqual(FixedFlows.expectedAmount(planID: ledger.plans[0].id, in: ledger, now: day(2026, 12, 1)), 14_240)
        XCTAssertNil(FixedFlows.lastActual(planID: ledger.plans[0].id, in: ledger, now: day(2026, 12, 1)))
    }
    func testForeignPriceEditKeepsOriginalAmountAndResetsOldEstimate() throws {
        var ledger = ledger(); ledger.plans = [foreign(ledger)]
        let due = day(2026, 11, 28), id = ledger.plans[0].id
        var paid = Entry(date: due, amount: 14_550, accountID: ledger.accounts[0].id, title: "Claude Pro")
        paid.planID = id; paid.occurrence = due; ledger.entries = [paid]
        let edit = try XCTUnwrap(FixedFlows.edit(planID: id, in: ledger, now: day(2026, 12, 1)))
        XCTAssertEqual(edit.amount, 2_000)
        let change = try FixedFlows.update(planID: id, title: edit.title, amount: 3_000, frequency: edit.frequency, date: edit.date,
                                           accountID: edit.accountID, category: edit.category, installments: edit.installments, autoPay: false,
                                           estimated: false, in: ledger, now: day(2026, 12, 1), currency: .usd)
        try change.apply(to: &ledger)
        XCTAssertEqual(FixedFlows.expectedAmount(planID: id, in: ledger, now: day(2026, 12, 2)), 21_360)
        XCTAssertEqual(FixedFlows.month(containing: due, in: ledger, asOf: day(2026, 12, 2)).occurrences.first?.state, .paid)
    }
    func testForeignEntryAutoMatchUsesCNYAndRealAmount() {
        var ledger = ledger(); let due = day(2026, 11, 28); ledger.plans = [foreign(ledger)]
        let entry = Entry(date: due, amount: 14_550, accountID: ledger.accounts[0].id, title: "Claude Pro", category: "订阅")
        ledger.entries = [entry]
        XCTAssertEqual(FixedFlows.autoLink(&ledger, addedEntryIDs: [entry.id], now: due).count, 1)
        XCTAssertEqual(ledger.entries[0].planID, ledger.plans[0].id)
        XCTAssertEqual(Finance.funds(ledger, now: due).committed, 0)
    }
    func testFullYearReservesTwelfthsAndAccumulatesAcrossMonths() {
        var ledger = ledger(); ledger.plans = [annual()]
        XCTAssertEqual(YearlyBillReserves.rows(in: ledger, now: day()).first?.monthly, 10_000)
        XCTAssertEqual(YearlyBillReserves.rows(in: ledger, now: day()).first?.reserved, 10_000)
        XCTAssertEqual(YearlyBillReserves.rows(in: ledger, now: day(2027, 1, 1)).first?.reserved, 30_000)
        XCTAssertEqual(Finance.funds(ledger, now: day(2027, 1, 1)).yearlySetAside, 30_000)
    }
    func testNearTermYearlyBillCatchesUpByDueMonthPerBill() {
        var ledger = ledger(); ledger.plans = [annual(amount: 10_001, due: day(2027, 1, 28))]
        let row = YearlyBillReserves.rows(in: ledger, now: day()).first
        XCTAssertEqual(row?.monthly, 3_334); XCTAssertEqual(row?.reserved, 3_334)
        XCTAssertEqual(YearlyBillReserves.rows(in: ledger, now: day(2026, 12, 1)).first?.reserved, 6_668)
    }
    func testDueMonthDoesNotDoubleCountAnnualEnvelope() {
        var ledger = ledger(); ledger.plans = [annual(due: day(2026, 12, 28))]
        let funds = Finance.funds(ledger, now: day(2026, 12, 1))
        XCTAssertEqual(funds.yearlySetAside, 0); XCTAssertEqual(funds.committed, 120_000)
        XCTAssertEqual(funds.available, 880_000)
    }
    func testPaydayCycleContainingAnnualDueDeductsOnlyFullBill() {
        var ledger = ledger(); ledger.cycleAnchor = .payday
        var salary = Plan(title: "工资", amount: 800_000, dueDate: day(2026, 11, 10), frequency: .monthly, inflow: true, category: "工资", nature: .income)
        salary.accountID = ledger.accounts[0].id
        ledger.plans = [salary, annual(due: day(2026, 12, 5))]
        let funds = Finance.funds(ledger, now: day())
        XCTAssertEqual(funds.yearlySetAside, 0); XCTAssertEqual(funds.committed, 120_000)
    }
    func testPaidYearlyBillDoesNotStartSavingForNextYearUntilFollowingMonth() throws {
        var ledger = ledger(); var plan = annual(due: day(2026, 12, 28)); plan.accountID = ledger.accounts[0].id; ledger.plans = [plan]
        let change = try FixedFlows.settle(planID: plan.id, occurrence: plan.dueDate, in: ledger, now: plan.dueDate)
        try change.apply(to: &ledger)
        XCTAssertEqual(YearlyBillReserves.rows(in: ledger, now: day(2026, 12, 29)).first?.reserved, 0)
        XCTAssertEqual(YearlyBillReserves.rows(in: ledger, now: day(2027, 1, 1)).first?.reserved, 10_000)
    }
    func testSetAsideOffAndOnPersistsAndInvalidatesCache() throws {
        var ledger = ledger(); ledger.plans = [annual()]
        let before = Finance.funds(ledger, now: day()).available
        YearlyBillReserves.setEnabled(false, in: &ledger, now: day())
        XCTAssertEqual(Finance.funds(ledger, now: day()).available, before + 10_000)
        let restored = try JSONDecoder().decode(Ledger.self, from: JSONEncoder().encode(ledger))
        XCTAssertTrue(YearlyBillReserves.rows(in: restored, now: day()).isEmpty)
        YearlyBillReserves.setEnabled(true, in: &ledger, now: day(2027, 1, 1))
        XCTAssertEqual(ledger.plans[0].yearlyReserveSince, day(2027, 1, 1))
    }
    func testStoppedSkippedAndIncomeYearlyBillsAreNotReserved() {
        var ledger = ledger(); var stopped = annual(); stopped.stoppedAt = day(); stopped.endDate = day()
        var skipped = annual(); skipped.skippedOccurrences = [skipped.dueDate]
        var income = annual(); income.inflow = true; income.nature = .income
        ledger.plans = [stopped, skipped, income]
        XCTAssertEqual(Finance.funds(ledger, now: day()).yearlySetAside, 0)
    }
    func testSpendableDerivationKeepsAnnualRowAsAnIdentity() {
        var ledger = ledger(); ledger.plans = [annual()]
        let formula = Finance.formula(ledger, now: day()), value = Finance.spendingDerivation(ledger, now: day())
        XCTAssertEqual(formula.yearlySetAside, 10_000); XCTAssertEqual(value.yearlySetAside, 10_000)
        XCTAssertEqual(value.otherFunds + value.income - value.fixedSavings - value.creditDebt - value.goals - value.uncertainInflow - value.saving - value.yearlySetAside - value.bills, value.budget)
        XCTAssertEqual(value.budget - value.spent, value.available)
    }
    func testForeignAnnualEnvelopeUsesManualRateThenActualCNY() throws {
        var ledger = ledger(); var plan = foreign(ledger, due: day(2027, 10, 28), yearly: true); plan.amount = 3_588; ledger.plans = [plan]
        XCTAssertEqual(YearlyBillReserves.rows(in: ledger, now: day()).first?.monthly, 2_129)
        var paid = Entry(date: plan.dueDate, amount: 26_000, accountID: ledger.accounts[0].id, title: "Claude Pro")
        paid.planID = plan.id; paid.occurrence = plan.dueDate; ledger.entries = [paid]
        XCTAssertEqual(YearlyBillReserves.rows(in: ledger, now: day(2027, 11, 1)).first?.monthly, 2_167)
    }
    func testYearlyKeepExpiresForNextYearWhileMonthlyKeepPersists() throws {
        var ledger = ledger(); var plan = annual(due: day(2026, 11, 27)); ledger.plans = [plan]
        let renewal = try XCTUnwrap(HomeButler.renewals(ledger, now: day()).first)
        HomeButler.answer(renewal.id, in: &ledger, now: day())
        XCTAssertTrue(HomeButler.renewals(ledger, now: day()).isEmpty)
        plan.skippedOccurrences = [plan.dueDate]; ledger.plans = [plan]
        XCTAssertEqual(HomeButler.renewals(ledger, now: day(2027, 11, 20)).count, 1)
    }
    func testForeignYearlyButlerCopyShowsBothCurrenciesAndHidesBoth() throws {
        var ledger = ledger(); var plan = foreign(ledger, due: day(2026, 11, 27), yearly: true); plan.amount = 3_588; plan.title = "1Password 年付"; ledger.plans = [plan]
        let renewal = try XCTUnwrap(HomeButler.renewals(ledger, now: day()).first)
        let copy = try XCTUnwrap(HomeTaskCopy.make(.renewal(renewal), now: day(), hidden: false))
        XCTAssertTrue(copy.kicker.contains("7 天后续费")); XCTAssertEqual(copy.title, "一年 US$35.88，约 255.47")
        let hidden = try XCTUnwrap(HomeTaskCopy.make(.renewal(renewal), now: day(), hidden: true))
        XCTAssertFalse(hidden.title.contains("35.88")); XCTAssertFalse(hidden.title.contains("255.47"))
    }
    func testStopForeignRenewalTallyUsesCNY() throws {
        var ledger = ledger(); var plan = foreign(ledger, due: day(2026, 11, 27), yearly: true); plan.title = "年付"; ledger.plans = [plan]
        let renewal = try XCTUnwrap(HomeButler.renewals(ledger, now: day()).first)
        try HomeButler.stop(renewal, in: &ledger, now: day()); try ledger.validate()
        XCTAssertEqual(ledger.butlerSavings.first?.amount, 14_240)
        XCTAssertEqual(ButlerSavings.total(ledger, now: day(2026, 11, 28)), 14_240)
    }
    func testCalendarHonorsSystemWeekStartAndPaidAndYearlyStates() throws {
        var ledger = ledger(); var plan = foreign(ledger); ledger.plans = [plan]
        plan.id = UUID(); plan.title = "1Password"; plan.frequency = .yearly; ledger.plans.append(plan)
        var sunday = Dates.calendar; sunday.firstWeekday = 1
        var monday = Dates.calendar; monday.firstWeekday = 2
        let a = BillCalendarMonth(containing: day(), in: ledger, now: day(), calendar: sunday)
        let b = BillCalendarMonth(containing: day(), in: ledger, now: day(), calendar: monday)
        XCTAssertEqual(a.leadingDays, 0); XCTAssertEqual(b.leadingDays, 6)
        XCTAssertEqual(a.weekdaySymbols.first, "日"); XCTAssertEqual(b.weekdaySymbols.first, "一")
        XCTAssertEqual(a.days.first { $0.date == day(2026, 11, 28) }?.bills.count, 2)
        XCTAssertTrue(a.days.first { $0.date == day(2026, 11, 28) }!.yearly)
        XCTAssertEqual(a.yearlyMonths, [11])
        let change = try FixedFlows.settle(planID: ledger.plans[0].id, occurrence: ledger.plans[0].dueDate, in: ledger, now: day(2026, 11, 28))
        try change.apply(to: &ledger)
        let paid = BillCalendarMonth(containing: day(), in: ledger, now: day(2026, 11, 28))
        XCTAssertEqual(paid.paid, 14_240); XCTAssertEqual(paid.remaining, 14_240); XCTAssertEqual(paid.unpaidCount, 1)
    }
    func testCalendarIncludesPaydayAndHandlesLeapFebruaryAndEmptyMonths() {
        var ledger = ledger(); ledger.plans = [Plan(title: "工资", amount: 800_000, dueDate: day(2028, 2, 29), frequency: .monthly, inflow: true, category: "工资", nature: .income)]
        let month = BillCalendarMonth(containing: day(2028, 2, 1), in: ledger, now: day(2028, 2, 1))
        XCTAssertEqual(month.days.count, 29); XCTAssertTrue(month.days.last!.payday); XCTAssertEqual(month.remaining, 0)
        XCTAssertEqual(BillCalendarMonth(containing: day(2028, 1, 1), in: ledger, now: day()).unpaidCount, 0)
    }
    func testCreditPaymentDayClampsAndOldAccountsDecode() throws {
        XCTAssertEqual(CreditPaymentDate.next(day: 31, now: day(2027, 2, 1)), day(2027, 2, 28))
        XCTAssertEqual(CreditPaymentDate.next(day: 5, now: day(2026, 11, 20)), day(2026, 12, 5))
        let account = Account(name: "旧账户")
        XCTAssertNil(try JSONDecoder().decode(Account.self, from: JSONEncoder().encode(account)).creditPaymentDay)
    }
    func testMatchedPaymentPreviewReleasesReservationWithoutChargingCashAgain() throws {
        var ledger = ledger(); var plan = Plan(title: "话费", amount: 16_000, dueDate: day(), frequency: .monthly)
        plan.accountID = ledger.accounts[0].id; ledger.plans = [plan]
        let entry = Entry(date: day(), amount: 15_800, accountID: ledger.accounts[0].id, title: "话费")
        ledger.entries = [entry]
        let before = Finance.funds(ledger, now: day()).available
        let preview = FixedFlows.availableAfterPayment(planID: plan.id, occurrence: day(), amount: entry.amount, matchedEntryID: entry.id, in: ledger, now: day())
        XCTAssertEqual(preview, before + 16_000)
        try FixedFlows.markPaid(planID: plan.id, occurrence: day(), with: entry.id, in: &ledger)
        XCTAssertEqual(preview, Finance.funds(ledger, now: day()).available)
        XCTAssertEqual(ledger.entries.count, 1)
    }
    func testNewPaymentPreviewMatchesActualAnnualSettlement() throws {
        var ledger = ledger(); var plan = annual(due: day()); plan.accountID = ledger.accounts[0].id; ledger.plans = [plan]
        let preview = FixedFlows.availableAfterPayment(planID: plan.id, occurrence: day(), amount: 110_000, in: ledger, now: day())
        let change = try FixedFlows.confirmPayment(planID: plan.id, occurrence: day(), amount: 110_000, in: ledger, now: day())
        try change.apply(to: &ledger)
        XCTAssertEqual(preview, Finance.funds(ledger, now: day()).available)
        XCTAssertEqual(preview, 890_000)
        XCTAssertEqual(Finance.funds(ledger, now: day()).committed, 0)
        XCTAssertEqual(FixedFlows.month(containing: day(), in: ledger, asOf: day()).occurrences.first?.state, .paid)
    }
    func testMonthlyDayEditKeeps31AcrossShortMonth() throws {
        var ledger = ledger()
        let plan = Plan(title: "房租", amount: 100, dueDate: day(2027, 2, 27), frequency: .monthly)
        ledger.plans = [plan]
        let change = try FixedFlows.update(planID: plan.id, title: plan.title, amount: 100, frequency: .monthly, date: day(2027, 2, 28),
                                           accountID: nil, category: plan.category, installments: nil, autoPay: false, estimated: false,
                                           in: ledger, now: day(2027, 2, 1), monthlyDay: 31)
        try change.apply(to: &ledger)
        XCTAssertEqual(ledger.plans[0].scheduledDate(at: 0), day(2027, 2, 28))
        XCTAssertEqual(ledger.plans[0].scheduledDate(at: 1), day(2027, 3, 31))
    }
    func testCalendarCountsPartialPaymentsInPaidTotalAndOnlyRemainderAsUnpaid() throws {
        var ledger = ledger(); var plan = Plan(title: "部分付款", amount: 10_000, dueDate: day(), frequency: .monthly)
        plan.accountID = ledger.accounts[0].id; ledger.plans = [plan]
        let change = try FixedFlows.settle(planID: plan.id, occurrence: day(), amount: 4_000, in: ledger, now: day())
        try change.apply(to: &ledger)
        let month = BillCalendarMonth(containing: day(), in: ledger, now: day())
        XCTAssertEqual(month.paid, 4_000); XCTAssertEqual(month.remaining, 6_000); XCTAssertEqual(month.unpaidCount, 1)
    }
}
