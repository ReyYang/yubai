import SwiftUI
import Charts
import YubaiCore

struct InsightsView: View {
    private enum Window: String, CaseIterable { case week = "本周", month = "本月", quarter = "近 3 个月", custom = "自定" }
    @Environment(AppStore.self) private var store
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var window = Window.month
    @State private var anchor = Date()
    @State private var income = false
    @State private var selectedSlice: [String]?
    @State private var selectionTrigger = 0
    @State private var customStart = Dates.calendar.dateInterval(of: .month, for: Date())!.start
    @State private var customEnd = Date()
    private var fullInterval: DateInterval {
        switch window {
        case .week: return ButlerCards.calendar.dateInterval(of: .weekOfYear, for: anchor)!
        case .month: return Dates.calendar.dateInterval(of: .month, for: anchor)!
        case .quarter:
            let month = Dates.calendar.dateInterval(of: .month, for: anchor)!
            return DateInterval(start: Dates.addMonths(-2, to: month.start), end: month.end)
        case .custom: return DateInterval(start: Dates.day(customStart), end: Dates.addDays(1, to: Dates.day(max(customStart, customEnd))))
        }
    }
    private var interval: DateInterval {
        let full = fullInterval
        return DateInterval(start: full.start, end: max(full.start, min(full.end, Date())))
    }
    private var canAdvance: Bool {
        window == .custom ? fullInterval.end <= Dates.day(Date()) : fullInterval.end <= Date()
    }
    var body: some View {
        let range = interval
        let summary = Finance.cashFlow(store.current, during: range)
        let slices = summary.slices(income: income)
        Page(spacing: 10, topPadding: 12) {
            TabRootHeader(title: "洞察")
            Segmented(choices: Window.allCases.map { ($0, $0.rawValue) }, selection: $window)
            if window == .custom { Button("选择日期范围") { store.pickingInsightDates = true }.frame(minHeight: 44) }
            HStack {
                Button { move(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }.accessibilityLabel("上一段")
                Spacer(minLength: 0)
                Text(dateLabel).yubaiFont(YubaiFont.callout).multilineTextAlignment(.center)
                Spacer(minLength: 0)
                Button { move(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }.disabled(!canAdvance).accessibilityLabel("下一段")
            }.buttonStyle(PressButtonStyle())
            let layout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
            layout {
                tile("收入", summary.income); tile("支出", summary.spending); tile("结余", summary.balance, balance: true)
            }
            Card(style: .compact) {
                VStack(spacing: 10) {
                    Segmented(choices: [(false, "支出 · 按类型"), (true, "收入 · 按类型")], selection: $income, background: YubaiColor.canvas)
                    if !store.current.preferences.hideAmounts {
                        donut(slices, total: income ? summary.income : summary.spending)
                    }
                    if slices.isEmpty { Text("还没有收支记录").yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary).padding(.vertical, 24) }
                    VStack(spacing: 0) {
                        ForEach(Array(slices.enumerated()), id: \.offset) { rank, slice in
                            NavigationLink { FlowRecordsView(categories: slice.categories, title: slice.title, income: income, interval: range).yubaiZoomDestination("category-\(rank)") } label: {
                                legend(slice, rank: rank, slices: slices).yubaiZoomSource("category-\(rank)")
                            }.buttonStyle(PressButtonStyle()).accessibilityIdentifier("insightCategory_\(rank)")
                            if slice.id != slices.last?.id { Rectangle().fill(YubaiColor.separator).frame(height: 1).accessibilityHidden(true) }
                        }
                    }
                }
            }
            if summary.spendingByCategory.contains(where: { $0.amount < 0 }) {
                Text("本期有跨期退款。")
                    .yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary)
            }
        }.amountPrivacy(store.current.preferences.hideAmounts).rootScrollContentMargins().navigationTitle("洞察")
            #if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
            #endif
            .onChange(of: window) { _, value in anchor = Date(); if value == .custom { store.pickingInsightDates = true } }
            .onChange(of: income) { _, _ in selectedSlice = nil }
            .onChange(of: fullInterval) { _, _ in selectedSlice = nil }
            .onChange(of: slices.map(\.id)) { _, _ in selectedSlice = nil }
            #if os(iOS)
            .sensoryFeedback(.selection, trigger: selectionTrigger)
            #endif
            .sheet(isPresented: Binding(get: { store.pickingInsightDates }, set: { store.pickingInsightDates = $0 })) {
                NavigationStack {
                    Form {
                        DatePicker("从", selection: $customStart, in: ...Date(), displayedComponents: .date)
                        DatePicker("至", selection: $customEnd, in: customStart...max(customStart, Date()), displayedComponents: .date)
                    }.editorForm().navigationTitle("自定时间")
                        .onChange(of: customStart) { _, value in if customEnd < value { customEnd = value } }
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("看这段时间") { store.pickingInsightDates = false } } }
                }.presentationDragIndicator(.visible)
            }
    }
    private var dateLabel: String {
        let last = min(Date(), fullInterval.end.addingTimeInterval(-1))
        let format = Date.FormatStyle.dateTime.month().day().locale(Locale(identifier: "zh_CN"))
        return fullInterval.start.formatted(format) + " – " + last.formatted(format)
    }
    private func tile(_ title: String, _ amount: Int64, balance: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).yubaiFont(YubaiFont.meta).foregroundStyle(balance ? YubaiColor.brandInk : YubaiColor.labelSecondary)
            AmountLabel(cents: amount, hide: store.current.preferences.hideAmounts, role: .summary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
            .background(balance ? YubaiColor.brandTint : YubaiColor.card, in: RoundedRectangle(cornerRadius: 18))
    }
    private func restrained(_ slice: CashFlowSlice) -> Bool {
        !income && store.current.profile.restrain.contains { area in
            slice.categories.contains { category in
                area.match.categories.contains { store.current.resolveCategory($0) == store.current.resolveCategory(category) } || area.title == category
            }
        }
    }
    private func color(_ slice: CashFlowSlice, rank: Int, slices: [CashFlowSlice]) -> Color {
        if restrained(slice) { return YubaiColor.amberDot }
        let colors = [YubaiColor.brand, YubaiColor.series2, YubaiColor.series3, YubaiColor.neutralStrong, YubaiColor.neutralSoft]
        let normalRank = slices.prefix(rank).filter { !restrained($0) }.count
        return colors[min(normalRank, colors.count - 1)]
    }
    private func donut(_ slices: [CashFlowSlice], total: Int64) -> some View {
        let positiveTotal = slices.reduce(0.0) { $0 + max(0, Double($1.amount)) }
        let selected = slices.first { $0.id == selectedSlice }
        return ChartSegments(key: "insights-donut", count: slices.count) { progress in
            ZStack {
                ForEach(Array(slices.enumerated()), id: \.element.id) { rank, slice in
                    let start = positiveTotal > 0 ? slices.prefix(rank).reduce(0.0) { $0 + max(0, Double($1.amount)) } / positiveTotal : 0
                    let share = positiveTotal > 0 ? max(0, Double(slice.amount)) / positiveTotal : 0
                    let shape = DonutSlice(start: start, end: start + share * progress[min(rank, 5)], outerRadius: selectedSlice == slice.id ? 100 : 90)
                    if share > 0 {
                        Button { select(slice.id) } label: {
                            shape.fill(color(slice, rank: rank, slices: slices))
                                .opacity(selectedSlice == nil || selectedSlice == slice.id ? 1 : 0.3)
                                .contentShape(shape)
                        }.buttonStyle(.plain)
                            .accessibilityLabel(slice.title + " · " + percentage(slice))
                            .accessibilityValue(Money.text(slice.amount))
                            .accessibilityAddTraits(selectedSlice == slice.id ? .isSelected : [])
                            .accessibilityIdentifier("donutSlice_\(rank)")
                    }
                }
                Button { select(nil) } label: {
                    VStack(spacing: 2) {
                        Text(selected.map { $0.title + " · " + percentage($0) } ?? (income ? "收入" : "支出"))
                            .yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary)
                        AmountLabel(cents: selected?.amount ?? total, role: .donut)
                        if selected != nil { Text("共 " + Money.text(total, currency: false)).yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary) }
                    }.frame(width: 124, height: 124).contentShape(Circle())
                }.buttonStyle(.plain).accessibilityIdentifier("donutSummary")
                    .accessibilityLabel(selected.map { $0.title + " · " + percentage($0) + "，" + Money.text($0.amount) + "，共 " + Money.text(total) } ?? ((income ? "收入" : "支出") + "合计 " + Money.text(total)))
                    .accessibilityHint("点两下回到全部")
            }.frame(width: 204, height: 204)
        }
            .frame(maxWidth: .infinity).padding(.vertical, 10)
            .animation(YubaiMotion.layout(reduceMotion: reduceMotion), value: slices.map(\.amount))
    }
    private func percentage(_ slice: CashFlowSlice) -> String { String(format: "%.0f%%", slice.share * 100) }
    private func select(_ id: [String]?) {
        let next = selectedSlice == id ? nil : id
        guard next != selectedSlice else { return }
        withAnimation(YubaiMotion.layout(reduceMotion: reduceMotion)) { selectedSlice = next }
        selectionTrigger &+= 1
    }
    private func legend(_ slice: CashFlowSlice, rank: Int, slices: [CashFlowSlice]) -> some View {
        let layout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6)) : AnyLayout(HStackLayout(spacing: 10))
        return layout {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 3).fill(color(slice, rank: rank, slices: slices)).frame(width: 10, height: 10).accessibilityHidden(true)
                Text(slice.title).yubaiFont(YubaiFont.row)
                if restrained(slice) { Text(slice.categories.count > 1 ? "含想克制" : "想克制").yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.amberInk) }
            }
            if !textSize.isAccessibilitySize { Spacer(minLength: 0) }
            HStack(spacing: 10) {
                AmountLabel(cents: slice.amount, hide: store.current.preferences.hideAmounts, role: .small)
                Text(store.current.preferences.hideAmounts ? "" : (slice.amount < 0 ? "—" : String(format: "%.0f%%", slice.share * 100)))
                    .yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary).numberTransition(value: slice.share * 100, enabled: !store.current.preferences.hideAmounts)
                Image(systemName: "chevron.right").yubaiFont(YubaiFont.meta)
            }
        }.frame(minHeight: 44).padding(.vertical, textSize.isAccessibilitySize ? 6 : 0)
            .padding(.horizontal, YubaiSpace.space8)
            .background { if selectedSlice == slice.id { RoundedRectangle(cornerRadius: YubaiRadius.row).fill(YubaiColor.brandTint) } }
            .opacity(selectedSlice == nil || selectedSlice == slice.id ? 1 : 0.55).contentShape(Rectangle())
    }
    private func move(_ direction: Int) {
        switch window {
        case .week: anchor = Dates.addDays(direction * 7, to: anchor)
        case .month: anchor = Dates.addMonths(direction, to: anchor)
        case .quarter: anchor = Dates.addMonths(direction * 3, to: anchor)
        case .custom:
            let days = Dates.calendar.dateComponents([.day], from: fullInterval.start, to: fullInterval.end).day ?? 1
            customStart = Dates.addDays(direction * days, to: customStart)
            customEnd = min(Date(), Dates.addDays(direction * days, to: customEnd))
        }
    }
}

