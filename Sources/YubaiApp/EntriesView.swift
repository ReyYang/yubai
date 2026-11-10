import SwiftUI
import YubaiCore

struct EntriesView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var month = Dates.calendar.dateInterval(of: .month, for: Date())!.start
    @State private var filter = EntryTimeline.Filter.all
    @State private var search = ""
    @State private var showingSearch = false
    @State private var pickingMonth = false
    @State private var pickerYear = Dates.calendar.component(.year, from: Date())
    @State private var pickerMonth = Dates.calendar.component(.month, from: Date())
    @State private var scrollMonth: Date?
    @State private var scrollToTop = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        // Cached once per ledger revision/query. List creates the display rows
        // lazily, including when thousands of entries span many months.
        let timeline = store.entryTimeline(month: month, search: search, filter: filter, allMonths: true)
        let hideAmounts = store.preferences.hideAmounts
        let groups = displayMonths(timeline)
        let previousDay = store.funds.cycleIsPayday ? timeline.days.first { $0.date < store.funds.cycleStart }?.date : nil
        ScrollViewReader { proxy in
            List {
                VStack(spacing: YubaiSpace.gapGroup) {
                    if !showingSearch {
                        if store.accounts.isEmpty { EmptyAccountState { store.sheet = .account(nil) } }
                        else { LedgerHero() }
                        LetterInboxChip()
                    }
                    filters
                    if showingSearch {
                        HStack {
                            Text("全部月份 · \(timeline.count) 笔").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                            Spacer()
                            AmountLabel(cents: timeline.income - timeline.spending, hide: hideAmounts)
                        }.accessibilityIdentifier("entriesSearchTotal")
                    }
                }
                .id("entriesTop")
                .listRowInsets(EdgeInsets(top: 16, leading: 0, bottom: 12, trailing: 0))
                .listRowBackground(Color.clear).listRowSeparator(.hidden)
                if timeline.days.isEmpty {
                    EmptyState("list.bullet.rectangle", showingSearch ? "没有找到这笔" : filter == .all ? "还没有账目" : "还没有这类账目",
                               action: showingSearch ? "清空搜索" : "记一笔", onAction: { if showingSearch { search = "" } else { store.sheet = .addEntry } })
                        .listRowBackground(Color.clear).listRowSeparator(.hidden)
                }
                ForEach(groups) { group in
                    monthHeader(group, hide: hideAmounts)
                        .id(group.date)
                        .listRowInsets(EdgeInsets(top: 16, leading: 0, bottom: 4, trailing: 0))
                        .listRowBackground(Color.clear).listRowSeparator(.hidden)
                    if showingSearch {
                        Section {
                            ForEach(group.days.flatMap(\.entries)) { entry in entryRow(entry, hideAmounts: hideAmounts, searchResult: true) }
                        }
                    } else {
                        ForEach(group.days) { day in
                            if day.date == previousDay {
                                cycleDivider.listRowBackground(Color.clear).listRowSeparator(.hidden)
                                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                            }
                            Section {
                                ForEach(day.entries) { entry in entryRow(entry, hideAmounts: hideAmounts) }
                            } header: {
                                ViewThatFits(in: .horizontal) {
                                    HStack { Text(dayLabel(day.date)).fixedSize(); Spacer(); dayTotal(day, hide: hideAmounts) }
                                    VStack(alignment: .leading, spacing: 4) { Text(dayLabel(day.date)); dayTotal(day, hide: hideAmounts) }
                                }.yubaiFont(YubaiFont.callout, weight: .semibold).textCase(nil).padding(.top, 8)
                            }
                        }
                    }
                }
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
            .rootPageHeader { header }
            .navigationTitle("账本").yubaiNavigation()
            .onChange(of: scrollToTop) { _, value in
                guard value else { return }
                proxy.scrollTo("entriesTop", anchor: .top); scrollToTop = false
            }
            .onChange(of: scrollMonth) { _, value in
                guard let value else { return }
                withAnimation(YubaiMotion.layout(reduceMotion: reduceMotion)) { proxy.scrollTo(value, anchor: .top) }
                scrollMonth = nil
            }
            .onChange(of: store.entryFilterRequest, initial: true) { _, request in
                guard request != nil else { return }
                filter = .uncategorized; endSearch()
                jump(to: store.entryFilterDate ?? Date())
            }
            #if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
            #endif
            .sheet(isPresented: $pickingMonth) { monthSheet }
        }
    }
    @ViewBuilder private var header: some View {
        if showingSearch {
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(YubaiColor.labelSecondary).accessibilityHidden(true)
                    TextField("搜索", text: $search).yubaiFont(YubaiFont.row).focused($searchFocused)
                        .submitLabel(.search).accessibilityLabel("搜索账目").accessibilityHint("可按用途、分类或金额搜索").accessibilityIdentifier("entriesSearch")
                    if !search.isEmpty {
                        Button { search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(YubaiColor.labelMuted) }
                            .accessibilityLabel("清空搜索")
                    }
                }.padding(.horizontal, 14).frame(minHeight: 40).background(YubaiColor.raised, in: Capsule())
                Button("取消", action: endSearch).yubaiFont(YubaiFont.row).foregroundStyle(YubaiColor.brandInk).fixedSize()
                    .yubaiHitTarget().accessibilityIdentifier("entriesSearchCancel")
            }.frame(minHeight: 48).buttonStyle(PressButtonStyle())
                .task { await Task.yield(); guard !Task.isCancelled, showingSearch else { return }; searchFocused = true }
        } else {
            TabRootHeader(title: "账本", showsAmountVisibility: true, onSearch: { showingSearch = true; scrollToTop = true })
        }
    }
    private var monthSheet: some View {
        VStack(spacing: 12) {
            ManualSheetHeader(title: "月份", actionTitle: "好", cancel: { pickingMonth = false }, action: {
                if let date = Dates.calendar.date(from: DateComponents(year: pickerYear, month: pickerMonth, day: 1)) { jump(to: date) }
                pickingMonth = false
            })
            HStack(spacing: 0) {
                Picker("年", selection: $pickerYear) { ForEach(monthYears, id: \.self) { Text("\($0) 年").tag($0) } }
                Picker("月", selection: $pickerMonth) { ForEach(1...12, id: \.self) { Text("\($0) 月").tag($0) } }
            }
            #if os(iOS)
            .pickerStyle(.wheel)
            #endif
        }.padding(.horizontal, 20).yubaiSheetBackground().presentationDetents([.height(300 + YubaiSpace.sheetHeaderTop)])
    }
    private func displayMonths(_ timeline: EntryTimeline.Snapshot) -> [EntryTimeline.Month] {
        if showingSearch { return timeline.months }
        guard !timeline.months.contains(where: { $0.date == month }) else { return timeline.months }
        return (timeline.months + [.init(date: month, spending: 0, income: 0, days: [])]).sorted { $0.date > $1.date }
    }
    private func jump(to date: Date) {
        month = Dates.calendar.dateInterval(of: .month, for: date)!.start
        // Scroll after List has received the target header (also for an empty month).
        Task { @MainActor in await Task.yield(); scrollMonth = month }
    }
    private func endSearch() { searchFocused = false; search = ""; showingSearch = false; scrollToTop = true }
    private var monthYears: ClosedRange<Int> {
        let years = store.sortedEntries.map { Dates.calendar.component(.year, from: $0.date) }
        let year = Dates.calendar.component(.year, from: Date())
        return min(years.min() ?? year, year - 2)...max(years.max() ?? year, year + 1)
    }
    private func monthTitle(_ date: Date) -> String {
        if showingSearch || !Dates.calendar.isDate(date, equalTo: Date(), toGranularity: .year) {
            return "\(Dates.calendar.component(.year, from: date)) 年 \(Dates.calendar.component(.month, from: date)) 月"
        }
        return "\(Dates.calendar.component(.month, from: date))月"
    }
    private func monthHeader(_ group: EntryTimeline.Month, hide: Bool) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack { monthButton(group.date); Spacer(minLength: 8); monthTotal(group, hide: hide) }
            VStack(alignment: .leading, spacing: 4) { monthButton(group.date); monthTotal(group, hide: hide) }
        }
    }
    private func monthButton(_ date: Date) -> some View {
        Button {
            pickerYear = Dates.calendar.component(.year, from: date); pickerMonth = Dates.calendar.component(.month, from: date); pickingMonth = true
        } label: {
            HStack(spacing: 4) {
                Text(monthTitle(date)).yubaiFont(YubaiFont.callout, weight: .semibold)
                if !showingSearch { Image(systemName: "chevron.down").yubaiFont(YubaiFont.meta) }
            }.fixedSize().yubaiHitTarget(alignment: .leading)
        }.buttonStyle(PressButtonStyle()).accessibilityIdentifier("entriesMonth")
    }
    @ViewBuilder private func monthTotal(_ group: EntryTimeline.Month, hide: Bool) -> some View {
        if showingSearch { AmountLabel(cents: group.income - group.spending, hide: hide, role: .day) }
        else {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 4) { monthSpending(group, hide: hide); Text("·"); monthIncome(group, hide: hide) }.fixedSize()
                VStack(alignment: .leading, spacing: 4) { monthSpending(group, hide: hide); monthIncome(group, hide: hide) }
            }.yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
        }
    }
    private func monthSpending(_ group: EntryTimeline.Month, hide: Bool) -> some View {
        HStack(spacing: 4) { Text("支出"); AmountLabel(cents: group.spending, hide: hide, role: .day) }.fixedSize()
    }
    private func monthIncome(_ group: EntryTimeline.Month, hide: Bool) -> some View {
        HStack(spacing: 4) { Text("收入"); AmountLabel(cents: group.income, hide: hide, role: .day, ink: YubaiColor.brandInk) }.fixedSize()
    }
    private var cycleDivider: some View {
        let start = store.funds.cycleStart
        let previous = Finance.cycle(in: store.current, now: start.addingTimeInterval(-0.001))
        let title = "上一期 · " + FixedFlowPresentation.monthDay(previous.start) + " – " + FixedFlowPresentation.monthDay(Dates.addDays(-1, to: start))
        return HStack(spacing: 8) {
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
    private func entryRow(_ entry: EntryTimeline.Row, hideAmounts: Bool, searchResult: Bool = false) -> some View {
        LedgerEntryRow(entry: entry, note: searchResult ? searchNote(entry) : noteText(entry), hideAmounts: hideAmounts, isFresh: store.freshEntryIDs.contains(entry.id), showsSearchContext: searchResult)
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            .listRowBackground(YubaiColor.paperSheet).listRowSeparatorTint(YubaiColor.separator)
    }
    private func searchNote(_ row: EntryTimeline.Row) -> String {
        guard let entry = store.entriesByID[row.id] else { return noteText(row) }
        return FixedFlowPresentation.monthDay(entry.date) + " · " + store.accountName(entry.accountID)
    }
    private func dayTotal(_ day: EntryTimeline.Day, hide: Bool) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 4) { daySpending(day, hide: hide); if day.income > 0 { Text("·"); dayIncome(day, hide: hide) } }.fixedSize()
            VStack(alignment: .leading, spacing: 4) { daySpending(day, hide: hide); if day.income > 0 { dayIncome(day, hide: hide) } }
        }.yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
    }
    private func daySpending(_ day: EntryTimeline.Day, hide: Bool) -> some View {
        HStack(spacing: 4) { if day.income > 0 { Text("支出") }; AmountLabel(cents: day.income > 0 ? day.spending : -day.spending, hide: hide, role: .day) }.fixedSize()
    }
    private func dayIncome(_ day: EntryTimeline.Day, hide: Bool) -> some View {
        HStack(spacing: 4) { Text("收入"); AmountLabel(cents: day.income, hide: hide, role: .day, ink: YubaiColor.brandInk) }.fixedSize()
    }
    private func noteText(_ row: EntryTimeline.Row) -> String {
        guard let purpose = store.manualNotePurposes[row.id] else { return row.note }
        return purpose == row.categoryName ? "" : purpose
    }
    private var filters: some View {
        ChipFlow {
            ForEach(EntryTimeline.Filter.allCases, id: \.self) { choice in
                Button { filter = choice } label: {
                    Text(choice.rawValue).yubaiFont(YubaiFont.callout, weight: filter == choice ? .medium : .regular)
                        .foregroundStyle(filter == choice ? YubaiColor.canvas : YubaiColor.label)
                        .padding(.horizontal, 16).frame(minHeight: 32)
                        .background(filter == choice ? YubaiColor.label : YubaiColor.raised, in: Capsule())
                        .frame(minHeight: YubaiSize.tapMin).contentShape(Rectangle())
                }.buttonStyle(PressButtonStyle()).accessibilityAddTraits(filter == choice ? .isSelected : [])
                    .accessibilityIdentifier("entriesFilter_" + choice.rawValue)
            }
        }.accessibilityElement(children: .contain).accessibilityLabel("筛选账目")
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
    let note: String
    let hideAmounts: Bool
    let isFresh: Bool
    var showsSearchContext = false
    var body: some View {
        Button { store.sheetSource = nil; store.sheet = .editEntry(entry.id) } label: { content }
            .buttonStyle(.plain).accessibilityIdentifier("ledgerEntry_" + entry.id.uuidString)
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button { delete(systemFeedback: true) } label: { Text("删掉").foregroundStyle(YubaiColor.amberInk) }
                    .tint(YubaiColor.amberTint).accessibilityIdentifier("deleteLedgerEntry_" + entry.id.uuidString)
            }
            .contextMenu {
                Button("改一笔", systemImage: "square.and.pencil") { store.sheet = .editEntry(entry.id) }
                Button("再记一笔一样的", systemImage: "plus") { duplicate() }
                Button("删掉", systemImage: "trash") { delete() }
            }
            .accessibilityAction(named: "删掉") { delete() }
            .task(id: isFresh) {
                guard isFresh, YubaiMotion.claim("new-row-" + entry.id.uuidString) else { highlighted = false; return }
                withAnimation(YubaiMotion.wash(reduceMotion: reduceMotion)) { highlighted = false }
            }
    }
    private var savedEntry: Entry? { store.entriesByID[entry.id] }
    private var restraint: ProfileArea? {
        guard let savedEntry, savedEntry.nature == .expense else { return nil }
        return store.profile.restrain.first { ButlerCards.matches($0, entry: savedEntry, ledger: store.current) }
    }
    private var subtitle: String {
        var parts = [entry.categoryName]
        if showsSearchContext && !note.isEmpty { parts.append(note) }
        else if let savedEntry, savedEntry.title != savedEntry.displayTitle { parts.append(savedEntry.title) }
        if let area = restraint, let savedEntry {
            let week = ButlerCards.calendar.dateInterval(of: .weekOfYear, for: savedEntry.date)!.start
            let stamp = savedEntry.recordedAt ?? savedEntry.date
            let count = store.current.activeEntries.filter { row in
                guard row.nature == .expense, row.date >= week, row.date <= savedEntry.date,
                      ButlerCards.matches(area, entry: row, ledger: store.current) else { return false }
                if row.date < savedEntry.date { return true }
                let other = row.recordedAt ?? row.date
                return other < stamp || (other == stamp && row.id.uuidString <= savedEntry.id.uuidString)
            }.count
            parts.append("本周第 \(count) 次")
        }
        return parts.joined(separator: " · ")
    }
    private func duplicate() {
        guard let saved = store.entriesByID[entry.id] else { return }
        store.sheetSource = nil; store.sheet = .prefilledEntry(QuickEntryPrefill(entry: saved))
    }
    private var content: some View {
        HStack(spacing: YubaiSpace.gapGroup) {
            Image(systemName: entry.uncategorized ? "questionmark" : entry.symbol).yubaiFont(YubaiFont.tabIcon)
                .foregroundStyle(entry.uncategorized ? YubaiColor.amberInk : entry.inflow ? YubaiColor.brandInk : YubaiColor.labelMuted)
                .frame(width: YubaiSize.rowIcon, height: YubaiSize.rowIcon)
                .background(entry.uncategorized ? YubaiColor.amberTint : entry.inflow ? YubaiColor.brandTint : YubaiColor.paperInset,
                            in: RoundedRectangle(cornerRadius: YubaiRadius.control)).accessibilityHidden(true)
            let layout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: YubaiSpace.space4)) : AnyLayout(HStackLayout(spacing: YubaiSpace.space8))
            layout {
                VStack(alignment: .leading, spacing: YubaiSpace.space4) {
                    ChipFlow(rowSpacing: 4) {
                        Text(savedEntry?.displayTitle ?? entry.categoryName).yubaiFont(YubaiFont.rowTitle).foregroundStyle(YubaiColor.label)
                        if entry.intoFixedSavings {
                            Label("存着不动", systemImage: "lock").yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.brandInk)
                                .padding(.horizontal, 6).frame(minHeight: 20).background(YubaiColor.brandTint, in: Capsule()).fixedSize()
                        }
                        if restraint != nil { Circle().fill(YubaiColor.amberDot).frame(width: 6, height: 6).accessibilityHidden(true) }
                    }
                    Text(subtitle).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
                AmountLabel(cents: entry.amount, hide: hideAmounts,
                            sign: entry.inflow ? .inflow : .outflow, ink: entry.inflow ? YubaiColor.brandInk : YubaiColor.label)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }.padding(.vertical, YubaiSpace.space4).frame(maxWidth: .infinity, minHeight: note.isEmpty ? YubaiSize.rowSingle : YubaiSize.rowDouble).contentShape(Rectangle())
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
