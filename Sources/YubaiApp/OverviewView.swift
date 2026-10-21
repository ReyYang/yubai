import SwiftUI
import YubaiCore

struct OverviewView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var displayedToday: TodayEntries?
    private var freshLetter: ButlerCard? {
        store.current.cards.first { WeeklyLetter.isFresh($0, now: Date()) && !ButlerCards.isMuted($0.dedupeKey, in: store.current) }
    }
    var body: some View {
        Group {
            if textSize > .xxLarge {
                ScrollView { content(chartHeight: 0).padding(.horizontal, 18).padding(.top, 12) }
                    .safeAreaPadding(.bottom, YubaiSize.rootBottomPadding)
            } else {
                ViewThatFits(in: .vertical) {
                    content(chartHeight: 150).fixedSize(horizontal: false, vertical: true)
                    content(chartHeight: 96).fixedSize(horizontal: false, vertical: true)
                    content(chartHeight: 0).fixedSize(horizontal: false, vertical: true)
                }.padding(.horizontal, 18).padding(.top, 12).padding(.bottom, YubaiSize.rootBottomPadding)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
        }.frame(maxWidth: 680).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(YubaiColor.canvas).navigationTitle("现在")
            #if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
            #endif
            .onAppear { displayedToday = TodayEntries(in: store.current) }
            .onChange(of: store.current.updatedAt) { _, _ in
                if !store.pendingEntrySave || store.sheet == nil { displayedToday = TodayEntries(in: store.current) }
            }
            .onChange(of: store.entrySaveTrigger) { _, _ in displayedToday = TodayEntries(in: store.current) }
    }
    private func content(chartHeight: CGFloat) -> some View {
        let funds = store.funds
        return VStack(alignment: .leading, spacing: YubaiSpace.space12) {
            GlassGroup { HStack {
                Button { store.update("切换金额显示", recordUndo: false) { $0.preferences.hideAmounts.toggle() } } label: {
                    Image(systemName: store.current.preferences.hideAmounts ? "eye.slash" : "eye")
                        .frame(width: YubaiSize.iconButton, height: YubaiSize.iconButton).floatingSurface(in: Circle())
                }.accessibilityLabel(store.current.preferences.hideAmounts ? "显示金额" : "隐藏金额")
                Spacer(); Text("现在").yubaiFont(YubaiFont.navTitle); Spacer()
                AskToolbarButton()
            }.buttonStyle(PressButtonStyle()).frame(minHeight: 48) }
            if let letter = freshLetter {
                Button { store.sheet = .letter(letter.id) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "envelope"); Text(letterChip(letter)).lineLimit(1); Image(systemName: "chevron.right")
                    }.yubaiFont(YubaiFont.caption).padding(.horizontal, 12).padding(.vertical, 6)
                        .background(YubaiColor.raised, in: Capsule()).frame(minHeight: 44)
                }.buttonStyle(PressButtonStyle()).accessibilityIdentifier("freshLetter")
            }
            if store.current.accounts.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("从真实余额开始").yubaiFont(YubaiFont.heroLabel)
                    Text("先添加账户，填写此刻真实余额。").yubaiFont(YubaiFont.callout)
                    Button("添加第一个账户") { store.sheet = .account(nil) }
                        .buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("addFirstAccount")
                }
            } else {
                HeroCard(available: funds.available, payable: funds.debt + funds.committed,
                         reserved: funds.goals + funds.emergency + funds.living + funds.uncertainInflow,
                         hideAmount: store.current.preferences.hideAmounts, title: "还能自在支配",
                         onDetails: { store.sheet = .fundsCalculation })
                todayRow
            }
            ButlerSection()
            if !store.current.accounts.isEmpty {
                if chartHeight > 0 && !store.current.preferences.hideAmounts {
                    ForecastChart(funds: funds, height: chartHeight)
                } else {
                    NavigationLink { Page { ForecastChart(funds: funds, height: 150) }.navigationTitle("现金会怎么走").yubaiNavigation() } label: {
                        HStack { Text("现金会怎么走").yubaiFont(YubaiFont.cardTitle); Spacer(); Image(systemName: "chevron.right") }
                            .padding(.horizontal, 16).frame(minHeight: 44).background(YubaiColor.card, in: RoundedRectangle(cornerRadius: 18))
                    }.buttonStyle(PressButtonStyle())
                }
                if let next = funds.occurrences.first(where: { !$0.inflow }) {
                    NavigationLink { Page { UpcomingPaymentsView() }.navigationTitle("接下来要付的").yubaiNavigation() } label: {
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 12) { nextTitle(next); Spacer(); nextAmount(next); Image(systemName: "chevron.right") }
                            VStack(alignment: .leading, spacing: 6) { nextTitle(next); nextAmount(next) }
                        }.padding(.horizontal, 16).padding(.vertical, 12).background(YubaiColor.raised, in: RoundedRectangle(cornerRadius: 18))
                    }.buttonStyle(PressButtonStyle())
                } else {
                    Text("下一笔 · 还没有待付款").yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
            }
        }.foregroundStyle(YubaiColor.label).amountPrivacy(store.current.preferences.hideAmounts)
            .animation(YubaiMotion.layout(reduceMotion: reduceMotion), value: ButlerCards.visible(store.current).first?.id)
    }
    private var todayRow: some View {
        let today = store.pendingEntrySave ? (displayedToday ?? TodayEntries(in: store.current)) : TodayEntries(in: store.current)
        return NavigationLink { EntriesView().yubaiZoomDestination("today") } label: {
            HStack(spacing: 8) {
                Text("今天").yubaiFont(YubaiFont.row, weight: .medium)
                Text(today.count == 0 ? "还没记" : "\(today.count) 笔 · \(today.latest?.displayTitle ?? "")")
                    .yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary).lineLimit(1)
                Spacer(minLength: 0)
                if today.count == 0 {
                    Text("账目").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                } else {
                    AmountLabel(cents: today.net, hide: store.current.preferences.hideAmounts, role: .small,
                                sign: today.net > 0 ? .inflow : .automatic, fractionDigits: 2)
                }
                Image(systemName: "chevron.right").yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary)
            }.padding(.horizontal, 16).frame(minHeight: 44).background(YubaiColor.raised, in: RoundedRectangle(cornerRadius: YubaiRadius.row))
                .yubaiZoomSource("today")
        }.buttonStyle(PressButtonStyle()).accessibilityIdentifier("todayEntries")
    }
    private func nextTitle(_ item: Occurrence) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("下一笔").yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary)
            Text(item.date.formatted(.dateTime.month().day().locale(Locale(identifier: "zh_CN"))) + " · " + item.title).yubaiFont(YubaiFont.rowTitle)
        }
    }
    private func nextAmount(_ item: Occurrence) -> some View {
        AmountLabel(cents: item.amount, hide: store.current.preferences.hideAmounts, sign: .outflow)
    }
    private func letterChip(_ card: ButlerCard) -> String {
        guard !store.current.preferences.hideAmounts, let facts = card.letter else { return "周一来信 · 这周的来信" }
        let change = facts.availableChange
        return "周一来信 · 这周余白" + (change >= 0 ? "多了 " : "少了 ") + Money.text(change == .min ? 0 : abs(change), currency: false)
    }
}

