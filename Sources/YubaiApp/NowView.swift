import SwiftUI
import YubaiCore

/// 现在：一个大数、一行日均、一张图，需要你动手的只展开最急的一张卡。
struct NowView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dynamicTypeSize) private var textSize

    private var hide: Bool { store.preferences.hideAmounts }

    var body: some View {
        ScrollView {
            content
                .padding(.horizontal, YubaiSpace.insetPage).padding(.top, YubaiSpace.space8).padding(.bottom, YubaiSpace.gapSection)
                .frame(maxWidth: 1080).frame(maxWidth: .infinity, alignment: .leading)
        }.yubaiFont(YubaiFont.body).foregroundStyle(YubaiColor.label)
            .rootScrollContentMargins().rootTabScroll(.now)
            .rootPageHeader { RootHeader(title: "现在") }
            .navigationTitle("现在").yubaiNavigation()
            .amountPrivacy(hide).accessibilityIdentifier("nowScroll")
            #if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
            #endif
    }

    // MARK: Page

    @ViewBuilder private var content: some View {
        if store.accounts.isEmpty {
            EmptyAccountState { store.sheetSource = nil; store.sheet = .account(nil) }
        } else {
            populated
        }
    }

    private var populated: some View {
        let items = store.inboxItems
        let pace = store.pace
        return VStack(alignment: .leading, spacing: YubaiSpace.none) {
            hero(pace)
            slot(items)
            if let pace, pace.lateDays == nil { chart(pace) }
            if let burst = pace?.burst, pace?.isFast == true, pace?.overBy == 0 { FastRow(burst: burst).padding(.top, YubaiSpace.gapGroup) }
            if let options = store.overspend { OverspendRows(options: options).padding(.top, YubaiSpace.gapGroup) }
            if showsSetup(pace) { SetupCard(done: store.setupDone).padding(.top, YubaiSpace.gapSection) }
            upcoming(items)
            recent
        }
    }

    // MARK: Hero

    private func horizonText(_ pace: CyclePace?) -> String {
        guard let pace else { return "手上所有的钱" }
        if let late = pace.lateDays { return late == 0 ? "今天发工资" : "工资晚了 \(late) 天" }
        let days = "还有 \(pace.daysLeft) 天"
        if textSize.isAccessibilitySize || !store.funds.cycleIsPayday { return days }
        return NowFormat.monthDay(Dates.addDays(1, to: pace.end)) + "发工资 · " + days
    }

    private func hero(_ pace: CyclePace?) -> some View {
        let funds = store.funds
        let over = (pace?.overBy ?? 0) > 0
        let headline = over ? "多花了" : "还能花"
        let value = over ? (pace?.overBy ?? 0) : funds.available
        let horizon = horizonText(pace)
        let spoken = headline + "，" + horizon + "，" + (hide ? "金额已隐藏" : amount2(value, hide: false))
        return VStack(alignment: .leading, spacing: YubaiSpace.space2) {
            TabNavigationLink(.formula) { FormulaView() } label: {
                VStack(alignment: .leading, spacing: YubaiSpace.space2) {
                    heroTitle(headline, horizon)
                    HStack(alignment: .firstTextBaseline, spacing: YubaiSpace.space8) {
                        AmountLabel(cents: value, hide: hide, role: .hero, ink: over ? YubaiColor.amberInk : YubaiColor.label)
                            .accessibilityIdentifier("availableFunds")
                        Image(systemName: "chevron.right").yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(PressButtonStyle()).yubaiZoomSource("funds").accessibilityIdentifier("fundsFormula")
                .accessibilityLabel(spoken).accessibilityHint("点开看怎么算")
            if let daily = pace?.daily { dailyRow(daily) }
        }
    }

    private func heroTitle(_ headline: String, _ horizon: String) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: YubaiSpace.space8) {
                Text(headline).yubaiFont(YubaiFont.heroLabel).fixedSize()
                Text(horizon).yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary).fixedSize()
            }
            VStack(alignment: .leading, spacing: YubaiSpace.space2) {
                Text(headline).yubaiFont(YubaiFont.heroLabel)
                Text(horizon).yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary)
            }
        }
    }

    private func dailyRow(_ daily: Int64) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: YubaiSpace.space8) {
            Text("日均").yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary)
            AmountLabel(cents: daily, hide: hide, role: .summary, currency: false)
        }.accessibilityElement(children: .combine)
            .accessibilityLabel("日均 " + (hide ? "金额已隐藏" : amount2(daily, hide: false))).accessibilityIdentifier("dailyPace")
    }

    // MARK: Card slot

    @ViewBuilder private func slot(_ items: [LetterItem]) -> some View {
        if let first = items.first, first.takesHomeSlot {
            card(for: first, more: items.count - 1).padding(.top, YubaiSpace.gapGroup + YubaiSpace.space2)
        } else if !items.isEmpty {
            todoLink(count: items.count).padding(.top, YubaiSpace.gapGroup + YubaiSpace.space2)
        }
    }

    @ViewBuilder private func card(for item: LetterItem, more: Int) -> some View {
        switch item {
        case .payday(let due): PaydayCard(due: due, more: more)
        case .bill(let bill): BillDueCard(bill: bill, more: more)
        case .leftover(let saving): NewCycleCard(saving: saving, more: more)
        case .gap(let gap): GapCard(gap: gap, more: more)
        case .imports(let pending):
            if store.organizingPendingImports || store.organizingBatchID != nil { ImportBusyRow(pending: pending) }
            else { ImportLookCard(pending: pending, more: more) }
        case .salary, .butler: EmptyView()
        }
    }

    private func todoLink(count: Int) -> some View {
        TabNavigationLink(.todo) { TodoView() } label: {
            Card(style: .compact) {
                HStack(spacing: YubaiSpace.gapGroup) {
                    Text("待处理").yubaiFont(YubaiFont.rowTitle, weight: .semibold)
                    Spacer(minLength: YubaiSpace.space8)
                    Text("\(count) 件").yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary)
                    Image(systemName: "chevron.right").yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary).accessibilityHidden(true)
                }.frame(minHeight: YubaiSize.rowIcon)
            }
        }.buttonStyle(PressButtonStyle()).accessibilityIdentifier("openLetterInbox")
    }

    // MARK: Chart

    private func chart(_ pace: CyclePace) -> some View {
        PaceChart(pace: pace, hide: hide).padding(.top, YubaiSpace.gapGroup + YubaiSpace.space2)
    }

    private func showsSetup(_ pace: CyclePace?) -> Bool {
        let done = store.setupDone
        if pace == nil { return true }
        return done.count < Setup.Item.allCases.count && store.sortedEntries.count < 20
    }

    // MARK: 接下来 7 天

    private func upcomingRows(_ items: [LetterItem]) -> [Occurrence] {
        let limit = Dates.addDays(7, to: Dates.day(Date()))
        let due = store.paydayDue
        let carded: String? = {
            guard let first = items.first else { return nil }
            if case .bill(let bill) = first { return bill.id }
            return nil
        }()
        return store.funds.occurrences.filter { occurrence in
            guard Dates.day(occurrence.date) <= limit, occurrence.id != carded else { return false }
            if occurrence.inflow, occurrence.planID != nil, occurrence.planID == due?.planID { return false }
            return true
        }
    }

    @ViewBuilder private func upcoming(_ items: [LetterItem]) -> some View {
        let rows = upcomingRows(items)
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: YubaiSpace.space8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("接下来 7 天").yubaiFont(YubaiFont.callout, weight: .semibold).foregroundStyle(YubaiColor.labelSecondary)
                    Spacer(minLength: YubaiSpace.gapGroup)
                    TabNavigationLink(.fixedFlows) { FixedFlowsView() } label: {
                        HStack(spacing: YubaiSpace.space2) {
                            Text("全部")
                            Image(systemName: "chevron.right").accessibilityHidden(true)
                        }.yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.brandInk).yubaiHitTarget(alignment: .trailing)
                    }.buttonStyle(PressButtonStyle()).accessibilityIdentifier("openFixedFlows")
                }.padding(.horizontal, YubaiSpace.space4)
                Card(style: .list) {
                    VStack(spacing: YubaiSpace.none) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                            NowUpcomingRow(row: row)
                            if index < rows.count - 1 { Rectangle().fill(YubaiColor.separator).frame(height: 1) }
                        }
                    }
                }
            }.padding(.top, YubaiSpace.gapSection - YubaiSpace.space2)
        }
    }

    // MARK: 今天 / 昨天

    private var recent: some View {
        NowRecentEntries().padding(.top, YubaiSpace.gapSection - YubaiSpace.space2)
    }
}

