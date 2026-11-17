import Foundation
import XCTest
import YubaiCore

final class MonthDayGridMetricsTests: XCTestCase {
    func testSevenColumnsFitRequiredPhoneWidthsAfterSheetScaling() {
        let cases: [(CGFloat, CGFloat)] = [(375, 13 / 6), (393, 31 / 6), (402, 40 / 6), (430, 8), (440, 8)]
        for (screen, gap) in cases {
            // Run 3: the resting sheet is inset 8pt at each screen edge.
            let scale = (screen - 16) / screen
            let minimum = ceil(44 / scale * 3) / 3
            let width = screen - 40 // page inset 20; no extra grid/card inset
            let grid = MonthDayGridMetrics(availableWidth: width, minimumTarget: minimum, accessibility: false)
            XCTAssertEqual(grid.columns, 7)
            XCTAssertEqual(grid.spacing, gap, accuracy: 0.000_001)
            let cell = (width - 6 * grid.spacing) / 7
            XCTAssertGreaterThanOrEqual(cell + 0.000_001, minimum)
            XCTAssertGreaterThanOrEqual(cell * scale, 44)
            XCTAssertGreaterThanOrEqual(minimum * scale, 44)
        }
    }

    func testEveryWidthBetween375And440FitsAtRestAndAtFullHeight() {
        for points in 375...440 {
            let screen = CGFloat(points), width = screen - 40
            for scale in [CGFloat(1), (screen - 16) / screen] {
                let minimum = ceil(44 / scale * 3) / 3
                let grid = MonthDayGridMetrics(availableWidth: width, minimumTarget: minimum, accessibility: false)
                XCTAssertEqual(grid.columns, 7)
                XCTAssertGreaterThanOrEqual((width - 6 * grid.spacing) / 7 * scale, 44)
                XCTAssertTrue((2...8).contains(grid.spacing))
            }
        }
    }

    func testAccessibilityKeepsFourColumnsAndMeasuredTargets() {
        for screen: CGFloat in [375, 393, 402, 430, 440] {
            let scale = (screen - 16) / screen, width = screen - 40
            let minimum = ceil(44 / scale * 3) / 3
            let grid = MonthDayGridMetrics(availableWidth: width, minimumTarget: minimum, accessibility: true)
            XCTAssertEqual(grid.columns, 4)
            XCTAssertEqual(grid.spacing, 8)
            XCTAssertGreaterThanOrEqual((width - 3 * grid.spacing) / 4 * scale, 44)
        }
    }

    func testTightFitUsesTwoPointGapsAndWideGridCapsGapsAtEight() {
        XCTAssertEqual(MonthDayGridMetrics(availableWidth: 334, minimumTarget: 46, accessibility: false).spacing, 2)
        XCTAssertEqual(MonthDayGridMetrics(availableWidth: 600, minimumTarget: 46, accessibility: false).spacing, 8)
    }
}
