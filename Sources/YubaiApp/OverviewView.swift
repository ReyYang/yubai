import SwiftUI
import YubaiCore

struct OverviewView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var freshLetter: ButlerCard? {
        store.current.cards.first { WeeklyLetter.isFresh($0, now: Date()) && !ButlerCards.isMuted($0.dedupeKey, in: store.current) }
    }
    private var dueBills: [Occurrence] {
        store.funds.occurrences.filter { !$0.inflow && ($0.planID != nil || $0.rentID != nil) && Dates.day($0.date) <= Dates.day(Date()) }
    }
    var body: some View {
        scrollingContent.rootPageHeader { TabRootHeader(title: "现在", showsAmountVisibility: true) }
            .frame(maxWidth: 680).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .navigationTitle("现在")
            #if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
            #endif
    }
    private var scrollingContent: some View {
        ScrollView { content.padding(.horizontal, YubaiSpace.insetPage) }
            .rootScrollContentMargins().accessibilityIdentifier("overviewScroll")
    }
    private var content: some View {
        let funds = store.funds
        return VStack(alignment: .leading, spacing: YubaiSpace.gapSection) {
            if let letter = freshLetter {
                Button { store.sheet = .letter(letter.id) } label: {
                    HStack(spacing: YubaiSpace.space8) {
                        Image(systemName: "envelope"); Text(letterChip(letter)).lineLimit(1); Image(systemName: "chevron.right")
                    }.yubaiFont(YubaiFont.caption).padding(.horizontal, YubaiSpace.gapGroup).padding(.vertical, YubaiSpace.space8)
                        .background(YubaiColor.raised, in: Capsule()).frame(minHeight: YubaiSize.tapMin)
                }.buttonStyle(PressButtonStyle()).accessibilityIdentifier("freshLetter")
            }
            if store.current.accounts.isEmpty {
                EmptyAccountState { store.sheet = .account(nil) }
            } else {
                VStack(alignment: .leading, spacing: YubaiSpace.none) {
                    HeroCard(available: funds.available, payable: funds.debt + funds.committed,
                             reserved: funds.goals + funds.living + funds.uncertainInflow,
                             hideAmount: store.current.preferences.hideAmounts, title: "还能花", horizon: funds.horizonTitle,
                             onDetails: { store.sheet = .fundsCalculation })
                    CashTimelineCard(timeline: store.cashTimeline).padding(.top, 14)
                }
                ButlerSection()
                RestrainNearRow()
                if !dueBills.isEmpty { dueCard }
            }
            if !store.current.accounts.isEmpty {
                if dueBills.isEmpty, let next = funds.occurrences.first(where: { !$0.inflow }) {
                    TabNavigationLink(.upcomingPayments) { Page { UpcomingPaymentsView() }.navigationTitle("接下来要付的").yubaiNavigation() } label: {
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: YubaiSpace.gapGroup) { nextTitle(next); Spacer(); nextAmount(next); Image(systemName: "chevron.right") }
                            VStack(alignment: .leading, spacing: YubaiSpace.space8) { nextTitle(next); nextAmount(next) }
                        }.padding(.horizontal, YubaiSpace.insetCard).padding(.vertical, YubaiSpace.space4).frame(minHeight: YubaiSize.rowDouble).paperCardSurface(in: RoundedRectangle(cornerRadius: YubaiRadius.row))
                    }.buttonStyle(PressButtonStyle())
                } else if dueBills.isEmpty {
                    Text("下一笔 · 还没有待付款").yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary)
                        .frame(maxWidth: .infinity, minHeight: YubaiSize.tapMin, alignment: .leading)
                }
            }
        }.foregroundStyle(YubaiColor.label).amountPrivacy(store.current.preferences.hideAmounts)
            .animation(YubaiMotion.layout(reduceMotion: reduceMotion), value: store.butlerVisibility.queued.first?.id)
            .animation(YubaiMotion.layout(reduceMotion: reduceMotion), value: dueBills.map(\.id))
    }
    private var dueCard: some View {
        let rows = dueBills
        return Card(style: .list, background: YubaiColor.amberTint) {
            VStack(spacing: YubaiSpace.none) {
                ForEach(Array(rows.prefix(2))) { row in
                    dueRow(row)
                    if row.id != rows.prefix(2).last?.id { EntryFormDivider() }
                }
                if rows.count > 2 {
                    TabNavigationLink(.fixedFlows) { FixedFlowsView() } label: {
                        HStack(spacing: YubaiSpace.gapGroup) { Text("还有 \(rows.count - 2) 笔 ›"); Spacer() }.yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.amberInk)
                            .frame(minHeight: YubaiSize.tapMin)
                    }.buttonStyle(PressButtonStyle()).accessibilityIdentifier("moreDueBills")
                        .accessibilityLabel("还有 \(rows.count - 2) 笔").accessibilityValue(String(rows.count - 2))
                }
            }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("dueBills")
    }
    private func dueRow(_ row: Occurrence) -> some View {
        HStack(spacing: YubaiSpace.gapGroup) {
            if let id = row.planID {
                Button { store.sheetSource = nil; store.sheet = .editPlan(id) } label: { dueSummary(row) }
                    .buttonStyle(.plain).accessibilityElement(children: .contain).accessibilityAddTraits(.isButton)
                    .accessibilityLabel("改" + row.title)
                    .accessibilityIdentifier("editFixedFlow_" + id.uuidString)
            } else { dueSummary(row) }
            if let id = row.planID {
                FixedFlowCheck(planID: id, occurrence: row.date, title: row.title, amount: row.amount)
            }
        }.frame(minHeight: YubaiSize.rowDouble)
    }
    private func dueSummary(_ row: Occurrence) -> some View {
        HStack(spacing: YubaiSpace.gapGroup) {
            FixedFlowDot(state: .due)
            VStack(alignment: .leading, spacing: YubaiSpace.space4) {
                Text(row.title).yubaiFont(YubaiFont.rowTitle).foregroundStyle(YubaiColor.amberStrong)
                Text(dueDetail(row)).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.amberInk)
            }.frame(maxWidth: .infinity, alignment: .leading)
            AmountLabel(cents: row.amount, hide: store.current.preferences.hideAmounts,
                        ink: YubaiColor.amberStrong)
        }.frame(maxWidth: .infinity, minHeight: YubaiSize.rowDouble).contentShape(Rectangle())
    }
    private func dueDetail(_ row: Occurrence) -> String {
        let date = Dates.day(row.date) == Dates.day(Date()) ? "今天到期" : FixedFlowPresentation.monthDay(row.date) + "到期"
        let account = store.current.plans.first { $0.id == row.planID }?.accountID ?? store.current.rents.first { $0.id == row.rentID }?.accountID
        return date + (account.map { " · " + store.current.accountName($0) } ?? "")
    }
    private func nextTitle(_ item: Occurrence) -> some View {
        VStack(alignment: .leading, spacing: YubaiSpace.space4) {
            Text("下一笔").yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary)
            Text(item.date.formatted(.dateTime.month().day().locale(Locale(identifier: "zh_CN"))) + " · " + item.title).yubaiFont(YubaiFont.rowTitle)
        }
    }
    private func nextAmount(_ item: Occurrence) -> some View {
        AmountLabel(cents: item.amount, hide: store.current.preferences.hideAmounts, sign: .outflow)
    }
    private func letterChip(_ card: ButlerCard) -> String {
        guard !store.current.preferences.hideAmounts, let facts = card.letter else { return "每周来信" }
        let change = facts.availableChange
        return "每周来信 · 还能花比上周" + (change >= 0 ? "多 " : "少 ") + Money.text(change == .min ? 0 : abs(change), currency: false)
    }
}