private struct DonutSlice: Shape {
    var start: Double
    var end: Double
    var outerRadius: Double
    var animatableData: AnimatablePair<Double, AnimatablePair<Double, Double>> {
        get { AnimatablePair(start, AnimatablePair(end, outerRadius)) }
        set { start = newValue.first; end = newValue.second.first; outerRadius = newValue.second.second }
    }
    func path(in rect: CGRect) -> Path {
        guard end > start else { return Path() }
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let gap = min(0.012, (end - start) / 3)
        let from = Angle.degrees((start + gap / 2) * 360 - 90)
        let to = Angle.degrees((end - gap / 2) * 360 - 90)
        var path = Path()
        path.addArc(center: center, radius: outerRadius, startAngle: from, endAngle: to, clockwise: false)
        path.addArc(center: center, radius: 64, startAngle: to, endAngle: from, clockwise: true)
        path.closeSubpath()
        return path
    }
}

private struct FlowRecordsView: View {
    @Environment(AppStore.self) private var store
    let categories: [String]
    let title: String
    let income: Bool
    let interval: DateInterval
    var body: some View {
        let entriesByID = Dictionary(uniqueKeysWithValues: store.current.entries.map { ($0.id, $0) })
        let rows = store.sortedEntries.filter { entry in
            guard entry.deletedAt == nil, entry.date >= interval.start, entry.date < interval.end else { return false }
            let natureMatches = income ? entry.nature == .income : (entry.nature == .expense || entry.nature == .refund)
            let category = income ? entry.category : Finance.spendingCategory(entry, entriesByID: entriesByID)
            return natureMatches && categories.contains(category)
        }
        Page {
            CardRows(rows) { entry in
                EntryLink(entry: entry, hideAmount: store.current.preferences.hideAmounts, editable: true)
            }
        }.navigationTitle(title).yubaiNavigation()
    }
}
