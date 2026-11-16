import SwiftUI

/// Reflow the same children using intrinsic widths. A live text-size change
/// never selects a second copy of a control or replaces its native editor.
struct AdaptiveStackLayout: Layout {
    var stacked = false
    var equalWidth = false
    var spreads = false
    var baseline = false
    var horizontalSpacing: CGFloat = YubaiSpace.space8
    var verticalSpacing: CGFloat = YubaiSpace.space4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrangement(width: proposal.width, subviews: subviews).size
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangement(width: bounds.width, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            let frame = result.frames[index]
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), anchor: .topLeading,
                          proposal: ProposedViewSize(frame.size))
        }
    }
    private func arrangement(width proposed: CGFloat?, subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        guard !subviews.isEmpty else { return (.zero, []) }
        let ideals = subviews.map { $0.sizeThatFits(.unspecified) }
        let gaps = horizontalSpacing * CGFloat(subviews.count - 1)
        let natural = equalWidth ? (ideals.map(\.width).max() ?? 0) * CGFloat(subviews.count) + gaps
            : ideals.reduce(gaps) { $0 + $1.width }
        let width = max(0, proposed.flatMap { $0.isFinite ? $0 : nil } ?? (stacked ? ideals.map(\.width).max() ?? 0 : natural))
        if stacked || natural > width + 0.5 {
            var y: CGFloat = 0
            let frames = subviews.map { subview -> CGRect in
                let size = subview.sizeThatFits(ProposedViewSize(width: width, height: nil))
                defer { y += size.height + verticalSpacing }
                return CGRect(x: YubaiSpace.none, y: y, width: width, height: size.height)
            }
            return (CGSize(width: width, height: max(0, y - verticalSpacing)), frames)
        }
        let slot = max(0, (width - gaps) / CGFloat(subviews.count))
        let sizes = subviews.indices.map { index in
            subviews[index].sizeThatFits(ProposedViewSize(width: equalWidth ? slot : ideals[index].width, height: nil))
        }
        let baselines = subviews.indices.map { index in
            subviews[index].dimensions(in: ProposedViewSize(sizes[index]))[.firstTextBaseline]
        }
        let firstBaseline = baselines.max() ?? 0
        let height = subviews.indices.map { index in
            sizes[index].height + (baseline ? firstBaseline - baselines[index] : 0)
        }.max() ?? 0
        var x: CGFloat = 0
        let frames = subviews.indices.map { index -> CGRect in
            let size = sizes[index]
            let childWidth = equalWidth ? slot : size.width
            let childX = spreads && subviews.count > 1 && index == subviews.count - 1 ? width - childWidth : x
            defer { x += childWidth + horizontalSpacing }
            return CGRect(x: childX, y: baseline ? firstBaseline - baselines[index] : (height - size.height) / 2,
                          width: childWidth, height: size.height)
        }
        return (CGSize(width: width, height: height), frames)
    }
}

/// The three header children keep their identity when the title moves above
/// the actions. All decisions are local measurement, with no state feedback.
struct SheetHeaderLayout: Layout {
    var stacked: Bool
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrangement(width: proposal.width, subviews: subviews).size
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangement(width: bounds.width, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            let frame = result.frames[index]
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), anchor: .topLeading,
                          proposal: ProposedViewSize(frame.size))
        }
    }
    private func arrangement(width proposed: CGFloat?, subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        guard subviews.count == 3 else { return (.zero, []) }
        let ideal = subviews.map { $0.sizeThatFits(.unspecified) }
        let side = YubaiSize.sheetHeaderActionWidth
        let width = max(0, proposed.flatMap { $0.isFinite ? $0 : nil } ?? side * 2 + ideal[1].width)
        if !stacked, ideal[0].width <= side, ideal[2].width <= side, ideal[1].width <= width - side * 2 {
            let height = ideal.map(\.height).max() ?? 0
            return (CGSize(width: width, height: height), [
                CGRect(x: YubaiSpace.none, y: (height - ideal[0].height) / 2, width: ideal[0].width, height: ideal[0].height),
                CGRect(x: side, y: (height - ideal[1].height) / 2, width: width - side * 2, height: ideal[1].height),
                CGRect(x: width - ideal[2].width, y: (height - ideal[2].height) / 2, width: ideal[2].width, height: ideal[2].height)
            ])
        }
        let title = subviews[1].sizeThatFits(ProposedViewSize(width: width, height: nil))
        let y = title.height + YubaiSpace.space4
        if ideal[0].width + ideal[2].width + YubaiSpace.space8 <= width {
            let actionsHeight = max(ideal[0].height, ideal[2].height)
            return (CGSize(width: width, height: y + actionsHeight), [
                CGRect(x: YubaiSpace.none, y: y + (actionsHeight - ideal[0].height) / 2, width: ideal[0].width, height: ideal[0].height),
                CGRect(x: YubaiSpace.none, y: YubaiSpace.none, width: width, height: title.height),
                CGRect(x: width - ideal[2].width, y: y + (actionsHeight - ideal[2].height) / 2, width: ideal[2].width, height: ideal[2].height)
            ])
        }
        let cancel = subviews[0].sizeThatFits(ProposedViewSize(width: width, height: nil))
        let action = subviews[2].sizeThatFits(ProposedViewSize(width: width, height: nil))
        return (CGSize(width: width, height: y + cancel.height + YubaiSpace.space8 + action.height), [
            CGRect(x: (width - cancel.width) / 2, y: y, width: cancel.width, height: cancel.height),
            CGRect(x: YubaiSpace.none, y: YubaiSpace.none, width: width, height: title.height),
            CGRect(x: (width - action.width) / 2, y: y + cancel.height + YubaiSpace.space8, width: action.width, height: action.height)
        ])
    }
}

struct SavedPillLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrangement(width: proposal.width, subviews: subviews).size
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangement(width: bounds.width, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            let frame = result.frames[index]
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), anchor: .topLeading,
                          proposal: ProposedViewSize(frame.size))
        }
    }
    private func arrangement(width proposed: CGFloat?, subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        guard subviews.count == 3 else { return (.zero, []) }
        let ideal = subviews.map { $0.sizeThatFits(.unspecified) }
        let gap = YubaiSpace.space6
        let natural = ideal.reduce(gap * 2) { $0 + $1.width }
        let width = min(proposed ?? natural, natural)
        if natural <= width + 0.5 {
            let height = ideal.map(\.height).max() ?? 0
            var x: CGFloat = 0
            let frames = ideal.map { size -> CGRect in
                defer { x += size.width + gap }
                return CGRect(x: x, y: (height - size.height) / 2, width: size.width, height: size.height)
            }
            return (CGSize(width: natural, height: height), frames)
        }
        let title = subviews[0].sizeThatFits(ProposedViewSize(width: max(0, width - ideal[2].width - gap), height: nil))
        let amount = subviews[1].sizeThatFits(ProposedViewSize(width: width, height: nil))
        let headerHeight = max(title.height, ideal[2].height)
        return (CGSize(width: width, height: headerHeight + YubaiSpace.space4 + amount.height), [
            CGRect(x: YubaiSpace.none, y: (headerHeight - title.height) / 2, width: title.width, height: title.height),
            CGRect(x: YubaiSpace.none, y: headerHeight + YubaiSpace.space4, width: width, height: amount.height),
            CGRect(x: width - ideal[2].width, y: (headerHeight - ideal[2].height) / 2, width: ideal[2].width, height: ideal[2].height)
        ])
    }
}
