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

/// 「还有 N 件」：点开是待处理列表。叠在卡片右上角。
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

private extension View {
    func moreOverlay(_ count: Int) -> some View {
        overlay(alignment: .topTrailing) {
            if count > 0 { MoreLink(count: count).padding(.top, 2).padding(.trailing, YubaiSpace.insetCard) }
        }
    }
}

/// 首页卡片上的「付了」和列表里的勾走同一条路（`BillPayFlow`）。
@MainActor enum BillActions {
    static func pay(_ bill: Occurrence, store: AppStore) {
        guard let planID = bill.planID else { return }
        BillPayFlow.pay(planID: planID, occurrence: Dates.day(bill.date), store: store)
    }
}

/// 发工资那天：「工资 8,010.00 到了吗?」
struct PaydayCard: View {
    @Environment(AppStore.self) private var store
    let due: Payday.Due
    var more = 0
    var body: some View {
        QuestionCard(eyebrow: "固定进账 · " + NowFormat.monthDay(due.occurrence), title: due.title, amount: due.usual, question: "到了吗?",
                     yesTitle: "到了", noTitle: "还没", yesIdentifier: "paydayArrived", noIdentifier: "paydayNotYet",
                     yes: { store.sheetSource = nil; store.sheet = .paydayAmount },
                     no: { store.snooze("payday-" + Dates.text(due.occurrence)) })
            .moreOverlay(more).accessibilityIdentifier("paydayCard")
    }
}

/// 账单到期：一个问题两个答案。过了三天还没付，标题换成「晚了 3 天」。
struct BillDueCard: View {
    @Environment(AppStore.self) private var store
    let bill: Occurrence
    var inTodo = false
    var more = 0
    private var lateDays: Int { max(0, Dates.calendar.dateComponents([.day], from: Dates.day(bill.date), to: Dates.day(Date())).day ?? 0) }
    private var eyebrow: String {
        (bill.inflow ? "固定进账 · " : "固定账单 · ") + (lateDays > 0 ? "晚了 \(lateDays) 天" : "今天到期")
    }
    var body: some View {
        if bill.planID != nil { planCard } else { rentCard }
    }
    private var planCard: some View {
        QuestionCard(eyebrow: eyebrow, title: bill.title, amount: bill.amount, question: inTodo ? "" : (bill.inflow ? "到了吗?" : "付了吗?"), amber: lateDays >= 3,
                     yesTitle: bill.inflow ? "到了" : (inTodo ? "付过了" : "付了"), noTitle: inTodo && !bill.inflow ? "还没付" : "还没",
                     yesIdentifier: "billDuePaid", noIdentifier: "billDueNotYet",
                     yes: { BillActions.pay(bill, store: store) },
                     no: { store.snooze("bill-" + bill.id) })
            .moreOverlay(more).accessibilityIdentifier("dueBills")
    }
    private var rentCard: some View {
        Card(style: .compact) {
            VStack(alignment: .leading, spacing: YubaiSpace.space8) {
                Text(eyebrow).yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary).padding(.trailing, 28)
                Text(bill.title + " " + amount2(bill.amount, hide: store.preferences.hideAmounts)).yubaiFont(YubaiFont.rowTitle, weight: .semibold)
                TabNavigationLink(.fixedFlows) { FixedFlowsView() } label: { Text("会回来的账单") }
                    .buttonStyle(NowCardButtonStyle(primary: true))
            }
        }.moreOverlay(more).accessibilityIdentifier("dueBills")
    }
}

/// 新周期开始：存下多少，还剩多少，剩的钱问一次。
struct NewCycleCard: View {
    @Environment(AppStore.self) private var store
    let saving: CycleSaving
    var more = 0
    private var summary: Text {
        let hide = store.preferences.hideAmounts
        return Text("存下 ") + Text(amount2(saving.saved, hide: hide)).foregroundStyle(YubaiColor.brandInk)
            + Text("，还剩 ") + Text(amount2(saving.unspent ?? 0, hide: hide)) + Text("。")
    }
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: YubaiSpace.space8) {
                Text("上个周期 · " + NowFormat.range(saving.cycleStart, saving.cycleEnd)).yubaiFont(YubaiFont.caption)
                    .foregroundStyle(YubaiColor.labelSecondary).padding(.trailing, more > 0 ? 72 : 0)
                summary.yubaiFont(YubaiFont.quote).fixedSize(horizontal: false, vertical: true)
                answers.padding(.top, YubaiSpace.space4)
            }
        }.moreOverlay(more).accessibilityElement(children: .contain).accessibilityIdentifier("newCycleCard")
    }
    private var answers: some View {
        ChipFlow {
            Button("剩的也存起来") { resolve(.save) }.buttonStyle(NowCardButtonStyle(primary: true)).accessibilityIdentifier("leftoverSave")
            Button("留着这个月花") { resolve(.keep) }.buttonStyle(NowCardButtonStyle()).accessibilityIdentifier("leftoverKeep")
        }
    }
    private func resolve(_ choice: LeftoverChoice) {
        _ = store.update("剩的钱", showToast: false) { try Savings.resolveLeftover(cycleStart: saving.cycleStart, choice: choice, in: &$0) }
    }
}

