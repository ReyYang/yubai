import XCTest
import YubaiCore
@testable import YubaiApp

/// 记一笔's rules: which 转账 is 存入, and when 记下 needs a category.
@MainActor
final class EntrySheetRulesTests: XCTestCase {
    private let now = Dates.parse("2026-11-23 14:20:00")!

    private func ledger() -> (Ledger, bank: Account, bank2: Account, credit: Account, invest: Account, invest2: Account) {
        let start = Dates.parse("2026-11-01")!
        var ledger = Ledger()
        let bank = Account(name: "招行", kind: .bank, balance: 1_000_000, at: start)
        let bank2 = Account(name: "工行", kind: .bank, balance: 1_000_000, at: start)
        let credit = Account(name: "信用卡", kind: .credit, at: start)
        let invest = Account(name: "基金", kind: .investment, balance: 100_000, at: start)
        let invest2 = Account(name: "养老", kind: .investment, at: start)
        ledger.accounts = [bank, bank2, credit, invest, invest2]
        return (ledger, bank, bank2, credit, invest, invest2)
    }

    private func transfer(_ from: Account, _ to: Account) -> EntrySheetDraft {
        var draft = EntrySheetDraft()
        draft.type = .transfer
        draft.accountID = from.id
        draft.destinationID = to.id
        draft.expression = EntryAmountExpression(cents: 20_000)
        return draft
    }

    func testOnlyCashOrBankIntoInvestmentIsDeposit() {
        let (ledger, bank, bank2, credit, invest, invest2) = ledger()
        XCTAssertTrue(EntrySheetViewModel(fixtureLedger: ledger, draft: transfer(bank, invest), now: now).savesAsDeposit)
        XCTAssertFalse(EntrySheetViewModel(fixtureLedger: ledger, draft: transfer(bank, bank2), now: now).savesAsDeposit)
        XCTAssertFalse(EntrySheetViewModel(fixtureLedger: ledger, draft: transfer(credit, invest), now: now).savesAsDeposit)
        XCTAssertFalse(EntrySheetViewModel(fixtureLedger: ledger, draft: transfer(invest2, invest), now: now).savesAsDeposit)
    }

    func testCreditIntoInvestmentSavesAsATransfer() {
        let (ledger, _, _, credit, invest, _) = ledger()
        let model = EntrySheetViewModel(fixtureLedger: ledger, draft: transfer(credit, invest), now: now)
        XCTAssertTrue(model.save())
        XCTAssertNil(model.failure)
        XCTAssertEqual(model.ledger.entries.last?.nature, .transfer)
    }

    func testDepositDraftIsReadAsTransferAndDoesNotCarryToOtherAccounts() {
        let (ledger, bank, bank2, credit, invest, _) = ledger()
        var draft = transfer(bank, bank2)
        draft.type = .deposit
        let model = EntrySheetViewModel(fixtureLedger: ledger, draft: draft, now: now)
        XCTAssertEqual(model.draft.type, .transfer)
        XCTAssertTrue(model.savesAsDeposit, "a bill read back stays as it was saved")
        model.selectAccount(invest.id, destination: true)
        XCTAssertTrue(model.savesAsDeposit, "招行 → 基金 decided afresh")
        model.selectAccount(credit.id, destination: false)
        XCTAssertFalse(model.savesAsDeposit, "信用卡 → 基金 is a 转账")
    }

    func testEditedDepositKeepsNatureUntilAnAccountChanges() {
        let (ledger, bank, _, credit, invest, _) = ledger()
        var buy = Entry(date: now, amount: 30_000, nature: .investBuy, accountID: bank.id, title: "定投", category: "内部移动")
        buy.otherAccountID = invest.id
        let draft = EntrySheetDraft(prefill: QuickEntryPrefill(copying: buy, date: now, keepLink: true), ledger: ledger)
        let model = EntrySheetViewModel(fixtureLedger: ledger, draft: draft, now: now, editingID: buy.id)
        XCTAssertEqual(model.draft.type, .transfer)
        XCTAssertTrue(model.savesAsDeposit)
        model.selectAccount(credit.id, destination: false)
        XCTAssertFalse(model.savesAsDeposit)
    }

    func testMonthlyDepositIntoInvestmentCanRepeat() {
        let (ledger, bank, bank2, _, invest, _) = ledger()
        XCTAssertTrue(EntrySheetViewModel(fixtureLedger: ledger, draft: transfer(bank, invest), now: now).canRepeat)
        XCTAssertFalse(EntrySheetViewModel(fixtureLedger: ledger, draft: transfer(bank, bank2), now: now).canRepeat)
    }

    private func expense(_ account: Account, purpose: String = "") -> EntrySheetDraft {
        var draft = EntrySheetDraft()
        draft.accountID = account.id
        draft.purpose = purpose
        draft.date = now
        draft.expression = EntryAmountExpression(cents: 2_800)
        return draft
    }

