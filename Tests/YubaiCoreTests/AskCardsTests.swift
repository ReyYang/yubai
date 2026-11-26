import Foundation
import XCTest
@testable import YubaiCore

/// 问余白 cards, the AI wiring and the weekly letter time (batch 4 run 2).
final class AskCardsTests: XCTestCase {
    private func date(_ value: String) -> Date { Dates.parse(value)! }
    private let now = Dates.parse("2026-11-23 12:00")!

    private func sample() -> (Ledger, Account) {
        let bank = Account(name: "招行储蓄", balance: 2_000_000, at: date("2026-10-01"))
        var ledger = Ledger()
        ledger.accounts = [bank]
        ledger.cycleAnchor = .calendarMonth
        ledger.categories = ["吃饭", "购物", "交通"].map { Category($0) } + [Category("工资", income: true)]
        ledger.entries = [Entry(date: date("2026-11-01"), amount: 1_000_000, nature: .income, accountID: bank.id, title: "工资", category: "工资")]
        ledger.spendingParts = [SpendingPart(name: "购物", amount: 150_000, categories: ["购物"]),
                                SpendingPart(name: "交通", amount: 60_000, categories: ["交通"])]
        ledger.entries.append(Entry(date: date("2026-11-10"), amount: 131_800, accountID: bank.id, title: "衣服", category: "购物"))
        var taxi = Entry(date: date("2026-11-22 18:00"), amount: 3_650, accountID: bank.id, title: "打车", category: "交通")
        taxi.pendingRecovery = .reimbursement
        ledger.entries.append(taxi)
        return (ledger, bank)
    }

    func testVerdictWordsComeFromCodeNotTheModel() {
        XCTAssertEqual(AskVerdictWord.word(.skip, title: "降噪耳机", category: "购物"), "先别买")
        XCTAssertEqual(AskVerdictWord.word(.wait, title: "羽绒被", category: "购物"), "建议延后")
        XCTAssertEqual(AskVerdictWord.word(.buy, title: "羽绒被", category: "购物"), "可以买")
        XCTAssertEqual(AskVerdictWord.word(.buy, title: "周末和朋友吃火锅", category: nil), "可以去")
    }

    func testPurchaseCardHeadlineAndOverrun() {
        let (ledger, _) = sample()
        let skip = AskPurchaseCard.make(ledger: ledger, title: "降噪耳机", amount: 129_900, category: "购物", verdict: .skip, daysLeft: 8, now: now)
        XCTAssertEqual(skip.headline.label, "还能花")
        XCTAssertEqual(skip.headline.to, skip.headline.from - 129_900)
        XCTAssertEqual(skip.changes.map(\.label), ["购物还剩", "每天"])
        XCTAssertEqual(skip.changes[0].from, 18_200)
        XCTAssertEqual(skip.changes[0].to, -111_700)
        XCTAssertTrue(skip.changes[0].overrun)
        XCTAssertNil(skip.remindOn)

        let wait = AskPurchaseCard.make(ledger: ledger, title: "羽绒被", amount: 89_900, category: "购物", verdict: .wait, daysLeft: 8, now: now)
        XCTAssertEqual(wait.headline.label, "购物还剩")
        XCTAssertEqual(wait.headline.to, -71_700)
        XCTAssertEqual(wait.remindOn, date("2026-12-01"))
    }

    func testBatchDuplicatesStartUncheckedAndTotalFollowsChecks() throws {
        let (ledger, bank) = sample()
        let lunch = EntryDraft(date: date("2026-11-23"), amount: 3_680, accountID: bank.id, title: "美团外卖", category: "吃饭")
        let taxi = EntryDraft(date: date("2026-11-22"), amount: 3_650, accountID: bank.id, title: "滴滴", category: "交通")
        let refund = EntryDraft(date: date("2026-11-22"), amount: 5_900, nature: .income, accountID: bank.id, title: "退款", category: "工资")
        let drafts = [lunch, taxi, refund]
        XCTAssertTrue(AskBatch.isLikelyDuplicate(taxi, in: ledger))
        XCTAssertEqual(AskBatch.initiallyChecked(drafts, in: ledger), [lunch.id, refund.id])

        let checked = AskBatch.initiallyChecked(drafts, in: ledger)
        let total = AskBatch.total(drafts, checked: checked, in: ledger, now: now)
        XCTAssertEqual(total.to - total.from, 5_900 - 3_680)
        let withTaxi = AskBatch.total(drafts, checked: checked.union([taxi.id]), in: ledger, now: now)
        XCTAssertEqual(withTaxi.to - withTaxi.from, 5_900 - 3_680 - 3_650)
        let none = AskBatch.total(drafts, checked: [], in: ledger, now: now)
        XCTAssertEqual(none.to, none.from)
    }