/// 几天没记：对一下余额最省事。
struct GapCard: View {
    @Environment(AppStore.self) private var store
    let gap: Reconciliation.Gap
    var more = 0
    var body: some View {
        QuestionCard(eyebrow: "上次记账 · " + NowFormat.monthDay(gap.lastRecorded), title: "\(gap.days) 天没记了",
                     yesTitle: "对一下余额", noTitle: "导入账单", yesIdentifier: "openReconcile", noIdentifier: "importFromGap",
                     yes: { store.sheetSource = nil; store.sheet = .reconcileAll },
                     no: { store.sheetSource = nil; store.sheet = .imports })
            .moreOverlay(more).accessibilityIdentifier("gapCard")
    }
}

/// 周期超了：这个月少存一点 / 从存着的钱出。
struct OverspendRows: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dynamicTypeSize) private var textSize
    let options: Overspend.Options
    var body: some View {
        let funds = store.funds
        Card(style: .list) {
            VStack(spacing: 0) {
                row("这个月少存一点", before: funds.savingTarget, amount: min(options.overBy, options.maxSaveLess),
                    enabled: options.maxSaveLess > 0, source: .saveLess, identifier: "coverSaveLess")
                Rectangle().fill(YubaiColor.separator).frame(height: 1)
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
            .accessibilityElement(children: .ignore).accessibilityLabel(title + "，" + change).accessibilityAddTraits(.isButton)
            .accessibilityIdentifier(identifier)
    }
}

/// 花快了：这个周末花了多少，点过去看是哪几笔。
struct FastRow: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dynamicTypeSize) private var textSize
    let burst: PaceBurst
    private var title: String {
        switch burst.kind {
        case .weekend: "这个周末花了"
        case .lastDays: "这三天花了"
        }
    }
    var body: some View {
        let amount = amount2(burst.amount, hide: store.preferences.hideAmounts)
        let layout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: YubaiSpace.space4)) : AnyLayout(HStackLayout(spacing: YubaiSpace.gapGroup))
        Button {
            store.ledgerPreset = LedgerPreset(mode: .detail, interval: burst.interval)
            store.destination = .ledger
        } label: {
            layout {
                HStack(spacing: YubaiSpace.space4) {
                    Text(title).foregroundStyle(YubaiColor.amberInk)
                    Text(amount).yubaiFont(YubaiFont.amount).foregroundStyle(YubaiColor.amberStrong)
                }.yubaiFont(YubaiFont.row)
                if !textSize.isAccessibilitySize { Spacer(minLength: YubaiSpace.space8) }
                HStack(spacing: YubaiSpace.space4) {
                    Text("看花在哪")
                    Image(systemName: "chevron.right").accessibilityHidden(true)
                }.yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.amberInk)
            }.padding(.horizontal, YubaiSpace.insetCard).padding(.vertical, YubaiSpace.space8)
                .frame(maxWidth: .infinity, minHeight: YubaiSize.buttonHeight, alignment: .leading)
                .background(YubaiColor.amberTint, in: RoundedRectangle(cornerRadius: YubaiRadius.row)).contentShape(Rectangle())
        }.buttonStyle(PressButtonStyle()).accessibilityElement(children: .ignore)
            .accessibilityLabel(title + amount + "，看花在哪").accessibilityAddTraits(.isButton).accessibilityIdentifier("fastRow")
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
                AssistantMark(size: 16, color: YubaiColor.brandInk).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: YubaiSpace.space4) {
                    Text(title).yubaiFont(YubaiFont.row)
                    if let progress, progress.total > 0 {
                        ProgressLine(value: Double(progress.completed) / Double(progress.total), tint: YubaiColor.brand, track: YubaiColor.card, height: 4)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                if let progress { Text(progress.countText).yubaiFont(YubaiFont.amountSmall).accessibilityIdentifier("organizeProgress") }
                else { ProgressView() }
            }.frame(minHeight: YubaiSize.rowIcon)
        }.accessibilityElement(children: .contain).accessibilityIdentifier("importBusyRow")
    }
}