    func testSaveNeedsACategory() {
        let (ledger, bank, _, _, _, _) = ledger()
        let model = EntrySheetViewModel(fixtureLedger: ledger, draft: expense(bank), now: now)
        XCTAssertFalse(model.save())
        XCTAssertTrue(model.needsCategory)
        XCTAssertEqual(model.blockedSave(), .category)
        model.select(category: "吃饭")
        XCTAssertTrue(model.save())
    }

    func testAStaleSuggestionIsNeverSaved() {
        let (ledger, bank, _, _, _, _) = ledger()
        let model = EntrySheetViewModel(fixtureLedger: ledger, draft: expense(bank, purpose: "zzqx"), now: now)
        // A guess made for other words, still on screen when 记下 is pressed.
        model.suggestion = CategoryAssignment(category: "交通")
        XCTAssertFalse(model.save())
        XCTAssertEqual(model.blockedSave(), .category)
    }

    func testEditingAsksAgainAfterDirectionChangeOrClearing() {
        let (ledger, bank, _, _, _, _) = ledger()
        var pending = expense(bank)
        pending.category = nil
        let untouched = EntrySheetViewModel(fixtureLedger: ledger, draft: pending, now: now, editingID: UUID())
        XCTAssertNil(untouched.blockedSave(), "an untouched 待整理 bill saves as it was")
        untouched.select(.income)
        untouched.draft.expression = EntryAmountExpression(cents: 2_800)
        XCTAssertEqual(untouched.blockedSave(), .category)

        var picked = expense(bank)
        picked.category = "吃饭"
        let cleared = EntrySheetViewModel(fixtureLedger: ledger, draft: picked, now: now, editingID: UUID())
        XCTAssertNil(cleared.blockedSave())
        cleared.toggle(category: "吃饭")
        XCTAssertEqual(cleared.blockedSave(), .category)
    }

    func testEditingATransferIntoAnExpenseAsksForACategory() {
        let (ledger, bank, _, _, invest, _) = ledger()
        var buy = Entry(date: now, amount: 30_000, nature: .investBuy, accountID: bank.id, title: "定投", category: "内部移动")
        buy.otherAccountID = invest.id
        let draft = EntrySheetDraft(prefill: QuickEntryPrefill(copying: buy, date: now, keepLink: true), ledger: ledger)
        let model = EntrySheetViewModel(fixtureLedger: ledger, draft: draft, now: now, editingID: buy.id)
        XCTAssertNil(model.blockedSave())
        model.select(.expense)
        XCTAssertEqual(model.blockedSave(), .category, "a 转账 turned 支出 is not an untouched 待整理 bill")
    }

    func testACopiedDepositDecidesByItsAccounts() {
        let (ledger, bank, bank2, _, _, _) = ledger()
        var saved = Entry(date: now, amount: 30_000, nature: .transfer, accountID: bank.id, title: "存起来", category: "内部移动")
        saved.otherAccountID = bank2.id
        saved.intoFixedSavings = true
        let prefill = QuickEntryPrefill(copying: saved, date: now)
        let edit = EntrySheetViewModel(fixtureLedger: ledger, draft: EntrySheetDraft(prefill: prefill, ledger: ledger), now: now, editingID: saved.id)
        XCTAssertTrue(edit.savesAsDeposit, "editing keeps it 存入")
        var copy = EntrySheetDraft(prefill: prefill, ledger: ledger)
        copy.keptRoute = copy.keptRoute.map { EntryKeptRoute(accountID: $0.accountID, destinationID: $0.destinationID, nature: $0.nature, intoFixedSavings: $0.intoFixedSavings, deposit: nil) }
        XCTAssertFalse(EntrySheetViewModel(fixtureLedger: ledger, draft: copy, now: now).savesAsDeposit, "再记一笔 招行 → 工行 is a 转账")
    }

    func testReorderKeepsHiddenCategoriesInTheirSlots() {
        var (ledger, bank, _, _, _, _) = ledger()
        ledger.categories = ["甲", "乙", "丙", "丁"].map { YubaiCore.Category($0) }
        ledger.categories[1].hidden = true
        ledger.preferences.categoryOrder = ["甲", "乙", "丙", "丁"].map { CategoryNamespace.key($0, income: false) }
        let model = EntrySheetViewModel(fixtureLedger: ledger, draft: expense(bank), now: now)
        model.reorderVisibleCategories(["丁", "甲", "丙"], income: false)
        XCTAssertEqual(model.ledger.categoryOrder(income: false), ["丁", "乙", "甲", "丙"])
    }

    func testDraftFollowsACategoryOnlyInItsOwnDirection() {
        let (ledger, bank, _, _, _, _) = ledger()
        var draft = expense(bank)
        draft.category = "其他"
        let model = EntrySheetViewModel(fixtureLedger: ledger, draft: draft, now: now)
        XCTAssertTrue(model.draftUses(category: "其他", income: false))
        XCTAssertFalse(model.draftUses(category: "其他", income: true))
    }
}
