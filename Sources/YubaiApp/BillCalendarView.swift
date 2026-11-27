import SwiftUI
import YubaiCore

struct BillBrandIcon: View {
    let title: String
    var category = Classification.pendingCategory
    var inflow = false
    var size: CGFloat = YubaiSize.headerIconMax
    @Environment(AppStore.self) private var store
    @Environment(\.colorScheme) private var scheme
    private var icon: DS.Icon {
        store.current.categories.first { $0.name == category && $0.income == inflow }.map(\.entryIcon) ?? .catOther
    }
    var body: some View {
        Group {
            if let icon = BrandIcons.match(title) {
                Image("Brand-" + icon.slug).resizable().renderingMode(.original).scaledToFit().padding(YubaiSpace.space4)
            } else {
                DSIconView(icon: icon, size: YubaiFont.row.size, color: scheme == .dark ? YubaiColor.label : YubaiColor.iconInk)
            }
        }.frame(width: size, height: size).background(YubaiColor.raised, in: RoundedRectangle(cornerRadius: YubaiRadius.control, style: .continuous))
            .accessibilityHidden(true)
    }
}

struct BillCalendarRow: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dynamicTypeSize) private var textSize
    let row: FixedFlowOccurrence
    var includesDate = false
    private var plan: Plan? { store.plans.first { $0.id == row.planID } }
    var body: some View {
        Group {
            if let plan {
                Button { store.sheet = .editPlan(plan.id) } label: { summary }
                    .buttonStyle(PressButtonStyle()).accessibilityIdentifier("editFixedFlow_" + plan.id.uuidString)
            } else { summary }
        }.opacity(row.state == .paid ? 0.45 : 1).accessibilityElement(children: .contain)
            .accessibilityIdentifier("fixedFlow_" + row.id)
            .accessibilityValue(FixedFlowPresentation.state(row.state, inflow: row.inflow))
    }
    private var summary: some View {
        let layout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: YubaiSpace.space8)) : AnyLayout(HStackLayout(spacing: YubaiSpace.space12))
        return layout {
            HStack(spacing: YubaiSpace.space12) {
                BillBrandIcon(title: row.title, category: plan?.category ?? "居住", inflow: row.inflow)
                VStack(alignment: .leading, spacing: YubaiSpace.space2) {
                    HStack {
                        Text(row.title).yubaiFont(YubaiFont.rowTitle).lineLimit(1)
                        if plan?.frequency == .yearly { Text("年付").yubaiFont(YubaiFont.meta).fixedSize().foregroundStyle(YubaiColor.canvas).padding(.horizontal, YubaiSpace.space4).background(YubaiColor.label, in: Capsule()) }
                    }
                    Text(schedule).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary).fixedSize(horizontal: false, vertical: true)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(maxWidth: .infinity, alignment: .leading)
            amounts
        }.frame(maxWidth: .infinity, minHeight: YubaiSize.sourceRow, alignment: .leading).padding(.vertical, YubaiSpace.space4).contentShape(Rectangle())
    }
    private var schedule: String {
        var value = plan.map { FixedFlowArrangement.schedule($0.frequency, date: $0.dueDate, monthlyDay: $0.monthlyDay).replacingOccurrences(of: " 日", with: " 号") } ?? FixedFlowPresentation.monthDay(row.date)
        if includesDate {
            let date = ManualBookkeeping.dayLabel(row.date, now: store.financialNow)
            if date != value { value = date + " · " + value }
        }
        if row.state == .paid { value += row.inflow ? " · 已收到" : " · 已付" }
        return value
    }
    @ViewBuilder private var amounts: some View {
        if let plan, plan.currency != .cny {
            VStack(alignment: .trailing, spacing: YubaiSpace.space2) {
                Text(plan.currency.amountText(plan.amount, hidden: store.preferences.hideAmounts)).yubaiFont(YubaiFont.amount)
                    .fixedSize(horizontal: false, vertical: true)
                Text((row.state == .paid ? "实付 " : "约 ") + amount2(row.amount, hide: store.preferences.hideAmounts))
                    .yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if row.state != .paid, FixedFlows.lastActual(planID: plan.id, in: store.current, now: store.financialNow) != nil {
                    Text("上次实付").yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary)
                }
            }
        } else {
            AmountLabel(cents: row.amount, hide: store.preferences.hideAmounts, role: .amount,
                        sign: row.inflow ? .inflow : .outflow, ink: row.inflow ? YubaiColor.brandInk : YubaiColor.label)
        }
    }
}

