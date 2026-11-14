import Foundation

/// Decisions depend on observed motion, never on the number of drags. The
/// caller owns the absolute deadline and obtains one coherent tree per sample.
struct UIRevealProgress {
    struct Sample {
        let target: CGRect?
        let viewport: CGRect
        var landmarks: [String: CGFloat] = [:]
    }
    enum Step: Equatable {
        case reached, stalled
        case drag(up: Bool, distance: CGFloat)
    }
    private var previous: Sample?
    private var movingUp = true

    mutating func next(_ sample: Sample) -> Step {
        defer { previous = sample }
        guard sample.viewport.height > 60 else { return .stalled }
        if let frame = sample.target, !frame.isEmpty, sample.viewport.insetBy(dx: -0.5, dy: -0.5).contains(frame) { return .reached }
        if let previous {
            if let before = previous.target, let after = sample.target {
                if distance(after, to: sample.viewport) >= distance(before, to: previous.viewport) - 0.5 { return .stalled }
            } else {
                // Crossing actions can disappear from AX for a sample. Other
                // content in that same scroll view must still move toward it.
                let motion = previous.landmarks.compactMap { key, y -> CGFloat? in
                    sample.landmarks[key].map { ($0 - y) * (movingUp ? -1 : 1) }
                }
                guard motion.contains(where: { $0 > 0.5 }) else { return .stalled }
            }
        }
        let maximum = sample.viewport.height * 0.5
        if let frame = sample.target, !frame.isEmpty {
            guard frame.height <= sample.viewport.height + 0.5 else { return .stalled }
            movingUp = frame.minY >= sample.viewport.minY
            let overflow = movingUp ? frame.maxY - sample.viewport.maxY : sample.viewport.minY - frame.minY
            return .drag(up: movingUp, distance: min(maximum, max(24, overflow + 8)))
        }
        return .drag(up: movingUp, distance: maximum)
    }

    private func distance(_ frame: CGRect, to viewport: CGRect) -> CGFloat {
        max(0, viewport.minY - frame.minY, frame.maxY - viewport.maxY)
    }
}
