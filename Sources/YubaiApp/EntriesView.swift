import SwiftUI
import YubaiCore

/// 账本「明细」：常驻搜索、筛选、按月按天的流水。根页的页头和「明细 / 去向」切换由 `LedgerTabView` 提供。
struct EntriesView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var textSize
    @Binding var mode: LedgerMode
    @Binding var request: LedgerPreset?
    @State private var month = Dates.calendar.dateInterval(of: .month, for: Date())!.start
    @State private var filter = EntryTimeline.Filter.all
    @State private var search = ""
    @State private var scope: DateInterval?
    @State private var pickingMonth = false
    @State private var pickerYear = Dates.calendar.component(.year, from: Date())
    @State private var pickerMonth = Dates.calendar.component(.month, from: Date())
    @State private var scrollMonth: Date?
    @State private var scrollToTop = false
    @State private var categoryTarget: CategoryTarget?
    @FocusState private var searchFocused: Bool

    init(mode: Binding<LedgerMode> = .constant(.detail), request: Binding<LedgerPreset?> = .constant(nil)) {
        _mode = mode; _request = request
    }
    private struct CategoryTarget: Identifiable { let id: UUID }
    private enum RowContext { case day, search, uncategorized }
    private var searching: Bool { searchFocused || !search.isEmpty }

    var body: some View {
        // Cached once per ledger revision/query. List creates the display rows
        // lazily, including when thousands of entries span many months.
        let timeline = store.entryTimeline(month: month, search: search, filter: filter, allMonths: true)
        let hideAmounts = store.preferences.hideAmounts
        let groups = scoped(displayMonths(timeline))
        ScrollViewReader { proxy in
            List {
                headerBlock(timeline: timeline, groups: groups, hide: hideAmounts)
                    .id("entriesTop")
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 12, trailing: 0))
                    .listRowBackground(Color.clear).listRowSeparator(.hidden)
                if groups.allSatisfy({ $0.days.isEmpty }) { emptyRow }
                else if search.isEmpty && scope == nil { monthRows(groups, hide: hideAmounts) }
                else { resultRows(groups, hide: hideAmounts) }
            }
            #if os(iOS)
            .listStyle(.insetGrouped).listSectionSpacing(12)
            .contentMargins(.horizontal, YubaiSpace.insetPage, for: .scrollContent)
            #else
            .listStyle(.inset)
            #endif
            .scrollContentBackground(.hidden).contentMargins(.top, 0, for: .scrollContent)
            .environment(\.defaultMinListRowHeight, 0)
            .scrollDismissesKeyboard(.interactively).amountPrivacy(hideAmounts).accessibilityIdentifier("entriesScroll")
            .rootScrollContentMargins().rootTabScroll(.ledger)
            .onChange(of: scrollToTop) { _, value in
                guard value else { return }
                proxy.scrollTo("entriesTop", anchor: .top); scrollToTop = false
            }
            .onChange(of: scrollMonth) { _, value in
                guard let value else { return }
                withAnimation(YubaiMotion.layout(reduceMotion: reduceMotion)) { proxy.scrollTo(value, anchor: .top) }
                scrollMonth = nil
            }
            .onChange(of: store.entryFilterRequest, initial: true) { _, pending in
                guard pending != nil else { return }
                filter = .uncategorized; endSearch()
                jump(to: store.entryFilterDate ?? Date())
            }
            .onChange(of: request, initial: true) { _, value in applyRequest(value) }
            .sheet(isPresented: $pickingMonth) { monthSheet }
            .sheet(item: $categoryTarget) { target in categorySheet(target.id) }
        }
    }

    // MARK: 页首

    @ViewBuilder private func headerBlock(timeline: EntryTimeline.Snapshot, groups: [EntryTimeline.Month], hide: Bool) -> some View {
        VStack(spacing: YubaiSpace.gapGroup) {
            if store.accounts.isEmpty { EmptyAccountState { store.sheet = .account(nil) } }
            else {
                if !searching {
                    SegmentedWide(choices: LedgerMode.allCases.map { ($0, $0 == .detail ? "明细" : "去向") }, selection: $mode,
                                  identifier: { "ledgerMode_" + $0.rawValue })
                }
                searchField
                if !searching { filters }
                summary(groups, hide: hide)
            }
        }.padding(.top, YubaiSpace.space4)
    }
    private var searchField: some View {
        HStack(spacing: YubaiSpace.gapGroup) {
            HStack(spacing: YubaiSpace.space8) {
                Image(systemName: "magnifyingglass").foregroundStyle(YubaiColor.labelSecondary).accessibilityHidden(true)
                TextField("搜名字、金额、备注", text: $search).yubaiFont(YubaiFont.row).focused($searchFocused)
                    .submitLabel(.search).accessibilityLabel("搜索账目").accessibilityIdentifier("entriesSearch")
                if !search.isEmpty {
                    Button { search = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(YubaiColor.labelMuted).yubaiHitTarget()
                    }.accessibilityLabel("清空搜索")
                }
            }.padding(.horizontal, YubaiSpace.gapGroup).frame(minHeight: YubaiSize.tapMin)
                .background(YubaiColor.card, in: Capsule())
                .overlay { if searchFocused { Capsule().strokeBorder(YubaiColor.brand, lineWidth: 1.5) } }
            if searching {
                Button(action: endSearch) {
                    Text("取消").yubaiFont(YubaiFont.row).foregroundStyle(YubaiColor.brandInk).fixedSize().yubaiHitTarget()
                }.accessibilityIdentifier("entriesSearchCancel")
            }
        }.buttonStyle(PressButtonStyle())
    }
    private var filters: some View {
        ChipFlow {
            ForEach(EntryTimeline.Filter.allCases, id: \.self) { choice in
                Button { filter = choice } label: {
                    Text(choice.rawValue).yubaiFont(YubaiFont.callout, weight: filter == choice ? .medium : .regular)
                        .foregroundStyle(filter == choice ? YubaiColor.canvas : YubaiColor.label)
                        .padding(.horizontal, YubaiSpace.space16).frame(minHeight: YubaiSize.chipHeight)
                        .background(filter == choice ? YubaiColor.label : YubaiColor.raised, in: Capsule())
                        .frame(minHeight: YubaiSize.tapMin).contentShape(Rectangle())
                }.buttonStyle(PressButtonStyle()).accessibilityAddTraits(filter == choice ? .isSelected : [])
                    .accessibilityIdentifier("entriesFilter_" + choice.rawValue)
            }
        }.accessibilityElement(children: .contain).accessibilityLabel("筛选账目")
    }
    @ViewBuilder private func summary(_ groups: [EntryTimeline.Month], hide: Bool) -> some View {
        let days = groups.flatMap(\.days)
        let count = days.reduce(0) { $0 + $1.entries.count }
        let net = days.reduce(Int64(0)) { $0 + $1.income - $1.spending }
        if !search.isEmpty || scope != nil {
            summaryLine(left: "\(count) 笔", hide: hide, net: net)
        } else if filter == .uncategorized, count > 0 {
            let ids = days.flatMap { $0.entries.map(\.id) }
            HStack {
                Text("\(count) 笔没分类").yubaiFont(YubaiFont.callout, weight: .semibold).foregroundStyle(YubaiColor.labelSecondary)
                    .accessibilityIdentifier("activeEntryCount")
                Spacer(minLength: YubaiSpace.space8)
                TabNavigationLink(.triage(ids)) { LetterTriageView(entryIDs: ids) } label: {
                    HStack(spacing: YubaiSpace.space4) { Text("一笔笔分"); Image(systemName: "chevron.right").yubaiFont(YubaiFont.meta) }
                        .yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.brandInk).yubaiHitTarget(alignment: .trailing)
                }.buttonStyle(PressButtonStyle()).accessibilityIdentifier("quickSortFromLedger")
            }.padding(.horizontal, YubaiSpace.space4)
        }
    }
    private func summaryLine(left: String, hide: Bool, net: Int64) -> some View {
        HStack {
            Text(left).yubaiFont(YubaiFont.callout, weight: .semibold).foregroundStyle(YubaiColor.labelSecondary)
                .accessibilityIdentifier("activeEntryCount")
            Spacer(minLength: YubaiSpace.space8)
            AmountLabel(cents: net, hide: hide, role: .summary).fixedSize().accessibilityIdentifier("entriesSearchTotal")
        }.padding(.horizontal, YubaiSpace.space4)
    }
    @ViewBuilder private var emptyRow: some View {
        if store.sortedEntries.allSatisfy({ $0.deletedAt != nil }) && search.isEmpty && scope == nil {
            VStack(spacing: YubaiSpace.gapGroup) {
                Text("还没有账").yubaiFont(YubaiFont.lead).padding(.top, YubaiSpace.emptyTop - YubaiSpace.space24)
                Button("记一笔") { store.sheet = .addEntry }.buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("emptyLedgerAdd")
                Button("导入账单") { store.sheet = .imports }.buttonStyle(SecondaryButtonStyle(background: YubaiColor.raised))
                    .accessibilityIdentifier("emptyLedgerImport")
            }.frame(maxWidth: .infinity).listRowBackground(Color.clear).listRowSeparator(.hidden)
        } else {
            EmptyState("list.bullet.rectangle", search.isEmpty && scope == nil ? "还没有这类账目" : "没有找到这笔",
                       action: search.isEmpty && scope == nil ? "记一笔" : "清空搜索",
                       onAction: { if search.isEmpty && scope == nil { store.sheet = .addEntry } else { endSearch() } })
                .listRowBackground(Color.clear).listRowSeparator(.hidden)
        }
    }

    // MARK: 行

    @ViewBuilder private func monthRows(_ groups: [EntryTimeline.Month], hide: Bool) -> some View {
        let previousDay = store.funds.cycleIsPayday ? groups.flatMap(\.days).first { $0.date < store.funds.cycleStart }?.date : nil
        ForEach(groups) { group in
            monthHeader(group, hide: hide)
                .id(group.date)
                .listRowInsets(EdgeInsets(top: 12, leading: 0, bottom: 4, trailing: 0))
                .listRowBackground(Color.clear).listRowSeparator(.hidden)
            ForEach(group.days) { day in
                if day.date == previousDay {
                    cycleDivider.listRowBackground(Color.clear).listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                }
                Section {
                    ForEach(day.entries) { entry in entryRow(entry, hide: hide, context: filter == .uncategorized ? .uncategorized : .day) }
                } header: {
                    ViewThatFits(in: .horizontal) {
                        HStack { Text(dayLabel(day.date)).fixedSize(); Spacer(); dayTotal(day, hide: hide) }
                        VStack(alignment: .leading, spacing: YubaiSpace.space4) { Text(dayLabel(day.date)); dayTotal(day, hide: hide) }
                    }.yubaiFont(YubaiFont.callout, weight: .semibold).textCase(nil).padding(.top, YubaiSpace.space8)
                }
            }
        }
    }
    @ViewBuilder private func resultRows(_ groups: [EntryTimeline.Month], hide: Bool) -> some View {
        let rows = groups.flatMap { $0.days.flatMap(\.entries) }
        Section {
            ForEach(rows) { entry in entryRow(entry, hide: hide, context: .search) }
        }
    }
    private func entryRow(_ entry: EntryTimeline.Row, hide: Bool, context: RowContext) -> some View {
        LedgerEntryRow(entry: entry, subtitle: subtitle(entry, context), hideAmounts: hide, isFresh: store.freshEntryIDs.contains(entry.id),
                       onSortCategory: { categoryTarget = CategoryTarget(id: entry.id) })
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            .listRowBackground(YubaiColor.paperSheet).listRowSeparatorTint(YubaiColor.separator)
    }
    private func subtitle(_ row: EntryTimeline.Row, _ context: RowContext) -> String {
        guard let entry = store.entriesByID[row.id] else { return row.categoryName }
        switch context {
        case .search:
            return FixedFlowPresentation.monthDay(entry.date) + " · " + row.categoryName
        case .uncategorized:
            if let from = entry.spreadFrom {
                return FixedFlowPresentation.monthDay(from) + " – " + "\(Dates.calendar.component(.day, from: entry.date))日"
            }
            return FixedFlowPresentation.monthDay(entry.date) + " · " + store.accountName(entry.accountID)
        case .day:
            let several = store.accounts.count > 1
            let other = several && entry.accountID != ManualBookkeeping.defaultAccount(in: store.current)?.id
            return other ? row.categoryName + " · " + store.accountName(entry.accountID) : row.categoryName
        }
    }

    // MARK: 月份与日

    private var monthSheet: some View {
        VStack(spacing: YubaiSpace.gapGroup) {
            ManualSheetHeader(title: "月份", actionTitle: "好", cancel: { pickingMonth = false }, action: {
                if let date = Dates.calendar.date(from: DateComponents(year: pickerYear, month: pickerMonth, day: 1)) { jump(to: date) }
                pickingMonth = false
            })
            HStack(spacing: 0) {
                Picker("年", selection: $pickerYear) { ForEach(monthYears, id: \.self) { Text(verbatim: "\($0) 年").tag($0) } }
                Picker("月", selection: $pickerMonth) { ForEach(1...12, id: \.self) { Text("\($0) 月").tag($0) } }
            }
            #if os(iOS)
            .pickerStyle(.wheel)
            #endif
        }.padding(.horizontal, 20).yubaiSheetBackground().presentationDetents([.height(300 + YubaiSpace.sheetHeaderTop)])
    }
    private func categorySheet(_ id: UUID) -> some View {
        let entry = store.entriesByID[id]
        let income = entry?.nature.categoryIncome ?? false
        let current = entry.map { CategoryAssignment(category: $0.category, subcategory: $0.subcategory) } ?? CategoryAssignment(category: "")
        return EntryMoreCategorySheet(income: income, selection: current, choose: { choice in
            store.update("改分类") { ledger in
                try CategoryModel.confirm(choice, entryIDs: [id], in: &ledger)
            }
            categoryTarget = nil
        }, dismiss: { categoryTarget = nil })
    }
    private func displayMonths(_ timeline: EntryTimeline.Snapshot) -> [EntryTimeline.Month] {
        if searching || !search.isEmpty { return timeline.months }
        guard !timeline.months.contains(where: { $0.date == month }) else { return timeline.months }
        guard filter == .all else { return timeline.months }
        return (timeline.months + [.init(date: month, spending: 0, income: 0, days: [])]).sorted { $0.date > $1.date }
    }
    private func scoped(_ months: [EntryTimeline.Month]) -> [EntryTimeline.Month] {
        guard let scope else { return months.filter { !$0.days.isEmpty || search.isEmpty && filter == .all } }
        return months.compactMap { group in
            let days = group.days.filter { scope.contains($0.date) }
            guard !days.isEmpty else { return nil }
            return EntryTimeline.Month(date: group.date, spending: days.reduce(0) { $0 + $1.spending },
                                       income: days.reduce(0) { $0 + $1.income }, days: days)
        }
    }
    private func applyRequest(_ value: LedgerPreset?) {
        guard let value, value.mode == .detail else { return }
        filter = .all
        search = value.search.isEmpty ? (value.category ?? "") : value.search
        scope = value.interval
        scrollToTop = true
        request = nil
    }
    private func jump(to date: Date) {
        month = Dates.calendar.dateInterval(of: .month, for: date)!.start
        // Scroll after List has received the target header (also for an empty month).
        Task { @MainActor in await Task.yield(); scrollMonth = month }
    }
    private func endSearch() { searchFocused = false; search = ""; scope = nil; scrollToTop = true }
    private var monthYears: ClosedRange<Int> {
        let years = store.sortedEntries.map { Dates.calendar.component(.year, from: $0.date) }
        let year = Dates.calendar.component(.year, from: Date())
        return min(years.min() ?? year, year - 2)...max(years.max() ?? year, year + 1)
    }
    private func monthTitle(_ date: Date) -> String {
        if !Dates.calendar.isDate(date, equalTo: Date(), toGranularity: .year) {
            return "\(Dates.calendar.component(.year, from: date)) 年 \(Dates.calendar.component(.month, from: date)) 月"
        }
        return "\(Dates.calendar.component(.month, from: date))月"
    }
    private func monthHeader(_ group: EntryTimeline.Month, hide: Bool) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack { monthButton(group.date); Spacer(minLength: YubaiSpace.space8); monthTotal(group, hide: hide) }
            VStack(alignment: .leading, spacing: YubaiSpace.space4) { monthButton(group.date); monthTotal(group, hide: hide) }
        }
    }
    private func monthButton(_ date: Date) -> some View {
        Button {
            pickerYear = Dates.calendar.component(.year, from: date); pickerMonth = Dates.calendar.component(.month, from: date); pickingMonth = true
        } label: {
            HStack(spacing: YubaiSpace.space4) {
                Text(monthTitle(date)).yubaiFont(YubaiFont.callout, weight: .semibold)
                Image(systemName: "chevron.down").yubaiFont(YubaiFont.meta)
            }.fixedSize().yubaiHitTarget(alignment: .leading)
        }.buttonStyle(PressButtonStyle()).accessibilityIdentifier("entriesMonth")
    }
    private func monthTotal(_ group: EntryTimeline.Month, hide: Bool) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: YubaiSpace.space4) { monthSpending(group, hide: hide); Text("·"); monthIncome(group, hide: hide) }.fixedSize()
            VStack(alignment: .leading, spacing: YubaiSpace.space4) { monthSpending(group, hide: hide); monthIncome(group, hide: hide) }
        }.yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
    }
    private func monthSpending(_ group: EntryTimeline.Month, hide: Bool) -> some View {
        HStack(spacing: YubaiSpace.space4) { Text("支出"); AmountLabel(cents: group.spending, hide: hide, role: .day, sign: .none) }.fixedSize()
    }
    private func monthIncome(_ group: EntryTimeline.Month, hide: Bool) -> some View {
        HStack(spacing: YubaiSpace.space4) { Text("收入"); AmountLabel(cents: group.income, hide: hide, role: .day, sign: .none, ink: YubaiColor.brandInk) }.fixedSize()
    }
    private var cycleDivider: some View {
        let start = store.funds.cycleStart
        let previous = Finance.cycle(in: store.current, now: start.addingTimeInterval(-0.001))
        let title = "上一期 · " + FixedFlowPresentation.monthDay(previous.start) + " – " + FixedFlowPresentation.monthDay(Dates.addDays(-1, to: start))
        return HStack(spacing: YubaiSpace.space8) {
            dashedLine
            Text(title).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary).fixedSize(horizontal: false, vertical: true)
            dashedLine
        }.accessibilityIdentifier("entriesPreviousCycle")
    }
    private var dashedLine: some View {
        Line().stroke(style: StrokeStyle(lineWidth: 1, dash: [3, 3])).foregroundStyle(YubaiColor.separator).frame(height: 1).accessibilityHidden(true)
    }
    private struct Line: Shape {
        func path(in rect: CGRect) -> Path { Path { $0.move(to: .zero); $0.addLine(to: CGPoint(x: rect.width, y: 0)) } }
    }
    private func dayTotal(_ day: EntryTimeline.Day, hide: Bool) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: YubaiSpace.space4) { daySpending(day, hide: hide); if day.income > 0 { Text("·"); dayIncome(day, hide: hide) } }.fixedSize()
            VStack(alignment: .leading, spacing: YubaiSpace.space4) { daySpending(day, hide: hide); if day.income > 0 { dayIncome(day, hide: hide) } }
        }.yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
    }
    private func daySpending(_ day: EntryTimeline.Day, hide: Bool) -> some View {
        HStack(spacing: YubaiSpace.space4) { if day.income > 0 { Text("支出") }; AmountLabel(cents: day.income > 0 ? day.spending : -day.spending, hide: hide, role: .day) }.fixedSize()
    }
    private func dayIncome(_ day: EntryTimeline.Day, hide: Bool) -> some View {
        HStack(spacing: YubaiSpace.space4) { Text("收入"); AmountLabel(cents: day.income, hide: hide, role: .day, ink: YubaiColor.brandInk) }.fixedSize()
    }
    private func dayLabel(_ date: Date) -> String {
        let label = ManualBookkeeping.dayLabel(date)
        if label == "今天" || label == "昨天" { return label + " · " + FixedFlowPresentation.monthDay(date) }
        return FixedFlowPresentation.monthDay(date)
    }
}

