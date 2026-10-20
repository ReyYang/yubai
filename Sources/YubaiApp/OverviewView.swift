import SwiftUI
import Charts
import YubaiCore

struct OverviewView: View {
    @Environment(AppStore.self) private var store
    var body: some View { OverviewContent(funds: store.funds) }
}

private struct OverviewContent: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var forecastExpanded = true; @State private var forecastAppeared = false
    let funds: Funds
    var body: some View {
        Page(hasTabBar: true) {
            HStack(alignment: .top, spacing: YubaiSpace.space12) {
                VStack(alignment: .leading, spacing: YubaiSpace.space6) {
                    Text(Date(), format: .dateTime.month(.wide).day().weekday(.wide)).yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary)
                    Text("给生活，留一点余白").yubaiFont(YubaiFont.lead)
                }
                Spacer()
                Button { store.update("切换金额显示") { $0.preferences.hideAmounts.toggle() } } label: {
                    Image(systemName: store.current.preferences.hideAmounts ? "eye.slash" : "eye").yubaiFont(YubaiFont.row)
                        .frame(width: YubaiSize.iconButton, height: YubaiSize.iconButton).background(YubaiColor.raised, in: Circle()).frame(minHeight: YubaiSize.tapMin)
                }.buttonStyle(PressButtonStyle()).accessibilityLabel("隐藏或显示总览金额")
            }
            Button { store.sheet = .ask("") } label: { Label("问余白", systemImage: "sparkle").frame(maxWidth: .infinity) }.buttonStyle(PrimaryButtonStyle())
            ButlerSection()
            if store.current.accounts.isEmpty {
                EmptyState("wallet.bifold", "从真实余额开始", "添加微信、支付宝和银行卡，再导入历史账单。余额以你核对的时刻为准，不会因导入旧记录重复增加。", action: "添加第一个账户") { store.sheet = .account(nil) }
            } else {
                hero.transaction { $0.animation = nil; $0.disablesAnimations = true }
                DisclosureGroup("查看资金走势", isExpanded: $forecastExpanded) { forecast.padding(.top, YubaiSpace.space12).transaction { if hasFreshLetter { $0.animation = nil; $0.disablesAnimations = true } } }.yubaiFont(YubaiFont.callout)
                upcoming
            }
            quickActions
            if !store.current.accounts.isEmpty {
                let layout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: YubaiSpace.space12)) : AnyLayout(HStackLayout(spacing: YubaiSpace.space24))
                layout {
                    Button { store.sheet = .accounts } label: { Label("账户与余额", systemImage: "wallet.bifold").frame(minHeight: YubaiSize.tapMin) }
                    Button { store.destination = .ledger } label: { Label("查看流水", systemImage: "text.book.closed").frame(minHeight: YubaiSize.tapMin) }
                }.yubaiFont(YubaiFont.row)
            }
            if !funds.warnings.isEmpty && !store.current.accounts.isEmpty {
                DisclosureGroup("判断依据，需要保持新鲜 · \(funds.warnings.count) 项") {
                    InlineNote(text: funds.warnings.map { "· " + $0 }.joined(separator: "\n"), style: .attention, action: "核对账户与预留", onAction: { store.sheet = .accounts }).padding(.top, YubaiSpace.space12)
                }.yubaiFont(YubaiFont.callout)
            }
        }.navigationTitle("现在").yubaiNavigation().toolbar { ToolbarItemGroup { Button { store.sheet = .imports } label: { Label("导入", systemImage: "square.and.arrow.down") }; Button { store.sheet = .entry(nil) } label: { Label("记一笔", systemImage: "plus") }.accessibilityIdentifier("addEntry") } }
    }
    private var hasFreshLetter: Bool {
        store.current.cards.contains { WeeklyLetter.isFresh($0, now: Date()) && !ButlerCards.isMuted($0.dedupeKey, in: store.current) }
    }
    var hero: some View {
        VStack(alignment: .leading, spacing: YubaiSpace.space12) {
            HeroCard(available: funds.available, payable: funds.debt + funds.committed, reserved: funds.goals + funds.emergency + funds.living + funds.uncertainInflow, attentionCount: funds.warnings.count, hideAmount: store.current.preferences.hideAmounts, onDetails: { store.sheet = .fundsCalculation }, onAttention: { store.sheet = .accounts })
            Text(funds.available >= 0 ? "已扣除已知付款与预留。" : "已知安排超过当前现金，先查看付款与预留。").yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelMuted).fixedSize(horizontal: false, vertical: true)
        }
    }
    var forecast: some View {
        Card {
            VStack(alignment: .leading, spacing: YubaiSpace.space12) {
                SectionHeading(title: "现金会怎么走", subtitle: "从今天出发，沿着真实付款日期", meta: "未来 \(store.current.preferences.horizonDays) 天")
                ChartGrow(appeared: $forecastAppeared) { progress in if store.current.preferences.hideAmounts {
                    Text("金额已隐藏，资金曲线也已收起。").yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary).frame(maxWidth: .infinity)
                } else { ForecastChart(funds: funds, progress: progress) } }
                InlineNote(text: "金额单位：元。已扣信用负债和目标预留；预测取决于记录完整度。")
            }
        }
    }
    var upcoming: some View {
        Card(style: .list, background: YubaiColor.raised) {
            VStack(alignment: .leading, spacing: YubaiSpace.space4) {
                HStack { SectionHeading(title: "接下来"); Spacer(); Button("全部安排") { store.destination = .plans }.yubaiFont(YubaiFont.callout).frame(minHeight: YubaiSize.tapMin).accessibilityLabel("查看全部安排") }
                if let item = funds.occurrences.first {
                    Button { store.destination = .plans } label: {
                        let layout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: YubaiSpace.space8)) : AnyLayout(HStackLayout(spacing: YubaiSpace.space12))
                        layout {
                            VStack(alignment: .leading, spacing: YubaiSpace.space4) {
                                Text(item.title).yubaiFont(YubaiFont.rowTitle)
                                Text(item.overdue ? "已到期 · 请核对" : Dates.text(item.date)).yubaiFont(YubaiFont.meta).foregroundStyle(item.overdue ? YubaiColor.amberInk : YubaiColor.labelSecondary)
                            }
                            if !textSize.isAccessibilitySize { Spacer() }
                            HStack { AmountLabel(cents: item.amount, hide: store.current.preferences.hideAmounts, sign: item.inflow ? .inflow : .outflow); Image(systemName: "chevron.right").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary) }
                        }.frame(minHeight: YubaiSize.buttonHeight).contentShape(Rectangle())
                    }.buttonStyle(PressButtonStyle())
                } else { Text("没有待完成的安排。把房租和还款日放进来，判断会更可靠。").yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelMuted).padding(.bottom, YubaiSpace.space12) }
            }
        }
    }
    var quickActions: some View {
        let layout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: YubaiSpace.space10)) : AnyLayout(HStackLayout(spacing: YubaiSpace.space10))
        return layout {
            Button { store.sheet = .entry(nil) } label: { Label("记一笔", systemImage: "plus").frame(maxWidth: .infinity) }.buttonStyle(PrimaryButtonStyle())
            Button { store.sheet = .imports } label: { Label("整理账单", systemImage: "square.and.arrow.down").frame(maxWidth: .infinity) }.buttonStyle(SecondaryButtonStyle())
        }
    }
}

