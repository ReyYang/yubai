import SwiftUI
import YubaiCore

/// Date text shared by the 现在 page: 「11月25日」.
enum NowFormat {
    static func monthDay(_ date: Date) -> String {
        let parts = Dates.calendar.dateComponents([.month, .day], from: date)
        return "\(parts.month ?? 1)月\(parts.day ?? 1)日"
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
        else if bill.rentID != nil { _ = store.update("已记下 1 笔") { try HomeButler.confirmRent(bill, in: &$0, now: Date()) } }
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
        QuestionCard(eyebrow: "上个周期结束了", title: "剩下 " + amount2(saving.unspent ?? 0, hide: store.preferences.hideAmounts) + "，存起来吗", more: more,
                     yesTitle: "存起来", noTitle: "留着花", yesIdentifier: "leftoverSave", noIdentifier: "leftoverKeep",
                     yes: { resolve(.save) }, no: { resolve(.keep) }).accessibilityIdentifier("newCycleCard")
    }
    private func resolve(_ choice: LeftoverChoice) {
        _ = store.update("剩下的钱", showToast: false) { try Savings.resolveLeftover(cycleStart: saving.cycleStart, choice: choice, in: &$0) }
    }
}

/// 几天没记：对一下余额最省事。
struct GapCard: View {
    @Environment(AppStore.self) private var store
    let gap: Reconciliation.Gap
    var more = 0
    var body: some View {
        QuestionCard(eyebrow: "上次记账 · " + NowFormat.monthDay(gap.lastRecorded), title: "\(gap.days) 天没记了", more: more,
                     yesTitle: "对一下余额", noTitle: "导入账单", yesIdentifier: "openReconcile", noIdentifier: "importFromGap",
                     yes: { store.sheetSource = nil; store.sheet = .reconcileAll },
                     no: { store.sheetSource = nil; store.sheet = .imports })
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
        let funds = store.funds
        Card(style: .list) {
            VStack(spacing: YubaiSpace.none) {
                if more > 0 { HStack { Spacer(); MoreLink(count: more) } }
                row("这个月少存一点", before: funds.savingTarget, amount: min(options.overBy, options.maxSaveLess),
                    enabled: options.maxSaveLess > 0, source: .saveLess, identifier: "coverSaveLess")
                Rectangle().fill(YubaiColor.separator).frame(height: YubaiSize.separator)
                row("从存着的钱出", before: funds.fixedSavingsTotal, amount: min(options.overBy, options.maxFromReserve),
                    enabled: options.maxFromReserve > 0, source: .fromReserve, identifier: "coverFromReserve")
            }
        }
    }
    private func row(_ title: String, before: Int64, amount: Int64, enabled: Bool, source: CycleCover.Source, identifier: String) -> some View {
        let hide = store.preferences.hideAmounts
        let change = ResultBar.change(before, max(0, before - amount), hide: hide)
        let layout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: YubaiSpace.space4)) : AnyLayout(HStackLayout(spacing: YubaiSpace.gapGroup))
        return Button { store.sheetSource = nil; store.sheet = .overspend(source) } label: {
            layout {
                Text(title).yubaiFont(YubaiFont.rowTitle, weight: .semibold)
                if !textSize.isAccessibilitySize { Spacer(minLength: YubaiSpace.space8) }
                Text(change).yubaiFont(YubaiFont.amountSmall).foregroundStyle(YubaiColor.labelSecondary).fixedSize(horizontal: false, vertical: true)
                Image(systemName: "chevron.right").yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary).accessibilityHidden(true)
            }.frame(maxWidth: .infinity, minHeight: YubaiSize.buttonHeight, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(PressButtonStyle()).disabled(!enabled).opacity(enabled ? 1 : 0.5)
            .accessibilityIdentifier(identifier).accessibilityLabel(title + "，" + change)
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
