import XCTest
import YubaiCore

final class MeterSegmentsTests: XCTestCase {
    func testNormalHeroUsesCashAsItsWhole() {
        let bar = HeroBarSegments(available: 474_660, payable: 120_000, reserved: 97_154)
        XCTAssertFalse(bar.isOverspent)
        XCTAssertEqual(bar.needs, 217_154)
        XCTAssertEqual(bar.cash, 691_814)
        XCTAssertEqual(bar.leadingAmount, 474_660)
        XCTAssertEqual(bar.trailingAmount, 217_154)
        XCTAssertEqual(bar.leadingFraction, 474_660.0 / 691_814, accuracy: 0.000001)
        XCTAssertEqual(bar.leadingFraction + bar.trailingFraction, 1, accuracy: 0.000001)
    }

    func testNoNeedsLeavesOneAvailableSegment() {
        let bar = HeroBarSegments(available: 25_000, payable: 0, reserved: 0)
        XCTAssertEqual(bar.cash, 25_000)
        XCTAssertEqual(bar.leadingFraction, 1)
        XCTAssertEqual(bar.trailingAmount, 0)
        XCTAssertEqual(bar.trailingFraction, 0)
    }

    func testOverspentHeroUsesNeedsAsItsWhole() {
        let bar = HeroBarSegments(available: -257_186, payable: 300_000, reserved: 89_000)
        XCTAssertTrue(bar.isOverspent)
        XCTAssertEqual(bar.needs, 389_000)
        XCTAssertEqual(bar.cash, 131_814)
        XCTAssertEqual(bar.leadingAmount, 131_814)
        XCTAssertEqual(bar.trailingAmount, 257_186)
        XCTAssertEqual(bar.leadingFraction, 131_814.0 / 389_000, accuracy: 0.000001)
        XCTAssertEqual(bar.leadingFraction + bar.trailingFraction, 1, accuracy: 0.000001)
    }

    func testZeroOrNegativeCashLeavesOnlyShortfall() {
        for available: Int64 in [-389_000, -400_000] {
            let bar = HeroBarSegments(available: available, payable: 300_000, reserved: 89_000)
            XCTAssertTrue(bar.isOverspent)
            XCTAssertLessThanOrEqual(bar.cash, 0)
            XCTAssertEqual(bar.leadingAmount, 0)
            XCTAssertEqual(bar.trailingAmount, abs(available))
            XCTAssertEqual(bar.leadingFraction, 0)
            XCTAssertEqual(bar.trailingFraction, 1)
        }
    }

    func testZeroAvailableWithAndWithoutNeeds() {
        let covered = HeroBarSegments(available: 0, payable: 120_000, reserved: 5_000)
        XCTAssertTrue(covered.isOverspent)
        XCTAssertEqual(covered.cash, covered.needs)
        XCTAssertEqual(covered.leadingFraction, 1)
        XCTAssertEqual(covered.trailingFraction, 0)
        let empty = HeroBarSegments(available: 0, payable: 0, reserved: 0)
        XCTAssertEqual(empty.leadingAmount, 0)
        XCTAssertEqual(empty.trailingAmount, 0)
        XCTAssertEqual(empty.leadingFraction, 0)
        XCTAssertEqual(empty.trailingFraction, 0)
    }

    func testRestrainOvershootPartitionsActualUsage() {
        let bar = SavingBarSegments(ratio: 1.4, showsOvershoot: true)
        XCTAssertEqual(bar.filledFraction, 5.0 / 7, accuracy: 0.000001)
        XCTAssertEqual(bar.overflowFraction, 2.0 / 7, accuracy: 0.000001)
        XCTAssertEqual(bar.filledFraction + bar.overflowFraction, 1)
    }

    func testZeroLimitWithUsageIsAllOverflow() {
        let bar = SavingBarSegments(ratio: .infinity, showsOvershoot: true)
        XCTAssertEqual(bar.filledFraction, 0)
        XCTAssertEqual(bar.overflowFraction, 1)
    }

    func testProgressAtOrBelowLimitKeepsExistingFill() {
        for ratio in [-1.0, 0, 0.8, 1] {
            let bar = SavingBarSegments(ratio: ratio, showsOvershoot: true)
            XCTAssertEqual(bar.filledFraction, max(0, ratio))
            XCTAssertEqual(bar.overflowFraction, 0)
        }
    }

    func testDefaultProgressStillClampsOvershoot() {
        for ratio in [1.4, Double.infinity] {
            let bar = SavingBarSegments(ratio: ratio)
            XCTAssertEqual(bar.filledFraction, 1)
            XCTAssertEqual(bar.overflowFraction, 0)
        }
    }
}
