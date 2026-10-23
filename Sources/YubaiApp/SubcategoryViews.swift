import SwiftUI
import YubaiCore

struct EntrySubcategoryRow: View {
    @Environment(AppStore.self) private var store
    let entry: Entry
    @State private var selecting = false
    private var classificationEntry: Entry {
        if entry.nature == .refund, let id = entry.relatedEntryID, let original = store.current.entries.first(where: { $0.id == id }) { return original }
        return entry
    }
    private var editable: Bool { entry.deletedAt == nil && [.expense, .income, .refund].contains(entry.nature) }
    var body: some View {
        Button { selecting = true } label: {
            HStack(spacing: YubaiSpace.space8) {
                Text("分类")
                Spacer(minLength: YubaiSpace.none)
                Text(Classification.displayCategory(classificationEntry.category) + (classificationEntry.subcategory.map { " · " + $0 } ?? ""))
                    .multilineTextAlignment(.trailing)
                if classificationEntry.subcategory != nil && !classificationEntry.subcategoryUserEdited {
                    AssistantMark(size: 14).accessibilityLabel("余白归的")
                }
                if editable { Image(systemName: "chevron.right").yubaiFont(YubaiFont.caption) }
            }.frame(minHeight: YubaiSize.rowSingle).contentShape(Rectangle())
        }.buttonStyle(PressButtonStyle()).disabled(!editable).accessibilityIdentifier("entrySubcategory")
            .sheet(isPresented: $selecting) {
                NavigationStack { SubcategoryPicker(entryID: entry.nature == .refund ? entry.relatedEntryID ?? entry.id : entry.id) }
                    .environment(store).appErrors()
                    #if os(macOS)
                    .frame(minWidth: 460, minHeight: 400)
                    #endif
            }
    }
}

private struct SubcategoryPicker: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let entryID: UUID
    @State private var category: String?
    private var entry: Entry? { store.current.activeEntries.first { $0.id == entryID } }
    var body: some View {
        Page {
            if let entry {
                let main = category ?? store.current.resolveCategory(entry.category)
                Card(background: YubaiColor.raised) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), alignment: .leading)], alignment: .leading, spacing: YubaiSpace.gapGroup) {
                        ForEach(store.current.categories.first(where: { $0.name == main })?.subcategories ?? [], id: \.self) { sub in
                            let selected = main == entry.category && sub == entry.subcategory
                            Button { save(main: main, sub: sub) } label: {
                                Text(sub).yubaiFont(YubaiFont.callout, weight: selected ? .medium : .regular)
                                    .padding(.horizontal, YubaiSpace.gapGroup).frame(minHeight: YubaiSize.chipHeight)
                                    .foregroundStyle(selected ? YubaiColor.onBrand : YubaiColor.label)
                                    .background(selected ? YubaiColor.brand : YubaiColor.card, in: Capsule()).yubaiHitTarget()
                            }.buttonStyle(PressButtonStyle()).accessibilityAddTraits(selected ? .isSelected : [])
                        }
                    }
                }
            }
        }.navigationTitle((category ?? entry?.category ?? "") + "里的哪一类").yubaiNavigation()
            .toolbar {
                CloseButton()
                ToolbarItem(placement: .confirmationAction) {
                    Menu("换主项") {
                        if let entry {
                            ForEach(store.current.categories.filter { $0.income == (entry.nature == .income) }) { main in
                                Button(Classification.displayCategory(main.name)) { category = main.name }
                            }
                        }
                    }
                }
            }
    }
    private func save(main: String, sub: String) {
        if store.update("修改分类", showToast: false, { ledger in
            if let entry = ledger.activeEntries.first(where: { $0.id == entryID }), entry.category != main {
                let change = ChangeSet(source: "用户操作", reason: "修改分类", items: [.setCategory(entryID, main)])
                try change.apply(to: &ledger)
            }
            try SubcategoryClassifier.set(sub, entryID: entryID, in: &ledger)
        }) { dismiss() }
    }
}

private struct SubcategoryLine: Identifiable {
    let title: String
    let amount: Int64
    let count: Int
    var id: String { title }
}

