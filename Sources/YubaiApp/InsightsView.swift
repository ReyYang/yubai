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
                    if slices.isEmpty { Text("先有生活的记录，再有洞察").yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary).padding(.vertical, 24) }
                    VStack(spacing: 0) {
                        ForEach(Array(slices.enumerated()), id: \.offset) { rank, slice in
                            NavigationLink { FlowRecordsView(categories: slice.categories, title: slice.title, income: income, interval: range).yubaiZoomDestination("category-\(rank)") } label: {
                                legend(slice, rank: rank, slices: slices).yubaiZoomSource("category-\(rank)")
                            }.buttonStyle(PressButtonStyle())
                            if slice.id != slices.last?.id { Rectangle().fill(YubaiColor.separator).frame(height: 1).accessibilityHidden(true) }
                        }
                    }
                }
            }
            Text("转账、还信用卡不算收支；退款只抵减支出，不算收入。与每周来信使用同一口径。")
                .yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary)
            if summary.spendingByCategory.contains(where: { $0.amount < 0 }) {
                Text("有跨期退款：负数类型不画扇区，占比按正数类型合计；中央与上方数字仍为退款抵减后的净额。")
                    .yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary)
            }
        }.amountPrivacy(store.current.preferences.hideAmounts).safeAreaPadding(.bottom, YubaiSize.rootBottomPadding).navigationTitle("洞察")
            #if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
            #endif
            .onChange(of: window) { _, value in anchor = Date(); if value == .custom { store.pickingInsightDates = true } }
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
        return ChartSegments(key: "insights-donut", count: slices.count) { progress in
            ZStack {
                ForEach(0..<6, id: \.self) { rank in
                    let start = positiveTotal > 0 ? slices.prefix(rank).reduce(0.0) { $0 + max(0, Double($1.amount)) } / positiveTotal : 0
                    let share = rank < slices.count && positiveTotal > 0 ? max(0, Double(slices[rank].amount)) / positiveTotal : 0
                    // Animate the angular mask; palette changes stay immediate.
                    (rank < slices.count ? color(slices[rank], rank: rank, slices: slices) : YubaiColor.neutralSoft).mask {
                        Chart {
                            SectorMark(angle: .value("整圈", 0.0..<1.0), outerRadius: .fixed(0)).foregroundStyle(.clear)
                            SectorMark(angle: .value("占比", start..<(start + share * progress[rank])), innerRadius: .fixed(64), outerRadius: .fixed(90), angularInset: 2.5)
                        }.chartLegend(.hidden).animation(YubaiMotion.layout(reduceMotion: reduceMotion), value: slices.map(\.amount))
                    }
                }
            }.frame(width: 180, height: 180)
        }
            .overlay {
                VStack(spacing: 2) { Text(income ? "收入" : "支出").yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary); AmountLabel(cents: total, role: .donut) }.frame(maxWidth: 116)
            }.frame(maxWidth: .infinity).padding(.vertical, 10)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel((income ? "收入" : "支出") + "合计 " + Money.text(total) + "。" + slices.map { $0.title + " " + Money.text($0.amount) }.joined(separator: "；"))
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
        }.frame(minHeight: 44).padding(.vertical, textSize.isAccessibilitySize ? 6 : 0).contentShape(Rectangle())
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
