import SwiftUI
import Charts
import YubaiCore
#if os(iOS)
import UIKit
#endif

struct CashTimelineCard: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var cycleOffset = 0
    @State private var selectedDay: Date?
    @State private var holding = false
    @State private var selectionTrigger = 0
    #if os(macOS)
    @State private var pointerLocation: CGPoint?
    #endif
    let timeline: CashTimeline

    private var window: CashTimelineWindow { timeline.window(cycleOffset: cycleOffset) }
    private var selected: CashTimelinePoint? { selectedDay.flatMap { window.point(on: $0) } }
    private var hidden: Bool { store.current.preferences.hideAmounts }

    var body: some View {
        let visible = window
        VStack(alignment: .leading, spacing: YubaiSpace.none) {
            HStack(alignment: .firstTextBaseline, spacing: YubaiSpace.space8) {
                Text("现金会怎么走").yubaiFont(YubaiFont.cardTitle)
                Spacer(minLength: YubaiSpace.space8)
                if let selected {
                    Text(FixedFlowPresentation.monthDay(selected.date)).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                } else if !visible.isDefault {
                    Button { cycleOffset = 0; selectedDay = nil } label: {
                        Text("这个月 ›").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.brandInk)
                            .padding(.horizontal, YubaiSpace.space10).padding(.vertical, 5)
                            .background(YubaiColor.raised, in: Capsule())
                            .contentShape(Rectangle().inset(by: -8))
                    }.buttonStyle(PressButtonStyle()).accessibilityIdentifier("cashTimelineToday")
                        .accessibilityLabel("回到这个月").accessibilityHint("显示当前发薪周期")
                } else {
                    Text(dateRange(visible)).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                }
            }
            if hidden {
                Text("金额已隐藏").yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary)
                    .frame(maxWidth: .infinity, minHeight: 220, alignment: .leading)
            } else {
                readout(visible).padding(.top, YubaiSpace.space6)
                plot(visible).padding(.top, YubaiSpace.space10)
                HStack(spacing: 14) {
                    legend(visible.isDefault ? "这个月" : shortDate(visible.start) + " 起", ink: YubaiColor.brand, width: 2)
                    legend(visible.isDefault ? "上个月" : shortDate(visible.cycle.previousStart) + " 起", ink: YubaiColor.labelSecondary.opacity(0.35), width: 1.2)
                }.padding(.top, YubaiSpace.space8).accessibilityIdentifier("cashTimelineLegend")
            }
        }.padding(.horizontal, YubaiSpace.insetCard).padding(.top, 14).padding(.bottom, YubaiSpace.space12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .paperCardSurface(in: RoundedRectangle(cornerRadius: YubaiRadius.card))
            .accessibilityElement(children: .contain).accessibilityIdentifier("cashTimelineCard")
            .onChange(of: timeline.cycles) { _, _ in cycleOffset = 0; selectedDay = nil; holding = false }
            .onChange(of: hidden) { _, _ in selectedDay = nil; holding = false }
            .onDisappear { selectedDay = nil; holding = false }
    }

    private func readout(_ visible: CashTimelineWindow) -> some View {
        VStack(alignment: .leading, spacing: YubaiSpace.space2) {
            let layout = textSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: YubaiSpace.space4))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: YubaiSpace.space8))
            layout {
                HStack(alignment: .firstTextBaseline, spacing: YubaiSpace.space8) {
                    Text(readoutTitle(visible)).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                    Text(amountText(selected?.balance ?? visible.endpoint?.balance ?? 0))
                        .yubaiFont(YubaiFont.amountDonut).monospacedDigit()
                        .foregroundStyle(selected == nil && visible.belowFloor ? YubaiColor.amberInk : YubaiColor.label)
                        .fixedSize(horizontal: true, vertical: false)
                }.accessibilityElement(children: .combine).accessibilityIdentifier("cashTimelineMinimum")
                if selected == nil && visible.belowFloor, let floor = visible.floor {
                    if !textSize.isAccessibilitySize { Spacer(minLength: YubaiSpace.none) }
                    HStack(spacing: YubaiSpace.space4) {
                        Line().stroke(YubaiColor.amberInk, style: StrokeStyle(lineWidth: 1, dash: [3, 2])).frame(width: 14, height: 1)
                        Text("始终留着 " + Money.text(floor, currency: false)).yubaiFont(YubaiFont.caption)
                    }.foregroundStyle(YubaiColor.amberInk).fixedSize(horizontal: true, vertical: false)
                        .accessibilityIdentifier("cashTimelineFloor")
                }
            }
            Text(detail(visible)).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                .accessibilityIdentifier("cashTimelineComparison")
        }.frame(maxWidth: .infinity, alignment: .leading).accessibilityIdentifier("cashTimelineReadout")
    }

    private func readoutTitle(_ visible: CashTimelineWindow) -> String {
        if selected != nil { return "当天余额" }
        if timeline.hasPayday { return visible.isDefault ? "发工资前还剩" : "发工资前剩下" }
        return visible.isDefault ? "月底还剩" : "月底剩下"
    }

    private func detail(_ visible: CashTimelineWindow) -> String {
        if let selected {
            var facts: [String] = []
            if let event = selected.events.first { facts.append(eventText(event)) }
            if let prior = visible.previousPoint(on: selected.date) { facts.append("上个月同一天 " + amountText(prior.balance)) }
            return facts.joined(separator: " · ")
        }
        let comparison = visible.difference.map {
            (visible.isDefault ? "比上个月同一天" : "比上个月") + ($0 >= 0 ? "多 " : "少 ") + Money.text(abs($0), currency: false)
        }
        return ([visible.isDefault ? nil : dateRange(visible), comparison].compactMap { $0 }).joined(separator: " · ")
    }

    private func legend(_ title: String, ink: Color, width: CGFloat) -> some View {
        HStack(spacing: 5) {
            Line().stroke(ink, lineWidth: width).frame(width: 14, height: 2).accessibilityHidden(true)
            Text(title).yubaiFont(YubaiFont.caption)
        }.foregroundStyle(YubaiColor.labelSecondary)
    }

    private func plot(_ visible: CashTimelineWindow) -> some View {
        let scale = CashTimelineScale(window: visible)
        return Chart {
            if visible.showsZero {
                RuleMark(y: .value("零点", 0)).foregroundStyle(YubaiColor.neutralSoft).lineStyle(StrokeStyle(lineWidth: 1))
            }
            if visible.belowFloor, let floor = visible.floor {
                RuleMark(y: .value("始终留着", money(floor)))
                    .foregroundStyle(YubaiColor.amberDot).lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
            ForEach(visible.previous) { point in
                LineMark(x: .value("日期", point.date), y: .value("余额", money(point.balance)), series: .value("段", "上周期"))
                    .foregroundStyle(YubaiColor.labelSecondary.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1.2, lineJoin: .round)).interpolationMethod(.linear)
            }
            ForEach(visible.history) { point in
                LineMark(x: .value("日期", point.date), y: .value("余额", money(point.balance)), series: .value("段", "本周期"))
                    .foregroundStyle(YubaiColor.brand).lineStyle(StrokeStyle(lineWidth: 2.2, lineJoin: .round)).interpolationMethod(.linear)
            }
            ForEach(visible.forecastLine) { point in
                LineMark(x: .value("日期", point.date), y: .value("余额", money(point.balance)), series: .value("段", "预测"))
                    .foregroundStyle(YubaiColor.brand).lineStyle(StrokeStyle(lineWidth: 2.2, dash: [4, 3])).interpolationMethod(.linear)
            }
            if visible.isDefault, let today = visible.history.last {
                PointMark(x: .value("今天", today.date), y: .value("余额", money(today.balance)))
                    .symbol { Circle().fill(YubaiColor.brand).frame(width: 7, height: 7) }
                if let end = visible.endpoint {
                    PointMark(x: .value("周期终点", end.date), y: .value("余额", money(end.balance)))
                        .symbol { Circle().fill(YubaiColor.paperSheet).frame(width: 8, height: 8)
                            .overlay { Circle().stroke(visible.belowFloor ? YubaiColor.amberDot : YubaiColor.brandInk, lineWidth: 2) } }
                }
            }
            if let selected {
                RuleMark(x: .value("选中日期", selected.date)).foregroundStyle(YubaiColor.label).lineStyle(StrokeStyle(lineWidth: 1))
                PointMark(x: .value("选中日期", selected.date), y: .value("余额", money(selected.balance)))
                    .symbol { Circle().fill(YubaiColor.label).frame(width: 8, height: 8).overlay { Circle().stroke(YubaiColor.paperSheet, lineWidth: 2) } }
            }
        }.chartLegend(.hidden)
            .chartXScale(domain: visible.start...visible.end, range: .plotDimension(padding: 4))
            .chartYScale(domain: scale.domain)
            .chartYAxis {
                AxisMarks(position: .trailing, values: scale.ticks) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6)).foregroundStyle(YubaiColor.neutralSoft)
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            Text(CashTimelineScale.label(number)).yubaiFont(YubaiFont.chartLabel).foregroundStyle(YubaiColor.labelSecondary)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: axisDates(visible)) { value in
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(date == timeline.today ? "今天" : shortDate(date)).yubaiFont(YubaiFont.chartLabel).foregroundStyle(YubaiColor.labelSecondary)
                        }
                    }
                }
            }.chartOverlay { proxy in
                GeometryReader { geometry in
                    if let plot = proxy.plotFrame {
                        annotations(visible, proxy: proxy, frame: geometry[plot]).allowsHitTesting(false).accessibilityHidden(true)
                        touchSurface(proxy, frame: geometry[plot])
                    }
                }
            }.frame(height: textSize.isAccessibilitySize ? 210 : 170)
            .accessibilityElement(children: .ignore).accessibilityIdentifier("cashTimelineChart")
            .accessibilityLabel("现金会怎么走").accessibilityValue(accessibilityValue(visible))
            .accessibilityHint("上下轻扫逐天查看；右滑看上个周期，左滑看下个周期，长按后拖动查看一天")
            .accessibilityAdjustableAction { direction in
                let points = visible.points
                guard !points.isEmpty else { return }
                let index = points.firstIndex { $0.date == selectedDay } ?? (points.firstIndex { $0.date == timeline.today } ?? 0)
                switch direction {
                case .increment: select(points[min(points.count - 1, index + 1)].date)
                case .decrement: select(points[max(0, index - 1)].date)
                @unknown default: break
                }
            }
            #if os(iOS)
            .sensoryFeedback(.selection, trigger: selectionTrigger)
            #endif
    }

    /// Measure rendered text, keep the largest first and reject intersecting labels.
    /// Eight card-colored copies form an outline without a rectangular label box.
    private func annotations(_ visible: CashTimelineWindow, proxy: ChartProxy, frame: CGRect) -> some View {
        Canvas { context, _ in
            var occupied: [CGRect] = []
            for event in visible.annotations {
                guard let point = visible.history.first(where: { $0.date == event.date }),
                      let x = proxy.position(forX: event.date), let y = proxy.position(forY: money(point.balance)) else { continue }
                let title = annotationText(event)
                let text: Text = Text(title).font(.system(size: YubaiFont.chartLabel.size))
                let resolved: GraphicsContext.ResolvedText = context.resolve(text.foregroundStyle(event.isSalary ? YubaiColor.brandInk : YubaiColor.labelSecondary))
                let size: CGSize = resolved.measure(in: CGSize(width: CGFloat.infinity, height: CGFloat.infinity))
                guard size.width <= frame.width, size.height <= frame.height else { continue }
                let halfWidth: CGFloat = size.width / 2
                let halfHeight: CGFloat = size.height / 2
                let verticalOffset: CGFloat = event.amount > 0 ? -12 : 12
                let centerX: CGFloat = min(frame.maxX - halfWidth, max(frame.minX + halfWidth, frame.minX + x))
                let centerY: CGFloat = min(frame.maxY - halfHeight, max(frame.minY + halfHeight, frame.minY + y + verticalOffset))
                let center = CGPoint(x: centerX, y: centerY)
                let rect = CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height).insetBy(dx: -3, dy: -2)
                guard !occupied.contains(where: { $0.intersects(rect) }) else { continue }
                occupied.append(rect)
                let outline: GraphicsContext.ResolvedText = context.resolve(text.foregroundStyle(YubaiColor.paperSheet))
                for dx: CGFloat in [-1.5, 0.0, 1.5] {
                    for dy: CGFloat in [-1.5, 0.0, 1.5] where dx != 0 || dy != 0 {
                        context.draw(outline, at: CGPoint(x: center.x + dx, y: center.y + dy))
                    }
                }
                context.draw(resolved, at: center)
            }
        }
    }

    @ViewBuilder private func touchSurface(_ proxy: ChartProxy, frame: CGRect) -> some View {
        #if os(iOS)
        Rectangle().fill(.clear).contentShape(Rectangle())
            .gesture(HorizontalPan(shouldBegin: { _ in !holding }, changed: { _ in selectedDay = nil }, ended: { distance, velocity in
                switchCycle(distance, velocity: velocity, width: frame.width)
            }))
            .gesture(CashTimelinePress(changed: { location in
                holding = true; scrub(location.x, proxy: proxy, frame: frame)
            }, ended: { holding = false; selectedDay = nil }))
            .accessibilityHidden(true)
        #else
        Rectangle().fill(.clear).contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location): pointerLocation = location
                case .ended: pointerLocation = nil
                }
            }
            .gesture(LongPressGesture(minimumDuration: 0.25, maximumDistance: 10).sequenced(before: DragGesture(minimumDistance: 0))
                .onChanged { value in
                    if case .second(true, let drag) = value {
                        holding = true
                        if let location = drag?.location ?? pointerLocation { scrub(location.x, proxy: proxy, frame: frame) }
                    }
                }.onEnded { _ in holding = false; selectedDay = nil })
            .simultaneousGesture(DragGesture(minimumDistance: 10).onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                switchCycle(value.translation.width, velocity: 0, width: frame.width)
            }).accessibilityHidden(true)
        #endif
    }

    private func switchCycle(_ distance: CGFloat, velocity: CGFloat, width: CGFloat) {
        guard !holding, width > 0, abs(distance) > width * 0.2 || abs(velocity) > 500 else { return }
        cycleOffset = min(timeline.cycles.count - 1, max(0, cycleOffset + (distance > 0 ? 1 : -1)))
        selectedDay = nil
    }
    private func scrub(_ x: CGFloat, proxy: ChartProxy, frame: CGRect) {
        guard let date: Date = proxy.value(atX: min(frame.width, max(0, x - frame.minX))) else { return }
        if let point = window.points.min(by: { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }) { select(point.date) }
    }
    private func select(_ day: Date) {
        if selectedDay != day { selectedDay = day; selectionTrigger &+= 1 }
    }
    private func axisDates(_ visible: CashTimelineWindow) -> [Date] {
        Array(Set([visible.start, visible.end] + (visible.isDefault ? [timeline.today] : []))).sorted()
    }
    private func accessibilityValue(_ visible: CashTimelineWindow) -> String {
        if let selected { return FixedFlowPresentation.monthDay(selected.date) + "，当天余额 " + Money.text(selected.balance) + "，" + detail(visible) }
        return dateRange(visible) + "，" + readoutTitle(visible) + " " + Money.text(visible.endpoint?.balance ?? 0)
            + "，" + detail(visible) + (visible.belowFloor ? "，低于始终留着" : "")
    }
    private func annotationText(_ event: CashTimelineEvent) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "zh_CN"); formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0; formatter.maximumFractionDigits = 0
        let amount = formatter.string(from: NSDecimalNumber(decimal: Decimal(abs(event.amount)) / 100)) ?? "0"
        return (event.isSalary ? "工资" : event.title) + " " + (event.amount >= 0 ? "+" : "−") + amount
    }
    private func amountText(_ cents: Int64) -> String {
        (cents < 0 ? "−" : "") + Money.text(abs(cents), currency: false)
    }
    private func eventText(_ event: CashTimelineEvent) -> String {
        event.title + " " + (event.amount >= 0 ? "+" : "−") + Money.text(abs(event.amount), currency: false)
    }
    private func dateRange(_ visible: CashTimelineWindow) -> String { shortDate(visible.start) + " – " + shortDate(visible.end) }
    private func shortDate(_ date: Date) -> String { "\(Dates.calendar.component(.month, from: date))/\(Dates.calendar.component(.day, from: date))" }
    private func money(_ cents: Int64) -> Double { Double(cents) / 100 }
    private struct Line: Shape {
        func path(in rect: CGRect) -> Path { Path { $0.move(to: CGPoint(x: rect.minX, y: rect.midY)); $0.addLine(to: CGPoint(x: rect.maxX, y: rect.midY)) } }
    }
}

#if os(iOS)
/// A stationary hold selects immediately. A moving horizontal finger is handled
/// by HorizontalPan; both recognizers take precedence over the root pager.
private struct CashTimelinePress: UIGestureRecognizerRepresentable {
    var changed: (CGPoint) -> Void
    var ended: () -> Void
    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let press = UILongPressGestureRecognizer()
        press.minimumPressDuration = 0.25; press.allowableMovement = 10
        press.delegate = context.coordinator
        return press
    }
    func updateUIGestureRecognizer(_ recognizer: UILongPressGestureRecognizer, context: Context) {}
    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }
    func handleUIGestureRecognizerAction(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        switch recognizer.state {
        case .began, .changed: changed(context.converter.location(in: .local))
        case .ended, .cancelled, .failed: ended()
        default: break
        }
    }
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            // HorizontalPan also returns false for this pair. UIKit lets the
            // first recognizer win: an early pan or a stationary 0.25s hold.
            // Once the hold begins, moving the finger only scrubs the chart.
            false
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
            guard let scroll = other.view as? UIScrollView else { return false }
            return other === scroll.panGestureRecognizer
        }
    }
}
#endif
