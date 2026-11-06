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
    @FocusState private var searchFocused: Bool
    var body: some View {
        let timeline = store.entryTimeline(month: month, search: search, filter: filter)
        let hideAmounts = store.preferences.hideAmounts
        List {
            VStack(spacing: YubaiSpace.gapGroup) {
                monthPicker
                if showingSearch { searchField }
                if searching {
                    HStack {
                        Text("全部月份 · \(timeline.count) 笔").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                        Spacer()
                        AmountLabel(cents: timeline.income - timeline.spending, hide: hideAmounts)
                    }.accessibilityIdentifier("entriesSearchTotal")
                } else {
                    HStack(spacing: YubaiSpace.gapGroup) {
                        total("本月支出", cents: timeline.spending)
                        total("本月收入", cents: timeline.income, inflow: true)
                    }
                    filters
                }
            }.listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 12, trailing: 0)).listRowBackground(Color.clear).listRowSeparator(.hidden)
            if timeline.days.isEmpty {
                EmptyState("list.bullet.rectangle", searching ? "没有找到这笔" : filter == .all ? "这个月还没有账目" : "还没有这类账目",
                           action: searching ? "清空搜索" : "记一笔", onAction: { if searching { search = "" } else { store.sheet = .addEntry } })
                    .listRowBackground(Color.clear).listRowSeparator(.hidden)
            }
            if searching {
                ForEach(timeline.months) { group in
                    Section {
                        ForEach(group.days.flatMap(\.entries)) { entry in entryRow(entry, hideAmounts: hideAmounts, searchResult: true) }
                    } header: {
                        HStack {
                            Text(monthTitle(group.date)).yubaiFont(YubaiFont.row, weight: .semibold)
                            Spacer()
                            AmountLabel(cents: group.income - group.spending, hide: hideAmounts, role: .day)
                        }.textCase(nil).padding(.top, 12)
                    }
                }
            } else {
                ForEach(timeline.days) { day in
                    Section {
                        ForEach(day.entries) { entry in entryRow(entry, hideAmounts: hideAmounts) }
                    } header: {
                        ViewThatFits(in: .horizontal) {
                            HStack { Text(dayLabel(day.date)).yubaiFont(YubaiFont.row, weight: .semibold); Spacer(); dayTotal(day, hide: hideAmounts) }
                            VStack(alignment: .leading, spacing: 4) { Text(dayLabel(day.date)).yubaiFont(YubaiFont.row, weight: .semibold); dayTotal(day, hide: hideAmounts) }
                        }.textCase(nil).padding(.top, 12)
                    }
                }
            }
        }
            #if os(iOS)
            .listStyle(.insetGrouped).listSectionSpacing(12)
            #else
            .listStyle(.inset)
            #endif
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, YubaiSize.rowDouble)
            .scrollDismissesKeyboard(.interactively).amountPrivacy(hideAmounts).accessibilityIdentifier("entriesScroll")
            .rootScrollContentMargins()
            .rootTabScroll(.entries)
            .rootPageHeader { TabRootHeader(title: "账目") }
            .navigationTitle("账目").yubaiNavigation()
            .onChange(of: store.entryFilterRequest, initial: true) { _, request in
                guard request != nil else { return }
                filter = .uncategorized; search = ""; showingSearch = false
                month = Dates.calendar.dateInterval(of: .month, for: store.entryFilterDate ?? Date())!.start
            }
            #if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
            #endif
            .sheet(isPresented: $pickingMonth) {
                VStack(spacing: 12) {
                    ManualSheetHeader(title: "月份", actionTitle: "好", cancel: { pickingMonth = false }, action: {
                        month = Dates.calendar.date(from: DateComponents(year: pickerYear, month: pickerMonth, day: 1))!; pickingMonth = false
                    })
                    HStack(spacing: 0) {
                        Picker("年", selection: $pickerYear) { ForEach(monthYears, id: \.self) { Text("\($0) 年").tag($0) } }
                        Picker("月", selection: $pickerMonth) { ForEach(1...12, id: \.self) { Text("\($0) 月").tag($0) } }
                    }
                    #if os(iOS)
                    .pickerStyle(.wheel)
                    #endif
                }.padding(.horizontal, 20).yubaiSheetBackground().presentationDetents([.height(300)])
            }
    }
    private var searching: Bool { !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var monthYears: ClosedRange<Int> {
        let years = store.sortedEntries.map { Dates.calendar.component(.year, from: $0.date) }
        let year = Dates.calendar.component(.year, from: Date())
        return min(years.min() ?? year, year - 2)...max(years.max() ?? year, year + 1)
    }
    private func monthTitle(_ date: Date) -> String { "\(Dates.calendar.component(.year, from: date)) 年 \(Dates.calendar.component(.month, from: date)) 月" }
    private func entryRow(_ entry: EntryTimeline.Row, hideAmounts: Bool, searchResult: Bool = false) -> some View {
        LedgerEntryRow(entry: entry, note: searchResult ? searchNote(entry) : noteText(entry), hideAmounts: hideAmounts, isFresh: store.freshEntryIDs.contains(entry.id))
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            .listRowBackground(YubaiColor.paperSheet).listRowSeparatorTint(YubaiColor.separator)
    }
    private func searchNote(_ row: EntryTimeline.Row) -> String {
        guard let entry = store.entriesByID[row.id] else { return noteText(row) }
        return ManualBookkeeping.dayLabel(entry.date) + " · " + store.accountName(entry.accountID)
    }
    @ViewBuilder private func dayTotal(_ day: EntryTimeline.Day, hide: Bool) -> some View {
        HStack(spacing: 4) {
            if day.income > 0 {
                Text("支出").yubaiFont(YubaiFont.caption)
                AmountLabel(cents: day.spending, hide: hide)
                Text("· 收入").yubaiFont(YubaiFont.caption)
                AmountLabel(cents: day.income, hide: hide, ink: YubaiColor.brandInk)
            } else { AmountLabel(cents: -day.spending, hide: hide, role: .day) }
        }.fixedSize().foregroundStyle(YubaiColor.labelSecondary)
    }
    private func noteText(_ row: EntryTimeline.Row) -> String {
        guard let purpose = store.manualNotePurposes[row.id] else { return row.note }
        return purpose == row.categoryName ? "" : purpose
    }
    private var monthTitleButton: some View {
        Button {
            pickerYear = Dates.calendar.component(.year, from: month); pickerMonth = Dates.calendar.component(.month, from: month); pickingMonth = true
        } label: { Text(monthTitle(month)).fixedSize().yubaiFont(YubaiFont.navTitle) }.accessibilityIdentifier("entriesMonth")
    }
    private var previousMonthButton: some View {
        Button { changeMonth(-1) } label: { Image(systemName: "chevron.left").yubaiPageArrowTarget(edge: .leading) }
            .accessibilityLabel("上个月").accessibilityIdentifier("entriesPreviousMonth")
    }
    private var nextMonthButton: some View {
        Button { changeMonth(1) } label: { Image(systemName: "chevron.right").yubaiHitTarget() }
            .accessibilityLabel("下个月").accessibilityIdentifier("entriesNextMonth")
    }
    @ViewBuilder private var currentMonthButton: some View {
        if !Dates.calendar.isDate(month, equalTo: Date(), toGranularity: .month) {
            Button("本月") { month = Dates.calendar.dateInterval(of: .month, for: Date())!.start }
                .yubaiFont(YubaiFont.callout, weight: .medium).foregroundStyle(YubaiColor.brandInk)
                .padding(.horizontal, 14).frame(minHeight: 32).background(YubaiColor.raised, in: Capsule()).fixedSize()
        }
    }
    private var searchToggleButton: some View {
        Button {
            withAnimation(YubaiMotion.layout(reduceMotion: reduceMotion)) { showingSearch.toggle() }
            searchFocused = showingSearch
            if !showingSearch { search = "" }
        } label: {
            Image(systemName: showingSearch ? "xmark" : "magnifyingglass")
                .frame(width: YubaiSize.iconButton, height: YubaiSize.iconButton)
                .controlSurface(in: Circle()).yubaiHitTarget(alignment: .trailing)
        }.accessibilityLabel(showingSearch ? "关闭搜索" : "搜索账目").accessibilityIdentifier("entriesSearchButton")
    }
    private var monthPicker: some View {
        Group {
            if textSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    monthTitleButton
                    HStack(spacing: 4) { previousMonthButton; nextMonthButton; currentMonthButton; Spacer(minLength: 0); searchToggleButton }
                }
            } else {
                HStack(spacing: 4) { previousMonthButton; monthTitleButton; nextMonthButton; currentMonthButton; Spacer(minLength: 0); searchToggleButton }
            }
        }.yubaiFont(YubaiFont.row).foregroundStyle(YubaiColor.label).buttonStyle(PressButtonStyle())
    }
    private var searchField: some View {
        HStack(spacing: YubaiSpace.space8) {
            Image(systemName: "magnifyingglass").foregroundStyle(YubaiColor.labelSecondary).accessibilityHidden(true)
            TextField("搜索", text: $search).yubaiFont(YubaiFont.row).focused($searchFocused)
                .accessibilityLabel("搜索账目").accessibilityHint("可按用途、分类或金额搜索").accessibilityIdentifier("entriesSearch")
        }.padding(.horizontal, YubaiSpace.insetCard).frame(minHeight: YubaiSize.tapMin)
            .background(YubaiColor.raised, in: Capsule())
    }
    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: YubaiSpace.space8) {
                ForEach(EntryTimeline.Filter.allCases, id: \.self) { choice in
                    Button { filter = choice } label: {
                        Text(choice.rawValue).yubaiFont(YubaiFont.callout, weight: filter == choice ? .medium : .regular)
                            .foregroundStyle(filter == choice ? YubaiColor.canvas : YubaiColor.label)
                            .padding(.horizontal, YubaiSpace.insetCard).frame(minHeight: YubaiSize.chipHeight)
                            .background(filter == choice ? YubaiColor.label : YubaiColor.raised, in: Capsule())
                            .frame(minHeight: YubaiSize.tapMin).contentShape(Rectangle())
                    }.buttonStyle(PressButtonStyle()).accessibilityAddTraits(filter == choice ? .isSelected : [])
                        .accessibilityIdentifier("entriesFilter_" + choice.rawValue)
                }
            }
        }.pageLocalHorizontalGestures()
            #if os(iOS)
            .contentMargins(.bottom, YubaiSpace.none, for: .scrollContent)
            #endif
            .accessibilityElement(children: .contain).accessibilityLabel("筛选账目")
    }
    private func total(_ title: String, cents: Int64, inflow: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: YubaiSpace.space4) {
            Text(title).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
            AmountLabel(cents: cents, hide: store.preferences.hideAmounts, role: .donut,
                        sign: inflow ? .inflow : .automatic,
                        ink: inflow ? YubaiColor.brandInk : YubaiColor.label)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(YubaiSpace.insetCard)
            .paperCardSurface(in: RoundedRectangle(cornerRadius: YubaiRadius.row))
    }
    private func changeMonth(_ offset: Int) { searchFocused = false; month = Dates.addMonths(offset, to: month) }
    private func dayLabel(_ date: Date) -> String {
        let label = ManualBookkeeping.dayLabel(date)
        if label == "今天" || label == "昨天" { return label }
        return label + " " + date.formatted(.dateTime.weekday(.abbreviated).locale(Locale(identifier: "zh_CN")))
    }
}