private struct FloorLine: View {
    @Environment(\.dynamicTypeSize) private var textSize
    let floor: Int64
    let floorRoom: Int64
    var hideAmounts = false
    var showsChevron = false
    private var canKeep: Bool { floorRoom >= 0 }
    private var statusInk: Color { canKeep ? YubaiColor.brandInk : YubaiColor.amberInk }
    var body: some View {
        let layout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: YubaiSpace.space8)) : AnyLayout(HStackLayout(spacing: YubaiSpace.space8))
        layout {
            HStack(spacing: YubaiSpace.space8) {
                Circle().fill(canKeep ? YubaiColor.brand : YubaiColor.amberDot)
                    .frame(width: YubaiSize.marker, height: YubaiSize.marker).accessibilityHidden(true)
                Text("始终留着").yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary)
                AmountLabel(cents: floor, hide: hideAmounts, role: .small, sign: .none)
            }
            if !textSize.isAccessibilitySize { Spacer(minLength: YubaiSpace.space8) }
            HStack(spacing: YubaiSpace.space8) {
                status
                if textSize.isAccessibilitySize { Spacer(minLength: YubaiSpace.none) }
                if showsChevron {
                    Image(systemName: "chevron.right").yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary).accessibilityHidden(true)
                }
            }
        }.padding(.horizontal, YubaiSpace.insetCard)
            .padding(.vertical, textSize.isAccessibilitySize ? YubaiSpace.space8 : YubaiSpace.none)
            .frame(maxWidth: .infinity, minHeight: YubaiSize.tapMin, alignment: .leading)
            .contentShape(Rectangle()).accessibilityElement(children: .combine)
    }
    @ViewBuilder private var status: some View {
        if canKeep {
            Text("能留住").yubaiFont(YubaiFont.caption).foregroundStyle(statusInk)
        } else if hideAmounts {
            Text("还差一点").yubaiFont(YubaiFont.caption).foregroundStyle(statusInk)
        } else {
            HStack(spacing: YubaiSpace.space4) {
                Text("还差").yubaiFont(YubaiFont.caption)
                AmountLabel(cents: floorRoom, role: .small, sign: .none, ink: statusInk)
            }.foregroundStyle(statusInk)
        }
    }
}

