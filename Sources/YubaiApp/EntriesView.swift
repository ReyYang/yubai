import SwiftUI
import YubaiCore

/// 账本「账目」：常驻搜索、筛选、按月按天的流水。根页的页头和「账目 / 去向」切换由 `LedgerTabView` 提供。
struct EntriesView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.yubaiReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var textSize
    @Binding var request: LedgerPreset?
    @State private var month = Dates.calendar.dateInterval(of: .month, for: Dates.now)!.start
    @State private var filter = EntryTimeline.Filter.all
    @State private var search = ""
    @State private var searchExpanded = false
    @State private var showsFilters = false
    @State private var savedOffset = CGFloat.zero
    @State private var currentOffset = CGFloat.zero
    #if os(iOS)
    @State private var position = ScrollPosition(edge: .top)
    #endif
    @State private var scope: DateInterval?
    @State private var entryIDsScope: Set<UUID>?
    @State private var categoryScope: String?
    @State private var categoryTimeline: EntryTimeline.Snapshot?
    @State private var pickingMonth = false
    @State private var pickerYear = Dates.calendar.component(.year, from: Dates.now)
    @State private var pickerMonth = Dates.calendar.component(.month, from: Dates.now)
    @State private var scrollMonth: Date?
    @State private var scrollToTop = false
    @State private var categoryTarget: CategoryTarget?
    @FocusState private var searchFocused: Bool

    init(request: Binding<LedgerPreset?> = .constant(nil)) {
        _request = request
    }
    private struct CategoryTarget: Identifiable { let id: UUID }
    private enum RowContext { case day, search, uncategorized }
    private var searching: Bool { searchExpanded || !search.isEmpty }

    var body: some View {
        // Cached once per ledger revision/query. List creates the display rows
        // lazily, including when thousands of entries span many months.
        let base = store.entryTimeline(month: month, search: search, filter: filter, allMonths: true)
        let timeline = categoryScope == nil && entryIDsScope == nil ? base : categoryTimeline ?? base
        let hideAmounts = store.preferences.hideAmounts
        let groups = scoped(displayMonths(timeline))
        ScrollViewReader { proxy in
            List {
                if (categoryScope != nil || entryIDsScope != nil) && categoryTimeline == nil {
                    ProgressView().listRowBackground(Color.clear).listRowSeparator(.hidden)
                } else {
                    headerBlock(groups: groups, categories: showsFilters || searching ? filterCategories(base) : [], hide: hideAmounts)
                        .id("entriesTop")
                        .listRowInsets(EdgeInsets(top: YubaiSpace.none, leading: YubaiSpace.none, bottom: YubaiSpace.space12, trailing: YubaiSpace.none))
                        .listRowBackground(Color.clear).listRowSeparator(.hidden)
                    if groups.allSatisfy({ $0.days.isEmpty }) { emptyRow }
                    else { monthRows(groups, hide: hideAmounts) }
                }
            }
            #if os(iOS)
            .listStyle(.insetGrouped).listSectionSpacing(YubaiSpace.space12)
            .contentMargins(.horizontal, YubaiSpace.insetPage, for: .scrollContent)
            #else
            .listStyle(.inset)
            #endif
            .scrollContentBackground(.hidden).contentMargins(.top, 0, for: .scrollContent)
            .environment(\.defaultMinListRowHeight, 0)
            .scrollDismissesKeyboard(.interactively).amountPrivacy(hideAmounts).accessibilityIdentifier("entriesScroll")
            .rootScrollContentMargins(for: .ledger)
            .coordinateSpace(name: "ledgerTimeline")
            #if os(iOS)
            .scrollPosition($position)
            .deferredScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.y }) { currentOffset = $0 }
            #endif
            .rootPageHeader { topBar.accessibilityHidden(store.destination != .ledger) }
            .onChange(of: store.rootScrollRequest[.ledger]) { _, _ in
                searchExpanded = false; searchFocused = false; search = ""; filter = .all; showsFilters = false
                scope = nil; entryIDsScope = nil; categoryScope = nil; categoryTimeline = nil
                month = Dates.calendar.dateInterval(of: .month, for: store.financialNow)!.start
                proxy.scrollTo("entriesTop", anchor: .top)
            }
            .onChange(of: scrollToTop) { _, value in
                guard value else { return }
                proxy.scrollTo("entriesTop", anchor: .top); scrollToTop = false
            }
            .onChange(of: store.receiptFeedbackTrigger) { _, _ in
                guard !store.receiptEntryIDs.isEmpty else { return }
                searchFocused = false; searchExpanded = false; search = ""; filter = .all; showsFilters = false
                scope = nil; entryIDsScope = nil; categoryScope = nil; categoryTimeline = nil
                scrollToTop = true
            }
            .onChange(of: scrollMonth) { _, value in
                guard let value else { return }
                withAnimation(YubaiMotion.layout(reduceMotion: reduceMotion)) { proxy.scrollTo("month-" + Dates.text(value), anchor: .top) }
                scrollMonth = nil
            }
            .onChange(of: store.entryFilterRequest, initial: true) { _, pending in
                guard pending != nil else { return }
                filter = .uncategorized; endSearch()
                jump(to: store.entryFilterDate ?? Dates.now)
            }
            .onChange(of: request, initial: true) { _, value in applyRequest(value) }
            .task(id: categoryQuery) { await refreshCategoryTimeline() }
            .sheet(isPresented: $pickingMonth) { monthSheet }
            .sheet(item: $categoryTarget) { target in categorySheet(target.id) }
        }
    }

    // MARK: 页首

    private var isScoped: Bool { scope != nil || entryIDsScope != nil || categoryScope != nil || categoryTimeline != nil }
    @ViewBuilder private func headerBlock(groups: [EntryTimeline.Month], categories: [String], hide: Bool) -> some View {
        VStack(alignment: .leading, spacing: YubaiSpace.space8) {
            if !searching && !showsFilters && filter == .all && !isScoped {
                LedgerHomeHeader(model: LedgerHomeModel.make(store))
            }
            if isScoped || filter != .all { scopeBar }
            if searching || showsFilters { filters(categories) }
            summary(groups, hide: hide)
        }.padding(.top, YubaiSpace.space20)
    }
    /// Any jump into a narrowed ledger (formula rows, category pages, filters)
    /// keeps one visible way back to every entry.
    private var scopeBar: some View {
        HStack(spacing: YubaiSpace.space8) {
            if let categoryScope {
                Button { clearCategory() } label: {
                    Label(Classification.displayCategory(categoryScope), systemImage: "xmark.circle")
                        .yubaiFont(YubaiFont.callout).frame(minHeight: YubaiSize.tapMin).contentShape(Rectangle())
                }.buttonStyle(PressButtonStyle()).accessibilityLabel("清掉分类筛选").accessibilityIdentifier("clearLedgerCategory")
            }
            if let title = scopeTitle ?? (categoryScope == nil ? "已筛选" : nil) {
                Text(title).yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary).lineLimit(1)
                    .accessibilityIdentifier("entriesScopeTitle")
            }
            Spacer(minLength: YubaiSpace.space8)
            Button { clearScope() } label: {
                Text("显示全部").yubaiFont(YubaiFont.callout, weight: .medium).foregroundStyle(YubaiColor.brandInk)
                    .fixedSize().yubaiHitTarget(alignment: .trailing)
            }.buttonStyle(PressButtonStyle()).accessibilityIdentifier("clearEntriesScope")
        }.padding(.horizontal, YubaiSpace.space4)
    }
    private var scopeTitle: String? {
        var parts: [String] = []
        if let scope { parts.append(NowFormat.range(scope.start, scope.end.addingTimeInterval(-1))) }
        if filter != .all { parts.append(filter.rawValue) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
    private func clearCategory() { categoryScope = nil; categoryTimeline = nil; scope = nil }
    private func clearScope() {
        scope = nil; entryIDsScope = nil; categoryScope = nil; categoryTimeline = nil; filter = .all; showsFilters = false
    }
    /// Spending categories present in the unscoped timeline, most used first.
    private func filterCategories(_ timeline: EntryTimeline.Snapshot) -> [String] {
        var counts: [String: Int] = [:]
        for row in timeline.months.lazy.flatMap(\.days).flatMap(\.entries) where !row.inflow && !row.uncategorized {
            guard let entry = store.entriesByID[row.id], entry.nature == .expense, !Classification.isPending(entry.category) else { continue }
            counts[entry.category, default: 0] += 1
        }
        var names = counts.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.map(\.key)
        if let categoryScope, !names.contains(categoryScope) { names.insert(categoryScope, at: 0) }
        return names
    }
    @ViewBuilder private var topBar: some View {
        if searching { searchField }
        else if textSize.isAccessibilitySize {
            HStack(spacing: YubaiSpace.space8) {
                AmountVisibilityButton()
                Spacer(minLength: YubaiSpace.none)
                monthButton(month)
                Spacer(minLength: YubaiSpace.none)
                searchButton
                filterButton
            }.frame(minHeight: YubaiSize.headerHeight)
        } else {
            // One button leading, two trailing: the month is centred on the
            // screen, not in the space left between them.
            HStack(spacing: YubaiSpace.space8) {
                AmountVisibilityButton()
                Spacer(minLength: YubaiSpace.none)
                searchButton
                filterButton
            }.frame(minHeight: YubaiSize.headerHeight)
                .overlay { monthButton(month) }
        }
    }
    private var searchButton: some View {
        HeaderIconButton {
            savedOffset = currentOffset; searchExpanded = true; scrollToTop = true
        } icon: { size in Image(systemName: "magnifyingglass").font(.system(size: size)) }
            .accessibilityLabel("搜索").accessibilityIdentifier("openLedgerSearch")
    }
    private var filterButton: some View {
        HeaderIconButton { showsFilters.toggle(); scrollToTop = true } icon: { size in Image(systemName: "line.3.horizontal.decrease").font(.system(size: size)) }
            .accessibilityLabel("筛选").accessibilityIdentifier("openLedgerFilters")
    }
    private var searchField: some View {
        SearchInput(text: $search, placeholder: "搜名字、金额、备注", identifier: "entriesSearch", label: "搜索账目",
                    focus: $searchFocused, autofocus: true, showsCancel: true, cancelIdentifier: "entriesSearchCancel", cancel: endSearch)
    }
    private func filters(_ categories: [String]) -> some View {
        VStack(alignment: .leading, spacing: YubaiSpace.space8) {
            ChipFlow {
                ForEach(EntryTimeline.Filter.allCases, id: \.self) { choice in
                    let selected = choice == .all ? filter == .all && !isScoped : filter == choice
                    Button {
                        // 「全部」also leaves any scope a jump left behind.
                        if choice == .all { clearScope(); showsFilters = true } else { filter = choice }
                    } label: { filterChipLabel(choice == .all ? "全部时间" : choice.rawValue, selected: selected) }
                        .buttonStyle(PressButtonStyle()).accessibilityAddTraits(selected ? .isSelected : [])
                        .accessibilityIdentifier("entriesFilter_" + choice.rawValue)
                }
            }
            if !categories.isEmpty {
                ChipFlow {
                    ForEach(categories, id: \.self) { name in
                        let selected = categoryScope == name
                        Button {
                            if selected { clearCategory() } else {
                                if filter == .income || filter == .uncategorized { filter = .all }
                                categoryScope = name; categoryTimeline = nil; entryIDsScope = nil
                            }
                        } label: { filterChipLabel(Classification.displayCategory(name), selected: selected) }
                            .buttonStyle(PressButtonStyle()).accessibilityAddTraits(selected ? .isSelected : [])
                            .accessibilityIdentifier("entriesCategory_" + name)
                    }
                }
            }
        }.accessibilityElement(children: .contain).accessibilityLabel("筛选账目")
    }
    private func filterChipLabel(_ title: String, selected: Bool) -> some View {
        Text(title).yubaiFont(YubaiFont.callout, weight: selected ? .medium : .regular)
            .fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(selected ? YubaiColor.canvas : YubaiColor.label)
            .padding(.horizontal, YubaiSpace.space16).frame(minHeight: YubaiSize.chipHeight)
            .background(selected ? YubaiColor.label : YubaiColor.raised, in: Capsule())
            .frame(minHeight: YubaiSize.tapMin).contentShape(Rectangle())
    }
    @ViewBuilder private func summary(_ groups: [EntryTimeline.Month], hide: Bool) -> some View {
        let days = groups.flatMap(\.days)
        let count = days.reduce(0) { $0 + $1.entries.count }
        let net = summaryNet(days)
        if searching || isScoped || (filter != .all && filter != .uncategorized) {
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
    /// Adjustments sit outside day income/spending; a list of only adjustments
    /// still totals to their signed sum rather than 0.00.
    private func summaryNet(_ days: [EntryTimeline.Day]) -> Int64 {
        let flow = days.reduce(Int64(0)) { $0 + $1.income - $1.spending }
        guard days.allSatisfy({ $0.income == 0 && $0.spending == 0 }) else { return abs(flow) }
        return days.flatMap(\.entries).reduce(Int64(0)) { total, row in
            switch store.entriesByID[row.id]?.nature {
            case .adjustmentIn?: total + row.amount
            case .adjustmentOut?: total - row.amount
            default: total
            }
        }
    }
    private func summaryLine(left: String, hide: Bool, net: Int64) -> some View {
        HStack {
            Text(left).yubaiFont(YubaiFont.callout, weight: .semibold).foregroundStyle(YubaiColor.labelSecondary)
                .accessibilityIdentifier("activeEntryCount")
            Spacer(minLength: YubaiSpace.space8)
            HStack(spacing: YubaiSpace.space4) { Text("共").yubaiFont(YubaiFont.callout); AmountLabel(cents: net, hide: hide, role: .small) }
                .fixedSize(horizontal: false, vertical: true).accessibilityElement(children: .combine).accessibilityIdentifier("entriesSearchTotal")
        }.padding(.horizontal, YubaiSpace.space4)
    }
    @ViewBuilder private var emptyRow: some View {
        if store.sortedEntries.allSatisfy({ $0.deletedAt != nil }) && search.isEmpty && !isScoped && filter == .all {
            EmptyState(.ledger, actionIdentifier: "emptyLedgerAdd", secondaryIdentifier: "emptyLedgerImport",
                       onAction: { store.requestCaptureSheet(.addEntry) }, onSecondary: { store.sheet = .imports })
                .listRowBackground(Color.clear).listRowSeparator(.hidden)
        } else {
            EmptyState(.search, title: search.isEmpty ? "没有找到" : "没有找到「\(search)」",
                       onAction: { searchFocused = false; searchExpanded = false; search = ""; clearScope() },
                       onSecondary: { clearScope(); scrollMonth = nil; month = Dates.calendar.dateInterval(of: .month, for: store.financialNow)!.start })
                .listRowBackground(Color.clear).listRowSeparator(.hidden)
        }
    }

    // MARK: 行

    @ViewBuilder private func monthRows(_ groups: [EntryTimeline.Month], hide: Bool) -> some View {
        ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
            if index == 0 && !group.days.isEmpty {
                Color.clear.frame(height: YubaiSize.separator).id("month-" + Dates.text(group.date))
                    .listRowInsets(EdgeInsets()).listRowBackground(Color.clear).listRowSeparator(.hidden).accessibilityHidden(true)
            }
            if index > 0 || group.days.isEmpty {
                monthHeader(group, hide: hide)
                    .id("month-" + Dates.text(group.date))
                    .listRowInsets(EdgeInsets(top: YubaiSpace.space12, leading: YubaiSpace.none, bottom: YubaiSpace.space4, trailing: YubaiSpace.none))
                    .listRowBackground(Color.clear).listRowSeparator(.hidden)
            }
            ForEach(group.days) { day in
                Section {
                    ForEach(day.entries) { entry in entryRow(entry, hide: hide, context: filter == .uncategorized ? .uncategorized : .day) }
                } header: {
                    dayHeader(day, hide: hide)
                        .deferredGeometryChange(for: CGFloat.self, of: { $0.frame(in: .named("ledgerTimeline")).minY }) { y in
                            if !searching && y >= 0 && y < YubaiSize.rowDouble { month = group.date }
                        }
                }.id(day.date)
            }
        }
    }
    /// The add button follows the date so day totals share the month totals' right edge.
    private func dayHeader(_ day: EntryTimeline.Day, hide: Bool) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: YubaiSpace.space8) {
                Text(dayLabel(day.date)).fixedSize(); dayAddButton(day)
                Spacer(minLength: YubaiSpace.space8); dayTotal(day, hide: hide)
            }
            VStack(alignment: .leading, spacing: YubaiSpace.space4) {
                HStack(spacing: YubaiSpace.space8) { Text(dayLabel(day.date)).fixedSize(); dayAddButton(day) }
                dayTotal(day, hide: hide)
            }
        }.yubaiFont(YubaiFont.callout, weight: .semibold).textCase(nil).padding(.top, YubaiSpace.space8)
    }
    private func dayAddButton(_ day: EntryTimeline.Day) -> some View {
            Button {
                store.requestCaptureSheet(.prefilledEntry(QuickEntryPrefill(category: nil, amount: nil, purpose: nil, date: day.date)))
            } label: {
                Image(systemName: "plus").yubaiFont(YubaiFont.callout, weight: .semibold)
                    .foregroundStyle(YubaiColor.brandInk).frame(width: YubaiSize.pillHeight, height: YubaiSize.pillHeight)
                    .controlSurface(in: Circle()).yubaiHitTarget()
            }.buttonStyle(PressButtonStyle()).accessibilityLabel("补记到" + FixedFlowPresentation.monthDay(day.date))
                .accessibilityIdentifier("addEntryOnDay_" + Dates.text(day.date))
    }
    private func entryRow(_ entry: EntryTimeline.Row, hide: Bool, context: RowContext) -> some View {
        LedgerEntryRow(entry: entry, subtitle: subtitle(entry, context), hideAmounts: hide, isFresh: store.freshEntryIDs.contains(entry.id),
                       onSortCategory: { categoryTarget = CategoryTarget(id: entry.id) })
            .listRowInsets(EdgeInsets(top: YubaiSpace.space4, leading: YubaiSpace.space16, bottom: YubaiSpace.space4, trailing: YubaiSpace.space16))
            .listRowBackground(YubaiColor.paperSheet).listRowSeparatorTint(YubaiColor.separator)
    }
    /// Category facts the title does not already show: an entry without a
    /// purpose is titled by its category, so only the subcategory remains.
    private func categoryText(_ row: EntryTimeline.Row, _ entry: Entry) -> String {
        let sub = entry.subcategory.flatMap { $0.isEmpty ? nil : $0 }
        let titledByCategory = entry.displayTitle == row.categoryName || entry.displayTitle == Classification.displayCategory(entry.category)
        if titledByCategory { return sub ?? "" }
        return sub.map { row.categoryName + " · " + $0 } ?? row.categoryName
    }
    private func joined(_ parts: String...) -> String { parts.filter { !$0.isEmpty }.joined(separator: " · ") }
    private func subtitle(_ row: EntryTimeline.Row, _ context: RowContext) -> String {
        guard let entry = store.entriesByID[row.id] else { return row.categoryName }
        switch context {
        case .search:
            return joined(FixedFlowPresentation.monthDay(entry.date), categoryText(row, entry))
        case .uncategorized:
            if let from = entry.spreadFrom {
                return FixedFlowPresentation.monthDay(from) + " – " + "\(Dates.calendar.component(.day, from: entry.date))日"
            }
            return FixedFlowPresentation.monthDay(entry.date) + " · " + store.accountName(entry.accountID)
        case .day:
            let several = store.accounts.count > 1
            let other = several && entry.accountID != ManualBookkeeping.defaultAccount(in: store.current)?.id
            return joined(categoryText(row, entry), other ? store.accountName(entry.accountID) : "")
        }
    }

    // MARK: 月份与日

    private var monthSheet: some View {
        VStack(spacing: YubaiSpace.gapGroup) {
            ManualSheetHeader(title: "月份", actionTitle: "好", cancel: { pickingMonth = false }, action: {
                if let date = Dates.calendar.date(from: DateComponents(year: pickerYear, month: pickerMonth, day: 1)) { jump(to: date) }
                pickingMonth = false
            })
            Menu {
                ForEach(monthYears, id: \.self) { year in
                    Button { pickerYear = year } label: {
                        if year == pickerYear { Label("\(year) 年", systemImage: "checkmark") }
                        else { Text(verbatim: "\(year) 年") }
                    }.accessibilityIdentifier("ledgerJumpYear_\(year)")
                }
            } label: {
                HStack(spacing: YubaiSpace.space8) {
                    Text(verbatim: "\(pickerYear) 年")
                    Image(systemName: "chevron.up.chevron.down").yubaiFont(YubaiFont.meta)
                }.yubaiFont(YubaiFont.row).frame(minHeight: YubaiSize.tapMin).contentShape(Rectangle()).yubaiHitTarget()
            }.buttonStyle(PressButtonStyle()).accessibilityLabel("年").accessibilityValue("\(pickerYear) 年")
                .accessibilityIdentifier("ledgerJumpYear")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: YubaiSpace.space8), count: 3), spacing: YubaiSpace.space8) {
                ForEach(1...12, id: \.self) { number in
                    Button("\(number)月") {
                        pickerMonth = number
                        if let date = Dates.calendar.date(from: DateComponents(year: pickerYear, month: number, day: 1)) { jump(to: date) }
                        pickingMonth = false
                    }.buttonStyle(NowCardButtonStyle(primary: number == pickerMonth))
                        .accessibilityIdentifier("ledgerJumpMonth_\(number)")
                }
            }
        }.padding(.horizontal, YubaiSpace.space20).frame(maxHeight: .infinity, alignment: .top)
            .yubaiSheetBackground().presentationDetents(textSize.isAccessibilitySize ? [.large] : [.height(YubaiSize.sheet480 + YubaiSpace.sheetHeaderTop)])
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
        search = value.search; searchExpanded = !value.search.isEmpty; showsFilters = true
        categoryScope = value.category; categoryTimeline = nil
        scope = value.interval
        entryIDsScope = value.entryIDs
        scrollToTop = true
        request = nil
    }
    private func jump(to date: Date) {
        month = Dates.calendar.dateInterval(of: .month, for: date)!.start
        // Scroll after List has received the target header (also for an empty month).
        Task { @MainActor in await Task.yield(); scrollMonth = month }
    }
    private func endSearch() {
        searchFocused = false; searchExpanded = false; search = ""; scope = nil; entryIDsScope = nil; categoryScope = nil; categoryTimeline = nil
        #if os(iOS)
        Task { @MainActor in await Task.yield(); position.scrollTo(y: savedOffset) }
        #endif
    }
    private var categoryQuery: String { "\(store.ledgerRevision)-\(store.financialNow)-\(categoryScope ?? "")-\(String(describing: entryIDsScope))-\(String(describing: scope))-\(search)-\(filter.rawValue)-\(month)" }
    @MainActor private func refreshCategoryTimeline() async {
        guard categoryScope != nil || entryIDsScope != nil else { categoryTimeline = nil; return }
        let categoryScope = categoryScope; let ids = entryIDsScope
        let ledger = store.current; let at = store.financialNow; let interval = scope
        let query = search; let filter = filter; let month = month
        let value = await Task.detached(priority: .userInitiated) {
            let lookup = Dictionary(uniqueKeysWithValues: ledger.entries.map { ($0.id, $0) })
            let category = categoryScope.map { ledger.resolveCategory($0, income: false) }
            let rows = ledger.entries.filter { entry in
                guard entry.deletedAt == nil, entry.date <= at else { return false }
                if let ids { return ids.contains(entry.id) }
                guard entry.nature == .expense || entry.nature == .refund else { return false }
                if let interval, entry.date < interval.start || entry.date >= interval.end { return false }
                let source = entry.relatedEntryID.flatMap { lookup[$0] } ?? entry
                if categoryScope == Reconciliation.unitemizedTitle { return source.isUnitemized && Classification.isPending(source) }
                return ledger.normalizedCategory(for: entry, entriesByID: lookup).category == category
            }.sorted { $0.date > $1.date }
            return EntryTimeline.snapshot(sortedEntries: rows, ledger: ledger, month: month, search: query, filter: filter, allMonths: true)
        }.value
        guard !Task.isCancelled else { return }
        categoryTimeline = value
    }
    private var monthYears: ClosedRange<Int> {
        let years = store.sortedEntries.map { Dates.calendar.component(.year, from: $0.date) }
        let year = Dates.calendar.component(.year, from: Dates.now)
        return min(years.min() ?? year, year - 2)...max(years.max() ?? year, year + 1)
    }
    private func monthTitle(_ date: Date) -> String {
        if !Dates.calendar.isDate(date, equalTo: Dates.now, toGranularity: .year) {
            return "\(Dates.calendar.component(.year, from: date)) 年 \(Dates.calendar.component(.month, from: date)) 月"
        }
        return "\(Dates.calendar.component(.month, from: date))月"
    }
    private func monthHeader(_ group: EntryTimeline.Month, hide: Bool) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack { Text(monthTitle(group.date)).yubaiFont(YubaiFont.month); Spacer(minLength: YubaiSpace.space8); monthTotal(group, hide: hide) }
            VStack(alignment: .leading, spacing: YubaiSpace.space4) { Text(monthTitle(group.date)).yubaiFont(YubaiFont.month); monthTotal(group, hide: hide) }
        }
    }
    private func monthButton(_ date: Date) -> some View {
        Button {
            pickerYear = Dates.calendar.component(.year, from: date); pickerMonth = Dates.calendar.component(.month, from: date); pickingMonth = true
        } label: {
            HStack(spacing: YubaiSpace.space4) {
                Text(monthTitle(date)).yubaiFont(YubaiFont.callout, weight: .semibold).accessibilityIdentifier("rootHeaderTitle")
                Image(systemName: "chevron.down").yubaiFont(YubaiFont.meta)
            }.fixedSize().yubaiHitTarget()
        }.buttonStyle(PressButtonStyle())
            .accessibilityIdentifier(Dates.day(date) == Dates.day(month) ? "entriesMonth" : "entriesMonth_" + Dates.text(date))
    }
    private func monthTotal(_ group: EntryTimeline.Month, hide: Bool) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: YubaiSpace.space4) { monthSpending(group, hide: hide); Text("·"); monthIncome(group, hide: hide) }.fixedSize()
            VStack(alignment: .leading, spacing: YubaiSpace.space4) { monthSpending(group, hide: hide); monthIncome(group, hide: hide) }
        }.yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
    }
    private func monthSpending(_ group: EntryTimeline.Month, hide: Bool) -> some View {
        AdaptiveValueRow(spreadsValue: false) { Text("支出") } value: { AmountLabel(cents: group.spending, hide: hide, role: .small, sign: .none) }
    }
    private func monthIncome(_ group: EntryTimeline.Month, hide: Bool) -> some View {
        AdaptiveValueRow(spreadsValue: false) { Text("收入") } value: { AmountLabel(cents: group.income, hide: hide, role: .small, sign: .none, ink: YubaiColor.brandInk) }
    }
    private func dayTotal(_ day: EntryTimeline.Day, hide: Bool) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: YubaiSpace.space4) { daySpending(day, hide: hide); if day.income > 0 { Text("·"); dayIncome(day, hide: hide) } }.fixedSize()
            VStack(alignment: .leading, spacing: YubaiSpace.space4) { daySpending(day, hide: hide); if day.income > 0 { dayIncome(day, hide: hide) } }
        }.yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
    }
    private func daySpending(_ day: EntryTimeline.Day, hide: Bool) -> some View {
        HStack(spacing: YubaiSpace.space4) { if day.income > 0 { Text("支出") }; AmountLabel(cents: day.income > 0 ? day.spending : -day.spending, hide: hide, role: .small) }.fixedSize()
    }
    private func dayIncome(_ day: EntryTimeline.Day, hide: Bool) -> some View {
        HStack(spacing: YubaiSpace.space4) { Text("收入"); AmountLabel(cents: day.income, hide: hide, role: .small, ink: YubaiColor.brandInk) }.fixedSize()
    }
    private func dayLabel(_ date: Date) -> String {
        let label = ManualBookkeeping.dayLabel(date)
        if label == "今天" || label == "昨天" { return label + " · " + FixedFlowPresentation.monthDay(date) }
        return FixedFlowPresentation.monthDay(date)
    }
}

