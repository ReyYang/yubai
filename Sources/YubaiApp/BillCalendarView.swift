import SwiftUI
import YubaiCore

struct BillBrandIcon: View {
    let title: String
    var category = Classification.pendingCategory
    var inflow = false
    var size: CGFloat = 32
    @Environment(AppStore.self) private var store
    private var symbol: String {
        store.current.categories.first { $0.name == category && $0.income == inflow }?.symbol ?? "square.grid.2x2"
    }
    var body: some View {
        Group {
            if let icon = BrandIcons.match(title) {
                Image("Brand-" + icon.slug).resizable().renderingMode(.original).scaledToFit().padding(YubaiSpace.space4)
            } else {
                Image(systemName: symbol).yubaiFont(YubaiFont.row).foregroundStyle(YubaiColor.iconInk)
            }
        }.frame(width: size, height: size).background(YubaiColor.raised, in: RoundedRectangle(cornerRadius: YubaiRadius.control))
            .accessibilityHidden(true)
    }
}

struct FixedFlowsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var shownMonth: Date?
    @State private var selectedDay: Date?
    @State private var editingRate: BillCurrency?
    private var date: Date { shownMonth ?? store.financialNow }
    private var snapshot: BillCalendarMonth { BillCalendarMonth(containing: date, in: store.current, now: store.financialNow) }
    var body: some View {
        let month = snapshot
        Page(spacing: YubaiSpace.gapGroup, topPadding: YubaiSpace.space8) {
            if !store.current.plans.contains(where: { $0.active && $0.stoppedAt == nil }) && store.current.rents.isEmpty {
                EmptyState(.bills, onAction: { store.sheet = .addPlan })
                stoppedBills
            } else {
            monthHeader(month)
            calendar(month)
            if let day = selectedDay {
                dayCard(day, rows: month.days.first { Dates.day($0.date) == Dates.day(day) }?.bills ?? [])
            } else {
                upcoming(month)
                YearlyBillsStrip(month: month)
                stoppedBills
            }
            }
        }.navigationTitle("账单").yubaiNavigation().amountPrivacy(store.preferences.hideAmounts)
            .accessibilityIdentifier("fixedFlowsScroll")
            .toolbar { ToolbarItem(placement: .primaryAction) {
                Button { store.sheetSource = nil; store.sheet = .addPlan } label: { Image(systemName: "plus") }
                    .yubaiHitTarget().accessibilityLabel("加一个账单").accessibilityIdentifier("addFixedFlow")
            } }
            .sheet(item: $editingRate) { currency in
                NavigationStack { BillRateEditor(currency: currency) }.environment(store).appErrors().yubaiSheetBackground()
            }
    }
    private func monthHeader(_ month: BillCalendarMonth) -> some View {
        VStack(alignment: .leading, spacing: YubaiSpace.space8) {
            HStack {
                Text(date.formatted(.dateTime.year().month().locale(Locale(identifier: "zh_CN")))).yubaiFont(YubaiFont.heroLabel)
                Spacer()
                pageMonth(-1)
                pageMonth(1)
            }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: YubaiSpace.space8) { monthSummary(month) }
                VStack(alignment: .leading, spacing: YubaiSpace.space4) { monthSummary(month) }
            }
        }
    }
    @ViewBuilder private func monthSummary(_ month: BillCalendarMonth) -> some View {
        Text("这个月还要付").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
        AmountLabel(cents: month.remaining, hide: store.preferences.hideAmounts, role: .summary)
            .accessibilityIdentifier("fixedFlowRemaining")
        Text("\(month.unpaidCount) 笔 · 已付 " + amount2(month.paid, hide: store.preferences.hideAmounts))
            .yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary).fixedSize(horizontal: false, vertical: true)
    }
    private func pageMonth(_ offset: Int) -> some View {
        Button { shownMonth = Dates.addMonths(offset, to: snapshot.month); selectedDay = nil } label: {
            Image(systemName: offset < 0 ? "chevron.backward" : "chevron.forward")
                .yubaiFont(YubaiFont.caption).frame(width: YubaiSize.tapMin, height: YubaiSize.tapMin)
        }.buttonStyle(PressButtonStyle()).accessibilityLabel(offset < 0 ? "上个月" : "下个月")
            .accessibilityIdentifier(offset < 0 ? "billsPreviousMonth" : "billsNextMonth")
    }
    private func calendar(_ month: BillCalendarMonth) -> some View {
        Group {
            if textSize.isAccessibilitySize {
                ScrollView(.horizontal) { calendarGrid(month).frame(width: YubaiSize.calendarWide) }
            } else { calendarGrid(month) }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("billsCalendar")
    }
    private func calendarGrid(_ month: BillCalendarMonth) -> some View {
        VStack(spacing: YubaiSpace.space8) {
            LazyVGrid(columns: columns, spacing: YubaiSpace.none) {
                ForEach(Array(month.weekdaySymbols.enumerated()), id: \.offset) { _, name in
                    Text(name).accessibilityIdentifier("truncatableName").yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary).frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: columns, spacing: YubaiSpace.space8) {
                ForEach(0..<month.leadingDays, id: \.self) { _ in Color.clear.frame(height: YubaiSize.calendarCell).accessibilityHidden(true) }
                ForEach(month.days) { day in dayCell(day) }
            }
        }
    }
    private var columns: [GridItem] { Array(repeating: GridItem(.flexible(minimum: YubaiSpace.none), spacing: YubaiSpace.space4), count: 7) }
    private func dayCell(_ day: BillCalendarDay) -> some View {
        let today = Dates.day(day.date) == Dates.day(store.financialNow)
        let selected = selectedDay.map(Dates.day) == Dates.day(day.date)
        return Button { selectedDay = selected ? nil : day.date } label: {
            VStack(spacing: YubaiSpace.space4) {
                HStack(spacing: YubaiSpace.calendarGap) {
                    Text("\(Dates.calendar.component(.day, from: day.date))").yubaiFont(YubaiFont.meta, weight: today ? .semibold : .regular)
                    if day.yearly { Text("年").yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.canvas).padding(.horizontal, YubaiSpace.space2).background(YubaiColor.label, in: Capsule()) }
                }
                if day.payday && day.bills.count == 1 {
                    Text("工资").yubaiFont(YubaiFont.meta, weight: .semibold).foregroundStyle(YubaiColor.brandInk).fixedSize()
                } else if let first = day.bills.first {
                    cellIcon(first, more: day.bills.count - 1)
                    if day.payday { Text("工资").yubaiFont(YubaiFont.meta, weight: .semibold).foregroundStyle(YubaiColor.brandInk).fixedSize() }
                } else { Color.clear.frame(height: YubaiSize.pillHeight) }
            }.frame(maxWidth: .infinity, minHeight: textSize.isAccessibilitySize ? YubaiSize.calendarCellLarge : YubaiSize.calendarCell)
                .background(day.payday ? YubaiColor.brandTint : selected ? YubaiColor.raised : .clear, in: RoundedRectangle(cornerRadius: YubaiRadius.control))
                .overlay { RoundedRectangle(cornerRadius: YubaiRadius.control).strokeBorder(today ? YubaiColor.label : .clear, lineWidth: YubaiSize.outline) }
        }.buttonStyle(PressButtonStyle()).accessibilityElement(children: .ignore)
            .accessibilityLabel(Dates.text(day.date) + (today ? "，今天" : "") + (day.payday ? "，工资" : "") + (day.yearly ? "，年付" : "") + "，\(day.bills.count) 笔账单")
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityIdentifier("billsDay_" + Dates.text(day.date))
    }
    private func cellIcon(_ row: FixedFlowOccurrence, more: Int) -> some View {
        let plan = row.planID.flatMap { id in store.plans.first { $0.id == id } }
        let layout = textSize.isAccessibilitySize || more >= 10 ? AnyLayout(VStackLayout(spacing: YubaiSpace.calendarGap)) : AnyLayout(HStackLayout(spacing: YubaiSpace.calendarGap))
        return layout {
            BillBrandIcon(title: row.title, category: plan?.category ?? "居住", inflow: row.inflow, size: YubaiFont.amountLarge.size)
                .opacity(row.state == .paid ? 0.35 : 1)
            if more > 0 { Text("+\(more)").yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary).fixedSize() }
        }
    }
    private func upcoming(_ month: BillCalendarMonth) -> some View {
        let rows = Array(month.days.flatMap(\.bills).filter { $0.state != .paid && $0.date >= Dates.day(store.financialNow) }.prefix(2))
        return VStack(alignment: .leading, spacing: YubaiSpace.gapHeading) {
            SectionHeading(title: "接下来").padding(.horizontal, YubaiSpace.space4)
            if rows.isEmpty { EmptyState(.bills, onAction: { store.sheet = .addPlan }) }
            else { CardRows(rows) { BillCalendarRow(row: $0, includesDate: true) } }
        }.padding(.top, YubaiSpace.space8)
    }
    private func dayCard(_ day: Date, rows: [FixedFlowOccurrence]) -> some View {
        let currencies = Array(Set(rows.compactMap { row in store.plans.first { $0.id == row.planID }?.currency }.filter { $0 != .cny })).sorted { $0.rawValue < $1.rawValue }
        let total = rows.filter { !$0.inflow }.reduce(Int64(0)) { $0 + $1.amount }
        return Card(style: .list) {
            VStack(spacing: YubaiSpace.none) {
                ViewThatFits(in: .horizontal) {
                    HStack { dayTitle(day); Spacer(); dayTotal(total, approximate: !currencies.isEmpty) }
                    VStack(alignment: .leading, spacing: YubaiSpace.space4) { dayTitle(day); dayTotal(total, approximate: !currencies.isEmpty) }
                }.padding(.vertical, YubaiSpace.space12)
                ForEach(rows) { row in
                    EntryFormDivider()
                    BillCalendarRow(row: row)
                }
                if rows.isEmpty { EmptyState(.bills, onAction: { store.sheet = .addPlan }) }
                ForEach(currencies) { currency in
                    Button { editingRate = currency } label: {
                        BillRateLabel(currency: currency).padding(.vertical, YubaiSpace.space12).contentShape(Rectangle())
                    }.buttonStyle(PressButtonStyle()).accessibilityIdentifier("billsRate_" + currency.rawValue)
                }
            }
        }.accessibilityIdentifier("billsSelectedDay")
    }
    private func dayTitle(_ day: Date) -> some View {
        Text(FixedFlowPresentation.monthDay(day) + " · " + day.formatted(.dateTime.weekday(.abbreviated).locale(Locale(identifier: "zh_CN"))))
            .yubaiFont(YubaiFont.caption, weight: .semibold).fixedSize(horizontal: false, vertical: true)
    }
    private func dayTotal(_ total: Int64, approximate: Bool) -> some View {
        Text((approximate ? "合计约 " : "合计 ") + amount2(total, hide: store.preferences.hideAmounts))
            .yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary).fixedSize()
    }
    @ViewBuilder private var stoppedBills: some View {
        let rows = FixedFlowArrangement.stopped(in: store.current, now: store.financialNow)
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: YubaiSpace.gapHeading) {
                SectionHeading(title: "已停掉")
                CardRows(rows) { row in
                    VStack(alignment: .leading, spacing: YubaiSpace.space4) {
                        Text(row.title).accessibilityIdentifier("truncatableName").yubaiFont(YubaiFont.rowTitle).lineLimit(1)
                        Text(row.detail).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                        ChipFlow {
                            Button("恢复") {
                                do {
                                    let change = try FixedFlows.resume(id: row.id, in: store.current, now: store.financialNow)
                                    _ = store.apply(change, label: "恢复安排")
                                } catch { store.error = error.localizedDescription }
                            }.accessibilityIdentifier("resumeFixedFlow_" + row.id.uuidString)
                            if let plan = store.plans.first(where: { $0.id == row.id }) {
                                Button("改账单") { store.sheetSource = nil; store.sheet = .editPlan(plan.id) }
                                    .accessibilityIdentifier("editFixedFlow_" + plan.id.uuidString)
                            }
                            if !row.pending.isEmpty {
                                Button(row.inflow ? "收到了" : "付了") { resolveStopped(row, .settle) }
                                Button("不要了") { resolveStopped(row, .skip) }
                            }
                        }.buttonStyle(NowCardButtonStyle()).padding(.vertical, YubaiSpace.space8)
                    }.padding(.vertical, YubaiSpace.space8).accessibilityIdentifier("stoppedFixedFlow_" + row.id.uuidString)
                }
            }
        }
    }
    private func resolveStopped(_ row: FixedFlowArrangement, _ resolution: FixedFlowStopResolution) {
        do {
            let change = try FixedFlows.resolveStopped(planID: row.id, resolution: resolution, in: store.current, now: store.financialNow)
            _ = store.apply(change, label: row.inflow ? "收到了" : "付了")
        } catch { store.error = error.localizedDescription }
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
                TabNavigationLink(.billDetail(plan.id)) { BillDetailView(planID: plan.id) } label: { summary }
                    .buttonStyle(PressButtonStyle()).accessibilityIdentifier("editFixedFlow_" + plan.id.uuidString)
                    .billRowMenu(planID: plan.id, occurrence: row.date, enabled: row.state != .paid)
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
        if includesDate { value = ManualBookkeeping.dayLabel(row.date, now: store.financialNow) + " · " + value }
        if row.state == .paid { value += row.inflow ? " · 已收到" : " · 已付" }
        return value
    }
    @ViewBuilder private var amounts: some View {
        if let plan, plan.currency != .cny {
            VStack(alignment: .trailing, spacing: YubaiSpace.space2) {
                Text(plan.currency.amountText(plan.amount, hidden: store.preferences.hideAmounts)).yubaiFont(YubaiFont.amount)
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge).lineLimit(1).minimumScaleFactor(0.5)
                Text((row.state == .paid ? "实付 ¥" : "约 ¥") + amount2(row.amount, hide: store.preferences.hideAmounts))
                    .yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge).lineLimit(1).minimumScaleFactor(0.5)
                if row.state != .paid, FixedFlows.lastActual(planID: plan.id, in: store.current, now: store.financialNow) != nil {
                    Text("上次实付").yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary)
                }
            }
        } else { AmountLabel(cents: row.amount, hide: store.preferences.hideAmounts, role: .amount).fixedSize() }
    }
}

