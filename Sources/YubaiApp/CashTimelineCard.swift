import SwiftUI
import Charts
import YubaiCore
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct CashTimelineCard: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dynamicTypeSize) private var textSize
    @ScaledMetric(relativeTo: .caption2) private var annotationSize: CGFloat = 10
    @State private var cycleOffset = 0
    @State private var plotWidth: CGFloat = 280
    @State private var selectedDay: Date?
    @State private var holding = false
    @State private var selectionTrigger = 0
    #if os(macOS)
    @State private var pointerLocation: CGPoint?
    @State private var heldDuringDrag = false
    #endif
    let timeline: CashTimeline

    private var window: CashTimelineWindow { timeline.window(cycleOffset: cycleOffset) }
    private var selected: CashTimelinePoint? { selectedDay.flatMap { window.point(on: $0) } }
    private var hidden: Bool { store.current.preferences.hideAmounts }

    var body: some View {
        let visible = window
        VStack(alignment: .leading, spacing: 0) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    title
                    Spacer(minLength: 0)
                    range(visible)
                }
                VStack(alignment: .leading, spacing: 4) { title; range(visible) }
            }
            if hidden {
                Text("金额已隐藏").yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary)
                    .frame(maxWidth: .infinity, minHeight: 220, alignment: .leading)
            } else {
                readout(visible).padding(.top, 8)
                plot(visible).padding(.top, 22)
                footer.padding(.top, 10)
            }
        }.padding(.horizontal, YubaiSpace.insetCard).padding(.top, 14).padding(.bottom, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .paperCardSurface(in: RoundedRectangle(cornerRadius: YubaiRadius.card))
            .accessibilityElement(children: .contain).accessibilityIdentifier("cashTimelineCard")
            .onChange(of: timeline.cycles) { _, _ in cycleOffset = 0; selectedDay = nil; holding = false }
            .onChange(of: hidden) { _, _ in selectedDay = nil; holding = false }
            .onDisappear { selectedDay = nil; holding = false }
    }

    private var title: some View {
        Text("现金会怎么走").yubaiFont(YubaiFont.cardTitle).lineLimit(1).fixedSize()
    }
    private func range(_ visible: CashTimelineWindow) -> some View {
        Text(dateRange(visible)).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
            .lineLimit(1).fixedSize().accessibilityIdentifier("cashTimelineRange")
    }
    private func readout(_ visible: CashTimelineWindow) -> some View {
        let value = visible.readout(selectedDay: selectedDay)
        return VStack(alignment: .leading, spacing: 2) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    readoutLabel(value); readoutAmount(value)
                }
                VStack(alignment: .leading, spacing: 4) {
                    readoutLabel(value); readoutAmount(value)
                }
            }.accessibilityElement(children: .combine).accessibilityIdentifier("cashTimelineMinimum")
            if let difference = value?.difference {
                // Wrapping moves complete facts to another row without squeezing.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 0) { comparisonLabel(difference); comparisonAmount(difference) }
                    VStack(alignment: .leading, spacing: 2) { comparisonLabel(difference); comparisonAmount(difference) }
                }.yubaiFont(YubaiFont.caption).accessibilityElement(children: .combine)
                    .accessibilityIdentifier("cashTimelineComparison")
            }
        }.frame(maxWidth: .infinity, alignment: .leading).accessibilityIdentifier("cashTimelineReadout")
    }
    private func comparisonLabel(_ difference: Int64) -> some View {
        Text("比上个月同一天" + (difference >= 0 ? "多 " : "少 "))
            .foregroundStyle(YubaiColor.labelSecondary).lineLimit(1).fixedSize()
    }
    private func comparisonAmount(_ difference: Int64) -> some View {
        Text(Money.text(abs(difference), currency: false))
            .foregroundStyle(difference >= 0 ? YubaiColor.brandInk : YubaiColor.amberInk).lineLimit(1).fixedSize()
    }
    private func readoutLabel(_ value: CashTimelineReadout?) -> some View {
        Text(value?.title ?? "今天").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
            .lineLimit(1).fixedSize()
    }
    private func readoutAmount(_ value: CashTimelineReadout?) -> some View {
        Text(amountText(value?.point.balance ?? 0))
            .yubaiFont(YubaiFont.Style(size: 26, lineHeight: 30, weight: .semibold, family: .num, tracking: -0.5, relativeTo: .title2))
            .foregroundStyle(YubaiColor.label).lineLimit(1).fixedSize()
    }

    private var legends: some View {
        HStack(spacing: 14) {
            legend("这个月", ink: YubaiColor.brand, width: 2.4)
            legend("上个月", ink: YubaiColor.chartRule, width: 1.5)
        }.fixedSize().accessibilityIdentifier("cashTimelineLegend")
    }
    private var footer: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { legends; Spacer(minLength: 0); pageControls }
            VStack(alignment: .leading, spacing: 8) {
                legends
                HStack { Spacer(minLength: 0); pageControls }
            }
        }
    }
    private var pageControls: some View {
        HStack(spacing: 10) {
            if cycleOffset != 0 {
                Button { cycleOffset = 0; selectedDay = nil; holding = false } label: {
                    Text("这个月 ›").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.label)
                        .lineLimit(1).fixedSize().padding(.horizontal, 10).frame(height: 28)
                        .background(YubaiColor.raised, in: Capsule())
                        .contentShape(Rectangle().inset(by: -8))
                }.buttonStyle(PressButtonStyle()).accessibilityIdentifier("cashTimelineToday")
                    .accessibilityLabel("回到这个月").accessibilityHint("显示当前发薪周期")
            }
            let last = min(timeline.cycles.count - 1, max(3, cycleOffset))
            let first = max(0, last - 3)
            HStack(spacing: 4) {
                ForEach(Array((first...last).reversed()), id: \.self) { index in
                    Capsule().fill(index == cycleOffset ? YubaiColor.label : YubaiColor.neutralStrong)
                        .frame(width: index == cycleOffset ? 14 : 6, height: 6)
                }
            }.accessibilityElement(children: .ignore).accessibilityIdentifier("cashTimelinePages")
                .accessibilityLabel("发薪周期").accessibilityValue("第 \(cycleOffset + 1) 页，共 \(timeline.cycles.count) 页")
        }.fixedSize()
    }
    private func legend(_ title: String, ink: Color, width: CGFloat) -> some View {
        HStack(spacing: 5) {
            Line().stroke(ink, lineWidth: width).frame(width: 14, height: 2).accessibilityHidden(true)
            Text(title).yubaiFont(YubaiFont.meta).lineLimit(1).fixedSize()
        }.foregroundStyle(YubaiColor.labelSecondary).fixedSize()
    }

    private func plot(_ visible: CashTimelineWindow) -> some View {
        let rows = CashTimelineAnnotationLayout.place(annotationCandidates(visible, width: plotWidth), width: Double(plotWidth))
        let rowCount = max(2, (rows.map(\.row).max() ?? 0) + 1)
        let annotationHeight = CGFloat(rowCount) * annotationRowHeight(visible, width: plotWidth) + 4
        let summary = selected.flatMap { CashTimelinePresentation.eventSummary($0.events) }
        let capsuleHeight = summary.map { factHeight($0, width: max(1, plotWidth - 20)) + 14 } ?? 0
        let bandHeight = max(annotationHeight, capsuleHeight)
        return ZStack(alignment: .bottomLeading) {
            chart(visible, bandHeight: bandHeight).padding(.top, bandHeight)
            if visible.showsFloor, let floor = visible.floor {
                Color.clear.frame(width: 1, height: 1).allowsHitTesting(false)
                    .accessibilityElement().accessibilityLabel("始终留着 " + Money.text(floor, currency: false))
                    .accessibilityIdentifier("cashTimelineFloor")
            }
        }.frame(height: max(textSize.isAccessibilitySize ? 270 : 168, bandHeight + 120))
            .accessibilityElement(children: .contain)
    }
    private func chart(_ visible: CashTimelineWindow, bandHeight: CGFloat) -> some View {
        let scale = CashTimelineScale(window: visible)
        let endpoint = visible.endpointPresentation
        let segments = visible.forecastSegments
        return Chart {
            if visible.showsFloor, let floor = visible.floor {
                RuleMark(y: .value("始终留着", money(floor)))
                    .foregroundStyle(YubaiColor.amberDot).lineStyle(StrokeStyle(lineWidth: 1, dash: [1.5, 2.5]))
            }
            ForEach(visible.previous) { point in
                LineMark(x: .value("日期", point.date), y: .value("余额", money(point.balance)), series: .value("段", "上周期"))
                    .foregroundStyle(YubaiColor.chartRule)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, lineJoin: .round)).interpolationMethod(.linear)
            }
            ForEach(visible.history) { point in
                LineMark(x: .value("日期", point.date), y: .value("余额", money(point.balance)), series: .value("段", "本周期"))
                    .foregroundStyle(YubaiColor.brand).lineStyle(StrokeStyle(lineWidth: 2.4, lineJoin: .round)).interpolationMethod(.linear)
            }
            ForEach(segments) { segment in
                ForEach(Array(segment.points.enumerated()), id: \.offset) { _, point in
                    LineMark(x: .value("日期", point.date), y: .value("余额", point.balance / 100), series: .value("段", "预测\(segment.id)"))
                        .foregroundStyle(segment.belowFloor ? YubaiColor.amberDot : YubaiColor.brand)
                        .lineStyle(StrokeStyle(lineWidth: 2.4, dash: [4, 4])).interpolationMethod(.linear)
                }
            }
            if visible.isDefault, let today = visible.history.last {
                PointMark(x: .value("今天", today.date), y: .value("余额", money(today.balance)))
                    .symbol { Circle().fill(YubaiColor.brand).frame(width: 8, height: 8)
                        .overlay { Circle().stroke(YubaiColor.paperSheet, lineWidth: 2) } }
                if let endpoint {
                    PointMark(x: .value("周期终点", endpoint.date), y: .value("余额", money(endpoint.balance)))
                        .symbol { Circle().fill(YubaiColor.paperSheet).frame(width: 8, height: 8)
                            .overlay { Circle().stroke(endpoint.belowFloor ? YubaiColor.amberDot : YubaiColor.brandInk, lineWidth: 2) } }
                }
            }
            if let selected {
                RuleMark(x: .value("选中日期", selected.date)).foregroundStyle(YubaiColor.label).lineStyle(StrokeStyle(lineWidth: 1))
                if let prior = visible.previousPoint(on: selected.date) {
                    PointMark(x: .value("选中日期", selected.date), y: .value("上周期余额", money(prior.balance)))
                        .symbol { Circle().fill(YubaiColor.chartRule).frame(width: 5, height: 5) }
                }
                PointMark(x: .value("选中日期", selected.date), y: .value("余额", money(selected.balance)))
                    .symbol { Circle().fill(YubaiColor.label).frame(width: 5, height: 5).padding(2)
                        .background(YubaiColor.paperSheet, in: Circle()) }
            }
        }.chartLegend(.hidden)
            .chartXScale(domain: visible.start...visible.end, range: .plotDimension(padding: 4))
            .chartYScale(domain: scale.domain)
            .chartYAxis {
                AxisMarks(position: .trailing, values: scale.ticks) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6)).foregroundStyle(YubaiColor.separator)
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            Text(CashTimelineScale.label(number)).yubaiFont(YubaiFont.chartLabel).foregroundStyle(YubaiColor.labelSecondary)
                                .lineLimit(1).fixedSize()
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: axisDates(visible)) { value in
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(date == timeline.today ? "今天" : shortDate(date)).yubaiFont(YubaiFont.chartLabel).foregroundStyle(YubaiColor.labelSecondary)
                                .lineLimit(1).fixedSize()
                        }
                    }
                }
            }.chartOverlay { proxy in
                GeometryReader { geometry in
                    if let plot = proxy.plotFrame {
                        let frame = geometry[plot]
                        annotations(visible, proxy: proxy, frame: frame, bandHeight: bandHeight)
                            .allowsHitTesting(false).accessibilityHidden(true)
                        if let endpoint, visible.isDefault, let y = proxy.position(forY: money(endpoint.balance)) {
                            let label = endpoint.label(hasPayday: timeline.hasPayday)
                            factLabel(label, width: frame.width).font(.system(size: annotationSize, weight: .medium))
                                .foregroundStyle(endpoint.belowFloor ? YubaiColor.amberInk : YubaiColor.brandInk)
                                .frame(width: frame.width, alignment: .trailing)
                                .position(x: frame.midX, y: frame.minY + y - factHeight(label, width: frame.width) / 2 - 8)
                                .allowsHitTesting(false).accessibilityHidden(true)
                        }
                        if visible.showsFloor, let floor = visible.floor, let y = proxy.position(forY: money(floor)) {
                            let label = "始终留着 " + Money.text(floor, currency: false)
                            factLabel(label, width: frame.width).font(.system(size: annotationSize))
                                .foregroundStyle(YubaiColor.amberInk)
                                .frame(width: frame.width, alignment: .leading)
                                .position(x: frame.midX, y: min(frame.maxY - 6, frame.minY + y + 10))
                                .allowsHitTesting(false).accessibilityHidden(true)
                        }
                        touchSurface(proxy, frame: frame)
                            .onAppear { plotWidth = max(1, frame.width) }
                            .onChange(of: frame.width) { _, width in plotWidth = max(1, width) }
                    }
                }
            }
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
            .accessibilityAction(named: "上个周期") { switchCycle(100, velocity: 0, width: 100) }
            .accessibilityAction(named: "下个周期") { switchCycle(-100, velocity: 0, width: 100) }
            .accessibilityAction(named: "结束查看") { selectedDay = nil }
            #if os(iOS)
            .sensoryFeedback(.selection, trigger: selectionTrigger)
            #endif
    }

    private func textWidth(_ text: String) -> CGFloat {
        #if os(iOS)
        return (text as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: annotationSize)]).width
        #else
        return (text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: annotationSize)]).width
        #endif
    }
    private var factLineHeight: CGFloat {
        #if os(iOS)
        return UIFont.systemFont(ofSize: annotationSize).lineHeight
        #else
        let font = NSFont.systemFont(ofSize: annotationSize)
        return font.ascender - font.descender + font.leading
        #endif
    }
    private func factLines(_ text: String, width: CGFloat) -> [String] {
        var result: [String] = [], line = ""
        for character in text {
            let next = line + String(character)
            if !line.isEmpty && textWidth(next) > max(annotationSize * 2, width) {
                result.append(line); line = String(character)
            } else { line = next }
        }
        if !line.isEmpty { result.append(line) }
        return result
    }
    private func factHeight(_ text: String, width: CGFloat) -> CGFloat {
        CGFloat(factLines(text, width: width).count) * (factLineHeight + 2) - 2
    }
    private func factWidth(_ text: String, width: CGFloat) -> CGFloat {
        factLines(text, width: width).map { textWidth($0) }.max() ?? 0
    }
    private func factLabel(_ text: String, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(factLines(text, width: width).enumerated()), id: \.offset) { _, line in
                Text(line).lineLimit(1).fixedSize()
            }
        }.fixedSize()
    }
    private func annotationRowHeight(_ visible: CashTimelineWindow, width: CGFloat) -> CGFloat {
        max(factLineHeight, visible.topAnnotations.map { factHeight(annotationText($0), width: width) }.max() ?? 0) + 4
    }
    private func annotationCandidates(_ visible: CashTimelineWindow, width: CGFloat) -> [CashTimelineAnnotationLayout.Candidate] {
        let duration = max(1, visible.end.timeIntervalSince(visible.start))
        return visible.topAnnotations.map { event in
            let x = 4 + CGFloat(event.date.timeIntervalSince(visible.start) / duration) * max(0, width - 8)
            return .init(id: event.id, x: Double(x), width: Double(factWidth(annotationText(event), width: width)))
        }
    }
    private func annotations(_ visible: CashTimelineWindow, proxy: ChartProxy, frame: CGRect, bandHeight: CGFloat) -> some View {
        let candidates = visible.topAnnotations.compactMap { event -> CashTimelineAnnotationLayout.Candidate? in
            guard let x = proxy.position(forX: event.date) else { return nil }
            return .init(id: event.id, x: Double(x), width: Double(factWidth(annotationText(event), width: frame.width)))
        }
        let placements = CashTimelineAnnotationLayout.place(candidates, width: Double(frame.width))
        let rowHeight = annotationRowHeight(visible, width: frame.width)
        return ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                for event in visible.topAnnotations {
                    guard let point = visible.point(on: event.date), let x = proxy.position(forX: event.date),
                          let y = proxy.position(forY: money(point.balance)),
                          let placement = placements.first(where: { $0.id == event.id }) else { continue }
                    let dot = CGPoint(x: frame.minX + x, y: frame.minY + y)
                    if selected == nil {
                        let labelY = frame.minY - bandHeight + CGFloat(placement.row) * rowHeight + factHeight(annotationText(event), width: frame.width) + 2
                        var leader = Path()
                        leader.move(to: CGPoint(x: frame.minX + CGFloat(placement.centerX), y: labelY))
                        leader.addLine(to: CGPoint(x: dot.x, y: dot.y - 5))
                        context.stroke(leader, with: .color(YubaiColor.chartRule), style: StrokeStyle(lineWidth: 1, dash: [1.5, 2.5]))
                    }
                    context.fill(Path(ellipseIn: CGRect(x: dot.x - 3, y: dot.y - 3, width: 6, height: 6)),
                                 with: .color(event.amount >= 0 ? YubaiColor.brandInk : YubaiColor.labelMuted))
                }
            }
            if selected == nil {
                ForEach(visible.topAnnotations) { event in
                    if let placement = placements.first(where: { $0.id == event.id }) {
                        factLabel(annotationText(event), width: frame.width).font(.system(size: annotationSize))
                            .foregroundStyle(event.amount >= 0 ? YubaiColor.brandInk : YubaiColor.labelMuted)
                            .position(x: frame.minX + CGFloat(placement.centerX),
                                      y: frame.minY - bandHeight + CGFloat(placement.row) * rowHeight + factHeight(annotationText(event), width: frame.width) / 2)
                    }
                }
            } else if let selected, let summary = CashTimelinePresentation.eventSummary(selected.events),
                      let x = proxy.position(forX: selected.date) {
                let capsuleWidth = factWidth(summary, width: max(1, frame.width - 20)) + 20
                factLabel(summary, width: max(1, frame.width - 20)).font(.system(size: annotationSize)).foregroundStyle(YubaiColor.paperSheet)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(YubaiColor.label, in: Capsule())
                    .position(x: frame.minX + min(frame.width - capsuleWidth / 2, max(capsuleWidth / 2, x)),
                              y: frame.minY - bandHeight / 2)
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
            .simultaneousGesture(DragGesture(minimumDistance: 10).onChanged { _ in
                if holding { heldDuringDrag = true }
            }.onEnded { value in
                defer { heldDuringDrag = false }
                guard !heldDuringDrag else { return }
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
        guard let value = visible.readout(selectedDay: selectedDay) else { return dateRange(visible) }
        var facts = [dateRange(visible), value.title + "，余额 " + Money.text(value.point.balance)]
        if let difference = value.difference {
            facts.append("比上个月同一天" + (difference >= 0 ? "多 " : "少 ") + Money.text(abs(difference)))
        }
        if let selected, let event = CashTimelinePresentation.eventSummary(selected.events) { facts.append(event) }
        if visible.isDefault, let endpoint = visible.endpointPresentation {
            facts.append(endpoint.label(hasPayday: timeline.hasPayday))
            if visible.showsFloor, let floor = visible.floor { facts.append("始终留着 " + Money.text(floor)) }
            if endpoint.belowFloor { facts.append("低于始终留着") }
        }
        return facts.joined(separator: "，")
    }
    private func annotationText(_ event: CashTimelineEvent) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "zh_CN"); formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0; formatter.maximumFractionDigits = 0
        let amount = formatter.string(from: NSDecimalNumber(decimal: Decimal(abs(event.amount)) / 100)) ?? "0"
        return (event.isSalary ? "工资" : event.title) + " " + (event.amount >= 0 ? "+" : "−") + amount
    }
    private func amountText(_ cents: Int64) -> String { CashTimelinePresentation.amount(cents) }
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
