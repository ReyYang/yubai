import XCTest
@testable import YubaiCore

final class Round45ReserveTests: XCTestCase {
    let now = Round45Fixture.now
    func testReservePurchasePreviewSaveDeleteAndRefund() throws {
        var l = Round45Fixture.ledger(); let original = l
        let before = Finance.funds(l, now: now).available
        let change = try ManualBookkeeping.change(amount: 120_000, nature: .expense, accountID: l.accounts[0].id, day: now,
                                                  purpose: "Coat", category: "购物", now: now, fromReserve: true)
        XCTAssertEqual(try ManualBookkeeping.available(after: change, in: l, now: now), before)
        try change.apply(to: &l)
        let purchase = try XCTUnwrap(l.entries.last)
        XCTAssertTrue(purchase.fromReserve); XCTAssertEqual(l.fixedSavingsTotal(now: now), 380_000)
        XCTAssertEqual(Finance.funds(l, now: now).available, before)
        XCTAssertEqual(Finance.pace(l, now: now)?.spent, Finance.pace(original, now: now)?.spent)
        let flow = Finance.cashFlow(l, during: DateInterval(start: Dates.day(now), end: Dates.addDays(1, to: now)))
        XCTAssertEqual(flow.spending, 123_600)
        var edited = purchase; edited.amount = 150_000
        XCTAssertEqual(try ManualBookkeeping.available(after: edited, in: l, now: now), before)
        try ManualBookkeeping.edit(edited, in: &l); XCTAssertEqual(l.fixedSavingsTotal(now: now), 350_000)
        var refund = Round45Fixture.entry(l, amount: 30_000, date: "2026-11-20 12:00", nature: .refund)
        refund.relatedEntryID = purchase.id; refund.recordedAt = now; l.entries.append(refund)
        XCTAssertEqual(l.fixedSavingsTotal(now: now), 380_000); XCTAssertEqual(Finance.funds(l, now: now).available, before)
        l.entries.removeAll { $0.id == purchase.id || $0.id == refund.id }
        XCTAssertEqual(l.fixedSavingsTotal(now: now), 500_000); XCTAssertEqual(Finance.funds(l, now: now).available, before)
        l = original; XCTAssertEqual(l.fixedSavingsTotal(now: now), 500_000)
    }
    func testReserveInsufficiencyAndNatureInvariant() throws {
        var l = Round45Fixture.ledger()
        let change = try ManualBookkeeping.change(amount: 500_001, nature: .expense, accountID: l.accounts[0].id, day: now,
                                                  purpose: "Coat", category: "购物", now: now, fromReserve: true)
        XCTAssertThrowsError(try change.apply(to: &l)) { XCTAssertEqual($0 as? YubaiError, .invalid("存着的钱不够。")) }
        XCTAssertThrowsError(try ManualBookkeeping.available(after: change, in: l, now: now))
        let valid = try ManualBookkeeping.change(amount: 120_000, nature: .expense, accountID: l.accounts[0].id, day: now,
                                                 purpose: "Coat", category: "购物", now: now, fromReserve: true)
        try valid.apply(to: &l)
        var edited = l.entries.last!; edited.amount = 500_001
        let before = l; XCTAssertThrowsError(try ManualBookkeeping.edit(edited, in: &l)); XCTAssertEqual(l, before)
        edited.nature = .income; XCTAssertFalse(edited.fromReserve)
        edited.fromReserve = true; XCTAssertFalse(edited.fromReserve)
        var draft = EntryDraft(date: now, amount: 1, accountID: l.accounts[0].id, title: "Test", fromReserve: true)
        draft.nature = .refund; XCTAssertFalse(draft.fromReserve)
    }
    func testNewPersistedFieldsAreOptionalAndFalseKeysAreOmitted() throws {
        var l = Round45Fixture.ledger(); let baseline = l
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(l)) as? [String: Any])
        XCTAssertNil(object["paydayConfirmSince"]); XCTAssertNil(object["cycleCovers"]); XCTAssertNil(object["reserveAdjustments"])
        for entry in try XCTUnwrap(object["entries"] as? [[String: Any]]) { XCTAssertNil(entry["fromReserve"]); XCTAssertNil(entry["spreadFrom"]) }
        XCTAssertEqual(try JSONDecoder().decode(Ledger.self, from: JSONEncoder().encode(l)), l)
        l.paydayConfirmSince = now; _ = Finance.funds(l, now: now)
        l.cycleCovers = [CycleCover(cycleStart: Finance.cycle(in: l, now: now).start, date: now, source: .saveLess, amount: 100)]
        l.reserveAdjustments = [ReserveAdjustment(date: now, delta: 10)]
        XCTAssertNotEqual(l, baseline)
        XCTAssertEqual(Finance.funds(l, now: now).savingTarget, 199_900)
        XCTAssertEqual(try JSONDecoder().decode(Ledger.self, from: JSONEncoder().encode(l)), l)
        let draft = EntryDraft(date: now, amount: 1, accountID: l.accounts[0].id, title: "Test")
        let draftObject = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(draft)) as? [String: Any])
        XCTAssertNil(draftObject["fromReserve"]); XCTAssertNil(draftObject["intoFixedSavings"])
        XCTAssertEqual(l.schema, 4)
    }
    func overspent() -> Ledger {
        var l = Round45Fixture.ledger(); l.entries = [Round45Fixture.entry(l, amount: 272_000, date: "2026-12-04")]
        l.accounts[0].anchorBalance = 1_029_000; l.accounts[0].anchorDate = Round45Fixture.date("2026-12-05 11:59")
        return l
    }
    func testOverspendBothRoutesAndCushion() throws {
        let at = Round45Fixture.date("2026-12-05 12:00")
        for source in [CycleCover.Source.saveLess, .fromReserve] {
            var l = overspent(); let options = try XCTUnwrap(Overspend.options(l, now: at))
            XCTAssertEqual(options.overBy, 32_000); XCTAssertEqual(options.daysLeft, 5)
            XCTAssertEqual(options.level, 32_000); XCTAssertEqual(options.cushion, 72_000)
            XCTAssertEqual(options.maxSaveLess, 200_000); XCTAssertEqual(options.maxFromReserve, 500_000)
            let preview = Overspend.preview(l, source: source, amount: 72_000, now: at)
            XCTAssertEqual(preview.before, source == .saveLess ? 200_000 : 500_000)
            XCTAssertEqual(preview.after, source == .saveLess ? 128_000 : 428_000)
            XCTAssertEqual(preview.availableAfter, 40_000); XCTAssertEqual(preview.dailyAfter, 8000)
            try Overspend.cover(&l, source: source, amount: 72_000, now: at)
            XCTAssertEqual(Finance.funds(l, now: at).available, 40_000); XCTAssertEqual(Finance.pace(l, now: at)?.daily, 8000)
            XCTAssertEqual(Finance.pace(l, now: at)?.budget, 312_000); XCTAssertNil(Overspend.options(l, now: at))
            if source == .saveLess {
                Savings.closeCycles(&l, now: Round45Fixture.date("2026-12-10 12:00"))
                XCTAssertEqual(l.savingHistory.last?.target, 200_000); XCTAssertEqual(l.savingHistory.last?.saved, 128_000)
                XCTAssertEqual(Finance.funds(l, now: Round45Fixture.date("2026-12-10 12:00")).savingTarget, 200_000)
            }
        }
    }
    func testOverspendLimitsInvalidAmountsAndZeroOptions() throws {
        let at = Round45Fixture.date("2026-12-05 12:00")
        var l = overspent()
        for amount in [-1 as Int64, 0, 200_001] { XCTAssertThrowsError(try Overspend.cover(&l, source: .saveLess, amount: amount, now: at)) }
        XCTAssertThrowsError(try Overspend.cover(&l, source: .fromReserve, amount: 500_001, now: at))
        l.fixedSavings = 0; l.savingRule = nil; l.accounts[0].anchorBalance = -1
        let options = try XCTUnwrap(Overspend.options(l, now: at))
        XCTAssertEqual(options.maxSaveLess, 0); XCTAssertEqual(options.maxFromReserve, 0)
    }
    func testBigPurchaseNumbersThresholdsAndReserveLimit() throws {
        var l = Round45Fixture.ledger(); let big = try XCTUnwrap(Finance.bigPurchase(l, amount: 120_000, now: now))
        XCTAssertEqual(big.days, 15); XCTAssertEqual(big.availableAfter, 36_400); XCTAssertEqual(big.reserveAfter, 380_000)
        XCTAssertTrue(big.canUseReserve); XCTAssertTrue(big.tight)
        XCTAssertEqual(Finance.bigPurchase(l, amount: 189_900, now: now)?.days, 24)
        XCTAssertNil(Finance.bigPurchase(l, amount: 56_000, now: now)); XCTAssertNotNil(Finance.bigPurchase(l, amount: 56_001, now: now))
        XCTAssertFalse(Finance.bigPurchase(l, amount: 500_001, now: now)!.canUseReserve)
        l.plans = []; l.cycleAnchor = nil
        XCTAssertNil(Finance.bigPurchase(l, amount: 120_000, now: now))
        l.entries = (1...90).map { day in Round45Fixture.entry(l, amount: 1000, date: Dates.text(Dates.addDays(-day, to: now))) }
        XCTAssertEqual(Finance.bigPurchase(l, amount: 8000, now: now)?.days, 8)
    }
    func testReserveOverviewSignsDatesAdjustmentsAndSetAside() throws {
        var l = Round45Fixture.ledger(); let initial = Reserve.overview(l, now: now)
        XCTAssertEqual(initial.total, 700_000); XCTAssertEqual(initial.setAside, 200_000)
        Reserve.setTotal(600_000, in: &l, now: now)
        XCTAssertEqual(l.fixedSavingsTotal(now: now), 600_000); XCTAssertEqual(l.reserveAdjustments.last?.delta, 100_000)
        let change = try ManualBookkeeping.change(amount: 120_000, nature: .expense, accountID: l.accounts[0].id, day: now, purpose: "Coat", category: "购物", now: now, fromReserve: true)
        try change.apply(to: &l)
        let result = Reserve.overview(l, now: now)
        XCTAssertEqual(result.total, 680_000)
        XCTAssertEqual(result.lines.first { if case .purchase = $0.kind { return true }; return false }?.title, "Coat")
        XCTAssertEqual(result.lines.first { if case .purchase = $0.kind { return true }; return false }?.amount, -120_000)
        XCTAssertEqual(result.lines.reduce(0) { $0 + $1.amount } + 500_000, result.total)
        let before = l; Reserve.setTotal(480_000, in: &l, now: now); XCTAssertEqual(l, before)
        l.fixedSavings = 0
        var income = Round45Fixture.entry(l, amount: 100_000, date: "2026-11-20 12:00", nature: .income); income.intoFixedSavings = true; income.recordedAt = now
        l.entries = [income]; l.cycleCovers = []
        l.setFixedSavingsTotal(0, now: now); XCTAssertEqual(l.fixedSavingsTotal(now: now), 100_000)
    }
    func testFormulaIdentityWithDebtGoalUncertainAndReserve() throws {
        var l = Round45Fixture.ledger()
        func check(_ ledger: Ledger) {
            let f = Finance.formula(ledger, now: now)
            XCTAssertEqual(f.hand - f.creditDebt - f.goals - f.uncertainInflow - f.fixedSavings - f.saving - f.billsRest, f.available)
            XCTAssertEqual(f.available, Finance.funds(ledger, now: now).available)
        }
        check(l)
        let f = Finance.formula(l, now: now)
        XCTAssertEqual(f.hand, 1_217_400); XCTAssertEqual(f.fixedSavings, 500_000); XCTAssertEqual(f.saving, 200_000); XCTAssertEqual(f.billsRest, 361_000); XCTAssertEqual(f.available, 156_400)
        l.accounts.append(Account(name: "Credit", kind: .credit, balance: -64_000, at: now))
        l.goals = [Goal(title: "Goal", target: 1000, reserved: 1000)]
        var uncertain = Round45Fixture.entry(l, amount: 500, date: "2026-11-20 12:00", nature: .unknownIn); uncertain.recordedAt = now; l.entries.append(uncertain)
        check(l)
        try Overspend.cover(&l, source: .saveLess, amount: 1000, now: now); check(l)
    }
}