struct LedgerEntryRow: View {
    @Environment(AppStore.self) private var store
    @Environment(\.yubaiReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var highlighted = true
    @State private var acknowledged = false
    let entry: EntryTimeline.Row
    let subtitle: String
    let hideAmounts: Bool
    let isFresh: Bool
    var onSortCategory: () -> Void = {}
    var body: some View {
        entryButton
            .buttonStyle(.plain).accessibilityIdentifier("ledgerEntry_" + entry.id.uuidString)
            .accessibilityValue(isFuture ? "未来" : acknowledged ? "已记下" : "")
            .nativeSwipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button { delete(systemFeedback: true) } label: { Text("删掉").foregroundStyle(YubaiColor.white) }
                    .tint(YubaiColor.swipeDelete).accessibilityIdentifier("deleteLedgerEntry_" + entry.id.uuidString)
                Button(action: onSortCategory) { Text("改分类").foregroundStyle(YubaiColor.label) }
                    .tint(YubaiColor.keyFn).accessibilityIdentifier("sortLedgerEntry_" + entry.id.uuidString)
                if savedEntry?.nature == .expense {
                    Button { refund() } label: { Text("退款").foregroundStyle(YubaiColor.onBrand) }
                        .tint(YubaiColor.brand).accessibilityIdentifier("refundLedgerEntry_" + entry.id.uuidString)
                }
            }
            .contextMenu {
                Button("改一笔", systemImage: "square.and.pencil") { store.sheet = .editEntry(entry.id) }
                Button("再记一笔一样的", systemImage: "plus") { duplicate() }
                if savedEntry?.nature == .expense {
                    Button("记退款", systemImage: "arrow.uturn.backward") { refund() }
                }
                Button("删掉", systemImage: "trash") { delete() }
            }
            .accessibilityAction(named: "改分类") { onSortCategory() }
            .accessibilityAction(named: "删掉") { delete() }
            .task(id: isFresh && store.sheet == nil) {
                guard isFresh, store.sheet == nil, YubaiMotion.claim("new-row-" + entry.id.uuidString) else {
                    highlighted = false; acknowledged = false; return
                }
                highlighted = true; acknowledged = true
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
                acknowledged = false
                withAnimation(YubaiMotion.quick) { highlighted = false }
            }
    }
    private var entryButton: some View {
        Button { store.sheetSource = nil; store.sheet = .editEntry(entry.id) } label: { content }
    }
    private var savedEntry: Entry? { store.entriesByID[entry.id] }
    private var title: String { savedEntry?.displayTitle ?? entry.categoryName }
    /// A refund linked to this expense offsets its category and the period spending.
    private func refund() {
        guard let saved = store.entriesByID[entry.id] else { return }
        store.requestCaptureSheet(.prefilledEntry(QuickEntryPrefill(category: saved.category, amount: nil, purpose: saved.displayTitle + " 退款",
                                                                    nature: .refund, subcategory: saved.subcategory, accountID: saved.accountID,
                                                                    relatedEntryID: saved.id)))
    }
    private func duplicate() {
        guard let saved = store.entriesByID[entry.id] else { return }
        store.sheetSource = nil; store.sheet = .prefilledEntry(QuickEntryPrefill(entry: saved))
    }
    private var tile: some View {
        LedgerCategoryIcon(category: entry.categoryName, pending: entry.uncategorized)
            .frame(width: YubaiSize.rowIcon, height: YubaiSize.rowIcon)
            .background(entry.inflow ? YubaiColor.brandTint : YubaiColor.paperInset,
                        in: RoundedRectangle(cornerRadius: YubaiRadius.control, style: .continuous)).accessibilityHidden(true)
    }
    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: YubaiSpace.space2) {
            HStack(spacing: YubaiSpace.space8) {
                Text(title).yubaiFont(YubaiFont.rowTitle).foregroundStyle(isFuture ? YubaiColor.labelSecondary : YubaiColor.label)
                    .lineLimit(1).truncationMode(.tail).accessibilityIdentifier("truncatableName")
                if isFuture {
                    Image(systemName: "calendar").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary).accessibilityLabel("未来")
                        .accessibilityIdentifier("futureEntry_" + entry.id.uuidString)
                }
                if entry.intoFixedSavings {
                    Label("存下的钱", systemImage: "lock").yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.brandInk)
                        .padding(.horizontal, YubaiSpace.space8).frame(minHeight: YubaiSize.headerIcon).background(YubaiColor.brandTint, in: Capsule()).fixedSize()
                }
            }
            if !subtitle.isEmpty {
                Text(subtitle).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var amountView: some View {
        AmountLabel(cents: entry.amount, hide: hideAmounts, sign: entry.inflow ? .inflow : .outflow,
                    ink: isFuture ? YubaiColor.labelSecondary : entry.inflow ? YubaiColor.brandInk : YubaiColor.label)
            .fixedSize(horizontal: false, vertical: true).layoutPriority(1)
    }
    private var isFuture: Bool { savedEntry.map { $0.date > store.financialNow } ?? false }
    private var content: some View {
        let layout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: YubaiSpace.space4)) : AnyLayout(HStackLayout(spacing: YubaiSpace.space8))
        return HStack(spacing: YubaiSpace.gapGroup) {
            tile
            layout { titleBlock; amountView }
        }.padding(.vertical, YubaiSpace.space4).frame(maxWidth: .infinity, minHeight: YubaiSize.rowDouble).contentShape(Rectangle())
            .background(isFresh && highlighted ? YubaiColor.brandTint : Color.clear)
    }
    private func delete(systemFeedback: Bool = false) {
        // Native swipe actions provide their own haptic.
        store.update("删掉", entryMotion: !systemFeedback) { ledger in
            guard let index = ledger.entries.firstIndex(where: { $0.id == entry.id && $0.deletedAt == nil }) else { return }
            ledger.entries[index].deletedAt = Dates.now
        }
    }
}
