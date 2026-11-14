import XCTest

/// These use a virtual clock: even the slow-query and timeout cases take no
/// wall-clock sleeps and make no automation session or application requests.
final class Round47FrameWaitTests: XCTestCase {
    func testDisappearanceWaitAcceptsASlowFirstObservation() {
        var now: TimeInterval = 0
        XCTAssertTrue(UIConditionWait.run(read: { now += 14; return true }, clock: { now }, poll: { now += $0 }))
    }
    func testDisappearanceWaitDoesNotRestartForAStillPresentedSheet() {
        var now: TimeInterval = 0
        var reads = 0
        XCTAssertFalse(UIConditionWait.run(timeout: 3, read: {
            reads += 1; now += 1; return false
        }, clock: { now }, poll: { now += $0 }))
        XCTAssertLessThanOrEqual(reads, 4)
    }
    func testDisappearanceWaitNeverAcceptsALateReadPastTheCallersDeadline() {
        var now: TimeInterval = 0
        XCTAssertFalse(UIConditionWait.run(deadline: 5, read: { now += 14; return true }, clock: { now }, poll: { now += $0 }))
    }
    private let frame = CGRect(x: 36, y: 173.333, width: 368, height: 64)

    func testSlowSnapshotsStillRequireAndReceiveTwoMatchingReads() {
        var time: TimeInterval = 0
        let result = UIFrameWait.run(read: { time += 5; return self.frame }, clock: { time }, poll: { time += $0 })
        XCTAssertTrue(result.stable)
        XCTAssertEqual(result.samples.count, 2)
        XCTAssertGreaterThan(time, 10)
    }
    func testBudgetStartsAfterFirstSuccessfulRead() {
        var time: TimeInterval = 0, reads = 0
        let result = UIFrameWait.run(timeout: 6, read: {
            reads += 1; time += reads == 1 ? 7 : 5
            return self.frame
        }, clock: { time }, poll: { time += $0 })
        XCTAssertTrue(result.stable)
        XCTAssertEqual(reads, 2)
    }
    func testMovingControlNeverPassesAndCannotExtendItsDeadline() {
        var time: TimeInterval = 0, reads = 0
        let result = UIFrameWait.run(timeout: 1, read: {
            reads += 1; time += 0.1
            return self.frame.offsetBy(dx: 0, dy: CGFloat(reads))
        }, clock: { time }, poll: { time += $0 })
        XCTAssertFalse(result.stable)
        XCTAssertLessThan(time, 1.3)
        XCTAssertGreaterThan(reads, 2)
    }
    func testMissingAndEmptyFramesNeverPass() {
        for empty in [CGRect?.none, .some(.zero), .some(.null), .some(.infinite)] {
            var time: TimeInterval = 0
            let result = UIFrameWait.run(timeout: 1, read: { time += 0.1; return empty }, clock: { time }, poll: { time += $0 })
            XCTAssertFalse(result.stable)
            XCTAssertLessThan(time, 1.3)
        }
    }
    func testMissingReadBreaksConsecutiveAgreement() {
        var time: TimeInterval = 0, reads = 0
        let result = UIFrameWait.run(read: {
            reads += 1; time += 0.1
            return reads == 2 ? nil : self.frame
        }, clock: { time }, poll: { time += $0 })
        XCTAssertTrue(result.stable)
        XCTAssertEqual(reads, 4)
    }
    func testEachFrameComponentMustSettle() {
        var time: TimeInterval = 0, reads = 0
        let frames = [frame, frame.offsetBy(dx: 2, dy: 0), frame.offsetBy(dx: 2, dy: 2),
                      CGRect(x: frame.minX + 2, y: frame.minY + 2, width: 370, height: 64),
                      CGRect(x: frame.minX + 2, y: frame.minY + 2, width: 370, height: 66)]
        let result = UIFrameWait.run(read: {
            let value = frames[min(reads, frames.count - 1)]; reads += 1; time += 0.1
            return value
        }, clock: { time }, poll: { time += $0 })
        XCTAssertTrue(result.stable)
        XCTAssertEqual(reads, 6)
    }
    func testInFlightReadPastObservationDeadlineCannotPass() {
        var time: TimeInterval = 0
        let result = UIFrameWait.run(timeout: 1, read: { time += 2; return self.frame }, clock: { time }, poll: { time += $0 })
        XCTAssertFalse(result.stable)
        XCTAssertEqual(result.samples.count, 2)
    }
    func testCallerDeadlineCapsTheFirstReadAndStabilization() {
        var time: TimeInterval = 0
        let result = UIFrameWait.run(timeout: 12, deadline: 1, read: { time += 2; return self.frame }, clock: { time }, poll: { time += $0 })
        XCTAssertFalse(result.stable)
        XCTAssertEqual(result.samples.count, 1)
        XCTAssertEqual(time, 2)
    }
}