private struct ForecastChart: View {
    let funds: Funds
    let progress: Double
    private var domain: ClosedRange<Double> {
        let values = funds.points.flatMap { [Double($0.conservative) / 100, Double($0.expected) / 100] }
        return min(0, values.min() ?? 0)...max(1, values.max() ?? 0)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: YubaiSpace.space8) {
            Chart {
                RuleMark(y: .value("底线", 0)).foregroundStyle(YubaiColor.neutralSoft).lineStyle(StrokeStyle(lineWidth: 1))
                ForEach(funds.points) { point in
                    LineMark(x: .value("日期", point.date), y: .value("余额", Double(point.conservative) / 100 * progress), series: .value("路径", "保守余量"))
                        .foregroundStyle(YubaiColor.brand).lineStyle(StrokeStyle(lineWidth: YubaiSize.lineWidth)).interpolationMethod(.stepEnd)
                    LineMark(x: .value("日期", point.date), y: .value("余额", Double(point.expected) / 100 * progress), series: .value("路径", "收入按时到账"))
                        .foregroundStyle(YubaiColor.seriesSoft).lineStyle(StrokeStyle(lineWidth: YubaiSize.lineWidth, dash: [5, 4])).interpolationMethod(.stepEnd)
                }
            }.chartYScale(domain: domain).chartLegend(.hidden).chartYAxis(.hidden)
                .chartXAxis { AxisMarks(values: .stride(by: .month)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated)).foregroundStyle(YubaiColor.labelSecondary).font(.system(size: YubaiFont.chartLabel.size)) } }
                .frame(height: 170)
        }.accessibilityLabel("未来资金走势。保守可动用 \(Money.text(funds.available))，包含预计收入时 \(Money.text(funds.available + funds.expectedIncome))。")
        if let last = funds.points.last {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: YubaiSpace.space16) { endpoints(last) }
                VStack(alignment: .leading, spacing: YubaiSpace.space6) { endpoints(last) }
            }.yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
        }
    }
    @ViewBuilder private func endpoints(_ point: ForecastPoint) -> some View {
        HStack(spacing: YubaiSpace.space6) { Text("保守余量"); AmountLabel(cents: point.conservative, role: .chart) }
        HStack(spacing: YubaiSpace.space6) { Text("预计收入到账后"); AmountLabel(cents: point.expected, role: .chart) }
    }
}

