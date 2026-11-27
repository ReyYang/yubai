import XCTest
import YubaiCore
@testable import YubaiApp

/// The real store paths: editing a bill, 记下 with a category, the delete bar, linked refunds, the long-press menu.
/// Each test writes into its own temporary folder.
@MainActor
final class BillEditingStoreTests: XCTestCase {
    private let now = Dates.parse("2026-11-23 14:20:00")!
    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("yubai-store-tests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private struct Book {
        var ledger: Ledger
        let bank: Account, bank2: Account, credit: Account, invest: Account
    }

    private func book() -> Book {
        let start = Dates.parse("2026-11-01")!
        var ledger = Ledger()
        let bank = Account(name: "招行", kind: .bank, balance: 1_000_000, at: start)
        let bank2 = Account(name: "工行", kind: .bank, balance: 1_000_000, at: start)
        let credit = Account(name: "信用卡", kind: .credit, at: start)
        let invest = Account(name: "基金", kind: .investment, balance: 100_000, at: start)
        ledger.accounts = [bank, bank2, credit, invest]
        ledger.categories = [YubaiCore.Category("吃饭", keywords: ["午饭"]), YubaiCore.Category("交通"),
                             YubaiCore.Category("其他支出"), YubaiCore.Category("工资", income: true)]
        ledger.preferences.onboardingComplete = true
        return Book(ledger: ledger, bank: bank, bank2: bank2, credit: credit, invest: invest)
    }

    private func store(_ ledger: Ledger) throws -> AppStore {
        try ledger.validate()
        return AppStore(testing: ledger, directory: directory)
    }

    /// Opens the editor, changes only the amount and saves, as a person would.
    private func editAmount(_ entry: Entry, in store: AppStore, to cents: Int64) throws -> Entry {
        store.openBillEditor(entry)
        let model = try XCTUnwrap(store.entrySheet)
        model.draft.expression = EntryAmountExpression(cents: cents)
        XCTAssertTrue(model.save(), model.failure ?? "not saved")
        return try XCTUnwrap(store.current.entries.first { $0.id == entry.id })
    }

    // MARK: 1 · editing keeps the route

    func testEditingAOneSidedInvestBuyKeepsItOneSided() throws {
        var book = book()
        var buy = Entry(date: now, amount: 30_000, nature: .investBuy, accountID: book.bank.id, title: "导入的申购", category: "内部移动")
        buy.otherAccountID = nil
        book.ledger.entries = [buy]
        let store = try store(book.ledger)
        let edited = try editAmount(buy, in: store, to: 31_000)
        XCTAssertEqual(edited.nature, .investBuy)
        XCTAssertNil(edited.otherAccountID, "no second account appears out of nowhere")
        XCTAssertEqual(edited.amount, 31_000)
    }

    func testEditingAnOldBankToCreditTransferStaysATransfer() throws {
        var book = book()
        var move = Entry(date: now, amount: 50_000, nature: .transfer, accountID: book.bank.id, title: "转到信用卡", category: "内部移动")
        move.otherAccountID = book.credit.id
        book.ledger.entries = [move]
        let store = try store(book.ledger)
        let edited = try editAmount(move, in: store, to: 51_000)
        XCTAssertEqual(edited.nature, .transfer, "not turned into a repayment")
        XCTAssertEqual(edited.otherAccountID, book.credit.id)
    }

    func testEditingAnOldSavingsTransferIntoInvestmentKeepsItsMark() throws {
        var book = book()
        var saved = Entry(date: now, amount: 20_000, nature: .transfer, accountID: book.bank.id, title: "存起来", category: "内部移动")
        saved.otherAccountID = book.invest.id
        saved.intoFixedSavings = true
        book.ledger.entries = [saved]
        let store = try store(book.ledger)
        let edited = try editAmount(saved, in: store, to: 21_000)
        XCTAssertEqual(edited.nature, .transfer, "not turned into an investment buy")
        XCTAssertTrue(edited.intoFixedSavings)
        XCTAssertEqual(edited.otherAccountID, book.invest.id)
    }

    func testEditingAPlannedInvestBuyKeepsItsPlanLink() throws {
        var book = book()
        var plan = Plan(title: "定投", amount: 50_000, dueDate: now, frequency: .monthly, inflow: false, category: "内部移动", nature: .investBuy)
        plan.accountID = book.bank.id
        plan.otherAccountID = book.invest.id
        var buy = Entry(date: now, amount: 50_000, nature: .investBuy, accountID: book.bank.id, title: "定投", category: "内部移动")
        buy.otherAccountID = book.invest.id
        buy.planID = plan.id
        buy.occurrence = now
        book.ledger.plans = [plan]
        book.ledger.entries = [buy]
        let store = try store(book.ledger)
        let edited = try editAmount(buy, in: store, to: 50_100)
        XCTAssertEqual(edited.nature, .investBuy)
        XCTAssertEqual(edited.planID, plan.id)
        XCTAssertEqual(edited.occurrence, now)
        XCTAssertEqual(edited.otherAccountID, book.invest.id)
    }

    // MARK: 2 · 记下 needs a category it can see

    func testSaveUsesOnlyTheSuggestionOnScreen() throws {
        let store = try store(book().ledger)
        store.openEntrySheet()
        let model = try XCTUnwrap(store.entrySheet)
        model.draft.expression = EntryAmountExpression(cents: 2_800)
        model.draft.purpose = "zzqx"
        model.schedulePreview()
        XCTAssertNil(model.shownSuggestion)
        XCTAssertFalse(model.save(), "no category and nothing suggested")
        XCTAssertEqual(model.blockedSave(), .category)
        model.draft.purpose = "午饭"
        model.schedulePreview()
        XCTAssertEqual(model.shownSuggestion?.category, "吃饭")
        XCTAssertTrue(model.save())
        XCTAssertEqual(store.current.activeEntries.last?.category, "吃饭")
    }

