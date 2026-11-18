import SwiftUI
import YubaiCore

/// Date text shared by the 现在 page: 「11月25日」.
enum NowFormat {
    static func monthDay(_ date: Date) -> String {
        Dates.monthDay(date)
    }
    static func range(_ from: Date, _ to: Date) -> String {
        let a = Dates.calendar.dateComponents([.month, .day], from: from), b = Dates.calendar.dateComponents([.month, .day], from: to)
        let tail = a.month == b.month ? "\(b.day ?? 1)日" : monthDay(to)
        return monthDay(from) + " – " + tail
    }
}

/// 「还有 N 件」：点开是管家的一叠卡。叠在卡片右上角。
struct MoreLink: View {
    let count: Int
    var body: some View {
        TabNavigationLink(.todo) { TodoView() } label: {
            HStack(spacing: YubaiSpace.space4) {
                Text("还有 \(count) 件")
                Image(systemName: "chevron.right").accessibilityHidden(true)
            }.yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.brandInk).yubaiHitTarget(alignment: .trailing)
        }.buttonStyle(PressButtonStyle()).accessibilityIdentifier("openLetterInbox")
    }
}

/// 首页卡片上的「付了」和列表里的勾走同一条路（`BillPayFlow`）。
@MainActor enum BillActions {
    static func pay(_ bill: Occurrence, store: AppStore) {
        if let planID = bill.planID { BillPayFlow.pay(planID: planID, occurrence: Dates.day(bill.date), store: store) }
        else if bill.rentID != nil { _ = store.update("已记下 1 笔") { try HomeButler.confirmRent(bill, in: &$0, now: Dates.now) } }
    }
}

/// 发工资那天：「工资 8,010.00 到了吗?」
struct PaydayCard: View {
    @Environment(AppStore.self) private var store
    let due: Payday.Due
    var more = 0
    var body: some View {
        if let copy = HomeTaskCopy.make(.payday(due), now: store.financialNow, hidden: store.preferences.hideAmounts) {
            QuestionCard(eyebrow: copy.kicker, title: copy.title, more: more,
                         yesTitle: "到了", noTitle: "还没", yesIdentifier: "paydayArrived", noIdentifier: "paydayNotYet",
                         yes: { store.sheetSource = nil; store.sheet = .paydayAmount },
                         no: { store.answerHome(.payday(due)) })
                .accessibilityIdentifier("paydayCard")
        }
    }
}

/// 账单到期：一个问题两个答案。过了三天还没付，标题换成「晚了 3 天」。
struct BillDueCard: View {
    @Environment(AppStore.self) private var store
    let bill: Occurrence
    var more = 0
    var body: some View {
        if let copy = HomeTaskCopy.make(.bill(bill), now: store.financialNow, hidden: store.preferences.hideAmounts) {
            QuestionCard(eyebrow: copy.kicker, title: copy.title, more: more,
                         yesTitle: bill.inflow ? "到了" : "付了", noTitle: "还没",
                         yesIdentifier: "billDuePaid", noIdentifier: "billDueNotYet",
                         yes: { BillActions.pay(bill, store: store) },
                         no: { store.answerHome(.bill(bill)) })
                .accessibilityIdentifier("dueBills")
        }
    }
}

/// 新周期开始：存下多少，还剩多少，剩的钱问一次。
struct NewCycleCard: View {
    @Environment(AppStore.self) private var store
    let saving: CycleSaving
    var more = 0
    var body: some View {
        let copy = HomeTaskCopy.make(.leftover(saving), now: store.financialNow, hidden: store.preferences.hideAmounts)!
        QuestionCard(eyebrow: copy.kicker, title: copy.title, more: more, titleIdentifier: "carryNoticeText",
                     yesTitle: "留这月花", noTitle: "", yesIdentifier: "leftoverKeep",
                     yes: {
            var undo = store.current
            HomeButler.answer(HomeTask.leftover(saving).id, in: &undo, now: store.financialNow)
            _ = store.update("上期留下", undoSnapshot: undo, entryMotion: false) { try Savings.keepLeftover(cycleStart: saving.cycleStart, in: &$0, now: store.financialNow) }
        }, no: {}, onDismiss: { store.answerHome(.leftover(saving)) }, dismissIdentifier: "leftoverDismiss").accessibilityIdentifier("newCycleCard")
    }
}

