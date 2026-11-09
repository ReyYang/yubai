import SwiftUI
import Charts
import YubaiCore

struct InsightsView: View {
    private enum Window: String, CaseIterable { case week = "本周", month = "这个月", quarter = "近 3 个月", custom = "自定" }
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
        case .month: return DateInterval(start: store.funds.cycleStart, end: Dates.addDays(1, to: store.funds.cycleEnd))
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
        let summary = store.cashFlow(during: range)
        let slices = store.cashFlowSlices(during: range, income: income)
        Page(spacing: YubaiSpace.gapSection, topPadding: YubaiSpace.none) {
            Segmented(choices: Window.allCases.map { ($0, $0.rawValue) }, selection: $window)
            if window == .custom { Button("选择日期范围") { store.pickingInsightDates = true }.frame(minHeight: YubaiSize.tapMin) }
            CashTimelineCard(timeline: store.cashTimeline)
            Card(style: .compact) {
                VStack(spacing: YubaiSpace.gapGroup) {
                    HStack {
                        Text("花在哪").yubaiFont(YubaiFont.heroLabel)
                        Spacer()
                        AmountLabel(cents: summary.spending, hide: store.preferences.hideAmounts, role: .summary)
                    }

                    VStack(spacing: YubaiSpace.none) {
                        ForEach(Array(slices.enumerated()), id: \.offset) { rank, slice in
                            categoryLink(slice, rank: rank, slices: slices, range: range)
                            if slice.id != slices.last?.id { Rectangle().fill(YubaiColor.separator).frame(height: 1).accessibilityHidden(true) }
                        }
                    }
                }
            }
        }.amountPrivacy(store.preferences.hideAmounts).rootScrollContentMargins().rootTabScroll(.insights).accessibilityIdentifier("insightsScroll")
            .rootPageHeader { TabRootHeader(title: "洞察") }.navigationTitle("洞察")
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
                    }.editorForm().manualSheetNavigation()
                        .onChange(of: customStart) { _, value in if customEnd < value { customEnd = value } }
                        .safeAreaInset(edge: .top) {
                            ManualSheetHeader(title: "自定时间", actionTitle: "看这段时间", cancel: { store.pickingInsightDates = false }, action: { store.pickingInsightDates = false }).padding(.horizontal, 20)
                        }
                }.presentationDragIndicator(.visible).yubaiSheetBackground()
            }
    }
    private func categoryLink(_ slice: CashFlowSlice, rank: Int, slices: [CashFlowSlice], range: DateInterval) -> some View {
        TabNavigationLink(categoryRoute(slice, range: range)) { categoryDestination(slice, range: range) } label: {
            legend(slice, rank: rank, slices: slices)
        }.buttonStyle(PressButtonStyle()).accessibilityIdentifier("insightCategory_\(rank)")
    }
    private func categoryRoute(_ slice: CashFlowSlice, range: DateInterval) -> TabRoute {
        if slice.categories.count == 1, let category = slice.categories.first {
            return .subcategoryInsights(category: category, income: income, interval: range, periodTitle: categoryPeriodTitle)
        }
        return .flowRecords(categories: slice.categories, title: slice.title, income: income, interval: range)
    }
    @ViewBuilder private func categoryDestination(_ slice: CashFlowSlice, range: DateInterval) -> some View {
        if slice.categories.count == 1, let category = slice.categories.first {
            SubcategoryInsightsView(category: category, income: income, interval: range, periodTitle: categoryPeriodTitle)
        } else {
            FlowRecordsView(categories: slice.categories, title: slice.title, income: income, interval: range)
        }
    }
    private var categoryPeriodTitle: String {
        if window == .month {
            return Dates.calendar.isDate(anchor, equalTo: Date(), toGranularity: .month) ? "本月" : "\(Dates.calendar.component(.month, from: anchor))月"
        }
        return dateLabel
    }
    private var dateLabel: String {
        let last = min(Date(), fullInterval.end.addingTimeInterval(-1))
        let format = Date.FormatStyle.dateTime.month().day().locale(Locale(identifier: "zh_CN"))
        return fullInterval.start.formatted(format) + " – " + last.formatted(format)
    }
    private func tile(_ title: String, _ amount: Int64, balance: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: YubaiSpace.space4) {
            Text(title).yubaiFont(YubaiFont.meta).foregroundStyle(balance ? YubaiColor.brandInk : YubaiColor.labelSecondary)
            AmountLabel(cents: amount, hide: store.preferences.hideAmounts, role: .summary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(YubaiSpace.insetCard)
            .paperCardSurface(in: RoundedRectangle(cornerRadius: YubaiRadius.row), background: balance ? YubaiColor.brandTint : nil)
    }
    private func restrained(_ slice: CashFlowSlice) -> Bool {
        !income && store.profile.restrain.contains { area in
            slice.categories.contains { category in
                area.match.categories.contains { store.resolveCategory($0) == store.resolveCategory(category) } || area.title == category
            }
        }
    }
    private func color(_ slice: CashFlowSlice, rank: Int, slices: [CashFlowSlice]) -> Color {
        if restrained(slice) { return YubaiColor.amberDot }
        let colors = [YubaiColor.brand, YubaiColor.series2, YubaiColor.series3, YubaiColor.neutralStrong, YubaiColor.neutralSoft]
        let normalRank = slices.prefix(rank).filter { !restrained($0) }.count
        return colors[min(normalRank, colors.count - 1)]
    }
    private func percentage(_ slice: CashFlowSlice) -> String { String(format: "%.0f%%", slice.share * 100) }
    private func legend(_ slice: CashFlowSlice, rank: Int, slices: [CashFlowSlice]) -> some View {
        let layout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: YubaiSpace.space8)) : AnyLayout(HStackLayout(spacing: YubaiSpace.gapGroup))
        return layout {
            HStack(spacing: YubaiSpace.gapGroup) {
                RoundedRectangle(cornerRadius: 3).fill(color(slice, rank: rank, slices: slices)).frame(width: 10, height: 10).accessibilityHidden(true)
                Text(slice.title).yubaiFont(YubaiFont.row)
                if restrained(slice) { Text(slice.categories.count > 1 ? "含想克制" : "想克制").yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.amberInk) }
            }
            if !textSize.isAccessibilitySize { Spacer(minLength: YubaiSpace.none) }
            HStack(spacing: YubaiSpace.gapGroup) {
                AmountLabel(cents: slice.amount, hide: store.preferences.hideAmounts, role: .small)
                Text(legendPercentage(slice))
                    .yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary).numberTransition(value: slice.share * 100, enabled: !store.preferences.hideAmounts)
                Image(systemName: "chevron.right").yubaiFont(YubaiFont.meta)
            }
        }.frame(minHeight: YubaiSize.rowSingle).padding(.vertical, textSize.isAccessibilitySize ? YubaiSpace.space8 : YubaiSpace.none)
            .background {
                if selectedSlice == slice.id {
                    RoundedRectangle(cornerRadius: YubaiRadius.row).fill(YubaiColor.brandTint)
                        .padding(.horizontal, -YubaiSpace.space8)
                }
            }
            .opacity(selectedSlice == nil || selectedSlice == slice.id ? 1 : 0.55).contentShape(Rectangle())
    }
    private func legendPercentage(_ slice: CashFlowSlice) -> String {
        if store.preferences.hideAmounts { return "" }
        return slice.amount < 0 ? "—" : percentage(slice)
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


struct FlowRecordsView: View {
    @Environment(AppStore.self) private var store
    let categories: [String]
    let title: String
    let income: Bool
    let interval: DateInterval
    var body: some View {
        let rows = store.flowRecords(categories: categories, income: income, interval: interval)
        Page {
            CardRows(rows) { entry in
                EntryLink(entry: entry, hideAmount: store.preferences.hideAmounts, editable: true)
            }
        }.navigationTitle(title).yubaiNavigation()
    }
}
