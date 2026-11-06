import SwiftUI
import YubaiCore

struct EntrySubcategoryRow: View {
    @Environment(AppStore.self) private var store
    let entry: Entry
    @State private var selecting = false
    private var classificationEntry: Entry {
        if entry.nature == .refund, let id = entry.relatedEntryID, let original = store.entriesByID[id] { return original }
        return entry
    }
    private var editable: Bool { entry.deletedAt == nil && [.expense, .income, .refund].contains(entry.nature) }
    private var categoryTitle: String {
        let choice = store.current.normalizedCategory(for: entry)
        let main: String = Classification.displayCategory(choice.category)
        return main + (choice.subcategory.map { " · " + $0 } ?? "")
    }
    private var classificationID: UUID {
        guard entry.nature == .refund else { return entry.id }
        return entry.relatedEntryID ?? entry.id
    }
    var body: some View {
        Button { selecting = true } label: { label }
            .buttonStyle(PressButtonStyle()).disabled(!editable).accessibilityIdentifier("entrySubcategory")
            .sheet(isPresented: $selecting) {
                NavigationStack { SubcategoryPicker(entryID: classificationID) }
                    .environment(store).appErrors().yubaiSheetBackground()
                    #if os(macOS)
                    .frame(minWidth: 460, minHeight: 400)
                    #endif
            }
    }
    private var label: some View {
        HStack(spacing: YubaiSpace.space8) {
            Text("分类")
            Spacer(minLength: YubaiSpace.none)
            Text(categoryTitle).multilineTextAlignment(.trailing)
            if classificationEntry.subcategory != nil && !classificationEntry.subcategoryUserEdited {
                AssistantMark(size: 14).accessibilityLabel("余白归的")
            }
            if editable { Image(systemName: "chevron.right").yubaiFont(YubaiFont.caption) }
        }.frame(minHeight: YubaiSize.rowSingle).contentShape(Rectangle())
    }
}

private struct SubcategoryPicker: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let entryID: UUID
    @State private var category: String?
    private var entry: Entry? { store.entriesByID[entryID].flatMap { $0.deletedAt == nil ? $0 : nil } }
    var body: some View {
        Page {
            if let entry {
                Menu("换主项") {
                    ForEach(mainCategories(for: entry)) { main in Button(Classification.displayCategory(main.name)) { category = main.name } }
                }.foregroundStyle(YubaiColor.brandInk)
                choices(for: entry)
            }
        }.manualSheetHeader((category ?? entry?.category ?? "") + "里的哪一类", cancelTitle: "关闭", showsAction: false)
    }
    private func mainCategories(for entry: Entry) -> [YubaiCore.Category] {
        store.current.selectableCategories.filter { $0.income == (entry.nature == .income) }
    }
    private func choices(for entry: Entry) -> some View {
        let choice: CategoryAssignment = store.current.normalizedCategory(for: entry)
        let main: String = category ?? choice.category
        let subcategories: [String] = store.current.selectableCategories.first { $0.name == main }?.subcategories ?? []
        return Card(background: YubaiColor.raised) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), alignment: .leading)], alignment: .leading, spacing: YubaiSpace.gapGroup) {
                ForEach(subcategories, id: \.self) { sub in
                    let selected: Bool = main == choice.category && choice.subcategory == sub
                    SubcategoryChoiceChip(sub: sub, selected: selected) { save(main: main, sub: sub) }
                }
            }
        }
    }
    private func save(main: String, sub: String) {
        if store.update("修改分类", showToast: false, { ledger in
            if let entry = ledger.activeEntries.first(where: { $0.id == entryID }), entry.category != main {
                let change = ChangeSet(source: "用户操作", reason: "修改分类", items: [.setCategory(entry: entryID, category: main)])
                try change.apply(to: &ledger)
            }
            try SubcategoryClassifier.set(sub, entryID: entryID, in: &ledger)
        }) { dismiss() }
    }
}

