import SwiftUI
import YubaiCore

struct CycleBillsView: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        let formula = store.formula
        Page(topPadding: YubaiSpace.space8) {
            Text(NowFormat.monthDay(formula.cycleStart) + " – " + NowFormat.monthDay(formula.cycleEnd))
                .yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary)
            CardRows(formula.bills) { row in BillCalendarRow(row: row, includesDate: true) }
        }.amountPrivacy(store.preferences.hideAmounts).navigationTitle("要付的账单").yubaiNavigation().accessibilityIdentifier("cycleBillsPage")
    }
}