    func testApprovalCardForReimbursementOffset() {
        let (ledger, bank) = sample()
        let taxi = ledger.entries.first { $0.title == "打车" }!
        let draft = EntryDraft(date: now, amount: 3_650, nature: .refund, accountID: bank.id, title: "报销", category: "交通")
        let change = ChangeSet(source: "问余白", reason: "报销到账", items: [.addEntry(draft), .linkRefund(refund: draft.id, original: taxi.id)])
        let card = AskApproval.make(change, ledger: ledger, now: now)
        XCTAssertEqual(card.title, "把到账的 36.50 冲抵昨天的打车")
        XCTAssertEqual(card.action, "确认冲抵")
        XCTAssertEqual(card.change.to - card.change.from, 3_650)
        XCTAssertTrue(card.change.better)
        XCTAssertEqual(card.facts.map(\.key), ["原账单", "到账", "交通"])
        XCTAssertEqual(card.facts[0].value, "打车 · 11月22日 · -36.50")
        XCTAssertEqual(card.facts[1].value, "招行储蓄 +36.50")
        XCTAssertEqual(card.facts[2].value, "36.50 → 0.00")
        XCTAssertEqual(card.editEntryID, taxi.id)
    }

    func testOfflineAnswersBudgetAndPurchaseFromCode() {
        let (ledger, _) = sample()
        guard case .budget(let budget) = AskLocal.answer("购物这个月还剩多少", in: ledger, daysLeft: 8, now: now) else { return XCTFail("budget") }
        XCTAssertEqual(budget.amount - budget.spent, 18_200)
        XCTAssertEqual(AskLocal.purchasePrice(in: "1299 的耳机能买吗"), 129_900)
        XCTAssertEqual(AskLocal.purchaseTitle("1299 的耳机能买吗"), "耳机")
        XCTAssertEqual(AskLocal.runningLabel("购物这个月还剩多少", in: ledger, now: now), "核对购物预算…")
    }

    func testToneChangesOnlyTheToneLine() {
        let gentle = AskYubai.prompt(now: now)
        let direct = AskYubai.prompt(now: now, tone: .direct)
        XCTAssertEqual(AskYubai.prompt(now: now, tone: .gentle), gentle)
        XCTAssertNotEqual(gentle, direct)
        XCTAssertEqual(direct, gentle + "\n" + AskYubai.directToneInstruction)
        XCTAssertFalse(gentle.contains(AskYubai.directToneInstruction))
    }

    func testWeeklyLetterNextFireUsesStoredTime() {
        // 2026-11-23 is a Monday.
        XCTAssertEqual(WeeklyReviewTime.standard.nextFire(after: now), date("2026-11-29 21:00"))
        XCTAssertEqual(WeeklyReviewTime(weekday: 1, hour: 8, minute: 30).nextFire(after: now), date("2026-11-30 08:30"))
        XCTAssertEqual(WeeklyReviewTime(weekday: 1, hour: 12, minute: 30).nextFire(after: now), date("2026-11-23 12:30"))
        XCTAssertEqual(WeeklyReviewTime.standard.dateComponents.weekday, 1, "Sunday in Foundation numbering")
    }

    func testRouterAppliesNoteSwitchToAssistantRequests() async throws {
        var (ledger, bank) = sample()
        var lunch = Entry(date: now, amount: 4_200, accountID: bank.id, title: "午饭", category: "吃饭")
        lunch.note = "和前同事老王"
        ledger.entries.append(lunch)
        final class Recorder: ChatTransport, @unchecked Sendable {
            var sent: [ChatRequest] = []
            func send(_ request: ChatRequest) async throws -> ChatMessage { sent.append(request); return ChatMessage(role: .assistant, content: "好") }
        }
        var preferences = Preferences()
        preferences.cloudAIEnabled = true
        XCTAssertFalse(preferences.cloudShareSettings.note, "notes stay on the phone by default")
        let recorder = Recorder()
        let router = ModelRouter.configured(preferences: preferences, feature: .answers, ledger: ledger, transport: recorder)
        _ = try await router.send(ChatRequest(messages: [ChatMessage(role: .user, content: "和前同事老王那顿午饭花了多少")]))
        let text = recorder.sent.flatMap(\.messages).compactMap(\.content).joined()
        XCTAssertFalse(text.contains("和前同事老王"))

        preferences.cloudAIEnabled = false
        let off = ModelRouter.configured(preferences: preferences, feature: .answers, ledger: ledger, transport: recorder)
        let availability = await off.availability()
        XCTAssertEqual(availability, .unavailable(.cloudOff))
        XCTAssertEqual(DeepSeekProvider.status(preferences: preferences, feature: .answers, keyConfigured: true), .unavailable(.cloudOff))
        preferences.cloudAIEnabled = true
        XCTAssertEqual(DeepSeekProvider.status(preferences: preferences, feature: .answers, keyConfigured: false), .unavailable(.missingKey))
    }

    func testSearchFilterMatchesTitleCategoryAndAmount() {
        let (ledger, _) = sample()
        XCTAssertEqual(ledger.searchBills("打车", now: now).map(\.title), ["打车"])
        XCTAssertEqual(ledger.searchBills("交通", now: now).map(\.title), ["打车"])
        XCTAssertTrue(ledger.searchBills("机票", now: now).isEmpty)
    }
}