/// 整理完：「4 笔要你看一眼」。
struct ImportLookCard: View {
    @Environment(AppStore.self) private var store
    let pending: PendingImportOrganization
    var more = 0
    private var eyebrow: String {
        "没分类 · " + (pending.dates.first.map { "\(Dates.calendar.component(.month, from: $0))月导入" } ?? "")
    }
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: YubaiSpace.space8) {
                Text(eyebrow).yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary).padding(.trailing, more > 0 ? 72 : 0)
                Text("\(pending.count) 笔要你看一眼").yubaiFont(YubaiFont.rowTitle, weight: .semibold)
                ChipFlow {
                    TabNavigationLink(.triage(pending.entryIDs)) { LetterTriageView(entryIDs: pending.entryIDs) } label: { Text("一笔笔过") }
                        .buttonStyle(NowCardButtonStyle(primary: true)).accessibilityIdentifier("classifyImportsManually")
                    Button("交给余白") {
                        if store.organizationAIReady { store.startOrganizingPendingImports() } else { store.sheet = .intelligencePrivacy }
                    }.buttonStyle(NowCardButtonStyle()).accessibilityIdentifier("organizeImports")
                }.padding(.top, YubaiSpace.space4)
            }
        }.moreOverlay(more).accessibilityElement(children: .contain).accessibilityIdentifier("pendingImportsCard")
    }
}

/// 刚装好：让这个数更准，1 / 4。
struct SetupCard: View {
    @Environment(AppStore.self) private var store
    let done: Set<Setup.Item>
    private var titles: [(Setup.Item, String)] {
        [(.hand, "手上的钱"), (.payday, "哪天发工资"), (.saving, "每月想存多少"), (.bills, "每月固定要付的")]
    }
    var body: some View {
        VStack(alignment: .leading, spacing: YubaiSpace.space8) {
            HStack(alignment: .firstTextBaseline) {
                Text("让这个数更准").yubaiFont(YubaiFont.callout, weight: .semibold)
                Spacer(minLength: YubaiSpace.space8)
                Text("\(done.count) / \(titles.count)").yubaiFont(YubaiFont.callout)
            }.foregroundStyle(YubaiColor.labelSecondary).padding(.horizontal, YubaiSpace.space4)
            Card(style: .list) {
                VStack(spacing: 0) {
                    ForEach(Array(titles.enumerated()), id: \.offset) { index, item in
                        row(item.0, item.1)
                        if index < titles.count - 1 { Rectangle().fill(YubaiColor.separator).frame(height: 1).padding(.leading, YubaiSize.rowIcon + YubaiSpace.gapGroup) }
                    }
                }
            }
            Button { store.sheetSource = nil; store.sheet = .imports } label: {
                Text("导入账单").yubaiFont(YubaiFont.button).frame(maxWidth: .infinity, minHeight: YubaiSize.buttonHeight)
                    .foregroundStyle(YubaiColor.label).paperCardSurface(in: RoundedRectangle(cornerRadius: YubaiRadius.card))
            }.buttonStyle(PressButtonStyle()).padding(.top, YubaiSpace.gapGroup).accessibilityIdentifier("setupImport")
        }
    }
    @ViewBuilder private func row(_ item: Setup.Item, _ title: String) -> some View {
        let finished = done.contains(item)
        if finished { content(item, title, finished: true).accessibilityIdentifier("setupItem_" + item.rawValue) }
        else {
            Button { act(item) } label: { content(item, title, finished: false) }.buttonStyle(PressButtonStyle())
                .accessibilityIdentifier("setupItem_" + item.rawValue)
        }
    }
    private func content(_ item: Setup.Item, _ title: String, finished: Bool) -> some View {
        HStack(spacing: YubaiSpace.gapGroup) {
            Image(systemName: finished ? "checkmark.circle.fill" : "circle").font(.system(size: 24))
                .foregroundStyle(finished ? YubaiColor.brand : YubaiColor.borderDashed).accessibilityHidden(true)
            Text(title).yubaiFont(YubaiFont.rowTitle, weight: finished ? .regular : .semibold)
                .foregroundStyle(finished ? YubaiColor.labelSecondary : YubaiColor.label)
            Spacer(minLength: YubaiSpace.space8)
            if finished {
                if item == .hand { AmountLabel(cents: store.funds.cash, hide: store.preferences.hideAmounts, role: .amount) }
            } else {
                Image(systemName: "chevron.right").yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary).accessibilityHidden(true)
            }
        }.frame(maxWidth: .infinity, minHeight: YubaiSize.buttonHeight, alignment: .leading).contentShape(Rectangle())
            .accessibilityElement(children: .combine).accessibilityValue(finished ? "已完成" : "")
    }
    private func act(_ item: Setup.Item) {
        store.sheetSource = nil
        switch item {
        case .hand: store.sheet = .account(nil)
        case .payday: store.sheet = .addPlan
        case .saving: store.sheet = .formulaEdit(.saving)
        case .bills: store.sheet = .addBill
        }
    }
}