/// The same Finance occurrences appear on Now and under the funds breakdown.
struct UpcomingPaymentsView: View {
    @Environment(AppStore.self) private var store
    @State private var ending: Occurrence?
    var throughHorizon = false
    private var payments: [Occurrence] { store.funds.occurrences.filter { !$0.inflow && (!throughHorizon || Dates.day($0.date) <= store.funds.horizonEnd) } }
    var body: some View {
        VStack(alignment: .leading, spacing: YubaiSpace.gapHeading) {
            SectionHeading(title: "接下来要付的", subtitle: (throughHorizon ? store.funds.horizonTitle : "未来 90 天") + " · 含已到期")
            if payments.isEmpty { Text("没有待完成的付款。")
                .yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary) }
            CardRows(payments) { item in
                paymentRow(item)
            }
        }
    }
    private func endButton(_ item: Occurrence) -> some View {
        Button("结束这个安排") { ending = item }.yubaiFont(YubaiFont.caption)
            .frame(minHeight: YubaiSize.tapMin).accessibilityIdentifier("endArrangement_" + item.id)
            .alert("停掉「\(item.title)」？",
                   isPresented: Binding(get: { ending?.id == item.id }, set: { if !$0 { ending = nil } })) {
            Button("停掉以后的", role: .destructive) {
                if let id = item.planID ?? item.rentID {
                    let change = ChangeSet(source: "用户操作", reason: "从现在起结束「\(item.title)」", items: [.endPlan(id, Date())])
                    store.apply(change, label: "结束安排")
                }
                ending = nil
            }.accessibilityIdentifier("endArrangementConfirm").accessibilityHint("只停以后的，已到期付款和历史记录保留")
            Button("取消", role: .cancel) { ending = nil }.accessibilityIdentifier("endArrangementCancel")
        }
    }
    private func title(_ item: Occurrence) -> some View {
        VStack(alignment: .leading, spacing: YubaiSpace.space4) {
            Text(item.title).yubaiFont(YubaiFont.rowTitle)
            Text(Dates.text(item.date) + (item.overdue ? " · 已到期，请核对" : ""))
                .yubaiFont(YubaiFont.meta).foregroundStyle(item.overdue ? YubaiColor.amberInk : YubaiColor.labelSecondary)
        }
    }
    private func amount(_ item: Occurrence) -> some View {
        AmountLabel(cents: item.amount, hide: store.current.preferences.hideAmounts, sign: .outflow)
    }
    private func paymentRow(_ item: Occurrence) -> some View {
        VStack(alignment: .leading, spacing: YubaiSpace.space8) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: YubaiSpace.gapGroup) { title(item); Spacer(); amount(item) }
                VStack(alignment: .leading, spacing: YubaiSpace.space8) { title(item); amount(item) }
            }
            if canEnd(item) {
                endButton(item)
            }
        }.padding(.vertical, YubaiSpace.space8)
    }
    private func canEnd(_ item: Occurrence) -> Bool {
        if let id = item.planID, let plan = store.current.plans.first(where: { $0.id == id }) { return plan.endDate == nil }
        if let id = item.rentID, let rent = store.current.rents.first(where: { $0.id == id }) { return rent.endDate == nil }
        return false
    }
}

struct FundsCalculationView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dynamicTypeSize) private var textSize
    var body: some View {
        let funds = store.funds
        Page {
            Text(funds.horizonTitle).yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelMuted)
            Card(style: .list) {
                VStack(spacing: YubaiSpace.none) {
                    formula("现金", funds.cash); formula("信用卡要还", -funds.debt); formula("接下来要付", -funds.committed)
                    formula("在存钱", -funds.goals); formula("日常开销", -funds.living)
                    if funds.uncertainInflow > 0 { formula("没写用途的进账", -funds.uncertainInflow) }
                    formula("= 还能花", funds.available)
                }
            }
            if let floor = store.current.profile.floorAmount, let room = funds.floorRoom {
                FloorLine(floor: floor, floorRoom: room, hideAmounts: store.current.preferences.hideAmounts)
                    .accessibilityIdentifier("floorLine")
            }
            ForEach(funds.warnings, id: \.self) { InlineNote(text: $0, style: .attention) }
            UpcomingPaymentsView(throughHorizon: true)
        }.navigationTitle("还能花是怎么算的").yubaiNavigation().toolbar { CloseButton() }
    }
    private func formula(_ title: String, _ amount: Int64) -> some View {
        let layout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: YubaiSpace.space8)) : AnyLayout(HStackLayout(spacing: YubaiSpace.gapGroup))
        return VStack(spacing: YubaiSpace.none) {
            layout { Text(title).yubaiFont(YubaiFont.row); if !textSize.isAccessibilitySize { Spacer() }; AmountLabel(cents: amount, hide: store.current.preferences.hideAmounts) }.frame(minHeight: YubaiSize.rowSingle)
            if title != "= 还能花" { Rectangle().fill(YubaiColor.separator).frame(height: 1).accessibilityHidden(true) }
        }
    }
}

extension Funds {
    var horizonTitle: String {
        guard let payday, let paydayTitle else { return "接下来 90 天" }
        let date = FixedFlowPresentation.monthDay(payday)
        return "到 " + date + (paydayTitle.contains("工资") ? "发工资" : " · " + paydayTitle)
    }
}
