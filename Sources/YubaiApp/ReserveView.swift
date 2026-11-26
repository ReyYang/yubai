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

struct ReserveLineRow: View {
    @Environment(\.dynamicTypeSize) private var textSize
    let line: ReserveLine
    let hide: Bool
    private var title: String {
        if line.paybackID != nil { return "这个月存的" }
        if !line.title.isEmpty { return line.title }
        switch line.kind {
        case .monthly: return "这个月存的"
        case .leftover: return "剩下的"
        case .cover: return "补超支"
        case .adjust: return "调整"
        case .income, .purchase: return "存下的钱"
        case .transfer(_, let direction): return direction == .take ? "拿出来用" : "放回去"
        }
    }
    private var dateText: String { FixedFlowPresentation.monthDay(line.date) }
    private var amountView: some View {
        AmountLabel(cents: line.amount, hide: hide, role: .amount, sign: line.amount >= 0 ? .inflow : .outflow,
                    ink: line.amount >= 0 ? YubaiColor.brandInk : YubaiColor.label)
    }
    var body: some View {
        let layout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: YubaiSpace.space4)) : AnyLayout(HStackLayout(spacing: YubaiSpace.gapGroup))
        layout {
            Text(dateText).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                .frame(minWidth: textSize.isAccessibilitySize ? YubaiSpace.none : YubaiSize.rowDouble, alignment: .leading)
            Text(title).accessibilityIdentifier("truncatableName").yubaiFont(YubaiFont.row).lineLimit(1).truncationMode(.tail).frame(maxWidth: .infinity, alignment: .leading)
            amountView
        }.frame(minHeight: YubaiSize.rowDouble).accessibilityElement(children: .combine)
            .accessibilityLabel(dateText + "，" + title + "，" + (hide ? "金额已隐藏" : AmountLabel.text(line.amount, sign: .automatic)))
    }
}
