import SwiftUI
import YubaiCore

/// 账本「去向」：上周回顾、花了多少和同一天比、花在哪、固定的、手上的钱。根页页头由 `LedgerTabView` 提供。
struct WhereView: View {
    private enum Window: Int, CaseIterable {
        case cycle, previous, quarter, custom
        var title: String {
            switch self { case .cycle: "这个周期"; case .previous: "上个周期"; case .quarter: "近 3 个月"; case .custom: "自定" }
        }
    }
    @Environment(AppStore.self) private var store
    @Environment(\.dynamicTypeSize) private var textSize
    @Binding var mode: LedgerMode
    @Binding var request: LedgerPreset?
    @State private var window = Window.cycle
    @State private var customStart = Dates.calendar.dateInterval(of: .month, for: Date())!.start
    @State private var customEnd = Date()
    @State private var spent: WhereSpent?
    @State private var comparison: CycleComparison?
    @State private var applyingRange = false

    init(mode: Binding<LedgerMode> = .constant(.whereTo), request: Binding<LedgerPreset?> = .constant(nil)) {
        _mode = mode; _request = request
    }
    private var hide: Bool { store.preferences.hideAmounts }
    private var currentCycle: (start: Date, end: Date) {
        (store.funds.cycleStart, Dates.addDays(1, to: store.funds.cycleEnd))
    }
    private var fullInterval: DateInterval {
        let cycle = currentCycle
        switch window {
        case .cycle: return DateInterval(start: cycle.start, end: cycle.end)
        case .previous:
            let previous = Finance.cycle(in: store.current, now: cycle.start.addingTimeInterval(-0.001))
            return DateInterval(start: previous.start, end: max(previous.start, cycle.start))
        case .quarter:
            let month = Dates.calendar.dateInterval(of: .month, for: Date())!
            return DateInterval(start: Dates.addMonths(-2, to: month.start), end: month.end)
        case .custom: return DateInterval(start: Dates.day(customStart), end: Dates.addDays(1, to: Dates.day(max(customStart, customEnd))))
        }
    }
    private var interval: DateInterval {
        let full = fullInterval
        return DateInterval(start: full.start, end: max(full.start, min(full.end, store.financialNow.addingTimeInterval(0.001))))
    }
    private var queryKey: String {
        "\(store.ledgerRevision)-\(interval.start.timeIntervalSince1970)-\(interval.end.timeIntervalSince1970)-\(window.rawValue)"
    }

    var body: some View {
        Page(spacing: YubaiSpace.gapGroup, topPadding: YubaiSpace.space4) {
            SegmentedWide(choices: LedgerMode.allCases.map { ($0, $0 == .detail ? "明细" : "去向") }, selection: $mode,
                          identifier: { "ledgerMode_" + $0.rawValue })
            SegmentedWide(choices: Window.allCases.map { ($0, $0.title) }, selection: $window,
                          identifier: { "wherePeriod_\($0.rawValue)" })
            if window == .custom {
                Button("选择日期范围") { store.pickingInsightDates = true }.frame(minHeight: YubaiSize.tapMin)
                    .accessibilityIdentifier("whereCustomRange")
            }
            weeklyRow
            totalCard
            whereCard
            fixedCard
        }.amountPrivacy(hide).rootScrollContentMargins().rootTabScroll(.ledger).accessibilityIdentifier("insightsScroll")
            .task(id: queryKey) { await refresh() }
            .onChange(of: window) { _, value in
                if applyingRange { applyingRange = false }
                else if value == .custom { store.pickingInsightDates = true }
            }
            .onChange(of: request, initial: true) { _, value in applyRequest(value) }
            .sheet(isPresented: Binding(get: { store.pickingInsightDates }, set: { store.pickingInsightDates = $0 })) { customSheet }
    }

    // MARK: 上周回顾

