import SwiftUI
import Charts
import YubaiCore
#if os(iOS)
import UIKit
#endif

struct CashTimelineCard: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var windowStart: Date?
    @State private var panStart: Date?
    @State private var selectedDay: Date?
    @State private var holding = false
    @State private var selectionTrigger = 0
    #if os(macOS)
    @State private var pointerLocation: CGPoint?
    #endif
    let timeline: CashTimeline

    private var window: CashTimelineWindow { timeline.window(startingAt: windowStart) }
    private var selected: CashTimelinePoint? { selectedDay.flatMap { window.point(on: $0) } }
    private var warningInk: Color { window.belowFloor ? YubaiColor.amberInk : YubaiColor.label }
    private var hidden: Bool { store.current.preferences.hideAmounts }

    var body: some View {
        let visible = window
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: YubaiSpace.space8) {
                Text("现金会怎么走").yubaiFont(YubaiFont.cardTitle)
                Spacer(minLength: YubaiSpace.space8)
                if let selected {
                    Text(monthDay(selected.date)).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                } else if !visible.isDefault {
                    Button { windowStart = nil; panStart = nil; selectedDay = nil } label: {
                        Text("今天 ›").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.label)
                            .padding(.horizontal, 10).padding(.vertical, 3)
                            .background(YubaiColor.raised, in: Capsule())
                            .contentShape(Rectangle().inset(by: -10))
                    }.buttonStyle(PressButtonStyle()).accessibilityIdentifier("cashTimelineToday")
                        .accessibilityLabel("回到今天").accessibilityHint("恢复最近两个月到预测截止日的窗口")
                } else {
                    Text("到 " + monthDay(timeline.end)).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                }
            }
            if hidden {
                Text("金额已隐藏").yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary)
                    .frame(maxWidth: .infinity, minHeight: 190, alignment: .leading)
            } else {
                readout(visible).padding(.top, 4)
                plot(visible).padding(.top, 10)
                indicator(visible).padding(.top, 8)
            }
        }.padding(.horizontal, YubaiSpace.insetCard).padding(.top, 14).padding(.bottom, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(YubaiColor.card, in: RoundedRectangle(cornerRadius: YubaiRadius.card))
            .accessibilityElement(children: .contain).accessibilityIdentifier("cashTimelineCard")
            .onChange(of: timeline.today) { _, _ in windowStart = nil; selectedDay = nil; panStart = nil }
            .onChange(of: hidden) { _, _ in selectedDay = nil; holding = false; panStart = nil }
            .onDisappear { selectedDay = nil; holding = false; panStart = nil }
    }

    @ViewBuilder private func readout(_ visible: CashTimelineWindow) -> some View {
        let layout = textSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
        layout {
            if let selected {
                amount(selected.balance, ink: YubaiColor.label)
                if !selected.events.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(selected.events) { event in
                            Text(eventText(event)).yubaiFont(YubaiFont.caption)
                                .foregroundStyle(event.amount >= 0 ? YubaiColor.brandInk : YubaiColor.labelSecondary)
                        }
                    }
                }
            } else if let low = visible.minimum {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("最低").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                    amount(low.balance, ink: warningInk)
                    Text(monthDay(low.date)).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                }.accessibilityElement(children: .combine).accessibilityIdentifier("cashTimelineMinimum")
                if !textSize.isAccessibilitySize { Spacer(minLength: 0) }
                if visible.belowFloor, let floor = visible.floor {
                    HStack(spacing: 5) {
                        Line().stroke(YubaiColor.amberInk, style: StrokeStyle(lineWidth: 1, dash: [3, 2])).frame(width: 14, height: 1)
                            .accessibilityHidden(true)
                        Text("始终留着 " + Money.text(floor, currency: false)).yubaiFont(YubaiFont.caption)
                    }.foregroundStyle(YubaiColor.amberInk).fixedSize(horizontal: true, vertical: false)
                        .accessibilityIdentifier("cashTimelineFloor")
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("cashTimelineReadout")
    }

    private func amount(_ cents: Int64, ink: Color) -> some View {
        Text(Money.text(cents, currency: false)).yubaiFont(YubaiFont.amountDonut)
            .monospacedDigit().foregroundStyle(ink).fixedSize(horizontal: true, vertical: false)
    }

    private func plot(_ visible: CashTimelineWindow) -> some View {
        Chart {
            ForEach(visible.forecastLine) { point in
                AreaMark(x: .value("日期", point.date), yStart: .value("下界", money(point.lower)), yEnd: .value("上界", money(point.upper)))
                    .foregroundStyle(YubaiColor.brand.opacity(0.14)).interpolationMethod(.linear)
            }
            if visible.showsZero {
                RuleMark(y: .value("零点", 0)).foregroundStyle(YubaiColor.neutralSoft).lineStyle(StrokeStyle(lineWidth: 1))
            }
            if visible.belowFloor, let floor = visible.floor {
                RuleMark(y: .value("始终留着", money(floor)))
                    .foregroundStyle(YubaiColor.amberDot).lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
            ForEach(visible.history) { point in
                LineMark(x: .value("日期", point.date), y: .value("现金", money(point.balance)), series: .value("段", "过去"))
                    .foregroundStyle(YubaiColor.brand).lineStyle(StrokeStyle(lineWidth: 2, lineJoin: .round)).interpolationMethod(.linear)
            }
            ForEach(visible.forecastLine) { point in
                LineMark(x: .value("日期", point.date), y: .value("现金", money(point.balance)), series: .value("段", "预测"))
                    .foregroundStyle(YubaiColor.brand).lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 3])).interpolationMethod(.linear)
            }
            if timeline.today >= visible.start && timeline.today <= visible.end {
                RuleMark(x: .value("今天", timeline.today)).foregroundStyle(YubaiColor.chartGuide)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
            }
            if let low = visible.minimum {
                PointMark(x: .value("最低日期", low.date), y: .value("最低现金", money(low.balance)))
                    .symbol { Circle().fill(visible.belowFloor ? YubaiColor.amberDot : YubaiColor.brandInk)
                        .frame(width: 8, height: 8).overlay { Circle().stroke(YubaiColor.card, lineWidth: 2) } }
            }
            if let selected {
                RuleMark(x: .value("选中日期", selected.date)).foregroundStyle(YubaiColor.label).lineStyle(StrokeStyle(lineWidth: 1))
                PointMark(x: .value("选中日期", selected.date), y: .value("现金", money(selected.balance)))
                    .symbol { Circle().fill(YubaiColor.label).frame(width: 8, height: 8).overlay { Circle().stroke(YubaiColor.card, lineWidth: 2) } }
            }
        }.chartLegend(.hidden).chartYAxis(.hidden)
            .chartXScale(domain: visible.start...visible.end, range: .plotDimension(padding: 4))
            .chartYScale(domain: yDomain(visible), range: .plotDimension(padding: 8))
            .chartXAxis {
                AxisMarks(values: axisDates(visible)) { value in
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(date == timeline.today ? "今天" : monthDay(date)).yubaiFont(YubaiFont.chartLabel)
                                .foregroundStyle(YubaiColor.labelSecondary)
                        }
                    }
                }
            }.chartOverlay { proxy in
                GeometryReader { geometry in
                    if let plot = proxy.plotFrame {
                        touchSurface(proxy, frame: geometry[plot])
                    }
                }
            }.frame(height: 150)
            .accessibilityElement(children: .ignore).accessibilityIdentifier("cashTimelineChart")
            .accessibilityLabel("现金会怎么走")
            .accessibilityValue(accessibilityValue(visible))
            .accessibilityHint("上下轻扫逐天查看；左右拖动看更早，长按后拖动查看一天")
            .accessibilityAdjustableAction { direction in
                let points = visible.history + visible.forecast.filter { $0.date > timeline.today }
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

    @ViewBuilder private func touchSurface(_ proxy: ChartProxy, frame: CGRect) -> some View {
        #if os(iOS)
        Rectangle().fill(.clear).contentShape(Rectangle())
            .gesture(HorizontalPan(shouldBegin: { _ in !holding }, changed: { distance in
                pan(distance, width: frame.width)
            }, ended: { distance, _ in
                pan(distance, width: frame.width); panStart = nil
            }, cancelled: { panStart = nil }))
            .simultaneousGesture(CashTimelinePress(changed: { location in
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
            .simultaneousGesture(DragGesture(minimumDistance: 10).onChanged { value in
                guard !holding, abs(value.translation.width) > abs(value.translation.height) else { return }
                pan(value.translation.width, width: frame.width)
            }.onEnded { _ in panStart = nil })
            .accessibilityHidden(true)
        #endif
    }

    private func pan(_ distance: CGFloat, width: CGFloat) {
        guard !holding, width > 0 else { return }
        if panStart == nil { panStart = window.start; selectedDay = nil }
        let days = Int((Double(distance / width) * Double(timeline.visibleDays)).rounded())
        windowStart = timeline.window(startingAt: Dates.addDays(-days, to: panStart ?? window.start)).start
    }

    private func scrub(_ x: CGFloat, proxy: ChartProxy, frame: CGRect) {
        guard let date: Date = proxy.value(atX: min(frame.width, max(0, x - frame.minX))) else { return }
        let candidates = window.history + window.forecast.filter { $0.date > timeline.today }
        if let point = candidates.min(by: { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }) { select(point.date) }
    }

    private func select(_ day: Date) {
        if selectedDay != day { selectedDay = day; selectionTrigger &+= 1 }
    }

    private func indicator(_ visible: CashTimelineWindow) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(YubaiColor.neutralSoft).frame(height: 2)
                Capsule().fill(YubaiColor.labelSecondary.opacity(0.55))
                    .frame(width: geometry.size.width * visible.indicatorLength, height: 4)
                    .offset(x: geometry.size.width * visible.indicatorStart)
            }.frame(height: 4)
        }.frame(height: 4).allowsHitTesting(false).accessibilityHidden(true)
    }

    private func yDomain(_ visible: CashTimelineWindow) -> ClosedRange<Double> {
        var values = (visible.history + visible.forecast).flatMap { [money($0.lower), money($0.upper)] }
        values += visible.forecastLine.flatMap { [money($0.lower), money($0.upper)] }
        if visible.belowFloor, let floor = visible.floor { values.append(money(floor)) }
        if visible.showsZero { values.append(0) }
        let lower = values.min() ?? 0, upper = values.max() ?? 0
        let pad = max(1, (upper - lower) * 0.08)
        return (lower - pad)...(upper + pad)
    }

    private func axisDates(_ visible: CashTimelineWindow) -> [Date] {
        var dates: [Date] = []
        // Payday/day-of-month positions match the approved two-month reference.
        for index in -6...0 {
            let day = Dates.addMonths(index, to: timeline.end)
            if day >= visible.start && day <= min(visible.end, Dates.addDays(-7, to: timeline.today)) { dates.append(day) }
        }
        if timeline.today >= visible.start && timeline.today <= visible.end { dates.append(timeline.today) }
        return dates.sorted()
    }

    private func accessibilityValue(_ visible: CashTimelineWindow) -> String {
        if let selected { return monthDay(selected.date) + "，余额 " + Money.text(selected.balance) + "。" + selected.events.map(eventText).joined(separator: "；") }
        guard let low = visible.minimum else { return "" }
        return monthDay(visible.start) + "至" + monthDay(visible.end) + "，最低 " + Money.text(low.balance) + "，" + monthDay(low.date)
            + (visible.belowFloor ? "，低于始终留着" : "")
    }
    private func eventText(_ event: CashTimelineEvent) -> String {
        event.title + " " + (event.amount >= 0 ? "+" : "−") + Money.text(abs(event.amount), currency: false)
    }
    private func monthDay(_ date: Date) -> String { FixedFlowPresentation.monthDay(date) }
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
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
            guard let scroll = other.view as? UIScrollView else { return false }
            return other === scroll.panGestureRecognizer
        }
    }
}
#endif
