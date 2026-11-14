import XCTest
@testable import YubaiCore

final class TextInputMetricsTests: XCTestCase {
    func testEmptyEditorHasOneLineAndTheFullHitTarget() {
        XCTAssertEqual(TextInputMetrics.height(textHeight: 0, lineHeight: 19.3, verticalInset: 0, minimum: 44, maximumLines: 6), 44)
    }
    func testWrappingGrowsUntilTheLineLimitWithoutDependingOnScrollState() {
        XCTAssertEqual(TextInputMetrics.height(textHeight: 95.5, lineHeight: 20, verticalInset: 12, minimum: 44, maximumLines: 5), 120)
        XCTAssertEqual(TextInputMetrics.height(textHeight: 300, lineHeight: 20, verticalInset: 12, minimum: 44, maximumLines: 5), 124)
    }
    func testRepeatedMeasurementsAndSubpixelNoiseDoNotInvalidateLayout() {
        for next in [44.0, 44.001, 44.49, 44.5] {
            XCTAssertFalse(TextInputMetrics.changed(from: 44, to: next))
        }
        XCTAssertTrue(TextInputMetrics.changed(from: 44, to: 45))
        XCTAssertTrue(TextInputMetrics.changed(from: 124, to: 44))
        XCTAssertFalse(TextInputMetrics.changed(from: 44, to: .nan))
        XCTAssertFalse(TextInputMetrics.changed(from: 44, to: .infinity))
        XCTAssertFalse(TextInputMetrics.changed(from: 44, to: 0))
    }
    func testLargestTextAndRepeatedKeyboardRelayoutKeepIdenticalHeight() {
        let height = TextInputMetrics.height(textHeight: 53.7, lineHeight: 53.7, verticalInset: 12, minimum: 44, maximumLines: 5)
        XCTAssertEqual(height, 78)
        for _ in 0..<50 {
            XCTAssertFalse(TextInputMetrics.changed(from: height, to: TextInputMetrics.height(textHeight: 53.7, lineHeight: 53.7, verticalInset: 12, minimum: 44, maximumLines: 5)))
        }
    }
}
