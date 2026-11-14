import XCTest
@testable import YubaiCore

final class Round46NoticeTests: XCTestCase {
    let now = Dates.parse("2026-11-20 12:00")!
    func ledger() -> Ledger {
        var ledger = Round45Fixture.ledger()
        var prefs = ButlerNoticePreferences(); prefs.immediate = true; prefs.ordinary = true
        ledger.preferences.butlerNotices = prefs
        return ledger
    }
    func testOldPreferencesKeepSystemNotificationsOptInAndHomeEnabled() throws {
        let value = try JSONDecoder().decode(ButlerNoticePreferences.self, from: Data("{}".utf8))
        XCTAssertFalse(value.immediate); XCTAssertFalse(value.ordinary); XCTAssertTrue(value.home)
        XCTAssertTrue(ButlerNotices.planned(Round45Fixture.ledger(), now: now).isEmpty)
    }
    func testRenewalNotificationUsesTheHomeCardsExactCopyAndKeepCancelsIt() throws {
        var value = ledger()
        var plan = Plan(title: "视频会员", amount: 2500, dueDate: Dates.addDays(1, to: Dates.day(now)), frequency: .monthly, category: "订阅")
        plan.accountID = value.accounts[0].id; value.plans.append(plan)
        let task = try XCTUnwrap(HomeButler.queue(value, now: now).first { if case .renewal = $0 { return true }; return false })
        let notice = try XCTUnwrap(ButlerNotices.planned(value, now: now).first { $0.taskID == task.id })
        XCTAssertEqual(notice.copy, HomeTaskCopy.make(task, now: now, hidden: false))
        XCTAssertEqual(notice.copy.title, "每月 25.00"); XCTAssertEqual(notice.tier, .ordinary)
        HomeButler.answer(task.id, in: &value, now: now)
        XCTAssertFalse(ButlerNotices.planned(value, now: now).contains { $0.taskID == task.id })
    }
    func testDayOnlyFundingNeverClaimsTimeSensitiveUrgency() {
        var value = ledger()
        value.accounts = [Account(name: "卡", balance: 0, at: now), Account(name: "微信", balance: 50000, at: now)]
        var plan = Plan(title: "房租", amount: 30000, dueDate: Dates.addDays(1, to: Dates.day(now)))
        plan.accountID = value.accounts[0].id; value.plans = [plan]
        XCTAssertFalse(ButlerNotices.planned(value, now: now).contains { $0.tier == .immediate })
    }
    func testKnownTimeAndVerifiedFundingGapAllowImmediateNotice() throws {
        var value = ledger()
        value.accounts = [Account(name: "卡", balance: 0, at: now), Account(name: "微信", balance: 50000, at: now)]
        var plan = Plan(title: "房租", amount: 30000, dueDate: now.addingTimeInterval(1800))
        plan.accountID = value.accounts[0].id; value.plans = [plan]
        let notice = try XCTUnwrap(ButlerNotices.planned(value, now: now).first { $0.tier == .immediate })
        XCTAssertEqual(notice.copy.title, "卡里还差 300.00")
        value.preferences.hideAmounts = true
        XCTAssertEqual(ButlerNotices.planned(value, now: now).first { $0.tier == .immediate }?.copy.title, "卡里还差 ••••")
    }
    func testFutureNotificationsRetainRealOccurrenceIDsAndDoNotRepeatAnsweredItems() throws {
        let value = ledger()
        let notices = ButlerNotices.planned(value, now: now)
        XCTAssertTrue(notices.contains { $0.fireDate > now })
        XCTAssertEqual(Set(notices.map(\.id)).count, notices.count)
        XCTAssertTrue(notices.allSatisfy { !$0.copy.title.isEmpty && !$0.copy.kicker.isEmpty })
        var decoded = try LedgerCodec.decode(LedgerCodec.encode(value))
        decoded.preferences.butlerNotices?[.ordinary] = false
        XCTAssertFalse(ButlerNotices.planned(decoded, now: now).contains { $0.tier == .ordinary })
        // Weekly bills do not inherit the monthly renewal's one-day lead.
        var weekly = ledger()
        let due = Dates.addDays(4, to: now)
        weekly.plans = [Plan(title: "每周会员", amount: 2500, dueDate: due, frequency: .weekly, category: "订阅")]
        let reminder = try XCTUnwrap(ButlerNotices.planned(weekly, now: now).first)
        XCTAssertEqual(Dates.day(reminder.fireDate), Dates.day(due))
        XCTAssertEqual(reminder.copy.kicker, "固定账单 · 今天到期")
    }
    func testNotificationFocusRaisesTheRequestedCardWithoutDroppingOtherCards() {
        var deck = ButlerDeck(); deck.reconcile(["one", "two", "three"]); deck.focus("three")
        XCTAssertEqual(deck.ids, ["three", "one", "two"])
        deck.cycle(); XCTAssertEqual(deck.ids, ["one", "two", "three"])
    }
}
