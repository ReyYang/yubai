import SwiftUI
import YubaiCore

struct EntriesView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var search = ""
    var body: some View {
        let months = EntryTimeline.months(sortedEntries: store.sortedEntries, ledger: store.current, search: search)
        let names = Dictionary(uniqueKeysWithValues: store.current.accounts.map { ($0.id, $0.name) })
        ScrollView {
            LazyVStack(alignment: .leading, spacing: YubaiSpace.space12) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(YubaiColor.labelSecondary)
                    TextField("找一笔：商户、用途、金额", text: $search).yubaiFont(YubaiFont.row)
                        .accessibilityLabel("搜索账目").accessibilityIdentifier("entriesSearch")
                }.padding(.horizontal, 14).frame(minHeight: 40).background(YubaiColor.raised, in: Capsule())
                ForEach(months) { month in
                    monthHeading(month)
                    ForEach(month.days) { day in
                        VStack(spacing: 6) {
                            HStack {
                                Text(ManualBookkeeping.dayLabel(day.date, includeTodayDate: true)).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                                Spacer()
                                AmountLabel(cents: day.net, hide: store.current.preferences.hideAmounts, role: .small,
                                            sign: day.net > 0 ? .inflow : .automatic, fractionDigits: 2)
                            }
                            CardRows(day.entries) { entry in
                                EntryLink(entry: entry, hideAmount: store.current.preferences.hideAmounts, editable: true,
                                          metadata: EntryTimeline.metadata(entry, accountNames: names))
                                    .accessibilityIdentifier("ledgerEntry_" + entry.id.uuidString)
                            }
                        }
                    }
                }
            }.animation(YubaiMotion.layout(reduceMotion: reduceMotion), value: store.entryDeleteTrigger)
                .padding(.horizontal, YubaiSpace.space18).padding(.top, 14).padding(.bottom, 24)
                .frame(maxWidth: 780).frame(maxWidth: .infinity)
        }.scrollDismissesKeyboard(.interactively).amountPrivacy(store.current.preferences.hideAmounts)
            .navigationTitle("账目").yubaiNavigation(hidesTabBar: false)
            .toolbar { ToolbarItem(placement: .primaryAction) {
                Button("记一笔") { store.present(.addEntry, from: "entries-add") }
                    .yubaiFont(YubaiFont.row, weight: .medium).foregroundStyle(YubaiColor.onBrand)
                    .padding(.horizontal, 14).frame(height: 36).background(YubaiColor.brand, in: Capsule())
                    .buttonStyle(PressButtonStyle()).yubaiZoomSource("entries-add").accessibilityIdentifier("addFromEntries")
            } }
    }
    private func monthHeading(_ month: EntryMonth) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) { monthTitle(month); Spacer(); totals(month) }
            VStack(alignment: .leading, spacing: 4) { monthTitle(month); totals(month) }
        }
    }
    private func monthTitle(_ month: EntryMonth) -> some View {
        Text("\(Dates.calendar.component(.month, from: month.date))月").yubaiFont(YubaiFont.month)
    }
    private func totals(_ month: EntryMonth) -> some View {
        HStack(spacing: 4) {
            Text("支出"); AmountLabel(cents: month.spending, hide: store.current.preferences.hideAmounts, role: .small, fractionDigits: month.spending % 100 == 0 ? 0 : 2)
            Text("· 收入"); AmountLabel(cents: month.income, hide: store.current.preferences.hideAmounts, role: .small, fractionDigits: month.income % 100 == 0 ? 0 : 2)
        }.yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
    }
}