    private var weeklyCard: ButlerCard? {
        store.cards.filter { $0.kind == .weeklyLetter }.max { $0.createdAt < $1.createdAt }
    }
    @ViewBuilder private var weeklyRow: some View {
        if let card = weeklyCard {
            let week = ButlerCards.calendar.dateInterval(of: .weekOfYear, for: Dates.addDays(-7, to: Date()))!
            let spending = store.cashFlow(during: week).spending
            TabNavigationLink(.weekly(card.id)) { LetterDetailView(cardID: card.id) } label: {
                Card(style: .list) {
                    HStack(spacing: YubaiSpace.gapGroup) {
                        Text("上周回顾").yubaiFont(YubaiFont.rowTitle)
                        Spacer(minLength: YubaiSpace.space8)
                        Text("花了 " + amount2(spending, hide: hide)).yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary)
                        Image(systemName: "chevron.right").yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary).accessibilityHidden(true)
                    }.frame(minHeight: YubaiSize.rowDouble).contentShape(Rectangle())
                }
            }.buttonStyle(PressButtonStyle()).accessibilityIdentifier("openWeekly")
        }
    }

    // MARK: 花了多少

    private var totalCard: some View {
        let range = interval
        let total = spentTotal
        let shown = window == .cycle ? (comparison?.spent ?? total) : total
        return Card {
            VStack(alignment: .leading, spacing: YubaiSpace.space8) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline) { Text("花了").yubaiFont(YubaiFont.callout); Spacer(minLength: YubaiSpace.space8); rangeText(range) }
                    VStack(alignment: .leading, spacing: YubaiSpace.space2) { Text("花了").yubaiFont(YubaiFont.callout); rangeText(range) }
                }.foregroundStyle(YubaiColor.labelSecondary)
                AmountLabel(cents: shown, hide: hide, role: .display, sign: .none).accessibilityIdentifier("whereTotal")
                if window == .cycle, let comparison { comparisonBlock(comparison) }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.accessibilityIdentifier("insightsCashFlowSummary")
    }
    private var spentTotal: Int64 {
        guard let spent else { return 0 }
        let flexible = spent.flexible.reduce(Int64(0)) { $0 + $1.amount }
        return flexible + spent.fixedTotal + spent.unitemized
    }
    private func rangeText(_ range: DateInterval) -> some View {
        let last = min(Date(), range.end.addingTimeInterval(-1))
        let end = Dates.calendar.isDateInToday(last) ? "今天" : FixedFlowPresentation.monthDay(last)
        return Text(FixedFlowPresentation.monthDay(range.start) + " – " + end).yubaiFont(YubaiFont.callout)
    }
    @ViewBuilder private func comparisonBlock(_ value: CycleComparison) -> some View {
        let gap = value.spent - value.previousSameDay
        VStack(alignment: .leading, spacing: YubaiSpace.space8) {
            HStack(spacing: YubaiSpace.space4) {
                Text("比上个周期同一天" + (gap > 0 ? "多" : "少")).yubaiFont(YubaiFont.row)
                AmountLabel(cents: abs(gap), hide: hide, role: .summary, sign: .none, ink: gap > 0 ? YubaiColor.amberInk : YubaiColor.brandInk)
                    .fixedSize()
            }
            if !value.changes.isEmpty {
                ChipFlow {
                    ForEach(Array(value.changes.enumerated()), id: \.offset) { _, change in
                        HStack(spacing: YubaiSpace.space4) {
                            Text(Classification.displayCategory(change.category))
                            Text(hide ? "••••" : (change.delta > 0 ? "+" : "−") + AmountLabel.text(abs(change.delta)))
                                .yubaiFont(YubaiFont.amountSmall, weight: .semibold)
                        }.yubaiFont(YubaiFont.callout).padding(.horizontal, YubaiSpace.gapGroup).frame(minHeight: YubaiSize.chipHeight)
                            .background(YubaiColor.card, in: Capsule())
                    }
                }
            }
        }
    }

    // MARK: 花在哪

    private var whereCard: some View {
        let flexible = spent?.flexible ?? []
        let unitemized = spent?.unitemized ?? 0
        let total = max(1, flexible.reduce(Int64(0)) { $0 + max(0, $1.amount) } + max(0, unitemized))
        let range = interval
        return Card(style: .compact) {
            VStack(alignment: .leading, spacing: YubaiSpace.space4) {
                Text("花在哪").yubaiFont(YubaiFont.heroLabel).padding(.bottom, YubaiSpace.space4)
                ForEach(Array(flexible.enumerated()), id: \.element.id) { rank, row in
                    TabNavigationLink(.whereCategory(category: row.category, interval: range)) {
                        WhereCategoryView(category: row.category, interval: range)
                    } label: { whereRow(title: Classification.displayCategory(row.category), amount: row.amount, share: Double(row.amount) / Double(total), rank: rank, link: true) }
                        .buttonStyle(PressButtonStyle()).accessibilityIdentifier("insightCategory_\(rank)")
                    if rank < flexible.count - 1 || unitemized > 0 { EntryFormDivider() }
                }
                if unitemized > 0 {
                    TabNavigationLink(.whereCategory(category: Reconciliation.unitemizedTitle, interval: range)) {
                        WhereCategoryView(category: Reconciliation.unitemizedTitle, interval: range)
                    } label: { whereRow(title: "没细记", amount: unitemized, share: Double(unitemized) / Double(total), rank: flexible.count, link: true) }
                        .buttonStyle(PressButtonStyle()).accessibilityIdentifier("whereUnitemized")
                }
            }
        }
    }
    private var periodTitle: String {
        switch window {
        case .cycle: "本月"
        case .previous: "上个周期"
        default: dateLabel
        }
    }
    private var dateLabel: String {
        let last = min(Date(), fullInterval.end.addingTimeInterval(-1))
        let format = Date.FormatStyle.dateTime.month().day().locale(Locale(identifier: "zh_CN"))
        return fullInterval.start.formatted(format) + " – " + last.formatted(format)
    }
    private func whereRow(title: String, amount: Int64, share: Double, rank: Int, link: Bool) -> some View {
        let wide = textSize.isAccessibilitySize
        let layout = wide ? AnyLayout(VStackLayout(alignment: .leading, spacing: YubaiSpace.space4)) : AnyLayout(HStackLayout(spacing: YubaiSpace.gapGroup))
        return VStack(alignment: .leading, spacing: YubaiSpace.space8) {
            layout {
                Text(title).yubaiFont(YubaiFont.row).frame(maxWidth: wide ? nil : .infinity, alignment: .leading)
                HStack(spacing: YubaiSpace.gapGroup) {
                    AmountLabel(cents: amount, hide: hide, role: .amount, sign: .none).fixedSize()
                    if !hide { Text(String(format: "%.0f%%", share * 100)).yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary) }
                    if link { Image(systemName: "chevron.right").yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary) }
                }
            }
            if !hide { ProgressLine(value: share, tint: rank == 0 ? YubaiColor.brand : rank == 1 ? YubaiColor.series2 : YubaiColor.seriesSoft) }
        }.padding(.vertical, YubaiSpace.space8).frame(minHeight: YubaiSize.rowSingle).contentShape(Rectangle())
    }

    // MARK: 固定的

    @ViewBuilder private var fixedCard: some View {
        if let spent, !spent.fixed.isEmpty {
            Card(style: .compact) {
                VStack(alignment: .leading, spacing: YubaiSpace.space8) {
                    HStack {
                        Text("固定的").yubaiFont(YubaiFont.heroLabel)
                        Spacer(minLength: YubaiSpace.space8)
                        AmountLabel(cents: spent.fixedTotal, hide: hide, role: .summary, sign: .none).fixedSize()
                    }
                    ForEach(spent.fixed) { entry in
                        Button { store.sheetSource = nil; store.sheet = .editEntry(entry.id) } label: {
                            HStack(spacing: YubaiSpace.space8) {
                                Text(entry.displayTitle).yubaiFont(YubaiFont.row).lineLimit(1)
                                Text("· " + FixedFlowPresentation.monthDay(entry.date)).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary).fixedSize()
                                Spacer(minLength: YubaiSpace.space8)
                                AmountLabel(cents: entry.amount, hide: hide, role: .amount, sign: .outflow).fixedSize()
                            }.frame(minHeight: YubaiSize.rowSingle).contentShape(Rectangle())
                        }.buttonStyle(PressButtonStyle())
                    }
                }
            }.accessibilityIdentifier("whereFixed")
        }
    }

    // MARK: 数据

    @MainActor private func refresh() async {
        let ledger = store.current; let range = interval; let now = Date(); let wantsComparison = window == .cycle
        let result = await Task.detached(priority: .userInitiated) {
            (Finance.whereSpent(ledger, during: range), wantsComparison ? Finance.cycleComparison(ledger, now: now) : nil)
        }.value
        guard !Task.isCancelled else { return }
        spent = result.0; comparison = result.1
    }
    private func applyRequest(_ value: LedgerPreset?) {
        guard let value, value.mode == .whereTo else { return }
        defer { request = nil }
        guard let range = value.interval else { return }
        let cycle = currentCycle
        if Dates.calendar.isDate(range.start, inSameDayAs: cycle.start) { window = .cycle; return }
        if window != .custom { applyingRange = true }
        customStart = range.start; customEnd = Dates.addDays(-1, to: range.end); window = .custom
    }
    private var customSheet: some View {
        NavigationStack {
            Form {
                DatePicker("从", selection: $customStart, in: ...Date(), displayedComponents: .date)
                DatePicker("至", selection: $customEnd, in: customStart...max(customStart, Date()), displayedComponents: .date)
            }.editorForm().manualSheetNavigation()
                .onChange(of: customStart) { _, value in if customEnd < value { customEnd = value } }
                .safeAreaInset(edge: .top) {
                    ManualSheetHeader(title: "自定时间", actionTitle: "看这段时间", cancel: { store.pickingInsightDates = false },
                                      action: { store.pickingInsightDates = false }).padding(.horizontal, 20)
                }
        }.presentationDragIndicator(.visible).yubaiSheetBackground()
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