extension Round45ReserveTests {
    func testReserveEditsCannotBorrowFutureEarmarkedIncome() throws {
        var l = Round45Fixture.ledger()
        let change = try ManualBookkeeping.change(amount: 120_000, nature: .expense, accountID: l.accounts[0].id, day: now,
                                                  purpose: "Coat", category: "购物", now: now, fromReserve: true)
        try change.apply(to: &l)
        let id = l.entries.last!.id
        var future = Round45Fixture.entry(l, amount: 1_000_000, date: "2026-12-01", nature: .income)
        future.intoFixedSavings = true; l.entries.append(future)
        var edited = l.entries.first { $0.id == id }!; edited.amount = 600_000
        XCTAssertThrowsError(try ManualBookkeeping.available(after: edited, in: l, now: now))
        XCTAssertThrowsError(try ManualBookkeeping.edit(edited, in: &l, now: now))
        XCTAssertThrowsError(try ManualBookkeeping.edit(edited, in: &l))
    }
    func testReserveTrueAndSpreadKeysRoundTripAndShareCoverUsesEffectiveTarget() throws {
        var l = Round45Fixture.ledger()
        l.savingRule = .share(20)
        let rule = Finance.funds(l, now: now).savingRuleTarget
        XCTAssertEqual(rule, 160_200)
        try Overspend.cover(&l, source: .saveLess, amount: 20_000, now: now)
        XCTAssertEqual(Finance.funds(l, now: now).savingRuleTarget, rule)
        XCTAssertEqual(Finance.funds(l, now: now).savingTarget, rule - 20_000)
        let change = try ManualBookkeeping.change(amount: 1000, nature: .expense, accountID: l.accounts[0].id, day: now,
                                                  purpose: "Test", category: "购物", now: now, fromReserve: true)
        try change.apply(to: &l)
        l.entries[l.entries.count - 1].spreadFrom = Dates.day(now)
        let decoded = try JSONDecoder().decode(Ledger.self, from: JSONEncoder().encode(l))
        XCTAssertEqual(decoded, l); XCTAssertTrue(decoded.entries.last!.fromReserve)
        let draft = EntryDraft(date: now, amount: 1000, accountID: l.accounts[0].id, title: "Test", fromReserve: true)
        XCTAssertEqual(try JSONDecoder().decode(EntryDraft.self, from: JSONEncoder().encode(draft)), draft)
        let at = Round45Fixture.date("2026-12-05 12:00")
        XCTAssertEqual(Reserve.overview(overspent(), now: at).setAside, 200_000)
    }
}