private struct LedgerEntryRow: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var highlighted = true
    let entry: EntryTimeline.Row
    let note: String
    let hideAmounts: Bool
    let isFresh: Bool
    var body: some View {
        Button { store.sheetSource = nil; store.sheet = .editEntry(entry.id) } label: { content }
            .buttonStyle(.plain).accessibilityIdentifier("ledgerEntry_" + entry.id.uuidString)
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(action: delete) { Text("删掉").foregroundStyle(YubaiColor.amberInk) }
                    .tint(YubaiColor.amberTint).accessibilityIdentifier("deleteLedgerEntry_" + entry.id.uuidString)
            }
            .contextMenu {
                Button("改一笔", systemImage: "square.and.pencil") { store.sheet = .editEntry(entry.id) }
                Button("再记一笔一样的", systemImage: "plus") { duplicate() }
                Button("删掉", systemImage: "trash", action: delete)
            }
            .accessibilityAction(named: "删掉", delete)
            .task(id: isFresh) {
                guard isFresh, YubaiMotion.claim("new-row-" + entry.id.uuidString) else { highlighted = false; return }
                withAnimation(YubaiMotion.wash(reduceMotion: reduceMotion)) { highlighted = false }
            }
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
                    Text(entry.categoryName).yubaiFont(YubaiFont.rowTitle).foregroundStyle(YubaiColor.label)
                    if !note.isEmpty { Text(note).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary) }
                }.lineLimit(textSize.isAccessibilitySize ? nil : 1).frame(maxWidth: .infinity, alignment: .leading)
                AmountLabel(cents: entry.amount, hide: hideAmounts,
                            sign: entry.inflow ? .inflow : .outflow, ink: entry.inflow ? YubaiColor.brandInk : YubaiColor.label)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }.padding(.vertical, YubaiSpace.space4).frame(maxWidth: .infinity, minHeight: note.isEmpty ? YubaiSize.rowSingle : YubaiSize.rowDouble).contentShape(Rectangle())
            .background(isFresh && highlighted ? YubaiColor.brandTint : YubaiColor.paperSheet)
    }
    private func delete() {
        store.update("删掉") { ledger in
            guard let index = ledger.entries.firstIndex(where: { $0.id == entry.id && $0.deletedAt == nil }) else { return }
            ledger.entries[index].deletedAt = Date()
        }
    }
}