struct YearlyBillsStrip: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dynamicTypeSize) private var textSize
    let month: BillCalendarMonth
    var body: some View {
        TabNavigationLink(.yearlyBills) { YearlyBillsView() } label: {
            Card(style: .compact) {
                VStack(spacing: YubaiSpace.space8) {
                    ViewThatFits(in: .horizontal) {
                        HStack { title; Spacer(); monthly }
                        VStack(alignment: .leading, spacing: YubaiSpace.space4) { title; monthly }
                    }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: YubaiSpace.space4), count: textSize.isAccessibilitySize ? 4 : 12), spacing: YubaiSpace.space8) {
                        ForEach(1...12, id: \.self) { value in
                            VStack(spacing: YubaiSpace.space4) {
                                RoundedRectangle(cornerRadius: YubaiRadius.messageTail).fill(month.yearlyMonths.contains(value) ? YubaiColor.label : YubaiColor.neutralSoft).frame(height: YubaiSize.tagHeight)
                                    .overlay { RoundedRectangle(cornerRadius: YubaiRadius.messageTail).strokeBorder(Dates.calendar.component(.month, from: month.month) == value ? YubaiColor.label : .clear, lineWidth: YubaiSize.outline).padding(-YubaiSpace.space4) }
                                Text("\(value)").yubaiFont(YubaiFont.meta)
                            }.accessibilityLabel("\(value)月" + (month.yearlyMonths.contains(value) ? "，有年付账单" : ""))
                        }
                    }
                }
            }
        }.buttonStyle(PressButtonStyle()).accessibilityIdentifier("yearlyBillsStrip")
    }
    private var title: some View {
        Text("一年付一次的 · \(store.plans.filter { $0.active && $0.stoppedAt == nil && !$0.inflow && $0.frequency == .yearly }.count) 样")
            .yubaiFont(YubaiFont.caption, weight: .semibold)
    }
    private var monthly: some View {
        let value = YearlyBillReserves.rows(in: store.current, now: store.financialNow).reduce(Int64(0)) { $0 + $1.monthly }
        return Text("每月先留 " + amount2(value, hide: store.preferences.hideAmounts)).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge).lineLimit(1).minimumScaleFactor(0.5)
    }
}