/// The same Finance occurrences appear on Now and under the funds breakdown.
struct UpcomingPaymentsView: View {
    @Environment(AppStore.self) private var store
    @State private var ending: Occurrence?
    private var payments: [Occurrence] { store.funds.occurrences.filter { !$0.inflow } }
    var body: some View {
        VStack(alignment: .leading, spacing: YubaiSpace.space12) {
            SectionHeading(title: "接下来要付的", subtitle: "未来 90 天，也保留已到期的付款。")
            if payments.isEmpty { Text("没有待完成的付款。新的安排可以告诉余白，确认后再记下。")
                .yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary) }
            CardRows(payments) { item in
                VStack(alignment: .leading, spacing: YubaiSpace.space8) {
                    ViewThatFits(in: .horizontal) {
                        HStack { title(item); Spacer(); amount(item) }
                        VStack(alignment: .leading, spacing: YubaiSpace.space8) { title(item); amount(item) }
                    }
                    if canEnd(item) {
                        Button("结束这个安排") { ending = item }.yubaiFont(YubaiFont.caption)
                            .frame(minHeight: YubaiSize.tapMin).accessibilityIdentifier("endArrangement_" + item.id)
                    }
                }.padding(.vertical, YubaiSpace.space8)
            }
        }.confirmationDialog("结束「\(ending?.title ?? "这个安排")」？已到期付款和历史记录继续保留。",
                             isPresented: Binding(get: { ending != nil }, set: { if !$0 { ending = nil } })) {
            Button("结束这个安排", role: .destructive) {
                if let item = ending, let id = item.planID ?? item.rentID {
                    let change = ChangeSet(source: "用户操作", reason: "从现在起结束「\(item.title)」", items: [.endPlan(id, Date())])
                    store.apply(change, label: "结束安排")
                }
                ending = nil
            }
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
            Text("从现在的现金里，留出已经有用途的钱").yubaiFont(YubaiFont.lead)
            Text("未来 90 天").yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelMuted)
            Card(style: .list) {
                VStack(spacing: 0) {
                    formula("可支配现金", funds.cash); formula("减：全部信用待还", -funds.debt); formula("减：已知付款", -funds.committed)
                    formula("减：目标预留", -funds.goals); formula("减：始终留着的底线", -funds.emergency); formula("减：日常生活预留", -funds.living)
                    Text("日常生活按近 90 天的小额支出估算，排除已关联的固定付款；记录少时可能偏低。")
                        .yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                    if funds.uncertainInflow > 0 { formula("减：性质待明确流入", -funds.uncertainInflow) }
                    formula("保守可动用", funds.available)
                }
            }
            ForEach(funds.warnings, id: \.self) { InlineNote(text: $0, style: .attention) }
            InlineNote(text: "未来收入、投资市值和借出待收不提前当现金；信用本金不重复预留。判断依赖账单和余额是否完整。")
            UpcomingPaymentsView()
        }.navigationTitle("计算依据").yubaiNavigation().toolbar { CloseButton() }
    }
    private func formula(_ title: String, _ amount: Int64) -> some View {
        let layout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: YubaiSpace.space6)) : AnyLayout(HStackLayout())
        return VStack(spacing: 0) {
            layout { Text(title).yubaiFont(YubaiFont.row); if !textSize.isAccessibilitySize { Spacer() }; AmountLabel(cents: amount, hide: store.current.preferences.hideAmounts) }.frame(minHeight: YubaiSize.buttonHeight)
            if title != "保守可动用" { Rectangle().fill(YubaiColor.separator).frame(height: 1).accessibilityHidden(true) }
        }
    }
}
