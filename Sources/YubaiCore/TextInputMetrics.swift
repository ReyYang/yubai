import Foundation

/// Native text measurement is independent of the live editor's scroll/layout
/// state. Round the result once and ignore subpixel measurement noise.
public enum TextInputMetrics {
    public static func height(textHeight: CGFloat, lineHeight: CGFloat, verticalInset: CGFloat,
                              minimum: CGFloat, maximumLines: Int) -> CGFloat {
        let lines = max(1, maximumLines)
        let text = min(max(lineHeight, textHeight), lineHeight * CGFloat(lines))
        return max(minimum, ceil(text + verticalInset * 2))
    }

    public static func changed(from previous: CGFloat, to next: CGFloat) -> Bool {
        next.isFinite && next > 0 && abs(next - previous) > 0.5
    }
}