struct SubcategoryInsightsView: View {
    @Environment(AppStore.self) private var store
    let category: String
    let income: Bool
    let interval: DateInterval
    var periodTitle = "本月"
    private var lines: [SubcategoryLine] {
        let rows = Finance.subcategoryBreakdown(store.current, category: category, during: interval)
        let grouped = Dictionary(grouping: rows) { $0.category == "没分类" || $0.category.isEmpty ? "其他" : $0.category }
        return grouped.map { name, rows in
            SubcategoryLine(title: name, amount: rows.reduce(0) { $0 + $1.amount }, count: rows.reduce(0) { $0 + $1.count })
        }.sorted { $0.amount == $1.amount ? $0.title < $1.title : $0.amount > $1.amount }
    }
    private var previousInterval: DateInterval {
        let month = Dates.calendar.dateInterval(of: .month, for: interval.start)!
        return DateInterval(start: Dates.addMonths(-1, to: month.start), end: month.start)
    }
    var body: some View {
        let rows = lines
        let total = rows.reduce(Int64(0)) { $0 + $1.amount }
        let count = rows.reduce(0) { $0 + $1.count }
        let summary = Finance.cashFlow(store.current, during: interval)
        let denominator = income ? summary.income : summary.spending
        let previous = Finance.subcategoryBreakdown(store.current, category: category, during: previousInterval).reduce(Int64(0)) { $0 + $1.amount }
        Page {
            VStack(alignment: .leading, spacing: YubaiSpace.space4) {
                Text(rangeText + " · \(count) 笔").yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary)
                AmountLabel(cents: total, hide: store.current.preferences.hideAmounts, role: .input, fractionDigits: 0)
                if !store.current.preferences.hideAmounts {
                    Text(shareText(total, denominator) + " · " + comparison(total - previous))
                        .yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary)
                }
            }
            Card(style: .list) {
                VStack(alignment: .leading, spacing: YubaiSpace.none) {
                    Text("按小项").yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary).frame(minHeight: YubaiSize.iconButton)
                    ForEach(rows) { row in
                        EntryFormDivider()
                        NavigationLink { SubcategoryRecordsView(category: category, subcategory: row.title, income: income, interval: interval) } label: {
                            VStack(alignment: .leading, spacing: YubaiSpace.space8) {
                                HStack(alignment: .firstTextBaseline, spacing: YubaiSpace.space8) {
                                    Text(row.title).yubaiFont(YubaiFont.row)
                                    if restrained(row.title) { Text("想克制").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.amberInk) }
                                    Spacer(minLength: YubaiSpace.none)
                                    AmountLabel(cents: row.amount, hide: store.current.preferences.hideAmounts)
                                    if !store.current.preferences.hideAmounts {
                                        Text(percent(row.amount, total)).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                                    }
                                }
                                if !store.current.preferences.hideAmounts {
                                    SavingProgressBar(ratio: total > 0 ? max(0, Double(row.amount) / Double(total) * 2) : 0)
                                }
                            }.padding(.vertical, YubaiSpace.gapGroup).frame(minHeight: YubaiSize.rowDouble).contentShape(Rectangle())
                        }.buttonStyle(PressButtonStyle())
                    }
                }
            }
        }.navigationTitle(Classification.displayCategory(category) + " · " + periodTitle).yubaiNavigation()
            .accessibilityIdentifier("subcategoryInsights")
    }
    private var rangeText: String {
        FixedFlowPresentation.monthDay(interval.start) + " – " + FixedFlowPresentation.monthDay(max(interval.start, interval.end.addingTimeInterval(-0.001)))
    }
    private func shareText(_ total: Int64, _ denominator: Int64) -> String { "占" + (income ? "收入 " : "支出 ") + percent(total, denominator) }
    private func percent(_ amount: Int64, _ total: Int64) -> String {
        total > 0 && amount >= 0 ? String(format: "%.0f%%", Double(amount) / Double(total) * 100) : "—"
    }
    private func comparison(_ delta: Int64) -> String {
        delta == 0 ? "和上月相同" : "比上月" + (delta > 0 ? "多 " : "少 ") + Money.text(abs(delta), currency: false)
    }
    private func restrained(_ sub: String) -> Bool {
        guard !income else { return false }
        var sample = Entry(date: interval.start, amount: 0, accountID: UUID(), title: sub, category: category)
        sample.subcategory = sub
        return store.current.profile.restrain.contains { area in
            ButlerCards.matches(area, entry: sample, ledger: store.current) || area.title == sub
        }
    }
}

private struct SubcategoryRecordsView: View {
    @Environment(AppStore.self) private var store
    let category: String
    let subcategory: String
    let income: Bool
    let interval: DateInterval
    var body: some View {
        let byID = Dictionary(uniqueKeysWithValues: store.current.entries.map { ($0.id, $0) })
        let rows = store.sortedEntries.filter { entry in
            guard entry.deletedAt == nil, entry.date >= interval.start, entry.date < interval.end,
                  income ? entry.nature == .income : (entry.nature == .expense || entry.nature == .refund),
                  store.current.resolveCategory(Finance.spendingCategory(entry, entriesByID: byID)) == store.current.resolveCategory(category) else { return false }
            let original = entry.nature == .refund ? entry.relatedEntryID.flatMap { byID[$0] } : nil
            return ((original ?? entry).subcategory ?? "其他") == subcategory
        }
        Page { CardRows(rows) { entry in EntryLink(entry: entry, hideAmount: store.current.preferences.hideAmounts, editable: true) } }
            .navigationTitle(subcategory).yubaiNavigation()
    }
}
