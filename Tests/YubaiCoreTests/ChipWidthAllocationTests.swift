import Foundation
import XCTest
import YubaiCore

final class ChipWidthAllocationTests: XCTestCase {
    func testTwoLongRecentPurposesKeepLunchAtNaturalWidthInAnyPosition() {
        // The 56pt item represents the short 「午饭」 chip in Mac validation M6.
        let cases: [([CGFloat], [CGFloat])] = [
            ([300, 240, 56], [144, 144, 56]),
            ([300, 56, 240], [144, 56, 144]),
            ([56, 300, 240], [56, 144, 144])
        ]
        for (natural, expected) in cases {
            let widths = ChipWidthAllocation.widths(naturalWidths: natural, availableWidth: 360, spacing: 8)
            XCTAssertEqual(widths, expected)
            XCTAssertEqual(widths.reduce(0, +) + 16, 360)
        }
    }

    func testFittingExactAndUnconstrainedRowsKeepNaturalWidths() {
        let natural: [CGFloat] = [60, 80, 50]
        for available: CGFloat in [206, 260, .infinity] {
            XCTAssertEqual(ChipWidthAllocation.widths(naturalWidths: natural, availableWidth: available, spacing: 8), natural)
        }
    }

    func testMultipleShortItemsKeepNaturalWidths() {
        XCTAssertEqual(ChipWidthAllocation.widths(naturalWidths: [300, 48, 80], availableWidth: 264, spacing: 8),
                       [120, 48, 80])
    }

    func testAllLongItemsShareOneCap() {
        XCTAssertEqual(ChipWidthAllocation.widths(naturalWidths: [300, 250, 200], availableWidth: 316, spacing: 8),
                       [100, 100, 100])
    }

    func testFractionalWidthsFillAvailableSpace() {
        let widths = ChipWidthAllocation.widths(naturalWidths: [90.5, 40.25, 240.75], availableWidth: 220.5, spacing: 8)
        XCTAssertEqual(widths, [82.125, 40.25, 82.125])
        XCTAssertEqual(widths.reduce(0, +) + 16, 220.5)
    }

    func testEmptySingleAndNoRemainingSpace() {
        XCTAssertEqual(ChipWidthAllocation.widths(naturalWidths: [], availableWidth: 0, spacing: 8), [])
        XCTAssertEqual(ChipWidthAllocation.widths(naturalWidths: [90], availableWidth: 50, spacing: 8), [50])
        for available: CGFloat in [16, 8, 0] {
            XCTAssertEqual(ChipWidthAllocation.widths(naturalWidths: [300, 240, 56], availableWidth: available, spacing: 8),
                           [0, 0, 0])
        }
    }
}
