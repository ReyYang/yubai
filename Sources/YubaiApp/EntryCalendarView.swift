import SwiftUI
import YubaiCore

/// 月历：今天描边，未来日期变灰但仍可选；拆分可传入原差额的日期范围。
struct EntryCalendarView: View {
    @Binding var selection: Date
    let today: Date
    var bounds: ClosedRange<Date>? = nil
    var identifier = "entryCalendar"
    @State private var month: Date
    @ScaledMetric(relativeTo: .callout) private var dayWidth = YubaiSize.tapMin

    init(selection: Binding<Date>, today: Date, bounds: ClosedRange<Date>? = nil, identifier: String = "entryCalendar") {
        _selection = selection; self.today = today; self.bounds = bounds; self.identifier = identifier
        _month = State(initialValue: Dates.calendar.dateInterval(of: .month, for: selection.wrappedValue)!.start)
    }
    private var monthTitle: String {
        "\(Dates.calendar.component(.year, from: month))年\(Dates.calendar.component(.month, from: month))月"
    }
    private var leading: Int { (Dates.calendar.component(.weekday, from: month) + 5) % 7 }
    private var count: Int { Dates.calendar.range(of: .day, in: .month, for: month)?.count ?? 0 }
    var body: some View {
        VStack(alignment: .leading, spacing: YubaiSpace.space8) {
            monthHeader
            ScrollView(.horizontal, showsIndicators: false) {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(dayWidth), spacing: YubaiSpace.space4), count: 7), spacing: YubaiSpace.space4) {
                    ForEach(Array(["一", "二", "三", "四", "五", "六", "日"].enumerated()), id: \.offset) { _, day in
                        Text(day).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary).frame(width: dayWidth).frame(minHeight: YubaiSize.tapMin)
                    }
                    ForEach(0..<(leading + count), id: \.self) { index in
                        if index < leading { Color.clear.frame(width: dayWidth, height: dayWidth).accessibilityHidden(true) }
                        else { dayButton(Dates.addDays(index - leading, to: month)) }
                    }
                }.frame(minWidth: dayWidth * 7 + YubaiSpace.space4 * 6)
            }
        }.accessibilityElement(children: .contain).accessibilityIdentifier(identifier)
    }
    private var monthHeader: some View {
        HStack(spacing: YubaiSpace.space8) {
            Text(monthTitle).yubaiFont(YubaiFont.rowTitle, weight: .semibold).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: YubaiSpace.space8)
            monthButton(-1, symbol: "chevron.left", label: "上个月")
            monthButton(1, symbol: "chevron.right", label: "下个月")
        }
    }
    private func monthButton(_ offset: Int, symbol: String, label: String) -> some View {
        Button { month = Dates.addMonths(offset, to: month) } label: {
            Image(systemName: symbol).yubaiFont(YubaiFont.callout)
                .frame(width: YubaiSize.tapMin, height: YubaiSize.tapMin).contentShape(Rectangle())
        }.buttonStyle(PressButtonStyle()).accessibilityLabel(label)
            .accessibilityIdentifier(identifier + (offset < 0 ? "Previous" : "Next"))
    }
    private func dayButton(_ day: Date) -> some View {
        let selected = Dates.calendar.isDate(day, inSameDayAs: selection)
        let current = Dates.calendar.isDate(day, inSameDayAs: today)
        let future = day > Dates.day(today)
        let allowed = bounds.map { day >= Dates.day($0.lowerBound) && day <= Dates.day($0.upperBound) } ?? true
        return Button { choose(day) } label: {
            Text("\(Dates.calendar.component(.day, from: day))").yubaiFont(YubaiFont.row)
                .foregroundStyle(selected ? YubaiColor.canvas : future || !allowed ? YubaiColor.labelSecondary : YubaiColor.label)
                .frame(width: dayWidth, height: dayWidth)
                .background { if selected { Circle().fill(YubaiColor.label) } }
                .overlay { if current { Circle().strokeBorder(YubaiColor.brand, lineWidth: YubaiSize.lineWidth) } }
                .contentShape(Circle())
        }.buttonStyle(PressButtonStyle()).disabled(!allowed).opacity(allowed ? 1 : 0.4)
            .accessibilityLabel(FixedFlowPresentation.monthDay(day)).accessibilityValue(future ? "未来" : "")
            .accessibilityAddTraits(selected ? .isSelected : []).accessibilityIdentifier(identifier + "Day_" + Dates.text(day))
    }
    private func choose(_ day: Date) {
        let calendar = Dates.calendar
        selection = calendar.date(bySettingHour: calendar.component(.hour, from: selection), minute: calendar.component(.minute, from: selection),
                                  second: calendar.component(.second, from: selection), of: day) ?? day
    }
}
