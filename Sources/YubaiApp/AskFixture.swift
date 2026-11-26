import Foundation
import YubaiCore

/// Canvas data for the 问余白 boards (`Ask.dc.html`). Debug launch arguments only.
/// The ledger is the home `normal` board, so every number is computed from it.
enum AskFixture: String {
    case nobuy, verdicts, approve, batch, offline
    /// Sheet closed, AI on, empty thread: UI tests ask through the script transport.
    case live

    static let current: Self? = {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-YubaiAskFixture"), args.indices.contains(index + 1) else { return nil }
        return Self(rawValue: args[index + 1])
        #else
        return nil
        #endif
    }()

    var aiConnected: Bool { self != .offline }
    var opensSheet: Bool { self != .live }

    // canvas Ask.dc.html: shotLines
    static let screenshotLines: [CGFloat] = [40, 52, 34, 46, 38, 50]

    #if DEBUG
    @MainActor func seed(_ ledger: inout Ledger, now: Date) -> [AskMessage] {
        ledger.preferences.cloudAIEnabled = aiConnected
        // 值不值 · 3 条: the 90-day habit line, one stored 消费观 note and one principle.
        ledger.profile.restrain = [ProfileArea(title: "数码", match: AreaMatch(categories: ["购物"]), note: "耳机能用就不换", confirmedAt: Dates.parse("2025-10-12"))]
        ledger.profile.principles = ["大件先放心愿单冷静三天"]
        let bank = ledger.accounts[0]
        func judgment(_ title: String, _ amount: Int64, _ category: String) -> PurchaseJudgment {
            PurchaseJudgment(title: title, amount: amount, category: category, hasProfile: true, facts: .object([:]))
        }
        func reply(_ judgment: PurchaseJudgment, _ verdict: PurchaseVerdict, _ reason: String, questions: [PurchaseQuestion]? = nil) -> AssistantReply {
            var value = AssistantReply(proposedChangeSets: [], text: reason)
            value.purchaseJudgment = judgment
            value.purchaseVerdict = SubmittedPurchaseVerdict(verdict: verdict, reason: reason, need: .want, boundReason: "")
            value.purchaseQuestions = questions
            return value
        }
        func user(_ text: String, lines: [CGFloat] = []) -> AskMessage { AskMessage(kind: .user(text, image: nil, placeholder: lines)) }
        func answer(_ value: AssistantReply, _ question: String) -> AskMessage { AskMessage(kind: .reply(value, question: question, image: nil)) }
        let day = { (value: Int, time: String) in Dates.parse(String(format: "2025-11-%02d %@", value, time))! }

        switch self {
        case .nobuy:
            return [user("想买个 1,299 的降噪耳机"),
                    answer(reply(judgment("降噪耳机", 129_900, "购物"), .skip, "购物只剩 182.00，买了要从机动余钱补 1,117.00",
                                 questions: [PurchaseQuestion(text: "现在这副哪里不满意？", options: ["降噪不够", "坏了", "就是想要"])]), "想买个 1,299 的降噪耳机")]
        case .verdicts:
            return [user("冬天的羽绒被 899 呢"),
                    answer(reply(judgment("羽绒被", 89_900, "购物"), .wait, "12.10 起购物有 1,500.00，现在的被子还能撑 17 天"), "冬天的羽绒被 899 呢"),
                    user("周末和朋友吃火锅 188"),
                    answer(reply(judgment("周末和朋友吃火锅", 18_800, "吃饭"), .buy, "这月外出聚餐 2 次，低于你平时的 4 次"), "周末和朋友吃火锅 188")]
        case .approve:
            guard let taxi = ledger.entries.first(where: { $0.title == "打车" && $0.pendingRecovery == .reimbursement }) else { return [] }
            let refund = EntryDraft(date: now, amount: taxi.amount, nature: .refund, accountID: bank.id, title: "报销", category: taxi.category)
            let change = ChangeSet(source: "问余白", reason: "报销到账", items: [.addEntry(refund), .linkRefund(refund: refund.id, original: taxi.id)])
            ledger.pendingChanges.append(change)
            return [user("昨天打车那 36.5 报销到账了"), answer(AssistantReply(proposedChangeSets: [change], text: ""), "昨天打车那 36.5 报销到账了")]
        case .batch:
            var refund = EntryDraft(date: day(22, "15:00"), amount: 5_900, nature: .income, accountID: bank.id, title: "优衣库", category: "购物")
            refund.purpose = "退款"
            let drafts = [EntryDraft(date: day(23, "12:10"), amount: 3_680, accountID: bank.id, title: "美团外卖", category: "吃饭"),
                          EntryDraft(date: day(22, "18:00"), amount: 3_650, accountID: bank.id, title: "滴滴", category: "交通"),
                          EntryDraft(date: day(22, "21:00"), amount: 1_200, accountID: bank.id, title: "便利店", category: "吃饭"),
                          refund]
            let change = ChangeSet(source: "问余白", reason: "截图记账", items: drafts.map { .addEntry($0) })
            ledger.pendingChanges.append(change)
            return [user("这几笔帮我记一下", lines: Self.screenshotLines), answer(AssistantReply(proposedChangeSets: [change], text: ""), "这几笔帮我记一下")]
        case .offline:
            let days = HomeDisplay.daysLeft(Finance.spendableBreakdown(ledger, now: now))
            return [user("购物这个月还剩多少"),
                    AskMessage(kind: .local(AskLocal.answer("购物这个月还剩多少", in: ledger, daysLeft: days, now: now), needsAI: false)),
                    user("1299 的耳机能买吗"),
                    AskMessage(kind: .local(AskLocal.answer("1299 的耳机能买吗", in: ledger, daysLeft: days, now: now), needsAI: true))]
        case .live:
            return []
        }
    }
    #endif
}
