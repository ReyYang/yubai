import SwiftUI
import YubaiCore

/// 存着的钱的存取记录与一次性的补回选择。
struct ReserveView: View {
    @Environment(AppStore.self) private var store
    @State private var editing = false
    @State private var keypad = EntryKeypad(amount: 0)
    private var hide: Bool { store.preferences.hideAmounts }
    private var overview: ReserveOverview { store.reserve }
    var body: some View {
        Page(spacing: YubaiSpace.gapSection, topPadding: YubaiSpace.space8) {
            hero
            if !overview.lines.isEmpty { lines }
            if let offer = store.paybackOffers.first { ReservePaybackOfferCard(offer: offer) }
            ReservePaybackProgressList(identifier: "reservePaybackProgress")
        }.amountPrivacy(hide).navigationTitle("存取记录").yubaiNavigation().accessibilityIdentifier("reservePage")
            .sheet(isPresented: $editing) {
                AmountEntrySheet(title: "存下的钱", keypad: $keypad, primaryTitle: "好", primaryIdentifier: "saveReserveTotal",
                                 canSave: keypad.amount != nil, save: saveTotal)
                    .environment(store).yubaiSheetBackground().presentationDragIndicator(.visible)
            }
    }
    private var hero: some View {
        VStack(spacing: YubaiSpace.space4) {
            Text("存下的钱").yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary)
            HStack(spacing: YubaiSpace.gapGroup) {
                AmountLabel(cents: overview.total, hide: hide, role: .hero).accessibilityIdentifier("reserveTotal")
                Button {
                    keypad = EntryKeypad(amount: overview.total); editing = true
                } label: {
                    Image(systemName: "pencil").yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.brandInk)
                        .frame(width: YubaiSize.tapMin, height: YubaiSize.tapMin).controlSurface(in: Circle()).yubaiHitTarget()
                }.buttonStyle(PressButtonStyle()).accessibilityLabel("修改存着的钱").accessibilityIdentifier("editReserveTotal")
            }
        }.frame(maxWidth: .infinity)
    }
    private var lines: some View {
        Card(style: .list) {
            VStack(spacing: YubaiSpace.none) {
                ForEach(Array(overview.lines.enumerated()), id: \.element.id) { index, line in
                    ReserveLineRow(line: line, hide: hide).accessibilityIdentifier("reserveLine_\(index)")
                    if index < overview.lines.count - 1 { EntryFormDivider() }
                }
            }
        }
    }
    private func saveTotal() {
        guard let value = keypad.resolve() else { return }
        let base = max(0, value - overview.setAside)
        if store.update("调整存着的钱", { Reserve.setTotal(base, in: &$0, now: Date()) }) { editing = false }
    }
}
