import SwiftUI
import Charts
import YubaiCore

struct OverviewView: View {
    @Environment(AppStore.self) private var store
    var body: some View { OverviewContent(funds: Finance.funds(store.current)) }
}

private struct OverviewContent: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var showCalculation = false
    let funds: Funds
    var body: some View {
        Page {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 7) { Text(Date(), format: .dateTime.month(.wide).day().weekday(.wide)).font(.caption).foregroundStyle(.secondary); Text("给生活，留一点余白").font(.system(.title, design: .serif).weight(.medium)) }
                Spacer(); Button { store.update("切换金额显示") { $0.preferences.hideAmounts.toggle() } } label: { Image(systemName: store.current.preferences.hideAmounts ? "eye.slash" : "eye").font(.body) }.buttonStyle(.plain).accessibilityLabel("隐藏或显示总览金额")
            }
            if store.current.accounts.isEmpty {
                Card { EmptyState("wallet.bifold", "从真实余额开始", "添加微信、支付宝和银行卡，再导入历史账单。余额以你核对的时刻为准，不会因导入旧记录重复增加。", action: "添加第一个账户") { store.sheet = .account(nil) } }
            } else {
                hero
                ViewThatFits(in: .horizontal) { HStack(alignment: .top, spacing: 20) { forecast.frame(minWidth: 380); upcoming.frame(width: 300) }; VStack(spacing: 20) { forecast; upcoming } }
            }
            quickActions
            if !store.current.accounts.isEmpty { accounts; recent }
            if !funds.warnings.isEmpty && !store.current.accounts.isEmpty {
                Card { VStack(alignment: .leading, spacing: 12) { Label("判断依据，需要保持新鲜", systemImage: "info.circle").font(.headline); ForEach(funds.warnings, id: \.self) { Text("· " + $0).font(.callout).foregroundStyle(.secondary) }; Button("核对账户与预留") { store.sheet = .accounts }.font(.callout) } }
            }
        }.navigationTitle("现在").toolbar { ToolbarItemGroup { Button { store.sheet = .imports } label: { Label("导入", systemImage: "square.and.arrow.down") }; Button { store.sheet = .entry(nil) } label: { Label("记一笔", systemImage: "plus") }.accessibilityIdentifier("addEntry") } }
    }
    var hero: some View {
        VStack(alignment: .leading, spacing: 24) {
            let titleLayout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout())
            titleLayout { Label("保守可动用", systemImage: "circle.lefthalf.filled").font(.callout.weight(.medium)); if !textSize.isAccessibilitySize { Spacer() }; Text("未来 \(store.current.preferences.horizonDays) 天").font(.caption).padding(.horizontal, 11).padding(.vertical, 6).background(.white.opacity(0.12), in: Capsule()) }
            AmountLabel(cents: funds.available, large: true, hide: store.current.preferences.hideAmounts).font(.largeTitle)
            Text(funds.available >= 0 ? "已为已知付款、还款和你的目标留出位置。" : "已知安排超过当前现金，先查看付款与预留。") .font(.callout).foregroundStyle(.white.opacity(0.8)).fixedSize(horizontal: false, vertical: true)
            Rectangle().fill(.white.opacity(0.15)).frame(height: 1)
            let metricsLayout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 14)) : AnyLayout(HStackLayout(alignment: .top, spacing: 14))
            metricsLayout {
                heroMetric("现金余额", funds.cash)
                heroMetric("信用待还", funds.debt)
                heroMetric("付款与预留", funds.committed + funds.goals + funds.emergency + funds.living + funds.uncertainInflow)
            }
            Button { showCalculation.toggle() } label: {
                HStack { Text("这笔数怎样算出来"); Spacer(); Image(systemName: showCalculation ? "chevron.down" : "chevron.right") }.foregroundStyle(.white).frame(minHeight: 44).contentShape(Rectangle())
            }.font(.caption).buttonStyle(.plain).accessibilityIdentifier("fundsFormula").accessibilityValue(showCalculation ? "已展开" : "已收起")
            if showCalculation {
                VStack(spacing: 10) {
                    formula("可支配现金", funds.cash); formula("减：全部信用待还", -funds.debt); formula("减：已知付款", -funds.committed)
                    formula("减：目标预留", -funds.goals); formula("减：应急底线", -funds.emergency); formula("减：日常生活预留", -funds.living)
                    if funds.uncertainInflow > 0 { formula("减：性质待明确流入", -funds.uncertainInflow) }
                    Text(store.current.preferences.hideAmounts ? "未来收入和投资市值单独展示，不提前计入。归还信用本金不重复预留。" : "未来收入 \(Money.text(funds.expectedIncome)) 和投资市值 \(Money.text(funds.investments)) 单独展示，不提前计入。归还信用本金不重复预留。") .font(.caption).foregroundStyle(.white.opacity(0.8)).padding(.top, 6)
                }.padding(.top, 14)
            }
        }.padding(26).foregroundStyle(.white).background(LinearGradient(colors: [YubaiTheme.deepJade, Color(red: 0.08, green: 0.29, blue: 0.25)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 26))
    }
    func heroMetric(_ title: String, _ cents: Int64) -> some View { VStack(alignment: .leading, spacing: 7) { Text(title).font(.caption).foregroundStyle(.white.opacity(0.75)); Text(store.current.preferences.hideAmounts ? "••••••" : Money.text(cents)).font(.system(.callout, design: .rounded).weight(.semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6) }.frame(maxWidth: .infinity, alignment: .leading) }
    func formula(_ title: String, _ amount: Int64) -> some View { HStack { Text(title); Spacer(); AmountLabel(cents: amount, hide: store.current.preferences.hideAmounts).font(.caption) } }
    var forecast: some View {
        Card {
            VStack(alignment: .leading, spacing: 18) {
                SectionHeading(title: "接下来的余地", subtitle: "从今天出发，沿着真实付款日期")
                if store.current.preferences.hideAmounts { Text("金额已隐藏，资金曲线也已收起。").font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 170) } else { Chart {
                    RuleMark(y: .value("底线", 0)).foregroundStyle(.secondary.opacity(0.4)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                    ForEach(funds.points) { p in
                        LineMark(x: .value("日期", p.date), y: .value("余额", Double(p.conservative) / 100), series: .value("路径", "保守余量")).foregroundStyle(YubaiTheme.jade).lineStyle(StrokeStyle(lineWidth: 2.5))
                        LineMark(x: .value("日期", p.date), y: .value("余额", Double(p.expected) / 100), series: .value("路径", "收入按时到账")).foregroundStyle(YubaiTheme.jade.opacity(0.35)).lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    }
                }.chartXAxis { AxisMarks(values: .stride(by: .month)) { _ in AxisGridLine(); AxisValueLabel(format: .dateTime.month(.abbreviated)) } }.chartYAxis { AxisMarks(position: .leading) }.frame(height: 170).accessibilityLabel("未来资金走势。保守可动用 \(Money.text(funds.available))，包含预计收入时 \(Money.text(funds.available + funds.expectedIncome))。") }
                HStack(spacing: 16) { Label("保守余量", systemImage: "line.diagonal").foregroundStyle(YubaiTheme.jade); Label("预计收入到账后", systemImage: "ellipsis").foregroundStyle(.secondary) }.font(.caption2)
                InlineNote(text: "金额单位：元。已扣信用负债和目标预留；预测取决于记录完整度。")
            }
        }
    }
    var upcoming: some View {
        Card {
            VStack(alignment: .leading, spacing: 17) {
                HStack { SectionHeading(title: "最近的安排"); Spacer(); Button { store.destination = .plans } label: { Image(systemName: "arrow.up.right") }.buttonStyle(.plain).accessibilityLabel("查看全部安排") }
                if funds.occurrences.isEmpty { Text("没有待完成的安排。把房租和还款日放进来，判断会更可靠。").font(.callout).foregroundStyle(.secondary).padding(.vertical, 20) }
                ForEach(Array(funds.occurrences.prefix(4))) { item in
                    HStack(spacing: 12) { VStack(alignment: .leading, spacing: 6) { Text(item.title).font(.callout.weight(.medium)); Text(item.overdue ? "已到期 · 请核对" : Dates.text(item.date)).font(.caption).foregroundStyle(item.overdue ? YubaiTheme.amber : .secondary) }; Spacer(); Text(store.current.preferences.hideAmounts ? "••••••" : (item.inflow ? "+" : "") + Money.text(item.amount)).font(.system(.callout, design: .rounded)).monospacedDigit() }
                    if item.id != funds.occurrences.prefix(4).last?.id { Divider() }
                }
            }
        }
    }
    var quickActions: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
            Button { store.sheet = .imports } label: { actionCard("square.and.arrow.down", "整理账单", "一次导入，之后轻松补充") }
            Button { store.sheet = .advice } label: { actionCard("sparkle", "购买前想一想", "看清影响，再作自己的决定") }
        }.buttonStyle(.plain)
    }
    func actionCard(_ symbol: String, _ title: String, _ subtitle: String) -> some View { Card { VStack(alignment: .leading, spacing: 12) { Image(systemName: symbol).font(.title2).foregroundStyle(YubaiTheme.jade); Text(title).font(.headline); Text(subtitle).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) } } }
    var accounts: some View {
        Card { VStack(alignment: .leading, spacing: 18) { HStack { SectionHeading(title: "钱在哪里"); Spacer(); Button("管理") { store.sheet = .accounts }.font(.callout) }; ForEach(store.current.accounts.filter { !$0.archived }) { account in HStack(spacing: 12) { IconTile(symbol: account.kind.symbol); VStack(alignment: .leading, spacing: 4) { Text(account.name).font(.callout.weight(.medium)); Text(account.kind.label).font(.caption).foregroundStyle(.secondary) }; Spacer(); AmountLabel(cents: Finance.balance(account, in: store.current), hide: store.current.preferences.hideAmounts) } }; Divider(); HStack { Text("净资产 · 包含投资市值").font(.caption).foregroundStyle(.secondary); Spacer(); AmountLabel(cents: funds.netWorth, hide: store.current.preferences.hideAmounts) } } }
    }
    var recent: some View {
        Card { VStack(alignment: .leading, spacing: 16) { HStack { SectionHeading(title: "最近记下的"); Spacer(); Button("全部") { store.destination = .ledger }.font(.callout) }; if store.current.activeEntries.isEmpty { Text("账本还是空的，可以记一笔或导入账单。").font(.callout).foregroundStyle(.secondary) }; ForEach(Array(store.current.activeEntries.sorted { $0.date > $1.date }.prefix(4))) { entry in Button { store.sheet = .entryDetail(entry.id) } label: { EntryRow(entry: entry, hideAmount: store.current.preferences.hideAmounts) }.buttonStyle(.plain) } } }
    }
}
