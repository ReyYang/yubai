import Foundation

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