struct LedgerEntryRow: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var highlighted = true
    let entry: EntryTimeline.Row
    let subtitle: String
    let hideAmounts: Bool
    let isFresh: Bool
    var onSortCategory: () -> Void = {}
    var body: some View {
        Button { store.sheetSource = nil; store.sheet = .editEntry(entry.id) } label: { content }
            .buttonStyle(.plain).accessibilityIdentifier("ledgerEntry_" + entry.id.uuidString)
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button { delete(systemFeedback: true) } label: { Text("删掉").foregroundStyle(YubaiColor.amberInk) }
                    .tint(YubaiColor.amberTint).accessibilityIdentifier("deleteLedgerEntry_" + entry.id.uuidString)
                Button(action: onSortCategory) { Text("改分类").foregroundStyle(YubaiColor.label) }
                    .tint(YubaiColor.keyFn).accessibilityIdentifier("sortLedgerEntry_" + entry.id.uuidString)
            }
            .contextMenu {
                Button("改一笔", systemImage: "square.and.pencil") { store.sheet = .editEntry(entry.id) }
                Button("再记一笔一样的", systemImage: "plus") { duplicate() }
                Button("删掉", systemImage: "trash") { delete() }
            }
            .accessibilityAction(named: "改分类") { onSortCategory() }
            .accessibilityAction(named: "删掉") { delete() }
            .task(id: isFresh) {
                guard isFresh, YubaiMotion.claim("new-row-" + entry.id.uuidString) else { highlighted = false; return }
                withAnimation(YubaiMotion.wash(reduceMotion: reduceMotion)) { highlighted = false }
            }
    }
    private var savedEntry: Entry? { store.entriesByID[entry.id] }
    private var title: String { savedEntry?.displayTitle ?? entry.categoryName }
    private func duplicate() {
        guard let saved = store.entriesByID[entry.id] else { return }
        store.sheetSource = nil; store.sheet = .prefilledEntry(QuickEntryPrefill(entry: saved))
    }
    private var tile: some View {
        Text(String(title.prefix(1))).yubaiFont(YubaiFont.callout, weight: .medium)
            .foregroundStyle(entry.uncategorized ? YubaiColor.amberInk : entry.inflow ? YubaiColor.brandInk : YubaiColor.labelMuted)
            .frame(width: YubaiSize.rowIcon, height: YubaiSize.rowIcon)
            .background(entry.uncategorized ? YubaiColor.amberTint : entry.inflow ? YubaiColor.brandTint : YubaiColor.paperInset,
                        in: RoundedRectangle(cornerRadius: YubaiRadius.control)).accessibilityHidden(true)
    }
    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: YubaiSpace.space2) {
            HStack(spacing: YubaiSpace.space8) {
                Text(title).yubaiFont(YubaiFont.rowTitle).foregroundStyle(YubaiColor.label)
                    .lineLimit(textSize.isAccessibilitySize ? 3 : 1).truncationMode(.tail)
                if entry.intoFixedSavings {
                    Label("存着不动", systemImage: "lock").yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.brandInk)
                        .padding(.horizontal, 6).frame(minHeight: 20).background(YubaiColor.brandTint, in: Capsule()).fixedSize()
                }
            }
            if !subtitle.isEmpty {
                Text(subtitle).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                    .lineLimit(textSize.isAccessibilitySize ? 3 : 1).truncationMode(.tail)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var amountView: some View {
        AmountLabel(cents: entry.amount, hide: hideAmounts, sign: entry.inflow ? .inflow : .outflow,
                    ink: entry.inflow ? YubaiColor.brandInk : YubaiColor.label)
            .fixedSize(horizontal: true, vertical: false)
    }
    private var content: some View {
        let layout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: YubaiSpace.space4)) : AnyLayout(HStackLayout(spacing: YubaiSpace.space8))
        return HStack(spacing: YubaiSpace.gapGroup) {
            tile
            layout { titleBlock; amountView }
        }.padding(.vertical, YubaiSpace.space4).frame(maxWidth: .infinity, minHeight: YubaiSize.rowDouble).contentShape(Rectangle())
            .background(isFresh && highlighted ? YubaiColor.brandTint : YubaiColor.paperSheet)
    }
    private func delete(systemFeedback: Bool = false) {
        // Native swipe actions provide their own haptic.
        store.update("删掉", entryMotion: !systemFeedback) { ledger in
            guard let index = ledger.entries.firstIndex(where: { $0.id == entry.id && $0.deletedAt == nil }) else { return }
            ledger.entries[index].deletedAt = Date()
        }
    }
}