/// 接下来 7 天里的一行：日期、名字、金额、右边的勾。
private struct NowUpcomingRow: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dynamicTypeSize) private var textSize
    let row: Occurrence
    private var hide: Bool { store.preferences.hideAmounts }
    private var estimated: Bool {
        guard let id = row.planID, !row.inflow else { return false }
        return store.plans.first { $0.id == id }?.estimated == true
    }
    private var checkable: Bool { row.planID != nil && !row.inflow }
    var body: some View {
        let layout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: YubaiSpace.space4)) : AnyLayout(HStackLayout(spacing: YubaiSpace.gapGroup))
        layout {
            Text(NowFormat.monthDay(row.date)).yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary)
                .frame(minWidth: textSize.isAccessibilitySize ? nil : 56, alignment: .leading).fixedSize()
            Text(row.title).yubaiFont(YubaiFont.body).lineLimit(textSize.isAccessibilitySize ? nil : 1)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: YubaiSpace.space8) {
                if estimated && !hide { Text("约").yubaiFont(YubaiFont.amount) }
                AmountLabel(cents: row.amount, hide: hide, sign: row.inflow ? .inflow : .outflow, ink: row.inflow ? YubaiColor.brandInk : YubaiColor.label)
                    .fixedSize(horizontal: true, vertical: false)
                if checkable, let planID = row.planID {
                    BillCheck(planID: planID, occurrence: Dates.day(row.date)).frame(minWidth: YubaiSize.tapMin, minHeight: YubaiSize.tapMin)
                }
            }
        }.padding(.vertical, YubaiSpace.space4).frame(maxWidth: .infinity, minHeight: YubaiSize.rowSingle, alignment: .leading)
            .accessibilityElement(children: .contain)
    }
}

