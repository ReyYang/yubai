import Foundation

/// Month-day choices use the entire page-inset width. Keep their column count
/// while shrinking both gaps before spending any of the measured hit target.
public struct MonthDayGridMetrics: Equatable, Sendable {
    public let columns: Int
    public let spacing: CGFloat

    public init(availableWidth: CGFloat, minimumTarget: CGFloat, accessibility: Bool) {
        columns = accessibility ? 4 : 7
        let roomPerGap = (availableWidth - CGFloat(columns) * minimumTarget) / CGFloat(columns - 1)
        spacing = min(8, max(2, roomPerGap))
    }
}