private struct SubcategoryChoiceChip: View {
    let sub: String
    let selected: Bool
    let save: () -> Void
    var body: some View {
        Button(action: save) {
            Text(sub).yubaiFont(YubaiFont.callout, weight: selected ? .medium : .regular)
                .padding(.horizontal, YubaiSpace.gapGroup).frame(minHeight: YubaiSize.chipHeight)
                .foregroundStyle(selected ? YubaiColor.onBrand : YubaiColor.label)
                .background(selected ? YubaiColor.brand : YubaiColor.raised, in: Capsule()).yubaiHitTarget()
        }.buttonStyle(PressButtonStyle()).accessibilityAddTraits(selected ? .isSelected : [])
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
        let rows: [Breakdown] = store.subcategoryBreakdown(category: category, during: interval)
        let grouped: [String: [Breakdown]] = Dictionary(grouping: rows) { row in
            row.category == "没分类" || row.category.isEmpty ? "其他" : row.category
        }
        let totals: [SubcategoryLine] = grouped.map { name, rows in
            let amount: Int64 = rows.reduce(0) { $0 + $1.amount }
            let count: Int = rows.reduce(0) { $0 + $1.count }
            return SubcategoryLine(title: name, amount: amount, count: count)
        }
        return totals.sorted {
            if $0.amount == $1.amount { return $0.title < $1.title }
            return $0.amount > $1.amount
        }
    }
    private var previousInterval: DateInterval {
        let month = Dates.calendar.dateInterval(of: .month, for: interval.start)!
        return DateInterval(start: Dates.addMonths(-1, to: month.start), end: month.start)
    }
    var body: some View {
        let rows: [SubcategoryLine] = lines
        let total: Int64 = rows.reduce(0) { $0 + $1.amount }
        Page {
            summary(rows: rows, total: total)
                .accessibilityElement(children: .contain).accessibilityIdentifier("subcategoryInsightsSummary")
            Card(style: .list) {
                VStack(alignment: .leading, spacing: YubaiSpace.none) {
                    Text("按小项").yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary).frame(minHeight: YubaiSize.iconButton)
                    ForEach(rows) { row in
                        EntryFormDivider()
                        line(row, total: total)
                    }
                }
            }
        }.navigationTitle(Classification.displayCategory(category) + " · " + periodTitle).yubaiNavigation()
            .accessibilityIdentifier("subcategoryInsights")
    }
    private func summary(rows: [SubcategoryLine], total: Int64) -> some View {
        let count: Int = rows.reduce(0) { $0 + $1.count }
        let flow: CashFlowSummary = store.cashFlow(during: interval)
        let denominator: Int64 = income ? flow.income : flow.spending
        let previousRows: [Breakdown] = store.subcategoryBreakdown(category: category, during: previousInterval)
        let previous: Int64 = previousRows.reduce(0) { $0 + $1.amount }
        let comparisonText: String = shareText(total, denominator) + " · " + comparison(total - previous)
        return VStack(alignment: .leading, spacing: YubaiSpace.space4) {
            Text(rangeText + " · \(count) 笔").yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary)
            AmountLabel(cents: total, hide: store.preferences.hideAmounts, role: .input)
            if !store.preferences.hideAmounts {
                Text(comparisonText).yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary)
            }
        }
    }
    private func line(_ row: SubcategoryLine, total: Int64) -> some View {
        let ratio: Double = total > 0 ? max(0, Double(row.amount) / Double(total) * 2) : 0
        return NavigationLink {
            SubcategoryRecordsView(category: category, subcategory: row.title, income: income, interval: interval)
        } label: {
            VStack(alignment: .leading, spacing: YubaiSpace.space8) {
                lineHeading(row, total: total)
                if !store.preferences.hideAmounts { SavingProgressBar(ratio: ratio) }
            }.padding(.vertical, YubaiSpace.gapGroup).frame(minHeight: YubaiSize.rowDouble).contentShape(Rectangle())
        }.buttonStyle(PressButtonStyle())
    }
    private func lineHeading(_ row: SubcategoryLine, total: Int64) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: YubaiSpace.space8) {
            Text(row.title).yubaiFont(YubaiFont.row)
            if restrained(row.title) { Text("想克制").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.amberInk) }
            Spacer(minLength: YubaiSpace.none)
            AmountLabel(cents: row.amount, hide: store.preferences.hideAmounts)
            if !store.preferences.hideAmounts {
                Text(percent(row.amount, total)).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
            }
        }
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
        return store.profile.restrain.contains { area in
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
    private var rows: [Entry] {
        store.flowRecords(categories: [category], income: income, interval: interval, subcategory: subcategory)
    }
    var body: some View {
        Page { CardRows(rows) { entry in EntryLink(entry: entry, hideAmount: store.preferences.hideAmounts, editable: true) } }
            .navigationTitle(subcategory).yubaiNavigation()
    }
}
