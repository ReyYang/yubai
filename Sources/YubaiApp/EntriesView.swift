import SwiftUI
import YubaiCore

struct EntriesView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var month = Dates.calendar.dateInterval(of: .month, for: Date())!.start
    @State private var filter = EntryTimeline.Filter.all
    @State private var search = ""
    @State private var showingSearch = false
    @State private var revealedEntryID: UUID?
    @FocusState private var searchFocused: Bool
    var body: some View {
        let end = Dates.addMonths(1, to: month)
        let entries = store.sortedEntries.filter { $0.date >= month && $0.date < end }
        let summary = EntryTimeline.months(sortedEntries: entries, ledger: store.current).first
        let days = EntryTimeline.months(sortedEntries: entries, ledger: store.current, search: search, filter: filter).first?.days ?? []
        let symbols = Dictionary(uniqueKeysWithValues: store.current.categories.map { ($0.name, $0.symbol) })
        ScrollView {
            LazyVStack(alignment: .leading, spacing: YubaiSpace.space18) {
                VStack(spacing: YubaiSpace.space10) {
                    monthPicker
                    if showingSearch { searchField }
                    HStack(spacing: YubaiSpace.space10) {
                        total("本月支出", cents: summary?.spending ?? 0)
                        total("本月收入", cents: summary?.income ?? 0, inflow: true)
                    }
                    filters
                }
                if days.isEmpty {
                    Text(search.isEmpty ? (filter == .all ? "这个月还没有账目" : "还没有这类账目") : "没有找到这笔")
                        .yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary)
                        .frame(maxWidth: .infinity).padding(.vertical, YubaiSpace.space24)
                }
                ForEach(days) { day in
                    VStack(spacing: YubaiSpace.space6) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(dayLabel(day.date)).yubaiFont(YubaiFont.row, weight: .semibold)
                            Spacer(minLength: YubaiSpace.space8)
                            AmountLabel(cents: -day.spending, hide: store.current.preferences.hideAmounts, role: .day, fractionDigits: 2)
                        }.foregroundStyle(YubaiColor.label).padding(.horizontal, YubaiSpace.space4)
                        CardRows(day.entries) { entry in
                            let category = store.current.resolveCategory(entry.category)
                            LedgerEntryRow(revealedEntryID: $revealedEntryID, entry: entry, category: category, symbol: symbols[category] ?? fallbackSymbol(category, nature: entry.nature))
                        }
                    }
                }
            }.animation(YubaiMotion.layout(reduceMotion: reduceMotion), value: store.entryDeleteTrigger)
                .padding(.horizontal, YubaiSpace.space18).padding(.top, YubaiSpace.space12).padding(.bottom, YubaiSpace.space24)
                .frame(maxWidth: 780).frame(maxWidth: .infinity)
        }.scrollDismissesKeyboard(.interactively).amountPrivacy(store.current.preferences.hideAmounts).accessibilityIdentifier("entriesScroll")
            #if os(iOS)
            .rootScrollContentMargins()
            .simultaneousGesture(TapGesture().onEnded { revealedEntryID = nil })
            .onScrollPhaseChange { _, phase in if phase == .interacting { revealedEntryID = nil } }
            .onChange(of: revealedEntryID, initial: true) { _, id in store.pagingLocked = id != nil }
            .onChange(of: store.destination) { _, _ in revealedEntryID = nil }
            .onChange(of: store.sheet?.id) { _, _ in revealedEntryID = nil }
            .onDisappear { revealedEntryID = nil; store.pagingLocked = false }
            #endif
            .navigationTitle("账目").yubaiNavigation(hidesTabBar: false)
    }
    private var monthPicker: some View {
        HStack(spacing: YubaiSpace.space4) {
            Button { changeMonth(-1) } label: {
                Image(systemName: "chevron.left").frame(width: YubaiSize.tapMin, height: YubaiSize.tapMin)
            }.accessibilityLabel("上个月").accessibilityIdentifier("entriesPreviousMonth")
            Text(verbatim: "\(Dates.calendar.component(.year, from: month)) 年 \(Dates.calendar.component(.month, from: month)) 月")
                .yubaiFont(YubaiFont.navTitle).accessibilityIdentifier("entriesMonth")
            Button { changeMonth(1) } label: {
                Image(systemName: "chevron.right").frame(width: YubaiSize.tapMin, height: YubaiSize.tapMin)
            }.accessibilityLabel("下个月").accessibilityIdentifier("entriesNextMonth")
            Spacer(minLength: 0)
            Button {
                withAnimation(YubaiMotion.layout(reduceMotion: reduceMotion)) { showingSearch.toggle() }
                searchFocused = showingSearch
                if !showingSearch { search = "" }
            } label: {
                Image(systemName: showingSearch ? "xmark" : "magnifyingglass")
                    .frame(width: YubaiSize.iconButton, height: YubaiSize.iconButton)
                    .background(YubaiColor.raised, in: Circle()).frame(width: YubaiSize.tapMin, height: YubaiSize.tapMin)
            }.accessibilityLabel(showingSearch ? "关闭搜索" : "搜索账目").accessibilityIdentifier("entriesSearchButton")
        }.yubaiFont(YubaiFont.row).foregroundStyle(YubaiColor.label).buttonStyle(PressButtonStyle())
    }
    private var searchField: some View {
        HStack(spacing: YubaiSpace.space8) {
            Image(systemName: "magnifyingglass").foregroundStyle(YubaiColor.labelSecondary).accessibilityHidden(true)
            TextField("找一笔：备注、分类、金额", text: $search).yubaiFont(YubaiFont.row).focused($searchFocused)
                .accessibilityLabel("搜索账目").accessibilityIdentifier("entriesSearch")
        }.padding(.horizontal, YubaiSpace.space16).frame(minHeight: YubaiSize.tapMin)
            .background(YubaiColor.raised, in: Capsule())
    }
    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: YubaiSpace.space8) {
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
            }
        }.pageLocalHorizontalGestures()
            #if os(iOS)
            .contentMargins(.bottom, 0, for: .scrollContent)
            #endif
            .accessibilityElement(children: .contain).accessibilityLabel("筛选账目")
    }
    private func total(_ title: String, cents: Int64, inflow: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: YubaiSpace.space2) {
            Text(title).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
            AmountLabel(cents: cents, hide: store.current.preferences.hideAmounts, role: .donut,
                        sign: inflow ? .inflow : .automatic, fractionDigits: cents % 100 == 0 ? 0 : 2,
                        ink: inflow ? YubaiColor.brandInk : YubaiColor.label)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(YubaiSpace.space12)
            .background(YubaiColor.card, in: RoundedRectangle(cornerRadius: YubaiRadius.row))
    }
    private func changeMonth(_ offset: Int) { searchFocused = false; month = Dates.addMonths(offset, to: month) }
    private func fallbackSymbol(_ category: String, nature: Nature) -> String {
        switch category {
        case "日用", "购物": "bag"
        case "娱乐": "sparkles"
        case "工资", "奖金": "banknote"
        case "兼职": "hammer"
        case "理财收益": "chart.line.uptrend.xyaxis"
        default: nature.symbol
        }
    }
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
    #if os(macOS)
    @GestureState private var dragging = false
    @State private var horizontal: Bool?
    @State private var tapsBlocked = false
    #endif
    @State private var offset: CGFloat = 0
    @State private var resting: CGFloat = 0
    @State private var highlighted = true
    @Binding var revealedEntryID: UUID?
    let entry: Entry
    let category: String
    let symbol: String
    private var uncategorized: Bool { EntryTimeline.isUncategorized(entry) }
    private var categoryName: String { uncategorized ? "没分类" : Classification.displayCategory(category) }
    private var note: String { entry.note.isEmpty ? (entry.displayTitle == categoryName ? "" : entry.displayTitle) : entry.note }
    var body: some View {
        Button {
            #if os(macOS)
            guard !tapsBlocked, !dragging else { return }
            #endif
            if resting != 0 {
                #if os(iOS)
                revealedEntryID = nil
                #endif
                resting = 0; reset(); return
            }
            store.sheetSource = nil; store.sheet = .editEntry(entry.id)
        } label: { content }
            .buttonStyle(PressButtonStyle()).accessibilityIdentifier("ledgerEntry_" + entry.id.uuidString)
            .offset(x: offset).background(alignment: .trailing) {
                Button("删除", action: delete).yubaiFont(YubaiFont.callout, weight: .semibold).foregroundStyle(YubaiColor.amberInk)
                    .frame(width: 84).frame(maxHeight: .infinity).background(YubaiColor.amberTint)
                    .opacity(offset < 0 ? 1 : 0).allowsHitTesting(offset < 0).accessibilityHidden(offset == 0)
                    .accessibilityIdentifier("deleteLedgerEntry_" + entry.id.uuidString)
            }.clipped().contentShape(Rectangle())
            #if os(iOS)
            .gesture(HorizontalPan(changed: { distance in
                if distance < 0 { revealedEntryID = entry.id }
                offset = max(-84, min(0, resting + distance))
            }, ended: { distance, _ in
                resting = resting < 0 ? (distance > 0 ? 0 : -84) : (offset < -36 ? -84 : 0)
                finishSwipe()
            }, cancelled: finishSwipe))
            .onChange(of: revealedEntryID) { _, id in
                if id != entry.id { resting = 0; reset() }
            }
            .onDisappear {
                if revealedEntryID == entry.id { revealedEntryID = nil }
                resting = 0; reset()
            }
            #else
            .simultaneousGesture(DragGesture(minimumDistance: 18)
                .updating($dragging) { _, state, _ in state = true }
                .onChanged { value in
                    if horizontal == nil { horizontal = abs(value.translation.width) > abs(value.translation.height) * 1.3 }
                    guard horizontal == true else { return }
                    tapsBlocked = true
                    offset = max(-84, min(0, resting + value.translation.width))
                }.onEnded { _ in
                    if horizontal == true { resting = offset < -36 ? -84 : 0 }
                    reset(); releaseTaps()
                })
            .onChange(of: dragging) { _, active in if !active { reset(); releaseTaps() } }
            .onDisappear { resting = 0; reset(); releaseTaps() }
            #endif
            .accessibilityAction(named: "删除这笔", delete)
            .task(id: store.freshEntryIDs.contains(entry.id)) {
                guard store.freshEntryIDs.contains(entry.id), YubaiMotion.claim("new-row-" + entry.id.uuidString) else { highlighted = false; return }
                withAnimation(YubaiMotion.wash(reduceMotion: reduceMotion)) { highlighted = false }
            }
    }
    private var content: some View {
        HStack(spacing: YubaiSpace.space12) {
            Image(systemName: uncategorized ? "questionmark" : symbol).yubaiFont(YubaiFont.tabIcon)
                .foregroundStyle(uncategorized ? YubaiColor.amberInk : entry.nature.inflow ? YubaiColor.brandInk : YubaiColor.labelMuted)
                .frame(width: 36, height: 36)
                .background(uncategorized ? YubaiColor.amberTint : entry.nature.inflow ? YubaiColor.brandTint : YubaiColor.raised,
                            in: RoundedRectangle(cornerRadius: YubaiRadius.control)).accessibilityHidden(true)
            let layout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: YubaiSpace.space4)) : AnyLayout(HStackLayout(spacing: YubaiSpace.space8))
            layout {
                VStack(alignment: .leading, spacing: YubaiSpace.space2) {
                    Text(categoryName).yubaiFont(YubaiFont.rowTitle).foregroundStyle(YubaiColor.label)
                    if !note.isEmpty { Text(note).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary) }
                }.lineLimit(textSize.isAccessibilitySize ? nil : 1).frame(maxWidth: .infinity, alignment: .leading)
                AmountLabel(cents: entry.amount, hide: store.current.preferences.hideAmounts,
                            sign: entry.nature.inflow ? .inflow : .outflow, ink: entry.nature.inflow ? YubaiColor.brandInk : YubaiColor.label)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }.padding(.vertical, YubaiSpace.space8).frame(maxWidth: .infinity, minHeight: 58).contentShape(Rectangle())
            .background(store.freshEntryIDs.contains(entry.id) && highlighted ? YubaiColor.brandTint : YubaiColor.card)
    }
    private func reset() {
        #if os(macOS)
        horizontal = nil
        #endif
        withAnimation(YubaiMotion.layout(reduceMotion: reduceMotion)) { offset = resting }
    }
    #if os(macOS)
    private func releaseTaps() { DispatchQueue.main.async { if !dragging { tapsBlocked = false } } }
    #elseif os(iOS)
    private func finishSwipe() {
        if resting < 0 { revealedEntryID = entry.id }
        else if revealedEntryID == entry.id { revealedEntryID = nil }
        reset()
    }
    #endif
    private func delete() {
        #if os(iOS)
        revealedEntryID = nil
        #endif
        store.update("删除这笔") { ledger in
            guard let index = ledger.entries.firstIndex(where: { $0.id == entry.id && $0.deletedAt == nil }) else { return }
            ledger.entries[index].deletedAt = Date()
        }
    }
}