    func testEditingAPendingBillAsksAgainAfterAnyCategoryChange() throws {
        var book = book()
        let pending = Entry(date: now, amount: 1_200, accountID: book.bank.id, title: "便利店", category: Classification.pendingCategory)
        book.ledger.entries = [pending]
        let store = try store(book.ledger)
        store.openBillEditor(pending)
        let model = try XCTUnwrap(store.entrySheet)
        XCTAssertNil(model.blockedSave(), "untouched 待整理 saves as it was")
        model.select(.income)
        model.select(.expense)
        model.draft.expression = EntryAmountExpression(cents: 1_200)
        XCTAssertEqual(model.blockedSave(), .category, "收入 and back is not untouched")
    }

    // MARK: 3 · the delete bar

    func testAnExpiredBarUndoesNothing() throws {
        var book = book()
        let lunch = Entry(date: now, amount: 1_200, accountID: book.bank.id, title: "午饭", category: "吃饭")
        book.ledger.entries = [lunch]
        let store = try store(book.ledger)
        XCTAssertTrue(store.deleteBill(lunch))
        let live = try XCTUnwrap(store.billUndo)
        store.billUndo = BillUndoNotice(label: live.label, entryIDs: live.entryIDs, deletedAt: live.deletedAt,
                                        deadline: Date().addingTimeInterval(-1))
        store.undoBillDeletion(try XCTUnwrap(store.billUndo?.id))
        XCTAssertFalse(store.current.activeEntries.contains { $0.id == lunch.id })
    }

    func testALockedLedgerKeepsTheBarAndUndoDoesNotRollBackLaterRenames() throws {
        var book = book()
        let lunch = Entry(date: now, amount: 1_200, accountID: book.bank.id, title: "午饭", category: "吃饭")
        book.ledger.entries = [lunch]
        let store = try store(book.ledger)
        XCTAssertTrue(store.deleteBill(lunch))
        let id = try XCTUnwrap(store.billUndo?.id)
        store.locked = true
        store.undoBillDeletion(id)
        XCTAssertEqual(store.billUndo?.id, id, "a write that cannot happen does not use up the bar")
        store.locked = false
        store.error = nil
        // A category rename in 记一笔 after the delete stays when the delete is undone.
        store.openEntrySheet()
        let model = try XCTUnwrap(store.entrySheet)
        XCTAssertTrue(model.mutateLedger("编辑分类") { try CategoryModel.rename("交通", to: "出行", income: false, in: &$0) })
        store.undoBillDeletion(id)
        XCTAssertTrue(store.current.activeEntries.contains { $0.id == lunch.id })
        XCTAssertTrue(store.current.categories.contains { $0.name == "出行" })
        XCTAssertNil(store.billUndo)
        store.undo()
        XCTAssertTrue(store.current.activeEntries.contains { $0.id == lunch.id }, "no older snapshot deletes it again")
        XCTAssertTrue(store.current.categories.contains { $0.name == "出行" })
    }

    func testAGeneralUndoAfterACategoryEditKeepsTheRename() throws {
        var book = book()
        let lunch = Entry(date: now, amount: 1_200, accountID: book.bank.id, title: "午饭", category: "吃饭")
        book.ledger.entries = [lunch]
        let store = try store(book.ledger)
        _ = try editAmount(lunch, in: store, to: 1_300)
        store.closeEntrySheet(try XCTUnwrap(store.entrySheet?.id))
        store.openEntrySheet()
        XCTAssertTrue(try XCTUnwrap(store.entrySheet).mutateLedger("编辑分类") {
            try CategoryModel.rename("交通", to: "出行", income: false, in: &$0)
        })
        store.undo()
        XCTAssertTrue(store.current.categories.contains { $0.name == "出行" }, "the rename is not rolled back")
    }

    // MARK: 4 · linked refunds go with the bill

    func testDeletingABillTakesItsLinkedRefundsEvenWhenNoLongerPending() throws {
        var book = book()
        let taxi = Entry(date: now, amount: 3_650, accountID: book.bank.id, title: "打车", category: "交通")
        var refund = Entry(date: now, amount: 3_650, nature: .refund, accountID: book.bank.id, title: "打车", category: "交通")
        refund.relatedEntryID = taxi.id
        book.ledger.entries = [taxi, refund]
        let store = try store(book.ledger)
        XCTAssertTrue(store.deleteBill(taxi))
        XCTAssertFalse(store.current.activeEntries.contains { $0.id == refund.id })
        XCTAssertEqual(store.billUndo?.entryIDs, [taxi.id, refund.id])
        store.undoBillDeletion(try XCTUnwrap(store.billUndo?.id))
        XCTAssertTrue(store.current.activeEntries.contains { $0.id == refund.id })
    }

    // MARK: 5 · the long-press menu never outlives its bill

    func testTheMenuClosesWhenItsBillGoes() throws {
        var book = book()
        let lunch = Entry(date: now, amount: 1_200, accountID: book.bank.id, title: "午饭", category: "吃饭")
        book.ledger.entries = [lunch]
        let store = try store(book.ledger)
        store.billMenu = BillMenuRequest(entryID: lunch.id, frame: .zero, icon: .catFood, name: "午饭", amount: "−12.00",
                                         detail: nil, detailAmount: nil, amountColor: DS.Color.ink)
        XCTAssertTrue(store.update("删除", recordUndo: false) { try EntryRecovery.delete(lunch.id, from: &$0, now: self.now) })
        XCTAssertNil(store.billMenu)
    }
}
