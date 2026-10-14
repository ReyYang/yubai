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
    @Environment(\.yubaiColorTheme) private var colorTheme
    @Environment(\.colorScheme) private var colorScheme
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
                upcoming
            }
            quickActions
            Button { store.sheet = .advice } label: {
                HStack { Text("购买前想一想"); Spacer(); Image(systemName: "chevron.right") }.frame(minHeight: 44).contentShape(Rectangle())
            }.font(.callout).buttonStyle(.plain).foregroundStyle(YubaiTheme.jade)
            if !store.current.accounts.isEmpty {
                DisclosureGroup("查看资金走势") { forecast.padding(.top, 12) }.font(.callout)
                let layout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(spacing: 24))
                layout {
                    Button { store.sheet = .accounts } label: { Label("账户与余额", systemImage: "wallet.bifold").frame(minHeight: 44) }
                    Button { store.destination = .ledger } label: { Label("查看流水", systemImage: "text.book.closed").frame(minHeight: 44) }
                }.font(.callout)
            }
            if !funds.warnings.isEmpty && !store.current.accounts.isEmpty {
                DisclosureGroup("判断依据，需要保持新鲜 · \(funds.warnings.count) 项") {
                    VStack(alignment: .leading, spacing: 12) { ForEach(funds.warnings, id: \.self) { Text("· " + $0).foregroundStyle(.secondary) }; Button("核对账户与预留") { store.sheet = .accounts } }.padding(.top, 12)
                }.font(.callout)
            }
        }.navigationTitle("现在").toolbar { ToolbarItemGroup { Button { store.sheet = .imports } label: { Label("导入", systemImage: "square.and.arrow.down") }; Button { store.sheet = .entry(nil) } label: { Label("记一笔", systemImage: "plus") }.accessibilityIdentifier("addEntry") } }
    }
    var hero: some View {
        let colors = YubaiTheme.colors(for: colorTheme, colorScheme: colorScheme)
        return VStack(alignment: .leading, spacing: 18) {
            let titleLayout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout())
            titleLayout { Label("保守可动用", systemImage: "circle.lefthalf.filled").font(.callout.weight(.medium)); if !textSize.isAccessibilitySize { Spacer() }; Text("未来 \(store.current.preferences.horizonDays) 天").font(.caption).padding(.horizontal, 11).padding(.vertical, 6).background(.white.opacity(0.12), in: Capsule()) }
            AmountLabel(cents: funds.available, large: true, hide: store.current.preferences.hideAmounts).font(.largeTitle)
            Text(funds.available >= 0 ? "已扣除已知付款与预留。" : "已知安排超过当前现金，先查看付款与预留。") .font(.callout).foregroundStyle(.white.opacity(0.8)).fixedSize(horizontal: false, vertical: true)
            Button { store.sheet = .fundsCalculation } label: {
                HStack { Text("看看这笔数怎样算出来"); Spacer(); Image(systemName: "chevron.right") }.foregroundStyle(.white).frame(minHeight: 44).contentShape(Rectangle())
            }.font(.caption).buttonStyle(.plain).accessibilityIdentifier("fundsFormula").accessibilityHint("打开计算依据")
        }.padding(26).foregroundStyle(.white).background(LinearGradient(colors: [colors.deepJade, colors.heroShadow], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 26))
    }
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
                HStack { SectionHeading(title: "接下来"); Spacer(); Button("全部安排") { store.destination = .plans }.font(.callout).accessibilityLabel("查看全部安排") }
                if let item = funds.occurrences.first {
                    Button { store.destination = .plans } label: {
                        let layout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(spacing: 12))
                        layout {
                            VStack(alignment: .leading, spacing: 6) { Text(item.title).font(.callout.weight(.medium)); Text(item.overdue ? "已到期 · 请核对" : Dates.text(item.date)).font(.caption).foregroundStyle(item.overdue ? YubaiTheme.amber : .secondary) }
                            if !textSize.isAccessibilitySize { Spacer() }
                            HStack { Text(store.current.preferences.hideAmounts ? "••••••" : (item.inflow ? "+" : "") + Money.text(item.amount)).font(.system(.callout, design: .rounded)).monospacedDigit(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary) }
                        }.frame(minHeight: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                } else {
                    Text("没有待完成的安排。把房租和还款日放进来，判断会更可靠。").font(.callout).foregroundStyle(.secondary)
                }
            }
        }
    }
    var quickActions: some View {
        let layout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 14)) : AnyLayout(HStackLayout(spacing: 14))
        return layout {
            Button { store.sheet = .entry(nil) } label: { Label("记一笔", systemImage: "plus").frame(maxWidth: .infinity) }.buttonStyle(PrimaryButtonStyle())
            Button { store.sheet = .imports } label: {
                Label("整理账单", systemImage: "square.and.arrow.down").font(.headline).padding(.horizontal, 16).padding(.vertical, 14).frame(maxWidth: .infinity, minHeight: 46).background(YubaiTheme.card, in: RoundedRectangle(cornerRadius: 14))
            }.buttonStyle(.plain).foregroundStyle(YubaiTheme.jade)
        }
    }
}

struct FundsCalculationView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dynamicTypeSize) private var textSize
    var body: some View {
        let funds = Finance.funds(store.current)
        Page {
            SectionHeading(title: "从现在的现金里，留出已经有用途的钱", subtitle: "未来 \(store.current.preferences.horizonDays) 天")
            Card {
                VStack(spacing: 10) {
                    formula("可支配现金", funds.cash); formula("减：全部信用待还", -funds.debt); formula("减：已知付款", -funds.committed)
                    formula("减：目标预留", -funds.goals); formula("减：应急底线", -funds.emergency); formula("减：日常生活预留", -funds.living)
                    if funds.uncertainInflow > 0 { formula("减：性质待明确流入", -funds.uncertainInflow) }
                    Divider().padding(.vertical, 6)
                    formula("保守可动用", funds.available)
                }
            }
            InlineNote(text: store.current.preferences.hideAmounts ? "未来收入和投资市值单独展示，不提前计入。归还信用本金不重复预留。" : "未来收入 \(Money.text(funds.expectedIncome)) 和投资市值 \(Money.text(funds.investments)) 单独展示，不提前计入。归还信用本金不重复预留。")
            Button("查看付款与预留") { store.sheet = nil; store.destination = .plans }.buttonStyle(PrimaryButtonStyle())
        }.navigationTitle("计算依据").toolbar { CloseButton() }
    }
    func formula(_ title: String, _ amount: Int64) -> some View {
        let layout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6)) : AnyLayout(HStackLayout())
        return layout { Text(title); if !textSize.isAccessibilitySize { Spacer() }; AmountLabel(cents: amount, hide: store.current.preferences.hideAmounts) }
    }
}
