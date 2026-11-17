import Foundation

/// Capture the settled row in screen space before sending a touch. Coordinates
/// bound to a Button/NavigationLink can activate that AX control instead of
/// exercising the native cell's swipe actions (run 13, ledger and memory).
enum UIRowSwipe {
    static func plan(row: CGRect, viewport: CGRect, excluding occlusions: [CGRect] = []) -> UIRevealPan.Gesture? {
        guard !row.isNull, !row.isInfinite, row.width >= 80, row.height > 0,
              !viewport.isNull, !viewport.isInfinite,
              [row.minX, row.minY, row.width, row.height, viewport.minX, viewport.minY, viewport.width, viewport.height].allSatisfy({ $0.isFinite }),
              viewport.contains(row) else { return nil }
        // Less than half the row width: reveal actions without committing a
        // full-swipe delete. The whole horizontal path must stay unobstructed.
        let start = CGPoint(x: row.minX + row.width * 0.85, y: row.midY)
        let end = CGPoint(x: row.minX + row.width * 0.4, y: row.midY)
        let path = CGRect(x: end.x, y: start.y - 1, width: start.x - end.x, height: 2)
        guard !occlusions.contains(where: { $0.intersects(path) }) else { return nil }
        return UIRevealPan.Gesture(start: start, end: end)
    }
}

/// Plan inside both the AX-visible viewport and a natively hit-tested lane of
/// the owning UIScrollView. Subtracting chrome alone cannot prove pan ownership:
/// the center of a large card can belong to its own gesture recognizers.
enum UIRevealPan {
    struct Gesture: Equatable {
        let start: CGPoint
        let end: CGPoint
    }
    static func plan(_ step: UIRevealProgress.Step, viewport: CGRect, nativeOrigins: [CGPoint]?, excluding occlusions: [CGRect] = []) -> Gesture? {
        guard viewport.width > 24, viewport.height > 24 else { return nil }
        let inner = viewport.insetBy(dx: 12, dy: 12)
        let vertical: Bool, forward: Bool, distance: CGFloat
        switch step {
        case let .drag(up, amount): vertical = true; forward = up; distance = amount
        case let .dragHorizontally(left, amount): vertical = false; forward = left; distance = amount
        case .reached, .stalled: return nil
        }
        guard distance.isFinite, distance > 0 else { return nil }
        let preferred = CGPoint(x: vertical ? viewport.midX : viewport.minX + viewport.width * (forward ? 0.78 : 0.22),
                                y: vertical ? viewport.minY + viewport.height * (forward ? 0.78 : 0.22) : viewport.midY)
        let candidates = nativeOrigins ?? [preferred]
        // Native order favors the List gutter over a card. Select the nearest
        // usable ordinate, keeping that order for points at the same height.
        let ranked = candidates.enumerated().filter { _, point in
            point.x.isFinite && point.y.isFinite && inner.contains(point) && !occlusions.contains { $0.contains(point) }
        }.sorted { a, b in
            let first = abs(vertical ? a.element.y - preferred.y : a.element.x - preferred.x)
            let second = abs(vertical ? b.element.y - preferred.y : b.element.x - preferred.x)
            return first != second ? first < second : a.offset < b.offset
        }
        for (_, start) in ranked {
            let sign: CGFloat = forward ? -1 : 1
            var end = vertical
                ? CGPoint(x: start.x, y: min(inner.maxY, max(inner.minY, start.y + sign * distance)))
                : CGPoint(x: min(inner.maxX, max(inner.minX, start.x + sign * distance)), y: start.y)
            // Target clearance can require a whole row above a toast, but a
            // pan can travel in the List gutter BESIDE it. Keep the actual
            // chrome rectangles for gestures; stop before any crossed surface.
            for cut in occlusions where !cut.isEmpty && !cut.isNull {
                if vertical && start.x >= cut.minX && start.x <= cut.maxX {
                    if forward && start.y >= cut.maxY { end.y = max(end.y, cut.maxY + 12) }
                    if !forward && start.y <= cut.minY { end.y = min(end.y, cut.minY - 12) }
                } else if !vertical && start.y >= cut.minY && start.y <= cut.maxY {
                    if forward && start.x >= cut.maxX { end.x = max(end.x, cut.maxX + 12) }
                    if !forward && start.x <= cut.minX { end.x = min(end.x, cut.minX - 12) }
                }
            }
            // An obstacle immediately beside the start must never reverse the
            // intended gesture, even if the absolute distance is large enough.
            let advance = (vertical ? start.y - end.y : start.x - end.x) * (forward ? 1 : -1)
            if advance >= 24 {
                return Gesture(start: start, end: end)
            }
        }
        return nil
    }
}

