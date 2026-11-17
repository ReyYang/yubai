import SwiftUI
import YubaiCore

/// Dates, names and signed amounts share one plain list.
struct ReserveView: View {
    @Environment(AppStore.self) private var store
    private var hide: Bool { store.preferences.hideAmounts }
    var body: some View {
        let lines = store.reserve.lines
        Page(spacing: YubaiSpace.gapSection, topPadding: YubaiSpace.space8) {
            if !lines.isEmpty {
                Card(style: .list) {
                    VStack(spacing: YubaiSpace.none) {
                        ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                            ReserveLineRow(line: line, hide: hide).accessibilityIdentifier("reserveLine_\(index)")
                            if index < lines.count - 1 { EntryFormDivider() }
                        }
                    }
                }
            }
        }.amountPrivacy(hide).navigationTitle("存取记录").yubaiNavigation().accessibilityIdentifier("reservePage")
    }
}
