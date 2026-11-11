import SwiftUI
import YubaiCore

/// 节奏图：实线是实际花的，虚线是匀着花。贴着就不说话；花快了或超了变琥珀；隐藏金额时只留形状。
struct PaceChart: View {
    @Environment(\.dynamicTypeSize) private var textSize
    let pace: CyclePace
    var hide = false

    private let plotHeight: CGFloat = 104
    private var amber: Bool { pace.isFast || pace.overBy > 0 }
    private var lineInk: Color { amber ? YubaiColor.amberDot : YubaiColor.brand }
    private var daysTotal: CGFloat { CGFloat(max(1, pace.daysTotal)) }
    private var todayIndex: CGFloat { CGFloat(max(0, pace.points.count - 1)) }
    private var todayFraction: CGFloat { min(1, todayIndex / daysTotal) }
    private var ceiling: Double {
        Double(max(1, pace.budget, pace.points.map(\.spent).max() ?? 0))
    }
    private var label: String {
        hide ? "金额已隐藏" : "到今天花了 " + amount2(pace.spent, hide: false) + "，匀着花是 " + amount2(pace.evenToDate, hide: false)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: YubaiSpace.space4) {
            plot.frame(height: plotHeight)
            axis.frame(height: 18)
            if pace.points.count > 1 { legend.padding(.top, YubaiSpace.space4) }
        }.accessibilityElement(children: .ignore).accessibilityLabel(label).accessibilityIdentifier("paceChart")
    }

    private func point(_ index: CGFloat, _ value: Int64, in size: CGSize) -> CGPoint {
        let floor = size.height - 2, top: CGFloat = 9.5
        let x = size.width * index / daysTotal
        let y = floor - (floor - top) * CGFloat(Double(max(0, value)) / ceiling)
        return CGPoint(x: x, y: y)
    }

    private var plot: some View {
        Canvas { context, size in
            let floor = size.height - 2
            var base = Path(); base.move(to: CGPoint(x: 0, y: floor)); base.addLine(to: CGPoint(x: size.width, y: floor))
            context.stroke(base, with: .color(YubaiColor.separator), lineWidth: 1)

            var guide = Path()
            guide.move(to: CGPoint(x: 0, y: floor)); guide.addLine(to: point(daysTotal, pace.budget, in: size))
            context.stroke(guide, with: .color(YubaiColor.labelSecondary),
                           style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [3, 5]))

            let spots = pace.points.enumerated().map { point(CGFloat($0.offset), $0.element.spent, in: size) }
            guard let first = spots.first, let last = spots.last else { return }
            var area = Path(); area.move(to: CGPoint(x: first.x, y: floor))
            for spot in spots { area.addLine(to: spot) }
            area.addLine(to: CGPoint(x: last.x, y: floor)); area.closeSubpath()
            context.fill(area, with: .color(lineInk.opacity(0.13)))

            var line = Path(); line.move(to: first)
            for spot in spots.dropFirst() { line.addLine(to: spot) }
            context.stroke(line, with: .color(lineInk), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

            let ring = CGRect(x: last.x - 8, y: last.y - 8, width: 16, height: 16)
            context.fill(Path(ellipseIn: ring), with: .color(YubaiColor.canvas))
            let dot = CGRect(x: last.x - 5, y: last.y - 5, width: 10, height: 10)
            context.fill(Path(ellipseIn: dot), with: .color(lineInk))
        }.accessibilityHidden(true)
    }

    private var axis: some View {
        GeometryReader { proxy in
            let todayX = min(max(proxy.size.width * todayFraction, 18), proxy.size.width - 18)
            ZStack(alignment: .topLeading) {
                if todayFraction > 0.12 {
                    Text(NowFormat.monthDay(pace.start)).fixedSize().frame(maxWidth: .infinity, alignment: .leading)
                }
                Text("今天").fontWeight(.semibold).foregroundStyle(YubaiColor.label).fixedSize().position(x: todayX, y: 8)
                if todayFraction < 0.9 {
                    Text(NowFormat.monthDay(pace.end)).fixedSize().frame(maxWidth: .infinity, alignment: .trailing)
                }
            }.yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary)
        }
    }

    private var legend: some View {
        let layout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: YubaiSpace.space4)) : AnyLayout(HStackLayout(spacing: YubaiSpace.gapSection))
        return layout {
            legendItem(title: "花了", amount: pace.spent, ink: lineInk, dashed: false)
            legendItem(title: "匀着花", amount: pace.evenToDate, ink: YubaiColor.labelSecondary, dashed: true)
        }
    }

    private func legendItem(title: String, amount: Int64, ink: Color, dashed: Bool) -> some View {
        HStack(spacing: YubaiSpace.space8) {
            Path { path in path.move(to: CGPoint(x: 0, y: 1.5)); path.addLine(to: CGPoint(x: 16, y: 1.5)) }
                .stroke(ink, style: StrokeStyle(lineWidth: dashed ? 2 : 3, lineCap: .round, dash: dashed ? [4, 3] : []))
                .frame(width: 16, height: 3).accessibilityHidden(true)
            Text(title)
            Text(amount2(amount, hide: hide)).yubaiFont(YubaiFont.amountCaption, weight: dashed ? .medium : .semibold)
        }.yubaiFont(YubaiFont.caption).foregroundStyle(dashed ? YubaiColor.labelSecondary : YubaiColor.label)
    }
}