/// Decisions depend on observed motion, never on the number of drags. The
/// caller owns the absolute deadline and obtains one coherent tree per sample.
struct UIRevealProgress {
    struct Sample {
        let target: CGRect?
        let viewport: CGRect
        var landmarks: [String: CGFloat] = [:]
        var scrollOffset: CGFloat? = nil
    }
    enum Step: Equatable {
        case reached, stalled
        case drag(up: Bool, distance: CGFloat)
        case dragHorizontally(left: Bool, distance: CGFloat)
    }
    private var previous: Sample?
    private var movingUp = true

    mutating func next(_ sample: Sample) -> Step {
        defer { previous = sample }
        if let frame = sample.target, !frame.isEmpty, sample.viewport.insetBy(dx: -0.5, dy: -0.5).contains(frame) { return .reached }
        guard !sample.viewport.isEmpty else { return .stalled }
        if let previous {
            // Font/layout settling can move the target away even as a long
            // page actually scrolls toward it. Native offset is independent
            // of that reflow and also survives virtualized landmark turnover.
            let advanced = previous.scrollOffset.flatMap { before in
                sample.scrollOffset.map { ($0 - before) * (movingUp ? 1 : -1) > 0.5 }
            } ?? false
            if let before = previous.target, let after = sample.target {
                if !advanced && distance(after, to: sample.viewport) >= distance(before, to: previous.viewport) - 0.5 { return .stalled }
            } else {
                // A virtualized row may be absent from an AX sample. Other
                // content in that same scroll view must still move toward it.
                let motion = previous.landmarks.compactMap { key, y -> CGFloat? in
                    sample.landmarks[key].map { ($0 - y) * (movingUp ? -1 : 1) }
                }
                guard advanced || motion.contains(where: { $0 > 0.5 }) else { return .stalled }
            }
        }
        if let frame = sample.target, !frame.isEmpty {
            guard frame.height <= sample.viewport.height + 0.5, frame.width <= sample.viewport.width + 0.5 else { return .stalled }
            if frame.minX < sample.viewport.minX - 0.5 || frame.maxX > sample.viewport.maxX + 0.5 {
                guard sample.viewport.width > 60 else { return .stalled }
                let left = frame.minX >= sample.viewport.minX
                let overflow = left ? frame.maxX - sample.viewport.maxX : sample.viewport.minX - frame.minX
                return .dragHorizontally(left: left, distance: min(sample.viewport.width * 0.5, max(24, overflow + 8)))
            }
            guard sample.viewport.height > 60 else { return .stalled }
            movingUp = frame.minY >= sample.viewport.minY
            let overflow = movingUp ? frame.maxY - sample.viewport.maxY : sample.viewport.minY - frame.minY
            return .drag(up: movingUp, distance: min(sample.viewport.height * 0.5, max(24, overflow + 8)))
        }
        guard sample.viewport.height > 60 else { return .stalled }
        return .drag(up: movingUp, distance: sample.viewport.height * 0.5)
    }

    private func distance(_ frame: CGRect, to viewport: CGRect) -> CGFloat {
        max(0, viewport.minY - frame.minY, frame.maxY - viewport.maxY, viewport.minX - frame.minX, frame.maxX - viewport.maxX)
    }
}