struct YearlyBillsView: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        let rows = YearlyBillReserves.rows(in: store.current, now: store.financialNow)
        Page {
            Card(style: .list) {
                Toggle("每月先留", isOn: Binding(get: { store.preferences.yearlyBillsSetAside != false }, set: { value in
                    _ = store.update("每月先留", entryMotion: false) { YearlyBillReserves.setEnabled(value, in: &$0, now: store.financialNow) }
                })).yubaiFont(YubaiFont.row).tint(YubaiColor.toggleOn).frame(minHeight: YubaiSize.buttonHeight).accessibilityIdentifier("yearlyBillsSetAside")
            }
            CardRows(store.plans.filter { $0.active && $0.stoppedAt == nil && !$0.inflow && $0.frequency == .yearly }) { plan in
                TabNavigationLink(.billDetail(plan.id)) { BillDetailView(planID: plan.id) } label: {
                    VStack(alignment: .leading, spacing: YubaiSpace.space4) {
                        Text(plan.title).accessibilityIdentifier("truncatableName").yubaiFont(YubaiFont.rowTitle).lineLimit(1)
                        if let row = rows.first(where: { $0.id == plan.id }) {
                            Text("每月先留 " + amount2(row.monthly, hide: store.preferences.hideAmounts)).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                                .dynamicTypeSize(...DynamicTypeSize.xxxLarge).lineLimit(1).minimumScaleFactor(0.5)
                        }
                    }.frame(maxWidth: .infinity, minHeight: YubaiSize.sourceRow, alignment: .leading)
                }.buttonStyle(PressButtonStyle())
            }
        }.navigationTitle("一年付一次的").yubaiNavigation().accessibilityIdentifier("yearlyBillsPage")
    }
}