/// 几天没记：先补记那几天的开销，记不清再对余额。
struct GapCard: View {
    @Environment(AppStore.self) private var store
    let gap: Reconciliation.Gap
    var more = 0
    var body: some View {
        QuestionCard(eyebrow: "上次记账 · " + NowFormat.monthDay(gap.lastRecorded), title: "\(gap.days) 天没记了", more: more,
                     yesTitle: "补记一笔", noTitle: "对一下余额", yesIdentifier: "addEntryFromGap", noIdentifier: "openReconcile",
                     yes: { store.requestCaptureSheet(.prefilledEntry(QuickEntryPrefill(category: nil, amount: nil, purpose: nil,
                                                                                        date: Dates.addDays(1, to: gap.lastRecorded)))) },
                     no: { store.sheetSource = nil; store.sheet = .reconcileAll })
            .accessibilityIdentifier("gapCard")
    }
}

/// 周期超了：这个月少存一点 / 从存着的钱出。
struct OverspendRows: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dynamicTypeSize) private var textSize
    let options: Overspend.Options
    var more = 0
    var body: some View {
        let value = store.formula
        let bill = value.rows.first { $0.kind == .bills }?.occurrences.first
        let kicker = bill.map { "还要付 · " + $0.title + " " + NowFormat.monthDay($0.date) } ?? "还要付"
        let amount = min(options.overBy, max(0, store.reserve.total))
        let title = "要付的账单差 " + amount2(options.overBy, hide: store.preferences.hideAmounts)
        if amount > 0 {
            QuestionCard(eyebrow: kicker, title: title, more: more, titleIdentifier: "deficitRescueText",
                         yesTitle: "拿出来用 " + (store.preferences.hideAmounts ? "¥••••" : Money.text(amount)), noTitle: "先不动",
                         yesIdentifier: "coverFromReserve", noIdentifier: "deficitKeep", yes: {
                _ = store.update("拿出来用", entryMotion: false) { try HomeButler.rescueDeficit(in: &$0, now: store.financialNow) }
            }, no: { store.answerHome(.overspend(options)) }).accessibilityIdentifier("deficitRescueCard")
        } else {
            // Nothing saved to draw from: no dead「拿出来用 ¥0.00」button.
            QuestionCard(eyebrow: kicker, title: title, more: more, titleIdentifier: "deficitRescueText",
                         yesTitle: "先不动", noTitle: "", yesIdentifier: "deficitKeep",
                         yes: { store.answerHome(.overspend(options)) }, no: {}).accessibilityIdentifier("deficitRescueCard")
        }
    }
}

/// 导入的账单正在整理：一条进度，不挡操作。
struct ImportBusyRow: View {
    @Environment(AppStore.self) private var store
    let pending: PendingImportOrganization
    private var title: String {
        guard let date = pending.dates.first else { return "正在整理账单" }
        return "正在整理 \(Dates.calendar.component(.month, from: date))月账单"
    }
    var body: some View {
        let progress = store.organizationProgress
        Card(style: .compact) {
            HStack(spacing: YubaiSpace.gapGroup) {
                AssistantMark(size: YubaiFont.navTitle.size, color: YubaiColor.brandInk).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: YubaiSpace.space4) {
                    Text(title).yubaiFont(YubaiFont.row)
                    if let progress, progress.total > 0 {
                        ProgressLine(value: Double(progress.completed) / Double(progress.total), tint: YubaiColor.brand, track: YubaiColor.card, height: YubaiSpace.space4)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                if let progress { Text(progress.countText).yubaiFont(YubaiFont.amountSmall).accessibilityIdentifier("organizeProgress") }
                else { ProgressView() }
            }.frame(minHeight: YubaiSize.rowIcon)
        }.accessibilityElement(children: .contain).accessibilityIdentifier("importBusyRow")
    }
}
