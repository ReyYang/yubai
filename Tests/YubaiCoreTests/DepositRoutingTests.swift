import Foundation
import XCTest
@testable import YubaiCore

/// 存入 is cash or a bank account into an investment account; every other route is a plain 转账.
final class DepositRoutingTests: XCTestCase {
    private let now = Dates.parse("2026-11-23 14:20:00")!
    private let start = Dates.parse("2026-11-01 00:00:00")!

    private func ledger() -> (Ledger, bank: Account, credit: Account, invest: Account, invest2: Account) {
        var ledger = Ledger()
        let bank = Account(name: "招行储蓄", kind: .bank, balance: 3_000_000, at: start)
        let credit = Account(name: "招行信用卡", kind: .credit, balance: -100_000, at: start)
        let invest = Account(name: "基金账户", kind: .investment, balance: 500_000, at: start)
        let invest2 = Account(name: "养老账户", kind: .investment, balance: 200_000, at: start)
        ledger.accounts = [bank, credit, invest, invest2]
        return (ledger, bank, credit, invest, invest2)
    }

    private func added(_ change: ChangeSet) -> EntryDraft? {
        for case .addEntry(let draft) in change.items { return draft }
        return nil
    }

    func testCreditAndInvestmentSourcesSaveAsPlainTransfers() throws {
        let (base, _, credit, invest, invest2) = ledger()
        for source in [credit, invest2] {
            var ledger = base
            let input = EntrySaveInput(type: .transfer, amountCents: 20_000, purpose: "", category: "内部移动",
                                       accountID: source.id, destinationAccountID: invest.id, date: now)
            let change = try EntrySaveMapper.makeChange(input, in: ledger, now: now)
            XCTAssertEqual(added(change)?.nature, .transfer)
            XCTAssertEqual(added(change)?.intoFixedSavings, false)
            XCTAssertNoThrow(try change.apply(to: &ledger), "\(source.name) → 基金 must save")
        }
    }

    func testEditingADepositKeepsItsNatureAndLinks() throws {
        var (ledger, bank, _, invest, _) = ledger()
        var buy = Entry(date: now, amount: 50_000, nature: .investBuy, accountID: bank.id, title: "定投", category: "内部移动")
        buy.otherAccountID = invest.id
        buy.note = "月定投"
        ledger.entries = [buy]
        let input = EntrySaveInput(type: .deposit, amountCents: 60_000, purpose: "定投", category: "内部移动",
                                   accountID: bank.id, destinationAccountID: invest.id, date: now)
        try EntrySaveMapper.edit(buy.id, input: input, in: &ledger, now: now)
        let edited = try XCTUnwrap(ledger.entries.first)
        XCTAssertEqual(edited.nature, .investBuy)
        XCTAssertEqual(edited.note, "月定投")
        XCTAssertEqual(edited.amount, 60_000)
    }

    func testDepositedThisCycleIsPositiveAndCountsTheDraftOnlyInThisCycle() {
        var (ledger, bank, _, invest, _) = ledger()
        ledger.cycleAnchor = .calendarMonth
        var buy = Entry(date: Dates.parse("2026-11-05")!, amount: 30_000, nature: .investBuy, accountID: bank.id, title: "基金", category: "内部移动")
        buy.otherAccountID = invest.id
        var saved = Entry(date: Dates.parse("2026-11-06")!, amount: 20_000, nature: .income, accountID: bank.id, title: "奖金", category: "工资")
        saved.intoFixedSavings = true
        let lastMonth = Entry(date: Dates.parse("2026-10-20")!, amount: 99_900, nature: .investBuy, accountID: bank.id, title: "旧", category: "内部移动")
        ledger.entries = [buy, saved, lastMonth]
        XCTAssertEqual(EntrySaveMapper.depositedThisCycle(in: ledger, now: now, adding: 10_000, on: now), 60_000)
        XCTAssertEqual(EntrySaveMapper.depositedThisCycle(in: ledger, now: now, adding: 10_000, on: Dates.parse("2026-10-30")!), 50_000)
    }
}
