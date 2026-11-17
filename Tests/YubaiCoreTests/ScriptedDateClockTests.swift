import XCTest
@testable import YubaiCore

final class ScriptedDateClockTests: XCTestCase {
    private let arguments = ["Yubai", "--test-ledger", "47000000-0000-0000-0000-000000470001"]
    private let beforeMidnight = Dates.parse("2026-11-13T23:59:50Z")!

    func testOneInjectedInstantSurvivesMidnightAndRelaunch() throws {
        let environment = ["YUBAI_UI_TEST_SCRIPT": "v47-receipt-normal", "YUBAI_UI_TEST_NOW": String(beforeMidnight.timeIntervalSince1970)]
        let first = try XCTUnwrap(ScriptedDateClock.capture(arguments: arguments, environment: environment, launchedAt: beforeMidnight))
        let second = try XCTUnwrap(ScriptedDateClock.capture(arguments: arguments, environment: environment, launchedAt: beforeMidnight.addingTimeInterval(120)))
        XCTAssertEqual(first, beforeMidnight)
        XCTAssertEqual(second, first)
        var ledger = Ledger()
        let account = Account(name: "现金", balance: 10_000, at: first)
        ledger.accounts = [account]
        ledger.entries = [Entry(date: first, amount: 2800, accountID: account.id, title: "午饭", category: "餐饮")]
        XCTAssertEqual(DailyReceipt.make(ledger, now: first).count, 1)
        XCTAssertEqual(DailyReceipt.make(ledger, now: first).total, 2800)
        XCTAssertEqual(DailyReceipt.make(ledger, now: first), DailyReceipt.make(ledger, now: second))
    }
    func testScriptWithoutInjectedInstantCapturesItsLaunch() {
        XCTAssertEqual(ScriptedDateClock.capture(arguments: arguments, environment: ["YUBAI_UI_TEST_SCRIPT": "v47-first"], launchedAt: beforeMidnight), beforeMidnight)
    }
    func testClockRequiresBothIsolatedLedgerAndScript() {
        let environment = ["YUBAI_UI_TEST_SCRIPT": "v47-first", "YUBAI_UI_TEST_NOW": "0"]
        XCTAssertNil(ScriptedDateClock.capture(arguments: [], environment: environment, launchedAt: beforeMidnight))
        XCTAssertNil(ScriptedDateClock.capture(arguments: ["--test-ledger", "real-ledger"], environment: environment, launchedAt: beforeMidnight))
        XCTAssertNil(ScriptedDateClock.capture(arguments: arguments, environment: ["YUBAI_UI_TEST_NOW": "0"], launchedAt: beforeMidnight))
    }
    func testInvalidClockValueFallsBackToOneLaunchInstant() {
        for value in ["not a date", "nan", "inf"] {
            XCTAssertEqual(ScriptedDateClock.capture(arguments: arguments, environment: ["YUBAI_UI_TEST_SCRIPT": "v47-first", "YUBAI_UI_TEST_NOW": value], launchedAt: beforeMidnight), beforeMidnight)
        }
    }
}