struct FundsCalculationView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dynamicTypeSize) private var textSize
    var body: some View {
        let funds = store.funds
        Page {
            VStack(alignment: .leading, spacing: YubaiSpace.space8) {
                Text("从现在的现金里，留出已经有用途的钱").yubaiFont(YubaiFont.lead)
                Text("未来 \(store.current.preferences.horizonDays) 天").yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelMuted)
            }
            Card(style: .list) {
                VStack(spacing: 0) {
                    formula("可支配现金", funds.cash); formula("减：全部信用待还", -funds.debt); formula("减：已知付款", -funds.committed)
                    formula("减：目标预留", -funds.goals); formula("减：应急底线", -funds.emergency); formula("减：日常生活预留", -funds.living)
                    if funds.livingEstimated { Text("按近 90 天小额日常支出估算；可在资金偏好中填写每日金额。").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary) }
                    if funds.uncertainInflow > 0 { formula("减：性质待明确流入", -funds.uncertainInflow) }
                    formula("保守可动用", funds.available)
                }
            }
            InlineNote(text: store.current.preferences.hideAmounts ? "未来收入和投资市值单独展示，不提前计入。归还信用本金不重复预留。" : "未来收入 \(Money.text(funds.expectedIncome)) 和投资市值 \(Money.text(funds.investments)) 单独展示，不提前计入。归还信用本金不重复预留。")
            Button("查看付款与预留") { store.sheet = nil; store.destination = .plans }.buttonStyle(PrimaryButtonStyle())
        }.navigationTitle("计算依据").yubaiNavigation().toolbar { CloseButton() }
    }
    func formula(_ title: String, _ amount: Int64) -> some View {
        let layout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: YubaiSpace.space6)) : AnyLayout(HStackLayout())
        return VStack(spacing: 0) {
            layout { Text(title).yubaiFont(YubaiFont.row); if !textSize.isAccessibilitySize { Spacer() }; AmountLabel(cents: amount, hide: store.current.preferences.hideAmounts) }.frame(minHeight: YubaiSize.buttonHeight)
            if title != "保守可动用" { Rectangle().fill(YubaiColor.separator).frame(height: 1).accessibilityHidden(true) }
        }
    }
}