/// 今天（没有就昨天）记的几笔，右边是小计；不和任何数相减。
private struct NowRecentEntries: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dynamicTypeSize) private var textSize
    private var hide: Bool { store.preferences.hideAmounts }

    private struct DayGroup {
        var title: String
        var entries: [Entry]
        var total: Int64
    }

    private func group() -> DayGroup? {
        let now = Date(), today = Dates.day(now), yesterday = Dates.addDays(-1, to: today)
        var day: Date?
        var rows: [Entry] = []
        for entry in store.sortedEntries {
            if entry.deletedAt != nil || entry.date > now { continue }
            let entryDay = Dates.day(entry.date)
            if day == nil {
                guard entryDay >= yesterday else { break }
                day = entryDay
            }
            if entryDay != day { break }
            rows.append(entry)
        }
        guard let day, !rows.isEmpty else { return nil }
        let ledger = store.current
        let spending = rows.reduce(Int64(0)) { $0 + Finance.spendingAmount($1, ledger: ledger) }
        let income = rows.filter { $0.nature == .income }.reduce(Int64(0)) { $0 + $1.amount }
        var title = day == today ? "今天" : "昨天"
        if rows.count == 1, let from = rows[0].spreadFrom { title = NowFormat.range(from, rows[0].date) }
        return DayGroup(title: title, entries: rows, total: spending != 0 ? -spending : income)
    }

    var body: some View {
        if let group = group() {
            VStack(alignment: .leading, spacing: YubaiSpace.space8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(group.title).yubaiFont(YubaiFont.callout, weight: .semibold).foregroundStyle(YubaiColor.labelSecondary)
                    Spacer(minLength: YubaiSpace.gapGroup)
                    if group.total != 0 {
                        AmountLabel(cents: group.total, hide: hide, role: .small, sign: group.total < 0 ? .automatic : .inflow, ink: YubaiColor.labelSecondary)
                    }
                }.padding(.horizontal, YubaiSpace.space4)
                Card(style: .list) {
                    VStack(spacing: YubaiSpace.none) {
                        ForEach(Array(group.entries.enumerated()), id: \.element.id) { index, entry in
                            NowEntryRow(entry: entry)
                            if index < group.entries.count - 1 {
                                Rectangle().fill(YubaiColor.separator).frame(height: 1).padding(.leading, textSize.isAccessibilitySize ? 0 : YubaiSize.rowIcon + YubaiSpace.gapGroup)
                            }
                        }
                    }
                }.accessibilityElement(children: .contain).accessibilityIdentifier("todayEntries")
            }
        }
    }
}

private struct NowEntryRow: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dynamicTypeSize) private var textSize
    let entry: Entry
    private var hide: Bool { store.preferences.hideAmounts }
    private var category: String { Classification.isPending(entry) ? "还没分类" : Classification.displayCategory(entry.category) }
    var body: some View {
        let inflow = entry.nature.inflow
        let stacked = textSize.isAccessibilitySize
        let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: YubaiSpace.space4)) : AnyLayout(HStackLayout(spacing: YubaiSpace.gapGroup))
        return Button { store.sheetSource = nil; store.sheet = .editEntry(entry.id) } label: {
            HStack(alignment: .center, spacing: YubaiSpace.gapGroup) {
                if !stacked {
                    Text(String(entry.displayTitle.prefix(1))).yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelMuted)
                        .frame(width: YubaiSize.rowIcon, height: YubaiSize.rowIcon)
                        .background(YubaiColor.paperInset, in: RoundedRectangle(cornerRadius: YubaiRadius.control)).accessibilityHidden(true)
                }
                layout {
                    VStack(alignment: .leading, spacing: YubaiSpace.space2) {
                        Text(entry.displayTitle).yubaiFont(YubaiFont.rowTitle).lineLimit(stacked ? nil : 1)
                        Text(category).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary).lineLimit(stacked ? nil : 1)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    AmountLabel(cents: entry.amount, hide: hide, sign: inflow ? .inflow : .outflow, ink: inflow ? YubaiColor.brandInk : YubaiColor.label)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }.padding(.vertical, YubaiSpace.space4).frame(maxWidth: .infinity, minHeight: YubaiSize.rowDouble, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier("ledgerEntry_" + entry.id.uuidString)
    }
}
